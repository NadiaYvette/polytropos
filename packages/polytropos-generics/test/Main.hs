{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedLabels #-}

module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Functor.Identity (Identity(..))
import Data.Primitive.SmallArray
import Unsafe.Coerce (unsafeCoerce)

import Polytropos
import Polytropos.Core
import Polytropos.Generics

-- A sample product ADT
data Person = Person String Int
  deriving (Show, Eq)

instance Generic Person where
  type RepOf Person = Rep I Person
  from (Person n a) = Rep 0 (smallArrayFromList [I (unsafeCoerce n), I (unsafeCoerce a)])
  to (Rep _ arr) =
    let I n = indexSmallArray arr 0
        I a = indexSmallArray arr 1
    in Person (unsafeCoerce n) (unsafeCoerce a)

instance GInstances Eq Person where
  gdicts = smallArrayFromList
    [ smallArrayFromList [mkDictAny @Eq @String, mkDictAny @Eq @Int]
    ]

instance GInstances Show Person where
  gdicts = smallArrayFromList
    [ smallArrayFromList [mkDictAny @Show @String, mkDictAny @Show @Int]
    ]

-- A sample sum ADT
data Shape = Circle Double | Rectangle Double Double
  deriving (Show, Eq)

instance Generic Shape where
  type RepOf Shape = Rep I Shape
  from (Circle r) = Rep 0 (smallArrayFromList [I (unsafeCoerce r)])
  from (Rectangle w h) = Rep 1 (smallArrayFromList [I (unsafeCoerce w), I (unsafeCoerce h)])
  to (Rep t arr) = case t of
    0 -> let I r = indexSmallArray arr 0 in Circle (unsafeCoerce r)
    1 -> let I w = indexSmallArray arr 0; I h = indexSmallArray arr 1 in Rectangle (unsafeCoerce w) (unsafeCoerce h)
    _ -> error "invalid tag"

instance GInstances Eq Shape where
  gdicts = smallArrayFromList
    [ smallArrayFromList [mkDictAny @Eq @Double]
    , smallArrayFromList [mkDictAny @Eq @Double, mkDictAny @Eq @Double]
    ]

instance GInstances Show Shape where
  gdicts = smallArrayFromList
    [ smallArrayFromList [mkDictAny @Show @Double]
    , smallArrayFromList [mkDictAny @Show @Double, mkDictAny @Show @Double]
    ]

-- Tests
main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Generics Tests"
  [ testGroup "Person (Product)"
      [ testCase "Roundtrip" $ do
          let p = Person "Alice" 30
          to (from p) @?= p
      , testCase "geq" $ do
          let p1 = Person "Alice" 30
              p2 = Person "Alice" 30
              p3 = Person "Bob" 30
          geq p1 p2 @?= True
          geq p1 p3 @?= False
      , testCase "gshowsPrec" $ do
          let p = Person "Alice" 30
          -- gshowsPrec shows "Constructor 0 \"Alice\" 30" (due to default implementation)
          gshowsPrec 0 p "" @?= "Constructor 0 \"Alice\" 30"
      ]
  , testGroup "Shape (Sum)"
      [ testCase "Roundtrip" $ do
          let c = Circle 5.5
              r = Rectangle 4.0 2.0
          to (from c) @?= c
          to (from r) @?= r
      , testCase "geq" $ do
          let c1 = Circle 5.5
              c2 = Circle 5.5
              c3 = Circle 6.0
              r1 = Rectangle 4.0 2.0
          geq c1 c2 @?= True
          geq c1 c3 @?= False
          geq c1 (unsafeCoerce r1) @?= False
      , testCase "gshowsPrec" $ do
          let c = Circle 5.5
              r = Rectangle 4.0 2.0
          gshowsPrec 0 c "" @?= "Constructor 0 5.5"
          gshowsPrec 0 r "" @?= "Constructor 1 4.0 2.0"
      ]
  , testGroup "RowRep Product Record (via Plugin AllFields)"
      [ testCase "geq on Record" $ do
          let r1 = insertField (Field @"name") ("Alice" :: String)
                 $ insertField (Field @"age") (30 :: Int)
                 $ emptyRecord
              r2 = insertField (Field @"name") ("Alice" :: String)
                 $ insertField (Field @"age") (30 :: Int)
                 $ emptyRecord
              r3 = insertField (Field @"name") ("Bob" :: String)
                 $ insertField (Field @"age") (25 :: Int)
                 $ emptyRecord
          geq r1 r2 @?= True
          geq r1 r3 @?= False
      , testCase "gcompare on Record" $ do
          let r1 = insertField (Field @"x") (10 :: Int)
                 $ insertField (Field @"y") (20 :: Int)
                 $ emptyRecord
              r2 = insertField (Field @"x") (10 :: Int)
                 $ insertField (Field @"y") (30 :: Int)
                 $ emptyRecord
          gcompare r1 r1 @?= EQ
          gcompare r1 r2 @?= LT
          gcompare r2 r1 @?= GT
      , testCase "gshowsPrec on Record" $ do
          let r = insertField (Field @"x") (10 :: Int)
                $ insertField (Field @"y") True
                $ emptyRecord
          gshowsPrec 0 r "" @?= "Constructor 0 10 True"
      , testCase "gmap on Record" $ do
          let r = insertField (Field @"a") (10 :: Int)
                $ insertField (Field @"b") (20 :: Int)
                $ emptyRecord
              r' = gmap @Num (\x -> x * 2) r
          let (Identity a) = indexSmallArray (repVals (unRowRep r')) 0
              (Identity b) = indexSmallArray (repVals (unRowRep r')) 1
          (unsafeCoerce a :: Int) @?= 20
          (unsafeCoerce b :: Int) @?= 40
      , testCase "gfoldMap on Record" $ do
          let r = insertField (Field @"a") ("hello" :: String)
                $ insertField (Field @"b") ("world" :: String)
                $ emptyRecord
              total = gfoldMap @Show (\x -> show x ++ ";") r
          total @?= "\"hello\";\"world\";"
      ]
  , testGroup "RowRep HKD Record (RecordF Maybe)"
      [ testCase "geq on RecordF" $ do
          let r1 = insertFieldF (Field @"code") (Just (200 :: Int))
                 $ insertFieldF (Field @"msg") (Just ("ok" :: String))
                 $ emptyRecordF
              r2 = insertFieldF (Field @"code") (Just (200 :: Int))
                 $ insertFieldF (Field @"msg") (Just ("ok" :: String))
                 $ emptyRecordF
              r3 = insertFieldF (Field @"code") (Nothing :: Maybe Int)
                 $ insertFieldF (Field @"msg") (Just ("ok" :: String))
                 $ emptyRecordF
          geq r1 r2 @?= True
          geq r1 r3 @?= False
      , testCase "gshowsPrec on RecordF" $ do
          let r = insertFieldF (Field @"code") (Just (200 :: Int))
                $ insertFieldF (Field @"msg") (Just ("ok" :: String))
                $ emptyRecordF
          gshowsPrec 0 r "" @?= "Constructor 0 (Just 200) (Just \"ok\")"
      ]
  ]
