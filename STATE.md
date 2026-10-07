# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Phase 1 decisions all made. Phase 2 sketching done. Phase 3 (the plugin) in progress.
Both packages build cleanly on GHC 9.14.1 and all tests pass:
- `polytropos-core` passes all 25 tests (representation, indexing, mutation, projection, matching).
- `polytropos-plugin-smoke` passes all 3 tests with `-fplugin=Polytropos.Plugin` (no handwritten instances: `RowEq` reflexive, `RowEq` mismatch detection, and `RowShow` rendering `R2`).

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `Row`, `SumRow`, `Rep`,
  `RowType`, `RowFlavour`, `RowRep`, `HandlerType`, `ResultType`,
  `productRep`, `injectRep`, `fieldAt`, `setFieldAt`, `projectRep`, `matchRep`,
  `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`, `ConstructorIndex`,
  `DictAny`, `noInlineUnsafeCo`, with `repTag`, `repVals`, `unRowRep` top-level accessors
- `packages/polytropos-core/test/Main.hs` — 25 tests; specification of representation
  semantics and literal evidence shapes
- `packages/polytropos-plugin/polytropos-plugin.cabal` — plugin package with
  `ghc-tcplugin-api` dependency and smoke test suite
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — TcPlugin that solves:
  * `FieldIndex` and `ConstructorIndex` by literal Int/Word index calculation
  * `RowEq` and `RowShow` on literal product rows by synthesizing Core AST method bodies
    reading payload slots from `repVals` via `indexSmallArray` and chaining equality / show calls
- `packages/polytropos-plugin/tests/smoke/Main.hs` — smoke test suite verifying
  typechecker plugin generation of `RowEq` and `RowShow` dictionaries for `R2`
- `docs/NEWBIE_GUIDE.md` — quickstart and token-conservation workflow guide
- `docs/MAINTAINER_GUIDE.md` — engineering governance and zero-contamination doctrine
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `docs/notes/DESIGN_REVIEW_CLAUDE-OPUS-4.6.md` — comprehensive design review,
  architectural audit, and ecosystem deployment assessment from the Claude Opus 4.6
  perspective
- `docs/notes/PHASE2_SKETCH.md` — Phase 2 sketch (all refinements resolved)
- `docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md` — architectural design and roadmap
  for hardware-vectorized Copy-on-Write updates, batched updates, and transient builders
- `docs/notes/SATELLITE_INTERFACES_DESIGN.md` — architectural strategy and interface
  design for 12 satellite packages spanning optics, serialization, databases, and testing
- `docs/task_packets/` — 19 structured task packets for progressive implementation by
  autonomous executors (`task-01` through `task-19`):
  * Phase 3 Core: `task-01` through `task-07` (CoW updates, batch updates, plugin sum solving,
    `HasField`, `OverloadedRecordUpdate`, consumer surface, generics)
  * Phase 4A Optics Satellites: `task-08` (`optics`), `task-09` (`microlens`), `task-10` (`lens`)
  * Phase 4B Serialization Satellites: `task-11` (`aeson`), `task-12` (`cbor`), `task-13` (`cassava`)
  * Phase 4C Database Satellites: `task-14` (`beam`), `task-15` (`hasql`), `task-16` (`rel8`), `task-17` (`persistent`)
  * Phase 4D Schema & Testing Satellites: `task-18` (`openapi3`), `task-19` (`quickcheck`)
- `scripts/tasks/` — deterministic test verification scripts for task packet gates (`task-01` through `task-19`)
- `bin/yamaarashi-exec` & `.agents/skills/yamaarashi/SKILL.md` — runner script and
  skill for executing task packets in isolated worktrees with SQLite tracking
- `benchmark/variants/` — the four-arm compile-time harness the design rests on
- `docs/registers/PACKAGES.md`, `docs/notes/PROVENANCE.md`, `THIRD_PARTY.md` —
  layout rules, licence obligations, attribution index
- `.agents/rules/` — subdivided AI coding assistant operational rules:
  `commit-attribution.md`, `code-navigation.md`, `compiler-verification.md`,
  `documentation-precedence.md`, and `plugin-invariants.md`

## What is deliberately missing

- `RowEqSum` / `RowShowSum` constraint solving — synthesizing sum row equality
  and show bodies matching on constructor tags and reading sum payloads (`task-03`).
- Arbitrary field type dictionary resolution — currently `RowEq` and `RowShow`
  resolve dictionaries for known wired-in/base types; generalized dictionary lookup across module boundaries queued in Phase 4.
- Row open/extension polymorphism handling beyond literal closed lists (Option A baseline complete).

## Next action

- Execute `task-01-field-update-cow.yaml` via `bin/yamaarashi-exec run` to implement
  hardware-vectorized Copy-on-Write `setFieldAt` and eliminate list allocations.
- Follow sequential sequence through `task-19`.
