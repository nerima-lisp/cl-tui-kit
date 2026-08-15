# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project
adheres to [Semantic Versioning][semver]. The API stability policy that
SemVer applies to is defined in [CONTRIBUTING.md](CONTRIBUTING.md): the
`cl-tui-kit/core`, `/layout`, `/widgets`, `/ansi`, and `/testing` exports are
the stable tier; `cl-tui-kit/tty` and `cl-tui-kit/codec` are experimental and
may change in a minor release.

## [Unreleased]

## [4.1.0]

### Fixed

- A select widget closed by Enter, Escape, or a mouse press did not fire the
  `:action` callback the application supplied at construction, while one
  closed through `select-widget-toggle` did. The returned semantic action was
  correct on every path — that is the protocol's primary channel and it was
  never affected — but an application watching the callback saw `:close` only
  on the toggle path.

  The toolkit's convention elsewhere is that state with a supported callback
  is mutated through exactly one function which also fires it:
  `checkbox-widget`, `spinner-widget-tick`, `spinner-widget-toggle`, and
  `radio-widget-select` all work that way. The select widget's three close
  paths bypassed `select-widget-toggle` with a direct assignment; they now go
  through it.

  `menu-widget` and `modal-widget` are unaffected: neither stores a callback,
  so neither has an asymmetry to correct.

### Added

- Tests covering the copying readers introduced across the last four releases
  — `viewport-bounds`, `focus-node-children`, `focus-tree-modal-stack`,
  `widget-rectangle`, `widget-children`. Each asserts the returned value
  matches what the sanctioned mutator stored, that successive calls are not
  `eq`, and that mutating the returned object leaves the source unchanged. A
  copying reader that forgot to copy, or returned a fresh empty object, would
  previously have passed unnoticed.

## [4.0.0]

The first three rounds audited only `defclass` `:accessor` slots. `grep -rn
":read-only" src/*.lisp` returned nothing across the whole tree, which is the
short version of what they missed: no `defstruct` slot had ever been made
read-only, so struct-based state — focus trees, keymaps, viewports, themes,
the event loop, event replay — was never looked at. This round audited both
kinds.

### Fixed

- `tty-runtime-raw-mode-enabled-p` was writable, and `tty-runtime-stop` gates
  its `disable-raw-mode` call on it. An external write made cleanup skip
  restoring the terminal while still reporting success, leaving the user in
  raw mode with echo off after what looked like a clean shutdown. This is the
  only entry here that was a defect rather than an exposure.
- `focus-tree-current` was writable, so a direct write could move focus to a
  node outside an open modal's scope, escaping the focus trap that
  `focus-tree-set-current` enforces.

### Changed

- Roughly thirty more accessors onto internal state are read-only, across
  `focus`, `keymap`, `geometry`, `style`, `protocol`, `testing`, `tty`, the
  widget layer, and the application runtime. Readers that previously handed
  back a live list, rectangle, style, or capability struct now return a copy,
  because blocking `setf` on the accessor does nothing about a caller reaching
  internal state through the object it was given.
- `widget-rectangle` and `widget-children` copy on read. Internal render and
  layout paths use the private accessors, so no per-frame allocation was
  added.
- `viewport-bounds` copies on read and on write rather than becoming
  read-only: no function owns it, so direct assignment is the interface, and
  only the aliasing route needed closing.

  **Breaking.** `setf` on the converted accessors no longer compiles, and
  mutating a returned list or struct no longer reaches the object it came
  from.

### Deliberately unchanged

- Widget content and configuration stay writable — `text-widget-text`,
  `progress-widget-value`, `input-widget-value`, `widget-style` and their
  kind. Assigning them is the interface.
- `point`, `size`, and `rectangle` accessors stay writable. They are value
  types an application builds and passes in; what changed is that readers
  handing back the toolkit's *own* instance of one now copy it.
- `notification-id` stays writable: `notification-center-push` assigns it
  after construction when the caller supplied none, so it is not
  construction-only state.

## [3.0.0]

Applies the read-only policy by its own rule rather than to a list of symbols
somebody wrote down. 1.0.0 converted eight accessors, 2.0.0 nine more, and
each time the set came from a review naming instances. A sweep of every
exported accessor in the tree found the same shape again in the widget
selection state and the backend's terminal-mode record.

### Changed

- Eighteen more accessors onto internal state are read-only. Widget selection
  state: `radio-widget-selected-index`, `select-widget-selected-index`,
  `menu-widget-selected-index`, `menu-widget-active-submenu`,
  `tabs-widget-selected-index`, `spinner-widget-index`,
  `list-widget-selected-key`, `list-widget-offset`,
  `tree-widget-selected-key`, `tree-widget-offset`. Input editing state:
  `input-widget-cursor`, `input-widget-selection-anchor`,
  `input-widget-scroll-offset`. Backend state: `backend-size`,
  `backend-cursor`, `backend-cursor-visible`, `backend-title`,
  `backend-alternate-screen-p`.

  Each has a mutator that does something a raw assignment does not: a bounds
  check, a paired update of a sibling slot, or — for the backend accessors —
  an escape sequence actually written to the terminal. Use `radio-widget-select`,
  `list-widget-select-key`, `backend-resize`, `backend-set-cursor`, and their
  siblings.

  `backend-size` and `backend-cursor` additionally return a copy, because
  `size` and `point` have exported mutable slots and a caller could otherwise
  reach the backend's own record through the value it handed back.

  **Breaking.** `setf` on those eighteen symbols no longer compiles.

### Deliberately unchanged

