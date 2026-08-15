# cl-tui-kit

A generic, composable Common Lisp terminal UI toolkit.

cl-tui-kit renders application state into cell-based off-screen surfaces. The
core keeps geometry, layout, widgets, normalized events, and backend protocols
separate from terminal lifecycle and application side effects. Resource
lifetimes are available both as CPS functions and as thin `defmacro` scopes,
so applications can choose explicit continuations or readable local bodies.

## Quick start

Load the umbrella system and render a surface without opening a terminal:

    (asdf:load-system "cl-tui-kit")

    (let ((surface (cl-tui-kit/core:make-surface 24 4)))
      (cl-tui-kit/core:surface-draw-text surface 1 1 "hello 日本")
      (cl-tui-kit/core:surface-string surface))

For deterministic frame checks, use the testing backend:

    (asdf:load-system "cl-tui-kit/testing")

    (let* ((backend (cl-tui-kit/testing:make-test-backend
                     :size (cl-tui-kit/core:make-size 24 4)))
           (surface (cl-tui-kit/core:make-surface 24 4)))
      (cl-tui-kit/core:surface-draw-text surface 0 0 "deterministic")
      (cl-tui-kit/core:backend-present backend surface)
      (cl-tui-kit/testing:test-backend-last-frame backend))

## Supported implementations

cl-tui-kit is developed and verified against SBCL only; no other Common
Lisp implementation runs in this project's checks.

| Implementation | Systems covered | Verified construction |
| --- | --- | --- |
| SBCL | All systems in this repository | x86_64-linux, aarch64-darwin |

`src/` contains no `#+`/`#-` reader conditionals and no
implementation-specific code, so loading under another conforming Common
Lisp implementation is plausible, but that has not been verified and is not
supported.

## Install

cl-tui-kit is distributed as ASDF systems in this repository; it is not yet
published to Quicklisp or Ultralisp. A fresh checkout is invisible to ASDF
until its directory is registered, so `(asdf:load-system "cl-tui-kit")` fails
with `Component "cl-tui-kit" not found` unless one of the following is done
first.

The pure umbrella system — `cl-tui-kit/core`, `/layout`, `/widgets`, `/ansi`,
and `/testing` — has no dependency outside this repository and Quicklisp.
Only the optional `cl-tui-kit/tty`, `cl-tui-kit/codec`, and `cl-tui-kit/tests`
systems require sibling nerima-lisp checkouts: `cl-tui-kit/tty` needs
`cl-tty-kit`; `cl-tui-kit/codec` needs `cl-codec-kit`; and `cl-tui-kit/tests`
loads both optional systems and needs `cl-host-kit` and `cl-weave`. The TTY
dependency chain also uses `cl-boundary-kit`, `cl-date-kit`, and
`cl-concurrent-kit`. Skip those siblings entirely if only the pure umbrella
system is being loaded.

Register the checkout with ASDF using either of the following methods, then
load the umbrella system as usual.

**Source-registry config file** (recommended; picked up automatically):

    mkdir -p ~/.config/common-lisp/source-registry.conf.d
    echo '(:tree "/absolute/path/to/cl-tui-kit/")' \
      > ~/.config/common-lisp/source-registry.conf.d/cl-tui-kit.conf

