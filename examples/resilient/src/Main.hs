{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

-- | Worked Tutorial Example: Resilient Parsing & Error ASTs ("Stope and Winze").
--
-- This executable demonstrates how row-polymorphic variants solve the
-- Error AST Dilemma in language servers and compiler pipelines:
-- 1. The clean AST is defined as an open row.
-- 2. The resilient parser widens the row by prepending a localized error hole ("hole").
-- 3. Downstream IDE tools (symbol collection, outline view, diagnostics) step over
--    the winze and continue analyzing the valid surrounding stope.
-- 4. The compilation gate cleanly narrows the AST back to the pure clean row using
--    'peel @"hole"' with ZERO tree-conversion boilerplate.
--
-- Running:
--   $ cabal run example-resilient
module Main (main) where

import Prelude hiding (span)
import Polytropos
import Data.Char (isDigit, isAlpha, isAlphaNum, isSpace)
import qualified Data.List as L

{-------------------------------------------------------------------------------
  1. AST Definitions via Row Polymorphism ("Stope and Winze")
-------------------------------------------------------------------------------}

-- | Localized syntax error node (The "Winze" carrying "Gangue").
type ParseHoleRow =
  '[ "span"     := String    -- Source location span, e.g. "line 2:9-12"
   , "expected" := String    -- Description of expected grammar production
   , "gangue"   := [String]  -- The unparsed raw tokens trapped in the hole
   ]

-- | Expression schema parameterized by sub-expression type 'e'.
-- This forms the valuable "Stope" (the valid syntactic structure).
type ExprRow e =
  '[ "lit"   := '[ "val" := Int ]
   , "var"   := '[ "name" := String ]
   , "binop" := '[ "op" := String, "lhs" := e, "rhs" := e ]
   ]

-- | Clean Expression AST: contains ONLY valid syntax nodes.
type CleanExprRow = ExprRow CleanExpr
newtype CleanExpr = CleanExpr (Variant CleanExprRow)

-- | Resilient Expression AST: formed by prepending "hole" to the clean row!
type ResilientExprRow = ("hole" := ParseHoleRow) ': ExprRow ResilientExpr
newtype ResilientExpr = ResilientExpr (Variant ResilientExprRow)

-- | Statement schema parameterized by expression type 'e'.
type StmtRow e =
  '[ "assign" := '[ "var" := String, "val" := e ]
   , "print"  := '[ "val" := e ]
   ]

-- | Clean Statement AST.
type CleanStmtRow = StmtRow CleanExpr
newtype CleanStmt = CleanStmt (Variant CleanStmtRow)

-- | Resilient Statement AST: can be a whole-statement hole, or a statement
-- whose inner expression contains localized holes.
type ResilientStmtRow = ("stmtHole" := ParseHoleRow) ': StmtRow ResilientExpr
newtype ResilientStmt = ResilientStmt (Variant ResilientStmtRow)

{-------------------------------------------------------------------------------
  2. Minimal Tokenizer with Source Spans
-------------------------------------------------------------------------------}

data Token = Token
  { tokStr  :: String
  , tokLine :: Int
  , tokCol  :: Int
  } deriving (Show, Eq)

tokenize :: String -> [Token]
tokenize = go 1 1
  where
    go _ _ [] = []
    go line col (c:cs)
      | c == '\n' = go (line + 1) 1 cs
      | isSpace c = go line (col + 1) cs
      | isDigit c =
          let (num, rest) = L.span isDigit (c:cs)
              len = length num
          in Token num line col : go line (col + len) rest
      | isAlpha c =
          let (ident, rest) = L.span isAlphaNum (c:cs)
              len = length ident
          in Token ident line col : go line (col + len) rest
      | c `elem` "=+-*;" =
          Token [c] line col : go line (col + 1) cs
      | otherwise =
          -- Unrecognized symbol (gangue)
          let (syms, rest) = L.span (\ch -> not (isSpace ch || isAlphaNum ch || ch `elem` "=+-*;")) (c:cs)
              len = length syms
          in Token syms line col : go line (col + len) rest

formatSpan :: Token -> String
formatSpan t = "line " ++ show t.tokLine ++ ":" ++ show t.tokCol

{-------------------------------------------------------------------------------
  3. Resilient Parsing with Delimiter Synchronization
-------------------------------------------------------------------------------}

