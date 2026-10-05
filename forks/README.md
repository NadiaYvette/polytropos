# forks/

Packages kept close to upstream because we want their fixes. Empty by design.

A package belongs here only if it is still *theirs* in any meaningful sense:
we contribute patches upstream, we take releases, and the local copy exists
solely to pin a revision that suits us. That is a small set — most things we
touch become `../ports/` instead, because changing the API to use polytropos
rows ends any prospect of a clean merge.

Rules for anything here:

- **Never** added to the root `cabal.project`. A fork is built by its own
  project, from its own checkout; if the root build depends on it, it is not a
  fork, it is a port.
- Recorded in `../docs/registers/PACKAGES.md` with class `fork` and the pinned
  revision.
- **Not** vendored as a git submodule. See `../docs/notes/PROVENANCE.md` for
  why: submodule friction scales with exactly the rate we intend to work at,
  and attribution depends on retaining a notice, not on preserving history. If
  upstream history is genuinely wanted, `git subtree add` keeps it in one
  repository.