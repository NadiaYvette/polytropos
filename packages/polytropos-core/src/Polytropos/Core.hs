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
-- 2. The /generic representation/: @t'Rep'@, a runtime tag plus a flat array of
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
  , Field(..)
  , RowOf
  , Row
  , ProductRow
  , ProductRowHKD
  , SumRowOf
  , SumRow
  , SumRowHKD
  , SumRowF
    -- * Type-level row metadata
  , FieldNames
  , SimpleFieldTypes
  , FieldTypes
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
  , thawRepSlice
  , freezeRep
  , writeFieldAt
  , writeFieldsAt
  , copyFieldsFrom
  , copyMFields
  , newMRep
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
  , peelRep
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
  , SubRow(..)
  , SubSum(..)
  , KnownHash(..)
  , labelHash
  , hashVal
  , fnv1a64
  , ProxyRowFlavour(..)
  , ProductRowProxy
  , SumRowProxy
  , ProductRowHKDProxy
  , SumRowHKDProxy
    -- * Utilities
  , noInlineUnsafeCo
  ) where

import Control.Monad               (forM_, when)
import Control.Monad.ST            (ST)
import Data.Bits                   (xor)
import Data.Char                   (ord)
import Data.Foldable               (toList)
import Data.Kind                   (Constraint, Type)
import Data.List                   (sortOn)
import Data.Primitive.SmallArray
import Data.Word                   (Word64)
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

-- | A poly-kinded row whose entries have kind @k@.
--
-- Poly-kinded over entry kind @k@, mirroring @large-anon@'s @Row k@.
type RowOf k = [Pair Symbol k]

-- | A /product/ row: an ordered list of field names and field types.
--
-- Order is the identity of the row; two rows with the same fields in a
-- different order are different rows. This is deliberate — it is what lets a
-- field index be a compile-time constant.
type Row = RowOf Type

-- | An HKD-aware product row parameterised by a field functor @f@.
--
-- In an HKD-aware product row, each field value is wrapped in the functor @f@.
-- Since @f ty@ has kind 'Type' for any @ty :: Type@, this is an alias for
-- a row where field types are parameterised by @f@.
type ProductRow (f :: Type -> Type) = RowOf Type

-- | Synonym for 'ProductRow'.
type ProductRowHKD (f :: Type -> Type) = ProductRow f

-- | A poly-kinded sum row whose constructor payloads have product kind @prod@.
type SumRowOf prod = [Pair Symbol prod]

-- | A /sum/ row: an ordered list of constructor names, each carrying the
-- product row of that constructor's fields.
--
-- The tag of a constructor is its position in this list. Constructor arities
-- are therefore the lengths of the nested product rows, and may differ
-- (see note §3, D7).
type SumRow = SumRowOf Row

-- | An HKD-aware sum row parameterised by a field functor @f@.
-- Each constructor carries an HKD product row.
type SumRowHKD (f :: Type -> Type) = SumRowOf (ProductRow f)

-- | Synonym for 'SumRowHKD'.
type SumRowF (f :: Type -> Type) = SumRowHKD f

{-------------------------------------------------------------------------------
  §1b  Type-level row metadata (rewritten by TcPlugin)

  Closed-form type families without Haskell-level equations. When a row is
  fully known, the TcPlugin rewrites these type families to concrete type-level
  lists, enabling generic programming over field names and field types.
-------------------------------------------------------------------------------}

-- | Extract field names as a type-level list of 'Symbol's.
--
-- For each field @"name" ':= ty@ in the row, this evaluates to @"name"@.
-- When the row is fully known, the TcPlugin rewrites this type family to a
-- concrete type-level list of symbols.
type family FieldNames (r :: k) :: [Symbol]

-- | Extract field names and bare field types as a type-level list of pairs.
--
-- For each field @"name" ':= ty@ in the row, this evaluates to @'("name", ty)@.
-- When the row is fully known, the TcPlugin rewrites this type family to a
-- concrete type-level list of pairs.
type family SimpleFieldTypes (r :: k) :: [(Symbol, Type)]

-- | Extract field names and instantiated field types as a type-level list of pairs.
--
-- For each field @"name" ':= ty@ in the row, this evaluates to @'("name", f ty)@.
-- When the row is fully known, the TcPlugin rewrites this type family to a
-- concrete type-level list of pairs.
type family FieldTypes (f :: Type -> Type) (r :: k) :: [(Symbol, Type)]

