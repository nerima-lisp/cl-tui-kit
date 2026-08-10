# Architecture

## Boundary

The main data flow is:

    application state
      -> normalized event handling and semantic actions
      -> layout, focus, and widgets
      -> off-screen surface
      -> backend

The application owns domain state and side effects. The toolkit owns
deterministic geometry, layout, rendering protocols, input normalization, and
frame presentation.

## Data and control

Widget state, normalized events, actions, and surfaces form the data path.
Lifecycle operations form a separate control path: CPS functions own the
start/restore/stop boundary, and the corresponding `defmacro` helpers only
bind expressions once before delegating to those functions. This keeps cleanup
visible without hiding an event loop or introducing a second runtime model.

## System direction

The dependency direction is intentionally one-way:

    core
      -> layout
      -> widgets
      -> testing

ANSI output depends on core. TTY and codec integrations are optional adapter
systems. The pure path does not import terminal lifecycle, OS process
management, PTY handling, or a hidden concurrency runtime.

## Geometry and surfaces

Geometry uses terminal-cell units. Layout allocates rectangles using
minimum, preferred, and flexible constraints. Surfaces store cells and expose
draw, clipping, dirty-region, and diff operations.

This makes frame construction inspectable before any terminal output occurs.
The test backend uses the same surface and backend protocols as a real output
backend.

## Text and style

Text measurement is centralized in the text-unit layer. Clipping,
truncation, wide-cell continuation, and ambiguous-width policy therefore
remain consistent across widgets and backends.

Styles and themes express presentation intent. Widgets use semantic theme
roles instead of embedding ANSI escape sequences or terminal color numbers.
The backend translates those styles according to capabilities.

## Events and focus

The core parser turns incremental input into normalized events. Keymaps turn
keys and modifiers into application-level bindings, while widgets return
semantic actions. Focus is a tree with scopes and modal restoration; it is
separate from list selection.

The CPS helpers expose continuation boundaries without introducing a hidden
event loop, thread, or sleep.

## Lazy data and composition

List and tree widgets query callback-based models for the visible range.
Composite widgets can interpret child actions through the generic ancestor
hook. Accessibility information and cursor position are exposed without
coupling the core to a particular screen reader.

## Non-responsibilities

The toolkit is not a terminal emulator, terminal multiplexer, PTY runtime,
shell, process supervisor, scrollback store, or arbitrary-output screen
interpreter. A future terminal-emulation layer would be a separate boundary.
