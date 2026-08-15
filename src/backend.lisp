(in-package #:cl-tui-kit/core)

;;;; A backend is an output protocol.  Input adapters may construct
;;;; normalized EVENT values and hand them to an application; the core does
;;;; not enable raw mode, own a file descriptor, or create a polling thread.

(defstruct (backend-capabilities
            (:constructor %make-backend-capabilities
                (color unicode mouse clipboard alternate-screen)))
  (color :none :type keyword)
  (unicode :basic :type keyword)
  (mouse :none :type keyword)
  clipboard
  (alternate-screen t :type boolean))

(defun make-backend-capabilities (&key (color :none) (unicode :basic)
                                       (mouse :none) clipboard
                                       (alternate-screen t))
  (%make-backend-capabilities color unicode mouse clipboard
                              (not (null alternate-screen))))

(defun %backend-capability-name-p (capability)
  (member capability '(:color :unicode :mouse :clipboard :alternate-screen)
          :test #'eq))

(defun %check-backend-capability (capability)
  (unless (%backend-capability-name-p capability)
    (error 'invalid-option-error
           :context 'capability
           :datum capability
           :allowed '(:color :unicode :mouse :clipboard :alternate-screen)))
  capability)

(defun %check-backend-capability-state (state)
  (unless (member state '(:unknown :unsupported :supported :error)
                  :test #'eq)
    (error 'invalid-option-error
           :context 'state
           :datum state
           :allowed '(:unknown :unsupported :supported :error)))
  state)

(defun %copy-capability-states (states)
  (let ((copy (make-hash-table :test #'eq)))
    (when states
      (unless (hash-table-p states)
        (error 'invalid-type-error
               :context 'capability-states
               :datum (bounded-datum states)
               :expected-type 'hash-table))
      (maphash (lambda (capability state)
                 (setf (gethash (%check-backend-capability capability) copy)
                       (%check-backend-capability-state state)))
               states))
    copy))

(defclass backend ()
  ((size :initarg :size :initform (make-size) :accessor backend-size)
   (capabilities :initarg :capabilities
                 :initform (make-backend-capabilities)
                 :accessor backend-capabilities)
   (cursor :initarg :cursor :initform (make-point) :accessor backend-cursor)
   (cursor-visible :initarg :cursor-visible :initform t
                   :accessor backend-cursor-visible)
   (title :initarg :title :initform nil :accessor backend-title)
   (alternate-screen-p :initarg :alternate-screen-p :initform nil
                       :accessor backend-alternate-screen-p)
   (capability-states :initarg :capability-states
                      :initform (make-hash-table :test #'eq)
                      :accessor backend-capability-states)
   (state :initarg :state :initform :closed :accessor backend-state)
   (last-error :initarg :last-error :initform nil
               :accessor backend-last-error)))

(defun make-backend (&key (size (make-size)) capabilities cursor
                          (cursor-visible t) title capability-states)
  (make-instance 'backend
                 :size (copy-size size)
                 :capabilities (or capabilities (make-backend-capabilities))
                 :cursor (copy-point (or cursor (make-point)))
                 :cursor-visible (not (null cursor-visible))
                 :capability-states (%copy-capability-states capability-states)
                 :title title))

(defun backend-capability (backend capability)
  "Return BACKEND's raw capability value for CAPABILITY.

CAPABILITY is one of :COLOR, :UNICODE, :MOUSE, :CLIPBOARD, or
:ALTERNATE-SCREEN.  Unknown capabilities return NIL so adapters can probe
optional features without depending on implementation-specific slots."
  (check-type backend backend)
  (let ((capabilities (backend-capabilities backend)))
    (case capability
      (:color (backend-capabilities-color capabilities))
      (:unicode (backend-capabilities-unicode capabilities))
      (:mouse (backend-capabilities-mouse capabilities))
      (:clipboard (backend-capabilities-clipboard capabilities))
      (:alternate-screen
       (backend-capabilities-alternate-screen capabilities))
      (otherwise nil))))

(defun backend-supports-p (backend capability)
  "Return true when BACKEND can provide CAPABILITY.

Capability levels such as :TRUECOLOR, :UTF-8, and :SGR-MOUSE are supported
only when the normalized capability state is :SUPPORTED.  Adapters can use
an explicit :UNKNOWN or :ERROR state while probing a terminal."
  (eq (backend-capability-state backend capability) :supported))

(defun %backend-derived-capability-state (value)
  (cond
    ((eq value :unknown) :unknown)
    ((eq value :error) :error)
    ((or (null value)
         (eq value :none)
         (eq value :unsupported))
     :unsupported)
    (t :supported)))

(defun backend-capability-state (backend capability)
  "Return a normalized state for CAPABILITY on BACKEND.

The raw capability value remains available through BACKEND-CAPABILITY.  NIL
means :UNSUPPORTED, while adapters may explicitly use :UNKNOWN or :ERROR to
represent a probe that has not completed or failed.  An explicit state takes
precedence over the declarative capability value."
  (check-type backend backend)
  (%check-backend-capability capability)
  (multiple-value-bind (state present-p)
    (gethash capability (backend-capability-states backend))
    (if present-p
        (%check-backend-capability-state state)
        (%backend-derived-capability-state
         (backend-capability backend capability)))))

(defun backend-set-capability (backend capability value)
  "Set the raw capability VALUE used by BACKEND.

This is an adapter hook: it records an observation but does not probe the
terminal itself.  COLOR, UNICODE, and MOUSE use keyword levels; CLIPBOARD
accepts an adapter-defined value; ALTERNATE-SCREEN is normalized to boolean."
  (check-type backend backend)
  (%check-backend-capability capability)
  (let ((capabilities (backend-capabilities backend)))
    (case capability
      (:color
       (check-type value keyword)
       (setf (backend-capabilities-color capabilities) value))
      (:unicode
       (check-type value keyword)
       (setf (backend-capabilities-unicode capabilities) value))
      (:mouse
       (check-type value keyword)
       (setf (backend-capabilities-mouse capabilities) value))
      (:clipboard
       (setf (backend-capabilities-clipboard capabilities) value))
      (:alternate-screen
       (setf (backend-capabilities-alternate-screen capabilities)
             (not (null value))))))
  backend)

(defun backend-set-capability-state
    (backend capability state &key (value nil value-supplied-p))
  "Set an explicit normalized capability STATE on BACKEND.

STATE must be one of :UNKNOWN, :UNSUPPORTED, :SUPPORTED, or :ERROR.  When
VALUE is supplied, BACKEND's raw capability value is updated as well."
  (check-type backend backend)
  (%check-backend-capability capability)
  (%check-backend-capability-state state)
  (when value-supplied-p
    (backend-set-capability backend capability value))
  (setf (gethash capability (backend-capability-states backend)) state)
  backend)

(defgeneric backend-open (backend)
  (:documentation "Open BACKEND's owned resources and mark it active."))

(defgeneric backend-close (backend)
  (:documentation "Close BACKEND and restore output state when necessary."))

(defgeneric backend-fail (backend condition)
  (:documentation "Record CONDITION as a backend failure and mark BACKEND failed."))

(defmethod backend-open ((backend backend))
  (check-type backend backend)
  (setf (backend-state backend) :open
        (backend-last-error backend) nil)
  backend)

(defmethod backend-close ((backend backend))
  (check-type backend backend)
  (unless (eq (backend-state backend) :closed)
    (handler-case
        (progn
          (backend-reset-output backend)
          (backend-flush backend))
      (condition (condition)
        (setf (backend-state backend) :failed
              (backend-last-error backend) condition)
        (error condition))))
  (setf (backend-state backend) :closed
        (backend-last-error backend) nil)
  backend)

(defmethod backend-fail ((backend backend) condition)
  (check-type backend backend)
  (check-type condition condition)
  (setf (backend-state backend) :failed
        (backend-last-error backend) condition)
  backend)

(defgeneric backend-resized (backend old-size new-size)
  (:documentation "Notify BACKEND adapters that its logical size changed."))

(defun backend-resize (backend width height)
  (check-type backend backend)
  (let ((old-size (copy-size (backend-size backend)))
        (new-size (make-size width height)))
    (setf (backend-size backend) new-size)
    (backend-resized backend old-size (copy-size new-size)))
  backend)

(defgeneric backend-begin-frame (backend)
  (:documentation "Begin a frame.  Implementations may reset their diff state."))

(defgeneric backend-present (backend surface &key region)
  (:documentation "Present a rendered SURFACE or REGION to the output device."))

(defgeneric backend-flush (backend)
  (:documentation "Flush buffered output to the output device."))

(defgeneric backend-set-cursor (backend point)
  (:documentation "Set the logical cursor position in terminal cells."))

(defgeneric backend-set-cursor-visible (backend visible-p)
  (:documentation "Set cursor visibility without parsing terminal input."))

(defgeneric backend-enter-alternate (backend)
  (:documentation "Enter an alternate screen when supported."))

(defgeneric backend-leave-alternate (backend)
  (:documentation "Leave an alternate screen when supported."))

(defgeneric backend-set-title (backend title)
  (:documentation "Set the terminal title when supported."))

(defgeneric backend-invalidate (backend)
  (:documentation "Discard any cached output snapshot before a full redraw."))

(defgeneric backend-clear-title (backend)
  (:documentation "Clear the backend's title, when the output device supports it."))

(defgeneric backend-reset-output (backend)
  (:documentation "Restore output state needed for a clean application shutdown."))

(defgeneric backend-write-clipboard (backend text)
  (:documentation "Write TEXT to the backend clipboard, returning value and status."))

(defgeneric backend-read-clipboard (backend)
  (:documentation "Read the backend clipboard, returning text and status."))

(defgeneric backend-request-clipboard (backend &key selection)
  (:documentation
   "Request an asynchronous clipboard response from BACKEND.

The response is delivered through the input adapter as a normalized
CLIPBOARD-EVENT.  Return the request result and a status keyword."))

(defmethod backend-resized ((backend backend) old-size new-size)
  (declare (ignore backend old-size new-size))
  nil)

(defmethod backend-begin-frame ((backend backend))
  (declare (ignore backend))
  nil)

(defmethod backend-present ((backend backend) surface &key region)
  (declare (ignore backend surface region))
  nil)

(defmethod backend-flush ((backend backend))
  (declare (ignore backend))
  nil)

(defmethod backend-set-cursor ((backend backend) point)
  (check-type point point)
  (setf (backend-cursor backend) (copy-point point))
  backend)

(defmethod backend-set-cursor-visible ((backend backend) visible-p)
  (setf (backend-cursor-visible backend) (not (null visible-p)))
  backend)

(defmethod backend-enter-alternate ((backend backend))
  (when (backend-supports-p backend :alternate-screen)
    (setf (backend-alternate-screen-p backend) t))
  backend)

(defmethod backend-leave-alternate ((backend backend))
  (setf (backend-alternate-screen-p backend) nil)
  backend)

(defmethod backend-set-title ((backend backend) title)
  (setf (backend-title backend) title)
  backend)

(defmethod backend-invalidate ((backend backend))
  (declare (ignore backend))
  nil)

(defmethod backend-clear-title ((backend backend))
  (backend-set-title backend nil))

(defmethod backend-reset-output ((backend backend))
  (backend-invalidate backend)
  (backend-set-cursor-visible backend t)
  (backend-clear-title backend)
  (backend-leave-alternate backend)
  backend)

(defmethod backend-write-clipboard ((backend backend) text)
  (declare (ignore backend text))
  (values nil :unsupported))

(defmethod backend-read-clipboard ((backend backend))
  (declare (ignore backend))
  (values nil :unsupported))

(defmethod backend-request-clipboard ((backend backend) &key (selection "c"))
  (declare (ignore backend))
  (check-type selection string)
  (values nil :unsupported))
