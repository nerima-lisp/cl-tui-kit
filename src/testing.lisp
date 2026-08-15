(in-package #:cl-tui-kit/testing)

(define-condition assertion-failed-error (cl-tui-kit-error)
  ((expected :initarg :expected :initform nil
             :reader assertion-failed-error-expected)
   (actual :initarg :actual :initform nil
           :reader assertion-failed-error-actual))
  (:documentation "A test assertion in CL-TUI-KIT/TESTING did not hold.")
  (:report
   (lambda (condition stream)
     (format stream "~A Expected ~S, got ~S."
             (or (cl-tui-kit-error-detail condition) "Assertion failed.")
             (assertion-failed-error-expected condition)
             (assertion-failed-error-actual condition)))))

;;;; This backend stores structured frames.  It has no stream and therefore
;;;; makes rendering assertions independent of a terminal.

(defclass test-backend (backend)
  ((frames :initform nil :accessor %test-backend-frames)
   (recorded-events :initform nil :accessor %test-backend-recorded-events)
   (operations :initform nil :accessor %test-backend-operations)))

(defun make-test-backend (&key size capabilities)
  (make-instance 'test-backend
                 :size (copy-size (or size (make-size)))
                 :capabilities (or capabilities
                                    (make-backend-capabilities
                                     :color :truecolor
                                     :unicode :full
                                     :mouse :basic
                                     :clipboard t))))

(defun test-backend-frames (backend)
  (reverse (%test-backend-frames backend)))

(defun test-backend-last-frame (backend)
  (car (last (test-backend-frames backend))))

(defun test-backend-recorded-events (backend)
  (reverse (%test-backend-recorded-events backend)))

(defun test-backend-operations (backend)
  "Return a chronological trace of protocol operations on BACKEND.

Surface values in the trace are copies, so assertions can inspect a frame
without observing later mutations by the application."
  (reverse (%test-backend-operations backend)))

(defmethod backend-open :after ((backend test-backend))
  (push '(:open) (%test-backend-operations backend))
  backend)

(defmethod backend-close :after ((backend test-backend))
  (push '(:close) (%test-backend-operations backend))
  backend)

(defmethod backend-begin-frame ((backend test-backend))
  (push '(:begin-frame) (%test-backend-operations backend))
  backend)

(defmethod backend-present ((backend test-backend) surface &key region)
  (push (copy-surface surface) (%test-backend-frames backend))
  (push (list :present (copy-surface surface)
              (and region (copy-rectangle region)))
        (%test-backend-operations backend))
  backend)

(defmethod backend-flush ((backend test-backend))
  (push '(:flush) (%test-backend-operations backend))
  backend)

(defmethod backend-resized :after ((backend test-backend) old-size new-size)
  (push (list :resized (copy-size old-size) (copy-size new-size))
        (%test-backend-operations backend))
  backend)

(defmethod backend-set-cursor :after ((backend test-backend) point)
  (push (list :cursor (copy-point point))
        (%test-backend-operations backend))
  backend)

(defmethod backend-set-cursor-visible :after ((backend test-backend) visible-p)
  (push (list :cursor-visible (not (null visible-p)))
        (%test-backend-operations backend))
  backend)

(defmethod backend-enter-alternate :after ((backend test-backend))
  (push '(:enter-alternate) (%test-backend-operations backend))
  backend)

(defmethod backend-leave-alternate :after ((backend test-backend))
  (push '(:leave-alternate) (%test-backend-operations backend))
  backend)

(defmethod backend-set-title :after ((backend test-backend) title)
  (push (list :title title) (%test-backend-operations backend))
  backend)

(defmethod backend-invalidate :after ((backend test-backend))
  (push '(:invalidate) (%test-backend-operations backend))
  backend)

(defun test-backend-emit (backend event)
  (push event (%test-backend-recorded-events backend))
  event)

(defstruct (event-replay
            (:constructor %make-event-replay (events index eof-value)))
  "A deterministic, one-shot event reader for integration tests."
  (events nil :type list)
  (index 0 :type fixnum)
  eof-value)

(defun make-event-replay (events &key (eof-value :eof))
  "Create a replay reader from EVENTS in their chronological order."
  (check-type events list)
  (dolist (event events)
    (check-type event event))
  (%make-event-replay (copy-list events) 0 eof-value))

(defun event-replay-next (replay)
  "Return the next recorded event, or REPLAY's EOF-VALUE when exhausted."
  (check-type replay event-replay)
  (if (< (event-replay-index replay) (length (event-replay-events replay)))
      (prog1 (nth (event-replay-index replay) (event-replay-events replay))
        (incf (event-replay-index replay)))
      (event-replay-eof-value replay)))

(defun event-replay-reset (replay)
  "Rewind REPLAY to its first event."
  (check-type replay event-replay)
  (setf (event-replay-index replay) 0)
  replay)

(defun event-replay-exhausted-p (replay)
  (check-type replay event-replay)
  (>= (event-replay-index replay)
      (length (event-replay-events replay))))

(defun event-replay-remaining-count (replay)
  (check-type replay event-replay)
  (max 0 (- (length (event-replay-events replay))
            (event-replay-index replay))))

(defun test-backend-event-replay (backend &key (eof-value :eof))
  "Return a replay reader over BACKEND's recorded events."
  (make-event-replay (test-backend-recorded-events backend)
                     :eof-value eof-value))

(defun test-backend-reset (backend)
  (setf (%test-backend-frames backend) nil
        (%test-backend-recorded-events backend) nil
        (%test-backend-operations backend) nil)
  backend)

(defun %testing-cell-equal-p (left right)
  (and (or (null left) (cell-p left))
       (or (null right) (cell-p right))
       (if (and left right)
           (and (string= (cell-content left) (cell-content right))
                (style= (cell-style left) (cell-style right))
                (= (cell-span left) (cell-span right))
                (eql (cell-continuation-p left)
                     (cell-continuation-p right)))
           (eql left right))))

(defun surface-equal-p (left right)
  (and (surface-p left)
       (surface-p right)
       (= (surface-width left) (surface-width right))
       (= (surface-height left) (surface-height right))
       (loop for y below (surface-height left)
             always (loop for x below (surface-width left)
                          always (%testing-cell-equal-p
                                  (surface-cell left x y)
                                  (surface-cell right x y))))))

(defun surface-cell-string (object)
  (if (cell-p object) (cell-content object) (surface-string object)))

(defun assert-surface-text (surface expected)
  (let ((actual (surface-string surface)))
    (unless (string= actual expected)
      (error 'assertion-failed-error :expected expected :actual actual
             :detail "Surface text mismatch.")))
  t)
