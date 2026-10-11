<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Evaluation of Candidate Tutorial Example Ideas

**Status:** LIVING STRATEGY NOTE · v1.0 · 2026-10-11  
**Audience:** Documentation Authors, Educators, AI Assistants  
**Context:** Formulates the roadmap for worked code examples for **Audience 1: Newcomers (Newbies)** per [`docs/notes/DOC_STRATEGY.md`](DOC_STRATEGY.md) and [`plans/FULL_COMPLETION_ROADMAP.md`](../../plans/FULL_COMPLETION_ROADMAP.md). Provides a permanent register of candidate pedagogical examples evaluated for cognitive load, instructional transfer, and code ergonomics.

---

## 1. Candidate Example Evaluation Matrix

The candidate example concepts below were identified and synthesized from research transcripts ([`gemini-optimising-language-design-for-AI.md`](../transcripts/gemini-optimising-language-design-for-AI.md), [`gemini-scaling-autonomous-coding.md`](../transcripts/gemini-scaling-autonomous-coding.md), and [`gemini-resilient-and-error-tolerant-parsing-strategies.md`](../transcripts/gemini-resilient-and-error-tolerant-parsing-strategies.md)):

| Candidate Concept | Pedagogical Value | Cognitive Load for Newbies | Implementation Invariants Exercised | Verdict & Staging |
|---|---|---|---|---|
| **A. Nanopass Row Subtraction (`desugarWhile`)** | **Very High**: Mathematically proves language construct elimination at compile time. | **Low to Moderate**: Pure syntactic tree rewrite; no heavy categorical or monadic machinery needed. | Open variant extension, single-constructor peeling (`peel`), sub-row widening (`widenVariant`), $O(1)$ dispatch. | **Primary Worked Tutorial Example**: Anchor for [`docs/TUTORIAL.md`](../TUTORIAL.md). Directly illustrates why open rows beat closed nominal sums. |
| **B. Resilient Parsing & AST ("Stope and Winze")** | **Highest**: Models syntax errors as explicit variant nodes (`ParseHole`), demonstrating semantic containment and error recovery. | **Moderate**: Requires understanding open error nodes, partial evaluation, and wildcard types (`ErrorType`). | Variant injection, view patterns, sub-variant narrowing, error containment without exceptions. | **Secondary / Advanced Example**: Follow-up chapter or dedicated case study for compiler frontends and IDE language servers. |
| **C. Profunctor IR Lowering (`Star`, `Costar`, `Choice`)** | **High for Systems**: Translates high-level algebraic effect ASTs to MLIR/GIMPLE/C-ABI representations. | **Very High**: Newcomers easily get bogged down in profunctor optics (`dimap`, `Choice`) rather than row polymorphism. | Profunctor dictionary synthesis, extensible metadata rows, variant branching. | **Deferred to Ecosystem Satellites**: Suitable for advanced compiler engineering notes or satellite packages. |
| **D. Relational AST / Code-in-Database** | **High for Architecture**: Replaces recursive AST pointers with relational keys (`DbId`), using open variants as SQL schemas. | **High**: Entangles database normalization, foreign keys, and SQL codecs with language syntax. | `Record` and `Variant` database codecs (e.g., `polytropos-rel8`, `polytropos-persistent`), incremental views. | **Deferred to Architecture Showcase**: Reference pattern for agentic coding protocols and persistent ASTs. |

---

## 2. Pedagogical Staging Principles

To ensure newcomers (both humans and AI coding assistants) achieve concept acquisition without token or attention degradation:

1. **Stage 1: Pure Polytropos First (Zero-Dependency Horizon)**
   - Introduce `Record` and `Variant` as standalone, first-class Haskell data structures.
   - Use plain functions and `IO` for early examples.
   - Do not require newcomers to understand algebraic effect systems or arrow frameworks simultaneously.

2. **Stage 2: Targeted Micro-Examples for Core Primitives**
   - Provide minimal, focused snippets illustrating specific primitives:
     * Construction & field access: `emptyRecord`, `insertField`, `[REC| ... |]`, `r.field`.
     * Variant injection & matching: `injectVariant`, `projectVariant`, `[VAR| ... |]`, view patterns.
     * Whole-variant elimination: `eliminate`, `eliminateUniform`.
     * Subtyping & transformations: `peel`, `widenVariant`, `narrowVariant`, `projectRecord`.

3. **Stage 3: End-to-End Real-World Architectures**
   - Anchor the tutorial in a practical, compelling problem (e.g., the Nanopass compiler pass) that clearly demonstrates where closed nominal ADTs fail and open row polymorphism shines.
   - Highlight how GHC typechecker diagnostics guide the programmer during refactorings.

4. **Stage 4: Ecosystem & Effect System Bridges**
   - Once the standalone row mechanics are mastered, demonstrate how `polytropos` integrates with ecosystem satellites and effect systems (`effectful-polytropos`, `polysemy-polytropos`, and `kernmantle-polytropos`).
