# API Reference

The exported symbols are grouped by stable responsibility. Applications
should depend on the smallest system that provides the protocol they need;
the umbrella system is convenient for small applications and examples.

`cl-tui-kit/core`, `cl-tui-kit/layout`, `cl-tui-kit/widgets`,
`cl-tui-kit/ansi`, and `cl-tui-kit/testing` are the SemVer-stable tier.
`cl-tui-kit/tty` and `cl-tui-kit/codec` are the **experimental** tier: their
exports can change in a minor or patch release. See
[API Stability](../project/api-stability.md) for the full policy.

Every signature below was read from its defining source file; every
condition type named is one a call site in that function actually signals,
not an inference from its name. `src/package.lisp` remains the single
authoritative list of what each system exports — consult it when this page
and the source disagree.

## Feature Matrix

This matrix is the acceptance map for the public toolkit. "Implemented" means
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
| Event loop | Deterministic, threadless scheduling: injected clock, FIFO event queue, one-shot and repeating timers, cancellation, and a caller-supplied error handler | `make-event-loop`, [Event Loop](event-loop.md) |
| Clipboard | OSC 52 query output, BEL/ST response parsing, split input, strict RFC 4648 Base64 validation, UTF-8 decoding, and normalized clipboard events | `backend-request-clipboard`, `ansi-request-clipboard`, `clipboard-event` |
| Keymaps and actions | Modifiers, multi-key sequences, prefixes, parent propagation, modes, overlays, semantic action constructors, and iterative dispatch | `make-keymap`, `dispatch-keymaps`, action constructors |
| Backend protocol | Open/close lifecycle, size and resize, frame begin/present/flush, cursor, title, alternate screen, capability states, clipboard, and recoverable failure state | `backend-*`, `make-backend-capabilities` |
| ANSI integration | Diff-based ANSI output, color degradation, cursor/title/alternate-screen control, mouse modes, bracketed paste, focus reporting, Kitty keyboard, synchronized updates, clipboard query, and cleanup | `cl-tui-kit/ansi` |
| TTY integration (experimental) | Terminal-size discovery, optional raw mode, synchronous blocking `next-event`, non-blocking `poll`, EOF/error state, and guaranteed stop/close cleanup | `cl-tui-kit/tty` |
| Application runtime | Event routing, propagation, event-source integration, timers, stop/failure state, frame lifecycle, and scoped application sessions | `application-step/k`, `application-step`, `application-start`, `with-application-session` |
| Widgets | Text, box, divider, button, checkbox, progress, input, textarea, radio, select, spinner, lazy list, lazy tree, text view, tabs, menu, table, form, viewport, modal, notifications, status bar, and scroll bar | `cl-tui-kit/widgets` |
| Models and accessibility | Lazy list/tree callbacks, stable selection keys, visible-range rendering, focusability, enabled state, semantic roles, help text, and cursor position | widget/model protocols |
| Conditions | A typed condition hierarchy rooted at `cl-tui-kit-error`, replacing untyped `simple-error` signalling | `cl-tui-kit-error`, [Conditions](conditions.md) |
| Testing and replay | Fake backend, frame assertions, event replay, property checks, structural Lisp checks, and coverage entry point | `cl-tui-kit/testing`, `run-tests.lisp` |
| Dependency boundary | Pure core systems are independent of terminal I/O; optional ANSI, TTY, and codec systems are loaded explicitly; no external utility-layer dependency remains | ASDF systems, `cl-host-kit` integration |

### Deliberate boundaries

The toolkit is a TUI rendering and interaction library, not a terminal
emulator or a terminal multiplexer. It does not provide a PTY runtime,
process supervisor, shell, scrollback database, or interpretation of
arbitrary application output as a terminal screen. Applications own those
policies and side effects, and can feed their own event sources into the
application runtime.

## Umbrella package re-exports

`src/umbrella.lisp` builds the `cl-tui-kit` package's public surface at
**load time**, not through `defpackage`:

```lisp
(dolist (package-name '(#:cl-tui-kit/core #:cl-tui-kit/layout
                        #:cl-tui-kit/widgets #:cl-tui-kit/ansi
                        #:cl-tui-kit/testing))
  (let ((package (find-package package-name)))
    (when package
      (do-external-symbols (symbol package)
        (export symbol (find-package '#:cl-tui-kit))))))
```

For each of the five stable-tier systems, every external symbol of that
package is exported from `cl-tui-kit` as a side effect of loading
`umbrella.lisp` — not because `cl-tui-kit`'s own `defpackage` form lists
them. Reading `(defpackage #:cl-tui-kit ...)` in `src/package.lisp` shows
only a `:use` clause and no `:export` list at all; the re-exported symbols
are invisible to a reader working from `defpackage` forms alone; loading the
system is what makes `cl-tui-kit:point`, `cl-tui-kit:make-vbox`, and every
other stable-tier export resolvable in the `cl-tui-kit` package.

`cl-tui-kit/tty` and `cl-tui-kit/codec` are **deliberately excluded** from
this loop. Depending on `cl-tui-kit` alone never pulls in the experimental
tier or its terminal-lifecycle side effects; an application that wants
`cl-tui-kit/tty` must depend on it explicitly. Per
[API Stability](../project/api-stability.md), `cl-tui-kit` itself carries no
separate stability contract — it aggregates the stable tier and exports
nothing of its own.

## cl-tui-kit/core

The core has no terminal I/O and is the foundation for every other pure
system.

### Geometry

All geometry types are immutable value structs (no `:copier`, so use the
paired `copy-*` function, not `copy-structure`). Coordinates are integers
and may be negative when a child is translated; extents (width, height, and
the padding/margin components) are normalized to non-negative integers by
construction. Constructors that receive a non-integer coordinate or a
negative extent signal `invalid-type-error`.

- **`point`** — `point-x`, `point-y`. `(make-point &optional (x 0) (y 0))`,
  `(copy-point point)`.
- **`size`** — `size-width`, `size-height` (both `(integer 0)`).
  `(make-size &optional (width 0) (height 0))`, `(copy-size size)`.
- **`rectangle`** — `rectangle-x`, `rectangle-y`, `rectangle-width`,
  `rectangle-height`. `(make-rectangle &optional (x 0) (y 0) (width 0)
  (height 0))`, `(copy-rectangle rectangle)`.
  - `(rectangle-empty-p rectangle)` — true when width or height is zero.
  - `(rectangle-right rectangle)`, `(rectangle-bottom rectangle)` — `x +
    width` and `y + height`.
  - `(rectangle-contains-point-p rectangle point-or-x &optional y)` — accepts
    either a `point` or two coordinates.
  - `(rectangle-contains-rectangle-p outer inner)`.
  - `(rectangle-intersection left right)`, `(rectangle-union left right)` —
    both return a new `rectangle`; an empty operand degenerates cleanly (a
    union with an empty rectangle returns a copy of the other).
  - `(rectangle-inset rectangle padding)` — shrinks by `padding`, clamped at
    zero.
  - `(rectangle-offset rectangle dx dy)` — translates by integer deltas.
    Signals `invalid-type-error` if `dx`/`dy` is not an integer.
- **`padding`** and **`margin`** — structurally identical: `-top`, `-right`,
  `-bottom`, `-left` (all `(integer 0)`). `(make-padding &key (top 0) (right
  top) (bottom top) (left right) all)` (and the equivalent `make-margin`) —
  `all`, when supplied, overrides all four sides; otherwise `right` defaults
  to `top`, `bottom` to `top`, and `left` to `right`, so `(make-padding :top
  1)` pads all sides with 1. `copy-padding`/`copy-margin` mirror the
  constructors.
- **`constraints`** — `constraints-min-width`, `-preferred-width`,
  `-max-width`, `-min-height`, `-preferred-height`, `-max-height`,
  `-flex-width`, `-flex-height`. `(make-constraints &key (min-width 0)
  preferred-width max-width (min-height 0) preferred-height max-height
  (flex-width 0) (flex-height 0))`. `flex-width`/`flex-height` must be
  non-negative reals (signals `invalid-range-error` otherwise), and a
  supplied `max-width`/`max-height` must not be smaller than the
  corresponding minimum (signals `invalid-range-error` naming the offending
  bound). `(copy-constraints constraints)`.
  - `(resolve-axis available constraints axis)` — resolves one axis (`axis`
    is `:width` or `:height`) deterministically against `available` space:
    honors a preferred size when possible, then clamps to `[0, available]`
    respecting minimum and maximum. Used by layout containers, not typically
    called directly by applications.
- **`clipping-region`** — `clipping-region-rectangle`. `(make-clipping-region
  &optional (rectangle (make-rectangle)))`. A thin wrapper accepted anywhere
  a clip is set (see `surface-set-clip` below) alongside a bare `rectangle`.
- **`viewport`** — `viewport-bounds` (a `rectangle`), `viewport-content-width`,
  `viewport-content-height`, `viewport-offset-x`, `viewport-offset-y`.
  `(make-viewport &key (bounds (make-rectangle)) (content-width 0)
  (content-height 0) (offset-x 0) (offset-y 0))` — the initial offset is
  clamped through `viewport-scroll-to`, so an out-of-range starting offset is
  silently corrected rather than rejected.
  - `(viewport-scroll-x-max viewport)`, `(viewport-scroll-y-max viewport)` —
    the maximum scroll offset on each axis, `max(0, content - bounds)`.
  - `(viewport-scroll-to viewport x y)` — sets the offset, clamped to `[0,
    scroll-max]` on each axis. Returns `viewport`.
  - `(viewport-scroll-by viewport dx dy)` — relative scroll; same clamping.
  - `(viewport-visible-rectangle viewport)` — the currently visible content
    rectangle, in content coordinates.

### Style and theme

- **`color`** — `color-kind` (a symbol: `:default`, `:named`, `:indexed`, or
  `:rgb`), `color-value`. Prefer the constructors over `make-color`
  directly:
  - `(default-color)` — the terminal's default foreground/background.
  - `(named-color name)` — one of the eight conventional ANSI names (for
    example `:red`); `name` is not validated at construction time.
  - `(indexed-color index)` — a 256-color palette index, 0–255. Signals
    `invalid-range-error` outside that range.
  - `(rgb-color red green blue)` — each component 0–255. Signals
    `invalid-range-error` on any out-of-range component.
  - `(color= left right)` — structural equality.
- **`style`** — `style-foreground`, `style-background` (both `color`),
  `style-bold`, `style-dim`, `style-italic`, `style-underline`,
  `style-reverse`, `style-strike` (all booleans). `(make-style &key
  (foreground (default-color)) (background (default-color)) bold dim italic
  underline reverse strike)`. `(copy-style style)`, `(style= left right)`.
  - `(merge-styles base overlay)` — returns a style with `overlay`'s enabled
    attributes layered over `base`. A default-colored `overlay` foreground
    or background falls through to `base`'s color; overlay attributes only
    ever add, never remove — construct explicitly with `make-style` to
    disable an attribute.
