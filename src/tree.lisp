(in-package #:cl-tui-kit/widgets)

;;;; Lazy tree protocol -----------------------------------------------------

(defclass tree-model ()
  ((root-count-source :initarg :root-count :accessor %tree-root-count-source)
   (root-source :initarg :root-at :accessor %tree-root-source)
   (key-source :initarg :key-at :accessor %tree-key-source)
   (label-source :initarg :label-at :accessor %tree-label-source)
   (children-source :initarg :children :accessor %tree-children-source)
   (expanded-source :initarg :expanded-p :accessor %tree-expanded-source)
   (render-source :initarg :render-item :accessor %tree-render-source)))

(defun make-tree-model (&key root-count root-at key-at label-at children expanded-p
                                  render-item)
  (unless (or (integerp root-count) (functionp root-count))
    (error 'invalid-type-error :context 'root-count :datum root-count
           :expected-type '(or integer function)))
  (when (and (integerp root-count) (minusp root-count))
    (error 'invalid-range-error :context 'root-count :datum root-count
           :expected "a non-negative integer"))
  (unless (functionp root-at)
    (error 'invalid-type-error :context 'root-at :datum root-at
           :expected-type 'function))
  (unless (functionp key-at)
    (error 'invalid-type-error :context 'key-at :datum key-at
           :expected-type 'function))
  (unless (functionp label-at)
    (error 'invalid-type-error :context 'label-at :datum label-at
           :expected-type 'function))
  (make-instance 'tree-model :root-count root-count :root-at root-at
                 :key-at key-at :label-at label-at :children children
                 :expanded-p (or expanded-p (lambda (node) (declare (ignore node)) nil))
                 :render-item render-item))

(defun tree-model-root-count (model)
  (%validated-model-count
   (%model-value (%tree-root-count-source model))
   "TREE-MODEL :ROOT-COUNT"))

(defun tree-model-root-at (model index)
  (funcall (%tree-root-source model) index))

(defun tree-model-key-at (model node)
  (funcall (%tree-key-source model) node))

(defun tree-model-label-at (model node)
  (%text (funcall (%tree-label-source model) node)))

(defun tree-model-children (model node)
  (let ((source (%tree-children-source model)))
    (and source (funcall source node))))

(defun tree-model-expanded-p (model node)
  (not (null (funcall (%tree-expanded-source model) node))))

(defun tree-model-render-item (model node)
  (let ((renderer (%tree-render-source model)))
    (if renderer (%text (funcall renderer node))
        (tree-model-label-at model node))))

(defun %tree-child-count (children)
  (cond
    ((null children) 0)
    ((typep children 'list-model) (list-model-count children))
    ((vectorp children) (length children))
    ((listp children) (length children))
    (t 0)))

(defun %tree-child-at (children index)
  (cond
    ((typep children 'list-model) (list-model-item-at children index))
    ((vectorp children) (aref children index))
    ((listp children) (nth index children))
    (t nil)))

(defstruct (%tree-visible-item (:constructor %make-tree-visible-item
                                                    (index node depth key label)))
  index node depth key label)

(defun %tree-walk-visible (model function)
  (let ((index 0)
        (stop nil))
    (labels ((visit (node depth)
               (unless stop
                 (let ((item (%make-tree-visible-item
                              index node depth (tree-model-key-at model node)
                              (tree-model-render-item model node))))
                   (incf index)
                   (when (funcall function item) (setf stop t))
                   (when (and (not stop) (tree-model-expanded-p model node))
                     (let ((children (tree-model-children model node)))
                       (loop for child-index below (%tree-child-count children)
                             do (visit (%tree-child-at children child-index)
                                       (1+ depth))))))))
             (roots ()
               (loop for root-index below (tree-model-root-count model)
                     do (visit (tree-model-root-at model root-index) 0))))
      (roots))))

(defun %tree-visible-count (model)
  (let ((count 0))
    (%tree-walk-visible model (lambda (item) (declare (ignore item))
                                (incf count) nil))
    count))

(defun %tree-visible-at (model target)
  (let ((found nil))
    (%tree-walk-visible model
                        (lambda (item)
                          (when (= target (%tree-visible-item-index item))
                            (setf found item)
                            t)))
    found))

(defun %tree-visible-range (model start limit)
  "Return at most LIMIT visible items beginning at START.

Unlike the full-range helpers above, this traversal does not compute keys or
labels for nodes before START.  It still follows their expansion state so that
a lazy model can skip the materialization work for rows outside the viewport."
  (let ((start (max 0 start))
        (limit (max 0 limit)))
    (unless (zerop limit)
      (let ((index 0)
              (end (+ start limit))
              (items nil)
              (stop nil))
          (labels ((visit (node depth)
                     (unless stop
                       (let ((item-index index))
                         (incf index)
                         (when (and (>= item-index start)
                                    (< item-index end))
                           (push (%make-tree-visible-item
                                  item-index node depth
                                  (tree-model-key-at model node)
                                  (tree-model-render-item model node))
                                 items))
                         (when (>= index end)
                           (setf stop t))
                         (when (and (not stop)
                                    (tree-model-expanded-p model node))
                           (let ((children (tree-model-children model node)))
                             (loop for child-index below (%tree-child-count children)
                                   do (visit (%tree-child-at children child-index)
                                             (1+ depth))))))))
                   (roots ()
                     (loop for root-index below (tree-model-root-count model)
                           do (visit (tree-model-root-at model root-index) 0))))
            (roots)
            (nreverse items))))))

(defclass tree-widget (widget)
  ((model :initarg :model :accessor %tree-widget-model)
   (selected-key :initarg :selected-key :accessor %tree-widget-selected-key
                 :initform nil)
   (offset :initarg :offset :accessor %tree-widget-offset :initform 0)))

(defun tree-widget-selected-key (widget)
  "Return WIDGET's selected key, or NIL when no node is selected.

This value is internal selection state kept consistent with WIDGET's
model by WIDGET's built-in key and mouse handling; use TREE-WIDGET-REFRESH
to reconcile it after the model's contents change."
  (%tree-widget-selected-key widget))

(defun tree-widget-offset (widget)
  "Return the index of the first visible row in WIDGET.

This value is internal scroll state that the owning subsystem keeps
clamped to the visible row window; it follows the selected key and
WIDGET's rendered size and has no direct setter."
  (%tree-widget-offset widget))

(defun make-tree-widget (model &key id rectangle style theme keymap selected-key
                                      (offset 0) focusable-p)
  (check-type model tree-model)
  (make-instance 'tree-widget :model model :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme)) :keymap keymap
                 :selected-key selected-key :offset (max 0 offset)
                 :focusable-p focusable-p))

(defun %tree-selected-item (widget)
  (let ((model (%tree-widget-model widget))
        (selected (%tree-widget-selected-key widget))
        (found nil))
    (%tree-walk-visible model
                        (lambda (item)
                          (when (equalp selected (%tree-visible-item-key item))
                            (setf found item) t)))
    found))

(defun tree-widget-selected-index (widget)
  "Return the visible index of the selected node, or NIL for an empty tree."
  (let ((item (%tree-selected-item widget)))
    (and item (%tree-visible-item-index item))))

(defun %tree-visible-row-count (widget)
  (max 1 (rectangle-height (%widget-rectangle widget))))

(defun %tree-set-index (widget index)
  (let* ((model (%tree-widget-model widget))
         (count (%tree-visible-count model)))
    (when (plusp count)
      (let* ((actual (min (1- count) (max 0 index)))
             (item (%tree-visible-at model actual))
             (rows (%tree-visible-row-count widget)))
        (when item
          (setf (%tree-widget-selected-key widget)
                (%tree-visible-item-key item))
          (let* ((offset (%tree-widget-offset widget))
                 (visible-offset
                   (cond
                     ((< actual offset) actual)
                     ((>= actual (+ offset rows)) (- (1+ actual) rows))
                     (t offset))))
            (setf (%tree-widget-offset widget)
                  (max 0 (min visible-offset (max 0 (- count rows))))))
          actual)))))

(defun tree-widget-page-up (widget)
  "Move the selection up by one viewport, keeping it visible."
  (let ((index (tree-widget-selected-index widget)))
    (when index
      (%tree-set-index widget (- index (%tree-visible-row-count widget)))))
  widget)

(defun tree-widget-page-down (widget)
  "Move the selection down by one viewport, keeping it visible."
  (let ((index (tree-widget-selected-index widget)))
    (when index
      (%tree-set-index widget (+ index (%tree-visible-row-count widget)))))
  widget)

(defun tree-widget-refresh (widget)
  "Reconcile selection and offset with a tree model whose contents changed."
  (let* ((model (%tree-widget-model widget))
         (count (%tree-visible-count model)))
    (if (zerop count)
        (setf (%tree-widget-selected-key widget) nil
              (%tree-widget-offset widget) 0)
        (%tree-set-index
         widget
         (or (tree-widget-selected-index widget)
             (min (1- count) (max 0 (%tree-widget-offset widget)))))))
  widget)

(defun tree-widget-toggle-expanded (widget)
  (let ((item (%tree-selected-item widget)))
    (when item
      (toggle-action (list :key (%tree-visible-item-key item)
                           :item (%tree-visible-item-node item))
                     widget))))

(defmethod widget-preferred-size ((widget tree-widget))
  (make-size 30 10))

(defmethod widget-render ((widget tree-widget) surface)
  (let* ((area (%widget-rectangle widget))
         (model (%tree-widget-model widget))
         (base-style (%widget-role-style widget :foreground))
         (selected-style (merge-styles base-style
                                       (%widget-role-style widget :selected)))
         (rows (max 0 (rectangle-height area)))
         (offset (max 0 (%tree-widget-offset widget)))
         (items (%tree-visible-range model offset rows)))
    (loop for row from 0
          for item in items
          for selected = (equalp (%tree-widget-selected-key widget)
                                 (%tree-visible-item-key item))
          for style = (if selected selected-style base-style)
          for label = (format nil "~V@T~A"
                              (* 2 (%tree-visible-item-depth item))
                              (%tree-visible-item-label item))
          do (surface-fill-rectangle
              surface (make-rectangle (rectangle-x area) (+ (rectangle-y area) row)
                                      (rectangle-width area) 1)
              #\Space style)
             (surface-draw-text surface (rectangle-x area) (+ (rectangle-y area) row)
                                 label :style style
                                 :max-width (rectangle-width area))))
  widget)

(defmethod widget-accessibility-info ((widget tree-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :tree))
    (setf (getf info :state)
          (list :selected-key (%tree-widget-selected-key widget)
                :selected-index (tree-widget-selected-index widget)
                :offset (%tree-widget-offset widget)))
    info))

(defmethod widget-handle-event ((widget tree-widget) event)
  (cond
    ((typep event 'key-event)
     (let* ((key (key-event-key event))
            (model (%tree-widget-model widget))
            (index (tree-widget-selected-index widget))
            (count (%tree-visible-count model)))
       (when (and index (plusp count))
         (cond
           ((member key '(:up :previous) :test #'equalp)
            (%tree-set-index widget (1- index))
            (move-action :up 1 widget))
           ((member key '(:down :next) :test #'equalp)
            (%tree-set-index widget (1+ index))
            (move-action :down 1 widget))
           ((member key '(:page-up :prior :previous-page) :test #'equalp)
            (tree-widget-page-up widget)
            (move-action :page-up (%tree-visible-row-count widget) widget))
           ((member key '(:page-down :next-page) :test #'equalp)
            (tree-widget-page-down widget)
            (move-action :page-down (%tree-visible-row-count widget) widget))
           ((member key '(:home) :test #'equalp)
            (%tree-set-index widget 0)
            (move-action :home 1 widget))
           ((member key '(:end) :test #'equalp)
            (%tree-set-index widget (1- count))
            (move-action :end 1 widget))
           ((member key '(:left) :test #'equalp)
            (custom-action :collapse (%tree-widget-selected-key widget) widget))
           ((member key '(:right) :test #'equalp)
            (custom-action :expand (%tree-widget-selected-key widget) widget))
           ((or (eql key #\Space) (equalp key :space))
            (tree-widget-toggle-expanded widget))
           ((member key '(:enter :return) :test #'equalp)
            (activate-action (%tree-widget-selected-key widget) widget))))))
    ((and (typep event 'mouse-event)
          (eq (mouse-event-kind event) :press)
          (rectangle-contains-point-p
           (%widget-rectangle widget)
           (make-point (mouse-event-x event) (mouse-event-y event))))
     (let* ((area (%widget-rectangle widget))
            (row (- (mouse-event-y event) (rectangle-y area)))
            (index (+ (%tree-widget-offset widget) row))
            (count (%tree-visible-count (%tree-widget-model widget))))
       (when (and (>= row 0) (< index count))
         (%tree-set-index widget index)
         (select-action (%tree-widget-selected-key widget) widget))))))
