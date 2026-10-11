{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- |
-- Module      : Polytropos.Rel8
-- Description : rel8 Rel8able instances over polytropos open rows
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : BSD-3-Clause
--
-- Integration of @polytropos@ open rows with Oliver Charles' @rel8@ PostgreSQL
-- framework. @t'PolyRow' r@ is rel8's 'Rel8able' for the product row @r@; its
-- column schema is a right-nested 'H.HProduct' tree of 'H.HLabel'ed 'H.HIdentity'
-- columns built directly from the row's type-level field list.
--
-- The flat 'SmallArray' payload of the underlying t'Rep' is read and written
-- slot by slot — one slot per column, in row order — so conversion to and from
-- rel8's columnar representation never materialises an intermediate tuple and
-- is unbounded in arity.
module Polytropos.Rel8
  ( -- * A rel8 table from an open row
    PolyRow (..)
  , toRecord
  , fromRecord

    -- * Schema & Rel8able Row Class
  , Rel8able
  , Rel8ableRow (..)
  , RowHTable
  , AllSql

    -- * Entry points for Identity/Result
  , rowToColumns
  , columnsToRow

    -- * Lifting to SQL Expressions
  , litPolyRow
  , litRecord

    -- * Columnar Combinators
  , hfield
  , hfieldAt
  , htabulate
  , hmap
  , htraverse
  , hzipWith
  ) where

import Data.Kind (Type, Constraint)
import Data.Functor.Identity (Identity (..))
import Data.Primitive.SmallArray
  ( SmallArray
  , indexSmallArray
  , sizeofSmallArray
  , smallArrayFromList
  )
import GHC.Exts (Any)
import GHC.TypeLits (KnownSymbol)
import Unsafe.Coerce (unsafeCoerce)

import Rel8 (Rel8able, Expr, lit)
import qualified Rel8.Internal.Generic.Rel8able as G
import Rel8.Internal.Generic.Rel8able (GColumns, GFromExprs)
import qualified Rel8.Internal.Schema.HTable as H
import qualified Rel8.Internal.Schema.HTable.Identity as H
import qualified Rel8.Internal.Schema.HTable.Product as H
import qualified Rel8.Internal.Schema.HTable.Label as H
import qualified Rel8.Internal.Schema.Kind as K
import Rel8.Internal.Schema.Null (Sql)
import Rel8.Internal.Schema.Result (Result)
import Rel8.Internal.Type (DBType)

import Polytropos (Record)
import Polytropos.Core
  ( Row
  , RowRep (..)
  , RowType (..)
  , Rep (..)
  , Pair (..)
  , Field (..)
  , FieldIndex (..)
  )

{-------------------------------------------------------------------------------
  Schema: row -> HTable (closed type family)
-------------------------------------------------------------------------------}

-- | Map a polytropos product row to rel8's HTable: a right-nested 'H.HProduct'
-- tree of 'H.HLabel'ed 'H.HIdentity' columns, one per field, named by the field's
-- 'GHC.TypeLits.Symbol'.
type RowHTable :: Row -> K.HTable
type family RowHTable r where
  RowHTable '[n ':= a] = H.HLabel n (H.HIdentity a)
  RowHTable (n ':= a ': r) = H.HProduct (H.HLabel n (H.HIdentity a)) (RowHTable r)

-- | Constraint: every field label has a 'GHC.TypeLits.KnownSymbol' instance and its type is a PostgreSQL
-- 'Sql' 'DBType'.
type AllSql :: Row -> Constraint
type family AllSql r where
  AllSql '[] = ()
  AllSql '[n ':= a] = (KnownSymbol n, Sql DBType a)
  AllSql (n ':= a ': r) = (KnownSymbol n, Sql DBType a, AllSql r)

{-------------------------------------------------------------------------------
  Rel8ableRow class
-------------------------------------------------------------------------------}

