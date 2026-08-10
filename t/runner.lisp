(in-package #:cl-tui-kit/tests)

(defun coverage-source-directories ()
  (list (asdf:system-relative-pathname "cl-tui-kit/core" "src/")))

(defun coverage-excluded-pathnames ()
  (list (asdf:system-relative-pathname "cl-tui-kit/core"
                                       "src/package.lisp")
        (asdf:system-relative-pathname "cl-tui-kit"
                                       "src/umbrella.lisp")))

(defun coverage-threshold (environment-variable)
  (let ((value (host-kit:getenv environment-variable)))
    (when value
      (handler-case
          (let ((threshold (parse-integer value :junk-allowed nil)))
            (unless (<= 0 threshold 100)
              (error "Coverage threshold must be between 0 and 100: ~A"
                     value))
            threshold)
        (error (condition)
          (error "Invalid coverage threshold ~A: ~A"
                 environment-variable condition))))))

(defun run-tests (&key (stream *standard-output*) coverage
                         coverage-report-directory)
  (let* ((suite (cl-weave:root-suite))
         (plan (cl-weave:collect-test-plan suite))
         (selected (length plan))
         (source-directories (when coverage
                               (coverage-source-directories)))
         (excluded-pathnames (when coverage
                               (coverage-excluded-pathnames)))
         (minimum-expression (when coverage
                              (coverage-threshold
                                "CL_TUI_KIT_MIN_EXPRESSION_COVERAGE")))
         (minimum-branch (when coverage
                           (coverage-threshold
                            "CL_TUI_KIT_MIN_BRANCH_COVERAGE"))))
    (when (zerop selected)
      (error "No cl-tui-kit tests were selected."))
    (unless (cl-weave:run-all :reporter :spec
                              :stream stream
                              :pass-with-no-tests nil
                              :coverage coverage
                              :coverage-report-directory
                              coverage-report-directory
                              :coverage-include-pathnames source-directories
                              :coverage-exclude-pathnames excluded-pathnames
                              :coverage-minimum-expression minimum-expression
                              :coverage-minimum-branch minimum-branch)
      (error "cl-weave reported a test failure."))
    (when coverage
      (let ((statistics (cl-weave:coverage-statistics
                         :include-pathnames source-directories
                         :exclude-pathnames excluded-pathnames)))
        (when (zerop (+ (getf statistics :expression-total)
                        (getf statistics :branch-total)))
          (error "Coverage requested, but no instrumented cl-tui-kit source was found. Load the sources with SB-COVER instrumentation first."))
        (format stream "Source coverage: expressions ~D/~D, branches ~D/~D~%"
                (getf statistics :expression-covered)
                (getf statistics :expression-total)
                (getf statistics :branch-covered)
                (getf statistics :branch-total))))
    (format stream "Selected: ~D~%" selected)
    selected))