{-------------------------------------------------------------------------------\n  §1b  Row flavours (Option D vocabulary)\n\n  Concrete row flavours, not kind-polymorphic. Each flavour carries a\n  type-level list of entries; the flavour tells the plugin what kind of\n  entries to expect.\n\n  See PHASE2_SKETCH.md, Piece 1, §1a.\n-------------------------------------------------------------------------------}

-- | The kind of row flavours (Option D).
--
-- Promoted by DataKinds: the types @ProductRowT@, @SumRowT@, @HandlerRowT@,
-- @ResultRowT@ have kind @RowType@, and can be used as the row parameter of
-- t'RowRep' and the evidence classes.
data RowType
  = ProductRowT        -- ^ field name → field type
  | SumRowT            -- ^ constructor name → fieldrow
  | HandlerRowT        -- ^ constructor name → handler type
  | ResultRowT         -- ^ constructor name → result type
  | ProductRowHKDT     -- ^ field name → f (field type)
  | SumRowHKDT         -- ^ constructor name → ProductRow f

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

-- | An HKD-aware productrow entry: a field name paired with an applied functor type.
instance RowFlavour ProductRowHKDT where
  type EntryKind ProductRowHKDT = Pair Symbol Type

-- | An HKD-aware sumrow entry: a constructor name paired with an HKD productrow.
instance RowFlavour SumRowHKDT where
  type EntryKind SumRowHKDT = Pair Symbol Row

-- | A handlerrow entry: a handler type (see t'HandlerType').
instance RowFlavour HandlerRowT where
  type EntryKind HandlerRowT = Pair Symbol Type

-- | A result-row entry: a result type (see t'ResultType').
instance RowFlavour ResultRowT where
  type EntryKind ResultRowT = Pair Symbol Type

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

{-------------------------------------------------------------------------------
  §1c  The row-carrying wrapper (Case 3)

  t'Rep' stays erased (it does not know its row). The wrapper t'RowRep' carries
  the row in its type, so that the evidence classes can work over t'RowRep'
  without a 'Data.Proxy.Proxy' argument (obligation 4, design note §6).

  See PHASE2_SKETCH.md, Piece 1, §1c.
-------------------------------------------------------------------------------}

-- | Typed, row-carrying wrapper around t'Rep'.
--
-- @f@ is the functor applied to each payload slot.
-- @r@ is the row flavour (one of 'ProductRowT', 'SumRowT', etc.).
-- @row@ is the actual row data (a type-level list of entries), of any kind.
-- @a@ is the value type.
--
-- At runtime this is exactly @Rep f a@ — a newtype with zero cost.
data RowRep (f :: Type -> Type) (r :: RowType) (row :: k) a = RowRep (Rep f a)

-- | Extract the underlying t'Rep' from a t'RowRep'.
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

-- | Allocate a new mutable t'MRep' pre-initialized with a default payload.
newMRep :: Word -> Int -> f Any -> ST s (MRep s f a)
newMRep tag n defaultVal = do
  m <- newSmallArray n defaultVal
  pure (MRep tag m)

-- | Safely thaw an immutable t'Rep' into a mutable builder.
thawRep :: Rep f a -> ST s (MRep s f a)
thawRep (Rep t v) = do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  pure (MRep t m)

-- | Safely thaw a sub-slice of an immutable t'Rep' into a mutable builder.
thawRepSlice :: Rep f a -> Int -> Int -> ST s (MRep s f a)
thawRepSlice (Rep t v) off len = do
  m <- thawSmallArray v off len
  pure (MRep t m)

-- | Safely freeze an ephemeral builder into an immutable t'Rep'.
freezeRep :: MRep s f a -> ST s (Rep f a)
freezeRep (MRep t m) = do
  v <- unsafeFreezeSmallArray m
  pure (Rep t v)

-- | In-place slot write (@O(1)@, zero allocation).
writeFieldAt :: MRep s f a -> Int -> f Any -> ST s ()
writeFieldAt (MRep _ m) i !x = writeSmallArray m i x

-- | In-place batch slot writes (@O(K)@, zero allocations).
writeFieldsAt :: MRep s f a -> [(Int, f Any)] -> ST s ()
writeFieldsAt (MRep _ m) updates =
  forM_ updates $ \(i, !x) -> writeSmallArray m i x

