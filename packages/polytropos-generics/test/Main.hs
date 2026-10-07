{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Primitive.SmallArray
import Unsafe.Coerce (unsafeCoerce)

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
    [ smallArrayFromList [DictAny @Eq @String, DictAny @Eq @Int]
    ]

instance GInstances Show Person where
  gdicts = smallArrayFromList
    [ smallArrayFromList [DictAny @Show @String, DictAny @Show @Int]
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
    [ smallArrayFromList [DictAny @Eq @Double]
    , smallArrayFromList [DictAny @Eq @Double, DictAny @Eq @Double]
    ]

instance GInstances Show Shape where
  gdicts = smallArrayFromList
    [ smallArrayFromList [DictAny @Show @Double]
    , smallArrayFromList [DictAny @Show @Double, DictAny @Show @Double]
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
  ]
