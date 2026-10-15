# polytropos — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

Phases 3, 4A and 4B/4D foundations are in. Tasks `task-01` through `task-19` have been executed
and verified through their deterministic gates. All milestones of `plans/2026-10-09-plugin-gap-roadmap.md`
(§1.1 generic field-class dictionary supply, §1.2 HKD-aware row vocabulary, §1.3 type-level row metadata + rewriting,
§1.4 subrow/subsum projection evidence, §1.5 compile-time label hashing `KnownHash`, §1.6 source-plugin construction syntax & open declaration forms,
and §1.7 generic instance layer over rows & dynamic dictionary emission) are implemented and verified.
All packages build cleanly on GHC 9.14.1 with `-Wall -Werror`:
- `polytropos-core` passes 37 tests (primitive SmallArray CoW updates, `setFieldsAt` batch updates,
  `MRep` transient builders, `Polytropos` consumer surface, `Record`, `Variant`, `peel`, `peelF`,
  `eliminateUniform`, `eliminateUniformM`, `eliminate`, `matchVariant`).
- `polytropos-plugin-smoke` passes 54 tests with `-fplugin=Polytropos.Plugin` (`RowEq`, `RowShow`,
  `RowEqSum`, `RowShowSum`, native `OverloadedRecordDot` on bare and `RecordF Maybe` records,
  `AllFields` generic dictionary supply across standard and HKD product rows, `FieldIndex`/`ConstructorIndex` on HKD rows,
  compile-time `Refl` type equality rewriting for `FieldNames`, `SimpleFieldTypes`, and `FieldTypes`,
  `SubRow`/`SubSum` projection, injection, and narrowing evidence with `projectRecord`, `widenVariant`, and `narrowVariant`,
  `KnownHash` compile-time label hashing with literal FNV-1a 64-bit `Word` dictionaries,
  source-plugin syntactic devices (`REC`, `REC_F`, field punning, `VAR`, `VARIANT`, `REC_UPD`, `REC_UPD_F`,
  record & variant view pattern matching, and `deriving OpenRecord` / `deriving OpenVariant` declaration forms),
  $O(1)$ eliminator jump tables (`eliminateUniform`, `eliminateUniformM`, `eliminate`) and single-constructor peeling (`peel`),
  and human-centric `TypeError` diagnostics with Levenshtein-distance fuzzy suggestions and schema summaries
  for missing fields, missing constructors, field type mismatches, and `SubRow`/`SubSum` structural discrepancies).
- `polytropos-generics-test` passes 13 tests (`Generic` and `GInstances` datatype generics bridge over flat `Rep`
  and `RowRep`, `geq`, `gcompare`, `gshowsPrec`, `gmap`, `gfoldMap` over product and sum ADTs and plugin-solved rows,
  including HKD `RecordF Maybe`).
- `polytropos-optics-test` passes 6 tests (`optics-core` + `LabelOptic` `#field` lenses and variant prisms).
- `polytropos-microlens-test` passes 5 tests (homogeneous `each` traversal, plugin-indexed `fieldLens`).
- `polytropos-lens-test` passes 14 tests (positional `_1`..`_9`, name-keyed `At`/`Ixed`, `each`,
  `fieldLens`, variant prisms).
- `polytropos-aeson-test` passes 7 tests (O(N) record/variant codecs, 20-field roundtrip,
  canonical row-order encoding, tagged variant shape).
- `polytropos-beam-test` passes 6 tests (30-column `Beamable` table: skeleton arity, lockstep
  `zipBeamFieldsM`, `allBeamValues`, row-symbol column names; compiles in a fraction of a second).
- `polytropos-openapi3-test` passes 7 tests (record object schemas with properties/required in row
  order, variant `oneOf` tagged unions, JSON roundtrip of the generated schemas).
- `polytropos-cbor-test` passes 6 tests (3- and 20-field record roundtrips, variant roundtrips,
  byte-level format assertions: length header + flat payload, tag + payload).
