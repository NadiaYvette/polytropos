# Mini-roadmap: closing the gap to a useful polytropos plugin

**Scope note:** This is a design/planning artifact, not a task packet. It exists
to connect the precedent review in this session to actual files in the repo. It is
companion material to:

- `plans/2026-10-09-plugin-gap-spec.md`
- `docs/notes/ROW_ROLE_DEFNS_DRAFT.ott` (the judgement/local-formal sketch the
  user asked to extend toward HKD-style row parameters)

**Reading assumption:** "useful to potential callers of the libraries" means
callers can depend on the plugin for generic-class, generic-type-level-metadata,
generic-projection/widening, and generic-construction ergonomics, not merely that
the current smoke tests pass. The current smoke state in this session is still
green: polytropos-core 32/32 and plugin smoke 10/10.

---

## 0. Current state, in one line

The plugin already solves the **literal index/emission** part well:
`FieldIndex`, `ConstructorIndex`, `RowEq`, `RowShow`, `RowEqSum`, `RowShowSum`,
and `HasField` (for `OverloadedRecordDot`). What it does not yet supply is the
**generic row-programming surface** that makes a row-polymorphic library usable
as a foundation: generic field-class dictionaries, row metadata rewriting,
subrow/projection evidence, compile-time label hashes, and HKD-aware row
vocabulary.

So the gap is not "the plugin is fake." The gap is "the plugin is a literal-index
engine without the generic layer around it."

---

## 1. Gap list, ranked by what callers will feel first

### 1.1 Generic dictionary supply for field classes (highest)

**Why it matters:** large-anon's `AllFields r c` turns a row-polymorphic
constraint into a usable flat array of field dictionaries. That is what enables
generic `Show`/`Eq`/serialization/mapping/other-class workflows over a row
without writing per-row instances by hand.

**Current state:** `DictAny` exists in `Polytropos.Core` as a forward-looking
mechanism, but there is no generic all-fields class plus solver path yet. Also,
the plugin's `getEqDict`/`getShowDict` are currently gated to a small hardcoded
set of types, which is exactly the gap the user wants closed toward full-coverage
generic-style class/type coverage.

**What "done" looks like:**

- A class comparable in spirit to `AllFields`, specialized to polytropos' row
  vocabulary, whose evidence is supplied by the plugin.
- The plugin can supply field-class dictionaries generically for a broad,
  closed-but-expandable set of classes/types, not just `Int`/`Bool`/`Word`.
- The test suite can assert this through the plugin, not just through hand-written
  per-row instances.

**Primary files:** `packages/polytropos-core/src/Polytropos/Core.hs`,
`packages/polytropos-plugin/src/Polytropos/Plugin.hs`,
`packages/polytropos-core/test/Main.hs`.

### 1.2 HKD-aware row vocabulary (high)

**Why it matters:** large-anon threads a functor parameter `f` through its row
so that `Record f r` can represent e.g. `f x` per field, which is the HKD-style
basis for boxing, defaults, constraint reification, and many generic operations.
polytropos currently has `Rep f`, but the row vocabulary itself is not yet HKD-aware
in the same way.

**Current state:** `Row` and `SumRow` are concrete `[Pair Symbol Type]` and
`[Pair Symbol Row]`. D3 in `POLYTROPOS_DESIGN.md` says the functor parameter is
deferred. That is the part to close.

**What "done" looks like:**

- Row vocabulary that can express `Row f` / `SumRow f` (or the Option D
  `RowType` analogue) so the row can carry the HKD functor parameter.
- Evidence classes and plugin solving that work over the HKD-aware row shape.
- A clear note in the draft/design about where `f` lives and what it is for.

**Primary files:** `docs/notes/ROW_ROLE_DEFNS_DRAFT.ott`,
`docs/notes/POLYTROPOS_DESIGN.md`, `packages/polytropos-core/src/Polytropos/Core.hs`.

### 1.3 Type-level row metadata + plugin rewriting (high)

**Why it matters:** large-anon does not just solve constraints; it rewrites type
families like `FieldTypes f r` and `SimpleFieldTypes r` to concrete
`[(Symbol, Type)]` lists when the row is fully known. That is what makes generic
programming over field names/types usable at the type level.

**Current state:** polytropos has a row vocabulary and a plugin that solves index
and equality/show constraints, but no type-family metadata layer and no rewriter
that reduces such families at use sites.

**What "done" looks like:**

- At least one metadata type family over polytropos rows (field types, field names,
  or both).
- A plugin rewriter that reduces it when the row is known, with test coverage.
- An explicit statement of which metadata the plugin will rewrite, and which it
  will not.

**Primary files:** `packages/polytropos-core/src/Polytropos/Core.hs`,
`packages/polytropos-plugin/src/Polytropos/Plugin.hs`,
`docs/notes/ROW_ROLE_DEFNS_DRAFT.ott`.

### 1.4 Subrow/projection evidence for sums/variants (medium-high)

