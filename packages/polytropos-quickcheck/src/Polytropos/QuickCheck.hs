{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- |
-- Module      : Polytropos.QuickCheck
-- Description : QuickCheck generators and slot-indexed shrinkers for polytropos
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : EUPL-1.2 OR Apache-2.0
--
-- Integrates @polytropos@ open records and variants with QuickCheck
-- property-based testing.
--
-- = Records
--
-- 'Arbitrary (Record r)' generates each field value via that field's own
-- 'Arbitrary' instance (the walk is heterogeneous: rows may mix field
-- types) and packs the results straight into the contiguous 'Data.Primitive.SmallArray.SmallArray'
-- payload — no intermediate tuples or generic-representation trees.
--
-- Shrinking is slot-indexed: each field slot is shrunk independently, one
-- field at a time, so shrinking a @k@-field record yields O(k) candidates
-- per level instead of the full Cartesian product over per-field shrink
-- lists.
--
-- = Variants
--
-- 'Arbitrary (Variant s)' uniformly selects a constructor tag index and
-- generates that constructor's payload fields. Shrinking is
-- branch-preserving: only the payload of the currently active constructor
-- is shrunk; the tag never changes, so a counterexample stays on the
-- constructor branch that exposed the property failure.
module Polytropos.QuickCheck
  ( -- * Row and sum constraint walks
    AllArbitrary (..)
  , AllCtorsArbitrary (..)
  ) where

import Data.Functor.Identity (Identity (..))
import Data.Proxy            (Proxy (..))
import GHC.Exts              (Any, toList)
import Polytropos            (Record, Variant)
import Polytropos.Core       (Pair (..), Row, RowRep (..), SumRow, noInlineUnsafeCo,
                              injectRep, productRep, repTag, repVals)
import Test.QuickCheck       (Arbitrary (..), Gen, choose)

{-------------------------------------------------------------------------------
  Row walk
-------------------------------------------------------------------------------}

-- | Heterogeneous generation walk: every field of the row @r@ has an
-- 'Arbitrary' instance at its own type.
class AllArbitrary (r :: Row) where
  -- | Generate a value for each payload slot, in row order.
  genFields :: Proxy r -> Gen [Identity Any]
  -- | Slot-indexed shrinks of the payload: one field shrinks at a time.
  shrinkFields :: Proxy r -> [Identity Any] -> [[Identity Any]]

instance AllArbitrary '[] where
  genFields _  = pure []
  shrinkFields _ _ = []

instance (Arbitrary a, AllArbitrary r) => AllArbitrary ((n ':= a) ': r) where
  genFields _ = do
    v <- arbitrary :: Gen a
    vs <- genFields (Proxy @r)
    pure (Identity (noInlineUnsafeCo v :: Any) : vs)

  shrinkFields _ (Identity x : xs) =
    [ Identity (noInlineUnsafeCo v :: Any) : xs
    | v <- shrink (noInlineUnsafeCo x :: a) ]
    ++ [ Identity x : rest | rest <- shrinkFields (Proxy @r) xs ]
  shrinkFields _ [] = []

{-------------------------------------------------------------------------------
  Sum walk
-------------------------------------------------------------------------------}

-- | Heterogeneous generation walk over a sum row: every constructor's
-- field row satisfies 'AllArbitrary'.
class AllCtorsArbitrary (s :: SumRow) where
  -- | Number of constructors in the sum.
  numCtors :: Proxy s -> Int
  -- | Generate the payload fields of constructor @i@ (0-based).
  genCtorFields :: Proxy s -> Int -> Gen [Identity Any]
  -- | Slot-indexed shrinks of the payload of constructor @i@.
  shrinkCtorFields :: Proxy s -> Int -> [Identity Any] -> [[Identity Any]]

instance AllCtorsArbitrary '[] where
  numCtors _          = 0
  genCtorFields _ _   = pure []
  shrinkCtorFields _ _ _ = []

instance (AllArbitrary fs, AllCtorsArbitrary s)
      => AllCtorsArbitrary ((c ':= fs) ': s) where
  numCtors _ = 1 + numCtors (Proxy @s)

  genCtorFields _ 0 = genFields (Proxy @fs)
  genCtorFields _ i | i < 0 = error "polytropos-quickcheck: negative constructor index"
                    | otherwise = genCtorFields (Proxy @s) (i - 1)

  shrinkCtorFields _ 0 xs = shrinkFields (Proxy @fs) xs
  shrinkCtorFields _ i xs = shrinkCtorFields (Proxy @s) (i - 1) xs

{-------------------------------------------------------------------------------
  QuickCheck instances
-------------------------------------------------------------------------------}

instance AllArbitrary r => Arbitrary (Record r) where
  arbitrary = RowRep . productRep <$> genFields (Proxy @r)
  shrink (RowRep rep) =
    [ RowRep (productRep vs)
    | vs <- shrinkFields (Proxy @r) (toList (repVals rep)) ]

instance AllCtorsArbitrary s => Arbitrary (Variant s) where
  arbitrary = do
    let n = numCtors (Proxy @s)
    if n == (0 :: Int)
      then pure (RowRep (injectRep 0 []))
      else do
        i <- choose (0, n - 1)
        vs <- genCtorFields (Proxy @s) i
        pure (RowRep (injectRep (fromIntegral (i :: Int)) vs))
  shrink (RowRep rep) =
    let tag = repTag rep
    in [ RowRep (injectRep tag vs)
       | vs <- shrinkCtorFields (Proxy @s) (fromIntegral tag)
                                            (toList (repVals rep)) ]
