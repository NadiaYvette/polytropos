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

{-|
Module      : Polytropos.Persistent
Description : persistent PersistValue marshalling for Polytropos records
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Bridges @polytropos@ open records with the Yesod ecosystem's
@persistent@ relational database framework.

= Architectural Overview & Rationale

'PersistRow' provides fast marshalling of records to and from
@['PersistValue']@ rows: 'toPersistFieldsRecord' serializes the flat
payload in row order, and 'fromPersistValuesRecord' reconstructs the
record by filling the payload slots directly, in \(O(N)\), with no
intermediate tuples. The walk is heterogeneous: each field uses its own
'PersistField' instance.

'PersistField (Record r)' lets a whole record travel through
persistent's value machinery as a 'PersistList' (a nested-column
analogue), and @t'PolyRowEntity'@ pairs an integer key with a record in the
shape of persistent's 'Database.Persist.Entity', marshalling to the
key-then-fields row layout backends use for @Entity@ rows.

= When to Use This Module

* When persisting @polytropos@ open records with Yesod and the @persistent@ ORM.

= Worked Example

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Database.Persist
> import Polytropos
> import Polytropos.Persistent
>
> type PersonRow = Record '["name" ':= Text, "age" ':= Int]
>
> person :: PersonRow
> person = REC { name = "Alice", age = 30 }
>
> -- Convert to persistent values:
> vals :: [PersistValue]
> vals = toPersistFieldsRecord person
-}
module Polytropos.Persistent
  ( -- * Row Marshalling
    PersistRow (..)

    -- * Row Constraint Walks
  , AllToPersist (..)
  , AllFromPersist (..)

    -- * Entity Wrapper
  , PolyRowEntity (..)
  , toPolyRowEntity
  , fromPolyRowEntity
  ) where

import Data.Functor.Identity (Identity (..))
import Data.Int              (Int64)
import Data.Proxy            (Proxy (..))
import Data.Text             (Text)
import qualified Data.Text as T
import GHC.Exts              (Any, toList)
import Polytropos            (Record)
import Polytropos.Core       (Pair (..), Row, RowRep (..), noInlineUnsafeCo,
                              productRep, repVals)
import Database.Persist      (PersistField (..), PersistValue (..))

{-------------------------------------------------------------------------------
  Row constraint walks
-------------------------------------------------------------------------------}

-- | Heterogeneous encode walk: every field of the row @r@ has a
-- 'PersistField' instance at its own type; 'toVals' serializes the erased
-- payload slots in row order.
class AllToPersist (r :: Row) where
  toVals :: Proxy r -> [Identity Any] -> [PersistValue]

instance AllToPersist '[] where
  toVals _ _ = []

instance (PersistField a, AllToPersist r) => AllToPersist ((n ':= a) ': r) where
  toVals _ (Identity x : xs) =
    toPersistValue (noInlineUnsafeCo x :: a) : toVals (Proxy @r) xs
  toVals _ [] = error "polytropos-persistent: payload arity mismatch"

-- | Heterogeneous decode walk: fills the payload slots from a
-- @['PersistValue']@ row in O(n).
class AllFromPersist (r :: Row) where
  fromVals :: Proxy r -> [PersistValue] -> Either Text [Identity Any]

instance AllFromPersist '[] where
  fromVals _ [] = Right []
  fromVals _ vs = Left (T.pack ("polytropos-persistent: expected 0 fields, got " ++ show (length vs)))

instance (PersistField a, AllFromPersist r) => AllFromPersist ((n ':= a) ': r) where
  fromVals _ (v : vs) = do
    x <- fromPersistValue v :: Either Text a
    xs <- fromVals (Proxy @r) vs
    Right (Identity (noInlineUnsafeCo x :: Any) : xs)
  fromVals _ [] = Left (T.pack "polytropos-persistent: row too short for record")

{-------------------------------------------------------------------------------
  PersistRow
-------------------------------------------------------------------------------}

-- | Fast marshalling of a polytropos record to and from a @['PersistValue']@
-- database row, in field order.
class PersistRow (r :: Row) where
  toPersistFieldsRecord :: Record r -> [PersistValue]
  fromPersistValuesRecord :: [PersistValue] -> Either Text (Record r)

instance (AllToPersist r, AllFromPersist r) => PersistRow r where
  toPersistFieldsRecord (RowRep rep) = toVals (Proxy @r) (toList (repVals rep))
  fromPersistValuesRecord vs =
    RowRep . productRep <$> fromVals (Proxy @r) vs

{-------------------------------------------------------------------------------
  PersistField bridge and entity wrapper
-------------------------------------------------------------------------------}

-- | A whole record travels through persistent's value machinery as a
-- 'PersistList' of its fields.
instance PersistRow r => PersistField (Record r) where
  toPersistValue = PersistList . toPersistFieldsRecord
  fromPersistValue (PersistList vs) = fromPersistValuesRecord vs
  fromPersistValue v = Left (T.pack ("polytropos-persistent: expected PersistList, got " ++ show v))

-- | Key-plus-record wrapper in the shape of persistent's 'Database.Persist.Entity' for a
-- record table: an integer key followed by the record's field values.
data PolyRowEntity (r :: Row) = PolyRowEntity
  { polyRowKey    :: Int64
  , polyRowRecord :: Record r
  }

-- | Wrap a record under the given integer key.
toPolyRowEntity :: Int64 -> Record r -> PolyRowEntity r
toPolyRowEntity k r = PolyRowEntity k r

-- | Unwrap an entity to its key and field values (key first, matching the
-- @id | fields@ layout backends use for entity rows).
fromPolyRowEntity :: PersistRow r => PolyRowEntity r -> (Int64, [PersistValue])
fromPolyRowEntity (PolyRowEntity k r) = (k, PersistInt64 k : toPersistFieldsRecord r)
