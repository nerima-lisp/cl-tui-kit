(in-package #:cl-tui-kit/widgets)

(defclass form-widget (widget)
  ((fields :initarg :fields :accessor form-widget-fields :initform nil)
   (validator :initarg :validator :accessor form-widget-validator
              :initform nil)
   (errors :accessor form-widget-errors :initform nil)
   (submit-action :initarg :submit-action
                  :accessor %form-widget-submit-action
                  :initform nil)))

(defun make-form-widget (fields &key validator submit-action id rectangle style
                                  theme keymap (focusable-p nil)
                                  semantic-role accessible-label
                                  accessible-description accessible-help-text)
  "Create a vertical form containing the widget FIELDS.

VALIDATOR is called with an alist of field values and the form.  It should
return NIL or T for a valid form, or an error object/list for an invalid one.
SUBMIT-ACTION is called with the same values and form after successful
validation; returning an ACTION preserves it, while any other non-NIL value
becomes the payload of a submit action."
  (check-type fields list)
  (dolist (field fields)
    (check-type field widget))
  (when (and validator (not (functionp validator)))
    (error "FORM validator must be a function or NIL."))
  (when (and submit-action (not (functionp submit-action)))
    (error "FORM submit action must be a function or NIL."))
  (make-instance 'form-widget
                 :fields (copy-list fields)
                 :validator validator
                 :submit-action submit-action
                 :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme))
                 :keymap keymap
                 :focusable-p focusable-p
                 :semantic-role (or semantic-role :form)
                 :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text
                 :children (copy-list fields)))

