# Why large-anon Rewrites Type-Level Metadata (Simple Explanation)

## The Problem: GHC Won't Compute Type Families Automatically

When you define a type family like:
```haskell
type family FieldTypes (f :: Type -> Type) (r :: Row) :: [(Symbol, Type)]
type instance FieldTypes f '[] = '[]
type instance FieldTypes f ((n := a) ': r) = '(n, f a) ': FieldTypes f r
```

GHC **will not automatically compute** `FieldTypes Maybe [("a",Int),("b",Bool)]` during type checking.

Why? Because:
1. `FieldTypes` is an "open" type family (defined with `type family`)
2. GHC assumes more instances could be added elsewhere
3. To avoid non-termination or inconsistencies, GHC leaves such applications **stuck** (unevaluated)

So if you try to use:
```haskell
foo :: FieldTypes Maybe [("a",Int),("b",Bool)] -> Int
```
GHC sees `FieldTypes Maybe [("a",Int),("b",Bool)]` as an opaque, unknown type - you can't pattern match on it, pass it to other type families, or use it anywhere GHC needs to know the concrete structure.

## The Solution: Plugin-Assisted Rewriting

The large-anon plugin's rewriter:
1. Watches for when the type checker encounters `FieldTypes f r`
2. When `f` and `r` are known concrete types, it computes the result using the same equations
3. **Rewrites** the type to replace `FieldTypes f r` with its computed value

Example:
- Input: `FieldTypes Maybe [("a",Int),("b",Bool)]`
- Plugin computes: `[("a",Maybe Int), ("b",Maybe Bool)]`
- Rewrites the type to be exactly that

After rewriting:
```haskell
foo :: [("a",Maybe Int), ("b",Maybe Bool)] -> Int
```
Which is a normal, concrete type GHC can work with freely.

## Why This Matters: Enabling Generic Programming

This rewriting enables useful compile-time computation like:
- Generating default values for all fields (need to know each field's type)
- Creating lenses or prisms for each field (need to know each field's type)
- Building validation functions that work per-field (need field-type-specific logic)
- Any operation that requires iterating over or inspecting field types at compile time

Without rewriting, these would be impossible because you couldn't inspect or decompose the stuck `FieldTypes` application.

## In Short

**Rewriting turns type family definitions from black boxes into reliable compile-time computation tools.**

It lets you write expressive type-level functions (like `FieldTypes`) and have the plugin automatically compute their results when the inputs are known - making those results available as concrete types for further computation.