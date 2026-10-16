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

{-|
Module      : Polytropos.Hasql
Description : High-performance hasql PostgreSQL row decoders for Polytropos records
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Integrates @polytropos@ open records with the high-performance
PostgreSQL driver @hasql@.

= Architectural Overview & Rationale

== Bypassing Tuple Limits & Intermediate Allocations

Conventional database libraries map SQL rows to Haskell data types via intermediate
tuples (e.g. @(a, b, c)@). This imposes GHC's 62-column tuple limit and generates
large numbers of short-lived heap objects.

'recordRow' builds a @'Row' (Record r)@ that consumes one column per row
field, in row order, and packs the decoded values straight into the
contiguous 'Data.Primitive.SmallArray.SmallArray' payload of the record. The column decoders are
combined by the 'AllRowDecoder' constraint walk in a single pass, appending one slot
at a time. Rows of arbitrary arity (50, 100, 200+ columns) decode with zero tuple overhead.

Each column picks its value decoder from the 'Column' class at that
field's own type, allowing heterogeneous column rows.

= When to Use This Module

* When executing high-throughput PostgreSQL queries with @hasql@ where rows have
  many columns or where open records are used as query results.

= Worked Example

@
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

import qualified Hasql.Decoders as HD
import Polytropos
import Polytropos.Hasql

type UserRow = Record '["id" ':= Int64, "age" ':= Int32]

userDecoder :: HD.Row UserRow
userDecoder = recordRow \@UserRow
@
-}
module Polytropos.Hasql
  ( -- * Row Decoder Construction
    HasqlRow
  , recordRow

    -- * Column-Decoder Walk
  , AllRowDecoder (..)

    -- * Per-Column Value Decoders
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
-- slots go straight into a contiguous 'Data.Primitive.SmallArray.SmallArray' payload via
-- 'productRep'. No intermediate tuples — the walk composes the column
-- decoders applicatively, so arity is unbounded.
recordRow :: forall r. AllRowDecoder r => HasqlRow (Record r)
recordRow = RowRep . productRep <$> genRow (Proxy @r)
