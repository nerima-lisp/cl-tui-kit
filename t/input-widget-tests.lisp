(in-package #:cl-tui-kit/tests)

(deftest input-selection-history-and-unicode (:widgets)
  (let ((input (make-input-widget
                :value "one two"
                :rectangle (make-rectangle 0 0 12 1))))
    (widget-handle-event input (test-key :home))
    (widget-handle-event input (test-key :right :ctrl))
    (is-equal 3 (input-widget-cursor input))
    (widget-handle-event input (test-key :right :alt))
    (is-equal 7 (input-widget-cursor input))
    (widget-handle-event input (test-key :left :ctrl))
    (is-equal 4 (input-widget-cursor input))

    (widget-handle-event input (test-key :home))
    (widget-handle-event input (test-key :right :shift))
    (is-equal "o" (input-widget-selected-text input))
    (is-equal 0 (input-widget-selection-start input))
    (is-equal 1 (input-widget-selection-end input))
    (widget-handle-event input (make-text-input-event "X"))
    (is-equal "Xne two" (input-widget-value input))
    (is-equal 1 (input-widget-cursor input))
    (widget-handle-event input (test-key :z :ctrl))
    (is-equal "one two" (input-widget-value input))
    (is-equal "o" (input-widget-selected-text input))
    (widget-handle-event input (test-key :y :ctrl))
    (is-equal "Xne two" (input-widget-value input))

    (widget-handle-event input (test-key :home))
    (widget-handle-event input (test-key :right :shift))
    (widget-handle-event input (test-key :backspace))
    (is-equal "ne two" (input-widget-value input))
    (widget-handle-event input (test-key :z :ctrl))
    (is-equal "X" (input-widget-selected-text input))
    (widget-handle-event input (test-key :y :ctrl))
    (is-equal "ne two" (input-widget-value input)))
  (let* ((combining (format nil "a~Cb" (code-char #x0301)))
         (input (make-input-widget :value combining
                                   :rectangle (make-rectangle 0 0 8 1))))
    (widget-handle-event input (test-key :home))
    (widget-handle-event input (test-key :right))
    (is-equal 2 (input-widget-cursor input))
    (widget-handle-event input (test-key :right))
    (is-equal 3 (input-widget-cursor input))
    (widget-handle-event input (test-key :left))
    (is-equal 2 (input-widget-cursor input))))

(deftest composite-form-and-modal-lifecycle (:composite-widgets)
  (let* ((name (make-input-widget :id :name :value "Ada"))
         (agree (make-checkbox-widget "Agree" :id :agree))
         (submitted nil)
         (form (make-form-widget
                (list name agree)
                :rectangle (test-rectangle 0 0 24 4)
                :validator (lambda (values form)
                             (declare (ignore form))
                             (unless (cdr (assoc :agree values))
                               (list "Agreement is required")))
                :submit-action (lambda (values form)
                                 (declare (ignore form))
                                 (setf submitted values)
                                 nil))))
    (is-equal "Ada" (cdr (assoc :name (form-widget-values form))))
    (is (not (form-widget-validate form)))
    (is-equal :validation-error
              (action-name (form-widget-submit form)))
    (widget-handle-event agree (test-key :space))
    (is (form-widget-validate form))
    (is-equal :submit (action-name (form-widget-submit form)))
    (is submitted)
    (let ((tree (widget-accessibility-tree form)))
      (is-equal :form (getf tree :role))
      (is-equal 2 (length (getf tree :children))))
    (let* ((button (make-button-widget "OK" :id :ok))
           (modal (make-modal-widget
                   form
                   :rectangle (test-rectangle 0 0 30 10)
                   :open-p t
                   :buttons (list button)
                   :outside-close-p t)))
      (widget-layout modal (test-rectangle 0 0 30 10))
      (setf (checkbox-widget-checked-p agree) nil)
      (let ((action (widget-handle-event modal (test-key :enter))))
        (is-equal :validation-error (action-name action))
        (is (modal-widget-open-p modal)))
      (setf (checkbox-widget-checked-p agree) t)
      (let ((action (widget-handle-event modal (test-key :enter))))
        (is-equal :submit (action-name action))
        (is (not (modal-widget-open-p modal)))
        (is-equal :submit (modal-widget-close-reason modal)))
      (modal-widget-open modal)
      (let* ((button-area (widget-rectangle button))
             (action (widget-handle-event
                      modal
                      (make-mouse-event (rectangle-x button-area)
                                        (rectangle-y button-area)
                                        :button :left))))
        (is-equal :activate (action-name action))
        (is-equal "OK" (modal-widget-result modal))
        (is-equal :button (modal-widget-close-reason modal)))
      (modal-widget-open modal)
      (let* ((root (make-box-widget
                    modal :rectangle (test-rectangle 0 0 30 10)))
             (button-area (progn
                            (widget-layout root (test-rectangle 0 0 30 10))
                            (widget-rectangle button)))
             (action (dispatch-widget-event
                      root
                      (make-mouse-event (rectangle-x button-area)
                                        (rectangle-y button-area)
                                        :button :left)
                      button)))
        (is-equal :activate (action-name action))
        (is (not (modal-widget-open-p modal)))
        (is-equal :button (modal-widget-close-reason modal)))
      (modal-widget-open modal)
      (is-equal :close
                (action-name (widget-handle-event
                              modal
                              (make-key-event :escape))))
      (is-equal :escape (modal-widget-close-reason modal))
      (modal-widget-open modal)
      (is-equal :close
                (action-name (widget-handle-event
                              modal
                              (make-mouse-event 0 0 :button :left))))
      (is-equal :outside (modal-widget-close-reason modal)))))

(deftest composite-data-widgets-handle-viewport-edges (:composite-widgets)
  (let ((menu (make-menu-widget
               (list (make-menu-item "Open" :key :open))
               :open-p t)))
    (is-equal :close
              (action-name (widget-handle-event menu (make-key-event :escape)))))
  (let* ((columns (list (make-table-column "Name" :width 5)
                        (make-table-column "Value" :width 4)))
         (rows (list (list "zero" "0") (list "one" "1")
                     (list "two" "2") (list "three" "3")))
         (table (make-table-widget
                 columns rows :selected-row 0
                 :rectangle (test-rectangle 0 0 12 3)))
         (surface (make-surface 12 3)))
    (widget-layout table (test-rectangle 0 0 12 3))
    (table-widget-select-row table 3)
    (is-equal 2 (table-widget-row-offset table))
    (widget-render table surface)
    (is (search "three" (surface-string surface)))
    (let ((action (widget-handle-event
                   table (make-mouse-event 5 2 :button :left))))
      (is-equal :select (action-name action))
      (is-equal 3 (getf (action-payload action) :row))
      (is-equal 1 (getf (action-payload action) :column))
      (is-equal 1 (table-widget-selected-column table))))
  (let ((center (make-notification-center
                 :placement :bottom :max-visible 2
                 :rectangle (test-rectangle 0 0 20 3))))
    (notification-center-push center "old" :id :old)
    (notification-center-push center "new" :id :new)
    (let ((action (widget-handle-event
                   center (make-mouse-event 0 2 :button :left))))
      (is-equal :close (action-name action))
      (is-equal :new (action-payload action))))
  (let ((key-calls 0)
        (label-calls 0))
    (let ((model (make-tree-model
                  :root-count 100
                  :root-at (lambda (index) index)
                  :key-at (lambda (node)
                            (incf key-calls)
                            node)
                  :label-at (lambda (node)
                              (incf label-calls)
                              (format nil "node-~D" node)))))
      (let ((tree (make-tree-widget
                   model :offset 50
                   :rectangle (test-rectangle 0 0 16 2)))
            (surface (make-surface 16 2)))
        (widget-render tree surface)
        (is-equal 2 key-calls)
        (is-equal 2 label-calls)
        (is (search "node-50" (surface-string surface)))))))

(deftest composite-widget-contracts (:composite-widgets)
  (let* ((form (make-form-widget nil))
         (surface (make-surface 10 3)))
    (is (form-widget-validate form))
    (is-equal :submit (action-name (form-widget-submit form)))
    (is-equal nil (action-payload (form-widget-submit form)))
    (widget-layout form (test-rectangle 0 0 10 3))
    (widget-render form surface)
    (is-equal :form (getf (widget-accessibility-tree form) :role)))
  (is (signals-error (make-form-widget nil :validator 42)))
  (is (signals-error (make-form-widget nil :submit-action 42)))
  (let* ((field (make-text-widget "value" :id :value))
         (form (make-form-widget
                (list field)
                :validator (lambda (values widget)
                             (declare (ignore values widget))
                             :invalid)))
         (surface (make-surface 16 4)))
    (widget-layout form (test-rectangle 0 0 16 4))
    (is (not (form-widget-validate form)))
    (is-equal '(:invalid) (form-widget-errors form))
    (widget-render form surface)
    (is-equal :validation-error
              (action-name (widget-handle-event
                            form (make-custom-event :submit))))
    (is (null (widget-handle-event form (make-custom-event :validate))))
    (is-equal :cancel
              (action-name (widget-handle-event
                            form (make-key-event :escape)))))
  (let* ((action-form
           (make-form-widget
            nil :submit-action
            (lambda (values widget)
              (declare (ignore values widget))
              (activate-action :done))))
         (payload-form
           (make-form-widget
            nil :submit-action
            (lambda (values widget)
              (declare (ignore values widget))
              42)))
         (values-form
           (make-form-widget
            (list (make-input-widget :id :value :value "ok"))
            :submit-action
            (lambda (values widget)
              (declare (ignore values widget))
              nil))))
    (is-equal :activate (action-name (form-widget-submit action-form)))
    (is-equal :done (action-payload (form-widget-submit action-form)))
    (is-equal :submit (action-name (form-widget-submit payload-form)))
    (is-equal 42 (action-payload (form-widget-submit payload-form)))
    (is-equal '((:value . "ok"))
              (action-payload (form-widget-submit values-form))))
  (let* ((viewport-widget
           (make-viewport-widget
            nil :rectangle (test-rectangle 0 0 3 2)
            :content-width 8 :content-height 6))
         (viewport (viewport-widget-viewport viewport-widget))
         (surface (make-surface 3 2)))
    (widget-layout viewport-widget (test-rectangle 0 0 3 2))
    (widget-render viewport-widget surface)
    (is-equal 8 (viewport-content-width viewport))
    (is-equal 6 (viewport-content-height viewport))
    (dolist (key '(:down :right :up :left))
      (is (widget-handle-event viewport-widget (make-key-event key))))
    (is-equal 0 (viewport-offset-x viewport))
    (is-equal 0 (viewport-offset-y viewport)))
  (let* ((button (make-button-widget "OK"))
         (modal (make-modal-widget
                 nil :buttons (list button) :open-p t
                 :rectangle (test-rectangle 0 0 16 8)))
         (surface (make-surface 16 8)))
    (widget-layout modal (test-rectangle 0 0 16 8))
    (widget-render modal surface)
    (is (search "OK" (surface-string surface)))
    (is-equal :dialog (getf (widget-accessibility-tree modal) :role))
    (let ((action (widget-handle-event
                   modal (make-custom-event :close :payload))))
      (is-equal :close (action-name action))
      (is-equal :payload (action-payload action))
      (is-equal :custom (modal-widget-close-reason modal)))))

(in-package #:cl-tui-kit/tests)

(deftest standard-form-controls (:widgets)
  (let* ((textarea (make-textarea-widget
                    :value "one"
                    :preferred-rows 2
                    :rectangle (test-rectangle 0 0 8 2)))
         (surface (make-surface 8 2)))
    (widget-handle-event textarea (test-key :home))
    (widget-handle-event textarea (test-key :end))
    (widget-handle-event textarea (test-key :enter))
    (widget-handle-event textarea (make-text-input-event "two"))
    (is-equal (format nil "one~%two") (input-widget-value textarea))
    (widget-render textarea surface)
    (is (search "two" (surface-string surface)))
    (is (widget-cursor-position textarea)))
  (let* ((radio (make-radio-widget
                 '("One" "Two")
                 :selected-index 0
                 :rectangle (test-rectangle 0 0 10 2)))
         (surface (make-surface 10 2)))
    (is-equal "One" (radio-widget-selected-option radio))
    (let ((action (widget-handle-event radio (test-key :down))))
      (is-equal :select (action-name action))
      (is-equal 1 (radio-widget-selected-index radio))
      (is-equal "Two" (action-payload action)))
    (widget-render radio surface)
    (is (search "Two" (surface-string surface))))
  (let* ((select (make-select-widget
                  '("Red" "Green")
                  :selected-index 0
                  :rectangle (test-rectangle 0 0 12 2)))
         (surface (make-surface 12 2)))
    (is-equal :open
              (action-name (widget-handle-event select (test-key :enter))))
    (is (select-widget-open-p select))
    (let ((action (widget-handle-event select (test-key :down))))
      (is-equal :select (action-name action))
      (is-equal "Green" (action-payload action)))
    (is-equal :select
              (action-name (widget-handle-event select (test-key :enter))))
    (is (not (select-widget-open-p select)))
    (widget-render select surface)
    (is (search "Green" (surface-string surface))))
  (let ((spinner (make-spinner-widget
                  :frames '("-" "|" "/")
                  :rectangle (test-rectangle 0 0 2 1))))
    (is-equal "-" (spinner-widget-current-frame spinner))
    (is-equal :tick
              (action-name (widget-handle-event spinner (make-tick-event))))
    (is-equal "|" (spinner-widget-current-frame spinner))
    (is (spinner-widget-running-p spinner))))

(deftest standard-form-control-metadata-and-viewport (:widgets)
  (let* ((textarea (make-textarea-widget
                    :value "body"
                    :id :body
                    :semantic-role :multiline-textbox
                    :accessible-label "Message"
                    :accessible-description "A multi-line message"
                    :accessible-help-text "Use Enter for a new line"
                    :focusable-p nil))
         (info (widget-accessibility-tree textarea)))
    (is-equal :body (getf info :id))
    (is-equal :multiline-textbox (getf info :role))
    (is-equal "Message" (getf info :label))
    (is-equal "A multi-line message" (getf info :description))
    (is-equal "Use Enter for a new line" (getf info :help-text))
    (is (not (getf info :focusable-p))))
  (let* ((radio (make-radio-widget
                 '("One" "Two")
                 :id :choice
                 :accessible-label "Choice"
                 :accessible-help-text "Choose one"
                 :selected-index 1))
         (info (widget-accessibility-tree radio)))
    (is-equal :choice (getf info :id))
    (is-equal :radiogroup (getf info :role))
    (is-equal "Choice" (getf info :label))
    (is-equal "Choose one" (getf info :help-text))
    (is-equal 1 (getf (getf info :state) :selected-index)))
  (let* ((select (make-select-widget
                  '("A" "B" "C" "D" "E")
                  :selected-index 4
                  :visible-rows 2
                  :open-p t
                  :id :letters
                  :accessible-label "Letters"
                  :rectangle (test-rectangle 0 0 8 2)))
         (surface (make-surface 8 2))
         (info (widget-accessibility-tree select)))
    (is-equal :letters (getf info :id))
    (is-equal :combobox (getf info :role))
    (is-equal "Letters" (getf info :label))
    (widget-render select surface)
    (is (search "D" (surface-string surface)))
    (is (search "E" (surface-string surface)))
    (let ((action (widget-handle-event
                   select (make-mouse-event 0 0 :kind :press))))
      (is-equal :select (action-name action))
      (is-equal "D" (action-payload action))))
  (let* ((spinner (make-spinner-widget
                   :id :busy
                   :accessible-label "Busy"
                   :accessible-description "Working"
                   :focusable-p nil))
         (info (widget-accessibility-tree spinner)))
    (is-equal :busy (getf info :id))
    (is-equal :status (getf info :role))
    (is-equal "Busy" (getf info :label))
    (is-equal "Working" (getf info :description))
    (is (not (getf info :focusable-p)))))
