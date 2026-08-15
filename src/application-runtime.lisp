(in-package #:cl-tui-kit/widgets)

;;;; Application lifecycle

(defun application-step/k (application event continuation)
  "Dispatch EVENT, render when dirty, and continue with the last action.

CONTINUATION receives the action recorded by the application.  EVENT may be
NIL when the caller only wants to flush a dirty frame."
  (check-type application application)
  (check-type continuation function)
  (when event
    (application-dispatch-event application event))
  (if (%application-dirty-p application)
      (application-render/k
       application
       (lambda (rendered-application)
         (declare (ignore rendered-application))
         (funcall continuation (application-last-action application))))
      (funcall continuation (application-last-action application))))

(defun application-step (application &optional event)
  (application-step/k application event #'identity))

(defun application-start (application)
  (unless (%application-running-p application)
    (let ((backend (application-backend application)))
      (backend-open backend)
      (when (application-alternate-screen-p application)
        (backend-enter-alternate backend))
      (when (application-title application)
        (backend-set-title backend (application-title application))))
    (setf (%application-running-p application) t)
    (application-render application))
  application)

(defun application-stop (application)
  (setf (%application-running-p application) nil)
  application)

(defun application-close (application)
  (application-stop application)
  (let ((backend (application-backend application)))
    (backend-close backend))
  application)

(defun call-with-application-session (application continuation)
  "Start APPLICATION, call CONTINUATION, and always close it."
  (check-type continuation function)
  (unwind-protect
       (progn
         (application-start application)
         (funcall continuation))
    (application-close application)))

(defmacro with-application-session ((application) &body body)
  "Run BODY inside a started application session."
  (let ((application-var (gensym "APPLICATION-")))
    `(let ((,application-var ,application))
       (call-with-application-session
        ,application-var
        (lambda () ,@body)))))

(defun application-run (application event-source &key (eof-value :eof))
  (check-type event-source function)
  (call-with-application-session
   application
   (lambda ()
     (loop while (%application-running-p application)
           for event = (funcall event-source)
           do (if (eq event eof-value)
                  (return)
                  (application-step application event)))))
  application)
