# Explanation: Subrecord Projection Indices in large-anon

You asked for clarification on point 4: "Subrecord Projection Indices" and mentioned being surprised that this isn't automatic. Let me explain what this means, why it requires explicit effort, and how the large-anon plugin handles it.

## What Does "Subrecord" Mean?

In the context of extensible records (like those in large-anon), a record type is a **row** - a type-level list of field names and types. For example:

```haskell
type FullRecord = '[ "name" := String, "age" := Int, "active" := Bool, "score" := Double ]
type SubRecord  = '[ "name" := String, "active" := Bool ]
```

We say `SubRecord` is a **subrecord** of `FullRecord` because every field in `SubRecord` (name and active) also appears in `FullRecord` with the same type.

The constraint `SubRow r r'` (where `r` is the source row and `r'` is the target row) means: "`r'` is a subrecord of `r`" - every field in `r'` exists in `r` with the same type.

## Why This Isn't Automatic (The Subtlety)

You might think: "If I have a record of type `FullRecord`, why can't I just treat it as a `SubRecord` by taking the first two fields?" The issue is **field order and positioning**.

Records in large-anon (and most extensible record libraries) are **ordered** - the position of a field matters for runtime representation. The runtime representation of a record is typically a vector or tuple where field values are stored in the order they appear in the row.

Consider how these records might be laid out in memory:

- `FullRecord`: [ name:String, age:Int, active:Bool, score:Double ]
  - Index 0: name
  - Index 1: age
  - Index 2: active
  - Index 3: score

- `SubRecord`: [ name:String, active:Bool ]
  - Index 0: name
  - Index 1: active

If you simply took the first two fields of a `FullRecord`, you'd get `[ name:String, age:Int ]` - which is **not** a `SubRecord` because the second field is `age` (Int) instead of `active` (Bool).

To convert a `FullRecord` to a `SubRecord`, you need to:
1. Extract the `name` field (at index 0 in source)
2. Extract the `active` field (at index 2 in source)
3. Place them in target order: [ name, active ]

This requires knowing: **for each field in the target record, what is its index in the source record?**

## What the Plugin Actually Does

When the plugin encounters a `SubRow r r'` constraint:
1. It verifies that `r'` is indeed a subrecord of `r` (every field in `r'` exists in `r` with the same type)
2. **Instead of just producing a yes/no answer, it computes the projection indices**: a list of integers where the i-th element is the index in the source record `r` of the i-th field in the target record `r'` (in target order)
3. It packages these indices as the evidence for the `SubRow r r'` constraint

The evidence type is defined in `Data.Record.Anon.Plugin.Internal.Runtime.hs`:

```haskell
-- | In order of the fields in the /target/ record, the index in the /source/
type DictSubRow k (r :: Row k) (r' :: Row k) =
       Tagged '(r, r') [Int]

evidenceSubRow :: forall k r r'. [Int] -> DictSubRow k r r'
evidenceSubRow = Tagged
```

So if we have:
- `r = [ "name" := String, "age" := Int, "active" := Bool, "score" := Double ]`
- `r' = [ "name" := String, "active" := Bool ]`

The plugin produces evidence: `evidenceSubRow [0, 2]` meaning:
- Target field 0 (`name`) is at source index 0
- Target field 1 (`active`) is at source index 2

## How This Enables Record Operations

With these projection indices, we can implement operations like **projection** (extracting a subrecord) and **injection** (inserting a subrecord into a larger record).

Let's look at the actual implementation in `Data.Record.Anon.Simple.hs`:

```haskell
project :: SubRow r r' => Record f r -> Record f r'
project (Record src) = Record $ A.map (\(I i) -> A.index src i) (reifySubRow (Proxy @SubRow))

inject :: SubRow r r' => Record f r' -> Record f r -> Record f r
inject (Record sub) (Record src) = Record $ A.updateMulti src (A.map (\(I i, v) -> (i, v)) (A.zipWith (,) (reifySubRow (Proxy @SubRow)) sub))
```

The key function is `reifySubRow`:

From `Data.Record.Anon.Advanced.hs`:
```haskell
-- | Reifies a 'SubRow' constraint.
reifySubRow :: (KnownFields r', SubRow r r') => Record (A.InRow r) r'
reifySubRow = A.reifySubRow
```

And in `Data.Record.Anon.Plugin.Internal.Runtime.hs` we would find (or the plugin provides):
```haskell
reifySubRow :: forall k r r' proxy. SubRow r r' => proxy r' -> DictSubRow k r r'
reifySubRow _ = undefined  -- Actually provided by plugin evidence
```

What `reifySubRow` does is take the evidence (the `[Int]` indices) and convert it into a record-like structure where each field holds an `Int` index (typically wrapped in a newtype like `I`).

So for our example:
- `reifySubRow (Proxy @SubRow)` produces something like: `{ name = I 0, active = I 2 }` (in target order)

Then:
- `project` maps over this, getting each index `i` and extracting `A.index src i` from the source record
- This gives us `[ A.index src 0, A.index src 2 ]` = `[ name value, active value ]` which is correctly ordered for the target record

## Concrete Example: Projecting a Full Record

Suppose we have:
```haskell
full :: Record Identity FullRecord
full = Record $ A.fromList [ Identity "Alice", Identity 30, Identity True, Identity 95.5 ]
```

We want to project it to a `SubRecord`:

```haskell
sub :: Record Identity SubRecord
sub = project full
```

