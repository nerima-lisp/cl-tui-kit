(in-package #:cl-tui-kit/widgets)

;;;; Lazy list protocol -----------------------------------------------------

(defclass list-model ()
  ((count-source :initarg :count :accessor %list-model-count-source)
   (item-source :initarg :item-at :accessor %list-model-item-source)
   (key-source :initarg :key-at :accessor %list-model-key-source)
   (label-source :initarg :label-at :accessor %list-model-label-source)
   (render-source :initarg :render-item
                  :accessor %list-model-render-source)))

(defun %model-value (source &rest arguments)
  (if (functionp source)
      (apply source arguments)
      source))

(defun make-list-model (&key count item-at key-at label-at render-item)
  (unless (or (integerp count) (functionp count))
    (error "LIST-MODEL :COUNT must be an integer or function."))
  (when (and (integerp count) (minusp count))
    (error "LIST-MODEL :COUNT must be non-negative."))
  (unless (functionp item-at)
    (error "LIST-MODEL :ITEM-AT must be a function."))
  (make-instance 'list-model
                 :count count :item-at item-at
                 :key-at (or key-at (lambda (item index)
                                      (declare (ignore index)) item))
                 :label-at (or label-at (lambda (item index)
                                          (declare (ignore index)) (%text item)))
                 :render-item render-item))

(defun %validated-model-count (value name)
  (unless (and (integerp value) (>= value 0))
    (error "~A must return a non-negative integer, got ~S." name value))
  value)

(defun list-model-count (model)
  (%validated-model-count
   (%model-value (%list-model-count-source model))
   "LIST-MODEL :COUNT"))

(defun list-model-item-at (model index)
  (funcall (%list-model-item-source model) index))

(defun list-model-key-at (model item index)
  (funcall (%list-model-key-source model) item index))

(defun list-model-label-at (model item index)
  (%text (funcall (%list-model-label-source model) item index)))

(defun list-model-render-item (model item index)
  (let ((renderer (%list-model-render-source model)))
    (if renderer
        (%text (funcall renderer item index))
        (list-model-label-at model item index))))

(defclass list-widget (widget)
  ((model :initarg :model :accessor list-widget-model)
   (selected-key :initarg :selected-key :accessor list-widget-selected-key
                 :initform nil)
   (offset :initarg :offset :accessor list-widget-offset :initform 0)
   (row-height :initarg :row-height :accessor list-widget-row-height
               :initform 1)))

(defun make-list-widget (model &key id rectangle style theme keymap selected-key
                                      (offset 0) (row-height 1) focusable-p)
  (check-type model list-model)
  (unless (and (integerp row-height) (plusp row-height))
    (error "List row height must be a positive integer."))
  (make-instance 'list-widget :model model :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme)) :keymap keymap
                 :selected-key selected-key :offset (max 0 offset)
                 :row-height row-height :focusable-p focusable-p))

(defun %list-index-for-key (widget key)
  (let ((model (list-widget-model widget)))
    (loop for index below (list-model-count model)
          for item = (list-model-item-at model index)
          when (equalp key (list-model-key-at model item index))
            do (return index))))

(defun %list-selected-index (widget)
  (or (%list-index-for-key widget (list-widget-selected-key widget))
      (and (plusp (list-model-count (list-widget-model widget))) 0)))

(defun list-widget-selected-index (widget)
  "Return the selected row index, or NIL when the model is empty."
  (%list-selected-index widget))

(defun %list-visible-row-count (widget)
  (max 1 (floor (rectangle-height (widget-rectangle widget))
                (list-widget-row-height widget))))

(defun %list-set-index (widget index)
  (let* ((model (list-widget-model widget))
         (count (list-model-count model)))
    (when (plusp count)
      (let* ((actual (min (1- count) (max 0 index)))
             (item (list-model-item-at model actual))
             (key (list-model-key-at model item actual)))
        (setf (list-widget-selected-key widget) key)
        (let* ((height (rectangle-height (widget-rectangle widget)))
               (row-height (list-widget-row-height widget))
               (rows (max 1 (floor height row-height)))
               (max-offset (max 0 (- count rows)))
               (offset (list-widget-offset widget))
               (visible-offset
                 (cond
                   ((< actual offset) actual)
                   ((>= actual (+ offset rows)) (- (1+ actual) rows))
                   (t offset))))
          (setf (list-widget-offset widget)
                (max 0 (min visible-offset max-offset))))
        actual))))

(defun list-widget-select-key (widget key)
  (let ((index (%list-index-for-key widget key)))
    (when index
      (%list-set-index widget index)
      (let* ((height (rectangle-height (widget-rectangle widget)))
             (rows (max 1 (floor height (list-widget-row-height widget)))))
        (setf (list-widget-offset widget)
              (max 0 (min (list-widget-offset widget)
                          (max 0 (- (list-model-count (list-widget-model widget))
                                    rows)))))))
  widget))

(defun list-widget-page-up (widget)
  "Move the selection up by one viewport, keeping it visible."
  (let ((index (%list-selected-index widget)))
    (when index
      (%list-set-index widget (- index (%list-visible-row-count widget)))))
  widget)

(defun list-widget-page-down (widget)
  "Move the selection down by one viewport, keeping it visible."
  (let ((index (%list-selected-index widget)))
    (when index
      (%list-set-index widget (+ index (%list-visible-row-count widget)))))
  widget)

(defun list-widget-refresh (widget)
  "Reconcile selection and offset with a model whose contents changed."
  (let* ((model (list-widget-model widget))
         (count (list-model-count model)))
    (if (zerop count)
        (setf (list-widget-selected-key widget) nil
              (list-widget-offset widget) 0)
        (%list-set-index widget
                         (or (%list-index-for-key
                              widget (list-widget-selected-key widget))
                             (min (1- count)
                                  (max 0 (list-widget-offset widget)))))))
  widget)

(defun list-widget-visible-items (widget)
  "Return only the rows needed by the current viewport.

Each result is a plist with :INDEX, :ITEM, :KEY, and :LABEL.  The model is
queried lazily; no complete list is materialized."
  (let* ((model (list-widget-model widget))
         (height (rectangle-height (widget-rectangle widget)))
         (row-height (list-widget-row-height widget))
         (rows (if (plusp row-height) (ceiling height row-height) 0))
         (start (min (list-widget-offset widget) (list-model-count model))))
    (loop for index from start below (min (list-model-count model) (+ start rows))
          for item = (list-model-item-at model index)
          for key = (list-model-key-at model item index)
          collect (list :index index :item item :key key
                        :label (list-model-render-item model item index)))))

(defmethod widget-preferred-size ((widget list-widget))
  (let ((model (list-widget-model widget)))
    (make-size (loop for index below (min 10 (list-model-count model))
                     maximize (string-cell-width
                               (list-model-label-at model
                                                     (list-model-item-at model index)
                                                     index)) into width
                     finally (return (or width 0)))
               10)))

(defmethod widget-render ((widget list-widget) surface)
  (let* ((area (widget-rectangle widget))
         (row-height (list-widget-row-height widget))
         (base-style (%widget-role-style widget :foreground))
         (selected-style (merge-styles base-style
                                       (%widget-role-style widget :selected))))
    (dolist (entry (list-widget-visible-items widget))
      (let* ((index (getf entry :index))
             (row (- index (list-widget-offset widget)))
             (y (+ (rectangle-y area) (* row row-height)))
             (selected (equalp (getf entry :key)
                               (list-widget-selected-key widget)))
             (style (if selected selected-style base-style)))
        (surface-fill-rectangle surface
                                 (make-rectangle (rectangle-x area) y
                                                 (rectangle-width area) row-height)
                                 #\Space style)
        (surface-draw-text surface (rectangle-x area) y (getf entry :label)
                            :style style
                            :max-width (rectangle-width area)))))
  widget)

(defmethod widget-accessibility-info ((widget list-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :listbox))
    (setf (getf info :state)
          (list :selected-key (list-widget-selected-key widget)
                :selected-index (%list-selected-index widget)
                :offset (list-widget-offset widget)
                :count (list-model-count (list-widget-model widget))))
    info))

(defmethod widget-handle-event ((widget list-widget) event)
  (cond
    ((typep event 'key-event)
     (let* ((key (key-event-key event))
            (index (%list-selected-index widget))
            (count (list-model-count (list-widget-model widget))))
       (when (and index (plusp count))
         (cond
           ((member key '(:up :previous) :test #'equalp)
            (%list-set-index widget (1- index))
            (move-action :up 1 widget))
           ((member key '(:down :next) :test #'equalp)
            (%list-set-index widget (1+ index))
            (move-action :down 1 widget))
           ((member key '(:page-up :prior :previous-page) :test #'equalp)
            (list-widget-page-up widget)
            (move-action :page-up (%list-visible-row-count widget) widget))
           ((member key '(:page-down :next-page) :test #'equalp)
            (list-widget-page-down widget)
            (move-action :page-down (%list-visible-row-count widget) widget))
           ((member key '(:home) :test #'equalp)
            (%list-set-index widget 0)
            (move-action :home 1 widget))
           ((member key '(:end) :test #'equalp)
            (%list-set-index widget (1- count))
            (move-action :end 1 widget))
           ((or (eql key #\Space) (equalp key :space))
            (toggle-action (list-widget-selected-key widget) widget))
           ((member key '(:enter :return) :test #'equalp)
            (activate-action (list-widget-selected-key widget) widget))))))
    ((and (typep event 'mouse-event)
          (eq (mouse-event-kind event) :press)
          (rectangle-contains-point-p
           (widget-rectangle widget)
           (make-point (mouse-event-x event) (mouse-event-y event))))
     (let* ((area (widget-rectangle widget))
            (row (floor (- (mouse-event-y event) (rectangle-y area))
                        (list-widget-row-height widget)))
            (index (+ (list-widget-offset widget) row))
            (count (list-model-count (list-widget-model widget))))
       (when (and (>= row 0) (< index count))
         (%list-set-index widget index)
         (select-action (list-widget-selected-key widget) widget))))))