- Widget content and configuration stay writable: `text-widget-text`,
  `progress-widget-value`, `checkbox-widget-checked-p`, `input-widget-value`,
  `list-widget-model`, the `-options` and `-items` accessors, and their kind.
  Assigning them is how the toolkit is used; there is no invariant behind
  them for a raw write to break.
- `backend-capabilities` keeps its writer: nothing in the tree reassigns that
  slot, so there is no mutator whose guarantee a direct write would bypass.
- `select-widget-open-p` and `menu-widget-open-p` keep theirs for a different
  reason worth recording — `widget-handle-event` assigns them directly rather
  than going through `select-widget-toggle`, so the toolkit does not itself
  treat those functions as the sole way in. Converting the accessor would
  have frozen a rule the code does not follow.

## [2.0.0]

Completes the read-only conversion that 1.0.0 applied to only part of the
tree.

### Changed

- The ANSI backend's terminal-mode accessors — `ansi-backend-mouse-mode`,
  `ansi-backend-mouse-sgr-p`, `ansi-backend-bracketed-paste-enabled-p`,
  `ansi-backend-focus-reporting-enabled-p`,
  `ansi-backend-kitty-keyboard-flags`,
  `ansi-backend-synchronized-updates-enabled-p` — and the backend lifecycle
  accessors `backend-state` and `backend-last-error` are now read-only.
  Each records state the toolkit also acted on: a mode accessor is paired
  with an escape sequence already written to the terminal, and the lifecycle
  accessors are paired with what `backend-open`, `backend-close`, and
  `backend-fail` did. Writing one directly desynchronised the record from
  the action, so the next disable emitted the wrong sequence or none at all.
  Use the `ansi-enable-*` and `ansi-disable-*` pairs, and `backend-open` /
  `backend-close` / `backend-fail`.
- `backend-capability-states` is read-only and returns a fresh copy of the
  table. Handing back the live table let a caller write an unvalidated state
  straight past `backend-set-capability-state`, which is where a capability
  name and a state keyword are checked. Use that function instead.

  **Breaking.** `setf` on those nine symbols no longer compiles, and mutating
  the table `backend-capability-states` returns no longer reaches the
  backend. This is a
  major bump rather than a deprecation cycle because 1.0.0 was published
  minutes earlier, is not on Quicklisp, and has no known consumer — the
  deprecation window in the stability policy exists to give users time, and
  there are none to give it to. Freezing a known-desynchronisable accessor
  for a whole major version was the worse trade.

## [1.0.0]

First stable release.

### Added

- API stability policy distinguishing a SemVer-frozen stable tier
  (`cl-tui-kit/core`, `/layout`, `/widgets`, `/ansi`, `/testing`) from an
  experimental tier (`cl-tui-kit/tty`, `cl-tui-kit/codec`) that may change in
  a minor release.
- A per-symbol API reference under `docs/src/reference/api.md`.
- A non-Nix CI path alongside the existing `nix flake check` gate, wired
  with a coverage ratchet: the `coverage` job rejects an empty test
  selection and an empty instrumented source set, prints the measured
  expression and branch coverage, and enforces a floor set from that
  measurement. Until a floor was measured the job deliberately failed rather
  than defaulting to a permissive value, which would have looked like an
  active gate while enforcing nothing.

### Changed

- Errors previously signalled as `simple-error` with only a message string
  are now typed conditions rooted at `cl-tui-kit/core:cl-tui-kit-error`.
  Code using `(handler-case ... (error (c) ...))` is unaffected; code that
  branched on the error message text must be updated to condition types.
- Narrowed the supported-implementation statement to SBCL, verified on
  `x86_64-linux`.
- Eight exported accessors that expose a subsystem's internal state are now
  read-only: `surface-clip`, `ansi-backend-previous-surface`,
  `keymap-state-pending`, `keymap-state-pending-since`,
  `terminal-input-parser-buffer`, `terminal-input-parser-pending-octets`,
  `terminal-input-parser-in-paste-p`, and `terminal-input-parser-paste-buffer`
  no longer accept `setf`; each symbol still reads the same value it always
  did. Several of these readers additionally now return a defensive copy of
  the string, list, or rectangle they expose rather than the live internal
  object, so mutating the returned value no longer reaches the internal
  state it was read from — a second, related behavior change on top of
  losing `setf`. This is not universal across all eight: an accessor whose
  docstring documents that it hands back the subsystem's own live object for
  introspection still does so, and that object remains mutable in place
  (unsupported, but not prevented). Use `surface-set-clip`,
  `reset-keymap-state`, or `terminal-input-parser-reset` to change the state
  that backs them instead. This project has not had a prior release, so no
  shipped version is affected by either change.
- `invalid-type-error`, `invalid-range-error`, and `index-out-of-bounds-error`
  now honor a supplied `:detail` in their `:report`, matching
  `invalid-argument-error`, `invalid-option-error`, and
  `callback-contract-error`: when `:detail` is set, the report reads
  `"<detail> Got <datum>."`; otherwise it falls back to the condition's own
  generated sentence. See [Conditions](docs/src/reference/conditions.md).

### Distribution

- Distributed via GitHub and the Nix flake only. Not published to Quicklisp
  or Ultralisp; installation is manual ASDF source-registry registration, as
  documented in [README.md](README.md#install).

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/nerima-lisp/cl-tui-kit/compare/v4.1.0...HEAD
[4.1.0]: https://github.com/nerima-lisp/cl-tui-kit/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/nerima-lisp/cl-tui-kit/compare/v3.0.0...v4.0.0
[3.0.0]: https://github.com/nerima-lisp/cl-tui-kit/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/nerima-lisp/cl-tui-kit/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/nerima-lisp/cl-tui-kit/releases/tag/v1.0.0
