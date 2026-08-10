(in-package #:cl-tui-kit/widgets)

;;;; Application lifecycle

(defun application-step (application &optional event)
  (when event
    (application-dispatch-event application event))
  (when (application-dirty-p application)
    (application-render application))
  (application-last-action application))

(defun application-start (application)
  (unless (application-running-p application)
    (let ((backend (application-backend application)))
      (backend-open backend)
      (when (application-alternate-screen-p application)
        (backend-enter-alternate backend))
      (when (application-title application)
        (backend-set-title backend (application-title application))))
    (setf (application-running-p application) t)
    (application-render application))
  application)

(defun application-stop (application)
  (setf (application-running-p application) nil)
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
     (loop while (application-running-p application)
           for event = (funcall event-source)
           do (if (eq event eof-value)
                  (return)
                  (application-step application event)))))
  application)
