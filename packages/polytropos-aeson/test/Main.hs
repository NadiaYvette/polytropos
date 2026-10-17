{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Aeson (encode, decode)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8 (pack)
import Polytropos
import Polytropos.Aeson ()

type MyRec = Record '["x" ':= Int, "y" ':= Int, "z" ':= Int]
type MyVar = Variant '["A" ':= '["foo" ':= Int], "B" ':= '["bar" ':= Int]]

myRec :: MyRec
myRec = REC { x = 1, y = 2, z = 3 }

varA :: MyVar
varA = Variant (Field @"A") (REC { foo = 42 :: Int })

varB :: MyVar
varB = Variant (Field @"B") (REC { bar = 7 :: Int })

type HeteroRec = Record '["host" ':= String, "port" ':= Int, "active" ':= Bool, "weight" ':= Double]
heteroRec :: HeteroRec
heteroRec = REC { host = "localhost", port = 8080, active = True, weight = 1.75 }

type HeteroVar = Variant '["Msg" ':= '["text" ':= String, "priority" ':= Int], "Ping" ':= '[]]
heteroVar1 :: HeteroVar
heteroVar1 = Variant (Field @"Msg") (REC { text = "alert", priority = 1 })

heteroVar2 :: HeteroVar
heteroVar2 = Variant (Field @"Ping") emptyRecord

type RowOf20 =
  '[ "f00" ':= Int, "f01" ':= Int, "f02" ':= Int, "f03" ':= Int, "f04" ':= Int
   , "f05" ':= Int, "f06" ':= Int, "f07" ':= Int, "f08" ':= Int, "f09" ':= Int
   , "f10" ':= Int, "f11" ':= Int, "f12" ':= Int, "f13" ':= Int, "f14" ':= Int
   , "f15" ':= Int, "f16" ':= Int, "f17" ':= Int, "f18" ':= Int, "f19" ':= Int
   ]

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
      , testCase "roundtrip heterogeneous 4 fields" $
          (decode (encode heteroRec) :: Maybe HeteroRec) @?= Just heteroRec
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
      , testCase "roundtrip heterogeneous Msg" $
          (decode (encode heteroVar1) :: Maybe HeteroVar) @?= Just heteroVar1
      , testCase "roundtrip heterogeneous empty Ping" $
          (decode (encode heteroVar2) :: Maybe HeteroVar) @?= Just heteroVar2
      , testCase "encodes tagged shape" $
          LBS.toStrict (encode varA) @?= BS8.pack "{\"A\":{\"foo\":42}}"
      ]
  ]
