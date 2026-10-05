# docs/INDEX.md — Corpus Inventory and Reading Map

Status: LIVING DOCUMENT · v0.1 · 2026-10-05

## Part 1 — Inventory

| Path | Genre | Stage | Tier | Flags |
|---|---|---|---|---|
| `notes/POLYTROPOS_DESIGN.md` | design | draft | cross-cutting | — |

## Part 2 — Reading paths

**Newcomer.** `README.md` → design note §§0–2 (what and how it is represented)
→ §6 (why a plugin) → §7 (what is not decided).

**Contributor.** Design note in full, then `polytropos-core/src/Polytropos/Core.hs`
— it is sectioned §1–§6 to match the note, and the two must be read together.

**Reviewer.** The two things most worth attacking: §3 (the widening/narrowing
asymmetry) and §4 (elimination). Both are marked open on purpose.

## Conventions

- `notes/` — designs and specs; `registers/` — living registers; `imports/` —
  verbatim third-party material; `transcripts/` — conversation archives.
- Genre, stage and tier are index metadata only; no filenames encode them.
- Superseded documents stay in place with successor links; there is no archive
  directory.
