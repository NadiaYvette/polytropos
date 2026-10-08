# Comparison: large-anon GHC Plugin Capabilities

This document explains what the `large-anon` GHC plugin does beyond basic constraint solving areas (Constraint solving, FieldIndex solving, ConstructorIndex solving, RowEq solving, RowShow solving, RowEqSum solving, RowShowSum solving, HasField solving, row walking, and dictionary resolution).

## Additional Functionality in large-anon Plugin

### 1. Type-Level Metadata Computation (Rewriter)
The plugin doesn't just solve constraints—it **computes and rewrites type families** to produce metadata that can be used in further computation:
- **FieldTypes**: Maps `(f :: k -> Type)` and `(r :: Row k)` to `[(Symbol, Type)]` where each field type is wrapped in the functor `f`
  - Example: `FieldTypes Maybe ["a" := Int, "b" := Bool]` → `[ '("a", Maybe Int), '("b", Maybe Bool) ]`
- **SimpleFieldTypes**: Similar but without functor wrapper (for the simple API)
  - Example: `SimpleFieldTypes ["a" := Int, "b" := Bool]` → `[ '("a", Int), '("b", Bool) ]`

**Why rewriting is necessary**: GHC does not automatically evaluate open type families during type checking (for safety/termination reasons). Without plugin intervention, `FieldTypes Maybe ["a" := Int, "b" := Bool]` remains a stuck, opaque type family application that cannot be inspected, decomposed, or used where GHC needs concrete type structure (e.g., as argument to another type family, in pattern matching, etc.).

The rewriter (`Data.Record.Anon.Internal.Plugin.TC.Rewriter`) matches applications of `tyConFieldTypes` and `tyConSimpleFieldTypes`, computes the result when arguments are known concrete types, and rewrites the type to replace the stuck type family application with its computed result.

### 2. Compile-Time Hash Known Instances
The plugin provides **compile-time computation of symbol hashes** to make symbols usable as efficient runtime keys with zero overhead:
- **Class**: `class KnownHash (s :: Symbol) where hashVal :: forall proxy. proxy s -> Int`
- **Evidence**: `evidenceKnownHash :: forall (s :: Symbol). Int -> DictKnownHash s`
- **Plugin behavior**: When solving `KnownHash "fieldname"`, computes the hash of `"fieldname"` at compile time and returns `evidenceKnownHash <computed_hash>`

**Why compile-time hashing is necessary**: Haskell's type-level strings (`Symbol`) exist only at compile time. At runtime, you cannot inspect, compare, or convert them to strings without constraints like `KnownSymbol`. If you want to use a field name as a key in a runtime data structure (e.g., for O(1) field lookup in a record), you need to convert it to a hashable integer. Computing this hash at runtime for every field access would be wasteful, especially in hot loops.

**How the plugin helps**: Rather than requiring users to manually compute and provide hashes, the plugin's constraint solver automatically:
1. Recognizes `KnownHash <literal symbol>` constraints during type checking
2. Computes the hash of the literal string using `Data.Hashable.hash` (or similar)
3. Produces evidence containing that hash as a compile-time constant

**What this enables**: With `KnownHash`, you can write code like:
```haskell
getFieldHash :: KnownHash s => proxy s -> Int
getFieldHash _ = hashVal (Proxy :: Proxy s)
```
Which, after plugin solving, becomes a constant-time operation returning the precomputed hash—no runtime string hashing needed. This allows:
- O(1) field name → array index mapping for efficient record representation
- Hash-consing/interning of field names with zero runtime cost
- Compile-time optimizations (constant folding, branch prediction on hash values)
- Efficient field lookup in records without runtime string comparisons or `KnownSymbol` constraints everywhere

The key insight is that compile-time hashing transforms an opaque, compile-time-only entity (`Symbol`) into a usable runtime value (its hash) with **zero runtime cost**, enabling efficient hash-based operations while preserving type-level safety.

### 3. AllFields Constraint Solving with Dictionary Generation
Beyond basic constraint solving, the plugin **generates actual runtime dictionaries** for `AllFields` constraints, enabling generic operations over all fields:
- Solves `AllFields r c` constraints (requiring `c x` for every `(n := x)` in `r`)
- Produces evidence: `evidenceAllFields :: [DictAny c] -> DictAllFields k r c`
- Where `DictAny c` wraps dictionaries existentially: `data DictAny c where DictAny :: c Any => DictAny c`
- Includes overlapping instances for common constraints like `Show`, `Eq`, `Ord` that automatically generate dictionaries when `KnownFields r` is available.

**Why this goes beyond basic constraint solving**: Basic solving would only verify that `AllFields r c` holds (giving a compile-time yes/no), but the plugin actually constructs and packages up all the necessary runtime dictionaries so you can use them generically in your code.

This is handled by the solver in `Data.Record.Anon.Internal.Plugin.TC.Constraints.AllFields` which:
1. For each field type `x` in `r`, solves the wanted constraint `c x` to get the dictionary
2. Wraps each dictionary in `DictAny c` (existential to hide the specific type)
3. Collects all `DictAny c` values into a `SmallArray`
4. Constructs the evidence using `evidenceAllFields`

