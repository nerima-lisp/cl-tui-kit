(in-package #:cl-tui-kit/core)

;;;; Terminal input escape and protocol sequences

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
                             (char= (char buffer (1+ index)) #\\))
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
