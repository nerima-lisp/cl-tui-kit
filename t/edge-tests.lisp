(in-package #:cl-tui-kit/tests)

(deftest empty-focus-and-list-contracts (:edge-cases)
  (let* ((root (make-focus-node :root :scope-p t))
         (tree (make-focus-tree root)))
    (is (null (focus-tree-current tree)))
    (is (null (focus-next tree)))
    (is (null (focus-previous tree)))
    (is (null (focus-directional tree :right))))
  (let* ((model (make-list-model :count 0 :item-at #'identity))
         (widget (make-list-widget model
                                   :rectangle (test-rectangle 0 0 8 2))))
    (is (null (list-widget-selected-index widget)))
    (is (null (list-widget-visible-items widget)))
    (list-widget-page-up widget)
    (list-widget-page-down widget)
    (list-widget-refresh widget)
    (is-equal (make-size 0 10) (widget-preferred-size widget))
    (is (null (list-widget-selected-key widget)))))

(deftest event-loop-preserves-same-deadline-order (:event-loop)
  (let ((events '())
        (loop (make-event-loop :clock (lambda () 10))))
    (event-loop-schedule loop 0
                         (lambda (scheduled-loop task)
                           (declare (ignore scheduled-loop task))
                           (push :first events)
                           nil))
    (event-loop-schedule loop 0
                         (lambda (scheduled-loop task)
                           (declare (ignore scheduled-loop task))
                           (push :second events)
                           nil))
    (is-equal 10 (event-loop-next-deadline loop))
    (is (event-loop-step loop :now 10))
    (is (event-loop-step loop :now 10))
    (is-equal '(:first :second) (nreverse events))
    (is (not (event-loop-step loop :now 10)))))

(deftest declarative-keymap-input-validation (:keymap)
  (is (signals-error
       (macroexpand-1 '(define-keymap 1 ()))))
  (is (signals-error
       (macroexpand-1 '(define-keymap make-edge-keymap :name))))
  (is (signals-error
       (macroexpand-1 '(define-keymap make-edge-keymap (invalid t)))))
  (is (signals-error
       (macroexpand-1 '(define-keymap make-edge-keymap (:parent)))))
  (is (signals-error
       (macroexpand-1 '(define-keymap make-edge-keymap (:parent nil))))))

  (deftest surface-testing-contracts (:testing)
    (let ((surface (make-surface 2 1)))
      (surface-draw-text surface 0 0 "ok")
      (is-equal "o" (surface-cell-string (surface-cell surface 0 0)))
      (is-equal "ok" (surface-cell-string surface))
      (is (surface-equal-p surface (copy-surface surface)))
      (is (not (surface-equal-p surface (make-surface 1 1))))
      (is (assert-surface-text surface "ok"))
      (is (signals-error (assert-surface-text surface "mismatch")))))

  (deftest focus-next-uses-first-focusable-when-current-is-unset (:edge-cases)
    (let* ((child (make-focus-node :child :focusable-p t))
           (tree (make-focus-tree
                  (make-focus-node :root :scope-p t
                                   :children (list child)))))
      (setf (focus-tree-current tree) nil)
      (is-equal :child (focus-node-id (focus-next tree)))))

  (deftest tree-model-accepts-plain-list-children (:edge-cases)
    (let* ((model (make-tree-model
                   :root-count 1
                   :root-at (lambda (index)
                              (declare (ignore index))
                              :root)
                   :key-at #'identity
                   :label-at (lambda (node)
                               (format nil "label-~A" node))
                   :children (lambda (node)
                               (when (eq node :root)
                                 '(:left :right)))
                   :expanded-p (lambda (node)
                                 (eq node :root))
                   :render-item (lambda (node)
                                  (format nil "row-~A" node))))
           (widget (make-tree-widget
                    model
                    :selected-key :root
                    :rectangle (test-rectangle 0 0 16 3)))
           (surface (make-surface 16 3)))
      (widget-layout widget (test-rectangle 0 0 16 3))
      (widget-render widget surface)
      (is (search "row-ROOT" (surface-string surface)))
      (is (search "row-LEFT" (surface-string surface)))
      (is-equal 2 (length (tree-model-children model :root)))))

  (deftest modal-child-mouse-events-are-forwarded (:edge-cases)
    (let* ((child (make-button-widget "Child"))
           (modal (make-modal-widget
                   child
                   :open-p t
                   :rectangle (test-rectangle 0 0 16 8)))
           (surface (make-surface 16 8)))
      (widget-layout modal (test-rectangle 0 0 16 8))
      (widget-render modal surface)
      (is (search "Child" (surface-string surface)))
      (let ((area (widget-rectangle child)))
        (let ((action (widget-handle-event
                       modal
                       (make-mouse-event
                        (rectangle-x area)
                        (rectangle-y area)
                        :button :left))))
          (is-equal :activate (action-name action))
          (is-equal "Child" (action-payload action))
          (is-equal :button (modal-widget-close-reason modal))))))

  (deftest modal-preferred-size-includes-button-row (:edge-cases)
    (let* ((child (make-widget))
           (without-buttons (make-modal-widget child))
           (with-buttons (make-modal-widget
                          child
                          :buttons (list (make-button-widget "OK")))))
      (is-equal (+ 2 (size-height (widget-preferred-size without-buttons)))
                (size-height (widget-preferred-size with-buttons)))
      (is (>= (size-width (widget-preferred-size with-buttons))
              (size-width (widget-preferred-size without-buttons))))))

  (deftest modal-event-target-prevents-duplicate-child-dispatch (:edge-cases)
    (let* ((child (make-widget))
           (button (make-button-widget "OK"))
           (modal (make-modal-widget
                   child
                   :open-p t
                   :buttons (list button)
                   :rectangle (test-rectangle 0 0 16 8)))
           (root (make-box-widget
                  modal
                  :rectangle (test-rectangle 0 0 16 8))))
      (widget-layout root (test-rectangle 0 0 16 8))
      (let ((area (widget-rectangle child)))
        (is (null
             (dispatch-widget-event
              root
              (make-mouse-event (rectangle-x area)
                                (rectangle-y area)
                                :button :left)
              child))))
      (is (modal-widget-open-p modal))
      (let* ((action-child (make-button-widget "Child"))
             (action-modal
               (make-modal-widget
                action-child
                :open-p t
                :rectangle (test-rectangle 0 0 16 8)))
             (action-root
               (make-box-widget
                action-modal
                :rectangle (test-rectangle 0 0 16 8))))
        (widget-layout action-root (test-rectangle 0 0 16 8))
        (let ((area (widget-rectangle action-child)))
          (let ((action
                  (dispatch-widget-event
                   action-root
                   (make-mouse-event (rectangle-x area)
                                     (rectangle-y area)
                                     :button :left)
                   action-modal)))
            (is-equal :activate (action-name action))
            (is (not (modal-widget-open-p action-modal))))))
      (let ((area (widget-rectangle button)))
        (is (null
             (dispatch-widget-event
              root
              (make-mouse-event (rectangle-x area)
                                (rectangle-y area)
                                :button :left)
              child))))
      (is (modal-widget-open-p modal))))

  (deftest menu-navigation-skips-disabled-items-in-both-directions (:edge-cases)
    (let ((menu (make-menu-widget
                 (list (make-menu-item "First")
                       (make-menu-item "Disabled" :enabled-p nil)
                       (make-menu-item "Last"))
                 :selected-index 2)))
      (let ((action (handle-widget-event menu (make-key-event :up))))
        (is-equal :move (action-name action))
        (is-equal 0 (menu-widget-selected-index menu)))
      (is (null (handle-widget-event menu (make-key-event :up))))))

  (deftest tabs-header-size-and-left-navigation (:edge-cases)
    (let ((tabs (make-tabs-widget
                 (list (make-tab "One" nil :key :one)
                       (make-tab "Off" nil :key :off :enabled-p nil)
                       (make-tab "Three" nil :key :three))
                 :selected-index 2)))
      (is-equal (make-size 7 1) (widget-preferred-size tabs))
      (let ((action (handle-widget-event tabs (make-key-event :left))))
        (is-equal :select (action-name action))
        (is-equal :one (action-payload action)))
      (is-equal 0 (tabs-widget-selected-index tabs))))

  (deftest application-dispatches-widget-keymaps (:edge-cases)
    (let* ((backend (make-test-backend :size (make-size 8 2)))
           (keymap (make-keymap))
           (root (make-widget :keymap keymap))
           (app (make-application :backend backend :root root)))
      (bind-key keymap #\x (custom-action :shortcut))
      (is-equal :shortcut
                (action-name
                 (application-dispatch-event app (make-key-event #\x))))
      (is (null (application-dispatch-event app (make-key-event #\q))))))

  (deftest input-rendering-covers-placeholder-and-selection (:edge-cases)
    (let* ((input (make-input-widget
                   :placeholder "Enter"
                   :rectangle (test-rectangle 0 0 7 1)))
           (surface (make-surface 7 1)))
      (widget-render input surface)
      (is-equal 7 (length (surface-string surface)))
      (is-equal "" (input-widget-value input)))
      (let* ((input (make-input-widget
                   :value "abcdef"
                   :rectangle (test-rectangle 0 0 4 1)))
           (surface (make-surface 4 1)))
      (widget-handle-event input (test-key :home))
      (widget-handle-event input (test-key :right :shift))
      (widget-render input surface)
      (is-equal 0 (input-widget-selection-start input))
      (is-equal 1 (input-widget-selection-end input))))

  (deftest input-delete-and-cancel-events (:edge-cases)
    (let ((input (make-input-widget :value "abc")))
      (widget-handle-event input (test-key :home))
      (is (null (widget-handle-event input (test-key :delete))))
      (is-equal "bc" (input-widget-value input))
      (is-equal :cancel
                (action-name
                 (widget-handle-event input (test-key :escape))))))

  (deftest surface-clip-mutation-does-not-corrupt-surface (:edge-cases)
    (let ((surface (make-surface 8 4)))
      (surface-set-clip surface (test-rectangle 1 1 4 2))
      (let ((clip (surface-clip surface)))
        (setf (rectangle-x clip) 0)
        (setf (rectangle-y clip) 0)
        (setf (rectangle-width clip) 8)
        (setf (rectangle-height clip) 4))
      (is-equal (test-rectangle 1 1 4 2) (surface-clip surface))
      (surface-draw-text surface 0 0 "x")
      (is-equal " " (surface-cell-string (surface-cell surface 0 0)))))

  (deftest keymap-state-pending-mutation-does-not-corrupt-state (:edge-cases)
    (let* ((keymap (make-keymap :name :edge))
           (state (make-keymap-state)))
      (bind-key keymap (list #\g #\g) (custom-action :top))
      (is-equal :prefix
                (keymap-result-status
                 (keymap-dispatch keymap state (test-key #\g))))
      (let ((pending (keymap-state-pending state)))
        (is-equal 1 (length pending))
        (setf (car pending) :corrupted)
        (setf (cdr pending) (list :extra :garbage)))
      (is-equal 1 (length (keymap-state-pending state)))
      (let ((result (keymap-dispatch keymap state (test-key #\g))))
        (is-equal :handled (keymap-result-status result))
        (is-equal :top (action-name (keymap-result-action result))))))

(deftest backend-close-clears-preexisting-last-error (:backend)
  (let ((backend (make-backend))
        (condition nil))
    (handler-case (error "seed failure")
      (error (caught) (setf condition caught)))
    (backend-fail backend condition)
    (is-equal :failed (backend-state backend))
    (is (eq condition (backend-last-error backend)))
    (backend-close backend)
    (is-equal :closed (backend-state backend))
    (is (null (backend-last-error backend)))))

(deftest ansi-synchronized-updates-disable-suppresses-present-wrapper (:ansi)
  (let* ((stream (make-string-output-stream))
         (backend (make-ansi-backend :stream stream :size (make-size 2 1)))
         (surface (make-surface 2 1)))
    (surface-draw-text surface 0 0 "x")
    (ansi-enable-synchronized-updates backend)
    (is (ansi-backend-synchronized-updates-enabled-p backend))
    (backend-present backend surface)
    (let ((output (get-output-stream-string stream)))
      (is (search (format nil "~C[?2026h" (code-char 27)) output))
      (is (search (format nil "~C[?2026l" (code-char 27)) output)))
    (ansi-disable-synchronized-updates backend)
    (is (not (ansi-backend-synchronized-updates-enabled-p backend)))
    (surface-draw-text surface 0 0 "y")
    (backend-present backend surface)
    (let ((output (get-output-stream-string stream)))
      (is (not (search (format nil "~C[?2026h" (code-char 27)) output)))
      (is (not (search (format nil "~C[?2026l" (code-char 27)) output))))))
