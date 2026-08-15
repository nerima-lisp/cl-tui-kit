(in-package #:cl-tui-kit/widgets)

;;;; Notification center widgets.

(defstruct (notification (:constructor %make-notification
                                        (id message level expires-at)))
  id message (level :info) expires-at)

(defun make-notification (message &key id (level :info) expires-at)
  (%make-notification id (%text message) level expires-at))

(defclass notification-center-widget (widget)
  ((notifications :initarg :notifications
                  :accessor %notification-center-notifications :initform nil)
   (next-id :initarg :next-id :initform 0)
   (max-visible :initarg :max-visible :initform 5)
   (placement :initarg :placement :initform :top)))

(defun make-notification-center (&key (max-visible 5) (placement :top) id rectangle
                                           style theme semantic-role accessible-label
                                           accessible-description accessible-help-text)
  (unless (and (integerp max-visible) (plusp max-visible))
    (error 'invalid-range-error :context 'max-visible :datum max-visible
           :expected "a positive integer"))
  (unless (member placement '(:top :bottom) :test #'eq)
    (error 'invalid-option-error :context 'placement :datum placement
           :allowed '(:top :bottom)))
  (make-instance 'notification-center-widget :max-visible max-visible
                 :placement placement :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style)) :theme (or theme (default-theme))
                 :semantic-role (or semantic-role :status)
                 :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defun notification-center-notifications (widget)
  "Return a fresh list of WIDGET's active notifications.

The returned list is a copy; mutating it does not affect WIDGET.  Use
NOTIFICATION-CENTER-PUSH, -DISMISS, -CLEAR, or -TICK to change it."
  (copy-list (%notification-center-notifications widget)))

(defun notification-center-push (widget message &key id (level :info) expires-at)
  (check-type widget notification-center-widget)
  (let* ((notification (if (typep message 'notification)
                           message
                           (make-notification message :id id :level level
                                              :expires-at expires-at)))
         (next-id (slot-value widget 'next-id)))
    (unless (notification-id notification)
      (setf (notification-id notification) next-id)
      (incf (slot-value widget 'next-id)))
    (push notification (%notification-center-notifications widget))
    notification))

(defun notification-center-dismiss (widget id)
  (check-type widget notification-center-widget)
  (let ((before (length (%notification-center-notifications widget))))
    (setf (%notification-center-notifications widget)
          (remove-if (lambda (notification)
                       (or (eq notification id)
                           (equal (notification-id notification) id)))
                     (%notification-center-notifications widget)))
    (= before (1+ (length (%notification-center-notifications widget))))))

(defun notification-center-clear (widget)
  (check-type widget notification-center-widget)
  (setf (%notification-center-notifications widget) nil)
  widget)

(defun notification-center-tick (widget &optional time)
  (check-type widget notification-center-widget)
  (let ((before (length (%notification-center-notifications widget))))
    (when (numberp time)
      (setf (%notification-center-notifications widget)
            (remove-if (lambda (notification)
                         (and (numberp (notification-expires-at notification))
                              (<= (notification-expires-at notification) time)))
                       (%notification-center-notifications widget))))
    (- before (length (%notification-center-notifications widget)))))

(defmethod widget-preferred-size ((widget notification-center-widget))
  (make-size 32 (max 1 (slot-value widget 'max-visible))))

(defun %notification-visible-list (widget)
  (let* ((all (%notification-center-notifications widget))
         (visible (subseq all 0 (min (length all)
                                     (slot-value widget 'max-visible)))))
    (if (eq (slot-value widget 'placement) :bottom)
        (reverse visible)
        visible)))

(defmethod widget-accessibility-info ((widget notification-center-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :status))
    (setf (getf info :state)
          (list :count (length (%notification-center-notifications widget))
                :messages (mapcar (lambda (notification)
                                    (list :id (notification-id notification)
                                          :level (notification-level notification)
                                          :message (notification-message notification)))
                                  (%notification-center-notifications widget))))
    info))

(defmethod widget-render ((widget notification-center-widget) surface)
  (let* ((area (widget-rectangle widget))
         (style (%widget-role-style widget :accent))
         (notifications (%notification-visible-list widget))
         (start (if (eq (slot-value widget 'placement) :bottom)
                    (- (rectangle-bottom area) (length notifications))
                    (rectangle-y area))))
    (dolist (notification notifications)
      (when (and (<= (rectangle-y area) start)
                 (< start (rectangle-bottom area)))
        (surface-fill-rectangle
         surface (make-rectangle (rectangle-x area) start
                                 (rectangle-width area) 1) #\Space style)
        (surface-draw-text surface (rectangle-x area) start
                           (format nil "[~A] ~A" (notification-level notification)
                                   (notification-message notification))
                           :style style :max-width (rectangle-width area)))
      (incf start)))
  widget)

(defmethod widget-handle-event ((widget notification-center-widget) event)
  (cond
    ((typep event 'tick-event)
     (when (plusp (notification-center-tick widget (tick-event-time event)))
       (custom-action :notifications-updated nil widget)))
    ((and (typep event 'custom-event)
          (eq (custom-event-name event) :dismiss))
     (when (notification-center-dismiss widget (custom-event-payload event))
       (close-action (custom-event-payload event) widget)))
    ((and (typep event 'mouse-event)
          (eq (mouse-event-kind event) :press)
          (rectangle-contains-point-p
           (widget-rectangle widget)
           (make-point (mouse-event-x event) (mouse-event-y event))))
     (let* ((area (widget-rectangle widget))
            (notifications (%notification-visible-list widget))
            (start (if (eq (slot-value widget 'placement) :bottom)
                       (- (rectangle-height area) (length notifications))
                       0))
            (row (- (mouse-event-y event) (rectangle-y area) start))
            (notification (and (<= 0 row) (< row (length notifications))
                               (nth row notifications))))
       (when notification
         (notification-center-dismiss widget notification)
         (close-action (notification-id notification) widget))))))
