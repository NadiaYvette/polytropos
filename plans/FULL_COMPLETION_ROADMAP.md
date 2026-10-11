<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Full-Completion Roadmap & Documentation Agenda

**Status:** STRATEGIC ROADMAP · v1.0 · 2026-10-10  
**Context:** Comprehensive execution plan resolving remaining technical debt, unfinished engine capabilities (e.g. `eliminate`, `TypeError` diagnostics), and the 4-tier documentation overhaul addressing ecosystem adoption barriers.  
**Related Documents:**
- [`docs/notes/ADOPTION_BARRIERS_AND_MITIGATIONS.md`](../docs/notes/ADOPTION_BARRIERS_AND_MITIGATIONS.md) (analysis of Discord feedback)
- [`docs/transcripts/discord-adoption-barriers-row-types.md`](../docs/transcripts/discord-adoption-barriers-row-types.md) (verbatim transcript)
- [`docs/notes/POLYTROPOS_DESIGN.md`](../docs/notes/POLYTROPOS_DESIGN.md) (decisions D1–D10, §4 elimination, §7 open questions)
- [`docs/notes/DOC_STRATEGY.md`](../docs/notes/DOC_STRATEGY.md) (four-audience documentation policy)
- [`docs/registers/OPEN_LOOPS.md`](../docs/registers/OPEN_LOOPS.md) (suspended architectural questions)

---

## 1. Execution Modalities & Human-in-the-Loop Reordering Policy

To avoid blocking progress when human maintainers are unavailable, all roadmap tasks are assigned an **Execution Mode**:

- **`[AUTONOMOUS-MACHINE]`**: Fully self-contained. The AI agent can implement, test, benchmark, and verify against zero-warning gates without requiring interactive human participation.
- **`[COLLABORATIVE-ASYNC]`**: Decoupled machine preparation + human review. Machine drafts code, examples, or documentation; the human reviews, refines, and edits asynchronously. These tasks can be reordered freely based on human availability.
- **`[HUMAN-GATED]`**: Involves product/design decisions or external publication where human approval is required before merging or releasing.

---

## 2. Technical Capabilities Track (Engine & Plugin)

### Milestone T1: Human-Centric `TypeError` Diagnostics in `Polytropos.Plugin` [COMPLETED]
- **Execution Mode:** `[AUTONOMOUS-MACHINE]` (Implemented & Verified: 52/52 tests in `polytropos-plugin-smoke`)
- **Motivation:** Directly eliminates Barrier #5 ("Bad type errors & inference fragility — nigh impossible to figure out what has gone wrong").
- **Deliverables:**
  1. **Missing Field Diagnostic:** When `FieldIndex (name :: Symbol) row a` cannot be solved, intercept the unsolved wanted constraint in `Polytropos.Plugin` and synthesize a custom GHC `TypeError`:
     ```text
     • Polytropos Record Error:
       Field 'email' does not exist in record:
         { name :: String, age :: Int, address :: Text }
       Did you mean: 'name' or 'age'?
     ```
  2. **Missing Constructor Diagnostic:** When `ConstructorIndex (tag :: Symbol) row` cannot be solved, emit:
     ```text
     • Polytropos Variant Error:
       Constructor 'Exit' is not a member of variant:
         < Start :: String | Stop :: Int >
       Available constructors: 'Start', 'Stop'
     ```
  3. **SubRow / SubSum Mismatch Diagnostics:** When `SubRow sub super` or `SubSum sub super` fails, list the exact subset discrepancy (missing fields or unhandled variant branches).
- **Verification:** Unit tests asserting the exact text of compiler diagnostics in `tests/smoke/Main.hs`.

---

### Milestone T2: The Full Hybrid Eliminator (`eliminate`) & Row Flavour Settlement
- **Execution Mode:** `[COLLABORATIVE-ASYNC]` (Machine drafts implementation; human reviews API shape)
- **Motivation:** Resolves lines 252 & 256 of `Polytropos.Core` and implements §4 of `POLYTROPOS_DESIGN.md`.
- **Deliverables:**
  1. **Handler Type Settlement:** Finalize between explicit field types (`HandlerType n fs res m`) and derived field types (`HandlerType n res m`) based on caller ergonomics.
  2. **RowFlavour Instances:** Un-comment and complete:
     ```haskell
     instance RowFlavour HandlerRowT where
       type EntryKind HandlerRowT = Pair Symbol (HandlerType ...)
     instance RowFlavour ResultRowT where
       type EntryKind ResultRowT = Pair Symbol Type
     ```
  3. **Coproduct of Results:** Implement `Results (r :: HandlerRowT)` GADT indexed by the handler row.
  4. **The `eliminate` Combinator:**
     ```haskell
     eliminate :: Variant r -> HandlerRow r m res -> m (Results res)
     eliminateUniform :: (forall x. ...) -> Variant r -> HandlerRow r m a -> m a
     ```
