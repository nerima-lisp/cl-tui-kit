(in-package #:cl-tui-kit/widgets)

;;;; Widgets are intentionally small protocol objects.  They own presentation
;;;; state only; application state and side effects remain outside this file.

(defclass widget ()
  ((id :initarg :id :accessor widget-id :initform nil)
   (rectangle :initarg :rectangle :accessor widget-rectangle
              :initform (make-rectangle))
   (style :initarg :style :accessor widget-style :initform (make-style))
   (theme :initarg :theme :accessor widget-theme :initform (default-theme))
   (keymap :initarg :keymap :accessor widget-keymap :initform nil)
   (focusable-p :initarg :focusable-p :accessor widget-focusable-p
                :initform nil)
   (enabled-p :initarg :enabled-p :accessor widget-enabled-p :initform t)
   (semantic-role :initarg :semantic-role :accessor widget-role
                  :initform nil)
   (accessible-label :initarg :accessible-label :accessor widget-label
                     :initform nil)
   (accessible-description :initarg :accessible-description
                           :accessor widget-description :initform nil)
   (accessible-help-text :initarg :accessible-help-text
                         :accessor widget-help-text :initform nil)
   (children :initarg :children :accessor widget-children :initform nil)))

(defun make-widget (&key id rectangle style theme keymap focusable-p
                         (enabled-p t) semantic-role accessible-label
                         accessible-description accessible-help-text children)
  (make-instance 'widget :id id :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme)) :keymap keymap
                 :focusable-p focusable-p :enabled-p enabled-p
                 :semantic-role semantic-role :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text
                 :children children))

(defgeneric widget-preferred-size (widget))
(defgeneric widget-layout (widget rectangle))
(defgeneric widget-render (widget surface))
(defgeneric widget-handle-event (widget event))
(defgeneric widget-cursor-position (widget))
(defgeneric widget-accessibility-state (widget))
(defgeneric widget-accessibility-info (widget))
(defgeneric widget-active-p (widget))
(defgeneric widget-interactive-children (widget))
(defgeneric widget-capture-event-p (widget event))

(defgeneric widget-handle-child-action (widget action))

;; Bound while an event is travelling through a widget path.  Composite
;; widgets may need to handle an event passed directly to themselves, but
;; must not dispatch the same event to a child a second time while bubbling
;; from that child.
(defvar *widget-event-target* nil)

(defmethod widget-active-p ((widget widget))
  (declare (ignore widget))
  t)

(defmethod widget-interactive-children ((widget widget))
  (widget-children widget))

(defmethod widget-capture-event-p ((widget widget) event)
  (declare (ignore widget event))
  nil)

(defmethod widget-preferred-size ((widget widget))
  (declare (ignore widget))
  (make-size))

(defmethod widget-layout ((widget widget) rectangle)
  (setf (widget-rectangle widget) (copy-rectangle rectangle))
  (dolist (child (widget-children widget))
    (widget-layout child rectangle))
  widget)

(defmethod widget-render ((widget widget) surface)
  (dolist (child (widget-children widget))
    (widget-render child surface))
  widget)

(defmethod widget-handle-event ((widget widget) event)
  (declare (ignore widget event))
  nil)

(defmethod widget-handle-child-action ((widget widget) action)
  (declare (ignore widget))
  action)

(defmethod widget-cursor-position ((widget widget))
  (declare (ignore widget))
  nil)

(defmethod widget-accessibility-state ((widget widget))
  (declare (ignore widget))
  nil)

(defmethod widget-accessibility-info ((widget widget))
  (list :id (widget-id widget)
        :role (widget-role widget)
        :label (widget-label widget)
        :description (widget-description widget)
        :help-text (widget-help-text widget)
        :enabled-p (widget-enabled-p widget)
        :focusable-p (widget-focusable-p widget)
        :state (widget-accessibility-state widget)))

(defun widget-accessibility-tree (widget)
  "Return a serializable accessibility snapshot for WIDGET and its children."
  (check-type widget widget)
  (let ((info (widget-accessibility-info widget)))
    (setf (getf info :children)
          (mapcar #'widget-accessibility-tree
                  (widget-interactive-children widget)))
    info))

(defun render-widget (widget surface &optional rectangle)
  (when rectangle
    (widget-layout widget rectangle))
  (widget-render widget surface)
  widget)

(defun handle-widget-event (widget event)
  (when (widget-enabled-p widget)
    (widget-handle-event widget event)))

(defun %widget-role-style (widget role)
  (or (theme-style (widget-theme widget) role)
      (widget-style widget)
      (make-style)))

(defun %text (value)
  (if (stringp value) value (princ-to-string value)))

(defclass text-widget (widget)
  ((text :initarg :text :accessor text-widget-text :initform "")
   (role :initarg :role :initform :foreground)))

(defun make-text-widget (text &key id rectangle style theme role semantic-role
                               accessible-label accessible-description
                               accessible-help-text)
  (make-instance 'text-widget :text (%text text) :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme)) :role (or role :foreground)
                 :semantic-role semantic-role :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defmethod widget-preferred-size ((widget text-widget))
  (let ((text (text-widget-text widget)))
    (make-size (string-cell-width text)
               (1+ (count #\Newline text)))))

(defmethod widget-render ((widget text-widget) surface)
  (surface-draw-text surface (rectangle-x (widget-rectangle widget))
                      (rectangle-y (widget-rectangle widget))
                      (text-widget-text widget)
                      :style (%widget-role-style widget
                                                 (slot-value widget 'role))
                      :max-width (rectangle-width (widget-rectangle widget)))
  widget)

(defclass box-widget (widget)
  ((child :initarg :child :accessor box-widget-child :initform nil)
   (border-kind :initarg :border-kind :initform :single)
   (padding :initarg :padding :initform (make-padding :all 1))))

(defun make-box-widget (child &key id rectangle style theme border-kind padding
                              semantic-role accessible-label
                              accessible-description accessible-help-text)
  (make-instance 'box-widget :child child :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme))
                 :border-kind (or border-kind :single)
                 :padding (or padding (make-padding :all 1))
                 :semantic-role semantic-role :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text
                 :children (and child (list child))))

(defmethod widget-preferred-size ((widget box-widget))
  (let* ((child (box-widget-child widget))
         (child-size (if child (widget-preferred-size child) (make-size)))
         (padding (slot-value widget 'padding)))
    (make-size (+ (size-width child-size) (padding-left padding)
                  (padding-right padding) 2)
               (+ (size-height child-size) (padding-top padding)
                  (padding-bottom padding) 2))))

(defmethod widget-render ((widget box-widget) surface)
  (let* ((area (widget-rectangle widget))
         (border-style (%widget-role-style widget :border))
         (inner (rectangle-inset (rectangle-inset area (make-padding :all 1))
                                 (slot-value widget 'padding)))
         (child (box-widget-child widget)))
    (surface-draw-border surface area :style border-style
                          :kind (slot-value widget 'border-kind))
    (when child
      (render-widget child surface inner)))
  widget)

(defmethod widget-layout ((widget box-widget) rectangle)
  (call-next-method)
  (let* ((area (widget-rectangle widget))
         (inner (rectangle-inset (rectangle-inset area (make-padding :all 1))
                                 (slot-value widget 'padding)))
         (child (box-widget-child widget)))
    (when child
      (widget-layout child inner)))
  widget)

(defclass divider-widget (widget)
  ((orientation :initarg :orientation :initform :horizontal)))

(defun make-divider-widget (&key (orientation :horizontal) id rectangle style theme
                                  semantic-role accessible-label
                                  accessible-description accessible-help-text)
  (unless (member orientation '(:horizontal :vertical) :test #'eq)
    (error 'invalid-option-error :context 'orientation :datum orientation
           :allowed '(:horizontal :vertical)))
  (make-instance 'divider-widget :orientation orientation :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme))
                 :semantic-role semantic-role :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defmethod widget-render ((widget divider-widget) surface)
  (let* ((area (widget-rectangle widget))
         (horizontal (eq (slot-value widget 'orientation) :horizontal))
         (glyph (if horizontal "─" "│")))
    (if horizontal
        (loop for x from (rectangle-x area) below (rectangle-right area)
              do (surface-draw-text surface x (rectangle-y area) glyph
                                     :style (%widget-role-style widget :border)))
        (loop for y from (rectangle-y area) below (rectangle-bottom area)
              do (surface-draw-text surface (rectangle-x area) y glyph
                                     :style (%widget-role-style widget :border)))))
  widget)

;;;; Common interactive widgets --------------------------------------------

(defun %widget-action (action default-name payload widget)
  (cond
    ((functionp action) (funcall action widget))
    ((typep action 'action) action)
    ((and action (symbolp action)) (custom-action action payload widget))
    (t (make-action default-name payload widget))))

(defclass button-widget (widget)
  ((label :initarg :label :accessor button-widget-label :initform "")
   (action :initarg :action :accessor button-widget-action :initform nil)))

(defun make-button-widget (label &key action id rectangle style theme keymap
                                      (focusable-p t) (enabled-p t) semantic-role
                                      accessible-label accessible-description
                                      accessible-help-text)
  (make-instance 'button-widget :label (%text label) :action action :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme)) :keymap keymap
                 :focusable-p focusable-p :enabled-p enabled-p
                 :semantic-role semantic-role :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defmethod widget-accessibility-info ((widget button-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :button))
    (setf (getf info :label)
          (or (getf info :label) (button-widget-label widget)))
    info))

(defmethod widget-preferred-size ((widget button-widget))
  (make-size (+ 4 (string-cell-width (button-widget-label widget))) 1))

(defmethod widget-render ((widget button-widget) surface)
  (let* ((area (widget-rectangle widget))
         (label (format nil "[ ~A ]" (button-widget-label widget)))
         (style (%widget-role-style widget :accent)))
    (surface-fill-rectangle surface area #\Space style)
    (surface-draw-text surface (rectangle-x area) (rectangle-y area) label
                       :style style :max-width (rectangle-width area)))
  widget)

(defmethod widget-handle-event ((widget button-widget) event)
  (when (or (and (typep event 'key-event)
                 (member (key-event-key event) '(:enter :return :space)
                         :test #'eq))
            (and (typep event 'mouse-event)
                 (eq (mouse-event-kind event) :press)))
    (%widget-action (button-widget-action widget) :activate
                    (button-widget-label widget) widget)))

(defclass checkbox-widget (widget)
  ((label :initarg :label :accessor checkbox-widget-label :initform "")
   (checked-p :initarg :checked-p :accessor checkbox-widget-checked-p
              :initform nil)
   (action :initarg :action :accessor checkbox-widget-action :initform nil)))

(defun make-checkbox-widget (label &key checked-p action id rectangle style theme
                                        keymap (focusable-p t) (enabled-p t)
                                        semantic-role accessible-label
                                        accessible-description accessible-help-text)
  (make-instance 'checkbox-widget :label (%text label) :checked-p checked-p
                 :action action :id id :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme)) :keymap keymap
                 :focusable-p focusable-p :enabled-p enabled-p
                 :semantic-role semantic-role :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defmethod widget-accessibility-info ((widget checkbox-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :checkbox))
    (setf (getf info :label)
          (or (getf info :label) (checkbox-widget-label widget)))
    info))

(defmethod widget-accessibility-state ((widget checkbox-widget))
  (list :checked-p (checkbox-widget-checked-p widget)))

(defmethod widget-preferred-size ((widget checkbox-widget))
  (make-size (+ 4 (string-cell-width (checkbox-widget-label widget))) 1))

(defmethod widget-render ((widget checkbox-widget) surface)
  (let* ((area (widget-rectangle widget))
         (text (format nil "[~A] ~A"
                       (if (checkbox-widget-checked-p widget) "X" " ")
                       (checkbox-widget-label widget)))
         (style (%widget-role-style widget :foreground)))
    (surface-fill-rectangle surface area #\Space style)
    (surface-draw-text surface (rectangle-x area) (rectangle-y area) text
                       :style style :max-width (rectangle-width area)))
  widget)

(defmethod widget-handle-event ((widget checkbox-widget) event)
  (when (or (and (typep event 'key-event)
                 (member (key-event-key event) '(:enter :return :space)
                         :test #'eq))
            (and (typep event 'mouse-event)
                 (eq (mouse-event-kind event) :press)))
    (setf (checkbox-widget-checked-p widget)
          (not (checkbox-widget-checked-p widget)))
    (%widget-action (checkbox-widget-action widget) :toggle
                    (checkbox-widget-checked-p widget) widget)))

(defclass progress-widget (widget)
  ((value :initarg :value :accessor progress-widget-value :initform 0)
   (maximum :initarg :maximum :accessor progress-widget-maximum :initform 1)
   (label :initarg :label :accessor progress-widget-label :initform nil)))

(defun make-progress-widget (&key (value 0) (maximum 1) label id rectangle style
                                      theme semantic-role accessible-label
                                      accessible-description accessible-help-text)
  (check-type value real)
  (check-type maximum real)
  (when (minusp maximum)
    (error 'invalid-range-error :context 'maximum :datum maximum
           :expected "a value that is not negative"))
  (make-instance 'progress-widget :value value :maximum maximum :label label
                 :id id :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style))
                 :theme (or theme (default-theme))
                 :semantic-role semantic-role :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defmethod widget-accessibility-info ((widget progress-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :progress))
    (setf (getf info :label)
          (or (getf info :label) (progress-widget-label widget)))
    info))

(defmethod widget-accessibility-state ((widget progress-widget))
  (list :value (progress-widget-value widget)
        :maximum (progress-widget-maximum widget)))

(defmethod widget-preferred-size ((widget progress-widget))
  (declare (ignore widget))
  (make-size 20 1))

(defmethod widget-render ((widget progress-widget) surface)
  (let* ((area (widget-rectangle widget))
         (width (rectangle-width area))
         (maximum (progress-widget-maximum widget))
         (value (max 0 (min (progress-widget-value widget) maximum)))
         (ratio (if (plusp maximum) (/ value maximum) 0))
         (filled (min width (floor (* width ratio))))
         (base-style (%widget-role-style widget :muted))
         (fill-style (%widget-role-style widget :accent)))
    (surface-fill-rectangle surface area #\Space base-style)
    (when (plusp filled)
      (surface-fill-rectangle
       surface
       (make-rectangle (rectangle-x area) (rectangle-y area)
                       filled (rectangle-height area))
       #\Space fill-style))
    (when (progress-widget-label widget)
      (surface-draw-text surface (rectangle-x area) (rectangle-y area)
                         (%text (progress-widget-label widget))
                         :style fill-style :max-width width)))
  widget)
