# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project
adheres to [Semantic Versioning][semver]. The API stability policy that
SemVer applies to is defined in [CONTRIBUTING.md](CONTRIBUTING.md): the
`cl-tui-kit/core`, `/layout`, `/widgets`, `/ansi`, and `/testing` exports are
the stable tier; `cl-tui-kit/tty` and `cl-tui-kit/codec` are experimental and
may change in a minor release.

## [Unreleased]

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
  expression and branch coverage, and fails outright until a human replaces
  the threshold sentinel with a measured floor — a permissive default would
  look like an active gate while enforcing nothing.

### Changed

- Errors previously signalled as `simple-error` with only a message string
  are now typed conditions rooted at `cl-tui-kit/core:cl-tui-kit-error`.
  Code using `(handler-case ... (error (c) ...))` is unaffected; code that
  branched on the error message text must be updated to condition types.
- Narrowed the supported-implementation statement to SBCL, verified on
  `x86_64-linux` and `aarch64-darwin`.
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
[Unreleased]: https://github.com/nerima-lisp/cl-tui-kit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/nerima-lisp/cl-tui-kit/releases/tag/v1.0.0
