{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}

{-|
Module      : Polytropos.Generics
Description : Generic deriving, representation bridging, and whole-data traversal for Polytropos
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Generic deriving, representation bridging, and structural traversal engine for
@polytropos@.

This module bridges nominal Haskell algebraic data types (ADTs) to and from the
unified flat representation @t'Polytropos.Core.Rep'@, and provides zero-overhead
structural operations (@'geq'@, @'gcompare'@, @'gshowsPrec'@, @'gmap'@, @'gfoldMap'@)
across both open rows (@t'RowRep'@, @Record@, @Variant@) and nominal types.

= Architectural Overview & Rationale

== Why does @polytropos-generics@ resemble built-in "GHC.Generics" rather than @large-generics@?

=== 1. Unified Sums and Products vs. Records-Only

Libraries such as @large-generics@ (@Data.Record.Generic@) are strictly
single-constructor /record/ (product) libraries. Their representation
@Rep f a = Rep (SmallArray (f Any))@ lacks a constructor tag entirely,
preventing them from representing sum types, variants, or multi-constructor ADTs.
Furthermore, their dictionary abstraction @dict :: Proxy c -> Rep (Dict c) a@
is a 1D vector corresponding only to the fields of that single constructor.

In contrast, @polytropos@ collapses products and sums into a single uniform mechanism:

@
data Rep (f :: Type -> Type) a = Rep {-# UNPACK #-} !Word !(SmallArray (f Any))
@

* In a product (record), the constructor tag is @0@, and the array carries all fields.
* In a sum (variant), the constructor tag corresponds to the constructor index, and the
  array carries that constructor's payloads.

Because types may have multiple constructors, dictionary resolution in @polytropos-generics@
is organized as a __2D dictionary matrix__:

@
class GInstances (c :: Type -> Constraint) a where
  gdicts :: SmallArray (SmallArray (DictAny c))
@

The outer array is indexed in \(O(1)\) by the constructor tag @tx :: Word@; the inner array
supplies the field dictionaries for that specific constructor.

=== 2. Flat Runtime Arrays vs. Binary Type-Tree Overhead

While standard "GHC.Generics" provides a simple @Generic(from, to)@ mental model,
it compiles down to deeply nested binary type trees (@(:*:)@, @(:+:)@, @M1@, @K1@).
For types with many fields or constructors, this causes \(O(2^N)\) compile-time metadata
blow-up and substantial runtime pointer-chasing and heap allocation.

@polytropos-generics@ adopts the intuitive @Generic(from, to)@ interface, but
maps directly to flat contiguous memory. Generic operations run as tight unrolled loops
over 'Data.Primitive.SmallArray.SmallArray' with literal dictionary dispatch.

= When to Use This Module

* __Whole-Data Operations on Open Rows__: When you need structural equality (@'geq'@),
  ordering (@'gcompare'@), rendering (@'gshowsPrec'@), or uniform mapping (@'gmap'@,
  @'gfoldMap'@) over open @Record@ or @Variant@ types without writing manual boilerplate.
* __Bridging Nominal ADTs__: When translating nominal Haskell data types into flat
  polytropos arrays for serialization (e.g. CBOR, Aeson), database marshalling (Hasql,
  Rel8, Beam), or open effect payload carrier systems.

= When Not to Use This Module

* When working purely with individual field access and modification on open rows; use
  the optics satellites (@polytropos-optics@, @polytropos-lens@, or @polytropos-microlens@)
  or the core field projection functions instead.
* When working with records that require SOP n-ary product combinators (@NP@, @czipWith@)
  over heterogeneous functors without sum representations; in those cases, specialized
  product generics may be preferred.

= Worked Examples

== Mode A: Whole-Data Operations over Open Rows

Open records and variants already provide built-in instances of 'Generic' and
'GInstances' via the typechecker plugin's 'AllFields' evidence synthesis:

> {-# LANGUAGE DataKinds #-}
>
> import Polytropos
> import Polytropos.Generics
>
> -- Create an open record using idiomatic REC syntax:
> person :: Record '["name" ':= String, "age" ':= Int]
> person = REC { name = "Alice", age = 30 }
>
> -- 1. Structural equality:
> isEqual :: Bool
> isEqual = geq person person  -- True
>
> -- 2. Uniform type-directed mapping:
> -- Double every numeric field in a record:
> doubled :: Record '["x" ':= Int, "y" ':= Int]
> doubled = gmap @Num (* 2) (REC { x = 10, y = 20 })
>
> -- 3. Folding across heterogeneous fields:
> summary :: String
> summary = gfoldMap @Show (\x -> show x ++ "; ") person
> -- Evaluates to: "\"Alice\"; 30; "

== Mode B: Bridging Nominal ADTs

Nominal Haskell types can implement 'Generic' and 'GInstances' to participate in
flat array-based generic routines:

> {-# LANGUAGE TypeApplications #-}
>
> import Polytropos.Core
> import Polytropos.Generics
> import Data.Primitive.SmallArray
> import Unsafe.Coerce (unsafeCoerce)
>
> data Shape = Circle Double | Rectangle Double Double
>   deriving (Show, Eq)
>
> instance Generic Shape where
>   type RepOf Shape = Rep I Shape
>   from (Circle r)        = Rep 0 (smallArrayFromList [I (unsafeCoerce r)])
>   from (Rectangle w h)   = Rep 1 (smallArrayFromList [I (unsafeCoerce w), I (unsafeCoerce h)])
>   to (Rep 0 arr)         = let I r = indexSmallArray arr 0 in Circle (unsafeCoerce r)
>   to (Rep 1 arr)         = let I w = indexSmallArray arr 0; I h = indexSmallArray arr 1 in Rectangle (unsafeCoerce w) (unsafeCoerce h)
>   to _                   = error "invalid constructor tag"
>
> instance GInstances Eq Shape where
>   gdicts = smallArrayFromList
>     [ smallArrayFromList [mkDictAny @Eq @Double]
>     , smallArrayFromList [mkDictAny @Eq @Double, mkDictAny @Eq @Double]
>     ]
>
> -- Usage:
> -- geq (Circle 5.0) (Circle 5.0) == True
-}
module Polytropos.Generics (
    -- * Generic Conversion Class
    Generic(..)
  , I(..)

    -- * Dictionary Supply Matrix
  , GInstances(..)

    -- * Generic Structural Operations
    -- ** Equality and Ordering
  , geq
  , gcompare

    -- ** Pretty Printing
  , gshowsPrec

    -- ** Functorial Mapping and Folding
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

-- | Identity functor for use with t'Polytropos.Core.Rep'.
newtype I a = I { unI :: a }

-- | Generic conversion class. Bridges nominal ADTs to t'Polytropos.Core.Rep'.
class Generic a where
  type RepOf a :: Type
  from :: a -> RepOf a
  to   :: RepOf a -> a

-- | Provides an array of constraint dictionaries for each constructor of @a@,
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
