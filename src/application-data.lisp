(in-package #:cl-tui-kit/widgets)

;;;; Application state and focus/layout data ---------------------------------

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
