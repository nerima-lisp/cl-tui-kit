(in-package #:cl-tui-kit/tests)

(deftest ansi-regional-present-preserves-full-diff (:ansi)
  (let* ((stream (make-string-output-stream))
         (backend (make-ansi-backend :stream stream :size (make-size 2 1)))
         (surface (make-surface 2 1)))
    (surface-draw-text surface 0 0 "aa")
    (backend-present backend surface)
    (get-output-stream-string stream)
    (surface-draw-text surface 0 0 "ca")
    (backend-present backend surface
                     :region (make-rectangle 1 0 1 1))
    (is-equal "" (get-output-stream-string stream))
    (backend-present backend surface)
    (is (search (format nil "~C[1;1H" (code-char 27))
                (get-output-stream-string stream)))))

(deftest support-widgets-tabs-menus-and-scrollbars (:widgets)
  (let* ((first (make-button-widget "First"))
         (third (make-text-widget "Third"))
         (tabs (make-tabs-widget
                (list (make-tab "One" first :key :one)
                      (make-tab "Disabled" nil :key :disabled :enabled-p nil)
                      (make-tab "Three" third :key :three))
                :selected-index 1
                :rectangle (test-rectangle 0 0 24 4)))
         (surface (make-surface 24 4)))
    (is-equal 0 (tabs-widget-selected-index tabs))
    (tabs-widget-select tabs 1)
    (is-equal 0 (tabs-widget-selected-index tabs))
    (widget-layout tabs (test-rectangle 0 0 24 4))
    (widget-render tabs surface)
    (is (search "One" (surface-string surface)))
    (is (search "First" (surface-string surface)))
    (is-equal :tablist (getf (widget-accessibility-tree tabs) :role))
    (let ((action (handle-widget-event tabs (make-key-event :right))))
      (is-equal :select (action-name action))
      (is-equal :three (action-payload action)))
    (is-equal 2 (tabs-widget-selected-index tabs))
    (let ((action (handle-widget-event tabs (make-mouse-event 1 0))))
      (is-equal :select (action-name action))
      (is-equal :one (action-payload action)))
    (tabs-widget-select tabs 0)
    (is-equal :activate
              (action-name (handle-widget-event tabs (make-key-event :enter))))
    (is (signals-error (make-tabs-widget (list :not-a-tab))))
    (let ((negative-tabs
            (make-tabs-widget (list (make-tab "Only" nil :key :only))
                              :selected-index -1)))
      (is-equal 0 (tabs-widget-selected-index negative-tabs))
      (tabs-widget-select negative-tabs -1)
      (is-equal 0 (tabs-widget-selected-index negative-tabs)))
    (let ((boundary-tabs
            (make-tabs-widget
             (list (make-tab "Only" nil :key :only)
                   (make-tab "Disabled" nil :key :disabled
                             :enabled-p nil))
             :rectangle (test-rectangle 0 0 20 2))))
      (is (null (handle-widget-event boundary-tabs
                                     (make-key-event :right))))
      (is-equal 0 (tabs-widget-selected-index boundary-tabs))
      (is (null (handle-widget-event boundary-tabs
                                     (make-mouse-event 6 0))))
      (is (null (handle-widget-event boundary-tabs
                                     (make-mouse-event 1 0 :kind :release))))
      (is (null (handle-widget-event boundary-tabs
                                     (make-mouse-event 1 1))))))
  (let* ((submenu (make-menu-widget
                   (list (make-menu-item "Child" :key :child))
                   :open-p nil))
         (menu (make-menu-widget
                (list (make-menu-item
                       "Open" :key :open
                       :action (lambda (widget)
                                 (declare (ignore widget))
                                 (activate-action :open)))
                      (make-menu-item "Disabled" :enabled-p nil)
                      (make-menu-item "More" :key :more :submenu submenu))
                :open-p nil
                :rectangle (test-rectangle 0 0 20 3)))
         (surface (make-surface 20 3)))
    (is-equal :menu (getf (widget-accessibility-tree menu) :role))
    (widget-layout menu (test-rectangle 0 0 20 3))
    (widget-render menu surface)
    (is (search "Open" (surface-string surface)))
    (let ((action (handle-widget-event menu (make-key-event :down))))
      (is-equal :move (action-name action)))
    (is-equal 2 (menu-widget-selected-index menu))
    (menu-widget-select menu 1)
    (is-equal 2 (menu-widget-selected-index menu))
    (let ((action (handle-widget-event menu (make-key-event :right))))
      (is-equal :open (action-name action))
      (is (menu-widget-open-p menu)))
    (widget-layout menu (test-rectangle 0 0 20 3))
    (widget-render menu surface)
    (is (search "Child" (surface-string surface)))
    (is-equal :close
              (action-name (handle-widget-event menu (make-key-event :escape))))
    (menu-widget-select menu 0)
    (is-equal :activate
              (action-name (handle-widget-event menu (make-mouse-event 1 0))))
    (let ((negative-menu
            (make-menu-widget (list (make-menu-item "Only" :key :only))
                              :selected-index -1)))
      (is-equal 0 (menu-widget-selected-index negative-menu))
      (menu-widget-select negative-menu -1)
      (is-equal 0 (menu-widget-selected-index negative-menu))))
  (let* ((status (make-status-bar-widget "ready"
                                         :rectangle (test-rectangle 0 0 8 1)))
         (status-surface (make-surface 8 1))
         (vertical (make-scroll-bar-widget
                    :orientation :vertical :position 3 :page-size 2
                    :content-size 10 :rectangle (test-rectangle 0 0 3 5)))
         (vertical-surface (make-surface 3 5))
         (horizontal (make-scroll-bar-widget
                      :orientation :horizontal :position 3 :page-size 2
                      :content-size 10 :rectangle (test-rectangle 0 0 5 1)))
         (horizontal-surface (make-surface 5 1)))
    (widget-render status status-surface)
    (is (search "ready" (surface-string status-surface)))
    (is-equal "ready" (status-bar-widget-text status))
    (widget-render vertical vertical-surface)
    (is (search "█" (surface-string vertical-surface)))
    (widget-render horizontal horizontal-surface)
    (is (search "█" (surface-string horizontal-surface)))
    (is (signals-error (make-scroll-bar-widget :orientation :diagonal)))
    (is (typep (make-scroll-bar-widget :page-size 0)
               'scroll-bar-widget))))
