{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Tests for the polytropos-lens satellite. The plugin solves the
-- FieldIndex, ConstructorIndex, RowEq/RowShow and RowEqSum/RowShowSum
-- constraints below as literals.
module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Control.Lens ((&), (.~), (^.), (^..), (^?), (%~), at, each, ix, preview,
                     review, (?~), _1, _2, _3)
import Polytropos
import Polytropos.Core (Pair (..), RowEqSum (..), RowShowSum (..))
import Polytropos.Lens

type MyRec = Record '["x" ':= Int, "y" ':= Bool, "z" ':= Bool]
type HomRec = Record '["x" ':= Int, "y" ':= Int, "z" ':= Int]
type MyVar = Variant '["A" ':= '["foo" ':= Int], "B" ':= '["bar" ':= Bool]]

instance Eq MyRec where
  (==) = repEq
instance Show MyRec where
  showsPrec = repShowsPrec

instance Eq HomRec where
  (==) = repEq
instance Show HomRec where
  showsPrec = repShowsPrec

instance Eq MyVar where
  (==) = repEqSum
instance Show MyVar where
  showsPrec = repShowsPrecSum

instance Eq (Record '["foo" ':= Int]) where
  (==) = repEq
instance Show (Record '["foo" ':= Int]) where
  showsPrec = repShowsPrec

instance Eq (Record '["bar" ':= Bool]) where
  (==) = repEq
instance Show (Record '["bar" ':= Bool]) where
  showsPrec = repShowsPrec

myRec :: MyRec
myRec = insertField (Field @"x") (42 :: Int)
      $ insertField (Field @"y") True
      $ insertField (Field @"z") False
      $ emptyRecord

homRec :: HomRec
homRec = insertField (Field @"x") (1 :: Int)
       $ insertField (Field @"y") (2 :: Int)
       $ insertField (Field @"z") (3 :: Int)
       $ emptyRecord

varA :: MyVar
varA = Variant (Field @"A") (insertField (Field @"foo") (42 :: Int) emptyRecord)

varB :: MyVar
varB = Variant (Field @"B") (insertField (Field @"bar") False emptyRecord)

main :: IO ()
main = defaultMain $ testGroup "Lens Integration"
  [ testGroup "positional lenses"
      [ testCase "view _1, _2, _3" $ do
          (myRec ^. _1) @?= (42 :: Int)
          (myRec ^. _2) @?= True
          (myRec ^. _3) @?= False
      , testCase "set _1" $ do
          let r' = myRec & _1 .~ (100 :: Int)
          (r' ^. _1) @?= (100 :: Int)
          (r' ^. _2) @?= True
      , testCase "over _2" $
          ((myRec & _2 %~ not) ^. _2) @?= False
      ]
  , testGroup "each"
      [ testCase "modifies all fields" $
          (homRec & each %~ (+ (1 :: Int)))
            @?= (insertField (Field @"x") (2 :: Int)
              $ insertField (Field @"y") (3 :: Int)
              $ insertField (Field @"z") (4 :: Int)
              $ emptyRecord)
      , testCase "views all fields" $
          (homRec ^.. each) @?= [1 :: Int, 2, 3]
      ]
  , testGroup "At and Ixed"
      [ testCase "ix views by name" $ do
          (homRec ^? ix "x") @?= (Just (1 :: Int))
          (homRec ^? ix "z") @?= (Just (3 :: Int))
          (homRec ^? ix "nope") @?= (Nothing :: Maybe Int)
      , testCase "at views by name" $ do
          (homRec ^. at "y") @?= (Just (2 :: Int))
          (homRec ^. at "nope") @?= (Nothing :: Maybe Int)
      , testCase "at sets existing field" $ do
          let r' = homRec & at "y" ?~ (9 :: Int)
          (r' ^. at "y") @?= (Just (9 :: Int))
          (r' ^. at "x") @?= (Just (1 :: Int))
      , testCase "ix sets existing field" $ do
          let r' = homRec & ix "z" .~ (7 :: Int)
          (r' ^? ix "z") @?= (Just (7 :: Int))
      ]
  , testGroup "fieldLens"
      [ testCase "views by field name" $ do
          (myRec ^. fieldLens #x) @?= (42 :: Int)
          (myRec ^. fieldLens #z) @?= False
      , testCase "sets by field name" $
          ((myRec & fieldLens #x .~ (7 :: Int)) ^. fieldLens #x) @?= (7 :: Int)
      ]
  , testGroup "variant prisms"
      [ testCase "prism matches A" $ do
          preview (prismVariant (Field @"A")) varA
            @?= Just (insertField (Field @"foo") (42 :: Int) emptyRecord)
          preview (prismVariant (Field @"A")) varB
            @?= (Nothing :: Maybe (Record '["foo" ':= Int]))
      , testCase "prism matches B" $
          preview (prismVariant (Field @"B")) varB
            @?= Just (insertField (Field @"bar") False emptyRecord)
      , testCase "prism inject roundtrip" $
          review (prismVariant (Field @"A"))
                 (insertField (Field @"foo") (42 :: Int) emptyRecord)
            @?= varA
      ]
  ]