- `polytropos-cassava-test` passes 4 tests (heterogeneous CSV named record codecs, 12-field roundtrips).
- `polytropos-persistent-test` passes 10 tests (PersistRow marshalling, 20-field roundtrips,
  row-order serialization, PersistField bridge, and Entity wrapper).
- `polytropos-rel8-test` passes 13 tests (Rel8 `Rel8able (PolyRow r)` instance, `RowHTable` right-nested
  column tree, `namesFromLabels` symbol column synthesis, `showQuery` SELECT/VALUES projections,
  `toRecord`/`fromRecord` and `columnsToRow`/`rowToColumns` roundtrips, and columnar combinators
  `hfield`, `hfieldAt`, `htabulate`, `hmap`, `htraverse`, `hzipWith`).
- `polytropos-quickcheck-test` passes 9 tests (record and variant arbitrary generation and convergence shrinking).
- **Haddock documentation:** All workspace packages build with 100% Haddock coverage and zero warnings under `cabal --jobs=20 haddock --haddock-for-hackage all`:
  * Resolved missing link destinations (`KnownSymbol`, boot libraries) via `cabal.project` haddock options.
  * Disambiguated type/value namespace collisions (`t'Rep'`, `t'RowRep'`, `t'MRep'`, `t'DictAny'`, `t'Field'`, `t'PolyRow'`, `t'Variant'`, `v'VAR'`, `pattern VARIANT`, `t'BeamTable'`, `t'PolyRowEntity'`).
  * Qualified external symbols and fixed doc markdown code blocks (`SmallArray`, `ToJSON`/`FromJSON`, `ToField`/`FromField`, `ToNamedRecord`/`FromNamedRecord`, `Entity`, `Traversal`).
  * Added complete module and function documentation across `Polytropos.Plugin` (`plugin`), `Polytropos.Generics`, and `Polytropos.Optics`.
  * Verified 100% coverage across all 17 library modules with zero doc errors or unlinked symbols.

### Tooling Integration: Haskell Language Server (Completed & Verified)

Milestone T4's `haskell-language-server` tooling integration has been implemented, tested, and committed on branch `polytropos-row-completions` in `/home/nyc/src/haskell-language-server` (commits `f0c588d35` and `f01e37d81`):
- **Row type inspection & autocompletion in `ghcide` (`Development.IDE.Plugin.Completions.Logic`):**
  * Traverses promoted type-level cons lists (`:`) unwrapping type synonyms via `coreView`.
  * Extracts field labels and types from both standard promoted tuple pairs `'(Symbol, Type)` and polytropos `Pair Symbol Type` / custom wrapper constructors.
  * Queries `identType` from `nodeIdentifiers` in addition to `nodeType`, resolving identifier occurrences (variable bindings like `recVal`) to their concrete row types.
  * Corrected guard precedence in `Logic.hs` where `T.null prefixScope` matched uncapitalized record variable prefixes first and prematurely discarded record-dot suggestions.
  * Mapped completion positions back through `fromDelta` position deltas (`PositionMapping`) with `lowerRange`, preserving query accuracy on active document edits.
  * Added synchronous fallback from `useWithStaleFast` to `useWithStale GetHieAst` when fast in-memory cache misses.
  * Verified with passing tests in `ghcide-test:test:ghcide-tests` (`row polymorphic record dot completion` and `polytropos Pair row dot completion`).
- **Human-readable Hover Type Summaries (`ghcide` `Development.IDE.Spans.AtPoint`):**
  * Transforms raw GHC `RowRep Identity ProductRowT ('[ 'Pair ...])` and `Record ('[ ...])` AST text into clean, ergonomic `Record { field :: Type, ... }` and `Variant < Con :: Type | ... >` representations in hover tooltips.
- **Open Record & Variant Wildcard Expansion (`hls-explicit-record-fields-plugin` `Ide.Plugin.ExplicitFields`):**
  * Added `OpenRecordWildcardExpansion` and `OpenVariantBranchExpansion` recognizing `REC { .. }` and `VAR { .. }` constructs.
  * Generates code actions to expand open record wildcards and open variant branches into explicit field puns and handlers.
