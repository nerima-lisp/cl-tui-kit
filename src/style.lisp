(in-package #:cl-tui-kit/core)

(defstruct (color (:constructor %make-color (kind value))
                  (:copier nil))
  (kind :default :type symbol)
  value)

(defun make-color (&optional (kind :default) value)
  (check-type kind symbol)
  (%make-color kind value))

(defun default-color ()
  (%make-color :default nil))

(defun named-color (name)
  (%make-color :named name))

(defun indexed-color (index)
  (unless (and (integerp index) (<= 0 index 255))
    (error 'invalid-range-error
           :context 'index
           :datum index
           :expected "an integer from 0 through 255"))
  (%make-color :indexed index))

(defun rgb-color (red green blue)
  (dolist (component (list red green blue))
    (unless (and (integerp component) (<= 0 component 255))
      (error 'invalid-range-error
             :context 'rgb-component
             :datum component
             :expected "an integer from 0 through 255")))
  (%make-color :rgb (list red green blue)))

(defun color= (left right)
  (and (color-p left)
       (color-p right)
       (eq (color-kind left) (color-kind right))
       (equal (color-value left) (color-value right))))

(defstruct (style
            (:copier nil)
            (:constructor %make-style
                (foreground background bold dim italic underline reverse strike)))
  (foreground (default-color) :type color)
  (background (default-color) :type color)
  (bold nil :type boolean)
  (dim nil :type boolean)
  (italic nil :type boolean)
  (underline nil :type boolean)
  (reverse nil :type boolean)
  (strike nil :type boolean))

(defun make-style (&key (foreground (default-color)) (background (default-color))
                        bold dim italic underline reverse strike)
  (%make-style foreground background (not (null bold)) (not (null dim))
               (not (null italic)) (not (null underline)) (not (null reverse))
               (not (null strike))))

(defun copy-style (style)
  (%make-style (color-copy (style-foreground style))
               (color-copy (style-background style))
               (style-bold style) (style-dim style) (style-italic style)
               (style-underline style) (style-reverse style) (style-strike style)))

(defun color-copy (color)
  (%make-color (color-kind color)
               (if (consp (color-value color))
                   (copy-list (color-value color))
                   (color-value color))))

(defun style= (left right)
  (and (style-p left)
       (style-p right)
       (color= (style-foreground left) (style-foreground right))
       (color= (style-background left) (style-background right))
       (eql (style-bold left) (style-bold right))
       (eql (style-dim left) (style-dim right))
       (eql (style-italic left) (style-italic right))
       (eql (style-underline left) (style-underline right))
       (eql (style-reverse left) (style-reverse right))
       (eql (style-strike left) (style-strike right))))

(defun merge-styles (base overlay)
  "Return a style with OVERLAY's enabled attributes over BASE.

Styles are intentionally value objects.  An overlay can enable attributes,
or provide a non-default color; callers that need to disable an attribute can
construct the final style explicitly with MAKE-STYLE."
  (make-style
   :foreground (if (color= (style-foreground overlay) (default-color))
                   (style-foreground base)
                   (style-foreground overlay))
   :background (if (color= (style-background overlay) (default-color))
                   (style-background base)
                   (style-background overlay))
   :bold (or (style-bold base) (style-bold overlay))
   :dim (or (style-dim base) (style-dim overlay))
   :italic (or (style-italic base) (style-italic overlay))
   :underline (or (style-underline base) (style-underline overlay))
   :reverse (or (style-reverse base) (style-reverse overlay))
   :strike (or (style-strike base) (style-strike overlay))))

(defstruct (theme (:constructor %make-theme (styles))
                  (:copier nil))
  styles)

(defun make-theme (&optional styles)
  (let ((table (make-hash-table :test #'eq)))
    (when styles
      (map nil (lambda (entry)
                 (setf (gethash (car entry) table) (copy-style (cdr entry))))
           styles))
    (%make-theme table)))

(defun copy-theme (theme)
  (let ((copy (make-theme)))
    (maphash (lambda (role style)
               (setf (gethash role (theme-styles copy)) (copy-style style)))
             (theme-styles theme))
    copy))

(defun theme-style (theme role &optional fallback)
  (or (gethash role (theme-styles theme)) fallback))

(defun theme-set-style (theme role style)
  (check-type role symbol)
  (check-type style style)
  (setf (gethash role (theme-styles theme)) (copy-style style))
  theme)

(defun default-theme ()
  (make-theme
   (list
    (cons :background (make-style))
    (cons :foreground (make-style))
    (cons :muted (make-style :dim t))
    (cons :accent (make-style :bold t :foreground (named-color :cyan)))
    (cons :selected (make-style :reverse t))
    (cons :border (make-style :foreground (named-color :white)))
    (cons :warning (make-style :bold t :foreground (named-color :yellow)))
    (cons :error (make-style :bold t :foreground (named-color :red)))
    (cons :success (make-style :foreground (named-color :green)))
    (cons :title (make-style :bold t))
    (cons :disabled (make-style :dim t)))))
