## Summary

<!-- What changed and why. -->

## API stability

<!--
Does this change a stable-tier export (cl-tui-kit/core, /layout, /widgets,
/ansi, /testing)? If so, it needs a major version bump and a CHANGELOG.md
entry. Experimental-tier exports (cl-tui-kit/tty, cl-tui-kit/codec) may
change in a minor release. See CONTRIBUTING.md.
-->

- [ ] No stable-tier export was added, removed, renamed, or changed.
- [ ] A stable-tier change is documented in `CHANGELOG.md` with a
      version bump, or this PR is explicitly marked as a breaking change.

## Checks

<!-- See CONTRIBUTING.md for what each command covers. -->

- [ ] `nix flake check` passes, or (outside Nix) `sbcl --script run-tests.lisp`
      passes and selected a non-empty test suite.
- [ ] `sbcl --script run-coverage.lisp` passes and the coverage report was
      inspected, for a behavior change.
- [ ] `nix fmt` reports no diff.
- [ ] `paredit inspect check` reports no structural issues on any Common
      Lisp file touched (see CONTRIBUTING.md for the `nix run` form).
- [ ] The relevant page under `docs/src` is updated, for a public system
      or protocol change.

## Design boundaries

- [ ] Widgets return semantic actions; no domain side effects were added
      to widget or layout code.
- [ ] The core remains independent of terminal lifecycle and PTY
      management; integrations remain optional ASDF systems.
