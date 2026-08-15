(in-package #:cl-tui-kit/core)

(defstruct (cell (:constructor %make-cell (content style span continuation-p))
                 (:copier nil))
  (content " " :type string)
  (style (make-style) :type style)
  (span 1 :type (integer 0))
  (continuation-p nil :type boolean))

(defstruct (text-span (:constructor %make-text-span (text style))
                      (:copier nil))
  "A string and the style that applies to its terminal cells."
  (text "" :type string)
  (style (make-style) :type style))

(defun make-text-span (text &key style)
  "Create an immutable-style TEXT-SPAN for styled surface drawing.

The style is copied so later changes to the caller's value object cannot
change the span's rendering contract."
  (check-type text string)
  (let ((draw-style (or style (make-style))))
    (check-type draw-style style)
    (%make-text-span text (copy-style draw-style))))

(defun %validate-cell-invariant (content span continuation-p)
  (if continuation-p
      (unless (and (string= content "") (zerop span))
        (error 'surface-error
               :detail "A continuation cell must have empty content and zero span."))
      (let ((units (text-units content)))
        (unless (and (= (length units) 1)
                     (= span (text-unit-width (first units)))
                     (plusp span))
          (error 'surface-error
                 :detail (format nil "A drawable cell must contain one display unit whose width matches its span: ~S / ~S."
                                  content span)))))
  t)

(defun %parse-keyword-options (arguments allowed)
  (unless (evenp (length arguments))
    (error 'invalid-argument-error
           :context 'arguments
           :datum arguments
           :detail "Keyword options must contain pairs."))
  (loop for (key value) on arguments by #'cddr
        do (unless (member key allowed :test #'eq)
             (error 'invalid-option-error
                    :context 'option
                    :datum key
                    :allowed allowed))
        append (list key value)))

(defun make-cell (&rest arguments)
  (let ((content " ")
        (style (make-style))
        (span 1)
        (continuation-p nil))
    (when (and arguments (not (keywordp (first arguments))))
      (setf content (pop arguments)))
    (let ((options (%parse-keyword-options
                    arguments '(:style :span :continuation-p))))
      (setf style (getf options :style style)
            span (getf options :span span)
            continuation-p (getf options :continuation-p continuation-p)))
    (when (characterp content)
      (setf content (string content)))
    (check-type content string)
    (unless (and (integerp span) (>= span 0))
      (error 'invalid-range-error
             :context 'span
             :datum span
             :expected "a non-negative integer"))
    (%validate-cell-invariant content span continuation-p)
    (%make-cell content (copy-style style) span (not (null continuation-p)))))

(defun copy-cell (cell)
  (%validate-cell-invariant (cell-content cell)
                           (cell-span cell)
                           (cell-continuation-p cell))
  (%make-cell (cell-content cell) (copy-style (cell-style cell))
              (cell-span cell) (cell-continuation-p cell)))

(defun blank-cell (&optional (style (make-style)))
  (make-cell " " :style style :span 1))

(defstruct (surface
            (:copier nil)
            (:constructor %make-surface
                (width height cells %clip dirty default-style)))
  (width 0 :type (integer 0))
  (height 0 :type (integer 0))
  cells
  (%clip (make-rectangle) :type rectangle)
  dirty
  (default-style (make-style) :type style))

(defun surface-clip (surface)
  "Return a copy of SURFACE's current clip rectangle.

The returned RECTANGLE is a fresh copy, so mutating its slots has no effect
on SURFACE; use SURFACE-SET-CLIP to change the clip, which clamps the new
rectangle to the surface's own bounds."
  (copy-rectangle (surface-%clip surface)))

(defun %surface-index (surface x y)
  (+ x (* y (surface-width surface))))

(defun %surface-bounds (surface)
  (make-rectangle 0 0 (surface-width surface) (surface-height surface)))

(defun %clip-rectangle (clip default)
  (let ((rectangle (typecase clip
                     (null default)
                     (rectangle clip)
                     (clipping-region (clipping-region-rectangle clip))
                     (t (error 'invalid-type-error
                               :context 'clip
                               :datum clip
                               :expected-type '(or rectangle clipping-region null))))))
    (copy-rectangle rectangle)))

(defun %surface-visible-p (surface x y)
  (and (<= 0 x) (< x (surface-width surface))
       (<= 0 y) (< y (surface-height surface))
       (rectangle-contains-point-p (surface-%clip surface) x y)))

(defun make-surface (&rest arguments)
  (let ((width 0)
        (height 0)
        (style (make-style))
        (clip nil))
    (when (and arguments (integerp (first arguments)))
      (setf width (pop arguments)))
    (when (and arguments (integerp (first arguments)))
      (setf height (pop arguments)))
    (let ((options (%parse-keyword-options arguments '(:style :clip))))
      (setf style (getf options :style style)
            clip (getf options :clip clip)))
    (unless (and (integerp width) (>= width 0)
                 (integerp height) (>= height 0))
      (error 'invalid-range-error
             :context "Surface dimensions"
             :datum (list width height)
             :expected "non-negative integers"))
    (let* ((default-style (copy-style style))
           (cells (make-array (* width height)))
           (surface (%make-surface width height cells
                                   (rectangle-intersection
                                    (%clip-rectangle clip
                                                     (make-rectangle 0 0 width height))
                                    (make-rectangle 0 0 width height))
                                   nil default-style)))
      (dotimes (index (length cells))
        (setf (aref cells index) (blank-cell default-style)))
      surface)))

(defun copy-surface (surface)
  (let ((copy (make-surface (surface-width surface) (surface-height surface)
                            :style (surface-default-style surface)
                            :clip (surface-%clip surface))))
    (dotimes (index (length (surface-cells surface)))
      (setf (aref (surface-cells copy) index)
            (copy-cell (aref (surface-cells surface) index))))
    (setf (surface-dirty copy)
          (mapcar #'copy-rectangle (surface-dirty surface)))
    copy))

(defun surface-cell (surface x y)
  (when (and (integerp x) (integerp y)
             (<= 0 x) (< x (surface-width surface))
             (<= 0 y) (< y (surface-height surface)))
    (aref (surface-cells surface) (%surface-index surface x y))))

(defun %surface-cell-equal-p (left right)
  (and (cell-p left) (cell-p right)
       (string= (cell-content left) (cell-content right))
       (style= (cell-style left) (cell-style right))
       (= (cell-span left) (cell-span right))
       (eql (cell-continuation-p left) (cell-continuation-p right))))

(defun surface-mark-dirty (surface rectangle)
  (let ((clipped (rectangle-intersection rectangle (%surface-bounds surface))))
    (unless (rectangle-empty-p clipped)
      (push clipped (surface-dirty surface))))
  surface)

(defun surface-set-clip (surface rectangle)
  (setf (surface-%clip surface)
        (rectangle-intersection (%clip-rectangle rectangle
                                                 (%surface-bounds surface))
                               (%surface-bounds surface)))
  surface)

(defun call-with-surface-clip (surface rectangle continuation)
  "Call CONTINUATION with SURFACE clipped to RECTANGLE.

The previous clip is restored even when CONTINUATION transfers control
through a non-local exit."
  (check-type continuation function)
  (let ((old-clip (surface-%clip surface)))
    (unwind-protect
         (progn
           (surface-set-clip surface rectangle)
           (funcall continuation))
      (surface-set-clip surface old-clip))))

(defmacro with-surface-clip ((surface rectangle) &body body)
  "Temporarily constrain drawing to RECTANGLE and restore the old clip.

The surface and rectangle expressions are each evaluated exactly once."
  (let ((surface-var (gensym "SURFACE-"))
        (rectangle-var (gensym "RECTANGLE-")))
    `(let* ((,surface-var ,surface)
            (,rectangle-var ,rectangle))
       (call-with-surface-clip
        ,surface-var ,rectangle-var
        (lambda () ,@body)))))

(defun %cell-anchor-x (surface x y)
  "Return the lead-cell column for the unit containing X/Y.

Continuation cells deliberately do not store a back-pointer.  Scanning left
keeps the cell representation small while making replacement deterministic."
  (loop while (and (plusp x)
                   (cell-continuation-p (surface-cell surface x y)))
        do (decf x)
        finally (return x)))

(defun %cell-unit-span (surface x y)
  (let ((cell (surface-cell surface x y)))
    (if (and cell (not (cell-continuation-p cell)))
        (max 1 (cell-span cell))
        1)))

(defun %clear-cell-unit-at (surface x y style)
  "Clear the complete cell unit containing X/Y and return its old area.

Wide cells are atomic for mutation.  This may clear a continuation just
outside a requested rectangle when its lead is inside; that is necessary to
avoid leaving an invalid dangling continuation in the surface."
  (when (and (<= 0 x) (< x (surface-width surface))
             (<= 0 y) (< y (surface-height surface)))
    (let* ((anchor-x (%cell-anchor-x surface x y))
           (span (%cell-unit-span surface anchor-x y))
           (end-x (min (surface-width surface) (+ anchor-x span)))
           (area (make-rectangle anchor-x y (- end-x anchor-x) 1)))
      (loop for column from anchor-x below end-x
            do (setf (aref (surface-cells surface)
                           (%surface-index surface column y))
                     (blank-cell style)))
      area)))

(defun %surface-span-visible-p (surface x y span)
  (and (plusp span)
       (loop for column from x below (+ x span)
             always (%surface-visible-p surface column y))))

(defun surface-put-cell (surface x y cell)
  (check-type cell cell)
  ;; Validate even when the target is clipped: accepting malformed cell
  ;; metadata outside the current clip would make the public mutation API
  ;; depend on rendering state and allow invalid cells to re-enter via a
  ;; later clip change or surface copy.
  (%validate-cell-invariant (cell-content cell)
                           (cell-span cell)
                           (cell-continuation-p cell))
  (when (%surface-visible-p surface x y)
    (let* ((stored (copy-cell cell))
           (span (if (cell-continuation-p stored)
                     1
                     (max 1 (cell-span stored)))))
      ;; A continuation is renderer metadata, not an independently drawable
      ;; glyph.  Replacing one clears the complete old unit, which preserves
      ;; the invariant that every continuation has a lead cell.
      (if (cell-continuation-p stored)
          (let ((old-area (%clear-cell-unit-at
                           surface x y (surface-default-style surface))))
            (when old-area
              (surface-mark-dirty surface old-area)))
          (when (%surface-span-visible-p surface x y span)
            (let ((old-area (%clear-cell-unit-at
                             surface x y (surface-default-style surface))))
              (when old-area
                (surface-mark-dirty surface old-area))
              (setf (aref (surface-cells surface) (%surface-index surface x y))
                    stored)
              (when (> span 1)
                (loop for offset from 1 below span
                      do (setf (aref (surface-cells surface)
                                     (%surface-index surface (+ x offset) y))
                                (make-cell "" :style (cell-style stored)
                                           :span 0 :continuation-p t))))
              (surface-mark-dirty surface (make-rectangle x y span 1)))))))
  surface)

(defun surface-clear (surface &optional rectangle style)
  (let ((area (rectangle-intersection
               (or rectangle (%surface-bounds surface))
               (surface-%clip surface)))
        (fill-style (or style (surface-default-style surface))))
    (loop for y from (rectangle-y area) below (rectangle-bottom area)
          do (loop for x from (rectangle-x area) below (rectangle-right area)
                   do (let ((cleared (%clear-cell-unit-at surface x y fill-style)))
                        (when cleared
                          (surface-mark-dirty surface cleared)))))
  surface))

(defun surface-fill (surface character &optional style)
  (surface-fill-rectangle surface (%surface-bounds surface) character style))

(defun surface-fill-rectangle (surface rectangle &optional (character #\Space)
                                         style)
  (let ((area (rectangle-intersection rectangle (surface-%clip surface)))
        (fill-style (or style (surface-default-style surface))))
    (loop for y from (rectangle-y area) below (rectangle-bottom area)
          do (loop for x from (rectangle-x area) below (rectangle-right area)
                   do (surface-put-cell surface x y
                                         (make-cell character :style fill-style)))))
  surface)

(defun %draw-unit (surface x y unit style)
  (let ((width (text-unit-width unit)))
    (cond
      ((zerop width) nil)
      ((and (<= 0 x) (< x (surface-width surface))
            (<= 0 y) (< y (surface-height surface))
            (<= (+ x width) (surface-width surface))
            (rectangle-contains-point-p (surface-%clip surface) x y)
            (rectangle-contains-point-p
             (surface-%clip surface) (1- (+ x width)) y))
       (surface-put-cell surface x y (make-cell unit :style style :span width))
       t)
      (t nil))))

(defun %surface-draw-text-units (surface x y text style origin-x limit tab-width)
  (loop for unit in (text-units text)
        do (cond
             ((string= unit (string #\Newline))
              (setf x origin-x)
              (incf y))
             ((string= unit (string #\Tab))
              (let ((spaces (- tab-width (mod (- x origin-x) tab-width))))
                (loop repeat spaces do
                  (when (or (null limit) (< x limit))
                    (%draw-unit surface x y " " style))
                  (incf x))))
             (t
              (let ((width (text-unit-width unit)))
                (when (or (null limit) (<= (+ x width) limit))
                  (%draw-unit surface x y unit style))
                (incf x width)))))
  (values x y))

(defun surface-draw-text (surface x y text &key style max-width (tab-width 8))
  "Draw TEXT in cell coordinates, clipping units and expanding tabs.

Newlines move to the next row.  A wide unit is omitted when only half of it
fits at an edge, so the result never leaves a dangling continuation cell."
  (let* ((draw-style (or style (surface-default-style surface)))
         (origin-x x)
         (limit (and max-width (+ x (max 0 max-width)))))
    (check-type text string)
    (check-type draw-style style)
    (unless (and (integerp tab-width) (plusp tab-width))
      (error 'invalid-range-error
             :context 'tab-width
             :datum tab-width
             :expected "a positive integer"))
    (%surface-draw-text-units surface x y text draw-style origin-x limit
                              tab-width))
  surface)

(defun surface-draw-styled-text (surface x y spans &key max-width (tab-width 8))
  "Draw a list of TEXT-SPANS as one logical text run.

Newlines and tabs keep their usual behavior across span boundaries, and
MAX-WIDTH is measured from the initial X coordinate for the whole run."
  (check-type spans list)
  (unless (and (integerp tab-width) (plusp tab-width))
    (error 'invalid-range-error
           :context 'tab-width
           :datum tab-width
           :expected "a positive integer"))
  (let* ((origin-x x)
         (limit (and max-width (+ x (max 0 max-width)))))
    (dolist (span spans surface)
      (check-type span text-span)
      (multiple-value-setq (x y)
        (%surface-draw-text-units surface x y (text-span-text span)
                                  (text-span-style span) origin-x limit
                                  tab-width)))))

(defun %border-glyphs (kind)
  (case kind
    (:double (list "╔" "╗" "╚" "╝" "═" "║"))
    (:rounded (list "╭" "╮" "╰" "╯" "─" "│"))
    (:ascii (list "+" "+" "+" "+" "-" "|"))
    (otherwise (list "┌" "┐" "└" "┘" "─" "│"))))

(defun surface-draw-border (surface rectangle &key (style (surface-default-style surface))
                                                  (kind :single))
  (let ((area (copy-rectangle rectangle)))
    (unless (rectangle-empty-p area)
      (destructuring-bind (top-left top-right bottom-left bottom-right horizontal vertical)
          (%border-glyphs kind)
        (let ((left (rectangle-x area))
              (right (1- (rectangle-right area)))
              (top (rectangle-y area))
              (bottom (1- (rectangle-bottom area))))
          (surface-draw-text surface left top top-left :style style)
          (surface-draw-text surface right top top-right :style style)
          (surface-draw-text surface left bottom bottom-left :style style)
          (surface-draw-text surface right bottom bottom-right :style style)
          (when (> right (1+ left))
            (loop for x from (1+ left) below right
                  do (surface-draw-text surface x top horizontal :style style)
                     (surface-draw-text surface x bottom horizontal :style style)))
          (when (> bottom (1+ top))
            (loop for y from (1+ top) below bottom
                  do (surface-draw-text surface left y vertical :style style)
                     (surface-draw-text surface right y vertical :style style)))))))
  surface)

(defun surface-blit (destination source &key (source-rectangle nil)
                                             (destination-point (make-point)))
  (let* ((source-area (rectangle-intersection
                       (or source-rectangle (%surface-bounds source))
                       (%surface-bounds source)))
         (dx (point-x destination-point))
         (dy (point-y destination-point)))
    (loop for sy from (rectangle-y source-area) below (rectangle-bottom source-area)
          for target-y = (+ dy (- sy (rectangle-y source-area)))
          do (loop for sx from (rectangle-x source-area) below (rectangle-right source-area)
                   for target-x = (+ dx (- sx (rectangle-x source-area)))
                    do (let ((cell (surface-cell source sx sy)))
                         (when (and cell
                                    (not (cell-continuation-p cell))
                                    (<= (+ sx (max 1 (cell-span cell)))
                                        (rectangle-right source-area)))
                           (surface-put-cell destination target-x target-y cell))))))
  destination)

(defstruct (cell-change (:constructor %make-cell-change (x y before after)))
  x y before after)

(defun surface-diff (current previous)
  "Return changed cells between two surfaces, in row-major order."
  (let ((changes '())
        (width (surface-width current))
        (height (surface-height current)))
    (dotimes (y height (nreverse changes))
      (dotimes (x width)
        (let ((after (surface-cell current x y))
              (before (and previous (surface-cell previous x y))))
          (unless (and before (%surface-cell-equal-p before after))
            (push (%make-cell-change x y (and before (copy-cell before))
                                     (and after (copy-cell after)))
                  changes)))))))

(defun surface-mark-clean (surface)
  (setf (surface-dirty surface) nil)
  surface)

(defun surface-dirty-regions (surface)
  (mapcar #'copy-rectangle (reverse (surface-dirty surface))))

(defun surface-string (surface)
  "Return a deterministic textual snapshot of the surface.

Continuation cells are omitted because their lead cell contains the complete
grapheme.  Exact cell positions remain available through SURFACE-CELL and
SURFACE-DIFF, while this projection stays readable for wide characters."
  (with-output-to-string (stream)
    (dotimes (y (surface-height surface))
      (dotimes (x (surface-width surface))
        (let ((cell (surface-cell surface x y)))
          (unless (cell-continuation-p cell)
            (write-string (cell-content cell) stream))))
      (unless (= y (1- (surface-height surface)))
        (terpri stream)))))
