# Explanation: Source-level Syntactic Sugar Source Plugin in large-anon

You asked for clarification on point 5: "Source-level Syntactic Sugar Source Plug-In" and mentioned having no idea such things existed. Let me explain what GHC source plugins are, what the large-anon source plugin does, and how it transforms record construction syntax.

## What Is a GHC Source Plugin?

A **source plugin** in GHC is a mechanism that allows you to transform Haskell source code **after parsing but before type checking**. Unlike type checker plugins (which work during type checking to solve constraints), source plugins operate on the `HsParsedModule` - the parsed abstract syntax tree (AST) of your Haskell code.

The large-anon package includes **two plugins**:
1. **Type checker plugin** (discussed in points 1-4): Solves constraints and computes type-level metadata during type checking
2. **Source plugin** (point 5): Transforms record construction syntax before type checking

This separation is important: the source plugin works on raw parsed Haskell, while the type checker plugin works on the typed AST during constraint solving.

## What the large-anon Source Plugin Actually Does

The source plugin (in `Data.Record.Anon.Internal.Plugin.Source`) transforms specific record construction expressions. Specifically, it looks for expressions of the form:

```haskell
ANON { field1 = expr1, field2 = expr2, ... }
ANON_F { field1 = expr1, field2 = expr2, ... }
```

And transforms them into calls to runtime functions that build the record step by step.

### The Transformation Process

From `src/Data/Record/Anon/Internal/Plugin/Source.hs`:

1. **Parsing options**: The plugin accepts options like `debug`, `typelet`, and `noapply` passed via `-fplugin-opt=Data.Record.Anon.Plugin:option`
2. **Finding target expressions**: It scans the parsed module for record constructions where:
   - The constructor is an unqualified identifier (`Unqual nm'`)
   - That identifier matches a known mode (`ANON` or `ANON_F`) via `parseMode`
   - It's a record construction (`RecordCon`) with fields (`HsRecFields`)
   - There's no dot-dot (`rec_dotdot` is `Nothing`) - meaning no `..` syntax
3. **Transforming the expression**: For each matching record construction, it calls `anonRec` which:
   - Gets the large-anon runtime names (`largeAnon_empty`, `largeAnon_insert`, etc.)
   - Transforms the fields into a series of insertions
   - Optionally wraps with typelet integration or applyPending calls

### What the Transformation Produces

Let's look at what happens to different forms:

#### Simple ANON Records (Without Typelet)

For `ANON { field1 = expr1, field2 = expr2 }` with no typelet option:
- Transforms to: `largeAnon_applyPending (largeAnon_insert label1 expr1 (largeAnon_insert label2 expr2 largeAnon_empty))`
- Or without `noapply`: `largeAnon_insert label1 expr1 (largeAnon_insert label2 expr2 largeAnon_empty)`

This means:
1. Start with an empty record (`largeAnon_empty`)
2. Insert field2 with value expr2
3. Insert field1 with value expr1 (note: fields processed in reverse order due to consing)
4. Optionally apply pending changes

#### Advanced ANON_F Records (Without Typelet)

For `ANON_F { field1 = expr1, field2 = expr2 }` (advanced mode):
- Similar transformation but uses different runtime representation
- Still builds up via insertions into an empty record

#### With Typelet Integration

