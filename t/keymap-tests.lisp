(in-package #:cl-tui-kit/tests)

(deftest hierarchical-keymaps-and-sequences (:keymap)
  (let* ((parent (make-keymap :name :parent))
         (child (make-keymap :name :child :parent parent))
         (state (make-keymap-state)))
    (bind-key parent #\q (custom-action :quit))
    (bind-key child (list #\g #\g) (custom-action :top))
    (let ((result (keymap-dispatch child state (test-key #\g))))
      (is-equal :prefix (keymap-result-status result)))
    (let ((result (keymap-dispatch child state (test-key #\g))))
      (is-equal :handled (keymap-result-status result))
      (is-equal :top (action-name (keymap-result-action result))))
    (let ((result (dispatch-keymaps (list child parent) state
                                    (test-key #\q))))
      (is-equal :quit (action-name (keymap-result-action result))))))

(deftest parent-owned-keymap-sequences (:keymap)
  (let* ((parent (make-keymap :name :parent))
         (child (make-keymap :name :child :parent parent))
         (state (make-keymap-state)))
    (bind-key parent (list #\g #\q) (custom-action :parent-sequence))
    (is-equal :prefix
              (keymap-result-status
               (keymap-dispatch child state (test-key #\g) :time 1)))
    (is-equal :parent-sequence
              (action-name
               (keymap-result-action
                (keymap-dispatch child state (test-key #\q) :time 2))))
    (is (not (keymap-state-prefix-active-p state)))))

(deftest declarative-keymaps-and-continuation-protocols (:protocol)
  (let* ((keymap (make-declarative-test-keymap))
         (state (make-keymap-state)))
    (is-equal :activate
              (action-name
               (keymap-result-action
                (keymap-dispatch keymap state (test-key #\x)))))
    (is-equal :prefix
              (keymap-result-status
               (keymap-dispatch keymap state (test-key #\g))))
    (is-equal :top
              (action-name
               (keymap-result-action
                (keymap-dispatch keymap state (test-key #\g))))))
  (let ((handled 0)
        (unhandled 0)
        (event (make-custom-event :refresh)))
    (is-equal :handled
              (dispatch-event/k
               (list (lambda (current next)
                       (declare (ignore current next))
                       nil)
                     (lambda (current next)
                       (declare (ignore current next))
                       :handled))
               event
               (lambda (value)
                 (incf handled)
                 value)
               :unhandled-k (lambda (current)
                              (declare (ignore current))
                              (incf unhandled)
                              :unhandled)))
    (is-equal 1 handled)
    (is-equal 0 unhandled)
    (is-equal :unhandled
              (dispatch-event/k
               (list (lambda (current next)
                       (declare (ignore current))
                       (funcall next)))
               event
               (lambda (value)
                 (declare (ignore value))
                 (incf handled)
                 :unexpected)
               :unhandled-k (lambda (current)
                              (declare (ignore current))
                              (incf unhandled)
                              :unhandled)))
    (is-equal 1 handled)
    (is-equal 1 unhandled))
  (let* ((backend (make-test-backend :size (make-size 4 1)))
         (surface (make-surface 4 1)))
    (cl-weave:with-continuation-result (presented next calledp)
        (present-frame/k backend surface #'next)
      (is calledp)
      (is-equal 4 (surface-width presented)))
    (is (test-backend-last-frame backend))))

(deftest vi-like-modes (:keymap-modes)
  (let* ((map (vi-like-keymap))
         (state (make-keymap-state)))
    (is-equal :prefix
              (keymap-result-status
               (keymap-dispatch map state (test-key #\g))))
    (is-equal :enter-normal-mode
              (action-name
               (keymap-result-action
                (keymap-dispatch map state (test-key #\g)))))
    (set-keymap-mode map :insert)
    (is-equal :enter-normal-mode
              (action-name
               (keymap-result-action
                (keymap-dispatch map state (test-key :escape)))))
    (set-keymap-mode map :normal)
    (is-equal :scroll-down-half-page
              (action-name
               (keymap-result-action
                (keymap-dispatch map state (test-key #\d :ctrl)))))))

(deftest keymap-modes-timeouts-retry-and-unbinding (:keymap-modes)
  (let* ((parent (make-keymap :name :parent))
         (child (make-keymap :name :child :parent parent))
         (state (make-keymap-state)))
    (bind-key parent #\q (custom-action :parent))
    (bind-key child (list #\g #\g) (custom-action :double))
    (bind-key child #\z (custom-action :z))
    (is-equal :prefix
              (keymap-result-status
               (keymap-dispatch child state (test-key #\g) :time 10)))
    (let ((result (keymap-dispatch child state (test-key #\z) :time 11)))
      (is-equal :handled (keymap-result-status result))
      (is-equal :z (action-name (keymap-result-action result))))
    (is (not (keymap-state-prefix-active-p state)))
    (is-equal :parent
              (action-name
               (keymap-result-action
                (keymap-dispatch child state (test-key #\q)))))
    (let ((mode-map (define-keymap-mode child :insert :inherit-parent nil)))
      (bind-key child #\i (custom-action :insert) :mode :insert)
      (set-keymap-mode child :insert)
      (is (eq mode-map (keymap-mode-map child)))
      (is-equal :insert
                (action-name
                 (keymap-result-action
                  (keymap-dispatch child state (test-key #\i))))))
    (unbind-key child #\i :mode :insert)
    (is-equal :unhandled
              (keymap-result-status
               (keymap-dispatch child state (test-key #\i)))))
  (let* ((seen nil)
         (keymap (make-keymap
                  :prefix-timeout
                  (lambda (pending event)
                    (setf seen (list pending event))
                    (custom-action :timeout))))
         (state (make-keymap-state :time 10)))
    (bind-key keymap (list #\g #\g) (custom-action :double))
    (is-equal :prefix
              (keymap-result-status
               (keymap-dispatch keymap state (test-key #\g) :time 10)))
    (let ((result (keymap-expire-prefix keymap state (test-key #\x))))
      (is-equal :timeout (keymap-result-status result))
      (is-equal :timeout (action-name (keymap-result-action result)))
      (is-equal 1 (length (first seen)))
      (is-equal #\x (key-event-key (second seen))))
    (is (not (keymap-state-prefix-active-p state))))
  (let ((keymap (make-keymap)))
    (bind-key keymap #\f
              (lambda (event)
                (custom-action :function (key-event-key event))))
    (is-equal :function
              (action-name
               (keymap-result-action
                (keymap-dispatch keymap (make-keymap-state)
                                 (test-key #\f)))))
    (is (signals-error (make-keymap :prefix-timeout :invalid)))
    (is (signals-error (set-keymap-prefix-timeout keymap :invalid)))
    (is (signals-error (set-keymap-mode keymap "insert"))))
  (let* ((specific (make-keymap :name :specific))
         (fallback (make-keymap :name :fallback))
         (state (make-keymap-state)))
    (bind-key specific (list (cons #\x '(:ctrl)))
              (custom-action :modified))
    (bind-key fallback #\q (custom-action :fallback))
    (is-equal :modified
              (action-name
               (keymap-result-action
                (keymap-dispatch specific state (test-key #\x :ctrl)))))
    (is-equal :fallback
              (action-name
               (keymap-result-action
               (dispatch-keymaps (list specific fallback)
                                  state
                                  (test-key #\q)))))))

(deftest keymap-unhandled-retry-and-named-variants (:keymap)
  (let* ((keymap (make-keymap))
         (state (make-keymap-state)))
    (bind-key keymap (list #\g #\g) (custom-action :double))
    (is-equal :prefix
              (keymap-result-status
               (keymap-dispatch keymap state (test-key #\g))))
    (is-equal :unhandled
              (keymap-result-status
               (keymap-dispatch keymap state (test-key #\x))))
    (is (not (keymap-state-prefix-active-p state)))
    (is-equal :unhandled
              (keymap-result-status
               (dispatch-keymaps (list (make-keymap) (make-keymap))
                                 state
                                 (test-key #\x)))))
  (is-equal :named (keymap-name (vi-like-keymap :name :named))))
