{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

-- | Worked Tutorial Example: Relational Database Models & Persistent Schemas.
--
-- This executable demonstrates:
--   1. Schema definition for a wide 10-column database entity row.
--   2. Type-safe Rel8 expression lifting and column projection with 'PolyRow'.
--   3. Heterogeneous Yesod Persistent serialization and deserialization via 'PersistRow'.
--   4. Zero-cost sub-row projection with 'projectRecord'.
--
-- Running:
--   $ cabal run example-database
module Main (main) where

import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Rel8 (Expr, showQuery, values)
import Database.Persist (PersistValue)

import Polytropos
import Polytropos.Rel8
import Polytropos.Persistent

{-------------------------------------------------------------------------------
  1. Relational Schema as an Open Row
-------------------------------------------------------------------------------}

-- | 10-column relational user entity row.
-- Unlike GHC standard tuples (which bottleneck at 62 columns and require
-- heavy metaprogramming), a Polytropos row has no arity limit and is
-- backed by a single flat SmallArray.
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

{-------------------------------------------------------------------------------
  2. Sample Records & Operations
-------------------------------------------------------------------------------}

sampleUser :: Record UserRow
sampleUser = REC
  { id         = 1001
  , name       = "Ada Lovelace"
  , email      = "ada@polytropos.org"
  , role       = "Architect"
  , tier       = "Enterprise"
  , active     = True
  , points     = 9500
  , quota      = 50000
  , created_at = "1843-12-10T00:00:00Z"
  , notes      = "First computer programmer; computational pioneer"
  }

main :: IO ()
main = do
  TIO.putStrLn "============================================================"
  TIO.putStrLn " Addendum C: Relational Database Models & Persistent Schemas"
  TIO.putStrLn "============================================================"
  TIO.putStrLn ""

  -- 1. Rel8 SQL Expression Representation
  TIO.putStrLn "--- 1. Rel8 Columnar Schema & SQL Literals ---"
  let userTable :: PolyRow UserRow Expr
      userTable = litRecord sampleUser

      _nameExpr :: Expr Text
      _nameExpr = hfield (Field @"name") userTable

      _pointsExpr :: Expr Int64
      _pointsExpr = hfield (Field @"points") userTable

      sqlQuery :: Text
      sqlQuery = T.pack (showQuery (values [userTable]))

  TIO.putStrLn $ "Generated Rel8 SQL query: " <> sqlQuery
  TIO.putStrLn ""

  -- 2. Persistent Row Serialization
  TIO.putStrLn "--- 2. Persistent PersistValue Marshalling ---"
  let pvals :: [PersistValue]
      pvals = toPersistFieldsRecord sampleUser
  TIO.putStrLn $ "Serialized fields count: " <> T.pack (show (length pvals))
  TIO.putStrLn $ "Raw PersistValues:       " <> T.pack (show pvals)

  case fromPersistValuesRecord @UserRow pvals of
    Left err -> TIO.putStrLn $ "Deserialization failed: " <> err
    Right decodedUser -> do
      TIO.putStrLn "Roundtrip deserialization successful!"
      TIO.putStrLn $ "  Decoded Name:   " <> decodedUser.name
      TIO.putStrLn $ "  Decoded Email:  " <> decodedUser.email
      TIO.putStrLn $ "  Decoded Points: " <> T.pack (show (decodedUser.points :: Int64))
  TIO.putStrLn ""

  -- 3. Sub-row Projection
  TIO.putStrLn "--- 3. Sub-Row Projection (projectRecord) ---"
  let summary :: Record UserSummaryRow
      summary = projectRecord sampleUser
  TIO.putStrLn $ "Projected summary view:"
  TIO.putStrLn $ "  Name:   " <> summary.name
  TIO.putStrLn $ "  Role:   " <> summary.role
  TIO.putStrLn $ "  Active: " <> T.pack (show (summary.active :: Bool))
  TIO.putStrLn ""

  -- 4. Entity Wrapper
  TIO.putStrLn "--- 4. Persistent PolyRowEntity Wrapper ---"
  let entity = toPolyRowEntity (1001 :: Int64) sampleUser
      k = polyRowKey entity
      userPayload = polyRowRecord entity
  TIO.putStrLn $ "Entity key:     " <> T.pack (show k)
  TIO.putStrLn $ "Entity payload: " <> userPayload.name <> " (" <> userPayload.tier <> ")"
  TIO.putStrLn ""
  TIO.putStrLn "Database demonstration completed cleanly!"
