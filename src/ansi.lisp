(in-package #:cl-tui-kit/ansi)

;;;; ANSI is deliberately an output-only backend.  It consumes normalized
;;;; surfaces and never parses input, enables raw mode, or owns a terminal.

(defgeneric ansi-backend-previous-surface (backend)
  (:documentation "Return BACKEND's live diff-rendering baseline surface.

The returned SURFACE is the backend's own internal snapshot from the
previous BACKEND-PRESENT call, not a copy: mutating it (through
SURFACE-PUT-CELL or any other surface mutation) corrupts the baseline that
the next BACKEND-PRESENT diffs against.  It is exposed only for
introspection and testing; application code must not write through it."))

(defclass ansi-backend (backend)
  ((stream :initarg :stream :initform *standard-output*
           :accessor ansi-backend-stream)
   (previous-surface :initarg :previous-surface :initform nil
                      :reader ansi-backend-previous-surface
                      :writer (setf %ansi-backend-previous-surface))
   (mouse-mode :initform nil
               :reader ansi-backend-mouse-mode
               :writer (setf %ansi-backend-mouse-mode))
   (mouse-sgr-p :initform nil
                :reader ansi-backend-mouse-sgr-p
                :writer (setf %ansi-backend-mouse-sgr-p))
   (bracketed-paste-enabled-p :initform nil
                              :reader ansi-backend-bracketed-paste-enabled-p
                              :writer (setf %ansi-backend-bracketed-paste-enabled-p))
   (focus-reporting-enabled-p :initform nil
                              :reader ansi-backend-focus-reporting-enabled-p
                              :writer (setf %ansi-backend-focus-reporting-enabled-p))
   (kitty-keyboard-flags :initform nil
                         :reader ansi-backend-kitty-keyboard-flags
                         :writer (setf %ansi-backend-kitty-keyboard-flags))
   (synchronized-updates-enabled-p :initform nil
                                   :reader ansi-backend-synchronized-updates-enabled-p
                                   :writer (setf %ansi-backend-synchronized-updates-enabled-p))))

(defun make-ansi-backend (&key stream size capabilities)
  (make-instance 'ansi-backend
                 :stream (or stream *standard-output*)
                 :size (copy-size (or size (make-size)))
                 :capabilities (or capabilities
                                    (make-backend-capabilities
                                     :color :truecolor
                                     :unicode :full))))

(defparameter *ansi-basic-rgb*
  '((0 0 0) (205 0 0) (0 205 0) (205 205 0)
    (0 0 238) (205 0 205) (0 205 205) (229 229 229)))

(defun %clamp-byte (value)
  (max 0 (min 255 value)))

(defun %rgb-distance (left right)
  (reduce #'+ (mapcar (lambda (a b)
                        (expt (- a b) 2))
                      left right)))

(defun %xterm-rgb (index)
  (let ((index (max 0 (min 255 index))))
    (cond
      ((< index 16)
       ;; The first 16 entries are the conventional ANSI palette.  Keeping
       ;; the low eight here is enough for deterministic down-conversion.
       (nth (mod index 8) *ansi-basic-rgb*))
      ((<= index 231)
       (let* ((offset (- index 16))
              (red (floor offset 36))
              (green (mod (floor offset 6) 6))
              (blue (mod offset 6))
              (level (lambda (component)
                       (if (zerop component) 0 (+ 55 (* component 40))))))
         (list (funcall level red)
               (funcall level green)
               (funcall level blue))))
      (t
       (let ((level (+ 8 (* (- index 232) 10))))
         (list level level level))))))

