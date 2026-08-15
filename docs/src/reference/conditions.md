# Conditions

Every condition cl-tui-kit signals inherits `cl-tui-kit-error`, which in turn
inherits `cl:error`. Before this hierarchy existed the toolkit signalled
`simple-error` everywhere, which left message-string matching as the only way
for an application to tell one failure apart from another. All symbols on
this page are exported from `cl-tui-kit/core` unless a section says
otherwise, and — like the rest of the stable tier — are also visible through
the `cl-tui-kit` umbrella package (see
[Umbrella package re-exports](api.md#umbrella-package-re-exports)).

## Hierarchy

```
cl-tui-kit-error                          (cl-tui-kit/core)
├── invalid-argument-error
│   ├── invalid-type-error                (also inherits cl:type-error)
│   ├── invalid-range-error
│   ├── invalid-option-error
│   └── index-out-of-bounds-error
├── protocol-error
│   ├── focus-error
│   ├── surface-error
│   └── callback-contract-error
└── lifecycle-error
    └── tty-runtime-error                 (cl-tui-kit/tty)

assertion-failed-error                    (cl-tui-kit/testing, direct child
                                            of cl-tui-kit-error)
```

## Root: `cl-tui-kit-error`

`cl-tui-kit-error` is the root of every condition the toolkit signals and the
one type to catch when an application wants to distinguish a toolkit
rejection from an error raised by its own code.

- `cl-tui-kit-error-context` — a symbol or string naming the parameter,
  slot, or operation the failure is about, or `nil` when the failure is not
  tied to one. Initarg `:context`.
- `cl-tui-kit-error-detail` — a human-readable sentence describing the
  failure, or `nil` to let the subclass compose one from its slots. Initarg
  `:detail`.

Its `:report` prints `detail` when supplied, otherwise the literal string
"cl-tui-kit signalled an error." `protocol-error`, `focus-error`,
`surface-error`, and `lifecycle-error` define no `:report` of their own, so
they fall back to this one — `detail` (when a call site supplies it) is the
only way those four produce a specific message.

## Invalid arguments

The caller passed a value the operation cannot use.

### `invalid-argument-error`

- `invalid-argument-error-datum` — the offending value, or a truncated
  printed representation of it when the value could grow without bound (see
  [`bounded-datum` and unbounded payloads](#bounded-datum-and-unbounded-payloads)
  below). Initarg `:datum`.

Report: when `detail` is set, `"<detail> Got <datum>."`; otherwise
`"Invalid <context>: <datum>."`.

Representative sites: `%parse-keyword-options` in `src/surface.lisp` (an
odd number of keyword arguments to `make-cell`/`make-surface`),
`backend-request-clipboard` in `src/ansi.lisp` (a malformed OSC 52
selection), `make-spinner-widget` in `src/input-spinner.lisp` (an empty
`:frames` list).

### `invalid-type-error`

Inherits both `invalid-argument-error` and `cl:type-error`. Because CLOS
merges same-named slots from multiple direct superclasses into one effective
slot, the single `datum` slot is reachable through both
`invalid-argument-error-datum` and the standard `type-error-datum`, and
`type-error-expected-type` (initarg `:expected-type`) keeps working exactly
as it did before this hierarchy existed, when the geometry constructors
signalled a bare `type-error`. There is no `invalid-type-error`-specific
accessor beyond what its two parents already provide.

Report: when `detail` is set, `"<detail> Got <datum>."`; otherwise
`"<context>: expected <expected-type>, got <datum>."` (the context prefix is
omitted when `context` is `nil`).

Representative sites: the `point`/`size`/`rectangle`/`padding`/`margin`/
`viewport` constructors in `src/geometry.lisp` (a non-integer coordinate or
extent), `make-backend` in `src/backend.lisp` (a non-hash-table
`:capability-states`), the `define-keymap` macro-expansion checks in
`src/keymap.lisp`, `terminal-input-parser-feed` in `src/input-parser.lisp`
(neither a string nor a vector), and `make-list-model`/`make-tree-model` in
`src/list.lisp`/`src/tree.lisp` (a non-function, non-integer
`:count`/`:root-count`).

### `invalid-range-error`

- `invalid-range-error-expected` — a human-readable description of the
  accepted range, such as `"a positive integer"` or `"a real number between
  0 and 1"`. Initarg `:expected`.

Report: when `detail` is set, `"<detail> Got <datum>."`; otherwise
`"<context> must be <expected>, got <datum>."` (or `"Expected <expected>,
got <datum>."` when `context` is `nil`).

Representative sites: `make-constraints` in `src/geometry.lisp` (negative
flexibility, or a maximum smaller than the minimum),
`string-cell-width`/`clip-text`/`truncate-text` in `src/text.lisp` (a
non-positive `:tab-width`), `indexed-color`/`rgb-color` in `src/style.lisp`
(a component outside 0–255), `make-split`/`make-grid` in `src/layout.lisp`
(a `:ratio` outside 0–1, or non-positive `:columns`/`:rows`),
`event-loop-schedule` in `src/protocol.lisp` (a negative `:delay` or
non-positive `:repeat`).

### `invalid-option-error`

- `invalid-option-error-allowed` — the list of values the operation accepts
  here. Initarg `:allowed`.

Report: when `detail` is set, `"<detail> Got <datum>."`; otherwise `"Invalid
<context>: <datum>.[ Expected one of <allowed>.]"` (the allowed clause is
omitted when `allowed` is `nil`; `context` defaults to `"option"` when the
call site does not supply one).

Representative sites: `normalize-modifiers` in `src/event.lisp` (an
unrecognized modifier designator), `src/backend.lisp` (an unknown capability
name or capability state), `make-divider-widget`/`make-scroll-bar-widget` in
`src/widgets.lisp` (an orientation outside `:horizontal`/`:vertical`),
`make-table-column` in `src/widgets-tables.lisp` (an `:align` outside
`:left`/`:right`/`:center`).

### `index-out-of-bounds-error`

- `index-out-of-bounds-error-index` — the index that was requested. Initarg
  `:index`.
- `index-out-of-bounds-error-count` — the number of elements actually
  available. Initarg `:count`.

Report: when `detail` is set, `"<detail> Got <datum>."`; otherwise
`"Index <index> is outside the range of <count> <context>."` (context
defaults to `"elements"`).

Representative sites: `make-spinner-widget` in `src/input-spinner.lisp`
(`:index` outside the frame list), `%control-check-index` in
`src/input-choice-controls.lisp` (shared by `radio-widget-select` and
`select-widget-select`).

## Protocol violations

The arguments were individually acceptable, but the structure or contract
they participate in was broken.

### `protocol-error`

No slots beyond the root. Signalled directly (not through a subclass) from
`event-loop-step` in `src/protocol.lisp`, when it finds a queued event but
no event handler was supplied to receive it.

### `focus-error`

A focus operation named a node that does not belong to the tree, or that
lies outside the active modal scope. No slots beyond the root. Signalled
from `focus-tree-set-current` and `focus-push-modal`, both in
`src/focus.lisp`.

### `surface-error`

A cell or surface invariant was broken: a continuation cell carrying
content, or a drawable cell whose display width does not match its span. No
slots beyond the root. Signalled from `%validate-cell-invariant` in
`src/surface.lisp` (reached from `make-cell`, `copy-cell`, and
`surface-put-cell`).

### `callback-contract-error`

A caller-supplied callback returned a value the protocol cannot use.

- `callback-contract-error-callback` — a symbol or string naming the
  callback that misbehaved. Initarg `:callback`.
- `callback-contract-error-value` — what the callback returned, truncated by
  `bounded-datum` when it could grow without bound. Initarg `:value`.

Report: `"<detail-or-default> Got <value>."`, where the default is
`"Callback <callback> returned an unusable value."`.

Sites: `%event-loop-post-result` in `src/protocol.lisp` (the event-loop
timer callback returned something other than an event, a list of events, or
`nil`), `terminal-event-source-next` in `src/protocol.lisp` (a terminal
event source reader returned something other than a string, an octet
vector, or its `eof-value`), and `%validated-model-count` in
`src/list.lisp` (shared by `list-model-count`/`tree-model-root-count` when a
`list-model`/`tree-model` `:count`/`:root-count` callback does not return a
non-negative integer).

## Lifecycle violations

The operation is well-formed but not legal for the object's current state.

### `lifecycle-error`

- `lifecycle-error-current-state` — the state the object was in when the
  operation was attempted. Initarg `:current-state`.
- `lifecycle-error-requested-operation` — a symbol naming the operation that
  was refused. Initarg `:requested-operation`.

No call site in `cl-tui-kit/core` signals `lifecycle-error` directly today;
it exists as the shared base for lifecycle violations across the toolkit,
currently specialized by `tty-runtime-error` below.

### `tty-runtime-error` (`cl-tui-kit/tty`)

Defined in `src/tty.lisp`, in the `cl-tui-kit/tty` package rather than
`cl-tui-kit/core`, deliberately: `cl-tui-kit/core` is the SemVer-frozen
stable tier, while `cl-tui-kit/tty` is the experimental integration tier (see
[API Stability](../project/api-stability.md)). Freezing this symbol in
`core` would tie a stable package's contract to a consumer that may still
change in a minor release. It adds no slots of its own — it inherits
`current-state`/`requested-operation` from `lifecycle-error` — and because it
inherits `lifecycle-error`, a `handler-case` written against the core
condition catches it too.

Signalled from `tty-runtime-start` (two call sites: refuses to start a
runtime whose input stream was closed, and refuses to restart one already at
EOF) and `tty-runtime-reset` (two call sites: refuses to reset a runtime
that is still running, or whose input stream was closed), both in
`src/tty.lisp`.

## Testing: `assertion-failed-error` (`cl-tui-kit/testing`)

Defined in `src/testing.lisp`, outside `cl-tui-kit/core` for the same
reason as `tty-runtime-error`: `cl-tui-kit/testing` is a stable-tier system
in its own right, but a testing assertion is not a toolkit protocol
violation, so it is a direct child of `cl-tui-kit-error` rather than a
subclass of `protocol-error` or `invalid-argument-error`.

- `assertion-failed-error-expected` — the expected value. Initarg
  `:expected`.
- `assertion-failed-error-actual` — the actual value. Initarg `:actual`.

Report: `"<detail-or-default> Expected <expected>, got <actual>."`, where the
hardcoded default is `"Assertion failed."`. `"Surface text mismatch."` is
not a default — it is the `:detail` the one call site below supplies
explicitly.

Signalled from `assert-surface-text` in `src/testing.lisp`, when a surface's
rendered text does not match the expected string.

## `bounded-datum` and unbounded payloads

A signalled condition can outlive the call that signalled it: `backend-fail`
in `src/backend.lisp` stores the condition object itself in
`backend-last-error` for the lifetime of the backend. Retaining a
caller-supplied sequence or a callback's return value in that slot — through
a condition's `datum` or `value` — would pin an arbitrarily large object
graph in memory for as long as the backend lives.

`bounded-datum`, defined in `src/conditions.lisp`, is the guard against
that. It returns numbers, symbols, and characters unchanged; for any other
value it returns a printed representation, never the original object, with
two independent guarantees:

- **No raw control characters.** `prin1` escapes only `"` and `\` in a
  string, leaving a raw control byte such as ESC untouched — so a condition
  signalled from untrusted terminal input could otherwise carry one into a
  report an application prints to a live terminal, where it would be
  re-interpreted as a terminal escape sequence. Every character whose
  `char-code` is below 32, plus `#\Rubout` (code 127), is replaced with a
  printable `\xHH` escape.
- **An absolute character cap**, applied after escaping
  (`*condition-datum-print-characters*`, default 200). `*print-length*`
  (`*condition-datum-print-length*`, default 10) and `*print-level*`
  (`*condition-datum-print-level*`, default 3) bound how many elements
  `prin1` descends into, not the character length of the string it
  produces — a single long string, or a short list of long strings, still
  prints without bound under those two alone, so the escaped string is
  truncated by character count as a second, absolute pass.

The result is always a `string`, not the original object — a handler that
expects `invalid-type-error-datum` or `callback-contract-error-value` to be
the original Lisp object at these call sites will instead see its printed,
escaped, and possibly truncated representation.

Verified call sites that pass a value through `bounded-datum` before storing
it in a condition:

- `terminal-input-parser-feed` in `src/input-parser.lisp` bounds `input`
  before raising `invalid-type-error` when it is neither a string nor an
  octet vector.
- `%event-loop-post-result` in `src/protocol.lisp` bounds a timer callback's
  return value before raising `callback-contract-error`.
- `terminal-event-source-next` in `src/protocol.lisp` bounds a reader
  function's return value before raising `callback-contract-error`.

Most other `:datum` values in this hierarchy (an index, a keyword, a small
integer) are already bounded by construction and are passed through
directly; `bounded-datum` is reserved for call sites where the value comes
from unconstrained caller or callback input and could otherwise be
arbitrarily large.

## Backward compatibility

This hierarchy is additive, not a breaking change, for three kinds of
existing handler code:

- **Code catching `cl:error`** is unaffected — every condition here still
  inherits `cl:error` through `cl-tui-kit-error`.
- **Code catching `cl:type-error`** is unaffected for the geometry
  constructors and similar call sites: `invalid-type-error` inherits
  `cl:type-error` directly, and `type-error-datum`/`type-error-expected-type`
  keep returning the same values a bare `type-error` handler already
  expected.
- **Code that branched on the error's message text** is the one case that
  must change. Messages are still human-readable, but a program should match
  on condition type and slot values (`cl-tui-kit-error-context`,
  `invalid-argument-error-datum`, and so on) instead of parsing `:report`
  output.

## Worked example

```lisp
(handler-case
    (make-rectangle x y width height)
  (invalid-range-error (condition)
    ;; A specific, expected failure: report it in the caller's own words
    ;; using the condition's structured slots rather than its message text.
    (format *error-output* "~A: ~A~%"
            (cl-tui-kit-error-context condition)
            (invalid-range-error-expected condition)))
  (cl-tui-kit-error (condition)
    ;; Anything else the toolkit signalled: log it and re-signal, since this
    ;; handler does not know how to recover from an unanticipated failure.
    (format *error-output* "cl-tui-kit error: ~A~%" condition)
    (error condition)))
```

The first clause only fires for the exact failure the caller planned for;
the second is a catch-all for every other toolkit condition, distinguishable
from an application's own errors because they all share the
`cl-tui-kit-error` root.
