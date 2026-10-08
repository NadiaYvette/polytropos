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

-- |
-- Module      : Polytropos.Hasql
-- Description : hasql row decoders for polytropos open records
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : BSD-3-Clause
--
-- Integrates @polytropos@ open records with the high-performance
-- PostgreSQL driver @hasql@.
--
-- 'recordRow' builds a @'Row' (Record r)@ that consumes one column per row
-- field, in row order, and packs the decoded values straight into the
-- contiguous 'SmallArray' payload of the record. The column decoders are
-- combined by the 'AllRowDecoder' constraint walk instead of a tuple
-- constructor, so there are no intermediate tuple allocations and none of
-- GHC's 62-column tuple limit: a row of any arity decodes in a single
-- pass, appending one slot at a time.
--
-- Each column picks its value decoder from the 'Column' class at that
-- field's own type, so rows may mix column types. The instances provided
-- cover the fixed-width integral columns (@INT2@\/@INT4@\/@INT8@); more can
-- be added locally without touching this module's machinery.
module Polytropos.Hasql
  ( -- * Row decoder construction
    HasqlRow
  , recordRow
    -- * Column-decoder walk
  , AllRowDecoder (..)
    -- * Per-column value decoders
  , Column (..)
  ) where

import Data.Functor.Identity (Identity (..))
import Data.Int              (Int16, Int32, Int64)
import Data.Kind             (Type)
import Data.Proxy            (Proxy (..))
import GHC.Exts              (Any)
import Polytropos            (Record)
import Polytropos.Core       (Pair (..), Row, RowRep (..), noInlineUnsafeCo,
                              productRep)
import Hasql.Decoders        (column, nonNullable)
import qualified Hasql.Decoders as HD

-- | hasql's row decoder monad; aliased to avoid clashing with the 'Row'
-- kind synonym from "Polytropos.Core".
type HasqlRow = HD.Row

-- | The hasql value decoder for a column of type @a@. Instances pick the
-- Postgres column type; the row walk only needs the 'column' combinator.
class Column (a :: Type) where
  columnValue :: HD.Value a

instance Column Int16 where
  columnValue = HD.int2

instance Column Int32 where
  columnValue = HD.int4

instance Column Int64 where
  columnValue = HD.int8

-- | Heterogeneous column walk: every field of the row @r@ has a 'Column'
-- instance at its own type. 'genRow' composes one 'Row' column decoder per
-- field, in row order, collecting the decoded values as erased payload
-- slots — a single pass, one slot appended per column, no tuples.
class AllRowDecoder (r :: Row) where
  genRow :: Proxy r -> HasqlRow [Identity Any]

instance AllRowDecoder '[] where
  genRow _ = pure []

instance (Column a, AllRowDecoder r) => AllRowDecoder ((n ':= a) ': r) where
  genRow _ =
    (\v vs -> Identity (noInlineUnsafeCo v :: Any) : vs)
      <$> (column (nonNullable columnValue) :: HasqlRow a)
      <*> genRow (Proxy @r)

-- | Build a hasql row decoder that consumes one column per field of the
-- row, in row order, and materialises the record directly: the decoded
-- slots go straight into a contiguous 'SmallArray' payload via
-- 'productRep'. No intermediate tuples — the walk composes the column
-- decoders applicatively, so arity is unbounded.
recordRow :: forall r. AllRowDecoder r => HasqlRow (Record r)
recordRow = RowRep . productRep <$> genRow (Proxy @r)
