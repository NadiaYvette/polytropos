{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeAbstractions #-}

{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}

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

import Data.Functor.Identity (Identity(..))
import Data.Kind (Constraint, Type)
import Data.Primitive.SmallArray
import GHC.Exts (Any)
import Polytropos.Core
  ( DictAny(..)
  , Rep(..)
  , RowRep(..)
  , RowType(..)
  , AllFields(..)
  , noInlineUnsafeCo
  )

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
withDictEq d x y = case d of DictAny -> x == y

withDictOrd :: DictAny Ord -> Any -> Any -> Ordering
withDictOrd d x y = case d of DictAny -> compare x y

withDictShow :: DictAny Show -> Any -> Int -> ShowS
withDictShow d x p = case d of DictAny -> showsPrec p x

withDictMap :: DictAny c -> (forall x. c x => x -> x) -> Any -> Any
withDictMap d f x = case d of DictAny -> f x

withDictFoldMap :: DictAny c -> (forall x. c x => x -> m) -> Any -> m
withDictFoldMap d f x = case d of DictAny -> f x

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

{-------------------------------------------------------------------------------
  Generic and GInstances for RowRep (§1.7 Generic instance layer)
-------------------------------------------------------------------------------}

-- | RowRep is an instance of Generic for product rows.
instance Generic (RowRep Identity ProductRowT r a) where
  type RepOf (RowRep Identity ProductRowT r a) = Rep I (RowRep Identity ProductRowT r a)
  from (RowRep (Rep t v)) =
    let n = sizeofSmallArray v
        v' = runSmallArray $ do
          m <- newSmallArray n (error "Polytropos.Generics.from: uninitialized")
          let loop i
                | i == n = pure ()
                | otherwise = do
                    let Identity val = indexSmallArray v i
                    writeSmallArray m i (I val)
                    loop (i + 1)
          loop 0
          pure m
    in Rep t v'
  to (Rep t v) =
    let n = sizeofSmallArray v
        v' = runSmallArray $ do
          m <- newSmallArray n (error "Polytropos.Generics.to: uninitialized")
          let loop i
                | i == n = pure ()
                | otherwise = do
                    let I val = indexSmallArray v i
                    writeSmallArray m i (Identity val)
                    loop (i + 1)
          loop 0
          pure m
    in RowRep (Rep t v')

-- | RowRep is an instance of Generic for HKD product rows.
instance Generic (RowRep f ProductRowHKDT r a) where
  type RepOf (RowRep f ProductRowHKDT r a) = Rep I (RowRep f ProductRowHKDT r a)
  from (RowRep (Rep t v)) =
    let n = sizeofSmallArray v
        v' = runSmallArray $ do
          m <- newSmallArray n (error "Polytropos.Generics.fromHKD: uninitialized")
          let loop i
                | i == n = pure ()
                | otherwise = do
                    let val = indexSmallArray v i
                    writeSmallArray m i (I (noInlineUnsafeCo val :: Any))
                    loop (i + 1)
          loop 0
          pure m
    in Rep t v'
  to (Rep t v) =
    let n = sizeofSmallArray v
        v' = runSmallArray $ do
          m <- newSmallArray n (error "Polytropos.Generics.toHKD: uninitialized")
          let loop i
                | i == n = pure ()
                | otherwise = do
                    let I val = indexSmallArray v i
                    writeSmallArray m i (noInlineUnsafeCo val :: f Any)
                    loop (i + 1)
          loop 0
          pure m
    in RowRep (Rep t v')

-- | RowRep is an instance of Generic for sum rows.
instance Generic (RowRep f SumRowT s a) where
  type RepOf (RowRep f SumRowT s a) = Rep I (RowRep f SumRowT s a)
  from (RowRep r) = noInlineUnsafeCo r
  to rep          = RowRep (noInlineUnsafeCo rep)

-- | RowRep is an instance of Generic for HKD sum rows.
instance Generic (RowRep f SumRowHKDT s a) where
  type RepOf (RowRep f SumRowHKDT s a) = Rep I (RowRep f SumRowHKDT s a)
  from (RowRep r) = noInlineUnsafeCo r
  to rep          = RowRep (noInlineUnsafeCo rep)

-- | GInstances for ProductRowT derived from AllFields.
instance AllFields ProductRowT r c => GInstances c (RowRep Identity ProductRowT r a) where
  gdicts = smallArrayFromList [fieldDicts @ProductRowT @r @c]

-- | GInstances for ProductRowHKDT derived from AllFields.
instance AllFields ProductRowHKDT r c => GInstances c (RowRep f ProductRowHKDT r a) where
  gdicts = smallArrayFromList [fieldDicts @ProductRowHKDT @r @c]
