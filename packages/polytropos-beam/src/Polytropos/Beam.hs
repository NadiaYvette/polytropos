{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module      : Polytropos.Beam
Description : beam schema integration for Polytropos open records
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Enables @polytropos@ open records to act as @beam@ database schema tables
without GHC out-of-memory compilation crashes on 50+ columns.

= Architectural Overview & Rationale

== Eliminating Generic Tree Explosion in Beam

A standard beam table is a nominal Haskell record whose 'Beamable' instance is
derived through "GHC.Generics". The resulting binary metadata tree is what causes
quadratic compile times and memory blow-up on tables with 50+ columns.

In @polytropos-beam@, a table is backed by a single flat 'Data.Primitive.SmallArray.SmallArray':
* 'zipBeamFieldsM' executes as a linear lockstep walk over flat array slots.
* 'tblSkeleton' builds the table spine once per row arity.
* @t'BeamTable'@ is a zero-cost newtype wrapper around @RowRep f ProductRowT r ()@.

= When to Use This Module

* When defining large database tables (dozens or hundreds of columns) with the @beam@
  framework while maintaining predictable, instantaneous compilation.

= Worked Example

@
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

import Database.Beam
import Polytropos
import Polytropos.Beam

type UserRow = '["id" ':= Int, "username" ':= String]
type UserTable f = BeamTable UserRow f

-- Convert an open record into a Beam table:
rec :: Record UserRow
rec = insertField (Field \@"id") (1 :: Int)
    $ insertField (Field \@"username") "Alice"
    $ emptyRecord

tbl :: UserTable Identity
tbl = toBeamTable rec
@
-}
module Polytropos.Beam
  ( -- * Beam Tables over Polytropos Rows
    BeamTable (..)
  , toBeamTable
  , fromBeamTable
  , beamTableOfSlots

    -- * Row Introspection
  , FieldNames (..)
  ) where

import Data.Functor.Identity (Identity)
import Data.Kind             (Type)
import Data.Proxy            (Proxy (..))
import GHC.Exts              (Any, toList)
import GHC.TypeLits          (KnownSymbol, symbolVal)
import Database.Beam.Schema.Tables (Beamable (..), Columnar' (..), Ignored (..))
import Polytropos            (Record)
import Polytropos.Core       (Pair (..), Rep (..), Row, RowRep (..), RowType (..),
                              noInlineUnsafeCo, productRep, repVals)

{-------------------------------------------------------------------------------
  Row introspection
-------------------------------------------------------------------------------}

-- | The field names of a row, in row order, reified from the type level.
-- These are the default column names beam derives from the row symbols.
class FieldNames (r :: Row) where
  fieldNames :: Proxy r -> [String]

instance FieldNames '[] where
  fieldNames _ = []

instance (KnownSymbol n, FieldNames r) => FieldNames ((n ':= a) ': r) where
  fieldNames _ = symbolVal (Proxy @n) : fieldNames (Proxy @r)

{-------------------------------------------------------------------------------
  Beam tables
-------------------------------------------------------------------------------}

-- | A @polytropos@ row presented as a beam table with column functor @f@.
--
-- Zero cost: unwraps to exactly the same t'Polytropos.Core.Rep' spine as the
-- corresponding 'Record' (for @f ~ Identity@).
newtype BeamTable (r :: Row) (f :: Type -> Type)
  = BeamTable (RowRep f ProductRowT r ())

-- | View a record as a beam table (zero-cost newtype wrap).
toBeamTable :: Record r -> BeamTable r Identity
toBeamTable (RowRep rep) = BeamTable (RowRep rep)

-- | View a beam table as a record (zero-cost newtype unwrap).
fromBeamTable :: BeamTable r Identity -> Record r
fromBeamTable (BeamTable (RowRep rep)) = RowRep rep

-- | Build a table from payload slots, in row order. The slot list must have
-- exactly the row's arity; a shorter list yields a partially filled table
-- that will misbehave if traversed, so prefer 'toBeamTable'.
beamTableOfSlots :: [f Any] -> BeamTable r f
beamTableOfSlots slots = BeamTable (RowRep (productRep slots))

instance FieldNames r => Beamable (BeamTable r) where
  zipBeamFieldsM combine (BeamTable (RowRep (Rep t fv))) (BeamTable (RowRep (Rep _ gv))) =
    BeamTable . RowRep . (\hs -> Rep t (repVals (productRep hs)))
      <$> traverse step (zip (toList fv) (toList gv))
    where
      -- The erased-slot coercions: Columnar' f a is a newtype around
      -- Columnar f a, which for a concrete f is f a — so a slot of type
      -- f Any and a Columnar' f Any dictionary have identical runtime
      -- representation. The @a@ is fixed to Any by the rebuild below.
      step (fx, gx) =
        fmap (\(Columnar' hx) -> noInlineUnsafeCo hx :: h Any)
             (combine (noInlineUnsafeCo fx) (noInlineUnsafeCo gx))
  {-# INLINE zipBeamFieldsM #-}

  tblSkeleton =
    BeamTable (RowRep (productRep (replicate (length (fieldNames (Proxy @r))) Ignored)))
