# OCaml Row Tail Subtype / Unify Mechanism — Followup 2

KEY POINT
OCaml does not eliminate row tails inside the structural relation algorithm.
In `subtype`, row tails are treated like ordinary type variables:
when the tail constructors are not directly comparable, `subtype_row` aborts
to a deferred unification constraint and lets the normal unifier resolve them.
In `unify`, row tails are unified with the same machinery used for other types,
with row-specific handling of `row_closed` / `fixed_explanation` and an explicit
structural merge into a fresh `Tvariant` row when the tail is not a survivable
`Tvar`.

This is why adopting row tails in polytropos is a coherent next step if the goal
is widening plus backward compat plus constraint generation, but why the actual
mechanisation matters: OCaml’s “open row” is not a row variable that
automatically “includes” another row’s fields. It is a type-level tail
constructor whose shape (`Tvar`, `Tunivar`, `Tnil`, `Tconstr`, `fixed_explanation`)
drives the algebra.

## The shape of a row in OCaml

A polymorphic variant is mostly carried as:

```
Tvariant { row_fields; row_more; closed; fixed; name }
```

Crucially, `row_more` is itself a type expression, not a magic row-only slot:

- `Tvar` — ordinary unification variable; the row is still open.
- `Tunivar` — universally quantified row variable.
- `Tconstr(p, [], _)` — abstract/private row type, or a locally reified row in GADT context.
- `Tnil` — static closed row with no tail.
- `Tfield(lab, kind, ty, rest)` — a row field whose `rest` is *also* a type expression,
  used especially for object rows.

That is the only way open rows exist without inventing a separate row kind: the tail
is a type expression, and “open” means “the tail is not `Tnil` and not a fixed
abstract row”.

Accessors include `row_more`, `row_closed`, `row_fixed`, `row_name`, with
`row_repr` peeling through `Tvariant`-chained `row_more` to reach the real tail.
`static_row` means “no polymorphic tail that could be unified to add fields”.

## What `subtype_row` actually does

OCaml’s subtype relation for variants is:

```
(Tvariant row1, Tvariant row2) ->
  begin try
    subtype_row env trace row1 row2 constraints
  with Exit ->
    (env, trace, t1, t2, !univar_pairs)::constraints
  end
```

So `subtype_row` is a decidable filter, not a tail solver.

Inside `subtype_row`, the steps are:

1. Destructure both rows:
   ```
   let Row {fields = row1_fields; more = more1; closed = row1_closed} = row_repr row1 in
   let Row {fields = row2_fields; more = more2; closed = row2_closed} = row_repr row2 in
   ```

2. Merge the known fields with `merge_row_fields`.

3. Widen/erase using closedness:
   - If `row2_closed`, remove from `r1` any field absent in `row2`.
   - If `row1_closed`, remove from `r2` any field absent in `row1`.
   This implements the closed-row side of the relation as a field-list filter,
   not as tail unification.

4. Then it only accepts a narrow set of tail shapes:
   - Both tails are the same known constructor (quick path equivalence) → delegate
     to `subtype_rec` on the tails.
   - `(Tvar | Tconstr | Tnil)` vs `(Tvar | Tconstr | Tnil)` when one side is closed
     and has no residual fields → check field compatibility.
   - `Tunivar` vs `Tunivar`, closedness equal, no residual fields on either side →
     delegate `more1` vs `more2` to `subtype_rec`.

5. Anything else raises `Exit`.

The `Exit` is caught exactly as OCaml catches ordinary type-variable uncertainty:
it emits a deferred constraint pair `(env, trace, t1, t2, !univar_pairs)`.

So for row tails, **subtyping emits constraints; it does not unify or instantiate
the tail itself**.

## What `unify_row` actually does

The real tail merging happens in `unify_row`.

There, `unify_row`:

- Computes the surviving tail `more` from the two tails, with special handling for
  `fixed_explanation`.
- For the common open, unfixed case, builds a fresh row:
  ```
  let ty =
    newgenty (Tvariant
                (create_row ~fields:rest ~more ~closed ~fixed ~name))
  in
  update_level_for Unify ...;
  update_scope_for Unify ...;
  link_type rm ty
  ```

- For the case where the existing tail is still a `Tvar`, it can directly bind it:
  ```
  if is_Tvar rm then link_type rm more else unify uenv rm more
  ```

So even in unification, “merge open tails” is done by constructing a new row from
the merged field lists and one surviving tail constructor. Row identity is preserved
only when the tail survives as a `Tvar`; otherwise OCaml builds a fresh structural
row node.

## How OCaml stops closed rows from being widened

