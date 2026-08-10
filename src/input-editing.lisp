(in-package #:cl-tui-kit/widgets)

;;;; Input, viewport, modal, status, and scroll widgets --------------------

(defclass input-widget (widget)
  ((value :initarg :value :accessor input-widget-value :initform "")
   (cursor :initarg :cursor :accessor input-widget-cursor :initform 0)
   (scroll-offset :initarg :scroll-offset
                  :accessor input-widget-scroll-offset :initform 0)
   (placeholder :initarg :placeholder :accessor input-widget-placeholder
                :initform "")
   (selection-anchor :initarg :selection-anchor
                     :accessor input-widget-selection-anchor
                     :initform nil)
   (undo-stack :accessor %input-widget-undo-stack :initform nil)
   (redo-stack :accessor %input-widget-redo-stack :initform nil)
   (max-history :initarg :max-history :accessor input-widget-max-history
                :initform 100)))

(defun make-input-widget (&key (value "") placeholder id rectangle style theme
                                keymap (focusable-p t) (max-history 100)
                                semantic-role accessible-label
                                accessible-description accessible-help-text)
  (check-type value string)
  (unless (and (integerp max-history) (plusp max-history))
    (error "MAX-HISTORY must be a positive integer."))
  (make-instance 'input-widget :value value :cursor (length value)
                 :scroll-offset 0
                 :placeholder (or placeholder "") :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style)) :theme (or theme (default-theme))
                 :keymap keymap :focusable-p focusable-p
                 :max-history max-history :semantic-role semantic-role
                 :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defmethod widget-preferred-size ((widget input-widget))
  (make-size (max 1 (string-cell-width (input-widget-value widget))) 1))

(defmethod widget-accessibility-info ((widget input-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :textbox))
    (setf (getf info :label)
          (or (getf info :label) (input-widget-placeholder widget)))
    (setf (getf info :value) (input-widget-value widget))
    info))

(defmethod widget-accessibility-state ((widget input-widget))
  (list :cursor (input-widget-cursor widget)
        :selection-start (input-widget-selection-start widget)
        :selection-end (input-widget-selection-end widget)))

(defun %input-state (widget)
  (list (copy-seq (input-widget-value widget))
        (input-widget-cursor widget)
        (input-widget-selection-anchor widget)))

(defun %input-restore-state (widget state)
  (setf (input-widget-value widget) (first state)
        (input-widget-cursor widget) (second state)
        (input-widget-selection-anchor widget) (third state))
  widget)

(defun %input-limit-history (stack maximum)
  (if (> (length stack) maximum)
      (subseq stack 0 maximum)
      stack))

(defun %input-record-change (widget)
  (setf (%input-widget-undo-stack widget)
        (%input-limit-history
         (cons (%input-state widget) (%input-widget-undo-stack widget))
         (input-widget-max-history widget))
        (%input-widget-redo-stack widget) nil)
  widget)

(defun %input-selection-range (widget)
  (let ((anchor (input-widget-selection-anchor widget))
        (cursor (input-widget-cursor widget)))
    (when (and anchor (/= anchor cursor))
      (values (min anchor cursor) (max anchor cursor)))))

(defun %input-has-selection-p (widget)
  (multiple-value-bind (start end) (%input-selection-range widget)
    (declare (ignore end))
    (not (null start))))

(defun input-widget-selection-start (widget)
  (multiple-value-bind (start end) (%input-selection-range widget)
    (declare (ignore end))
    start))

(defun input-widget-selection-end (widget)
  (multiple-value-bind (start end) (%input-selection-range widget)
    (declare (ignore start))
    end))

(defun input-widget-selected-text (widget)
  (multiple-value-bind (start end) (%input-selection-range widget)
    (if start
        (subseq (input-widget-value widget) start end)
        "")))

(defun input-widget-clear-selection (widget)
  (setf (input-widget-selection-anchor widget) nil)
  widget)

(defun input-widget-undo (widget)
  (when (%input-widget-undo-stack widget)
    (let ((current (%input-state widget))
          (previous (pop (%input-widget-undo-stack widget))))
      (setf (%input-widget-redo-stack widget)
            (%input-limit-history
             (cons current (%input-widget-redo-stack widget))
             (input-widget-max-history widget)))
      (%input-restore-state widget previous)))
  widget)

(defun input-widget-redo (widget)
  (when (%input-widget-redo-stack widget)
    (let ((current (%input-state widget))
          (next (pop (%input-widget-redo-stack widget))))
      (setf (%input-widget-undo-stack widget)
            (%input-limit-history
             (cons current (%input-widget-undo-stack widget))
             (input-widget-max-history widget)))
      (%input-restore-state widget next)))
  widget)

(defun %input-boundaries (value)
  (let ((index 0)
        (boundaries (list 0)))
    (dolist (unit (text-units value) (nreverse boundaries))
      (incf index (length unit))
      (push index boundaries))))

