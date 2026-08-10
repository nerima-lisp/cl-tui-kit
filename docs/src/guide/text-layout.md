# Text Layout

## Cell width

Terminal layout is measured in cells rather than Lisp characters. The text
layer provides:

- per-unit width calculation;
- total string-cell width;
- clipping and truncation;
- configurable ambiguous-width policy;
- conversion of wide units into a lead cell and continuation cell.

ASCII and East Asian wide characters, combining marks, representative emoji,
tabs, newlines, and mixed-width text are handled by the cell-aware scanner.
The default ambiguous-width policy is narrow; with-ambiguous-width can select
wide behavior for a particular rendering operation.

## Clipping and continuation cells

Clipping and truncation operate on complete text units. A wide unit is not
split into an orphaned half-cell. The continuation cell is not printed
independently by surface-string or the ANSI diff renderer.

## Deliberate limitation

This is a portable approximation of terminal width rules, not a complete
implementation of every grapheme boundary or terminal shaping behavior.
Complex scripts, ZWJ sequences, flags, and application-specific shaping may
need a higher-level text provider.

The input widget keeps its cursor as a code-point index in the original Lisp
string. Applications that edit complex grapheme clusters should provide a
grapheme-aware editing layer.

Tests should assert cell widths and rendered cells rather than assuming one
Lisp character equals one terminal cell. The core suite covers mixed-width
text, combining marks, wide-unit clipping, tabs, and ellipsis.