How this works at runtime:
1. The `SubRow FullRecord SubRecord` constraint is solved by the plugin, producing evidence `[0, 2]`
2. `reifySubRow (Proxy @SubRow)` converts this evidence to a structure: `{ name = I 0, active = I 2 }`
3. `project` maps over this structure:
   - For `name`: gets index 0, extracts `A.index full 0` → `Identity "Alice"`
   - For `active`: gets index 2, extracts `A.index full 2` → `Identity True`
4. Constructs target record: `Record $ A.fromList [ Identity "Alice", Identity True ]`

Result: `[ "Alice", True ]` - correctly projected subrecord.

## Why You Need This (Beyond Manual Field Listing)

You could manually write projection by listing fields:
```haskell
projectManual :: Record f r -> Record f r'
projectManual (Record src) = Record $ A.fromList [
    A.index src (fieldIndex @"_name"),
    A.index src (fieldIndex @ "_active")
  ]
```

But this requires:
- Knowing the field names at compile time (you do)
- Having a way to get the index for each field name (you might, via `KnownFields` or similar)
- **Manually listing every field** - if you add/remove fields from the subrecord, you must update this function
- Being careful to maintain target order

The plugin approach:
- Requires only the `SubRow r r'` constraint (one constraint, no field listing)
- Automatically computes the correct indices for whatever `r'` is
- Works for any subrecord size - no need to change code when `r'` changes
- Guarantees correctness (if the constraint solves, the indices are correct)

## How the Plugin Computes the Indices

From `src/Data/Record/Anon/Internal/Plugin/TC/Constraints/SubRow.hs`:

```haskell
solveSubRow rn orig (L loc proj@CSubRow{..}) =
  case ( ParsedRow.allKnown subrowParsedLHS
       , ParsedRow.allKnown subrowParsedRHS
       ) of
    (Just lhs, Just rhs) ->
      case rhs `KnownRow.isSubRowOf` lhs of
        Right inBoth -> do
          eqs <- forM inBoth $ \(Target r, Source l) -> newWanted loc $
                   mkEqPredRole Nominal (knownRowFieldInfo l) (knownFieldInfo r)
          ev  <- evidenceSubRow rn proj inBoth
          return (Just (ev, orig), map mkNonCanonical eqs)
        Left _err -> return (Nothing, [])
    _otherwise -> return (Nothing, [])
```

And the evidence function:
```haskell
evidenceSubRow :: ResolvedNames -> CSubRow -> [(Target (KnownField Type), Source (KnownRowField Type))] -> TcPluginM 'Solve EvTerm
evidenceSubRow ResolvedNames{..} CSubRow{..} fields = do
  return $ EvExpr $
    evDataConApp
      (classDataCon clsSubRow)
      typeArgsEvidence
      [ mkCoreApps (Var idEvidenceSubRow) $ concat [
            map Type typeArgsEvidence
          , [ mkListExpr intTy
                (map (mkUncheckedIntExpr . fromIntegral) indices) ]
          ]
        ]
  where
    -- ...
    indices :: [Int]
    indices = map (knownRowFieldIndex . getSource . snd) fields
```

What happens:
1. The plugin parses the `SubRow r r'` constraint into `CSubRow` containing the parsed LHS (`r`) and RHS (`r'`) as `Fields` (lists of known fields)
2. It checks that every field in `r'` (parsedRHS) exists in `r` (parsedLHS) with the same type - this is `KnownRow.isSubRowOf`
3. For each matching field pair (where `Target r` is the field in `r'` and `Source l` is the field in `r`), it:
   - Generates an equality constraint to ensure the types match (for the solver)
   - Records the pair `(Target r, Source l)` in `inBoth`
4. To compute the indices: for each `(Target _, Source l)` in `inBoth`, it gets `knownRowFieldIndex l` - the index of that source field in the original row `r`
5. The list of these indices (in the order they were processed, which is target row order) becomes the evidence

Thus, the evidence `[i0, i1, ..., in]` means: target field 0 comes from source index i0, target field 1 from source index i1, etc.

## How to Use This in Your Code

With large-anon, you get:
- `project :: SubRow r r' => Record f r -> Record f r'`
- `inject :: SubRow r r' => Record f r' -> Record f r -> Record f r`
- `lens :: SubRow r r' => Record r -> (Record r', Record r' -> Record r)`

All implemented using the projection indices computed by the plugin.

If you want similar functionality in your polytropos codebase, consider:

1. **Define a `SubRow` class** (like large-anon's) that represents "`r'` is a subrecord of `r`"
2. **Write a plugin constraint solver for `SubRow`** that:
   - Recognizes `SubRow r r'` constraints
   - Verifies that `r'` is a subrecord of `r` (every field in `r'` exists in `r` with same type)
   - For each field in `r'` (in target order), finds its index in `r`
   - Collects these indices into a list (target order)
   - Constructs evidence using something like `evidenceSubRow :: [Int] -> DictSubRow r r'`
3. **Provide a `reifySubRow` function** (or equivalent) that takes the `SubRow r r'` evidence and converts it to a usable structure where each field holds its source index
4. **Implement projection/injection/lens operations** using `reifySubRow` to extract the indices and perform the field extraction/insertion

## Key Insight

The subtlety you noticed is correct: **subrecord conversion is not automatic** because records are ordered data structures. Simply having the right fields is not enough - you need to know **where each field lives in the source record** to extract them in the correct target order.

The large-anon plugin transforms the `SubRow r r'` constraint from a **compile-time subrecord check** into a **runtime-projection mechanism** by computing and providing the necessary field index mapping as evidence. This enables generic record operations (projection, injection, lenses) that work for any subrecord pair with only a single constraint and no manual field listing.

This is analogous to the other plugin features we discussed: it takes a compile-time relationship (suborderness) and makes its computational content (the projection indices) available as usable runtime values with zero manual boilerplate.