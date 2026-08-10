(in-package #:cl-tui-kit/tests)

(deftest paredit-structural-source-edit (:tooling) (let ((rectangle (test-rectangle 1 2 3 4))) (is-equal 3 (rectangle-width rectangle)) (is-equal 4 (rectangle-height rectangle))))