- **Verification:** Unit tests with multi-constructor variants running handlers in `IO` and `Identity`.

---

### Milestone T3: Hardware-Vectorized SIMD CoW Updates [COMPLETED]
- **Execution Mode:** `[AUTONOMOUS-MACHINE]` (Implemented & Verified: 8/8 SIMD CoW tests in `polytropos-core-test`)
- **Motivation:** Fulfills `docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md` for high-throughput record updates.
- **Deliverables:**
  1. Implement SIMD-vectorized array copy primitives for records with $>32$ fields using GHC primitives or byte-aligned block copies (`copySmallArray` non-overlapping slice copies in `setFieldAt` and `setFieldsAt`).
  2. In-place batch mutation fast-paths and slice copy primitives in `MRep` transient builders (`writeFieldsAt`, `copyFieldsFrom`, `copyMFields`, `newMRep`, `thawRepSlice`).
- **Verification:** 8 micro-test assertions in `polytropos-core-test` verifying 64-field and 100-field record scaling, slice copy roundtrips, and sorted/unsorted batch updates.

---

### Milestone T4: HLS / IDE Autocompletion Ergonomics & Tooling Bridge
- **Execution Mode:** `[COLLABORATIVE-ASYNC]`
- **Motivation:** Directly resolves Barrier #6 ("No autocompletion in IDE / tooling — nigh impossible to use comfortably compared to nominal records").
- **Deliverables:**
  1. **OverloadedRecordDot Row Autocompletion (ghcide):**
     Extend `ghcide`'s `Development.IDE.Plugin.Completions.Logic` to inspect `Type` arguments when `tyConFieldLabels` yields no nominal selectors. Extract type-level string literals (`LitTy (StrTyLit fs)`) and field types from promoted row lists (`Pair Symbol Type`, promoted tuples), delivering instant completion popup items (`CompletionItemKind_Field`) with field names and type annotations for `Record r` and `Variant s`.
  2. **`hls-explicit-record-fields-plugin` Extension:**
     Update `hls-explicit-record-fields-plugin` to recognize open record wildcards (`REC { .. }`) and synthesize explicit field puns from the expected row type. Add constructor branch expansion for open variants (`VAR { .. }`).
  3. **HLS Hover Type Summaries:**
     Render type-level rows with clean human-readable record syntax (`{ name :: String, age :: Int }`) in hover tooltips rather than raw `RowRep Identity ProductRowT ('[ 'Pair ...])` type ASTs.
  4. **LSP QuickFix CodeActions for `TypeError` Diagnostics:**
     Wire `Polytropos.Plugin`'s Levenshtein-distance fuzzy suggestions ("Did you mean: 'name'?") directly to LSP QuickFix CodeActions, enabling one-click typo correction in VS Code, Neovim, and Emacs.
- **Verification:** Test cases in `ghcide/test/exe/CompletionTests.hs` asserting completions on `Record` and `Variant` types.

---

### Milestone T5: Scale Re-Measurement Against Prior Art [COMPLETED]
- **Execution Mode:** `[AUTONOMOUS-MACHINE]` (Executed & Verified in `benchmark/variants/results.csv`)
- **Motivation:** Empirically demonstrate the compile-time and runtime claims of `POLYTROPOS_DESIGN.md` §6.
- **Deliverables:**
  1. Re-run `benchmark/variants` with the complete `Polytropos.Plugin` enabled across $N \in [10..100]$.
  2. Measure compile times, Core sizes (`ds_preopt`, `simpl`), and peak RSS for variants (Arm P) and records (Arm PR).
  3. Compare against unassisted type-level search (Arm C, $O(N^{2.8})$) and nominal records/sums (Arms R and A):
     - **Variant (Arm P):** Slashes N=100 Core from 2,081,480 lines down to 17,066 lines (**122× reduction**), peak RSS from 804 MB to 290 MB. Post-simplification Core (5,876 lines) is smaller than nominal sums (5,945 lines).
     - **Record (Arm PR):** $O(N)$ linear scaling (exponent 1.03), requiring **less Core than nominal Haskell records** (5,602 lines vs 6,070 lines).

---

