(in-package #:cl-tui-kit/widgets)

;;;; Application composition and execution ---------------------------------

;;;; Rendering and event dispatch live here; application state and geometry
;;;; are defined in src/application-data.lisp.

(defun application-render/k (application continuation)
  "Render APPLICATION, then invoke CONTINUATION with APPLICATION.

The continuation runs after the frame has been flushed and the application
has been marked clean.  Keeping this boundary explicit lets a caller compose
rendering with another CPS operation without introducing an event-loop
wrapper."
  (check-type application application)
  (check-type continuation function)
  (application-layout application)
  (let ((backend (application-backend application))
        (surface (%application-surface application)))
    (surface-clear surface)
    (widget-render (application-root application) surface)
    (let* ((focused (%application-focused-widget application))
           (cursor (and focused (widget-cursor-position focused))))
      (if cursor
          (progn
            (backend-set-cursor backend cursor)
            (backend-set-cursor-visible backend t))
          (backend-set-cursor-visible backend nil)))
    (present-frame/k
     backend surface
     (lambda (presented-surface)
       (declare (ignore presented-surface))
       (surface-mark-clean surface)
       (setf (%application-dirty-p application) nil)
       (funcall continuation application)))))

(defun application-render (application)
  (application-render/k application #'identity))

(defun widget-hit-test (widget x y)
  (when (and (widget-active-p widget)
             (widget-enabled-p widget)
             (rectangle-contains-point-p (widget-rectangle widget) x y))
    (dolist (child (reverse (widget-interactive-children widget)))
      (let ((hit (widget-hit-test child x y)))
        (when hit (return-from widget-hit-test hit))))
    widget))

(defun %widget-path (root target)
  (unless (widget-active-p root)
    (return-from %widget-path))
  (when (eq root target)
    (return-from %widget-path (list root)))
  (dolist (child (widget-interactive-children root))
    (let ((path (%widget-path child target)))
      (when path (return-from %widget-path (cons root path)))))
  nil)

(defun %propagate-widget-action (ancestors action)
  (dolist (ancestor ancestors action)
    (setf action (widget-handle-child-action ancestor action))))

(defun %dispatch-widget-handler-result (widget event keymap-state)
  (let ((keymap (widget-keymap widget)))
    (if (and (typep event 'key-event) keymap)
        (let ((result (keymap-dispatch keymap keymap-state event)))
          (values
           (not (eq (keymap-result-status result) :unhandled))
           (keymap-result-action result)))
        (let ((action (handle-widget-event widget event)))
          (values (not (null action)) action)))))

(defun %make-widget-event-handler (widget ancestors keymap-state handled-k)
  (lambda (event next-k)
    (multiple-value-bind (handledp action)
        (%dispatch-widget-handler-result widget event keymap-state)
      (if handledp
          (progn
            (funcall handled-k ancestors)
            ;; Keep handled-with-NIL distinct from an unhandled result while
            ;; the generic CPS dispatcher walks.
            (list :handled action))
          (funcall next-k)))))

(defun %dispatch-widget-event/k (path event keymap-state)
  (let ((handled-ancestors nil)
        (widgets (reverse path)))
    (dispatch-event/k
     (loop for remaining on widgets
           collect (%make-widget-event-handler
                    (car remaining)
                    (cdr remaining)
                    keymap-state
                    (lambda (ancestors)
                      (setf handled-ancestors ancestors))))
     event
     (lambda (result)
       (%propagate-widget-action handled-ancestors (second result)))
     :unhandled-k (lambda (current-event)
                    (declare (ignore current-event))
                    nil))))

(defun dispatch-widget-event (root event &optional target keymap-state)
  (check-type root widget)
  (let ((target (or target root)))
    (let ((path (%widget-path root target)))
      (when path
        (let ((*widget-event-target* target))
          (let ((capture (find-if (lambda (widget)
                                    (and (widget-active-p widget)
                                         (widget-capture-event-p widget event)))
                                  (reverse path))))
            (if capture
                (or (handle-widget-event capture event)
                    (%dispatch-widget-event/k
                     path event (or keymap-state (make-keymap-state))))
                (%dispatch-widget-event/k
                 path event (or keymap-state (make-keymap-state))))))))))

(defun %application-focused-widget (application)
  (let ((current (focus-tree-current (%application-focus-tree application))))
    (and current (focus-node-widget current))))

(defun %application-set-focus-widget (application widget)
  (let ((node (%find-focus-node (focus-tree-root
                                 (%application-focus-tree application))
                                widget)))
    (when (and node (focus-node-focusable-p node))
      (focus-tree-set-current (%application-focus-tree application) node)
      widget)))
