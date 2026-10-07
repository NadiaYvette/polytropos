{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeAbstractions #-}

module Polytropos.Generics (
    Generic(..)
  , I(..)
  , GInstances(..)
  , geq
  , gcompare
  , gshowsPrec
  , gmap
  , gfoldMap
  ) where

import Data.Kind (Constraint, Type)
import Data.Primitive.SmallArray
import GHC.Exts (Any)
import Polytropos.Core (DictAny(..), Rep(..))
import Unsafe.Coerce (unsafeCoerce)

-- | Identity functor for use with 'Rep'.
newtype I a = I { unI :: a }

-- | Generic conversion class. Bridges nominal ADTs to 'Rep'.
class Generic a where
  type RepOf a :: Type
  from :: a -> RepOf a
  to   :: RepOf a -> a

-- | Provides an array of constraint dictionaries for each constructor of 'a',
-- and for each field within that constructor.
class GInstances (c :: Type -> Constraint) a where
  gdicts :: SmallArray (SmallArray (DictAny c))

-- CPS helpers to avoid ambiguity
withDictEq :: DictAny Eq -> Any -> Any -> Bool
withDictEq d x y = case d of (DictAny @_ @t) -> (unsafeCoerce x :: t) == (unsafeCoerce y :: t)

withDictOrd :: DictAny Ord -> Any -> Any -> Ordering
withDictOrd d x y = case d of (DictAny @_ @t) -> compare (unsafeCoerce x :: t) (unsafeCoerce y :: t)

withDictShow :: DictAny Show -> Any -> Int -> ShowS
withDictShow d x p = case d of (DictAny @_ @t) -> showsPrec p (unsafeCoerce x :: t)

withDictMap :: DictAny c -> (forall x. c x => x -> x) -> Any -> Any
withDictMap d f x = case d of (DictAny @_ @t) -> unsafeCoerce @t @Any (f @t (unsafeCoerce @Any @t x))

withDictFoldMap :: DictAny c -> (forall x. c x => x -> m) -> Any -> m
withDictFoldMap d f x = case d of (DictAny @_ @t) -> f @t (unsafeCoerce @Any @t x)

-- | Generic equality using the 'Eq' class.
geq :: forall a. (Generic a, RepOf a ~ Rep I a, GInstances Eq a) => a -> a -> Bool
geq x y =
  let Rep tx vx = from x
      Rep ty vy = from y
  in tx == ty &&
     let dicts = indexSmallArray (gdicts @Eq @a) (fromIntegral tx)
     in loop dicts vx vy 0 (sizeofSmallArray vx)
  where
    loop dicts vx vy i n
      | i == n = True
      | otherwise =
          let d = indexSmallArray dicts i
              I vx_i = indexSmallArray vx i
              I vy_i = indexSmallArray vy i
          in withDictEq d vx_i vy_i && loop dicts vx vy (i + 1) n

-- | Generic comparison using the 'Ord' class.
gcompare :: forall a. (Generic a, RepOf a ~ Rep I a, GInstances Ord a) => a -> a -> Ordering
gcompare x y =
  let Rep tx vx = from x
      Rep ty vy = from y
  in compare tx ty <>
     let dicts = indexSmallArray (gdicts @Ord @a) (fromIntegral tx)
     in loop dicts vx vy 0 (sizeofSmallArray vx)
  where
    loop dicts vx vy i n
      | i == n = EQ
      | otherwise =
          let d = indexSmallArray dicts i
              I vx_i = indexSmallArray vx i
              I vy_i = indexSmallArray vy i
              c = withDictOrd d vx_i vy_i
          in case c of
               EQ -> loop dicts vx vy (i + 1) n
               _  -> c

-- | Generic showsPrec using the 'Show' class.
gshowsPrec :: forall a. (Generic a, RepOf a ~ Rep I a, GInstances Show a) => Int -> a -> ShowS
gshowsPrec p x =
  let Rep tx vx = from x
      dicts = indexSmallArray (gdicts @Show @a) (fromIntegral tx)
  in showParen (p > 10 && sizeofSmallArray vx > 0) $
       showString "Constructor " . shows tx . loop dicts vx 0 (sizeofSmallArray vx)
  where
    loop dicts vx i n
      | i == n = id
      | otherwise =
          let d = indexSmallArray dicts i
              I vx_i = indexSmallArray vx i
          in showString " " . withDictShow d vx_i 11 . loop dicts vx (i + 1) n

-- | Generic map over all fields.
gmap :: forall c a. (Generic a, RepOf a ~ Rep I a, GInstances c a) => (forall x. c x => x -> x) -> a -> a
gmap f x =
  let Rep tx vx = from x
      dicts = indexSmallArray (gdicts @c @a) (fromIntegral tx)
      n = sizeofSmallArray vx
      vx' = runSmallArray $ do
        m <- thawSmallArray vx 0 n
        let loop i
              | i == n = pure ()
              | otherwise = do
                  let d = indexSmallArray dicts i
                  let I vx_i = indexSmallArray vx i
                  writeSmallArray m i (I (withDictMap d f vx_i))
                  loop (i + 1)
        loop 0
        pure m
  in to (Rep tx vx')

-- | Generic foldMap over all fields.
gfoldMap :: forall c a m. (Generic a, RepOf a ~ Rep I a, GInstances c a, Monoid m) => (forall x. c x => x -> m) -> a -> m
gfoldMap f x =
  let Rep tx vx = from x
      dicts = indexSmallArray (gdicts @c @a) (fromIntegral tx)
  in loop dicts vx 0 (sizeofSmallArray vx)
  where
    loop dicts vx i n
      | i == n = mempty
      | otherwise =
          let d = indexSmallArray dicts i
              I vx_i = indexSmallArray vx i
          in withDictFoldMap d f vx_i <> loop dicts vx (i + 1) n