### Milestone T6: Refactoring, Linters & Semantic Code Modernizers [COMPLETED]
- **Execution Mode:** `[COLLABORATIVE-ASYNC]` (Executed & Verified in `scripts/tasks/verify-milestone-t6.sh`)
- **Motivation:** Automate the migration from nominal ADTs to open rows and prevent performance pitfalls in downstream codebases.
- **Deliverables:**
  1. **`retrie` & `hls-retrie-plugin` Equational Rewrites:**
     Defined semantic rewrite rules in `rules/retrie/`:
     - `rules/retrie/record-dot.rules`: `getField @"field" r` $\to$ `r.field`
     - `rules/retrie/batch-updates.rules`: sequential `setField` calls $\to$ transient `runMRep` / `setFieldsAt`
     - `rules/retrie/variant-eliminators.rules`: `matchVariant` / cascading cases $\to$ `eliminateUniform`
     - `rules/retrie/open-adt-migration.rules`: legacy nominal products/sums $\to$ `REC` and `VAR` sugar
  2. **`stan` & `hls-stan-plugin` Static Analysis:**
     Defined project `.stan.toml` and inspection specification in `rules/stan/POLYTROPOS_INSPECTIONS.md`:
     - `STAN-P01`: Repeated CoW updates in hot loops ($\mathcal{O}(M \cdot K \cdot N)$ allocations) $\to$ `setFieldsAt` / transient `MRep`
     - `STAN-P02`: Redundant `widenVariant` where source and destination rows are identical
     - `STAN-P03`: Unused/dead fields in open product rows
     - `STAN-P04`: Non-exhaustive manual `narrowVariant` cascades $\to$ total `eliminateUniform`
  3. **`hlint` & `hls-hlint-plugin` Rules:**
     Custom HLint hint rules implemented in `.hlint.yaml` and `rules/hlint/polytropos.yaml`:
     - `Use OverloadedRecordDot`: suggests `r.field` over explicit `getField @"field" r`
     - `Avoid chained setField (O(N*K) allocations)`: recommends `runMRep` or `setFieldsAt`
     - `Avoid repeated setField in foldl`: flags CoW loops
     - `Use peel for single-constructor elimination`: recommends `peel @"tag"`
     - `Use eliminateUniform for handler dispatch`: recommends $\mathcal{O}(1)$ jump-table eliminator
     - `Redundant widenVariant`: strips identity casts
     - `Use REC sugar instead of nested insertField` & `Use VAR pattern matching`
  4. **Unified Modernizer CLI & Documentation:**
     - `bin/polytropos-modernize`: automated CLI runner supporting `--check`, `--apply`, `--rules`, `--retrie-rules`, and `--stan-spec`
     - `docs/tools/MODERNIZER_AND_LINTER_GUIDE.md`: comprehensive tooling and migration guide
     - `scripts/tasks/verify-milestone-t6.sh`: deterministic gate asserting all rules against test fixtures

---

### Milestone T7: Program Synthesis, Formal Verification & Continuous Compilation [COMPLETED]
- **Execution Mode:** `[COLLABORATIVE-ASYNC]` (Executed & Verified in `scripts/tasks/verify-milestone-t7.sh`)
- **Motivation:** Bridge `polytropos` with formal methods, type-directed synthesis, and continuous zero-log compiler verification.
- **Deliverables:**
  1. **`liquidhaskell` Refinement Types:**
     Developed LiquidHaskell specifications and proof contracts under `verification/liquid/`:
     - `verification/liquid/Polytropos/Liquid/RowPredicates.spec`: Specifications for `SmallArray` bounds, `Rep` memory layouts, slot bounds, subrow projection, and field predicate refinements (`NatField`, `ValidPort`, etc.).
     - `verification/liquid/Polytropos/Liquid/Proofs.hs`: Typechecked Haskell module proving slot indexing safety (`safeFieldAt`), subrow memory safety (`safeProjectSubRow`), and variant eliminator exhaustiveness (`safeEliminateUniform`), compiling cleanly with GHC (`-Wall -Werror`).
     - `verification/liquid/Polytropos/Liquid/RowBounds.fq`: Liquid-Fixpoint Horn clause constraint system solved and verified `SAFE` (5 constraints) via Z3 SMT solver.
  2. **`synquid` Program Synthesis:**
     Author formal Synquid synthesis specifications under `synthesis/synquid/`:
     - `RecordAdapter-SubRow.sq`: Type-directed width subtyping record adapter synthesis.
     - `RecordAdapter-Permute.sq`: Field permutation record adapter synthesis.
     - `RecordAdapter-Defaults.sq`: Extension adapter with defaulted optional fields.
     - `VariantEliminator.sq`: Exhaustive variant eliminator dispatch synthesis.
     - `VariantSubsumption.sq`: Variant widening and constructor tag injection synthesis.
  3. **`tricorder` Continuous Compilation:**
     - Created workspace `.tricorder.yaml` multi-target GHCi daemon configuration.
     - Verified `tricorder-mcp` server registration in `.mcp.json`.
     - Provided `bin/polytropos-tricorder` CLI helper and `bin/polytropos-verify` runner.
  4. **Documentation & Deterministic Verification:**
     - `docs/tools/FORMAL_VERIFICATION_AND_SYNTHESIS_GUIDE.md`: Comprehensive guide.
     - `scripts/tasks/verify-milestone-t7.sh`: Deterministic verification test gate.

