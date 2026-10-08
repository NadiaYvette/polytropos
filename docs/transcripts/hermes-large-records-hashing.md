# Explanation: Compile-Time Hash Known Instances in large-anon

You asked for clarification on the "compile-time hash known instances" point, specifically why computing hashes of symbols at compile time is useful and what problem it solves. Let me explain this with concrete examples from the large-anon codebase.

## What the KnownHash Class Is

In `Data.Record.Anon.Internal.Plugin.Runtime.hs`, we see:

```haskell
-- | Symbol (type-level string) with compile-time computed hash
-- 
-- Instances are computed on the fly by the plugin.
class KnownHash (s :: Symbol) where
  hashVal :: forall proxy. proxy s -> Int

type DictKnownHash (s :: Symbol) =
       forall proxy. proxy s -> Int

evidenceKnownHash :: forall (s :: Symbol).
  Int -> DictKnownHash s
evidenceKnownHash x _ = x
```

This defines:
- A class `KnownHash s` where `s` is a type-level string (`Symbol`)
- The class has one method: `hashVal :: forall proxy. proxy s -> Int` (which, given a proxy for the symbol, returns an `Int`)
- The dictionary type `DictKnownHash s` is essentially `forall proxy. proxy s -> Int` (a function that, given any proxy for the symbol, returns an `Int`)
- `evidenceKnownHash` is the constructor: given an `Int`, it produces the evidence for `KnownHash s`

In practice, when the plugin solves a `KnownHash "fieldname"` constraint, it computes the hash of the string `"fieldname"` and returns `evidenceKnownHash <hash>`.

## Why Do We Need Compile-Time Hashing of Symbols?

### The Problem: Symbols Are Opaque at Runtime

In Haskell, type-level strings (`Symbol`) exist only at compile time. At runtime, there is no direct way to:
- Inspect what a `Symbol` is
- Compare two `Symbol`s for equality (beyond what the type checker can do)
- Convert a `Symbol` to a runtime `String` without special tricks (like `Symbol` to `String` via `KnownSymbol` and `symbolVal`, which requires a `KnownSymbol` constraint)

If you want to use a `Symbol` as a key in a runtime data structure (like a `HashMap` for efficient field lookup), you need to convert it to a hashable runtime value. But you can't do this generically without knowing the specific symbol at compile time.

### The Solution: Precompute Hashes at Compile Time

The large-anon plugin solves this by:
1. When it encounters a constraint like `KnownHash "myfield"`
2. Computing the hash of the string `"myfield"` at compile time (using `Data.Hashable.hash` or similar)
3. Producing the evidence: `evidenceKnownHash <computed_hash>`

This evidence can then be used at runtime to get the hash of the symbol via:
```haskell
getHash :: KnownHash s => proxy s -> Int
getHash _ = hashVal (Proxy :: Proxy s)
-- Which, given the evidence, returns the precomputed hash
```

Because the hash is computed at compile time, `hashVal` is effectively a constant function - no runtime work is needed to compute the hash of the symbol.

## Why This Matters: Enabling Efficient Record Operations

Let's look at how `large-anon` actually uses `KnownHash`. In `src/Data/Record/Anon/Internal/Advanced.hs`, we find:

```haskell
-- | A field in a record, with its name and value
data Field (n :: Symbol) (a :: Type) where
  Field :: (KnownSymbol n, KnownHash n) => Proxy n -> a -> Field n a

-- | Use OverloadedLabels to create a field
instance (n ~ n', KnownSymbol n, KnownHash n) => IsLabel n' (Field n) where
  fromLabel _ = Field Proxy
```

And later:
```haskell
-- | Convert a field name to a hash for use in efficient lookup
mkFieldName :: (KnownSymbol n, KnownHash n) => Proxy n -> FieldName
mkFieldName _ = FieldName (hashVal Proxy)
```

Here, `FieldName` is likely a wrapper around an `Int` (the hash) used internally for efficient record representation.

### Concrete Use Case: O(1) Field Access by Name

