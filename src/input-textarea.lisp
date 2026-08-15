(in-package #:cl-tui-kit/widgets)

(defclass textarea-widget (input-widget)
  ((preferred-rows :initarg :preferred-rows
                   :accessor textarea-widget-preferred-rows
                   :initform 4
                   :type integer)
   (soft-wrap-p :initarg :soft-wrap-p
                :accessor textarea-widget-soft-wrap-p
                :initform t
                :type boolean)
   (submit-on-enter-p :initarg :submit-on-enter-p
                      :accessor textarea-widget-submit-on-enter-p
                      :initform nil
                      :type boolean)
   (line-scroll-offset :accessor %textarea-widget-line-scroll-offset
                       :initform 0
                       :type integer)))

(defun textarea-widget-line-scroll-offset (widget)
  "Return WIDGET's current line-scroll offset.

This value is internal scroll state that WIDGET recomputes on every render
and cursor-position query to keep the cursor visible; it has no direct
setter."
  (%textarea-widget-line-scroll-offset widget))

(defun make-textarea-widget (&key (value "") placeholder id
                                  (preferred-rows 4) (soft-wrap-p t)
                                  (submit-on-enter-p nil) rectangle style theme
                                  keymap (focusable-p t) (enabled-p t)
                                  (max-history 100) semantic-role
                                  accessible-label accessible-description
                                  accessible-help-text)
  "Create a multi-line text editing widget.

The text-editing history and selection behavior are inherited from
INPUT-WIDGET.  PREFERRED-ROWS controls the default height when no rectangle
is supplied, while SOFT-WRAP-P controls visual line wrapping."
  (check-type value string)
  (check-type preferred-rows (integer 1))
  (check-type soft-wrap-p boolean)
  (check-type submit-on-enter-p boolean)
  (check-type max-history (integer 1))
  (make-instance 'textarea-widget
                 :value value
                 :cursor (length value)
                 :placeholder (or placeholder "")
                 :id id
                 :max-history max-history
                 :preferred-rows preferred-rows
                 :soft-wrap-p soft-wrap-p
                 :submit-on-enter-p submit-on-enter-p
                 :rectangle (or rectangle
                                (make-rectangle 0 0 20 preferred-rows))
                 :style (or style (make-style))
                 :theme (or theme (default-theme))
                 :keymap keymap
                 :enabled-p enabled-p
                 :focusable-p focusable-p
                 :semantic-role (or semantic-role :textbox)
                 :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defun %textarea-line-ranges (value)
  (let ((start 0)
        (length (length value))
        (ranges nil))
    (loop for newline = (position #\Newline value :start start)
          do (if newline
                 (progn
                   (push (cons start newline) ranges)
                   (setf start (1+ newline)))
                 (progn
                   (push (cons start length) ranges)
                   (return))))
    (nreverse ranges)))

(defun %textarea-segments (widget)
  "Return visual rows as absolute VALUE index ranges.

Newline characters are separators and are not part of a segment.  A segment
is a cons of its inclusive start and exclusive end index."
  (let* ((value (input-widget-value widget))
         (line-width (max 1 (rectangle-width (%widget-rectangle widget)))))
    (loop for range in (%textarea-line-ranges value)
          append
          (let ((start (car range))
                (end (cdr range)))
            (if (or (not (textarea-widget-soft-wrap-p widget))
                    (= start end))
                (list (cons start end))
                (let ((segment-start start)
                      (index start)
                      (column 0)
                      (segments nil))
                  (dolist (unit (text-units (subseq value start end)))
                    (let ((unit-width (text-unit-width unit))
                          (next-index (+ index (length unit))))
                      (when (and (> index segment-start)
                                 (> (+ column unit-width) line-width))
                        (push (cons segment-start index) segments)
                        (setf segment-start index
                              column 0))
                      (incf column unit-width)
                      (setf index next-index)))
                  (push (cons segment-start index) segments)
                  (nreverse segments)))))))

(defun %textarea-segment-at-cursor (segments cursor)
  (or (find-if (lambda (segment)
                 (and (>= cursor (car segment))
                      (< cursor (cdr segment))))
               segments)
      ;; At a wrapped boundary, the cursor belongs to the following row.
      (find-if (lambda (segment) (= cursor (car segment))) segments)
      ;; A cursor immediately before a newline belongs at the end of the
      ;; preceding row, which is how terminals display it.
      (find-if (lambda (segment)
                 (and (= cursor (cdr segment))
                      (/= (car segment) (cdr segment))))
               segments)
      (car (last segments))))

(defun %textarea-segment-index (segments segment)
  (loop for candidate in segments
        for index from 0
        when (eq candidate segment)
          do (return index)
        finally (return 0)))

(defun %textarea-cursor-column (widget segment)
  (let* ((cursor (input-widget-cursor widget))
         (start (car segment))
         (end (cdr segment))
         (index (min end (max start cursor))))
    (string-cell-width
     (subseq (input-widget-value widget) start index))))

(defun %textarea-index-at-column (widget segment target-column)
  (let ((index (car segment))
        (column 0)
        (value (input-widget-value widget)))
    (dolist (unit (text-units (subseq value (car segment) (cdr segment)))
             index)
      (when (>= column target-column)
        (return index))
      (incf column (text-unit-width unit))
      (incf index (length unit)))))

(defun %textarea-selection-active-p (start end unit-start unit-end)
  (and start end (< unit-start end) (> unit-end start)))

(defun %textarea-ensure-cursor-visible (widget segments)
  (let* ((cursor (input-widget-cursor widget))
         (segment (%textarea-segment-at-cursor segments cursor))
         (index (%textarea-segment-index segments segment))
         (height (rectangle-height (%widget-rectangle widget)))
         (offset (%textarea-widget-line-scroll-offset widget)))
    (when (plusp height)
      (setf offset
            (max 0
                 (min index
                      (max 0 (- (1+ index) height)))))
      (setf (%textarea-widget-line-scroll-offset widget) offset))
    index))

(defmethod widget-preferred-size ((widget textarea-widget))
  (let ((width 1))
    (dolist (range (%textarea-line-ranges (input-widget-value widget)))
      (setf width
            (max width
                 (string-cell-width
                  (subseq (input-widget-value widget)
                          (car range) (cdr range))))))
    (make-size width (textarea-widget-preferred-rows widget))))

(defmethod widget-render ((widget textarea-widget) surface)
  (let* ((rectangle (%widget-rectangle widget))
         (x (rectangle-x rectangle))
         (y (rectangle-y rectangle))
         (right (+ x (rectangle-width rectangle)))
         (bottom (+ y (rectangle-height rectangle)))
         (segments (%textarea-segments widget))
         (value (input-widget-value widget))
         (style (%widget-role-style widget :foreground))
         (row-offset (%textarea-widget-line-scroll-offset widget)))
    (%textarea-ensure-cursor-visible widget segments)
    (surface-fill-rectangle surface rectangle #\Space style)
    (multiple-value-bind (selection-start selection-end)
        (%input-selection-range widget)
      (loop for segment in segments
            for row-index from 0
            for row = (+ y (- row-index row-offset))
            when (and (>= row y) (< row bottom))
              do (let ((index (car segment))
                       (column x))
                   (dolist (unit (text-units
                                  (subseq value (car segment) (cdr segment))))
                     (let* ((unit-end (+ index (length unit)))
                            (unit-width (text-unit-width unit))
                            (unit-style
                              (if (%textarea-selection-active-p
                                   selection-start selection-end index unit-end)
                                  (%widget-role-style widget :selection)
                                  style)))
                       (when (< column right)
                         (surface-draw-text
                          surface column row unit
                          :style unit-style
                          :max-width (max 0 (- right column))))
                       (incf column unit-width)
                       (setf index unit-end))))))
    (let* ((cursor (input-widget-cursor widget))
           (segment (%textarea-segment-at-cursor segments cursor))
           (row-index (%textarea-segment-index segments segment))
           (row (+ y (- row-index (%textarea-widget-line-scroll-offset widget))))
           (cursor-column (min (max 0 (1- (max 1 (rectangle-width rectangle))))
                               (%textarea-cursor-column widget segment))))
      (when (and (>= row y) (< row bottom) (< x right))
        ;; Draw a reverse blank at the insertion point.  The terminal cursor
        ;; itself is positioned separately through WIDGET-CURSOR-POSITION.
        (surface-draw-text surface (+ x cursor-column) row " "
                           :style (%widget-role-style widget :cursor)
                           :max-width 1)))
    surface))

(defmethod widget-cursor-position ((widget textarea-widget))
  (let* ((rectangle (%widget-rectangle widget))
         (segments (%textarea-segments widget))
         (segment (%textarea-segment-at-cursor
                   segments (input-widget-cursor widget)))
          (row-index (%textarea-segment-index segments segment))
         (row (- row-index (%textarea-widget-line-scroll-offset widget)))
         (height (rectangle-height rectangle))
         (width (rectangle-width rectangle)))
    (when (and (plusp height) (plusp width) (>= row 0) (< row height))
      (make-point
       (+ (rectangle-x rectangle)
          (min (1- width) (%textarea-cursor-column widget segment)))
       (+ (rectangle-y rectangle) row)))))

(defun %textarea-shift-p (event)
  (member :shift (key-event-modifiers event)))

(defun %textarea-move-to-segment (widget segment end-p shift-p)
  (%input-move-cursor widget (if end-p (cdr segment) (car segment))
                      :shift shift-p)
  (move-action (if end-p :end :home) nil widget))

(defun %textarea-move-line (widget delta shift-p)
  (let* ((segments (%textarea-segments widget))
         (current (%textarea-segment-at-cursor
                   segments (input-widget-cursor widget)))
         (current-index (%textarea-segment-index segments current))
         (target-index (and current-index (+ current-index delta))))
    (when (and target-index (>= target-index 0)
               (< target-index (length segments)))
      (let* ((target (nth target-index segments))
             (column (%textarea-cursor-column widget current)))
        (%input-move-cursor widget
                            (%textarea-index-at-column widget target column)
                            :shift shift-p)
        (move-action (if (plusp delta) :down :up) 1 widget)))))

(defmethod widget-handle-event ((widget textarea-widget) event)
  (cond
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:up :down :page-up :page-down)))
     (%textarea-move-line
      widget
      (case (key-event-key event)
        (:up -1)
        (:down 1)
        (:page-up (- (max 1 (rectangle-height (%widget-rectangle widget)))))
        (:page-down (max 1 (rectangle-height (%widget-rectangle widget)))))
      (%textarea-shift-p event)))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:home :end))
          (not (member :ctrl (key-event-modifiers event))))
     (let* ((segments (%textarea-segments widget))
            (segment (%textarea-segment-at-cursor
                      segments (input-widget-cursor widget))))
       (%textarea-move-to-segment
        widget segment (eq (key-event-key event) :end)
        (%textarea-shift-p event))))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:enter :return)))
     (if (textarea-widget-submit-on-enter-p widget)
         (submit-action (input-widget-value widget) widget)
         (progn
           (%input-insert widget (string #\Newline))
           nil)))
    (t
     (call-next-method))))
