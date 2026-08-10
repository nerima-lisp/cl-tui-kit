(defpackage #:cl-tui-kit/core
  (:use #:cl)
  (:export
   ;; Geometry
   #:point #:point-x #:point-y #:make-point #:copy-point
   #:size #:size-width #:size-height #:make-size #:copy-size
   #:rectangle #:rectangle-x #:rectangle-y #:rectangle-width #:rectangle-height
   #:make-rectangle #:copy-rectangle #:rectangle-empty-p
   #:rectangle-right #:rectangle-bottom #:rectangle-contains-point-p
   #:rectangle-contains-rectangle-p #:rectangle-intersection
   #:rectangle-union #:rectangle-inset #:rectangle-offset
   #:padding #:padding-top #:padding-right #:padding-bottom #:padding-left
   #:make-padding #:copy-padding
   #:margin #:margin-top #:margin-right #:margin-bottom #:margin-left
   #:make-margin #:copy-margin
   #:constraints #:constraints-min-width #:constraints-preferred-width
   #:constraints-max-width #:constraints-min-height #:constraints-preferred-height
   #:constraints-max-height #:constraints-flex-width #:constraints-flex-height
   #:make-constraints #:copy-constraints #:resolve-axis
   #:clipping-region #:clipping-region-rectangle #:make-clipping-region
   #:viewport #:viewport-bounds #:viewport-content-width #:viewport-content-height
   #:viewport-offset-x #:viewport-offset-y #:make-viewport
   #:viewport-visible-rectangle #:viewport-scroll-to #:viewport-scroll-by
   #:viewport-scroll-x-max #:viewport-scroll-y-max
   ;; Style and theme
   #:color #:color-kind #:color-value #:make-color #:default-color
   #:named-color #:indexed-color #:rgb-color #:color=
   #:style #:style-foreground #:style-background #:style-bold #:style-dim
   #:style-italic #:style-underline #:style-reverse #:style-strike
   #:make-style #:copy-style #:style= #:merge-styles
   #:theme #:make-theme #:copy-theme #:theme-style #:theme-set-style
   #:default-theme
   ;; Text and cell width
   #:*ambiguous-width* #:with-ambiguous-width #:cell-width
   #:text-units #:text-unit-width #:string-cell-width
   #:truncate-text #:clip-text
   ;; Surfaces
   #:cell #:cell-p #:cell-content #:cell-style #:cell-span #:cell-continuation-p
   #:make-cell #:copy-cell #:blank-cell
   #:text-span #:text-span-p #:text-span-text #:text-span-style #:make-text-span
   #:surface #:surface-p #:surface-width #:surface-height #:make-surface #:copy-surface
   #:surface-default-style
   #:surface-cell #:surface-put-cell #:surface-clear #:surface-fill
   #:surface-fill-rectangle #:surface-draw-text #:surface-draw-styled-text
   #:surface-draw-border
   #:surface-blit #:surface-clip #:surface-set-clip #:call-with-surface-clip
   #:with-surface-clip
   #:surface-dirty-regions #:surface-mark-clean #:surface-mark-dirty
   #:cell-change #:cell-change-x #:cell-change-y #:cell-change-before
   #:cell-change-after #:surface-diff #:surface-string
   ;; Normalized events
   #:event #:event-kind #:key-event #:key-event-key #:key-event-modifiers
   #:key-event-text #:key-event-phase #:make-key-event
   #:text-input-event #:text-input-event-text
   #:make-text-input-event #:paste-event #:paste-event-text #:make-paste-event
   #:clipboard-event #:clipboard-event-selection #:clipboard-event-text
   #:make-clipboard-event
   #:resize-event #:resize-event-width #:resize-event-height #:make-resize-event
   #:mouse-event #:mouse-event-x #:mouse-event-y #:mouse-event-button
   #:mouse-event-kind #:mouse-event-modifiers #:make-mouse-event
   #:focus-event #:focus-event-focused-p #:focus-event-reason #:make-focus-event
   #:tick-event #:tick-event-time #:make-tick-event
   #:custom-event #:custom-event-name #:custom-event-payload #:make-custom-event
   #:event-p #:normalize-modifiers
   ;; Incremental terminal input normalization
   #:terminal-input-parser #:make-terminal-input-parser
   #:terminal-input-parser-buffer #:terminal-input-parser-pending-octets
   #:terminal-input-parser-in-paste-p #:terminal-input-parser-paste-buffer
   #:terminal-input-parser-max-sequence-length
   #:terminal-input-parser-max-paste-length
   #:terminal-input-parser-feed #:terminal-input-parser-flush
   #:terminal-input-parser-reset #:terminal-input-parser-pending-p
   #:terminal-event-source #:terminal-event-source-reader
   #:terminal-event-source-parser #:terminal-event-source-eof-value
   #:terminal-event-source-eof-p #:terminal-event-source-closed-p
   #:make-terminal-event-source #:terminal-event-source-next
   #:terminal-event-source-close #:terminal-event-source-pending-p
   #:make-stream-event-source
   ;; Deterministic event loop
   #:event-loop-task #:event-loop-task-id #:event-loop-task-deadline
   #:event-loop-task-repeat #:event-loop-task-cancelled-p
   #:event-loop #:make-event-loop #:event-loop-clock
   #:event-loop-event-handler #:event-loop-error-handler
   #:event-loop-now #:event-loop-post #:event-loop-schedule
   #:event-loop-schedule-event #:event-loop-cancel #:event-loop-step
   #:event-loop-run #:event-loop-stop #:event-loop-running-p
   #:event-loop-stopped-p #:event-loop-pending-p
   #:event-loop-pending-event-p #:event-loop-pending-task-count
   #:event-loop-next-deadline #:event-loop-wakeup #:event-loop-wakeup-p
   #:event-loop-clear-wakeup
   ;; Actions
   #:action #:action-name #:action-payload #:action-source #:make-action
   #:activate-action #:cancel-action #:submit-action #:move-action
   #:select-action #:toggle-action #:open-action #:close-action #:custom-action
   ;; Keymaps
   #:key-stroke #:key-stroke-key #:key-stroke-modifiers #:make-key-stroke
   #:keymap #:make-keymap #:keymap-name #:keymap-parent #:keymap-mode
   #:set-keymap-mode #:keymap-prefix-timeout #:set-keymap-prefix-timeout
   #:bind-key #:unbind-key #:define-keymap #:define-keymap-mode #:keymap-mode-map
   #:keymap-state #:make-keymap-state #:keymap-state-pending
   #:keymap-state-pending-since #:keymap-state-prefix-active-p
   #:reset-keymap-state #:keymap-dispatch #:keymap-expire-prefix
   #:dispatch-keymaps
   #:keymap-result-status #:keymap-result-action #:keymap-result-prefix
   #:vi-like-keymap
   ;; Backend protocol
   #:backend #:make-backend #:backend-size #:backend-resize
   #:backend-capabilities #:backend-cursor #:backend-cursor-visible
   #:backend-title #:backend-alternate-screen-p #:backend-state
   #:backend-last-error
   #:backend-open #:backend-close #:backend-fail
   #:backend-begin-frame
   #:backend-present #:backend-flush #:backend-set-cursor
   #:backend-set-cursor-visible #:backend-enter-alternate
   #:backend-leave-alternate #:backend-set-title #:backend-resized
   #:backend-invalidate #:backend-clear-title #:backend-reset-output
   #:backend-capabilities-color #:backend-capabilities-unicode
   #:backend-capabilities-mouse #:backend-capabilities-clipboard
   #:backend-capabilities-alternate-screen
   #:make-backend-capabilities #:backend-capability #:backend-supports-p
   #:backend-capability-state #:backend-capability-states
   #:backend-set-capability #:backend-set-capability-state
   #:backend-write-clipboard #:backend-read-clipboard
   #:backend-request-clipboard
   ;; Continuation-oriented protocol helpers
   #:dispatch-event/k #:present-frame/k))

(defpackage #:cl-tui-kit/layout
  (:use #:cl #:cl-tui-kit/core)
  (:export
   #:layout-node #:layout-kind #:layout-children #:layout-item
   #:layout-item-child #:layout-item-constraints #:layout-item-margin
   #:make-layout-item
   #:make-layout-node #:make-vbox #:make-hbox #:make-stack #:make-overlay
   #:make-split #:make-padding-layout #:make-border-layout #:make-center-layout
   #:make-viewport-layout #:make-scroll-container #:make-grid
   #:layout-rects #:layout-child-rectangle #:layout-preferred-size
   #:focus-node #:focus-node-id #:focus-node-widget #:focus-node-children
   #:focus-node-parent #:focus-node-rectangle #:focus-node-focusable-p
   #:focus-node-scope-p #:make-focus-node #:focus-tree #:make-focus-tree
   #:focus-tree-root #:focus-tree-current #:focus-tree-modal-stack
   #:focus-tree-set-current #:focus-next #:focus-previous
   #:focus-directional #:focus-push-modal #:focus-pop-modal
   #:focus-restore #:focus-visible-p))

(defpackage #:cl-tui-kit/widgets
  (:use #:cl #:cl-tui-kit/core #:cl-tui-kit/layout)
  (:export
   #:widget #:widget-id #:widget-rectangle #:widget-style #:widget-theme
   #:widget-keymap #:widget-focusable-p #:widget-enabled-p #:widget-children
   #:widget-role #:widget-label #:widget-description #:widget-help-text
   #:make-widget #:widget-preferred-size #:widget-layout #:widget-render
   #:widget-handle-event #:widget-handle-child-action #:widget-cursor-position
   #:widget-accessibility-state #:widget-accessibility-info
   #:widget-active-p #:widget-interactive-children #:widget-capture-event-p
   #:widget-accessibility-tree
   #:render-widget #:handle-widget-event
   #:text-widget #:make-text-widget #:text-widget-text
   #:box-widget #:make-box-widget #:box-widget-child
   #:divider-widget #:make-divider-widget
   #:button-widget #:make-button-widget #:button-widget-label
   #:button-widget-action
   #:checkbox-widget #:make-checkbox-widget #:checkbox-widget-label
   #:checkbox-widget-checked-p #:checkbox-widget-action
   #:progress-widget #:make-progress-widget #:progress-widget-value
   #:progress-widget-maximum #:progress-widget-label
   #:text-view-widget #:make-text-view-widget #:text-view-widget-text
   #:text-view-widget-wrap-p #:text-view-widget-offset
   #:text-view-widget-search-query #:text-view-widget-scroll-to
   #:text-view-widget-scroll-by #:text-view-widget-find
   #:tab-entry #:make-tab #:tab-entry-key #:tab-entry-label
   #:tab-entry-content #:tab-entry-enabled-p
   #:tabs-widget #:make-tabs-widget #:tabs-widget-tabs
   #:tabs-widget-selected-index #:tabs-widget-select
   #:menu-item #:make-menu-item #:menu-item-label #:menu-item-action
   #:menu-item-enabled-p #:menu-item-submenu #:menu-item-key
   #:menu-widget #:make-menu-widget #:menu-widget-items
   #:menu-widget-selected-index #:menu-widget-open-p
   #:menu-widget-active-submenu #:menu-widget-select
   #:table-column #:make-table-column #:table-column-label
   #:table-column-key #:table-column-width #:table-column-min-width
   #:table-column-align
   #:table-widget #:make-table-widget #:table-widget-columns
   #:table-widget-rows #:table-widget-selected-row
   #:table-widget-selected-column #:table-widget-row-offset
   #:table-widget-select-row #:table-widget-select-column
   #:table-widget-set-rows
   #:notification #:make-notification #:notification-id
   #:notification-message #:notification-level #:notification-expires-at
   #:notification-center-widget #:make-notification-center
   #:notification-center-notifications #:notification-center-push
   #:notification-center-dismiss #:notification-center-clear
   #:notification-center-tick
   #:form-widget #:make-form-widget #:form-widget-fields
   #:form-widget-validator #:form-widget-errors #:form-widget-values
   #:form-widget-validate #:form-widget-submit
   #:application #:make-application #:application-backend #:application-root
   #:application-surface #:application-focus-tree
   #:application-keymap-state #:application-running-p #:application-dirty-p
   #:application-last-action #:application-alternate-screen-p
   #:application-title #:make-widget-focus-tree
   #:application-refresh-focus-tree #:application-layout
   #:application-invalidate #:application-render/k #:application-render
   #:widget-hit-test #:dispatch-widget-event #:application-dispatch-event
   #:application-step/k #:application-step
   #:application-start #:application-stop #:application-close
   #:call-with-application-session #:with-application-session
   #:application-run
   #:list-model #:make-list-model #:list-model-count #:list-model-item-at
   #:list-model-key-at #:list-model-label-at #:list-model-render-item
   #:list-widget #:make-list-widget
   #:list-widget-model #:list-widget-selected-key #:list-widget-offset
   #:list-widget-row-height #:list-widget-selected-index
   #:list-widget-select-key #:list-widget-page-up #:list-widget-page-down
   #:list-widget-refresh #:list-widget-visible-items
   #:tree-model #:make-tree-model #:tree-model-root-count
   #:tree-model-root-at #:tree-model-key-at #:tree-model-label-at
   #:tree-model-children #:tree-model-expanded-p #:tree-model-render-item
   #:tree-widget #:make-tree-widget #:tree-widget-selected-key
   #:tree-widget-offset #:tree-widget-selected-index
   #:tree-widget-page-up #:tree-widget-page-down #:tree-widget-refresh
   #:tree-widget-toggle-expanded
   #:input-widget #:make-input-widget #:input-widget-value
   #:input-widget-cursor #:input-widget-scroll-offset
   #:input-widget-placeholder #:input-widget-selection-anchor
   #:input-widget-selection-start #:input-widget-selection-end
   #:input-widget-selected-text #:input-widget-clear-selection
   #:input-widget-undo #:input-widget-redo #:input-widget-max-history
   #:textarea-widget #:make-textarea-widget
   #:textarea-widget-preferred-rows #:textarea-widget-soft-wrap-p
   #:textarea-widget-submit-on-enter-p #:textarea-widget-line-scroll-offset
   #:radio-widget #:make-radio-widget #:radio-widget-options
   #:radio-widget-selected-index #:radio-widget-selected-option
   #:radio-widget-wrap-p #:radio-widget-select
   #:select-widget #:make-select-widget #:select-widget-options
   #:select-widget-selected-index #:select-widget-selected-option
   #:select-widget-open-p #:select-widget-visible-rows
   #:select-widget-select #:select-widget-toggle
   #:spinner-widget #:make-spinner-widget #:spinner-widget-frames
   #:spinner-widget-index #:spinner-widget-current-frame
   #:spinner-widget-running-p #:spinner-widget-tick #:spinner-widget-toggle
   #:viewport-widget #:make-viewport-widget #:viewport-widget-viewport
   #:modal-widget #:make-modal-widget #:modal-widget-open-p
   #:modal-widget-open #:modal-widget-close #:modal-widget-result
   #:modal-widget-close-reason #:modal-widget-buttons
   #:modal-widget-outside-close-p
   #:status-bar-widget #:make-status-bar-widget #:status-bar-widget-text
   #:scroll-bar-widget #:make-scroll-bar-widget))

(defpackage #:cl-tui-kit/ansi
  (:use #:cl #:cl-tui-kit/core)
  (:export #:ansi-backend #:make-ansi-backend #:ansi-backend-stream
           #:ansi-backend-previous-surface #:ansi-backend-mouse-mode
           #:ansi-backend-mouse-sgr-p
           #:ansi-backend-bracketed-paste-enabled-p
           #:ansi-backend-focus-reporting-enabled-p
           #:ansi-backend-kitty-keyboard-flags
           #:ansi-backend-synchronized-updates-enabled-p
           #:ansi-encode-style #:ansi-enable-mouse-reporting
           #:ansi-request-clipboard
           #:ansi-disable-mouse-reporting #:ansi-enable-bracketed-paste
           #:ansi-disable-bracketed-paste #:ansi-enable-focus-reporting
           #:ansi-disable-focus-reporting #:ansi-enable-kitty-keyboard
           #:ansi-disable-kitty-keyboard #:ansi-enable-synchronized-updates
           #:ansi-disable-synchronized-updates))

(defpackage #:cl-tui-kit/testing
  (:use #:cl #:cl-tui-kit/core)
  (:export #:test-backend #:make-test-backend #:test-backend-frames
   #:test-backend-last-frame #:test-backend-recorded-events
           #:test-backend-operations
           #:test-backend-emit #:event-replay #:event-replay-events
           #:event-replay-index #:event-replay-eof-value
           #:make-event-replay #:event-replay-next #:event-replay-reset
           #:event-replay-exhausted-p #:event-replay-remaining-count
           #:test-backend-event-replay #:test-backend-reset
           #:surface-equal-p #:surface-cell-string #:assert-surface-text))

(defpackage #:cl-tui-kit/tty
  (:use #:cl #:cl-tui-kit/core #:cl-tui-kit/ansi)
  (:export #:tty-backend #:make-tty-backend #:tty-backend-refresh-size
           #:tty-runtime #:make-tty-runtime #:tty-runtime-input-stream
           #:tty-runtime-file-descriptor #:tty-runtime-parser
           #:tty-runtime-read-size #:tty-runtime-raw-mode-p
           #:tty-runtime-close-input-p #:tty-runtime-eof-value
           #:tty-runtime-started-p #:tty-runtime-raw-mode-enabled-p
           #:tty-runtime-input-closed-p #:tty-runtime-eof-p
           #:tty-runtime-last-error #:tty-runtime-start #:tty-runtime-stop
           #:tty-runtime-close #:tty-runtime-reset
           #:tty-runtime-next-event #:tty-runtime-poll
           #:tty-runtime-event-source #:call-with-tty-runtime
           #:with-tty-runtime))

(defpackage #:cl-tui-kit/codec
  (:use #:cl)
  (:export #:string-to-utf8-octets #:write-utf8))

(defpackage #:cl-tui-kit
  (:use #:cl #:cl-tui-kit/core #:cl-tui-kit/layout #:cl-tui-kit/widgets
        #:cl-tui-kit/ansi #:cl-tui-kit/testing))
