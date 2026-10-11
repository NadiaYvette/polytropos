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

### Milestone T3: Hardware-Vectorized SIMD CoW Updates
- **Execution Mode:** `[AUTONOMOUS-MACHINE]`
- **Motivation:** Fulfills `docs/notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md` for high-throughput record updates.
- **Deliverables:**
  1. Implement SIMD-vectorized array copy primitives for records with $>32$ fields using GHC primitives or byte-aligned block copies.
  2. In-place batch mutation fast-paths in `MRep` transient builders.
- **Verification:** Microbenchmarks measuring throughput on records up to 100 fields.

---

### Milestone T4: HLS / IDE Autocompletion Ergonomics & Tooling Bridge
- **Execution Mode:** `[COLLABORATIVE-ASYNC]`
- **Motivation:** Directly resolves Barrier #6 ("No autocompletion in IDE / tooling").
- **Deliverables:**
  1. Evaluate how `Haskell Language Server` handles `OverloadedRecordDot` over `Record r` and identify why completions are missing.
  2. Design a lightweight HLS plugin or code-action provider / nominal wrapper generator that exposes record field symbols to the LSP completion engine.
- **Verification:** Manual verification in VS Code / Neovim with HLS.

---

### Milestone T5: Scale Re-Measurement Against Prior Art
- **Execution Mode:** `[AUTONOMOUS-MACHINE]`
- **Motivation:** Empirically demonstrate the compile-time and runtime claims of `POLYTROPOS_DESIGN.md` §6.
- **Deliverables:**
  1. Re-run `benchmark/variants` with the complete `Polytropos.Plugin` enabled.
  2. Measure compile times for records and sums at $N \in \{5, 10, 20, 50, 100\}$.
  3. Compare against `vinyl`, `large-anon`, and standard `GHC.Generics`, confirming $O(N)$ linear scaling vs. $O(N^{2.8})$ polynomial explosion.

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
    subgraph Phase 1: Machine Technical Enhancements
        T1["T1: Plugin Custom TypeError Diagnostics<br>[AUTONOMOUS-MACHINE]"]
        T5["T5: Scale Re-Measurement in benchmark/variants<br>[AUTONOMOUS-MACHINE]"]
        A4_doc["B4: AI Governance & Rules Refinement<br>[AUTONOMOUS-MACHINE]"]
    end

    subgraph Phase 2: Collaborative Documentation Drafts
        B1_draft["B1: Tutorial & Newbie Guide Draft<br>[COLLABORATIVE-ASYNC]"]
        B3_draft["B3: Authoritative Maintainer Guide Draft<br>[COLLABORATIVE-ASYNC]"]
        B2_audit["B2: Haddock Scan & Clunkiness Audit<br>[COLLABORATIVE-ASYNC]"]
    end

    subgraph Phase 3: Advanced Capabilities & Settlement
        T2["T2: Hybrid Eliminator & RowFlavour Settlement<br>[COLLABORATIVE-ASYNC]"]
        T3["T3: Hardware SIMD CoW Updates<br>[AUTONOMOUS-MACHINE]"]
        T4["T4: HLS Autocompletion Exploration<br>[COLLABORATIVE-ASYNC]"]
    end

    Phase 1 --> Phase 2
    Phase 2 --> Phase 3
```

- **Immediate Step:** Begin Phase 1 (Target T1: Custom `TypeError` diagnostics in `Polytropos.Plugin` and Target B4: AI rules refinement), which requires zero human blocking and directly eliminates the community's primary frustration regarding error messages.
