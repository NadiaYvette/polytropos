# docs/INDEX.md — Corpus Inventory and Reading Map

Status: LIVING DOCUMENT · v0.1 · 2026-10-05

## Part 1 — Inventory

| Path | Genre | Stage | Tier | Flags |
|---|---|---|---|---|
| `notes/POLYTROPOS_DESIGN.md` | design | draft | cross-cutting | — |
| `notes/COMMIT_ATTRIBUTION.md` | convention | live | cross-cutting | — |
| `notes/PROVENANCE.md` | convention | live | cross-cutting | — |
| `registers/PACKAGES.md` | register | live | cross-cutting | — |
| `transcripts/gemini-large-data-hybrid-variant-records-spec.md` | transcript | archive | cross-cutting | superseded in part |

## Part 2 — Reading paths

**Newcomer.** `README.md` → design note §§0–2 (what and how it is represented)
→ §6 (why a plugin) → §7 (what is not decided).

**Contributor.** Design note in full, then `packages/polytropos-core/src/Polytropos/Core.hs`
— it is sectioned §1–§6 to match the note, and the two must be read together.
Commit convention: `AGENTS.md` advisory 4, details in the attribution note.

**Reviewer.** The two things most worth attacking: §3 (the widening/narrowing
asymmetry) and §4 (elimination). Both are marked open on purpose.

**Someone new to the idea.** The transcript that started this
(`transcripts/gemini-large-data-hybrid-variant-records-spec.md`) explains the
appeal, but several of its claims about the existing codebase were later
measured and found false — read it as the question, then read
`benchmark/variants/README.md` for the answer.

## Conventions

- `notes/` — designs and specs; `registers/` — living registers; `imports/` —
  verbatim third-party material; `transcripts/` — conversation archives.
- Genre, stage and tier are index metadata only; no filenames encode them.
- Superseded documents stay in place with successor links; there is no archive
  directory.
