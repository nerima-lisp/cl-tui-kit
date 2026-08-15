(in-package #:cl-tui-kit/core)

;;;; Geometry is integer-only.  Coordinates may be negative when a child is
;;;; translated, but all extents are normalized to non-negative cell counts.

(defun %coordinate (value name)
  (unless (integerp value)
    (error 'invalid-type-error :context name :datum value :expected-type 'integer))
  value)

(defun %extent (value name)
  (unless (integerp value)
    (error 'invalid-type-error :context name :datum value :expected-type '(integer 0)))
  (max 0 value))

(defstruct (point (:constructor %make-point (x y))
                  (:copier nil))
  (x 0 :type integer)
  (y 0 :type integer))

(defun make-point (&optional (x 0) (y 0))
  (%make-point (%coordinate x 'x) (%coordinate y 'y)))

(defun copy-point (point)
  (make-point (point-x point) (point-y point)))

(defstruct (size (:constructor %make-size (width height))
                 (:copier nil))
  (width 0 :type (integer 0))
  (height 0 :type (integer 0)))

(defun make-size (&optional (width 0) (height 0))
  (%make-size (%extent width 'width) (%extent height 'height)))

(defun copy-size (size)
  (make-size (size-width size) (size-height size)))

(defstruct (rectangle (:constructor %make-rectangle (x y width height))
                      (:copier nil))
  (x 0 :type integer)
  (y 0 :type integer)
  (width 0 :type (integer 0))
  (height 0 :type (integer 0)))

(defun make-rectangle (&optional (x 0) (y 0) (width 0) (height 0))
  (%make-rectangle (%coordinate x 'x)
                   (%coordinate y 'y)
                   (%extent width 'width)
                   (%extent height 'height)))

(defun copy-rectangle (rectangle)
  (make-rectangle (rectangle-x rectangle)
                  (rectangle-y rectangle)
                  (rectangle-width rectangle)
                  (rectangle-height rectangle)))

(defun rectangle-empty-p (rectangle)
  (or (zerop (rectangle-width rectangle))
      (zerop (rectangle-height rectangle))))

(defun rectangle-right (rectangle)
  (+ (rectangle-x rectangle) (rectangle-width rectangle)))

(defun rectangle-bottom (rectangle)
  (+ (rectangle-y rectangle) (rectangle-height rectangle)))

(defun rectangle-contains-point-p (rectangle point-or-x &optional y)
  (let ((x (if (typep point-or-x 'point)
               (point-x point-or-x)
               point-or-x))
        (point-y-value (if (typep point-or-x 'point)
                           (point-y point-or-x)
                           y)))
    (and (not (rectangle-empty-p rectangle))
         (<= (rectangle-x rectangle) x)
         (< x (rectangle-right rectangle))
         (<= (rectangle-y rectangle) point-y-value)
         (< point-y-value (rectangle-bottom rectangle)))))

(defun rectangle-contains-rectangle-p (outer inner)
  (or (rectangle-empty-p inner)
      (and (<= (rectangle-x outer) (rectangle-x inner))
           (<= (rectangle-y outer) (rectangle-y inner))
           (<= (rectangle-right inner) (rectangle-right outer))
           (<= (rectangle-bottom inner) (rectangle-bottom outer)))))

(defun rectangle-intersection (left right)
  (let ((x (max (rectangle-x left) (rectangle-x right)))
        (y (max (rectangle-y left) (rectangle-y right)))
        (right-edge (min (rectangle-right left) (rectangle-right right)))
        (bottom-edge (min (rectangle-bottom left) (rectangle-bottom right))))
    (make-rectangle x y (max 0 (- right-edge x)) (max 0 (- bottom-edge y)))))

(defun rectangle-union (left right)
  (cond
    ((rectangle-empty-p left) (copy-rectangle right))
    ((rectangle-empty-p right) (copy-rectangle left))
    (t
     (let ((x (min (rectangle-x left) (rectangle-x right)))
           (y (min (rectangle-y left) (rectangle-y right)))
           (right-edge (max (rectangle-right left) (rectangle-right right)))
           (bottom-edge (max (rectangle-bottom left) (rectangle-bottom right))))
       (make-rectangle x y (- right-edge x) (- bottom-edge y))))))

(defun rectangle-offset (rectangle dx dy)
  (make-rectangle (+ (rectangle-x rectangle) (%coordinate dx 'dx))
                  (+ (rectangle-y rectangle) (%coordinate dy 'dy))
                  (rectangle-width rectangle)
                  (rectangle-height rectangle)))

(defstruct (padding (:constructor %make-padding (top right bottom left))
                    (:copier nil))
  (top 0 :type (integer 0))
  (right 0 :type (integer 0))
  (bottom 0 :type (integer 0))
  (left 0 :type (integer 0)))

(defun make-padding (&key (top 0) (right top) (bottom top) (left right) all)
  (when all
    (setf top all right all bottom all left all))
  (%make-padding (%extent top 'top)
                 (%extent right 'right)
                 (%extent bottom 'bottom)
                 (%extent left 'left)))

(defun copy-padding (padding)
  (make-padding :top (padding-top padding)
                :right (padding-right padding)
                :bottom (padding-bottom padding)
                :left (padding-left padding)))

(defun rectangle-inset (rectangle padding)
  (make-rectangle (+ (rectangle-x rectangle) (padding-left padding))
                  (+ (rectangle-y rectangle) (padding-top padding))
                  (max 0 (- (rectangle-width rectangle)
                            (padding-left padding)
                            (padding-right padding)))
                  (max 0 (- (rectangle-height rectangle)
                            (padding-top padding)
                            (padding-bottom padding)))))

(defstruct (margin (:constructor %make-margin (top right bottom left))
                   (:copier nil))
  (top 0 :type (integer 0))
  (right 0 :type (integer 0))
  (bottom 0 :type (integer 0))
  (left 0 :type (integer 0)))

(defun make-margin (&key (top 0) (right top) (bottom top) (left right) all)
  (when all
    (setf top all right all bottom all left all))
  (%make-margin (%extent top 'top)
                (%extent right 'right)
                (%extent bottom 'bottom)
                (%extent left 'left)))

(defun copy-margin (margin)
  (make-margin :top (margin-top margin)
               :right (margin-right margin)
               :bottom (margin-bottom margin)
               :left (margin-left margin)))

(defstruct (constraints
            (:copier nil)
            (:constructor %make-constraints
                (min-width preferred-width max-width
                 min-height preferred-height max-height flex-width flex-height)))
  (min-width 0 :type (integer 0))
  preferred-width
  max-width
  (min-height 0 :type (integer 0))
  preferred-height
  max-height
  (flex-width 0 :type number)
  (flex-height 0 :type number))

(defun %optional-extent (value)
  (when value (%extent value 'constraint)))

(defun make-constraints (&key (min-width 0) preferred-width max-width
                              (min-height 0) preferred-height max-height
                              (flex-width 0) (flex-height 0))
  (unless (and (realp flex-width) (>= flex-width 0)
               (realp flex-height) (>= flex-height 0))
    (error 'invalid-range-error
           :context "Flexibility"
           :datum (list flex-width flex-height)
           :expected "a non-negative real number"
           :detail "Flexibility must be a non-negative real number."))
  (let* ((minimum-width (%extent min-width 'min-width))
         (maximum-width (%optional-extent max-width))
         (minimum-height (%extent min-height 'min-height))
         (maximum-height (%optional-extent max-height)))
    (when (and maximum-width (< maximum-width minimum-width))
      (error 'invalid-range-error
             :context 'max-width
             :datum maximum-width
             :expected (format nil "no smaller than MIN-WIDTH (~D)" minimum-width)
             :detail (format nil "MAX-WIDTH ~D cannot be smaller than MIN-WIDTH ~D."
                              maximum-width minimum-width)))
    (when (and maximum-height (< maximum-height minimum-height))
      (error 'invalid-range-error
             :context 'max-height
             :datum maximum-height
             :expected (format nil "no smaller than MIN-HEIGHT (~D)" minimum-height)
             :detail (format nil "MAX-HEIGHT ~D cannot be smaller than MIN-HEIGHT ~D."
                              maximum-height minimum-height)))
    (%make-constraints minimum-width
                       (%optional-extent preferred-width)
                       maximum-width
                       minimum-height
                       (%optional-extent preferred-height)
                       maximum-height
                       flex-width flex-height)))

(defun copy-constraints (constraints)
  (make-constraints
   :min-width (constraints-min-width constraints)
   :preferred-width (constraints-preferred-width constraints)
   :max-width (constraints-max-width constraints)
   :min-height (constraints-min-height constraints)
   :preferred-height (constraints-preferred-height constraints)
   :max-height (constraints-max-height constraints)
   :flex-width (constraints-flex-width constraints)
   :flex-height (constraints-flex-height constraints)))

(defun resolve-axis (available constraints axis)
  "Resolve one axis deterministically, clamping to available space.

AXIS is :WIDTH or :HEIGHT.  A preferred size is honored when possible;
flexibility is used by layout containers when extra space is distributed."
  (let* ((available (%extent available 'available))
         (minimum (if (eq axis :height)
                      (constraints-min-height constraints)
                      (constraints-min-width constraints)))
         (preferred (if (eq axis :height)
                        (constraints-preferred-height constraints)
                        (constraints-preferred-width constraints)))
         (maximum (if (eq axis :height)
                      (constraints-max-height constraints)
                      (constraints-max-width constraints)))
         (value (or preferred minimum)))
    (when maximum (setf value (min value maximum)))
    (max 0 (min available (max minimum value)))))

(defstruct (clipping-region (:constructor %make-clipping-region (rectangle))
                            (:copier nil))
  rectangle)

(defun make-clipping-region (&optional (rectangle (make-rectangle)))
  (%make-clipping-region (copy-rectangle rectangle)))

(defstruct (viewport
            (:copier nil)
            (:constructor %make-viewport
                (bounds content-width content-height %offset-x %offset-y)))
  (bounds (make-rectangle) :type rectangle)
  (content-width 0 :type (integer 0))
  (content-height 0 :type (integer 0))
  (%offset-x 0 :type (integer 0))
  (%offset-y 0 :type (integer 0)))

(defun viewport-offset-x (viewport)
  "Return VIEWPORT's horizontal scroll offset.

This value is kept clamped to [0, VIEWPORT-SCROLL-X-MAX] by the owning
subsystem; use VIEWPORT-SCROLL-TO or VIEWPORT-SCROLL-BY to change it."
  (viewport-%offset-x viewport))

(defun viewport-offset-y (viewport)
  "Return VIEWPORT's vertical scroll offset.

This value is kept clamped to [0, VIEWPORT-SCROLL-Y-MAX] by the owning
subsystem; use VIEWPORT-SCROLL-TO or VIEWPORT-SCROLL-BY to change it."
  (viewport-%offset-y viewport))

(defun make-viewport (&key (bounds (make-rectangle)) (content-width 0)
                           (content-height 0) (offset-x 0) (offset-y 0))
  (let ((viewport (%make-viewport (copy-rectangle bounds)
                                  (%extent content-width 'content-width)
                                  (%extent content-height 'content-height)
                                  0 0)))
    (viewport-scroll-to viewport offset-x offset-y)))

(defun viewport-scroll-x-max (viewport)
  (max 0 (- (viewport-content-width viewport)
            (rectangle-width (viewport-bounds viewport)))))

(defun viewport-scroll-y-max (viewport)
  (max 0 (- (viewport-content-height viewport)
            (rectangle-height (viewport-bounds viewport)))))

(defun viewport-scroll-to (viewport x y)
  (setf (viewport-%offset-x viewport)
        (min (viewport-scroll-x-max viewport) (max 0 (%coordinate x 'x)))
        (viewport-%offset-y viewport)
        (min (viewport-scroll-y-max viewport) (max 0 (%coordinate y 'y))))
  viewport)

(defun viewport-scroll-by (viewport dx dy)
  (viewport-scroll-to viewport
                      (+ (viewport-%offset-x viewport) (%coordinate dx 'dx))
                      (+ (viewport-%offset-y viewport) (%coordinate dy 'dy))))

(defun viewport-visible-rectangle (viewport)
  (let ((bounds (viewport-bounds viewport)))
    (make-rectangle (viewport-%offset-x viewport)
                    (viewport-%offset-y viewport)
                    (rectangle-width bounds)
                    (rectangle-height bounds))))