Suppose we want to implement a record type where:
- Fields are stored in an array indexed by field position
- We want to look up a field by its name (like `record #fieldname`) in O(1) time
- To do this, we need to map field names to array indices

With `KnownHash`, we can:
1. At compile time, compute a hash for each field name
2. Use that hash (e.g., modulo array size) to compute the index
3. Store the hash-to-index mapping in a compile-time generated lookup table (or perfect hash if possible)
4. At runtime, to look up `#fieldname`, compute its hash (O(1) via `KnownHash` dictionary) and use the precomputed mapping to get the index

This gives O(1) field access by name without needing to:
- Keep an association list of (String, index) pairs at runtime
- Do string comparisons at runtime for each lookup
- Require `KnownSymbol` constraints everywhere (which need `symbolVal` calls)

### Another Use Case: Hash-Consing or Interning

If you want to intern field names (so that the same field name always uses the same runtime representation), you need a way to map field names to unique IDs. Computing a hash of the symbol at compile time gives you a deterministic ID that you can use without runtime string hashing.

## How the Plugin Actually Computes the Hash

From `src/Data/Record/Anon/Internal/Plugin/TC/Constraints/KnownHash.hs`:

```haskell
evidenceKnownFieldLabel ResolvedNames{..} CKnownHash{..} =
  return $ EvExpr $
    evDataConApp
      (classDataCon clsKnownHash)
      typeArgsEvidence
      [ mkCoreApps (Var idEvidenceKnownHash) $ concat [
            map Type typeArgsEvidence
          , [ mkUncheckedIntExpr . fromIntegral $
                  hash (unpackFS knownHashLabel)
            ]
          ]
        ]
```

When solving `KnownHash "label"`:
1. `knownHashLabel` is the `FastString` of the literal symbol (e.g., `"myfield"`)
2. `unpackFS knownHashLabel` converts it to a regular `String`
3. `hash` (from `Data.Hashable`) computes the hash of that string
4. `mkUncheckedIntExpr` turns that hash into a core expression literal
5. The evidence is `evidenceKnownHash <hash>`

This means the hash is computed by the plugin during type checking and baked into the compiled code as a literal.

## Why This Is Better Than Runtime Hashing

You might ask: "Why not just compute the hash at runtime when needed?"

Because:
1. **Redundant work**: If you need the hash of the same symbol many times (e.g., for every field access in a loop), computing it once at compile time and reusing the constant is faster than hashing the string every time.
2. **No runtime dependency**: You don't need to carry the original string or a hashing function at runtime just to get the hash.
3. **Enables compile-time optimizations**: If the hash is known at compile time, the compiler can do constant folding, branch prediction, etc. (e.g., if you switch on the hash of a field name).
4. **Deterministic and pure**: The hash is a pure function of the symbol, so computing it at compile time is safe and referentially transparent.

## For Your polytropos Codebase

If you want similar functionality, consider:
1. Defining a `KnownHash` class like large-anon's (or using `KnownSymbol` + runtime hashing if compile-time hash isn't critical)
2. Writing a plugin constraint solver for `KnownHash` that:
   - Recognizes `KnownHash <literal symbol>` constraints
   - Computes the hash of the literal string at compile time
   - Produces evidence containing that hash
3. Using the `KnownHash` constraint in your library where you need efficient, compile-time-computable mapping from field names to IDs (e.g., for:
   - Field name → array index mapping
   - Field name → unique internal ID
   - Hash-based field lookup in records
   - Interning or hash-consing of field names
4. Ensuring your runtime code can use `hashVal proxy` to get the precomputed hash with zero runtime cost.

## Key Insight

Compile-time hashing of symbols turns an opaque, compile-time-only entity (`Symbol`) into a usable runtime value (its hash) with **zero runtime cost**. This enables efficient, hash-based operations on field names (like O(1) lookup) while preserving the type-level safety and expressiveness of using symbols as field names.

It's similar to the metadata rewriting point: both take compile-time type-level computations and make their results available as usable values (types for metadata, integers for hashes) with no runtime overhead.