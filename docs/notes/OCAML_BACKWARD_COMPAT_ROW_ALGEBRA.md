# OCaml Type-Checker Row Algebra — What Actually Makes Backward Compat Work

KEY POINT
OCaml's row machinery does NOT rest on a single `Named`/`Anonymous` flag.
It rests on the row algebra being a first-class part of the type representation.
Backward compat works because the OLD nominal types are a SPECIAL CASE
of the SAME algebra: closed rows with no open tail, no fixed-explanation
discharge, no private effect — exactly what the pre-row system already
produced.

THE ROW ALGEBRA THAT BACKWARD-COMPAT FLOATS ON

## 1) `type_desc` constructors involved in rows/variants

- `Tvar` — a type variable
- `Tunivar` — a universal (scheme) variable
- `Tconstr` — a constructor / GADT application (often closed)
- `Tnil` — closed row end marker
- `Tfield(lab, kind, ty, rest)` — a row field whose **rest** is the row tail as a type expression. This is the key idea: a row can END with `Tnil`, or it can be OPEN via a tail that is `Tvar` / `Tunivar` / `Tconstr`. That is how open rows exist without introducing a new kind.
- `Tvariant(row_desc)` — variant wrapper carrying a `row_desc`
- `Tobject(...)` — object rows, treated with the SAME row algebra

## 2) `row_desc` is the row's metadata separate from its tail type expression

```
row_desc = { row_fields; row_more; row_closed; row_fixed; row_name }
```

- `row_fields` — sorted list of `(label, row_field)`
- `row_more` — the row tail AS a type expression (`Tvar | Tunivar | Tconstr | Tnil`)
- `row_closed` — does this row admit more fields?
- `row_fixed` — is this row fixed (cannot be unified with an open row)?
- `row_name` — optional name for debugging / abbreviation expansion

## 3) `row_field` is richer than "this field is present"

- `Rpresent(None)` — required field, no default
- `Rpresent(Some ty)` — required field with a default
- `Reither` — conjunctive constraint for variants/objects. This is how OCaml represents "any of these constructors / fields" and supports conjunctive ("and also") object typing.

## 4) The row tail is what makes open vs closed a property of the TYPE, not a property of a value-level wrapper

- **open row** — `row_more` is `Tvar` / `Tunivar` / `Tconstr`; can be unified with a tail that adds fields
- **closed row** — `row_more` is `Tnil` AND `row_closed = true`
- **fixed row** — `row_fixed` explains WHY it is fixed (`Rigid | Univar | Fixed_private | Reified | ...`); this is the answer to "can I widen this?"
- A closed user-defined type is typically: `row_more = Tnil`, `row_closed = true`, and the tail is NOT a unification variable.

WHAT "BACKWARD COMPAT" MEANS HERE

A type declared BEFORE row polymorphism was added:

```
type t = A | B of int
```

becomes a `Tvariant` with:
- `row_closed = true`
- `row_more = Tnil`
- `row_fixed` set
- a fixed set of `row_fields` (the constructors)

It is NOTHING special — it is just a closed row with NO tail variable. Before row polymorphism, ALL variant/object types were closed, so they already fit this shape; nothing had to be reinterpreted.

The row algebra EXTENDS them rather than replacing them:
- a closed row is a row
- a closed tail is `Tnil`
- a closed field list is a field list

No flag needed.

A type WITH row polymorphism (polymorphic record / variant / object):
- `row_more` can be `Tvar` / `Tunivar` / `Tconstr` instead of `Tnil`
- `row_closed` may be false, or the tail may be a variable that can be unified with a bigger row
- this is the OPEN case, represented with the SAME constructors, only with a tail that is not `Tnil`

SO BACKWARD COMPAT comes from:
- closed nominal types are EXACTLY the `Tnil`-closed case, which is what the pre-row system already produced (it had no open rows at all)
- open polymorphism is represented by allowing `row_more` / `row_closed` to take open shapes WITHOUT changing the closed case's representation
- the unifier (`Ctype`) treats `Tvariant` / `Tobject` / `Tfield` / `Tnil` specially, but in a way that does NOT disturb already-solved closed rows

HOW THE UNIFIER PROTECTS CLOSED ROWS

Key functions and the invariants they enforce:

- `static_row` — a row has NO polymorphic tail (no `Tvar` / `Tunivar` in `row_more` that could be unified to add fields). **CLOSED NOMINAL ROWS ARE STATIC.**
- `is_fixed` / `has_fixed_explanation` / `fixed_explanation` — explain WHY a row cannot be widened. A closed user type is fixed: it cannot gain unknown fields.
- `row_closed` — closed rows disallow adding fields via the row algebra.
- `make_rowvar` / `row_more` unification — OPEN rows get a polymorphic tail variable.
- `merge_row_fields` / `sort_row_fields` / `associate_fields` / `filter_row_fields` — the algebra for merging and traversing rows without breaking closedness.
- `unify_var` on `Tvariant` — when a `Tvariant`'s row is closed, the unifier does NOT unify its tail with an open row the way it would for an open variant.
- `eqtype_row` / `moregen_row` — row equality / generalisation that respects the closed/open shape without forcing open rows onto closed ones.

Practical upshot: if you take a pre-row nominal type and ask the type checker to unify it with an open-row variable, the answer is NO (or restricted) because the closed shape is fixed by `row_closed` / `row_fixed` / `static_row`. That protection is WHERE backward compat lives.

HOW PRIVACY / FIXED NARROWS IT FURTHER

