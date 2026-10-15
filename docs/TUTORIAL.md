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
# Build and run the executable tutorial
cabal run example-nanopass

# Or explore the types and combinators interactively in GHCi
cabal repl example-nanopass
```

The executable source code is located at [`examples/nanopass/src/Main.hs`](../examples/nanopass/src/Main.hs).

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

Standard Haskell data types are **nominal** and **closed**:
- A type declared with `data Person = Person { name :: String, age :: Int }` exists only under that specific name (`Person`).
- You cannot add a field or constructor to a data type without modifying its definition and breaking every pattern match across your project.
- You cannot take a subset of fields or constructors without declaring an entirely separate data type and writing tedious conversion boilerplate.

`polytropos` introduces **structural row polymorphism** for both products (records) and sums (variants). Under the hood, both collapse into a single flat representation:
```haskell
data Rep (f :: Type -> Type) a = Rep
  {-# UNPACK #-} !Word
  !(SmallArray (f Any))

repTag  :: Rep f a -> Word
repVals :: Rep f a -> SmallArray (f Any)
```
All row operations compile down to literal array index reads, writes, and tag jumps evaluated in $\mathcal{O}(1)$ time by the `Polytropos.Plugin` typechecker plugin.

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

-- Ergonomic record update syntax:
let olderUser = (REC_UPD user) { age = 31 }
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

## Upcoming Addenda in this Series

| Addendum | Architecture | Core Primitives Demonstrated |
|---|---|---|
| **Addendum B** | *Resilient Parsing & Error ASTs ("Stope and Winze")* | Explicit variant error nodes (`ParseHole`), semantic error containment, IDE language server fault tolerance. |
| **Addendum C** | *Relational Database Models* | High-throughput SQL table schemas and query projection with `polytropos-rel8` and `polytropos-persistent`. |
| **Addendum D** | *Extensible Algebraic Effects* | Modular effect rows and $\mathcal{O}(1)$ handler dispatch with `effectful-polytropos` and `kernmantle-polytropos`. |

---

# Part III: Hands-on Reader Exercises

To deepen your mastery, open [`examples/nanopass/src/Main.hs`](../examples/nanopass/src/Main.hs) and experiment with these exercises:

### Exercise 1: Add a `"for_"` Loop
Extend `SurfaceStmtRow` with a C-style for-loop:
```haskell
type SurfaceStmtRow =
  ("for_" := '[ "var" := String, "limit" := Int, "body" := [SurfaceStmt] ])
  ': ("while_" := '[ "cond" := String, "body" := [SurfaceStmt] ])
  ': CoreStmtRow
```
Now update `desugarStmt` to peel `"for_"` and lower it into an `"assign"` followed by a `"while_"`. Notice how your lowering passes compose naturally!

### Exercise 2: Add an `"if_"` Statement to Core
Add an `"if_"` statement to `CoreStmtRow`:
```haskell
, "if_" := '[ "cond" := String, "thenB" := [CoreStmt], "elseB" := [CoreStmt] ]
```
Re-run `cabal run example-nanopass`. Notice that `desugarStmt` **still compiles unchanged without modifying a single line**, because `Left rest -> rest` forwards untouched constructors automatically!

### Exercise 3: Inspect Compiler Diagnostics
Deliberately misspell a field name in a record (e.g. `val_` instead of `val`) or omit a constructor handler in `ppCore`. Observe how the `Polytropos.Plugin` intercepts the unsolved constraint and outputs a custom human-centric diagnostic suggesting the correct name.
