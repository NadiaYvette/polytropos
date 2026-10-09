<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Reviewer-Facing Well-Foundedness Argument Sources

Status: DRAFT · v0.1 · 2026-10-09

Related: `ROW_ROLE_DEFNS_DRAFT.ott`, `ROW_ROLE_JUDGEMENT_SKETCH.md`,
`OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md`, `POLYTROPOS_DESIGN.md` §7,
`~/src/corespec-roles/spec/ett.ott`, `~/src/haskell-spec/`,
`~/src/algebraic-subtyping/`, `~/src/simple-sub/`,
`~/Dokumente/Algebraic_Subtyping-Stephen_Dolan-Ph.D._Thesis.pdf`,
`~/src/Nimzo/`.

---

## Purpose

This note records the argument structure and the external source mapping
for a reviewer-facing claim that the type-system extension polytropos's
plugin implements (or will implement) is well-founded / consistent enough
to be taken seriously by GHC-involved reviewers.

It is written so that each part of the argument has an explicit external
citation, and so that the wrong sources (haskell-spec, Nimzo) are
explicitly excluded with a reason.

---

## 1. What the argument needs to establish

For a GHC reviewer, "well-founded / consistent enough" for a
plugin-implemented type extension means roughly four things:

1. **Role side is GHC-native.** The extension uses GHC's existing
   Nom/Rep role apparatus and role-indexed equality, not a new role
   system. The lattice and the role-subsumption rule are a published,
   mechanized thing, not an ad hoc invention.

2. **Constraint side is GHC-native.** The row-equality constraints the
   plugin emits are GHC's `~` constraints at a role, not a new
   constraint kind. The plugin is not extending GHC's constraint solver
   in a way that could leak unsoundness into the rest of the solver.

3. **Row side is standard.** Row inclusion with an open tail, closed-to-
   open widening, and a distinction between width-inclusion and exact
   equality is a known row-polymorphism discipline, used in a real
   compiler (OCaml). The extension is not inventing a novel row theory.

4. **Plugin boundary is literal and bounded.** The plugin emits
   constraints and literal indices; it does not perform type-level
   search. The hand-off between the row-shape layer and the constraint
   layer is a stated boundary contract, and the plugin's obligations are
   tested, not inferred.

The strongest version of the claim is: *the extension is conservative
over GHC's existing role/constraint apparatus plus a standard row
discipline, with a literal plugin and a stated boundary contract.*

It is not: *a proved system.* The draft's §12 is explicit about what is
and isn't committed.

---

## 2. Source mapping by argument piece

### 2.1 Roles — canonical citation (lattice + subsumption apparatus)

**Citation:** ICFP 2019, *A Role for Dependent Types in Haskell*
(Weirich, Choudhury, Voizard, Eisenberg; arxiv `1905.13706v1`), with
the accompanying Coq/Ott mechanization at `~/src/corespec-roles`
(branch `main`; `spec/ett.ott` + `src/FcEtt`).

**What it covers for us:**
- the two-role lattice `Nom`/`Rep` with `<= R1 R2` (corespec rule
  `JSubRole`; NomBot, RepTop, Refl, Trans)
- role-indexed definitional equality `a == b : A / R`
- the `Sub` rule: `a == b : A / R1`, `R1 <= R2` ⇒ `a == b : A / R2`
- the separate `roleing` judgement `W |= a : R`
- erasure `erase_tm a r` and the role-indexed erasure/reduction machinery
- the design constraint (paper §2.5): type-checking should not also check
  roles; kinds should not mention roles; the only interaction is on
  top-level axioms

**What it justifies in the argument:** that the draft's role lattice
(§9) and role-subsumption rule (§11) are restatements of a published,
mechanized apparatus, and that the row-equality constraints the plugin
emits (`r1 ~ r2 : A / R`) are in the same *class* of apparatus as GHC's
role-parameterized equality — not a new role system.

**What it does NOT claim:** that GHC's implementation is identical to the
corespec mechanization. Whether GHC's actual implementation matches the
corespec model exactly is a GHC-internal question, not a polytropos
question.

