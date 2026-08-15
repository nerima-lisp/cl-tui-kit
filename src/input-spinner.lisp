(in-package #:cl-tui-kit/widgets)

;;; Spinners

(defclass spinner-widget (widget)
  ((frames :initarg :frames :accessor spinner-widget-frames :initform nil)
   (index :initarg :index :accessor %spinner-widget-index :initform 0
          :type integer)
   (running-p :initarg :running-p :accessor spinner-widget-running-p
              :initform t :type boolean)
   (action :initarg :action :accessor spinner-widget-action :initform nil)))

(defun spinner-widget-index (widget)
  "Return WIDGET's current frame index.

This value is internal animation state kept within WIDGET's frame count by
wrapping; use SPINNER-WIDGET-TICK to advance it."
  (%spinner-widget-index widget))

(defmethod (setf spinner-widget-frames) :after (new-frames (widget spinner-widget))
  "Keep WIDGET's frame index within NEW-FRAMES' bounds.

SPINNER-WIDGET-FRAMES is a plain writable accessor, so an application may
replace it directly with a shorter -- or empty -- list.  Without this, a
stale index surviving a non-empty shrink made SPINNER-WIDGET-CURRENT-
FRAME return NIL via NTH, which WIDGET-RENDER then fed to
SURFACE-DRAW-TEXT's (CHECK-TYPE TEXT STRING).  An empty list is a
separate failure this clamp alone cannot fix -- see the guards in
SPINNER-WIDGET-TICK and WIDGET-RENDER below."
  (declare (ignore new-frames))
  (let ((count (length (spinner-widget-frames widget))))
    (when (>= (%spinner-widget-index widget) count)
      (setf (%spinner-widget-index widget) (max 0 (1- count))))))

(defun make-spinner-widget
    (&key (frames nil frames-p)
          (index 0)
          (running-p t)
          action rectangle style theme keymap
          (focusable-p t)
          (enabled-p t)
          id semantic-role
          accessible-label accessible-description accessible-help-text)
  (let ((frames (if frames-p frames (list "-" "/" "|" "\\"))))
    (check-type frames list)
    (unless frames
      (error 'invalid-argument-error :context 'frames :datum frames
             :detail "A spinner needs at least one frame."))
    (setf frames (copy-list frames))
    (check-type index (integer 0))
    (when (>= index (length frames))
      (error 'index-out-of-bounds-error :context "frames" :index index
             :count (length frames)))
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
  (nth (%spinner-widget-index widget) (spinner-widget-frames widget)))

(defun spinner-widget-tick (widget)
  (when (and (spinner-widget-running-p widget) (spinner-widget-frames widget))
    (setf (%spinner-widget-index widget)
          (mod (1+ (%spinner-widget-index widget))
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
  (let ((rectangle (widget-rectangle widget))
        (frame (spinner-widget-current-frame widget)))
    (surface-fill-rectangle surface rectangle #\Space
                             (%widget-role-style widget :background))
    (when frame
      (surface-draw-text
       surface (rectangle-x rectangle) (rectangle-y rectangle)
       frame
       :style (%widget-role-style widget :accent)
       :max-width (rectangle-width rectangle))))
  surface)

(defmethod widget-accessibility-info ((widget spinner-widget))
  (let ((info (call-next-method)))
    (or (getf info :role) (setf (getf info :role) :status))
    (setf (getf info :label) (or (getf info :label) "Progress"))
    (setf (getf info :state)
          (list :running-p (spinner-widget-running-p widget)
                :frame (spinner-widget-current-frame widget)
                :index (%spinner-widget-index widget)))
    info))

(defmethod widget-handle-event ((widget spinner-widget) event)
  (cond
    ((typep event 'tick-event) (spinner-widget-tick widget))
    ((and (typep event 'key-event)
          (member (key-event-key event) '(:space :enter :return)))
     (spinner-widget-toggle widget))
    ((and (typep event 'mouse-event)
          (eq (mouse-event-kind event) :press)
          (rectangle-contains-point-p
           (widget-rectangle widget) (mouse-event-x event)
           (mouse-event-y event)))
     (spinner-widget-toggle widget))))
