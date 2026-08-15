(in-package #:cl-tui-kit/widgets)

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
    (error 'index-out-of-bounds-error :context "options" :index index
           :count (length options)))
  index)

(defmacro define-indexed-control-movement
    (name options-accessor index-accessor &key wrap-accessor selector)
  "Define bounded selection movement for an indexed option control.

The option collection and movement policy are data supplied by the control;
the generated function only coordinates those values and delegates the state
change to SELECTOR.  This keeps radio and select controls consistent without
sharing their rendering or event policies."
  (let ((delta (gensym "DELTA-"))
        (options (gensym "OPTIONS-"))
        (count (gensym "COUNT-"))
        (current (gensym "CURRENT-"))
        (next (gensym "NEXT-")))
    `(defun ,name (widget ,delta)
       (let ((,options (,options-accessor widget)))
         (when ,options
           (let* ((,count (length ,options))
                  (,current (or (,index-accessor widget) 0))
                  (,next (+ ,current ,delta)))
             (setf ,next
                   ,(if wrap-accessor
                        `(if (,wrap-accessor widget)
                             (mod ,next ,count)
                             (max 0 (min (1- ,count) ,next)))
                        `(max 0 (min (1- ,count) ,next))))
             (,selector widget ,next)))))))

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

(define-indexed-control-movement %radio-move
  radio-widget-options radio-widget-selected-index
  :selector radio-widget-select
  :wrap-accessor radio-widget-wrap-p)

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

(define-indexed-control-movement %select-move
  select-widget-options select-widget-selected-index
  :selector select-widget-select)

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
    (if (select-widget-open-p widget) (let* ((count (length options))
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
                      :max-width (max 0 (- right x)))))) (surface-draw-text
         surface x y
         (format nil "[v] ~A"
                 (if selected
                     (%control-option-label
                      (nth selected options))
                     ""))
         :style (%widget-role-style widget :foreground)
         :max-width (max 0 (- right x))))
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
     (if (select-widget-open-p widget) (let ((index (+ (%select-visible-start widget)
                         (- (mouse-event-y event)
                            (rectangle-y (widget-rectangle widget))))))
           (when (and (>= index 0) (< index (length (select-widget-options widget))))
             (let ((action (select-widget-select widget index)))
               (setf (select-widget-open-p widget) nil)
               action))) (select-widget-toggle widget)))))