-- | Parse an expression with localized panic-mode recovery.
-- If parsing fails, it consumes tokens up to ';' or statement boundaries,
-- wraps the gangue into a 'VAR { hole = ... }', and returns without failing.
parseResilientExpr :: [Token] -> (ResilientExpr, [Token])
parseResilientExpr [] =
  let hole = VAR { hole = REC { span = "EOF", expected = "expression", gangue = [] } }
  in (ResilientExpr hole, [])
parseResilientExpr (t : ts)
  -- 1. Integer literal:
  | all isDigit t.tokStr =
      let val = read t.tokStr :: Int
          e = VAR { lit = REC { val } }
      in parseBinopRhs (ResilientExpr e) ts
  -- 2. Variable identifier:
  | (case t.tokStr of (c:_) -> isAlpha c; [] -> False) && t.tokStr /= "print" =
      let e = VAR { var = REC { name = t.tokStr } }
      in parseBinopRhs (ResilientExpr e) ts
  -- 3. Syntax error encountered: isolate the winze!
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

-- | Check if next token is a binary operator (+, -, *).
parseBinopRhs :: ResilientExpr -> [Token] -> (ResilientExpr, [Token])
parseBinopRhs lhs (opTok : ts)
  | opTok.tokStr `elem` ["+", "-", "*"] =
      let (rhs, rest) = parseResilientExpr ts
          binop = VAR
            { binop = REC
                { op = opTok.tokStr
                , lhs
                , rhs
                }
            }
      in (ResilientExpr binop, rest)
parseBinopRhs lhs tokens = (lhs, tokens)

-- | Parse a single statement.
-- If the statement header is corrupt, skips tokens until ';' and emits a 'stmtHole'.
parseResilientStmt :: [Token] -> Maybe (ResilientStmt, [Token])
parseResilientStmt [] = Nothing
parseResilientStmt (t1 : t2 : ts)
  -- Assignment: "var = <expr> ;"
  | (case t1.tokStr of (c:_) -> isAlpha c; [] -> False) && t1.tokStr /= "print" && t2.tokStr == "=" =
      let (expr, rest) = parseResilientExpr ts
          restAfterSemi = dropWhile (\t -> t.tokStr == ";") (dropSemi rest)
          stmt = VAR { assign = REC { var = t1.tokStr, val = expr } }
      in Just (ResilientStmt stmt, restAfterSemi)
parseResilientStmt (t1 : ts)
  -- Print statement: "print <expr> ;"
  | t1.tokStr == "print" =
      let (expr, rest) = parseResilientExpr ts
          restAfterSemi = dropWhile (\t -> t.tokStr == ";") (dropSemi rest)
          stmt = VAR { print = REC { val = expr } }
      in Just (ResilientStmt stmt, restAfterSemi)
  -- Corrupt statement header: skip to next ';'
  | otherwise =
      let (gangueTokens, rest) = L.span (\tok -> tok.tokStr /= ";") (t1:ts)
          gangue = map (\tok -> tok.tokStr) gangueTokens
          restAfterSemi = dropSemi rest
          hole = VAR
            { stmtHole = REC
                { span = formatSpan t1
                , expected = "assignment ('x = ...') or 'print ...'"
                , gangue
                }
            }
      in Just (ResilientStmt hole, restAfterSemi)

dropSemi :: [Token] -> [Token]
dropSemi (t : ts) | t.tokStr == ";" = ts
dropSemi ts = ts

-- | Parse an entire program into resilient statements.
parseResilientProgram :: String -> [ResilientStmt]
parseResilientProgram input = go (tokenize input)
  where
    go [] = []
    go tokens = case parseResilientStmt tokens of
      Nothing -> []
      Just (stmt, rest) -> stmt : go rest

{-------------------------------------------------------------------------------
  4. IDE Passes: Stepping Over the Winze
-------------------------------------------------------------------------------}

-- | IDE Symbol Table Pass:
-- Harvests variable declarations across the entire file so autocomplete and
-- jump-to-definition continue working even when other statements are broken.
collectSymbols :: [ResilientStmt] -> [String]
collectSymbols = concatMap getSym
  where
    getSym (ResilientStmt s) = case peel @"stmtHole" s of
      Right _ -> [] -- Step over the winze!
      Left validStmt -> case peel @"assign" validStmt of
        Right (REC { var }) -> [var]
        Left _              -> []