(defun %input-previous-boundary (value cursor)
  (let ((previous 0))
    (dolist (boundary (%input-boundaries value) previous)
      (when (>= boundary cursor)
        (return previous))
      (setf previous boundary))))

(defun %input-next-boundary (value cursor)
  (dolist (boundary (%input-boundaries value) (length value))
    (when (> boundary cursor)
      (return boundary))))

(defun %input-cursor-column-at-index (value index)
  (string-cell-width (subseq value 0 index)))

(defun %input-cursor-column (widget)
  (string-cell-width (subseq (input-widget-value widget)
                             0 (input-widget-cursor widget))))

(defun %input-index-at-cell-offset (value offset)
  (labels ((walk (units index column)
             (if units
                 (let* ((unit (car units))
                        (width (text-unit-width unit)))
                   (if (> (+ column width) offset)
                       index
                       (walk (cdr units)
                             (+ index (length unit))
                             (+ column width))))
                 index)))
    (walk (text-units value) 0 0)))

(defun %input-unit-word-p (value start end)
  (and (< start end)
       (let ((character (char value start)))
         (or (alphanumericp character)
             (char= character #\_)))))

(defun %input-word-left (value cursor)
  (let ((index cursor))
    (loop while (plusp index)
          do (let ((previous (%input-previous-boundary value index)))
               (if (%input-unit-word-p value previous index)
                   (return)
                   (setf index previous))))
    (loop while (plusp index)
          do (let ((previous (%input-previous-boundary value index)))
               (if (%input-unit-word-p value previous index)
                   (setf index previous)
                   (return))))
    index))

(defun %input-word-right (value cursor)
  (let ((index cursor)
        (length (length value)))
    (loop while (< index length)
          do (let ((next (%input-next-boundary value index)))
               (if (%input-unit-word-p value index next)
                   (return)
                   (setf index next))))
    (loop while (< index length)
          do (let ((next (%input-next-boundary value index)))
               (if (%input-unit-word-p value index next)
                   (setf index next)
                   (return))))
    index))

(defun %input-replace-range (widget start end text)
  (let ((value (input-widget-value widget)))
    (setf (input-widget-value widget)
          (concatenate 'string (subseq value 0 start) text (subseq value end))
          (input-widget-cursor widget) (+ start (length text))
          (input-widget-selection-anchor widget) nil))
  widget)

(defun %input-delete-range (widget start end)
  (when (< start end)
    (%input-record-change widget)
    (%input-replace-range widget start end "")
    t))

(defun %input-delete-selection (widget)
  (multiple-value-bind (start end) (%input-selection-range widget)
    (when start
      (%input-delete-range widget start end))))

(defun %input-ensure-cursor-visible (widget)
  (let* ((area (widget-rectangle widget))
         (width (max 0 (rectangle-width area)))
         (column (%input-cursor-column widget))
         (offset (max 0 (input-widget-scroll-offset widget))))
    (setf (input-widget-scroll-offset widget)
          (cond
            ((zerop width) 0)
            ((< column offset) column)
            ((>= column (+ offset width))
             (max 0 (- (1+ column) width)))
            (t offset)))))

(defmethod widget-cursor-position ((widget input-widget))
  (%input-ensure-cursor-visible widget)
  (let* ((area (widget-rectangle widget))
         (width (rectangle-width area))
         (x (+ (rectangle-x area)
               (- (%input-cursor-column widget)
                  (input-widget-scroll-offset widget)))))
    (when (and (plusp width)
               (>= x (rectangle-x area))
               (< x (rectangle-right area)))
      (make-point x (rectangle-y area)))))

(defun %input-cursor-text (widget)
  (let ((cursor (input-widget-cursor widget))
        (value (input-widget-value widget)))
    (if (< cursor (length value))
        (subseq value cursor (%input-next-boundary value cursor))
        " ")))

(defun %input-insert (widget text)
  (unless (zerop (length text))
    (multiple-value-bind (selection-start selection-end)
        (%input-selection-range widget)
      (let ((start (or selection-start (input-widget-cursor widget)))
            (end (or selection-end (input-widget-cursor widget))))
        (%input-record-change widget)
        (%input-replace-range widget start end text))))
  widget)

(defun %input-render-selection (widget surface area value offset style)
  (multiple-value-bind (selection-start selection-end)
      (%input-selection-range widget)
    (when selection-start
      (let* ((visible-start (%input-index-at-cell-offset value offset))
             (start (max selection-start visible-start))
             (start-column (%input-cursor-column-at-index value start))
             (x (+ (rectangle-x area) (- start-column offset)))
             (max-width (- (rectangle-right area) (max x (rectangle-x area)))))
        (when (and (< start selection-end) (plusp max-width))
          (surface-draw-text surface (max x (rectangle-x area))
                              (rectangle-y area)
                              (subseq value start selection-end)
                              :style (merge-styles style (make-style :reverse t))
                              :max-width max-width))))))

(defun %input-move-cursor (widget position &key shift)
  (let* ((value (input-widget-value widget))
         (old (input-widget-cursor widget))
         (new (max 0 (min (length value) position))))
    (if shift
        (unless (input-widget-selection-anchor widget)
          (setf (input-widget-selection-anchor widget) old))
        (setf (input-widget-selection-anchor widget) nil))
    (setf (input-widget-cursor widget) new)
    widget))

(defun %input-key-named-p (key name character)
  (or (equalp key name)
      (and (characterp key) (char-equal key character))))

(defun %input-modifier-p (event modifier)
  (member modifier (key-event-modifiers event) :test #'eq))

(defmethod widget-render ((widget input-widget) surface)
  (let* ((area (widget-rectangle widget))
         (value (input-widget-value widget))
         (width (max 0 (rectangle-width area))))
    (%input-ensure-cursor-visible widget)
    (surface-fill-rectangle surface area #\Space
                             (%widget-role-style widget :foreground))
    (when (plusp width)
      (let* ((empty-p (zerop (length value)))
             (source (if empty-p (input-widget-placeholder widget) value))
             (offset (if empty-p
                         0
                         (input-widget-scroll-offset widget)))
             (start (if empty-p
                        0
                        (%input-index-at-cell-offset value offset)))
             (display (clip-text (subseq source start) width))
             (display-style (%widget-role-style widget
                                                 (if empty-p :muted :foreground)))
             (cursor-column (%input-cursor-column widget))
             (cursor-x (+ (rectangle-x area)
                          (- cursor-column (input-widget-scroll-offset widget))))
             (cursor-style (merge-styles display-style
                                         (make-style :reverse t))))
        (surface-draw-text surface (rectangle-x area) (rectangle-y area) display
                            :style display-style :max-width width)
        (%input-render-selection widget surface area value
                                 (input-widget-scroll-offset widget)
                                 display-style)
        (when (and (>= cursor-x (rectangle-x area))
                   (< cursor-x (rectangle-right area)))
          (surface-draw-text surface cursor-x (rectangle-y area)
                              (%input-cursor-text widget)
                              :style cursor-style
                              :max-width (- (rectangle-right area) cursor-x))))))
  widget)

(defmethod widget-handle-event ((widget input-widget) event)
  (cond
    ((typep event 'text-input-event)
     (%input-insert widget (text-input-event-text event))
     nil)
    ((typep event 'paste-event)
     (%input-insert widget (paste-event-text event))
     nil)
    ((typep event 'key-event)
     (let* ((key (key-event-key event))
            (cursor (input-widget-cursor widget))
            (value (input-widget-value widget))
            (shift-p (%input-modifier-p event :shift))
            (control-p (%input-modifier-p event :ctrl))
            (alt-p (%input-modifier-p event :alt))
            (word-p (or control-p alt-p)))
       (cond
         ((equalp key :left)
          (if (and (not shift-p) (%input-has-selection-p widget))
              (multiple-value-bind (start end) (%input-selection-range widget)
                (declare (ignore end))
                (%input-move-cursor widget start))
              (%input-move-cursor
               widget (if word-p
                          (%input-word-left value cursor)
                          (%input-previous-boundary value cursor))
               :shift shift-p))
          (move-action :left 1 widget))
         ((equalp key :right)
          (if (and (not shift-p) (%input-has-selection-p widget))
              (multiple-value-bind (start end) (%input-selection-range widget)
                (declare (ignore start))
                (%input-move-cursor widget end))
              (%input-move-cursor
               widget (if word-p
                          (%input-word-right value cursor)
                          (%input-next-boundary value cursor))
               :shift shift-p))
          (move-action :right 1 widget))
         ((or (equalp key :home)
              (and control-p (%input-key-named-p key :a #\a)))
          (%input-move-cursor widget 0 :shift shift-p)
          (move-action :home 1 widget))
         ((or (equalp key :end)
              (and control-p (%input-key-named-p key :e #\e)))
          (%input-move-cursor widget (length value) :shift shift-p)
          (move-action :end 1 widget))
         ((and control-p (%input-key-named-p key :z #\z)
               (not shift-p))
          (input-widget-undo widget)
          nil)
         ((and (or control-p alt-p) (%input-key-named-p key :z #\z)
               shift-p)
          (input-widget-redo widget)
          nil)
         ((and control-p (%input-key-named-p key :y #\y))
          (input-widget-redo widget)
          nil)
         ((equalp key :backspace)
          (unless (%input-delete-selection widget)
            (let ((start (if word-p
                             (%input-word-left value cursor)
                             (%input-previous-boundary value cursor))))
              (%input-delete-range widget start cursor)))
          nil)
         ((equalp key :delete)
          (unless (%input-delete-selection widget)
            (let ((end (if word-p
                           (%input-word-right value cursor)
                           (%input-next-boundary value cursor))))
              (%input-delete-range widget cursor end)))
          nil)
         ((member key '(:enter :return) :test #'equalp)
          (submit-action (input-widget-value widget) widget))
         ((equalp key :escape)
          (cancel-action nil widget)))))))
