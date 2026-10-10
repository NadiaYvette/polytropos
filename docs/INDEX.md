# docs/INDEX.md — Corpus Inventory and Reading Map

Status: LIVING DOCUMENT · v0.1 · 2026-10-05

## Part 1 — Inventory

| Path | Genre | Stage | Tier | Flags |
|---|---|---|---|---|
| `NEWBIE_GUIDE.md` | guide | live | cross-cutting | — |
| `MAINTAINER_GUIDE.md` | guide | live | cross-cutting | — |
| `notes/POLYTROPOS_DESIGN.md` | design | draft | cross-cutting | §4 answered; §7 Q1–Q3 closed; §7 Q4 nuanced; §7 Q5 open |
| `notes/DESIGN_REVIEW_CLAUDE-OPUS-4.6.md` | review | draft | cross-cutting | — |
| `notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md` | design | draft | cross-cutting | — |
| `notes/SATELLITE_INTERFACES_DESIGN.md` | design | draft | cross-cutting | — |
| `notes/COMMIT_ATTRIBUTION.md` | convention | blessed | cross-cutting | — |
| `notes/PROVENANCE.md` | convention | blessed | cross-cutting | — |
| `notes/DOC_STRATEGY.md` | strategy | blessed | cross-cutting | — |
| `notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md` | notes | draft | cross-cutting | — |
| `notes/ROW_ROLE_DEFNS_DRAFT.ott` | notes | draft | cross-cutting | — |
| `notes/REVIEWER_WFU_ARGUMENT.md` | notes | draft | cross-cutting | — |
| `notes/EFFECT_SYSTEMS_PORTING_MASTER_PLAN.md` | plan | draft | cross-cutting | — |
| `notes/EFFECTFUL_POLYTROPOS_PORT_PLAN.md` | plan | draft | cross-cutting | — |
| `notes/POLYSEMY_POLYTROPOS_PORT_PLAN.md` | plan | draft | cross-cutting | — |
| `notes/KERNMANTLE_POLYTROPOS_PORT_PLAN.md` | plan | draft | cross-cutting | — |
| `registers/PACKAGES.md` | register | live | cross-cutting | — |
| `transcripts/gemini-large-data-hybrid-variant-records-spec.md` | transcript | archive | cross-cutting | inconsistent |
| `transcripts/gemini-powerful-abstraction-techniques-in-haskell.md` | transcript | archive | cross-cutting | — |

## Part 2 — Reading paths

**Newcomer.** `README.md` → `NEWBIE_GUIDE.md` (workflow & token conservation)
→ design note §§0–2 (what and how it is represented) → §6 (why a plugin)
→ §7 (what is still open).

**Maintainer.** `MAINTAINER_GUIDE.md` (governance & engineering invariants)
→ design note in full → `DOC_STRATEGY.md`.

**Anyone changing the documentation.** `notes/DOC_STRATEGY.md` governs genres,
lifecycle, canonicity and tone. Its §4 precedence rule — code wins at runtime, the
note is corrected regardless — is the one that fires most often.

**Contributor.** Design note in full, then `packages/polytropos-core/src/Polytropos/Core.hs`
— it is sectioned §1–§6 to match the note, and the two must be read together.
Commit convention: `AGENTS.md` advisory 4, details in the attribution note.

**Reviewer.** `notes/DESIGN_REVIEW_CLAUDE-OPUS-4.6.md` provides the holistic
architectural evaluation and ecosystem deployment assessment from the Claude Opus 4.6
perspective. The §3 widening/narrowing asymmetry is still the load-bearing open shape;
§4 (elimination) is now answered (hybrid + Option D vocabulary + Case 3 wrapper) and
sketched in `PHASE2_SKETCH.md`. The remaining §7 open items are Q4 (`DictAny` fate)
and Q5 (polytropos/large-anon coexistence).

**AI Coding Assistant.** `AGENTS.md` (bounded ~4 KB orientation projection) →
[`.agents/README.md`](../.agents/README.md) → subdivided domain rules in
`.agents/rules/` (`commit-attribution.md`, `code-navigation.md`,
`compiler-verification.md`, `documentation-precedence.md`, `plugin-invariants.md`).

**Task Packet Implementer / Autonomous Worker.**
`notes/FIELD_UPDATE_EFFICIENCY_DESIGN.md` & `notes/SATELLITE_INTERFACES_DESIGN.md`
→ sequential task packets in `task_packets/` (`task-01-field-update-cow.yaml` through
`task-19-satellite-quickcheck.yaml`) executed via `bin/yamaarashi-exec run`.

**Effect System Implementer / Library Porter.**
`notes/EFFECT_SYSTEMS_PORTING_MASTER_PLAN.md` (tri-paradigm synthesis)
→ per-package plans: `notes/EFFECTFUL_POLYTROPOS_PORT_PLAN.md` (`effectful` in-place environment),
`notes/POLYSEMY_POLYTROPOS_PORT_PLAN.md` (`polysemy` freer union variant),
`notes/KERNMANTLE_POLYTROPOS_PORT_PLAN.md` (`kernmantle` arrow pipeline).

**Someone new to the idea.** The transcripts in `transcripts/` record the
ideation context: `transcripts/gemini-powerful-abstraction-techniques-in-haskell.md`
discusses the architectural motivation for high-leverage abstractions (open ADTs,
algebraic effects, datatype generics, profunctors), while
`transcripts/gemini-large-data-hybrid-variant-records-spec.md` initiated the hybrid
variant record exploration (read alongside `benchmark/variants/README.md` for
measured corrections).

## Conventions

Column vocabularies are defined in `notes/DOC_STRATEGY.md` §3 (stages, flags) and
§5 (genre, directory); the values below are drawn from them. `Tier` is retained
from the inherited schema but carries only `cross-cutting` — see `DOC_STRATEGY.md`
§0.1 for why it has no discriminating power here.

- `notes/` — designs and specs; `registers/` — living registers; `transcripts/` —
  conversation archives. A new genre decides directory and suffix together.
- Genre, stage and tier are index metadata only; no filenames encode them.
- Superseded documents stay in place with successor links; there is no archive
  directory.