**Draft sections that map:** `ROW_ROLE_DEFNS_DRAFT.ott` §0 (reference
notes), §9 (role lattice), §11 (role-subsumption).

**What it does NOT cover:** rows, row inclusion, row widening, row tail
variables, row equality as distinct from term equality. The role side is
the anchor; the row side comes from elsewhere.

### 2.2 Rows — canonical citation

**Citation:** OCaml typechecker, `typing/ctype.ml`, file
`/home/nyc/src/ocaml/typing/ctype.ml`, with the repo's own
`docs/notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md`.

**What it covers for us:**
- row-field merge: `merge_row_fields`, `merge_rf`
- row subtype entry point: `subtype_row`
- row unification: `unify_row`, `unify_row_field`
- row carriers: `row_fields`, `row_more`, `row_name`, `row_closed`,
  `row_fixed`, `static_row`
- closedness: `closed_type`, `closed_type_decl`

**What it justifies in the argument:** that row inclusion with an open
tail, closed-to-open widening, label-by-label decomposition with leftover
fields, and deferred constraint emission for non-comparable tails is a
known compiler discipline, not an ad hoc invention. The draft's §3
(Reading B inclusion) and §4 (boundary contract) are aligned with this.

**What it does NOT cover:** roles, the Nom/Rep lattice, role-indexed
equality on rows. The row side and the role side are separate sources in
the argument; they are not derived from one another.

### 2.3 "Tilde at a role" constraint form — GHC-native citation

**Citation (GHC, not corespec):** GHC compiler source for equality
predicates and the role machinery on the constraint/coercion side:

- `compiler/Language/Haskell/Syntax/Basic.hs` — `data Role = Nominal |
  Representational | Phantom` (with the note that the constructor order
  coincides with the *super*typing relation on roles)
- `compiler/GHC/Core/Predicate.hs` — `data EqRel = NomEq | ReprEq`,
  `eqRelRole :: EqRel -> Role`, `mkEqPredRole :: Role -> Type -> Type
  -> PredType`, `mkNomEqPred`, `mkReprEqPred`; the `EqPred EqRel Type
  Type` constructor of `data Pred`; the classify/predication machinery
  that treats `(t1 ~# t2)` and `(t1 ~R# t2)` as equality predicates
