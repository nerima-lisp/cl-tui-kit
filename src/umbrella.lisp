(in-package #:cl-tui-kit)

;; The umbrella package deliberately re-exports the stable protocol packages.
;; The implementation packages remain independently loadable, while users who
;; want the small toolkit surface can depend on just CL-TUI-KIT.
(dolist (package-name '(#:cl-tui-kit/core
                        #:cl-tui-kit/layout
                        #:cl-tui-kit/widgets
                        #:cl-tui-kit/ansi
                        #:cl-tui-kit/testing))
  (let ((package (find-package package-name)))
    (when package
      (do-external-symbols (symbol package)
        (export symbol (find-package '#:cl-tui-kit))))))
