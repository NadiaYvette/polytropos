{-# OPTIONS_GHC -Wno-orphans #-}
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Int (Int64)
import Data.Text (Text)
import Database.Persist (PersistField (..), PersistValue (..))
import Polytropos
import Polytropos.Core (Pair (..))
import Polytropos.Persistent

type MyRec = Record '[ "x" ':= Int, "y" ':= Int, "z" ':= Int ]

instance Eq MyRec where
  (==) = repEq
instance Show MyRec where
  showsPrec = repShowsPrec

-- Heterogeneous row: each field marshals through its own PersistField.
type Hetero = Record '[ "n" ':= Int, "b" ':= Bool, "w" ':= Int ]

instance Eq Hetero where
  (==) = repEq
instance Show Hetero where
  showsPrec = repShowsPrec

myRec :: MyRec
myRec = insertField (Field @"x") (1 :: Int)
      $ insertField (Field @"y") (2 :: Int)
      $ insertField (Field @"z") (3 :: Int)
      $ emptyRecord

heteroRec :: Hetero
heteroRec = insertField (Field @"n") (7 :: Int)
          $ insertField (Field @"b") True
          $ insertField (Field @"w") (9 :: Int)
          $ emptyRecord

type RowOf20 =
  '[ "f00" ':= Int, "f01" ':= Int, "f02" ':= Int, "f03" ':= Int, "f04" ':= Int
   , "f05" ':= Int, "f06" ':= Int, "f07" ':= Int, "f08" ':= Int, "f09" ':= Int
   , "f10" ':= Int, "f11" ':= Int, "f12" ':= Int, "f13" ':= Int, "f14" ':= Int
   , "f15" ':= Int, "f16" ':= Int, "f17" ':= Int, "f18" ':= Int, "f19" ':= Int
   ]

instance Eq (Record RowOf20) where
  (==) = repEq
instance Show (Record RowOf20) where
  showsPrec = repShowsPrec

buildBig :: Int -> Record RowOf20
buildBig n =
  insertField (Field @"f00") n
  $ insertField (Field @"f01") n
  $ insertField (Field @"f02") n
  $ insertField (Field @"f03") n
  $ insertField (Field @"f04") n
  $ insertField (Field @"f05") n
  $ insertField (Field @"f06") n
  $ insertField (Field @"f07") n
  $ insertField (Field @"f08") n
  $ insertField (Field @"f09") n
  $ insertField (Field @"f10") n
  $ insertField (Field @"f11") n
  $ insertField (Field @"f12") n
  $ insertField (Field @"f13") n
  $ insertField (Field @"f14") n
  $ insertField (Field @"f15") n
  $ insertField (Field @"f16") n
  $ insertField (Field @"f17") n
  $ insertField (Field @"f18") n
  $ insertField (Field @"f19") n
  $ emptyRecord

main :: IO ()
main = defaultMain $ testGroup "Persistent Integration"
  [ testGroup "PersistRow marshalling"
      [ testCase "roundtrip 3 fields" $
          fromPersistValuesRecord (toPersistFieldsRecord myRec)
            @?= Right myRec
      , testCase "roundtrip heterogeneous row" $
          fromPersistValuesRecord (toPersistFieldsRecord heteroRec)
            @?= Right heteroRec
      , testCase "roundtrip 20 fields" $ do
          let big = buildBig (42 :: Int)
          fromPersistValuesRecord (toPersistFieldsRecord big)
            @?= Right big
      , testCase "serializes fields in row order" $
          toPersistFieldsRecord myRec
            @?= [ PersistInt64 1, PersistInt64 2, PersistInt64 3 ]
      , testCase "rejects a short row" $
          case (fromPersistValuesRecord (take 2 (toPersistFieldsRecord myRec)) :: Either Text' MyRec) of
            Left _   -> return ()
            Right _  -> assertFailure "short row should not decode"
      , testCase "rejects a long row" $
          case (fromPersistValuesRecord (PersistInt64 9 : toPersistFieldsRecord myRec) :: Either Text' MyRec) of
            Left _   -> return ()
            Right _  -> assertFailure "long row should not decode"
      ]
  , testGroup "PersistField bridge"
      [ testCase "record roundtrips through PersistList" $ do
          let pv = toPersistValue myRec
          (fromPersistValue pv :: Either Text' MyRec) @?= Right myRec
      , testCase "non-list value is rejected" $
          case (fromPersistValue (PersistInt64 5) :: Either Text' MyRec) of
            Left _   -> return ()
            Right _  -> assertFailure "PersistInt64 should not decode as a record"
      ]
  , testGroup "Entity wrapper"
      [ testCase "entity row is key-then-fields" $ do
          let e = toPolyRowEntity (123 :: Int64) myRec
          fromPolyRowEntity e
            @?= (123 :: Int64, [ PersistInt64 123, PersistInt64 1, PersistInt64 2, PersistInt64 3 ])
      , testCase "entity roundtrip" $ do
          let e = toPolyRowEntity (77 :: Int64) myRec
          let (k, vs) = fromPolyRowEntity e
          k @?= polyRowKey e
          (fromPersistValuesRecord (drop 1 vs) :: Either Text' MyRec)
            @?= Right (polyRowRecord e)
      ]
  ]

type Text' = Text