When the `typelet` option is enabled, the plugin integrates with the [`typelet`](https://hackage.haskell.org/package/typelet) package to enable truly O(1) record construction by avoiding intermediate record allocations.

The transformation becomes more complex, using:
- `largeAnon_letRecordT` to start a record construction context
- `largeAnon_letInsertAs` for each field insertion
- `typelet_castEqual` to finalize and cast the result

## Concrete Examples from the Test Suite

Let's look at actual usage from `test/Test/Sanity/SrcPlugin/WithoutTypelet.hs`:

```haskell
example_simple = ANON {
    a = I True
  , b = I 'a'
  , c = I ()
}
```

This gets transformed (conceptually) to something like:
```haskell
largeAnon_insert (label @"a") (I True)
  $ largeAnon_insert (label @"b") (I 'a')
  $ largeAnon_insert (label @"c") (I ())
  $ largeAnon_empty
```

Another example from the same file showing reordering:
```haskell
example_simple_reordered = S.project $ ANON {
    b = I 'a'
  , a = I True
  , c = I ()
}
```

Even though the fields are written in order b,a,c, the resulting record will have fields in the order they were inserted (which depends on the implementation, but the key point is that the source plugin handles the transformation regardless of field order).

## Why This Is Useful: Benefits Over Manual Construction

Without the source plugin, to construct a record you would need to write:

```haskell
manualConstruction = S.insert @"c" (I ())
                   $ S.insert @"b" (I 'a')
                   $ S.insert @"a" (I True)
                   $ S.empty
```

Or using the advanced API:
```haskell
manualConstruction = A.insert @"c" (I ())
                   $ A.insert @"b" (I 'a')
                   $ A.insert @"a" (I True)
                   $ A.empty
```

The source plugin provides several advantages:

1. **More concise syntax**: `ANON { a = ..., b = ..., c = ... }` vs nested inserts
2. **Field order independence**: You can write fields in any order - the plugin handles the transformation correctly (though note: the actual field order in the resulting record may depend on implementation details)
3. **Less boilerplate**: No need to repeatedly write `insert` and `$`
4. **Consistent with label syntax**: Uses the same `OverloadedLabels` syntax (`#label`) that's used elsewhere in the library for field access
5. **Integration point**: Provides a hook for optimizations like typelet integration

## How It Relates to the Rest of the Plugin System

It's important to understand that the source plugin is **entirely separate** from the type checker plugin:

| Aspect | Source Plugin | Type Checker Plugin |
|--------|---------------|---------------------|
| **When it runs** | After parsing, before type checking | During type checking |
| **What it works on** | `HsParsedModule` (parsed Haskell AST) | In-flight type checking constraints and types |
| **What it does** | Transforms specific syntactic forms | Solves constraints, rewrites type families |
| **Example transformation** | `ANON {a=1,b=True}` → insert calls | Solving `KnownHash "a"` → returns hash evidence |
| **Dependencies** | Works on raw Haskell, no type info needed | Requires type checker API, works with typed terms |

This separation allows the source plugin to focus purely on syntactic transformation without worrying about types, while the type checker plugin can do its work on the transformed code.

## Runtime Functions Used

The source plugin generates calls to functions defined in `Data.Record.Anon.Plugin.Internal.Runtime.hs`:

- `largeAnon_empty :: Record f '[]` - creates an empty record
- `largeAnon_insert :: KnownHash s => Label s -> f a -> Record f r -> Record f (s := a ': r)` - inserts a field
- `largeAnon_letRecordT` - for typelet integration (starts construction context)
- `largeAnon_letInsertAs` - for typelet integration (inserts field in context)
- `largeAnon_applyPending` - applies any pending changes (can be omitted with `noapply`)

Note that these functions rely on the `KnownHash` constraint (point 2 we discussed earlier) - the plugin uses compile-time hashing of field names to make insertion efficient.

## Practical Effects on Code Generation

When you write:
```haskell
myRecord = ANON { name = "John", age = 30 }
```

After the source plugin runs, the compiler sees something like:
```haskell
myRecord = largeAnon_insert (label @"name") "John"
         $ largeAnon_insert (label @"age") 30
         $ largeAnon_empty
```

Then during type checking:
1. The type checker plugin solves `KnownHash "name"` and `KnownHash "age"` to get the hash values
2. Those hash values are used as runtime arguments to `largeAnon_insert`
3. The record is built up through these insertions

This means the source plugin enables a **nice user-facing syntax** while still generating code that leverages all the other plugin features (hashing, constraint solving, etc.).

## How to Use This in Your polytropos Codebase

If you want similar syntactic sugar for your record library, consider:

1. **Create a source plugin** (module implementing `sourcePlugin :: [String] -> HsParsedModule -> Hsc HsParsedModule`)
2. **Define your target syntax** - e.g., look for record constructions with specific constructors like `MYREC` or `MYREC_F`
3. **Implement the transformation**:
   - Parse plugin options from the string list
   - Traverse the parsed module (using `Data.Generics.everywhereM` or similar)
   - For each matching record construction:
     - Extract the field names and expressions
     - Generate calls to your runtime construction functions
     - Return the transformed expression
4. **Define your runtime construction functions** (like `empty`, `insert`, etc.)
5. **Export the plugin** in your package's `.cabal` file under `plugins:` or make it available via `-fplugin=Your.Plugin.Module`

## Key Insights

- GHC source plugins let you transform Haskell syntax **before** type checking - a powerful metaprogramming facility
- The large-anon source plugin provides **convenient record construction syntax** (`ANON { ... }`) that transforms into efficient runtime insertion calls
- This syntax is **separate from** the type checker plugin features we discussed earlier (hashing, constraint solving, type rewriting)
- The transformation enables **more ergonomic code** while still benefiting from all the other plugin optimizations
- You can implement similar syntactic sugar for your own libraries by following the same pattern: define a source plugin that transforms your preferred syntax into calls to your runtime API

The source plugin is essentially a **user experience enhancement** - it lets library users write more concise, readable record construction code while the generated code remains efficient and leverages all the underlying plugin machinery.