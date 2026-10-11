<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# Interactive Tutorial: Practical Row Polymorphism with Polytropos

**Status:** LIVING TUTORIAL · v1.0 · 2026-10-11  
**Audience:** Haskell Programmers, Compiler Writers, AI Coding Assistants  
**Prerequisites:** Familiarity with basic Haskell syntax (types, pattern matching, functions). No prior experience with type-level programming, category theory, or compiler plugins is required!

---

## Quick Start: Run the Tutorial Code Live

Every code example in this tutorial is live, compilable, and runnable right out of the repository. You can execute the complete worked compiler pass immediately from your terminal:

```bash
# Build and run the executable tutorial
cabal run example-nanopass

# Or explore the functions interactively in GHCi
cabal repl example-nanopass
```

The executable source code is located at [`examples/nanopass/src/Main.hs`](../examples/nanopass/src/Main.hs). We encourage you to follow along, edit the code, and test your own language extensions!

---

## 1. The Core Mental Model

Standard Haskell data types are **nominal** and **closed**:
- A data type declared with `data Stmt = Assign ... | While ...` exists only under that specific name (`Stmt`).
- You cannot add a constructor to `Stmt` without modifying its definition and breaking every pattern match across your codebase.
- You cannot take a subset of `Stmt` constructors without declaring an entirely separate data type and writing tedious conversion boilerplate.

`polytropos` introduces **structural row polymorphism** for both products (records) and sums (variants).

### 1.1 What is a Row?

A **row** is a type-level association list of names (`Symbol`) and types.

For records:
```haskell
type PersonRow = '[ "name" := String, "age" := Int ]
```

For variants (open sum types):
```haskell
type ResultRow = '[ "Ok" := '[ "val" := Int ], "Err" := '[ "msg" := String ] ]
```

Notice the key symmetry:
- A **Record** is a product of named fields: it holds a value for *every* field in the row.
- A **Variant** is a sum of named constructors: it holds *one active constructor* whose payload is a record of that constructor's arguments.

### 1.2 Flat Runtime Architecture ($O(1)$)

Unlike traditional extensible record libraries that encode rows as nested pairs (`(a, (b, (c, ())))`) or recursive typeclass trees (which take $O(N)$ time to access and quadratic time to compile), `polytropos` collapses all rows into a single flat representation:

```haskell
data Rep f a = Rep
  { repTag  :: {-# UNPACK #-} !Word
  , repVals :: {-# UNPACK #-} !(SmallArray (f Any))
  }
```

- A **Record** has `repTag = 0` and stores all field values in a contiguous `SmallArray`. Field access is an $O(1)$ direct array index evaluated at compile time.
- A **Variant** stores the active constructor index in `repTag` and the constructor's payload in `repVals`.

---

## 2. Ergonomic Syntax

With the `Polytropos.Plugin` enabled (`{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}`), you can write records and variants using standard Haskell syntax:

### 2.1 Records: `REC` and OverloadedRecordDot

```haskell
-- Constructing a record:
let user = REC { name = "Alice", age = 30 :: Int }

-- Field access via standard dot syntax:
let greeting = "Hello, " ++ user.name
```

### 2.2 Variants: `VAR`

```haskell
-- Injecting into an open variant:
let successVal :: Variant '[ "ok" := '[ "val" := Int ], "err" := '[ "msg" := String ] ]
    successVal = VAR { ok = REC { val = 200 :: Int } }

let failureVal = VAR { err = REC { msg = "Not Found" } }
```

---

## 3. Worked Case Study: The Nanopass Compiler

The **Nanopass** compiler architecture (pioneered by Sarkar, Waddell, and Dybvig) structures compilers into dozens of tiny, single-purpose passes. Each pass removes, rewrites, or introduces exactly one language construct.

### 3.1 The Nominal Dilemma

In traditional Haskell, implementing a nanopass is notoriously painful:

1. **Option A (Shared Closed AST):** If all passes share `data Stmt = While ... | Loop ... | Assign ...`, the output type of `desugarWhile` is still `Stmt`. The type system cannot prevent subsequent code generation passes from failing if they encounter an unexpected `While`.
2. **Option B (Duplicated ASTs):** If you define `data SurfaceStmt` and `data CoreStmt`, you must write 50 lines of boilerplate copying every constructor you *didn't* touch:
   ```haskell
   desugar (SurfaceAssign v x) = CoreAssign v x
   desugar (SurfacePrint m)    = CorePrint m
   desugar (SurfaceIf c t e)   = CoreIf c (desugar t) (desugar e)
   -- ... duplicate 50 other statements ...
   ```

### 3.2 The Polytropos Solution: Row Subtraction

With row-polymorphic variants, we define our ASTs modularly:

```haskell
-- 1. The Core Target Language:
-- Primitive assignments, printing, infinite loops, and breaks.
-- (Notice: Core has NO while loops!)
type CoreStmtRow =
  '[ "assign" := '[ "var" := String, "val" := Int ]
   , "print"  := '[ "msg" := String ]
   , "loop"   := '[ "body" := [CoreStmt] ]
   , "break_" := '[]
   ]

-- 2. The Surface Language:
-- Formed by prepending "while_" to CoreStmtRow!
type SurfaceStmtRow = ("while_" := '[ "cond" := String, "body" := [SurfaceStmt] ]) ': CoreStmtRow

-- Recursive newtypes:
newtype SurfaceStmt = SurfaceStmt (Variant SurfaceStmtRow)
newtype CoreStmt    = CoreStmt    (Variant CoreStmtRow)
```

