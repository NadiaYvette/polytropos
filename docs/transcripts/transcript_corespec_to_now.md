What is the relationship of the type system modelled by ~/src/corespec-roles/ to the type system used within ~/src/ghc/ ?
The corespec‑roles development is a formal model of a core Haskell‑like language that makes the role system (nominal, representational, phantom) explicit in the type theory.  It is not the actual implementation that lives in GHC, but a Coq‑based specification that captures the essential typing rules, coercion machinery, and role‑based safety properties that GHC’s type system (System FC with roles) relies on.  In other words, corespec‑roles gives a *mathematical* account of the role‑annotated type system that GHC uses internally for type‑checking, generalization, and coercion generation, and it is used to prove metatheoretic results (type safety, parametricity, etc.) about that system.  The actual GHC type checker implements the same ideas in Haskell code, while corespec‑roles provides an independent, machine‑checked reference model.
How do row-polymorphic open ADTs / hybrid nominal-structural extensible variant records like in ~/src/ocaml/ or ~/src/row-types/ or ~/src/data-diverse/ or ~/src/open-adt/ relate to the type system implemented in ~/src/ghc/ and modelled in ~/src/corespec-roles/ ?
Row‑polymorphic open ADTs (or hybrid nominal‑structural extensible variant records) are a way of giving a datatype a *structural* interface while still keeping a *nominal* name for pattern‑matching and abstraction.  In the languages you mention the idea is:

* **OCaml polymorphic variants** – a type like `[`A of int | `B of bool]` is an *open sum*: any term that provides a subset of those tags can be used where the type is expected, and new tags can be added later without changing existing code.
* **row‑type libraries** (e.g. `row-types`, `data-diverse`, `open-adt`) encode the same idea at the type level: a type parameter `r :: Row k` stands for a row of labelled fields (for records) or labelled constructors (for variants).  Constraints such as `HasField l r a` or `HasConstructor l r a` let you query whether a particular label is present, and `SubRow r r'` lets you express that one row is a sub‑row of another (i.e. that `r'` contains at least the labels of `r`).  The concrete representation is usually a flat array of payloads together with a tag that is the hash of the label, so access by label is O(1).

**How this connects to GHC’s type system and the `corespec‑roles` model**

1. **GHC’s core language (System FC + roles)** already supports:
   * **Type‑level lists and type families** – you can encode a row as a type‑level list of `(Symbol -> Type)` pairs and write closed type families that compute a hash, an index, or a sub‑row relation.
   * **Constraints with functional dependencies or equality** – classes like `KnownHash s`, `HasField l r a`, or `HasConstructor l r a` can be solved by a type‑checker plugin that looks at the row structure and produces the appropriate dictionary evidence.
   * **Roles** – the phantom parameters that distinguish product vs sum, nominal vs structural, or named vs anonymous have role `phantom`; they never affect runtime representation, which matches the role‑based reasoning in `corespec‑roles`.
   * **Unpacked Word + SmallArray** – the concrete representation (`Rep`) is just an unboxed tag (`Word`) and a payload array; this is compatible with GHC’s ability to store unboxed fields and to generate efficient code for pattern matching on the tag.

2. **What `corespec‑roles` adds**  
   The `corespec‑roles` development gives a *formal, machine‑checked* account of a core language where:
   * **Roles** (nominal, representational, phantom) are first‑class in the typing judgment and are essential for proving type safety and parametricity.
   * **Type equality and coercions** are made explicit, which mirrors how GHC’s solver produces coercions for `KnownHash` evidence, `SubRow` proofs, etc.
   * **Dependent types** are available in the model (via the `FcEtt` core), so one can encode rows as dependent pairs `(label, type)` and reason about their extension properties directly in the logic.

   In short, `corespec‑roles` provides the *theoretical foundation* (role‑annotated System FC with dependent types) that justifies the practical extensions you implement via GHC plugins: the plugin‑generated `KnownHash`, `AllFields`, `SubRow`, etc., are exactly the kind of *role‑respecting, phantom‑only* constraints that the model proves safe to add without breaking type safety or parametricity.

3. **Putting it together for Polytropos**  
   * You define a `RowRep f rf r a` where `rf` (`'ProductRowT`/`'SumRowT`) and a phantom `af` (`Named`/`Anonymous`) capture the nominal/structural and named/anonymous distinctions—these are all phantom, hence role `phantom`.
   * The plugin supplies:
     * `KnownHash s` → gives a compile‑time `Int` tag for each label.
     * Closed type families `IndexOf r s` (or perfect‑hash → index map) that turn that tag into the actual array offset.
     * Classes `AllFields r c` / `AllCons r c` and `SubRow r r'` / `SubVar r r'` that produce the dictionaries needed for generic traversal, projection, and injection.
   * Because all of these constraints are solved by inspecting only the *structure* of the row (a finite type‑level list) and never by inspecting or manipulating the phantom parameters, they respect the role system: they are *representational* in the row argument and *phantom* in the flag arguments.  This is precisely the kind of extension that `corespec‑roles` shows preserves type safety and parametricity.
   * The resulting runtime representation (`Rep`) is identical for nominal and structural, named and anonymous uses; the only difference is which phantom arguments appear in the type, which are erased after type checking—so there is **no runtime overhead** for the nominal/structural distinction, matching the role‑based expectation that phantom arguments carry no computational content.

