# Row + Role Judgement Sketch (minimal countable core)

**Purpose.** A compact formal sketch of a closed/open row algebra with a
role lattice, enough to reason about extending a Haskell typesystem model
(ideally GHC + a TcPlugin) with closed rows, open rows, row inclusion,
widening, and row constraints. It is **not** a full formalism; its job is
to make the open questions in `POLYTROPOS_DESIGN.md` §7 answerable in
writing, and to give a shared reference for whether a given extension is
well-conceived.

**Why these two sources.** The row algebra below is deliberately aligned
with the existing OCaml implementation, and the role/erasure layer is
deliberately aligned with the existing ICFP 2019 proof development. Using
two real systems as reference points is cheaper than inventing both from
scratch and hoping they fit together.

## 0. Sources checked in this session

- **Row algebra.** OCaml typechecker, `typing/ctype.ml`, file
  `/home/nyc/src/ocaml/typing/ctype.ml`:
  - row-field merge: `merge_row_fields`, `merge_rf`
  - row closedness/environment expansion: `closed_type_decl`,
    `free_vars` with `Row_variable`, `static_row`
  - row subtype: entry point `subtype_row` (called from the main
    `subtype` judgement; the exact line numbers were read directly from
    the file in this session)
  - the OCaml note you already wrote at
    `docs/notes/OCAML_BACKWARD_COMPAT_ROW_ALGEBRA.md` also applies.
- **Role + erasure + coercion consistency.** Weirich, Choudhury, Voizard,
  Eisenberg, *A Role for Dependent Types in Haskell (Extended version)*,
  see arxiv `1905.13706v1`, and the accompanying Coq/Ott development at
  `/home/nyc/src/corespec-roles` (ICFP 2019). The relevant checked pieces
  are:
  - the two-role lattice `Nom`/`Rep` with `<= R1 R2`
  - role-indexed definitional equality `a == b : A / R` and the Sub rule
  - the separate `roleing W |= a : R` judgement
  - `erase_tm a r` and the role-indexed erasure/reduction machinery
  - the explicit-language coercion constructors and the consistency
    theorems proved in Coq
  - the **design constraint** in paper Section 2.5: type-checking should
    not also check roles, and kinds should not mention roles; the only
    interaction is on top-level axioms.

## 1. Minimal row vocabulary (OCaml-flavored)

### 1.1 Row kinds

A row is one of:

- **closed row** — a finite ordered map `{(label, type)}`. No tail.
- **open row** — a closed row plus a **row tail variable** `ρ`. The tail
  stands for "zero or more additional unknown labels".

This is exactly the OCaml split: a variant/object type is either static
(fully known) or static fields plus `row_more`, and `row_more` can be a
variable or a concrete continuation. In `ctype.ml` the relevant carrier is
`row` with `row_fields` and `row_more`, plus `row_name` for naming the
open tail when it is an uninstantiated variable. The closedness check is
`closed_type` / `closed_type_decl`, which reports the first `Row_variable`
it encounters.

### 1.2 Row inclusion as a judgement

The central judgement is **row inclusion**:

```
r1 ⊆ r2
```

with the intended meaning: a value whose row is `r1` can be safely used
where a value whose row is `r2` is expected. In OCaml terms, this is the
relation computed (with unification constraints) by `subtype_row` when it
walks `row_fields` of both sides and decomposes into label-at-a-time
requirements, using `merge_row_fields` to align the two field lists and
emit paired constraints for shared labels and leftover fields for the rest.

Important: **inclusion is not equality.** OCaml's `merge_row_fields` does
not require the two rows to be identical; it partitions them into
shared labels (for which it builds a `(label, field, field)` pair list)
and leftover labels (one side has a label the other does not). That
partition is the footprint of open/closed compatibility.

### 1.3 Widening (row extension)

Widening is the constructive direction of inclusion:

- a closed row can be widened to an open row by attaching a fresh (or
  already-bound) tail variable
- an open row can be narrowed only when its tail is instantiated, or when
  a constraint forces the tail to be compatible

This is where **variance** matters: if a constructor argument is covariant
in its row, widening is allowed in that position; if invariant/phantom,
the rules tighten. OCaml implements this through the variance lattice in
`type_variance` and the `lower_contravariant` machinery. A minimal sketch
does not need OCaml's full variance story, but it should acknowledge that
row inclusion is only safe in positions where the surrounding type admits
it.