- **LSP QuickFix CodeActions for `TypeError` Diagnostics (`hls-refactor-plugin` `Development.IDE.Plugin.CodeAction`):**
  * Extends `extractRenamableTerms` to parse Polytropos Levenshtein-distance fuzzy typo suggestions from GHC `TypeError` diagnostics.
  * Generates instant `Replace with ‘...’` LSP QuickFix code actions for typos in record fields and variant constructors.
  * Verified with 4/4 passing unit tests in `hls-refactor-plugin-tests:test:hls-refactor-plugin-tests` (`extractRenamableTerms`).

### Hardware-Vectorized SIMD CoW Updates (Completed & Verified)

Milestone T3 has been implemented, tested, and verified via `polytropos-core-test`:
- **Vectorized Copy Primitives:** `setFieldAt` and `setFieldsAt` use non-overlapping block copies (`copySmallArray`) for records $>32$ fields, avoiding redundant reads and in-place overwrites.
- **In-Place Batch Fast-Paths in `MRep`:** Implemented `writeFieldsAt`, `copyFieldsFrom`, `copyMFields`, `newMRep`, and `thawRepSlice` in `Polytropos.Core`.
- **Verification:** 8 unit tests in `packages/polytropos-core/test/Main.hs` covering 64-field and 100-field record scaling, slice copy roundtrips, and batch mutation fast-paths.

### Refactoring, Linters & Semantic Code Modernizers (Completed & Verified)

Milestone T6 has been implemented, tested, and deterministically verified via `scripts/tasks/verify-milestone-t6.sh`:
- **`hlint` & `hls-hlint-plugin` Rules:** Root `.hlint.yaml` and modular `rules/hlint/polytropos.yaml` implementing 8 custom semantic and performance rules (`Use OverloadedRecordDot`, `Avoid chained setField`, `Avoid repeated setField in foldl`, `Use peel for single-constructor elimination`, `Use eliminateUniform for handler dispatch`, `Redundant widenVariant`, `Use REC sugar instead of nested insertField`, `Use VAR pattern matching`).
- **`retrie` Equational Rewrites:** Structured rewrite rule files in `rules/retrie/` covering `record-dot.rules`, `batch-updates.rules`, `variant-eliminators.rules`, and `open-adt-migration.rules`.
- **`stan` Static Analysis:** Project `.stan.toml` configuration and `rules/stan/POLYTROPOS_INSPECTIONS.md` inspection catalog covering `STAN-P01` (hot-loop CoW allocations), `STAN-P02` (redundant variant widening), `STAN-P03` (dead row fields), and `STAN-P04` (non-exhaustive manual cascades).
- **CLI Runner & Documentation:** `bin/polytropos-modernize` executable runner and comprehensive guide `docs/tools/MODERNIZER_AND_LINTER_GUIDE.md`.
- **Verification Gate:** `rules/test/ModernizerFixtures.hs` and `scripts/tasks/verify-milestone-t6.sh` passing all assertions cleanly.

### Program Synthesis, Formal Verification & Continuous Compilation (Completed & Verified)

Milestone T7 has been implemented, tested, and deterministically verified via `scripts/tasks/verify-milestone-t7.sh`:
- **`liquidhaskell` Refinement Types:** Specifications and formal contracts under `verification/liquid/`:
  * `verification/liquid/Polytropos/Liquid/RowPredicates.spec`: Memory bounds, slot indexing, subrow extraction, and field refinement predicates.
  * `verification/liquid/Polytropos/Liquid/Proofs.hs`: Typechecked Haskell module proving array bounds safety, safe subrow projections, and jump table exhaustiveness without warnings under GHC (`-Wall -Werror`).
  * `verification/liquid/Polytropos/Liquid/RowBounds.fq`: Liquid-Fixpoint Horn constraint problem verified `Safe` (5 constraints checked) using Z3 SMT solver.
