{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Core vocabulary and generic representation for @polytropos@.
--
-- This module is deliberately small and self-contained. It fixes three things
-- and defers everything else to the design note
-- (@docs/notes/POLYTROPOS_DESIGN.md@):
--
-- 1. The /row vocabulary/: how products and sums are spelled at the type level
--    (§1 of the note).
-- 2. The /generic representation/: @'Rep'@, a runtime tag plus a flat array of
--    payload slots (§2).
-- 3. The /evidence classes/: @'RowEq'@ and @'RowShow'@, whose instance bodies
--    are meant to be synthesised as literals by the TcPlugin (§5). They are
--    declared here with @undefined@ defaults so the class /structure/ is fixed
--    before the plugin exists.
--
-- == Why one @Rep@ for both products and sums
--
-- A product is a sum with exactly one constructor. Making that literal rather
-- than a special case buys one uniform representation, so the four quadrants of
-- the design space (nominal product, structural product, structural sum of
-- nominal products, nominal sum of structural products) differ only in what the
-- /type/ says, never in what the /value/ is. For a product the tag is always
-- @0@ and is known statically, so it folds away.
module Polytropos.Core (
    -- * Rows
    Pair(..)
  , Row
  , SumRow
  , ProductRowHKD
  , Field(..)
    -- * Row flavours (Option D vocabulary)
  , RowType(..)
  , RowFlavour(..)
    -- * Handler and result types
  , HandlerType(..)
  , ResultType(..)
    -- * Generic representation
  , Rep(..)
  , repTag
  , repVals
    -- * Ephemeral transient representation
  , MRep(..)
  , thawRep
  , freezeRep
  , writeFieldAt
  , modifyRep
    -- * Row-carrying wrapper (Case 3)
  , RowRep(..)
  , unRowRep
    -- * Construction
  , productRep
  , injectRep
    -- * Access
  , repArity
  , fieldAt
  , setFieldAt
  , setFieldsAt
  , setFieldSumAt
  , projectRep
  , matchRep
    -- * Evidence classes
  , RowEq(..)
  , RowShow(..)
  , RowEqSum(..)
  , RowShowSum(..)
  , FieldIndex(..)
  , ConstructorIndex(..)
  , Dict(..)
  , DictAny(..)
  , mkDictAny
  , evidenceAllFields
  , AllFields(..)
  , DictAllFields
  , ProxyRowFlavour(..)
  , ProductRowProxy
  , SumRowProxy
    -- * Utilities
  , noInlineUnsafeCo
  ) where

import Control.Monad               (forM_)
import Control.Monad.ST            (ST)
import Data.Foldable               (toList)
import Data.Kind                   (Constraint, Type)
import Data.Primitive.SmallArray
-- import Data.Tagged                 (Tagged(..))
import GHC.Exts                    (Any)
import GHC.OverloadedLabels        (IsLabel(..))
import GHC.TypeLits                (Symbol)
import Unsafe.Coerce               (unsafeCoerce)

{-------------------------------------------------------------------------------\n  §1  The row vocabulary\n-------------------------------------------------------------------------------}

-- | A type-level pair: a name bound to a type.
--
-- Poly-kinded with independent parameters, mirroring @large-anon@'s
-- @Pair@ / @:=@. Kept deliberately simple; the @f@-functor parameter that
-- @large-anon@ threads through its rows is future work (see note §1, D3).
data Pair a b = a := b

-- | A zero-cost witness for a type-level field name.
--
-- Can be constructed ergonomically via @OverloadedLabels@ (e.g. @#foo@).
data Field (n :: Symbol) = Field

instance (l ~ l') => IsLabel l (Field l') where
  fromLabel = Field

-- | A /product/ row: an ordered list of field names and field types.
--
-- Order is the identity of the row; two rows with the same fields in a
-- different order are different rows. This is deliberate — it is what lets a
-- field index be a compile-time constant.
type Row = [Pair Symbol Type]

-- | A /sum/ row: an ordered list of constructor names, each carrying the
-- product row of that constructor's fields.
--
-- The tag of a constructor is its position in this list. Constructor arities
-- are therefore the lengths of the nested product rows, and may differ
-- (see note §3, D7).
--
-- NOTE: In the HKD-aware vocabulary this becomes a row whose payload entry is
-- itself a parameterised product row (see `ProductRowHKD`). For now this is
-- the current legacy definition so the existing smoke continues to compile.
--
type SumRow = [Pair Symbol Row]

-- | A product row parameterised by a field functor @f@ (HKD-style).
--
-- Each entry is @\"name\" := f ty@, and the plugin solves field-class evidence
-- over this shape rather than only over bare @Type@ rows.
type ProductRowHKD (f :: Type -> Type) = [Pair Symbol (f Type)]

{-------------------------------------------------------------------------------\n  §1b  Row flavours (Option D vocabulary)\n\n  Concrete row flavours, not kind-polymorphic. Each flavour carries a\n  type-level list of entries; the flavour tells the plugin what kind of\n  entries to expect.\n\n  See PHASE2_SKETCH.md, Piece 1, §1a.\n-------------------------------------------------------------------------------}

-- | The kind of row flavours (Option D).
--
-- Promoted by DataKinds: the types @ProductRowT@, @SumRowT@, @HandlerRowT@,
-- @ResultRowT@ have kind @RowType@, and can be used as the row parameter of
-- 'RowRep' and the evidence classes.
data RowType
  = ProductRowT        -- ^ field name → field type
  | SumRowT            -- ^ constructor name → fieldrow
  | HandlerRowT        -- ^ constructor name → handler type
  | ResultRowT         -- ^ constructor name → result type

-- | The class that abstracts over row flavours.
--
-- Each flavour has an associated 'EntryKind' — the kind of a single entry
-- in a row of that flavour. The plugin uses this to know what to inspect.
class RowFlavour (r :: RowType) where
  -- | The kind of entries in a row of this flavour.
  type EntryKind (r :: RowType) :: Type

-- | A productrow entry: a field name paired with a field type.
instance RowFlavour ProductRowT where
  type EntryKind ProductRowT = Pair Symbol Type

-- | A sumrow entry: a constructor name paired with its fieldrow.
instance RowFlavour SumRowT where
  type EntryKind SumRowT = Pair Symbol Row

-- | A handlerrow entry: a handler type (see 'HandlerType').
-- instance RowFlavour HandlerRowT where  -- reserved for Phase 4
--  type EntryKind HandlerRowT = HandlerType  -- not yet implemented

-- | A result-row entry: a result type (see 'ResultType').
-- instance RowFlavour ResultRowT where  -- reserved for Phase 4
--  type EntryKind ResultRowT = ResultType  -- not yet implemented

-- | A handler type: \"handler for constructor n, with field types fs,
-- returning result type res in monad m\".
--
-- This is the entry kind of 'HandlerRowT'. Each handler entry carries the
-- constructor name, field types, result type, and monad explicitly, so that
-- handler rows are self-contained and can be passed around without a paired
-- sum row (see PHASE2_SKETCH.md, refinement #2).
data HandlerType (n :: Symbol) (fs :: Row) (res :: Type) (m :: Type -> Type)
  = HandlerType

-- | A result type: \"result for constructor n, of type res\".
--
-- This is the entry kind of 'ResultRowT'. Each result entry carries the
-- constructor name and the result type.
data ResultType (n :: Symbol) (res :: Type)
  = ResultType

{-------------------------------------------------------------------------------\n  §1c  The row-carrying wrapper (Case 3)\n\n  'Rep' stays erased (it does not know its row). The wrapper 'RowRep' carries\n  the row in its type, so that the evidence classes can work over 'RowRep'\n  without a 'Proxy' argument (obligation 4, design note §6).\n\n  See PHASE2_SKETCH.md, Piece 1, §1c.\n-------------------------------------------------------------------------------}

-- | Typed, row-carrying wrapper around 'Rep'.
--
-- @f@ is the functor applied to each payload slot.
-- @r@ is the row flavour (one of 'ProductRowT', 'SumRowT', etc.).
-- @row@ is the actual row data (a type-level list of entries), of any kind.
-- @a@ is the value type.
--
-- At runtime this is exactly @Rep f a@ — a newtype with zero cost.
data RowRep (f :: Type -> Type) (r :: RowType) (row :: k) a = RowRep (Rep f a)

-- | Extract the underlying 'Rep' from a 'RowRep'.
unRowRep :: RowRep f r row a -> Rep f a
unRowRep (RowRep r) = r
  -- Note: @k@ is a kind variable that allows any kind for the row data.
  -- For product rows, @row@ has kind @[Pair Symbol Type]@.
  -- For sum rows, @row@ has kind @[Pair Symbol Row]@.
  -- The evidence classes use this flexibility to accept different row kinds.


{-------------------------------------------------------------------------------
  §2  The generic representation
-------------------------------------------------------------------------------}

-- | Generic representation of a product or a sum.
--
-- The layout is exactly the one proposed for this project: a tag plus a flat
-- array of payload slots.
--
-- > newtype Rep f a = Rep (Word#, SmallArray# (f Any))
--
-- written here at the Haskell level, which has the same layout:
-- @{-# UNPACK #-} !Word@ is @Word#@, and @SmallArray (f Any)@ is a
-- @SmallArray# (f Any)@ behind a newtype. @SmallArray@ rather than @Vector@
-- because it stores one pointer per element instead of a three-word box, which
-- is the change @large-generics@ 0.2 made for the same reason.
--
-- @f@ is the functor applied to each payload slot, so that @Rep I@ is
-- isomorphic to the value itself and @Rep Maybe@ boxes the slots.
data Rep (f :: Type -> Type) a = Rep
  {-# UNPACK #-} !Word
  !(SmallArray (f Any))

-- | Constructor index. @0@ for a product.
repTag :: Rep f a -> Word
repTag (Rep t _) = t

-- | Payload slots, in row order, of the /selected/ constructor.
repVals :: Rep f a -> SmallArray (f Any)
repVals (Rep _ v) = v

-- | Materialise the payload slots as a list, in row order.
toListSlots :: SmallArray (f Any) -> [f Any]
toListSlots = toList

-- | How many payload slots the selected constructor has.
repArity :: Rep f a -> Int
repArity = sizeofSmallArray . vals

  where
    vals (Rep _ v) = v

{-------------------------------------------------------------------------------\n  §2b  Ephemeral transient representation\n-------------------------------------------------------------------------------}

-- | Ephemeral mutable representation for in-place construction and deserialization.
data MRep s (f :: Type -> Type) a = MRep
  {-# UNPACK #-} !Word
  !(SmallMutableArray s (f Any))

-- | Safely thaw an immutable 'Rep' into a mutable builder.
thawRep :: Rep f a -> ST s (MRep s f a)
thawRep (Rep t v) = do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  pure (MRep t m)

-- | Safely freeze an ephemeral builder into an immutable 'Rep'.
freezeRep :: MRep s f a -> ST s (Rep f a)
freezeRep (MRep t m) = do
  v <- unsafeFreezeSmallArray m
  pure (Rep t v)

-- | In-place slot write (@O(1)@, zero allocation).
writeFieldAt :: MRep s f a -> Int -> f Any -> ST s ()
writeFieldAt (MRep _ m) i !x = writeSmallArray m i x

-- | Scoped pure modification wrapper.
modifyRep :: Rep f a -> (forall s. MRep s f a -> ST s ()) -> Rep f a
modifyRep (Rep t v) act = Rep t $ runSmallArray $ do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  act (MRep t m)
  pure m

{-------------------------------------------------------------------------------\n  §3  Construction\n-------------------------------------------------------------------------------}

-- | Build a product from its field values, in row order.
--
-- The tag is @0@: a product is the one-constructor sum.
productRep :: [f Any] -> Rep f a
productRep xs = Rep 0 (smallArrayFromList xs)

-- | Build a sum value carrying the given tag and that constructor's fields.
injectRep :: Word -> [f Any] -> Rep f a
injectRep t xs = Rep t (smallArrayFromList xs)

{-------------------------------------------------------------------------------\n  §4  Access\n-------------------------------------------------------------------------------}

-- | Read the payload slot at a compile-time-known index.
--
-- The @x@ is not determined by the index alone; it comes from the row type. The
-- coercion is unchecked, exactly as in @large-anon@: the index is only ever
-- produced by the plugin from a row that actually has that field.
fieldAt :: forall f a x. Int -> Rep f a -> f x
fieldAt i r = noInlineUnsafeCo (indexSmallArray (repVals r) i)

-- | Replace the payload slot at a compile-time-known index.
--
-- @O(n)@: primitive Copy-on-Write via 'thawSmallArray' and 'writeSmallArray',
-- performing a single contiguous array allocation and single in-place slot write.
setFieldAt :: forall f a. Int -> f Any -> Rep f a -> Rep f a
setFieldAt i !x (Rep t v) = Rep t $ runSmallArray $ do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  writeSmallArray m i x
  pure m

-- | Clone once, apply K updates in-place, freeze once.
--
-- Reduces multi-field update overhead from @K * O(N)@ to @1 * O(N)@.
setFieldsAt :: forall f a. [(Int, f Any)] -> Rep f a -> Rep f a
setFieldsAt [] r = r
setFieldsAt updates (Rep t v) = Rep t $ runSmallArray $ do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  forM_ updates $ \(i, !x) -> writeSmallArray m i x
  pure m

-- | Partial field update for sum constructors.
--
-- Ensures the runtime tag matches the expected constructor tag before updating.
setFieldSumAt :: forall f a. Word -> Int -> f Any -> Rep f a -> Maybe (Rep f a)
setFieldSumAt expectedTag idx !val r@(Rep t _)
  | t == expectedTag = Just (setFieldAt idx val r)
  | otherwise        = Nothing

-- | Project a constructor, or 'Nothing' if the tag does not match.
--
-- A sum over a /superset/ of the row can therefore be narrowed, but only
-- observably: the failure is a 'Nothing', not a type error. See note §3, D8 for
-- why widening is total and narrowing is not.
projectRep :: Word -> Rep f a -> Maybe [f Any]
projectRep t (Rep t' v)
  | t == t'  = Just (toListSlots v)
  | otherwise = Nothing

-- | Eliminate a sum: hand the tag and the selected payload to a continuation.
--
-- The continuation sees the tag, so the unmatched case is the continuation's
-- own business; this primitive does not decide it. The elimination story is
-- unsettled — see note §4.
matchRep :: (Word -> [f Any] -> a) -> Rep f a -> a
matchRep k r = k (repTag r) (toListSlots (repVals r))

{-------------------------------------------------------------------------------\n  §5  Evidence classes\n\n  The instance bodies are intended to be produced as integer literals by the\n  TcPlugin, the same way @large-anon@ produces @DictRowHasField@. Until the\n  plugin exists, the defaults are @undefined@; the concrete instances in the\n  test suite are hand-written and stand in for what the plugin will emit.\n-------------------------------------------------------------------------------}

-- | Field-wise equality for a product row.
--
-- The method works over 'RowRep', so the row is in the type and no 'Proxy'
-- argument is needed (obligation 4, design note §6). A plugin will build the
-- body by substituting literal slot indices and a literal element count, so
-- there is no type-level search at the use site.
--
-- The test suite writes these bodies by hand, which makes the tests the
-- specification of what the plugin must emit.
class RowFlavour r => RowEq (r :: RowType) (row :: k) where
  repEq :: RowRep f r row a -> RowRep f r row a -> Bool
  repEq _ _ = undefined

-- | Field-wise @Show@ for a product row. See 'RowEq' for the design.
class RowFlavour r => RowShow (r :: RowType) (row :: k) where
  repShowsPrec :: Int -> RowRep f r row a -> ShowS
  repShowsPrec _ _ = undefined

-- | Field-wise equality for a sum row.
--
-- Sums need their own class because the comparison includes the tag (the
-- constructor index), which products don't have (their tag is always 0 and
-- folds away).
class RowFlavour r => RowEqSum (r :: RowType) (row :: k) where
  repEqSum :: RowRep f r row a -> RowRep f r row a -> Bool
  repEqSum _ _ = undefined

-- | Field-wise @Show@ for a sum row.
class RowFlavour r => RowShowSum (r :: RowType) (row :: k) where
  repShowsPrecSum :: Int -> RowRep f r row a -> ShowS
  repShowsPrecSum _ _ = undefined

-- | Evidence that a field name @n@ has a slot at a known index in a row.
--
-- The plugin solves this by inspecting the row and emitting the index as a
-- literal (obligation 1, design note §5).
class FieldIndex (n :: Symbol) (row :: k) (a :: Type) where
  fieldIndex :: Int
  fieldIndex = undefined

-- | Evidence that a constructor name @n@ has a known tag in a row.
--
-- The plugin solves this by inspecting the row and emitting the tag as a
-- literal (obligation 2, design note §5).
class ConstructorIndex (n :: Symbol) (row :: k) where
  constructorIndex :: Word
  constructorIndex = undefined

-- | Witness for a class constraint @c a@.
data Dict (c :: Type -> Constraint) (a :: Type) where
  Dict :: c a => Dict c a

-- | Evidence that all fields of a row satisfy some class.
--
-- @DictAny c@ is the type-erased form of @c Any@, mirroring @large-anon@'s
-- dictionary packing. It is what lets one dictionary carry many field
-- dictionaries without a type-level list of them.
data DictAny (c :: Type -> Constraint) where
  DictAny :: c Any => DictAny c

-- | Wrap a class dictionary into 'DictAny'.
mkDictAny :: forall c a. c a => DictAny c
mkDictAny = aux (noInlineUnsafeCo (Dict :: Dict c a) :: Dict c Any)
  where
    aux :: Dict c Any -> DictAny c
    aux Dict = DictAny

-- | Construct evidence for the 'AllFields' class.
{-# NOINLINE evidenceAllFields #-}
evidenceAllFields :: forall c. [DictAny c] -> DictAllFields c
evidenceAllFields = smallArrayFromList

-- | The evidence type for 'AllFields': a flat array of type-erased per-field
-- dictionaries, in row order.
type DictAllFields (c :: Type -> Constraint) = SmallArray (DictAny c)

-- | Evidence that every field in a row satisfies a class.
--
-- This is the generic dictionary-supply class the plugin solves
-- for fully-known rows. Its evidence is a flat array of type-erased field
-- dictionaries, in row order, so callers can map/fold over all fields without
-- writing per-row instances by hand.
--
-- The class is kind-polymorphic in the row parameter so the same surface can
-- be reused for the legacy @Row@ rows and for the HKD-aware product and sum rows
-- once those are layered on top. The row flavour parameter remains so the
-- plugin can distinguish product vs sum rows.
type AllFields :: forall {k}. RowType -> k -> (Type -> Constraint) -> Constraint
class RowFlavour r => AllFields (r :: RowType) (row :: k) (c :: Type -> Constraint) where
  fieldDicts :: DictAllFields c
  fieldDicts = undefined

-- | A stand-in proxy for the row flavour. This is used in the smoke test as a
-- placeholder for the row-flavour parameter of 'AllFields' until the row
-- vocabulary is finalised and the class is re-indexed.
data ProxyRowFlavour (r :: RowType) = ProxyRowFlavour
  deriving (Show)

-- | The row-flavour proxy for product rows, used in the smoke test.
type ProductRowProxy = ProxyRowFlavour ProductRowT

-- | The row-flavour proxy for sum rows, for use in the smoke test once sum
-- rows are exercised.
type SumRowProxy = ProxyRowFlavour SumRowT

-- | A type-level proxy for the TwoInts row, used in the smoke test as a
-- placeholder until the row vocabulary is finalised.
{-------------------------------------------------------------------------------\n  §6  Utilities\n-------------------------------------------------------------------------------}

-- | @unsafeCoerce@ that survives GHC's Core linter.
--
-- Must be marked @NOINLINE@: @large-anon@ found that without it, GHC 9.6
-- produces @-dcore-lint@ errors for the evidence built on top of this.
noInlineUnsafeCo :: a -> b
{-# NOINLINE noInlineUnsafeCo #-}
noInlineUnsafeCo = unsafeCoerce
