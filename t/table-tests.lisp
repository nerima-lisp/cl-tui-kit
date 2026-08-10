(in-package #:cl-tui-kit/tests)

(deftest table-text-and-surface-contracts (:table-surface-text)
  (is (signals-error (make-table-column "Bad" :width -1)))
  (is (signals-error (make-table-column "Bad" :align :diagonal)))
  (is (signals-error (make-table-widget nil nil :row-height 0)))
  (let* ((columns (list (make-table-column "A" :key 0 :width 3)
                        (make-table-column "B" :key :name :width 8)
                        (make-table-column "C" :key -1 :width 3)
                        (make-table-column "D"
                                           :key (lambda (row)
                                                  (if (vectorp row) "V" "L"))
                                           :width 3)))
         (rows (list #("a" "vector")
                     (list :name "plist")
                     "scalar"))
         (table (make-table-widget
                 columns rows :selected-row 0
                 :rectangle (test-rectangle 0 0 20 4)))
         (surface (make-surface 20 4)))
    (widget-layout table (test-rectangle 0 0 20 4))
    (widget-render table surface)
    (is (search "vector" (surface-string surface)))
    (dolist (key '(:down :right :up :left :home :end :page-up :page-down))
      (is (widget-handle-event table (make-key-event key))))
    (is-equal :select
              (action-name (widget-handle-event
                            table (make-key-event :enter))))
    (table-widget-set-rows table nil)
    (is (null (table-widget-selected-row table)))
    (is (null (widget-handle-event table (make-key-event :home)))))
  (let* ((columns (list (make-table-column "Right" :width 5 :align :right)
                        (make-table-column "Center" :width 5 :align :center)))
         (table (make-table-widget
                 columns (list (list "x" "y")) :selected-row 0
                 :rectangle (test-rectangle 0 0 10 3)))
         (surface (make-surface 10 3)))
    (widget-layout table (test-rectangle 0 0 10 3))
    (widget-render table surface)
    (is (search "    x" (surface-string surface)))
    (is (search "  y  " (surface-string surface)))
    (is-equal 13 (size-width (widget-preferred-size table)))
    (is-equal 2 (size-height (widget-preferred-size table)))
    (let ((info (widget-accessibility-tree table)))
      (is-equal :grid (getf info :role))
      (is-equal 1 (getf (getf info :state) :row-count))
      (is-equal 2 (getf (getf info :state) :column-count)))
    (is (null (widget-handle-event table
                                   (make-mouse-event 0 0 :button :left))))
    (is (null (widget-handle-event table
                                   (make-mouse-event 10 1 :button :left))))
    (is (null (widget-handle-event table
                                   (make-mouse-event 1 1 :kind :release)))))
  (let* ((table (make-table-widget
                 (list (make-table-column "A")
                       (make-table-column "B"))
                 (list (list "wide" "x"))
                 :header-p nil :rectangle (test-rectangle 0 0 12 1)))
         (surface (make-surface 12 1)))
    (widget-layout table (test-rectangle 0 0 12 1))
    (widget-render table surface)
    (is (search "wide" (surface-string surface)))
    (let ((shrunken (make-table-widget
                     (list (make-table-column "A" :width 4 :min-width 2)
                           (make-table-column "B" :width 4 :min-width 2))
                     (list (list "abcd" "efgh"))
                     :header-p nil :rectangle (test-rectangle 0 0 5 1)))
          (shrunken-surface (make-surface 5 1)))
      (widget-layout shrunken (test-rectangle 0 0 5 1))
      (widget-render shrunken shrunken-surface)
      (is (search "abefg" (surface-string shrunken-surface)))))
  (let ((table (make-table-widget
                (list (make-table-column "A" :width 2)
                      (make-table-column "B" :width 2))
                (list (list "a" "b") (list "c" "d")) :selected-row 1
                :rectangle (test-rectangle 0 0 3 2))))
    (is-equal :move
              (action-name (widget-handle-event table (make-key-event :k-up))))
    (is-equal :move
              (action-name (widget-handle-event table (make-key-event :k-down))))
    (is-equal :move
              (action-name (widget-handle-event table (make-key-event :prior))))
    (is-equal :move
              (action-name (widget-handle-event table
                                                (make-key-event :previous-page))))
    (is-equal :move
              (action-name (widget-handle-event table
                                                (make-key-event :next-page))))
    (is-equal :select
              (action-name (widget-handle-event table (make-key-event :return))))
    (is (null (table-widget-select-row table 99)))
    (is (null (table-widget-select-column table 99)))
    (is (null (widget-handle-event table (make-custom-event :noop)))))
  (let ((ambiguous (code-char #x391)))
    (is-equal 1 (cell-width ambiguous))
    (is-equal 2 (with-ambiguous-width (:wide)
                  (cell-width ambiguous)))
    (is-equal "a  b" (clip-text (format nil "a~Cbc" #\Tab) 4 :tab-width 3))
    (is-equal "" (truncate-text "abcdef" 0))
    (is-equal "." (truncate-text "abcdef" 1 :ellipsis "..."))
    (is (signals-error (string-cell-width "x" :tab-width 0)))
    (is (signals-error (clip-text "x" 2 :tab-width 0)))
    (is (signals-error (truncate-text "x" -1))))
  (let ((surface (make-surface 6 4)))
    (surface-fill surface #\x)
    (is (search "xxxxxx" (surface-string surface)))
    (surface-clear surface (test-rectangle 0 0 2 1))
    (is (search "  xxxx" (surface-string surface)))
    (dolist (kind '(:double :rounded :ascii :single))
      (surface-draw-border surface (test-rectangle 0 0 6 4) :kind kind))
    (surface-draw-text surface 0 0 (format nil "a~Cb" #\Tab) :tab-width 2)
    (surface-draw-styled-text
     surface 0 1 (list (make-text-span "styled")) :max-width 4)
    (is (signals-error (make-surface -1 1)))
    (is (signals-error (make-cell "x" :bogus t)))
    (is (signals-error (surface-draw-text surface 0 0 "x" :tab-width 0)))
    (is (signals-error (surface-set-clip surface :invalid)))
    (let ((old-clip (surface-clip surface)))
      (catch 'escaped
        (with-surface-clip (surface (test-rectangle 0 0 1 1))
          (throw 'escaped :done)))
      (is (equalp old-clip (surface-clip surface))))))

(deftest inactive-modal-descendants-are-not-interactive (:focus)
  (let* ((input (make-input-widget :value ""))
         (modal (make-modal-widget input
                                   :rectangle (test-rectangle 0 0 20 8)
                                   :open-p nil))
         (root (make-box-widget modal
                                :rectangle (test-rectangle 0 0 20 8)))
         (event (make-text-input-event "X")))
    (widget-layout root (test-rectangle 0 0 20 8))
    (is (null (getf (widget-accessibility-tree modal) :children)))
    (is (not (eq input (widget-hit-test root 1 1))))
    (is (null (dispatch-widget-event root event input)))
    (is-equal "" (input-widget-value input))
    (modal-widget-open modal)
    (let ((area (widget-rectangle input)))
      (is (eq input (widget-hit-test root
                                     (rectangle-x area)
                                     (rectangle-y area))))
      (dispatch-widget-event root event input)
      (is-equal "X" (input-widget-value input)))
    (is-equal :close
              (action-name
               (dispatch-widget-event root (make-key-event :escape) input)))
    (is (not (modal-widget-open-p modal)))
    (modal-widget-close modal)
    (is (null (getf (widget-accessibility-tree modal) :children)))))
