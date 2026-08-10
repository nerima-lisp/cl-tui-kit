(in-package #:cl-tui-kit/tests)

(defmacro deftest (name (&optional description) &body body)
  (declare (ignore description))
  `(cl-weave:it ,(string-downcase (symbol-name name))
     (cl-weave:expect-has-assertions)
     ,@body))

(defmacro is (form &optional message)
  (declare (ignore message))
  `(cl-weave:expect ,form :to-be-truthy))

(defmacro is-equal (expected form &optional message)
  (declare (ignore message))
  (let ((wanted-var (gensym "WANTED-")))
    `(let ((,wanted-var ,expected))
       (cl-weave:expect ,form :to-equalp ,wanted-var))))

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
