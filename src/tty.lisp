(in-package #:cl-tui-kit/tty)

(define-condition tty-runtime-error (lifecycle-error) ()
  (:documentation "A TTY-RUNTIME operation was attempted while the runtime was
in a state that does not permit it.

Defined here rather than in CL-TUI-KIT/CORE because CORE is SemVer-frozen
while CL-TUI-KIT/TTY is the experimental integration tier; freezing this
symbol in CORE would tie a stable package's contract to a consumer that may
still change in a minor release.  It still inherits CORE's LIFECYCLE-ERROR, so
a HANDLER-CASE written against the core condition catches it too."))

;;;; Optional integration with nerima-lisp's cl-tty-kit.  The backend keeps
;;;; terminal-size discovery and ANSI output separate from the synchronous
;;;; runtime below, which owns only raw-mode lifetime and input acquisition.

(defclass tty-backend (ansi-backend)
  ((file-descriptor :initarg :file-descriptor :initform 0
                    :accessor %tty-backend-file-descriptor)))

(defun %tty-size-valid-p (columns rows)
  (and (integerp columns)
       (plusp columns)
       (integerp rows)
       (plusp rows)))

(defun %tty-size-or (file-descriptor fallback)
  (handler-case
      (multiple-value-bind (columns rows)
          (cl-tty-kit:terminal-size file-descriptor)
        (if (%tty-size-valid-p columns rows)
            (make-size columns rows)
            fallback))
    (error () fallback)))

(defun make-tty-backend (&key stream (file-descriptor 0) size capabilities)
  (let ((fallback (or size (make-size 80 24))))
    (make-instance 'tty-backend
                   :stream (or stream *standard-output*)
                   :file-descriptor file-descriptor
                   :size (%tty-size-or file-descriptor fallback)
                   :capabilities (or capabilities
                                      (make-backend-capabilities
                                       :color :truecolor
                                       :unicode :full)))))

(defun tty-backend-refresh-size (backend)
  (let ((size (%tty-size-or (%tty-backend-file-descriptor backend)
                            (backend-size backend))))
    (backend-resize backend (size-width size) (size-height size))))

;;;; Synchronous TTY runtime

(defgeneric tty-runtime-started-p (runtime)
  (:documentation "Return true once TTY-RUNTIME-START has taken effect and
until TTY-RUNTIME-STOP clears it again."))

(defgeneric tty-runtime-raw-mode-enabled-p (runtime)
  (:documentation "Return true while TTY-RUNTIME-START has put the terminal
into raw mode and TTY-RUNTIME-STOP has not yet disabled it.

This is the achieved state, distinct from TTY-RUNTIME-RAW-MODE-P, which is
the caller's construction-time request for whether raw mode should be
used."))

(defgeneric tty-runtime-input-closed-p (runtime)
  (:documentation "Return true once TTY-RUNTIME-STOP has closed the input
stream, which it does only when TTY-RUNTIME-CLOSE-INPUT-P was requested at
construction."))

(defgeneric tty-runtime-eof-p (runtime)
  (:documentation "Return true once TTY-RUNTIME-NEXT-EVENT or
TTY-RUNTIME-POLL has observed end of input.  TTY-RUNTIME-RESET clears it so
an open stream can be reused."))

(defgeneric tty-runtime-queue (runtime)
  (:documentation "Return the runtime's pending parsed-event queue, filled by
TTY-RUNTIME-NEXT-EVENT and TTY-RUNTIME-POLL as input is parsed and drained as
events are returned to the caller."))

(defgeneric tty-runtime-last-error (runtime)
  (:documentation "Return the condition TTY-RUNTIME-STOP most recently caught
while disabling raw mode or closing input, or NIL when the last stop
succeeded.  TTY-RUNTIME-START and TTY-RUNTIME-RESET clear it before a fresh
run."))

(defclass tty-runtime ()
  ((input-stream :initarg :input-stream :initform *standard-input*
                 :accessor tty-runtime-input-stream)
   (file-descriptor :initarg :file-descriptor :initform 0
                    :accessor tty-runtime-file-descriptor)
   (parser :initarg :parser :initform (make-terminal-input-parser)
           :accessor tty-runtime-parser)
   (read-size :initarg :read-size :initform 4096
              :accessor tty-runtime-read-size)
   (raw-mode-p :initarg :raw-mode :initform t
               :accessor tty-runtime-raw-mode-p)
   (close-input-p :initarg :close-input-p :initform nil
                  :accessor tty-runtime-close-input-p)
   (eof-value :initarg :eof-value :initform :eof
              :accessor tty-runtime-eof-value)
   (started-p :initform nil
              :reader tty-runtime-started-p
              :writer (setf %tty-runtime-started-p))
   (raw-mode-enabled-p :initform nil
                       :reader tty-runtime-raw-mode-enabled-p
                       :writer (setf %tty-runtime-raw-mode-enabled-p))
   (input-closed-p :initform nil
                   :reader tty-runtime-input-closed-p
                   :writer (setf %tty-runtime-input-closed-p))
   (eof-p :initform nil
          :reader tty-runtime-eof-p
          :writer (setf %tty-runtime-eof-p))
   (queue :initform nil
          :reader tty-runtime-queue
          :accessor %tty-runtime-queue)
   (last-error :initform nil
              :reader tty-runtime-last-error
              :writer (setf %tty-runtime-last-error))))

(defun make-tty-runtime (&key (input-stream *standard-input*)
                              (file-descriptor 0)
                              (parser (make-terminal-input-parser))
                              (read-size 4096)
                              (raw-mode t)
                              (close-input-p nil)
                              (eof-value :eof))
  "Create a synchronous terminal input runtime.

When RAW-MODE is true, START enables cl-tty-kit's raw mode for
FILE-DESCRIPTOR and STOP disables it again.  No thread or background poller is
created; NEXT-EVENT blocks and POLL returns immediately when no character is
available."
  (check-type input-stream stream)
  (check-type file-descriptor (integer 0 *))
  (check-type parser terminal-input-parser)
  (check-type read-size (integer 1 *))
  (check-type raw-mode boolean)
  (check-type close-input-p boolean)
  (make-instance 'tty-runtime
                 :input-stream input-stream
                 :file-descriptor file-descriptor
                 :parser parser
                 :read-size read-size
                 :raw-mode raw-mode
                 :close-input-p close-input-p
                 :eof-value eof-value))

(defun %tty-runtime-check (runtime)
  (check-type runtime tty-runtime)
  runtime)

(defun %tty-runtime-enqueue (runtime events)
  (dolist (event events)
    (check-type event event))
  (when events
    (setf (%tty-runtime-queue runtime)
          (nconc (tty-runtime-queue runtime) events)))
  runtime)

(defun %tty-runtime-drain (runtime)
  (prog1 (tty-runtime-queue runtime)
    (setf (%tty-runtime-queue runtime) nil)))

(defun %tty-runtime-read-character (runtime &key no-hang)
  (let ((eof-marker (gensym "TTY-EOF-")))
    (values (if no-hang
                (read-char-no-hang
                 (tty-runtime-input-stream runtime) nil eof-marker)
                (read-char (tty-runtime-input-stream runtime) nil eof-marker))
            eof-marker)))

(defun %tty-runtime-feed-character (runtime character)
  (check-type character character)
  (%tty-runtime-enqueue
   runtime
   (terminal-input-parser-feed
    (tty-runtime-parser runtime)
    (string character))))

(defun %tty-runtime-poll-result (runtime)
  (cond
    ((tty-runtime-queue runtime)
     (values (%tty-runtime-drain runtime) :events))
    ((tty-runtime-eof-p runtime)
     (values nil :eof))
    ((terminal-input-parser-pending-p (tty-runtime-parser runtime))
     (values nil :pending))
    (t
     (values nil :no-data))))

(defun tty-runtime-start (runtime)
  "Enable the runtime and, unless disabled, the terminal's raw mode."
  (%tty-runtime-check runtime)
  (when (tty-runtime-input-closed-p runtime)
    (error 'tty-runtime-error
           :current-state :input-closed
           :requested-operation 'tty-runtime-start
           :detail "Cannot start a TTY runtime after its input stream was closed."))
  (when (tty-runtime-eof-p runtime)
    (error 'tty-runtime-error
           :current-state :eof
           :requested-operation 'tty-runtime-start
           :detail "Cannot restart an exhausted TTY runtime; call TTY-RUNTIME-RESET first."))
  (unless (tty-runtime-started-p runtime)
    (setf (%tty-runtime-last-error runtime) nil)
    (when (tty-runtime-raw-mode-p runtime)
      (cl-tty-kit:enable-raw-mode (tty-runtime-file-descriptor runtime))
      (setf (%tty-runtime-raw-mode-enabled-p runtime) t))
    (setf (%tty-runtime-started-p runtime) t))
  runtime)

(defun tty-runtime-stop (runtime)
  "Stop the runtime and restore terminal state, collecting cleanup failures."
  (%tty-runtime-check runtime)
  (let ((failure nil))
    (when (tty-runtime-raw-mode-enabled-p runtime)
      (handler-case
          (progn
            (cl-tty-kit:disable-raw-mode (tty-runtime-file-descriptor runtime))
            (setf (%tty-runtime-raw-mode-enabled-p runtime) nil))
        (condition (condition)
          (setf failure condition))))
    (when (and (tty-runtime-close-input-p runtime)
               (not (tty-runtime-input-closed-p runtime)))
      (handler-case
          (progn
            (close (tty-runtime-input-stream runtime))
            (setf (%tty-runtime-input-closed-p runtime) t))
        (condition (condition)
          (unless failure
            (setf failure condition)))))
    (setf (%tty-runtime-started-p runtime) nil
          (%tty-runtime-last-error runtime) failure)
    (when failure
      (error failure)))
  runtime)

(defun tty-runtime-close (runtime)
  "Release raw mode and optionally close the input stream."
  (tty-runtime-stop runtime))

(defun tty-runtime-reset (runtime)
  "Reset parser and EOF state so an open input stream can be reused."
  (%tty-runtime-check runtime)
  (when (or (tty-runtime-started-p runtime)
            (tty-runtime-raw-mode-enabled-p runtime))
    (error 'tty-runtime-error
           :current-state :running
           :requested-operation 'tty-runtime-reset
           :detail "Cannot reset a running TTY runtime; stop it first."))
  (when (tty-runtime-input-closed-p runtime)
    (error 'tty-runtime-error
           :current-state :input-closed
           :requested-operation 'tty-runtime-reset
           :detail "Cannot reset a TTY runtime after its input stream was closed."))
  (terminal-input-parser-reset (tty-runtime-parser runtime))
  (setf (%tty-runtime-queue runtime) nil
        (%tty-runtime-eof-p runtime) nil
        (%tty-runtime-last-error runtime) nil)
  runtime)

(defun %tty-runtime-finish-eof (runtime)
  (setf (%tty-runtime-eof-p runtime) t)
  (%tty-runtime-enqueue
   runtime
   (terminal-input-parser-flush (tty-runtime-parser runtime)))
  (tty-runtime-stop runtime)
  runtime)

(defun tty-runtime-next-event (runtime)
  "Read and return the next normalized EVENT, or EOF-VALUE at EOF.

This operation is blocking after START has enabled the runtime.  Incomplete
escape sequences remain in the parser until more input or EOF arrives."
  (%tty-runtime-check runtime)
  (loop
    (when (tty-runtime-queue runtime)
      (return (pop (%tty-runtime-queue runtime))))
    (when (tty-runtime-eof-p runtime)
      (return (tty-runtime-eof-value runtime)))
    (tty-runtime-start runtime)
    (multiple-value-bind (character eof-marker)
        (%tty-runtime-read-character runtime)
      (if (eq character eof-marker)
          (%tty-runtime-finish-eof runtime)
          (%tty-runtime-feed-character runtime character)))))

(defun tty-runtime-poll (runtime)
  "Return `(values EVENTS STATUS)` without blocking.

STATUS is :EVENTS when complete events are available, :PENDING when input
was consumed but the parser still has an incomplete sequence, :NO-DATA when
the stream currently has no character, and :EOF after end of input."
  (%tty-runtime-check runtime)
  (when (tty-runtime-queue runtime)
    (return-from tty-runtime-poll
      (values (%tty-runtime-drain runtime) :events)))
  (when (tty-runtime-eof-p runtime)
    (return-from tty-runtime-poll (values nil :eof)))
  (tty-runtime-start runtime)
  (let ((read-count 0)
        (eof-seen-p nil))
    (loop while (< read-count (tty-runtime-read-size runtime))
          do (multiple-value-bind (character eof-marker)
                 (%tty-runtime-read-character runtime :no-hang t)
               (cond
                 ((eq character eof-marker)
                  (setf eof-seen-p t)
                  (return))
                 ((null character)
                  (return))
                 (t
                  (incf read-count)
                  (%tty-runtime-feed-character runtime character)))))
    (when eof-seen-p
      (%tty-runtime-finish-eof runtime))
    (%tty-runtime-poll-result runtime)))

(defun tty-runtime-event-source (runtime)
  "Return a zero-argument reader suitable for MAKE-TERMINAL-EVENT-SOURCE."
  (%tty-runtime-check runtime)
  (lambda ()
    (tty-runtime-next-event runtime)))

(defun call-with-tty-runtime (runtime continuation)
  "Start RUNTIME, call CONTINUATION, and always stop the runtime."
  (check-type continuation function)
  (unwind-protect
       (progn
         (tty-runtime-start runtime)
         (funcall continuation))
    (tty-runtime-stop runtime)))

(defmacro with-tty-runtime ((runtime) &body body)
  "Run BODY with RUNTIME started and always attempt to stop it."
  (let ((runtime-var (gensym "RUNTIME-")))
    `(let ((,runtime-var ,runtime))
       (call-with-tty-runtime
        ,runtime-var
        (lambda () ,@body)))))
