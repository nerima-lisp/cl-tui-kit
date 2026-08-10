(in-package #:cl-tui-kit/tests)

(defmacro deftest (name (&optional description) &body body)
  (let ((test-name
          (string-downcase
           (format nil "~A~@[ — ~A~]" (symbol-name name) description))))
    `(cl-weave:it ,test-name
     (cl-weave:expect-has-assertions)
     ,@body)))

(defmacro is (form &optional message)
  (if message
      (let ((value-var (gensym "VALUE-")))
        `(let ((,value-var ,form))
           (if ,value-var
               (cl-weave:expect ,value-var :to-be-truthy)
               (cl-weave:fail "~A" ,message))))
      `(cl-weave:expect ,form :to-be-truthy)))

(defmacro is-equal (expected form &optional message)
  (let ((wanted-var (gensym "WANTED-"))
        (actual-var (gensym "ACTUAL-")))
    (if message
        `(let ((,wanted-var ,expected)
               (,actual-var ,form))
           (if (equalp ,wanted-var ,actual-var)
               (cl-weave:expect ,actual-var :to-equalp ,wanted-var)
               (cl-weave:fail "~A: expected ~S, got ~S"
                              ,message ,wanted-var ,actual-var)))
        `(let ((,wanted-var ,expected))
           (cl-weave:expect ,form :to-equalp ,wanted-var)))))

(defmacro signals-error (form)
  `(cl-weave:signals error ,form))

(defun test-rectangle (x y width height)
  (make-rectangle x y width height))

(defun test-key (key &rest modifiers)
  (make-key-event key :modifiers modifiers))

(defun test-cell-at (surface x y)
  (or (surface-cell surface x y) (blank-cell)))

(cl-weave:it-property "rectangle boundaries preserve their geometry"
  ((x (cl-weave:gen-integer :min -20 :max 20))
   (y (cl-weave:gen-integer :min -20 :max 20))
   (width (cl-weave:gen-integer :min 1 :max 20))
   (height (cl-weave:gen-integer :min 1 :max 20)))
  (let ((rectangle (test-rectangle x y width height)))
    (is (rectangle-contains-point-p rectangle x y))
    (is (rectangle-contains-point-p rectangle
                                    (1- (+ x width))
                                    (1- (+ y height))))
    (is (not (rectangle-contains-point-p rectangle (+ x width) y)))
    (is (not (rectangle-contains-point-p rectangle x (+ y height))))))

(define-keymap make-declarative-test-keymap (:name :declarative)
  (#\x :activate)
  ((#\g #\g) :top))
