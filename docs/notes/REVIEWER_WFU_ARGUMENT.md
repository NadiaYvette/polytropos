# Reviewer-facing well-foundedness argument (source-mapped)

**Owns:** reviewer-facing source-mapping note for the judgement/paper argument.

## 1. Why this note exists

A reviewer asked, in effect: *how do you know the judgement draft is not
making up a constraint kind and a role apparatus that GHC does not actually
have?*

This note answers with sources, not assertions. Each point names the exact
file or artifact that justifies it, and names the artifact's role in the
argument (primary anchor, secondary support, internal source, or out of
scope).

The note is meant to be read alongside `ROW_ROLE_DEFNS_DRAFT.ott`: the draft
is the formal sketch, this note is the source map for the claims the sketch
makes about the surrounding ecosystem.

## 2. The four-point argument, source-mapped

### 2.1 What the draft claims, stated plainly

1. The draft defines row judgements (inclusion, widening, equality, role
subsumption) against a stated background theory, not against GHC's
constraint solver.
2. The row side is anchored to OCaml's row machinery, not to GHC.
3. The role side is anchored to the ICFP 2019 corespec roles apparatus, not
to GHC — though it claims GHC already has the same *class* of apparatus.
4. The constraint *form* the draft uses (`r1 ~ r2 : A / R`) is GHC's
existing equality predicate parameterized by a role. The draft does not
invent a new constraint kind.
5. The plugin boundary is internal to the repo: the tests specify what the
plugin must emit, the plugin emits literals, and the hand-off is stated
explicitly in the draft.

### 2.2 Row side — primary anchor

**Citation (OCaml, primary):** OCaml typechecker source for row inclusion,
unification, and the row representation types:

- `typing/ctype.ml` in the OCaml compiler:
  - `merge_row_fields` / `merge_rf`
  - `subtype_row`
  - `unify_row` / `unify_row_field`
  - `row_rep`, `row_more`, `row_closed`, `row_fixed`
  - `static_row`
- `docs/notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md` (polytropos-local
  reading of the above)

**What it justifies in the argument:** the draft's row judgements
(inclusion, widening, the tail contract) are aligned with an existing
row-algebra implementation, not invented from whole cloth. The OCaml source
is the primary row-side anchor.

**Secondary theoretical support for the width-subtype-vs-equality
distinction:** Dolan, *Algebraic Subtyping* (PhD thesis); Parreaux, *The
Simple Essence of Algebraic Subtyping* (ICFP Functional Pearl). These
support the draft's choice of two distinct tail judgements (`⊆₊` for
inclusion, `≃₊` for equality) rather than defining equality as mutual
inclusion. They are secondary: they are about subtyping theory and inference
algorithms, not about GHC Core roles and not about OCaml's compiler
implementation.

### 2.3 "Tilde at a role" constraint form — GHC-native citation

**Canonical citation (GHC, not corespec):** the draft's §0 GHC anchor is
the canonical GHC-native paragraph for "the plugin emits ~ constraints at
roles, which GHC already supports." The paragraph below is the same content
as §0's GHC anchor; keep these two in sync.

**GHC compiler source for equality predicates and the role machinery on the
constraint/coercion side:**

- `compiler/Language/Haskell/Syntax/Basic.hs` — `data Role = Nominal |
  Representational | Phantom` (constructor order coincides with the
  *super*typing relation on roles)
- `compiler/GHC/Core/Predicate.hs` — `data EqRel = NomEq | ReprEq`,
  `eqRelRole :: EqRel -> Role`, `mkEqPredRole :: Role -> Type -> Type ->
  PredType`, `mkNomEqPred`, `mkReprEqPred`; the `EqPred EqRel Type Type`
  constructor of `data Pred`; the classify/predication machinery that treats
  `(t1 ~# t2)` and `(t1 ~R# t2)` as equality predicates
- `compiler/GHC/Core/TyCo/Rep.hs` — `Note [Roles]` (the GHC roles note;
  points to `docs/core-spec/core-spec.pdf` and to
  https://gitlab.haskell.org/ghc/ghc/wikis/roles-implementation, and to
  Weirich et al., *Generative Type Abstraction and Type-level Computation*,
  POPL 2010); coercion role machinery including `SubCo` (nominal-to-
  representational demotion) and `TyConAppCo` role parameter
- `compiler/GHC/Core/Coercion.hs` — `Note [Roles]` on the coercion side,
  including `setNominalRole_maybe` and the role-parameterized coercion
  constructors

**What it justifies in the argument:** that the draft's row-equality
constraint form `r1 ~ r2 : A / R` is GHC's existing equality predicate
parameterized by a role — NOT a new constraint kind invented by polytropos.
GHC already has:

- a three-role lattice (Nominal, Representational, Phantom) on its own,
  independent of our draft's two-role Nom/Rep lattice
- equality predicates tagged by `EqRel` (NomEq / ReprEq), which is the
  GHC-side analogue of our `/ R` role index
- a constructor `mkEqPredRole :: Role -> Type -> Type -> PredType` for
  building a primitive equality predicate at a chosen role
- the role/subsumption apparatus (SubCo, the Nom→Rep demotion) that
  realizes the same Nom ≤ Rep direction our draft's Sub rule uses

So the claim "the plugin emits ~ constraints at roles, which GHC already
supports" is anchored in GHC's actual source, with corespec as the separate
mechanized justification for why the Nom/Rep apparatus is well-founded.

**What it does NOT claim:** that GHC has anything called a "row constraint"
or a "row-equality constraint" specifically. GHC has equality predicates at
a role; our draft's `r1 ~ r2 : A / R` is that machinery applied to row types.
Whether GHC's existing role machinery reaches row types the way our draft
assumes is a question for the GHC reviewer and for the plugin's actual
emission behavior, not a claim this note makes on GHC's behalf.

