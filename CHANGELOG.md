# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project
adheres to [Semantic Versioning][semver]. The API stability policy that
SemVer applies to is defined in [CONTRIBUTING.md](CONTRIBUTING.md): the
`cl-tui-kit/core`, `/layout`, `/widgets`, `/ansi`, and `/testing` exports are
the stable tier; `cl-tui-kit/tty` and `cl-tui-kit/codec` are experimental and
may change in a minor release.

## [Unreleased]

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
[Unreleased]: https://github.com/nerima-lisp/cl-tui-kit/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/nerima-lisp/cl-tui-kit/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/nerima-lisp/cl-tui-kit/releases/tag/v1.0.0
