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
successful process exit.

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