Look at `SurfaceStmtRow`: `while_` is simply added to `CoreStmtRow`.

### 3.3 The Lowering Pass: $O(1)$ Constructor Peeling

Now, how do we write `desugarStmt :: SurfaceStmt -> CoreStmt`?

We use `peel @"while_"`:

```haskell
desugarStmt :: SurfaceStmt -> CoreStmt
desugarStmt (SurfaceStmt stmt) = CoreStmt $ case peel @"while_" stmt of
  Right (REC { cond, body }) ->
    -- 1. We encountered a while loop!
    -- Desugar it into an infinite loop with a condition check and break:
    let checkCond = CoreStmt (VAR { print = REC { msg = "check (" ++ cond ++ ")" } })
        breakStmt = CoreStmt (VAR { break_ = REC {} })
        loweredBody = checkCond : (map desugarStmt body ++ [breakStmt])
    in VAR { loop = REC { body = loweredBody } }

  Left rest ->
    -- 2. Pure O(1) pass-through!
    rest
```

### 3.4 Why `Left rest -> rest` is Magic

Look closely at line:
```haskell
  Left rest -> rest
```

What just happened here?
1. `peel @"while_"` inspected the active constructor in $O(1)$ time.
2. If `stmt` was *not* a `while_`, it returned `Left rest`.
3. The type of `rest` is `Variant (Delete "while_" SurfaceStmtRow)`.
4. Because `SurfaceStmtRow = ("while_" := ...) ': CoreStmtRow`, deleting `"while_"` produces **definitionally and exactly** `CoreStmtRow`!
5. Therefore, `rest` is **already** a valid `Variant CoreStmtRow`!

**We did not write a single line of code for `assign`, `print`, `loop`, or `break_`!** Even if our language had 100 other statements, `Left rest -> rest` passes them all through instantly, with zero array copying and zero heap allocations.

---

## 4. Total Elimination & Modular Interpretation

How do we evaluate or pretty-print our ASTs?

### 4.1 $O(1)$ Total Elimination: `eliminateUniform`

`polytropos` provides `eliminateUniform` to eliminate a variant using a record of handler functions:

```haskell
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

**How it works under the hood:**
- `eliminateUniform` does **not** perform linear sequential `case` matching.
- It extracts the variant's tag $t$ and immediately indexes slot $t$ of the handler record's array in $O(1)$ time.
- If you forget any constructor, the compiler will refuse to compile with an informative missing field diagnostic.

### 4.2 Modular Extension: Reusing `ppCore` for `ppSurface`

Now, do we need to rewrite `ppSurface` from scratch? No! We peel off `"while_"` and delegate all other constructors directly to `ppCore`:

```haskell
ppSurface :: SurfaceStmt -> String
ppSurface (SurfaceStmt stmt) = case peel @"while_" stmt of
  Right (REC { cond, body }) ->
    "while (" ++ cond ++ ") {\n" ++ indent (intercalate "\n" (map ppSurface body)) ++ "}"
  Left rest ->
    -- rest is already a CoreStmt! Delegate directly:
    ppCore (CoreStmt rest)
```

We get 100% code reuse for free.

---

## 5. Try It Yourself: Exercises for the Reader

To solidify your understanding, open [`examples/nanopass/src/Main.hs`](../examples/nanopass/src/Main.hs) and try these hands-on exercises:

### Exercise 1: Add a `"for_"` Loop
Extend `SurfaceStmtRow` with a C-style for-loop:
```haskell
type SurfaceStmtRow =
  ("for_" := '[ "initVar" :: String, "limit" :: Int, "body" :: [SurfaceStmt] ])
  ': ("while_" := '[ "cond" := String, "body" := [SurfaceStmt] ])
  ': CoreStmtRow
```
Now update `desugarStmt` to peel `"for_"` and lower it into an `"assign"` followed by a `"while_"`. Notice how your lowering pipeline composes!

### Exercise 2: Add an `"if_"` Statement to Core
Add an `"if_"` constructor to `CoreStmtRow`:
```haskell
, "if_" := '[ "cond" := String, "thenB" := [CoreStmt], "elseB" := [CoreStmt] ]
```
Re-run `cabal run example-nanopass`. Notice that `desugarStmt` **still compiles unchanged without touching a single line**, because `Left rest -> rest` automatically forwards the new constructor!

### Exercise 3: Observe Compiler Diagnostics
Deliberately misspell a field name in a record (e.g. `val_` instead of `val`) or omit a constructor in `ppCore`. Notice how the `polytropos` compiler plugin intercepts the error and outputs a crystal-clear human-centric diagnostic suggesting the right field name.

---

## 6. Tutorial Roadmap: Upcoming Chapters

This tutorial is the first chapter in our documentation series. Future worked examples will cover:

| Chapter | Topic | Real-World Application |
|---|---|---|
| **Chapter 2** | *Resilient Parsing & Error ASTs ("Stope and Winze")* | Modeling syntax errors as explicit open variant nodes (`ParseHole`) for resilient compiler frontends. |
| **Chapter 3** | *High-Performance Database Models* | Generating relational schemas and SQL queries using `polytropos-rel8` and `polytropos-persistent`. |
| **Chapter 4** | *Extensible Algebraic Effects* | Defining modular effect signatures with `effectful-polytropos` and `kernmantle-polytropos`. |

Enjoy experimenting with row polymorphism in Haskell!
