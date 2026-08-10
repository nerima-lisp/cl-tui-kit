(require :asdf)

(let* ((bootstrap-root
         (make-pathname :name nil :type nil :defaults *load-truename*))
       (host-kit-asd
         (merge-pathnames "../cl-host-kit/cl-host-kit.asd" bootstrap-root)))
  (unless (asdf:find-system "cl-host-kit" nil)
    (when (probe-file host-kit-asd)
      (asdf:load-asd host-kit-asd)))
  (asdf:load-system "cl-host-kit"))

(let* ((root (host-kit:pathname-directory-pathname
               (host-kit:ensure-absolute-pathname *load-truename*)))
       (project-asd (merge-pathnames "cl-tui-kit.asd" root))
       (environment-asd
         (let ((value (host-kit:getenv "CL_WEAVE_ASD")))
           (and value (host-kit:ensure-absolute-pathname value)))))
  (asdf:load-asd project-asd)
  (unless (asdf:find-system "cl-weave" nil)
    (when (and environment-asd
               (probe-file environment-asd))
      (asdf:load-asd environment-asd))
    (unless (asdf:find-system "cl-weave" nil)
      (let ((sibling-asd (merge-pathnames "../cl-weave/cl-weave.asd" root)))
        (when (probe-file sibling-asd)
          (asdf:load-asd sibling-asd)))))
  (asdf:test-system "cl-tui-kit"))
