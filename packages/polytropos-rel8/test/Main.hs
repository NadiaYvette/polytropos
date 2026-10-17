{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

module Main (main) where

import Data.Functor.Const (Const (..))
import Data.Functor.Identity (Identity (..))
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Unsafe.Coerce (unsafeCoerce)

import Rel8 (TableSchema (..), namesFromLabels, each, values, showQuery)
import Rel8.Internal.Schema.Name (Name (..))

import Polytropos
  ( Record
  , Pair (..)
  , Field (..)
  , emptyRecord
  , insertField
  )
import Polytropos.Rel8
  ( PolyRow
  , toRecord
  , fromRecord
  , rowToColumns
  , columnsToRow
  , litPolyRow
  , litRecord
  , hfield
  , hfieldAt
  , htabulate
  , hmap
  , htraverse
  , hzipWith
  )

{-------------------------------------------------------------------------------
  Test Schemas and Records
-------------------------------------------------------------------------------}

type UserRow = '["id" ':= Int64, "name" ':= Text, "active" ':= Bool]

userSchema :: TableSchema (PolyRow UserRow Name)
userSchema = TableSchema
  { name = "users"
  , columns = Rel8.namesFromLabels
  }

userRecord :: Record UserRow
userRecord = REC { id = 42 :: Int64, name = "Alice" :: Text, active = True }

type SingleRow = '["value" ':= Int64]

singleSchema :: TableSchema (PolyRow SingleRow Name)
singleSchema = TableSchema
  { name = "singles"
  , columns = Rel8.namesFromLabels
  }

singleRecord :: Record SingleRow
singleRecord = REC { value = 100 :: Int64 }

{-------------------------------------------------------------------------------
  Main Test Tree
-------------------------------------------------------------------------------}

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "polytropos-rel8"
  [ testGroup "Table Schema & Name Synthesis"
      [ testCase "namesFromLabels synthesizes column names from Symbol labels" $ do
          let TableSchema { columns = cols } = userSchema
              Name idCol = hfield (Field @"id") cols
              Name nameCol = hfield (Field @"name") cols
              Name activeCol = hfield (Field @"active") cols
          idCol @?= "id_1"
          nameCol @?= "name_2"
          activeCol @?= "active_3"

      , testCase "each userSchema generates SELECT query with column projections" $ do
          let q = T.pack (showQuery (each userSchema))
          assertBool "contains table name 'users'" (T.isInfixOf "users" q)
          assertBool "contains 'id_1'" (T.isInfixOf "id_1" q)
          assertBool "contains 'name_2'" (T.isInfixOf "name_2" q)
          assertBool "contains 'active_3'" (T.isInfixOf "active_3" q)
      ]

  , testGroup "Lifting & Query Generation"
      [ testCase "values with litRecord generates VALUES query" $ do
          let q = T.pack (showQuery (values [litRecord userRecord]))
          assertBool "contains 'VALUES'" (T.isInfixOf "VALUES" q)
          assertBool "contains '42'" (T.isInfixOf "42" q)
          assertBool "contains 'Alice'" (T.isInfixOf "Alice" q)
          assertBool "contains 'TRUE'" (T.isInfixOf "TRUE" q)

      , testCase "values with litPolyRow generates VALUES query" $ do
          let q = T.pack (showQuery (values [litPolyRow (fromRecord userRecord)]))
          assertBool "contains 'VALUES'" (T.isInfixOf "VALUES" q)
          assertBool "contains 'Alice'" (T.isInfixOf "Alice" q)
      ]

  , testGroup "Conversions & Roundtrips"
      [ testCase "toRecord . fromRecord is identity" $ do
          toRecord (fromRecord userRecord) @?= userRecord

      , testCase "columnsToRow . rowToColumns is identity" $ do
          columnsToRow (rowToColumns userRecord) @?= userRecord
      ]

  , testGroup "Columnar Combinators"
      [ testCase "hfield reads fields by type-level label" $ do
          let polyRes = fromRecord userRecord
          runIdentity (hfield (Field @"id") polyRes) @?= (42 :: Int64)
          runIdentity (hfield (Field @"name") polyRes) @?= ("Alice" :: Text)
          runIdentity (hfield (Field @"active") polyRes) @?= True

      , testCase "hfieldAt reads raw slots by slot index" $ do
          let polyRes = fromRecord userRecord
              val0 = unsafeCoerce (hfieldAt 0 polyRes) :: Identity Int64
              val1 = unsafeCoerce (hfieldAt 1 polyRes) :: Identity Text
              val2 = unsafeCoerce (hfieldAt 2 polyRes) :: Identity Bool
          runIdentity val0 @?= 42
          runIdentity val1 @?= "Alice"
          runIdentity val2 @?= True

      , testCase "htabulate constructs row from column indices" $ do
          let tab = htabulate @UserRow @(Const Int) (\i -> Const (i * 10))
              fId = hfield (Field @"id") tab :: Const Int Int64
              fName = hfield (Field @"name") tab :: Const Int Text
              fActive = hfield (Field @"active") tab :: Const Int Bool
          getConst fId @?= 0
          getConst fName @?= 10
          getConst fActive @?= 20

      , testCase "hmap maps natural transformation across columns" $ do
          let polyRes = fromRecord userRecord
              mappedId = hmap id polyRes
          toRecord mappedId @?= userRecord

          let constRow = hmap (\(Identity _) -> Const (99 :: Int)) polyRes
              fId = hfield (Field @"id") constRow :: Const Int Int64
          getConst fId @?= 99

      , testCase "htraverse traverses row with applicative" $ do
          let polyRes = fromRecord userRecord
              traversed = htraverse (\(Identity x) -> Identity (Identity x)) polyRes
          runIdentity traversed @?= polyRes

      , testCase "hzipWith combines columns slot-by-slot" $ do
          let polyRes = fromRecord userRecord
              zipped = hzipWith (\(Identity a) (Identity _) -> Identity a) polyRes polyRes
          zipped @?= polyRes
      ]

  , testGroup "Single-Column Row"
      [ testCase "single-column table schema and queries" $ do
          let TableSchema { columns = cols } = singleSchema
              Name valCol = hfield (Field @"value") cols
          valCol @?= "value_1"

          let qEach = T.pack (showQuery (each singleSchema))
          assertBool "contains 'singles'" (T.isInfixOf "singles" qEach)

          let qVal = T.pack (showQuery (values [litRecord singleRecord]))
          assertBool "contains '100'" (T.isInfixOf "100" qVal)
      ]
  ]
