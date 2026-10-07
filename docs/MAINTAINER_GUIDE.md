# `polytropos` Maintainer Guide & Engineering Governance

**Audience:** Maintainers, subsystem leads, and autonomous AI coding assistant drivers.  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md)  
**Newbie Guide:** [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md)  

---

## 1. Zero-Contamination Doctrine

`polytropos` enforces a strict isolation boundary between development tooling and library code:

1. **Zero Cabal Contamination:** Assistant tooling (`tricorder`, `contextful`, `ast-grep`, `hasktags`, `open-kioku`, `codegraph`) must **never** be added as dependencies to `cabal.project` or the `.cabal` files of `packages/`.
2. **Out-of-Process Execution:** All assistant tooling operates strictly out-of-process via standard POSIX binaries, stdio IPC, or JSON-RPC (MCP).
3. **Pristine Core Builds:** Any contributor cloning `polytropos` must be able to build and pass tests under the **Tier 0 POSIX Baseline** (`cabal build all`, `cabal test all` on GHC 9.14.1 / Cabal 3.18) without any background daemons or external tools installed.

---

## 2. Multi-Package Architecture & Scope

The repository layout is governed by [`docs/registers/PACKAGES.md`](registers/PACKAGES.md):

| Path | Purpose |
|---|---|
| `packages/polytropos-core` | Core library: `Rep`, `RowRep`, `Row`, `SumRow`, slot indexing, projection, mutation, and evidence classes (`RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`, `ConstructorIndex`). |
| `packages/polytropos-plugin` | GHC Typechecker Plugin (`Polytropos.Plugin`): solves row constraints and synthesizes literal dictionary method bodies. Contains the `polytropos-plugin-smoke` test suite. |
| `benchmark/variants` | Empirical compile-time measurement harness comparing plain records, plain sums, type-level searched rows, and plugin-synthesized literal rows. Kept outside `cabal.project` to preserve isolated `-O0` execution. |

---

## 3. GHC Typechecker Plugin Engineering Invariants

1. **Literal Evidence Only:**
   The plugin must emit literal constant indices and synthesized dictionary method bodies directly in GHC Core. It must **never** perform type-level list induction or typeclass search at runtime; doing so triggers the $O(N^{2.8})$ compile-time bottleneck that the project exists to avoid.
2. **Selector Mangling Safeguards:**
   Avoid GHC's internal record selector name mangling (`$sel:...`). In `Polytropos.Core`, `Rep` and `RowRep` export explicit top-level accessor functions (`repTag`, `repVals`, `unRowRep`) rather than record fields so interface lookups in the plugin resolve cleanly.
3. **GHC 9.14 Symbol Resolution:**
   In `base-4.22`, core classes and functions live in `GHC.Internal.*`. The plugin references wired-in module names (`gHC_CLASSES`, `gHC_INTERNAL_SHOW`, `gHC_INTERNAL_BASE`) and uses `resolveImport` for Cabal-hashed package unit IDs.

---

## 4. Documentation Precedence & The Two-File Loop

1. **Code Wins, Notes Corrected:**
   Per `DOC_STRATEGY.md` §4: code wins at runtime, but design notes must be updated in the same change set. Blessed notes are never granted advisory status.
2. **Two-File Loop:**
   Update `STATE.md` before ending or resetting a session. Fresh sessions always initialize from `PLAN.md` and `STATE.md`.
3. **Corpus Budget:**
   `AGENTS.md` carries a ~4 KB context budget. Add links into canonical documents (`docs/notes/`, `docs/registers/`, `.agents/`), never inline architectural restatements.

---

## 5. Git Commit & Attribution Protocol

1. **Commit Hygiene:**
   Commits should be local and frequent, with descriptive-imperative subjects and HEREDOC bodies explaining the rationale.
2. **Attribution Schema (`sarutahiko` convention):**
   ```
   Assisted-by: <Tool> (<Provider> / <Model>)
   Orchestrated-by: <Engine>
   ```
   Enforced mechanically by [`.githooks/commit-msg`](../.githooks/commit-msg).
3. **Legal Safeguard:**
   Never use `Co-authored-by:` or `Signed-off-by:` for AI tools. An assistant cannot certify the Developer Certificate of Origin.
