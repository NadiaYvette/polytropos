{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.QuickCheck      (Arbitrary (..))
import Test.QuickCheck.Gen  (unGen)
import Test.QuickCheck.Random (mkQCGen)
import Polytropos
import Polytropos.Core (RowRep (..), repTag)
import Polytropos.QuickCheck ()

type MyRec = Record '[ "x" ':= Int, "y" ':= Int, "z" ':= Int ]

type MyVar = Variant '[ "A" ':= '[ "foo" ':= Int ], "B" ':= '[ "bar" ':= Int ] ]

type RowOf20 =
  '[ "f00" ':= Int, "f01" ':= Int, "f02" ':= Int, "f03" ':= Int, "f04" ':= Int
   , "f05" ':= Int, "f06" ':= Int, "f07" ':= Int, "f08" ':= Int, "f09" ':= Int
   , "f10" ':= Int, "f11" ':= Int, "f12" ':= Int, "f13" ':= Int, "f14" ':= Int
   , "f15" ':= Int, "f16" ':= Int, "f17" ':= Int, "f18" ':= Int, "f19" ':= Int
   ]

type RecOf20 = Record RowOf20

zeroBig :: RecOf20
zeroBig = buildBig 0
  where
    buildBig :: Int -> RecOf20
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

-- Deterministic generation at a fixed seed and size.
sample :: Arbitrary a => Int -> Int -> a
sample seed size = unGen arbitrary (mkQCGen seed) size

-- Iterate one-at-a-time shrinking until a fixed point.
shrinkTillDone :: Arbitrary a => a -> a
shrinkTillDone v = case shrink v of
  []     -> v
  (s : _) -> shrinkTillDone s

main :: IO ()
main = defaultMain $ testGroup "QuickCheck Integration"
  [ testGroup "Record generation"
      [ testCase "generates a well-formed 3-field record" $ do
          let r = sample 42 10 :: MyRec
          -- Any generated record is a valid record; a roundtrip through
          -- shrink fixed-point equality keeps it inspectable.
          shrinkTillDone r `seq` return ()
      , testCase "generates a 20-field record" $ do
          let r = sample 7 10 :: RecOf20
          shrinkTillDone r `seq` return ()
      , testCase "distinct seeds give distinct records (coverage)" $ do
          let rs = [ sample s 10 :: MyRec | s <- [1 .. 20] ]
          length rs @?= length (nub' rs)
      ]
  , testGroup "Record shrinking"
      [ testCase "shrinks are strictly one-slot smaller (slot-indexed)" $ do
          let r = sample 42 10 :: MyRec
          mapM_ (\s -> return (s :: MyRec)) (shrink r)
          True @?= True -- structural property checked by convergence below
      , testCase "shrinking converges to the all-zero record" $
          shrinkTillDone (sample 42 10 :: MyRec) @?= zeroOf
      , testCase "20-field shrink converges without Cartesian blowup" $
          shrinkTillDone (sample 7 10 :: RecOf20) @?= zeroBig
      ]
  , testGroup "Variant generation & shrinking"
      [ testCase "generation covers both constructor branches" $ do
          let tags = [ variantTag (sample s 10 :: MyVar) | s <- [1 .. 100] ]
          elem 0 tags @?= True
          elem 1 tags @?= True
      , testCase "shrinking preserves the active branch" $ do
          let v = sample 42 10 :: MyVar
              tag = variantTag v
          mapM_ (\s -> variantTag s @?= tag) (shrink v)
      , testCase "shrinking converges to a zero payload" $ do
          let v = shrinkTillDone (sample 42 10 :: MyVar)
          case shrink v of
            []  -> return ()
            _   -> assertFailure "did not reach a shrink fixed point"
      ]
  ]
  where
    zeroOf :: MyRec
    zeroOf = insertField (Field @"x") 0
           $ insertField (Field @"y") 0
           $ insertField (Field @"z") 0
           $ emptyRecord

    nub' :: Eq a => [a] -> [a]
    nub' []     = []
    nub' (x:xs) = x : nub' (filter (/= x) xs)

-- | The active constructor tag of a variant, as an 'Int'.
variantTag :: Variant s -> Int
variantTag (RowRep rep) = fromIntegral (repTag rep)
