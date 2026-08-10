# Events and Keymaps

## Normalized events

Application code consumes normalized events rather than backend-specific raw
bytes. The core event family includes key, text-input, paste, resize, mouse,
focus, clipboard, tick, and custom events.

The incremental terminal input parser accepts split input and handles UTF-8,
CSI key and mouse sequences, Kitty keyboard events (including repeat and
release phases), modifyOtherKeys, SGR and X10 mouse reports, focus changes,
bracketed paste, and OSC 52 clipboard responses. OSC sequences accept BEL or
ST terminators, validate Base64 strictly, and report malformed input as a
custom event. Stream event sources provide synchronous readers; terminal
ownership remains an integration responsibility.

## Keymaps

Keymaps support modifiers, multi-key sequences, prefixes, parent keymaps,
modes, and overlays. An unhandled event can propagate to a parent keymap.
Applications decide their own prefix timeout policy.

The mode-keymap and vi-like-keymap helpers are opt-in composition tools. They
do not impose a particular editing model on every application.

## Actions and dispatch

Widgets can return semantic actions such as activate, cancel, submit, move,
select, toggle, open, close, or custom-action. The application interprets
these actions and performs any domain side effect.

Event dispatch can walk from a target widget through its ancestors. Composite
widgets can intercept child actions before they reach the application. The CPS
helpers make continuation boundaries explicit without creating a hidden event
loop, thread, or sleep.
