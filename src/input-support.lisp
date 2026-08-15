(in-package #:cl-tui-kit/widgets)

(defclass status-bar-widget (widget)
  ((text :initarg :text :accessor status-bar-widget-text :initform "")))

(defun make-status-bar-widget (text &key id rectangle style theme)
  (make-instance 'status-bar-widget :text (%text text) :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style)) :theme (or theme (default-theme))))

(defmethod widget-render ((widget status-bar-widget) surface)
  (let ((area (%widget-rectangle widget))
        (style (%widget-role-style widget :muted)))
    (surface-fill-rectangle surface area #\Space style)
    (surface-draw-text surface (rectangle-x area) (rectangle-y area)
                        (status-bar-widget-text widget) :style style
                        :max-width (rectangle-width area)))
  widget)

(defclass scroll-bar-widget (widget)
  ((orientation :initarg :orientation :initform :vertical)
   (position :initarg :position :initform 0)
   (page-size :initarg :page-size :initform 1)
   (content-size :initarg :content-size :initform 1)))

(defun make-scroll-bar-widget (&key (orientation :vertical) position page-size
                                         content-size id rectangle style theme)
  (unless (member orientation '(:vertical :horizontal) :test #'eq)
    (error 'invalid-option-error :context 'orientation :datum orientation
           :allowed '(:vertical :horizontal)))
  (make-instance 'scroll-bar-widget :orientation orientation
                 :position (max 0 (or position 0))
                 :page-size (max 1 (or page-size 1))
                 :content-size (max 1 (or content-size 1)) :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style)) :theme (or theme (default-theme))))

(defmethod widget-render ((widget scroll-bar-widget) surface)
  (let* ((area (%widget-rectangle widget))
         (vertical (eq (slot-value widget 'orientation) :vertical))
         (length (if vertical (rectangle-height area) (rectangle-width area)))
         (track (max 1 (ceiling (* length (slot-value widget 'page-size))
                                (slot-value widget 'content-size))))
         (maximum (max 1 (- (slot-value widget 'content-size)
                            (slot-value widget 'page-size))))
         (start (floor (* (max 0 (min maximum (slot-value widget 'position)))
                          (max 0 (- length track))) maximum))
         (track-style (%widget-role-style widget :muted))
         (thumb-style (%widget-role-style widget :accent)))
    (surface-fill-rectangle surface area #\Space track-style)
    (if vertical
        (surface-fill-rectangle surface
                                 (make-rectangle (rectangle-x area)
                                                 (+ (rectangle-y area) start)
                                                 (rectangle-width area) track)
                                 #\█ thumb-style)
        (surface-fill-rectangle surface
                                 (make-rectangle (+ (rectangle-x area) start)
                                                 (rectangle-y area) track
                                                 (rectangle-height area))
                                 #\█ thumb-style)))
  widget)