- **`theme`** — an opaque role→style table. `(make-theme &optional styles)`
  where `styles` is an alist of `(role . style)`. `(copy-theme theme)`.
  - `(theme-style theme role &optional fallback)` — returns the style bound
    to `role`, or `fallback` (default `nil`) when unbound.
  - `(theme-set-style theme role style)` — binds `role` to a copy of
    `style`. Signals `invalid-type-error` (via `check-type`) if `role` is
    not a symbol or `style` is not a `style`.
  - `(default-theme)` — returns a theme with these roles pre-populated:
    `:background`, `:foreground`, `:muted` (dim), `:accent` (bold cyan),
    `:selected` (reverse), `:border` (white), `:warning` (bold yellow),
    `:error` (bold red), `:success` (green), `:title` (bold), `:disabled`
    (dim). Every built-in widget looks up its presentation through these
    role names rather than embedding colors directly, so restyling an
    application is a matter of building a different theme, not editing
    widget code.

### Text and cell width

A deliberately small, centralized terminal-cell width policy. It groups
combining marks and ZWJ sequences well enough for normal TUI labels, while
documenting that it is not a full UAX #29 grapheme-cluster implementation
(see [Text Layout](../guide/text-layout.md) for the design rationale).

- `*ambiguous-width*` — dynamic variable, `:narrow` (default) or `:wide`,
  controlling how East Asian Ambiguous-width characters are measured.
- `(with-ambiguous-width (width) &body body)` — macro; binds
  `*ambiguous-width*` to `width` for the dynamic extent of `body`.
- `(cell-width character &optional (ambiguous-width *ambiguous-width*))` —
  the terminal-cell width of one code point: 0 for combining marks,
  variation selectors, ZWJ, emoji modifiers, and control characters; 2 for
  wide code points (and for ambiguous-width code points when
  `ambiguous-width` is `:wide`); 1 otherwise.
- `(text-units text)` — splits `text` (a `string`) into approximate
  grapheme-like units, grouping a base character with trailing combining
  marks, variation selectors, and simple ZWJ sequences. Returns a list of
  one-or-more-character strings. Signals `invalid-type-error` if `text` is
  not a string.
- `(text-unit-width unit &optional (ambiguous-width *ambiguous-width*))` —
  the display width of one unit returned by `text-units`, capped at 2.
- `(string-cell-width text &key (tab-width 8) (ambiguous-width
  *ambiguous-width*))` — the maximum cell width of any line in `text`,
  expanding tabs to `tab-width`-aligned stops. Signals `invalid-range-error`
  if `tab-width` is not a positive integer.
- `(clip-text text max-width &key (tab-width 8) (ambiguous-width
  *ambiguous-width*))` — clips a single display line to `max-width` cells
  without splitting a grapheme unit; a unit that would only partially fit is
  dropped rather than truncated mid-glyph. Stops at the first newline.
  Signals `invalid-range-error` if `max-width` is negative or `tab-width` is
  not positive.
- `(truncate-text text max-width &key (ellipsis "…") (tab-width 8)
  (ambiguous-width *ambiguous-width*))` — returns `text` unchanged if it
  already fits `max-width`; otherwise clips it and appends `ellipsis`
  (itself clipped to fit if `max-width` is too small for it). Signals
  `invalid-range-error` if `max-width` is negative.

### Cells and surfaces

- **`cell`** — `cell-p`, `cell-content` (a one-grapheme-unit string),
  `cell-style`, `cell-span` (`(integer 0)`, its display width),
  `cell-continuation-p` (true for the filler cell trailing a wide glyph).
  `(make-cell &rest arguments)` accepts an optional leading content
  character/string followed by `:style`, `:span`, and `:continuation-p`
  keywords. `(copy-cell cell)`, `(blank-cell &optional (style (make-style)))`
  — a single space cell.
  - A drawable (non-continuation) cell must hold exactly one display unit
    whose width equals its span; a continuation cell must have empty content
    and zero span. `make-cell`, `copy-cell`, and `surface-put-cell` all
    enforce this and signal `surface-error` when it does not hold. An
    invalid `:span` (not a non-negative integer) signals
    `invalid-range-error`; an odd number of keyword arguments to `make-cell`
    or `make-surface` signals `invalid-argument-error`; an unrecognized
    keyword signals `invalid-option-error`.
- **`text-span`** — `text-span-text`, `text-span-style`. `(make-text-span
  text &key style)` — copies `style` so a later mutation of the caller's
  style object cannot retroactively change the span's rendering contract.
  Signals `invalid-type-error` if `text` is not a string or `style` (when
  supplied) is not a `style`.
