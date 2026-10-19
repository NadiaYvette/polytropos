# polytropos — Plan

Canonical roadmap. The operational frontier lives in `STATE.md`.

## Milestone 1 — skeleton (current)

- [x] Row vocabulary for products and sums (`Row`, `SumRow`)
- [x] `Rep`: tag + `SmallArray` payload, one representation for both shapes
- [x] Construction, access, injection, projection, elimination primitive
- [x] Evidence classes (`RowEq`, `RowShow`) with hand-written test instances
- [x] Design note with decisions, costs, and open questions

## Milestone 2 — semantics before machinery
 
Settle design note §4 and §7 **before** writing the plugin, because the answers
can change the row shape:
 
- [x] Q1 eliminator result type and handler-result combination (hybrid monadic coproduct in PHASE2_SKETCH.md)
- [x] Q2 widening check: type-level evidence with runtime bounds check elision (PHASE2_SKETCH.md)
- [x] Q3 row-index `Rep`, or add a row-carrying wrapper beside the erased one (`RowRep` Case 3 wrapper adopted)
- [x] Field update efficiency architecture (`docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md`)
- [x] Implement CoW updates, batched updates, and transient builders (`task-01`, `task-02`)
- [x] `OverloadedLabels` / record-dot / record-update instance surface (`task-04`, `task-05`)
- [x] Deriving (nominal products/sums) and generics (`task-07`)
 
## Milestone 3 — the plugin
 
Design note §6, in order:
 
- [x] Field name → literal slot index (solves `FieldIndex` constraints)
- [x] Constructor name → literal tag (solves `ConstructorIndex` constraints)
- [x] Plugin infrastructure: tcPluginInit looks up names from Polytropos.Core, GHC.Classes, GHC.Show, GHC.Base and stores in PluginState
- [x] RowEq/RowShow/RowEqSum/RowShowSum solvers walk rows with types (walkRowWithTypes, walkSumRowWithTypes)
- [x] Core AST method synthesis for `RowEq` and `RowShow` on literal products (smoke tests pass)
- [x] Synthesize Core AST for `RowEqSum` and `RowShowSum` on sum rows (`task-03`)
- [x] Synthesize `HasField` evidence for `OverloadedRecordDot` (`task-04`)
- [x] Synthesize batched `setFieldsAt` evidence for `OverloadedRecordUpdate` (`task-05`)

## Milestone 4 — scale

- [x] Port the measurement harness into this repo so the compile-time claims
      are first-class and re-runnable here (`benchmark/variants`)
- [x] Re-measure with the plugin in place; the target is arm-L behaviour
      (linear, and cheaper than a plain sum; Arm P achieves 122× Core reduction vs unassisted search; Arm PR exponent 1.03)

## Milestone 5 — ecosystem satellite interfaces

- [x] Optics integration (`task-08` `polytropos-optics`, `task-09` `polytropos-microlens`, `task-10` `polytropos-lens`)
- [x] Serialization & codecs (`task-11` `polytropos-aeson`, `task-12` `polytropos-cbor`, `task-13` `polytropos-cassava`)
- [x] Database & relational models (`task-14` `polytropos-beam`, `task-15` `polytropos-hasql`, `task-16` `polytropos-rel8`, `task-17` `polytropos-persistent`)
- [x] Schema generation & testing (`task-18` `polytropos-openapi3`, `task-19` `polytropos-quickcheck`)
- [x] Self-documenting records & multi-context reader environments: `polytropos-docrecords` and `polytropos-reader-soup` (re-architected from Yves Parès's Porcupine ecosystem with zero-overhead row polymorphism)

## Milestone 6 — algebraic effect systems ports

- [x] `effectful-polytropos` (`/home/nyc/src/effectful`, branch `polytropos-port`): flat open product rows with compile-time literal index solving; synchronized to GitHub, GitCode, Disroot, Framagit, and Radicle (`rad:z2xXG4qgbVQfsjaXak39VD9HPjcgW`); configured with `source-repository-package`
- [x] `polysemy-polytropos` (`/home/nyc/src/polysemy`, branch `polytropos-port`): $O(1)$ tag `decomp` and `weaken` without Peano search; synchronized to GitHub, GitCode, Disroot, Framagit, and Radicle (`rad:z2CJzaBZPriPHfmzzBQLjeSShnr7z`); configured with `source-repository-package`
- [x] `kernmantle-polytropos` (`/home/nyc/src/kernmantle`, branch `polytropos-port`): forked from master, replacing `vinyl` with `polytropos` Higher-Kinded Data ropes; synchronized to GitHub, GitCode, Disroot, Framagit, and Radicle (`rad:z3KgUX2HXHeu8VysLhN5EVtePWc5q`); configured with `source-repository-package`

## Milestone 7 — engine diagnostics, syntax & eliminators

- [x] Human-centric custom `TypeError` diagnostics in `Polytropos.Plugin` (Milestone T1) with Levenshtein-distance fuzzy suggestions
- [x] Source plugin syntactic devices: `REC`, `REC_F`, `VAR`, `REC_UPD`, view patterns, and `deriving OpenRecord` / `deriving OpenVariant`
- [x] Full hybrid eliminators and peeling (Milestone T2): `eliminateUniform`, `eliminateUniformM`, `eliminate`, `eliminateM`, `matchVariant`, `peel`, `peelF` with $O(1)$ array jump table dispatch

## Milestone 8 — documentation & pedagogical framework

- [x] Candidate tutorial examples evaluation matrix (`docs/notes/TUTORIAL_EXAMPLES_EVALUATION.md`)
- [x] Worked live Nanopass and Resilient Parsing tutorial executables in `examples/nanopass/` and `examples/resilient/` (`cabal run example-nanopass`, `cabal run example-resilient`)
- [x] Part II Worked Real-World Case Studies and Companion Executables:
  - [x] Addendum C: Relational Database Models & Persistent Schemas (`examples/database/`, `cabal run example-database`)
  - [x] Addendum D: Extensible Algebraic Effects & Higher-Kinded Ropes (`examples/effects/`, `cabal run example-effects`)
  - [x] Addendum E: Federated Context & Memory MCP Server Capstone (`examples/mcp-server/`, `cabal run example-mcp-server`)
  - [x] Dedicated satellite package `packages/polytropos-mcp` (Model Context Protocol JSON-RPC 2.0 server)
- [ ] Four-Audience documentation agenda overhaul:
  - [x] Audience 1: Foundational 5-Lesson Plan + Addenda A, B, C, D, E (`docs/TUTORIAL.md`) and refreshed `docs/NEWBIE_GUIDE.md`
  - [x] Audience 2: Systematic Haddock audit & polish across `Polytropos` and `Polytropos.Core`
  - [x] Audience 3: Authoritative architectural guide & maintenance recipes (`docs/MAINTAINER_GUIDE.md`)
  - [x] Audience 4: AI context projections & agentic governance (`AGENTS.md`, `.agents/rules/`)

- [x] Milestone T3: Hardware-vectorized SIMD CoW updates for $>32$ fields (`docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md`)
- [x] Milestone T4: HLS / IDE autocompletion and hover integration (`Development.IDE.Plugin.Completions.Logic`, `AtPoint`)
- [x] Milestone T9: Multi-GHC Backward Compatibility Matrix (GHC 9.6.7 LTS through 9.14.1 with `Polytropos.Plugin.Compat` shim and universal SIMD `copySmallArray` fallback)
- [ ] Collaborative human review and polish of revised documentation tiers