Closedness is not a soft annotation. It is reflected in the tail shape and in
`fixed_explanation`.

- A closed row has `row_closed = true`.
- A static closed row’s tail is effectively `Tnil`, or a known abstract row
  constructor.
- `has_fixed_explanation` distinguishes ordinary open row variables from fixed cases:
  `Rigid`, `Univar`, `Fixed_private`, `Reified`, or `None` for an ordinary open `Tvar`.
- `unify_row` explicitly refuses the “create a fresh open row” path when one side is
  fixed; it either binds the surviving `Tvar` tail, or errors.
- Static closed rows can have their tail pinned to `Tnil`:
  ```
  if static_row row1 then begin
    let rm = row_more row1 in
    if is_Tvar rm then link_type rm (newty2 ~level:(get_level rm) Tnil)
  end
  ```

And `subtype_row` itself has special cases for closed rows and otherwise gives up
to the constraint solver.

## What this says about “constraint emission vs direct instantiation”

The answer in OCaml is both, but in different phases, and only in the sense that
all other type variables already work that way:

- **`subtype`** → constraint emission for row tails when the tails are not directly
  comparable; identical treatment to ordinary `Tvar` uncertainty.
- **`unify`** → direct variable binding when one tail is still a `Tvar`; otherwise
  explicit structural row construction with the merged fields and one surviving tail.

So there is no separate “row inclusion judgment with its own row variable solver”.
Rows are types; row tails are type expressions; the row-specific work is in the
shape of `row_more` and in the closed/fixed checks that gate widening.

That is the subtle part it is easy to guess wrong on:

- OCaml’s open rows do not “unify to include both sides’ fields” by magic.
- OCaml does not turn a closed row back into an open one during unification.
- OCaml does not keep a separate row constraint language for the structural relation;
  it uses the same constraint-unify pipeline and lets row-specific rules live in
  `unify_row` and `subtype_row`.

## What this implies for polytropos

polytropos currently has:

- `RowRep f r row a`
- `row :: k` fully known at the use site
- no row tail / row variable in shipped code
- no shipped closed/open row distinction; the `Named`/`Anonymous` thing is only a
  minimal closed-by-default framing story device in the transcript, not implemented semantics

If polytropos wants row tails to mean what OCaml means, then the minimal coherent
next step is not just “add a tail field to the row GADT”. It is:

1. Introduce a row tail constructor kind into the core row representation:
   - open tail with a unification-variable-like slot,
   - closed/abstract tail,
   - static closed tail.

2. Make at least one row shape carry a tail variable that can be:
   - widened via constraint emission in the structural relation plugin,
   - unified with a plugin-supplied pattern analogous to OCaml’s `unify_row`.

3. Keep the existing nominal index machinery (`FieldIndex`, `ConstructorIndex`,
   literal `RowEq`/`RowShow` bodies) as the shipped **closed-row special case**,
   and treat the new tail machinery as the generalization that preserves that case.

4. Update `POLYTROPOS_DESIGN.md` to make this the row model, and correct the
   transcript framing if needed so it says this is the row model rather than a
   phantom flag story.

OCaml’s evidence supports the claim that the right target shape is:

- tail as a real part of the row representation,
- relation algorithm constraint-generating in the subtype direction,
- tail resolution by ordinary unification plus explicit structural merge when the
  tail does not survive as a variable,
- closedness and fixedness enforced by tail shape, not by a soft flag.

SOURCE FILES READ

- `~/src/ocaml/typing/ctype.ml`:
  `subtype_row`, `subtype_rec` variant case, `subtype` constraint-solving phase,
  `unify_row`, `unify_row_field`, `fixed_explanation`, `static_row`, `row_more`,
  `row_closed`, `row_repr`, `create_row`, `has_fixed_explanation`.
- `~/src/ocaml/typing/btype.ml`:
  `proxy`, `static_row`, `fixed_explanation`, `is_constr_row`, `row_of_type`,
  `set_static_row_name`, `copy_row`.
- `~/src/ocaml/typing/types.mli` / `types.ml`:
  `row_desc`, `row_more` documentation, `row_repr`, `row_desc_repr`, `create_row`,
  `row_field_view`.
- `~/src/ocaml/typing/includecore.ml`:
  `is_absrow`, `private_variant`, `type_manifest` private-row handling,
  `Private_extensible_variant`.

This note verifies the followup-2 claim from the OCaml type-checker sources only.
It does not claim any change to shipped polytropos code.

LIMITATIONS

- OCaml side is strong on row representation / subtype / unify / closedness.
- Not traced in this session: full middle-end / runtime polymorphic-variant cost,
  and polytropos plugin obligation #4 wiring under the new tail model.