- **`surface`** — `surface-p`, `surface-width`, `surface-height` (both
  `(integer 0)`), `surface-default-style`. `(make-surface &rest arguments)`
  accepts optional leading `width height` integers followed by `:style` and
  `:clip` keywords; `:clip` accepts a `rectangle`, a `clipping-region`, or
  `nil`. Signals `invalid-range-error` if width/height is negative,
  `invalid-type-error` if `:clip` is none of the accepted types.
  `(copy-surface surface)` — a deep copy, including dirty regions.
  - `(surface-cell surface x y)` — the cell at `(x, y)`, or `nil` outside
    bounds (no error).
  - `(surface-put-cell surface x y cell)` — writes `cell`, clipped to the
    surface's current clip rectangle and bounds. Writing a wide (span > 1)
    cell also writes the trailing continuation cells and clears whatever
    unit previously occupied that span, so the invariant above never breaks
    from a partial overwrite. Marks the affected region dirty. Signals
    `invalid-type-error` (via `check-type`) if `cell` is not a `cell`.
  - `(surface-clear surface &optional rectangle style)` — blanks
    `rectangle` (default: the whole surface, clipped) with `style` (default:
    the surface's default style).
  - `(surface-fill surface character &optional style)` — fills the whole
    surface (respecting clip) with one repeated character.
  - `(surface-fill-rectangle surface rectangle &optional (character #\Space)
    style)` — as above, scoped to `rectangle`.
  - `(surface-draw-text surface x y text &key style max-width (tab-width
    8))` — draws `text` starting at `(x, y)`; newlines move to the next row
    at the original `x`; a unit that would only half-fit at `max-width` (or
    the surface edge) is omitted rather than split. Signals
    `invalid-range-error` if `tab-width` is not a positive integer.
  - `(surface-draw-styled-text surface x y spans &key max-width
    (tab-width 8))` — draws a list of `text-span`s as one logical run, each
    keeping its own style; newline/tab/width behavior matches
    `surface-draw-text`. Signals `invalid-range-error` on a bad `tab-width`.
  - `(surface-draw-border surface rectangle &key (style
    (surface-default-style surface)) (kind :single))` — `kind` is `:single`
    (default), `:double`, `:rounded`, or `:ascii`.
  - `(surface-blit destination source &key source-rectangle
    (destination-point (make-point)))` — copies lead (non-continuation)
    cells from `source` into `destination`; a cell whose span would extend
    past `source-rectangle`'s right edge is skipped.
  - `(surface-clip surface)` — the current clip rectangle. Read-only; use
    `(surface-set-clip surface rectangle)` to change it (accepting a
    `rectangle` or `clipping-region`, intersected with the surface bounds).
  - `(call-with-surface-clip surface rectangle continuation)` /
    `(with-surface-clip (surface rectangle) &body body)` — temporarily
    narrows the clip for the dynamic extent of `continuation`/`body`,
    restoring the previous clip afterward even on a non-local exit
    (`unwind-protect`). Signals `invalid-type-error` if `continuation` is
    not a function.
  - `(surface-dirty-regions surface)` — copies of the rectangles marked
    dirty since the last `surface-mark-clean`. `(surface-mark-clean
    surface)`, `(surface-mark-dirty surface rectangle)` (the latter is used
    internally by the mutators above but is exported for a custom backend
    that needs to mark a region dirty directly).
  - `(surface-diff current previous)` — returns a list of `cell-change`
    structs (`cell-change-x`, `-y`, `-before`, `-after`) for every cell that
    differs between the two surfaces, in row-major order. `previous` may be
    `nil`, in which case every cell in `current` is reported changed.
  - `(surface-string surface)` — a deterministic textual snapshot: one line
    per row, continuation cells omitted (their lead cell already carries the
    full grapheme). Positional detail remains available through
    `surface-cell`/`surface-diff`; this projection is for readable
    assertions and debugging.

### Events

Normalized input and output events, and the semantic actions widgets return
in response to them. Every event struct includes an `event-kind` accessor
(inherited from the base `event` struct) returning its dispatch keyword
(`:key`, `:text-input`, `:paste`, `:clipboard`, `:resize`, `:mouse`,
`:focus`, `:tick`, or `:custom`), and `event-p` tests membership in the
`event` type.

- **`key-event`** — `key-event-key`, `key-event-modifiers` (a normalized
  list, see below), `key-event-text` (the literal text a plain character key
  would insert, or `nil`), `key-event-phase` (`:press`, `:repeat`, or
  `:release`, when the input source distinguishes them; default `:press`).
  `(make-key-event key &key modifiers text (phase :press))`.
- **`text-input-event`** — `text-input-event-text`. `(make-text-input-event
  text)`. Signals `invalid-type-error` if `text` is not a string.
- **`paste-event`** — `paste-event-text`. `(make-paste-event text)`. Same
  type check.
- **`clipboard-event`** — `clipboard-event-selection` (a string, default
  `"c"`), `clipboard-event-text`. `(make-clipboard-event text &key
  (selection "c"))`. Normalizes a terminal OSC 52 clipboard response.
- **`resize-event`** — `resize-event-width`, `resize-event-height` (both
  non-negative integers, clamped at 0). `(make-resize-event width height)`.
- **`mouse-event`** — `mouse-event-x`, `mouse-event-y` (integers),
  `mouse-event-button`, `mouse-event-kind` (`:press`, `:release`, `:move`,
  `:scroll-up`, or `:scroll-down`), `mouse-event-modifiers`. `(make-mouse-event
  x y &key button (kind :press) modifiers)`.
- **`focus-event`** — `focus-event-focused-p`, `focus-event-reason`.
  `(make-focus-event focused-p &optional reason)`.
- **`tick-event`** — `tick-event-time`. `(make-tick-event &optional time)` —
  `time` is an opaque, caller-supplied value; the core never generates one
  itself (no wall-clock read, no timer thread).
- **`custom-event`** — `custom-event-name` (a symbol), `custom-event-payload`.
  `(make-custom-event name &optional payload)`. Signals `invalid-type-error`
  if `name` is not a symbol. Used both by application code for its own event
  types and internally, by the terminal input parser, for conditions such as
  `:paste-overflow` and `:input-incomplete`.
- `(normalize-modifiers modifiers)` — canonicalizes a list of modifier
  designators (keywords, or case-insensitive strings/symbols naming
  `"control"`/`"ctrl"`, `"meta"`/`"alt"`, `"shift"`, `"super"`, `"hyper"`)
  into a deduplicated, canonically ordered list of `:ctrl`/`:alt`/`:shift`/
  `:super`/`:hyper` keywords, without interning caller-provided strings as
  new symbols. Any other keyword is passed through unchanged; a non-keyword
  designator that matches none of the named strings signals
  `invalid-option-error`. Called automatically by every event and
  key-stroke constructor above that takes a `modifiers` argument.

### Actions

- **`action`** — `action-name` (a symbol), `action-payload`, `action-source`
  (typically the widget that produced it). `(make-action name &optional
  payload source)`. Signals `invalid-type-error` if `name` is not a symbol.
- Semantic constructors, each `(&optional payload source)` composing
  `make-action` with a fixed name: `activate-action` (`:activate`),
  `cancel-action` (`:cancel`), `submit-action` (`:submit`), `toggle-action`
  (`:toggle`), `open-action` (`:open`), `close-action` (`:close`).
  `(move-action direction &optional amount source)` builds `:move` with
  payload `(:direction direction :amount (or amount 1))`. `(select-action
  key &optional source)` builds `:select` with `key` as the payload.
  `(custom-action name &optional payload source)` is `make-action` under
  another name, for an application's own action vocabulary.

### Keymaps

- **`key-stroke`** — `key-stroke-key`, `key-stroke-modifiers`.
  `(make-key-stroke key &key modifiers)` — `modifiers` is passed through
  `normalize-modifiers`.
- **`keymap`** — `keymap-name`, `keymap-parent`, `keymap-mode`.
  `(make-keymap &key (name :keymap) parent (mode :default) prefix-timeout)`
  — `prefix-timeout`, when supplied, must be a function (signals
  `invalid-type-error` otherwise).
  - `(set-keymap-mode keymap mode)`, `(set-keymap-prefix-timeout keymap
    function)` — mutate in place, return `keymap`.
  - `(keymap-mode-map keymap &optional (mode (keymap-mode keymap)))` — the
    sub-keymap registered for `mode`, or `keymap` itself when no mode map is
    registered.
  - `(define-keymap-mode keymap mode &key (inherit-parent t))` — creates and
    registers a child keymap for `mode`; when `inherit-parent` is true (the
    default), unhandled sequences fall through to `keymap`.
  - `(bind-key keymap sequence binding &key mode)` — `sequence` is a
    `key-stroke`, a `key-event`, a `(key . modifiers)` cons, or a bare key
    designator, or a list of any of those for a multi-key sequence.
    `binding` is a function of one argument (the triggering event), a
    symbol (wrapped as a custom action via `custom-action`), or any other
    value (returned as-is). `(unbind-key keymap sequence &key mode)` removes
    a binding.
  - `(define-keymap name options &body bindings)` — macro; generates
    `(defun name (&key parent) ...)` that builds a declarative keymap.
    `options` is a literal plist passed to `make-keymap` (and must not
    include `:parent`, which the generated function supplies at call time).
    Each entry in `bindings` is `(sequence action &rest bind-options)`.
    Signals (at macroexpansion time) `invalid-type-error` if `name` is not a
    symbol or `options` is not a list, `invalid-argument-error` if `options`
    has an odd length, `invalid-option-error` if an option key is not a
    keyword or is `:parent`.
  - **`keymap-state`** — `keymap-state-pending`, `keymap-state-pending-since`
    (both read-only; `(reset-keymap-state state)` clears them together).
    `(make-keymap-state &key time)`.
    `(keymap-state-prefix-active-p state)` — true when a multi-key prefix is
    in progress.
  - **`keymap-result`** — `keymap-result-status` (`:handled`, `:prefix`,
    `:timeout`, or `:unhandled`), `keymap-result-action`,
    `keymap-result-prefix`.
  - `(keymap-dispatch keymap state event &key time)` — dispatches one
    `key-event` through `keymap`, tracking a pending prefix in `state`
    across calls. A failed longer sequence retries as a fresh single key
    (the least-surprising behavior for modal applications) rather than
    dropping the key entirely. Signals `invalid-type-error` (via
    `check-type`) if `keymap`/`state`/`event` has the wrong type.
  - `(keymap-expire-prefix keymap state &optional event)` — explicitly
    expires a pending prefix using `keymap`'s `prefix-timeout` callback
    (receiving the pending key-stroke list and `event`), returning a
    `:timeout`-status result. The core never starts a timer for this itself;
    an application drives it from its own clock, or from the
    [event loop](event-loop.md).
  - `(dispatch-keymaps keymaps state event &key time)` — tries `keymaps` in
    order, most specific first; the first non-`:unhandled` result wins.
  - `(vi-like-keymap &key (name :vi-like))` — a generic three-mode
    (`:normal`/`:insert`/`:visual`) keymap skeleton. It only emits semantic
    action names such as `:enter-normal-mode`; it does not itself switch the
    keymap's mode or interpret those actions — the application does.

### Incremental terminal input normalization

Turns raw terminal bytes into normalized `event`s. The parser owns only its
buffering state — no stream, thread, or file descriptor — so an input source
(a TTY runtime, a test replay, an arbitrary byte source) feeds it octets or
strings and receives events back.

- **`terminal-input-parser`** — `terminal-input-parser-buffer`,
  `-pending-octets`, `-in-paste-p`, `-paste-buffer` (all four read-only; call
  `terminal-input-parser-reset` to clear them together), `-max-sequence-length`
  (default 256), `-max-paste-length` (default 1 MiB). `(make-terminal-input-parser
  &key (max-sequence-length 256) (max-paste-length (* 1024 1024)))`.
  - `(terminal-input-parser-feed parser input)` — `input` is a `string` or an
    octet vector; returns newly decoded events. UTF-8 and escape sequences
    may be split across calls and remain buffered until complete. Malformed
    UTF-8 decodes to U+FFFD; a control/escape sequence or a bracketed paste
    that exceeds its configured maximum length becomes an explicit
    `:input-overflow`/`:paste-overflow` custom event rather than growing the
    buffer without bound. Signals `invalid-range-error` if an octet in a
    vector `input` is outside 0–255, `invalid-type-error` if `input` is
    neither a string nor a vector.
  - `(terminal-input-parser-flush parser)` — call at end-of-stream; drains
    any incomplete state as a best-effort final event (a lone incomplete
    UTF-8 sequence becomes U+FFFD, a lone unresolved escape becomes an
    `:escape` key event, an incomplete paste becomes a `:paste-incomplete`
    custom event) rather than silently discarding it.
  - `(terminal-input-parser-reset parser)` — discards all buffered input
    while retaining the configured limits.
  - `(terminal-input-parser-pending-p parser)` — true when the parser is
    waiting for more input to complete a sequence.
- **`terminal-event-source`** — `terminal-event-source-reader`, `-parser`,
  `-eof-value`, `-eof-p`, `-closed-p`. `(make-terminal-event-source reader
  &key parser (eof-value :eof) close-reader)` — `reader` is a zero-argument
  function returning a string, an octet vector, or `eof-value`; `parser`
  defaults to a fresh `terminal-input-parser`; `close-reader`, when
  supplied, runs at most once, at EOF or explicit close. Signals
  `invalid-type-error` if `reader`/`parser`/`close-reader` has the wrong
  type.
  - `(terminal-event-source-next source)` — returns the next normalized
    event, buffering any extra events decoded from one `reader` call so
    callers always receive exactly one event per call; returns
    `eof-value` once the reader reports EOF (after a final parser flush). A
    `reader` return value that is neither a string, an octet vector, nor
    `eof-value` signals `callback-contract-error` (see
    [Conditions](conditions.md#callback-contract-error)).
  - `(terminal-event-source-close source)` — idempotent; discards queued
    events and parser state (unlike natural EOF, which preserves a final
    flush) and invokes `close-reader` at most once.
  - `(terminal-event-source-pending-p source)` — true when an event is
    queued or the parser holds incomplete input.
- `(make-stream-event-source stream &key parser (chunk-size 4096)
  (element-type :character) (close-stream-p nil) (eof-value :eof))` — a
  blocking `terminal-event-source` backed by a standard Common Lisp stream.
  `element-type` is `:character` or `:octet`; `stream` is read via
  `read-sequence` in `chunk-size` pieces. `stream` is closed only when
  `close-stream-p` is true, keeping this usable with standard streams an
  application does not own. Signals `invalid-range-error` if `chunk-size` is
  not a positive integer, `invalid-option-error` if `element-type` is
  neither `:character` nor `:octet`.

### Deterministic event loop

An optional scheduling primitive — construction, posting, one-shot and
repeating timers, cancellation, stepping and running, the wakeup
coordination flag, and the caller-supplied error handler — fully documented
on its own page: [Event Loop](event-loop.md). It is driven by an injected
clock rather than wall time and never spawns a thread or sleeps.

### Backend protocol

`backend` is the abstract output protocol every concrete backend (the
in-memory `test-backend`, the streaming `ansi-backend`, the experimental
`tty-backend`) implements. The core defines it and a no-op default
implementation; it does not itself open a terminal.

- **`backend-capabilities`** — `backend-capabilities-color` (keyword,
  default `:none`), `-unicode` (default `:basic`), `-mouse` (default
  `:none`), `-clipboard`, `-alternate-screen` (boolean, default `t`).
  `(make-backend-capabilities &key (color :none) (unicode :basic) (mouse
  :none) clipboard (alternate-screen t))`.
- **`backend`** class — `backend-capabilities` is a plain read/write
  accessor: nothing in `cl-tui-kit/core` ever reassigns the slot on its own,
  so there is no invariant behind it that a raw `setf` could desynchronize.

  Every other reader below is read-only, each backed by a dedicated mutator
  that keeps it consistent with something the backend has already done:
  - `backend-size` — a copy of the current logical size (`copy-size`, so
    mutating the returned `size` has no effect on `backend`, and a caller
    cannot reach the backend's own record through it); call `backend-resize`
    to change it.
  - `backend-cursor` — a copy of the current logical cursor position
    (`copy-point`, same reasoning); call `backend-set-cursor` to change it.
  - `backend-cursor-visible` — call `backend-set-cursor-visible` to change
    it.
  - `backend-title` — call `backend-set-title` (or `backend-clear-title`)
    to change it.
  - `backend-alternate-screen-p` — call `backend-enter-alternate` (which
    additionally checks `backend-supports-p` for `:alternate-screen` before
    setting it) or `backend-leave-alternate` to change it.

  `backend-state` (a keyword: `:closed`, `:open`, or `:failed`) and
  `backend-last-error` (the condition object from the most recent
  `backend-fail`, or `nil`) are likewise read-only: both are maintained
  internally by `backend-open`, `backend-close`, and `backend-fail`, and a
  raw `setf` on either would desynchronize the recorded state from the
  lifecycle those functions enforce. `backend-capability-states` is also
  read-only, and additionally returns a fresh copy of the backend's internal
  capability-state hash table on every call — mutating the returned table
  has no effect on `backend`; call `backend-set-capability-state` to change
  a capability's recorded state.

  `(make-backend &key (size (make-size)) capabilities cursor
  (cursor-visible t) title capability-states)`.
  - `(backend-capability backend capability)` — the raw value for
    `:color`/`:unicode`/`:mouse`/`:clipboard`/`:alternate-screen`; an
    unrecognized keyword returns `nil` rather than erroring, so an adapter
    can probe optional capabilities freely.
  - `(backend-capability-state backend capability)` — a normalized state:
    `:unknown`, `:unsupported`, `:supported`, or `:error`, read from
    `backend-capability-states`. An explicit state set via
    `backend-set-capability-state` takes precedence over the derived value
    from the raw capability. Signals `invalid-option-error` for an
    unrecognized `capability`.
  - `(backend-supports-p backend capability)` — true only when the
    normalized state is exactly `:supported`.
  - `(backend-set-capability backend capability value)`,
    `(backend-set-capability-state backend capability state &key (value nil
    value-supplied-p))` — adapter hooks that record an observation; they do
    not themselves probe the terminal. Both signal `invalid-option-error`
    for an unrecognized `capability` or (the latter) `state`.
  - `(backend-open backend)` / `(backend-close backend)` — the `:closed` ↔
    `:open` lifecycle. The default `backend-close` calls
    `backend-reset-output` and `backend-flush`; a condition from either is
    recorded via `backend-fail` and re-signalled.
  - `(backend-fail backend condition)` — records `condition` in
    `backend-last-error` and sets `backend-state` to `:failed`. Signals
    `invalid-type-error` (via `check-type`) if `condition` is not a
    `condition`.
  - `(backend-resize backend width height)` — updates `backend-size` and
    calls the `backend-resized` generic function with the old and new size
    (a hook for adapters, such as `ansi-backend`, to invalidate a cached
    diff baseline).
  - Frame lifecycle generic functions, each with a documented no-op default
    method on the base `backend` class: `backend-begin-frame`,
    `(backend-present backend surface &key region)`, `backend-flush`,
    `(backend-set-cursor backend point)`, `(backend-set-cursor-visible
    backend visible-p)`, `backend-enter-alternate`, `backend-leave-alternate`,
    `(backend-set-title backend title)`, `backend-invalidate`,
    `backend-clear-title`, `backend-reset-output` (composes invalidate,
    show-cursor, clear-title, and leave-alternate — the state a clean
    shutdown should restore).
  - Clipboard generic functions, each defaulting to `(values nil
    :unsupported)` on the base class: `(backend-write-clipboard backend
    text)`, `backend-read-clipboard`, `(backend-request-clipboard backend
    &key (selection "c"))` — the last is asynchronous; its response arrives
    later as a normalized `clipboard-event` through the input path, not as
    this call's return value.

### Continuation-oriented protocol helpers

- `(dispatch-event/k handlers event handled-k &key (unhandled-k #'identity))`
  — dispatches `event` through the list `handlers` using explicit
  continuations rather than a fixed handler-chain data structure. Each
  handler receives `(event next-k)`; returning non-`nil` handles the event
  and calls `handled-k` with that value, returning `nil` falls through
  to the next handler (or to `unhandled-k` when the list is exhausted), and
  a handler may call `next-k` explicitly to delegate after doing its own
  work first. Signals `invalid-type-error` (via `check-type`) on a
  malformed `handlers`/`event`/`handled-k`/`unhandled-k`.
- `(present-frame/k backend surface continuation &key region)` — calls
  `backend-begin-frame`, `backend-present`, and `backend-flush` in sequence,
  then `continuation` with `surface`. A thin, explicit orchestration
  helper — it introduces no thread or hidden terminal side effect beyond
  what the three backend calls already do. Signals `invalid-type-error` on
  a malformed `backend`/`surface`/`continuation`, or if `region` is supplied
  and is not a `rectangle`.

### Conditions

The 22-symbol typed condition hierarchy rooted at `cl-tui-kit-error` — every
class, its slots, which call sites signal it, and how it interacts with
`cl:type-error` and `handler-case` — is documented on its own page:
[Conditions](conditions.md).

## cl-tui-kit/layout

Layout is deliberately a pure calculation over rectangles: it knows nothing
about widgets, application state, or terminal capabilities. A layout tree is
built from `layout-node`s and computed against a bounding `rectangle` only
when `layout-rects` is called — nothing here owns mutable render state.

### Layout nodes

- **`layout-item`** — `layout-item-child`, `layout-item-constraints`,
  `layout-item-margin`. `(make-layout-item child &key constraints margin)` —
  wraps a child (a widget, or any application-defined object recognized by
  `layout-preferred-size`) with per-child sizing. Building a layout node
  directly from bare children (see below) wraps each one in a default
  `layout-item` automatically; use this constructor only when a child needs
  non-default `constraints` or `margin`.
- **`layout-node`** — `layout-kind` (a keyword, e.g. `:vbox`),
  `layout-children` (a list of `layout-item`s — bare children passed to a
  `make-*` constructor are normalized into these). `(make-layout-node kind
  children &key constraints options)` — the generic constructor; the
  `make-vbox`/`make-hbox`/etc. functions below are the ones application
  code normally calls. Signals `invalid-type-error` if `kind` is not a
  keyword.
- Node constructors, each `make-layout-node` under a fixed `kind`:
  - `(make-vbox children &key constraints (gap 0))`,
    `(make-hbox children &key constraints (gap 0))` — stack children
    vertically/horizontally with `gap` cells between them. Signals
    `invalid-range-error` if `gap` is negative.
  - `(make-stack children &key constraints)` — all children fill the same
    rectangle (rendering order decides what's on top).
  - `(make-overlay children &key constraints)` — synonym for `make-stack`'s
    placement semantics under a distinct `:overlay` kind, for callers that
    want to express intent (an overlay layer) rather than a plain stack.
  - `(make-split children &key (ratio 0.5) (axis :horizontal) constraints)`
    — exactly two children, split at `ratio` (0–1) along `axis`
    (`:horizontal` or `:vertical`). Signals `invalid-range-error` if `ratio`
    is outside 0–1, `invalid-option-error` if `axis` is neither
    `:horizontal` nor `:vertical`.
  - `(make-padding-layout child &key (padding (make-padding)) constraints)`
    — one child, inset by `padding`.
  - `(make-border-layout child &key (padding (make-padding :all 1))
    constraints)` — like padding, but conventionally reserves the outer
    ring for a border a widget draws itself; `cl-tui-kit/widgets`'
    `box-widget` combines this with `surface-draw-border`.
  - `(make-center-layout child &key constraints)` — one child, centered at
    its preferred size (never grown beyond it).
  - `(make-viewport-layout child &key constraints)`, `(make-scroll-container
    child &key constraints)` — one child, given the full rectangle; these
    exist as layout-tree placeholders for viewport/scroll widgets, which
    manage their own content offset rather than the layout engine
    reflowing content for them.
  - `(make-grid children &key columns rows (column-gap 0) (row-gap 0)
    constraints)` — `columns` is required and must be a positive integer;
    `rows` is optional (computed from the child count when omitted) but
    must be positive when supplied. Column/track sizing is computed per
    the widest/tallest cell in that track. Signals `invalid-range-error` on
    a non-positive `columns`/`rows` or a negative gap.
- `(layout-rects layout bounds)` — computes and returns an alist mapping
  each immediate child (the original object passed to the constructor, not
  the `layout-item` wrapper) to its resolved `rectangle` within `bounds`.
  Signals `invalid-type-error` (via `check-type`) if `layout` is not a
  `layout-node` or `bounds` is not a `rectangle`.
- `(layout-child-rectangle layout child bounds)` — convenience: `(cdr (assoc
  child (layout-rects layout bounds) :test #'eq))`.
- `(layout-preferred-size layout)` — a `defgeneric`; the default method on
  `t` returns `(make-size)` (zero), letting a layout tree containing
  arbitrary application objects degrade gracefully. `cl-tui-kit/widgets`
  registers no method on `widget` for this generic function: a bare widget
  placed directly as a layout child falls through to the `t` method and is
  sized as zero. `widget-preferred-size` (see below) is a separate,
  widget-only sizing protocol — composite widgets such as `box-widget` call
  it directly on their children — and is not consulted by the layout
  engine; an application that needs a widget's real size inside a layout
  tree must query `widget-preferred-size` itself rather than rely on
  `layout-preferred-size`/`layout-rects` to do it automatically.

### Focus

A focus tree is a parallel structure to the layout/widget tree, tracking
which node currently has input focus, modal scoping, and directional
navigation. It is deliberately separate from list/table row selection.

- **`focus-node`** — `focus-node-id`, `focus-node-widget`,
  `focus-node-children`, `focus-node-parent`, `focus-node-rectangle`,
  `focus-node-focusable-p`, `focus-node-scope-p`. `(make-focus-node id &key
  widget children rectangle focusable-p scope-p)` — `children` are adopted
  (their `parent` slot is set to the new node) recursively. `focus-node` has
  a custom `print-object` method that never descends into `:parent` or
  `:children`, because parent/child references form a genuine cycle that
  would otherwise recurse the default structure printer into a stack
  overflow.
- **`focus-tree`** — `focus-tree-root`, `focus-tree-current`,
  `focus-tree-modal-stack`. `(make-focus-tree root)` — `root` may be a
  `focus-node` or a raw id (wrapped as one); initial focus is the first
  focusable node found by a depth-first walk.
  - `(focus-tree-set-current tree node)` — moves focus, after verifying
    `node` belongs to `tree` and, if a modal is active, lies inside the
    active modal's scope. Signals `focus-error` (see
    [Conditions](conditions.md#focus-error)) on either violation.
  - `(focus-next tree)` / `(focus-previous tree)` — move focus to the
    next/previous focusable node (within the active modal scope, if any),
    wrapping around; return the new `focus-tree-current`.
  - `(focus-directional tree direction)` — `direction` is `:left`, `:right`,
    `:up`, or `:down`; moves to the nearest focusable node whose center lies
    in that direction from the current node's center, or does nothing if
    none qualifies. Signals `invalid-type-error` (via `check-type`) if
    `direction` is not a keyword.
  - `(focus-push-modal tree scope)` — pushes `scope` (a `focus-node` that
    must belong to `tree`) as the active modal scope, saving the prior
    focus to restore later, and moves focus to the first focusable node
    inside `scope`. Signals `focus-error` if `scope` is not part of `tree`.
  - `(focus-pop-modal tree)` — pops the modal stack and restores the focus
    saved when that scope was pushed.
  - `(focus-restore tree)` — a documented alias for `focus-pop-modal`,
    named for the call site's intent ("leave the modal and restore prior
    focus") rather than the stack mechanics.
  - `(focus-visible-p tree node)` — true when `node` is both the current
    focus and reachable from the active scope (so a node that is
    technically `focus-tree-current` but has been orphaned by a modal push
    reports `nil`, not a stale `t`).

## cl-tui-kit/widgets

Widgets are small protocol objects that own presentation state only;
application state and side effects stay in the application. `cl-tui-kit/widgets`
depends on `cl-tui-kit/layout` and `cl-tui-kit/core`.

Most widget accessors are plain read/write: content such as
`text-widget-text`, `progress-widget-value`, `checkbox-widget-checked-p`,
and `input-widget-value`, and configuration such as `list-widget-model` and
every `-options`/`-items` accessor, is how an application *uses* a widget —
assigning it directly is the interface, and no sanctioned function's
invariant sits behind the slot. A widget's own *selection or scroll state*
— which option, row, tab, or key is currently selected, and where a
viewport has scrolled to — is the exception: it is documented read-only per
widget below, each paired with the function that is the sanctioned way to
change it (see [API
Stability](../project/api-stability.md#read-only-accessors-for-internal-state)
for the general rule). `select-widget-open-p` and `menu-widget-open-p` are a
deliberate non-exception: both widgets' own `widget-handle-event` methods
assign them directly — closing a `select-widget` on Escape, or opening a
`menu-widget`'s submenu on Enter — rather than always routing through
`select-widget-toggle`, so the toolkit does not itself treat that function
as the only way in, and converting the accessor to read-only would have
frozen a rule the code does not follow.

### Widget protocol

`widget` is a `defclass`, not a struct, so every built-in widget below
inherits its accessors and may be subclassed. Base accessors: `widget-id`,
`widget-rectangle`, `widget-style`, `widget-theme` (default: `(default-theme)`),
`widget-keymap`, `widget-focusable-p`, `widget-enabled-p`, `widget-role`
(a semantic-role keyword), `widget-label`, `widget-description`,
`widget-help-text` (the last four back the accessibility protocol below),
`widget-children`. `(make-widget &key id rectangle style theme keymap
focusable-p (enabled-p t) semantic-role accessible-label
accessible-description accessible-help-text children)` constructs a bare
`widget`; application code almost always uses one of the concrete
constructors below instead.

Generic functions every widget participates in, each with a default method
on the base `widget` class:

- `(widget-preferred-size widget)` — default `(make-size)`.
- `(widget-layout widget rectangle)` — default sets `widget-rectangle` and
  recurses into `widget-children` with the same rectangle (a composite
  widget overrides this to partition space among its children).
- `(widget-render widget surface)` — default renders each child in turn.
- `(widget-handle-event widget event)` — default `nil` (unhandled).
- `(widget-handle-child-action widget action)` — default returns `action`
  unchanged; a composite widget overrides this to intercept or transform
  actions bubbling up from a descendant (see `render-widget`/dispatch below).
- `(widget-cursor-position widget)` — default `nil`; a text-entry widget
  returns a `point` in surface coordinates when it wants the terminal cursor
  shown there.
- `(widget-accessibility-state widget)` — default `nil`; widget-specific
  state such as a checkbox's checked flag or a progress bar's value/maximum.
- `(widget-accessibility-info widget)` — default assembles a plist from
  `:id`, `:role`, `:label`, `:description`, `:help-text`, `:enabled-p`,
  `:focusable-p`, and `:state` (via `widget-accessibility-state`); each
  built-in widget's method fills in a default `:role` and `:label` when the
  caller did not supply one.
- `(widget-active-p widget)` — default `t`; `modal-widget` overrides this to
  return its open/closed state, which is how a closed modal's children stop
  participating in hit-testing and focus without being removed from the
  tree.
- `(widget-interactive-children widget)` — default `widget-children`;
  overridden where the active child set differs from the full child list
  (again, `modal-widget`).
- `(widget-capture-event-p widget event)` — default `nil`; a widget that
  returns true here intercepts `event` before it reaches a descendant along
  the dispatch path (used by `modal-widget` for Escape and `:close`).
- `(widget-accessibility-tree widget)` — not generic; walks
  `widget-accessibility-info`/`widget-interactive-children` recursively into
  a serializable snapshot, adding a `:children` entry at each level.
- `(render-widget widget surface &optional rectangle)` — calls
  `widget-layout` (when `rectangle` is supplied) then `widget-render`;
  the composition point most application code calls directly.
- `(handle-widget-event widget event)` — calls `widget-handle-event` only
  when `widget-enabled-p` is true; a disabled widget silently ignores every
  event.

### Application lifecycle

- **`application`** — `application-backend`, `application-root` (the root
  `widget`), `application-surface`, `application-focus-tree`,
  `application-keymap-state`, `application-running-p`, `application-dirty-p`
  (default `t`), `application-last-action`, `application-alternate-screen-p`
  (default `t`), `application-title`. `(make-application &key backend root
  surface focus-tree keymap-state (alternate-screen-p t) title)` — `backend`
  defaults to a bare `(make-backend)`, `root` to a bare `(make-widget)`,
  `surface` to one sized from the backend's current size, `focus-tree` to
  `(make-widget-focus-tree root)`. Signals `invalid-type-error` (via
  `check-type`) if `root` is not a `widget`.
- `(make-widget-focus-tree root)` — builds a `focus-tree` mirroring the
  widget tree rooted at `root`: each `focus-node`'s `focusable-p` is `(and
  (widget-active-p w) (widget-enabled-p w) (widget-focusable-p w))`.
  `(application-refresh-focus-tree application)` — rebuilds this tree
  (needed after the active child set changes, for example when a modal
  opens) while preserving the currently focused widget when it still exists
  in the new tree.
- `(application-layout application)` — lays out `application-root` against
  the backend's current size, refreshes the focus tree, resizes the surface
  if the backend size changed, and synchronizes every focus node's cached
  `rectangle` from its widget.
- `(application-invalidate application)` — sets `application-dirty-p` to
  `t`, requesting a render on the next step.
- `(application-render/k application continuation)` — lays out, clears and
  redraws the surface, positions (or hides) the terminal cursor based on the
  focused widget's `widget-cursor-position`, presents the frame via
  `present-frame/k`, marks the surface and application clean, then calls
  `continuation` with `application`. `(application-render application)` is
  this with `continuation` defaulting to `#'identity`. Both signal
  `invalid-type-error` on a malformed `application`/`continuation`.
- `(widget-hit-test widget x y)` — the topmost active, enabled,
  interactive-child (searched back-to-front, i.e. last-rendered-first) whose
  rectangle contains `(x, y)`, or `widget` itself when no child qualifies
  but `widget` does; `nil` if `widget` itself is inactive or the point is
  outside its rectangle.
- `(dispatch-widget-event root event &optional target keymap-state)` —
  dispatches `event` along the path from `root` to `target` (default
  `root`). A widget on that path whose `widget-capture-event-p` returns true
  for `event` handles it directly and skips the rest of the path (this is
  how `modal-widget` intercepts Escape ahead of a focused descendant).
  Otherwise, each widget along the path from `target` back up to `root` gets
  a chance to handle the event — through its `widget-keymap` when it has one
  and `event` is a `key-event`, otherwise through `widget-handle-event` —
  and a handled action then propagates upward through every ancestor's
  `widget-handle-child-action`. Signals `invalid-type-error` (via
  `check-type`) if `root` is not a `widget`.
- `(application-dispatch-event application event)` — the application-level
  wrapper: routes by event type (resize triggers a backend resize and focus
  refresh; tick broadcasts to every active widget; Tab moves focus;
  mouse hit-tests and re-focuses before dispatching; everything else
  dispatches to the currently focused widget), records the result in
  `application-last-action`, and marks the application dirty first (unless
  the event is a resize, whose own dirtying happens through the layout
  pass). Returns the resulting action, or `nil`.
- `(application-step/k application event continuation)` — dispatches `event`
  (when non-`nil`), renders if `application-dirty-p`, then calls
  `continuation` with the last recorded action. `(application-step
  application &optional event)` defaults `continuation` to `#'identity`.
  `event` may be `nil` to flush a dirty frame without dispatching anything.
- `(application-start application)` — idempotent: opens the backend, enters
  the alternate screen (if `application-alternate-screen-p`), sets the
  backend title (if `application-title` is set), marks the application
  running, and renders the first frame.
- `(application-stop application)` — marks the application not running
  (does not close the backend).
- `(application-close application)` — stops, then closes the backend.
- `(call-with-application-session application continuation)` /
  `(with-application-session (application) &body body)` — starts
  `application`, calls `continuation`/`body`, and always closes the
  application afterward via `unwind-protect`, even on a non-local exit.
- `(application-run application event-source &key (eof-value :eof))` —
  drives a session end-to-end: starts the application, then repeatedly
  calls `event-source` (a zero-argument function) and steps the application
  with each result, until `event-source` returns `eof-value` or
  `application-running-p` becomes false, then closes the session. This is
  the simplest way to run a complete application against any blocking event
  source — a `terminal-event-source`, a `cl-tui-kit/testing` `event-replay`,
  or an application-defined generator. Signals `invalid-type-error` if
  `event-source` is not a function.

### Presentation widgets

- **`text-widget`** — `text-widget-text`. `(make-text-widget text &key id
  rectangle style theme role semantic-role accessible-label
  accessible-description accessible-help-text)` — `role` (default
  `:foreground`) is the theme role its style is drawn from. Read-only,
  non-interactive; `text` may be any object (coerced with `princ-to-string`
  if not already a string).
- **`box-widget`** — `box-widget-child`. `(make-box-widget child &key id
  rectangle style theme border-kind padding semantic-role accessible-label
  accessible-description accessible-help-text)` — draws a border (`kind` per
  `surface-draw-border`: `:single` default, `:double`, `:rounded`, `:ascii`)
  around `child`, inset by `padding` (default `(make-padding :all 1)`)
  inside the border.
- **`divider-widget`** — no additional public accessor beyond the base
  class. `(make-divider-widget &key (orientation :horizontal) id rectangle
  style theme semantic-role accessible-label accessible-description
  accessible-help-text)` — draws a single `─` or `│` rule across its
  rectangle. Signals `invalid-option-error` if `orientation` is neither
  `:horizontal` nor `:vertical`.
- **`button-widget`** — `button-widget-label`, `button-widget-action`.
  `(make-button-widget label &key action id rectangle style theme keymap
  (focusable-p t) (enabled-p t) semantic-role accessible-label
  accessible-description accessible-help-text)`. `action` is a function of
  one argument (the widget), an `action`, a symbol (wrapped via
  `custom-action`), or `nil` (produces a default `:activate` action).
  Activates on Enter/Return/Space or a mouse press.
- **`checkbox-widget`** — `checkbox-widget-label`,
  `checkbox-widget-checked-p`, `checkbox-widget-action`.
  `(make-checkbox-widget label &key checked-p action id rectangle style
  theme keymap (focusable-p t) (enabled-p t) semantic-role accessible-label
  accessible-description accessible-help-text)`. Toggles `checked-p` and
  fires a `:toggle` action on Enter/Return/Space or a mouse press; the
  callback contract mirrors `button-widget`'s `action` argument.
- **`progress-widget`** — `progress-widget-value`,
  `progress-widget-maximum` (default 1), `progress-widget-label`.
  `(make-progress-widget &key (value 0) (maximum 1) label id rectangle style
  theme semantic-role accessible-label accessible-description
  accessible-help-text)` — non-interactive; renders a proportionally filled
  bar. Signals `invalid-range-error` if `maximum` is negative.
- **`status-bar-widget`** — `status-bar-widget-text`.
  `(make-status-bar-widget text &key id rectangle style theme)` —
  non-interactive, single-line, styled with the `:muted` theme role.
- **`scroll-bar-widget`** — no public accessors beyond construction
  arguments (it is purely a rendering widget driven by the values passed at
  construction; there is no `scroll-bar-widget-position` setter — an
  application re-creates or re-lays-out the widget to reflect a new
  position). `(make-scroll-bar-widget &key (orientation :vertical) position
  page-size content-size id rectangle style theme)`. Signals
  `invalid-option-error` if `orientation` is neither `:vertical` nor
  `:horizontal`.

### Text entry widgets

- **`input-widget`** — single-line text entry with undo/redo, selection,
  and word-boundary editing. `input-widget-value` (a `string`),
  `input-widget-cursor` (a character index; read-only, kept clamped to
  `input-widget-value` by the widget's built-in key handling, with no
  direct setter), `input-widget-scroll-offset` (read-only scroll state that
  follows `input-widget-cursor` and the widget's rendered size, with no
  direct setter), `input-widget-placeholder`, `input-widget-selection-anchor`
  (read-only; pairs with `input-widget-cursor` to define the selected range
  — use `input-widget-clear-selection` to clear it), `input-widget-max-history`
  (default 100). `(make-input-widget &key (value
  "") placeholder id rectangle style theme keymap (focusable-p t)
  (max-history 100) semantic-role accessible-label accessible-description
  accessible-help-text)`. Signals `invalid-range-error` if `max-history` is
  not a positive integer.
  - `(input-widget-selection-start widget)`, `(input-widget-selection-end
    widget)` — both `nil` when nothing is selected. `(input-widget-selected-text
    widget)` — `""` when nothing is selected. `(input-widget-clear-selection
    widget)`.
  - `(input-widget-undo widget)`, `(input-widget-redo widget)` — pop from
    the bounded undo/redo stack (each capped at `input-widget-max-history`
    entries); a no-op when the respective stack is empty.
  - Key handling built in: arrow keys (word-wise with Ctrl/Alt), Home/End
    (also Ctrl-A/Ctrl-E), Backspace/Delete (word-wise with Ctrl/Alt,
    selection-aware), Ctrl-Z/Ctrl-Shift-Z/Ctrl-Y for undo/redo, Enter
    produces a `submit-action`, Escape a `cancel-action`. `text-input-event`
    and `paste-event` insert at the cursor (replacing any selection).
  - `(widget-cursor-position input-widget)` returns a `point` scrolled into
    view — this is what makes the terminal cursor track the edit position.
- **`textarea-widget`** (subclass of `input-widget`) — adds
  `textarea-widget-preferred-rows` (default 4), `textarea-widget-soft-wrap-p`
  (default `t`), `textarea-widget-submit-on-enter-p` (default `nil`),
  `textarea-widget-line-scroll-offset`. `(make-textarea-widget &key (value
  "") placeholder id (preferred-rows 4) (soft-wrap-p t)
  (submit-on-enter-p nil) rectangle style theme keymap (focusable-p t)
  (enabled-p t) (max-history 100) semantic-role accessible-label
  accessible-description accessible-help-text)`. Inherits `input-widget`'s
  editing, selection, and undo/redo behavior; adds Up/Down/PageUp/PageDown
  line navigation across soft-wrapped visual rows, and Enter either submits
  (when `submit-on-enter-p`) or inserts a newline. Signals
  `invalid-range-error` (via `check-type`) if `preferred-rows` or
  `max-history` is not a positive integer, `invalid-type-error` if
  `soft-wrap-p`/`submit-on-enter-p` is not a boolean.

### Choice controls

- **`radio-widget`** — `radio-widget-options`,
  `radio-widget-selected-index` (`nil` when `options` is empty; read-only,
  kept within `options`' bounds — use `radio-widget-select` to change it),
  `radio-widget-wrap-p` (default `t`). `(make-radio-widget options &key
  selected-index action wrap-p rectangle style theme keymap (focusable-p t)
  (enabled-p t) id semantic-role accessible-label accessible-description
  accessible-help-text)`. Signals `index-out-of-bounds-error` if
  `selected-index` is out of range for `options`.
  - `(radio-widget-selected-option widget)` — the option object, or `nil`.
  - `(radio-widget-select widget index)` — sets the selection and fires the
    `action` callback with `:select`. Signals `index-out-of-bounds-error` on
    an out-of-range `index`.
  - Up/Left and Down/Right move the selection (wrapping when `wrap-p`);
    Space/Enter/Return re-fires selection of the current option; a mouse
    press selects by row.
- **`select-widget`** — a combobox: closed, it shows only the selected
  option; open, it shows up to `select-widget-visible-rows` options.
  `select-widget-options`, `select-widget-selected-index` (read-only, kept
  within `options`' bounds — use `select-widget-select` to change it),
  `select-widget-open-p` (a plain read/write accessor — see the note at the
  top of the widgets section on why it stayed writable),
  `select-widget-visible-rows` (default 5).
  `(make-select-widget options &key selected-index (open-p nil)
  (visible-rows 5) action rectangle style theme keymap (focusable-p t)
  (enabled-p t) id semantic-role accessible-label accessible-description
  accessible-help-text)`. Signals `invalid-range-error` (via `check-type`)
  if `visible-rows` is not a positive integer, `index-out-of-bounds-error`
  for an out-of-range `selected-index`.
  - `(select-widget-selected-option widget)`, `(select-widget-select widget
    index)` (signals `index-out-of-bounds-error` out of range),
    `(select-widget-toggle widget)` (opens/closes, firing `:open`/`:close`).
  - Up/Left and Down/Right move the selection; Enter/Return/Space opens,
    then (when already open) confirms and closes; Escape closes without
    selecting; a mouse press on a closed control opens it, on an open
    control's row selects and closes.
- **`spinner-widget`** — an animated frame cycle (also usable as a plain
  toggle). `spinner-widget-frames` (default `("-" "/" "|" "\\")`),
  `spinner-widget-index` (read-only, kept within `frames`' bounds by
  wrapping — use `spinner-widget-tick` to advance it),
  `spinner-widget-running-p` (default `t`).
  `(make-spinner-widget &key (frames ("-" "/" "|" "\\")) (index 0)
  (running-p t) action rectangle style theme keymap (focusable-p t)
  (enabled-p t) id semantic-role accessible-label accessible-description
  accessible-help-text)`. Signals `invalid-argument-error` if `frames` is
  empty, `index-out-of-bounds-error` if `index` is outside `frames`.
  - `(spinner-widget-current-frame widget)` — the frame string at the
    current index.
  - `(spinner-widget-tick widget)` — advances to the next frame (wrapping)
    when `running-p`; bound automatically to `tick-event`. Fires the
    `action` callback with `:tick`.
  - `(spinner-widget-toggle widget)` — flips `running-p`; bound to
    Space/Enter/Return and a mouse press. Fires `action` with `:toggle`.

### Lazy list and tree

Both models query a data source through callbacks for exactly the visible
range, rather than materializing every item on every frame — the point of
"lazy" in `docs/src/guide/widgets.md`. **This is why "lazy list" in the
older text on this page was wrong to describe as a separate widget from
plain "list": every `list-widget` uses this lazy `list-model` protocol, and
likewise every `tree-widget` uses the lazy `tree-model` protocol below.**
There is no separate materialized-list widget.

- **`list-model`** — opaque; construct only through `make-list-model`.
  `(make-list-model &key count item-at key-at label-at render-item)`. `count`
  is an integer or a zero-argument function returning one; `item-at` is
  required, `(lambda (index) ...)`; `key-at` defaults to `(lambda (item
  index) item)`; `label-at` defaults to `(lambda (item index)
  (princ-to-string item))`; `render-item`, when supplied, overrides the
  displayed label independently of `label-at` (used for a row-rendering
  hook distinct from the accessibility label). Signals `invalid-type-error`
  if `count` is neither an integer nor a function or `item-at` is not a
  function, `invalid-range-error` if a literal `count` is negative.
  - `(list-model-count model)` — calls `count`; signals
    `callback-contract-error` if the callback does not return a
    non-negative integer.
  - `(list-model-item-at model index)`, `(list-model-key-at model item
    index)`, `(list-model-label-at model item index)`,
    `(list-model-render-item model item index)`.
- **`list-widget`** — `list-widget-model`, `list-widget-selected-key`
  (read-only, kept consistent with `list-widget-model` — use
  `list-widget-select-key` to change it, or `list-widget-refresh` to
  reconcile it after the model's contents change), `list-widget-offset`
  (default 0; read-only scroll state kept clamped to the visible row
  window, following the selected key and the widget's rendered size, with
  no direct setter), `list-widget-row-height` (default 1).
  `(make-list-widget model &key id rectangle style theme keymap
  selected-key (offset 0) (row-height 1) focusable-p)`. Signals
  `invalid-range-error` if `row-height` is not a positive integer.
  - `(list-widget-selected-index widget)` — the row index for the current
    `selected-key`, or `nil` for an empty model.
  - `(list-widget-select-key widget key)` — selects by key (a no-op if
    `key` is not found) and scrolls it into view.
  - `(list-widget-page-up widget)`, `(list-widget-page-down widget)` — move
    selection by one viewport height, keeping it visible.
  - `(list-widget-refresh widget)` — call after the underlying model's
    contents change, to reconcile the current selection/offset against the
    new count (falls back to clamping the offset when the previously
    selected key no longer exists).
  - `(list-widget-visible-items widget)` — only the rows the current
    viewport needs, as a list of plists (`:index`, `:item`, `:key`,
    `:label`); this is what keeps rendering lazy.
  - Built-in key handling: Up/Down (also Previous/Next), Page Up/Down, Home,
    End move the selection; Space toggles (`toggle-action`); Enter/Return
    activates (`activate-action`); a mouse press selects by row.
- **`tree-model`** — opaque; construct only through `make-tree-model`.
  `(make-tree-model &key root-count root-at key-at label-at children
  expanded-p render-item)`. `root-count`, `root-at`, `key-at`, and
  `label-at` are required (the first as an integer or zero-argument
  function, the rest as functions); `children`, when supplied, is a
  function of one node returning a `list-model`, a vector, a list, or `nil`
  (a leaf); `expanded-p` defaults to always-`nil` (fully collapsed).
  Signals `invalid-type-error` if `root-count` is neither integer nor
  function, or if `root-at`/`key-at`/`label-at` is not a function;
  `invalid-range-error` if a literal `root-count` is negative.
  - `(tree-model-root-count model)` — signals `callback-contract-error` on
    a bad callback return, same as `list-model-count`.
  - `(tree-model-root-at model index)`, `(tree-model-key-at model node)`,
    `(tree-model-label-at model node)`, `(tree-model-children model node)`,
    `(tree-model-expanded-p model node)`, `(tree-model-render-item model
    node)`.
- **`tree-widget`** — `tree-widget-selected-key` (read-only, kept
  consistent with the tree model by the widget's built-in key and mouse
  handling — use `tree-widget-refresh` to reconcile it after the model's
  contents change), `tree-widget-offset` (default 0; read-only scroll state
  kept clamped to the visible row window, following the selected key and
  the widget's rendered size, with no direct setter). `(make-tree-widget
  model &key id rectangle style theme keymap selected-key (offset 0)
  focusable-p)`. The visible row set is
  computed by a depth-first walk that only expands nodes with
  `tree-model-expanded-p` true, and — for the viewport-scoped traversal
  used during rendering — does not compute keys or labels for nodes before
  the visible range, so a lazy model still skips materialization work
  outside the viewport.
  - `(tree-widget-selected-index widget)` — visible-row index of the
    selection, or `nil`.
  - `(tree-widget-page-up widget)`, `(tree-widget-page-down widget)`,
    `(tree-widget-refresh widget)` — same contract as the list-widget
    equivalents.
  - `(tree-widget-toggle-expanded widget)` — fires a `toggle-action` whose
    payload names the selected node's key and item; the model's
    `expanded-p` callback is what an application updates in response (the
    widget does not store expansion state itself).
  - Built-in key handling: Up/Down/Page Up/Down/Home/End move the visible
    selection; Left/Right fire `:collapse`/`:expand` custom actions; Space
    toggles expansion; Enter/Return activates; a mouse press selects by row.

### Text view

- **`text-view-widget`** — `text-view-widget-text`,
  `text-view-widget-wrap-p` (default `t`), `text-view-widget-offset`
  (a line offset, default 0), `text-view-widget-search-query`.
  `(make-text-view-widget text &key (wrap-p t) (offset 0) id rectangle style
  theme keymap focusable-p semantic-role accessible-label
  accessible-description accessible-help-text)`. Signals
  `invalid-type-error` if `text` is not a string.
  - `(text-view-widget-scroll-to widget offset)` — clamps to `[0,
    max(0, line-count - height)]`. `(text-view-widget-scroll-by widget
    amount)` — relative. Both signal `invalid-type-error` (via
    `check-type`) if the argument is not an integer.
  - `(text-view-widget-find widget query &optional (start 0))` —
    case-insensitive substring search from character offset `start`,
    scrolling to the matching line and returning the match position (or
    `nil`). Signals `invalid-type-error` if `query` is not a string or
    `start` is not an integer.
  - Built-in key handling: Up/Down, Page Up/Down, Home, End scroll;
    mouse-wheel events scroll by 3 lines.

### Tabs

- **`tab-entry`** — `tab-entry-key`, `tab-entry-label`, `tab-entry-content`
  (a `widget` or `nil`), `tab-entry-enabled-p` (default `t`). `(make-tab
  label content &key key (enabled-p t))`. Signals `invalid-type-error` if
  `content` is non-`nil` and not a `widget`.
- **`tabs-widget`** — `tabs-widget-tabs`, `tabs-widget-selected-index`
  (read-only, kept within `tabs`' bounds and paired with the synced child
  content — use `tabs-widget-select` to change it).
  `(make-tabs-widget tabs &key (selected-index 0) id rectangle style theme
  keymap focusable-p semantic-role accessible-label accessible-description
  accessible-help-text)` — falls back to the first enabled tab if
  `selected-index` names a disabled or out-of-range tab.
  - `(tabs-widget-select widget index)` — no-op (returns `nil`) if `index`
    names a disabled or out-of-range tab; otherwise selects it and syncs
    `widget-children` to the new tab's content.
  - Left/Right (also `:previous-tab`/`:next-tab`) move to the nearest
    enabled tab in that direction; a mouse press on the tab header row
    selects by position; any other event is forwarded to the active tab's
    content widget.

### Menu

- **`menu-item`** — `menu-item-label`, `menu-item-action`,
  `menu-item-enabled-p` (default `t`), `menu-item-submenu` (a `menu-widget`
  or `nil`), `menu-item-key`. `(make-menu-item label &key action
  (enabled-p t) submenu key)`. Signals `invalid-type-error` if `submenu` is
  non-`nil` and not a `menu-widget`.
- **`menu-widget`** — `menu-widget-items`, `menu-widget-selected-index`
  (read-only, kept within `items`' bounds and paired with
  `menu-widget-active-submenu` — use `menu-widget-select` to change both
  together), `menu-widget-open-p` (default `t`; a plain read/write
  accessor — see the note at the top of the widgets section on why it
  stayed writable), `menu-widget-active-submenu` (read-only; see
  `menu-widget-selected-index` above).
  `(make-menu-widget items &key (selected-index 0) (open-p t) id rectangle
  style theme keymap (focusable-p t) semantic-role accessible-label
  accessible-description accessible-help-text)` — falls back to the first
  enabled item if `selected-index` is invalid.
  - `(menu-widget-select widget index)` — a no-op for a disabled or
    out-of-range index; otherwise selects the item and, if it has a
    submenu, makes that submenu the active child.
  - Up/Down move to the nearest enabled item; Escape closes; Right/Enter/Return
    opens a submenu (if the selected item has one) or activates the item;
    a mouse press selects (and activates) by row.

### Table

- **`table-column`** — `table-column-label`, `table-column-key`,
  `table-column-width` (a fixed width, or `nil` for natural sizing),
  `table-column-min-width` (default 1), `table-column-align` (`:left`
  default, `:right`, or `:center`). `(make-table-column label &key key width
  (min-width 1) (align :left))` — `key` selects a row's value for this
  column: a function of the row, an integer index into a list/vector row, a
  plist key for a plist row, or `nil` (falls back to positional). Signals
  `invalid-range-error` if `width` is supplied and negative,
  `invalid-option-error` if `align` is not one of the three keywords.
- **`table-widget`** — `table-widget-columns`, `table-widget-rows`,
  `table-widget-selected-row` (`nil`-able), `table-widget-selected-column`
  (default 0), `table-widget-row-offset` (default 0). `(make-table-widget
  columns rows &key selected-row (selected-column 0) (header-p t)
  (row-height 1) id rectangle style theme keymap (focusable-p t)
  semantic-role accessible-label accessible-description
  accessible-help-text)`. Signals `invalid-range-error` if `row-height` is
  not a positive integer.
  - `(table-widget-set-rows widget rows)` — replaces the row data, clamping
    the selection if it now falls outside the new row count.
  - `(table-widget-select-row widget row)`, `(table-widget-select-column
    widget column)` — bounds-checked; a no-op (return `nil`) on an
    out-of-range index rather than signalling.
  - Column widths are computed once per render from each column's natural
    content width (or its fixed `width`), then shrunk (from the last
    shrinkable column backward) or the last column expanded to exactly fill
    the available width.
  - Built-in key handling: Up/Down move the row selection; Left/Right move
    the column selection; Home/End jump to the first/last row; Page Up/Down
    move by one viewport; Enter/Return fires a `select-action` with the
    current `(:row :column)`; a mouse press selects the clicked cell.

### Form

- **`form-widget`** — `form-widget-fields` (a list of child `widget`s),
  `form-widget-validator`, `form-widget-errors` (populated by
  `form-widget-validate`). `(make-form-widget fields &key validator
  submit-action id rectangle style theme keymap (focusable-p nil)
  semantic-role accessible-label accessible-description
  accessible-help-text)`. `validator` is `(lambda (values form) ...)`
  returning `nil`/`t` for valid, or an error object/list of them for
  invalid; `submit-action` is `(lambda (values form) ...)`, called after
  successful validation — returning an `action` preserves it as-is, any
  other non-`nil` value becomes the payload of a `submit-action`. Signals
  `invalid-type-error` if any field is not a `widget`, or if `validator`/
  `submit-action` is supplied and not a function.
  - `(form-widget-values form)` — an alist of `(widget-id-or-position .
    value)`, reading `input-widget-value`/`checkbox-widget-checked-p`
    directly and falling back to each other field's `widget-accessibility-info`
    `:value` entry.
  - `(form-widget-validate form)` — runs `validator` (if any) and stores its
    result in `form-widget-errors`; returns true when there are no errors.
  - `(form-widget-submit form)` — validates first; on failure returns a
    `:validation-error` custom action carrying the errors instead of
    submitting. On success, calls `submit-action` (if any) and returns the
    resulting action as described above.
  - Fields are laid out vertically, each given its preferred height (or 1
    row) up to the space available; errors render below the fields in the
    `:error` theme role. Enter submits; Escape cancels; a `:validate` or
    `:submit` custom event triggers the corresponding method.

### Viewport and modal

- **`viewport-widget`** — `viewport-widget-viewport` (a `viewport`, see
  [Geometry](#geometry)). `(make-viewport-widget child &key id rectangle
  style theme keymap viewport content-width content-height focusable-p)` —
  `content-width`/`content-height` default to the child's preferred size
  (or the widget's own rectangle when there is no child). Renders `child`
  clipped to the widget's rectangle, offset by the viewport's scroll
  position. Arrow keys scroll by one cell in each direction.
- **`modal-widget`** — `modal-widget-open-p` (default `nil`),
  `modal-widget-result`, `modal-widget-close-reason`,
  `modal-widget-buttons` (a list of `widget`s), `modal-widget-outside-close-p`
  (default `nil`). `(make-modal-widget child &key id rectangle style theme
  keymap (open-p nil) focusable-p buttons (outside-close-p nil)
  semantic-role accessible-label accessible-description
  accessible-help-text)`. Signals `invalid-type-error` if `child` is
  non-`nil` and not a `widget`, or any button is not a `widget`.
  - `(modal-widget-open widget)` — opens, clears any prior result/reason,
    and re-lays-out immediately so hit-test rectangles are valid before the
    first event.
  - `(modal-widget-close widget &optional result (reason :programmatic))`.
  - Overrides `widget-active-p` (open state), `widget-interactive-children`
    (empty when closed), and `widget-capture-event-p` (captures Escape and
    a `:close` custom event while open) — this is the mechanism that keeps
    a closed modal's contents out of hit-testing and focus without removing
    them from the tree.
  - `widget-handle-child-action` closes the modal automatically when a
    descendant (the child or a button) returns `:submit`, `:cancel`,
    `:close`, or `:activate` (the last treated as a button press, closing
    with reason `:button`).
  - Dialog geometry is centered and sized from the child's preferred size
    plus a fixed button row; a mouse press outside the dialog closes it only
    when `outside-close-p` is true.

### Notifications

- **`notification`** — `notification-id`, `notification-message`,
  `notification-level` (default `:info`), `notification-expires-at`.
  `(make-notification message &key id (level :info) expires-at)`.
- **`notification-center-widget`** — `notification-center-notifications`
  (most-recent-first). `(make-notification-center &key (max-visible 5)
  (placement :top) id rectangle style theme semantic-role accessible-label
  accessible-description accessible-help-text)`. Signals
  `invalid-range-error` if `max-visible` is not a positive integer,
  `invalid-option-error` if `placement` is neither `:top` nor `:bottom`.
  - `(notification-center-push widget message &key id (level :info)
    expires-at)` — `message` may be a plain object (wrapped via
    `make-notification`) or an existing `notification`; assigns an
    auto-incrementing id when none is supplied. Returns the notification.
  - `(notification-center-dismiss widget id)` — removes by id (or by `eq`
    identity if `id` is itself a `notification`); returns true if something
    was removed.
  - `(notification-center-clear widget)` — removes all.
  - `(notification-center-tick widget &optional time)` — removes every
    notification whose `expires-at` is `<= time`; returns the count
    removed. Bound automatically to `tick-event`, which passes
    `tick-event-time`.
  - A mouse press on a visible notification dismisses it and fires a
    `close-action`.

## cl-tui-kit/ansi

An output-only ANSI backend: it consumes normalized surfaces and never
parses input, enables raw mode, or owns a terminal file descriptor. Depends
on `cl-tui-kit/core` only.

- **`ansi-backend`** (subclass of `backend`) — `ansi-backend-stream`
  (default `*standard-output*`), `ansi-backend-previous-surface` (read-only;
  the diff baseline from the last full-frame present, managed internally by
  `backend-present`), `ansi-backend-mouse-mode`,
  `ansi-backend-mouse-sgr-p`, `ansi-backend-bracketed-paste-enabled-p`,
  `ansi-backend-focus-reporting-enabled-p`,
  `ansi-backend-kitty-keyboard-flags`,
  `ansi-backend-synchronized-updates-enabled-p` — all six are read-only:
  each records a terminal mode the backend has also written an escape
  sequence for, so a raw `setf` would desynchronize the record from the
  terminal's actual state and the next disable would emit the wrong
  sequence or none at all. Change them only through the matching
  `ansi-enable-*`/`ansi-disable-*` pair documented under Terminal-mode
  controls below. `(make-ansi-backend &key stream size capabilities)` —
  `capabilities` defaults to `:truecolor` color and `:full` unicode.
- `(ansi-encode-style style &key (color-capability :truecolor))` — encodes
  `style` as a self-contained ANSI SGR escape sequence. `color-capability`
  is `:none`, `:basic`, `:256`, or `:truecolor`; a color the target
  capability cannot represent is deterministically down-converted (nearest
  ANSI-16 or nearest xterm-256 entry by RGB distance) rather than dropped.
  Signals `invalid-type-error` (via `check-type`) if `style` is not a
  `style`.
- Terminal-mode controls, each idempotent and each ending with a flush.
  Enable/disable pairs track their own enabled state, so calling either
  twice in a row is safe:
  - `(ansi-enable-mouse-reporting backend &key (mode :click) (sgr-p t))` —
    `mode` is `:click`, `:button-motion`, or `:any-motion`; `sgr-p` selects
    extended SGR 1006 encoding over the legacy form. `(ansi-disable-mouse-reporting
    backend)`.
  - `(ansi-enable-bracketed-paste backend)` /
    `(ansi-disable-bracketed-paste backend)`.
  - `(ansi-enable-focus-reporting backend)` /
    `(ansi-disable-focus-reporting backend)`.
  - `(ansi-enable-kitty-keyboard backend &key (flags 1))` /
    `(ansi-disable-kitty-keyboard backend)`. Signals `invalid-range-error`
    (via `check-type`) if `flags` is not a positive integer.
  - `(ansi-enable-synchronized-updates backend)` /
    `(ansi-disable-synchronized-updates backend)` — wraps each subsequent
    `backend-present` frame in DEC mode 2026, so a terminal that supports it
    never shows a partially updated frame.
- `(ansi-request-clipboard backend &key (selection "c"))` — a convenience
  name for `backend-request-clipboard` on an `ansi-backend`; writes an OSC
  52 query. The response arrives later as a normalized `clipboard-event`
  once the terminal's reply is fed to a `terminal-input-parser` — this
  function's return value is only the immediate request status, not the
  clipboard contents.
- `backend-present`, `backend-resized`, `backend-invalidate`,
  `backend-set-cursor`, `backend-set-cursor-visible`,
  `backend-enter-alternate`, `backend-leave-alternate`, `backend-set-title`,
  `backend-write-clipboard`, `backend-read-clipboard`,
  `backend-request-clipboard`, `backend-reset-output`, and `backend-flush`
  all have `ansi-backend` methods implementing the `backend` protocol
  documented under [Backend protocol](#backend-protocol) — `ansi-backend`
  does not export new generic function names for these, only new behavior
  on the inherited ones. `backend-present` diffs against
  `ansi-backend-previous-surface` (via `surface-diff`) and emits only the
  changed cells; a call scoped to a `:region` deliberately does not update
  that cached baseline, so a later full-frame diff cannot mistake the
  unwritten cells outside that region for having been refreshed.
  `backend-write-clipboard` signals nothing extra beyond `check-type text
  string`; `backend-request-clipboard` signals `invalid-argument-error` if
  `selection` fails validation (contains `;`, CR, LF, BEL, or ESC).

## cl-tui-kit/testing

A fake backend and supporting assertions for testing widgets and
applications without a terminal. Depends on `cl-tui-kit/core` only.

- **`test-backend`** (subclass of `backend`) — no public slots of its own;
  every accessor below is a function, not a raw slot reader, because each
  one returns a defensive copy or a derived view rather than exposing
  mutable internal state directly. `(make-test-backend &key size
  capabilities)` — `capabilities` defaults to `:truecolor`/`:full`/`:basic`
  mouse/clipboard `t`.
  - `(test-backend-frames backend)` — every presented surface, oldest
    first (each a `copy-surface` taken at present time, so later mutation
    of the live surface does not retroactively change history).
    `(test-backend-last-frame backend)` — the most recent one, or `nil`.
  - `(test-backend-operations backend)` — a chronological trace of every
    protocol call (`:open`, `:close`, `:begin-frame`, `(:present surface
    region)`, `:flush`, `(:resized old new)`, `(:cursor point)`,
    `(:cursor-visible bool)`, `:enter-alternate`, `:leave-alternate`,
    `(:title title)`, `:invalidate`) — useful for asserting not just what
    was rendered but which backend calls happened and in what order.
  - `(test-backend-emit backend event)` — pushes `event` onto
    `test-backend-recorded-events` (also readable directly); a hook for a
    test to simulate the backend "receiving" input to later replay.
  - `(test-backend-event-replay backend &key (eof-value :eof))` — wraps
    `test-backend-recorded-events` in a fresh `event-replay` (below).
  - `(test-backend-reset backend)` — clears frames, recorded events, and
    the operation trace (does not change backend state/size/capabilities).
- **`event-replay`** — `event-replay-events`, `event-replay-index`,
  `event-replay-eof-value`. `(make-event-replay events &key (eof-value
  :eof))` — a deterministic, one-shot event reader suitable as the
  `event-source` argument to `application-run` in a test. Signals
  `invalid-type-error` if `events` is not a list or contains a non-`event`.
  - `(event-replay-next replay)` — the next event, or `eof-value` once
    exhausted. `(event-replay-reset replay)` — rewinds to the first event.
  - `(event-replay-exhausted-p replay)`, `(event-replay-remaining-count
    replay)`.
- `(surface-equal-p left right)` — structural equality of two surfaces
  (dimensions and every cell), independent of `eq`/dirty-region state.
- `(surface-cell-string object)` — `cell-content` for a `cell`,
  `surface-string` for a `surface` — one function for either granularity of
  assertion.
- `(assert-surface-text surface expected)` — asserts `(surface-string
  surface)` equals `expected`; on mismatch, signals
  `assertion-failed-error` (see
  [Conditions](conditions.md#testing-assertion-failed-error-cl-tui-kittesting));
  returns `t` on success.

## cl-tui-kit/tty (experimental)

Optional integration with nerima-lisp's `cl-tty-kit`, providing
terminal-size discovery and a synchronous input runtime. **Not covered by
the v1.0.0 stability promise**; see [API Stability](../project/api-stability.md)
for the policy.
Loading `cl-tui-kit/core`, `/layout`, `/widgets`, `/ansi`, or `/testing`
never requires this system or an interactive terminal; only code that
explicitly depends on `cl-tui-kit/tty` pulls in terminal lifecycle side
effects.

- **`tty-backend`** (subclass of `ansi-backend`). `(make-tty-backend &key
  stream (file-descriptor 0) size capabilities)` — `capabilities` defaults
  to `:truecolor`/`:full`; falls back to `size` (or 80×24) if terminal-size
  discovery on `file-descriptor` fails or returns an implausible size.
  - `(tty-backend-refresh-size backend)` — re-queries terminal size and, if
    it changed, calls `backend-resize`.
- **`tty-runtime`** — a synchronous, blocking terminal input runtime, kept
  deliberately separate from `tty-backend`'s (output-only) ANSI writing.
  `tty-runtime-input-stream` (default `*standard-input*`),
  `tty-runtime-file-descriptor` (default 0), `tty-runtime-parser` (a
  `terminal-input-parser`), `tty-runtime-read-size` (default 4096),
  `tty-runtime-raw-mode-p` (whether `start` should enable raw mode; default
  `t`), `tty-runtime-close-input-p` (whether `stop` should close the input
  stream; default `nil`), `tty-runtime-eof-value` (default `:eof`),
  `tty-runtime-started-p`, `tty-runtime-raw-mode-enabled-p`,
  `tty-runtime-input-closed-p`, `tty-runtime-eof-p`, `tty-runtime-last-error`.
  `(make-tty-runtime &key (input-stream *standard-input*)
  (file-descriptor 0) (parser (make-terminal-input-parser)) (read-size
  4096) (raw-mode t) (close-input-p nil) (eof-value :eof))`. Signals
  `invalid-type-error` (via `check-type`) on a malformed
  `input-stream`/`file-descriptor`/`parser`/`read-size`/`raw-mode`/
  `close-input-p`.
  - `(tty-runtime-start runtime)` — idempotent; enables raw mode (if
    `raw-mode-p`) via `cl-tty-kit:enable-raw-mode`. Signals
    `tty-runtime-error` (see
    [Conditions](conditions.md#tty-runtime-error-cl-tui-kittty)) if the
    input stream was already closed, or if the runtime already reached EOF
    (call `tty-runtime-reset` first).
  - `(tty-runtime-stop runtime)` — disables raw mode (if it was enabled) and
    closes the input stream (if `close-input-p`), collecting the first
    cleanup failure into `tty-runtime-last-error` and re-signalling it
    after both cleanup steps have been attempted, rather than aborting the
    second step because the first failed. `(tty-runtime-close runtime)` is
    a documented alias for `tty-runtime-stop`.
  - `(tty-runtime-reset runtime)` — clears parser and EOF state so an open
    stream can be reused. Signals `tty-runtime-error` if the runtime is
    still running (stop it first) or its input stream was already closed.
  - `(tty-runtime-next-event runtime)` — blocking; returns the next
    normalized event, or `tty-runtime-eof-value` at end of input. Starts
    the runtime automatically on first call.
  - `(tty-runtime-poll runtime)` — non-blocking; returns `(values events
    status)`, where `status` is `:events` (complete events ready), `:pending`
    (input consumed but an escape sequence is incomplete), `:no-data` (the
    stream has nothing available right now), or `:eof`.
  - `(tty-runtime-event-source runtime)` — returns a zero-argument reader
    function suitable for `make-terminal-event-source`, bridging this
    runtime into the core's event-source protocol.
  - `(call-with-tty-runtime runtime continuation)` /
    `(with-tty-runtime (runtime) &body body)` — starts `runtime`, calls
    `continuation`/`body`, and always stops the runtime afterward via
    `unwind-protect`.
- `tty-runtime-error` — signalled by the lifecycle operations above; a
  subclass of core's `lifecycle-error`, defined here rather than in
  `cl-tui-kit/core` specifically because this tier is not SemVer-frozen (see
  [Conditions](conditions.md#tty-runtime-error-cl-tui-kittty) for the full
  rationale and its slots).

## cl-tui-kit/codec (experimental)

Optional integration with nerima-lisp's `cl-codec-kit`, for a backend or
application that explicitly needs UTF-8 octets rather than Lisp strings.
**Not covered by the v1.0.0 stability promise**; see [API Stability](../project/api-stability.md).
Two exports total.

- `(string-to-utf8-octets string &key (start 0) end (errorp t))` — encodes
  `string` (or the `start`/`end` substring) as UTF-8 octets via
  `cl-codec-kit:string-to-octets`. `errorp` is passed through to the codec
  library unchanged.
- `(write-utf8 string stream &key (start 0) end (errorp t))` — encodes and
  writes to `stream` (which must accept `(unsigned-byte 8)` elements) via
  `write-sequence`; returns the octets written. Does not change stream
  modes or terminal state.