-- | Batch copy of a slice of fields from an immutable t'Rep' into an t'MRep'.
copyFieldsFrom :: Rep f a -> Int -> MRep s f a -> Int -> Int -> ST s ()
copyFieldsFrom (Rep _ src) srcOff (MRep _ dst) dstOff len =
  copySmallArray dst dstOff src srcOff len

-- | In-place batch block copy between mutable builders.
copyMFields :: MRep s f a -> Int -> MRep s f a -> Int -> Int -> ST s ()
copyMFields (MRep _ src) srcOff (MRep _ dst) dstOff len =
  copySmallMutableArray dst dstOff src srcOff len

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
-- For records with @>32@ fields (Milestone T3), uses hardware-vectorized SIMD
-- non-overlapping block copies ('copySmallArray'), eliminating redundant reads
-- and writes of slot @i@ from the source array.
--
-- For small records (@<=32@ fields), uses direct in-cache 'thawSmallArray'.
setFieldAt :: forall f a. Int -> f Any -> Rep f a -> Rep f a
setFieldAt i !x (Rep t v)
  | n > 32 = Rep t $ runSmallArray $ do
      m <- newSmallArray n x
      when (i > 0) $
        copySmallArray m 0 v 0 i
      let !after = i + 1
          !lenAfter = n - after
      when (lenAfter > 0) $
        copySmallArray m after v after lenAfter
      pure m
  | otherwise = Rep t $ runSmallArray $ do
      m <- thawSmallArray v 0 n
      writeSmallArray m i x
      pure m
  where
    !n = sizeofSmallArray v

-- | Clone once, apply K updates in-place, freeze once.
--
-- Reduces multi-field update overhead from @K * O(N)@ to @1 * O(N)@.
-- For records with @>32@ fields (Milestone T3), sorts update offsets and copies
-- non-overlapping unchanged slices in contiguous vectorized blocks.
setFieldsAt :: forall f a. [(Int, f Any)] -> Rep f a -> Rep f a
setFieldsAt [] r = r
setFieldsAt [(!i, !x)] r = setFieldAt i x r
setFieldsAt updates (Rep t v)
  | n > 32, (firstUpd : _) <- updates = Rep t $ runSmallArray $ do
      let sortedUpds = sortOn fst updates
      m <- newSmallArray n (snd firstUpd)
      let copySlices curIdx [] = do
            when (curIdx < n) $
              copySmallArray m curIdx v curIdx (n - curIdx)
          copySlices curIdx ((i, !x) : rest)
            | i < curIdx = do
                writeSmallArray m i x
                copySlices curIdx rest
            | otherwise = do
                when (i > curIdx) $
                  copySmallArray m curIdx v curIdx (i - curIdx)
                writeSmallArray m i x
                copySlices (i + 1) rest
      copySlices 0 sortedUpds
      pure m
  | otherwise = Rep t $ runSmallArray $ do
      m <- thawSmallArray v 0 n
      forM_ updates $ \(i, !x) -> writeSmallArray m i x
      pure m
  where
    !n = sizeofSmallArray v

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

-- | Peel a target tag from a sum representation in \(\mathcal{O}(1)\) time.
--
-- If @repTag r == targetTag@, returns @Right (toListSlots (repVals r))@.
-- Otherwise, returns @Left r'@ where the remaining tag is preserved if
-- @repTag r < targetTag@, or decremented by 1 if @repTag r > targetTag@.
--
-- Complexity: \(\mathcal{O}(1)\) time, requiring zero array payload copying or allocations.
peelRep :: Word -> Rep f a -> Either (Rep f a) [f Any]
peelRep targetTag (Rep t v)
  | t == targetTag = Right (toListSlots v)
  | t < targetTag  = Left (Rep t v)
  | otherwise      = Left (Rep (t - 1) v)

{-------------------------------------------------------------------------------\n  §5  Evidence classes\n\n  The instance bodies are intended to be produced as integer literals by the\n  TcPlugin, the same way @large-anon@ produces @DictRowHasField@. Until the\n  plugin exists, the defaults are @undefined@; the concrete instances in the\n  test suite are hand-written and stand in for what the plugin will emit.\n-------------------------------------------------------------------------------}

-- | Field-wise equality for a product row.
--
-- The method works over t'RowRep', so the row is in the type and no 'Data.Proxy.Proxy'
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

