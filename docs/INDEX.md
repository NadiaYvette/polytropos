# docs/INDEX.md — Corpus Inventory and Reading Map

Status: LIVING DOCUMENT · v0.1 · 2026-10-05

## Part 1 — Inventory

| Path | Genre | Stage | Tier | Flags |
|---|---|---|---|---|
| `notes/POLYTROPOS_DESIGN.md` | design | draft | cross-cutting | §4 answered; §7 Q1–Q3 closed; §7 Q4 nuanced; §7 Q5 open |
| `notes/COMMIT_ATTRIBUTION.md` | convention | blessed | cross-cutting | — |
| `notes/PROVENANCE.md` | convention | blessed | cross-cutting | — |
| `notes/DOC_STRATEGY.md` | strategy | blessed | cross-cutting | — |
| `registers/PACKAGES.md` | register | live | cross-cutting | — |
| `transcripts/gemini-large-data-hybrid-variant-records-spec.md` | transcript | archive | cross-cutting | inconsistent |

## Part 2 — Reading paths

**Newcomer.** `README.md` → design note §§0–2 (what and how it is represented)
→ §6 (why a plugin) → §7 (what is still open).

**Anyone changing the documentation.** `notes/DOC_STRATEGY.md` governs genres,
lifecycle, canonicity and tone. Its §4 precedence rule — code wins at runtime, the
note is corrected regardless — is the one that fires most often.

**Contributor.** Design note in full, then `packages/polytropos-core/src/Polytropos/Core.hs`
— it is sectioned §1–§6 to match the note, and the two must be read together.
Commit convention: `AGENTS.md` advisory 4, details in the attribution note.

**Reviewer.** The §3 widening/narrowing asymmetry is still the load-bearing
open shape; §4 (elimination) is now answered (hybrid + Option D vocabulary + Case 3
wrapper) and sketched in `PHASE2_SKETCH.md`. The remaining §7 open items are Q4
(`DictAny` fate) and Q5 (polytropos/large-anon coexistence).

**Someone new to the idea.** The transcript that started this
(`transcripts/gemini-large-data-hybrid-variant-records-spec.md`) explains the
appeal, but several of its claims about the existing codebase were later
measured and found false — read it as the question, then read
`benchmark/variants/README.md` for the answer.

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
