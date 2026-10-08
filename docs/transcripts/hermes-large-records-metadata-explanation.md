# Explanation: Type-Level Metadata Computation in large-anon

You asked for clarification on the "type-level metadata computation" point, specifically why rewriting type-level metadata is useful. Let me explain this with concrete examples from the large-anon codebase.

## What FieldTypes and SimpleFieldTypes Are

In `Data.Record.Anon.Internal.Plugin.Runtime.hs`, we see:

```haskell
-- | Type-level metadata
-- 
-- >    FieldTypes Maybe [ "a" := Int, "b" := Bool ]
-- > == [ '("a", Maybe Int), '("b", Maybe Bool) ]
type family FieldTypes (f :: k -> Type) (r :: Row k) :: [(Symbol, Type)]

-- | Like 'FieldTypes', but for the simple API (no functor argument)
-- 
-- >    SimpleFieldTypes [ "a" := Int, "b" := Bool ]
-- > == [ '("a", Int), '("b", Bool) ]
type family SimpleFieldTypes (r :: Row Type) :: [(Symbol, Type)]
```

These are **type families** - functions that operate at the type level, taking types as input and producing types as output.

## The Problem: Stuck Type Families

Without plugin intervention, if you wrote a type signature like:
```haskell
foo :: FieldTypes Maybe ['("a", Int), ('"b", Bool)] -> ...
```

The type checker would see `FieldTypes Maybe ['("a", Int), ('"b", Bool)]` as an **unsolved type family application**. It couldn't reduce this further because:
1. Type families are not automatically evaluated during type checking unless they match a known instance
2. The type checker doesn't know how to compute `FieldTypes` for arbitrary inputs

This would cause type errors in many contexts where GHC needs to know the exact type (e.g., when pattern matching, when using the type in another type family application, etc.).

## The Solution: Plugin-Assisted Rewriting

The large-anon plugin's **rewriter** (in `Data.Record.Anon.Internal.Plugin.TC.Rewriter`) does something clever:

1. It recognizes when the type checker encounters an application of `tyConFieldTypes` or `tyConSimpleFieldTypes` (the type constructors behind these type families)
2. It computes what the result *should be* based on the arguments
3. It **rewrites** the type to replace the stuck type family application with its computed result

For example:
- Input type: `FieldTypes Maybe ['("a", Int), ('"b", Bool)]`
- Plugin recognizes this as an application of `FieldTypes` to `Maybe` and `[('"a", Int), ('"b", Bool)]`
- Computes the result: `[ '("a", Maybe Int), '("b", Maybe Bool) ]`
- Rewrites the type to be exactly that concrete list

After rewriting, the type checker sees:
```haskell
foo :: [ '("a", Maybe Int), '("b", Maybe Bool) ] -> ...
```

Which is a perfectly normal, concrete type that can be used anywhere.

## Why This Is Useful: Concrete Examples

### 1. Building Default Values
In large-anon, when you want to create a record with all fields set to their "default" values (e.g., `Nothing` for `Maybe` fields), you need to know what the wrapped type is for each field.

With rewritten `FieldTypes`, you can write:
```haskell
defaults :: forall f r. KnownFields r => Proxy r -> [Dynamic]
defaults _ = map (toDyn . defaultVal) (fieldTypes (Proxy @f) (Proxy @r))
  where
    fieldTypes :: Proxy f -> Proxy r -> [(Symbol, Type)]
    fieldTypes _ _ = undefined -- Actually provided by plugin rewriting
    
    defaultVal :: (Symbol, Type) -> Dynamic
    defaultVal _ = toDyn (Nothing :: Maybe a) -- Simplified
```

Because `fieldTypes` gets rewritten to a concrete list like `[('"a", Maybe Int), ('"b", Maybe Bool)]`, you can iterate over it at compile time (via type class techniques) to generate the actual default values.

### 2. Generating Lenses or Prisms
If you want to create a lens for each field that works with the wrapped type:
```haskell
makeLenses :: forall f r. KnownFields r => Proxy r -> [Lens (f a) (f b)]
makeLenses _ = map makeFieldLens (fieldTypes (Proxy @f) (Proxy @r))
```

Again, because `fieldTypes` becomes concrete, the plugin can generate the exact number and types of lenses needed.

### 3. Enabling Type-Safe Operations
Consider a function that validates all fields in a record:
```haskell
validateAll :: forall r c. (AllFields r c, KnownFields r) => Proxy r -> (forall a. c a => a -> Bool) -> Bool
validateAll _ p = and $ map (\dict -> ...) (fieldDicts (Proxy @r) (Proxy @c))
```

Here, `AllFields r c` is a constraint that requires `c a` for every field type `a` in `r`. The plugin solves this constraint and generates the `fieldDicts` evidence - which is a vector of dictionaries, one for each field. This evidence generation depends on knowing the exact field types, which comes from the rewritten metadata.

### 4. Interoperability with Other Type-Level Code
If you have other type families that operate on lists of `(Symbol, Type)` pairs (like filtering fields by type, extracting field names, etc.), you need the input to be a concrete list, not a stuck type family application.

For example:
```haskell
-- Get just the field names from a field type list
type family FieldNames (xs :: [(Symbol, Type)]) -> [Symbol] where
  FieldNames '[] = '[]
  FieldNames ('(sym, ty) ': xs) = sym ': FieldNames xs

-- This only works if xs is concrete!
type MyFieldNames = FieldNames (FieldTypes Maybe ['("a", Int), ('"b", Bool)])
-- Without rewriting: MyFieldNames is stuck
-- With rewriting: MyFieldNames evaluates to '["a", "b"]
```

## The Key Insight

The rewriting isn't just about making the type checker happy - it's about **making type-level computation actually useful**. 

In Haskell's type system, type families are powerful but often frustrating because they don't automatically evaluate. The large-anon plugin bridges this gap by:
1. Allowing you to write expressive type-level functions (like FieldTypes)
2. Automatically computing their results during type checking when the inputs are known
3. Making those results available as concrete types that can be used in further type-level or term-level computation

This transforms type families from "black boxes that might or might not solve" into "reliable compile-time computation tools."

## For Your polytropos Codebase

If you want similar functionality, consider:
1. Defining type families that compute useful metadata about your records (field types, field names, invariants, etc.)
2. Writing a plugin rewriter that recognizes applications of these type families and replaces them with their computed results when possible
3. Ensuring your runtime code can take advantage of this concrete metadata (e.g., for generating defaults, lenses, validation, etc.)

The rewriting step is what makes the metadata "computable" rather than just "declared" - it turns your type family definitions into active compile-time computation engines.