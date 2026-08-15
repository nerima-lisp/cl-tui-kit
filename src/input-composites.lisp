(in-package #:cl-tui-kit/widgets)

(defclass form-widget (widget)
  ((fields :initarg :fields :accessor form-widget-fields :initform nil)
   (validator :initarg :validator :accessor form-widget-validator
              :initform nil)
   (errors :accessor %form-widget-errors :initform nil)
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
    (error 'invalid-type-error :context 'validator :datum validator
           :expected-type '(or function null)))
  (when (and submit-action (not (functionp submit-action)))
    (error 'invalid-type-error :context 'submit-action :datum submit-action
           :expected-type '(or function null)))
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

(defun form-widget-errors (form)
  "Return a fresh list of FORM's validation errors.

The returned list is a copy; mutating it does not affect FORM.  Use
FORM-WIDGET-VALIDATE to recompute it."
  (copy-list (%form-widget-errors form)))

(defun form-widget-validate (form)
  "Validate FORM and return true when no errors remain."
  (check-type form form-widget)
  (let ((validator (form-widget-validator form)))
    (setf (%form-widget-errors form)
          (when validator
            (let ((result (funcall validator (form-widget-values form)
                                   form)))
              (cond
                ((or (null result) (eq result t)) nil)
                ((listp result) (copy-list result))
                (t (list result))))))
    (null (%form-widget-errors form))))

(defun form-widget-submit (form)
  "Validate FORM and return a submit or validation-error action."
  (check-type form form-widget)
  (unless (form-widget-validate form)
    (return-from form-widget-submit
      (custom-action :validation-error (%form-widget-errors form) form)))
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
          (getf info :errors) (copy-list (%form-widget-errors widget)))
    info))

(defmethod widget-preferred-size ((widget form-widget))
  (let* ((fields (form-widget-fields widget))
         (errors (%form-widget-errors widget))
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
  (setf (%widget-rectangle widget) (copy-rectangle rectangle))
  (let ((area (%widget-rectangle widget))
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
  (let* ((area (%widget-rectangle widget))
         (y (reduce #'max
                   (form-widget-fields widget)
                   :key (lambda (field)
                          (rectangle-bottom
                           (%widget-rectangle field)))
                   :initial-value (rectangle-y area)))
         (style (%widget-role-style widget :error)))
    (loop for error in (%form-widget-errors widget)
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
         (area (%widget-rectangle widget))
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
   (open-p :initarg :open-p :accessor %modal-widget-open-p :initform nil)
   (dialog-rectangle :accessor %modal-dialog-rectangle
                     :initform (make-rectangle))
   (result :initarg :result :accessor %modal-widget-result :initform nil)
   (close-reason :initarg :close-reason
                 :accessor %modal-widget-close-reason
                 :initform nil)
   (buttons :initarg :buttons :accessor modal-widget-buttons :initform nil)
   (outside-close-p :initarg :outside-close-p
                    :accessor modal-widget-outside-close-p
                    :initform nil)))

(defun modal-widget-open-p (widget)
  "Return true when WIDGET's modal is currently open.

Use MODAL-WIDGET-OPEN and MODAL-WIDGET-CLOSE to change it."
  (%modal-widget-open-p widget))

(defun modal-widget-result (widget)
  "Return the result WIDGET was closed with, or NIL.

This is reset by MODAL-WIDGET-OPEN and set by MODAL-WIDGET-CLOSE."
  (%modal-widget-result widget))

(defun modal-widget-close-reason (widget)
  "Return the reason WIDGET was closed, or NIL while open.

This is reset by MODAL-WIDGET-OPEN and set by MODAL-WIDGET-CLOSE."
  (%modal-widget-close-reason widget))

(defmethod widget-active-p ((widget modal-widget))
  (%modal-widget-open-p widget))

(defmethod widget-interactive-children ((widget modal-widget))
  (when (%modal-widget-open-p widget)
    (call-next-method)))

(defmethod widget-capture-event-p ((widget modal-widget) event)
  (and (%modal-widget-open-p widget)
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
  (if (%modal-widget-open-p widget)
      (%modal-handle-child-action widget action)
      action))

(defun modal-widget-open (widget)
  (setf (%modal-widget-open-p widget) t)
  (setf (%modal-widget-result widget) nil
        (%modal-widget-close-reason widget) nil)
  ;; A child can have changed its preferred size while the modal was closed
  ;; (for example, after a form validation error).  Synchronize hit-test
  ;; rectangles before callers query them or dispatch the first event.
  (%modal-layout widget)
  widget)

(defun modal-widget-close (widget &optional result (reason :programmatic))
  (setf (%modal-widget-open-p widget) nil)
  (setf (%modal-widget-result widget) result
        (%modal-widget-close-reason widget) reason)
  widget)

(defun %modal-button-row-width (buttons)
  (if buttons
      (+ (loop for button in buttons
               sum (max 1 (size-width (widget-preferred-size button))))
         (1- (length buttons)))
      0))

(defun %modal-geometry (widget)
  (let* ((area (%widget-rectangle widget))
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
  (setf (%widget-rectangle widget) (copy-rectangle rectangle))
  (%modal-layout widget)
  widget)

(defmethod widget-accessibility-info ((widget modal-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :dialog))
    (setf (getf info :focusable-p)
          (and (%modal-widget-open-p widget)
               (widget-focusable-p widget)))
    (setf (getf info :state)
          (list :open-p (%modal-widget-open-p widget)
                :result (%modal-widget-result widget)
                :close-reason (%modal-widget-close-reason widget)
                :button-count (length (modal-widget-buttons widget))))
    info))

(defmethod widget-render ((widget modal-widget) surface)
  (when (%modal-widget-open-p widget)
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
  (when (%modal-widget-open-p widget)
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
                         (%widget-rectangle candidate)
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