- **`synquid` Program Synthesis:** Type-directed synthesis specifications under `synthesis/synquid/`:
  * `RecordAdapter-SubRow.sq`: Width subtyping adapter synthesis.
  * `RecordAdapter-Permute.sq`: Field permutation adapter synthesis.
  * `RecordAdapter-Defaults.sq`: Extension adapter with defaulted optional fields.
  * `VariantEliminator.sq`: Exhaustive variant eliminator dispatch synthesis.
  * `VariantSubsumption.sq`: Variant widening and constructor tag injection synthesis.
- **`tricorder` Continuous Compilation & MCP Bridge:**
  * Workspace `.tricorder.yaml` multi-target GHCi daemon configuration.
  * Verified `tricorder-mcp` server registration in `.mcp.json`.
  * `bin/polytropos-tricorder`: CLI helper for status queries (<50 tokens) and daemon management.
  * `bin/polytropos-verify`: Unified runner for formal verification, synthesis specs, and diagnostics.
- **Documentation & Verification Gate:**
  * Comprehensive guide in `docs/tools/FORMAL_VERIFICATION_AND_SYNTHESIS_GUIDE.md`.
  * Deterministic test gate `scripts/tasks/verify-milestone-t7.sh` passing all 6 assertion steps.

### Source Formatters & Layout Engines (Completed & Verified)

Milestone T8 has been implemented, tested, and deterministically verified via `scripts/tasks/verify-milestone-t8.sh`:
- **Fourmolu & Ormolu:** Root `fourmolu.yaml` with leading comma style, `record-brace-space: true`, aligned records, and operator fixity declarations (`:=`, `.==`, `.#`). Formats open row syntax, record dot access, and combinators cleanly with zero AST drift.
- **Brittany & Floskell:** Root `.brittany.yaml` with `lconfig_indentListSpecial: true`, multiline column alignment, and GHC option forwarding (`-XDataKinds`, `-XTypeOperators`, `-XOverloadedRecordDot`). Root `floskell.json` layout configuration with record field and type operator alignments.
- **CLI Runner & Fixtures:** `bin/polytropos-format` runner supporting `--check`, `--apply`, `--ormolu`, `--brittany`, `--verify-configs`, and `--fixtures`. Formatter test fixture module `formatters/test/FormatFixtures.hs`.
- **Documentation & Gate:** Authoritative guide in `docs/tools/SOURCE_FORMATTERS_AND_LAYOUT_GUIDE.md` and deterministic test gate `scripts/tasks/verify-milestone-t8.sh`.

### Algebraic Effect Systems Ports (Completed & Verified)

All three algebraic effect system ports planned in `docs/notes/EFFECT_SYSTEMS_PORTING_MASTER_PLAN.md` have been implemented, tested, and committed on their respective `polytropos-port` branches:
- **`effectful`** (`/home/nyc/src/effectful`, branch `polytropos-port`, commit `470e6d7`):
  * Local linkage to `polytropos-core` and `polytropos-plugin` with `-fplugin=Polytropos.Plugin`.
  * Open row representation with polykinded `(:::)` and `HasEffect` aliases.
  * Overlappable `FieldIndex` fallback instance for `(:>)` providing compile-time literal integer index resolution.
  * 89/89 tests passing in `effectful:test:test` under GHC 9.14.1.
- **`polysemy`** (`/home/nyc/src/polysemy`, branch `polytropos-port`, commit `6247540`):
  * Local linkage to `polytropos-core` and `polytropos-plugin` with `-fplugin=Polytropos.Plugin`.
  * Wired `Member t r` directly to `ConstructorIndex t r`, eliminating linked-list Peano search stalls and the need for `polysemy-plugin`.
  * Implemented $O(1)$ integer operations for `decomp`, `extract`, `weaken`, and `decompCoerce`.
  * 43/43 tests passing in `polysemy:test:polysemy-test` under GHC 9.14.1.
