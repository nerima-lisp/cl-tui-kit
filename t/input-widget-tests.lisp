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
  (let ((input (make-input-widget :value "one two")))
    (widget-handle-event input (test-key #\e :ctrl))
    (is-equal 7 (input-widget-cursor input))
    (widget-handle-event input (test-key #\a :ctrl))
    (is-equal 0 (input-widget-cursor input))
    (widget-handle-event input (test-key :right :shift))
    (widget-handle-event input (test-key :left))
    (is-equal 0 (input-widget-cursor input))
    (widget-handle-event input (test-key :right :shift))
    (widget-handle-event input (test-key :right))
    (is-equal 1 (input-widget-cursor input)))
  (let ((input (make-input-widget :value "one two")))
    (widget-handle-event input (test-key #\e :ctrl))
    (widget-handle-event input (test-key :backspace :ctrl))
    (is-equal "one " (input-widget-value input)))
  (let ((input (make-input-widget :value "one two")))
    (widget-handle-event input (test-key #\a :ctrl))
    (widget-handle-event input (test-key :delete :ctrl))
    (is-equal " two" (input-widget-value input)))
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

(deftest input-widget-clear-selection-empties-a-real-selection
    (:widgets)
  ;; INPUT-WIDGET-CLEAR-SELECTION (src/input-editing.lisp:106-108) was never
  ;; exercised in T/, directly or via any keybinding.  Establish a real
  ;; selection through the same shift+arrow path a user drives, then assert
  ;; on observable selection state -- not on the function's return value.
  (let ((input (make-input-widget
                :value "one two"
                :rectangle (make-rectangle 0 0 12 1))))
    (widget-handle-event input (test-key :home))
    (widget-handle-event input (test-key :right :shift))
    (widget-handle-event input (test-key :right :shift))
    (is-equal "on" (input-widget-selected-text input))
    (is (input-widget-selection-start input))
    (is (input-widget-selection-end input))
    (input-widget-clear-selection input)
    (is (null (input-widget-selection-start input)))
    (is (null (input-widget-selection-end input)))
    (is-equal "" (input-widget-selected-text input))))

(deftest input-paste-history-and-key-actions (:widgets)
  (is (signals-error (make-input-widget :max-history 0)))
  (let ((input (make-input-widget
                :value "ab"
                :max-history 1
                :rectangle (make-rectangle 0 0 8 1))))
    (widget-handle-event input (make-paste-event "CD"))
    (is-equal "abCD" (input-widget-value input))
    (widget-handle-event input (make-paste-event ""))
    (is-equal "abCD" (input-widget-value input))
    (widget-handle-event input (test-key :z :ctrl))
    (is-equal "ab" (input-widget-value input))
    (widget-handle-event input (test-key :z :ctrl))
    (is-equal "ab" (input-widget-value input))
    (widget-handle-event input (test-key :y :ctrl))
    (is-equal "abCD" (input-widget-value input))
    (widget-handle-event input (make-text-input-event "E"))
    (widget-handle-event input (test-key :z :ctrl))
    (is-equal "abCD" (input-widget-value input))
    (widget-handle-event input (test-key :z :ctrl :shift))
    (is-equal "abCDE" (input-widget-value input)))
  (let ((input (make-input-widget :value "value")))
    (is-equal :submit
              (action-name (widget-handle-event input (test-key :enter))))
    (is-equal :cancel
              (action-name (widget-handle-event input (test-key :escape))))))

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

(deftest spinner-protocol-and-invalid-inputs (:widgets)
  (is (signals-error (make-spinner-widget :frames nil)))
  (is (signals-error (make-spinner-widget :frames '("-") :index 1)))
  (is (signals-error (make-spinner-widget :frames '("-") :running-p :yes)))
  (is-equal '("-" "/" "|" "\\")
            (spinner-widget-frames (make-spinner-widget)))
  (let ((spinner (make-spinner-widget)))
    (setf (widget-role spinner) nil
          (widget-label spinner) nil)
    (let ((info (widget-accessibility-info spinner)))
      (is-equal :status (getf info :role))
      (is-equal "Progress" (getf info :label))))
  (let ((spinner (make-spinner-widget :action (make-action :custom :payload))))
    (is-equal :custom
              (action-name (spinner-widget-toggle spinner))))
  (let* ((spinner (make-spinner-widget :frames '("aa" "b")
                                       :index 1
                                       :running-p nil
                                       :rectangle (test-rectangle 0 0 2 1)))
         (surface (make-surface 2 1)))
    (is-equal 2 (size-width (widget-preferred-size spinner)))
    (is-equal 1 (size-height (widget-preferred-size spinner)))
    (spinner-widget-tick spinner)
    (is-equal 1 (spinner-widget-index spinner))
    (is-equal :toggle
              (action-name
               (widget-handle-event spinner (make-key-event :space))))
    (is-equal :toggle
              (action-name
               (widget-handle-event spinner (make-mouse-event 0 0))))
    (widget-render spinner surface)
    (is (search "b" (surface-string surface)))
    (is (null (widget-handle-event spinner (make-key-event :escape)))))
  (let ((spinner (make-spinner-widget
                  :action (lambda (widget)
                            (make-action :callback widget)))))
    (is-equal :callback
              (action-name (spinner-widget-toggle spinner)))))

(deftest choice-and-textarea-boundaries (:widgets)
  (let ((empty-radio (make-radio-widget nil))
        (empty-select (make-select-widget nil)))
    (is (null (radio-widget-selected-option empty-radio)))
    (is (null (select-widget-selected-option empty-select)))
    (is (null (widget-handle-event empty-radio (test-key :down))))
    (is (null (widget-handle-event empty-select (test-key :down))))
    (is (signals-error (radio-widget-select
                        (make-radio-widget '("A")) 1)))
    (is (signals-error (select-widget-select
                        (make-select-widget '("A")) -1))))
  (let ((radio (make-radio-widget '("A" "B") :selected-index 0
                                  :wrap-p nil))
        (wrapped (make-radio-widget '("A" "B") :selected-index 0
                                    :wrap-p t)))
    (widget-handle-event radio (test-key :up))
    (is-equal 0 (radio-widget-selected-index radio))
    (widget-handle-event wrapped (test-key :up))
    (is-equal 1 (radio-widget-selected-index wrapped)))
  (let ((select (make-select-widget '("A" "B") :selected-index 0
                                    :open-p t
                                    :rectangle (test-rectangle 0 0 6 2))))
    (is-equal :close
              (action-name (widget-handle-event select (test-key :escape))))
    (is (not (select-widget-open-p select)))
    (is (null (widget-handle-event
               select (make-mouse-event 20 20 :kind :press)))))
  (let ((textarea (make-textarea-widget
                   :value (format nil "ab~%cdef~%gh")
                   :soft-wrap-p nil
                   :rectangle (test-rectangle 0 0 4 2))))
    (widget-handle-event textarea (test-key :home))
    (widget-handle-event textarea (test-key :down))
    (is (plusp (input-widget-cursor textarea)))
    (widget-handle-event textarea (test-key :page-down))
    (widget-handle-event textarea (test-key :page-up :shift))
    (is (and (input-widget-selection-start textarea)
             (input-widget-selection-end textarea)))
    (is (widget-cursor-position textarea)))
  (let ((textarea (make-textarea-widget :value "ready"
                                         :submit-on-enter-p t)))
    (is-equal :submit
              (action-name (widget-handle-event textarea (test-key :enter)))))
  (let* ((radio (make-radio-widget '("A" "Longer")))
         (select (make-select-widget '("A" "Longer")
                                     :visible-rows 1))
         (textarea (make-textarea-widget
                    :value (format nil "a~%hello")
                    :preferred-rows 3)))
    (is-equal 10 (size-width (widget-preferred-size radio)))
    (is-equal 2 (size-height (widget-preferred-size radio)))
    (is-equal 10 (size-width (widget-preferred-size select)))
    (is-equal 1 (size-height (widget-preferred-size select)))
    (is-equal 5 (size-width (widget-preferred-size textarea)))
    (is-equal 3 (size-height (widget-preferred-size textarea)))
    (setf (widget-role radio) nil
          (widget-label radio) nil
          (widget-role select) nil
          (widget-label select) nil)
    (let ((radio-info (widget-accessibility-info radio))
          (select-info (widget-accessibility-info select)))
      (is-equal :radiogroup (getf radio-info :role))
      (is-equal "Radio group" (getf radio-info :label))
      (is-equal :combobox (getf select-info :role))
      (is-equal "Select" (getf select-info :label))))
  (let ((textarea (make-textarea-widget
                   :value "abcdef"
                   :soft-wrap-p t
                   :rectangle (test-rectangle 0 0 3 2)))
        (surface (make-surface 3 2)))
    (widget-handle-event textarea (test-key :home))
    (widget-handle-event textarea (test-key :right))
    (widget-handle-event textarea (test-key :up))
    (widget-handle-event textarea (test-key :down))
    (widget-handle-event textarea (test-key :page-up))
    (widget-handle-event textarea (test-key :page-down))
    (widget-handle-event textarea (test-key :left :shift))
    (is (input-widget-selection-start textarea))
    (is (input-widget-selection-end textarea))
    (widget-render textarea surface)
    (is (search "abc" (surface-string surface)))
    (is (widget-cursor-position textarea)))
  (let* ((radio (make-radio-widget '("A" "B")))
         (select (make-select-widget '("A" "B")))
         (radio-surface (make-surface 20 2))
         (select-surface (make-surface 20 2)))
    (is-equal 0 (radio-widget-selected-index radio))
    (is-equal 0 (select-widget-selected-index select))
    (is-equal :select
              (action-name (widget-handle-event radio (test-key :enter))))
    (is-equal :open
              (action-name (widget-handle-event select (test-key :space))))
    (is (select-widget-open-p select))
    (is (widget-handle-event
         radio (make-mouse-event 0 1 :kind :press)))
    (is-equal 1 (radio-widget-selected-index radio))
    (is (null (widget-handle-event
               radio (make-mouse-event 0 2 :kind :press))))
    (widget-render radio radio-surface)
    (widget-render select select-surface)
    (is (search "A" (surface-string radio-surface)))
    (is (search "A" (surface-string select-surface)))))

(deftest textarea-segment-and-control-contracts (:widgets)
  (let ((segments (list (cons 0 2) (cons 2 4))))
    (let ((segment (cl-tui-kit/widgets::%textarea-segment-at-cursor
                    segments 1)))
      (is-equal 0 (car segment))
      (is-equal 2 (cdr segment)))
    (is-equal (second segments)
              (cl-tui-kit/widgets::%textarea-segment-at-cursor
               segments 2))
    (is-equal (second segments)
              (cl-tui-kit/widgets::%textarea-segment-at-cursor
               segments 4))
    (is-equal (second segments)
              (cl-tui-kit/widgets::%textarea-segment-at-cursor
               segments 9))
    (is-equal 1
              (cl-tui-kit/widgets::%textarea-segment-index
               segments (second segments)))
    (is-equal 0
              (cl-tui-kit/widgets::%textarea-segment-index
               segments (cons 2 4)))
    (is-equal 0
              (cl-tui-kit/widgets::%textarea-segment-index '() nil)))
  (let* ((value (format nil "ab~%cd"))
         (textarea (make-textarea-widget :value value)))
    (widget-handle-event textarea (test-key :home :ctrl))
    (is-equal 0 (input-widget-cursor textarea))
    (widget-handle-event textarea (test-key :end :ctrl))
    (is-equal (length value) (input-widget-cursor textarea))))

(cl-weave:it-property "indexed controls keep movement inside their options"
  ((index (cl-weave:gen-integer :min 0 :max 4))
   (delta (cl-weave:gen-integer :min -12 :max 12)))
  (let ((radio (make-radio-widget '("A" "B" "C" "D" "E")
                                  :selected-index index
                                  :wrap-p nil))
        (select (make-select-widget '("A" "B" "C" "D" "E")
                                    :selected-index index)))
    (cl-tui-kit/widgets::%radio-move radio delta)
    (cl-tui-kit/widgets::%select-move select delta)
    (is (<= 0 (radio-widget-selected-index radio) 4))
    (is (<= 0 (select-widget-selected-index select) 4))))

(cl-weave:it-property "spinner transitions preserve a generated frame cycle"
  ((frames (cl-weave:gen-list
            (cl-weave:gen-member '("." "o" "O"))
            :min-length 1 :max-length 6))
   (running-p (cl-weave:gen-boolean)))
  (let* ((spinner (make-spinner-widget :frames frames :running-p running-p))
         (expected-index (if running-p (mod 1 (length frames)) 0)))
    (spinner-widget-tick spinner)
    (is-equal (nth expected-index frames) (spinner-widget-current-frame spinner))
    (let ((before (spinner-widget-running-p spinner)))
      (spinner-widget-toggle spinner)
      (spinner-widget-toggle spinner)
      (is-equal before (spinner-widget-running-p spinner)))))

(cl-weave:it-property "spinner follows generated event traces"
  ((trace
    (cl-weave:gen-state-machine
     (list 0 t)
     (lambda (state event)
       (destructuring-bind (index running-p) state
         (case event
           (:tick (list (if running-p (mod (1+ index) 3) index)
                        running-p))
           (:toggle (list index (not running-p))))))
     (cl-weave:gen-one-of
      (cl-weave:gen-member '(:tick :toggle)))
     :min-length 1
     :max-length 12)))
  (let ((spinner (make-spinner-widget :frames '("." "o" "O"))))
    (dolist (event (getf trace :events))
      (case event
        (:tick (spinner-widget-tick spinner))
        (:toggle (spinner-widget-toggle spinner))))
    (let ((final (getf trace :final)))
      (is-equal (first final) (spinner-widget-index spinner))
      (is-equal (second final) (spinner-widget-running-p spinner)))))

(cl-weave:it-property "derived option labels remain renderable"
  ((labels
    (cl-weave:gen-tuple
     (cl-weave:gen-such-that
      (lambda (value) (plusp (length value)))
      (cl-weave:gen-string :min-length 0 :max-length 8))
     (cl-weave:gen-map
      #'string-upcase
      (cl-weave:gen-string :min-length 1 :max-length 8)))))
  (let* ((radio (make-radio-widget labels :selected-index 1))
         (surface (make-surface 24 2)))
    (is-equal (second labels) (radio-widget-selected-option radio))
    (widget-render radio surface)
    (is (search (second labels) (surface-string surface)))))
