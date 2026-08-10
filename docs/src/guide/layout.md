# Layout and Focus

## Geometry

Geometry is expressed in terminal-cell units:

- point;
- size;
- rectangle;
- padding and margin;
- minimum, preferred, and flexible constraints;
- clipping region and viewport.

Invalid or negative dimensions are normalized at the geometry boundary. Layout
allocation is deterministic, including when the available region is smaller
than the requested minimum.

## Layout nodes

The layout system provides composable vertical, horizontal, stack, overlay,
split, padding, border, center, viewport, and scroll-container primitives.
Layout nodes allocate rectangles; they do not inspect domain data or perform
application side effects.

Widgets are kept separate from allocation. A widget receives its allocated
rectangle and renders into the supplied surface or child layout.

## Focus

Focus is a tree rather than a property of list selection. The focus protocol
supports next and previous traversal, directional movement, scopes, modal
focus traps, and restoration after a modal closes.

Keeping focus and selection separate lets a list remain selected while a
different control receives keyboard input.
