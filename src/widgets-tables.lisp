(in-package #:cl-tui-kit/widgets)

;;;; Table widgets.

(defstruct (table-column (:constructor %make-table-column
                                       (label key width min-width align)))
  label key width (min-width 1) (align :left))

(defun make-table-column (label &key key width (min-width 1) (align :left))
  (when width
    (unless (and (integerp width) (>= width 0))
      (error "Table column width must be a non-negative integer or NIL.")))
  (check-type min-width (integer 0))
  (unless (member align '(:left :right :center) :test #'eq)
    (error "Table column alignment must be :LEFT, :RIGHT, or :CENTER."))
  (%make-table-column (%text label) key width min-width align))

(defclass table-widget (widget)
  ((columns :initarg :columns :accessor table-widget-columns :initform nil)
   (rows :initarg :rows :accessor table-widget-rows :initform nil)
   (selected-row :initarg :selected-row :accessor table-widget-selected-row
                 :initform nil)
   (selected-column :initarg :selected-column
                    :accessor table-widget-selected-column :initform 0)
   (row-offset :initarg :row-offset :accessor table-widget-row-offset :initform 0)
   (header-p :initarg :header-p :initform t)
   (row-height :initarg :row-height :initform 1)))

(defun make-table-widget (columns rows &key selected-row (selected-column 0)
                                      (header-p t) (row-height 1) id rectangle style
                                      theme keymap (focusable-p t) semantic-role
                                      accessible-label accessible-description
                                      accessible-help-text)
  (dolist (column columns) (check-type column table-column))
  (unless (and (integerp row-height) (plusp row-height))
    (error "Table row height must be a positive integer."))
  (make-instance 'table-widget :columns (copy-list columns) :rows (copy-list rows)
                 :selected-row (and rows selected-row
                                    (max 0 (min (1- (length rows)) selected-row)))
                 :selected-column (max 0 (min (1- (max 1 (length columns)))
                                               selected-column))
                 :header-p header-p :row-height row-height :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style)) :theme (or theme (default-theme))
                 :keymap keymap :focusable-p focusable-p
                 :semantic-role (or semantic-role :grid)
                 :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defun %table-row-value (row index)
  (cond ((vectorp row)
         (and (<= 0 index) (< index (length row)) (aref row index)))
        ((listp row)
         (and (<= 0 index) (< index (length row)) (nth index row)))
        (t row)))

(defun %table-column-value (column row index)
  (let ((key (table-column-key column)))
    (cond ((functionp key) (funcall key row))
          ((integerp key) (%table-row-value row key))
          ((and key (listp row)) (or (getf row key) (%table-row-value row index)))
          (t (%table-row-value row index)))))

(defun %table-natural-column-width (column rows index)
  (max (table-column-min-width column)
       (or (table-column-width column)
           (let ((width (string-cell-width
                         (table-column-label column))))
             (dolist (row rows width)
               (setf width
                     (max width
                          (string-cell-width
                           (%text (%table-column-value column row index))))))))))

(defun %table-natural-widths (columns rows)
  (loop for column in columns
        for index from 0
        collect (%table-natural-column-width column rows index)))

(defun %table-shrinkable-column-index (columns widths)
  (loop for width in widths
        for column in columns
        for candidate from 0
        when (> width (table-column-min-width column))
          do (return candidate)))