(defun %form-field-value (field)
  (cond
    ((typep field 'input-widget)
     (input-widget-value field))
    ((typep field 'checkbox-widget)
     (checkbox-widget-checked-p field))
    (t
     (getf (widget-accessibility-info field) :value))))

(defun form-widget-values (form)
  "Return FORM values as an alist keyed by widget IDs or field positions."
  (check-type form form-widget)
  (loop for field in (form-widget-fields form)
        for index from 0
        collect (cons (or (widget-id field) index)
                      (%form-field-value field))))

(defun form-widget-validate (form)
  "Validate FORM and return true when no errors remain."
  (check-type form form-widget)
  (let ((validator (form-widget-validator form)))
    (setf (form-widget-errors form)
          (when validator
            (let ((result (funcall validator (form-widget-values form)
                                   form)))
              (cond
                ((or (null result) (eq result t)) nil)
                ((listp result) (copy-list result))
                (t (list result))))))
    (null (form-widget-errors form))))

(defun form-widget-submit (form)
  "Validate FORM and return a submit or validation-error action."
  (check-type form form-widget)
  (unless (form-widget-validate form)
    (return-from form-widget-submit
      (custom-action :validation-error (form-widget-errors form) form)))
  (let* ((values (form-widget-values form))
         (callback (%form-widget-submit-action form)))
    (if callback
        (let ((result (funcall callback values form)))
          (cond
            ((typep result 'action) result)
            (result (submit-action result form))
            (t (submit-action values form))))
        (submit-action values form))))

(defmethod widget-accessibility-info ((widget form-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :form))
    (setf (getf info :values) (form-widget-values widget)
          (getf info :errors) (copy-list (form-widget-errors widget)))
    info))

(defmethod widget-preferred-size ((widget form-widget))
  (let* ((fields (form-widget-fields widget))
         (errors (form-widget-errors widget))
         (field-width (loop for field in fields
                            maximize (size-width (widget-preferred-size field))))
         (error-width (loop for error in errors
                            maximize (string-cell-width (%text error))))
         (field-height (loop for field in fields
                             sum (max 1
                                      (size-height
                                       (widget-preferred-size field))))))
    (make-size (max 1 (or field-width 0) (or error-width 0))
               (+ (or field-height 0) (length errors)))))

(defmethod widget-layout ((widget form-widget) rectangle)
  (setf (widget-rectangle widget) (copy-rectangle rectangle))
  (let ((area (widget-rectangle widget))
        (y (rectangle-y rectangle))
        (remaining (rectangle-height rectangle)))
    (dolist (field (form-widget-fields widget))
      (let* ((preferred (widget-preferred-size field))
             (height (min remaining (max 1 (size-height preferred)))))
        (widget-layout
         field
         (make-rectangle (rectangle-x area) y (rectangle-width area)
                         (max 0 height)))
        (incf y height)
        (decf remaining height))))
  widget)

(defmethod widget-render ((widget form-widget) surface)
  (dolist (field (form-widget-fields widget))
    (widget-render field surface))
  (let* ((area (widget-rectangle widget))
         (last-bottom (loop for field in (form-widget-fields widget)
                            maximize (rectangle-bottom
                                      (widget-rectangle field))))
         (y (max (rectangle-y area) (or last-bottom (rectangle-y area))))
         (style (%widget-role-style widget :error)))
    (loop for error in (form-widget-errors widget)
          do (surface-draw-text surface (rectangle-x area) y (%text error)
                                :style style
                                :max-width (rectangle-width area))
             (incf y)))
  widget)

(defmethod widget-handle-event ((widget form-widget) event)
  (cond
    ((typep event 'custom-event)
     (case (custom-event-name event)
       (:validate (form-widget-validate widget) nil)
       (:submit (form-widget-submit widget))))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:enter :return) :test #'equalp))
     (form-widget-submit widget))
    ((and (typep event 'key-event)
          (equalp (key-event-key event) :escape))
     (cancel-action nil widget))))

(defclass viewport-widget (widget)
  ((child :initarg :child :accessor %viewport-widget-child :initform nil)
   (viewport :initarg :viewport :accessor viewport-widget-viewport)
   (content-width :initarg :content-width :initform nil)
   (content-height :initarg :content-height :initform nil)))

(defun make-viewport-widget (child &key id rectangle style theme keymap viewport
                                       content-width content-height focusable-p)
  (let* ((area (or rectangle (make-rectangle)))
         (view (or viewport (make-viewport :bounds area)))
         (widget (make-instance 'viewport-widget :child child :id id
                                :rectangle area
                                :style (or style (make-style))
                                :theme (or theme (default-theme))
                                :keymap keymap
                                :viewport view
                                :content-width content-width
                                :content-height content-height
                                :focusable-p focusable-p
                                :children (and child (list child)))))
    ;; Keep the viewport useful before the first layout/render pass.  Layout
    ;; still remains authoritative when the widget is attached to a tree.
    (setf (viewport-bounds view) (copy-rectangle area))
    (when content-width
      (setf (viewport-content-width view) content-width))
    (when content-height
      (setf (viewport-content-height view) content-height))
    widget))

(defmethod widget-layout ((widget viewport-widget) rectangle)
  (call-next-method)
  (let ((viewport (viewport-widget-viewport widget)))
    (setf (viewport-bounds viewport) (copy-rectangle rectangle)))
  widget)

(defmethod widget-render ((widget viewport-widget) surface)
  (let* ((child (%viewport-widget-child widget))
         (viewport (viewport-widget-viewport widget))
         (area (widget-rectangle widget))
         (preferred (and child (widget-preferred-size child)))
         (content-width (or (slot-value widget 'content-width)
                            (and preferred (size-width preferred))
                            (rectangle-width area)))
         (content-height (or (slot-value widget 'content-height)
                             (and preferred (size-height preferred))
                             (rectangle-height area))))
    (setf (viewport-content-width viewport) content-width
          (viewport-content-height viewport) content-height)
    (with-surface-clip
        (surface (rectangle-intersection (surface-clip surface) area))
      (when child
        (render-widget child surface
                       (rectangle-offset area
                                         (- (viewport-offset-x viewport))
                                         (- (viewport-offset-y viewport))))))
    widget))

(defmethod widget-handle-event ((widget viewport-widget) event)
  (when (typep event 'key-event)
    (let ((key (key-event-key event)))
      (cond
        ((equalp key :up)
         (viewport-scroll-by (viewport-widget-viewport widget) 0 -1)
         (move-action :up 1 widget))
        ((equalp key :down)
         (viewport-scroll-by (viewport-widget-viewport widget) 0 1)
         (move-action :down 1 widget))
        ((equalp key :left)
         (viewport-scroll-by (viewport-widget-viewport widget) -1 0)
         (move-action :left 1 widget))
        ((equalp key :right)
         (viewport-scroll-by (viewport-widget-viewport widget) 1 0)
         (move-action :right 1 widget))))))

(defclass modal-widget (widget)
  ((child :initarg :child :accessor %modal-widget-child :initform nil)
   (open-p :initarg :open-p :accessor modal-widget-open-p :initform nil)
   (dialog-rectangle :accessor %modal-dialog-rectangle
                     :initform (make-rectangle))
   (result :initarg :result :accessor modal-widget-result :initform nil)
   (close-reason :initarg :close-reason
                 :accessor modal-widget-close-reason
                 :initform nil)
   (buttons :initarg :buttons :accessor modal-widget-buttons :initform nil)
   (outside-close-p :initarg :outside-close-p
                    :accessor modal-widget-outside-close-p
                    :initform nil)))

(defmethod widget-active-p ((widget modal-widget))
  (modal-widget-open-p widget))

(defmethod widget-interactive-children ((widget modal-widget))
  (when (modal-widget-open-p widget)
    (call-next-method)))

(defmethod widget-capture-event-p ((widget modal-widget) event)
  (and (modal-widget-open-p widget)
       (or (and (typep event 'key-event)
                (equalp (key-event-key event) :escape))
           (and (typep event 'custom-event)
                (eq (custom-event-name event) :close)))))

(defun make-modal-widget (child &key id rectangle style theme keymap (open-p nil)
                                    focusable-p buttons (outside-close-p nil)
                                    semantic-role accessible-label
                                    accessible-description accessible-help-text)
  (check-type child (or null widget))
  (check-type buttons list)
  (dolist (button buttons)
    (check-type button widget))
  (make-instance 'modal-widget :child child :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style)) :theme (or theme (default-theme))
                 :keymap keymap :open-p open-p :focusable-p focusable-p
                 :buttons (copy-list buttons) :outside-close-p outside-close-p
                 :semantic-role (or semantic-role :dialog)
                 :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text
                 :children (append (and child (list child))
                                   (copy-list buttons))))

(defmethod widget-handle-child-action ((widget modal-widget) action)
  (if (modal-widget-open-p widget)
      (%modal-handle-child-action widget action)
      action))

(defun modal-widget-open (widget)
  (setf (modal-widget-open-p widget) t)
  (setf (modal-widget-result widget) nil
        (modal-widget-close-reason widget) nil)
  ;; A child can have changed its preferred size while the modal was closed
  ;; (for example, after a form validation error).  Synchronize hit-test
  ;; rectangles before callers query them or dispatch the first event.
  (%modal-layout widget)
  widget)

(defun modal-widget-close (widget &optional result (reason :programmatic))
  (setf (modal-widget-open-p widget) nil)
  (setf (modal-widget-result widget) result
        (modal-widget-close-reason widget) reason)
  widget)

(defun %modal-button-row-width (buttons)
  (if buttons
      (+ (loop for button in buttons
               sum (max 1 (size-width (widget-preferred-size button))))
         (1- (length buttons)))
      0))

(defun %modal-geometry (widget)
  (let* ((area (widget-rectangle widget))
         (child (%modal-widget-child widget))
         (buttons (modal-widget-buttons widget))
         (preferred (if child (widget-preferred-size child) (make-size 0 0)))
         (button-width (%modal-button-row-width buttons))
         (content-width (max 1 (size-width preferred) button-width))
         (content-height (+ (max 0 (size-height preferred))
                            (if buttons 1 0)
                            (if buttons 1 0)))
         (width (min (max 0 (rectangle-width area)) (+ 2 content-width)))
         (height (min (max 0 (rectangle-height area))
                      (max 1 (+ 2 content-height))))
         (dialog (make-rectangle
                  (+ (rectangle-x area)
                     (floor (- (rectangle-width area) width) 2))
                  (+ (rectangle-y area)
                     (floor (- (rectangle-height area) height) 2))
                  width height))
         (inner (rectangle-inset dialog (make-padding :all 1)))
         (button-height (if buttons 1 0))
         (child-height (max 0 (- (rectangle-height inner) button-height
                                 (if buttons 1 0))))
         (child-area (make-rectangle (rectangle-x inner) (rectangle-y inner)
                                     (rectangle-width inner) child-height))
         (button-area (and buttons
                           (make-rectangle
                            (rectangle-x inner)
                            (+ (rectangle-y inner) child-height
                               (if buttons 1 0))
                            (rectangle-width inner) button-height))))
    (values dialog child-area button-area)))

(defun %modal-layout (widget)
  (multiple-value-bind (dialog child-area button-area)
      (%modal-geometry widget)
    (setf (%modal-dialog-rectangle widget) dialog)
    (let ((child (%modal-widget-child widget)))
      (when child
        (widget-layout child child-area)))
    (when button-area
      (let ((x (rectangle-x button-area))
            (remaining (rectangle-width button-area)))
        (loop for button in (modal-widget-buttons widget)
              for index from 0
              do (let* ((preferred (widget-preferred-size button))
                        (width (min remaining
                                     (max 1 (size-width preferred)))))
                   (widget-layout
                    button
                    (make-rectangle x (rectangle-y button-area)
                                    (max 0 width)
                                    (rectangle-height button-area)))
                   (incf x width)
                   (decf remaining width)
                   (when (and (< index (1- (length (modal-widget-buttons widget))))
                              (plusp remaining))
                     (incf x)
                     (decf remaining))))))
    (values dialog child-area button-area)))

(defun %modal-handle-child-action (widget action)
  (when (and action
             (member (action-name action) '(:submit :cancel :close :activate)
                     :test #'eq))
    (modal-widget-close widget (action-payload action)
                        (if (eq (action-name action) :activate)
                            :button
                            (action-name action))))
  action)

(defmethod widget-preferred-size ((widget modal-widget))
  (let* ((child (%modal-widget-child widget))
         (child-size (if child (widget-preferred-size child) (make-size 0 0)))
         (button-width (%modal-button-row-width (modal-widget-buttons widget)))
         (content-width (max 1 (size-width child-size) button-width))
         (content-height (+ (size-height child-size)
                            (if (modal-widget-buttons widget) 2 0))))
    (make-size (+ 2 content-width) (max 1 (+ 2 content-height)))))

(defmethod widget-layout ((widget modal-widget) rectangle)
  (setf (widget-rectangle widget) (copy-rectangle rectangle))
  (%modal-layout widget)
  widget)

(defmethod widget-accessibility-info ((widget modal-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :dialog))
    (setf (getf info :focusable-p)
          (and (modal-widget-open-p widget)
               (widget-focusable-p widget)))
    (setf (getf info :state)
          (list :open-p (modal-widget-open-p widget)
                :result (modal-widget-result widget)
                :close-reason (modal-widget-close-reason widget)
                :button-count (length (modal-widget-buttons widget))))
    info))

(defmethod widget-render ((widget modal-widget) surface)
  (when (modal-widget-open-p widget)
    (multiple-value-bind (dialog ignored-child-area button-area)
        (%modal-layout widget)
      (declare (ignore ignored-child-area))
      (surface-fill-rectangle surface dialog #\Space
                               (%widget-role-style widget :background))
      (surface-draw-border surface dialog :style (%widget-role-style widget :border))
      (when (and button-area (plusp (rectangle-height button-area)))
        (loop for button in (modal-widget-buttons widget)
              do (widget-render button surface)))
      (when (%modal-widget-child widget)
        (widget-render (%modal-widget-child widget) surface)))))

(defmethod widget-handle-event ((widget modal-widget) event)
  (when (modal-widget-open-p widget)
    (%modal-layout widget)
    (cond
      ((and (typep event 'key-event)
            (equalp (key-event-key event) :escape))
       (modal-widget-close widget nil :escape)
       (close-action :escape widget))
      ((and (typep event 'custom-event)
            (eq (custom-event-name event) :close))
       (modal-widget-close widget (custom-event-payload event) :custom)
       (close-action (custom-event-payload event) widget))
      ((typep event 'mouse-event)
       (let ((dialog (%modal-dialog-rectangle widget)))
         (if (and (eq (mouse-event-kind event) :press)
                  (not (rectangle-contains-point-p
                        dialog (mouse-event-x event) (mouse-event-y event))))
             (when (modal-widget-outside-close-p widget)
               (modal-widget-close widget nil :outside)
               (close-action :outside widget))
             (let ((button
                     (find-if
                      (lambda (candidate)
                        (rectangle-contains-point-p
                         (widget-rectangle candidate)
                         (mouse-event-x event) (mouse-event-y event)))
                      (modal-widget-buttons widget))))
               (cond
                 (button
                  (unless (and *widget-event-target*
                               (not (eq *widget-event-target* widget)))
                    (%modal-handle-child-action
                     widget (handle-widget-event button event))))
                 ((and (%modal-widget-child widget)
                       (rectangle-contains-point-p
                        (multiple-value-bind (ignored child-area ignored-buttons)
                            (%modal-geometry widget)
                          (declare (ignore ignored ignored-buttons))
                          child-area)
                        (mouse-event-x event) (mouse-event-y event)))
                  (unless (and *widget-event-target*
                               (not (eq *widget-event-target* widget)))
                    (%modal-handle-child-action
                     widget
                     (handle-widget-event (%modal-widget-child widget) event)))))))))
      (t
       (%modal-handle-child-action
        widget
        (and (or (null *widget-event-target*)
                 (eq *widget-event-target* widget))
             (%modal-widget-child widget)
             (handle-widget-event (%modal-widget-child widget) event)))))))

(in-package #:cl-tui-kit/widgets)

;;; Text areas

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
   (line-scroll-offset :accessor textarea-widget-line-scroll-offset
                       :initform 0
                       :type integer)))

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
         (line-width (max 1 (rectangle-width (widget-rectangle widget)))))
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
         (index (or (position segment segments :test #'eq) 0))
         (height (rectangle-height (widget-rectangle widget)))
         (offset (textarea-widget-line-scroll-offset widget)))
    (when (> height 0)
      (setf offset
            (max 0
                 (min index
                      (max 0 (- (1+ index) height)))))
      (setf (textarea-widget-line-scroll-offset widget) offset))
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
  (let* ((rectangle (widget-rectangle widget))
         (x (rectangle-x rectangle))
         (y (rectangle-y rectangle))
         (right (+ x (rectangle-width rectangle)))
         (bottom (+ y (rectangle-height rectangle)))
         (segments (%textarea-segments widget))
         (value (input-widget-value widget))
         (style (%widget-role-style widget :foreground))
         (row-offset (textarea-widget-line-scroll-offset widget)))
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
           (row-index (or (position segment segments :test #'eq) 0))
           (row (+ y (- row-index (textarea-widget-line-scroll-offset widget))))
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
  (let* ((rectangle (widget-rectangle widget))
         (segments (%textarea-segments widget))
         (segment (%textarea-segment-at-cursor
                   segments (input-widget-cursor widget)))
         (row-index (or (position segment segments :test #'eq) 0))
         (row (- row-index (textarea-widget-line-scroll-offset widget)))
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
         (current-index (position current segments :test #'eq))
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
        (:page-up (- (max 1 (rectangle-height (widget-rectangle widget)))))
        (:page-down (max 1 (rectangle-height (widget-rectangle widget)))))
      (%textarea-shift-p event)))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:home :end))
          (not (member :control (key-event-modifiers event))))
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

;;; Radio groups

(defclass radio-widget (widget)
  ((options :initarg :options :accessor radio-widget-options :initform nil)
   (selected-index :initarg :selected-index
                   :accessor radio-widget-selected-index
                   :initform nil)
   (wrap-p :initarg :wrap-p :accessor radio-widget-wrap-p :initform t
           :type boolean)
   (action :initarg :action :accessor radio-widget-action :initform nil)))

(defun %control-option-label (option)
  (%text option))

(defun %control-selected-index (options selected-index)
  (when options
    (or selected-index 0)))

(defun %control-check-index (options index)
  (check-type index integer)
  (unless (and (>= index 0) (< index (length options)))
    (error "Option index ~D is outside the range of ~D options."
           index (length options)))
  index)

(defun make-radio-widget (options &key selected-index action wrap-p rectangle
                                    style theme keymap (focusable-p t)
                                    (enabled-p t) id semantic-role
                                    accessible-label accessible-description
                                    accessible-help-text)
  (check-type options list)
  (check-type wrap-p boolean)
  (let ((index (%control-selected-index options selected-index)))
    (when index (%control-check-index options index))
    (make-instance 'radio-widget
                   :options (copy-list options)
                   :selected-index index
                   :action action
                   :wrap-p wrap-p
                   :rectangle
                   (or rectangle
                       (make-rectangle
                        0 0 20 (max 1 (length options))))
                   :style (or style (make-style))
                   :theme (or theme (default-theme)) :keymap keymap
                   :enabled-p enabled-p
                   :focusable-p focusable-p
                   :id id
                   :semantic-role (or semantic-role :radiogroup)
                   :accessible-label accessible-label
                   :accessible-description accessible-description
                   :accessible-help-text accessible-help-text)))

(defun radio-widget-selected-option (widget)
  (let ((index (radio-widget-selected-index widget)))
    (and index (nth index (radio-widget-options widget)))))

(defun radio-widget-select (widget index)
  (when (radio-widget-options widget)
    (%control-check-index (radio-widget-options widget) index)
    (setf (radio-widget-selected-index widget) index)
    (%widget-action (radio-widget-action widget) :select
                    (radio-widget-selected-option widget) widget)))

(defmethod widget-preferred-size ((widget radio-widget))
  (make-size
   (max 1
        (loop for option in (radio-widget-options widget)
              maximize (+ 4 (string-cell-width (%control-option-label option)))))
   (max 1 (length (radio-widget-options widget)))))

(defmethod widget-render ((widget radio-widget) surface)
  (let* ((rectangle (widget-rectangle widget))
         (x (rectangle-x rectangle))
         (y (rectangle-y rectangle))
         (right (+ x (rectangle-width rectangle)))
         (bottom (+ y (rectangle-height rectangle)))
         (selected (radio-widget-selected-index widget)))
    (surface-fill-rectangle surface rectangle #\Space
                             (%widget-role-style widget :background))
    (loop for option in (radio-widget-options widget)
          for index from 0
          for row = (+ y index)
          while (< row bottom)
          do (let* ((chosen (and selected (= index selected)))
                    (prefix (if chosen "(●) " "(○) "))
                    (text (concatenate 'string prefix
                                       (%control-option-label option))))
               (surface-draw-text
                surface x row text
                :style (%widget-role-style
                        widget (if chosen :accent :foreground))
                :max-width (max 0 (- right x)))))
    surface))

(defmethod widget-accessibility-info ((widget radio-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :radiogroup))
    (setf (getf info :label)
          (or (getf info :label) "Radio group"))
    (setf (getf info :state)
          (list :selected-index (radio-widget-selected-index widget)
                :selected-option (radio-widget-selected-option widget)
                :options (mapcar #'%control-option-label
                                 (radio-widget-options widget))))
    info))

(defun %radio-move (widget delta)
  (let ((options (radio-widget-options widget)))
    (when options
      (let* ((count (length options))
             (current (or (radio-widget-selected-index widget) 0))
             (next (+ current delta)))
        (setf next
              (if (radio-widget-wrap-p widget)
                  (mod next count)
                  (max 0 (min (1- count) next))))
        (radio-widget-select widget next)))))

(defmethod widget-handle-event ((widget radio-widget) event)
  (cond
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:up :left)))
     (%radio-move widget -1))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:down :right)))
     (%radio-move widget 1))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:space :enter :return)))
     (radio-widget-select
      widget (or (radio-widget-selected-index widget) 0)))
    ((and (typep event 'mouse-event)
          (eq (mouse-event-kind event) :press)
          (rectangle-contains-point-p
           (widget-rectangle widget) (mouse-event-x event)
           (mouse-event-y event)))
     (let ((index (- (mouse-event-y event)
                     (rectangle-y (widget-rectangle widget)))))
       (when (and (>= index 0) (< index (length (radio-widget-options widget))))
         (radio-widget-select widget index))))))

;;; Select / combobox

(defclass select-widget (widget)
  ((options :initarg :options :accessor select-widget-options :initform nil)
   (selected-index :initarg :selected-index
                   :accessor select-widget-selected-index
                   :initform nil)
   (open-p :initarg :open-p :accessor select-widget-open-p :initform nil
           :type boolean)
   (visible-rows :initarg :visible-rows :accessor select-widget-visible-rows
                 :initform 5 :type integer)
   (action :initarg :action :accessor select-widget-action :initform nil)))

(defun make-select-widget (options &key selected-index (open-p nil)
                                     (visible-rows 5) action rectangle style theme
                                     keymap (focusable-p t) (enabled-p t) id
                                     semantic-role accessible-label
                                     accessible-description accessible-help-text)
  (check-type options list)
  (check-type open-p boolean)
  (check-type visible-rows (integer 1))
  (let ((index (%control-selected-index options selected-index)))
    (when index (%control-check-index options index))
    (make-instance 'select-widget
                   :options (copy-list options)
                   :selected-index index
                   :open-p open-p
                   :visible-rows visible-rows
                   :action action
                   :rectangle
                   (or rectangle
                       (make-rectangle
                        0 0 24 (if options (min visible-rows (length options)) 1)))
                   :style (or style (make-style))
                   :theme (or theme (default-theme)) :keymap keymap
                   :enabled-p enabled-p
                   :focusable-p focusable-p
                   :id id
                   :semantic-role (or semantic-role :combobox)
                   :accessible-label accessible-label
                   :accessible-description accessible-description
                   :accessible-help-text accessible-help-text)))

(defun select-widget-selected-option (widget)
  (let ((index (select-widget-selected-index widget)))
    (and index (nth index (select-widget-options widget)))))

(defun select-widget-select (widget index)
  (when (select-widget-options widget)
    (%control-check-index (select-widget-options widget) index)
    (setf (select-widget-selected-index widget) index)
    (%widget-action (select-widget-action widget) :select
                    (select-widget-selected-option widget) widget)))

(defun select-widget-toggle (widget)
  (setf (select-widget-open-p widget) (not (select-widget-open-p widget)))
  (%widget-action
   (select-widget-action widget)
   (if (select-widget-open-p widget) :open :close)
   (select-widget-selected-option widget) widget))

(defun %select-move (widget delta)
  (let ((options (select-widget-options widget)))
    (when options
      (let* ((count (length options))
             (current (or (select-widget-selected-index widget) 0))
             (next (max 0 (min (1- count) (+ current delta)))))
        (select-widget-select widget next)))))

(defun %select-visible-start (widget)
  (let* ((options (select-widget-options widget))
         (count (length options))
         (visible (min count (select-widget-visible-rows widget))))
    (if (plusp count)
        (max 0 (min (or (select-widget-selected-index widget) 0)
                    (- count visible)))
        0)))

(defmethod widget-preferred-size ((widget select-widget))
  (make-size
   (max 4
        (loop for option in (select-widget-options widget)
              maximize (+ 4 (string-cell-width (%control-option-label option)))))
   (if (select-widget-open-p widget)
       (max 1 (min (select-widget-visible-rows widget)
                   (length (select-widget-options widget))))
       1)))

(defmethod widget-render ((widget select-widget) surface)
  (let* ((rectangle (widget-rectangle widget))
         (x (rectangle-x rectangle))
         (y (rectangle-y rectangle))
         (right (+ x (rectangle-width rectangle)))
         (bottom (+ y (rectangle-height rectangle)))
         (options (select-widget-options widget))
         (selected (select-widget-selected-index widget)))
    (surface-fill-rectangle surface rectangle #\Space
                             (%widget-role-style widget :background))
    (if (not (select-widget-open-p widget))
        (surface-draw-text
         surface x y
         (format nil "[v] ~A"
                 (if selected
                     (%control-option-label
                      (nth selected options))
                     ""))
         :style (%widget-role-style widget :foreground)
         :max-width (max 0 (- right x)))
        (let* ((count (length options))
               (visible (min count (select-widget-visible-rows widget)))
               (start (%select-visible-start widget)))
          (loop for offset from 0 below visible
                for row = (+ y offset)
                while (< row bottom)
                do (let* ((index (+ start offset))
                          (chosen (and selected (= index selected)))
                          (prefix (if chosen "[>] " "[ ] "))
                          (text (concatenate
                                 'string prefix
                                 (%control-option-label (nth index options)))))
                     (surface-draw-text
                      surface x row text
                      :style (%widget-role-style
                              widget (if chosen :accent :foreground))
                      :max-width (max 0 (- right x)))))))
    surface))

(defmethod widget-accessibility-info ((widget select-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :combobox))
    (setf (getf info :label)
          (or (getf info :label) "Select"))
    (setf (getf info :state)
          (list :open-p (select-widget-open-p widget)
                :selected-index (select-widget-selected-index widget)
                :selected-option (select-widget-selected-option widget)
                :options (mapcar #'%control-option-label
                                 (select-widget-options widget))))
    info))

(defmethod widget-handle-event ((widget select-widget) event)
  (cond
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:up :left)))
     (%select-move widget -1))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:down :right)))
     (%select-move widget 1))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:enter :return :space)))
     (if (select-widget-open-p widget)
         (let ((action (select-widget-select
                        widget (or (select-widget-selected-index widget) 0))))
           (setf (select-widget-open-p widget) nil)
           action)
         (select-widget-toggle widget)))
    ((and (typep event 'key-event)
          (eq (key-event-key event) :escape)
          (select-widget-open-p widget))
     (setf (select-widget-open-p widget) nil)
     (close-action nil widget))
    ((and (typep event 'mouse-event)
          (eq (mouse-event-kind event) :press)
          (rectangle-contains-point-p
           (widget-rectangle widget) (mouse-event-x event)
           (mouse-event-y event)))
     (if (not (select-widget-open-p widget))
         (select-widget-toggle widget)
         (let ((index (+ (%select-visible-start widget)
                         (- (mouse-event-y event)
                            (rectangle-y (widget-rectangle widget))))))
           (when (and (>= index 0) (< index (length (select-widget-options widget))))
             (let ((action (select-widget-select widget index)))
               (setf (select-widget-open-p widget) nil)
               action)))))))