- `compiler/GHC/Core/TyCo/Rep.hs` — `Note [Roles]` (the GHC roles
  note; points to `docs/core-spec/core-spec.pdf` and to
  https://gitlab.haskell.org/ghc/ghc/wikis/roles-implementation, and to
  Weirich et al., "Generative Type Abstraction and Type-level
  Computation," POPL 2010); coercion role machinery including `SubCo`
  (nominal-to-representational demotion) and `TyConAppCo` role
  parameter
- `compiler/GHC/Core/Coercion.hs` — `Note [Roles]` on the coercion
  side, including `setNominalRole_maybe` and the role-parameterized
  coercion constructors

**What it justifies in the argument:** that the draft's row-equality
constraint form `r1 ~ r2 : A / R` is GHC's existing equality predicate
parameterized by a role — NOT a new constraint kind invented by
polytropos. GHC already has:

- a three-role lattice (Nominal, Representational, Phantom) on its own,
  independent of our draft's two-role Nom/Rep lattice
- equality predicates tagged by `EqRel` (NomEq / ReprEq), which is the
  GHC-side analogue of our `/ R` role index
- a constructor `mkEqPredRole :: Role -> Type -> Type -> PredType` for
  building a primitive equality predicate at a chosen role
- the role/subsumption apparatus (SubCo, the Nom→Rep demotion) that
  realizes the same Nom ≤ Rep direction our draft's Sub rule uses

So the claim "the plugin emits ~ constraints at roles, which GHC already
supports" is anchored in GHC's actual source, with corespec as the
separate mechanized justification for why the Nom/Rep apparatus is
well-founded.

**What it does NOT claim:** that GHC has anything called a "row
constraint" or a "row-equality constraint" specifically. GHC has
equality predicates at a role; our draft's `r1 ~ r2 : A / R` is that
machinery applied to row types. Whether GHC's existing role machinery
reaches row types the way our draft assumes is a question for the GHC
 reviewer and for the plugin's actual emission behavior, not a claim this
note makes on GHC's behalf.

**Draft sections that map:** `ROW_ROLE_DEFNS_DRAFT.ott` §0 (the GHC-
native anchor paragraph), §10 (constraint form `RowEq`), §11 (role-
subsumption on that form).

### 2.3 Row side — secondary theoretical support

**Citations:**
- Stephen Dolan, *Algebraic Subtyping*, PhD thesis,
  `~/Dokumente/Algebraic_Subtyping-Stephen_Dolan-Ph.D._Thesis.pdf`
- Lionel Parreaux, *The Simple Essence of Algebraic Subtyping* (ICFP
  Functional Pearl), and the accompanying code at
  `~/src/algebraic-subtyping/` and `~/src/simple-sub/`

**What they justify in the argument:** that width-subtyping on records
(inclusion, widening, union/intersection where relevant) is a
well-studied, sound subtyping discipline, and that the distinction
between *inclusion/width-subtype* and *structural equality* is a known
and important one. This supports the draft's core design choice of
having two distinct tail judgements — `⊆₊` (compatibility/widening) for
inclusion and `≃₊` (exactness) for equality — rather than defining
equality as mutual inclusion.

**Where they are secondary, not primary:** they are about subtyping
theory and inference algorithms (MLsub/Simple-sub), not about GHC Core
roles or about OCaml's compiler implementation. They support the row
design's soundness intuition; they are not the source for the constraint
or role apparatus.

### 2.4 Plugin boundary — internal sources, not external

The plugin-boundary argument (literal emission, no type-level search,
stated hand-off, tested obligations) is justified by internal repo
sources, not by external citations:

- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` (or wherever the
  plugin entry lives)
- `packages/polytropos-core/test/Main.hs` (the hand-written RowEq/RowShow
  instances that specify what the plugin must emit)
- `docs/notes/POLYTROPOS_DESIGN.md` §6 (the plugin is the load-bearing
  part)
- `packages/polytropos-plugin/` cabal and test suites

The argument here is: *the tests specify the plugin; the plugin is literal;
the boundary contract in the draft makes the hand-off explicit.*

---

## 3. Sources explicitly excluded, with reasons

### 3.1 `~/src/haskell-spec/` — excluded

haskell-spec is a Lean mechanization of the Haskell 98/2010 language
reports (starting from Faxen's "A Static Semantics for Haskell," 2002).
Per its README, the Haskell 2010 coverage is aspirational ("adapt the
formalization to the Haskell 2010 report as a second step"), and the
formalization is a *source-language* semantics (modules, import/export,
patterns, literals, type-class dictionary elaboration), not a Core
calculus with roles or coercions.

**Why excluded from the argument:** a GHC reviewer asking whether the
extension is well-founded in GHC's type system wants the role/constraint
story, which lives at the Core layer, not the Haskell98/2010 source
layer. haskell-spec has no roles, no coercions, no Nom/Rep lattice, no
row inclusion judgement, and no plugin boundary. Citing it would weaken
the argument by pointing at the wrong layer.

**When it might be relevant:** if the question ever becomes "how does
row-polymorphic record syntax interact with Haskell source-language
modules, import/export, or pattern matching," haskell-spec becomes
relevant as the source-language anchor. That is not the current
well-foundedness argument.

### 3.2 `~/src/Nimzo/` — excluded

Nimzo is "Subtyping the Calculus of Constructions" — a dependent-type
subtyping system built on the CoC, with record union/difference,
presence variables, bounded quantifiers `[Tlo <: a <: Thi]`, and
`⊓`/`⊔`. Its TODO and structure make clear it is a dependent-type
subtyping project, not a Haskell Core rows-and-roles project.

**Why excluded from the argument:** the current extension is not
dependently typed, and the row+role judgements in the draft do not need
the CoC's subtyping apparatus. Nimzo's record union/difference and
presence-variable ideas are row-adjacent, but its base calculus is wrong
for this argument. Citing it would read as overreaching.

**When it might be relevant:** if the row system ever becomes dependently
typed (row variables indexed by label sets, dependent field types,
bounded row quantifiers), Nimzo's treatment of subtyping in a dependent
setting becomes more relevant. That is a future question, not the current
one.

### 3.3 `~/src/corespec/` (without `-roles`) — superseded, not cited

`~/src/corespec/` is the ICFP 2017 system extended with eta-equivalence,
per its README. `~/src/corespec-roles/` (ICFP 2019) is the later,
corespec-roles-specific development, and it is the one the draft cites.
The ICFP 2017 version is superseded by the ICFP 2019 version for our
purposes.

**Why not cited:** we cite the ICFP 2019 corespec-roles development
because that is the one with the Nom/Rep lattice and the role-indexed
equality and Sub rule in the form we use. The ICFP 2017 version is the
prior art that corespec-roles supersedes; it is not the canonical
citation for the role apparatus as it currently exists.

---

## 4. What the argument does not claim

- It does not claim the extension is proved. The draft's §12 and
  `ROW_ROLE_JUDGEMENT_SKETCH.md` §4 are explicit that the sketch is not
  complete or proved.
- It does not claim the row discipline is identical to OCaml's. It
  claims it is aligned with OCaml's known mechanics and documented
  against them; any divergence is a design decision, not a claim of
  identity.
- It does not claim the role side is GHC's exact implementation. It
  claims the lattice and role-indexed equality are the same apparatus
  GHC already has, formalized in the ICFP 2019 development; whether
  GHC's actual implementation matches the mechanization exactly is a
  GHC-internal question, not a polytropos question.
- It does not claim the algebraic-subtyping resources are a direct model
  for polytropos. They support the soundness intuition for the row
  subtyping discipline; they are not the source for the constraint or
  role apparatus, and polytropos does not do MLsub-style inference.

---

## 5. Suggested shape for a reviewer-facing write-up

If a reviewer-facing note is written from this, the cleanest shape is a
short document that restates the four-point argument above, with inline
citations:

- **Roles.** ICFP 2019 corespec-roles (`JSubRole`, `Sub`, `a == b : A
  / R`). GHC-native apparatus; not new.
- **Constraints.** GHC's existing `~` constraint at a role; the plugin
  emits these, not a new kind. (GHC source for `~` + roles is the
  actual GHC citation here, not corespec.)
- **Rows.** OCaml `ctype.ml` + the repo's OCaml note. Standard
  row-inclusion/widening discipline; not new.
- **Equality vs inclusion.** Algebraic-subtyping/Dolan literature on the
  width-subtype vs structural-equality distinction; embodied in the
  draft's two-tail-judgement design.
- **Plugin.** Internal sources: plugin code, test spec, design note §6,
  plugin-invariants. Literal, bounded, tested.
- **Openness.** Draft §12; what is and isn't committed; what is still
  open.

The haskell-spec and Nimzo citations do not appear in this argument
except as explicitly excluded resources with a one-line reason.

---

## 6. Where to put the actual reviewer-facing note

This note records the source mapping and the argument structure. The
actual reviewer-facing write-up, if one is written, should live somewhere
that signals it is the argument artifact, not a transcript. Candidate
locations, per `DOC_STRATEGY.md` genre discipline:

- `docs/notes/` if it is a design-spec-adjacent argument (e.g.
  `REVIEWER_WFU_ARGUMENT.md` or similar), at `draft` stage until
  reviewed
- `docs/registers/` only if it becomes a living register of
  reviewer-facing claims (unlikely; this is a one-off argument, not a
  living inventory)

This note itself stays at `draft` and is indexed as a notes-stage
artifact. It is canonical for the source-mapping decision (which sources
are in, which are out, and why), not for the underlying technical claims,
which remain canonical in their own sources.
