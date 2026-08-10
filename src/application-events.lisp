(in-package #:cl-tui-kit/widgets)

;;;; Event routing

(defun %broadcast-widget-event/k (widget event continuation)
  (check-type continuation function)
  (if (widget-active-p widget)
      (let ((action (handle-widget-event widget event)))
        (if action
            (funcall continuation action)
            (labels ((visit (children)
                       (if (endp children)
                           (funcall continuation nil)
                           (%broadcast-widget-event/k
                            (first children) event
                            (lambda (child-action)
                              (if child-action
                                  (funcall continuation child-action)
                                  (visit (rest children))))))))
              (visit (widget-interactive-children widget)))))
      (funcall continuation nil)))

(defun %dispatch-resize-event (application event)
  (backend-resize (application-backend application)
                  (resize-event-width event)
                  (resize-event-height event))
  (application-refresh-focus-tree application)
  (dispatch-widget-event
   (application-root application) event
   (application-root application)
   (application-keymap-state application)))

(defun %dispatch-tick-event (application event)
  (%broadcast-widget-event/k (application-root application)
                             event #'identity))

(defun %dispatch-tab-event (application event)
  (let ((tree (application-focus-tree application)))
    (if (member :shift (key-event-modifiers event) :test #'eq)
        (focus-previous tree)
        (focus-next tree))))

(defun %dispatch-mouse-event (application event)
  (let ((target (widget-hit-test (application-root application)
                                 (mouse-event-x event)
                                 (mouse-event-y event))))
    (when target
      (%application-set-focus-widget application target)
      (dispatch-widget-event
       (application-root application) event target
       (application-keymap-state application)))))

(defun %dispatch-default-event (application event)
  (dispatch-widget-event
   (application-root application) event
   (%application-focused-widget application)
   (application-keymap-state application)))

(defun %application-event-action (application event)
  (cond
    ((typep event 'resize-event)
     (%dispatch-resize-event application event))
    ((typep event 'tick-event)
     (%dispatch-tick-event application event))
    ((and (typep event 'key-event)
          (eq (key-event-key event) :tab))
     (%dispatch-tab-event application event))
    ((typep event 'mouse-event)
     (%dispatch-mouse-event application event))
    (t
     (%dispatch-default-event application event))))

(defun application-dispatch-event (application event)
  (setf (application-last-action application) nil)
  (when event
    (application-invalidate application)
    (unless (typep event 'resize-event)
      (application-refresh-focus-tree application)))
  (let ((action (%application-event-action application event)))
    (setf (application-last-action application) action)
    action))