(defun %color-rgb (color)
  (case (color-kind color)
    (:named
     (nth (or (position (color-value color)
                        '(:black :red :green :yellow :blue :magenta :cyan :white)
                        :test #'eq)
              7)
          *ansi-basic-rgb*))
    (:indexed (%xterm-rgb (color-value color)))
    (:rgb (mapcar #'%clamp-byte (color-value color)))
    (otherwise nil)))

(defun %nearest-basic-index (rgb)
  (loop with best-index = 0
        with best-distance = most-positive-fixnum
        for candidate in *ansi-basic-rgb*
        for index from 0
        for distance = (%rgb-distance rgb candidate)
        when (< distance best-distance)
          do (setf best-index index
                   best-distance distance)
        finally (return best-index)))

(defun %nearest-xterm-index (rgb)
  (loop with best-index = 0
        with best-distance = most-positive-fixnum
        for index from 0 below 256
        for distance = (%rgb-distance rgb (%xterm-rgb index))
        when (< distance best-distance)
          do (setf best-index index
                   best-distance distance)
        finally (return best-index)))

(defun %ansi-color-codes (color foreground-p capability)
  (let ((default-code (if foreground-p "39" "49"))
        (base (if foreground-p 30 40)))
    (case capability
      (:none (list default-code))
      (:basic
       (if (eq (color-kind color) :default)
           (list default-code)
           (list (princ-to-string (+ base (%nearest-basic-index
                                           (or (%color-rgb color)
                                               '(229 229 229))))))))
      (:256
       (case (color-kind color)
         (:default (list default-code))
         (:named
          (list (princ-to-string (+ base (or (position (color-value color)
                                                    '(:black :red :green :yellow
                                                      :blue :magenta :cyan :white)
                                                    :test #'eq)
                                                7)))))
         (otherwise
          (list (if foreground-p "38" "48") "5"
                (princ-to-string (%nearest-xterm-index
                                  (or (%color-rgb color) '(229 229 229))))))))
      (otherwise
       (case (color-kind color)
         (:default (list default-code))
         (:named
          (list (princ-to-string (+ base (or (position (color-value color)
                                                    '(:black :red :green :yellow
                                                      :blue :magenta :cyan :white)
                                                    :test #'eq)
                                                7)))))
         (:indexed
          (list (if foreground-p "38" "48") "5"
                (princ-to-string (max 0 (min 255 (color-value color))))))
         (:rgb
          (append (list (if foreground-p "38" "48") "2")
                  (mapcar (lambda (value)
                            (princ-to-string (%clamp-byte value)))
                          (color-value color))))
         (otherwise (list default-code)))))))

(defun ansi-encode-style (style &key (color-capability :truecolor))
  "Encode STYLE as a self-contained ANSI SGR sequence.

COLOR-CAPABILITY may be :NONE, :BASIC, :256, or :TRUECOLOR.  Rich colors are
deterministically down-converted when the backend cannot represent them."
  (check-type style style)
  (let ((codes (list "0")))
    (flet ((add (value)
             (push value codes)))
      (when (style-bold style) (add "1"))
      (when (style-dim style) (add "2"))
      (when (style-italic style) (add "3"))
      (when (style-underline style) (add "4"))
      (when (style-reverse style) (add "7"))
      (when (style-strike style) (add "9"))
      (dolist (code (%ansi-color-codes (style-foreground style) t
                                       color-capability))
        (add code))
      (dolist (code (%ansi-color-codes (style-background style) nil
                                       color-capability))
        (add code)))
    (format nil "~C[~{~A~^;~}m" (code-char 27) (nreverse codes))))

(defun %ansi-write-private-mode (stream mode enabled-p)
  (format stream "~C[?~D~C" (code-char 27) mode
          (if enabled-p #\h #\l)))

(defun %ansi-mouse-mode-code (mode)
  (ecase mode
    (:click 1000)
    (:button-motion 1002)
    (:any-motion 1003)))

(defun %ansi-finish (backend)
  (finish-output (ansi-backend-stream backend))
  backend)

(defun ansi-enable-mouse-reporting (backend &key (mode :click) (sgr-p t))
  "Enable an explicit ANSI mouse-reporting mode on BACKEND.

MODE is :CLICK, :BUTTON-MOTION, or :ANY-MOTION.  When SGR-P is true, use
the extended SGR 1006 mouse encoding; otherwise retain the legacy encoding.
The mode remains enabled until ANSI-DISABLE-MOUSE-REPORTING or cleanup."
  (check-type backend ansi-backend)
  (check-type sgr-p boolean)
  (let ((mode-code (%ansi-mouse-mode-code mode))
        (stream (ansi-backend-stream backend)))
    (when (and (ansi-backend-mouse-mode backend)
               (not (eq (ansi-backend-mouse-mode backend) mode)))
      (%ansi-write-private-mode
       stream (%ansi-mouse-mode-code (ansi-backend-mouse-mode backend)) nil))
    (when (and (ansi-backend-mouse-sgr-p backend)
               (not sgr-p))
      (%ansi-write-private-mode stream 1006 nil))
    (when (and sgr-p (not (ansi-backend-mouse-sgr-p backend)))
      (%ansi-write-private-mode stream 1006 t))
    (%ansi-write-private-mode stream mode-code t)
    (setf (%ansi-backend-mouse-mode backend) mode
          (%ansi-backend-mouse-sgr-p backend) sgr-p)
    (%ansi-finish backend)))

(defun ansi-disable-mouse-reporting (backend)
  "Disable mouse reporting previously enabled on BACKEND."
  (check-type backend ansi-backend)
  (let ((stream (ansi-backend-stream backend)))
    (when (ansi-backend-mouse-mode backend)
      (%ansi-write-private-mode
       stream (%ansi-mouse-mode-code (ansi-backend-mouse-mode backend)) nil))
    (when (ansi-backend-mouse-sgr-p backend)
      (%ansi-write-private-mode stream 1006 nil))
    (setf (%ansi-backend-mouse-mode backend) nil
          (%ansi-backend-mouse-sgr-p backend) nil)
    (%ansi-finish backend)))

(defun ansi-enable-bracketed-paste (backend)
  "Enable bracketed paste reporting on BACKEND."
  (check-type backend ansi-backend)
  (unless (ansi-backend-bracketed-paste-enabled-p backend)
    (%ansi-write-private-mode (ansi-backend-stream backend) 2004 t)
    (setf (%ansi-backend-bracketed-paste-enabled-p backend) t))
  (%ansi-finish backend))

(defun ansi-disable-bracketed-paste (backend)
  "Disable bracketed paste reporting on BACKEND."
  (check-type backend ansi-backend)
  (when (ansi-backend-bracketed-paste-enabled-p backend)
    (%ansi-write-private-mode (ansi-backend-stream backend) 2004 nil)
    (setf (%ansi-backend-bracketed-paste-enabled-p backend) nil))
  (%ansi-finish backend))

(defun ansi-enable-focus-reporting (backend)
  "Enable terminal focus-in/focus-out reporting on BACKEND."
  (check-type backend ansi-backend)
  (unless (ansi-backend-focus-reporting-enabled-p backend)
    (%ansi-write-private-mode (ansi-backend-stream backend) 1004 t)
    (setf (%ansi-backend-focus-reporting-enabled-p backend) t))
  (%ansi-finish backend))

(defun ansi-disable-focus-reporting (backend)
  "Disable terminal focus reporting on BACKEND."
  (check-type backend ansi-backend)
  (when (ansi-backend-focus-reporting-enabled-p backend)
    (%ansi-write-private-mode (ansi-backend-stream backend) 1004 nil)
    (setf (%ansi-backend-focus-reporting-enabled-p backend) nil))
  (%ansi-finish backend))

(defun ansi-enable-kitty-keyboard (backend &key (flags 1))
  "Enable Kitty keyboard protocol reporting with FLAGS on BACKEND."
  (check-type backend ansi-backend)
  (check-type flags (integer 1))
  (format (ansi-backend-stream backend) "~C[>~Du" (code-char 27) flags)
  (setf (%ansi-backend-kitty-keyboard-flags backend) flags)
  (%ansi-finish backend))

(defun ansi-disable-kitty-keyboard (backend)
  "Disable Kitty keyboard protocol reporting on BACKEND."
  (check-type backend ansi-backend)
  (when (ansi-backend-kitty-keyboard-flags backend)
    (format (ansi-backend-stream backend) "~C[<u" (code-char 27))
    (setf (%ansi-backend-kitty-keyboard-flags backend) nil))
  (%ansi-finish backend))

(defun ansi-enable-synchronized-updates (backend)
  "Request synchronized updates around each complete ANSI frame."
  (check-type backend ansi-backend)
  (setf (%ansi-backend-synchronized-updates-enabled-p backend) t)
  backend)

(defun ansi-disable-synchronized-updates (backend)
  "Stop wrapping subsequent ANSI frames in synchronized updates."
  (check-type backend ansi-backend)
  (setf (%ansi-backend-synchronized-updates-enabled-p backend) nil)
  backend)

(defun %ansi-write-cursor (stream x y)
  (format stream "~C[~D;~DH" (code-char 27) (1+ y) (1+ x)))

(defun %ansi-cell-text (cell)
  (cond
    ((null cell) " ")
    ((cell-continuation-p cell) " ")
    (t (cell-content cell))))

(defmethod backend-present ((backend ansi-backend) surface &key region)
  (let ((stream (ansi-backend-stream backend))
        (previous (ansi-backend-previous-surface backend))
        (synchronized-p
          (ansi-backend-synchronized-updates-enabled-p backend)))
    (when synchronized-p
      (%ansi-write-private-mode stream 2026 t))
    (unwind-protect
         (progn
           (dolist (change (surface-diff surface previous))
             (let ((x (cell-change-x change))
                   (y (cell-change-y change)))
               (when (and (or (null region)
                              (rectangle-contains-point-p region x y))
                          (not (and (cell-change-after change)
                                    (cell-continuation-p
                                     (cell-change-after change)))))
                 (let ((cell (cell-change-after change)))
                   (%ansi-write-cursor stream x y)
                   (write-string (ansi-encode-style
                                  (if cell (cell-style cell) (make-style))
                                  :color-capability
                                  (backend-capabilities-color
                                   (backend-capabilities backend)))
                                 stream)
                   (write-string (%ansi-cell-text cell) stream)))))
           ;; A regional present does not establish the contents of the other
           ;; cells in the terminal.  Preserve the previous snapshot until a
           ;; full frame has been emitted, otherwise a later diff can
           ;; incorrectly suppress an update outside the first region.
           (unless region
             (setf (%ansi-backend-previous-surface backend)
                   (copy-surface surface))))
      (when synchronized-p
        (%ansi-write-private-mode stream 2026 nil))))
  backend)

(defmethod backend-resized :after ((backend ansi-backend) old-size new-size)
  (declare (ignore old-size new-size))
  ;; A resize changes the coordinate space, so a cached frame cannot be used
  ;; as a diff baseline for the next render.
  (backend-invalidate backend))

(defmethod backend-invalidate ((backend ansi-backend))
  (setf (%ansi-backend-previous-surface backend) nil)
  backend)

(defmethod backend-set-cursor :after ((backend ansi-backend) point)
  (%ansi-write-cursor (ansi-backend-stream backend)
                      (point-x point) (point-y point)))

(defmethod backend-set-cursor-visible :after ((backend ansi-backend) visible-p)
  (format (ansi-backend-stream backend) "~C[?25~C"
          (code-char 27) (if visible-p #\h #\l)))

(defmethod backend-enter-alternate :after ((backend ansi-backend))
  (when (backend-capabilities-alternate-screen (backend-capabilities backend))
    (format (ansi-backend-stream backend) "~C[?1049h~C[H"
            (code-char 27) (code-char 27))))

(defmethod backend-leave-alternate :after ((backend ansi-backend))
  (when (backend-capabilities-alternate-screen (backend-capabilities backend))
    (format (ansi-backend-stream backend) "~C[?1049l" (code-char 27))))

(defun %ansi-safe-title (title)
  (when title
    (with-output-to-string (stream)
      (loop for character across (princ-to-string title)
            unless (or (char= character (code-char 27))
                       (char= character (code-char 7))
                       (char= character #\Return)
                       (char= character #\Newline)
                       (char= character #\Linefeed)
                       (char= character #\Page))
            do (write-char character stream)))))

(defmethod backend-set-title :after ((backend ansi-backend) title)
  ;; OSC titles are control sequences; remove control characters from the
  ;; payload and emit an empty title when clearing it.
  (format (ansi-backend-stream backend) "~C]2;~A~C"
          (code-char 27) (or (%ansi-safe-title title) "") (code-char 7)))

(defun %ansi-utf8-octets (text)
  "Encode TEXT as UTF-8 octets for terminal control payloads.

Surrogate code points are not Unicode scalar values; replace them with the
replacement character rather than emitting an invalid UTF-8 sequence."
  (loop for character across text
        for code = (char-code character)
        append (cond
                 ((<= code #x7f)
                  (list code))
                 ((<= code #x7ff)
                  (list (+ #xc0 (ash code -6))
                        (+ #x80 (logand code #x3f))))
                 ((and (<= code #xffff)
                       (or (< code #xd800) (> code #xdfff)))
                  (list (+ #xe0 (ash code -12))
                        (+ #x80 (logand (ash code -6) #x3f))
                        (+ #x80 (logand code #x3f))))
                 ((<= code #x10ffff)
                  (list (+ #xf0 (ash code -18))
                        (+ #x80 (logand (ash code -12) #x3f))
                        (+ #x80 (logand (ash code -6) #x3f))
                        (+ #x80 (logand code #x3f))))
                 (t
                  (list #xef #xbf #xbd)))))

(defparameter *ansi-base64-alphabet*
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defun %ansi-base64 (octets)
  "Encode a sequence of non-negative octets as unwrapped Base64."
  (with-output-to-string (stream)
    (loop for index from 0 below (length octets) by 3
          for first = (elt octets index)
          for second-p = (< (1+ index) (length octets))
          for third-p = (< (+ index 2) (length octets))
          for second = (if second-p (elt octets (1+ index)) 0)
          for third = (if third-p (elt octets (+ index 2)) 0)
          for word = (logior (ash first 16) (ash second 8) third)
          do (write-char (char *ansi-base64-alphabet* (ldb (byte 6 18) word))
                         stream)
             (write-char (char *ansi-base64-alphabet* (ldb (byte 6 12) word))
                         stream)
             (if second-p
                 (write-char (char *ansi-base64-alphabet*
                                   (ldb (byte 6 6) word))
                             stream)
                 (write-char #\= stream))
             (if third-p
                 (write-char (char *ansi-base64-alphabet* (ldb (byte 6 0) word))
                             stream)
                 (write-char #\= stream)))))

(defmethod backend-write-clipboard ((backend ansi-backend) text)
  "Write TEXT through the OSC 52 clipboard convention when advertised.

Reading a terminal clipboard is intentionally separate: it is an
asynchronous query/response protocol and is not faked by this synchronous
output backend."
  (check-type text string)
  (if (backend-supports-p backend :clipboard)
      (let ((stream (ansi-backend-stream backend)))
        (format stream "~C]52;c;~A~C"
                (code-char 27)
                (%ansi-base64 (%ansi-utf8-octets text))
                (code-char 7))
        (finish-output stream)
        (values t :ok))
      (values nil :unsupported)))

(defmethod backend-read-clipboard ((backend ansi-backend))
  (declare (ignore backend))
  (values nil :unsupported))

(defun %ansi-valid-clipboard-selection-p (selection)
  (and (plusp (length selection))
       (not (find-if (lambda (character)
                       (member character
                               (list #\; #\Return #\Newline
                                     (code-char 7) (code-char 27))))
                     selection))))

(defmethod backend-request-clipboard ((backend ansi-backend)
                                      &key (selection "c"))
  "Request an asynchronous OSC 52 clipboard response.

The terminal response must be fed to TERMINAL-INPUT-PARSER.  A successful
request returns T and :PENDING; the eventual response is a CLIPBOARD-EVENT."
  (check-type selection string)
  (unless (%ansi-valid-clipboard-selection-p selection)
    (error 'invalid-argument-error
           :context 'selection
           :datum selection
           :detail "Invalid OSC 52 clipboard selection."))
  (if (backend-supports-p backend :clipboard)
      (let ((stream (ansi-backend-stream backend)))
        (format stream "~C]52;~A;?~C"
                (code-char 27) selection (code-char 7))
        (finish-output stream)
        (values t :pending))
      (values nil :unsupported)))

(defun ansi-request-clipboard (backend &key (selection "c"))
  "Request a clipboard response using the ANSI backend protocol.

This is a convenience name for BACKEND-REQUEST-CLIPBOARD.  The response is
asynchronous and is normalized by TERMINAL-INPUT-PARSER."
  (backend-request-clipboard backend :selection selection))

(defmethod backend-reset-output :after ((backend ansi-backend))
  (let ((stream (ansi-backend-stream backend)))
    (when (ansi-backend-mouse-mode backend)
      (%ansi-write-private-mode
       stream (%ansi-mouse-mode-code (ansi-backend-mouse-mode backend)) nil))
    (when (ansi-backend-mouse-sgr-p backend)
      (%ansi-write-private-mode stream 1006 nil))
    (when (ansi-backend-bracketed-paste-enabled-p backend)
      (%ansi-write-private-mode stream 2004 nil))
    (when (ansi-backend-focus-reporting-enabled-p backend)
      (%ansi-write-private-mode stream 1004 nil))
    (when (ansi-backend-kitty-keyboard-flags backend)
      (format stream "~C[<u" (code-char 27)))
    (when (ansi-backend-synchronized-updates-enabled-p backend)
      (%ansi-write-private-mode stream 2026 nil))
    (setf (%ansi-backend-mouse-mode backend) nil
          (%ansi-backend-mouse-sgr-p backend) nil
          (%ansi-backend-bracketed-paste-enabled-p backend) nil
          (%ansi-backend-focus-reporting-enabled-p backend) nil
          (%ansi-backend-kitty-keyboard-flags backend) nil
          (%ansi-backend-synchronized-updates-enabled-p backend) nil)
    (format stream "~C[0m" (code-char 27))))

(defmethod backend-flush ((backend ansi-backend))
  (finish-output (ansi-backend-stream backend))
  backend)