**Draft sections that map:** `ROW_ROLE_DEFNS_DRAFT.ott` §0 (the GHC-native
anchor paragraph), §10 (constraint form `RowEq`), §11 (role-subsumption on
that form).

**Review-side caveat:** GHC's role lattice is THREE-role (Nominal /
Representational / Phantom); the draft's is TWO-role (Nom / Rep). This note
does not claim the two are identical; it claims the Nom ≤ Rep direction GHC
already has is the direction the draft's Sub rule uses.

### 2.4 Plugin boundary — internal sources, not external

The plugin-boundary argument (literal emission, no type-level search, stated
hand-off, tested obligations) is justified by internal repo sources, not by
external citations.

**Sources consulted for this update:**

- `packages/polytropos-core/test/Main.hs` — hand-written `RowEq` /
  `RowShow` instances as the emission spec
- `packages/polytropos-plugin/src/Polytropos/Plugin.hs` — plugin
  implementation
- `packages/polytropos-plugin/tests/smoke/Main.hs` — plugin smoke tests
- `packages/polytropos-core/src/Polytropos/Core.hs` — evidence class
  declarations and `Rep` / `RowRep` surface
- `.agents/rules/plugin-invariants.md` — literal-evidence and Core-AST
  synthesis invariants

**What the sources say, concretely:**

- The `RowEq ProductRowT R2` and `RowShow ProductRowT R2` instances in
  `Main.hs` are the literal spec: tag equality, arity equality, then slot
  comparisons at fixed indices (`intAt0`, `boolAt1`) with no type-level
  search. The plugin's `solveRowEq` emits exactly that shape: tag compare
  (`psRepTag` / `psEqClass` / `$fEqWord`), arity compare (`psRepArity` /
  `$fEqInt`), then `compareField` per walked field at literal indices.
- The plugin walks the row once via `walkRowWithTypes` (a static type-tree
  walk over the row carried in the `RowRep` type), emits literal `Int`
  indices from that walk, and builds Core dictionaries by `mkCoreLams` /
  `mkCoreApps` over `unRowRep`, `repTag`, `repArity`, `fieldAt`,
  `noInlineUnsafeCo`. It does not induct over the row at the use site.
- The plugin's `getEqDict` / `getShowDict` are closed over `Int`, `Bool`,
  `Word`. Any field type outside that set is a hard `error` at plugin solve
  time, not a type-level fallback. That is a concrete scope bound, not an
  unbounded claim.
- `RowEqSum` / `RowShowSum` are implemented by the plugin (tag dispatch,
  per-constructor field walks), and the smoke test (`Main.hs` in
  `tests/smoke`) exercises them. The core test suite only writes a
  `RowEqSum` instance for a single-constructor sum by hand; the plugin's
  sum story is exercised through the smoke tests, not the hand-written core
  instances.
- `HasField` is implemented by the plugin for native `OverloadedRecordDot`.
  That is a separate solver path (`solveHasField`) and is exercised by the
  smoke test's `OverloadedRecordDot` group.

**What is still open (is not yet specified by the sources):**

- The plugin currently solves the core literal-emission obligations for
  product rows and sum rows over `Int`, `Bool`, `Word` only. The coverage
  of other field types is not extended by any source here; it is a planned
  expansion, not an existing fact.
- `FieldIndex` / `ConstructorIndex` are solved literally by the plugin, but
  the core test suite does not currently assert them through the plugin in
  the same way it asserts `RowEq`/`RowShow` through the smoke tests; the
  smoke tests exercise `HasField` (via `OverloadedRecordDot`) but not
  `FieldIndex`/`ConstructorIndex` directly.
- The plugin's sum-dispatch bodies are tree-shaped conditional dispatches
  over constructor tags. That is literal emission, but the shape is not
  covered by a hand-written sum instance in the core test suite in the same
  way the product case is. The smoke tests cover it at runtime, which is the
  plugin's acceptance gate.

**The argument, restated with the gaps visible:**

The tests specify the plugin; the plugin is literal; the boundary contract
in the draft makes the hand-off explicit. The hand-written `RowEq`/`RowShow`
instances in `Main.hs` are the spec for product rows; the plugin's
`solveRowEq`/`solveRowShow` emit that spec shape as Core AST literals. The
sum case and `HasField` are specified and accepted through the plugin smoke
tests rather than hand-written core instances. The gaps above are concrete
scope vs. implementation differentials, not a failure of the literal-emission
invariant.

### 2.5 Undecided surface — syntax and plugin entry

The emission spec is concrete enough to be read and checked. The user-facing
syntax and the final plugin entry shape are not yet decided.

That is a documentation/planning state, not a verification blocker for the
emission spec: the test spec and the invariants doc describe what the plugin
must emit regardless of how the surface is eventually spelled.

### 2.6 What is out of scope for this note

- Soundness proofs for the judgement draft. That is the draft's own burden,
  not this note's.
- Whether the draft's two-role lattice is the final shape. It is the draft's
  current shape; if it changes, this note's §2.3 caveat is the part that
  touches the role apparatus claim.
- Anything about the third shared layer. That is a separate open loop with
  its own trigger.

---

## 3. Maintenance rule

When a source cited here changes status, this note is updated in the same
change set. When the draft's anchoring paragraph changes, §2.3 is read
against the draft's §0 and corrected if they drift.

This note is a source map. It does not replace the draft, the OCaml source,
the GHC source, the plugin code, or the test spec.It points at them.

Assisted-by: Freebuff (Upstage AI / Solar Pro 4)