**Bottom line:**  
Row‑polymorphic open ADTs / hybrid nominal‑structural extensible variant records are encoded in GHC using the same mechanisms that `corespec‑roles` formalizes: phantom type‑level parameters for nominal/structural/named/anonymous distinctions, closed type families and constraint classes for hash‑based label → index mapping and sub‑row reasoning, and a Word‑tag + SmallArray payload representation.  The `corespec‑roles` model gives a proof‑checked justification that these extensions are sound with respect to GHC’s role‑annotated type system, so you can safely add them as plugins without breaking type safety or parametricity.
It's been suggested to me elsewhere that the Named/Anonymous phantom type idea was unsound and that it would be better to borrow the ideas of open and closed rows from ~/src/ocaml/ to handle these things.
The **Named/Anonymous** phantom flag you proposed is *not* inherently unsound—it is a phantom parameter, so it carries no runtime information and, as long as you do not expose any operation that can change it (e.g. an unsafe cast), the type system remains safe.  The worry usually raised is that a phantom flag alone does not *prevent* someone from treating a nominal type as extensible (or vice‑versa) by simply writing a type‑signature that changes the flag; the flag only records the programmer’s intention, it does not enforce it at the type level.

### What OCaml’s open/closed rows give you
OCaml distinguishes two kinds of rows:

* **open rows** – can be extended with extra labels; they are the default for polymorphic variant types and for object types.
* **closed rows** – have a fixed set of labels; they correspond to ordinary variants/records.

The key point is that the *kind* of the row (open vs. closed) is part of the type, and the type system will not let you write an expression that expects an open row where a closed row is required, or vice‑versa, without an explicit coercion.  In other words, the openness/closedness of a row is *enforced* by the kind system, not merely recorded by a phantom flag that could be ignored.

### How you could adapt that idea to Polytropos
Instead of (or in addition to) a Named/Anonymous flag, introduce a **row‑kind** parameter that tells whether the row is open or closed:

```haskell
data RowKind = Open | Closed   -- promoted to a kind

data RowRep f (rk :: RowKind) (rf :: RowType) (r :: Row k) a =
    RowRep (Rep f a)
```

* `rk = 'Closed` corresponds to a **named**, nominal type (the constructor/field set is fixed).
* `rk = 'Open` corresponds to an **anonymous**, structurally extensible type (the row can be instantiated with any superset of the labels you mention).

Now you can design the constraint solvers so that they only fire when the row is open:

* `KnownHash s` works for both kinds (it just gives the hash of a label).
* `AllFields r c` and `SubRow r r'` require `rk ~ 'Open` (or have a functional dependency that fails for `'Closed`).  
  This means you cannot write a generic `showAllFields` function for a nominal (closed) type unless you first explicitly open it (e.g. via a newtype wrapper or a type‑family that reduces a closed name to its open row).

* SubVariant – a constraint `SubVariant r r'` meaning `r'` is a sub‑variant of `r`, with evidence providing the projection indices (just like `SubRow` for records).  This enables functions like `projectVariant` and `injectVariant`.

* Generic operations – with `AllCons r Show` you could write a `showVariant :: Variant r -> String` that works for any set of constructors, using the same `reifyAllCons` pattern you already have for records.

* Source‑plugin variant – if you want ergonomic construction, the source plugin could recognise `VAR { … }` (or `#[ … ]`) and emit calls to runtime constructors such as `variantEmpty`, `variantInject`, etc., optionally using `typelet` for O(1) construction.

### Soundness comparison
| Approach | What it prevents | Where the guarantee lives |
|----------|------------------|---------------------------|
| **Named/Anonymous phantom flag** | Only prevents confusion if you *choose* not to expose a coercion; the type system itself does not stop you from mixing the two. | Relies on programmer discipline (no unsafe casts). |
| **Open/Closed row kind** | Prevents any term that expects an open row from being used where a closed row is required (and vice‑versa) without an explicit, visible conversion. | Enforced by the kind system; no need to rely on discipline. |