- **`kernmantle`** (`/home/nyc/src/kernmantle`, branch `polytropos-port`, commit `60b2ddc`):
  * Clean fork off upstream `master` (`11431c0`), leaving behind incomplete `large-anon` changes and completely removing `vinyl`.
  * Flat `Rec` backed by `SmallArray Any` with $O(1)$ `rgetf` via `FieldIndex` and $O(1)$ bulk-copy `rcast` via `SubRow`.
  * Collapsed `TightRope` and `LooseRope` into the identical flat array representation (`tighten = loosen = id`).
  * Provided GADT-backed `RecView` pattern synonyms `RNil` and `(:&)`, and `Label`/`IsLabel` support.
  * All 4 executables (`exCli`, `ex1`, `exBypass`, `exLenses`) compile, link, and run cleanly, and `kernmantle-batteries` compiles cleanly under GHC 9.14.1.

### Multi-GHC Backward Compatibility Matrix (Completed & Verified)

Milestone T9 has been implemented, tested, and deterministically verified across all five GHC versions: GHC 9.6.7 (LTS baseline), GHC 9.8.4 (Hackage baseline), GHC 9.10.3, GHC 9.12.4, and GHC 9.14.1 (primary toolchain).
- **Test Pass Rate:** 100% across all 5 compilers (45/45 tests in `polytropos-core-test`, 54/54 tests in `polytropos-plugin-smoke`, totaling 495 passed tests, 0 failures).
- **Zero Warnings:** All packages and test suites compile cleanly under `-Wall -Werror` without warning noise.
- **Architectural Shim (`Polytropos.Plugin.Compat`):**
  * Record update AST matching across GHC 9.6 `Left` and GHC $\ge 9.8$ `RegularRecUpdFields`.
  * Field occurrence extraction across GHC 9.6-9.10 `AmbiguousFieldOcc` and GHC $\ge 9.12$ `FieldOcc`.
  * Pattern synonym `PrefixConPat` abstracting 3-parameter `HsConDetails tyarg arg rec` (GHC 9.6-9.12) vs 2-parameter `HsConDetails arg rec` (GHC 9.14).
  * `stripHsPar` handling 4-field `HsPar` (GHC 9.6-9.8) and 2-field `HsPar` (GHC $\ge 9.10$).
  * `polyLabel` constructing `HsOverLabel` across `noAnn NoSourceText` (GHC 9.6-9.8), `noExtField NoSourceText` (GHC 9.10), and `NoSourceText` (GHC $\ge 9.12$).
  * `mkPolytroposImportDecl` handling `ideclLevelSpec = NotLevelled` (GHC $\ge 9.14$) vs standard `ImportDecl` without level spec (GHC 9.6-9.12).
  * `mkHsApp`, `mkTupArg`, and `mkLambda` abstracting application, tuple present argument, and lambda constructors across GHC AST differences.
  * Runtime module unit resolution: `modBase` (`GHC.Base` vs `GHC.Internal.Base`), `modShow` (`GHC.Show` vs `GHC.Internal.Show`), and `modRecords` dynamically using `moduleUnit modBase` (`base:GHC.Records` on GHC 9.6-9.8 vs `ghc-internal:GHC.Internal.Records` on GHC 9.10-9.14).
- **Universal SIMD Fallback:** `primitive >= 0.9`'s `copySmallArray` primitive provides autovectorized SIMD block copy on GHC 9.14 while falling back cleanly to libc `memcpy` on older GHC releases, with zero linked-list churn and zero code divergence.
- **Multi-Compiler Overlays:** Dedicated cabal project files (`cabal.project.ghc-9.6`, `cabal.project.ghc-9.8`, `cabal.project.ghc-9.10`, `cabal.project.ghc-9.12`) allowing isolated regression verification.

## What exists

