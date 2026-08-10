(in-package #:asdf-user)

(asdf:defsystem "cl-tui-kit/core"
  :description "Terminal-cell geometry, surfaces, text, styles, events, keymaps, and backend protocol."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :serial t
  :components
  ((:file "src/package")
   (:file "src/geometry")
   (:file "src/style")
   (:file "src/text")
   (:file "src/surface")
   (:file "src/event")
   (:file "src/input-parser")
   (:file "src/keymap")
   (:file "src/backend")
   (:file "src/protocol")))

(asdf:defsystem "cl-tui-kit/layout"
  :description "Composable layout and focus-tree primitives."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit/core")
  :serial t
  :components
  ((:file "src/layout")
   (:file "src/focus")))

(asdf:defsystem "cl-tui-kit/widgets"
  :description "Domain-neutral widgets built on the core and layout protocols."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit/layout")
  :serial t
  :components ((:file "src/widgets")
               (:file "src/widgets-text")
               (:file "src/widgets-tabs")
               (:file "src/widgets-menus")
               (:file "src/widgets-tables")
               (:file "src/widgets-notifications")
               (:file "src/application")
               (:file "src/application-events")
               (:file "src/application-runtime")
               (:file "src/list")
               (:file "src/tree")
               (:file "src/input-editing")
               (:file "src/input-composites")
               (:file "src/input-support")))

(asdf:defsystem "cl-tui-kit/ansi"
  :description "Optional ANSI output backend; it does not parse terminal input."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit/core")
  :serial t
  :components ((:file "src/ansi")))

(asdf:defsystem "cl-tui-kit/tty"
  :description "Optional terminal-size adapter using nerima-lisp's cl-tty-kit."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit/ansi" "cl-tty-kit")
  :serial t
  :components ((:file "src/tty")))

(asdf:defsystem "cl-tui-kit/codec"
  :description "Optional UTF-8 adapter using nerima-lisp's cl-codec-kit."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit/core" "cl-codec-kit")
  :serial t
  :components ((:file "src/codec")))

(asdf:defsystem "cl-tui-kit/testing"
  :description "Deterministic structured test backend and frame helpers."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit/core")
  :serial t
  :components ((:file "src/testing")))

(asdf:defsystem "cl-tui-kit"
  :description "A generic, composable Common Lisp terminal UI toolkit."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit/core"
               "cl-tui-kit/layout"
               "cl-tui-kit/widgets"
               "cl-tui-kit/ansi"
               "cl-tui-kit/testing")
  :in-order-to ((test-op (test-op "cl-tui-kit/test")))
  :serial t
  :components ((:file "src/umbrella")))

(asdf:defsystem "cl-tui-kit/examples"
  :description "Domain-neutral examples built from cl-tui-kit protocols."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit")
  :serial t
  :components ((:file "examples/searchable-list")))

(asdf:defsystem "cl-tui-kit/tests"
  :description "cl-weave tests for cl-tui-kit's deterministic protocols."
  :author "takeokunn"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-tui-kit"
               "cl-host-kit"
               (:version "cl-weave" "1.3.0"))
  :serial t
  :components
  ((:file "t/package")
   (:file "t/suite")
   (:file "t/edge-tests")
   (:file "t/core-tests")
   (:file "t/input-tests")
   (:file "t/keymap-tests")
   (:file "t/layout-tests")
   (:file "t/backend-tests")
   (:file "t/application-tests")
   (:file "t/cps-tests")
   (:file "t/input-widget-tests")
   (:file "t/table-tests")
   (:file "t/support-tests")
   (:file "t/notification-tests")
   (:file "t/tooling-tests")
   (:file "t/runner")))

(asdf:defsystem "cl-tui-kit/test"
  :depends-on ("cl-tui-kit/tests")
  :perform
  (asdf:test-op (operation component)
    (declare (ignore operation component))
    (let* ((package (find-package "CL-TUI-KIT/TESTS"))
           (runner (and package (find-symbol "RUN-TESTS" package))))
      (unless (and runner (fboundp runner))
        (error "CL-TUI-KIT/TESTS:RUN-TESTS is not available."))
      (funcall runner))))
