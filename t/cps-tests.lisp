(in-package #:cl-tui-kit/tests)

(deftest resource-scopes-restore-state (:cps)
  (let* ((surface (make-surface 6 3))
         (original-clip (surface-clip surface))
         (inner-clip (make-rectangle 1 1 3 1)))
    (is-equal :completed
              (call-with-surface-clip
               surface inner-clip
               (lambda ()
                 (is-equal inner-clip (surface-clip surface))
                 :completed)))
    (is-equal original-clip (surface-clip surface))
    (is-equal :escaped
              (block escaped
                (call-with-surface-clip
                 surface inner-clip
                 (lambda ()
                   (return-from escaped :escaped)))))
    (is-equal original-clip (surface-clip surface))
    (with-surface-clip (surface inner-clip)
      (is-equal inner-clip (surface-clip surface)))
    (is-equal original-clip (surface-clip surface))))

(deftest application-session-closes-on-return (:cps)
  (let* ((backend (make-test-backend :size (make-size 8 2)))
         (application (make-application :backend backend
                                        :root (make-widget)
                                        :alternate-screen-p nil)))
    (is-equal :completed
              (call-with-application-session
               application
               (lambda ()
                 (is (application-running-p application))
                 :completed)))
    (is (not (application-running-p application)))
    (is (member '(:open) (test-backend-operations backend) :test #'equal))
    (is (member '(:close) (test-backend-operations backend) :test #'equal))
    (with-application-session (application)
      (is (application-running-p application)))
    (is (not (application-running-p application)))))

(deftest application-session-closes-on-nonlocal-exit (:cps)
  (let* ((backend (make-test-backend :size (make-size 8 2)))
         (application (make-application :backend backend
                                        :root (make-widget)
                                        :alternate-screen-p nil)))
    (is-equal :escaped
              (block escaped
                (call-with-application-session
                 application
                 (lambda ()
                   (return-from escaped :escaped)))))
    (is (not (application-running-p application)))
    (is (member '(:close) (test-backend-operations backend) :test #'equal))))

(deftest application-render-and-step-continue-after-frame (:cps)
  (let* ((backend (make-test-backend :size (make-size 8 2)))
         (application (make-application :backend backend
                                        :root (make-widget)
                                        :alternate-screen-p nil))
         (rendered-application nil)
         (stepped-action :unset))
    (is-equal :rendered
              (application-render/k
               application
               (lambda (rendered)
                 (setf rendered-application rendered)
                 :rendered)))
    (is (eq application rendered-application))
    (is (not (application-dirty-p application)))
    (application-invalidate application)
    (is-equal :stepped
              (application-step/k
               application nil
               (lambda (action)
                 (setf stepped-action action)
                 :stepped)))
    (is (null stepped-action))
    (is (not (application-dirty-p application)))))

(deftest application-session-rejects-non-function-continuation (:cps)
  (let* ((backend (make-test-backend :size (make-size 8 2)))
         (application (make-application :backend backend
                                        :root (make-widget)
                                        :alternate-screen-p nil)))
    (is (signals-error
         (call-with-application-session application :not-a-function)))
    (is (null (test-backend-operations backend)))
    (is (not (application-running-p application)))))

(deftest application-event-routing-has-safe-no-op-leaves (:cps)
  (let* ((backend (make-test-backend :size (make-size 8 2)))
         (child (make-widget))
         (closed-modal (make-modal-widget (make-widget) :open-p nil))
         (root (make-widget :rectangle (make-rectangle 0 0 4 1)
                            :children (list child closed-modal)))
         (application (make-application :backend backend
                                        :root root
                                        :alternate-screen-p nil)))
    (is (null (application-dispatch-event application (make-tick-event))))
    (is (null (application-dispatch-event application
                                          (make-mouse-event 7 1))))))

(cl-weave:it-property "normalizing modifiers is idempotent"
  ((modifiers (cl-weave:gen-list
               (cl-weave:gen-member '(:shift :control :meta :alt :super))
               :min-length 0
               :max-length 8)))
  (is-equal (normalize-modifiers modifiers)
            (normalize-modifiers (normalize-modifiers modifiers))))
