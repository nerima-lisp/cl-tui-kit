# Terminal Integration

The pure systems leave terminal lifecycle and byte-level integration to
explicit adapters.

## ANSI output

cl-tui-kit/ansi provides an output backend built on the core surface and diff
protocol. It emits ANSI output and uses backend capabilities for graceful
color degradation. It also manages opt-in terminal modes for SGR/X10 mouse
reports, bracketed paste, focus reporting, Kitty keyboard events, and
synchronized updates. `backend-reset-output` restores every mode enabled by
the backend before it closes.

Clipboard access uses the OSC 52 protocol. `backend-request-clipboard` (or
the ANSI convenience function `ansi-request-clipboard`) writes an asynchronous
query; the response is normalized by the core input parser as a
`clipboard-event`. The ANSI backend does not own an input thread or parser.

## TTY runtime

cl-tui-kit/tty adds terminal-size discovery and a synchronous input runtime.
The runtime can enable raw mode when started and restores it when stopped or
closed. next-event blocks for input; poll returns immediately when no
character is available.

The runtime does not create a hidden thread, background poller, or PTY. It
owns the lifecycle of the configured input stream and raw-mode descriptor
according to its options.

## UTF-8 codec

cl-tui-kit/codec provides explicit UTF-8 octet conversion for applications or
backends that need binary output. The core continues to represent text as Lisp
strings and cell content.

## Choosing an adapter

An application can use the core and testing systems only, use the ANSI backend
with its own stream lifecycle, or load both tty and codec adapters for a
terminal application. These choices do not alter the dependency boundary of
the pure core.