;;; Spinners

(defclass spinner-widget (widget)
  ((frames :initarg :frames :accessor spinner-widget-frames :initform nil)
   (index :initarg :index :accessor spinner-widget-index :initform 0
          :type integer)
   (running-p :initarg :running-p :accessor spinner-widget-running-p
              :initform t :type boolean)
   (action :initarg :action :accessor spinner-widget-action :initform nil)))

(defun make-spinner-widget (&key frames (index 0) (running-p t) action rectangle
                                  style theme keymap (focusable-p t)
                                  (enabled-p t) id semantic-role
                                  accessible-label accessible-description
                                  accessible-help-text)
  (let ((frames (copy-list (or frames (list "-" "/" "|" "\\")))))
    (check-type frames list)
    (unless frames
      (error "A spinner needs at least one frame."))
    (check-type index (integer 0))
    (when (>= index (length frames))
      (error "Spinner frame index ~D is outside the range of ~D frames."
             index (length frames)))
    (check-type running-p boolean)
    (make-instance 'spinner-widget
                   :frames frames :index index :running-p running-p
                   :action action
                   :rectangle
                   (or rectangle
                       (make-rectangle
                        0 0
                        (max 1 (loop for frame in frames
                                     maximize (string-cell-width frame)))
                        1))
                   :style (or style (make-style))
                   :theme (or theme (default-theme)) :keymap keymap
                   :enabled-p enabled-p
                   :focusable-p focusable-p
                   :id id
                   :semantic-role (or semantic-role :status)
                   :accessible-label accessible-label
                   :accessible-description accessible-description
                   :accessible-help-text accessible-help-text)))

