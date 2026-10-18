<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# Interactive Tutorial: Practical Row Polymorphism with Polytropos

**Status:** LIVING TUTORIAL · v1.1 · 2026-10-11  
**Audience:** Haskell Programmers, Compiler Writers, AI Coding Assistants  
**Prerequisites:** Basic Haskell syntax (types, functions, pattern matching). No prior experience with type-level programming or compiler plugins required.  
**Related Guides:** [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) · [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) · [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)

---

## Quick Start: Run the Worked Examples Live

Every concept in this tutorial is backed by live, compilable code in this repository. You can run the executable tutorial pass right now from your terminal:

```bash
# Build and run the Nanopass compiler pass tutorial (Addendum A)
cabal run example-nanopass

# Build and run the Resilient Parsing tutorial (Addendum B)
cabal run example-resilient

# Build and run the Relational Database Models & Persistent Schemas tutorial (Addendum C)
cabal run example-database

# Build and run the Extensible Algebraic Effects & Ropes tutorial (Addendum D)
cabal run example-effects

# Build and run the Federated Context & Memory MCP Server Capstone (Addendum E)
cabal run example-mcp-server

# Or explore the types and combinators interactively in GHCi
cabal repl example-resilient
```

The executable companion source code is located under [`examples/`](../examples/):
- [`examples/nanopass/src/Main.hs`](../examples/nanopass/src/Main.hs) (Addendum A)
- [`examples/resilient/src/Main.hs`](../examples/resilient/src/Main.hs) (Addendum B)
- [`examples/database/src/Main.hs`](../examples/database/src/Main.hs) (Addendum C)
- [`examples/effects/src/Main.hs`](../examples/effects/src/Main.hs) (Addendum D)
- [`examples/mcp-server/src/Main.hs`](../examples/mcp-server/src/Main.hs) (Addendum E)

### Interactive REPL Exploration (`cabal repl`, `ghci`, `stack repl`)

Because `polytropos` uses a compiler plugin (`-fplugin=Polytropos.Plugin`) to solve row constraints (`FieldIndex`, `ConstructorIndex`, `SubRow`, `SubSum`) and desugar syntactic sugar (`REC`, `VAR`, `REC_UPD`), running an interactive REPL requires activating the plugin in your session.

#### 1. Inside the Repository with `cabal repl` (Easiest)
Any test or example target in this repository already has the plugin enabled in its `.cabal` file:
```bash
# Start GHCi with polytropos and example components preloaded:
cabal repl example-resilient
# or test suites:
cabal repl polytropos-plugin-smoke
```
Once inside the REPL, type declarations, `REC`, `r.field` dot syntax, and unparenthesized `REC_UPD` work immediately!

#### 2. Standalone `ghci` (Ad-Hoc Exploration)
If launching GHCi directly outside a configured project:
```bash
# Launch GHCi with the plugin loaded from the current environment:
ghci -package-env . -fplugin=Polytropos.Plugin
```
Or start a bare `ghci` and activate the plugin and extensions dynamically at the prompt:
```haskell
ghci> :set -package polytropos-core -package polytropos-plugin
ghci> :set -fplugin=Polytropos.Plugin
ghci> :set -XDataKinds -XTypeOperators -XOverloadedRecordDot -XTypeApplications
ghci> import Polytropos
```

#### 3. In Downstream Projects with `cabal` or `stack`
- **In `cabal` projects:** Add the plugin to your component's stanza in `.cabal`:
  ```cabal
  build-depends: polytropos-core, polytropos-plugin
  ghc-options:   -fplugin=Polytropos.Plugin
  ```
  Then simply run `cabal repl`.
- **In `stack` projects:** Add `polytropos-core` and `polytropos-plugin` to `extra-deps` / `package.yaml`, and start the REPL with:
  ```bash
  stack repl --ghci-options="-fplugin=Polytropos.Plugin"
  ```

#### 4. Live REPL Walkthrough

> [!IMPORTANT] GHC Interactive Prompt vs. Loaded Modules
> In GHC's plugin architecture, **source plugins** (`parsedResultAction` lowering `REC`, `VAR`, `REC_UPD`) only run when compiling **modules** (`.hs` files, `:load`, `cabal repl`). Interactive statements typed directly at the `ghci>` prompt bypass the source plugin.
> - **At the `ghci>` prompt:** Use the core combinators with `#labels` (`insertField`, `recordField`, `setField`, `injectVariant`).
> - **In loaded modules (`:load Scratch.hs`):** Full syntactic sugar (`REC { ... }`, `VAR { ... }`, `REC_UPD`) is active!

**Interactive Prompt Exploration:**
```haskell
ghci> :set -XDataKinds -XTypeApplications -XOverloadedLabels -XOverloadedRecordDot
ghci> import Polytropos

-- 1. Construct an open record at the prompt:
ghci> u1 = insertField #name "Alice" (insertField #age (30 :: Int) (insertField #active True emptyRecord))
ghci> recordField #name u1
"Alice"
ghci> recordField #age u1
30

-- 2. Update a field functionally:
ghci> u2 = setField #age 31 u1
ghci> recordField #age u2
31

-- 3. Construct an open variant:
ghci> v1 = injectVariant #ok (insertField #code (200 :: Int) emptyRecord)
ghci> :type v1
v1 :: Variant '[ "ok" ':= '[ "code" ':= Int ] ]
```

**Using `REC` and `VAR` interactively via a scratch file (`Scratch.hs`):**
```haskell
-- In Scratch.hs:
{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
module Scratch where
import Polytropos

u1 = REC { name = "Alice", age = 30 :: Int, active = True }
u2 = REC_UPD u1 { age = 31 }
```
```haskell
ghci> :load Scratch.hs
[1 of 1] Compiling Scratch ( Scratch.hs, interpreted )
Ok, one module loaded.
ghci> u1.name
"Alice"
ghci> u2.age
31
```

### Standard GHC Extensions & Setup

