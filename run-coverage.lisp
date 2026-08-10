;;;; Run cl-weave with SBCL source instrumentation enabled before cl-tui-kit is
;;;; compiled.  The normal test system intentionally does not promise that
;;;; already-built FASLs contain coverage probes.

(require :asdf)
(require :sb-cover)

(defun load-sibling-asd-if-present (root system relative-path)
  (unless (asdf:find-system system nil)
    (let ((sibling-asd (merge-pathnames relative-path root)))
      (when (probe-file sibling-asd)
        (asdf:load-asd sibling-asd)))))

(let* ((bootstrap-root
         (make-pathname :name nil :type nil :defaults *load-truename*))
       (host-kit-asd
         (merge-pathnames "../cl-host-kit/cl-host-kit.asd" bootstrap-root)))
  (unless (asdf:find-system "cl-host-kit" nil)
    (when (probe-file host-kit-asd)
      (asdf:load-asd host-kit-asd)))
  (asdf:load-system "cl-host-kit"))

(defparameter *cl-tui-kit-root*
  (host-kit:pathname-directory-pathname
   (host-kit:ensure-absolute-pathname *load-truename*)))

(load-sibling-asd-if-present *cl-tui-kit-root* "cl-codec-kit"
                             "../cl-codec-kit/cl-codec-kit.asd")
(load-sibling-asd-if-present *cl-tui-kit-root* "cl-boundary-kit"
                             "../cl-boundary-kit/cl-boundary-kit.asd")
(load-sibling-asd-if-present *cl-tui-kit-root* "cl-date-kit"
                             "../cl-date-kit/cl-date-kit.asd")
(load-sibling-asd-if-present *cl-tui-kit-root* "cl-concurrent-kit"
                             "../cl-concurrent-kit/cl-concurrent-kit.asd")
(load-sibling-asd-if-present *cl-tui-kit-root* "cl-tty-kit"
                             "../cl-tty-kit/cl-tty-kit.asd")

(let ((cl-weave-asd (host-kit:getenv "CL_WEAVE_ASD")))
  (when cl-weave-asd
    (let ((resolved-asd (host-kit:ensure-absolute-pathname cl-weave-asd)))
      (when (probe-file resolved-asd)
        (asdf:load-asd resolved-asd))))
  (unless (asdf:find-system "cl-weave" nil)
    (let ((sibling-asd
            (merge-pathnames "../cl-weave/cl-weave.asd" *cl-tui-kit-root*)))
      (when (probe-file sibling-asd)
        (asdf:load-asd sibling-asd)))))

;; SB-COVER is a compile-time optimization policy.  This proclamation must
;; happen before ASDF force-compiles the project sources.
(proclaim '(optimize (sb-cover:store-coverage-data 3)))

;; Preserve the policy for every source file ASDF compiles.  A source file may
;; establish its own optimization declaration, so setting the policy once is
;; not sufficient for a reliable coverage run.
(defmethod asdf:perform :around ((operation asdf:compile-op)
                                 (component asdf:cl-source-file))
  (declare (ignore operation component))
  (proclaim '(optimize (sb-cover:store-coverage-data 3)))
  (unwind-protect
       (call-next-method)
    (proclaim '(optimize (sb-cover:store-coverage-data 0)))))

(asdf:load-asd (merge-pathnames "cl-tui-kit.asd" *cl-tui-kit-root*))
;; ASDF's :force applies to the requested system's own components.  Force each
;; project layer explicitly so an already-built, non-instrumented dependency
;; FASL cannot hide the source from SB-COVER.
(dolist (system '("cl-tui-kit/core"
                  "cl-tui-kit/layout"
                  "cl-tui-kit/widgets"
                  "cl-tui-kit/ansi"
                  "cl-tui-kit/tty"
                  "cl-tui-kit/codec"
                  "cl-tui-kit/testing"
                  "cl-tui-kit"
                  "cl-tui-kit/tests"))
  (asdf:load-system system :force t))

(let* ((report-directory (host-kit:getenv
                          "CL_TUI_KIT_COVERAGE_REPORT_DIRECTORY"))
       (report-directory
         (and report-directory
              (not (string= report-directory ""))
              (host-kit:ensure-directory-pathname
               (host-kit:ensure-absolute-pathname report-directory))))
       (selected (cl-tui-kit/tests:run-tests
                   :coverage t
                   :coverage-report-directory report-directory)))
  (unless (plusp selected)
    (error "Coverage run selected no tests.")))
