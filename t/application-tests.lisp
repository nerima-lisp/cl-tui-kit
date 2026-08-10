(in-package #:cl-tui-kit/tests)

(deftest event-replay-resize-and-custom-event (:integration)
  (let* ((backend (make-test-backend :size (make-size 4 2)))
         (events (list (make-resize-event 8 3)
                       (make-custom-event :refresh :payload)))
         (surface nil))
    (dolist (event events)
      (test-backend-emit backend event)
      (case (event-kind event)
        (:resize
         (backend-resize backend
                         (resize-event-width event)
                         (resize-event-height event)))
        (:custom nil)))
    (setf surface (make-surface (size-width (backend-size backend))
                                (size-height (backend-size backend))))
    (surface-draw-text surface 0 0 "resized")
    (backend-present backend surface)
    (is-equal 2 (length (test-backend-recorded-events backend)))
    (is-equal 8 (surface-width (test-backend-last-frame backend)))
    (is-equal 3 (surface-height (test-backend-last-frame backend)))))

(deftest application-runtime-focus-and-events (:application)
  (let* ((backend (make-test-backend :size (make-size 12 4)))
         (button (make-button-widget "OK" :id :button))
         (input (make-input-widget :id :input))
         (root (make-widget :children (list button input)))
         (application (make-application :backend backend :root root
                                        :alternate-screen-p t
                                        :title "Demo")))
    (application-start application)
    (is (application-running-p application))
    (is (not (application-dirty-p application)))
    (is-equal 12 (surface-width (test-backend-last-frame backend)))
    (is-equal 4 (surface-height (test-backend-last-frame backend)))
    (is-equal 1 (count '(:begin-frame) (test-backend-operations backend)
                       :test #'equal))
    (is (member '(:enter-alternate) (test-backend-operations backend)
                :test #'equal))
    (is (member '(:title "Demo") (test-backend-operations backend)
                :test #'equal))
    (let ((operations (copy-list (test-backend-operations backend))))
      (application-start application)
      (is-equal operations (test-backend-operations backend)))
    (is-equal :button
              (focus-node-id
               (focus-tree-current (application-focus-tree application))))
    (is (null (application-step application)))
    (application-step application (make-key-event :tab))
    (is-equal :input
              (focus-node-id
               (focus-tree-current (application-focus-tree application))))
    (application-step application (make-text-input-event "x"))
    (is-equal "x" (input-widget-value input))
    (application-step application
                       (make-key-event :tab :modifiers '(:shift)))
    (is-equal :button
              (focus-node-id
               (focus-tree-current (application-focus-tree application))))
    (application-step application (make-resize-event 16 5))
    (is-equal 16 (size-width (backend-size backend)))
    (is-equal 5 (size-height (backend-size backend)))
    (application-step application (make-key-event :tab))
    (is-equal :input
              (focus-node-id
               (focus-tree-current (application-focus-tree application))))
    (is (test-backend-last-frame backend))
    (application-close application)
    (is (not (application-running-p application)))
    (let ((events (list (make-text-input-event "y") :eof)))
      (application-run application (lambda () (pop events)))
      (is-equal "xy" (input-widget-value input))
      (is (not (application-running-p application))))
    (setf (widget-rectangle button) (test-rectangle 0 0 5 1)
          (widget-rectangle input) (test-rectangle 0 1 5 1))
    (application-refresh-focus-tree application)
    (let ((action (application-dispatch-event
                   application (make-mouse-event 1 0))))
      (is-equal :activate (action-name action)))
    (is-equal :button
              (focus-node-id
               (focus-tree-current (application-focus-tree application))))
    (is (member '(:open) (test-backend-operations backend) :test #'equal))
    (is (member '(:close) (test-backend-operations backend) :test #'equal))))

(deftest application-tick-broadcast-reaches-descendants (:application)
  (let* ((backend (make-test-backend :size (make-size 24 2)))
         (center (make-notification-center
                  :rectangle (test-rectangle 0 0 24 1)))
         (root (make-widget :children (list center)))
         (application (make-application :backend backend :root root)))
    (notification-center-push center "expires" :expires-at 4)
    (let ((action (application-dispatch-event application
                                               (make-tick-event 4))))
      (is-equal :notifications-updated (action-name action))
      (is-equal action (application-last-action application)))
    (is (null (notification-center-notifications center)))))

(deftest common-widgets-and-horizontal-input (:widgets)
  (let* ((surface (make-surface 12 2))
         (button (make-button-widget "Run"
                                     :rectangle (make-rectangle 0 0 12 1)))
         (checkbox (make-checkbox-widget "Ready"
                                         :rectangle (make-rectangle 0 1 12 1)))
         (progress (make-progress-widget :value 5 :maximum 10 :label "50%"
                                         :rectangle (make-rectangle 0 0 12 1))))
    (widget-render button surface)
    (is (search "Run" (surface-string surface)))
    (let ((action (widget-handle-event button (make-key-event :enter))))
      (is-equal :activate (action-name action)))
    (is (not (checkbox-widget-checked-p checkbox)))
    (widget-render checkbox surface)
    (is (search "[ ] Ready" (surface-string surface)))
    (is-equal 9 (size-width (widget-preferred-size checkbox)))
    (let ((action (widget-handle-event checkbox (make-key-event :space))))
      (is (checkbox-widget-checked-p checkbox))
      (is-equal :toggle (action-name action)))
    (widget-render checkbox surface)
    (is (search "[X] Ready" (surface-string surface)))
    (is-equal :toggle
              (action-name (widget-handle-event checkbox
                                                 (make-key-event :enter))))
    (is (not (checkbox-widget-checked-p checkbox)))
    (is-equal :toggle
              (action-name (widget-handle-event checkbox
                                                 (make-key-event :return))))
    (is (checkbox-widget-checked-p checkbox))
    (widget-render progress surface)
    (is (search "50%" (surface-string surface)))
    (is-equal :progress
              (getf (widget-accessibility-tree progress) :role))
    (is-equal "50%"
              (getf (widget-accessibility-tree progress) :label))
    (is-equal 20 (size-width (widget-preferred-size progress))))
  (let* ((input (make-input-widget
                 :value "abcdef"
                 :rectangle (make-rectangle 0 0 4 1)))
         (surface (make-surface 4 1)))
    (widget-render input surface)
    (is-equal 3 (input-widget-scroll-offset input))
    (is-equal "def " (surface-string surface))
    (widget-handle-event input (make-key-event :home))
    (is-equal 0 (input-widget-cursor input))
    (is (widget-cursor-position input))
    (is-equal 0 (input-widget-scroll-offset input))
    (widget-handle-event input (make-key-event :end))
    (is-equal 6 (input-widget-cursor input))
    (is (widget-cursor-position input))
    (is-equal 3 (input-widget-scroll-offset input))
    (let ((zero-width (make-input-widget
                       :value "x"
                       :rectangle (make-rectangle 0 0 0 1))))
      (is (null (widget-cursor-position zero-width))))))

(deftest widget-protocol-and-basic-presentations (:widgets)
  (let* ((child (make-text-widget 42 :accessible-label "42"))
         (root (make-widget :id :root :focusable-p t :enabled-p nil
                            :children (list child)))
         (rectangle (test-rectangle 1 2 8 3))
         (surface (make-surface 12 6))
         (event (make-key-event :enter))
         (action (activate-action :done)))
    (is (widget-active-p root))
    (is-equal (list child) (widget-interactive-children root))
    (is (not (widget-capture-event-p root event)))
    (is (null (widget-cursor-position root)))
    (is (null (widget-accessibility-state root)))
    (is (null (widget-handle-event root event)))
    (is (eq action (widget-handle-child-action root action)))
    (is (eq root (widget-layout root rectangle)))
    (is-equal 1 (rectangle-x (widget-rectangle child)))
    (is-equal 2 (rectangle-y (widget-rectangle child)))
    (render-widget root surface)
    (is (search "42" (surface-string surface)))
    (is (null (handle-widget-event root event)))
    (let ((info (widget-accessibility-tree root)))
      (is-equal :root (getf info :id))
      (is-equal 1 (length (getf info :children)))
      (is-equal "42" (getf (first (getf info :children)) :label))))

  (let* ((text (make-text-widget 42
                                 :rectangle (test-rectangle 0 0 8 1)))
         (empty-box (make-box-widget nil
                                     :rectangle (test-rectangle 0 0 4 3)))
         (boxed (make-box-widget text
                                 :rectangle (test-rectangle 0 0 8 3)))
         (horizontal (make-divider-widget
                      :rectangle (test-rectangle 0 0 4 1)))
         (vertical (make-divider-widget :orientation :vertical
                                        :rectangle (test-rectangle 0 0 1 3)))
         (surface (make-surface 8 3)))
    (is-equal 2 (size-width (widget-preferred-size text)))
    (is-equal 1 (size-height (widget-preferred-size text)))
    (is (typep (widget-preferred-size empty-box) 'size))
    (render-widget text surface)
    (is (search "42" (surface-string surface)))
    (widget-layout boxed (test-rectangle 0 0 8 3))
    (is-equal 2 (rectangle-x (widget-rectangle text)))
    (is-equal 2 (rectangle-y (widget-rectangle text)))
    (widget-render boxed surface)
    (widget-render horizontal surface)
    (widget-render vertical surface)
    (is (search "─" (surface-string surface)))
    (is (search "│" (surface-string surface)))
    (is (signals-error (make-divider-widget :orientation :diagonal))))

  (let* ((callback-widget nil)
         (callback-button
           (make-button-widget
            "Callback"
            :action (lambda (widget)
                      (setf callback-widget widget)
                      (activate-action :callback widget))))
         (symbol-button (make-button-widget "Save" :action :save))
         (existing-action (activate-action :existing))
         (existing-button (make-button-widget "Existing"
                                              :action existing-action))
         (disabled (make-button-widget "Disabled" :enabled-p nil)))
    (let ((action (widget-handle-event callback-button
                                       (make-key-event :enter))))
      (is (eq callback-button callback-widget))
      (is-equal :activate (action-name action))
      (is-equal :callback (action-payload action))
      (is-equal callback-button (action-source action)))
    (is-equal :save
              (action-name (widget-handle-event symbol-button
                                                 (make-key-event :space))))
    (is (eq existing-action
            (widget-handle-event existing-button (make-key-event :return))))
    (is-equal :activate
              (action-name (widget-handle-event callback-button
                                                 (make-mouse-event 0 0))))
    (is (null (widget-handle-event callback-button (make-key-event :escape))))
    (is (null (handle-widget-event disabled (make-key-event :enter))))
    (is-equal :button
              (getf (widget-accessibility-tree callback-button) :role)))

  (let* ((checkbox (make-checkbox-widget "Ready"))
         (surface (make-surface 12 1))
         (zero-progress (make-progress-widget :value -1 :maximum 0
                                               :rectangle (test-rectangle 0 0 12 1))))
    (is-equal :checkbox
              (getf (widget-accessibility-tree checkbox) :role))
    (is-equal nil (getf (widget-accessibility-state checkbox) :checked-p))
    (is-equal :toggle
              (action-name (widget-handle-event
                            checkbox (make-mouse-event 0 0))))
    (is (checkbox-widget-checked-p checkbox))
    (widget-render zero-progress surface)
    (is-equal 0 (progress-widget-maximum zero-progress))
    (is-equal 0 (getf (widget-accessibility-state zero-progress) :maximum))
    (is (signals-error (make-progress-widget :value "bad")))
    (is (signals-error (make-progress-widget :maximum -1))))

  (let* ((view (make-text-view-widget
                (format nil "alpha~%bravo~%charlie")
                :wrap-p nil
                :rectangle (test-rectangle 0 0 6 2)))
         (wrapped (make-text-view-widget "abcdef"
                                         :rectangle (test-rectangle 0 0 2 2)))
         (surface (make-surface 6 2)))
    (is-equal 7 (size-width (widget-preferred-size view)))
    (is-equal 3 (size-height (widget-preferred-size view)))
    (is-equal 0 (text-view-widget-find view "alpha"))
    (is-equal "alpha" (text-view-widget-search-query view))
    (is (null (text-view-widget-find view "")))
    (is (null (text-view-widget-find view "missing")))
    (text-view-widget-scroll-to view most-positive-fixnum)
    (is-equal 1 (text-view-widget-offset view))
    (text-view-widget-scroll-by view -100)
    (is-equal 0 (text-view-widget-offset view))
    (widget-render view surface)
    (is (search "alpha" (surface-string surface)))
    (is-equal :move
              (action-name (widget-handle-event view (make-key-event :down))))
    (is-equal :move
              (action-name (widget-handle-event view (make-key-event :page-down))))
    (is-equal :move
              (action-name (widget-handle-event view (make-key-event :page-up))))
    (is-equal :move
              (action-name (widget-handle-event view (make-key-event :home))))
    (is-equal :move
              (action-name (widget-handle-event view (make-key-event :end))))
    (is-equal :move
              (action-name (widget-handle-event
                            view (make-mouse-event 0 0 :button :wheel-up))))
    (is-equal :move
              (action-name (widget-handle-event
                            view (make-mouse-event 0 0 :button :scroll-down))))
    (is-equal :find
              (action-name (widget-handle-event
                            view (make-custom-event :find "charlie"))))
    (is-equal 1 (text-view-widget-offset view))
    (widget-render wrapped surface)
    (is (search "ab" (surface-string surface)))
    (is-equal :document
              (getf (widget-accessibility-tree wrapped) :role))))
