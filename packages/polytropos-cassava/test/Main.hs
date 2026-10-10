{-# OPTIONS_GHC -Wno-orphans #-}
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Vector as V
import Data.Csv (decodeByName, encodeByName, header)
import Polytropos
import Polytropos.Cassava ()

type MyRec = Record '[ "x" ':= Int, "y" ':= Int, "z" ':= Int ]

-- A heterogeneous row: each field uses its own ToField/FromField instance.
type Hetero = Record '[ "n" ':= Int, "w" ':= Word, "m" ':= Int ]

myRec :: MyRec
myRec = insertField (Field @"x") (1 :: Int)
      $ insertField (Field @"y") (2 :: Int)
      $ insertField (Field @"z") (3 :: Int)
      $ emptyRecord

heteroRec :: Hetero
heteroRec = insertField (Field @"n") (7 :: Int)
          $ insertField (Field @"w") (9 :: Word)
          $ insertField (Field @"m") (11 :: Int)
          $ emptyRecord

type RowOf12 =
  '[ "c00" ':= Int, "c01" ':= Int, "c02" ':= Int, "c03" ':= Int
   , "c04" ':= Int, "c05" ':= Int, "c06" ':= Int, "c07" ':= Int
   , "c08" ':= Int, "c09" ':= Int, "c10" ':= Int, "c11" ':= Int
   ]

buildWide :: Int -> Record RowOf12
buildWide n =
  insertField (Field @"c00") n
  $ insertField (Field @"c01") n
  $ insertField (Field @"c02") n
  $ insertField (Field @"c03") n
  $ insertField (Field @"c04") n
  $ insertField (Field @"c05") n
  $ insertField (Field @"c06") n
  $ insertField (Field @"c07") n
  $ insertField (Field @"c08") n
  $ insertField (Field @"c09") n
  $ insertField (Field @"c10") n
  $ insertField (Field @"c11") n
  $ emptyRecord

recNames :: [BS8.ByteString]
recNames = map BS8.pack ["x", "y", "z"]

wideNames :: [BS8.ByteString]
wideNames = map BS8.pack ["c00","c01","c02","c03","c04","c05","c06","c07","c08","c09","c10","c11"]

heteroNames :: [BS8.ByteString]
heteroNames = map BS8.pack ["n", "w", "m"]

main :: IO ()
main = defaultMain $ testGroup "Cassava Integration"
  [ testGroup "Named record codecs"
      [ testCase "roundtrip 3 fields" $
          decodeByName (encodeByName (header recNames) [myRec])
            @?= Right (header recNames, V.singleton myRec)
      , testCase "roundtrip 12 fields" $ do
          let wide = buildWide (42 :: Int)
          decodeByName (encodeByName (header wideNames) [wide])
            @?= Right (header wideNames, V.singleton wide)
      , testCase "heterogeneous row roundtrip" $
          decodeByName (encodeByName (header heteroNames) [heteroRec])
            @?= Right (header heteroNames, V.singleton heteroRec)
      , testCase "encodes header + row shape" $
          LBS.toStrict (encodeByName (header recNames) [myRec])
            @?= BS8.pack "x,y,z\r\n1,2,3\r\n"
      ]
  ]
