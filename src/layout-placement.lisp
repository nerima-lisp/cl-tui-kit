(in-package #:cl-tui-kit/layout)

;;;; Placement and preferred-size calculations -------------------------------

(defun %grid-track-items (children track columns &key row-p)
  (loop for index below (length children)
        for item = (aref children index)
        when (= (if row-p (floor index columns) (mod index columns)) track)
          collect item))

(defun %grid-track-constraints (children track columns axis &key row-p)
  (let ((items (%grid-track-items children track columns :row-p row-p)))
    (if items
        (let* ((minimum (reduce #'max items
                                :key (lambda (item)
                                       (%axis-min
                                        (layout-item-constraints item) axis))
                                :initial-value 0))
               (preferred (reduce #'max items
                                  :key (lambda (item)
                                         (%axis-preferred
                                          (layout-item-constraints item) axis))
                                  :initial-value minimum))
               (maximums (remove nil
                                 (mapcar (lambda (item)
                                           (%axis-max
                                            (layout-item-constraints item) axis))
                                         items)))
               (maximum (and maximums (reduce #'min maximums)))
               (flexibility (reduce #'max items
                                    :key (lambda (item)
                                           (%axis-flex
                                            (layout-item-constraints item) axis))
                                    :initial-value 0)))
          (if (eq axis :height)
              (make-constraints :min-height minimum
                                :preferred-height preferred
                                :max-height maximum
                                :flex-height flexibility)
              (make-constraints :min-width minimum
                                :preferred-width preferred
                                :max-width maximum
                                :flex-width flexibility)))
        (make-constraints))))

(defun %grid-rectangles (node bounds children)
  (let* ((columns (%option node :columns 1))
         (requested-rows (%option node :rows nil))
         (rows (max (or requested-rows 0)
                    (ceiling (length children) columns)))
         (column-gap (%option node :column-gap 0))
         (row-gap (%option node :row-gap 0))
         (column-constraints
           (loop for column below columns
                 collect (%grid-track-constraints children column columns :width)))
         (row-constraints
           (loop for row below rows
                 collect (%grid-track-constraints children row columns :height)))
         (column-items
           (mapcar (lambda (constraints)
                     (make-layout-item nil :constraints constraints))
                   column-constraints))
         (row-items
           (mapcar (lambda (constraints)
                     (make-layout-item nil :constraints constraints))
                   row-constraints))
         (available-width
           (max 0 (- (rectangle-width bounds)
                     (* column-gap (max 0 (1- columns))))))
         (available-height
           (max 0 (- (rectangle-height bounds)
                     (* row-gap (max 0 (1- rows))))))
         (column-sizes
           (%allocate-axis available-width
                           (coerce column-items 'vector) :width))
         (row-sizes
           (%allocate-axis available-height
                           (coerce row-items 'vector) :height))
         (column-offsets (make-array columns))
         (row-offsets (make-array rows)))
    (loop with cursor = (rectangle-x bounds)
          for column below columns
          do (setf (aref column-offsets column) cursor)
             (incf cursor (+ (aref column-sizes column) column-gap)))
    (loop with cursor = (rectangle-y bounds)
          for row below rows
          do (setf (aref row-offsets row) cursor)
             (incf cursor (+ (aref row-sizes row) row-gap)))
    (loop for index below (length children)
          for column = (mod index columns)
          for row = (floor index columns)
          when (< row rows)
            collect
            (cons index
                  (%item-content-rectangle
                   (make-rectangle (aref column-offsets column)
                                   (aref row-offsets row)
                                   (aref column-sizes column)
                                   (aref row-sizes row))
                   (aref children index))))))


(defun %axis-rectangle (bounds axis cursor amount)
  (if (eq axis :height)
      (make-rectangle (rectangle-x bounds) cursor
                      (rectangle-width bounds) amount)
      (make-rectangle cursor (rectangle-y bounds)
                      amount (rectangle-height bounds))))

(defun %layout-linear-rectangles (node bounds children rectangles)
  (let* ((axis (if (eq (layout-kind node) :vbox) :height :width))
         (gap (%option node :gap 0))
         (gaps (* gap (max 0 (1- (length children)))))
         (available (if (eq axis :height)
                        (- (rectangle-height bounds) gaps)
                        (- (rectangle-width bounds) gaps)))
         (sizes (%allocate-axis available children axis)))
    (loop with cursor = (if (eq axis :height)
                            (rectangle-y bounds)
                            (rectangle-x bounds))
          for index below (length children)
          for amount = (aref sizes index)
          do (setf (aref rectangles index)
                   (%item-content-rectangle
                    (%axis-rectangle bounds axis cursor amount)
                    (aref children index)))
             (incf cursor (+ amount gap)))))

(defun %layout-split-rectangles (node bounds rectangles)
  (when (= (length rectangles) 2)
    (let ((ratio (%option node :ratio 0.5))
          (axis (%option node :axis :horizontal)))
      (if (eq axis :horizontal)
          (let ((first-width (floor (* ratio (rectangle-width bounds)))))
            (setf (aref rectangles 0)
                  (make-rectangle (rectangle-x bounds) (rectangle-y bounds)
                                  first-width (rectangle-height bounds))
                  (aref rectangles 1)
                  (make-rectangle (+ (rectangle-x bounds) first-width)
                                  (rectangle-y bounds)
                                  (- (rectangle-width bounds) first-width)
                                  (rectangle-height bounds))))
          (let ((first-height (floor (* ratio (rectangle-height bounds)))))
            (setf (aref rectangles 0)
                  (make-rectangle (rectangle-x bounds) (rectangle-y bounds)
                                  (rectangle-width bounds) first-height)
                  (aref rectangles 1)
                  (make-rectangle (rectangle-x bounds)
                                  (+ (rectangle-y bounds) first-height)
                                  (rectangle-width bounds)
                                  (- (rectangle-height bounds)
                                     first-height))))))))

(defun %layout-fill-rectangles (bounds children rectangles)
  (loop for index below (length children)
        do (setf (aref rectangles index)
                 (%item-content-rectangle bounds (aref children index)))))

(defun %layout-single-child-rectangle (node bounds item)
  (case (layout-kind node)
    ((:padding :border)
     (%item-content-rectangle
      (rectangle-inset bounds (%option node :padding (make-padding)))
      item))
    (:center
     (let* ((preferred (layout-preferred-size (layout-item-child item)))
            (width (min (rectangle-width bounds) (size-width preferred)))
            (height (min (rectangle-height bounds) (size-height preferred))))
       (%item-content-rectangle
        (make-rectangle (+ (rectangle-x bounds)
                           (floor (- (rectangle-width bounds) width) 2))
                        (+ (rectangle-y bounds)
                           (floor (- (rectangle-height bounds) height) 2))
                        width height)
        item)))
    ((:viewport :scroll)
     (%item-content-rectangle bounds item))))

(defun %child-rectangles (node bounds)
  (let* ((children (coerce (layout-node-children node) 'vector))
         (kind (layout-kind node))
         (count (length children))
         (rectangles (make-array count :initial-element nil)))
    (cond
      ((member kind '(:vbox :hbox) :test #'eq)
       (%layout-linear-rectangles node bounds children rectangles))
      ((eq kind :grid)
       (dolist (entry (%grid-rectangles node bounds children))
         (setf (aref rectangles (car entry)) (cdr entry))))
      ((eq kind :split)
       (%layout-split-rectangles node bounds rectangles))
      ((member kind '(:stack :overlay) :test #'eq)
       (%layout-fill-rectangles bounds children rectangles))
      ((member kind '(:padding :border :center :viewport :scroll) :test #'eq)
       (when (plusp count)
         (setf (aref rectangles 0)
               (%layout-single-child-rectangle node bounds
                                               (aref children 0)))))
      (t
       (%layout-fill-rectangles bounds children rectangles)))
    (loop for index below count
          collect (cons (layout-item-child (aref children index))
                        (or (aref rectangles index) (make-rectangle))))))

(defun layout-rects (layout bounds)
  "Return an alist mapping each immediate child of LAYOUT to a rectangle."
  (check-type layout layout-node)
  (check-type bounds rectangle)
  (%child-rectangles layout bounds))

(defun layout-child-rectangle (layout child bounds)
  (cdr (assoc child (layout-rects layout bounds) :test #'eq)))

(defun %layout-item-preferred-size (item)
  (let* ((preferred (layout-preferred-size (layout-item-child item)))
         (margin (layout-item-margin item)))
    (make-size (+ (size-width preferred)
                  (margin-left margin)
                  (margin-right margin))
               (+ (size-height preferred)
                  (margin-top margin)
                  (margin-bottom margin)))))

(defun %grid-preferred-size (child-sizes columns column-gap row-gap)
  (let* ((count (length child-sizes))
         (rows (ceiling count columns))
         (column-widths (make-array columns :initial-element 0))
         (row-heights (make-array rows :initial-element 0)))
    (loop for size in child-sizes
          for index from 0
          for column = (mod index columns)
          for row = (floor index columns)
          do (setf (aref column-widths column)
                   (max (aref column-widths column) (size-width size))
                   (aref row-heights row)
                   (max (aref row-heights row) (size-height size))))
    (make-size (+ (reduce #'+ column-widths :initial-value 0)
                  (* column-gap (max 0 (1- columns))))
               (+ (reduce #'+ row-heights :initial-value 0)
                  (* row-gap (max 0 (1- rows)))))))

(defgeneric layout-preferred-size (layout)
  (:documentation "Return the preferred terminal-cell size of a layout child."))

(defmethod layout-preferred-size ((layout t))
  (declare (ignore layout))
  (make-size))

(defmethod layout-preferred-size ((layout layout-item))
  (%layout-item-preferred-size layout))

(defmethod layout-preferred-size ((layout layout-node))
  (let* ((children (layout-node-children layout))
         (kind (layout-kind layout))
         (node-constraints (layout-node-constraints layout))
         (child-sizes (mapcar #'%layout-item-preferred-size
                             children))
         (base (if child-sizes
                   (case kind
                     ((:vbox)
                      (make-size (reduce #'max child-sizes :key #'size-width :initial-value 0)
                                 (+ (reduce #'+ child-sizes :key #'size-height
                                            :initial-value 0)
                                    (* (%option layout :gap 0)
                                       (max 0 (1- (length child-sizes)))))))
                     ((:hbox)
                      (make-size (+ (reduce #'+ child-sizes :key #'size-width
                                            :initial-value 0)
                                    (* (%option layout :gap 0)
                                       (max 0 (1- (length child-sizes)))))
                                 (reduce #'max child-sizes :key #'size-height :initial-value 0)))
                     ((:grid)
                      (%grid-preferred-size child-sizes
                                            (%option layout :columns 1)
                                            (%option layout :column-gap 0)
                                            (%option layout :row-gap 0)))
                     ((:split)
                      (if (eq (%option layout :axis :horizontal) :horizontal)
                          (make-size (reduce #'+ child-sizes :key #'size-width :initial-value 0)
                                     (reduce #'max child-sizes :key #'size-height :initial-value 0))
                          (make-size (reduce #'max child-sizes :key #'size-width :initial-value 0)
                                     (reduce #'+ child-sizes :key #'size-height :initial-value 0))))
                     (otherwise
                      (make-size (reduce #'max child-sizes :key #'size-width :initial-value 0)
                                 (reduce #'max child-sizes :key #'size-height :initial-value 0))))
                   (make-size (or (constraints-preferred-width node-constraints)
                                  (constraints-min-width node-constraints))
                              (or (constraints-preferred-height node-constraints)
                                  (constraints-min-height node-constraints))))))
    (case kind
      ((:padding :border)
       (let ((padding (%option layout :padding (make-padding))))
         (make-size (+ (size-width base) (padding-left padding) (padding-right padding))
                    (+ (size-height base) (padding-top padding) (padding-bottom padding)))))
      (otherwise base))))