- `packages/polytropos-core/src/Polytropos/Core.hs` — `RowOf`, `Row`, `ProductRow`,
  `ProductRowHKD`, `SumRowOf`, `SumRow`, `SumRowHKD`, `SumRowF`, `Rep`,
  `RowType` (`ProductRowT`, `SumRowT`, `ProductRowHKDT`, `SumRowHKDT`), `RowFlavour`, `RowRep`,
  `HandlerType`, `ResultType`, `FieldNames`, `SimpleFieldTypes`, `FieldTypes`,
  `SubRow(..)`, `SubSum(..)`, `KnownHash(..)`, `labelHash`, `hashVal`, `fnv1a64`, `productRep`, `injectRep`, `fieldAt`, `setFieldAt` (primitive CoW),
  `setFieldsAt` (batch update), `MRep`, `thawRep`, `freezeRep`, `writeFieldAt`, `modifyRep` (ST transients),
  `setFieldSumAt`, `projectRep`, `matchRep`, `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`, `FieldIndex`,
  `ConstructorIndex`, `Field(..)`, `IsLabel`, `DictAny`, `AllFields`, `noInlineUnsafeCo`
- `packages/polytropos-core/src/Polytropos.hs` — Human-facing consumer module:
  `Record`, `RecordF`, `Variant`, `VariantF`, `emptyRecord`, `emptyRecordF`, `insertField`, `insertFieldF`,
  `injectVariant`, `injectVariantF`, `projectVariant`, `projectVariantF`, `projectRecord`, `projectRecordF`,
  `widenVariant`, `widenVariantF`, `narrowVariant`, `narrowVariantF`, pattern synonyms, and re-exports
  (`KnownHash`, `labelHash`, `hashVal`, `fnv1a64`)
- `packages/polytropos-core/test/Main.hs` — 32 unit tests verifying representations, batch mutations,
  transients, and consumer API
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — TcPlugin structured with GHC Note architecture (`tagref`-validated, 6 comprehensive notes):
  * Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails]: Didier Rémy row calculus & open vs closed rows
  * Note [Literal Evidence Synthesis vs Type-Level Search]: O(1) literal index and tag evidence generation
  * Note [SubRow and SubSum Projection and Narrowing Evidence]: literal projection index and narrowing table emission
  * Note [Type-Level Metadata Rewriting and Defunctionalization]: O(1) compile-time reflection rewriting
  * Note [Human-Centric TypeError Diagnostics & Fuzzy Matching]: Levenshtein edit distance suggestions and schema formatting
  * Note [OCaml Subtype/Unify Correlation and Row Tail Algebra]: row walking and deferral semantics on unfixed tails
  * Solves `FieldIndex` and `ConstructorIndex` by literal Int/Word calculation (`mkIntExpr` and `mkWordExpr`)
  * Solves `RowEq` and `RowShow` for product rows via Core AST synthesis
  * Solves `RowEqSum` and `RowShowSum` for sum rows via tag testing and constructor dispatch
  * Solves `GHC.Records.HasField` for native `OverloadedRecordDot` (`r.field`)
  * Solves `AllFields` generic field-class dictionary supply (solving wanteds and packing flat `SmallArray (DictAny c)`)
  * Type-level row metadata rewriter: reduces `FieldNames`, `SimpleFieldTypes`, and `FieldTypes` when product rows are closed
  * `SubRow` and `SubSum` evidence solver: emits literal projection slot indices `[Int]` for products, and literal injection tags `[Word]` / narrowing maps `[Maybe Word]` for sums
  * `KnownHash` compile-time label hashing: evaluates literal symbol names and synthesizes literal FNV-1a 64-bit `Word` dictionaries
  * Cleaned Core expression builders (`mkIntExpr` and `mkWordExpr`), abbreviated `polytroposInit` via `RecordWildCards` (`pure PluginState{..}`), and imported standard `Data.Either.partitionEithers`
- `packages/polytropos-plugin/tests/smoke/Main.hs` — Smoke tests exercising plugin-solved dictionary synthesis,
  `AllFields` generic dictionary supply across homogeneous and heterogeneous rows, compile-time `Refl`
  equality reduction of metadata families, `SubRow`/`SubSum` widening, narrowing, and projection,
  `KnownHash` compile-time symbol hashing matching `fnv1a64`, and 9 negative-compilation assertions
  verifying human-centric compiler stderr diagnostics.
