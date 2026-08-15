(in-package #:cl-tui-kit/widgets)

;;;; Text-view presentation and navigation --------------------------------

(defun %split-widget-lines (text)
  (let ((lines '())
        (start 0))
    (loop for end = (position #\Newline text :start start)
          do (if end
                 (progn
                   (push (subseq text start end) lines)
                   (setf start (1+ end)))
                 (progn
                   (push (subseq text start) lines)
                   (return))))
    (nreverse lines)))

(defun %wrap-widget-line (line width)
  (if (or (zerop width) (zerop (length line)))
      (list "")
      (let ((lines '())
            (current '())
            (column 0))
        (labels ((finish-line ()
                   (push (with-output-to-string (stream)
                           (dolist (piece (nreverse current))
                             (write-string piece stream)))
                         lines)
                   (setf current nil
                         column 0)))
          (dolist (unit (text-units line))
            (let ((unit-width (if (string= unit (string #\Tab))
                                  (- 8 (mod column 8))
                                  (text-unit-width unit))))
              (when (and (plusp column) (> (+ column unit-width) width))
                (finish-line)
                (setf unit-width (if (string= unit (string #\Tab)) 8
                                     (text-unit-width unit))))
              (push (if (string= unit (string #\Tab))
                        (make-string unit-width :initial-element #\Space)
                        unit)
                    current)
              (incf column unit-width)))
          (finish-line)
          (nreverse lines)))))

(defclass text-view-widget (widget)
  ((text :initarg :text :accessor text-view-widget-text :initform "")
   (wrap-p :initarg :wrap-p :accessor text-view-widget-wrap-p :initform t)
   (offset :initarg :offset :accessor %text-view-widget-offset :initform 0)
   (search-query :initarg :search-query
                 :accessor text-view-widget-search-query :initform nil)))

(defun make-text-view-widget (text &key (wrap-p t) (offset 0) id rectangle style
                                       theme keymap focusable-p semantic-role
                                       accessible-label accessible-description
                                       accessible-help-text)
  (check-type text string)
  (make-instance 'text-view-widget :text text :wrap-p wrap-p
                 :offset (max 0 offset) :id id
                 :rectangle (or rectangle (make-rectangle))
                 :style (or style (make-style)) :theme (or theme (default-theme))
                 :keymap keymap :focusable-p focusable-p
                 :semantic-role (or semantic-role :document)
                 :accessible-label accessible-label
                 :accessible-description accessible-description
                 :accessible-help-text accessible-help-text))

(defun %text-view-lines (widget)
  (let ((width (max 1 (rectangle-width (%widget-rectangle widget)))))
    (if (text-view-widget-wrap-p widget)
        (mapcan (lambda (line) (%wrap-widget-line line width))
                (%split-widget-lines (text-view-widget-text widget)))
        (%split-widget-lines (text-view-widget-text widget)))))

(defun text-view-widget-offset (widget)
  "Return WIDGET's current scroll offset, in lines.

This value is internal scroll state kept within WIDGET's line count and
rendered height; use TEXT-VIEW-WIDGET-SCROLL-TO or TEXT-VIEW-WIDGET-SCROLL-BY
to change it."
  (%text-view-widget-offset widget))

(defun %text-view-clamp-offset (widget offset)
  (let* ((height (max 0 (rectangle-height (%widget-rectangle widget))))
         (maximum (max 0 (- (length (%text-view-lines widget)) height))))
    (max 0 (min maximum offset))))

(defmethod widget-preferred-size ((widget text-view-widget))
  (let ((lines (%split-widget-lines (text-view-widget-text widget))))
    (make-size (max 1 (loop for line in lines maximize (string-cell-width line)))
               (max 1 (length lines)))))

(defun text-view-widget-scroll-to (widget offset)
  (check-type widget text-view-widget)
  (check-type offset integer)
  (setf (%text-view-widget-offset widget)
        (%text-view-clamp-offset widget offset))
  widget)

(defun text-view-widget-scroll-by (widget amount)
  (check-type amount integer)
  (text-view-widget-scroll-to widget
                              (+ (%text-view-widget-offset widget) amount)))

(defun text-view-widget-find (widget query &optional (start 0))
  (check-type widget text-view-widget)
  (check-type query string)
  (check-type start integer)
  (setf (text-view-widget-search-query widget) query)
  (when (plusp (length query))
    (let* ((text (text-view-widget-text widget))
           (start (min (length text) (max 0 start)))
           (position (search query text :start2 start :test #'char-equal)))
      (when position
        (text-view-widget-scroll-to
         widget
         (count #\Newline (subseq text 0 position)))
        position))))

(defmethod widget-accessibility-info ((widget text-view-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :document))
    (setf (getf info :state)
          (list :offset (%text-view-widget-offset widget)
                :line-count (length (%text-view-lines widget))
                :search-query (text-view-widget-search-query widget)))
    info))

(defmethod widget-render ((widget text-view-widget) surface)
  (let* ((area (%widget-rectangle widget))
         (style (%widget-role-style widget :foreground))
         (lines (%text-view-lines widget))
         (offset (%text-view-widget-offset widget)))
    (surface-fill-rectangle surface area #\Space style)
    (loop for row from 0 below (rectangle-height area)
          for index = (+ offset row)
          when (< index (length lines))
            do (surface-draw-text surface (rectangle-x area) (+ (rectangle-y area) row)
                                   (nth index lines) :style style
                                   :max-width (rectangle-width area))))
  widget)

(defmethod widget-handle-event ((widget text-view-widget) event)
  (let ((key (and (typep event 'key-event) (key-event-key event))))
    (cond
      ((member key '(:up :k-up) :test #'equalp)
       (text-view-widget-scroll-by widget -1)
       (move-action :up 1 widget))
      ((member key '(:down :k-down) :test #'equalp)
       (text-view-widget-scroll-by widget 1)
       (move-action :down 1 widget))
      ((equalp key :page-up)
       (text-view-widget-scroll-by widget (- (max 1 (rectangle-height
                                                       (%widget-rectangle widget)))))
       (move-action :page-up 1 widget))
      ((equalp key :page-down)
       (text-view-widget-scroll-by widget (max 1 (rectangle-height
                                                   (%widget-rectangle widget))))
       (move-action :page-down 1 widget))
      ((equalp key :home)
       (text-view-widget-scroll-to widget 0)
       (move-action :home 1 widget))
      ((equalp key :end)
       (text-view-widget-scroll-to widget most-positive-fixnum)
       (move-action :end 1 widget))
      ((and (typep event 'mouse-event)
            (eq (mouse-event-kind event) :press)
            (rectangle-contains-point-p
             (%widget-rectangle widget)
             (make-point (mouse-event-x event) (mouse-event-y event)))
            (member (mouse-event-button event)
                    '(:wheel-up :scroll-up :wheel-down :scroll-down)
                    :test #'eq))
       (if (member (mouse-event-button event) '(:wheel-up :scroll-up)
                   :test #'eq)
           (text-view-widget-scroll-by widget -3)
           (text-view-widget-scroll-by widget 3))
       (move-action :scroll 3 widget))
      ((and (typep event 'custom-event)
            (eq (custom-event-name event) :find))
       (text-view-widget-find widget (or (custom-event-payload event) ""))
       (custom-action :find (custom-event-payload event) widget)))))
