(in-package #:cl-tui-kit/widgets)

;;;; Tab navigation widgets.

(defstruct (tab-entry (:constructor %make-tab-entry (key label content enabled-p)))
  key label content (enabled-p t))

(defun make-tab (label content &key key (enabled-p t))
  (when content (check-type content widget))
  (%make-tab-entry key (%text label) content enabled-p))

(defclass tabs-widget (widget)
  ((tabs :initarg :tabs :accessor tabs-widget-tabs :initform nil)
   (selected-index :initarg :selected-index
                   :accessor %tabs-widget-selected-index :initform 0)))

(defun tabs-widget-selected-index (widget)
  "Return WIDGET's selected tab index.

This value is internal selection state kept within WIDGET's tab count and
paired with the synced child content; use TABS-WIDGET-SELECT to change it."
  (%tabs-widget-selected-index widget))

(defun %first-enabled-tab (tabs)
  (loop for tab in tabs for index from 0
        when (tab-entry-enabled-p tab) do (return index)))

(defun %tabs-current-entry (widget)
  (let ((index (%tabs-widget-selected-index widget)))
    (and index (nth index (tabs-widget-tabs widget)))))

(defun %tabs-sync-children (widget)
  (let ((content (and (%tabs-current-entry widget)
                      (tab-entry-content (%tabs-current-entry widget)))))
    (setf (widget-children widget) (and content (list content)))
    content))

(defun make-tabs-widget (tabs &key (selected-index 0) id rectangle style theme keymap
                                    focusable-p semantic-role accessible-label
                                    accessible-description accessible-help-text)
  (dolist (tab tabs) (check-type tab tab-entry))
  (let* ((selected (if (and (integerp selected-index)
                            (<= 0 selected-index)
                            (< selected-index (length tabs))
                            (nth selected-index tabs)
                            (tab-entry-enabled-p (nth selected-index tabs)))
                       selected-index
                       (or (%first-enabled-tab tabs) 0)))
         (widget (make-instance 'tabs-widget :tabs (copy-list tabs)
                                :selected-index selected :id id
                                :rectangle (or rectangle (make-rectangle))
                                :style (or style (make-style))
                                :theme (or theme (default-theme)) :keymap keymap
                                :focusable-p focusable-p
                                :semantic-role (or semantic-role :tablist)
                                :accessible-label accessible-label
                                :accessible-description accessible-description
                                :accessible-help-text accessible-help-text)))
    (%tabs-sync-children widget)
    widget))

(defun tabs-widget-select (widget index)
  (check-type widget tabs-widget)
  (when (and (integerp index)
             (<= 0 index)
             (< index (length (tabs-widget-tabs widget)))
             (nth index (tabs-widget-tabs widget))
             (tab-entry-enabled-p (nth index (tabs-widget-tabs widget))))
    (setf (%tabs-widget-selected-index widget) index)
    (%tabs-sync-children widget)
    widget))

(defun %tabs-index-at-x (widget x)
  (let ((cursor (rectangle-x (widget-rectangle widget))))
    (loop for tab in (tabs-widget-tabs widget) for index from 0
          for width = (+ 2 (string-cell-width (tab-entry-label tab)))
          do (when (and (<= cursor x) (< x (+ cursor width)))
               (return index))
             (incf cursor width))))

(defmethod widget-preferred-size ((widget tabs-widget))
  (let* ((header (max 1 (loop for tab in (tabs-widget-tabs widget)
                              maximize (+ 2 (string-cell-width (tab-entry-label tab))))))
         (content (%tabs-current-entry widget))
         (size (if (and content (tab-entry-content content))
                   (widget-preferred-size (tab-entry-content content))
                   (make-size 0 0))))
    (make-size (max header (size-width size)) (1+ (size-height size)))))

(defmethod widget-layout ((widget tabs-widget) rectangle)
  (setf (widget-rectangle widget) (copy-rectangle rectangle))
  (let* ((area (widget-rectangle widget))
         (content (and (%tabs-current-entry widget)
                       (tab-entry-content (%tabs-current-entry widget))))
         (content-area (make-rectangle (rectangle-x area) (1+ (rectangle-y area))
                                       (rectangle-width area)
                                       (max 0 (1- (rectangle-height area))))))
    (when content (widget-layout content content-area)))
  widget)

(defmethod widget-render ((widget tabs-widget) surface)
  (let* ((area (widget-rectangle widget))
         (header-style (%widget-role-style widget :border))
         (selected-style (%widget-role-style widget :accent))
         (muted-style (%widget-role-style widget :muted))
         (cursor (rectangle-x area)))
    (surface-fill-rectangle surface area #\Space
                             (%widget-role-style widget :background))
    (loop for tab in (tabs-widget-tabs widget) for index from 0
          for label = (format nil " ~A " (tab-entry-label tab))
          for width = (+ 2 (string-cell-width (tab-entry-label tab)))
          do (surface-draw-text surface cursor (rectangle-y area) label
                                 :style (cond ((not (tab-entry-enabled-p tab)) muted-style)
                                              ((= index (%tabs-widget-selected-index widget))
                                               selected-style)
                                              (t header-style))
                                 :max-width width)
             (incf cursor width))
    (let ((content (and (%tabs-current-entry widget)
                        (tab-entry-content (%tabs-current-entry widget)))))
      (when content (widget-render content surface))))
  widget)

(defmethod widget-accessibility-info ((widget tabs-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :tablist))
    (setf (getf info :state)
          (list :selected-index (%tabs-widget-selected-index widget)
                :tabs (mapcar (lambda (tab)
                                (list :key (tab-entry-key tab)
                                      :label (tab-entry-label tab)
                                      :enabled-p (tab-entry-enabled-p tab)))
                              (tabs-widget-tabs widget))))
    info))

(defmethod widget-handle-event ((widget tabs-widget) event)
  (let ((key (and (typep event 'key-event) (key-event-key event))))
    (cond
      ((member key '(:left :previous-tab) :test #'equalp)
       (let ((index (%tabs-widget-selected-index widget)))
         (loop for candidate downfrom (1- index) to 0
               when (tab-entry-enabled-p (nth candidate (tabs-widget-tabs widget)))
                 do (tabs-widget-select widget candidate)
                    (return (select-action (tab-entry-key (nth candidate
                                                                (tabs-widget-tabs widget)))
                                           widget)))))
      ((member key '(:right :next-tab) :test #'equalp)
       (let ((index (%tabs-widget-selected-index widget)))
         (loop for candidate from (1+ index) below (length (tabs-widget-tabs widget))
               when (tab-entry-enabled-p (nth candidate (tabs-widget-tabs widget)))
                 do (tabs-widget-select widget candidate)
                    (return (select-action (tab-entry-key (nth candidate
                                                                (tabs-widget-tabs widget)))
                                           widget)))))
      ((and (typep event 'mouse-event)
            (eq (mouse-event-kind event) :press)
            (= (mouse-event-y event) (rectangle-y (widget-rectangle widget))))
       (let ((index (%tabs-index-at-x widget (mouse-event-x event))))
         (when (tabs-widget-select widget index)
           (select-action (tab-entry-key (nth index (tabs-widget-tabs widget)))
                          widget))))
      (t
       (let ((content (and (%tabs-current-entry widget)
                           (tab-entry-content (%tabs-current-entry widget)))))
         (and content (handle-widget-event content event)))))))
