# Why Rewrite Type-Level Metadata? (Large-anon Plugin Explained)

You're asking: *"Why not just let type families evaluate naturally? What's the point of the plugin rewriting them?"*

This is an excellent question that gets to the heart of GHC's type system limitations. Let me explain with a concrete example showing exactly where rewriting enables useful computation that would otherwise be impossible.

## The Core Problem: Stuck Type Families

Consider this simplified version of what `large-anon` provides:

```haskell
-- In Runtime.hs (simplified)
type family FieldTypes (f :: Type -> Type) (r :: Row) :: [(Symbol, Type)]
type instance FieldTypes f '[] = '[]
type instance FieldTypes f ((n := a) ': r) = '(n, f a) ': FieldTypes f r
```

This looks fine - it's a recursive type family that should compute `[('"a", f Int), ('"b", f Bool)]` for input `f` and `[("a",Int),("b",Bool)]`.

**But here's the catch**: GHC cannot reduce open type families during type checking unless *all* instances are visible and the reduction is guaranteed to terminate.

Since `FieldTypes` is an *open* type family (defined with `type family`, not `type instance` in a closed block), GHC assumes:
1. More instances could appear in other modules
2. Reduction might loop
3. Therefore: **do not reduce it automatically**

So if you write:
```haskell
foo :: FieldTypes Maybe [("a",Int),("b",Bool)] -> Int
foo _ = 42
```

GHC sees `FieldTypes Maybe [("a",Int),("b",Bool)]` as an **irreducible type family application** - it's stuck. You cannot use this type anywhere GHC needs to know the concrete structure (like in pattern matching, as an argument to another type family, etc.).

## What the Plugin Rewriter Does

The large-anon plugin's rewriter (`Data.Record.Anon.Internal.Plugin.TC.Rewriter`) does this:

1. **Watches for** type checker encounters with `tyConFieldTypes` or `tyConSimpleFieldTypes` (the type constructors behind these families)
2. **When it sees** an application like `FieldTypes f r` where `f` and `r` are known concrete types
3. **It computes** what the result should be (using the same equations as the type family instances)
4. **It rewrites** the type to replace `FieldTypes f r` with its computed result

Example:
- Input type: `FieldTypes Maybe [("a",Int),("b",Bool)]`
- Plugin recognizes this as an application of `FieldTypes` to `Maybe` and `[("a",Int),("b",Bool)]`
- Applies the equations: 
  - `FieldTypes Maybe (('"a",Int) ': ('"b",Bool) ': '[])` 
  - = `('"a", Maybe Int) ': FieldTypes Maybe (('"b",Bool) ': '[])`
  - = `('"a", Maybe Int) ': (('"b", Maybe Bool) ': FieldTypes Maybe '[])`
  - = `('"a", Maybe Int) ': (('"b", Maybe Bool) ': '[])`
  - = `[('"a", Maybe Int), ('"b", Maybe Bool)]`
- Rewrites the type to be exactly `[('"a", Maybe Int), ('"b", Maybe Bool)]`

After rewriting, GHC sees:
```haskell
foo :: [('"a", Maybe Int), ('"b", Maybe Bool)] -> Int
foo _ = 42
```

Which is a perfectly ordinary, concrete type that can be used anywhere.

## Where This Actually Matters: A Real Use Case

Let's look at how `large-anon` uses this in practice. In `Data.Record.Anon.Internal.Plugin.Runtime.hs`, we find:

```haskell
-- | Require that all field names in @r@ are known
class KnownFields (r :: Row k) where
  fieldNames :: DictKnownFields k r
  fieldNames = undefined

type DictKnownFields k (r :: Row k) = Tagged r [String]

evidenceKnownFields :: forall k r. [String] -> DictKnownFields k r
evidenceKnownFields = Tagged
```

And later:
```haskell
fieldMetadata :: forall k (r :: Row k) proxy.
     KnownFields r
  => proxy r -> [FieldMetadata Any]
fieldMetadata _ = map aux $ proxy fieldNames (Proxy @r)
  where
    aux name = case someSymbolVal name of
                 SomeSymbol p -> FieldMetadata p FieldStrict
```

This `fieldNames` approach works, but it's limited to just getting field *names*. What if you need the field *types*?

Suppose you want to write a function that:
1. Takes a record
2. For each field, extracts its value 
3. Puts it in a dynamic container (like `Dynamic`)
4. Returns a list of all field values

You'd need to know the type of each field to know how to extract it and what type to put in the `Dynamic`.

With rewritten `FieldTypes`, you could write:

```haskell
allFieldsToDyn :: forall f r. 
     (KnownFields r, AllFields r (Compose ToDyn f)) 
  => Record f r 
  -> [Dynamic]
allFieldsToDyn rec = 
  let fieldTypeList = fieldTypes (Proxy @f) (Proxy @r)  -- <-- Rewritten here!
      extractField :: (Symbol, Type) -> Dynamic
      extractField _ = undefined -- Actually uses evidence from AllFields constraint
  in map extractField fieldTypeList
```

After plugin rewriting:
- If `r = [("a",Int),("b",Bool)]` and `f = Maybe`
- `fieldTypes (Proxy @f) (Proxy @r)` becomes `[('"a", Maybe Int), ('"b", Maybe Bool)]`
- You can now map over this concrete list at compile time (via type class techniques)
- For each element, you know exactly what type to expect and how to extract it

**Without rewriting**: `fieldTypes (Proxy @f) (Proxy @r)` remains stuck as `FieldTypes Maybe [("a",Int),("b",Bool)]`. You cannot map over it because it's not a concrete list - it's an opaque type family application. The code wouldn't compile.

## The Key Insight: Making Type Families Useful for Computation

Type families are Haskell's primary mechanism for compile-time computation. But they're frustratingly limited because:
- They don't automatically reduce during type checking (for safety/openess reasons)
- Stuck type family applications are black boxes you can't inspect or decompose

The plugin rewriter **bridges this gap** by:
1. Allowing you to define expressive type-level functions (like `FieldTypes`)
2. Automatically computing their results when inputs are known
3. Making those results available as concrete, inspectable types

This transforms type families from "definitions that might or might not solve" into "reliable compile-time computation engines."

## For Your polytropos Codebase

If you want similar functionality:
1. Define type families for useful metadata (field types, field names, invariants, etc.)
2. Write a plugin rewriter that recognizes applications of these families
3. When the arguments are known concrete types, compute and rewrite to the result
4. Design your runtime to take advantage of this concrete metadata (e.g., for generating defaults, lenses, validation, etc.)

The rewriting step is what makes your type-level functions actually *computable* rather than just declarative - it turns them into active tools for generic programming.

As a concrete test: try writing a function that needs to iterate over field types in your polytropos codebase. If you hit a wall where you can't inspect or decompose a type family application, that's exactly where rewriting would help.