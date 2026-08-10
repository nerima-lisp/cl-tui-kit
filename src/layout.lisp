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

;;;; Placement and preferred-size calculations live in
;;;; src/layout-placement.lisp.
