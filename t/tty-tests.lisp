(in-package #:cl-tui-kit/tests)

(deftest tty-runtime-poll-normalizes-input (:tty)
  (let ((runtime (make-tty-runtime
                  :input-stream (make-string-input-stream "abc")
                  :raw-mode nil
                  :read-size 3
                  :eof-value :done)))
    (multiple-value-bind (events status)
      (tty-runtime-poll runtime)
      (is-equal :events status)
      (is-equal 3 (length events))
      (is-equal '(:text-input :text-input :text-input)
                (mapcar #'event-kind events))
      (is-equal '("a" "b" "c")
                (mapcar #'text-input-event-text events)))
    (multiple-value-bind (events status)
        (tty-runtime-poll runtime)
      (is-equal nil events)
      (is-equal :eof status))
    (is (tty-runtime-eof-p runtime))
    (is (not (tty-runtime-started-p runtime)))))

(deftest tty-runtime-poll-reports-pending-sequences (:tty)
  (let ((runtime (make-tty-runtime
                  :input-stream
                  (make-string-input-stream (string (code-char 27)))
                  :raw-mode nil
                  :read-size 1
                  :eof-value :done)))
    (multiple-value-bind (events status)
        (tty-runtime-poll runtime)
      (is-equal nil events)
      (is-equal :pending status)
      (is (tty-runtime-started-p runtime)))
    (multiple-value-bind (events status)
        (tty-runtime-poll runtime)
      (is-equal :events status)
      (is-equal 1 (length events))
      (is-equal :escape (key-event-key (first events))))
    (multiple-value-bind (events status)
        (tty-runtime-poll runtime)
      (is-equal nil events)
      (is-equal :eof status))
    (is (not (tty-runtime-started-p runtime)))))

(deftest tty-runtime-cps-cleanup-is-unconditional (:tty)
  (let ((runtime (make-tty-runtime
                  :input-stream (make-string-input-stream "")
                  :raw-mode nil)))
    (is-equal :completed
              (call-with-tty-runtime runtime (lambda () :completed)))
    (is (not (tty-runtime-started-p runtime))))
  (let ((runtime (make-tty-runtime
                  :input-stream (make-string-input-stream "")
                  :raw-mode nil)))
    (is (signals-error
         (with-tty-runtime (runtime)
           (error "expected TTY runtime failure"))))
    (is (not (tty-runtime-started-p runtime)))))

(deftest tty-runtime-event-source-reads-normalized-events (:tty)
  (let* ((runtime (make-tty-runtime
                   :input-stream (make-string-input-stream "z")
                   :raw-mode nil
                   :eof-value :done))
         (source (tty-runtime-event-source runtime))
         (event (funcall source)))
    (is-equal :text-input (event-kind event))
    (is-equal "z" (text-input-event-text event))
    (is-equal :done (funcall source))))
