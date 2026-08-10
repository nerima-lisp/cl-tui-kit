# Getting Started

## Prerequisites

The library is distributed as ASDF systems. A Common Lisp implementation with
ASDF is enough for the pure systems. The repository also provides a Nix flake
for reproducible development checks.

## Render a surface

The umbrella system is convenient for small applications:

    (asdf:load-system "cl-tui-kit")

    (let ((surface (cl-tui-kit/core:make-surface 24 4)))
      (cl-tui-kit/core:surface-draw-text surface 1 1 "hello 日本")
      (cl-tui-kit/core:surface-string surface))

For a smaller dependency boundary, load cl-tui-kit/core directly. It owns
geometry, cell and surface operations, text width, styles, normalized events,
keymaps, and the backend protocol.

## Check a frame without a terminal

The testing system records structured frames:

    (asdf:load-system "cl-tui-kit/testing")

    (let* ((backend (cl-tui-kit/testing:make-test-backend
                     :size (cl-tui-kit/core:make-size 24 4)))
           (surface (cl-tui-kit/core:make-surface 24 4)))
      (cl-tui-kit/core:surface-draw-text surface 0 0 "deterministic")
      (cl-tui-kit/core:backend-present backend surface)
      (cl-tui-kit/testing:test-backend-last-frame backend))

This keeps frame assertions independent of terminal dimensions and escape
sequence output. See [Screen and Rendering](guide/screen-and-rendering.md) for
the backend protocol.

## Choose the systems you need

| System | Use it when |
| --- | --- |
| cl-tui-kit/core | You need the terminal-independent foundation |
| cl-tui-kit/layout | You need composable allocation or focus |
| cl-tui-kit/widgets | You need standard widget protocols and models |
| cl-tui-kit/ansi | You need ANSI output for a backend |
| cl-tui-kit/testing | You need structured frame assertions or event replay |
| cl-tui-kit/tty | You need synchronous stream input and raw-mode lifetime |
| cl-tui-kit/codec | You need UTF-8 octet conversion |
| cl-tui-kit/examples | You want to load the searchable-list example |

The tty and codec systems are optional. They do not become dependencies of the
pure core path.

## Run the local checks

From the repository root:

    sbcl --script run-tests.lisp
    sbcl --script run-coverage.lisp

The runners first resolve cl-host-kit and then discover adjacent ASDF
definitions for the TTY dependency chain: cl-codec-kit, cl-boundary-kit,
cl-date-kit, cl-concurrent-kit, and cl-tty-kit. They find cl-weave through
`CL_WEAVE_ASD` or a neighboring checkout. The coverage runner force-compiles
the project systems, including the optional TTY and codec systems, before
selecting its tests and rejects an empty selection. See
[Development](project/development.md) for the complete workflow.
