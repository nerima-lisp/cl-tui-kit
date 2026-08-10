(in-package #:cl-tui-kit/core)

(defstruct (key-stroke (:constructor %make-key-stroke (key modifiers)))
  key
  (modifiers '() :type list))

(defun make-key-stroke (key &key modifiers)
  (%make-key-stroke key (normalize-modifiers modifiers)))

(defun %stroke (value)
  (cond
    ((key-stroke-p value) value)
    ((key-event-p value)
     (make-key-stroke (key-event-key value)
                      :modifiers (key-event-modifiers value)))
    ((and (consp value) (or (keywordp (car value)) (characterp (car value))))
     (make-key-stroke (car value) :modifiers (cdr value)))
    (t (make-key-stroke value))))

(defun %sequence (sequence)
  (mapcar #'%stroke (if (listp sequence) sequence (list sequence))))

(defstruct (keymap
            (:constructor %make-keymap
                (name parent mode bindings modes prefix-timeout)))
  (name :keymap :type symbol)
  parent
  (mode :default :type symbol)
  bindings
  modes
  prefix-timeout)

(defun make-keymap (&key (name :keymap) parent (mode :default)
                         prefix-timeout)
  (when prefix-timeout (check-type prefix-timeout function))
  (%make-keymap name parent mode (make-hash-table :test #'equalp)
                (make-hash-table :test #'eq) prefix-timeout))

(defun set-keymap-mode (keymap mode)
  (check-type mode symbol)
  (setf (keymap-mode keymap) mode)
  keymap)

(defun set-keymap-prefix-timeout (keymap function)
  (when function (check-type function function))
  (setf (keymap-prefix-timeout keymap) function)
  keymap)

(defun keymap-mode-map (keymap &optional (mode (keymap-mode keymap)))
  (or (and mode (gethash mode (keymap-modes keymap))) keymap))

(defun define-keymap-mode (keymap mode &key (inherit-parent t))
  (let ((mode-map (make-keymap :name mode
                               :parent (and inherit-parent keymap)
                               :mode mode)))
    (setf (gethash mode (keymap-modes keymap)) mode-map)
    mode-map))

(defun bind-key (keymap sequence binding &key mode)
  (let ((target (if mode
                   (or (gethash mode (keymap-modes keymap))
                       (define-keymap-mode keymap mode))
                   keymap)))
    (setf (gethash (%sequence sequence) (keymap-bindings target)) binding)
    target))

(defmacro define-keymap (name options &body bindings)
  "Define a constructor for a declarative KEYMAP.

OPTIONS is a literal plist passed to MAKE-KEYMAP.  Each binding has the
form `(SEQUENCE ACTION &rest BIND-OPTIONS)`, where SEQUENCE is a key or a
literal list of keys.  The generated constructor accepts a runtime PARENT,
which makes the same declarative map usable in a hierarchy or overlay."
  (unless (symbolp name)
    (error "Keymap constructor name must be a symbol: ~S" name))
  (unless (listp options)
    (error "Keymap options must be a literal plist: ~S" options))
  (unless (evenp (length options))
    (error "Keymap options must contain an even number of forms: ~S" options))
  (loop for key in options by #'cddr
        do (unless (and (keywordp key) (not (eq key :parent)))
             (error "Invalid keymap option: ~S" key)))
  (let ((keymap-var (gensym "KEYMAP-")))
    `(defun ,name (&key parent)
       (let ((,keymap-var (make-keymap :parent parent ,@options)))
         ,@(loop for binding in bindings
                 collect
                 (destructuring-bind (sequence action &rest bind-options)
                     binding
                   `(bind-key ,keymap-var ',sequence ,action ,@bind-options)))
         ,keymap-var))))

(defun unbind-key (keymap sequence &key mode)
  (let ((target (if mode (gethash mode (keymap-modes keymap)) keymap)))
    (when target
      (remhash (%sequence sequence) (keymap-bindings target)))
    keymap))

(defstruct (keymap-state (:constructor %make-keymap-state
                                      (pending pending-since)))
  (pending '() :type list)
  pending-since)

(defun make-keymap-state (&key time)
  (%make-keymap-state '() time))

(defun reset-keymap-state (state)
  (setf (keymap-state-pending state) nil)
  (setf (keymap-state-pending-since state) nil)
  state)

(defun keymap-state-prefix-active-p (state)
  (not (null (keymap-state-pending state))))

(defstruct (keymap-result (:constructor %make-keymap-result (status action prefix)))
  (status :unhandled :type symbol)
  action
  (prefix '() :type list))

(defun %binding-for (keymap sequence)
  (multiple-value-bind (binding presentp)
      (gethash sequence (keymap-bindings keymap))
    (values binding presentp)))

(defun %sequence-prefix-p (prefix sequence)
  (and (<= (length prefix) (length sequence))
       (equalp prefix (subseq sequence 0 (length prefix)))))

(defun %has-prefix-binding-p (keymap sequence)
  (loop for candidate being the hash-keys of (keymap-bindings keymap)
        thereis (and (> (length candidate) (length sequence))
                     (%sequence-prefix-p sequence candidate))))

(defun %find-binding (keymap sequence)
  "Find an exact binding or prefix through KEYMAP's parent chain.

The first exact binding wins.  Prefix detection is intentionally separate
from exact lookup so a sequence can be both a complete command and a prefix
for a longer command; callers may use the complete command immediately."
  (loop for current = (keymap-mode-map keymap)
          then (keymap-parent current)
        while current
        do (multiple-value-bind (binding presentp)
               (%binding-for current sequence)
             (when presentp (return-from %find-binding
                              (values :exact binding))))
           (when (%has-prefix-binding-p current sequence)
             (return-from %find-binding (values :prefix nil)))
        finally (return (values nil nil))))

(defun %binding-action (binding event)
  (cond
    ((functionp binding) (funcall binding event))
    ((symbolp binding) (custom-action binding nil event))
    (t binding)))

(defun %dispatch-sequence (keymap state sequence event time)
  (multiple-value-bind (kind binding)
      (%find-binding keymap sequence)
    (case kind
      (:exact
       (reset-keymap-state state)
       (%make-keymap-result :handled (%binding-action binding event) nil))
      (:prefix
       (setf (keymap-state-pending state) sequence)
       (unless (keymap-state-pending-since state)
         (setf (keymap-state-pending-since state) time))
       (%make-keymap-result :prefix nil sequence))
      (otherwise nil))))

(defun keymap-dispatch (keymap state event &key time)
  "Dispatch a normalized KEY EVENT through KEYMAP.

The pending prefix is kept in STATE, so the caller can share one state across
frames.  A failed longer sequence is retried as a fresh single key, which is
the deterministic and least surprising behavior for modal applications.  TIME
is an opaque caller-supplied timestamp recorded when a prefix begins; the
core never sleeps or creates a timer."
  (check-type keymap keymap)
  (check-type state keymap-state)
  (check-type event key-event)
  (let* ((stroke (%stroke event))
         (pending (keymap-state-pending state))
         (sequence (append pending (list stroke)))
         (result (%dispatch-sequence keymap state sequence event time)))
    (or result
        (if pending
            (progn
              (reset-keymap-state state)
              (or (%dispatch-sequence keymap state (list stroke) event time)
                  (%make-keymap-result :unhandled nil nil)))
            (%make-keymap-result :unhandled nil nil)))))

(defun keymap-expire-prefix (keymap state &optional event)
  "Expire STATE's pending prefix using KEYMAP's caller-provided policy.

The timeout callback receives the pending key-stroke list and EVENT (which
may be NIL), and returns an action or NIL.  The returned result has status
:TIMEOUT.  Calling this function is deliberately explicit so applications
can use their event loop's monotonic clock without making the core sleep or
spawn a timer thread."
  (check-type keymap keymap)
  (check-type state keymap-state)
  (let ((pending (keymap-state-pending state)))
    (when pending
      (let ((timeout (keymap-prefix-timeout keymap)))
        (reset-keymap-state state)
        (%make-keymap-result
         :timeout
         (and timeout (funcall timeout (copy-list pending) event))
         pending)))))

(defun dispatch-keymaps (keymaps state event &key time)
  "Try KEYMAPS from most specific to least specific.

An :UNHANDLED result propagates to the next map.  A prefix is considered
handled because it reserves the following key for that map."
  (check-type state keymap-state)
  (check-type event key-event)
  (loop for keymap in keymaps
        for result = (keymap-dispatch keymap state event :time time)
        unless (eq (keymap-result-status result) :unhandled)
          do (return result)
        finally (return (%make-keymap-result :unhandled nil nil))))

(defun vi-like-keymap (&key (name :vi-like))
  "Create a generic three-mode keymap with vi-like expression points.

The returned map only emits semantic action names.  It does not change an
application's mode itself; the application may interpret :ENTER-NORMAL-MODE,
:ENTER-INSERT-MODE, and :ENTER-VISUAL-MODE as it sees fit."
  (let* ((keymap (make-keymap :name name :mode :normal))
         (normal (define-keymap-mode keymap :normal))
         (insert (define-keymap-mode keymap :insert))
         (visual (define-keymap-mode keymap :visual))
         (escape (make-key-stroke :escape))
         (g (make-key-stroke #\g))
         (ctrl-u (make-key-stroke #\u :modifiers '(:ctrl)))
         (ctrl-d (make-key-stroke #\d :modifiers '(:ctrl))))
    (bind-key normal (list g g) :enter-normal-mode)
    (bind-key normal ctrl-u :scroll-up-half-page)
    (bind-key normal ctrl-d :scroll-down-half-page)
    (bind-key normal #\/ :search-forward)
    (bind-key normal #\? :search-backward)
    (bind-key normal #\n :search-next)
    (bind-key normal (make-key-stroke #\N) :search-previous)
    (bind-key normal escape :enter-normal-mode)
    (bind-key insert escape :enter-normal-mode)
    (bind-key visual escape :enter-normal-mode)
    keymap))
