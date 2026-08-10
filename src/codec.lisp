(in-package #:cl-tui-kit/codec)

;;;; Optional integration with nerima-lisp's cl-codec-kit.  The core keeps
;;;; text as Lisp strings and cell content; this adapter is only for a backend
;;;; or application that explicitly needs UTF-8 octets.

(defun string-to-utf8-octets (string &key (start 0) end (errorp t))
  "Encode STRING as UTF-8 octets through CL-CODEC-KIT.

START and END follow the usual half-open string range convention.  ERRORP is
passed through unchanged to the codec package."
  (check-type string string)
  (cl-codec-kit:string-to-octets string
                                 :start start
                                 :end end
                                 :encoding :utf-8
                                 :errorp errorp))

(defun write-utf8 (string stream &key (start 0) end (errorp t))
  "Write STRING as UTF-8 octets to binary STREAM and return the octets.

STREAM must accept (UNSIGNED-BYTE 8) elements.  The function intentionally
does not change stream modes or terminal state."
  (let ((octets (string-to-utf8-octets string
                                       :start start
                                       :end end
                                       :errorp errorp)))
    (write-sequence octets stream)
    octets))