-- | Evidence that a field name or type @n@ has a slot at a known index in a row.
--
-- The plugin solves this by inspecting the row and emitting the index as a
-- literal (obligation 1, design note §5).
type FieldIndex :: forall {kn} k {ka}. kn -> k -> ka -> Constraint
class FieldIndex (n :: kn) (row :: k) (a :: ka) where
  fieldIndex :: Int
  fieldIndex = undefined

-- | Evidence that a constructor name or type @n@ has a known tag in a row.
--
-- The plugin solves this by inspecting the row and emitting the tag as a
-- literal (obligation 2, design note §5).
type ConstructorIndex :: forall {kn} k. kn -> k -> Constraint
class ConstructorIndex (n :: kn) (row :: k) where
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

-- | Wrap a class dictionary into t'DictAny'.
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

-- | The row-flavour proxy for HKD product rows.
type ProductRowHKDProxy = ProxyRowFlavour ProductRowHKDT

-- | The row-flavour proxy for HKD sum rows.
type SumRowHKDProxy = ProxyRowFlavour SumRowHKDT

{-------------------------------------------------------------------------------
  Standard type class instances for RowRep (§1.7 Generic instance layer)
-------------------------------------------------------------------------------}

-- | Standard 'Eq' instance for product rows, backed by 'RowEq'.
instance RowEq ProductRowT row => Eq (RowRep f ProductRowT row a) where
  (==) = repEq

-- | Standard 'Show' instance for product rows, backed by 'RowShow'.
instance RowShow ProductRowT row => Show (RowRep f ProductRowT row a) where
  showsPrec = repShowsPrec

-- | Standard 'Ord' instance for product rows, backed by 'AllFields'.
instance (RowEq ProductRowT row, AllFields ProductRowT row Ord) => Ord (RowRep f ProductRowT row a) where
  compare (RowRep r1) (RowRep r2) =
    let dicts = fieldDicts @ProductRowT @row @Ord
        v1 = repVals r1
        v2 = repVals r2
        n = sizeofSmallArray v1
        loop i
          | i == n = EQ
          | otherwise =
              case indexSmallArray dicts i of
                DictAny ->
                  let x1 :: Any
                      x1 = noInlineUnsafeCo (indexSmallArray v1 i)
                      x2 :: Any
                      x2 = noInlineUnsafeCo (indexSmallArray v2 i)
                  in case compare x1 x2 of
                       EQ -> loop (i + 1)
                       other -> other
    in loop 0

-- | Standard 'Eq' instance for HKD product rows, backed by 'RowEq'.
instance RowEq ProductRowHKDT row => Eq (RowRep f ProductRowHKDT row a) where
  (==) = repEq

-- | Standard 'Show' instance for HKD product rows, backed by 'RowShow'.
instance RowShow ProductRowHKDT row => Show (RowRep f ProductRowHKDT row a) where
  showsPrec = repShowsPrec

-- | Standard 'Ord' instance for HKD product rows, backed by 'AllFields'.
instance (RowEq ProductRowHKDT row, AllFields ProductRowHKDT row Ord) => Ord (RowRep f ProductRowHKDT row a) where
  compare (RowRep r1) (RowRep r2) =
    let dicts = fieldDicts @ProductRowHKDT @row @Ord
        v1 = repVals r1
        v2 = repVals r2
        n = sizeofSmallArray v1
        loop i
          | i == n = EQ
          | otherwise =
              case indexSmallArray dicts i of
                DictAny ->
                  let x1 :: Any
                      x1 = noInlineUnsafeCo (indexSmallArray v1 i)
                      x2 :: Any
                      x2 = noInlineUnsafeCo (indexSmallArray v2 i)
                  in case compare x1 x2 of
                       EQ -> loop (i + 1)
                       other -> other
    in loop 0

-- | Standard 'Eq' instance for sum rows, backed by 'RowEqSum'.
instance RowEqSum SumRowT row => Eq (RowRep f SumRowT row a) where
  (==) = repEqSum

-- | Standard 'Show' instance for sum rows, backed by 'RowShowSum'.
instance RowShowSum SumRowT row => Show (RowRep f SumRowT row a) where
  showsPrec = repShowsPrecSum

-- | Standard 'Eq' instance for HKD sum rows, backed by 'RowEqSum'.
instance RowEqSum SumRowHKDT row => Eq (RowRep f SumRowHKDT row a) where
  (==) = repEqSum