(defun spinner-widget-current-frame (widget)
  (nth (spinner-widget-index widget) (spinner-widget-frames widget)))

(defun spinner-widget-tick (widget)
  (when (spinner-widget-running-p widget)
    (setf (spinner-widget-index widget)
          (mod (1+ (spinner-widget-index widget))
               (length (spinner-widget-frames widget))))
    (%widget-action (spinner-widget-action widget) :tick
                    (spinner-widget-current-frame widget) widget)))

(defun spinner-widget-toggle (widget)
  (setf (spinner-widget-running-p widget)
        (not (spinner-widget-running-p widget)))
  (%widget-action (spinner-widget-action widget) :toggle
                  (spinner-widget-running-p widget) widget))

(defmethod widget-preferred-size ((widget spinner-widget))
  (make-size
   (max 1 (loop for frame in (spinner-widget-frames widget)
                maximize (string-cell-width frame)))
   1))

(defmethod widget-render ((widget spinner-widget) surface)
  (let ((rectangle (widget-rectangle widget)))
    (surface-fill-rectangle surface rectangle #\Space
                             (%widget-role-style widget :background))
    (surface-draw-text
     surface (rectangle-x rectangle) (rectangle-y rectangle)
     (spinner-widget-current-frame widget)
     :style (%widget-role-style widget :accent)
     :max-width (rectangle-width rectangle)))
  surface)

(defmethod widget-accessibility-info ((widget spinner-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :status))
    (setf (getf info :label)
          (or (getf info :label) "Progress"))
    (setf (getf info :state)
          (list :running-p (spinner-widget-running-p widget)
                :frame (spinner-widget-current-frame widget)
                :index (spinner-widget-index widget)))
    info))

(defmethod widget-handle-event ((widget spinner-widget) event)
  (cond
    ((typep event 'tick-event)
     (spinner-widget-tick widget))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:space :enter :return)))
     (spinner-widget-toggle widget))
    ((and (typep event 'mouse-event)
          (eq (mouse-event-kind event) :press)
          (rectangle-contains-point-p
           (widget-rectangle widget) (mouse-event-x event)
           (mouse-event-y event)))
     (spinner-widget-toggle widget))))
