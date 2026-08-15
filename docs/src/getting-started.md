# Getting Started

## Prerequisites

cl-tui-kit is developed and verified against SBCL only; no other Common Lisp
implementation runs in this project's checks.

| Implementation | Systems covered | Verified construction |
| --- | --- | --- |
| SBCL | All systems in this repository | x86_64-linux, aarch64-darwin |

`src/` contains no `#+`/`#-` reader conditionals and no implementation-specific
code, so loading under another conforming Common Lisp implementation is
plausible, but that has not been verified and is not supported. The
repository also provides a Nix flake for reproducible development checks;
see [Development](project/development.md).

cl-tui-kit is distributed only as ASDF systems in this GitHub repository and
through the Nix flake; it is not published to Quicklisp or Ultralisp. A
fresh checkout is invisible to ASDF until its directory is registered, so
loading the umbrella system below fails with `Component "cl-tui-kit" not
found` until one of the following is done first.

Register the checkout with a source-registry config file (recommended; picked
up automatically):

    mkdir -p ~/.config/common-lisp/source-registry.conf.d
    echo '(:tree "/absolute/path/to/cl-tui-kit/")' \
      > ~/.config/common-lisp/source-registry.conf.d/cl-tui-kit.conf

or push it onto `asdf:*central-registry*` for the current session, before
loading:

    (push #P"/absolute/path/to/cl-tui-kit/" asdf:*central-registry*)

Either way, the checkout only needs to be registered once (or once per
session, for the `*central-registry*` form).

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
selecting its tests and rejects an empty selection or instrumented source set.
Its report covers executable project sources under `src/`; package and
umbrella declarations plus the static Unicode range table are excluded. See
[Development](project/development.md) for the complete workflow.
