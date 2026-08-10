# API Reference

The exported symbols are grouped by stable responsibility. Applications
should depend on the smallest system that provides the protocol they need;
the umbrella system is convenient for small applications and examples.

## cl-tui-kit/core

The core has no terminal I/O and is the foundation for every other pure
system.

- Geometry: point, size, rectangle, padding, margin, constraints,
  clipping-region, and viewport.
- Text: cell-width, text-units, string-cell-width, clip-text, truncate-text,
  ambiguous-width policy, and with-ambiguous-width.
- Cells and surfaces: cell, surface, make-surface, surface-cell,
  surface-put-cell, surface-clear, surface-fill-rectangle,
  surface-draw-text, surface-draw-border, surface-blit, surface-diff,
  surface-string, surface-dirty-regions, call-with-surface-clip, and
  with-surface-clip.
- Style: color, style, theme, default-theme, merge-styles, and theme-style.
- Events: key, text-input, paste, resize, mouse, focus, tick, and custom
  event constructors, clipboard requests and responses; incremental terminal
  input parsing and event sources.
- Actions and keymaps: action constructors, keymap construction and
  dispatch, parent propagation, overlays, modes, and vi-like composition.
- Backend: frame lifecycle, surface presentation, flushing, cursor,
  alternate screen, title, size, capabilities, clipboard, and output-mode
  lifecycle.
- CPS: dispatch-event/k, present-frame/k, and call-with-surface-clip.

## cl-tui-kit/layout

Layout nodes include make-vbox, make-hbox, make-stack, make-overlay,
make-split, make-grid, make-padding-layout, make-border-layout,
make-center-layout, make-viewport-layout, and make-scroll-container.

Focus is a separate protocol with focus nodes and trees, next and previous
traversal, directional movement, modal push and pop, restoration, and
visibility checks.

## cl-tui-kit/widgets

The widget protocol is render-widget and handle-widget-event. Built-in
constructors cover text, box, divider, list, lazy list, tree, text view, tabs,
menu, table, input, textarea, button, checkbox, radio, select, spinner,
progress, form, viewport, modal, notification center, status bar, and scroll
bar widgets. Application lifecycle is exposed through
application-start, application-step/k, application-step, application-close,
application-render/k, and call-with-application-session or
with-application-session.

List and tree models expose callback-based counts, lookup, stable keys,
labels, rendering, children, and expansion state. Accessibility information,
widget state, and cursor position are available through the widget protocols.

## cl-tui-kit/ansi and cl-tui-kit/testing

The ANSI system provides make-ansi-backend for output, explicit terminal-mode
controls, and OSC 52 clipboard requests. The testing system
provides make-test-backend, test-backend-last-frame, test-backend-emit,
surface-equal-p, assert-surface-text, and make-event-replay.

## Optional integrations

cl-tui-kit/tty uses terminal-size and raw-mode operations from its TTY
dependency and supplies synchronous runtime input. Its
call-with-tty-runtime and with-tty-runtime scopes start and stop the runtime
around a continuation or body. cl-tui-kit/codec uses an external UTF-8 codec
for string-to-octet conversion.

Loading core, layout, widgets, ANSI, or testing does not require an
interactive terminal. The optional integrations are separate ASDF systems.

## Feature Matrix

This matrix is the acceptance map for the public toolkit. “Implemented” means
the behavior is represented by a public protocol or integration and is covered by
non-interactive tests where the behavior is deterministic. Optional integration
rows remain explicit so loading the pure core never changes terminal state.

| Area | Implemented coverage | Main public surface |
| --- | --- | --- |
| Rendering | Cell surfaces, dirty regions, clipping, blitting, wide-cell repair, frame diffs, cursor state, and deterministic frame strings | `surface-*`, `backend-present`, `surface-diff` |
| Text | Unicode cell widths, ambiguous-width policy, truncation, styled spans, borders, and UTF-8 codec integration | `cell-width`, `with-ambiguous-width`, `clip-text`, `cl-tui-kit/codec` |
| Style | Named, indexed, RGB, and default colors; text attributes; themes; capability-aware ANSI degradation | `style`, `theme`, `ansi-encode-style` |
| Layout | VBox, HBox, stack, overlay, split, grid, padding, border, center, viewport, and scroll layouts with constraints, flex, gaps, margins, and clipping | `make-vbox`, `make-grid`, layout protocols |
| Focus | Focus trees, traversal, directional movement, visibility, modal push/pop, and restoration | `make-focus-tree`, focus protocols |
| Input normalization | Incremental UTF-8 parsing; CSI keys; Kitty keyboard press/repeat/release; modifyOtherKeys; SGR and X10 mouse; focus; bracketed paste; bounded overflow; unknown/custom events | `make-terminal-input-parser`, normalized event constructors |
| Clipboard | OSC 52 query output, BEL/ST response parsing, split input, strict RFC 4648 Base64 validation, UTF-8 decoding, and normalized clipboard events | `backend-request-clipboard`, `ansi-request-clipboard`, `clipboard-event` |
| Keymaps and actions | Modifiers, multi-key sequences, prefixes, parent propagation, modes, overlays, semantic action constructors, and iterative dispatch | `make-keymap`, `dispatch-keymaps`, action constructors |
| Backend protocol | Open/close lifecycle, size and resize, frame begin/present/flush, cursor, title, alternate screen, capability states, clipboard, and recoverable failure state | `backend-*`, `make-backend-capabilities` |
| ANSI integration | Diff-based ANSI output, color degradation, cursor/title/alternate-screen control, mouse modes, bracketed paste, focus reporting, Kitty keyboard, synchronized updates, clipboard query, and cleanup | `cl-tui-kit/ansi` |
| TTY integration | Terminal-size discovery, optional raw mode, synchronous blocking `next-event`, non-blocking `poll`, EOF/error state, and guaranteed stop/close cleanup | `cl-tui-kit/tty` |
| Application runtime | Event routing, propagation, event-source integration, timers, stop/failure state, frame lifecycle, and scoped application sessions | `application-step/k`, `application-step`, `application-start`, `with-application-session` |
| Widgets | Text, box, divider, button, checkbox, progress, input, textarea, radio, select, spinner, list, tree, text view, tabs, menu, table, form, viewport, modal, notifications, status bar, and scroll bar | `cl-tui-kit/widgets` |
| Models and accessibility | Lazy list/tree callbacks, stable selection keys, visible-range rendering, focusability, enabled state, semantic roles, help text, and cursor position | widget/model protocols |
| Testing and replay | Fake backend, frame assertions, event replay, property checks, structural Lisp checks, and coverage entry point | `cl-tui-kit/testing`, `run-tests.lisp` |
| Dependency boundary | Pure core systems are independent of terminal I/O; optional ANSI, TTY, and codec systems are loaded explicitly; no external utility-layer dependency remains | ASDF systems, `cl-host-kit` integration |

### Deliberate boundaries

The toolkit is a TUI rendering and interaction library, not a terminal
emulator or a terminal multiplexer. It does not provide a PTY runtime,
process supervisor, shell, scrollback database, or interpretation of
arbitrary application output as a terminal screen. Applications own those
policies and side effects, and can feed their own event sources into the
application runtime.

## Authoritative exports

The package declarations in src/package.lisp are the authoritative package
boundary. Implementation helpers remain unexported. This page groups the
public protocols by responsibility; consult the package declarations when an
exact symbol or package export is required.
