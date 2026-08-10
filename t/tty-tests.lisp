(in-package #:cl-tui-kit/tests)

(deftest tty-size-validation-rejects-invalid-values (:tty)
  (is (cl-tui-kit/tty::%tty-size-valid-p 80 24))
  (is (not (cl-tui-kit/tty::%tty-size-valid-p nil 24)))
  (is (not (cl-tui-kit/tty::%tty-size-valid-p 80 nil)))
  (is (not (cl-tui-kit/tty::%tty-size-valid-p 0 24)))
  (is (not (cl-tui-kit/tty::%tty-size-valid-p 80 -1)))
  (is (not (cl-tui-kit/tty::%tty-size-valid-p 80 24.0))))

(deftest tty-backend-falls-back-and-refreshes-size (:tty)
  (let* ((size (make-size 7 3))
         (backend (make-tty-backend
                   :stream (make-string-output-stream)
                   :file-descriptor 999999
                   :size size)))
    (is-equal 7 (size-width (backend-size backend)))
    (is-equal 3 (size-height (backend-size backend)))
    (is-equal backend (tty-backend-refresh-size backend))
    (is-equal 7 (size-width (backend-size backend)))
    (is-equal 3 (size-height (backend-size backend)))))

(deftest tty-runtime-lifecycle-is-reusable (:tty)
  (let ((runtime (make-tty-runtime
                  :input-stream (make-string-input-stream "")
                  :raw-mode nil)))
    (is-equal runtime (tty-runtime-start runtime))
    (is (tty-runtime-started-p runtime))
    (is-equal runtime (tty-runtime-start runtime))
    (is (signals-error (tty-runtime-reset runtime)))
    (is-equal runtime (tty-runtime-stop runtime))
    (is-equal runtime (tty-runtime-close runtime))
    (is-equal runtime (tty-runtime-reset runtime))))

(deftest tty-runtime-closes-owned-input (:tty)
  (let ((runtime (make-tty-runtime
                  :input-stream (make-string-input-stream "")
                  :raw-mode nil
                  :close-input-p t)))
    (tty-runtime-start runtime)
    (is-equal runtime (tty-runtime-stop runtime))
    (is (tty-runtime-input-closed-p runtime))
    (is (signals-error (tty-runtime-start runtime)))
    (is (signals-error (tty-runtime-reset runtime)))))

(deftest tty-runtime-poll-drains-queued-events (:tty)
  (let ((runtime (make-tty-runtime
                  :input-stream (make-string-input-stream "")
                  :raw-mode nil)))
    (cl-tui-kit/tty::%tty-runtime-enqueue
     runtime (list (make-text-input-event "queued")))
    (multiple-value-bind (events status)
        (tty-runtime-poll runtime)
      (is-equal :events status)
      (is-equal 1 (length events))
      (is-equal "queued" (text-input-event-text (first events))))
    (is-equal nil (cl-tui-kit/tty::tty-runtime-queue runtime))))

(deftest tty-runtime-rejects-restart-after-eof (:tty)
  (let ((runtime (make-tty-runtime
                  :input-stream (make-string-input-stream "")
                  :raw-mode nil)))
    (multiple-value-bind (events status)
        (tty-runtime-poll runtime)
      (is-equal nil events)
      (is-equal :eof status))
    (is (signals-error (tty-runtime-start runtime)))
    (is-equal runtime (tty-runtime-reset runtime))
    (is (not (tty-runtime-eof-p runtime)))))

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
