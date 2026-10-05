# AGENTS.md — Advisory Context for AI Coding Assistants

Pointer file. Canonical sources win on any disagreement.

## What this repository is

`polytropos` — a row-polymorphic / open ADT engine for Haskell. One generic
representation (`Rep`: a tag plus a flat `SmallArray` of payload slots) serves
products and sums, so the four quadrants of the nominal/structural design space
collapse to one mechanism.

## Read first, in this order

1. `README.md` — what this is, and its status.
2. `docs/notes/POLYTROPOS_DESIGN.md` — the canonical design note: decisions
   D1–D10, known costs, and the open questions (§7).
3. `docs/INDEX.md` — corpus inventory and reading map.

## Operational advisories

1. **Design docs are load-bearing.** A change that makes the design note stale
   must correct the note in the same change set. Code wins at runtime; the
   note must still be fixed, not ignored.
2. **§4 (elimination) and §7 (open questions) are open on purpose.** Do not
   quietly settle them in code; the row shape may need rework once they are
   answered, and that is cheaper now than later.
3. **The tests specify the plugin.** The hand-written `RowEq` / `RowShow`
   instances in `polytropos-core/test/Main.hs` are the specification of what the
   TcPlugin must emit: literal indices, no type-level search. Keep them literal
   — a test that performs a type-level search no longer tests the point.
4. **Commits:** descriptive-imperative subject, body explains why, HEREDOC
   style. Attribution uses Linux kernel-style git trailers:
   `Assisted-by: <Tool> (<Provider> / <Model>)`.
5. **Toolchain:** GHC 9.14 / Cabal 3.18; features opt in via the cabal commons
   only. Tests: tasty.
6. **This file has a ~4 KB budget.** Add links, not content.
7. **Two-file loop.** Update `STATE.md` before ending or resetting a session;
   fresh sessions initialise from `PLAN.md` and `STATE.md`.
