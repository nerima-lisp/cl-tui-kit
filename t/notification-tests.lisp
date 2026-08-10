(in-package #:cl-tui-kit/tests)

(deftest notification-center-lifecycle (:widgets)
  (let* ((center (make-notification-center
                  :max-visible 2 :placement :top
                  :rectangle (test-rectangle 0 0 24 2)))
         (old (notification-center-push center "old"
                                        :id :old :expires-at 2))
         (new (notification-center-push
               center (make-notification "new" :id :new :level :warning)))
         (surface (make-surface 24 2)))
    (is-equal :old (notification-id old))
    (is-equal :new (notification-id new))
    (is-equal 2 (length (notification-center-notifications center)))
    (widget-render center surface)
    (is (search "[WARNING] new" (surface-string surface)))
    (let ((info (widget-accessibility-tree center)))
      (is-equal :status (getf info :role))
      (is-equal 2 (getf (getf info :state) :count)))
    (let ((action (handle-widget-event center (make-mouse-event 0 0))))
      (is-equal :close (action-name action))
      (is-equal :new (action-payload action)))
    (is-equal 1 (notification-center-tick center 2))
    (notification-center-push center "soon" :id :soon :expires-at 3)
    (is-equal :notifications-updated
              (action-name (handle-widget-event center (make-tick-event 3))))
    (notification-center-push center "manual" :id :manual)
    (is-equal :close
              (action-name
               (handle-widget-event center (make-custom-event :dismiss :manual))))
    (is-equal 0 (length (notification-center-notifications center)))
    (is (eq center (notification-center-clear center))))
  (let* ((center (make-notification-center
                  :placement :bottom :rectangle (test-rectangle 0 0 24 2)))
         (surface (make-surface 24 2)))
    (notification-center-push center "bottom" :id :bottom)
    (widget-render center surface)
    (is (search "bottom" (surface-string surface))))
  (is (signals-error (make-notification-center :max-visible 0)))
  (is (signals-error (make-notification-center :placement :middle))))