OCaml also has:

- **private row types** — a row usable only in restricted ways (`set_private_row`, `privacy_mismatch`, `Tconstr` vs `Tnil` handling).
- **fixed explanations** — `Rigid | Univar | Fixed_private | Reified | ...` — these pin down WHY a row is closed/fixed, so the unifier can reject illegal widening without breaking legitimate use.

Backward compat INCLUDES these, because they are more cases of the same fixed/closed algebra, not a separate code path.

THE BACKTICK PREFIX ISSUE

The OCaml backtick constructor prefix (`A`) is the **SURFACE SYNTAX** for **POLYMORPHIC VARIANT TAGS** — i.e. OPEN / STRUCTURAL variant constructors.

It is NOT "a nominal-vs-structural flag on a constructor in the type representation".

The real mapping is:
- **lower-case constructor** — nominal / closed variant constructor (part of a closed row)
- **backtick constructor** — polymorphic variant tag (open row tail, structural)

So your suspicion was partly right in SPIRIT: OCaml does have an open-vs-closed variant discipline, and it is row-based. But the specific guess — that backtick is the OCaml analogue of a `Named`/`Anonymous` phantom flag — is NOT the right mapping.

The real analogue is:
- the closed / open / fixed / private row distinction
- the `row_more` tail shape
- for variants, the `Tvariant` / `row_desc` machinery
- the unifier treatment of those shapes

HOW THIS COMPARES TO THE POLYTROPOS NAMED/ANONYMOUS FLAG

The Polytropos `Named`/`Anonymous` flag is a **TYPE-LEVEL PHANTOM** on `RowRep`.

OCaml's equivalent is NOT a phantom flag like that. It is the row algebra WITHIN the type representation:
`row_desc.row_closed`, `row_desc.row_fixed`, `row_desc.row_more`,
`row_field` variants, `Tnil`, `Tfield` rest, `Reither`, private rows,
and the special unifier cases.

Why this matters for your question:

- If Polytropos ends up with ONLY a `Named`/`Anonymous` phantom and NO row algebra distinguishing closed / open / fixed in the type system, then you are NOT yet at an OCaml-like discipline; you have a policy marker on a library type.
- The honest backward-compat design in the OCaml style is: closed types are the default and are represented as the closed end of the SAME algebra the open types use. You do NOT preserve backward compat by "defaulting to `Named`"; you preserve it by representing closed types as closed rows in a row algebra that already treats closed rows as a non-special case.

This is the gap flagged earlier: the current polytropos `RowRep` vocabulary does NOT have that algebra — it has a single row parameter that is fully known at the use site. That is fine IF the goal is a library-level structural layer on top of closed nominal ADTs, but it is a different design point from OCaml's type-checker-integrated row discipline.

SUMMARY

OCaml maintains backward compat with nominal types because:

1. Row polymorphism was added AS an extension to the EXISTING type algebra, not as a parallel polymorphism with a flag.
2. Closed nominal rows are the `Tnil` / closed / fixed / static case of that algebra — what the old system already produced — so they never became special or broken.
3. Open rows exist by giving `row_more` a non-`Tnil` tail (`Tvar` / `Tunivar` / `Tconstr`), not by introducing a new "structural" value representation.
4. Protection of closed rows is in the unifier: `static_row`, `is_fixed`, `row_closed`, `fixed_explanation`, merge / filter / sort / associate row fields, row equality / generalisation, `unify_var` on `Tvariant` / `Tobject`.
5. Private / fixed rows are MORE cases of the same fixed/closed algebra.

The OCaml backtick constructor is the surface syntax for open polymorphic variant tags, NOT the type-system analogue of a `Named`/`Anonymous` flag. The real analogue is the closed / open / fixed / private row discipline.

Honest read for polytropos:
if "backward compat via `Named` default" is the only mechanism, it is a plausible first cut, but it is NOT the OCaml-shape story. The OCaml-shape story is: represent closed types as closed rows in a row algebra that already handles open rows, and protect closed rows in the unifier, so no flag is needed to preserve what predated rows.

SOURCE FILES VERIFIED

- Polytropos: `packages/polytropos-core/src/Polytropos/Core.hs`, `packages/polytropos-core/test/Main.hs`, `docs/transcripts/nominal-structural-flag.md`.
- OCaml: `~/src/ocaml/typing/ctype.mli`, `~/src/ocaml/typing/ctype.ml`, `~/src/ocaml/typing/btype.mli`, `~/src/ocaml/typing/btype.ml`.

VERIFICATION STATUS

- Polytropos repo unchanged this session (`git status --short` still only `M cabal.project` and `?? packages/polytropos-rel8/`; HEAD still `6dcfc07` / `ea7adb3` / `f013c7c`).
- Polytropos backward-compat read is from code/docs, not from a build/typecheck/test run (none was requested).
- OCaml read is grounded in the type-checker row algebra symbols verified through a code-graph DB built from `~/src/ocaml` plus re-reading the relevant `ctype`/`btype` sources.

LIMITATIONS / STILL OPEN

- No semantic `codegraph` embeddings were built this session (embed workers stalled loading the transformers/WASM model path); we fell back to structural/keyword search by decision.
- The other reference repos (`row-types`, `open-adt`, `data-diverse`, `Megarecord`, `Superrecord`, `purescript`, polytropos itself) were **not** indexed/queried this session.
- OCaml's full middle-end/runtime polymorphic-variant cost was **not** traced this session; the read is stronger on the type-system/row-representation/unifier side than on full compilation cost.
