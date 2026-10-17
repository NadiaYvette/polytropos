{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Tests for the polytropos-microlens satellite. The plugin solves the
-- FieldIndex and RowEq/RowShow constraints below as literals; the @each@
-- tests exercise the homogeneity-gated traversal.
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Lens.Micro ((&), (.~), (^.), (^..), (%~), each)
import Polytropos
import Polytropos.Microlens

type MyRec = Record '["x" ':= Int, "y" ':= Int, "z" ':= Int]

myRec :: MyRec
myRec = REC { x = 1, y = 2, z = 3 }

main :: IO ()
main = defaultMain $ testGroup "Microlens Integration"
  [ testGroup "each"
      [ testCase "modifies all fields" $
          (myRec & each %~ (+ (1 :: Int)))
            @?= (insertField (Field @"x") (2 :: Int)
              $ insertField (Field @"y") (3 :: Int)
              $ insertField (Field @"z") (4 :: Int)
              $ emptyRecord)
      , testCase "views all fields" $ do
          (myRec ^.. each) @?= [1 :: Int, 2, 3]
      ]
  , testGroup "fieldLens"
      [ testCase "views by field name" $ do
          (myRec ^. fieldLens #x) @?= (1 :: Int)
          (myRec ^. fieldLens #y) @?= (2 :: Int)
          (myRec ^. fieldLens #z) @?= (3 :: Int)
      , testCase "sets by field name" $ do
          let r' = myRec & fieldLens #z .~ (9 :: Int)
          (r' ^. fieldLens #z) @?= (9 :: Int)
          (r' ^. fieldLens #x) @?= (1 :: Int)
      , testCase "modifies by field name" $ do
          let r' = myRec & fieldLens #y %~ (* (10 :: Int))
          (r' ^. fieldLens #y) @?= (20 :: Int)
      ]
  ]
