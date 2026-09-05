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

## Install and supported implementations

See [Getting Started](docs/src/getting-started.md) for ASDF registration,
optional dependencies, supported implementations, and system selection.

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

See [Development](docs/src/project/development.md) for tests, coverage, Nix
checks, and structural source checks. The domain-neutral searchable-list
example is in [examples/searchable-list.lisp](examples/searchable-list.lisp).

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

See [Architecture](docs/src/reference/architecture.md) for ownership and
non-responsibilities, and the [Feature Matrix](docs/src/reference/api.md#feature-matrix)
for the implemented capability map.

## License

MIT.
