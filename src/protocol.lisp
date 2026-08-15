(in-package #:cl-tui-kit/core)

;;;; Deterministic event loop

(defun %event-loop-default-clock ()
  (/ (get-internal-real-time) internal-time-units-per-second))

(defun %event-loop-default-error-handler (condition loop source)
  (declare (ignore loop source))
  (error condition))

(defstruct (event-loop-task
            (:constructor %make-event-loop-task
                (id deadline sequence callback repeat cancelled-p)))
  id
  deadline
  sequence
  callback
  repeat
  (cancelled-p nil :type boolean))

(defstruct (event-loop
            (:constructor %make-event-loop
                (clock event-handler error-handler events-head events-tail
                 tasks next-id next-sequence running-p stopped-p woken-p)))
  (clock #'%event-loop-default-clock :type function)
  event-handler
  (error-handler #'%event-loop-default-error-handler :type function)
  events-head
  events-tail
  tasks
  (next-id 0 :type fixnum)
  (next-sequence 0 :type fixnum)
  (running-p nil :type boolean)
  (stopped-p nil :type boolean)
  (woken-p nil :type boolean))

(defun make-event-loop
    (&key clock event-handler (error-handler #'%event-loop-default-error-handler))
  "Create a deterministic, threadless event loop.

CLOCK is a zero-argument function returning a numeric monotonic time.  The
default uses GET-INTERNAL-REAL-TIME.  EVENT-HANDLER receives normalized EVENT
objects.  ERROR-HANDLER receives a condition, the loop, and a source keyword;
returning true continues the loop, while the default re-signals the
condition."
  (when clock (check-type clock function))
  (when event-handler (check-type event-handler function))
  (check-type error-handler function)
  (%make-event-loop (or clock #'%event-loop-default-clock)
                    event-handler error-handler nil nil nil 0 0 nil nil nil))

(defun event-loop-now (loop)
  (check-type loop event-loop)
  (funcall (event-loop-clock loop)))

(defun event-loop-pending-event-p (loop)
  (check-type loop event-loop)
  (not (null (event-loop-events-head loop))))

(defun event-loop-pending-task-count (loop)
  (check-type loop event-loop)
  (count-if-not #'event-loop-task-cancelled-p (event-loop-tasks loop)))

(defun event-loop-pending-p (loop)
  (or (event-loop-pending-event-p loop)
      (plusp (event-loop-pending-task-count loop))))

(defun event-loop-next-deadline (loop)
  (check-type loop event-loop)
  (let ((deadline nil))
    (dolist (task (event-loop-tasks loop) deadline)
      (unless (event-loop-task-cancelled-p task)
        (when (or (null deadline)
                  (< (event-loop-task-deadline task) deadline))
          (setf deadline (event-loop-task-deadline task)))))))

(defun event-loop-wakeup-p (loop)
  (check-type loop event-loop)
  (event-loop-woken-p loop))

(defun event-loop-wakeup (loop)
  "Mark LOOP as woken by an external input adapter.

This is deliberately only a coordination flag.  A TTY adapter may use it to
  avoid sleeping in its own poll implementation, without making the core own a
  file descriptor or a thread."
  (check-type loop event-loop)
  (setf (event-loop-woken-p loop) t)
  loop)

(defun event-loop-clear-wakeup (loop)
  (check-type loop event-loop)
  (setf (event-loop-woken-p loop) nil)
  loop)

(defun event-loop-post (loop event)
  "Append EVENT to LOOP's FIFO queue and mark it woken."
  (check-type loop event-loop)
  (check-type event event)
  (let ((cell (list event)))
    (if (event-loop-events-tail loop)
        (setf (cdr (event-loop-events-tail loop)) cell
              (event-loop-events-tail loop) cell)
        (setf (event-loop-events-head loop) cell
              (event-loop-events-tail loop) cell)))
  (event-loop-wakeup loop)
  event)

(defun %event-loop-pop-event (loop)
  (let ((cell (event-loop-events-head loop)))
    (when cell
      (setf (event-loop-events-head loop) (cdr cell))
      (unless (event-loop-events-head loop)
        (setf (event-loop-events-tail loop) nil))
      (car cell))))

(defun event-loop-schedule (loop delay callback &key repeat)
  "Schedule CALLBACK after DELAY and return a cancellable task.

CALLBACK receives LOOP and the task.  It may return one EVENT or a list of
EVENTs, which are posted after the callback.  REPEAT, when non-NIL, is the
non-zero delay between repeated invocations.  Timers are evaluated only when
EVENT-LOOP-STEP is called, so the result is deterministic and does not create
a hidden thread."
  (check-type loop event-loop)
  (check-type delay real)
  (unless (>= delay 0)
    (error 'invalid-range-error
           :context 'delay
           :datum delay
           :expected "a non-negative real number"))
  (check-type callback function)
  (when repeat
    (check-type repeat real)
    (unless (plusp repeat)
      (error 'invalid-range-error
             :context 'repeat
             :datum repeat
             :expected "a positive real number")))
  (let ((task (%make-event-loop-task
               (incf (event-loop-next-id loop))
               (+ (event-loop-now loop) delay)
               (incf (event-loop-next-sequence loop))
               callback repeat nil)))
    (push task (event-loop-tasks loop))
    (event-loop-wakeup loop)
    task))

(defun event-loop-schedule-event (loop delay event &key repeat)
  "Schedule EVENT for delivery after DELAY.

The returned task can be passed to EVENT-LOOP-CANCEL.  REPEAT has the same
meaning as in EVENT-LOOP-SCHEDULE."
  (check-type event event)
  (event-loop-schedule loop delay
                       (lambda (scheduled-loop task)
                         (declare (ignore scheduled-loop task))
                         event)
                       :repeat repeat))

(defun event-loop-cancel (loop task)
  "Cancel TASK.  Cancellation is idempotent and does not remove the object."
  (check-type loop event-loop)
  (check-type task event-loop-task)
  (setf (event-loop-task-cancelled-p task) t)
  (event-loop-wakeup loop)
  task)

(defun %event-loop-task-before-p (left right)
  (or (< (event-loop-task-deadline left)
         (event-loop-task-deadline right))
      (and (= (event-loop-task-deadline left)
              (event-loop-task-deadline right))
           (< (event-loop-task-sequence left)
              (event-loop-task-sequence right)))))

(defun %event-loop-ready-task (loop now)
  (let ((best nil))
    (dolist (task (event-loop-tasks loop) best)
      (when (and (not (event-loop-task-cancelled-p task))
                 (<= (event-loop-task-deadline task) now)
                 (or (null best) (%event-loop-task-before-p task best)))
        (setf best task)))))

(defun %event-loop-remove-task (loop task)
  (setf (event-loop-tasks loop)
        (delete task (event-loop-tasks loop) :test #'eq)))

(defun %event-loop-post-result (loop result)
  (cond
    ((null result) nil)
    ((event-p result) (event-loop-post loop result))
    ((and (listp result) (every #'event-p result))
     (dolist (event result) (event-loop-post loop event))
     result)
    (t (error 'callback-contract-error
              :callback "event loop timer callback"
              :detail "Timer callback returned neither an event nor a list of events."
              :value (bounded-datum result)))))

(defun %event-loop-handle-error (loop condition source)
  (unless (funcall (event-loop-error-handler loop) condition loop source)
    (error condition)))

(defun %event-loop-dispatch (loop event handler)
  (handler-case
      (funcall handler event)
    (condition (condition)
      (%event-loop-handle-error loop condition :event))))

(defun %event-loop-run-task (loop task)
  (handler-case
      (let ((result (funcall (event-loop-task-callback task) loop task)))
        (%event-loop-post-result loop result)
        (when (and (event-loop-task-repeat task)
                   (not (event-loop-task-cancelled-p task)))
          (incf (event-loop-task-deadline task)
                (event-loop-task-repeat task))
          (push task (event-loop-tasks loop)))
        result)
    (condition (condition)
      (%event-loop-handle-error loop condition :timer))))

(defun event-loop-step (loop &key now handler)
  "Process at most one queued event or due timer.

Return true when work was processed and NIL when no event is queued and no
timer is due at NOW.  No waiting occurs; adapters decide how to poll and then
call EVENT-LOOP-POST or EVENT-LOOP-WAKEUP."
  (check-type loop event-loop)
  (when handler (check-type handler function))
  (let* ((current-time (or now (event-loop-now loop)))
         (dispatch (or handler (event-loop-event-handler loop))))
    (cond
      ((event-loop-pending-event-p loop)
       (unless dispatch
         (error 'protocol-error
                :detail "EVENT-LOOP-STEP needs an event handler for queued events."))
       (%event-loop-dispatch loop (%event-loop-pop-event loop) dispatch)
       t)
      (t
       (let ((task (%event-loop-ready-task loop current-time)))
         (when task
           (%event-loop-remove-task loop task)
           (%event-loop-run-task loop task)
           t))))))

(defun event-loop-stop (loop)
  (check-type loop event-loop)
  (setf (event-loop-stopped-p loop) t)
  (event-loop-wakeup loop)
  loop)

(defun event-loop-run (loop &key handler max-steps until)
  "Drain ready work until stopped, idle, MAX-STEPS, or UNTIL returns true.

The loop never sleeps.  This makes it suitable for tests and for an adapter
that owns its own poll/select policy.  Return the number of processed work
items."
  (check-type loop event-loop)
  (when handler (check-type handler function))
  (when max-steps
    (check-type max-steps (integer 0 *)))
  (when until (check-type until function))
  (setf (event-loop-stopped-p loop) nil
        (event-loop-running-p loop) t)
  (unwind-protect
       (loop with processed = 0
             while (and (not (event-loop-stopped-p loop))
                        (or (null max-steps) (< processed max-steps))
                        (not (and until (funcall until loop))))
             for did-work = (event-loop-step loop :handler handler)
             while did-work
             do (incf processed)
             finally (return processed))
    (setf (event-loop-running-p loop) nil)))

;;;; Incremental terminal event sources

(defstruct (terminal-event-source
            (:constructor %make-terminal-event-source
                (reader parser eof-value close-reader queue eof-p closed-p)))
  "A synchronous source that turns decoded terminal input into EVENTs.

The source owns only the reader function and parser state.  It does not own a
file descriptor, a thread, or a polling policy; adapters can supply those
pieces around this small protocol."
  (reader nil :type function)
  (parser (make-terminal-input-parser) :type terminal-input-parser)
  eof-value
  close-reader
  queue
  (eof-p nil :type boolean)
  (closed-p nil :type boolean))

(defun make-terminal-event-source (reader &key parser (eof-value :eof)
                                                close-reader)
  "Create a normalized EVENT source around READER.

READER is a zero-argument function returning a character string, an octet
vector, or EOF-VALUE.  PARSER defaults to a fresh TERMINAL-INPUT-PARSER.
CLOSE-READER, when supplied, is called at most once when the source reaches
EOF or is explicitly closed."
  (check-type reader function)
  (when parser
    (check-type parser terminal-input-parser))
  (when close-reader
    (check-type close-reader function))
  (%make-terminal-event-source reader
                               (or parser (make-terminal-input-parser))
                               eof-value close-reader nil nil nil))

(defun %terminal-event-source-queue-events (source events)
  (check-type source terminal-event-source)
  (dolist (event events)
    (check-type event event))
  (when events
    (setf (terminal-event-source-queue source)
          (nconc (terminal-event-source-queue source)
                 (copy-list events))))
  source)

(defun %terminal-event-source-finish-eof (source)
  (unless (terminal-event-source-eof-p source)
    (setf (terminal-event-source-eof-p source) t)
    (%terminal-event-source-queue-events
     source
     (terminal-input-parser-flush
      (terminal-event-source-parser source)))
    (let ((close-reader (terminal-event-source-close-reader source)))
      (setf (terminal-event-source-close-reader source) nil
            (terminal-event-source-closed-p source) t)
      (when close-reader
        (funcall close-reader))))
  source)

(defun terminal-event-source-close (source)
  "Close SOURCE and discard any unconsumed events.

Closing is idempotent and invokes the optional close callback at most once.
Unlike natural EOF, explicit close discards both queued events and parser
state because the caller has declared the input session over."
  (check-type source terminal-event-source)
  (unless (terminal-event-source-closed-p source)
    (let ((close-reader (terminal-event-source-close-reader source)))
      (setf (terminal-event-source-queue source) nil
            (terminal-event-source-eof-p source) t
            (terminal-event-source-close-reader source) nil
            (terminal-event-source-closed-p source) t)
      (terminal-input-parser-reset (terminal-event-source-parser source))
      (when close-reader
        (funcall close-reader))))
  source)

(defun terminal-event-source-pending-p (source)
  "Return true when SOURCE has an event or incomplete parser input pending."
  (check-type source terminal-event-source)
  (not (null
        (or (terminal-event-source-queue source)
            (terminal-input-parser-pending-p
             (terminal-event-source-parser source))))))

(defun terminal-event-source-next (source)
  "Return the next normalized EVENT from SOURCE, or its EOF-VALUE.

The reader may return multiple bytes or characters per call.  Any events
decoded from one chunk are buffered so callers always receive one event at a
time.  A final parser flush happens before EOF is returned."
  (check-type source terminal-event-source)
  (loop
    for queued = (terminal-event-source-queue source)
    when queued
      do (setf (terminal-event-source-queue source) (rest queued))
         (return (first queued))
    when (terminal-event-source-eof-p source)
      do (return (terminal-event-source-eof-value source))
    do (let ((input (funcall (terminal-event-source-reader source))))
         (if (eq input (terminal-event-source-eof-value source))
             (%terminal-event-source-finish-eof source)
             (progn
               (unless (or (stringp input) (vectorp input))
                 (error 'callback-contract-error
                        :callback "terminal event source reader"
                        :detail "Terminal event source reader returned a value that was not a string, octet vector, or EOF-VALUE."
                        :value (bounded-datum input)))
               (%terminal-event-source-queue-events
                source
                (terminal-input-parser-feed
                 (terminal-event-source-parser source) input)))))))

(defun make-stream-event-source
    (stream &key parser (chunk-size 4096) (element-type :character)
                   (close-stream-p nil) (eof-value :eof))
  "Create a blocking event source backed by a Common Lisp STREAM.

ELEMENT-TYPE is :CHARACTER or :OCTET.  CHUNK-SIZE controls each
READ-SEQUENCE call.  The stream is not closed unless CLOSE-STREAM-P is true;
this ownership rule keeps the core usable with standard streams and with
adapters that manage their own descriptors."
  (check-type stream stream)
  (unless (and (integerp chunk-size) (plusp chunk-size))
    (error 'invalid-range-error
           :context 'chunk-size
           :datum chunk-size
           :expected "a positive integer"))
  (unless (member element-type '(:character :octet) :test #'eq)
    (error 'invalid-option-error
           :context 'element-type
           :datum element-type
           :allowed '(:character :octet)))
  (check-type close-stream-p boolean)
  (make-terminal-event-source
   (lambda ()
     (let* ((buffer (ecase element-type
                      (:character (make-string chunk-size))
                      (:octet (make-array chunk-size
                                          :element-type '(unsigned-byte 8)))))
            (count (read-sequence buffer stream)))
       (if (zerop count)
           eof-value
           (subseq buffer 0 count))))
   :parser parser
   :eof-value eof-value
   :close-reader (when close-stream-p
                   (lambda () (close stream)))))

;;;; Continuation-oriented integration points

(defun dispatch-event/k (handlers event handled-k &key (unhandled-k #'identity))
  "Dispatch EVENT through HANDLERS using explicit continuations.

Each handler receives EVENT and a NEXT-K continuation.  Returning a non-NIL
value handles the event and passes that value to HANDLED-K.  Returning NIL
falls through to the next handler.  A handler may call NEXT-K explicitly to
delegate after doing its own work; in that case NEXT-K's value is returned
without invoking HANDLED-K a second time.  UNHANDLED-K receives the final
event when no handler handles it."
  (check-type handlers list)
  (check-type event event)
  (check-type handled-k function)
  (check-type unhandled-k function)
  (labels ((dispatch (remaining current-event)
             (if (endp remaining)
                 (funcall unhandled-k current-event)
                 (let ((continued-p nil)
                       (handler (first remaining)))
                   (check-type handler function)
                   (let ((result
                           (funcall handler
                                    current-event
                                    (lambda (&optional (next-event current-event))
                                      (setf continued-p t)
                                      (dispatch (rest remaining) next-event)))))
                     (cond
                       (continued-p result)
                       (result (funcall handled-k result))
                       (t (dispatch (rest remaining) current-event))))))))
    (dispatch handlers event)))

(defun present-frame/k (backend surface continuation &key region)
  "Present SURFACE through BACKEND and invoke CONTINUATION afterwards.

This helper keeps frame orchestration explicit without introducing a hidden
thread or terminal side effect into the surface and widget protocols."
  (check-type backend backend)
  (check-type surface surface)
  (check-type continuation function)
  (when region
    (check-type region rectangle))
  (backend-begin-frame backend)
  (backend-present backend surface :region region)
  (backend-flush backend)
  (funcall continuation surface))
