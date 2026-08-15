# Event Loop

`cl-tui-kit/core` ships a deterministic, optional event-loop protocol,
implemented in `src/protocol.lisp`. It is not forced on an application:
`application-step`/`application-step/k` (see [API Reference](api.md)) work
without it, driven by whatever event source the application already has. The
event loop exists for applications that want a single place to coordinate
posted events and delayed or repeating work — a spinner tick, a debounce, a
timeout — without reaching for threads or wall-clock sleeps.

Every `event-loop-*` symbol exported by `cl-tui-kit/core` is covered by
this page and is part of the SemVer-stable surface (see
[API Stability](../project/api-stability.md)).

## Why this reconciles with "no hidden event loop"

[Architecture](architecture.md) says the toolkit does not hide an event loop
or a second runtime model behind the application's back, and does not
introduce a hidden thread or sleep. This event loop is consistent with both
claims because:

- It is **opt-in**: nothing in `cl-tui-kit/widgets` or `cl-tui-kit/ansi`
  constructs one for you, and using it is an application choice, not a
  toolkit requirement.
- It is **deterministic**: `EVENT-LOOP-CLOCK` is an injected zero-argument
  function, not a call to wall-clock time baked into the implementation.
  Feeding it a test clock makes timer behavior reproducible.
- It **never sleeps and never spawns a thread**. `event-loop-step` processes
  at most one unit of work and returns immediately, whether or not anything
  was ready; `event-loop-run` loops over `event-loop-step` calls but stops
  the moment there is no more ready work, rather than blocking to wait for
  more.

## Constructing a loop

```lisp
(make-event-loop &key clock event-handler error-handler)
```

Creates a deterministic, threadless `event-loop`.

- `clock` — a zero-argument function returning a numeric monotonic time.
  Defaults to a function that divides `get-internal-real-time` by
  `internal-time-units-per-second`.
- `event-handler` — a function of one argument (a normalized `event`) used
  by `event-loop-step`/`event-loop-run` when no `:handler` override is
  passed to those calls.
- `error-handler` — a function of three arguments, `(condition loop
  source)`, where `source` is `:event` or `:timer`. Returning a true value
  continues the loop; when omitted, defaults to an internal handler that
  always re-signals `condition` with `(error condition)`.

Signals `invalid-type-error` (via `check-type`) if `clock`, `event-handler`,
or `error-handler` is supplied but not a function.

### The `event-loop` struct

`event-loop` is opaque state; construct it only through `make-event-loop`.
Its readers:

- `event-loop-clock` — the clock function.
- `event-loop-event-handler` — the default event handler, or `nil`.
- `event-loop-error-handler` — the error handler.
- `event-loop-running-p` — true while `event-loop-run` is on the stack.
- `event-loop-stopped-p` — true after `event-loop-stop`, until the next
  `event-loop-run` call resets it.

`event-loop-now`:

```lisp
(event-loop-now loop) ; => a number
```

Calls the loop's clock function and returns its result. Signals
`invalid-type-error` if `loop` is not an `event-loop`.

## Posting events

```lisp
(event-loop-post loop event) ; => event
```

