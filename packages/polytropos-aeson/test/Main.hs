{-# OPTIONS_GHC -Wno-orphans #-}
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Aeson (encode, decode)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8 (pack)
import Polytropos
import Polytropos.Core (Pair (..), RowEqSum (..), RowShowSum (..))
import Polytropos.Aeson ()

type MyRec = Record '["x" ':= Int, "y" ':= Int, "z" ':= Int]
type MyVar = Variant '["A" ':= '["foo" ':= Int], "B" ':= '["bar" ':= Int]]

instance Eq MyRec where
  (==) = repEq
instance Show MyRec where
  showsPrec = repShowsPrec

instance Eq (Record '[]) where
  (==) = repEq
instance Show (Record '[]) where
  showsPrec = repShowsPrec

instance Eq MyVar where
  (==) = repEqSum
instance Show MyVar where
  showsPrec = repShowsPrecSum

instance Eq (Record '["foo" ':= Int]) where
  (==) = repEq
instance Show (Record '["foo" ':= Int]) where
  showsPrec = repShowsPrec

instance Eq (Record '["bar" ':= Int]) where
  (==) = repEq
instance Show (Record '["bar" ':= Int]) where
  showsPrec = repShowsPrec

myRec :: MyRec
myRec = insertField (Field @"x") (1 :: Int)
      $ insertField (Field @"y") (2 :: Int)
      $ insertField (Field @"z") (3 :: Int)
      $ emptyRecord

varA :: MyVar
varA = Variant (Field @"A") (insertField (Field @"foo") (42 :: Int) emptyRecord)

varB :: MyVar
varB = Variant (Field @"B") (insertField (Field @"bar") (7 :: Int) emptyRecord)

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
main = defaultMain $ testGroup "Aeson Integration"
  [ testGroup "Record codecs"
      [ testCase "roundtrip 3 fields" $
          (decode (encode myRec) :: Maybe MyRec) @?= Just myRec
      , testCase "roundtrip empty record" $
          (decode (encode (emptyRecord :: Record '[])))
            @?= (Just emptyRecord :: Maybe (Record '[]))
      , testCase "roundtrip 20 fields" $ do
          let big = buildBig (42 :: Int)
          (decode (encode big) :: Maybe (Record RowOf20)) @?= Just big
      , testCase "encodes row order" $
          LBS.toStrict (encode myRec) @?= BS8.pack "{\"x\":1,\"y\":2,\"z\":3}"
      ]
  , testGroup "Variant codecs"
      [ testCase "roundtrip A" $
          (decode (encode varA) :: Maybe MyVar) @?= Just varA
      , testCase "roundtrip B" $
          (decode (encode varB) :: Maybe MyVar) @?= Just varB
      , testCase "encodes tagged shape" $
          LBS.toStrict (encode varA) @?= BS8.pack "{\"A\":{\"foo\":42}}"
      ]
  ]