-- | Type class providing bidirectional conversion between a flat 'SmallArray'
-- of slots and the nested rel8 'RowHTable' column tree.
class (AllSql r, H.HTable (RowHTable r)) => Rel8ableRow (r :: Row) where
  -- | Convert a flat array into the nested HTable tree at a given starting offset.
  toHTable :: forall context. SmallArray (context Any) -> Int -> (RowHTable r context, Int)

  -- | Unroll the nested HTable tree into a list of erased column context slots.
  fromHTable :: forall context. RowHTable r context -> [context Any]

  -- | Lift column values at 'Result' (t'Data.Functor.Identity.Identity') into PostgreSQL expressions ('Expr').
  litHTable :: RowHTable r Result -> RowHTable r Expr

  -- | Arity (number of columns).
  rowArity :: Int

instance (KnownSymbol n, Sql DBType a) => Rel8ableRow '[n ':= a] where
  rowArity = 1
  toHTable arr offset =
    let val = unsafeCoerce (indexSmallArray arr offset) :: context a
    in (H.HLabel (H.HIdentity val), offset + 1)
  fromHTable (H.HLabel (H.HIdentity val)) =
    [unsafeCoerce val]
  litHTable (H.HLabel (H.HIdentity (Identity a))) =
    H.HLabel (H.HIdentity (lit a))

