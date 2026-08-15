# Quality Gates

## Code and behavior

The ordinary test command must select a non-empty suite and report failures
or errors through its exit status. Tests cover geometry, surfaces, text
width, styles, keymaps, layout, focus, lazy models, widgets, ANSI capability
fallback, structured frames, event replay, resize behavior, and the optional
TTY and codec integrations.

Coverage is measured separately because a successful test run does not prove
that every source path was instrumented or executed. Full coverage remains a
target; the coverage report must be inspected rather than inferred from a
successful process exit. The SB-COVER runner measures executable project
sources under `src/`, excludes only package/umbrella declarations and the
static Unicode range table, and rejects both an empty test plan and an empty
instrumented source set. CI runs it in a Linux Nix development environment;
the regular flake check remains the behavior and documentation gate.

The flake declares `x86_64-linux` only. On any other host `nix flake check`
reports `The check omitted these incompatible systems: x86_64-linux`, runs
nothing, and exits zero — a pass that verifies nothing. Read the warning
line, not the exit status, and treat CI as the authoritative gate when
developing on another platform.

### Coverage ratchet

The coverage runner (`t/runner.lisp`) accepts two environment variables,
`CL_TUI_KIT_MIN_EXPRESSION_COVERAGE` and `CL_TUI_KIT_MIN_BRANCH_COVERAGE`,
each an integer percentage from 0 to 100. When set, cl-weave fails the run
if measured coverage falls below either floor. CI's `coverage` job wires
these in as a ratchet: the floor may only move up as coverage improves,
never down to turn a red run green.

The floor is defined once, in the `env:` block at the top of
`.github/workflows/ci.yml`. It is set to a measured value taken from this
job's own output, kept a little under the measurement so a property test's
generator drawing a different sample cannot turn a real pass red.

Either value may be set back to the sentinel `UNSET` to re-measure. While
either is `UNSET`, the coverage job runs without enforcing a threshold — so
the true numbers are printed — and then fails outright with an actionable
message. That is how the floor was first obtained, and it is deliberate: a
floor of `0` would look like an active gate while accepting any coverage
percentage, which is worse than no gate because it reads as verified when it
verifies nothing.

To raise the floor:

1. Run `nix develop --command sbcl --script run-coverage.lisp` (or read the
   `coverage` job's log in CI).
2. Read the printed `Source coverage: expressions X/Y, branches A/B` line.
3. Set `CL_TUI_KIT_MIN_EXPRESSION_COVERAGE` and
   `CL_TUI_KIT_MIN_BRANCH_COVERAGE` in `.github/workflows/ci.yml` to
   `floor(100*X/Y)` and `floor(100*A/B)` respectively, or lower, to leave
   headroom. Commit the change.

## Documentation

The MkDocs configuration uses strict mode. Every page listed in the
navigation must exist, and warnings are treated as build failures.

When MkDocs is available directly, build the site with:

    mkdocs build --strict -f docs/mkdocs.yml

The Nix flake also declares docs.root so the project-level check can build the
documentation with the same source tree.

## Boundaries

Documentation should preserve these project contracts:

- the core remains independent of terminal lifecycle and PTY management;
- integrations remain optional ASDF systems;
- widgets return semantic actions instead of performing domain side effects;
- rendering and text layout remain cell-aware and deterministic;
- examples and tests remain usable without an interactive terminal.
