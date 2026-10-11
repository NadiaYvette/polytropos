{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

-- | Worked Tutorial Example: Nanopass Compiler Pass with Polytropos.
--
-- This executable demonstrates how row-polymorphic variants solve the
-- Expression Problem and eliminate AST duplication in compiler pipelines.
--
-- Running:
--   $ cabal run example-nanopass
module Main (main) where

import Polytropos
import Data.List (intercalate)

{-------------------------------------------------------------------------------
  1. AST Definitions via Row Polymorphism
-------------------------------------------------------------------------------}

-- | Core statement row (the target language IR).
-- Notice: Core has primitive assignments, printing, infinite loops, and breaks,
-- but NO high-level while loops.
type CoreStmtRow =
  '[ "assign" := '[ "var" := String, "val" := Int ]
   , "print"  := '[ "msg" := String ]
   , "loop"   := '[ "body" := [CoreStmt] ]
   , "break_" := '[]
   ]

-- | Surface statement row (the user-facing language).
-- Formed by simply prepending "while_" to CoreStmtRow!
type SurfaceStmtRow = ("while_" := '[ "cond" := String, "body" := [SurfaceStmt] ]) ': CoreStmtRow

-- | Recursive AST newtypes.
newtype SurfaceStmt = SurfaceStmt (Variant SurfaceStmtRow)
newtype CoreStmt    = CoreStmt (Variant CoreStmtRow)

{-------------------------------------------------------------------------------
  2. The Desugaring Nanopass: desugarWhile
-------------------------------------------------------------------------------}

-- | Lower a surface AST to a core AST by desugaring "while_" into "loop".
--
-- KEY INVARIANT:
-- Using 'peel @"while_"', we isolate the "while_" constructor in O(1).
-- If the statement is a "while_", we rewrite it into a "loop" with desugared body.
-- If the statement is NOT a "while_", 'peel' returns (Left rest) where 'rest'
-- is ALREADY of type 'Variant CoreStmtRow'. We pass it through directly
-- with ZERO boilerplate and ZERO runtime reallocation!
desugarStmt :: SurfaceStmt -> CoreStmt
desugarStmt (SurfaceStmt stmt) = CoreStmt $ case peel @"while_" stmt of
  Right (REC { cond, body }) ->
    -- Desugar: while (cond) { body }
    -- Into:    loop { print("checking " ++ cond); body; break; }
    let checkCond = CoreStmt (VAR { print = REC { msg = "check (" ++ cond ++ ")" } })
        breakStmt = CoreStmt (VAR { break_ = REC {} })
        loweredBody = checkCond : (map desugarStmt body ++ [breakStmt])
    in VAR { loop = REC { body = loweredBody } }
  Left rest ->
    -- Pure O(1) pass-through!
    -- Statically guaranteed by GHC's type system to be a valid CoreStmtRow.
    rest

{-------------------------------------------------------------------------------
  3. Pretty Printers: Modular Extension
-------------------------------------------------------------------------------}

-- | Helper to indent lines for pretty printing.
indent :: String -> String
indent = unlines . map ("  " ++) . lines

-- | Pretty print target IR statements using 'eliminateUniform'.
-- 'eliminateUniform' dispatches in O(1) via an array jump table and enforces
-- total pattern coverage at compile time.
ppCore :: CoreStmt -> String
ppCore (CoreStmt stmt) = eliminateUniform handlers stmt
  where
    handlers = REC
      { assign = \(REC { var, val }) -> var ++ " = " ++ show (val :: Int) ++ ";"
      , print  = \(REC { msg })      -> "print(\"" ++ msg ++ "\");"
      , loop   = \(REC { body })     -> "loop {\n" ++ indent (intercalate "\n" (map ppCore body)) ++ "}"
      , break_ = \_                  -> "break;"
      }

-- | Pretty print surface statements.
-- Instead of duplicating the pretty printer for assign, print, loop, and break_,
-- we peel off "while_", format it, and delegate all other constructors directly to 'ppCore'!
ppSurface :: SurfaceStmt -> String
ppSurface (SurfaceStmt stmt) = case peel @"while_" stmt of
  Right (REC { cond, body }) ->
    "while (" ++ cond ++ ") {\n" ++ indent (intercalate "\n" (map ppSurface body)) ++ "}"
  Left rest ->
    ppCore (CoreStmt rest)

{-------------------------------------------------------------------------------
  4. Live Demonstration
-------------------------------------------------------------------------------}

main :: IO ()
main = do
  putStrLn "================================================================="
  putStrLn "  POLYTROPOS WORKED TUTORIAL: NANOPASS COMPILER PASS"
  putStrLn "================================================================="
  putStrLn ""

  -- Build a sample surface program:
  -- count = 0;
  -- while (count < 3) {
  --   print("Counting...");
  --   count = 1;
  -- }
  -- print("Done!");
  let program :: [SurfaceStmt]
      program =
        [ SurfaceStmt (VAR { assign = REC { var = "count", val = (0 :: Int) } })
        , SurfaceStmt (VAR
            { while_ = REC
                { cond = "count < 3"
                , body =
                    [ SurfaceStmt (VAR { print = REC { msg = "Counting..." } })
                    , SurfaceStmt (VAR { assign = REC { var = "count", val = (1 :: Int) } })
                    ]
                }
            })
        , SurfaceStmt (VAR { print = REC { msg = "Done!" } })
        ]

  putStrLn "--- [1] Original Surface Program ---"
  mapM_ (putStrLn . ppSurface) program
  putStrLn ""

  putStrLn "--- [2] Running Nanopass Lowering (desugarStmt) ---"
  let loweredProgram :: [CoreStmt]
      loweredProgram = map desugarStmt program
  putStrLn "Successfully desugared: 'while_' eliminated at compile-time!"
  putStrLn ""

  putStrLn "--- [3] Lowered Core IR Program ---"
  mapM_ (putStrLn . ppCore) loweredProgram
  putStrLn ""
  putStrLn "================================================================="
  putStrLn "All passes executed cleanly. The target AST cannot contain while_!"
  putStrLn "================================================================="
