(in-package #:cl-tui-kit/layout)

;;;; Layout is deliberately a pure calculation over rectangles.  It does not
;;;; know about widgets, application state, or terminal capabilities.

(defstruct (layout-item
            (:constructor %make-layout-item (child constraints margin)))
  child
  (constraints (make-constraints) :type constraints)
  (margin (make-margin) :type margin))

(defun make-layout-item (child &key constraints margin)
  (%make-layout-item child (or constraints (make-constraints))
                     (or margin (make-margin))))

(defstruct (layout-node
            (:constructor %make-layout-node (kind children constraints options)))
  (kind :stack :type keyword)
  (children '() :type list)
  (constraints (make-constraints) :type constraints)
  (options '() :type list))

(defun layout-kind (node)
  "Return NODE's layout primitive kind."
  (layout-node-kind node))

(defun layout-children (node)
  "Return NODE's immediate layout items."
  (layout-node-children node))

(defun %layout-children (children)
  (mapcar (lambda (child)
            (if (typep child 'layout-item)
                child
                (make-layout-item child)))
          (if (and (= (length children) 1)
                   (listp (first children))
                   (not (typep (first children) 'layout-node)))
              (first children)
              children)))

(defun make-layout-node (kind children &key constraints options)
  (check-type kind keyword)
  (%make-layout-node kind (%layout-children children)
                     (or constraints (make-constraints)) options))

(defun %check-non-negative-integer (value name)
  (unless (and (integerp value) (>= value 0))
    (error "~A must be a non-negative integer: ~S" name value))
  value)

(defun make-vbox (children &key constraints (gap 0))
  (%check-non-negative-integer gap :gap)
  (make-layout-node :vbox children :constraints constraints
                    :options (list :gap gap)))

(defun make-hbox (children &key constraints (gap 0))
  (%check-non-negative-integer gap :gap)
  (make-layout-node :hbox children :constraints constraints
                    :options (list :gap gap)))

(defun make-stack (children &key constraints)
  (make-layout-node :stack children :constraints constraints))

(defun make-overlay (children &key constraints)
  (make-layout-node :overlay children :constraints constraints))

(defun make-split (children &key (ratio 0.5) (axis :horizontal) constraints)
  (unless (and (realp ratio) (<= 0 ratio) (<= ratio 1))
    (error "Split ratio must be between 0 and 1: ~S" ratio))
  (unless (member axis '(:horizontal :vertical) :test #'eq)
    (error "Split axis must be :HORIZONTAL or :VERTICAL: ~S" axis))
  (make-layout-node :split children :constraints constraints
                    :options (list :ratio ratio :axis axis)))

(defun make-padding-layout (child &key (padding (make-padding)) constraints)
  (make-layout-node :padding (list child) :constraints constraints
                    :options (list :padding padding)))

(defun make-border-layout (child &key (padding (make-padding :all 1)) constraints)
  (make-layout-node :border (list child) :constraints constraints
                    :options (list :padding padding)))

(defun make-center-layout (child &key constraints)
  (make-layout-node :center (list child) :constraints constraints))

(defun make-viewport-layout (child &key constraints)
  (make-layout-node :viewport (list child) :constraints constraints))

(defun make-scroll-container (child &key constraints)
  (make-layout-node :scroll (list child) :constraints constraints))

(defun make-grid (children &key columns rows (column-gap 0) (row-gap 0)
                             constraints)
  (unless (and (integerp columns) (plusp columns))
    (error "Grid columns must be a positive integer: ~S" columns))
  (when rows
    (unless (and (integerp rows) (plusp rows))
      (error "Grid rows must be a positive integer when supplied: ~S" rows)))
  (%check-non-negative-integer column-gap :column-gap)
  (%check-non-negative-integer row-gap :row-gap)
  (make-layout-node :grid children :constraints constraints
                    :options (list :columns columns :rows rows
                                   :column-gap column-gap :row-gap row-gap)))

(defun %option (node key &optional default)
  (getf (layout-node-options node) key default))

(defun %axis-min (constraints axis)
  (if (eq axis :height)
      (constraints-min-height constraints)
      (constraints-min-width constraints)))

(defun %axis-preferred (constraints axis)
  (or (if (eq axis :height)
          (constraints-preferred-height constraints)
          (constraints-preferred-width constraints))
      (%axis-min constraints axis)))

(defun %axis-max (constraints axis)
  (if (eq axis :height)
      (constraints-max-height constraints)
      (constraints-max-width constraints)))

(defun %axis-flex (constraints axis)
  (if (eq axis :height)
      (constraints-flex-height constraints)
      (constraints-flex-width constraints)))

(defun %item-margin-before (item axis)
  (if (eq axis :height)
      (margin-top (layout-item-margin item))
      (margin-left (layout-item-margin item))))

(defun %item-margin-after (item axis)
  (if (eq axis :height)
      (margin-bottom (layout-item-margin item))
      (margin-right (layout-item-margin item))))

(defun %item-axis-min (item axis)
  (+ (%axis-min (layout-item-constraints item) axis)
     (%item-margin-before item axis)
     (%item-margin-after item axis)))

(defun %item-axis-preferred (item axis)
  (+ (%axis-preferred (layout-item-constraints item) axis)
     (%item-margin-before item axis)
     (%item-margin-after item axis)))

(defun %item-axis-max (item axis)
  (let ((maximum (%axis-max (layout-item-constraints item) axis)))
    (when maximum
      (+ maximum (%item-margin-before item axis)
         (%item-margin-after item axis)))))

(defun %trim-to-fit (sizes available)
  (let ((excess (- (reduce #'+ sizes :initial-value 0) available)))
    (when (plusp excess)
      (loop for index downfrom (1- (length sizes)) to 0
            while (plusp excess)
            for amount = (min excess (aref sizes index))
            do (decf (aref sizes index) amount)
               (decf excess amount))))
  sizes)

(defun %distribute-toward (sizes items remaining axis)
  (when (plusp remaining)
    (loop with progress = t
          while (and (plusp remaining) progress)
          do (setf progress nil)
             (loop for index below (length items)
                   while (plusp remaining)
                   for item = (aref items index)
                   for target = (%item-axis-preferred item axis)
                   for maximum = (%item-axis-max item axis)
                   when (and (< (aref sizes index) target)
                              (or (null maximum)
                                  (< (aref sizes index) maximum)))
                     do (incf (aref sizes index))
                        (decf remaining)
                        (setf progress t))))
  remaining)

(defun %distribute-flex (sizes items remaining axis)
  (when (plusp remaining)
    (let ((growth (make-array (length items)
                              :element-type 'integer
                              :initial-element 0)))
      (loop while (plusp remaining)
            do (let ((best-index nil)
                     (best-score nil))
                 (loop for index below (length items)
                       for item = (aref items index)
                       for flexibility = (%axis-flex
                                          (layout-item-constraints item) axis)
                       for maximum = (%item-axis-max item axis)
                       when (and (plusp flexibility)
                                 (or (null maximum)
                                     (< (aref sizes index) maximum)))
                         do (let ((score (/ (1+ (aref growth index))
                                            flexibility)))
                              (when (or (null best-score)
                                        (< score best-score)
                                        (and (= score best-score)
                                             (< index best-index)))
                                (setf best-index index
                                      best-score score))))
                 (unless best-index
                   (return))
                 (incf (aref sizes best-index))
                 (incf (aref growth best-index))
                 (decf remaining)))))
  remaining)

(defun %allocate-axis (available children axis)
  (let* ((items (coerce children 'vector))
         (sizes (make-array (length items) :element-type 'integer :initial-element 0)))
    (loop for index below (length items)
          for item = (aref items index)
          do (setf (aref sizes index) (%item-axis-min item axis)))
    (%trim-to-fit sizes available)
    (let ((remaining (- available (reduce #'+ sizes :initial-value 0))))
      (setf remaining (%distribute-toward sizes items remaining axis))
      (%distribute-flex sizes items remaining axis))
    sizes))

(defun %item-content-rectangle (rectangle item)
  (let ((margin (layout-item-margin item)))
    (rectangle-inset
     rectangle
     (make-padding :top (margin-top margin)
                   :right (margin-right margin)
                   :bottom (margin-bottom margin)
                   :left (margin-left margin)))))

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

(defun %child-rectangles (node bounds)
  (let* ((children (coerce (layout-node-children node) 'vector))
         (kind (layout-kind node))
         (count (length children))
         (rectangles (make-array count :initial-element nil)))
    (cond
      ((member kind '(:vbox :hbox) :test #'eq)
       (let* ((axis (if (eq kind :vbox) :height :width))
              (gap (%option node :gap 0))
              (available (if (eq axis :height)
                             (- (rectangle-height bounds)
                                (* gap (max 0 (1- count))))
                             (- (rectangle-width bounds)
                                (* gap (max 0 (1- count))))))
              (sizes (%allocate-axis available children axis))
              (cursor (if (eq axis :height)
                          (rectangle-y bounds)
                          (rectangle-x bounds))))
         (loop for index below count
               for amount = (aref sizes index)
               do (setf (aref rectangles index)
                        (%item-content-rectangle
                         (if (eq axis :height)
                             (make-rectangle (rectangle-x bounds) cursor
                                             (rectangle-width bounds) amount)
                             (make-rectangle cursor (rectangle-y bounds)
                                             amount (rectangle-height bounds)))
                         (aref children index)))
                  (incf cursor (+ amount gap)))))
      ((eq kind :grid)
       (dolist (entry (%grid-rectangles node bounds children))
         (setf (aref rectangles (car entry)) (cdr entry))))
      ((eq kind :split)
       (when (= count 2)
         (let* ((ratio (%option node :ratio 0.5))
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
      ((member kind '(:stack :overlay) :test #'eq)
       (loop for index below count
             do (setf (aref rectangles index)
                      (%item-content-rectangle bounds (aref children index)))))
      ((member kind '(:padding :border) :test #'eq)
       (when (plusp count)
         (setf (aref rectangles 0)
               (%item-content-rectangle
                (rectangle-inset bounds (%option node :padding (make-padding)))
                (aref children 0)))))
      ((eq kind :center)
       (when (plusp count)
           (let* ((child (layout-item-child (aref children 0)))
                  (preferred (layout-preferred-size child))
                  (width (min (rectangle-width bounds) (size-width preferred)))
                  (height (min (rectangle-height bounds) (size-height preferred))))
           (setf (aref rectangles 0)
                 (%item-content-rectangle
                  (make-rectangle (+ (rectangle-x bounds)
                                     (floor (- (rectangle-width bounds) width) 2))
                                  (+ (rectangle-y bounds)
                                     (floor (- (rectangle-height bounds) height) 2))
                                  width height)
                  (aref children 0))))))
      ((member kind '(:viewport :scroll) :test #'eq)
       (when (plusp count)
         (setf (aref rectangles 0)
               (%item-content-rectangle bounds (aref children 0)))))
      (t
      (loop for index below count
             do (setf (aref rectangles index)
                      (%item-content-rectangle bounds (aref children index)))))
    )
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
