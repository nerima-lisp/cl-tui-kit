(in-package #:cl-tui-kit/core)

;;;; Terminal input encoding helpers

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
            for second = (char text (1+ index))
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
                         (not (or third-value third-padding-p))
                         (not (or fourth-value fourth-padding-p))
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
