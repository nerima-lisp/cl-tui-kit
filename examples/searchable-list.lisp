(defpackage #:cl-tui-kit/examples
  (:use #:cl #:cl-tui-kit)
  (:export
   #:searchable-list-demo
   #:make-searchable-list-demo
   #:searchable-list-demo-backend
   #:searchable-list-demo-input
   #:searchable-list-demo-list
   #:searchable-list-demo-modal
   #:searchable-list-demo-focus-tree
   #:searchable-list-demo-render
   #:searchable-list-demo-handle-event))

(in-package #:cl-tui-kit/examples)

;;;; This example deliberately contains no domain model beyond generic items
;;;; with a stable key and a label.  It is a small integration surface for
;;;; layout, focus, keymaps, selection, lazy filtering, overlays, resize
;;;; events, and the structured test backend.

(defun %default-items ()
  (loop for label in '("Alpha" "Bravo" "Charlie" "Delta" "Echo"
                       "Foxtrot" "Golf" "Hotel" "India" "Juliett"
                       "Kilo" "Lima" "Mike" "November" "Oscar"
                       "Papa" "Quebec" "Romeo" "Sierra" "Tango"
                       "Uniform" "Victor" "Whiskey" "X-ray" "Yankee"
                       "Zulu")
        for index from 0
        collect (list :key (format nil "item-~D" index)
                      :label label)))

(defstruct (searchable-list-demo
            (:constructor %make-searchable-list-demo
                (backend items input list status modal body-layout overlay-layout
                 focus-tree modal-node keymap keymap-state)))
  backend
  items
  input
  list
  status
  modal
  body-layout
  overlay-layout
  focus-tree
  modal-node
  keymap
  keymap-state)

(defun %filtered-items (demo)
  (let ((needle (string-downcase (input-widget-value
                                  (searchable-list-demo-input demo)))))
    (if (zerop (length needle))
        (searchable-list-demo-items demo)
        (remove-if-not
         (lambda (item)
           (not (null (search needle
                              (string-downcase (getf item :label))))))
         (searchable-list-demo-items demo)))))

(defun %ensure-selection (demo)
  (let ((visible (list-widget-visible-items
                  (searchable-list-demo-list demo))))
    (when (and visible
               (not (find (list-widget-selected-key
                           (searchable-list-demo-list demo))
                          visible
                          :key (lambda (entry) (getf entry :key))
                          :test #'equalp)))
      (list-widget-select-key (searchable-list-demo-list demo)
                              (getf (first visible) :key)))))

(defun %update-status (demo width height)
  (let ((selected (or (list-widget-selected-key
                       (searchable-list-demo-list demo))
                      "-")))
    (setf (status-bar-widget-text (searchable-list-demo-status demo))
          (format nil "filter: ~A  selected: ~A  ? help  q quit  ~Dx~D"
                  (input-widget-value (searchable-list-demo-input demo))
                  selected width height))))

(defun %render-demo (demo)
  (let* ((backend (searchable-list-demo-backend demo))
         (size (backend-size backend))
         (width (size-width size))
         (height (size-height size))
         (bounds (make-rectangle 0 0 width height))
         (surface (make-surface width height))
         (body (searchable-list-demo-body-layout demo))
         (overlay (searchable-list-demo-overlay-layout demo))
         (body-rectangle (layout-child-rectangle overlay body bounds))
         (input (searchable-list-demo-input demo))
         (list-widget (searchable-list-demo-list demo))
         (status (searchable-list-demo-status demo)))
    (%ensure-selection demo)
    (%update-status demo width height)
    (surface-clear surface)
    (render-widget input surface (layout-child-rectangle body input body-rectangle))
    (render-widget list-widget
                   surface
                   (layout-child-rectangle body list-widget body-rectangle))
    (render-widget status surface (layout-child-rectangle body status body-rectangle))
    (render-widget (searchable-list-demo-modal demo) surface bounds)
    (setf (focus-node-rectangle
           (searchable-list-demo-modal-node demo)) bounds)
    (backend-begin-frame backend)
    (backend-present backend surface)
    (backend-flush backend)
    surface))

(defun make-searchable-list-demo (&key items size backend)
  (let* ((actual-items (or items (%default-items)))
         (actual-size (or size (make-size 40 12)))
         (actual-backend (or backend (make-test-backend :size actual-size)))
         (input (make-input-widget :placeholder "filter"
                                   :id :filter
                                   :focusable-p t))
         (status (make-status-bar-widget "" :id :status))
         (modal-child (make-text-widget
                       "Help: type to filter, j/k move, Tab focus, Esc close."
                       :role :foreground))
         (modal (make-modal-widget modal-child
                                   :id :help
                                   :open-p nil
                                   :focusable-p t))
         (demo nil))
    (setf demo
          (let* ((model (make-list-model
                         :count (lambda () (length (%filtered-items demo)))
                         :item-at (lambda (index)
                                    (nth index (%filtered-items demo)))
                         :key-at (lambda (item index)
                                   (declare (ignore index))
                                   (getf item :key))
                         :label-at (lambda (item index)
                                     (declare (ignore index))
                                     (getf item :label))))
                 (list-widget (make-list-widget model
                                                :id :items
                                                :selected-key (getf (first actual-items)
                                                                    :key)
                                                :focusable-p t))
                 (body (make-vbox
                        (list
                         (make-layout-item input
                                           :constraints
                                           (make-constraints :min-height 1
                                                             :preferred-height 1))
                         (make-layout-item list-widget
                                           :constraints
                                           (make-constraints :flex-height 1))
                         (make-layout-item status
                                           :constraints
                                           (make-constraints :min-height 1
                                                             :preferred-height 1)))))
                 (overlay (make-overlay (list body modal)))
                 (modal-node (make-focus-node :help
                                              :widget modal
                                              :focusable-p t
                                              :scope-p t))
                 (focus-tree (make-focus-tree
                              (make-focus-node
                               :root
                               :scope-p t
                               :children
                               (list (make-focus-node :filter
                                                       :widget input
                                                       :focusable-p t)
                                     (make-focus-node :items
                                                      :widget list-widget
                                                      :focusable-p t)
                                     modal-node))))
                 (keymap (make-keymap :name :searchable-list))
                 (keymap-state (make-keymap-state)))
            (bind-key keymap #\? :open-help)
            (bind-key keymap #\q :quit)
            (bind-key keymap #\j :next)
            (bind-key keymap #\k :previous)
            (bind-key keymap :tab :focus-next)
            (bind-key keymap :backtab :focus-previous)
            (bind-key keymap (list #\g #\g) :top)
            (%make-searchable-list-demo actual-backend actual-items input list-widget status
                                         modal body overlay focus-tree modal-node
                                         keymap keymap-state)))
    (%render-demo demo)
    demo))

(defun %focus-widget (demo)
  (focus-node-widget (focus-tree-current
                      (searchable-list-demo-focus-tree demo))))

(defun %handle-global-action (demo action)
  (case (and action (action-name action))
    (:open-help
     (modal-widget-open (searchable-list-demo-modal demo))
     (focus-push-modal (searchable-list-demo-focus-tree demo)
                       (searchable-list-demo-modal-node demo))
     action)
    (:close
     (modal-widget-close (searchable-list-demo-modal demo))
     (focus-pop-modal (searchable-list-demo-focus-tree demo))
     action)
    (:quit action)
    (:focus-next
     (focus-next (searchable-list-demo-focus-tree demo))
     action)
    (:focus-previous
     (focus-previous (searchable-list-demo-focus-tree demo))
     action)
    (:next
     (handle-widget-event (searchable-list-demo-list demo)
                          (make-key-event :down)))
    (:previous
     (handle-widget-event (searchable-list-demo-list demo)
                          (make-key-event :up)))
    (:top
     (handle-widget-event (searchable-list-demo-list demo)
                          (make-key-event :home)))
    (otherwise action)))

(defun searchable-list-demo-render (demo)
  (%render-demo demo))

(defun searchable-list-demo-handle-event (demo event)
  (let ((action
          (cond
            ((typep event 'resize-event)
             (backend-resize (searchable-list-demo-backend demo)
                             (resize-event-width event)
                             (resize-event-height event))
             (custom-action :resize
                            (list :width (resize-event-width event)
                                  :height (resize-event-height event))
                            demo))
            ((modal-widget-open-p (searchable-list-demo-modal demo))
             (handle-widget-event (searchable-list-demo-modal demo) event))
            ((typep event 'text-input-event)
             (handle-widget-event (%focus-widget demo) event))
            ((typep event 'key-event)
             (let ((result (keymap-dispatch
                            (searchable-list-demo-keymap demo)
                            (searchable-list-demo-keymap-state demo)
                            event)))
               (if (eq (keymap-result-status result) :handled)
                   (%handle-global-action demo (keymap-result-action result))
                   (handle-widget-event (%focus-widget demo) event))))
            ((eq (event-kind event) :custom) nil)
            (t nil))))
    (when (or action (typep event 'resize-event)
              (typep event 'text-input-event))
      (%render-demo demo))
    action))
