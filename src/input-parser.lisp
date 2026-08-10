(in-package #:cl-tui-kit/core)

;;;; Incremental terminal input

(defstruct (terminal-input-parser
            (:constructor %make-terminal-input-parser
                (buffer pending-octets in-paste-p paste-buffer
                 max-sequence-length max-paste-length)))
  "State for parsing a terminal input byte stream.

The parser deliberately has no stream, thread, or file-descriptor dependency.
An adapter owns those resources and feeds octets or strings into this state
machine. Incomplete escape sequences and UTF-8 sequences remain buffered until
more input arrives."
  (buffer "" :type string)
  (pending-octets '() :type list)
  (in-paste-p nil :type boolean)
  (paste-buffer "" :type string)
  (max-sequence-length 256 :type (integer 1 *))
  (max-paste-length (* 1024 1024) :type (integer 1 *)))

(defun make-terminal-input-parser (&key (max-sequence-length 256)
                                        (max-paste-length (* 1024 1024)))
  "Create an incremental parser with bounded control and paste buffers."
  (check-type max-sequence-length (integer 1 *))
  (check-type max-paste-length (integer 1 *))
  (%make-terminal-input-parser "" '() nil ""
                               max-sequence-length max-paste-length))

(defun terminal-input-parser-reset (parser)
  "Discard all buffered input while retaining parser limits."
  (check-type parser terminal-input-parser)
  (setf (terminal-input-parser-buffer parser) ""
        (terminal-input-parser-pending-octets parser) '()
        (terminal-input-parser-in-paste-p parser) nil
        (terminal-input-parser-paste-buffer parser) "")
  parser)

(defun terminal-input-parser-pending-p (parser)
  "Return true when PARSER is waiting for more input."
  (check-type parser terminal-input-parser)
  (not (null
        (or (plusp (length (terminal-input-parser-buffer parser)))
            (terminal-input-parser-pending-octets parser)
            (terminal-input-parser-in-paste-p parser)))))

(defun %terminal-input-parser-utf8-decode-one (octets)
  (let* ((first (first octets))
         (needed (cond ((< first #x80) 1)
                       ((<= #xc2 first #xdf) 2)
                       ((<= #xe0 first #xef) 3)
                       ((<= #xf0 first #xf4) 4)
                       (t nil))))
    (cond
      ((null needed)
       (values (code-char #xfffd) 1 :invalid))
      ((< (length octets) needed)
       (values nil 0 :incomplete))
      ((= needed 1)
       (values (code-char first) 1 :valid))
      (t
       (let ((rest (subseq octets 1 needed)))
         (if (or (not (every (lambda (byte) (<= #x80 byte #xbf)) rest))
                 (and (= needed 3)
                      (or (and (= first #xe0) (< (first rest) #xa0))
                          (and (= first #xed) (> (first rest) #x9f))))
                 (and (= needed 4)
                      (or (and (= first #xf0) (< (first rest) #x90))
                          (and (= first #xf4) (> (first rest) #x8f)))))
             (values (code-char #xfffd) 1 :invalid)
             (let ((code (case needed
                           (2 (+ (ash (logand first #x1f) 6)
                                 (logand (first rest) #x3f)))
                           (3 (+ (ash (logand first #x0f) 12)
                                 (ash (logand (first rest) #x3f) 6)
                                 (logand (second rest) #x3f)))
                           (4 (+ (ash (logand first #x07) 18)
                                 (ash (logand (first rest) #x3f) 12)
                                 (ash (logand (second rest) #x3f) 6)
                                 (logand (third rest) #x3f))))))
               (values (or (code-char code) (code-char #xfffd))
                       needed :valid))))))))

(defun %terminal-input-parser-append-octets (parser octets)
  (let ((remaining (append (terminal-input-parser-pending-octets parser)
                           (coerce octets 'list))))
    (setf (terminal-input-parser-pending-octets parser) '())
    (loop while remaining do
      (multiple-value-bind (character consumed status)
          (%terminal-input-parser-utf8-decode-one remaining)
        (case status
          (:incomplete
           (setf (terminal-input-parser-pending-octets parser) remaining)
           (return))
          (otherwise
           (setf remaining (nthcdr consumed remaining)
                 (terminal-input-parser-buffer parser)
                 (concatenate 'string
                              (terminal-input-parser-buffer parser)
                              (string character))))))))
  parser)

(defun %terminal-input-parser-plain-character-p (character)
  (let ((code (char-code character)))
    (and (/= code 27)
         (> code 31)
         (/= code 127))))

(defun %terminal-input-parser-split-parameters (body)
  (let ((length (length body))
        (start 0)
        (parts '()))
    (loop for index from 0 to length do
      (when (or (= index length)
                (char= (char body index) #\;))
        (push (subseq body start index) parts)
        (setf start (1+ index))))
    (nreverse parts)))

(defparameter *terminal-input-parser-base64-alphabet*
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defun %terminal-input-parser-base64-value (character)
  (position character *terminal-input-parser-base64-alphabet*))

(defun %terminal-input-parser-base64-decode (text)
  "Decode strict RFC 4648 base64 TEXT into a list of octets.

Return two values: the decoded octets and a boolean indicating whether TEXT
was valid. OSC 52 responses are terminal input, so malformed data must not
be silently converted into a partial clipboard value."
  (block decode
    (unless (zerop (mod (length text) 4))
      (return-from decode (values nil nil)))
    (let ((octets '())
          (length (length text)))
      (loop for index from 0 below length by 4
            for final-p = (= (+ index 4) length)
            for first = (char text index)
            for second = (char text (+ index 1))
            for third = (char text (+ index 2))
            for fourth = (char text (+ index 3))
            for first-value = (%terminal-input-parser-base64-value first)
            for second-value = (%terminal-input-parser-base64-value second)
            for third-padding-p = (char= third #\=)
            for fourth-padding-p = (char= fourth #\=)
            for third-value = (unless third-padding-p
                               (%terminal-input-parser-base64-value third))
            for fourth-value = (unless fourth-padding-p
                                (%terminal-input-parser-base64-value fourth))
            do (when (or (null first-value)
                         (null second-value)
                         (and (null third-value) (not third-padding-p))
                         (and (null fourth-value) (not fourth-padding-p))
                         (and third-padding-p (not fourth-padding-p))
                         (and third-padding-p
                              (not (zerop (logand second-value #x0f))))
                         (and (not third-padding-p)
                              fourth-padding-p
                              (not (zerop (logand third-value #x03))))
                         (and (or third-padding-p fourth-padding-p)
                              (not final-p)))
                 (return-from decode (values nil nil)))
               (let ((bits (logior (ash first-value 18)
                                   (ash second-value 12)
                                   (ash (or third-value 0) 6)
                                   (or fourth-value 0))))
                 (push (ldb (byte 8 16) bits) octets)
                 (unless third-padding-p
                   (push (ldb (byte 8 8) bits) octets))
                 (unless fourth-padding-p
                   (push (ldb (byte 8 0) bits) octets))))
      (values (nreverse octets) t))))

(defun %terminal-input-parser-octets-to-string (octets)
  (with-output-to-string (stream)
    (loop while octets
          do (multiple-value-bind (character consumed status)
                 (%terminal-input-parser-utf8-decode-one octets)
               (cond
                 ((eq status :valid)
                  (write-char character stream)
                  (setf octets (nthcdr consumed octets)))
                 (t
                  (write-char (code-char #xfffd) stream)
                  (setf octets (rest octets))))))))

(defun %terminal-input-parser-osc-event (payload)
  (let ((parts (%terminal-input-parser-split-parameters payload)))
    (if (and (= (length parts) 3)
             (string= (first parts) "52"))
        (let ((selection (second parts))
              (encoded (third parts)))
          (multiple-value-bind (octets valid-p)
              (%terminal-input-parser-base64-decode encoded)
            (if valid-p
                (make-clipboard-event
                 (%terminal-input-parser-octets-to-string octets)
                 :selection selection)
                (make-custom-event
                 :terminal-sequence
                 (list :protocol :osc
                       :command "52"
                       :selection selection
                       :payload encoded
                       :error :invalid-base64)))))
        (make-custom-event
         :terminal-sequence
         (list :protocol :osc :payload payload)))))

(defun %terminal-input-parser-decimal (text)
  (when (plusp (length text))
    (loop with value = 0
          for character across text
          for code = (char-code character)
          do (unless (<= (char-code #\0) code (char-code #\9))
               (return-from %terminal-input-parser-decimal))
             (setf value (+ (* value 10) (- code (char-code #\0))))
          finally (return value))))

(defun %terminal-input-parser-modifiers (parameter)
  (let ((mask (max 0 (1- (or parameter 1)))))
    (normalize-modifiers
     (append (when (logtest 1 mask) '(:shift))
             (when (logtest 2 mask) '(:alt))
             (when (logtest 4 mask) '(:ctrl))
             (when (logtest 8 mask) '(:super))))))

(defun %terminal-input-parser-kitty-modifiers (parameter)
  "Translate kitty keyboard modifier bits into normalized modifiers."
  (let ((mask (max 0 (1- (or parameter 1)))))
    (normalize-modifiers
     (append (when (logtest 1 mask) '(:shift))
             (when (logtest 2 mask) '(:alt))
             (when (logtest 4 mask) '(:ctrl))
             (when (logtest 8 mask) '(:super))
             (when (logtest 16 mask) '(:hyper))
             (when (logtest 32 mask) '(:alt))))))

(defun %terminal-input-parser-parameters (body)
  (let ((private-p (and (plusp (length body))
                        (member (char body 0) '(#\? #\> #\!))))
        (body (if (and (plusp (length body))
                       (member (char body 0) '(#\? #\> #\!)))
                  (subseq body 1)
                  body)))
    (values private-p
            (mapcar #'%terminal-input-parser-decimal
                    (%terminal-input-parser-split-parameters body)))))

(defun %terminal-input-parser-key-for (final parameters)
  (case final
    (#\A :up)
    (#\B :down)
    (#\C :right)
    (#\D :left)
    (#\H :home)
    (#\F :end)
    (#\P :f1)
    (#\Q :f2)
    (#\R :f3)
    (#\S :f4)
    (#\~
     (case (first parameters)
       ((1 7) :home)
       ((2) :insert)
       ((3) :delete)
       ((4 8) :end)
       ((5) :page-up)
       ((6) :page-down)
       ((11) :f1)
       ((12) :f2)
       ((13) :f3)
       ((14) :f4)
       ((15) :f5)
       ((17) :f6)
       ((18) :f7)
       ((19) :f8)
       ((20) :f9)
       ((21) :f10)
       ((23) :f11)
       ((24) :f12)
       (otherwise nil)))
    (otherwise nil)))

(defun %terminal-input-parser-key-event-for-codepoint
    (codepoint modifiers &key (phase :press))
  "Build a key event for a protocol-encoded Unicode codepoint."
  (let ((character (and (integerp codepoint) (code-char codepoint))))
    (when character
      (case codepoint
        (9 (make-key-event :tab :modifiers modifiers :phase phase))
        ((8 127) (make-key-event :backspace :modifiers modifiers :phase phase))
        ((10 13) (make-key-event :enter :modifiers modifiers :phase phase))
        (27 (make-key-event :escape :modifiers modifiers :phase phase))
        (otherwise
         (make-key-event
          character
          :modifiers modifiers
          :phase phase
          :text (when (%terminal-input-parser-plain-character-p character)
                  (string character))))))))

(defun %terminal-input-parser-kitty-event (body)
  "Parse kitty's CSI codepoint;modifiers:event-type u form."
  (let* ((separator (position #\: body))
         (parameter-body (if separator (subseq body 0 separator) body))
         (event-type (if separator
                         (%terminal-input-parser-decimal
                          (subseq body (1+ separator)))
                         1))
         (parameters (mapcar #'%terminal-input-parser-decimal
                             (%terminal-input-parser-split-parameters
                              parameter-body)))
         (phase (case event-type
                  (1 :press)
                  (2 :repeat)
                  (3 :release)
                  (otherwise nil))))
    (when (and phase
               (integerp (first parameters))
               (or (null (second parameters))
                   (integerp (second parameters))))
      (%terminal-input-parser-key-event-for-codepoint
       (first parameters)
       (%terminal-input-parser-kitty-modifiers (second parameters))
       :phase phase))))

(defun %terminal-input-parser-modify-other-keys-event (parameters)
  "Parse xterm's CSI 27;modifier;codepoint~ form."
  (when (and (eql (first parameters) 27)
             (member (length parameters) '(2 3)))
    (let ((modifier (if (= (length parameters) 3)
                        (second parameters)
                        1))
          (codepoint (car (last parameters))))
      (when (and (integerp modifier) (integerp codepoint))
        (%terminal-input-parser-key-event-for-codepoint
         codepoint
         (%terminal-input-parser-modifiers modifier))))))

(defun %terminal-input-parser-mouse-button (code)
  (case (logand code 3)
    (0 :left)
    (1 :middle)
    (2 :right)
    (otherwise :unknown)))

(defun %terminal-input-parser-mouse-event (body final)
  (let ((body (if (and (plusp (length body)) (char= (char body 0) #\<))
                  (subseq body 1)
                  body)))
    (let ((parameters (mapcar #'%terminal-input-parser-decimal
                              (%terminal-input-parser-split-parameters body))))
      (when (and (= (length parameters) 3)
                 (every #'integerp parameters))
        (let* ((button-code (first parameters))
               (x (max 0 (1- (second parameters))))
               (y (max 0 (1- (third parameters))))
               (wheel-p (logtest #x40 button-code))
               (motion-p (logtest #x20 button-code))
               (modifiers (%terminal-input-parser-modifiers
                           (+ 1
                              (if (logtest #x04 button-code) 1 0)
                              (if (logtest #x08 button-code) 2 0)
                              (if (logtest #x10 button-code) 4 0))))
               (kind (cond
                       (wheel-p (if (zerop (logand button-code 1))
                                    :scroll-up
                                    :scroll-down))
                       (motion-p :move)
                       ((char= final #\m) :release)
                       (t :press)))
               (button (if wheel-p :wheel
                           (%terminal-input-parser-mouse-button button-code))))
           (make-mouse-event x y :button button :kind kind
                             :modifiers modifiers))))))

(defun %terminal-input-parser-x10-mouse-event (buffer)
  "Parse the six-byte X10 mouse form ESC [ M Cb Cx Cy."
  (when (>= (length buffer) 6)
    (let ((bytes (map 'list #'char-code (subseq buffer 3 6))))
      (when (every (lambda (byte) (<= 32 byte 255)) bytes)
        (let* ((button-code (- (first bytes) 32))
               (x (- (second bytes) 33))
               (y (- (third bytes) 33))
               (wheel-p (logtest #x40 button-code))
               (motion-p (logtest #x20 button-code))
               (modifiers
                 (normalize-modifiers
                  (append (when (logtest #x04 button-code) '(:shift))
                          (when (logtest #x08 button-code) '(:alt))
                          (when (logtest #x10 button-code) '(:ctrl)))))
               (kind (cond
                       (wheel-p (if (zerop (logand button-code 1))
                                    :scroll-up
                                    :scroll-down))
                       (motion-p :move)
                       ((= (logand button-code 3) 3) :release)
                       (t :press)))
               (button (if wheel-p :wheel
                           (%terminal-input-parser-mouse-button button-code))))
          (make-mouse-event (max 0 x) (max 0 y)
                            :button button :kind kind
                            :modifiers modifiers))))))

(defun %terminal-input-parser-csi-event (parser body final)
  (multiple-value-bind (private-p parameters)
      (%terminal-input-parser-parameters body)
    (declare (ignore private-p))
    (cond
      ((char= final #\u)
       (or (%terminal-input-parser-kitty-event body)
           (make-custom-event :terminal-sequence
                              (list :body body :final final))))
      ((and (char= final #\I) (zerop (length body)))
       (make-focus-event t))
      ((and (char= final #\O) (zerop (length body)))
       (make-focus-event nil))
      ((and (char= final #\~) (eql (first parameters) 200))
       (setf (terminal-input-parser-in-paste-p parser) t
             (terminal-input-parser-paste-buffer parser) "")
       nil)
      ((and (char= final #\~) (eql (first parameters) 201))
       nil)
      ((and (plusp (length body)) (char= (char body 0) #\<))
       (or (%terminal-input-parser-mouse-event body final)
           (make-custom-event :terminal-sequence
                              (list :body body :final final))))
      (t
       (let ((encoded-key (and (char= final #\~)
                               (%terminal-input-parser-modify-other-keys-event
                                parameters)))
             (key (%terminal-input-parser-key-for final parameters)))
         (cond
           (encoded-key encoded-key)
           (key
            (make-key-event
             key
             :modifiers (%terminal-input-parser-modifiers
                         (second parameters))))
           (t
            (make-custom-event :terminal-sequence
                               (list :body body :final final)))))))))

(defun %terminal-input-parser-osc (parser)
  (let* ((buffer (terminal-input-parser-buffer parser))
         (length (length buffer))
         (bel (position (code-char 7) buffer :start 2))
         (st (loop for index from 2 below (1- length)
                   when (and (char= (char buffer index) (code-char 27))
                             (char= (char buffer (1+ index)) (code-char 92)))
                     do (return index)))
         (terminator (cond
                       ((and bel st) (min bel st))
                       (bel bel)
                       (st st))))
    (cond
      (terminator
       (let ((terminator-length (if (and st (= terminator st)) 2 1)))
         (prog1
             (values
              (%terminal-input-parser-osc-event
               (subseq buffer 2 terminator))
              :done)
           (setf (terminal-input-parser-buffer parser)
                 (subseq buffer (+ terminator terminator-length))))))
      ((> length (terminal-input-parser-max-sequence-length parser))
       (setf (terminal-input-parser-buffer parser) "")
       (values (make-custom-event
                :input-overflow
                (list :kind :escape-sequence
                      :limit (terminal-input-parser-max-sequence-length
                              parser)))
               :done))
      (t
       (values nil :wait)))))

(defun %terminal-input-parser-escape (parser)
  (let* ((buffer (terminal-input-parser-buffer parser))
         (length (length buffer)))
    (cond
      ((= length 1)
       (values nil :wait))
      ((char= (char buffer 1) #\[)
       (if (and (> length 2) (char= (char buffer 2) #\M))
           (cond
             ((>= length 6)
              (let ((event (%terminal-input-parser-x10-mouse-event buffer)))
                (setf (terminal-input-parser-buffer parser)
                      (subseq buffer 6))
                (values (or event
                            (make-custom-event
                             :terminal-sequence
                             (list :protocol :x10
                                   :bytes (map 'list #'char-code
                                               (subseq buffer 3 6)))))
                        :done)))
             ((> length (terminal-input-parser-max-sequence-length parser))
              (setf (terminal-input-parser-buffer parser) "")
              (values (make-custom-event
                       :input-overflow
                       (list :kind :escape-sequence
                             :limit (terminal-input-parser-max-sequence-length
                                     parser)))
                      :done))
             (t (values nil :wait)))
           (let ((final (position-if
                         (lambda (character)
                           (<= #x40 (char-code character) #x7e))
                         buffer :start 2)))
             (cond
               (final
                (let* ((body (subseq buffer 2 final))
                       (event (%terminal-input-parser-csi-event
                               parser body (char buffer final))))
                  (setf (terminal-input-parser-buffer parser)
                        (subseq buffer (1+ final)))
                  (values event :done)))
               ((> length (terminal-input-parser-max-sequence-length parser))
                (setf (terminal-input-parser-buffer parser) "")
                (values (make-custom-event
                         :input-overflow
                         (list :kind :escape-sequence
                               :limit (terminal-input-parser-max-sequence-length
                                       parser)))
                        :done))
               (t (values nil :wait))))))
      ((char= (char buffer 1) #\])
       (%terminal-input-parser-osc parser))
      ((char= (char buffer 1) #\O)
       (if (= length 2)
           (values nil :wait)
           (let ((event (%terminal-input-parser-key-for
                         (char buffer 2)
                         '())))
             (setf (terminal-input-parser-buffer parser)
                   (subseq buffer 3))
             (values (or event
                         (make-custom-event
                          :terminal-sequence
                          (list :body "" :final (char buffer 2))))
                     :done))))
      (t
       (let ((character (char buffer 1)))
         (setf (terminal-input-parser-buffer parser)
               (subseq buffer 2))
         (values (make-key-event character :modifiers '(:alt)) :done))))))

(defun %terminal-input-parser-paste-suffix-length (buffer marker)
  (let ((limit (min (length buffer) (1- (length marker)))))
    (loop for suffix from limit downto 0
          when (string= marker buffer
                       :start2 (- (length buffer) suffix)
                       :end2 (length buffer)
                       :end1 suffix)
            do (return suffix))))

(defun %terminal-input-parser-append-paste (parser text)
  (let ((new-length (+ (length (terminal-input-parser-paste-buffer parser))
                       (length text))))
    (unless (> new-length (terminal-input-parser-max-paste-length parser))
      (setf (terminal-input-parser-paste-buffer parser)
            (concatenate 'string
                         (terminal-input-parser-paste-buffer parser)
                         text))
      t)))

(defun %terminal-input-parser-drain-paste (parser events)
  (let ((marker (format nil "~C[201~~" (code-char 27)))
        (buffer (terminal-input-parser-buffer parser)))
    (let ((end (search marker buffer)))
      (cond
        (end
         (let ((accepted (%terminal-input-parser-append-paste
                          parser (subseq buffer 0 end))))
           (unless accepted
             (push (make-custom-event
                    :paste-overflow
                    (list :limit
                          (terminal-input-parser-max-paste-length parser)))
                   events))
           (setf (terminal-input-parser-buffer parser)
                 (subseq buffer (+ end (length marker)))
                 (terminal-input-parser-in-paste-p parser) nil)
           (when accepted
             (push (make-paste-event
                    (terminal-input-parser-paste-buffer parser))
                   events))
           (setf (terminal-input-parser-paste-buffer parser) "")
           events))
        (t
         (let* ((suffix (%terminal-input-parser-paste-suffix-length
                         buffer marker))
                (safe-length (- (length buffer) suffix)))
           (if (zerop safe-length)
               events
               (if (%terminal-input-parser-append-paste
                    parser (subseq buffer 0 safe-length))
                   (progn
                     (setf (terminal-input-parser-buffer parser)
                           (subseq buffer safe-length))
                     events)
                   (progn
                     (setf (terminal-input-parser-buffer parser) ""
                           (terminal-input-parser-in-paste-p parser) nil
                           (terminal-input-parser-paste-buffer parser) "")
                     (push (make-custom-event
                            :paste-overflow
                            (list :limit
                                  (terminal-input-parser-max-paste-length
                                   parser)))
                           events))))))))))

(defun %terminal-input-parser-control-event (character)
  (case (char-code character)
    (9 (make-key-event :tab))
    ((10 13) (make-key-event :enter))
    ((8 127) (make-key-event :backspace))
    ((1 2 3 4 5 6 7 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26)
     (make-key-event (code-char (+ 96 (char-code character)))
                     :modifiers '(:ctrl)))
    (otherwise (make-custom-event :control (char-code character)))))

(defun %terminal-input-parser-drain (parser)
  (let ((events '()))
    (loop while (plusp (length (terminal-input-parser-buffer parser))) do
      (if (terminal-input-parser-in-paste-p parser)
          (let ((before (terminal-input-parser-buffer parser)))
            (setf events (%terminal-input-parser-drain-paste parser events))
            (when (and (string= before (terminal-input-parser-buffer parser))
                       (terminal-input-parser-in-paste-p parser))
              (return)))
          (let ((buffer (terminal-input-parser-buffer parser))
                (character (char (terminal-input-parser-buffer parser) 0)))
            (cond
              ((char= character (code-char 27))
               (multiple-value-bind (event status)
                   (%terminal-input-parser-escape parser)
                 (when event (push event events))
                 (when (eq status :wait) (return))))
              ((%terminal-input-parser-plain-character-p character)
               (let ((end (or (position-if
                               (lambda (item)
                                 (not (%terminal-input-parser-plain-character-p
                                       item)))
                               buffer)
                              (length buffer))))
                 (push (make-text-input-event (subseq buffer 0 end)) events)
                 (setf (terminal-input-parser-buffer parser)
                       (subseq buffer end))))
              (t
               (setf (terminal-input-parser-buffer parser)
                     (subseq buffer 1))
               (push (%terminal-input-parser-control-event character)
                     events))))))
    (nreverse events)))

(defun terminal-input-parser-feed (parser input)
  "Feed a string or octet vector and return newly decoded events.

UTF-8 and terminal control sequences may be split across calls. Malformed
UTF-8 is represented by U+FFFD; oversized control sequences and pastes become
explicit custom events rather than growing without bound."
  (check-type parser terminal-input-parser)
  (cond
    ((stringp input)
     (setf (terminal-input-parser-buffer parser)
           (concatenate 'string (terminal-input-parser-buffer parser) input)))
    ((vectorp input)
     (loop for byte across input do
       (unless (and (integerp byte) (<= 0 byte 255))
         (error "Input vector contains non-octet ~S." byte)))
     (%terminal-input-parser-append-octets parser input))
    (t
     (error "Terminal input must be a string or vector, got ~S." input)))
  (%terminal-input-parser-drain parser))

(defun terminal-input-parser-flush (parser)
  "Flush buffered input at end-of-stream, preserving no incomplete state."
  (check-type parser terminal-input-parser)
  (when (terminal-input-parser-pending-octets parser)
    (setf (terminal-input-parser-buffer parser)
          (concatenate 'string (terminal-input-parser-buffer parser)
                       (string (code-char #xfffd)))
          (terminal-input-parser-pending-octets parser) '()))
  (let ((events (%terminal-input-parser-drain parser)))
    (if (terminal-input-parser-in-paste-p parser)
        (progn
          (unless (string= (terminal-input-parser-buffer parser) "")
            (%terminal-input-parser-append-paste
             parser (terminal-input-parser-buffer parser)))
          (setf (terminal-input-parser-buffer parser) ""
                (terminal-input-parser-in-paste-p parser) nil)
          (push (make-custom-event
                 :paste-incomplete
                 (terminal-input-parser-paste-buffer parser))
                events)
          (setf (terminal-input-parser-paste-buffer parser) "")
          (nreverse events))
        (if (plusp (length (terminal-input-parser-buffer parser)))
            (let ((buffer (terminal-input-parser-buffer parser)))
              (push (if (and (= (length buffer) 1)
                             (char= (char buffer 0) (code-char 27)))
                        (make-key-event :escape)
                        (make-custom-event :input-incomplete buffer))
                    events)
              (setf (terminal-input-parser-buffer parser) "")
              (nreverse events))
            events))))