(defun %table-shrink-widths (columns widths area-width)
  (let ((total (reduce #'+ widths :initial-value 0)))
    (loop while (> total area-width)
          for index = (%table-shrinkable-column-index columns widths)
          while index
          do (decf (nth index widths))
             (decf total))
    widths))

(defun %table-expand-widths (widths area-width)
  (let ((total (reduce #'+ widths :initial-value 0)))
    (when (and widths (< total area-width))
      (incf (car (last widths)) (- area-width total)))
    widths))

(defun %table-widths (widget)
  (let* ((columns (table-widget-columns widget))
         (rows (table-widget-rows widget))
         (area-width (max 0 (rectangle-width (widget-rectangle widget))))
         (widths (%table-natural-widths columns rows)))
    (%table-expand-widths
     (%table-shrink-widths columns widths area-width)
     area-width)))

(defun %table-column-at-x (widget x)
  (let* ((area (widget-rectangle widget))
         (offset (- x (rectangle-x area))))
    (when (and (<= 0 offset)
               (< offset (rectangle-width area)))
      (loop with consumed = 0
            for width in (%table-widths widget)
            for column from 0
            when (< offset (+ consumed width))
              do (return column)
            do (incf consumed width)))))

(defun %table-visible-row-count (widget)
  (let* ((height (rectangle-height (widget-rectangle widget)))
         (header-height (if (slot-value widget 'header-p) 1 0)))
    (max 1 (floor (max 0 (- height header-height))
                  (slot-value widget 'row-height)))))

(defun %table-clamp-row-offset (widget)
  (let* ((rows (length (table-widget-rows widget)))
         (visible (%table-visible-row-count widget)))
    (setf (table-widget-row-offset widget)
          (max 0 (min (table-widget-row-offset widget)
                      (max 0 (- rows visible)))))))

(defun %table-ensure-selected-row-visible (widget)
  (let ((selected (table-widget-selected-row widget))
        (visible (%table-visible-row-count widget)))
    (when selected
      (cond
        ((< selected (table-widget-row-offset widget))
         (setf (table-widget-row-offset widget) selected))
        ((>= selected (+ (table-widget-row-offset widget) visible))
         (setf (table-widget-row-offset widget) (- (1+ selected) visible)))))
    (%table-clamp-row-offset widget)
    widget))

(defun %table-padded-cell (text width align)
  (let* ((text (clip-text (%text text) width))
         (padding (max 0 (- width (string-cell-width text))))
         (left (case align (:right padding) (:center (floor padding 2)) (otherwise 0)))
         (right (- padding left)))
    (concatenate 'string (make-string left :initial-element #\Space)
                 text (make-string right :initial-element #\Space))))

(defun table-widget-set-rows (widget rows)
  (check-type widget table-widget)
  (setf (table-widget-rows widget) (copy-list rows))
  (when (and (table-widget-selected-row widget)
             (>= (table-widget-selected-row widget) (length rows)))
    (setf (table-widget-selected-row widget)
          (and rows (1- (length rows)))))
  (%table-ensure-selected-row-visible widget)
  widget)

(defun table-widget-select-row (widget row)
  (check-type widget table-widget)
  (when (and (integerp row) (<= 0 row) (< row (length (table-widget-rows widget))))
    (setf (table-widget-selected-row widget) row)
    (%table-ensure-selected-row-visible widget)
    widget))

(defun table-widget-select-column (widget column)
  (check-type widget table-widget)
  (when (and (integerp column) (<= 0 column)
             (< column (length (table-widget-columns widget))))
    (setf (table-widget-selected-column widget) column)
    widget))

(defmethod widget-preferred-size ((widget table-widget))
  (let ((width (loop for column in (table-widget-columns widget)
                     sum (1+ (string-cell-width (table-column-label column)))))
        (height (+ (if (slot-value widget 'header-p) 1 0)
                   (* (length (table-widget-rows widget))
                      (slot-value widget 'row-height)))))
    (make-size (max 1 width) (max 1 height))))

(defmethod widget-layout ((widget table-widget) rectangle)
  (call-next-method)
  (%table-clamp-row-offset widget)
  (%table-ensure-selected-row-visible widget))

(defmethod widget-render ((widget table-widget) surface)
  (let* ((area (widget-rectangle widget))
         (columns (table-widget-columns widget))
         (rows (table-widget-rows widget))
         (widths (%table-widths widget))
         (row-height (slot-value widget 'row-height))
         (header-p (slot-value widget 'header-p))
         (base-style (%widget-role-style widget :foreground))
         (header-style (%widget-role-style widget :border))
         (selected-style (%widget-role-style widget :accent)))
    (surface-fill-rectangle surface area #\Space base-style)
    (let ((y (rectangle-y area))
          (x (rectangle-x area)))
      (when header-p
        (loop for column in columns for width in widths
              do (surface-draw-text surface x y
                                     (%table-padded-cell (table-column-label column)
                                                         width (table-column-align column))
                                     :style header-style :max-width width)
                 (incf x width))
        (incf y))
      (%table-clamp-row-offset widget)
      (loop for row in (nthcdr (table-widget-row-offset widget) rows)
            for row-index from (table-widget-row-offset widget)
            while (< y (rectangle-bottom area))
            do (let ((x (rectangle-x area)))
                 (loop for column in columns for width in widths for column-index from 0
                       do (surface-draw-text
                           surface x y
                           (%table-padded-cell
                            (%table-column-value column row column-index)
                            width (table-column-align column))
                           :style (if (and (table-widget-selected-row widget)
                                           (= row-index (table-widget-selected-row widget))
                                           (= column-index (table-widget-selected-column widget)))
                                      selected-style
                                      (if (and (table-widget-selected-row widget)
                                               (= row-index (table-widget-selected-row widget)))
                                          selected-style base-style))
                           :max-width width)
                          (incf x width)))
               (incf y row-height))))
  widget)

(defmethod widget-accessibility-info ((widget table-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :grid))
    (setf (getf info :state)
          (list :row-count (length (table-widget-rows widget))
                :column-count (length (table-widget-columns widget))
                :selected-row (table-widget-selected-row widget)
                :selected-column (table-widget-selected-column widget)))
    info))

(defun %table-select-row-and-move (widget row action distance)
  (table-widget-select-row widget row)
  (move-action action distance widget))

(defun %table-handle-vertical-key (widget key)
  (let ((selected (table-widget-selected-row widget))
        (row-count (length (table-widget-rows widget))))
    (cond
      ((member key '(:up :k-up) :test #'equalp)
       (when (and selected (plusp selected))
         (%table-select-row-and-move widget (1- selected) :up 1)))
      ((member key '(:down :k-down) :test #'equalp)
       (when (and selected (< (1+ selected) row-count))
         (%table-select-row-and-move widget (1+ selected) :down 1))))))

(defun %table-handle-horizontal-key (widget key)
  (let ((selected (table-widget-selected-column widget))
        (column-count (length (table-widget-columns widget))))
    (cond
      ((equalp key :left)
       (when (plusp selected)
         (table-widget-select-column widget (1- selected))
         (move-action :left 1 widget)))
      ((equalp key :right)
       (when (< (1+ selected) column-count)
         (table-widget-select-column widget (1+ selected))
         (move-action :right 1 widget))))))

(defun %table-handle-boundary-key (widget key)
  (let ((rows (table-widget-rows widget)))
    (cond
      ((equalp key :home)
       (when rows
         (%table-select-row-and-move widget 0 :home 1)))
      ((equalp key :end)
       (when rows
         (%table-select-row-and-move widget (1- (length rows)) :end 1))))))

(defun %table-handle-page-key (widget key)
  (let ((selected (table-widget-selected-row widget)))
    (cond
      ((member key '(:page-up :prior :previous-page) :test #'equalp)
       (when selected
         (let ((distance (%table-visible-row-count widget)))
           (%table-select-row-and-move widget (- selected distance)
                                        :page-up distance))))
      ((member key '(:page-down :next-page) :test #'equalp)
       (when selected
         (let ((distance (%table-visible-row-count widget)))
           (%table-select-row-and-move widget (+ selected distance)
                                        :page-down distance)))))))

(defun %table-handle-activate-key (widget key)
  (when (and (member key '(:enter :return) :test #'equalp)
             (table-widget-selected-row widget))
    (select-action (list :row (table-widget-selected-row widget)
                         :column (table-widget-selected-column widget))
                   widget)))

(defun %table-handle-key-event (widget event)
  (let ((key (key-event-key event)))
    (or (%table-handle-vertical-key widget key)
        (%table-handle-horizontal-key widget key)
        (%table-handle-boundary-key widget key)
        (%table-handle-page-key widget key)
        (%table-handle-activate-key widget key))))

(defun %table-handle-mouse-event (widget event)
  (when (and (eq (mouse-event-kind event) :press)
             (rectangle-contains-point-p
              (widget-rectangle widget)
              (make-point (mouse-event-x event) (mouse-event-y event))))
    (let* ((area (widget-rectangle widget))
           (rows (table-widget-rows widget))
           (header-offset (if (slot-value widget 'header-p) 1 0))
           (local-row (floor (- (mouse-event-y event) (rectangle-y area)
                                header-offset)
                               (slot-value widget 'row-height)))
           (row (+ local-row (table-widget-row-offset widget)))
           (column (%table-column-at-x widget (mouse-event-x event))))
      (when (and (<= 0 local-row) (< row (length rows)) column)
        (table-widget-select-row widget row)
        (table-widget-select-column widget column)
        (select-action (list :row row :column column) widget)))))

(defmethod widget-handle-event ((widget table-widget) event)
  (cond
    ((typep event 'key-event)
     (%table-handle-key-event widget event))
    ((typep event 'mouse-event)
     (%table-handle-mouse-event widget event))))
