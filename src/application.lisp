(in-package #:cl-tui-kit/widgets)

;;;; Application composition and execution ---------------------------------

(defclass application ()
  ((backend :initarg :backend :accessor application-backend)
   (root :initarg :root :accessor application-root)
   (surface :initarg :surface :accessor application-surface)
   (focus-tree :initarg :focus-tree :accessor application-focus-tree)
   (keymap-state :initarg :keymap-state :accessor application-keymap-state
                 :initform (make-keymap-state))
   (running-p :initarg :running-p :accessor application-running-p
              :initform nil)
   (dirty-p :initarg :dirty-p :accessor application-dirty-p :initform t)
   (last-action :initarg :last-action :accessor application-last-action
                :initform nil)
   (alternate-screen-p :initarg :alternate-screen-p
                       :accessor application-alternate-screen-p
                       :initform t)
   (title :initarg :title :accessor application-title :initform nil)))

(defun make-widget-focus-tree (root)
  (check-type root widget)
  (labels ((build (current)
             (make-focus-node
              (or (widget-id current) current)
              :widget current
              :children (mapcar #'build
                                (widget-interactive-children current))
              :rectangle (widget-rectangle current)
              :focusable-p (and (widget-active-p current)
                                (widget-enabled-p current)
                                (widget-focusable-p current)))))
    (make-focus-tree (build root))))

(defun %find-focus-node (node widget)
  (when (eq (focus-node-widget node) widget)
    (return-from %find-focus-node node))
  (dolist (child (focus-node-children node))
    (let ((found (%find-focus-node child widget)))
      (when found (return-from %find-focus-node found))))
  nil)

(defun application-refresh-focus-tree (application)
  (let* ((old-tree (application-focus-tree application))
         (old-current (and old-tree (focus-tree-current old-tree)))
         (old-widget (and old-current (focus-node-widget old-current)))
         (tree (make-widget-focus-tree (application-root application))))
    (setf (application-focus-tree application) tree)
    (when old-widget
      (let ((current (%find-focus-node (focus-tree-root tree) old-widget)))
        (when current
          (focus-tree-set-current tree current))))
    tree))

(defun make-application (&key backend root surface focus-tree keymap-state
                                  (alternate-screen-p t) title)
  (let* ((backend (or backend (make-backend)))
         (root (or root (make-widget)))
         (size (backend-size backend)))
    (check-type root widget)
    (make-instance
     'application
     :backend backend
     :root root
     :surface (or surface
                  (make-surface (size-width size) (size-height size)))
     :focus-tree (or focus-tree (make-widget-focus-tree root))
     :keymap-state (or keymap-state (make-keymap-state))
     :alternate-screen-p alternate-screen-p
     :title title)))

(defun %sync-focus-node-rectangles (node)
  (let ((widget (focus-node-widget node)))
    (when widget
      (setf (focus-node-rectangle node) (copy-rectangle
                                         (widget-rectangle widget)))))
  (dolist (child (focus-node-children node))
    (%sync-focus-node-rectangles child)))

(defun application-layout (application)
  (let* ((backend (application-backend application))
         (size (backend-size backend))
         (root (application-root application))
         (area (make-rectangle 0 0 (size-width size) (size-height size)))
         (surface (application-surface application)))
    (widget-layout root area)
    ;; Layout can change the active child set (for example, when a modal is
    ;; opened or closed directly by application code), so rebuild focus
    ;; navigation before synchronizing its rectangles.
    (application-refresh-focus-tree application)
    (unless (and (= (surface-width surface) (size-width size))
                 (= (surface-height surface) (size-height size)))
      (setf (application-surface application)
            (make-surface (size-width size) (size-height size)))
      (setf surface (application-surface application)))
    (%sync-focus-node-rectangles (focus-tree-root
                                  (application-focus-tree application)))
    application))

(defun application-invalidate (application)
  (setf (application-dirty-p application) t)
  application)

(defun application-render (application)
  (application-layout application)
  (let ((backend (application-backend application))
        (surface (application-surface application)))
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
       (setf (application-dirty-p application) nil))))
  application)

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
  (let ((current (focus-tree-current (application-focus-tree application))))
    (and current (focus-node-widget current))))

(defun %application-set-focus-widget (application widget)
  (let ((node (%find-focus-node (focus-tree-root
                                 (application-focus-tree application))
                                widget)))
    (when (and node (focus-node-focusable-p node))
      (focus-tree-set-current (application-focus-tree application) node)
      widget)))
