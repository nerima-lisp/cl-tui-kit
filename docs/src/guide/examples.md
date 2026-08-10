# Examples

The repository contains a domain-neutral searchable-list example at
examples/searchable-list.lisp.

Load it through the examples system:

    (asdf:load-system "cl-tui-kit/examples")

    (let ((demo (cl-tui-kit/examples:make-searchable-list-demo)))
      (cl-tui-kit/examples:searchable-list-demo-render demo)
      (cl-tui-kit/examples:searchable-list-demo-handle-event
       demo (cl-tui-kit/core:make-key-event #\?)))

The example combines a callback-based list model, selection, scrolling,
keymaps, focus, a help modal, resize handling, and the testing backend. It
does not require a domain-specific service or terminal session.
