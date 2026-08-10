(in-package #:cl-tui-kit/widgets)

;;;; Menu widgets.

(defstruct (menu-item (:constructor %make-menu-item
                                    (label action enabled-p submenu key)))
  label action (enabled-p t) submenu key)

(defun make-menu-item (label &key action (enabled-p t) submenu key)
  (when submenu (check-type submenu menu-widget))
  (%make-menu-item (%text label) action enabled-p submenu key))

(defclass menu-widget (widget)
  ((items :initarg :items :accessor menu-widget-items :initform nil)
   (selected-index :initarg :selected-index
                   :accessor menu-widget-selected-index :initform 0)
   (open-p :initarg :open-p :accessor menu-widget-open-p :initform nil)
   (active-submenu :initarg :active-submenu
                   :accessor menu-widget-active-submenu :initform nil)))

(defun %menu-sync-child (widget)
  (let ((submenu (and (menu-widget-open-p widget)
                      (menu-widget-active-submenu widget))))
    (setf (widget-children widget) (and submenu (list submenu)))
    submenu))

(defun %menu-first-enabled (items)
  (loop for item in items for index from 0
        when (menu-item-enabled-p item) do (return index)))

(defun make-menu-widget (items &key (selected-index 0) (open-p t) id rectangle style
                                     theme keymap (focusable-p t) semantic-role
                                     accessible-label accessible-description
                                     accessible-help-text)
  (dolist (item items)
    (check-type item menu-item)
    (when (menu-item-submenu item)
      (check-type (menu-item-submenu item) menu-widget)))
  (let ((widget (make-instance 'menu-widget :items (copy-list items)
                               :selected-index (if (and (integerp selected-index)
                                                        (<= 0 selected-index)
                                                        (< selected-index (length items))
                                                        (nth selected-index items)
                                                        (menu-item-enabled-p
                                                         (nth selected-index items)))
                                                   selected-index
                                                   (or (%menu-first-enabled items) 0))
                               :open-p open-p :id id
                               :rectangle (or rectangle (make-rectangle))
                               :style (or style (make-style))
                               :theme (or theme (default-theme)) :keymap keymap
                               :focusable-p focusable-p
                               :semantic-role (or semantic-role :menu)
                               :accessible-label accessible-label
                               :accessible-description accessible-description
                               :accessible-help-text accessible-help-text)))
    (%menu-sync-child widget)
    widget))

(defun menu-widget-select (widget index)
  (check-type widget menu-widget)
  (when (and (integerp index)
             (<= 0 index)
             (< index (length (menu-widget-items widget)))
             (nth index (menu-widget-items widget))
             (menu-item-enabled-p (nth index (menu-widget-items widget))))
    (setf (menu-widget-selected-index widget) index
          (menu-widget-active-submenu widget)
          (menu-item-submenu (nth index (menu-widget-items widget))))
    (%menu-sync-child widget)
    widget))

(defun %menu-item-action (widget item)
  (%widget-action (menu-item-action item) :activate
                  (menu-item-key item) widget))

(defmethod widget-preferred-size ((widget menu-widget))
  (let ((width (max 1 (loop for item in (menu-widget-items widget)
                            maximize (+ 4 (string-cell-width (menu-item-label item)))))))
    (make-size width (max 1 (length (menu-widget-items widget))))))

(defmethod widget-layout ((widget menu-widget) rectangle)
  (setf (widget-rectangle widget) (copy-rectangle rectangle))
  (let ((submenu (and (menu-widget-open-p widget) (menu-widget-active-submenu widget))))
    (when submenu
      (let* ((area (widget-rectangle widget))
             (width (min (rectangle-width area) (size-width
                                                   (widget-preferred-size submenu))))
             (child-area (make-rectangle (max (rectangle-x area)
                                              (- (rectangle-right area) width))
                                         (rectangle-y area) width
                                         (rectangle-height area))))
        (widget-layout submenu child-area))))
  widget)

(defmethod widget-render ((widget menu-widget) surface)
  (let* ((area (widget-rectangle widget))
         (items (menu-widget-items widget))
         (style (%widget-role-style widget :foreground))
         (selected-style (%widget-role-style widget :accent))
         (muted-style (%widget-role-style widget :muted)))
    (surface-fill-rectangle surface area #\Space style)
    (loop for item in items for row from 0
          while (< row (rectangle-height area))
          for prefix = (if (= row (menu-widget-selected-index widget)) "> " "  ")
          for suffix = (if (menu-item-submenu item) " ▶" "")
          for label = (concatenate 'string prefix (menu-item-label item) suffix)
          do (surface-draw-text surface (rectangle-x area) (+ (rectangle-y area) row)
                                 label :style (cond ((not (menu-item-enabled-p item))
                                                    muted-style)
                                                   ((= row (menu-widget-selected-index widget))
                                                    selected-style)
                                                   (t style))
                                 :max-width (rectangle-width area)))
    (let ((submenu (and (menu-widget-open-p widget)
                        (menu-widget-active-submenu widget))))
      (when submenu (widget-render submenu surface))))
  widget)

(defmethod widget-accessibility-info ((widget menu-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :menu))
    (setf (getf info :state)
          (list :selected-index (menu-widget-selected-index widget)
                :open-p (menu-widget-open-p widget)
                :items (mapcar (lambda (item)
                                 (list :key (menu-item-key item)
                                       :label (menu-item-label item)
                                       :enabled-p (menu-item-enabled-p item)))
                               (menu-widget-items widget))))
    info))

(defmethod widget-handle-event ((widget menu-widget) event)
  (let ((key (and (typep event 'key-event) (key-event-key event))))
    (cond
      ((member key '(:up :k-up) :test #'equalp)
       (let ((start (menu-widget-selected-index widget)))
         (loop for candidate downfrom (1- start) to 0
               when (menu-item-enabled-p (nth candidate (menu-widget-items widget)))
                 do (menu-widget-select widget candidate)
                    (return (move-action :up 1 widget)))))
      ((member key '(:down :k-down) :test #'equalp)
       (let ((start (menu-widget-selected-index widget)))
         (loop for candidate from (1+ start) below (length (menu-widget-items widget))
               when (menu-item-enabled-p (nth candidate (menu-widget-items widget)))
                 do (menu-widget-select widget candidate)
                    (return (move-action :down 1 widget)))))
      ((equalp key :escape)
       (setf (menu-widget-open-p widget) nil)
       (%menu-sync-child widget)
       (close-action nil widget))
      ((member key '(:right :enter :return) :test #'equalp)
       (let ((item (nth (menu-widget-selected-index widget)
                        (menu-widget-items widget))))
         (when item
           (if (menu-item-submenu item)
               (progn
                 (setf (menu-widget-open-p widget) t)
                 (menu-widget-select widget (menu-widget-selected-index widget))
                 (open-action (menu-item-key item) widget))
               (%menu-item-action widget item)))))
      ((and (typep event 'mouse-event)
            (eq (mouse-event-kind event) :press)
            (rectangle-contains-point-p
             (widget-rectangle widget)
             (make-point (mouse-event-x event) (mouse-event-y event))))
       (let* ((area (widget-rectangle widget))
              (row (- (mouse-event-y event) (rectangle-y area))))
         (when (and (<= 0 row) (< row (length (menu-widget-items widget)))
                    (menu-widget-select widget row))
           (%menu-item-action widget (nth row (menu-widget-items widget)))))))))