To use `polytropos`, your modules typically require the typechecker plugin and a standard set of GHC language extensions:

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE NamedFieldPuns #-}      -- For { field } pattern matching and punning
{-# LANGUAGE ViewPatterns #-}        -- For variant pattern matching
{-# LANGUAGE TypeApplications #-}    -- For Field @"name" type applications
{-# LANGUAGE ScopedTypeVariables #-} -- For explicit type signatures in handlers
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

import Polytropos
```

---

# Part I: The Foundational 5-Lesson Plan

## Conceptual Primer: What Are "Row-Polymorphic Open ADTs"?

If you are new to advanced type systems, the phrase **"row-polymorphic open algebraic data type"** may sound like academic jargon. In reality, every part of that phrase directly addresses an everyday frustration that developers fight against constantly.

Let's break the concept down into four clear ideas:

### 1. "ADT" (Algebraic Data Type): The Two Shapes of Data
Every programmer uses ADTs, whether they know the name or not. In any language, data is modeled using two basic structures:
- **Product Types ("AND" data):** Structs, records, or objects. A `User` has a `name` **AND** an `age` **AND** an `email`.
- **Sum Types ("OR" data):** Enums, variants, or tagged unions. A `PaymentStatus` is `Pending` **OR** `Approved` **OR** `Declined`.

### 2. "Closed" vs. "Open": Breaking Out of the Rigid Box
In standard Haskell, Rust, or Java, data types are **closed** and **nominal** (locked to a specific name declared in source code):
- **A closed product** (`data Person = Person { name :: String, age :: Int }`): You cannot attach an extra field (like `email :: String`) without creating a brand-new type (`data PersonWithEmail = ...`) and writing boilerplate copying the existing fields.
- **A closed sum** (`data Expr = Lit Int | Add Expr Expr`): You cannot add a constructor (like `Mul Expr Expr` or `ErrorHole Text`) without modifying the original definition and breaking every pattern match across the codebase.

**Open ADTs** eliminate these rigid boundaries. An open record or variant is defined structurally by its schema on the fly, allowing fields and constructors to be added, combined, or removed without defining throwaway intermediate wrapper types.

### 3. "Row Polymorphism": Flexible Schemas with Exact Static Guarantees
- **What is a "Row"?** Think of a database table or a spreadsheet row: a list of named columns and their types, e.g. `[ "name" := String, "age" := Int ]`.
- **What is "Row Polymorphism"?** It is the ability to write functions that work over **any** record or variant that contains a given set of fields, while statically tracking the rest of the schema (`r`):
  ```haskell
  -- "I accept ANY record that has a 'name' field, plus any remaining fields 'r'."
  -- The compiler preserves 'r' without losing its types!
  greet :: Record ("name" := String ': r) -> String
  greet user = "Hello, " ++ user.name
  ```

#### How Does This Differ from Object-Oriented Subtyping?
- In OOP (Java or TypeScript interfaces), if `Admin` extends `User`, passing an `Admin` to a function expecting `User` often causes **type erasure** or **object slicing**: the compiler forgets that the object had `permissions` or `auditLog`, or requires unsafe runtime downcasts.
- In **row polymorphism**, the compiler remembers the exact type of the remaining fields (`r`). If you pass a 10-field record into a function that updates one field, you get back the exact same 10-field record with its full type safety intact—no runtime checks, no downcasts, and zero data loss.

#### Helpful Analogies:
- **TypeScript:** Similar to `{ name: string, ...rest }` or string union types (`"Pending" | "Approved" | "Rejected"`), but with **100% sound runtime guarantees** (no `undefined is not a function` and no prototype surprises).
- **SQL / Relational Databases:** A query like `SELECT name FROM users` works whether the table has 2 columns or 50 columns. Row polymorphism brings this query-like structural flexibility directly into the Haskell type system.
- **OCaml:** Directly inspired by OCaml's polymorphic variants (`` `Tag of a ``) and object rows, allowing modular, extensible pattern matching across independent compiler passes.

### 4. The Polytropos Breakthrough: Why Hasn't Haskell Always Done This?
Historically, row polymorphism in Haskell suffered from two severe flaws:
1. **Compile-Time Explosion:** Older libraries represented rows as nested type lists (`a :*: b :*: c`). At 20+ fields, GHC's type checker would grind to a halt, suffering quadratic or cubic compile times ($O(N^{2.8})$).
2. **Runtime Memory Bloat:** Extensible variants were often implemented as nested `Either` trees, creating chains of pointer hops in memory.

**How Polytropos Solves This:**
- **One Unified Layout (`Rep`):** Under the hood, whether a data structure is a 20-field record or a 10-constructor variant, `polytropos` stores it as an unboxed **tag** plus a **flat array of pointers** (`SmallArray`):
  ```haskell
  data Rep (f :: Type -> Type) a = Rep
    {-# UNPACK #-} !Word
    !(SmallArray (f Any))

  repTag  :: Rep f a -> Word
  repVals :: Rep f a -> SmallArray (f Any)
  ```
- **Compile-Time Plugin:** The `Polytropos.Plugin` typechecker plugin calculates field offsets and constructor tags at compile time into **literal numbers** ($\mathcal{O}(1)$ array index lookups).
- **Result:** You get the fluid, structural freedom of TypeScript or OCaml with the execution speed and compact memory footprint of C-like flat structs.

---

## Lesson 1: Constructing Records

A **record** is an open product type: it holds a value for every named field in a row.

### 1.1 Type-Level Row Vocabulary
In `polytropos`, a record's type carries its field names and types as a type-level list of `'Pair Symbol Type`:
```haskell
type UserRow = '[ "name" := String, "age" := Int, "active" := Bool ]
type User = Record UserRow
```

### 1.2 Core Construction Primitives
At the lowest level, you build records from `emptyRecord` by chaining `insertField`:
```haskell
import Polytropos

user :: User
user = insertField (Field @"name") "Alice"
     $ insertField (Field @"age") (30 :: Int)
     $ insertField (Field @"active") True
     $ emptyRecord
```

### 1.3 Ergonomic Syntax (`REC` & Field Punning)
With the `Polytropos.Plugin` enabled (`{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}`), you don't need manual `insertField` chains. You write natural record syntax:
```haskell
-- Standard record construction:
user :: User
user = REC { name = "Alice", age = 30 :: Int, active = True }

-- Field punning:
let name = "Bob"
    age = 25 :: Int
    active = False
in REC { name, age, active }
```

### 1.4 Higher-Kinded Data (HKD) Records (`REC_F`)
For schemas parameterized by an outer functor `f` (such as `Maybe` for partial updates or `Validation` for forms):
```haskell
type PartialUser = RecordF Maybe '[ "name" := String, "age" := Int ]

partialUser :: PartialUser
partialUser = REC_F { name = Just "Alice", age = Nothing }
```

> [!TIP] Syntactic Ergonomics: Eliding `$` for Record Expressions and `BlockArguments`
> In Haskell grammar, record construction `REC { ... }` and `VAR { ... }` parses as an atomic expression (`aexp`). This means function application does not need infix `$` grouping:
> ```haskell
> -- Clean function application without '$' or extra parentheses:
> encode REC { name = "Alice", age = 30 }
> handleCall VAR { search = REC { query = "polytropos", limit = 10 } }
> ```
> Combining this with `{-# LANGUAGE BlockArguments #-}` allows clean, modern Haskell idioms without `$` before blocks:
> ```haskell
> when (user.age >= 18) do
>   notifyAdmin user
>
> forM users \u -> do
>   processAccount u
> ```

---

## Lesson 2: Accessing and Updating Fields

### 2.1 First-Class Dot Syntax (`OverloadedRecordDot`)
Thanks to the plugin solving GHC's `HasField` constraints into literal integer array indices, you access fields using standard dot syntax:
```haskell
let greeting = "Hello, " ++ user.name
let isAdult  = user.age >= 18
```
This is **not** a dictionary lookup at runtime; GHC emits an $\mathcal{O}(1)$ direct array index (`indexSmallArray vals 0`).

### 2.2 Functional Updates (`setField` & `REC_UPD`)
You can update fields functionally using `setField` or the `REC_UPD` syntax:
```haskell
-- Primitive update:
let olderUser = setField (Field @"age") 31 user

-- Ergonomic unparenthesized record update syntax:
let olderUser = REC_UPD user { age = 31 }

-- Functorial/HKD partial record update:
let updatedPartial = REC_UPD_F partialUser { age = Just 31 }
```

### 2.3 Update Performance: Copy-on-Write vs Batch Updates
In `polytropos`, single-field updates use copy-on-write:
- An $N$-field record creates a new `SmallArray` of size $N$ sharing all untouched slot pointers ($\mathcal{O}(N)$ allocation).
- For multiple field updates, **batch updates** (`setFieldsAt` in `Polytropos.Core`) copy the array **once**, avoiding intermediate allocations:
  ```haskell
  import Polytropos.Core (slot, setFieldsAt, unRowRep)

  -- Mutates slots 0 and 1 in a single copy:
  let updatedRep = setFieldsAt [(0, slot "Charlie"), (1, slot (40 :: Int))] (unRowRep user)
  ```
- For high-throughput imperatively-styled builders, transient builders (`thawRep` / `freezeRep`) permit chained in-place mutations in `ST` before freezing into an immutable `Record`.

---

## Lesson 3: Working with Open Variants

A **variant** is an open sum type: it represents one active constructor selected from a row of possibilities, accompanied by that constructor's payload.

### 3.1 Type-Level Variant Vocabulary
A variant row maps constructor names (`Symbol`) to their payload rows:
```haskell
type StatusRow =
  '[ "ok"    := '[ "code" := Int, "body" := String ]
   , "err"   := '[ "reason" := String ]
   , "retry" := '[]
   ]

type Status = Variant StatusRow
```

> [!NOTE] Haskell Grammar Invariant: Field vs Constructor Names
> In Haskell 2010 syntax, record braces `{ label = value }` require `label` to be a variable identifier (`varid`), which must begin with a lowercase letter or underscore. When working with anonymous `VAR { tag = ... }` or `REC { field = ... }`, constructor tags must be lowercase (e.g. `ok`, `err`, `retry`).
>
> If you prefer standard capitalized constructor syntax (e.g. `Success { val = 200 }` or `Failure { msg = "..." }`), use **`deriving OpenVariant`** (§3.4), where GHC's grammar permits top-level nominal data declarations that the plugin maps directly into open variants.

### 3.2 Injecting into a Variant (`VAR`)
```haskell
-- Success with multiple fields:
let s1 :: Status
    s1 = VAR { ok = REC { code = 200 :: Int, body = "OK" } }

-- Error with a single field:
let s2 :: Status
    s2 = VAR { err = REC { reason = "Gateway Timeout" } }

-- Nullary constructor:
let s3 :: Status
    s3 = VAR { retry = REC {} }
```

### 3.3 Pattern Matching & View Patterns
You can pattern-match on variants using view patterns:
```haskell
describeStatus :: Status -> String
describeStatus s = case s of
  VAR { ok = REC { code, body } } -> "200: " ++ body
  VAR { err = REC { reason } }    -> "Error: " ++ reason
  VAR { retry = REC {} }          -> "Please retry"
  _                               -> "Other"
```

### 3.4 Nominal Declaration Sugar (`deriving OpenVariant`)
If you prefer standard Haskell data type declarations with uppercase constructors, you can derive `OpenVariant`:
```haskell
data Response
  = Success { val :: Int }
  | Failure { msg :: String }
  deriving (Show, Eq, OpenVariant)
```
The source plugin translates these declarations into open `Variant` types while letting you write ordinary Haskell constructors!

---

## Lesson 4: Structural Subtyping in Practice

Because rows are structural, `polytropos` allows safe, static conversions between sub-types and super-types without runtime overhead.

### 4.1 Record Projection (`projectRecord` & `SubRow`)
Suppose you have a large record with 20 fields (e.g., a database user profile), but a function only needs 2 fields:
```haskell
type FullProfile = '[ "id" := Int, "name" := String, "email" := String, "role" := String, "created" := String ]
type BasicUser   = '[ "name" := String, "email" := String ]

stripProfile :: Record FullProfile -> Record BasicUser
stripProfile full = projectRecord full
```
The `Polytropos.Plugin` verifies that `BasicUser` is a subset of `FullProfile` and emits literal projection indices `[1, 2]`. Runtime execution is a single pre-allocated array copy!

### 4.2 Variant Widening (`widenVariant` & `SubSum`)
Dually, if you have a function that returns a small set of errors, you can embed it into a broader error variant:
```haskell
type IoErrors  = '[ "notFound" := '[ "path" := FilePath ], "permissionDenied" := '[] ]
type AppErrors = ("networkError" := '[ "code" := Int ]) ': IoErrors

liftIoError :: Variant IoErrors -> Variant AppErrors
liftIoError err = widenVariant err
```
`widenVariant` is **total** and takes $\mathcal{O}(1)$ time: it uses a literal lookup table emitted by the plugin to remap the constructor tag without copying the payload.

### 4.3 Variant Narrowing (`narrowVariant`)
To attempt to downcast a super-variant back into a sub-variant:
```haskell
handleIo :: Variant AppErrors -> Maybe (Variant IoErrors)
handleIo appErr = narrowVariant appErr
```
If the active constructor is a member of `IoErrors`, it returns `Just` with the tag remapped; otherwise it returns `Nothing`.

---

## Lesson 5: Extensible Pipelines & Total Elimination

How do you eliminate a closed variant into a result without writing fragile, un-checked cascading `case` trees?

### 5.1 The Eliminator Problem
In traditional Haskell, pattern matching with `case` trees has two problems:
1. $\mathcal{O}(N)$ sequential branching: matching the 50th constructor checks 49 failed conditions before finding a match.
2. Code reuse: you cannot easily parameterize or share handler records across different passes.

### 5.2 Uniform Elimination (`eliminateUniform`)
`polytropos` provides `eliminateUniform`:
```haskell
eliminateUniform
  :: Record (HandlerRecordRow s a)  -- ^ Record of handler functions
  -> Variant s                      -- ^ The variant to eliminate
  -> a                              -- ^ Uniform result
```

Example:
```haskell
type ExprRow =
  '[ "lit" := '[ "val" := Int ]
   , "neg" := '[ "sub" := Int ]
   , "add" := '[ "left" := Int, "right" := Int ]
   ]

type Expr = Variant ExprRow

evalExpr :: Expr -> Int
evalExpr expr = eliminateUniform handlers expr
  where
    handlers = REC
      { lit = \(REC { val }) -> val
      , neg = \(REC { sub }) -> -sub
      , add = \(REC { left, right }) -> left + right
      }
```

**How it works under the hood:**
- Handlers are stored in a contiguous `Record` array indexed by constructor tag.
- When `eliminateUniform` runs, it reads the variant's integer tag $t$ and immediately indexes slot $t$ in the handler array ($\mathcal{O}(1)$ jump table).
- GHC verifies that **every single constructor** in the row is handled. If you miss one, compilation fails with an informative error.

### 5.3 Data-First Elimination (`matchVariant`)
If you prefer a data-first syntax matching Swift or Rust `match`, use `matchVariant`:
```haskell
result = matchVariant expr REC
  { lit = \(REC { val }) -> val
  , neg = \(REC { sub }) -> -sub
  , add = \(REC { left, right }) -> left + right
  }
```

### 5.4 Heterogeneous & Monadic Eliminators (`eliminate`, `eliminateM`, `eliminateUniformM`)
When different branches compute different result types or require a monad `m`, `polytropos` provides:
- **`eliminateUniformM`**: runs handlers uniformly inside a monad `m` (e.g. `IO` or `Reader`):
  ```haskell
  logAndEval :: Expr -> IO Int
  logAndEval expr = eliminateUniformM handlers expr
    where
      handlers = REC
        { lit = \(REC { val }) -> putStrLn ("Lit " ++ show val) >> pure val
        , neg = \(REC { sub }) -> putStrLn ("Neg " ++ show sub) >> pure (-sub)
        , add = \(REC { left, right }) -> putStrLn "Add" >> pure (left + right)
        }
  ```
- **`eliminate`**: heterogeneous elimination mapping `Variant s` to `Variant resRow` with $\mathcal{O}(1)$ constructor tag preservation:
  ```haskell
  stringifyExpr :: Expr -> Variant '[ "lit" := '[ "val" := String ], "neg" := '[ "sub" := String ] ]
  stringifyExpr expr = eliminate handlers expr
    where
      handlers = REC
        { lit = \(REC { val }) -> REC { val = show val }
        , neg = \(REC { sub }) -> REC { sub = show (-sub) }
        }
  ```
- **`eliminateM`**: full monadic heterogeneous elimination returning `m (Variant resRow)`.

---

# Part II: Addenda — Worked Real-World Case Studies

The 5 foundational lessons above form the building blocks for real-world architectures. The worked case studies below demonstrate how these primitives solve long-standing software engineering challenges.

---

## Addendum A: Worked Case Study — The Nanopass Compiler

The **Nanopass** compiler architecture (pioneered by Sarkar, Waddell, and Dybvig) breaks compiler pipelines into dozens of tiny, single-purpose passes. Each pass rewrites, eliminates, or lowers exactly one language construct.

### A.1 The Nominal Dilemma
In traditional Haskell, writing a compiler pass that removes one construct is notoriously frustrating:
1. **Shared Nominal Type:** If `data Stmt = While ... | Loop ... | Assign ...` is shared across passes, the output type of `desugarWhile` is still `Stmt`. The type system cannot guarantee that subsequent passes won't encounter an unexpected `While`.
2. **Duplicated Nominal Types:** If you declare `data SurfaceStmt` and `data CoreStmt`, you must write 50 lines of boilerplate copying every constructor you *didn't* touch:
   ```haskell
   desugar (SurfaceAssign v x) = CoreAssign v x
   desugar (SurfacePrint m)    = CorePrint m
   desugar (SurfaceIf c t e)   = CoreIf c (desugar t) (desugar e)
   -- 50 lines of identical copy-paste code!
   ```

### A.2 The Polytropos Solution: Row Subtraction
With row polymorphism, we define the target language IR first, and derive the surface language by simply prepending `"while_"`:

```haskell
-- 1. Core Target IR (NO while loops!):
type CoreStmtRow =
  '[ "assign" := '[ "var" := String, "val" := Int ]
   , "print"  := '[ "msg" := String ]
   , "loop"   := '[ "body" := [CoreStmt] ]
   , "break_" := '[]
   ]

-- 2. Surface Language:
-- Formed by prepending "while_" to CoreStmtRow!
type SurfaceStmtRow = ("while_" := '[ "cond" := String, "body" := [SurfaceStmt] ]) ': CoreStmtRow

-- Recursive newtypes:
newtype SurfaceStmt = SurfaceStmt (Variant SurfaceStmtRow)
newtype CoreStmt    = CoreStmt    (Variant CoreStmtRow)
```

### A.3 The Lowering Pass: $\mathcal{O}(1)$ Single-Constructor Peeling (`peel`)
To implement `desugarStmt :: SurfaceStmt -> CoreStmt`, we use `peel @"while_"`:

```haskell
desugarStmt :: SurfaceStmt -> CoreStmt
desugarStmt (SurfaceStmt stmt) = CoreStmt $ case peel @"while_" stmt of
  Right (REC { cond, body }) ->
    -- 1. We isolated the while loop!
    -- Lower it into a loop with a condition check and break:
    let checkCond = CoreStmt (VAR { print = REC { msg = "check (" ++ cond ++ ")" } })
        breakStmt = CoreStmt (VAR { break_ = REC {} })
        loweredBody = checkCond : (map desugarStmt body ++ [breakStmt])
    in VAR { loop = REC { body = loweredBody } }

  Left rest ->
    -- 2. Pure O(1) pass-through!
    rest
```

### A.4 Why `Left rest -> rest` is Revolutionary
Notice line:
```haskell
  Left rest -> rest
```
What happened here?
1. `peel @"while_"` inspected the active constructor tag in $\mathcal{O}(1)$ time.
2. If `stmt` was not `"while_"`, it returned `Left rest`.
3. The type of `rest` is `Variant (Delete "while_" SurfaceStmtRow)`.
4. Because `SurfaceStmtRow = ("while_" := ...) ': CoreStmtRow`, deleting `"while_"` produces **definitionally and exactly** `CoreStmtRow`!
5. Therefore, `rest` is **already** a valid `Variant CoreStmtRow`!

**We did not write a single line of boilerplate for `assign`, `print`, `loop`, or `break_`!** Even if our language had 100 other statements, `Left rest -> rest` passes them all through instantly, with zero array copying and zero heap allocations.

### A.5 Modular Interpretation: Reusing Pretty Printers
We write the target IR pretty-printer using `eliminateUniform` (with `Data.List (intercalate)` and a standard 2-space `indent` helper):

```haskell
import Data.List (intercalate)

indent :: String -> String
indent = unlines . map ("  " ++) . lines

ppCore :: CoreStmt -> String
ppCore (CoreStmt stmt) = eliminateUniform handlers stmt
  where
    handlers = REC
      { assign = \(REC { var, val }) -> var ++ " = " ++ show (val :: Int) ++ ";"
      , print  = \(REC { msg })      -> "print(\"" ++ msg ++ "\");"
      , loop   = \(REC { body })     -> "loop {\n" ++ indent (intercalate "\n" (map ppCore body)) ++ "}"
      , break_ = \_                  -> "break;"
      }
```

And for the surface language, we peel off `"while_"` and delegate all other constructors directly to `ppCore`:
```haskell
ppSurface :: SurfaceStmt -> String
ppSurface (SurfaceStmt stmt) = case peel @"while_" stmt of
  Right (REC { cond, body }) ->
    "while (" ++ cond ++ ") {\n" ++ indent (intercalate "\n" (map ppSurface body)) ++ "}"
  Left rest ->
    ppCore (CoreStmt rest)
```
100% code reuse with complete compile-time type safety.

---

## Addendum B: Worked Case Study — Resilient Parsing & Error ASTs ("Stope and Winze")

In modern IDEs, language servers, and interactive programming environments, user code is syntactically incomplete or broken more than 90% of the time as the developer types. 

Traditional compiler pipelines use **fail-stop** parsing:
```haskell
parseProgram :: String -> Either ParseError AST
```
If a single token or semicolon is missing in the middle of a file, the parser aborts, the entire `AST` is discarded, and the language server loses its outline view, type tooltips, and autocompletion across the entire module.

### B.1 The Error AST Dilemma in Closed Nominal Type Systems
Language designers attempting to make parsers error-tolerant in traditional Haskell run directly into the **Nominal Dilemma**:
1. **Approach 1: Polluting the Core AST:**
   Add an error node constructor directly to the closed nominal data type:
   ```haskell
   data Expr
     = Lit Int
     | Var String
     | BinOp String Expr Expr
     | ExprHole Span [Token]   -- Error node!
   ```
   *The fatal flaw:* Now **every single downstream pass**—the typechecker, constant folder, dead code eliminator, and code generator—is permanently forced to pattern match on `ExprHole`, even in backend passes that run long after errors have been validated! If someone forgets to handle `ExprHole` in a backend pass, it crashes at runtime.
2. **Approach 2: Duplicating the AST Hierarchy:**
   Maintain two parallel ASTs: `data ParsedExpr = ... | ParsedHole ...` and `data CleanExpr = ...`.
   *The fatal flaw:* You must write hundreds of lines of boilerplate tree-conversion code just to copy identical nodes (`ParsedLit` $\to$ `CleanLit`, `ParsedVar` $\to$ `CleanVar`, etc.) from the parser into the compiler.

### B.2 The "Stope and Winze" Architecture
Rather than viewing error recovery as "island parsing" (where valid code is treated as isolated islands in a meaningless sea of errors), the **stope and winze** model views errors through the lens of mining geology:
* **The Stope (The Ore Body):** The overarching, structurally valid framework of the program (module headers, imports, function declarations, and clean sibling statements).
* **The Winze (The Local Excavation):** An explicit, localized error hole carved out of the stope at the exact failure site.
* **The Gangue (The Waste Rock):** The unparsed raw tokens trapped within the winze.

With `polytropos`, we model this architecture cleanly:
* The **Stope** is an open row of clean language constructs (`ExprRow e`).
* The **Winze** is an additive variant constructor (`"hole" := ParseHoleRow`).
* The parser emits `ResilientExpr` (widened with `"hole"`).
* IDE passes inspect the tree and step over the winze, preserving symbols in the stope.
* The compilation gate narrows `ResilientExpr` back to `CleanExpr` using $\mathcal{O}(1)$ `peel @"hole"` with **zero tree-conversion boilerplate**!

### B.3 Defining the Schemas
We parameterize the clean expression and statement rows by sub-node type `e`, and derive the resilient versions by prepending error constructors:

```haskell
-- 1. Localized syntax error node (The Winze carrying Gangue):
type ParseHoleRow =
  '[ "span"     := String    -- e.g. "line 2:10"
   , "expected" := String    -- Grammar expectation
   , "gangue"   := [String]  -- Trapped unparsed tokens
   ]

-- 2. The Clean Stope (Valid Expression Forms):
type ExprRow e =
  '[ "lit"   := '[ "val" := Int ]
   , "var"   := '[ "name" := String ]
   , "binop" := '[ "op" := String, "lhs" := e, "rhs" := e ]
   ]

type CleanExprRow = ExprRow CleanExpr
newtype CleanExpr = CleanExpr (Variant CleanExprRow)

-- 3. The Resilient Parse AST: simply prepend "hole"!
type ResilientExprRow = ("hole" := ParseHoleRow) ': ExprRow ResilientExpr
newtype ResilientExpr = ResilientExpr (Variant ResilientExprRow)

-- 4. Statements:
type StmtRow e =
  '[ "assign" := '[ "var" := String, "val" := e ]
   , "print"  := '[ "val" := e ]
   ]

type CleanStmtRow = StmtRow CleanExpr
newtype CleanStmt = CleanStmt (Variant CleanStmtRow)

type ResilientStmtRow = ("stmtHole" := ParseHoleRow) ': StmtRow ResilientExpr
newtype ResilientStmt = ResilientStmt (Variant ResilientStmtRow)
```

### B.4 Resilient Parsing: Localizing the Winze
In our parser, when expression parsing fails (e.g. ungrammatical characters or missing delimiters), the parser doesn't crash or drop the statement. It skips tokens up to the statement delimiter (`;`), bundles the unparsed tokens as `gangue`, and emits a localized hole:

```haskell
parseResilientExpr (t : ts)
  | all isDigit t.tokStr = ...
  | isAlpha (head t.tokStr) = ...
  -- Syntax error encountered: isolate the winze!
  | otherwise =
      let (gangueTokens, rest) = L.span (\tok -> tok.tokStr /= ";") (t:ts)
          gangue = map (\tok -> tok.tokStr) gangueTokens
          hole = VAR
            { hole = REC
                { span = formatSpan t
                , expected = "number or variable"
                , gangue
                }
            }
      in (ResilientExpr hole, rest)
```

When parsing a source file with syntax errors:
```text
a = 10;
b = 20 + %$#@!;        -- Localized expression hole in b's RHS!
??? malformed stmt;    -- Complete statement hole!
c = 30;
print c;
```
The parser emits a lossless list of 5 `ResilientStmt` nodes! Statement 1 (`a`), Statement 4 (`c`), and Statement 5 (`print c`) are completely valid, while Statements 2 and 3 isolate their gangue into explicit holes.

### B.5 IDE Passes: Stepping Over the Winze
Because `ResilientStmt` is an open variant, downstream IDE tools can query the tree and step right over error holes:

```haskell
-- | IDE Symbol Table Pass:
-- Harvests variable declarations across the entire file so autocomplete and
-- jump-to-definition continue working even when other statements are broken.
collectSymbols :: [ResilientStmt] -> [String]
collectSymbols = concatMap getSym
  where
    getSym (ResilientStmt s) = case peel @"stmtHole" s of
      Right _ -> [] -- Step over the statement hole!
      Left validStmt -> case peel @"assign" validStmt of
        Right (REC { var }) -> [var]
        Left _              -> []
```

Running `collectSymbols` on the broken source above produces:
```haskell
["a", "b", "c"]
```
Even though line 2 and line 3 contain invalid syntax, the language server **successfully extracted all declared variables**. Autocompletion, outline views, and hover documentation remain fully operational across the entire file!

Simultaneously, an IDE diagnostic pass collects error squigglies:
```haskell
collectDiagnostics :: [ResilientStmt] -> [String]
collectDiagnostics = concatMap stmtDiag
  where
    stmtDiag (ResilientStmt s) = case peel @"stmtHole" s of
      Right (REC { span, expected, gangue }) ->
        [ "[" ++ span ++ "] Syntax Error: expected " ++ expected ++ ", but found: " ++ unwords gangue ]
      Left validStmt -> case peel @"assign" validStmt of
        Right (REC { val }) -> exprDiag val
        Left rest -> case peel @"print" rest of
          Right (REC { val }) -> exprDiag val
          Left _              -> []

    exprDiag (ResilientExpr e) = case peel @"hole" e of
      Right (REC { span, expected, gangue }) ->
        [ "[" ++ span ++ "] Expression Error: expected " ++ expected ++ ", but found: " ++ unwords gangue ]
      Left rest -> case peel @"binop" rest of
        Right (REC { lhs, rhs }) -> exprDiag lhs ++ exprDiag rhs
        Left _                   -> []
```

### B.6 The Compilation Gate: Zero-Boilerplate Narrowing via `peel`
When the compiler moves from IDE analysis to code generation, we must guarantee that no error holes can possibly reach the backend.

In traditional Haskell, converting from `ParsedAST` to `CleanAST` requires copying every constructor. With `polytropos`, we use `peel @"hole"`:

```haskell
validateExpr :: ResilientExpr -> Either String CleanExpr
validateExpr (ResilientExpr e) = case peel @"hole" e of
  Right (REC { span, expected, gangue }) ->
    Left ("[" ++ span ++ "] Unresolved hole: expected " ++ expected)
  Left rest -> case peel @"binop" rest of
    Right (REC { op, lhs, rhs }) -> do
      cleanL <- validateExpr lhs
      cleanR <- validateExpr rhs
      Right (CleanExpr (VAR { binop = REC { op, lhs = cleanL, rhs = cleanR } }))
    Left nonBinop -> case peel @"lit" nonBinop of
      Right (REC { val }) ->
        Right (CleanExpr (VAR { lit = REC { val } }))
      Left nonLit -> case peel @"var" nonLit of
        Right (REC { name }) ->
          Right (CleanExpr (VAR { var = REC { name } }))
        Left _ ->
          Left "Internal error"
```

Notice what happens in `Left rest`:
1. `peel @"hole"` verified in $\mathcal{O}(1)$ that the active constructor was not `"hole"`.
2. The remaining variant is definitionally stripped of `"hole"`.
3. If the expression is a leaf (`lit` or `var`), it is **already** of type `Variant CleanExprRow`!
4. The pure backend evaluator (`evalCleanExpr`) only ever accepts `CleanExpr`, guaranteeing total type safety at compile time with zero AST duplication.

You can run the full, live resilient parsing tutorial right now:
```bash
cabal run example-resilient
```

---

## Addendum C: Relational Database Models & Persistent Schemas

### C.1 Motivation: The Wide-Table Problem in Haskell Databases
Relational database tables in production systems rarely resemble toy tutorial examples. A real-world database table—such as an enterprise `users`, `invoices`, or `transactions` table—typically contains between 15 and 60 columns.

When interacting with relational backends in standard Haskell, developers face severe architectural bottlenecks:
1. **The 62-Column GHC Tuple Ceiling:** Standard Haskell tuples cap at 62 fields. If an SQL query selects more than 62 columns, GHC cannot construct the result tuple, forcing developers into fragile nested pairs or raw string manipulation.
2. **Nominal Record Proliferation:** Adding, dropping, or projecting columns (e.g. projecting a 3-column summary view from a 15-column table) requires declaring new nominal data types and writing repetitive projection boilerplate:
   ```haskell
   -- The tedious boilerplate required by traditional nominal records:
   toSummary :: FullUser -> UserSummary
   toSummary u = UserSummary { name = u.name, role = u.role, active = u.active }
   ```
3. **Template Haskell Compilation Tax:** Libraries like `persistent` often rely on heavy Template Haskell quasi-quoters (`[persistLowerCase| ... |]`). Modifying a single column triggers extensive recompilation cascades.

### C.2 Solution: Unified Open Rows Across Rel8 and Persistent
With `polytropos`, relational tables and queries are modeled as open rows. Because `polytropos` records are backed by a single flat `SmallArray`, they exhibit:
- **Zero Arity Limit:** Schemas can have 10, 50, or 500 columns with no tuple limit.
- **$\mathcal{O}(1)$ Column Access:** Compiles directly into literal array index offsets.
- **Zero-Boilerplate Sub-Row Projection:** Any subset of columns is projected in $\mathcal{O}(N)$ payload copies via `projectRecord` without writing any conversion functions.

Two dedicated satellite packages provide first-class integration:
- `polytropos-rel8`: Connects open rows to Oliver Charles' `rel8` PostgreSQL framework, providing `PolyRow` for `Rel8able` schemas and type-safe SQL query expressions (`litRecord`, `hfield`).
- `polytropos-persistent`: Bridges open rows to Yesod's `persistent` ORM, providing `PersistRow` for heterogeneous `[PersistValue]` marshalling and `PolyRowEntity` for entity keys.

### C.3 Step-by-Step Architecture: The User Table Schema
Let's examine how a 10-column database table is represented in [`examples/database/src/Main.hs`](../examples/database/src/Main.hs):

```haskell
-- | 10-column relational user entity row.
type UserRow =
  '[ "id"         ':= Int64
   , "name"       ':= Text
   , "email"      ':= Text
   , "role"       ':= Text
   , "tier"       ':= Text
   , "active"     ':= Bool
   , "points"     ':= Int64
   , "quota"      ':= Int64
   , "created_at" ':= Text
   , "notes"      ':= Text
   ]

-- | Projection view: a 3-column summary subset.
type UserSummaryRow =
  '[ "name"   ':= Text
   , "role"   ':= Text
   , "active" ':= Bool
   ]
```

### C.4 Lifting Open Rows to Rel8 SQL Expressions
Using `polytropos-rel8`, we lift an in-memory record directly into a Rel8 SQL table expression (`PolyRow UserRow Expr`):

```haskell
let userTable :: PolyRow UserRow Expr
    userTable = litRecord sampleUser

    nameExpr :: Expr Text
    nameExpr = hfield @"name" userTable

    pointsExpr :: Expr Int64
    pointsExpr = hfield @"points" userTable
```

Here:
1. `litRecord` recursively traverses the row at compile time, lifting each field into `Rel8.lit`.
2. `hfield @"name"` accesses the column expression using `HasField` typechecker resolution—completely avoiding manual tuple lens indexing.

### C.5 Heterogeneous Persistent Marshalling
Using `polytropos-persistent`, the same record marshals to and from Yesod's `[PersistValue]` rows in $\mathcal{O}(N)$ without intermediate tuples:

```haskell
-- Heterogeneous serialization
let pvals :: [PersistValue]
    pvals = toPersistFieldsRecord sampleUser

-- Heterogeneous deserialization
case fromPersistValuesRecord @UserRow pvals of
  Left err -> putStrLn ("Decode failed: " ++ T.unpack err)
  Right decodedUser -> putStrLn ("Decoded user: " ++ T.unpack decodedUser.name)
```

### C.6 Zero-Boilerplate Sub-Row Projection
When an API endpoint or report only requires a subset of columns, `projectRecord` projects the 3-column `UserSummaryRow` from `sampleUser` with zero conversion boilerplate:

```haskell
let summary :: Record UserSummaryRow
    summary = projectRecord sampleUser

putStrLn ("User: " ++ T.unpack summary.name ++ " (" ++ T.unpack summary.role ++ ")")
```
The GHC typechecker plugin proves that `UserSummaryRow` is a structural sub-row of `UserRow` and synthesizes the exact memory indices to copy into the new `Record`.

Run the full executable example:
```bash
cabal run example-database
```

---

## Addendum D: Extensible Algebraic Effects & Higher-Kinded Ropes

### D.1 Motivation: The Composition Crisis in Haskell Effects
Managing side effects (database queries, logging, metrics, caching) in large Haskell applications has traditionally relied on one of three paradigms, each with trade-offs:
1. **Monad Transformers (`MTL`):** Deep transformer stacks (`ReaderT (StateT (ExceptT ...)))`) suffer quadratic $O(N^2)$ instance resolution overhead and compile-time deceleration.
2. **Free / Extensible Monads:** Deeply nested AST trees require $O(N)$ runtime tree walks for every effect invocation, incurring GC pressure and pointer chasing.
3. **Effect Stacks (`effectful`, `polysemy`):** While fast, effect lists are typically closed type-level lists where changing the order or inserting a capability can break signatures across dozens of modules.

### D.2 The Higher-Kinded Rope (`kernmantle-polytropos`)
In pipeline-oriented and arrow-based applications (such as data pipelines, compiler passes, and microservices), effect composition is expressed naturally as an **extensible rope**:
- **Strands:** Individual effect interfaces (e.g. `LoggerStrand`, `DatabaseStrand`, `MetricsStrand`).
- **Mantle:** A record of active strands, modeled as an open row:
  ```haskell
  type AppMantle =
    '[ "logger"  ':= LoggerStrand
     , "db"      ':= DatabaseStrand
     , "metrics" ':= MetricsStrand
     ]
  ```
- **The Extensible Rope Arrow:**
  ```haskell
  newtype Rope (req :: Row) a b = Rope
    { unRope :: Record req -> a -> IO b
    }
  ```

### D.3 Composition via `SubRow` Projection
Notice how individual pipeline steps declare **only** the strands they require. When composing steps sequentially (`(>>>)`) or in parallel fan-out (`(&&&)`), `SubRow` automatically reconciles capability requirements:

```haskell
-- Step 1 requires ONLY "logger" and "db"
fetchAccountStep :: Rope '["logger" ':= LoggerStrand, "db" ':= DatabaseStrand] Text (Text, Int)

-- Step 2 requires ONLY "db" and "metrics"
chargeFeeStep :: Int -> Rope '["db" ':= DatabaseStrand, "metrics" ':= MetricsStrand] (Text, Int) (Text, Int)

-- Step 3 requires ONLY "logger"
auditStep :: Rope '["logger" ':= LoggerStrand] (Text, Int) Text

-- Composite Pipeline: Chains Step 1 >>> Step 2 >>> Step 3
-- Automatically infers the unified requirement row: 'AppMantle'!
orderPipeline :: Rope AppMantle Text Text
orderPipeline = fetchAccountStep >>> chargeFeeStep 25 >>> auditStep
```

When executing `orderPipeline`, each step receives its projected sub-mantle via `projectRecord`, executing at $\mathcal{O}(1)$ with zero runtime strand lookups!

### D.4 Higher-Kinded Records (`RecordF`) & Capability Audits
Beyond standard records, `polytropos` provides Higher-Kinded Records (`RecordF f r`), where every field slot is wrapped in a functor `f`.

Using `RecordF`, we can inspect, mock, or audit capabilities before running a pipeline:
- `RecordF Identity r`: Standard concrete runtime environment.
- `RecordF Maybe r`: Environment with optional or disabled features.
- `RecordF (Const [Text]) r`: Dry-run capability audit using `cfoldMapRecordF`.

Run the full executable example:
```bash
cabal run example-effects
```

---

## Addendum E: The Federated Context & Memory MCP Server Capstone

### E.1 Motivation: Multi-Backend AI Tool Multiplexing
Modern agentic AI architectures (such as Google Antigravity, Claude Desktop, and Claude Code) interact with codebases and knowledge stores via the **Model Context Protocol (MCP)**, an open standard built on JSON-RPC 2.0.

In enterprise software engineering environments, an AI assistant must multiplex multiple distinct data backends:
1. **Contextful:** High-speed local codebase search over SQLite3 FTS5 chunks, symbol indexes, and AST graphs.
2. **Kioku:** Long-term agent episodic memory and knowledge claims stored in PostgreSQL event logs (via `hasql`).

Implementing an MCP server in standard Haskell typically introduces extensive boilerplate:
- Hand-writing JSON-RPC protocol envelopes.
- Manually writing OpenAPI 3.0 input schemas for LLM tool calling.
- Cascading `if-then-else` or string-matching dispatch blocks to execute tools.
- Rigid response serialization that wastes expensive context window tokens.

### E.2 The Polytropos MCP Solution (`polytropos-mcp`)
The `polytropos-mcp` satellite package leverages the full four-quadrant design space of `polytropos`:
1. **Tool Input Schemas as Product Rows:** Each tool's parameters are defined as an open product row (e.g. `SearchArgs`, `RecallArgs`).
2. **Automatic OpenAPI 3.0 Schemas:** `recordToTool` automatically synthesizes valid OpenAPI 3.0 JSON Schema definitions directly from the type-level row structure!
3. **Tools as a Sum Row (Variant):** The collection of all tools registered by the server is represented as an open variant:
   ```haskell
   type ServerToolsRow =
     '[ "contextful_search" ':= SearchArgs
      , "kioku_recall"      ':= RecallArgs
      ]

   type ServerTools = Variant ServerToolsRow
   ```
4. **$\mathcal{O}(1)$ Jump-Table Tool Dispatch:** Instead of linear string matching, `eliminateUniform` compiles the tool handlers into a hardware jump table.
5. **Token-Budget Dynamic Sub-Row Compression:** When the LLM specifies a tight token budget, `projectRecord` dynamically sheds non-essential metadata fields before response serialization!

### E.3 Walkthrough of the Capstone Implementation
Let's walk through the architecture of [`examples/mcp-server/src/Main.hs`](../examples/mcp-server/src/Main.hs):

#### Step 1: Defining Tool Arguments as Open Rows
```haskell
-- | Arguments for searching Contextful's SQLite FTS5 index.
type SearchArgs =
  '[ "query"     ':= Text
   , "workspace" ':= Text
   , "budget"    ':= Int
   ]

-- | Arguments for recalling memories from Kioku's PostgreSQL event store.
type RecallArgs =
  '[ "scope"     ':= Text
   , "claim"     ':= Text
   ]

type ServerToolsRow =
  '[ "contextful_search" ':= SearchArgs
   , "kioku_recall"      ':= RecallArgs
   ]

type ServerTools = Variant ServerToolsRow
```

#### Step 2: Automatic Tool Registration & OpenAPI Synthesis
```haskell
serverTools :: [McpTool]
serverTools =
  [ recordToTool @"contextful_search"
      "Search Contextful codebase FTS5 index across chunks and symbols"
      (Proxy @SearchArgs)
  , recordToTool @"kioku_recall"
      "Recall agent memory and knowledge claims from Kioku PostgreSQL event store"
      (Proxy @RecallArgs)
  ]
```
`recordToTool` synthesizes the `tools/list` JSON response with zero runtime reflection or Template Haskell.

#### Step 3: $\mathcal{O}(1)$ Jump-Table Dispatch & Token Compression
```haskell
-- Full result row with verbose scoring and workspace metadata
type FullResultRow =
  '[ "title"     ':= Text
   , "path"      ':= Text
   , "snippet"   ':= Text
   , "score"     ':= Double
   , "workspace" ':= Text
   ]

-- Compact result row (sub-row of FullResultRow)
type CompactResultRow =
  '[ "title"     ':= Text
   , "path"      ':= Text
   , "snippet"   ':= Text
   ]

serverHandler :: ServerTools -> IO [McpContent]
serverHandler = eliminateUniform REC
  { contextful_search = \args -> do
      let rawResult :: Record FullResultRow
          rawResult = REC
            { title     = "Plugin Architecture Invariants"
            , path      = "docs/notes/POLYTROPOS_DESIGN.md"
            , snippet   = "Decisions D1-D10 collapse the four-quadrant design space into Rep."
            , score     = 0.982
            , workspace = args.workspace
            }

      -- Token-budget compression: if budget < 100 tokens, project to CompactResultRow!
      if args.budget < 100
        then do
          let compact :: Record CompactResultRow
              compact = projectRecord rawResult
          pure [TextContent $ "[COMPACT] " <> compact.title <> ": " <> compact.snippet]
        else do
          pure [TextContent $ "[FULL] " <> rawResult.title <> " [" <> rawResult.path <> "]: " <> rawResult.snippet]

  , kioku_recall = \args -> do
      pure [TextContent $ "[KIOKU MEMORY] Recall from scope '" <> args.scope <> "': " <> args.claim]
  }
```

### E.4 Running the Capstone Executable
You can run the simulated interactive demo:
```bash
cabal run example-mcp-server
```

Or connect it directly to an MCP client (such as Claude Desktop or Antigravity) over standard input/output:
```bash
cabal run example-mcp-server -- --stdio
```

---

# Part III: Hands-on Reader Exercises

To deepen your mastery, open the example files under [`examples/`](../examples/) and experiment with these exercises:

### Exercise 1: Add a `"for_"` Loop (Addendum A)
Extend `SurfaceStmtRow` in [`examples/nanopass/src/Main.hs`](../examples/nanopass/src/Main.hs) with a C-style for-loop:
```haskell
type SurfaceStmtRow =
  ("for_" := '[ "var" := String, "limit" := Int, "body" := [SurfaceStmt] ])
  ': ("while_" := '[ "cond" := String, "body" := [SurfaceStmt] ])
  ': CoreStmtRow
```
Now update `desugarStmt` to peel `"for_"` and lower it into an `"assign"` followed by a `"while_"`. Notice how your lowering passes compose naturally!

### Exercise 2: Add an `"if_"` Statement to Core (Addendum A)
Add an `"if_"` statement to `CoreStmtRow`:
```haskell
, "if_" := '[ "cond" := String, "thenB" := [CoreStmt], "elseB" := [CoreStmt] ]
```
Re-run `cabal run example-nanopass`. Notice that `desugarStmt` **still compiles unchanged without modifying a single line**, because `Left rest -> rest` forwards untouched constructors automatically!

### Exercise 3: Inspect Compiler Diagnostics
Deliberately misspell a field name in a record (e.g. `val_` instead of `val`) or omit a constructor handler in `ppCore`. Observe how the `Polytropos.Plugin` intercepts the unsolved constraint and outputs a custom human-centric diagnostic suggesting the correct name.

### Exercise 4: Add String Literals to the Resilient AST (Addendum B)
Open [`examples/resilient/src/Main.hs`](../examples/resilient/src/Main.hs) and extend `ExprRow e` with a string literal:
```haskell
, "str" := '[ "val" := String ]
```
Update the tokenizer and `parseResilientExpr` to recognize double-quoted strings (e.g. `"hello"`). Notice how `collectSymbols`, `collectDiagnostics`, and the compilation gate adapt with minimal edits!

### Exercise 5: Add a Timestamp Column to the Database Schema (Addendum C)
Open [`examples/database/src/Main.hs`](../examples/database/src/Main.hs) and add an `"updated_at" ':= Text` column to `UserRow`. Notice how:
1. `litRecord` automatically incorporates the new column into Rel8 expressions.
2. `toPersistFieldsRecord` and `fromPersistValuesRecord` automatically adjust their payload arities without changing any typeclasses or instances.
3. `projectRecord @UserSummaryRow` continues to compile without changes.

### Exercise 6: Add an In-Memory Cache Strand (Addendum D)
Open [`examples/effects/src/Main.hs`](../examples/effects/src/Main.hs) and define a `CacheStrand` storing key-value pairs in an `IORef (Map Text Text)`. Insert `"cache" ':= CacheStrand` into `AppMantle`, create a `cacheLookupStep`, and compose it with `fetchAccountStep >>> chargeFeeStep`. Notice how `SubRow` verifies capability requirements statically.

### Exercise 7: Add a Git Diff Tool to the MCP Server (Addendum E)
Open [`examples/mcp-server/src/Main.hs`](../examples/mcp-server/src/Main.hs) and add a new tool:
```haskell
type GitDiffArgs =
  '[ "commit_a" ':= Text
   , "commit_b" ':= Text
   ]
```
Add `"git_diff" ':= GitDiffArgs` to `ServerTools`, register it with `recordToTool @"git_diff"`, and supply the handler in `eliminateUniform`. Test calling the new tool over JSON-RPC!

