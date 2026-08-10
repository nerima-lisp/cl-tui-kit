(in-package #:cl-tui-kit/tests)

(deftest layout-split-overlay-and-insufficient-space (:layout)
  (let* ((left (make-layout-item :left
                                 :constraints (make-constraints :min-width 3)))
         (right (make-layout-item :right
                                  :constraints (make-constraints :min-width 3)))
         (split (make-split (list left right) :ratio 0.3 :axis :horizontal))
         (rects (layout-rects split (test-rectangle 0 0 10 4)))
         (vbox (make-vbox
                (list (make-layout-item :first
                                        :constraints (make-constraints
                                                      :min-height 3))
                      (make-layout-item :second
                                        :constraints (make-constraints
                                                      :min-height 3)))))
         (small-rects (layout-rects vbox (test-rectangle 0 0 4 4))))
    (is-equal 3 (rectangle-width (cdr (assoc :left rects))))
    (is-equal 7 (rectangle-width (cdr (assoc :right rects))))
    (is-equal 3 (rectangle-height (cdr (assoc :first small-rects))))
    (is-equal 1 (rectangle-height (cdr (assoc :second small-rects))))
    (let* ((overlay (make-overlay (list :a :b)))
           (overlay-rects (layout-rects overlay (test-rectangle 1 2 3 4))))
      (is-equal (test-rectangle 1 2 3 4)
                (cdr (assoc :a overlay-rects)))
      (is-equal (test-rectangle 1 2 3 4)
                (cdr (assoc :b overlay-rects))))))

(deftest layout-gap-margin-grid-and-weighted-flex (:layout)
  (let* ((left (make-layout-item
                :left :constraints (make-constraints :flex-width 1)))
         (right (make-layout-item
                 :right :constraints (make-constraints :flex-width 2)))
         (hbox (make-hbox (list left right) :gap 1))
         (rects (layout-rects hbox (test-rectangle 0 0 10 1)))
         (left-rect (cdr (assoc :left rects)))
         (right-rect (cdr (assoc :right rects))))
    (is-equal 3 (rectangle-width left-rect))
    (is-equal 6 (rectangle-width right-rect))
    (is-equal 4 (rectangle-x right-rect)))
  (let* ((child (make-layout-item
                 :margin
                 :margin (make-margin :left 1 :right 2)))
         (layout (make-stack (list child)))
         (rect (layout-child-rectangle layout :margin
                                       (test-rectangle 0 0 10 2))))
    (is-equal 1 (rectangle-x rect))
    (is-equal 7 (rectangle-width rect)))
  (let* ((children (loop for name in '(:a :b :c :d)
                         collect (make-layout-item
                                  name
                                  :constraints
                                  (make-constraints :preferred-width 3
                                                    :preferred-height 1))))
         (grid (make-grid children :columns 2 :column-gap 1 :row-gap 1))
         (rects (layout-rects grid (test-rectangle 0 0 8 3))))
    (is-equal (test-rectangle 0 0 3 1) (cdr (assoc :a rects)))
    (is-equal (test-rectangle 4 0 3 1) (cdr (assoc :b rects)))
    (is-equal (test-rectangle 0 2 3 1) (cdr (assoc :c rects)))
    (is-equal (test-rectangle 4 2 3 1) (cdr (assoc :d rects)))))

(deftest layout-respects-maximum-before-flex-growth (:layout)
  (let* ((capped (make-layout-item
                  :capped
                  :constraints (make-constraints :preferred-width 5
                                                 :max-width 2)))
         (flexible (make-layout-item
                    :flexible
                    :constraints (make-constraints :preferred-width 1
                                                   :flex-width 1)))
         (rects (layout-rects (make-hbox (list capped flexible))
                              (test-rectangle 0 0 8 1))))
    (is-equal 2 (rectangle-width (cdr (assoc :capped rects))))
    (is-equal 6 (rectangle-width (cdr (assoc :flexible rects))))))

(deftest layout-constructors-and-preferred-size-contracts (:layout)
  (let* ((node (make-layout-node :custom (list (list :a :b))))
         (item (first (layout-children node)))
         (empty (make-layout-node
                 :stack '()
                 :constraints (make-constraints :min-width 2
                                                :preferred-width 5
                                                :min-height 3
                                                :preferred-height 4)))
         (wide (make-layout-node
                :stack '()
                :constraints (make-constraints :preferred-width 3
                                               :preferred-height 2)))
         (tall (make-layout-node
                :stack '()
                :constraints (make-constraints :preferred-width 1
                                               :preferred-height 5)))
         (with-margin (make-layout-item
                       wide
                       :margin (make-margin :left 1 :right 2
                                            :top 3 :bottom 4)))
         (vbox (make-vbox (list (make-layout-item wide)
                                (make-layout-item tall))
                          :gap 1))
         (hbox (make-hbox (list (make-layout-item wide)
                                (make-layout-item tall))
                          :gap 1))
         (grid (make-grid (list (make-layout-item wide)
                                (make-layout-item tall))
                           :columns 2 :column-gap 1 :row-gap 2))
         (horizontal (make-split (list (make-layout-item wide)
                                      (make-layout-item tall))
                                :axis :horizontal))
         (vertical (make-split (list (make-layout-item wide)
                                    (make-layout-item tall))
                              :axis :vertical))
         (padding (make-padding-layout wide
                                       :padding (make-padding :all 1)))
         (border (make-border-layout wide))
         (center (make-center-layout wide))
         (viewport (make-viewport-layout wide))
         (scroll (make-scroll-container wide))
         (unknown (make-layout-node :unknown (list :unknown)))
         (single-split (make-split (list :only)))
         (bounds (test-rectangle 0 0 8 6)))
    (is-equal :custom (layout-kind node))
    (is-equal 2 (length (layout-children node)))
    (is-equal :a (layout-item-child item))
    (is-equal (make-size 5 4) (layout-preferred-size empty))
    (is-equal (make-size 6 9)
              (layout-preferred-size with-margin))
    (is (signals-error (make-layout-node 1 (list :invalid))))
    (is (signals-error (make-vbox (list :invalid) :gap -1)))
    (is (signals-error (make-hbox (list :invalid) :gap -1)))
    (is (signals-error (make-split (list :a :b) :ratio 2)))
    (is (signals-error (make-split (list :a :b) :axis :diagonal)))
    (is (signals-error (make-grid (list :a) :columns 0)))
    (is (signals-error (make-grid (list :a) :columns 1 :rows 0)))
    (is (signals-error (make-grid (list :a) :columns 1 :column-gap -1)))
    (is (signals-error (make-grid (list :a) :columns 1 :row-gap -1)))
    (is-equal (make-size 3 8) (layout-preferred-size vbox))
    (is-equal (make-size 5 5) (layout-preferred-size hbox))
    (is-equal (make-size 5 5) (layout-preferred-size grid))
    (is-equal (make-size 4 5) (layout-preferred-size horizontal))
    (is-equal (make-size 3 7) (layout-preferred-size vertical))
    (is-equal (make-size 5 4) (layout-preferred-size padding))
    (is-equal (make-size 5 4) (layout-preferred-size border))
    (is-equal (make-size 3 2) (layout-preferred-size center))
    (is-equal (make-size 3 2) (layout-preferred-size viewport))
    (is-equal (make-size 3 2) (layout-preferred-size scroll))
    (is-equal (make-size 0 0) (layout-preferred-size unknown))
    (is-equal (test-rectangle 0 0 8 3)
              (cdr (assoc wide
                          (layout-rects vertical bounds))))
    (is-equal (test-rectangle 0 3 8 3)
              (cdr (assoc tall
                          (layout-rects vertical bounds))))
    (is-equal (test-rectangle 1 1 6 4)
              (layout-child-rectangle padding wide bounds))
    (is-equal (test-rectangle 1 1 6 4)
              (layout-child-rectangle border wide bounds))
    (is-equal (test-rectangle 2 2 3 2)
              (layout-child-rectangle center wide bounds))
    (is-equal bounds (layout-child-rectangle viewport wide bounds))
    (is-equal bounds (layout-child-rectangle scroll wide bounds))
    (is-equal bounds (layout-child-rectangle unknown :unknown bounds))
    (is-equal (make-rectangle)
              (layout-child-rectangle single-split :only bounds))
    (let* ((sparse-grid (make-grid (list :only) :columns 2 :rows 2))
           (rects (layout-rects sparse-grid (test-rectangle 0 0 1 1))))
      (is-equal (make-rectangle)
                (cdr (assoc :only rects))))))

(deftest focus-tree-and-modal-restoration (:focus)
  (let* ((first (make-focus-node :first :focusable-p t
                                 :rectangle (test-rectangle 0 0 3 1)))
         (second (make-focus-node :second :focusable-p t
                                  :rectangle (test-rectangle 4 0 3 1)))
         (third (make-focus-node :third :focusable-p t
                                 :rectangle (test-rectangle 9 0 3 1)))
         (modal-child (make-focus-node :modal-input :focusable-p t
                                       :rectangle (test-rectangle 2 2 3 1)))
         (modal (make-focus-node :modal :scope-p t
                                 :children (list modal-child)))
         (root (make-focus-node :root :scope-p t
                                :children (list first second third modal)))
         (tree (make-focus-tree root)))
    (is-equal :first (focus-node-id (focus-tree-current tree)))
    (is-equal :second (focus-node-id (focus-next tree)))
    (is-equal :first (focus-node-id (focus-directional tree :left)))
    (is-equal :second (focus-node-id (focus-directional tree :right)))
    (focus-push-modal tree modal)
    (is-equal :modal-input (focus-node-id (focus-tree-current tree)))
    (is (focus-visible-p tree modal-child))
    (is (signals-error (focus-tree-set-current tree first)))
    (is-equal :modal-input
              (focus-node-id (focus-directional tree :right)))
    (focus-pop-modal tree)
    (is-equal :second (focus-node-id (focus-tree-current tree)))
    (is (not (focus-visible-p tree modal-child)))))

(deftest focus-node-print-object-handles-parent-child-cycle (:focus)
  (let* ((child (make-focus-node :child :focusable-p t))
         (root (make-focus-node :root :scope-p t
                                :children (list child)))
         (root-printed (format nil "~A" root))
         (child-printed (with-output-to-string (stream)
                          (print child stream))))
    (is (focus-node-parent child))
    (is (focus-node-children root))
    (is (stringp root-printed))
    (is (< (length root-printed) 500))
    (is (stringp child-printed))
    (is (< (length child-printed) 500))))

(deftest lazy-list-selection-and-virtualization (:list)
  (let ((calls 0)
        (items (loop for index below 100 collect (format nil "item-~D" index))))
    (let* ((model (make-list-model
                   :count (length items)
                   :item-at (lambda (index)
                              (incf calls)
                              (nth index items))
                   :key-at (lambda (item index)
                             (declare (ignore item))
                             (format nil "key-~D" index))))
           (widget (make-list-widget model
                                     :rectangle (test-rectangle 0 0 20 3)
                                     :selected-key "key-0"
                                     :focusable-p t))
           (visible (list-widget-visible-items widget)))
      (is-equal 3 (length visible))
      (is (< calls 10))
      (is-equal "key-0" (getf (first visible) :key))
      (list-widget-select-key widget "key-7")
      (is-equal "key-7" (list-widget-selected-key widget))
      (is-equal 5 (list-widget-offset widget)))))

(deftest model-count-contracts (:models)
  (is (signals-error
       (make-list-model :count -1 :item-at #'identity)))
  (let ((model (make-list-model :count (lambda () -1)
                                :item-at #'identity)))
    (is (signals-error (list-model-count model))))
  (is (signals-error
       (make-tree-model :root-count -1
                        :root-at #'identity
                        :key-at #'identity
                        :label-at #'identity)))
  (let ((model (make-tree-model :root-count (lambda () -1)
                                :root-at #'identity
                                :key-at #'identity
                                :label-at #'identity)))
    (is (signals-error (tree-model-root-count model)))))

(deftest ansi-color-capability-fallback (:ansi)
  (let ((style (make-style :foreground (rgb-color 255 100 10)
                           :background (rgb-color 1 2 3)
                           :bold t)))
    (is (search "38;2;" (ansi-encode-style style :color-capability :truecolor)))
    (is (search "38;5;" (ansi-encode-style style :color-capability :256)))
    (is (not (search "38;2;" (ansi-encode-style style :color-capability :basic))))
    (is (not (search "38;2;" (ansi-encode-style style :color-capability :none))))))

(deftest lazy-tree-input-viewport-and-modal (:widgets)
  (let* ((expanded (make-hash-table :test #'equal))
         (children (lambda (node)
                     (case node
                       (:root '(:child-a :child-b))
                       (otherwise nil))))
         (tree-model (make-tree-model
                      :root-count 1 :root-at (lambda (index)
                                               (declare (ignore index)) :root)
                      :children children
                      :expanded-p (lambda (node)
                                    (gethash node expanded))
                      :key-at (lambda (node) node)
                      :label-at (lambda (node) (symbol-name node))))
         (tree (make-tree-widget tree-model
                                 :rectangle (test-rectangle 0 0 20 3)
                                 :selected-key :root)))
    (setf (gethash :root expanded) t)
    (is-equal :toggle
              (action-name (tree-widget-toggle-expanded tree)))
    (let ((input (make-input-widget :value "abc")))
      (handle-widget-event input (make-text-input-event "X"))
      (is-equal "abcX" (input-widget-value input))
      (handle-widget-event input (make-key-event :backspace))
      (is-equal "abc" (input-widget-value input))
      (is-equal :submit
                (action-name (handle-widget-event input
                                                  (make-key-event :enter)))))
    (let* ((child (make-text-widget "content"))
           (viewport (make-viewport-widget child
                                            :rectangle (test-rectangle 0 0 5 2)
                                            :content-width 20
                                            :content-height 10)))
      (handle-widget-event viewport (make-key-event :down))
      (is-equal 1 (viewport-offset-y (viewport-widget-viewport viewport))))
    (let ((modal (make-modal-widget (make-text-widget "dialog") :open-p t)))
      (is (modal-widget-open-p modal))
      (is-equal :close
                (action-name (handle-widget-event modal
                                                  (make-key-event :escape)))))))