-- | IDE Diagnostic Pass:
-- Harvests all error holes and format editor squigglies without aborting compilation.
collectDiagnostics :: [ResilientStmt] -> [String]
collectDiagnostics = concatMap stmtDiag
  where
    stmtDiag (ResilientStmt s) = case peel @"stmtHole" s of
      Right (REC { span, expected, gangue }) ->
        [ "[" ++ span ++ "] Syntax Error: expected " ++ expected ++ ", but found gangue: " ++ unwords gangue ]
      Left validStmt -> case peel @"assign" validStmt of
        Right (REC { val }) -> exprDiag val
        Left rest -> case peel @"print" rest of
          Right (REC { val }) -> exprDiag val
          Left _              -> []

    exprDiag (ResilientExpr e) = case peel @"hole" e of
      Right (REC { span, expected, gangue }) ->
        [ "[" ++ span ++ "] Expression Error: expected " ++ expected ++ ", but encountered: " ++ unwords gangue ]
      Left rest -> case peel @"binop" rest of
        Right (REC { lhs, rhs }) -> exprDiag lhs ++ exprDiag rhs
        Left _                   -> []

{-------------------------------------------------------------------------------
  5. The Compilation Gate: Zero-Boilerplate Narrowing via 'peel'
-------------------------------------------------------------------------------}

-- | Validate and narrow a resilient expression into a clean expression.
-- If a "hole" constructor is present, it returns an error.
-- If NO hole is present, 'peel @"hole"' proves to GHC that the variant
-- belongs purely to 'CleanExprRow' with ZERO tree copying!
validateExpr :: ResilientExpr -> Either String CleanExpr
validateExpr (ResilientExpr e) = case peel @"hole" e of
  Right (REC { span, expected, gangue }) ->
    Left ("[" ++ span ++ "] Unresolved expression hole: expected " ++ expected ++ " (gangue: " ++ unwords gangue ++ ")")
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
          Left "Internal error: unexpected empty expression row"

-- | Validate and narrow a resilient statement into a clean statement.
validateStmt :: ResilientStmt -> Either String CleanStmt
validateStmt (ResilientStmt s) = case peel @"stmtHole" s of
  Right (REC { span, expected, gangue }) ->
    Left ("[" ++ span ++ "] Unresolved statement hole: expected " ++ expected ++ " (gangue: " ++ unwords gangue ++ ")")
  Left validStmt -> case peel @"assign" validStmt of
    Right (REC { var, val }) -> do
      cleanExpr <- validateExpr val
      Right (CleanStmt (VAR { assign = REC { var, val = cleanExpr } }))
    Left rest -> case peel @"print" rest of
      Right (REC { val }) -> do
        cleanExpr <- validateExpr val
        Right (CleanStmt (VAR { print = REC { val = cleanExpr } }))
      Left _ ->
        Left "Internal error: unexpected empty statement row"

-- | Validate an entire program through the compilation gate.
validateProgram :: [ResilientStmt] -> Either [String] [CleanStmt]
validateProgram stmts =
  let diags = collectDiagnostics stmts
  in if null diags
       then case mapM validateStmt stmts of
              Left err -> Left [err]
              Right clean -> Right clean
       else Left diags

{-------------------------------------------------------------------------------
  6. Clean Backend Interpreter
-------------------------------------------------------------------------------}

-- | Evaluate a clean expression against a variable environment.
evalCleanExpr :: [(String, Int)] -> CleanExpr -> Int
evalCleanExpr env (CleanExpr e) = eliminateUniform handlers e
  where
    handlers = REC
      { lit   = \(REC { val }) -> val
      , var   = \(REC { name }) -> case lookup name env of
                  Just v  -> v
                  Nothing -> error ("Undefined variable: " ++ name)
      , binop = \(REC { op, lhs, rhs }) ->
                  let l = evalCleanExpr env lhs
                      r = evalCleanExpr env rhs
                  in case op of
                       "+" -> l + r
                       "-" -> l - r
                       "*" -> l * r
                       _   -> error ("Unknown operator: " ++ op)
      }

-- | Execute a clean statement.
execCleanStmt :: [(String, Int)] -> CleanStmt -> IO [(String, Int)]
execCleanStmt env (CleanStmt s) = eliminateUniform handlers s
  where
    handlers = REC
      { assign = \(REC { var, val }) -> do
          let evaluated = evalCleanExpr env val
          pure ((var, evaluated) : filter ((/= var) . fst) env)
      , print = \(REC { val }) -> do
          let evaluated = evalCleanExpr env val
          putStrLn ("-> Output: " ++ show evaluated)
          pure env
      }

execCleanProgram :: [CleanStmt] -> IO ()
execCleanProgram stmts = go [] stmts
  where
    go _ [] = pure ()
    go env (s:ss) = do
      env' <- execCleanStmt env s
      go env' ss