- `packages/polytropos-generics/` — Datatype generics library unifying nominal Haskell ADTs with `polytropos`
  `Rep` with zero boxed intermediate tree representations
- `packages/polytropos-optics/` — Satellite package integrating with `optics-core` and `LabelOptic`
- `packages/polytropos-microlens/` — Satellite package: `microlens` `Each` for homogeneous records
  (`AllFieldsAre`-gated) and plugin-indexed `fieldLens`, zero deps beyond base/microlens/core/plugin
- `packages/polytropos-lens/` — Satellite package: positional `Field1`..`Field9`, name-keyed
  `At`/`Ixed`, `Each`, `fieldLens`, and `prismVariant` profunctor prisms over `lens`
- `packages/polytropos-aeson/` — Satellite package: linear O(N) `ToJSON`/`FromJSON` for records
  (row-order canonical objects) and variants (single-member tagged objects), no GHC.Generics tree
- `packages/polytropos-beam/` — Satellite package: erased `Beamable` instance over `BeamTable r f`
  (zero-cost newtype over `RowRep f ProductRowT r ()`), lockstep `zipBeamFieldsM` over flat arrays
- `packages/polytropos-openapi3/` — Satellite package: `ToSchema` for records (object schema,
  properties/required from row symbols) and variants (`oneOf` tagged unions), row-walked not
  Generic-derived
- `packages/polytropos-cbor/` — Satellite package: `Serialise` for records (CBOR array: length
  header + flat payload) and variants (array: constructor Word tag + payload), positional encoding
  mirroring the runtime Rep layout; scoped allow-newer for cborg/serialise's pre-9.14 base bounds
- `packages/polytropos-rel8/` — Satellite package: `Rel8able (PolyRow r)` for PostgreSQL schemas,
  mapping open product rows directly to a nested `RowHTable r` column tree (`HProduct`/`HLabel`/`HIdentity`),
  type-level label symbol synthesis via `namesFromLabels`, `litPolyRow`/`litRecord`, and columnar combinators
  (`hfield`, `hfieldAt`, `htabulate`, `hmap`, `htraverse`, `hzipWith`).
- `plans/2026-10-09-plugin-gap-roadmap.md` & `plans/2026-10-09-plugin-gap-spec.md` — Plugin gap-closing
  roadmap and specification sketches (all milestones §1.1 through §1.7 complete).
- `plans/FULL_COMPLETION_ROADMAP.md` — Full-completion roadmap and documentation agenda:
  technical capabilities (Milestone T1 `TypeError` diagnostics, T2 hybrid eliminator `eliminate`,
  T3 SIMD CoW updates, T4 HLS autocompletion, T5 re-benchmarking) and 4-tier documentation overhaul
  with execution modalities (`[AUTONOMOUS-MACHINE]`, `[COLLABORATIVE-ASYNC]`, `[HUMAN-GATED]`).
- `docs/notes/ADOPTION_BARRIERS_AND_MITIGATIONS.md` — Architectural mitigations directly addressing
  the 8 community adoption barriers from the Discord feedback.