Appends `event` to the loop's internal FIFO queue and marks the loop woken
(see [Deadlines, pending work, and the wakeup mechanism](#deadlines-pending-work-and-the-wakeup-mechanism)
below). `event` must satisfy `event-p` (any of the normalized event structs
from [API Reference](api.md#events)). Returns `event`.

Queued events are drained strictly before any due timer: `event-loop-step`
checks `event-loop-pending-event-p` first and only looks at timers when the
queue is empty.

## Scheduling one-shot and repeating tasks

```lisp
(event-loop-schedule loop delay callback &key repeat) ; => event-loop-task
```

Schedules `callback` to run after `delay` and returns a cancellable task.

- `delay` — a non-negative real number of clock units from now. Signals
  `invalid-range-error` when negative.
- `callback` — a function of two arguments, `(loop task)`. Its return value
  is interpreted by the loop: `nil` posts nothing, one `event` is posted
  directly, a list all of whose elements satisfy `event-p` is posted in
  order, and anything else signals `callback-contract-error` (see
  [Conditions](conditions.md#callback-contract-error)).
- `repeat` — when non-`nil`, a positive real delay between repeated
  invocations; the task reschedules itself after each run rather than being
  discarded. Signals `invalid-range-error` when supplied and not a positive
  real number.

Timers are evaluated only when `event-loop-step` runs a due task, so nothing
here creates a background thread or timer.

```lisp
(event-loop-schedule-event loop delay event &key repeat) ; => event-loop-task
```

Convenience wrapper: schedules `event` for delivery after `delay` without
writing a callback closure. `event` must satisfy `event-p`. `repeat` has the
same meaning as above. Internally this is `event-loop-schedule` with a
callback that ignores its arguments and returns `event`.

### The `event-loop-task` struct

Returned by both scheduling functions; also constructed only internally.
Exported readers:

- `event-loop-task-id` — an integer assigned in creation order, unique
  within the owning loop.
- `event-loop-task-deadline` — the clock value at which the task becomes
  ready to run. For a repeating task, this advances by `repeat` after each
  run.
- `event-loop-task-repeat` — the repeat interval, or `nil` for a one-shot
  task.
- `event-loop-task-cancelled-p` — true once `event-loop-cancel` has been
  called on this task.

## Cancellation

```lisp
(event-loop-cancel loop task) ; => task
```

Marks `task` cancelled and wakes the loop. Cancellation is idempotent —
calling it again on an already-cancelled task is a no-op — and does not
remove the task object from the loop's internal list; a cancelled task is
simply skipped by both readiness checks (`event-loop-next-deadline`,
`event-loop-pending-task-count`) and by `event-loop-step` itself. Signals
`invalid-type-error` if `task` is not an `event-loop-task`.

## Stepping versus running

```lisp
(event-loop-step loop &key now handler) ; => generalized boolean
```

Processes **at most one** queued event or one due timer, then returns —
true when work was processed, `nil` when nothing was ready.

- If an event is queued, it is dispatched to `handler` (or, when `handler`
  is omitted, to the loop's `event-handler`). If neither is available,
  signals `protocol-error` (see
  [Conditions](conditions.md#protocol-error)) — the loop refuses to
  silently drop a queued event.
- Otherwise, the single task with the earliest deadline at or before `now`
  (defaulting to `(event-loop-now loop)`) runs. Ties break by scheduling
  order (`event-loop-task`'s internal `sequence` field), so behavior is
  deterministic even when two tasks share a deadline.
- A condition signalled inside either an event handler or a timer callback
  is caught and routed to the loop's error handler via `handler-case`
  wrapping `(condition (condition) ...)`, not to the caller of
  `event-loop-step`.

`event-loop-step` never waits. When nothing is queued and nothing is due, it
returns `nil` immediately; the caller (an adapter, a test, or an application
loop) decides how and whether to wait for more input before calling it
again.

```lisp
(event-loop-run loop &key handler max-steps until) ; => integer
```

Repeatedly calls `event-loop-step` until one of:

- `event-loop-stop` has been called (`event-loop-stopped-p` becomes true),
- `event-loop-step` returns `nil` (no more ready work — the loop goes idle
  and returns rather than blocking),
- `max-steps` work items have been processed, or
- `until` (a function of one argument, the loop) returns true.

Returns the number of work items processed. Like `event-loop-step`, it never
sleeps; an idle loop with no `max-steps` or `until` limit simply returns as
soon as it finds no ready work. `event-loop-running-p` is true for the
duration of the call, via `unwind-protect`, so it becomes `nil` again even
if a propagated condition unwinds past this call.

```lisp
(event-loop-stop loop) ; => loop
```

Sets `event-loop-stopped-p` and wakes the loop. The next `event-loop-run`
call resets `stopped-p` to `nil` before it starts processing again, so
stopping is a one-shot request to end the *current* run, not a permanent
disable.

## Deadlines, pending work, and the wakeup mechanism

```lisp
(event-loop-pending-event-p loop)     ; => generalized boolean
(event-loop-pending-task-count loop)  ; => non-negative integer
(event-loop-pending-p loop)           ; => generalized boolean
(event-loop-next-deadline loop)       ; => number or nil
```

- `event-loop-pending-event-p` — true when the FIFO queue is non-empty.
- `event-loop-pending-task-count` — the count of tasks that are not
  cancelled (cancelled tasks are excluded, whether or not they have run).
- `event-loop-pending-p` — true when either of the above is true; a
  convenience for "does this loop have anything left to do."
- `event-loop-next-deadline` — the earliest deadline among non-cancelled
  tasks, or `nil` when there are none. An adapter that owns its own
  `poll`/`select` loop can use this to bound how long it waits for input
  before calling `event-loop-step` again.

```lisp
(event-loop-wakeup loop)        ; => loop
(event-loop-wakeup-p loop)      ; => generalized boolean
(event-loop-clear-wakeup loop)  ; => loop
```

The wakeup flag is a coordination signal, not a queue or a lock. `event-loop-post`,
`event-loop-schedule`, `event-loop-schedule-event`, `event-loop-cancel`, and
`event-loop-stop` all set it automatically. It exists so an external input
adapter — a TTY runtime polling a file descriptor, for example — can check
`event-loop-wakeup-p` to decide whether to skip its own blocking wait,
without the event-loop core owning that file descriptor or a thread itself.
`event-loop-clear-wakeup` resets the flag; the loop does not clear it for
you, since only the adapter knows when it has finished reacting to it.

## The error handler

Passed as `:error-handler` to `make-event-loop`, read back with
`event-loop-error-handler`. It receives `(condition loop source)`, where
`source` is `:event` (the condition came from an event handler) or `:timer`
(it came from a task callback). Returning a true value tells
`event-loop-step` to swallow the condition and continue; returning `nil` (or
any false value) re-signals `condition` with `(error condition)`, which
propagates out of `event-loop-step`/`event-loop-run` to the caller. The
default error handler always re-signals.

## Example

```lisp
(let* ((now 0)
       (loop (cl-tui-kit:make-event-loop
              :clock (lambda () now)
              :event-handler (lambda (event)
                                (format t "handled: ~S~%" event)))))
  ;; A one-shot timer that posts a custom event two ticks from now.
  (cl-tui-kit:event-loop-schedule-event
   loop 2 (cl-tui-kit:make-custom-event :ping))

  ;; Advance the injected clock instead of sleeping.
  (setf now 2)
  (cl-tui-kit:event-loop-run loop))
;; => 2 (one step runs the due timer and posts its event, one step dispatches
;;       the posted event to the handler)
;; prints: handled: #S(CUSTOM-EVENT ...)
```

Because the clock is an ordinary closure over `now`, this example is fully
reproducible in a test: no wall-clock sleep is needed to exercise the
timer's firing behavior.