## 2. Role lattice (corespec-roles-flavored)

### 2.1 The lattice

Use at least:

- `Nom` — nominal equality only; head-matching, no coercion
- `Rep` — representational equality; coercion-safe

with `<= R1 R2`:

- `Nom <= R`
- `R <= Rep`
- refl, trans

That is the two-point flat lattice from `corespec-roles`. Do not reach for
the full `min`/`param`/`app_role` machinery yet unless you actually need
per-spine-role propagation.

### 2.2 Role-indexed equality

Adopt the key judgement shape:

```
a == b : A / R
```

and the **Sub rule**:

```
a == b : A / R1    R1 <= R2
-----------------------------
      a == b : A / R2
```

This is the part that makes roles useful: equality at a stronger role
implies equality at any weaker role, so you can forget information when
you move from `Nom` toward `Rep`.

In the paper, this is what lets a newtype be "unfolded" only at
`Rep`, while staying opaque at `Nom`. For rows, the natural analogue is:

- closed row equality may be nominal (exact field set and types)
- closed-row-to-open-row compatibility may be representational under
  inclusion constraints, where the tail is allowed to absorb unknown
  labels

### 2.3 Separating type-checking from role-checking

Follow the paper's Section 2.5 separation constraint: the core typing
judgement should not depend on the role judgement. Roles should matter
only when you touch the specific axioms that can see through abstractions
(newtypes in the paper; closed/open row boundaries in our model). This is
a **design constraint**, not a theorem; it exists so that most code never
has to think about roles.

## 3. Putting rows and roles together

### 3.1 Row constraints

The sketch should have at least these constraint forms:

- `r1 ~ r2` — row equality (likely nominal)
- `r1 ⊆ r2` — row inclusion
- possibly `r1 ~ r2 : K / R` — row equality at a given role, if you want
  the role-lattice to reach row constraints at all

The minimal version that matches your stated goal is: row constraints are
about inclusion/equality of rows; roles are about whether the equality or
coercion evidence is safe to use. Do not merge the two lattices too early.

### 3.2 Where row-tail unification lives

In OCaml, row tails are unified through the same constraint machinery that
handles other type variables; in `merge_row_fields` / `unify_row_field`,
mismatched leftover fields on one side may unify with the other side's tail.
For a Haskell model, the important point is that the tail is not magical:
it is just a tunable point in the constraint solver. If polytropos wants to
avoid row tails entirely, that is a **design decision**, not a formalism
requirement, and it should be stated explicitly.

### 3.3 The likely soundness concerns

The ICFP 2019 paper exists precisely because `coerce` + type families
without roles is unsound. The row analogue is:

- allowing a value with row `r1` to masquerade as a value with row `r2`
  when the label/type correspondence is not guaranteed is potentially
  unsound at runtime
- allowing coercion through a closed/open boundary must be gated by a
  role like condition: when is it safe to "see through" the closedness?

For polytropos, the practical question is: **what runtime representation
claims are you making?** If a `Record r` and a `Variant s` share a flat
`SmallArray` payload but differ in interpretation, row inclusion must not
allow reinterpretating one as the other unless you have proven the payload
layout is stable and the interpretation is valid. That is the hook where
roles matter.

## 4. What this sketch deliberately leaves out

- Per-label roles (roles inside the row, not just on the row itself)
- Full row-polymorphic quantification over rows
- Pattern-matching on rows
- The ICFP 2019 full dependent-type apparatus (only the role/erasure
  skeleton is borrowed)
- OCaml's full object/variant `Reither` row-field encoding, which is
  richer than we need
- Any claim that the sketch is complete or proved

## 5. Immediate next step it implies

If the goal is a plan for extending the Haskell typesystem model, the first
concrete artifact is: **write the minimal judgement set in the style of
`ett.ott` defns blocks** (or equivalent) for exactly:

- row kinds
- `r1 ⊆ r2`
- a widening rule or two
- one role lattice
- one role-subsumption rule for row constraints

Then line it up against:

- OCaml's `merge_row_fields` / `subtype_row` for the row side
- ICFP 2019's `Sub`, `roleing`, and `erase` for the role side

That artifact should be falsifiable: if it cannot state a closed-to-open
widening and a nominal closed-row equality without stepping on itself, it
is not ready yet.