---

### Milestone T8: Source Formatters & Layout Engines [COMPLETED]
- **Execution Mode:** `[COLLABORATIVE-ASYNC]` (Executed & Verified in `scripts/tasks/verify-milestone-t8.sh`)
- **Motivation:** Ensure formatters do not mangle ergonomic syntactic sugar (`REC`, `VAR`, `REC_UPD`) or type-level row lists.
- **Deliverables:**
  1. **`fourmolu` & `ormolu` Support:**
     - Created root `fourmolu.yaml` with leading comma style, `record-brace-space: true`, aligned record style, and fixity declarations for `(:=)`, `(.==)`, and `(.#)`.
     - Verified AST-preserving formatting across `formatters/test/FormatFixtures.hs` for type-level rows, record dot projections, `peel`, and record pipelines.
  2. **`brittany` & `floskell` Layout Support:**
     - Created root `.brittany.yaml` with `lconfig_indentListSpecial: true`, multiline column alignment, and GHC option forwarding (`-XDataKinds`, `-XTypeOperators`, `-XOverloadedRecordDot`).
     - Created root `floskell.json` with alignment rules for record fields and operators.
  3. **Unified CLI & Documentation:**
     - `bin/polytropos-format`: executable runner supporting `--check`, `--apply`, `--ormolu`, `--brittany`, `--verify-configs`, and `--fixtures`.
     - `docs/tools/SOURCE_FORMATTERS_AND_LAYOUT_GUIDE.md`: comprehensive tooling and editor integration guide.
     - `scripts/tasks/verify-milestone-t8.sh`: deterministic verification test gate.

---

## 3. Four-Audience Documentation Overhaul Agenda

Governed by [`docs/notes/DOC_STRATEGY.md`](../docs/notes/DOC_STRATEGY.md):

### Audience 1: Newcomers (Concept Acquisition & Tutorials)
- **Target File:** [`docs/TUTORIAL.md`](../docs/TUTORIAL.md) and refreshed [`docs/NEWBIE_GUIDE.md`](../docs/NEWBIE_GUIDE.md).
- **Execution Mode:** `[COLLABORATIVE-ASYNC]` (Machine drafts full worked narrative; human reviews & edits).
- **Deliverables:**
  1. **The Conceptual Mental Model:**
     - What is row polymorphism? Why do open ADTs matter?
     - Why collapsing products and sums into a single representation (`Rep`: tag + flat `SmallArray`) unifies the nominal/structural design space.
     - Contrasting open records against nominal Haskell records and `GHC.Generics`.
  2. **Progressive Worked Tutorial:**
     - Lesson 1: Constructing records (`emptyRecord`, `insertField`, `[REC| ... |]`).
     - Lesson 2: Accessing and updating fields (`r.field`, `setFieldAt`, `[REC_UPD| ... |]`).
     - Lesson 3: Working with open variants (`Variant`, injection, projection, pattern matching).
     - Lesson 4: Subtyping in practice (`widenVariant`, `narrowVariant`, `projectRecord`).
     - Lesson 5: Building an extensible pipeline / configuration object.

---

### Audience 2: API Callers (Haddock Audit & Polish)
- **Target Files:** In-code Haddock throughout `packages/` (`polytropos-core`, `polytropos-plugin`, and 12 satellite packages).
- **Execution Mode:** `[COLLABORATIVE-ASYNC]` (Machine performs systematic scan & drafts improvements; human refines).
- **Deliverables:**
  1. **Systematic Clunkiness Audit:**
     - Scan all exported types, classes, and combinators.
     - Eliminate opaque type variable names (e.g. replace bare `f`, `m`, `c` with descriptive names where beneficial).
     - Ensure every exported function has a worked example and documented failure behavior.
  2. **Mathematical Precision & Invariants:**
     - Add inline Unicode invariants ($\forall r, O(1), O(N)$) per `DOC_STRATEGY.md` §1.
     - Ensure module headers provide orientation paragraphs and reading paths.

