(in-package #:cl-tui-kit/core)

(defstruct (event (:constructor %make-event (kind)))
  (kind :event :type symbol))

(defun %normalize-modifier (modifier)
  (if (keywordp modifier)
      (case modifier
        (:control :ctrl)
        (:meta :alt)
        (otherwise modifier))
      (cond
        ((or (string-equal modifier "control")
             (string-equal modifier "ctrl"))
         :ctrl)
        ((or (string-equal modifier "meta")
             (string-equal modifier "alt"))
         :alt)
        ((string-equal modifier "shift") :shift)
        ((string-equal modifier "super") :super)
        ((string-equal modifier "hyper") :hyper)
        (t
         (error 'invalid-option-error
                :context 'modifier
                :datum modifier
                :allowed '(:control :ctrl :meta :alt :shift :super :hyper)
                :detail "Unsupported modifier designator. Any keyword is accepted; a non-keyword designator must otherwise name one of the listed symbols.")))))

(defun normalize-modifiers (modifiers)
  "Canonicalize modifier designators without interning user-provided names."
  (let ((normalized
          (remove-duplicates
           (mapcar #'%normalize-modifier
                   (or modifiers '()))
           :test #'eq)))
    (sort normalized #'<
          :key (lambda (modifier)
                 (or (position modifier '(:ctrl :alt :shift :super :hyper)
                                      :test #'eq)
                     99)))))

(defstruct (key-event (:include event (kind :key))
                      (:constructor %make-key-event
                          (key modifiers text phase)))
  (key :unknown)
  (modifiers '() :type list)
  text
  (phase :press :type symbol))

(defun make-key-event (key &key modifiers text (phase :press))
  (check-type phase symbol)
  (%make-key-event key (normalize-modifiers modifiers) text phase))

(defstruct (text-input-event (:include event (kind :text-input))
                             (:constructor %make-text-input-event (text)))
  (text "" :type string))

(defun make-text-input-event (text)
  (check-type text string)
  (%make-text-input-event text))

(defstruct (paste-event (:include event (kind :paste))
                        (:constructor %make-paste-event (text)))
  (text "" :type string))

(defun make-paste-event (text)
  (check-type text string)
  (%make-paste-event text))

(defstruct (clipboard-event (:include event (kind :clipboard))
                            (:constructor %make-clipboard-event
                                (selection text)))
  "A terminal clipboard response normalized from an OSC 52 sequence."
  (selection "c" :type string)
  (text "" :type string))

(defun make-clipboard-event (text &key (selection "c"))
  (check-type text string)
  (check-type selection string)
  (%make-clipboard-event selection text))

(defstruct (resize-event (:include event (kind :resize))
                         (:constructor %make-resize-event (width height)))
  (width 0 :type (integer 0))
  (height 0 :type (integer 0)))

(defun make-resize-event (width height)
  (%make-resize-event (%extent width 'width) (%extent height 'height)))

(defstruct (mouse-event (:include event (kind :mouse))
                        (:conc-name mouse-event-slot-)
                        (:constructor %make-mouse-event
                            (x y button mouse-kind modifiers)))
  (x 0 :type integer)
  (y 0 :type integer)
  button
  (mouse-kind :press :type symbol)
  (modifiers '() :type list))

(defun make-mouse-event (x y &key button (kind :press) modifiers)
  (%make-mouse-event (%coordinate x 'x) (%coordinate y 'y) button kind
                     (normalize-modifiers modifiers)))

(defun mouse-event-kind (event)
  "Return the semantic mouse action (:PRESS, :RELEASE, or :MOVE)."
  (mouse-event-slot-mouse-kind event))

(defun mouse-event-x (event)
  (mouse-event-slot-x event))

(defun mouse-event-y (event)
  (mouse-event-slot-y event))

(defun mouse-event-button (event)
  (mouse-event-slot-button event))

(defun mouse-event-modifiers (event)
  (mouse-event-slot-modifiers event))

(defstruct (focus-event (:include event (kind :focus))
                        (:constructor %make-focus-event (focused-p reason)))
  (focused-p nil :type boolean)
  reason)

(defun make-focus-event (focused-p &optional reason)
  (%make-focus-event (not (null focused-p)) reason))

(defstruct (tick-event (:include event (kind :tick))
                       (:constructor %make-tick-event (time)))
  time)

(defun make-tick-event (&optional time)
  (%make-tick-event time))

(defstruct (custom-event (:include event (kind :custom))
                         (:constructor %make-custom-event (name payload)))
  (name :custom :type symbol)
  payload)

(defun make-custom-event (name &optional payload)
  (check-type name symbol)
  (%make-custom-event name payload))

(defstruct (action (:constructor %make-action (name payload source)))
  (name :custom :type symbol)
  payload
  source)

(defun make-action (name &optional payload source)
  (check-type name symbol)
  (%make-action name payload source))

(defmacro define-simple-action-constructors (&body definitions)
  "Define action constructors with the common payload/source contract."
  `(progn
     ,@(mapcar
        (lambda (definition)
          (destructuring-bind (function-name action-name) definition
            `(defun ,function-name (&optional payload source)
               (make-action ,action-name payload source))))
        definitions)))

(define-simple-action-constructors
  (activate-action :activate)
  (cancel-action :cancel)
  (submit-action :submit)
  (toggle-action :toggle)
  (open-action :open)
  (close-action :close))

(defun move-action (direction &optional amount source)
  (make-action :move (list :direction direction :amount (or amount 1)) source))

(defun select-action (key &optional source)
  (make-action :select key source))

(defun custom-action (name &optional payload source)
  (make-action name payload source))
