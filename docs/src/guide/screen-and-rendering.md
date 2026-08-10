# Screen and Rendering

## Surfaces are off-screen frames

A surface is a rectangular collection of cells. A cell contains character and
style information, and drawing is clipped to the surface bounds and the active
clip region. The surface can be inspected as structured data or rendered as a
string.

The basic operations are:

- create and clear a surface;
- read or write a cell;
- draw text, rectangles, borders, and child surfaces;
- inspect dirty regions;
- calculate a surface diff.

The surface is mutable while a frame is being built. The resulting cells and
diff are deterministic values that can be asserted in tests.

## Backend protocol

Backends receive a frame through a small protocol:

1. begin a frame;
2. present a surface or surface diff;
3. flush output;
4. optionally update cursor, alternate-screen, title, or size state.

The ANSI backend translates surface changes into output sequences. It does not
own input parsing. Capabilities let it degrade colors and other presentation
features when the target terminal cannot provide them.

## Deterministic testing

The testing backend keeps a structured last frame and supports event replay.
Applications can compare cells, text, styles, and frame transitions without
depending on a real terminal or the current terminal size.

This separation is useful for both unit tests and examples: the same widget can
be rendered into a test backend and into a terminal backend.