-- | Standard 'Show' instance for HKD sum rows, backed by 'RowShowSum'.
instance RowShowSum SumRowHKDT row => Show (RowRep f SumRowHKDT row a) where
  showsPrec = repShowsPrecSum

{-------------------------------------------------------------------------------
  §5b  Subrow and Subsum evidence classes
-------------------------------------------------------------------------------}

-- | Sub-row relationship between two product rows.
--
-- @'SubRow' sub super@ holds when every field in @sub@ occurs in @super@ with
-- the same field type. The plugin emits the 0-based projection slot indices
-- as evidence.
type SubRow :: forall {k1} {k2}. k1 -> k2 -> Constraint
class SubRow (sub :: k1) (super :: k2) where
  -- | For each field in @sub@, its 0-based slot index in @super@.
  subRowIndices :: [Int]
  subRowIndices = undefined

-- | Sub-sum relationship between two sum rows (variant widening & narrowing).
--
-- @'SubSum' sub super@ holds when every constructor in @sub@ occurs in @super@
-- with identical field rows. The plugin emits the injection tag indices
-- (for widening) and narrowing tag indices (for projection) as evidence.
type SubSum :: forall {k1} {k2}. k1 -> k2 -> Constraint
class SubSum (sub :: k1) (super :: k2) where
  -- | For each constructor in @sub@, its tag in @super@ (widening).
  subSumInjectIndices :: [Word]
  subSumInjectIndices = undefined

  -- | For each constructor in @super@, its tag in @sub@ if present, or 'Nothing'
  -- if it does not belong to @sub@ (narrowing).
  subSumNarrowIndices :: [Maybe Word]
  subSumNarrowIndices = undefined

{-------------------------------------------------------------------------------
  §5c  Compile-time label hashing
-------------------------------------------------------------------------------}

-- | Class providing a compile-time hash for a label 'Symbol'.
--
-- The @TcPlugin@ solves this by evaluating the hash (FNV-1a 64-bit) of the literal
-- symbol at compile time and emitting a literal 'Word' dictionary.
--
-- == Purpose and Non-Purpose
--
-- * __Purpose:__ @'KnownHash'@ provides O(1) integer keys for dynamic/HAMT label
--   dispatch, label interning, and name-based field lookup without requiring
--   'GHC.TypeLits.KnownSymbol' dictionary plumbing or runtime string hashing in hot paths.
--
-- * __Non-purpose:__ @'KnownHash'@ is /not/ used for slot offset indexing in
--   records and sums. Record slot access in @polytropos@ is statically determined
--   at compile time by 'FieldIndex' and 'ConstructorIndex' (0, 1, 2, ...), which are
--   dense, collision-free literal offsets into 'Polytropos.Rep.repVals'.
type KnownHash :: Symbol -> Constraint
class KnownHash (s :: Symbol) where
  -- | Literal compile-time hash for label @s@.
  knownHash :: Word
  knownHash = undefined

-- | Ergonomic helper to extract the compile-time hash of a label via a proxy
-- (such as t'Field' or 'Data.Proxy.Proxy').
labelHash :: forall (s :: Symbol) proxy. KnownHash s => proxy s -> Word
labelHash _ = knownHash @s

-- | Synonymous with 'labelHash' for compatibility with large-record conventions.
hashVal :: forall (s :: Symbol) proxy. KnownHash s => proxy s -> Word
hashVal _ = knownHash @s

-- | FNV-1a 64-bit hash of a 'String', matching the hash computed at compile-time
-- by the @TcPlugin@ for 'KnownHash'.
fnv1a64 :: String -> Word
fnv1a64 str = fromIntegral (foldl' step (14695981039346656037 :: Word64) str)
  where
    step !h !c = (h `xor` fromIntegral (ord c)) * 1099511628211

{-------------------------------------------------------------------------------
  §6  Utilities
-------------------------------------------------------------------------------}

-- | @unsafeCoerce@ that survives GHC's Core linter.
--
-- Must be marked @NOINLINE@: @large-anon@ found that without it, GHC 9.6
-- produces @-dcore-lint@ errors for the evidence built on top of this.
noInlineUnsafeCo :: a -> b
{-# NOINLINE noInlineUnsafeCo #-}
noInlineUnsafeCo = unsafeCoerce