- `docs/transcripts/discord-adoption-barriers-row-types.md` — Verbatim Discord transcript from #fp-general.
- `docs/NEWBIE_GUIDE.md` — quickstart and token-conservation workflow guide
- `docs/MAINTAINER_GUIDE.md` — engineering governance and zero-contamination doctrine
- `docs/notes/POLYTROPOS_DESIGN.md` — decisions D1–D10, costs, open questions
- `docs/notes/DESIGN_REVIEW_CLAUDE-OPUS-4.6.md` — architectural evaluation and ecosystem deployment assessment
- `docs/notes/PHASE2_SKETCH.md` — Phase 2 sketch (all refinements resolved)
- `docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md` — architectural roadmap for hardware-vectorized CoW updates
- `docs/notes/SATELLITE_INTERFACES_DESIGN.md` — architecture and package catalogue for 12 ecosystem satellites
- `docs/notes/EFFECT_SYSTEMS_PORTING_MASTER_PLAN.md` — master architectural plan for porting and forking algebraic effect systems (`effectful`, `polysemy`, `kernmantle`) to `polytropos`
- `docs/notes/EFFECTFUL_POLYTROPOS_PORT_PLAN.md` — implementation plan for `effectful-polytropos` (flat open product rows, `FieldIndex` literal index solving, eliminating `effectful-plugin`)
- `docs/notes/POLYSEMY_POLYTROPOS_PORT_PLAN.md` — implementation plan for `polysemy-polytropos` (freer monad union variant over `Rep`, $O(1)$ tag `decomp`, eliminating `polysemy-plugin`)
- `docs/notes/KERNMANTLE_POLYTROPOS_PORT_PLAN.md` — implementation plan for `kernmantle-polytropos` (forked from `master`, dropping `vinyl` and discarding `large-anon`, `RecordF` Higher-Kinded Data ropes)
- `docs/task_packets/` — 19 structured task packets (`task-01` through `task-19`)
- `scripts/tasks/` — deterministic test verification scripts for task packet gates (`task-01` through `task-19`)
- `bin/yamaarashi-exec` & `.agents/skills/yamaarashi/SKILL.md` — runner script and skill with SQLite ledger
- `benchmark/variants/` — six-arm compile-time harness: empirical validation of `Polytropos.Plugin`
  variants (Arm P, 122× Core reduction vs type-level search, 5,876 simpl lines) and records
  (Arm PR, $O(N)$ exponent 1.03, beating nominal Haskell records at 5,602 lines Core vs 6,070)
- `examples/nanopass/` — worked live tutorial executable (`example-nanopass`), building and running cleanly via `cabal run example-nanopass`
- `docs/TUTORIAL.md` — interactive tutorial with foundational 5-lesson curriculum + Nanopass worked case study addendum + future addenda anchors
- `docs/NEWBIE_GUIDE.md` — refreshed newcomer quickstart connecting directly to the 5-lesson tutorial and updating quality gates
- `docs/MAINTAINER_GUIDE.md` — authoritative maintainer guide covering Core memory layouts, TcPlugin solving pipeline, and maintenance recipes
- `docs/notes/TUTORIAL_EXAMPLES_EVALUATION.md` — pedagogical evaluation matrix and staging roadmap for tutorial chapters
- `verification/liquid/` — LiquidHaskell specifications, GHC-verified proofs (`Proofs.hs`), and SMT-checked Horn constraints (`RowBounds.fq`)
- `synthesis/synquid/` — Synquid type-directed synthesis specifications for record and variant adapters
- `bin/polytropos-tricorder` & `bin/polytropos-verify` — continuous diagnostics runner and formal verification gate
- `bin/polytropos-format` — unified source formatter and layout engine CLI runner
- `docs/developer/LIQUIDHASKELL_AND_SYNQUID_GUIDE.md` — comprehensive developer guide for out-of-process LiquidHaskell formal verification contracts and Synquid type-directed synthesis
- `docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md` — authoritative catalog of upstream repositories modified for polytropos (`haskell-language-server`, `effectful`, `polysemy`, `kernmantle`, `synquid`, `stan` [branch `polytropos-compat`], `retrie`, `tricorder`), explaining modification rationale, branches, and why formatters need no forks
- `rules/` — downstream developer rules & tool configuration library (`rules/formatters/`, `rules/hlint/`, `rules/retrie/`, `rules/stan/`, `rules/tricorder/`, `rules/README.md`)
- `.agents/rules/` — subdivided AI coding assistant operational rules

## What is deliberately missing

- The plugin itself (now in development).
- Subsumption for sum elimination when the result row is not syntactically identical.

## Next action

- Expand HLS integrations beyond core completions (e.g. `hls-explicit-record-fields-plugin` open record wildcard expansion and `TypeError` code actions).
- Human-in-the-loop review of the revised documentation tiers (Audience 1 `TUTORIAL.md` & `NEWBIE_GUIDE.md`, Audience 2 Haddock polish, Audience 3 `MAINTAINER_GUIDE.md`).
