# cl-tui-kit

cl-tui-kit is a generic, composable Common Lisp toolkit for terminal user
interfaces. It turns application state into cell-based off-screen surfaces and
lets an application choose how those surfaces are presented.

The pure path does not open a terminal or change terminal state. Terminal-size,
raw-mode, ANSI output, and UTF-8 octet handling are explicit adapter systems.

## Start here

| Reader goal | Page |
| --- | --- |
| Render a first surface | [Getting Started](getting-started.md) |
| Understand frames and backends | [Screen and Rendering](guide/screen-and-rendering.md) |
| Compose geometry and focus | [Layout and Focus](guide/layout.md) |
| Build or extend widgets | [Widgets and Models](guide/widgets.md) |
| Connect input and commands | [Events and Keymaps](guide/events.md) |
| Find exported protocols | [API Reference](reference/api.md) |
| Audit implemented capabilities | [Feature Matrix](reference/api.md#feature-matrix) |
| Understand the boundaries | [Architecture](reference/architecture.md) |

## Rendering flow

The toolkit keeps application policy outside the rendering pipeline:

    application state
            |
            v
    normalized events and semantic actions
            |
            v
    layout, focus, and widgets
            |
            v
    off-screen cell surface
            |
            v
    backend

Widgets may return semantic actions such as activate, submit, move, or close.
The application decides which side effects, if any, those actions cause.

## Scope

The toolkit provides cell geometry, text measurement, styles and themes,
surfaces, layout allocation, focus trees, normalized events, keymaps, lazy
models, widgets, backend protocols, and deterministic test helpers.

It intentionally does not provide a terminal emulator, terminal multiplexer,
PTY runtime, shell, process supervisor, scrollback store, or interpretation of
arbitrary application output as a terminal screen.