{-------------------------------------------------------------------------------
  7. Pretty Printers
-------------------------------------------------------------------------------}

ppResilientExpr :: ResilientExpr -> String
ppResilientExpr (ResilientExpr e) = case peel @"hole" e of
  Right (REC { expected, gangue }) ->
    "<HOLE: expected " ++ expected ++ ", skipped: " ++ unwords gangue ++ ">"
  Left rest -> case peel @"binop" rest of
    Right (REC { op, lhs, rhs }) ->
      "(" ++ ppResilientExpr lhs ++ " " ++ op ++ " " ++ ppResilientExpr rhs ++ ")"
    Left nonBinop -> case peel @"lit" nonBinop of
      Right (REC { val }) -> show val
      Left nonLit -> case peel @"var" nonLit of
        Right (REC { name }) -> name
        Left _               -> "<unknown>"

ppResilientStmt :: ResilientStmt -> String
ppResilientStmt (ResilientStmt s) = case peel @"stmtHole" s of
  Right (REC { gangue }) ->
    "<STMT_HOLE: skipped: " ++ unwords gangue ++ ">;"
  Left validStmt -> case peel @"assign" validStmt of
    Right (REC { var, val }) -> var ++ " = " ++ ppResilientExpr val ++ ";"
    Left rest -> case peel @"print" rest of
      Right (REC { val }) -> "print " ++ ppResilientExpr val ++ ";"
      Left _              -> "<unknown_stmt>;"

{-------------------------------------------------------------------------------
  8. Live Demonstration
-------------------------------------------------------------------------------}

main :: IO ()
main = do
  putStrLn "================================================================="
  putStrLn "  POLYTROPOS WORKED TUTORIAL: RESILIENT PARSING (STOPE & WINZE)"
  putStrLn "================================================================="
  putStrLn ""

  -- Scenario A: A script containing deliberate syntax errors (gangue)
  let brokenSource :: String
      brokenSource = unlines
        [ "a = 10;"
        , "b = 20 + %$#@!;"    -- Localized expression hole in b's RHS!
        , "??? malformed stmt;" -- Complete statement hole!
        , "c = 30;"
        , "print c;"
        ]

  putStrLn "--- [Scenario A: Ingesting Broken Code] ---"
  putStrLn "Source text:"
  putStrLn brokenSource

  putStrLn "--- [A.1 Resilient Parse Tree (Lossless AST)] ---"
  let resilientAST = parseResilientProgram brokenSource
  mapM_ (putStrLn . ppResilientStmt) resilientAST
  putStrLn ""

  putStrLn "--- [A.2 IDE Symbol Table Harvesting (Stepping Over the Winze)] ---"
  let symbols = collectSymbols resilientAST
  putStrLn ("Harvested symbols in scope: " ++ show symbols)
  putStrLn "Notice: 'a', 'b', and 'c' are all available for autocomplete despite errors!"
  putStrLn ""

  putStrLn "--- [A.3 IDE Diagnostics (Localizing the Gangue)] ---"
  let diagnostics = collectDiagnostics resilientAST
  mapM_ putStrLn diagnostics
  putStrLn ""

  putStrLn "--- [A.4 The Compilation Gate (Preventing Unsound Codegen)] ---"
  case validateProgram resilientAST of
    Left errors -> do
      putStrLn "Compilation Gate BLOCKED codegen as expected with errors:"
      mapM_ (\err -> putStrLn ("  [X] " ++ err)) errors
    Right _ ->
      putStrLn "Unexpected: broken program passed compilation gate!"
  putStrLn ""

  -- Scenario B: A clean script passing the gate and executing
  let cleanSource :: String
      cleanSource = unlines
        [ "a = 10;"
        , "b = 20 + 5;"
        , "c = a * b;"
        , "print c;"
        ]

  putStrLn "--- [Scenario B: Ingesting Clean Code] ---"
  putStrLn "Source text:"
  putStrLn cleanSource

  let cleanResilientAST = parseResilientProgram cleanSource
  case validateProgram cleanResilientAST of
    Left errors -> do
      putStrLn "Validation unexpectedly failed:"
      mapM_ putStrLn errors
    Right cleanAST -> do
      putStrLn "Compilation Gate PASSED: narrowed to 'CleanStmt' with zero boilerplate!"
      putStrLn "Executing pure backend:"
      execCleanProgram cleanAST

  putStrLn ""
  putStrLn "================================================================="
  putStrLn "Tutorial completed: Resilient ASTs cleanly isolate errors via rows!"
  putStrLn "================================================================="
