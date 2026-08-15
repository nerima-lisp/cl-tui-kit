(in-package #:cl-tui-kit/core)

;;;; Incremental terminal input drain

;;; All accesses in this file are internal to the state machine and go
;;; directly through the raw struct accessors (TERMINAL-INPUT-PARSER-%BUFFER
;;; and so on) defined in input-parser-model.lisp, with no wrapper layer in
;;; between; the plain TERMINAL-INPUT-PARSER-* names are public, read-only,
;;; and hand back a defensive copy where the slot is a string or list.

(defun %terminal-input-parser-paste-suffix-length (buffer marker)
  (let ((limit (min (length buffer) (1- (length marker)))))
    (loop for suffix from limit downto 0
          when (string= marker buffer
                       :start2 (- (length buffer) suffix)
                       :end2 (length buffer)
                       :end1 suffix)
            do (return suffix))))

(defun %terminal-input-parser-append-paste (parser text)
  (let ((new-length (+ (length (terminal-input-parser-%paste-buffer parser))
                       (length text))))
    (unless (> new-length (terminal-input-parser-max-paste-length parser))
      (setf (terminal-input-parser-%paste-buffer parser)
            (concatenate 'string
                         (terminal-input-parser-%paste-buffer parser)
                         text))
      t)))

(defun %terminal-input-parser-drain-paste (parser events)
  (let ((marker (format nil "~C[201~~" (code-char 27)))
        (buffer (terminal-input-parser-%buffer parser)))
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
           (setf (terminal-input-parser-%buffer parser)
                 (subseq buffer (+ end (length marker)))
                 (terminal-input-parser-%in-paste-p parser) nil)
           (when accepted
             (push (make-paste-event
                    (terminal-input-parser-%paste-buffer parser))
                   events))
           (setf (terminal-input-parser-%paste-buffer parser) "")
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
                     (setf (terminal-input-parser-%buffer parser)
                           (subseq buffer safe-length))
                     events)
                   (progn
                     (setf (terminal-input-parser-%buffer parser) ""
                           (terminal-input-parser-%in-paste-p parser) nil
                           (terminal-input-parser-%paste-buffer parser) "")
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
    (loop while (plusp (length (terminal-input-parser-%buffer parser))) do
      (if (terminal-input-parser-%in-paste-p parser)
          (let ((before (terminal-input-parser-%buffer parser)))
            (setf events (%terminal-input-parser-drain-paste parser events))
            (when (and (string= before (terminal-input-parser-%buffer parser))
                       (terminal-input-parser-%in-paste-p parser))
              (return)))
          (let ((buffer (terminal-input-parser-%buffer parser))
                (character (char (terminal-input-parser-%buffer parser) 0)))
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
                 (setf (terminal-input-parser-%buffer parser)
                       (subseq buffer end))))
              (t
               (setf (terminal-input-parser-%buffer parser)
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
     (setf (terminal-input-parser-%buffer parser)
           (concatenate 'string (terminal-input-parser-%buffer parser) input)))
    ((vectorp input)
     (loop for byte across input do
       (unless (and (integerp byte) (<= 0 byte 255))
         (error 'invalid-range-error
                :context 'byte
                :datum byte
                :expected "an octet (an integer from 0 to 255)")))
     (%terminal-input-parser-append-octets parser input))
    (t
     (error 'invalid-type-error
            :context 'input
            :datum (bounded-datum input)
            :expected-type '(or string vector))))
  (%terminal-input-parser-drain parser))

(defun terminal-input-parser-flush (parser)
  "Flush buffered input at end-of-stream, preserving no incomplete state."
  (check-type parser terminal-input-parser)
  (when (terminal-input-parser-%pending-octets parser)
    (setf (terminal-input-parser-%buffer parser)
          (concatenate 'string (terminal-input-parser-%buffer parser)
                       (string (code-char #xfffd)))
          (terminal-input-parser-%pending-octets parser) '()))
  (let ((events (%terminal-input-parser-drain parser)))
    (if (terminal-input-parser-%in-paste-p parser)
        (progn
          (unless (string= (terminal-input-parser-%buffer parser) "")
            (%terminal-input-parser-append-paste
             parser (terminal-input-parser-%buffer parser)))
          (setf (terminal-input-parser-%buffer parser) ""
                (terminal-input-parser-%in-paste-p parser) nil)
          (push (make-custom-event
                 :paste-incomplete
                 (terminal-input-parser-%paste-buffer parser))
                events)
          (setf (terminal-input-parser-%paste-buffer parser) "")
          (nreverse events))
        (if (plusp (length (terminal-input-parser-%buffer parser)))
            (let ((buffer (terminal-input-parser-%buffer parser)))
              (push (if (and (= (length buffer) 1)
                             (char= (char buffer 0) (code-char 27)))
                        (make-key-event :escape)
                        (make-custom-event :input-incomplete buffer))
                    events)
              (setf (terminal-input-parser-%buffer parser) "")
              (nreverse events))
            events))))