instance (KnownSymbol n, Sql DBType a, Rel8ableRow (r1 ': rs)) => Rel8ableRow (n ':= a ': r1 ': rs) where
  rowArity = 1 + rowArity @(r1 ': rs)
  toHTable arr offset =
    let val = unsafeCoerce (indexSmallArray arr offset) :: context a
        (rest, nextOffset) = toHTable @(r1 ': rs) arr (offset + 1)
    in (H.HProduct (H.HLabel (H.HIdentity val)) rest, nextOffset)
  fromHTable (H.HProduct (H.HLabel (H.HIdentity val)) rest) =
    unsafeCoerce val : fromHTable @(r1 ': rs) rest
  litHTable (H.HProduct (H.HLabel (H.HIdentity (Identity a))) rest) =
    H.HProduct (H.HLabel (H.HIdentity (lit a))) (litHTable @(r1 ': rs) rest)

{-------------------------------------------------------------------------------
  The Rel8able
-------------------------------------------------------------------------------}

-- | A rel8 table row backed by an open polytropos product row @r@.
--
-- The newtype is polymorphic in the rel8 context functor @context@ so that rel8
-- can use the same 'Rel8able' at 'Result', 'Expr', 'Rel8.Name', etc.
newtype PolyRow (r :: Row) (context :: Type -> Type) = PolyRow
  { unPolyRow :: RowRep context 'ProductRowT r ()
  }

-- | Convert a @t'PolyRow' r 'Result'@ to a polytropos @'Record' r@.
toRecord :: PolyRow r Result -> Record r
toRecord (PolyRow rep) = rep

-- | Wrap a polytropos @'Record' r@ as a @t'PolyRow' r 'Result'@.
fromRecord :: Record r -> PolyRow r Result
fromRecord rep = PolyRow rep

instance Eq (Record r) => Eq (PolyRow r Result) where
  PolyRow a == PolyRow b = a == b

instance Show (Record r) => Show (PolyRow r Result) where
  showsPrec d (PolyRow a) = showsPrec d a

instance Rel8ableRow r => Rel8able (PolyRow r) where
  type GColumns (PolyRow r) = RowHTable r
  type GFromExprs (PolyRow r) = PolyRow r Result

  gfromColumns _ cols =
    PolyRow (RowRep (Rep 0 (smallArrayFromList (fromHTable @r cols))))
  gtoColumns _ (PolyRow (RowRep (Rep _ arr))) =
    fst (toHTable @r arr 0)
  gfromResult cols =
    PolyRow (RowRep (Rep 0 (smallArrayFromList (fromHTable @r cols))))
  gtoResult (PolyRow (RowRep (Rep _ arr))) =
    fst (toHTable @r arr 0)

{-------------------------------------------------------------------------------
  Identity / Result round-trip entry points
-------------------------------------------------------------------------------}

-- | Pack a @'Record' r@ into its rel8 column tree at t'Data.Functor.Identity.Identity'.
rowToColumns :: forall r. Rel8ableRow r => Record r -> RowHTable r Identity
rowToColumns (RowRep (Rep _ arr)) = fst (toHTable @r arr 0)

-- | Unpack rel8 columns (at t'Data.Functor.Identity.Identity') back into a @'Record' r@.
columnsToRow :: forall r. Rel8ableRow r => RowHTable r Identity -> Record r
columnsToRow cols = RowRep (Rep 0 (smallArrayFromList (fromHTable @r cols)))

{-------------------------------------------------------------------------------
  Lifting to SQL Expressions
-------------------------------------------------------------------------------}

-- | Lift a @t'PolyRow' r 'Result'@ to a @t'PolyRow' r 'Expr'@.
litPolyRow :: forall r. Rel8ableRow r => PolyRow r Result -> PolyRow r Expr
litPolyRow (PolyRow (RowRep (Rep _ arr))) =
  let (resCols, _) = toHTable @r arr 0
      exprCols = litHTable @r resCols
  in PolyRow (RowRep (Rep 0 (smallArrayFromList (fromHTable @r exprCols))))

-- | Lift a polytropos @'Record' r@ directly into a @t'PolyRow' r 'Expr'@.
litRecord :: forall r. Rel8ableRow r => Record r -> PolyRow r Expr
litRecord = litPolyRow . fromRecord

{-------------------------------------------------------------------------------
  Columnar Combinators
-------------------------------------------------------------------------------}

-- | Read a field by name using 'FieldIndex'.
hfield :: forall name r context a. FieldIndex name r a
  => Field name -> PolyRow r context -> context a
hfield _ (PolyRow (RowRep (Rep _ arr))) =
  unsafeCoerce (indexSmallArray arr (fieldIndex @_ @name @r @a))

-- | Read a field at a slot index from a t'PolyRow'.
hfieldAt :: Int -> PolyRow r context -> context Any
hfieldAt i (PolyRow (RowRep (Rep _ arr))) = indexSmallArray arr i

-- | Build a t'PolyRow' by evaluating a generator across each column slot.
htabulate :: forall r context. Rel8ableRow r
  => (Int -> context Any) -> PolyRow r context
htabulate f =
  let n = rowArity @r
      vals = [f i | i <- [0 .. n - 1]]
  in PolyRow (RowRep (Rep 0 (smallArrayFromList vals)))

-- | Map a natural transformation across all columns in a t'PolyRow'.
hmap :: forall r f g. Rel8ableRow r
  => (forall a. f a -> g a) -> PolyRow r f -> PolyRow r g
hmap f (PolyRow (RowRep (Rep _ arr))) =
  let n = sizeofSmallArray arr
      vals = [unsafeCoerce (f (unsafeCoerce (indexSmallArray arr i))) | i <- [0 .. n - 1]]
  in PolyRow (RowRep (Rep 0 (smallArrayFromList vals)))

-- | Traverse all columnar fields in a t'PolyRow'.
htraverse :: forall r f g m. (Applicative m, Rel8ableRow r)
  => (forall a. f a -> m (g a)) -> PolyRow r f -> m (PolyRow r g)
htraverse f (PolyRow (RowRep (Rep _ arr))) =
  let n = sizeofSmallArray arr
      go i
        | i >= n    = pure []
        | otherwise = (:) <$> f (unsafeCoerce (indexSmallArray arr i)) <*> go (i + 1)
  in fmap (\res -> PolyRow (RowRep (Rep 0 (smallArrayFromList (map unsafeCoerce res))))) (go 0)

-- | Zip two columnar records slot-by-slot in a tight vector loop.
hzipWith :: forall r f g h. Rel8ableRow r
  => (forall a. f a -> g a -> h a) -> PolyRow r f -> PolyRow r g -> PolyRow r h
hzipWith f (PolyRow (RowRep (Rep _ a))) (PolyRow (RowRep (Rep _ b))) =
  let n = sizeofSmallArray a
      vals = [unsafeCoerce (f (unsafeCoerce (indexSmallArray a i)) (unsafeCoerce (indexSmallArray b i))) | i <- [0 .. n - 1]]
  in PolyRow (RowRep (Rep 0 (smallArrayFromList vals)))