If you are happy to keep the API surface free of any casting operations that flip the flag, the phantom flag is sound.  If you want the type system to *actively* prohibit treating a nominal type as extensible (and the other way round), moving to an open/closed row kind—mirroring OCaml’s design—is the more robust solution.

### Recommendation for Polytropos
1. Keep the current `Rep`/`RowRep` layout (hash tag + payload array).  
2. Add a row‑kind parameter (`Open`/`Closed`) to `RowRep`.  
3. Default ordinary `data`/`newtype`/`type` declarations to `'Closed`.  
4. Require an explicit opt‑in (e.g. `{-# LANGUAGE ExtensibleRows #-}` or a keyword `data open … where …`) to get `'Open`.  
5. Make the generic solvers (`AllFields`, `SubRow`, etc.) require `rk ~ 'Open`.  
6. Provide safe conversion functions only if you explicitly want to promote a nominal type to an open row (e.g. `openNominal :: RowRep f 'Closed r a -> RowRep f 'Open r a`) and make it clear that such a conversion loses the nominal guarantee.

This gives you the same zero‑overhead, nominal/structural hybrid you want, with a stronger, kind‑based guarantee that matches the OCaml open/closed row discipline and preserves backward compatibility for existing Haskell code.
I think the OTT draft left out the HKD-ish functor parameter; is my reading correct? How difficult is it to reincorporate the HKD-ish functionality?
Yes – the OTT draft `ROW_ROLE_DEFNS_DRAFT.ott` talks only about plain rows and the role‑based constraints that operate on them.  It does **not** mention the higher‑kinded‑data (HKD) functor parameter that appears in the Polytropos representation:

```haskell
data Rep   f a = Rep {-# UNPACK #-} !Word !(SmallArray (f Any))
data RowRep f rf r a = RowRep (Rep f a)
```

So the draft’s rows are essentially `RowRep f …` with `f` fixed to `Identity` (or omitted entirely).  The functor `f` is what lets Polytropos reuse the same layout for:

* the actual data (`f ~ Identity`),
* metadata or validation (`f ~ Const String`, `f ~ Maybe`, etc.),
* or any other HKD‑style interpretation.

---

### How hard is it to add the HKD parameter back?

**Very little extra work** – the functor is completely orthogonal to the row algebra that the OTT draft formalises.  The steps are:

1. **Make the representation polymorphic in `f`.**  
   ```haskell
   data Rep   f a = Rep {-# UNPACK #-} !Word !(SmallArray (f Any))
   data RowRep f (rk :: RowKind) (af :: AnonFlag) (r :: Row k) a =
       RowRep (Rep f a)
   ```
   Both constructors already have the `f` parameter; you just keep it polymorphic throughout the codebase.

2. **Leave the shared row‑algebra unchanged.**  
   All the type families in `Polytropos.RowAlgebra` (`KnownHash`, `IndexOf`, `AllFields`, `SubRow`, …) operate **only on the row structure** (`r :: Row k`) and on labels/types.  They do not inspect or manipulate the functor `f`, so they remain valid for any `f`.  No modification is needed there.

3. **Adjust the plugin’s evidence generation to stay polymorphic in `f`.**  
   * When solving `KnownHash s` the plugin still emits a hash literal – no `f` involved.  
   * When solving `IndexOf r s` it still returns a `Nat` – again no `f`.  
   * For `AllFields r c` the plugin builds a list of dictionaries `[Dict (c ty_i)]`; the `ty_i` are the field types *as they appear in the row*, still independent of `f`.  
   * The only place `f` appears is when the plugin constructs the `SmallArray (f Any)` payload at runtime (e.g. when desugaring `ANON { … }`).  There you simply store the user‑provided values wrapped in `f` (e.g. `Identity x`, `Const "msg"` etc.).  No extra constraint solving is required.

4. **Update any term‑level code that unpacks/repacks the payload** (pattern matches, field accessors, generic folds, etc.) to be polymorphic in `f`.  Typically this is just a matter of:
   * using `fmap`/`traverse` when you need to work with the underlying `Any` values,
   * or providing `getConst`, `runIdentity`, etc., at the call sites where a specific interpretation of `f` is required.

5. **Verify that the phantom parameters (`rk`, `af`) remain role‑phantom** – they still carry no runtime information, so adding `f` does not affect the role system or the soundness proofs that the OTT draft sketches.

In short, the OTT draft omitted the HKD functor only because it was focusing on the row/role aspect; reintroducing it is a matter of keeping the existing `f` parameter polymorphic and ensuring the term‑level code treats it abstractly.  The theoretical account (row algebra, inclusion/equality judgements, role subsumption, constraint‑emission hand‑off) stays exactly the same; the representation layer simply becomes `Rep f` instead of `Rep Identity`.  No deep changes to the inference rules or the shared algebra are required.