**`*central-registry*`** (per-session, before loading):

    (push #P"/absolute/path/to/cl-tui-kit/" asdf:*central-registry*)

Either way, the checkout only needs to be registered once (or once per
session, for the `*central-registry*` form); after that:

    (asdf:load-system "cl-tui-kit")

Use `cl-tui-kit/core` when an application needs only the dependency-free core;
load the optional integration systems explicitly when terminal or codec support
is required. If `cl-tui-kit/tty`, `cl-tui-kit/codec`, or `cl-tui-kit/tests` is
loaded, also register the corresponding sibling nerima-lisp repositories
listed above using the same method. The checked-in test and coverage runners
can discover adjacent ASDF definitions for this dependency chain; set
`CL_WEAVE_ASD` when cl-weave is stored elsewhere.

## Documentation

The documentation source is organized as a five-part guide:

- [Home](docs/src/index.md)
- [Getting Started](docs/src/getting-started.md)
- [Guide](docs/src/guide/screen-and-rendering.md)
- [Reference](docs/src/reference/api.md)
- [Project](docs/src/project/development.md)

The canonical documentation source is under [`docs/src`](docs/src), with
navigation defined in [`docs/mkdocs.yml`](docs/mkdocs.yml).

## Systems

| System | Responsibility |
| --- | --- |
| cl-tui-kit/core | Cell geometry, surfaces, text width, styles, events, keymaps, and backend protocol |
| cl-tui-kit/layout | Composable layout allocation and focus trees |
| cl-tui-kit/widgets | Domain-neutral widget and application protocols |
| cl-tui-kit/ansi | Optional ANSI output backend, terminal modes, and OSC 52 clipboard queries |
| cl-tui-kit/testing | Structured fake backend, frame assertions, and event replay |
| cl-tui-kit/tty | Optional synchronous TTY and raw-mode integration |
| cl-tui-kit/codec | Optional UTF-8 octet codec integration |
| cl-tui-kit/examples | Domain-neutral examples |
| cl-tui-kit/tests | Non-interactive test suite |
| cl-tui-kit | Umbrella system for the pure toolkit path |

The core systems do not depend on a terminal emulator, PTY, process manager,
shell, or background thread. Loading the pure systems does not change terminal
state. The tty and codec integrations are separate systems that applications
can load explicitly.

The widgets application layer is split into event dispatch and runtime
lifecycle modules. The resulting data path is easy to test without opening a
terminal, while `application-render/k`, `application-step/k`,
`call-with-application-session`, `with-application-session`,
`call-with-surface-clip`, and the optional TTY integration keep cleanup
explicit.

Indexed option controls share their movement invariant through the
`define-indexed-control-movement` macro. Radio and select widgets therefore
share bounded-selection logic while retaining independent rendering and event
policies. This is the preferred pattern for new controls: keep immutable or
callback-backed data separate from state transitions, expose an explicit CPS
entry point when cleanup or delegation matters, and provide a macro only for a
readable lexical scope or a repeated protocol invariant.

## Development

Run the test suite from the repository root:

    sbcl --script run-tests.lisp

The test and coverage entry points include the optional TTY and codec
integration systems. They discover adjacent dependency ASDF definitions when
needed and accept `CL_WEAVE_ASD` for a non-adjacent cl-weave checkout. The
coverage entry point recompiles the project with SB-COVER before selecting
tests:

    sbcl --script run-coverage.lisp

When Nix is available, the repository also exposes the standard development
checks:

    nix flake check
    nix fmt

The domain-neutral searchable-list example is in
[examples/searchable-list.lisp](examples/searchable-list.lisp).

## Contributing

Keep protocol boundaries and package exports explicit, add non-interactive
coverage for behavior changes, and update the relevant page under `docs/src`
when a public system or protocol changes. The pinned `paredit-cli` project
provides the `paredit` executable in the Nix development shell; use the
reproducible `nix run` form documented below for structural Common Lisp
inspection, then run the checks above before sharing a change.

## Support

Start with [Getting Started](docs/src/getting-started.md), the
[API Reference](docs/src/reference/api.md), and the examples. A useful bug
report includes the Common Lisp implementation, the system loaded, the
smallest reproducing frame or event sequence, and the command that was run.

## Design boundaries

Applications own domain state, I/O side effects, process management, and
application policy. Widgets render state and return semantic actions; the
application decides whether an action changes a file, starts a process, or
connects to a service.

The toolkit is not a terminal multiplexer, terminal emulator, PTY runtime, or
scrollback store. It does not interpret arbitrary application output as a
terminal screen. The complete implemented capability map is in the
[Feature Matrix](docs/src/reference/api.md#feature-matrix).

## License

MIT.
