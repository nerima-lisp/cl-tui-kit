# Development

## Repository layout

- src/package.lisp defines the public package boundaries.
- src/ contains the serial ASDF components for the core, layout, widgets,
  integrations, and testing backend. Application event dispatch and runtime
  lifecycle live in separate source components.
- t/ contains the cl-weave test system.
- examples/ contains domain-neutral examples.
- docs/src/ contains the canonical documentation source.
- docs/mkdocs.yml defines the documentation site.

## Run tests

From the repository root:

    sbcl --script run-tests.lisp

The runner loads the local ASDF definition and resolves cl-host-kit before
using its environment and pathname operations. It resolves cl-weave from
CL_WEAVE_ASD or a neighboring source checkout. CL_WEAVE_ASD is resolved from
the current directory, so a relative value works when the command is run from
the repository root. It then invokes the cl-tui-kit test system. Project
tooling uses cl-host-kit directly for portability.

## Run coverage

Use the separate coverage entry point:

    sbcl --script run-coverage.lisp

The coverage runner enables SB-COVER before force-compiling the project
systems. A report directory can be selected with
CL_TUI_KIT_COVERAGE_REPORT_DIRECTORY. Coverage is a separate acceptance
condition from ordinary test success.

The test system also uses cl-weave property tests for algebraic contracts such
as idempotent modifier normalization. Keep property generators bounded and
keep deterministic example tests beside the protocol they exercise.

## Nix checks

The flake provides the development environment and package checks:

    nix flake check
    nix fmt

The Nix shell also registers the external systems used by the optional tty and
codec systems. Verify those ASDF edges in that environment with:

    nix develop --command sbcl --non-interactive \
      --eval '(require :asdf)' \
      --load cl-tui-kit.asd \
      --eval '(asdf:load-system "cl-tui-kit/tty" :force t)' \
      --eval '(asdf:load-system "cl-tui-kit/codec" :force t)'

Outside the Nix shell, configure ASDF's source registry for cl-tty-kit and
cl-codec-kit before loading those optional systems.

For structural Common Lisp checks, use the pinned development tool. The Nix
development shell exposes its executable as `paredit`; the explicit `nix run`
form below is reproducible outside the shell as well:

    nix run github:nerima-lisp/paredit-cli/v1.6.0 -- inspect check \
      --dialect common-lisp --file src/application.lisp

The documentation root is declared in the flake so the same project metadata
can build the MkDocs site along with the Lisp package.

## Documentation changes

Update the canonical page under docs/src and keep the five navigation
sections in docs/mkdocs.yml ordered as Home, Getting Started, Guide,
Reference, and Project.
