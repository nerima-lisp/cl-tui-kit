(in-package #:cl-tui-kit/tests)

(deftest codec-encodes-utf8-with-ranges (:codec)
  (is-equal '(65 227 129 130)
            (coerce (string-to-utf8-octets "Aあ") 'list))
  (is-equal '(227 129 130)
            (coerce (string-to-utf8-octets "Aあ" :start 1) 'list))
  (is-equal '(65)
            (coerce (string-to-utf8-octets "Aあ" :end 1) 'list))
  (is-equal '()
            (coerce (string-to-utf8-octets "Aあ" :start 1 :end 1)
                    'list)))

(deftest codec-writes-binary-utf8 (:codec)
  (let* ((octets (string-to-utf8-octets "Aあ"))
         (path (merge-pathnames
                (format nil "cl-tui-kit-utf8-~A.bin"
                        (symbol-name (gensym "TEST-")))
                (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (with-open-file (stream path
                                   :direction :output
                                   :element-type '(unsigned-byte 8)
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (is-equal (coerce octets 'list)
                       (coerce (write-utf8 "Aあ" stream) 'list)))
           (with-open-file (stream path
                                   :direction :input
                                   :element-type '(unsigned-byte 8))
             (let ((actual (make-array (length octets)
                                       :element-type '(unsigned-byte 8))))
               (is-equal (length octets) (read-sequence actual stream))
               (is-equal (coerce octets 'list)
                         (coerce actual 'list)))))
      (when (probe-file path)
        (delete-file path)))))
