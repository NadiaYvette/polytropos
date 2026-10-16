{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module      : Polytropos.Cassava
Description : cassava CSV codecs for Polytropos open records
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Connects @polytropos@ open records to the standard Haskell CSV library
@cassava@ without intermediate nominal conversions: 'Csv.ToNamedRecord'
serializes field names and values straight from the flat
@t'Polytropos.Core.Rep'@ payload, and 'Csv.FromNamedRecord' looks up each field
label in the CSV header map in \(O(1)\).

= Architectural Overview & Rationale

== Heterogeneous Row Support

Unlike satellites that require homogeneous rows, @polytropos-cassava@ is
genuinely heterogeneous: the 'AllToField' and 'AllFromField' row constraint walks
require the CSV field classes ('Csv.ToField' \/ 'Csv.FromField') at /each field's own type/,
so a row mixing @String@, @Int@, and @Double@ columns encodes and decodes directly.

Decoding is strict about field presence (a missing header column fails),
but ignores extra columns in the CSV input, matching cassava's own generic behaviour.

= When to Use This Module

* When reading or writing CSV files, spreadsheets, or tabular datasets using open records.

= Worked Example

@
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

import qualified Data.Csv as Csv
import Polytropos
import Polytropos.Cassava

type UserRow = Record '["username" ':= String, "score" ':= Int]

row :: UserRow
row = insertField (Field \@"username") "Alice"
    $ insertField (Field \@"score") (95 :: Int)
    $ emptyRecord

-- Encodes to CSV named record:
namedRec = Csv.toNamedRecord row
@
-}
module Polytropos.Cassava
  ( -- * Row Constraint Walks
    AllToField (..)
  , AllFromField (..)

    -- * Row Introspection
  , FieldNames (..)
  ) where

import Data.Functor.Identity (Identity (..))
import Data.Proxy           (Proxy (..))
import GHC.Exts             (Any, toList)
import GHC.TypeLits         (KnownSymbol, symbolVal)
import Polytropos           (Record)
import Polytropos.Core      (Pair (..), Row, RowRep (..), noInlineUnsafeCo,
                              productRep, repVals)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Csv            as Csv

{-------------------------------------------------------------------------------
  Row introspection
-------------------------------------------------------------------------------}

-- | The field names of a row, in row order, reified from the type level.
class FieldNames (r :: Row) where
  fieldNames :: Proxy r -> [String]

instance FieldNames '[] where
  fieldNames _ = []

instance (KnownSymbol n, FieldNames r) => FieldNames ((n ':= a) ': r) where
  fieldNames _ = symbolVal (Proxy @n) : fieldNames (Proxy @r)

{-------------------------------------------------------------------------------
  Row constraint walk
-------------------------------------------------------------------------------}

-- | Evidence that every field of the row @r@ has a 'Csv.ToField' instance
-- at that field's own type — the heterogeneous analogue of a constraint
-- fold. The walk applies @toField@ to each erased payload slot exactly where
-- the row structure guarantees the slot's type.
class AllToField (r :: Row) where
  encFields :: Proxy r -> [Identity Any] -> [BS8.ByteString]

instance AllToField '[] where
  encFields _ _ = []

instance (KnownSymbol n, Csv.ToField a, AllToField r)
      => AllToField ((n ':= a) ': r) where
  encFields _ (Identity x : xs) =
    Csv.toField (noInlineUnsafeCo x :: a) : encFields (Proxy @r) xs
  encFields _ [] = error "polytropos-cassava: payload arity mismatch"

-- | Heterogeneous decode walk: every field of the row @r@ has a
-- 'Csv.FromField' instance at its own type, and 'decFields' looks each
-- column up by name in O(1).
class AllFromField (r :: Row) where
  decFields :: Proxy r -> Csv.NamedRecord -> Csv.Parser [Identity Any]

instance AllFromField '[] where
  decFields _ _ = pure []

instance (KnownSymbol n, Csv.FromField a, AllFromField r)
      => AllFromField ((n ':= a) ': r) where
  decFields _ nr = do
    v <- nr Csv..: BS8.pack (symbolVal (Proxy @n)) :: Csv.Parser a
    vs <- decFields (Proxy @r) nr
    pure (Identity (noInlineUnsafeCo v :: Any) : vs)

{-------------------------------------------------------------------------------
  cassava instances
-------------------------------------------------------------------------------}

instance (FieldNames r, AllToField r) => Csv.ToNamedRecord (Record r) where
  toNamedRecord (RowRep rep) = Csv.namedRecord
    (zip (map BS8.pack (fieldNames (Proxy @r)))
         (encFields (Proxy @r) (toList (repVals rep))))

instance AllFromField r => Csv.FromNamedRecord (Record r) where
  parseNamedRecord nr = do
    vs <- decFields (Proxy @r) nr
    pure (RowRep (productRep vs))