What this enables: With `AllFields r c`, you can write generic functions that operate on every field of a record (like showing all fields, converting all fields to JSON, etc.) by:
1. Using `reifyAllFields (Proxy @c)` to get the evidence as a structure of `DictAny c` values
2. Mapping over that structure, extracting each `DictAny c`
3. Using the underlying dictionary to perform the operation (`show`, `toJSON`, etc.)

This eliminates boilerplate like needing `(Show a, Show b, Show c, ...)` constraints and lets you write one function that works for any record size.

### 4. Subrecord Projection Indices
The plugin solves `SubRow` constraints to provide **projection indices** for record operations, transforming a compile-time subrecord check into usable runtime field mappings:
- Solves `SubRow r r'` constraints (indicating `r'` is a subrecord of `r`)
- Produces evidence: `evidenceSubRow :: [Int] -> DictSubRow k r r'`
- Where the `[Int]` lists indices in the source record `r` corresponding to each field in the target record `r'` (in target order)
- This enables operations like `project` and lens generation by providing the necessary field mapping at compile time.

**Why this goes beyond basic constraint solving**: Basic solving would only verify that `SubRow r r'` holds (giving a compile-time yes/no), but the plugin actually computes and packages up the **projection indices** - the mapping from target field positions to source field positions - so you can use them generically in your code.

This is handled by the solver in `Data.Record.Anon.Internal.Plugin.TC.Constraints.SubRow` which:
1. Parses the `SubRow r r'` constraint into source and target field lists
2. Verifies that every field in the target `r'` exists in the source `r` with the same type (using `KnownRow.isSubRowOf`)
3. For each field in the target (in target order), finds its index in the source record
4. Collects these indices into a list (target field order)
5. Constructs the evidence using `evidenceSubRow` with this index list

What this enables: With `SubRow r r'`, you can write generic record operations that work for any subrecord pair by:
1. Using `reifySubRow (Proxy @SubRow)` to get the evidence as a structure of indices (one per target field)
2. Extracting each index and using it to get/set the corresponding field in the source record
3. Building the target record from these extracted values (for projection) or updating the source record (for injection)

This eliminates boilerplate like manually listing field names and computing their indices, and lets you write one projection/injection function that works for any record size.

### 5. Source-Level Syntactic Sugar (Source Plugin)
The plugin includes a **source plugin** that transforms record construction syntax before type checking, providing ergonomic record construction:
- Transforms expressions like `ANON { field1 = expr1, field2 = expr2 }` and `ANON_F { field1 = expr1, field2 = expr2 }` (using OverloadedLabels)
- Generates calls to runtime functions: `largeAnon_empty`, `largeAnon_insert`, `largeAnon_letRecordT`, `largeAnon_letInsertAs`, `largeAnon_applyPending`
- Supports both standard insertion style and experimental typelet-based construction
- This is entirely separate from the type checker plugin—it works on the parsed Haskell source before type checking.

**Why this is more than just syntactic sugar**: While it could be viewed as simple desugaring, the source plugin enables:
1. **More concise record construction** without manual nesting of insertions
2. **Integration with compile-time optimizations** like the typelet package for O(1) construction
3. **Separation of concerns** - the source plugin handles syntax transformation while the type checker plugin handles constraint solving and metadata computation
4. **User-facing ergonomics** that make the library more pleasant to use while still generating efficient code

This is handled by the source plugin in `Data.Record.Anon.Internal.Plugin.Source` which:
1. Scans the parsed module for record constructions with constructors `ANON` or `ANON_F`
2. For each match, extracts the field names and expressions
3. Transforms them into a series of runtime insertion calls (starting from empty record)
4. Optionally integrates with typelet for truly O(1) construction when enabled
5. Optionally omits the final applyPending call based on plugin options

What this enables: Instead of writing:
```haskell
manual = insert @"c" expr3 $ insert @"b" expr2 $ insert @"a" expr1 $ empty
```
Users can simply write:
```haskell
sugared = ANON { a = expr1, b = expr2, c = expr3 }
```
Which gets transformed into the efficient insertion calls, benefiting from all the other plugin features (hashing for efficient labels, etc.) while providing much more readable construction syntax.

### 6. Runtime Code Generation Support
The plugin relies on the `Runtime.hs` module which provides:
- Low-level representations used in generated code (Pair, Row, various dictionary types)
- Instances that bridge plugin-generated constraints to actual class instances (often marked `OVERLAPPING`)
- Utility functions like `noInlineUnsafeCo` for safe coercions in generated code
- The convention that anything the plugin needs to reference internally is defined here to avoid brittle cross-package lookups

## What Your polytropos Codebase Might Consider Adding

If you want to make life more convenient for callers of your library similar to large-anon, consider implementing:

1. **Type-level metadata computation** (like FieldTypes/SimpleFieldTypes) via a type checker plugin rewriter
2. **Compile-time known instances** for useful type-level computations (hashes, lengths, etc.)
3. **Automatic dictionary generation** for constraints that need to be satisfied across all fields (like your AllFields analogue)
4. **Projection/sublearning support** that computes field mappings at compile time
5. **Source plugin syntactic sugar** for more ergonomic record construction (if your library uses overloaded labels/record syntax)
6. **Clear separation** between constraint solving and metadata rewriting phases

The key insight is that large-anon's plugin doesn't just solve constraints—it actively **computes and generates useful artifacts** (metadata, evidence, indices, source transformations) that make the resulting types much more usable at both compile time and runtime.