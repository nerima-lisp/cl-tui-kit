# Contributing to cl-tui-kit

cl-tui-kit is a generic, composable Common Lisp terminal UI toolkit. This
guide covers what a change needs before it can be shared.

## Before you start

Read [README.md](README.md), in particular the Systems, Development, and
Design boundaries sections, and [docs/src/project/development.md](docs/src/project/development.md)
and [docs/src/project/quality-gates.md](docs/src/project/quality-gates.md).
Those pages describe the repository layout, the test and coverage runners,
and the project contracts that documentation and code changes must preserve.

## API stability tiers

cl-tui-kit's exports are split into two tiers:

- **Stable tier** (SemVer-frozen): every export of `cl-tui-kit/core`,
  `cl-tui-kit/layout`, `cl-tui-kit/widgets`, `cl-tui-kit/ansi`, and
  `cl-tui-kit/testing`. A change that adds, removes, renames, or changes the
  calling convention of a stable-tier export requires a major version bump.
- **Experimental tier** (not frozen): `cl-tui-kit/tty` and `cl-tui-kit/codec`.
  These may change in a minor release.

Keep protocol boundaries and package exports explicit in `src/package.lisp`.
If a change touches a public system or protocol, update the relevant page
under `docs/src` and, for a stable-tier export, note the tier in
[CHANGELOG.md](CHANGELOG.md).

## Making a change

1. Add non-interactive coverage for any behavior change. Deterministic
   example tests belong beside the protocol they exercise; the test system
   also uses cl-weave property tests for algebraic contracts such as
   idempotent modifier normalization — keep property generators bounded.
2. Update the relevant page under `docs/src` when a public system or
   protocol changes, and keep the five navigation sections in
   `docs/mkdocs.yml` ordered as Home, Getting Started, Guide, Reference, and
   Project.
3. Preserve the project's boundaries: the core stays independent of
   terminal lifecycle and PTY management; integrations (`cl-tui-kit/tty`,
   `cl-tui-kit/codec`) stay optional ASDF systems; widgets return semantic
   actions instead of performing domain side effects; rendering and text
   layout stay cell-aware and deterministic; examples and tests stay usable
   without an interactive terminal.
4. For structural Common Lisp checks, use the pinned `paredit-cli` project.
   The Nix development shell exposes its executable as `paredit`; the
   reproducible form outside the shell is:

       nix run github:nerima-lisp/paredit-cli/v1.6.0 -- inspect check \
         --dialect common-lisp --file <path>

## Running the checks

When Nix is available, run the standard development checks from the
repository root:

    nix flake check
    nix fmt

`nix flake check` is the cross-platform behavior and documentation gate; it
also builds the MkDocs site in strict mode, so a broken navigation link or a
page missing from `docs/mkdocs.yml` fails the check.

Outside Nix, or to run the SBCL-specific paths directly:

    sbcl --script run-tests.lisp
    sbcl --script run-coverage.lisp

`run-tests.lisp` discovers adjacent ASDF definitions for the optional TTY
and codec integration systems and their dependency chain
(`cl-tty-kit`, `cl-codec-kit`, `cl-boundary-kit`, `cl-date-kit`,
`cl-concurrent-kit`), and resolves `cl-weave` from `CL_WEAVE_ASD` or a
neighboring source checkout. `run-coverage.lisp` enables SB-COVER and
force-compiles the project systems before selecting the test suite; it
rejects an empty test selection and an empty instrumented source set, so a
coverage run that silently selected nothing is treated as a failure rather
than a pass. Coverage is a separate acceptance condition from ordinary test
success — inspect the report rather than inferring completeness from a
successful exit.

CI runs the SB-COVER entry point in a Linux Nix development environment in
addition to `nix flake check`; see `.github/workflows/ci.yml` for the exact
jobs.

## Commit and PR expectations

A change is ready to share once:

- `nix flake check` passes (or, outside Nix, `run-tests.lisp` and, for a
  behavior change, `run-coverage.lisp` pass and the coverage report was
  inspected).
- `nix fmt` reports no diff.
- `paredit inspect check` reports no structural issues on any Common Lisp
  file touched.
- Any public system or protocol change has matching documentation under
  `docs/src` and, for a stable-tier export, a `CHANGELOG.md` entry.

Describe in the PR body which of these were run and how, since a green CI
run does not by itself show that a coverage run selected a non-empty test
set or that the MkDocs build actually included the changed page.
