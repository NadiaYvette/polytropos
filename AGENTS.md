# AGENTS.md — Advisory Context for AI Coding Assistants

Pointer file. Canonical sources win on any disagreement.

## What this repository is

`polytropos` — a row-polymorphic / open ADT engine for Haskell. One generic
representation (`Rep`: a tag plus a flat `SmallArray` of payload slots) serves
products and sums, so the four quadrants of the nominal/structural design space
collapse to one mechanism.

## Read first, in this order

1. `README.md` — what this is, and its status.
2. `PLAN.md` & `STATE.md` — operational roadmap and active session frontier.
3. `docs/notes/POLYTROPOS_DESIGN.md` — the canonical design note: decisions
   D1–D10, known costs, and the open questions (§7).
4. `docs/notes/DOC_STRATEGY.md` — documentation policy: genres, lifecycle,
   canonicity, tone. §4's precedence rule is the one that fires most.
5. `docs/INDEX.md` — corpus inventory and reading map.

## Subdivided operational rules (`.agents/rules/`)

To conserve context tokens and prevent attention degradation, operational
guidance is subdivided into modular rules loaded on demand:

- [`.agents/rules/commit-attribution.md`](.agents/rules/commit-attribution.md) —
  Linux kernel RFC 2822 trailer format (`Assisted-by:`), DCO boundaries, and hook enforcement.
- [`.agents/rules/code-navigation.md`](.agents/rules/code-navigation.md) —
  Token-saving funnel (`./tags` symbol jump, `ast-grep`, targeted slice viewing).
- [`.agents/rules/compiler-verification.md`](.agents/rules/compiler-verification.md) —
  Zero-log compiler verification (`tricorder status --json`), tests, and zero-contamination.
- [`.agents/rules/documentation-precedence.md`](.agents/rules/documentation-precedence.md) —
  Precedence rule ("code wins at runtime; notes corrected regardless") and the two-file loop.
- [`.agents/rules/plugin-invariants.md`](.agents/rules/plugin-invariants.md) —
  TcPlugin literal index calculation, Core AST synthesis, and selector safety.

## Operational advisories

1. **Design docs are load-bearing.** A change that makes the design note stale
   must correct the note in the same change set. Code wins at runtime; the
   note must still be fixed, not ignored. (`DOC_STRATEGY.md` §4.)
2. **§4 (elimination) and §7 (open questions) are open on purpose.** Do not
   quietly settle them in code; the row shape may need rework once they are
   answered, and that is cheaper now than later.
3. **The tests specify the plugin.** The hand-written `RowEq` / `RowShow`
   instances in `packages/polytropos-core/test/Main.hs` are the specification
   of what the TcPlugin must emit: literal indices, no type-level search. Keep them
   literal — a test that performs a type-level search no longer tests the point.
4. **Commits:** descriptive-imperative subject, body explains why, HEREDOC
   style. AI attribution uses git trailers per `sarutahiko`:
   `Assisted-by: <Tool> (<Provider> / <Model>)` (or `<Tool>`) and optional
   `Orchestrated-by: <Engine>`. Never `Co-authored-by:` or `Signed-off-by:`
   for AI tools (only humans certify the DCO). Enforced by `.githooks/commit-msg`;
   template in `.gitmessage`; see `docs/notes/COMMIT_ATTRIBUTION.md`.
5. **Toolchain:** GHC 9.14 / Cabal 3.18; features opt in via the cabal commons
   only. Tests: tasty.
6. **This file has a ~4 KB budget.** Add links, not content.
7. **Two-file loop.** Update `STATE.md` before ending or resetting a session;
   fresh sessions initialise from `PLAN.md` and `STATE.md`.
8. **Keep source-mapping notes current.** When a design doc rests on external
   sources, the anchor goes inline at the claim, and the source-mapping note
   for that doc must be kept current as the sources change. For the row/role
   judgement draft, that is `docs/notes/ROW_ROLE_DEFNS_DRAFT.ott` and
   `docs/notes/REVIEWER_WFU_ARGUMENT.md`.