---

### Audience 3: Maintainers (Architecture & Invariant Preservation)
- **Target File:** Substantially expanded [`docs/MAINTAINER_GUIDE.md`](../docs/MAINTAINER_GUIDE.md).
- **Execution Mode:** `[COLLABORATIVE-ASYNC]` (Machine creates authoritative architectural draft; human reviews & marks corrections).
- **Deliverables:**
  1. **The Comprehensive Architectural Guide:**
     - Detailed explanation of Core AST generation, TcPlugin constraint interception, and `SmallArray` memory layouts.
     - Concrete walk-through of the dictionary-synthesis pipeline (`AllFields`, `SubRow`, `SubSum`, `KnownHash`).
  2. **Step-by-Step Maintenance Recipes:**
     - Recipe 1: How to add a new evidence class without introducing plugin stalls.
     - Recipe 2: How to create a new ecosystem satellite package (e.g. for `servant` or `esqueleto`).
     - Recipe 3: How to debug TcPlugin Core AST generation bugs and GHC internal panics.
  3. **Open Correction Process:** Clear guidelines inviting maintainers and contributors to revise and correct maintainer documentation as the codebase evolves.

---

### Audience 4: AI Assistants (Context Projections & Agentic Governance)
- **Target Files:** [`AGENTS.md`](../AGENTS.md) and [`.agents/rules/`](../.agents/rules/).
- **Execution Mode:** `[AUTONOMOUS-MACHINE]`
- **Deliverables:**
  1. **Strict Context Budget Maintenance:** Keep `AGENTS.md` strictly within its ~4 KB budget by maintaining pointer-file projections into canonical docs.
  2. **Agent Governance Invariants:**
     - Clear rules on when an AI agent can execute autonomously (`[AUTONOMOUS-MACHINE]`) vs. when it must yield for human feedback (`[HUMAN-GATED]`).
     - Zero-contamination doctrine enforcement (never touch Cabal project with external assistant tools).
     - Standardized commit attribution schema (`Assisted-by:` / `Orchestrated-by:` RFC 2822 trailers).
     - Fast code navigation via `tags` and `ast-grep` before viewing full files.

---

## 4. Prioritized Execution Phases

```mermaid
flowchart TD
    subgraph Phase 1: Machine Technical Enhancements [COMPLETED]
        T1["T1: Plugin Custom TypeError Diagnostics<br>[AUTONOMOUS-MACHINE] ✅"]
        T5["T5: Scale Re-Measurement in benchmark/variants<br>[AUTONOMOUS-MACHINE] ✅"]
        A4_doc["B4: AI Governance & Rules Refinement<br>[AUTONOMOUS-MACHINE] ✅"]
    end

    subgraph Phase 2: Collaborative Documentation & Eliminators [COMPLETED]
        T2["T2: Hybrid Eliminator & Peeling Primitives<br>[COLLABORATIVE-ASYNC] ✅"]
        B1_draft["B1: Tutorial & Newbie Guide Draft<br>[COLLABORATIVE-ASYNC] ✅"]
        B3_draft["B3: Authoritative Maintainer Guide Draft<br>[COLLABORATIVE-ASYNC] ✅"]
        B2_audit["B2: Haddock Scan & Clunkiness Audit<br>[COLLABORATIVE-ASYNC] ✅"]
    end

    subgraph Phase 3: Tooling & IDE Infrastructure Integration [ACTIVE]
        T4["T4: HLS / IDE Autocompletion & CodeActions<br>[COLLABORATIVE-ASYNC]"]
        T6["T6: Retrie, Stan, HLint & Wingman Tooling<br>[COLLABORATIVE-ASYNC]"]
        T7["T7: LiquidHaskell, Synquid & Tricorder Synthesis<br>[COLLABORATIVE-ASYNC]"]
        T8["T8: Ormolu, Fourmolu & Source Formatters<br>[COLLABORATIVE-ASYNC]"]
        T3["T3: Hardware SIMD CoW Updates<br>[AUTONOMOUS-MACHINE]"]
    end

    Phase 1 --> Phase 2
    Phase 2 --> Phase 3
```

- **Immediate Step:** Advance Phase 3 (Milestone T4: Implementing `OverloadedRecordDot` row autocompletion in `haskell-language-server`).
