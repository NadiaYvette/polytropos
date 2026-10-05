# ports/

Libraries retrofitted to run on polytropos rows. Empty by design.

A package belongs here when it started as someone else's code and has since
diverged far enough that merging upstream is no longer possible — which is the
normal outcome once the API changes to use `Row`. It then becomes *our*
package with *our* name, carrying their copyright notice only in files where
code was actually copied.

This is deliberately **not** a directory of git forks. A fork implies a
two-repository tax and a merge policy, and for a genuine port the merge is
dead on arrival. See `../docs/notes/PROVENANCE.md` for the reasoning and
`../docs/registers/PACKAGES.md` for the register.

Before a port lands:

1. Register it in `../docs/registers/PACKAGES.md` with class `port`.
2. Add the upstream and its holders to `../THIRD_PARTY.md`.
3. Add a `Ported from:` section to the port's own `LICENSE`.
4. Add the package here to the root `cabal.project`'s `packages:` list — it is
   already covered by the `packages/*/` glob only for `packages/`, so a port
   needs its own entry.