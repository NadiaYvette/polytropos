{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}

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
    -- * Generic representation
  , Rep(..)
    -- * Construction
  , productRep
  , injectRep
    -- * Access
  , repArity
  , fieldAt
  , setFieldAt
  , projectRep
  , matchRep
    -- * Evidence classes
  , RowEq(..)
  , RowShow(..)
  , DictAny(..)
    -- * Utilities
  , noInlineUnsafeCo
  ) where

import Data.Foldable                 (toList)
import Data.Kind                   (Constraint, Type)
import Data.Proxy                  (Proxy(..))
import Data.Primitive.SmallArray
import GHC.Exts                    (Any)
import GHC.TypeLits                (Symbol)
import Unsafe.Coerce               (unsafeCoerce)

{-------------------------------------------------------------------------------
  §1  The row vocabulary
-------------------------------------------------------------------------------}

-- | A type-level pair: a name bound to a type.
--
-- Poly-kinded with independent parameters, mirroring @large-anon@'s
-- @Pair@ / @:=@. Kept deliberately simple; the @f@-functor parameter that
-- @large-anon@ threads through its rows is future work (see note §1, D3).
data Pair a b = a := b

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
type SumRow = [Pair Symbol Row]

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
  { repTag  :: {-# UNPACK #-} !Word
    -- ^ Constructor index. @0@ for a product.
  , repVals :: !(SmallArray (f Any))
    -- ^ Payload slots, in row order, of the /selected/ constructor.
  }

-- | Materialise the payload slots as a list, in row order.
toListSlots :: SmallArray (f Any) -> [f Any]
toListSlots = toList

-- | How many payload slots the selected constructor has.
repArity :: Rep f a -> Int
repArity = sizeofSmallArray . vals

  where
    vals (Rep _ v) = v

{-------------------------------------------------------------------------------
  §3  Construction
-------------------------------------------------------------------------------}

-- | Build a product from its field values, in row order.
--
-- The tag is @0@: a product is the one-constructor sum.
productRep :: [f Any] -> Rep f a
productRep xs = Rep 0 (smallArrayFromList xs)

-- | Build a sum value carrying the given tag and that constructor's fields.
injectRep :: Word -> [f Any] -> Rep f a
injectRep t xs = Rep t (smallArrayFromList xs)

{-------------------------------------------------------------------------------
  §4  Access
-------------------------------------------------------------------------------}

-- | Read the payload slot at a compile-time-known index.
--
-- The @x@ is not determined by the index alone; it comes from the row type. The
-- coercion is unchecked, exactly as in @large-anon@: the index is only ever
-- produced by the plugin from a row that actually has that field.
fieldAt :: forall f a x. Int -> Rep f a -> f x
fieldAt i r = noInlineUnsafeCo (indexSmallArray (repVals r) i)

-- | Replace the payload slot at a compile-time-known index.
--
-- @O(n)@: the array is rebuilt from a list. A plugin that knows the arity can
-- do better, and note §2, 'Known cost' of the
-- rebuild-in-place-avoiding representation.
setFieldAt :: forall f a. Int -> f Any -> Rep f a -> Rep f a
setFieldAt i x r = r { repVals = smallArrayFromList (go 0 (toListSlots (repVals r))) }
  where
    go :: Int -> [f Any] -> [f Any]
    go j ys
      | j == i    = case ys of
          _ : ys' -> x : ys'
          []      -> [x]
      | otherwise = case ys of
          y : ys' -> y : go (succ j) ys'
          []      -> []

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

{-------------------------------------------------------------------------------
  §5  Evidence classes

  The instance bodies are intended to be produced as integer literals by the
  TcPlugin, the same way @large-anon@ produces @DictRowHasField@. Until the
  plugin exists, the defaults are @undefined@; the concrete instances in the
  test suite are hand-written and stand in for what the plugin will emit.
-------------------------------------------------------------------------------}

-- | Evidence that all fields of a row satisfy some class.
--
-- @DictAny c@ is the type-erased form of @c x@, mirroring @large-anon@'s
-- dictionary packing. It is what lets one dictionary carry many field
-- dictionaries without a type-level list of them.
data DictAny (c :: Type -> Constraint) where
  DictAny :: c x => DictAny c

-- | Field-wise equality for a product or a sum row.
--
-- The method is /polymorphic in the representation/: one dictionary compares
-- any @Rep f a@ known to have row @r@. A plugin will build the body by
-- substituting literal slot indices and a literal element count, so there is
-- no type-level search at the use site. The test suite writes these bodies by
-- hand, which makes the tests the specification of what the plugin must emit.
--
-- == Why the row is an explicit argument
--
-- 'Rep' is deliberately /not/ indexed by its row: it is the erased runtime
-- form, and products and sums share it. The cost is that @RowEq r@ cannot be
-- solved from the arguments alone, so the row is passed as a 'Proxy'.
--
-- This is a known ergonomic debt, not a neutral choice. @large-anon@ does not
-- pay it because its @Record f r@ carries the row in the type, so
-- @RowHasField n r a@ resolves from the value's own type. Closing this gap is
-- one of the plugin's jobs: see note §6.
class RowEq (r :: Row) where
  repEq :: Proxy r -> Rep f a -> Rep f a -> Bool
  repEq _ _ _ = undefined

-- | Field-wise @Show@ for a product or a sum row. See 'RowEq' for the 'Proxy'.
class RowShow (r :: Row) where
  repShowsPrec :: Proxy r -> Int -> Rep f a -> ShowS
  repShowsPrec _ _ _ = undefined

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
