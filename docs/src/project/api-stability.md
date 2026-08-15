# API Stability

cl-tui-kit uses two stability tiers, applied at the level of ASDF systems.
The tier an export belongs to is decided by which system defines it, not by
any per-symbol annotation.

## Stable tier

`cl-tui-kit/core`, `cl-tui-kit/layout`, `cl-tui-kit/widgets`,
`cl-tui-kit/ansi`, and `cl-tui-kit/testing` are stable. Every symbol these
five systems export is covered by SemVer, including every `event-loop-*`
symbol that `cl-tui-kit/core` exports for the deterministic event loop.
These systems have no dependency outside this repository and Quicklisp, so
their release cadence is under this project's control alone.

## Experimental tier

`cl-tui-kit/tty` and `cl-tui-kit/codec` are experimental. Their exports can
change in a minor or patch release without following the deprecation
procedure below. Each depends on a sibling nerima-lisp library —
`cl-tty-kit` and `cl-codec-kit` respectively — that is not published to
Quicklisp or Ultralisp and is versioned on its own schedule. Freezing these
two systems under the same SemVer contract as the stable tier would tie
cl-tui-kit's version number to decisions made in those sibling repositories,
which this project does not control. Keeping them experimental until that
dependency settles avoids promising a stability guarantee this project
cannot back.

## Not part of the versioned API surface

`cl-tui-kit`, the umbrella system, aggregates the stable tier through `:use`
and exports no symbols of its own (see `src/package.lisp`); loading it is
equivalent to loading the five stable-tier systems together, so it carries
no separate stability contract. `cl-tui-kit/examples` and the
`cl-tui-kit/tests` and `cl-tui-kit/test` systems are development and
verification aids, not libraries other code is expected to depend on, and
are out of scope for this document.

## What SemVer means here

Starting at the 1.0.0 release, a change to a stable-tier export is breaking,
and requires a major-version bump, when it does any of the following:

- removes an exported symbol, or removes an existing keyword or required
  argument from an exported function, macro, or structure constructor;
- adds a new required (non-optional, non-keyword) argument to an exported
  function or macro;
- changes the type of an exported function's return value in a way an
  existing caller could observe (for example, returning a list where it
  returned a single value, or vice versa);
- changes which condition type is signalled for a given error case, or
  removes a condition type that was part of the documented protocol;
- narrows the range of input a function accepts (for example, rejecting a
  value type or value range that a prior release accepted without error).

Adding a new export, a new optional or keyword argument with a default that
preserves prior behavior, widening accepted input, or fixing a function to
match its documented behavior are not breaking changes under this policy.

## Read-only accessors for internal state

A stable-tier struct or class may export a reader for a slot that holds
process state the owning subsystem maintains for its own correctness — a
diff-rendering baseline, a parser's escape/UTF-8 buffers, a keymap's
pending-prefix timer — without exporting a `setf` for it. This is
deliberate: an external `setf` on that slot could desynchronize it from an
invariant the owning code maintains internally (for example, `ansi-backend`
expects its diff baseline to change only through the frames it has
presented). Each such reader's docstring names the supported way to change
the underlying state instead — a dedicated mutator such as
`surface-set-clip`, or a reset function such as `reset-keymap-state` or
`terminal-input-parser-reset`.

**Deciding whether a new accessor falls under this rule.** It does when some
sanctioned function maintains an invariant behind the slot that a raw writer
would bypass. In practice that invariant takes one of three shapes:

- a bounds check — the slot holds an index or key that a sanctioned function
  keeps within the bounds of a collection it also reads, so a raw write
  could point it somewhere every other reader of that slot gets wrong;
- a paired update — the slot is kept synchronized with another slot by the
  same function, so writing it alone would leave the pair inconsistent;
- a real side effect — the slot records something the toolkit has already
  done elsewhere, such as an escape sequence written to the terminal or a
  resource already opened, so a raw `setf` would desynchronize the record
  from that action.

If none of the three applies, an ordinary read/write accessor is the right
shape, and that is a deliberate choice, not an oversight: the slot is
storage the caller is meant to assign directly, with no sanctioned
function's invariant behind it for a raw writer to bypass. Making such a
slot read-only would add friction without a matching safety.

The codebase expresses this in two shapes:

- A `defstruct` slot renamed with a `%` prefix, excluded from the exported
  accessor name, with the public reader defined as an ordinary `defun`. For
  example, `terminal-input-parser`'s `%buffer` slot is never exported;
  `terminal-input-parser-buffer` is a `defun` that returns a defensive copy
  of it, and the slot can only be cleared — in a way that keeps the
  parser's other buffers consistent — through `terminal-input-parser-reset`.
- A `defclass` slot declared with `:reader` and a separate, unexported
  `:writer (setf %name)`. For example, `backend`'s `state` slot is declared
  with `:reader backend-state` and `:writer (setf %backend-state)`; only
  `backend-open`, `backend-close`, and `backend-fail` call that `setf`
  form, so an external caller only ever observes `backend-state` change
  through the lifecycle those functions enforce.

Because only the read behavior is part of the documented contract, the
representation behind a read-only accessor — which slot backs it, how it is
stored — stays free to change within a major version without that being a
breaking change under the policy above.

This section states the rule the toolkit follows, not a claim that every
accessor onto internal state already conforms to it. Accessors are exposed
read-only where the toolkit maintains an invariant behind the slot they
read, converted as that invariant is identified rather than in one pass
across the whole codebase; consult the accessor's own docstring, not this
page, for whether a given symbol currently accepts `setf` and whether it
returns the live internal object or a defensive copy.

## Deprecation procedure

A stable-tier export scheduled for removal or a breaking change is marked
deprecated first, in the release that introduces the replacement it should
be migrated to. Marking deprecated means: the export's docstring states the
deprecation and names its replacement, and the release's CHANGELOG entry
lists it under a "Deprecated" heading.

A deprecated export keeps its existing behavior for the rest of its major
version's minor releases; it is not removed in a patch release, and it is
not removed in the same minor release that deprecates it. It is removed no
earlier than the next major-version release. For a single-author project
without a support contract to honor, this is the whole policy — there is no
separate long-term support branch and no extended maintenance window beyond
what the next major release schedule already provides.

## Promoting an experimental export to stable

`cl-tui-kit/tty` or `cl-tui-kit/codec` moves to the stable tier when its
sibling dependency is judged stable enough that this project is willing to
carry its own SemVer commitment on top of it. Promotion is decided by the
maintainer and recorded in the CHANGELOG entry for the release it takes
effect in. Promotion does not itself change any already-stable export, so it
can ship in a minor release; from that release forward, the promoted
system's exports follow the same breaking-change and deprecation rules as
the rest of the stable tier.

## Authoritative package boundary

`src/package.lisp` is the single authoritative definition of what each
system exports. A symbol is part of the public API if and only if it appears
in that file's `:export` list for a stable-tier or experimental-tier
package; anything reachable only through an internal package reference is
not covered by this document, whatever tier the file that defines it belongs
to.
