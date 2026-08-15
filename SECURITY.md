# Security Policy

## Scope

cl-tui-kit is a rendering and interaction library, not a terminal emulator,
multiplexer, PTY runtime, or scrollback store (see the Design boundaries
section of [README.md](README.md)). It has no network stack, no credential
handling, and no process supervision. The realistic threat surface is
therefore narrow and concentrated in code that parses or renders data an
application received from outside its own control:

- Untrusted terminal input parsed by the input parser in
  `src/input-parser-model.lisp`, `src/input-parser-encoding.lisp`,
  `src/input-parser-sequences.lisp`, and `src/input-parser.lisp`.
- OSC 52 clipboard responses parsed in `src/ansi.lisp`.
- Untrusted text rendered through the cell-width logic in `src/text.lisp`.

A finding in one of these areas — for example, a crafted escape sequence or
clipboard response that causes unbounded buffering, an infinite loop, or
memory growth rather than a clean parse failure — is in scope. A finding
that requires an application to already trust its own domain state, or that
concerns a system outside this repository (an ASDF client, an SBCL
installation, a sibling nerima-lisp package such as `cl-tty-kit`), is
outside this project's scope; report it to that project instead.

## Supported versions

The 1.x series is supported. Only the stable-tier systems
(`cl-tui-kit/core`, `/layout`, `/widgets`, `/ansi`, `/testing`) carry a
SemVer stability guarantee; `cl-tui-kit/tty` and `cl-tui-kit/codec` are
experimental and may change between minor releases. A security fix targets
the latest 1.x release.

## Reporting a vulnerability

Report a suspected vulnerability privately through GitHub's [private
vulnerability reporting][ghsa] for this repository
(`https://github.com/nerima-lisp/cl-tui-kit/security/advisories/new`), rather
than opening a public issue. Include the Common Lisp implementation and
version, the system loaded, the smallest reproducing frame or event
sequence, and the command that was run — the same information requested for
an ordinary bug report in README.md's Support section.

This project is maintained by a single author on a best-effort basis. There
is no service-level agreement on response time; expect an initial
acknowledgement before a fix timeline is discussed, and expect the timeline
itself to depend on severity and reproducibility. Coordinated disclosure is
preferred: please allow a fix to land before any public write-up.

[ghsa]: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability
