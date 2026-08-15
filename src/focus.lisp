(in-package #:cl-tui-kit/layout)

(defstruct (focus-node
            (:constructor %make-focus-node
                (id widget %children %parent rectangle focusable-p scope-p)))
  id
  widget
  (%children '() :type list)
  %parent
  (rectangle (make-rectangle) :type rectangle)
  (focusable-p nil :type boolean)
  (scope-p nil :type boolean))

(defun focus-node-children (node)
  "Return a copy of NODE's child list.

The returned list is a fresh copy, so mutating it has no effect on NODE.
Child adoption, and the corresponding parent pointer on each child, is
maintained by MAKE-FOCUS-NODE; it is not settable directly."
  (copy-list (focus-node-%children node)))

(defun focus-node-parent (node)
  "Return NODE's parent focus-node, or NIL for the root of a tree.

Parent linkage is established by MAKE-FOCUS-NODE when NODE is adopted as
a child; it is not settable directly."
  (focus-node-%parent node))

(defmethod print-object ((node focus-node) stream)
  ;; focus-node forms a genuine parent/child cycle (a parent's %CHILDREN slot
  ;; holds its children, and each child's %PARENT slot points back), so the
  ;; default structure printer would recurse forever and blow the control
  ;; stack. Print only identifying fields and never descend into :PARENT or
  ;; :CHILDREN.
  (print-unreadable-object (node stream :type t :identity t)
    (format stream "ID: ~S PARENT: ~:[NONE~;PRESENT~] CHILDREN: ~D"
            (focus-node-id node)
            (focus-node-%parent node)
            (length (focus-node-%children node))))
  node)

(defun %adopt-focus-children (node children)
  (setf (focus-node-%children node) children)
  (dolist (child children)
    (setf (focus-node-%parent child) node)
    (%adopt-focus-children child (focus-node-%children child)))
  node)

(defun make-focus-node (id &key widget children rectangle focusable-p scope-p)
  (let ((node (%make-focus-node id widget (or children '()) nil
                                (copy-rectangle (or rectangle (make-rectangle)))
                                (not (null focusable-p))
                                (not (null scope-p)))))
    (%adopt-focus-children node (focus-node-%children node))))

(defstruct (focus-tree
            (:constructor %make-focus-tree (root %current %modal-stack)))
  root
  %current
  (%modal-stack '() :type list))

(defun focus-tree-current (tree)
  "Return TREE's current focus node.

Use FOCUS-TREE-SET-CURRENT to change it; that function validates tree
membership and the active modal scope, which a direct slot write would
skip."
  (focus-tree-%current tree))

(defun focus-tree-modal-stack (tree)
  "Return a copy of TREE's modal scope stack.

The returned list is a fresh copy, so mutating it has no effect on TREE;
use FOCUS-PUSH-MODAL and FOCUS-POP-MODAL to change it."
  (copy-list (focus-tree-%modal-stack tree)))

(defun %first-focusable (node)
  (when (focus-node-focusable-p node)
    (return-from %first-focusable node))
  (loop for child in (focus-node-%children node)
        for result = (%first-focusable child)
        when result do (return result)))

(defun make-focus-tree (root)
  (let ((actual-root (if (typep root 'focus-node)
                         root
                         (make-focus-node root))))
    (%make-focus-tree actual-root (%first-focusable actual-root) nil)))

(defun %node-in-tree-p (node root)
  (or (eq node root)
      (some (lambda (child) (%node-in-tree-p node child))
            (focus-node-%children root))))

(defun focus-tree-set-current (tree node)
  (check-type tree focus-tree)
  (unless (%node-in-tree-p node (focus-tree-root tree))
    (error 'focus-error :context 'focus-tree-set-current
                         :detail "Focus node is not part of this focus tree."))
  (when (and (focus-tree-%modal-stack tree)
             (not (%node-in-tree-p node
                                   (first (first (focus-tree-%modal-stack tree))))))
    (error 'focus-error :context 'focus-tree-set-current
                         :detail "Focus node is outside the active modal scope."))
  (setf (focus-tree-%current tree) node)
  node)

(defun %active-root (tree)
  (if (focus-tree-%modal-stack tree)
      (first (first (focus-tree-%modal-stack tree)))
      (focus-tree-root tree)))

(defun %focusable-nodes (node)
  (append (when (focus-node-focusable-p node) (list node))
          (mapcan #'%focusable-nodes (focus-node-%children node))))

(defun %focus-move (tree delta)
  (let* ((nodes (%focusable-nodes (%active-root tree)))
         (count (length nodes)))
    (when (plusp count)
      (let* ((current (position (focus-tree-%current tree) nodes :test #'eq))
             (index (mod (+ (or current (if (plusp delta) -1 0)) delta)
                         count)))
        (focus-tree-set-current tree (nth index nodes)))))
  (focus-tree-%current tree))

(defun focus-next (tree)
  (%focus-move tree 1))

(defun focus-previous (tree)
  (%focus-move tree -1))

(defun %center (rectangle)
  (values (+ (rectangle-x rectangle) (floor (rectangle-width rectangle) 2))
          (+ (rectangle-y rectangle) (floor (rectangle-height rectangle) 2))))

(defun %direction-candidate-p (direction current candidate)
  (multiple-value-bind (cx cy) (%center current)
    (multiple-value-bind (x y) (%center candidate)
      (case direction
        (:left (< x cx))
        (:right (> x cx))
        (:up (< y cy))
        (:down (> y cy))))))

(defun %direction-distance (direction current candidate)
  (multiple-value-bind (cx cy) (%center current)
    (multiple-value-bind (x y) (%center candidate)
      (if (member direction '(:left :right) :test #'eq)
          (+ (abs (- x cx)) (abs (- y cy)))
          (+ (abs (- y cy)) (abs (- x cx)))))))

(defun %nearest-direction-candidate (direction current candidates)
  (reduce (lambda (best candidate)
            (if (< (%direction-distance direction current
                                         (focus-node-rectangle candidate))
                   (%direction-distance direction current
                                         (focus-node-rectangle best)))
                candidate
                best))
          (rest candidates)
          :initial-value (first candidates)))

(defun focus-directional (tree direction)
  (check-type direction keyword)
  (let* ((current (focus-tree-%current tree))
         (current-rectangle (and current (focus-node-rectangle current)))
         (candidates (and current
                          (remove-if-not
                           (lambda (node)
                             (and (not (eq node current))
                                  (%direction-candidate-p
                                   direction current-rectangle
                                   (focus-node-rectangle node))))
                           (%focusable-nodes (%active-root tree))))))
    (when candidates
      (focus-tree-set-current
       tree
       (%nearest-direction-candidate
        direction current-rectangle
        candidates)))
    (focus-tree-%current tree)))

(defun focus-push-modal (tree scope)
  (check-type scope focus-node)
  (unless (%node-in-tree-p scope (focus-tree-root tree))
    (error 'focus-error :context 'focus-push-modal
                         :detail "Modal focus scope is not part of this focus tree."))
  (push (list scope (focus-tree-%current tree))
        (focus-tree-%modal-stack tree))
  (setf (focus-tree-%current tree) (or (%first-focusable scope) scope))
  (focus-tree-%current tree))

(defun focus-pop-modal (tree)
  (when (focus-tree-%modal-stack tree)
    (let ((entry (pop (focus-tree-%modal-stack tree))))
      (setf (focus-tree-%current tree)
            (or (second entry) (%first-focusable (focus-tree-root tree))))))
  (focus-tree-%current tree))

(defun focus-restore (tree)
  "Leave the active modal scope and restore the focus saved on entry."
  (focus-pop-modal tree))

(defun focus-visible-p (tree node)
  (and (eq node (focus-tree-%current tree))
       (%node-in-tree-p node (%active-root tree))))