**Why it matters:** large-anon solves `SubRow` by emitting projection indices as
evidence, which is what makes projection/injection/lens-style operations over
extensible rows usable without hand-written per-field plumbing. For polytropos,
this is especially relevant to variant narrowing, sub-variant extraction, and
eliding runtime tag checks where possible.

**Current state:** design-side there is a widening/narrowing story and a sketched
`SubSum`-style evidence idea, but no plugin-solved subrow/projection evidence class
with emitted indices as a library service yet.

**What "done" looks like:**

- A constraint/evidence class for subrow/subvariant relationships over polytropos
  rows.
- The plugin emits projection/narrowing indices as evidence.
- Some consumer (even a smoke test) uses it.

**Primary files:** `packages/polytropos-core/src/Polytropos/Core.hs`,
`packages/polytropos-plugin/src/Polytropos/Plugin.hs`,
`docs/notes/POLYTROPOS_DESIGN.md`.

### 1.5 Compile-time label hashing (medium)

**Why it matters:** large-anon uses `KnownHash` so field names become efficient
runtime keys without plumbing `KnownSymbol` everywhere and without runtime string
hashing in hot paths. If polytropos wants efficient name-based dispatch or
interning, this is the shape to adopt.

**Current state:** `Field n` and `IsLabel` exist for ergonomics, but there is no
`KnownHash`-style compile-time hash supply in the plugin story yet.

**What "done" looks like:**

- A compile-time hash class/mechanism for row labels.
- A stated purpose: what it is used for, and what it is not used for.

**Primary files:** `packages/polytropos-core/src/Polytropos/Core.hs`,
`packages/polytropos-plugin/src/Polytropos/Plugin.hs`.

### 1.6 Source-plugin construction syntax (medium, later)

**Why it matters:** large-anon has a source plugin that desugars
`ANON { ... }` / `ANON_F { ... }` into insertion chains before typechecking.
That is "just" syntax, but it often determines whether a library feels
constructable or constructable-with-pain.

**Current state:** no source plugin of that shape yet.

**What "done" looks like:**

- A declared construction syntax, and a source plugin that desugars it.
- Not required for correctness, but important for adoption.

**Primary files:** a new plugin source module, plus cabal/plugin wiring.

### 1.7 Generic instance layer, not just raw `Rep` (medium)

**Why it matters:** callers usually want generic `Eq`/`Show`/serialization/other
instances derived from the row. polytropos has `Rep`, hand-written and plugin-solved
`RowEq`/`RowShow` families, and satellite optics/lens/microlens packages that use
`FieldIndex`/`ConstructorIndex`, but not yet a shipped generic instance layer that
callers would use directly.

**Current state:** present in intent; not yet a complete library surface.

**What "done" looks like:**

- Generic classes/methods that derive instances from the row.
- Test coverage showing they work through the plugin, including for HKD-aware rows.

**Primary files:** `packages/polytropos-core/src/Polytropos/Core.hs`,
satellite packages, test suites.

---

## 2. Suggested order

If the goal is "get to useful quickly without rebuilding the wrong layer," I would
sequence it like this:

1. **Close the dictionary-coverage gap first.** That is the most direct route from
   "literal indices" to "generic row library," and it is exactly the gap the user
   named in this session. Make `getEqDict`/`getShowDict` generic-style and add the
   all-fields-style dictionary supply path.
2. **Make the row vocabulary HKD-aware.** Do this in parallel or just after the
   dictionary work, because HKD is the shape that lets the generic dictionary/metadata
   story compose.
3. **Add type-level metadata + rewriting.** This is the thing that makes the row
   usable for generic programming at the type level, not just at the term level.
4. **Add subrow/projection evidence for variants.** This is where the sum/variant
   story becomes generically usable instead of manually dissected.
5. **Later:** label hashing, source-plugin syntax, and the generic instance layer
   as adoption/ergonomics surface.

---

## 3. What to read alongside this

- `plans/2026-10-09-plugin-gap-spec.md` for the concrete immediate-next-step sketch.
- `docs/notes/ROW_ROLE_DEFNS_DRAFT.ott` for the judgement/local-formal side the
  user asked to extend toward HKD-style row parameters.
- `docs/notes/POLYTROPOS_DESIGN.md` §1/D3 and §5/§6 for current vocabulary and
  plugin obligations.
- The local large-records checkout for the precedent shapes: large-anon's
  `AllFields` + `DictAny` + rewriter + `KnownHash` + `SubRow`, and large-records'
  annotation-driven scalable record rewriting.

---

## 4. Non-claims

- This list does **not** say the current plugin is wrong. It says the current plugin
  is a good literal-index core and that the generic surface around it is what is
  missing for caller usefulness.
- This list does **not** commit to copying large-anon or large-records verbatim.
  It says those are the precedent shapes to aim at, adapted to polytropos' own
  one-representation-for-products-and-sums design.
