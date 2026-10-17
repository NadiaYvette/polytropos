{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Tests for the polytropos-cbor satellite. The plugin solves the
-- RowEq/RowShow/RowEqSum/RowShowSum constraints below as literals. Format
-- assertions pin the positional binary shape (length header, tag, slots).
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Codec.Serialise (serialise, deserialise)
import qualified Codec.CBOR.Encoding as E
import qualified Codec.CBOR.Write as W
import Polytropos
import Polytropos.CBOR ()

type MyRec = Record '["x" ':= Int, "y" ':= Int, "z" ':= Int]
type MyVar = Variant '["A" ':= '["foo" ':= Int], "B" ':= '["bar" ':= Int]]

myRec :: MyRec
myRec = REC { x = 1, y = 2, z = 3 }

varA :: MyVar
varA = Variant (Field @"A") (REC { foo = 42 :: Int })

varB :: MyVar
varB = Variant (Field @"B") (REC { bar = 7 :: Int })

type HeteroRec = Record '["id" ':= Int, "name" ':= String, "flag" ':= Bool]
heteroRec :: HeteroRec
heteroRec = REC { id = 42, name = "test", flag = True }

type HeteroVar = Variant '["Msg" ':= '["text" ':= String, "code" ':= Int], "Ping" ':= '[]]
heteroVar1 :: HeteroVar
heteroVar1 = Variant (Field @"Msg") (REC { text = "hi", code = 7 })

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
main = defaultMain $ testGroup "CBOR Integration"
  [ testGroup "Record codecs"
      [ testCase "roundtrip 3 fields" $
          (deserialise (serialise myRec) :: MyRec) @?= myRec
      , testCase "roundtrip heterogeneous 3 fields" $
          (deserialise (serialise heteroRec) :: HeteroRec) @?= heteroRec
      , testCase "roundtrip 20 fields" $ do
          let big = buildBig (42 :: Int)
          (deserialise (serialise big) :: Record RowOf20) @?= big
      , testCase "encodes as length header + flat payload" $
          serialise myRec
            @?= W.toLazyByteString
                  (E.encodeListLen 3 <> E.encodeInt 1 <> E.encodeInt 2 <> E.encodeInt 3)
      ]
  , testGroup "Variant codecs"
      [ testCase "roundtrip A" $ (deserialise (serialise varA) :: MyVar) @?= varA
      , testCase "roundtrip B" $ (deserialise (serialise varB) :: MyVar) @?= varB
      , testCase "roundtrip heterogeneous Msg" $
          (deserialise (serialise heteroVar1) :: HeteroVar) @?= heteroVar1
      , testCase "roundtrip heterogeneous empty Ping" $
          (deserialise (serialise heteroVar2) :: HeteroVar) @?= heteroVar2
      , testCase "encodes as tag + payload" $
          serialise varA
            @?= W.toLazyByteString
                  (E.encodeListLen 2 <> E.encodeWord 0 <> E.encodeInt 42)
      ]
  ]
