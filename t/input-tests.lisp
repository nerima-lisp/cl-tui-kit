(in-package #:cl-tui-kit/tests)

(deftest normalized-events-and-actions (:events)
  (let ((event (make-key-event :enter :modifiers '(:shift "ctrl" :shift))))
    (is-equal '(:ctrl :shift) (key-event-modifiers event))
    (is (typep event 'key-event))
    (is-equal :submit (action-name (submit-action))))
  (let ((event (make-key-event :x
                               :modifiers '("control" "meta" "shift" "super"))))
    (is-equal '(:ctrl :alt :shift :super)
              (key-event-modifiers event)))
  (let ((event (make-key-event :x :modifiers '("hyper"))))
    (is-equal '(:hyper) (key-event-modifiers event)))
  (let ((event (make-custom-event :refresh '(:source :test))))
    (is-equal :custom (event-kind event))
    (is-equal :refresh (custom-event-name event))
    (is-equal :resize (event-kind (make-resize-event 80 24)))
    (is (signals-error
         (make-key-event :enter :modifiers '("unsupported"))))))

(deftest event-families-and-action-contracts (:events)
  (let* ((paste (make-paste-event "pasted"))
         (mouse (make-mouse-event 2 3 :button :right
                                  :kind :release
                                  :modifiers '(:control "meta")))
         (focus (make-focus-event nil :blur))
         (tick (make-tick-event 42))
         (custom (make-custom-event :refresh '(:source :test)))
         (source (list :source :test))
         (actions (list (activate-action :payload source)
                        (cancel-action :payload source)
                        (submit-action :payload source)
                        (move-action :right 2 source)
                        (select-action :item source)
                        (toggle-action :payload source)
                        (open-action :payload source)
                        (close-action :payload source)
                        (custom-action :refresh :payload source))))
    (is-equal :paste (event-kind paste))
    (is-equal "pasted" (paste-event-text paste))
    (is-equal :release (mouse-event-kind mouse))
    (is-equal 2 (mouse-event-x mouse))
    (is-equal 3 (mouse-event-y mouse))
    (is-equal :right (mouse-event-button mouse))
    (is-equal '(:ctrl :alt) (mouse-event-modifiers mouse))
    (is-equal :focus (event-kind focus))
    (is (not (focus-event-focused-p focus)))
    (is-equal :blur (focus-event-reason focus))
    (is-equal 42 (tick-event-time tick))
    (is-equal :refresh (custom-event-name custom))
    (is-equal '(:source :test) (custom-event-payload custom))
    (is-equal '(:activate :cancel :submit :move :select :toggle :open :close :refresh)
              (mapcar #'action-name actions))
    (is-equal '(:direction :right :amount 2)
              (action-payload (fourth actions)))
    (is-equal source (action-source (first actions)))))

(deftest terminal-input-parser-osc52-clipboard-responses (:input-parser)
  (let* ((parser (make-terminal-input-parser))
         (escape (code-char 27))
         (bel (code-char 7)))
    (is (null (terminal-input-parser-feed
               parser (format nil "~C]52;c;S" escape))))
    (is (terminal-input-parser-pending-p parser))
    (let ((events (terminal-input-parser-feed
                   parser (format nil "Gk=~C" bel))))
      (is-equal 1 (length events))
      (is-equal :clipboard (event-kind (first events)))
      (is-equal "c" (clipboard-event-selection (first events)))
      (is-equal "Hi" (clipboard-event-text (first events))))
    (is (not (terminal-input-parser-pending-p parser))))
  (let* ((parser (make-terminal-input-parser))
         (escape (code-char 27))
         (backslash #\\))
    (is (null (terminal-input-parser-feed
               parser (format nil "~C]52;p;5pel5pys~C" escape escape))))
    (let ((events (terminal-input-parser-feed parser (string backslash))))
      (is-equal 1 (length events))
      (is-equal "p" (clipboard-event-selection (first events)))
      (is-equal "日本" (clipboard-event-text (first events)))))
  (let* ((parser (make-terminal-input-parser))
         (escape (code-char 27)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C]52;c;!!!!~C"
                                        escape (code-char 7))))))
      (is-equal :terminal-sequence (custom-event-name event))
      (is-equal :invalid-base64
                (getf (custom-event-payload event) :error)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C]52;c;Zh==~C"
                                        escape (code-char 7))))))
      (is-equal :terminal-sequence (custom-event-name event))
      (is-equal :invalid-base64
                (getf (custom-event-payload event) :error)))
    (dolist (encoded '("A" "Zg=A" "Zm9=" "Zg==AA=="))
      (let ((event (first (terminal-input-parser-feed
                           parser (format nil "~C]52;c;~A~C"
                                          escape encoded (code-char 7))))))
        (is-equal :terminal-sequence (custom-event-name event))
        (is-equal :invalid-base64
                  (getf (custom-event-payload event) :error)))))
  (let* ((parser (make-terminal-input-parser))
         (escape (code-char 27)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C]0;title~C"
                                        escape (code-char 7))))))
      (is-equal :terminal-sequence (custom-event-name event))
      (is-equal :osc (getf (custom-event-payload event) :protocol)))
    (let ((events (terminal-input-parser-feed
                   parser (concatenate 'string
                                       (format nil "~C]0;title~C"
                                               escape (code-char 7))
                                       "ignored"
                                       (string escape)
                                       (string #\\)))))
      (is-equal :terminal-sequence (custom-event-name (first events)))
      (is-equal "0;title"
                (getf (custom-event-payload (first events)) :payload)))))

(deftest terminal-input-parser-incremental-and-structured-events (:input-parser)
  (let* ((parser (make-terminal-input-parser))
         (escape (code-char 27)))
    (is (null (terminal-input-parser-feed parser (vector #xe6))))
    (is (terminal-input-parser-pending-p parser))
    (let ((events (terminal-input-parser-feed parser (vector #x97 #xa5))))
      (is-equal 1 (length events))
      (is-equal "日" (text-input-event-text (first events))))
    (is (null (terminal-input-parser-pending-p parser)))
    (is (null (terminal-input-parser-feed parser (format nil "~C[" escape))))
    (let ((events (terminal-input-parser-feed parser "1;5A")))
      (is-equal 1 (length events))
      (is-equal :up (key-event-key (first events)))
      (is-equal '(:ctrl) (key-event-modifiers (first events))))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<0;3;4M" escape)))))
      (is-equal :mouse (event-kind event))
      (is-equal 2 (mouse-event-x event))
      (is-equal 3 (mouse-event-y event))
      (is-equal :left (mouse-event-button event))
      (is-equal :press (mouse-event-kind event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[I" escape)))))
      (is-equal :focus (event-kind event))
      (is (focus-event-focused-p event)))
    (is (null (terminal-input-parser-feed
               parser (format nil "~C[200~~hello" escape))))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[201~~" escape)))))
      (is-equal :paste (event-kind event))
      (is-equal "hello" (paste-event-text event))))
  (let ((events (terminal-input-parser-feed
                 (make-terminal-input-parser) (vector #xff))))
    (is-equal 1 (length events))
    (is-equal (code-char #xfffd)
              (char (text-input-event-text (first events)) 0)))
  (let* ((escape (code-char 27))
         (events (terminal-input-parser-feed
                  (make-terminal-input-parser :max-sequence-length 3)
                  (format nil "~C[123" escape))))
    (is-equal 1 (length events))
    (is-equal :input-overflow (custom-event-name (first events))))
  (dolist (sequence (list (format nil "~C]abc" (code-char 27))
                          (format nil "~C[M12" (code-char 27))
                          (format nil "~C[12" (code-char 27))))
    (let ((events (terminal-input-parser-feed
                   (make-terminal-input-parser :max-sequence-length 3)
                   sequence)))
      (is-equal 1 (length events))
      (is-equal :input-overflow (custom-event-name (first events)))))
  (let ((parser (make-terminal-input-parser)))
    (terminal-input-parser-feed parser (string (code-char 27)))
    (let ((events (terminal-input-parser-flush parser)))
      (is-equal 1 (length events))
      (is-equal :escape (key-event-key (first events))))))

(deftest terminal-input-parser-escape-control-and-bounded-input (:input-parser)
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser)))
    (let ((events (terminal-input-parser-feed parser
                                              (concatenate 'string
                                                           (string #\Tab)
                                                           (string #\Return)
                                                           (string escape)
                                                           "OP"))))
      (is-equal 3 (length events))
      (is-equal :tab (key-event-key (first events)))
      (is-equal :enter (key-event-key (second events)))
      (is-equal :f1 (third events)))
    (let ((events (terminal-input-parser-feed
                   parser (format nil "~C~C" escape #\x))))
      (is-equal 1 (length events))
      (is-equal #\x (key-event-key (first events)))
      (is-equal '(:alt) (key-event-modifiers (first events))))
    (let ((events (terminal-input-parser-feed
                   parser (format nil "~C~C" (code-char 1) (code-char 0)))))
      (is-equal 2 (length events))
      (is-equal #\a (key-event-key (first events)))
      (is-equal '(:ctrl) (key-event-modifiers (first events)))
      (is-equal :control (custom-event-name (second events)))
      (is-equal 0 (custom-event-payload (second events))))
    (let ((events (terminal-input-parser-feed
                   parser (format nil "~C[2~~" escape))))
      (is-equal :insert (key-event-key (first events))))
    (is (null (terminal-input-parser-feed parser
                                          (format nil "~CO" escape))))
    (let ((events (terminal-input-parser-feed parser "z")))
      (is-equal 1 (length events))
      (is-equal :terminal-sequence (custom-event-name (first events)))
      (is-equal #\z (getf (custom-event-payload (first events)) :final)))
    (loop for (sequence expected) in
            '(("[A" :up) ("[B" :down) ("[C" :right) ("[D" :left)
              ("[H" :home) ("[F" :end) ("[P" :f1) ("[Q" :f2)
              ("[R" :f3) ("[S" :f4) ("[1~" :home) ("[2~" :insert)
              ("[3~" :delete) ("[4~" :end) ("[5~" :page-up)
              ("[6~" :page-down) ("[11~" :f1) ("[12~" :f2)
              ("[13~" :f3) ("[14~" :f4) ("[15~" :f5) ("[17~" :f6)
              ("[18~" :f7) ("[19~" :f8) ("[20~" :f9) ("[21~" :f10)
              ("[23~" :f11) ("[24~" :f12))
          for event = (first (terminal-input-parser-feed
                              parser (format nil "~C~A" escape sequence)))
          do (is-equal expected (key-event-key event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[1;9A" escape)))))
      (is-equal :up (key-event-key event))
      (is-equal '(:super) (key-event-modifiers event)))
    (let ((events (terminal-input-parser-feed
                   parser (format nil "~C[?25l" escape))))
      (is-equal :terminal-sequence (custom-event-name (first events)))
      (is-equal #\l (getf (custom-event-payload (first events)) :final)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<0;3;4m" escape)))))
      (is-equal :release (mouse-event-kind event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<1;2;2M" escape)))))
      (is-equal :middle (mouse-event-button event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<2;2;2M" escape)))))
      (is-equal :right (mouse-event-button event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<:;2;2M" escape)))))
      (is-equal :terminal-sequence (custom-event-name event))
      (is-equal "<:;2;2" (getf (custom-event-payload event) :body))
      (is-equal #\M (getf (custom-event-payload event) :final)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<64;2;2M" escape)))))
      (is-equal :scroll-up (mouse-event-kind event))
      (is-equal :wheel (mouse-event-button event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<65;2;2M" escape)))))
      (is-equal :scroll-down (mouse-event-kind event))
      (is-equal :wheel (mouse-event-button event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<3;2;2M" escape)))))
      (is-equal :unknown (mouse-event-button event))
      (is-equal :press (mouse-event-kind event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[<60;2;2M" escape)))))
      (is-equal :move (mouse-event-kind event))
      (is-equal '(:ctrl :alt :shift)
                (mouse-event-modifiers event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[O" escape)))))
      (is-equal :focus (event-kind event))
      (is (not (focus-event-focused-p event))))
    (let ((events (terminal-input-parser-feed
                   parser (format nil "~C~C~C" #\Tab #\Return #\Backspace))))
      (is-equal '(:tab :enter :backspace)
                (mapcar #'key-event-key events))))
  (let ((events (terminal-input-parser-feed
                 (make-terminal-input-parser)
                 (vector #xf0 #x9f #x98 #x80))))
    (is-equal "😀" (text-input-event-text (first events))))
  (let ((events (terminal-input-parser-feed
                 (make-terminal-input-parser)
                 (vector #xc2 #xa2))))
    (is-equal "¢" (text-input-event-text (first events))))
  (let ((events (terminal-input-parser-feed
                 (make-terminal-input-parser)
                 (vector #x41))))
    (is-equal "A" (text-input-event-text (first events))))
  (let ((events (terminal-input-parser-feed
                 (make-terminal-input-parser)
                 (concatenate 'string "abc" (string #\Tab)))))
    (is-equal 2 (length events))
    (is-equal "abc" (text-input-event-text (first events)))
    (is-equal :tab (key-event-key (second events))))
  (dolist (octets (list (vector #xc2 #x20)
                        (vector #xe0 #x80 #x80)
                        (vector #xed #xa0 #x80)
                        (vector #xf0 #x80 #x80 #x80)
                        (vector #xf4 #x90 #x80 #x80)))
    (let ((events (terminal-input-parser-feed
                   (make-terminal-input-parser) octets)))
      (is-equal (code-char #xfffd)
                (char (text-input-event-text (first events)) 0))))
  (let ((parser (make-terminal-input-parser)))
    (is (null (terminal-input-parser-feed parser (vector #xf0 #x9f))))
    (let ((events (terminal-input-parser-flush parser)))
      (is-equal 1 (length events))
      (is-equal (code-char #xfffd)
                (char (text-input-event-text (first events)) 0))))
  (is (signals-error
       (terminal-input-parser-feed (make-terminal-input-parser)
                                   (vector 256))))
  (is (signals-error
       (terminal-input-parser-feed (make-terminal-input-parser)
                                   (vector :bad))))
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser :max-paste-length 3)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[200~~abcd" escape)))))
      (is-equal :paste-overflow (custom-event-name event))))
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser :max-paste-length 3)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[200~~abcd~C[201~~"
                                escape escape)))))
      (is-equal :paste-overflow (custom-event-name event))))
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser)))
    (terminal-input-parser-feed parser (format nil "~C[200~~partial" escape))
    (let ((event (first (terminal-input-parser-flush parser))))
      (is-equal :paste-incomplete (custom-event-name event))
      (is-equal "partial" (custom-event-payload event))))
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser)))
    (terminal-input-parser-feed parser (format nil "~C[200~~a~C[20"
                                  escape escape))
    (let ((event (first (terminal-input-parser-flush parser))))
      (is-equal :paste-incomplete (custom-event-name event))
      (is-equal (format nil "a~C[20" escape)
                (custom-event-payload event))))
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser)))
    (is (null (terminal-input-parser-feed
               parser (format nil "~C[200~~" escape))))
    (is (null (terminal-input-parser-feed
               parser (format nil "~C[20" escape))))
    (is (terminal-input-parser-pending-p parser))
    (let ((events (terminal-input-parser-feed parser "1~")))
      (is-equal 1 (length events))
      (is-equal :paste (event-kind (first events)))
      (is-equal "" (paste-event-text (first events)))))
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser)))
    (terminal-input-parser-feed parser (format nil "~C[" escape))
    (let ((event (first (terminal-input-parser-flush parser))))
      (is-equal :input-incomplete (custom-event-name event))))
  (is (signals-error
       (terminal-input-parser-feed (make-terminal-input-parser) :invalid))))

(deftest deterministic-event-loop-timers-and-errors (:protocol)
  (let* ((events nil)
        (event-loop (make-event-loop
                     :clock (lambda () 0)
                     :event-handler (lambda (event)
                                      (push (custom-event-name event) events)))))
    (event-loop-post event-loop (make-custom-event :queued))
    (event-loop-schedule-event event-loop 0 (make-custom-event :timer))
    (is (event-loop-wakeup-p event-loop))
    (is (event-loop-step event-loop))
    (is-equal :queued (first events))
    (is (event-loop-step event-loop :now 0))
    (is (event-loop-step event-loop :now 0))
    (is-equal :timer (first events))
    (event-loop-clear-wakeup event-loop)
    (is (not (event-loop-wakeup-p event-loop))))
  (let* ((calls 0)
        (events nil)
        (event-loop (make-event-loop
                     :clock (lambda () 0)
                     :event-handler (lambda (event)
                                      (push (custom-event-name event) events)))))
    (let ((task (event-loop-schedule
                 event-loop 2
                 (lambda (scheduled-loop task)
                   (declare (ignore scheduled-loop task))
                   (incf calls)
                   (make-custom-event :timer-fired))
                 :repeat 2)))
      (is (not (event-loop-step event-loop :now 1)))
      (is (event-loop-step event-loop :now 2))
      (is-equal 1 calls)
      (is (event-loop-step event-loop :now 2))
      (is-equal :timer-fired (first events))
      (event-loop-cancel event-loop task)
      (is (not (event-loop-step event-loop :now 4)))))
  (let* ((errors 0)
        (source nil)
        (event-loop (make-event-loop
                     :event-handler (lambda (event)
                                      (declare (ignore event))
                                      (error "expected event failure"))
                     :error-handler (lambda (condition loop actual-source)
                                      (declare (ignore condition loop))
                                      (incf errors)
                                      (setf source actual-source)
                                      t))))
    (event-loop-post event-loop (make-custom-event :failure))
    (is (event-loop-step event-loop))
    (is-equal 1 errors)
    (is-equal :event source)))

(deftest event-loop-run-scheduling-and-stop-contracts (:protocol)
  (let* ((events nil)
         (event-loop (make-event-loop
                      :clock (lambda () 10)
                      :event-handler (lambda (event)
                                       (push (custom-event-name event) events)))))
    (event-loop-post event-loop (make-custom-event :queued))
    (let ((task (event-loop-schedule
                 event-loop 0
                 (lambda (scheduled-loop scheduled-task)
                   (declare (ignore scheduled-loop scheduled-task))
                   (list (make-custom-event :first)
                         (make-custom-event :second))))))
      (is-equal 1 (event-loop-pending-task-count event-loop))
      (is-equal 10 (event-loop-next-deadline event-loop))
      (is-equal 2 (event-loop-run event-loop :max-steps 2))
      (is-equal '(:queued) events)
      (is (event-loop-pending-event-p event-loop))
      (is-equal 2 (event-loop-run event-loop))
      (is-equal '(:second :first :queued) events)
      (is (not (event-loop-pending-p event-loop)))
      (is (not (event-loop-running-p event-loop)))
      (is (not (event-loop-step event-loop :now 10)))
      (is (event-loop-cancel event-loop task))
      (is (null (event-loop-next-deadline event-loop)))))
  (let* ((events nil)
         (event-loop (make-event-loop
                      :clock (lambda () 10)
                      :event-handler (lambda (event)
                                       (push (custom-event-name event) events))))
         (task (event-loop-schedule-event
                event-loop 1 (make-custom-event :future))))
    (is-equal 11 (event-loop-next-deadline event-loop))
    (is (not (event-loop-step event-loop :now 10)))
    (is (event-loop-step event-loop :now 11))
    (is (event-loop-pending-event-p event-loop))
    (is (event-loop-step event-loop :now 11))
    (is-equal '(:future) events)
    (is-equal 0 (event-loop-pending-task-count event-loop))
    (is (event-loop-cancel event-loop task)))
  (let* ((seen 0)
         (event-loop (make-event-loop
                      :event-handler (lambda (event)
                                       (declare (ignore event))
                                       (incf seen)))))
    (event-loop-post event-loop (make-custom-event :until))
    (is-equal 1
              (event-loop-run event-loop
                              :until (lambda (loop)
                                       (declare (ignore loop))
                                       (plusp seen))))
    (is-equal 1 seen))
  (let ((event-loop nil)
        (seen 0))
    (setf event-loop
          (make-event-loop
           :event-handler (lambda (event)
                            (declare (ignore event))
                            (incf seen)
                            (event-loop-stop event-loop))))
    (event-loop-post event-loop (make-custom-event :stop))
    (is-equal 1 (event-loop-run event-loop))
    (is (event-loop-stopped-p event-loop))
    (is (not (event-loop-running-p event-loop)))
    (is-equal 1 seen))
  (let* ((errors 0)
         (event-loop (make-event-loop
                      :error-handler (lambda (condition loop source)
                                       (declare (ignore condition loop source))
                                       (incf errors)
                                       t))))
    (event-loop-schedule
     event-loop 0
     (lambda (scheduled-loop task)
       (declare (ignore scheduled-loop task))
       (error "expected timer failure")))
    (is (event-loop-step event-loop))
    (is-equal 1 errors))
  (let ((event-loop (make-event-loop)))
    (is (signals-error
         (event-loop-schedule event-loop -1 #'identity)))
    (is (signals-error
         (event-loop-schedule event-loop 0 nil)))
    (is (signals-error
         (event-loop-schedule event-loop 0 #'identity :repeat 0)))
    (is (signals-error (event-loop-post event-loop :not-an-event)))
    (is (signals-error (event-loop-run event-loop :max-steps -1)))))

(deftest terminal-event-sources-and-replay (:protocol)
  (let* ((escape (code-char 27))
         (chunks (list (format nil "~C[" escape) "1A" "z"))
         (close-count 0)
         (source (make-terminal-event-source
                  (lambda ()
                    (if chunks
                        (pop chunks)
                        :eof))
                  :close-reader (lambda () (incf close-count)))))
    (is (not (terminal-event-source-pending-p source)))
    (is-equal :up
              (key-event-key (terminal-event-source-next source)))
    (is-equal "z"
              (text-input-event-text (terminal-event-source-next source)))
    (is-equal :eof (terminal-event-source-next source))
    (is (terminal-event-source-eof-p source))
    (is (terminal-event-source-closed-p source))
    (is-equal 1 close-count)
    (terminal-event-source-close source)
    (is-equal 1 close-count))
  (let ((stream (make-string-input-stream "ab")))
    (let ((source (make-stream-event-source stream
                                            :chunk-size 1
                                            :close-stream-p t)))
      (is-equal "a"
                (text-input-event-text (terminal-event-source-next source)))
      (is-equal "b"
                (text-input-event-text (terminal-event-source-next source)))
      (is-equal :eof (terminal-event-source-next source))
      (is (not (open-stream-p stream)))))
  (let* ((event-a (make-custom-event :a))
         (event-b (make-custom-event :b))
         (replay (make-event-replay (list event-a event-b)
                                    :eof-value :done)))
    (is-equal 2 (event-replay-remaining-count replay))
    (is (eq event-a (event-replay-next replay)))
    (is-equal 1 (event-replay-remaining-count replay))
    (is (eq event-b (event-replay-next replay)))
    (is (event-replay-exhausted-p replay))
    (is-equal :done (event-replay-next replay))
    (event-replay-reset replay)
    (is (not (event-replay-exhausted-p replay)))
    (is (eq event-a (event-replay-next replay))))
  (let ((backend (make-test-backend)))
    (test-backend-emit backend (make-custom-event :recorded))
    (let ((replay (test-backend-event-replay backend :eof-value :done)))
      (is-equal :recorded
                (custom-event-name (event-replay-next replay)))
      (is-equal :done (event-replay-next replay)))))

(deftest terminal-source-parser-and-stream-contracts (:protocol)
  (let* ((parser (make-terminal-input-parser))
         (close-count 0)
         (source (make-terminal-event-source
                  (lambda () :eof)
                  :parser parser
                  :close-reader (lambda () (incf close-count)))))
    (terminal-input-parser-feed parser (format nil "~C[" (code-char 27)))
    (is (terminal-event-source-pending-p source))
    (terminal-event-source-close source)
    (is (not (terminal-event-source-pending-p source)))
    (is (terminal-event-source-eof-p source))
    (is (terminal-event-source-closed-p source))
    (is-equal :eof (terminal-event-source-next source))
    (terminal-event-source-close source)
    (is-equal 1 close-count))
  (let ((stream (make-string-input-stream "x")))
    (let ((source (make-stream-event-source stream
                                            :chunk-size 1
                                            :close-stream-p nil)))
      (is-equal "x"
                (text-input-event-text (terminal-event-source-next source)))
      (is-equal :eof (terminal-event-source-next source))
      (is (open-stream-p stream))))
  (let ((source (make-terminal-event-source (lambda () :invalid))))
    (is (signals-error (terminal-event-source-next source))))
  (is (signals-error (make-terminal-event-source nil)))
  (is (signals-error
       (make-terminal-event-source #'identity :parser :invalid)))
  (is (signals-error
       (make-terminal-event-source #'identity :close-reader :invalid)))
  (let ((stream (make-string-input-stream "")))
    (is (signals-error
         (make-stream-event-source stream :chunk-size 0)))
    (is (signals-error
         (make-stream-event-source stream :element-type :invalid)))
    (is (signals-error
         (make-stream-event-source stream :close-stream-p :yes)))))

(deftest terminal-input-parser-modern-keyboard-and-x10-mouse (:input-parser)
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[97;5u" escape)))))
      (is (typep event 'key-event))
      (is-equal #\a (key-event-key event))
      (is-equal "a" (key-event-text event))
      (is-equal '(:ctrl) (key-event-modifiers event))
      (is-equal :press (key-event-phase event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[97;49u" escape)))))
      (is-equal #\a (key-event-key event))
      (is-equal '(:alt :hyper) (key-event-modifiers event)))
    (dolist (case '((9 :tab) (8 :backspace) (127 :backspace)
                    (10 :enter) (13 :enter) (27 :escape)))
      (destructuring-bind (codepoint key) case
        (let ((event (first (terminal-input-parser-feed
                             parser (format nil "~C[~Du" escape codepoint)))))
          (is-equal key (key-event-key event)))))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[97;64u" escape)))))
      (is-equal '(:ctrl :alt :shift :super :hyper)
                (key-event-modifiers event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[97;1:4u" escape)))))
      (is-equal :terminal-sequence (custom-event-name event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[97;1:2u" escape)))))
      (is-equal #\a (key-event-key event))
      (is-equal :repeat (key-event-phase event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[13;1:3u" escape)))))
      (is-equal :enter (key-event-key event))
      (is-equal :release (key-event-phase event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (format nil "~C[27;5;97~~" escape)))))
      (is-equal #\a (key-event-key event))
      (is-equal '(:ctrl) (key-event-modifiers event))
      (is-equal "a" (key-event-text event)))
    (is (null (terminal-input-parser-feed parser
                                          (format nil "~C[M" escape))))
    (let ((event (first (terminal-input-parser-feed
                         parser (string (map 'string #'code-char
                                             (list 32 33 35)))))))
      (is (typep event 'mouse-event))
      (is-equal :left (mouse-event-button event))
      (is-equal :press (mouse-event-kind event))
      (is-equal 0 (mouse-event-x event))
      (is-equal 2 (mouse-event-y event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (concatenate
                                 'string
                                 (format nil "~C[M" escape)
                                 (string (map 'string #'code-char
                                               (list 100 34 34))))))))
      (is-equal :scroll-up (mouse-event-kind event))
      (is-equal :wheel (mouse-event-button event))
      (is-equal '(:shift) (mouse-event-modifiers event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (concatenate
                                 'string
                                 (format nil "~C[M" escape)
                                 (string (map 'string #'code-char
                                               (list 56 34 34))))))))
      (is-equal :left (mouse-event-button event))
      (is-equal :press (mouse-event-kind event))
      (is-equal '(:ctrl :alt) (mouse-event-modifiers event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (concatenate
                                 'string
                                 (format nil "~C[M" escape)
                                 (string (map 'string #'code-char
                                               (list 64 34 35))))))))
      (is-equal :move (mouse-event-kind event))
      (is-equal :left (mouse-event-button event))
      (is-equal 1 (mouse-event-x event))
      (is-equal 2 (mouse-event-y event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (concatenate
                                 'string
                                 (format nil "~C[M" escape)
                                 (string (map 'string #'code-char
                                               (list 35 34 35))))))))
      (is-equal :release (mouse-event-kind event))
      (is-equal :unknown (mouse-event-button event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (concatenate
                                 'string
                                 (format nil "~C[M" escape)
                                 (string (map 'string #'code-char
                                               (list 32 32 32))))))))
      (is-equal 0 (mouse-event-x event))
      (is-equal 0 (mouse-event-y event)))
    (let ((event (first (terminal-input-parser-feed
                         parser (concatenate
                                 'string
                                 (format nil "~C[M" escape)
                                 (string (map 'string #'code-char
                                               (list 31 33 34))))))))
      (is-equal :terminal-sequence (custom-event-name event)))))

(deftest terminal-input-parser-public-readers-return-defensive-copies
    (:input-parser)
  (let* ((escape (code-char 27))
         (parser (make-terminal-input-parser)))
    (is (null (terminal-input-parser-feed parser (format nil "~C[" escape))))
    (let ((buffer (terminal-input-parser-buffer parser)))
      (is-equal (format nil "~C[" escape) buffer)
      ;; Destructively mutate the copy in place. If TERMINAL-INPUT-PARSER-
      ;; BUFFER ever hands back the live internal string again instead of a
      ;; copy, this corrupts the buffered "ESC [" into "ESC X" and the CSI
      ;; sequence fed below is parsed as a bare Alt+X keypress instead of
      ;; Ctrl+Up.
      (setf (char buffer 1) #\X)
      (is (not (eq buffer (terminal-input-parser-buffer parser))))
      (let ((events (terminal-input-parser-feed parser "1;5A")))
        (is-equal 1 (length events))
        (is-equal :up (key-event-key (first events)))
        (is-equal '(:ctrl) (key-event-modifiers (first events))))))
  (let ((parser (make-terminal-input-parser)))
    (is (null (terminal-input-parser-feed parser (vector #xe6))))
    (let ((octets (terminal-input-parser-pending-octets parser)))
      (is-equal (list #xe6) octets)
      ;; Same idea for the octet list: corrupt the copy's first cons. If
      ;; TERMINAL-INPUT-PARSER-PENDING-OCTETS ever hands back the live
      ;; internal list, this replaces the buffered lead byte of a 3-byte
      ;; UTF-8 sequence with 0, and the two continuation bytes fed below
      ;; decode as garbage instead of completing "日".
      (setf (car octets) 0)
      (is (not (eq octets (terminal-input-parser-pending-octets parser))))
      (let ((events (terminal-input-parser-feed parser (vector #x97 #xa5))))
        (is-equal 1 (length events))
        (is-equal "日" (text-input-event-text (first events)))))))

(cl-weave:it-fuzz "terminal input parser accepts generated bounded text"
  ((input (cl-weave:gen-string
           :min-length 0
           :max-length 48
           :alphabet (concatenate 'string
                                  "abc[];?~"
                                  (string (code-char 27))
                                  (string (code-char 7))))))
  (:trials 120 :timeout-per-trial 2)
  ;; The original assertion only checked LISTP, which every reachable input
  ;; already satisfies -- it could not distinguish correct parsing from
  ;; garbage.  This strengthens it with two structural invariants: every
  ;; returned element is a normalized EVENT, and parsing is deterministic
  ;; (a fresh parser fed the same input produces the same events), while
  ;; keeping the original crash-resistance property (a trial fails only if
  ;; the parser signals an ERROR).
  (let* ((parser (make-terminal-input-parser :max-sequence-length 64))
         (fed-events (terminal-input-parser-feed parser input))
         (flushed-events (terminal-input-parser-flush parser)))
    (is (every #'event-p fed-events))
    (is (every #'event-p flushed-events))
    (let* ((replay-parser (make-terminal-input-parser :max-sequence-length 64))
           (replay-fed-events
             (terminal-input-parser-feed replay-parser input))
           (replay-flushed-events
             (terminal-input-parser-flush replay-parser)))
      (is-equal fed-events replay-fed-events)
      (is-equal flushed-events replay-flushed-events))))
