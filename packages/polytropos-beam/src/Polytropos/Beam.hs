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

-- |
-- Module      : Polytropos.Beam
-- Description : beam schema integration for polytropos open records
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : EUPL-1.2 OR Apache-2.0
--
-- Enables @polytropos@ open records to act as @beam@ database schema tables
-- without GHC out-of-memory compilation crashes on 50+ columns.
--
-- = Why this is cheap
--
-- A beam table is normally a Haskell record whose 'Beamable' instance is
-- derived through GHC.Generics; the generic tree is what blows up compile
-- time on 50+ column tables. A @polytropos@ table is one flat 'Data.Primitive.SmallArray.SmallArray'
-- of payload slots, so 'zipBeamFieldsM' is a lockstep walk of two arrays —
-- column count costs one array element, not one node of a generic tree —
-- and 'tblSkeleton' is a spine built once per row arity.
--
-- = Shape
--
-- t'BeamTable' is a zero-cost newtype around @RowRep f ProductRowT r ()@
-- with the column functor @f@ as its second parameter, so
-- a table's columns are @Columnar f <field-i>@. The 'Beamable' instance is
-- completely erased — it never names field types — so heterogeneous rows
-- work exactly like homogeneous ones. Default column names come from the
-- row symbols via 'fieldNames'.
module Polytropos.Beam
  ( -- * Beam tables over polytropos rows
    BeamTable (..)
  , toBeamTable
  , fromBeamTable
  , beamTableOfSlots
    -- * Row introspection
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
