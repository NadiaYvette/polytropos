<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# The Documentation Strategy

Status: POLICY · v1.0 · 2026-10-05 — sections §1–§11 decided; see the decision log.
Adapted from `~/src/sarutahiko/docs/notes/DOC_STRATEGY.md` (same maintainer, same
licence). Section numbering is preserved deliberately, so the two documents can be
diffed and so cross-references stay stable. What did **not** transfer, and why, is
§0.1 — read that before assuming a missing section was overlooked.

Related: `POLYTROPOS_DESIGN.md` (the design this corpus documents),
`registers/PACKAGES.md` (register discipline), `PROVENANCE.md` (licensing),
`COMMIT_ATTRIBUTION.md` (commit trailers), `~/src/sarutahiko/docs/registers/REUSE_REGISTER.md`
(the source document's own companion)

---

## 0. What this document is

The corpus is small and mostly code-bearing: one package, one design note, one
benchmark, four conventions. Its *policies* are nonetheless implicit and already
load-bearing — `AGENTS.md` carries three of them already, and this document is
where they become one referable thing with a rationale.

Its scale differs from the source document by roughly two orders of magnitude,
and the adaptations below mostly follow from that. Where a rule is inherited
wholesale it says so; where it is changed it says why.

### 0.1 Not carried over

Recorded so their absence reads as a decision rather than an oversight.

| Dropped | Why |
|---|---|
| LaTeX whitepaper programme, `telix`/`nadie` apparatus donors, i18n and Japanese typesetting | No whitepaper programme here, and none is planned; a library with one package does not need a CJK-capable document toolchain. |
| The doc-drift **judge** (§2's LLM assessment instrument, its oracle consensus, the finding store) | Machinery for a twenty-file corpus with subsystem maintainers. The *precedence rule* it enforces (code wins; the note is corrected regardless) is already in force via `AGENTS.md` advisory 1 and is kept here. Revisit when the corpus passes ~15 files. |
| Glossary register | Three terms are in play. A one-line index is not worth a file that must be kept current. |
| Tier column (substrate/streaming/database/…) | polytropos has no subsystems to tier. `cross-cutting` was the only value any document would carry, which is information-free. |
| Noh naming registry, `NIH_PLAN` backlog, `CODEC_QUICKS`, `EFFECT_CATALOG_DESIGN` | Project-specific or not-yet-existing. **No naming registry is adopted** — polytropos shares sarutahiko's documentation skeleton, explicitly not its naming. |
| Radicle, subsystem maintainers / delegates, the "vassal" gate | Single maintainer. The gate structure is defined in §4 and staffed by one person; stating that explicitly is better than implying multi-party review. |
| docs-words/core-LOC ratio (§11 of the source) | Its purpose was to make documentation intensity visible against a specific thesis about code volume. polytropos has no such thesis. §11 is repurposed instead. |
| `CREDITS.md`, `LICENSES/` | Superseded by `THIRD_PARTY.md` and per-package `LICENSE` sections, which this repo established first. |

## 1. The audience map — three audiences, three genres

Inherited from the source and still the right shape: purpose-built documents per
audience, with canonicity fixed **per fact class** rather than per document.

**Arrivals → orientation.** `README.md` and the newcomer reading path in
`docs/INDEX.md`. Canonical for orientation facts only; always deferring to
canonical sources for technical claims. The source document's *scaled textbook
with enlightenment-forcing exercises* is **deferred**: polytropos has one module
and 25 tests. Revisit if a tutorial track appears.

**API consumers → Haddock, deliberately more verbose than ecosystem convention.**
Haddock runs to full paragraphs — invariants, failure behaviour, worked examples —
with no length quota and no filler; the test is whether each sentence earns its
place. Inline Unicode math (∀ es, O(n), r₁ ++ r₂) is the house style. A claim with
an external source *links to it*. `--hyperlinked-source` on. Module intros
mandatory.

**Maintainers → the corpus.** `docs/notes/` and `docs/registers/`, canonical for
rationale and decisions. Open questions live in `POLYTROPOS_DESIGN.md` §7 and are
enumerated rather than folk knowledge.

**AI assistants → pointer projections and code intelligence.** Inherited whole;
it is the most transferable part of the source document, because a corpus read by
agents has an audience no human register serves. `AGENTS.md` is a bounded pointer
file (~4 KB) into selectively loadable canonical documents — a projection, never
a restatement. Code intelligence data (`.hie` files, `hiedb`) is derived, never
hand-maintained.

Canonicity per fact class: **decisions** → registers and this document, per domain;
**design rationale** → the design note; **package origin, class and licence** →
`registers/PACKAGES.md`; **licence obligations** → `PROVENANCE.md` + `THIRD_PARTY.md`;
**commit attribution** → `COMMIT_ATTRIBUTION.md`; **measured compile-time claims**
→ `benchmark/variants/README.md` (see §11); **orientation** → `README.md` and the
index reading paths.

## 2. Single source of truth and drift

Any fact written twice drifts. Duplications that exist here: compile-time figures
(design note ↔ benchmark README), package inventory (`PACKAGES.md` ↔ `cabal.project`),
licence facts (`THIRD_PARTY.md` ↔ package `LICENSE`), attribution (`AGENTS.md` ↔
`COMMIT_ATTRIBUTION.md`). Each has one canonical home; the others link.

**Repairs are proposed, never applied.** As in the source: mechanical repairs
(path rewrites, stale links) are cheap enough to do directly, but a machine that
can silently rewrite prose will eventually rewrite a *decision*. The rule is that
flag-clearing is human-gated and batched — sweep, triage, one repair change per
cycle — so human attention scales with adjudication rather than with commit volume.

**The deterministic net is not deferred, because it is not expensive.** A script
checking that every relative link resolves, every `docs/` document has an inventory
row in `docs/INDEX.md`, and every path named in a document exists is a day's work
and catches the common failure. The LLM layer above it is what is deferred (§0.1).

## 3. Lifecycle and authority

Inherited wholesale; the stage vocabulary is what `docs/INDEX.md` already uses.

**Stages**, carried in each document's Status header:

1. `seed` — issue space recorded, policy pending. A seed needs no owner and no
   cadence; its only obligation is presence in the index, so a parked idea is not lost.
2. `draft` — full draft exists, pre-review.
3. `review` — under maintainer review; challenges pending.
4. `blessed` — decisions adopted; blessing date in the Status header and a row in §12.
5. `implemented` — the blessed design realized in code; stamped at the implementing
   change. Partial stamps permitted (`implemented (core, 2026-10-…)`).
6. `superseded` — replaced; **must link its successor**.
7. `dead` — removed from the tree; tombstoned (below).

Stages 1–7 govern **notes**, which record decisions and therefore have a
lifecycle. Two further values apply to the other genres, which are not decision
artifacts and have no blessing step:

8. `live` — a living register or inventory: append-only by its own rules, never
   blessed, superseded in place rather than replaced. `registers/`.
9. `archive` — a preserved record kept for provenance: verbatim, never edited, not
   canonical for anything. `transcripts/`.

The distinction is the point: a note at `draft` is work pending adoption, whereas a
register at `live` is finished and merely accumulating. Collapsing the two would
make "needs a decision" indistinguishable from "needs a row".

**Invalidity flags** — an orthogonal overlay on stages 2–5, so that an implemented
document can be inconsistent without leaving `implemented` and repair need not force
a re-blessing cycle. Carried in the Status header: `erroneous`, `inconsistent`,
`stale`, `dead-links`, `needs-work`.

*Effect of a flag:* the document is not citable as canonical for the fact classes its
flags touch, until cleared. Repair is an ordinary commit; no re-blessing unless the
repair changes a decision.

**Revision in place vs new document:** revise in place when identity and scope
survive the change (a correction of record, the challenge preserved in history); a
new document when scope or thesis changes. Living documents are append-only by their
own rules — never deleted, superseded in place.

**Dead documents and the attic.** Removal is `git rm` plus a tombstone row in
`docs/registers/ATTIC.md` — to be created on first use — carrying: title, former
path, removal commit SHA, last-content SHA, reason, successor link. Git history is
the content store (`git show <last-content-sha>:<former-path>`); nothing is stubbed
in-tree. Version-qualified references keep stale links resolving: Hackage
version-qualified docs for released packages, tag-pinned source links otherwise.

**The working example.** The Gemini transcript in `docs/transcripts/` is the only
document currently carrying a defect flag. It asserts three things about the
`large-data` codebase that later measurement found false, so it carries
`inconsistent` in the index and its provenance header points at the benchmark. It
stays in the tree: an archive record that quietly contradicts the design note is
worse than no archive.

Note what the flag does and does not do here. The document is at stage `archive`,
so `superseded` would be wrong — nothing replaced it, and it is not going to be
revised. The flag marks the *claims* as not citable; it does not demote the
document out of the archive, because an uncorrected primary source with a stated
correction is worth more than one quietly deleted.

## 4. The rot problem — design ahead of code

Most of this corpus describes unbuilt systems, so a blessed note can silently
diverge from the code that eventually implements it. Inherited, and the single most
load-bearing rule in the document:

> **Code wins at runtime; the note must be corrected regardless.** A behaviour
> change without a note correction is an incomplete change. Blessed notes are not
> granted advisory status.

This is already `AGENTS.md` advisory 1 and it has already fired: moving
`polytropos-core` under `packages/` changed paths that three documents named, and
the correction landed in the same change as the move.

**Anchoring is part of the doc, not decoration.** When a design note or
strategy makes a claim that rests on an external source, the anchor goes
inline at the claim, not just in a related-doc list. The rule is: a claim
that rests on a source is non-canonical unless the source is named at the
claim, and a doc that cites sources must keep those citations current as
the sources change. `ROW_ROLE_DEFNS_DRAFT.ott` §0 and each judgement's
alignment note are the in-progress example; `docs/notes/REVIEWER_WFU_
ARGUMENT.md` is the canonical source-mapping record for that draft's
argument. The maintenance commitment is: when a source changes (new
version, superseded reference, corrected reading), update the claims that
rested on it, or explicitly weaken them. This is §4's precedence rule
applied to citations, not just to code.

**Stamp mechanics** — the implementing change self-stamps `proposed-implemented`;
CI gates must pass; the maintainer accepts; the stamp records package and date.
The check is bidirectional — stamps without realizing code, and realizing code
without stamps.

**The partial-realization shield.** Consistency checks misfire on deliberately
unrealized work, and this corpus is full of it: §4 of the design note (elimination)
and §7 (five open questions) are open *on purpose*. A blessed note carries an
**unrealized-surface inventory** — its `pending` entries plus explicitly deferred
scope. Checks suppress or annotate findings inside the granted surface; every
suppressed finding must cite its shield, so suppression is auditable; shields
**expire** — a pending entry with no birth event across a milestone boundary
converts from shield to finding.

This is why `AGENTS.md` advisory 2 exists. §4 and §7 are not oversights and must
not be quietly settled in code.

**Pre-birth documentation.** Documentation for unwritten code is most of this
corpus today, and a reference to planned work is healthy, not a defect — so it does
not ride §3's flag overlay. Instead: prospective references carry an inline
`[planned: …]` marker; the implementing change that brings the artifact into
existence removes the markers (the **birth event**); if the design dies first, the
references die with it. The frontier is typed — planned, dormant, born — rather than
confused with error states.

**Gates.** CI gates (build, tests, `cabal check`) plus a review gate held by the
maintainer. Until collaborators exist the maintainer occupies every gate, stated
plainly so the policy implies no multi-party fiction. Where authorities disagree
there is no ambient "maintainer wins": the maintainer overrides by **explicit
recorded decision** naming the dispute, the overridden authority, and the reasoning.

## 5. Structure and discoverability

**Directories**, inherited and already in force:

| Directory | Holds |
|---|---|
| `docs/notes/` | Design notes, specs and strategies. The suffix-as-genre table (`_DESIGN`, `_SPEC`, `_STRATEGY`, `_PLAN`) governs within. |
| `docs/registers/` | Living registers and inventories. `PACKAGES.md` today; `ATTIC.md` on first tombstone (§3). |
| `docs/transcripts/` | Conversation transcripts as archive (§9). |
| `benchmark/` | Measurement harnesses. **Outside `docs/` on purpose**: it is executable evidence, not prose, and must not be swept into a word count or a link net. |

A new genre decides directory and suffix together at creation.

**Transcripts: title = origin, filename = topic.** Inherited whole, and applied
already. An inherited title names the session, which is not the topic; the filename
must be findable by what the document contains. Hence
`gemini-large-data-hybrid-variant-records-spec.md` rather than the session title.
Transcripts are freely renamable; every one carries a provenance header.

**Hybrid index.** `docs/INDEX.md` has an inventory table (path, genre, stage,
flags) plus hand-curated reading paths per §1 audience. The inventory is *generated*
from Status headers so it cannot drift; the reading paths are hand-written because
they encode judgement. A reader new to the idea is pointed at the transcript that
started it **and** the measurement that corrected it, in that order — the two are
useless apart.

**No archive directory.** Superseded documents stay in place with successor links;
dead documents leave via §3's tombstone. The index's flags column is the archive.

**Cross-references: IDs canonical, links convenience.** ID citations (§-numbers,
`D1`–`D10`, the design note's `Q1`–`Q5`) are the stable layer and survive renames.
Relative hyperlinks are the convenience layer. **Local divergence from the source
document, recorded deliberately:** sibling checkouts are referenced as `~/src/…`
in house style for local co-development paths, not by `../..` traversal. For published
artifacts and public forks (such as the ecosystem repositories modified for polytropos),
their canonical public mirror URLs (across GitHub, GitCode, Disroot, Framagit) and Radicle URNs
are authoritatively cataloged in `docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md`.
Published things get URLs; unpublished local checkouts get `~/src/…`.

## 6. Rendering and build infrastructure

Mostly **not applicable** at this scale, and stated rather than silently skipped.

**Canonical source and projections.** The git markdown corpus is canonical. There
are no mirrors, no rendered site, no PDF track. When any of those arrive, the
inherited rule applies immediately: every other format is a projection, and
rendered artifacts are never committed.

**Haddock** is the one real obligation, per §1: per-package units, mandatory module
intros, `--hyperlinked-source`, laws carrying their identifiers.

**Glossary, i18n, literate Haskell, whitepapers:** not adopted. See §0.1.

## 7. Terminology and style control

**The dense rationale-first register is canonical and codified by declaration,
not by rulebook.** Design notes keep it — dense, rationale-first, table-heavy,
present tense for stable truth. User-facing surfaces (`README.md`) follow
developer-documentation register: second person, active voice, fewer words. The
style is held by review, not by a rulebook that would itself drift.

**Assistant-context budgets.** `AGENTS.md` is an explicit pointer file with a ~4 KB
budget — an index into selectively loadable canonical documents, not a restatement
of them. This is a design constraint, not an accident. Canonical documents lead
with a short header block (status, related, thesis) so a small-context reader can
decide *whether* to load more without reading it all.

The ~4 KB budget is load-bearing in a way that is easy to erode: every rule added to
`AGENTS.md` costs every agent that reads it on every session. Add links, not content.

## 8. Co-authorship and authority

Inherited whole. The corpus is **AI-drafted and maintainer-blessed**, by policy.
Blessing certifies that the maintainer read it, challenged it where needed, and owns
it — an authority transfer, not a rubber stamp. Future human contributions land
under the same review. CI gates apply to documentation changes exactly as to code.

Every document in this repository that was not written by hand says so, in the place
where a reader will look before relying on it. See §9.

## 9. Exposure, credit and tone

**Everything here is meant to be public** — pulled, mirrored, read. No document class
gets a private treatment.

**Credit is granted by choice, not only where an obligation attaches.** This is the
source document's position and polytropos adopts it deliberately. `THIRD_PARTY.md`
records derivation sources — including ones whose approaches were *rejected*,
because design analysis is derivation. The current index is small: `large-anon`'s
observation that a row-polymorphic *accessor* is what costs rather than the sum is
the load-bearing idea, and `large-records` framed the problem.

Credit is recorded in the ledger; it is **not** recorded in commit trailers. The
trailer describes the commit, the document describes the material — see
`COMMIT_ATTRIBUTION.md`, which is where that distinction is drawn, and where the
kernel's bare `Assisted-by: LLM` rule is explained.

**Tone: the about-face.** Differing-design discussions use a respectful engineering
register: state what the other design optimizes for, what was chosen instead, and
why. Criticism targets designs, never people. Charged phrasings get rewritten in our
voice. **Verbatim transcripts are archived records** — they retain their original
language under a quotation header marking them as unedited third-party-voiced
history. The tone policy governs our voice, not the archive.

This is why the transcript's header names Gemini and preserves its claims verbatim
rather than quietly correcting them. Correction belongs in the document that makes
the claim ours — the benchmark — with the transcript pointing at it.

## 10. Boundaries with adjacent artifacts

**Benchmark evidence.** `benchmark/` is canonical for measured compile-time claims
and is referenced *by* prose, never duplicated into it. A number appearing in the
design note is a citation of `benchmark/variants/results.csv`, not a second copy;
the benchmark README's own consistency rules govern its numbers (§11).

**ADRs: declined as a foreign format.** The design note *is* the decision record —
rationale, open questions, decisions `D1`–`D10`, all in one place. The §12 decision
log supplies the numbered-decision essence an ADR would capture. ADR tooling would
duplicate at lower fidelity.

**CHANGELOGs** are PVP-tied and per-package; owned by the package, not by this
document.

**TODOs** are owned canonically by the design note's §7 open-questions section, which
is enumerated and machine-anchorable. Closing a question updates that section in the
same change that answers it.

## 11. The measurement interaction

Repurposed from the source document. That one tracked documentation *intensity*
against a LOC budget; polytropos has neither, but it has something better — the
corpus is **built on measurement**, and that has a documentation cost worth naming.

**Measurement is a first-class documentation citizen.** The compile-time argument
for the whole project is an empirical claim, held in an executable harness that a
reader can re-run in two commands. Prose cites it; prose does not restate it.

Three rules follow, all learned the hard way:

1. **A measurement's environment is part of its result.** The harness passes
   `-package-env -` because a stray `.ghc.environment.*` in an ancestor directory
   changes how GHC qualifies names, which changes line wrapping, which changed every
   figure by ~7% while two runs in the same directory agreed exactly. A number
   without its reproduction conditions is not a measurement.
2. **Say which columns are reproducible.** Core line counts are deterministic; peak
   RSS and wall time are not. A blanket "reproduces exactly" is false and costs a
   reader an afternoon.
3. **A benchmark is not a doc.** It lives outside `docs/`, is never part of
   `cabal build all`, and must be compiled in isolation at the optimization level
   its methodology requires — otherwise a convenience build silently invalidates it.

When a design decision rests on a measurement, the note cites the artifact and the
artifact's own caveats travel with it. Corrections propagate to the note in the same
change; that is §4's precedence rule applied to evidence rather than to code.

## 12. Decision log

| Date | Decision |
|---|---|
| 2026-10-05 | Imported from `~/src/sarutahiko/docs/notes/DOC_STRATEGY.md` (v1.0, 2026-09-24), same maintainer and licence. Section numbering preserved deliberately so the documents diff and cross-references stay stable. |
| 2026-10-05 | §0.1 records what did not transfer and why: whitepaper/LaTeX apparatus, i18n, glossary, tier column, Noh naming registry, the doc-drift judge (its precedence rule retained), Radicle and subsystem-maintainer gates, the docs-words/core-LOC ratio. Absence is to be read as decision. |
| 2026-10-05 | §5 diverges deliberately from the source's "no local paths" rule: sibling checkouts are cited as `~/src/…`. They are unpublished local checkouts, not artifacts with public URLs, and relative traversal breaks on read. Published references still get URLs. |
| 2026-10-05 | §6 and §11 repurposed rather than dropped. Rendering infrastructure is not applicable at one package and says so. §11 is rewritten around polytropos's actual relationship to measurement — evidence as a first-class documentation citizen — including the `-package-env -` reproducibility rule, the which-columns-are-stable rule, and benchmark-is-not-a-doc. |
| 2026-10-05 | §9 keeps the source's "credit by choice, not obligation" position, and points at `THIRD_PARTY.md` and `COMMIT_ATTRIBUTION.md` rather than introducing `CREDITS.md`/`LICENSES/`, which this repository had already replaced. |
| 2026-10-05 | §1 retains the scaled-textbook tutorial ambition as deferred rather than dropped, with a revisit trigger (a tutorial track appearing). |
| 2026-10-05 | §3 extended with two stages for the non-note genres: `live` (living register, append-only) and `archive` (preserved record, not canonical). Found by applying the document to the corpus it governs: the index was already using both, and the Gemini transcript was marked `superseded in part`, which was neither a defined flag nor the right claim -- nothing replaced the transcript, so `inconsistent` on the claims is what the vocabulary actually expresses. `docs/INDEX.md` corrected to the defined vocabulary, and `COMMIT_ATTRIBUTION.md` / `PROVENANCE.md` given the Status headers their new `blessed` stage requires. |
| 2026-10-15 | §5 updated: while local co-development paths remain referenced as `~/src/…`, all modified ecosystem repositories, forks, and polytropos are now rooted in 4 public git mirrors and Radicle, cataloged in `docs/developer/UPSTREAM_REPOSITORIES_AND_INTEGRATIONS.md`. |