{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

-- | A plugin-free structural variant, for benchmarking.
--
-- This is the design an extensible-variant library converges on when it does
-- /not/ have a GHC plugin: a runtime tag (the index of the constructor in the
-- row) plus a boxed payload, with the index computed at compile time by a
-- type-level search over the row.
--
-- == Why the search is written the way it is
--
-- The natural way to write 'Idx' is a closed type family that compares the
-- sought name against each head of the row. That cannot be written directly,
-- because a type family can match on type constructors, type literals and
-- variables, but it cannot test two type variables for equality, so it cannot
-- branch on @n == m@. The standard workaround (used by every plugin-free
-- library in this space --- @row-types@, @vary@, @extensible@) is either
-- overlapping class instances, or a conditional: compute @n == m@ and select
-- with a type-level @If@. This module uses the latter, which keeps the row a
-- plain @[Symbol]@ / @[Type]@ pair.
--
-- That search is exactly the work a TcPlugin would replace with a
-- compile-time-computed literal, so this module is the honest baseline to
-- measure against.
module Bench.StructVariant (
    -- * Rows
    Variant
  , Names
  , Payloads
    -- * Type-level search
  , Idx
  , Pld
    -- * Operations
  , mkVariant
  , asVariant
  , natToInt
  , tagOf
  , widenC
  , caseTag
  ) where

import Data.Kind            (Type)
import Data.Proxy           (Proxy(..))
import Data.Type.Equality   (type (==))
import GHC.Exts             (Any)
import GHC.TypeLits         (ErrorMessage(..), KnownNat, Nat, Symbol, TypeError, natVal)
import GHC.TypeLits         (type (+))
import Unsafe.Coerce        (unsafeCoerce)

{-------------------------------------------------------------------------------
  Rows
-------------------------------------------------------------------------------}

-- | Constructor names in the row, in tag order.
type Names = [Symbol]

-- | Payload types in the row, in tag order.
type Payloads = [Type]

-- | A structural variant: a runtime tag plus a boxed payload.
--
-- Mirrors the @Variant !Int Any@ shape proposed in the plan document, which is
-- the representation any such library would converge on.
data Variant (ns :: Names) (ps :: Payloads) =
    Variant {-# UNPACK #-} !Int Any

{-------------------------------------------------------------------------------
  Type-level search

  The O(N) per lookup that a plugin would make O(1).
-------------------------------------------------------------------------------}

-- | Type-level conditional, used to select on @n == m@.
type family If (b :: Bool) (t :: Nat) (f :: Nat) :: Nat where
  If 'True  t f = t
  If 'False t f = f

-- | The same, at kind @Type@, for selecting a payload type.
type family IfType (b :: Bool) (t :: Type) (f :: Type) :: Type where
  IfType 'True  t f = t
  IfType 'False t f = f

-- | The tag of constructor @n@ in @ns@.
type family Idx (n :: Symbol) (ns :: Names) :: Nat where
  Idx n '[]      = TypeError ('Text "unknown constructor in row")
  Idx n (m ': ms) = If (n == m) 0 (1 + Idx n ms)

-- | The payload type of constructor @n@.
type family Pld (n :: Symbol) (ns :: Names) (ps :: Payloads) :: Type where
  Pld n '[]       _   = TypeError ('Text "unknown constructor in row")
  Pld n (_  ': ms) '[] = TypeError ('Text "row/payload arity mismatch")
  Pld n (m  ': ms) (p ': ps) = IfType (n == m) p (Pld n ms ps)

{-------------------------------------------------------------------------------
  Operations
-------------------------------------------------------------------------------}

-- | Build a variant from a compile-time-computed tag.
--
-- The tag must be computed at a /concrete/ type, e.g.
--
-- > mkVariant (natToInt (Proxy @(Idx "C00" NS))) payload
--
-- A polymorphic wrapper cannot do this for you: @Idx n ns@ does not reduce
-- while @n@ and @ns@ are abstract, so no @KnownNat@ evidence is available.
mkVariant :: forall ns ps a. Int -> a -> Variant ns ps
mkVariant t x = Variant t (unsafeCoerce x)

-- | Read a variant back as a payload, checking the tag.
asVariant :: forall ns ps a. Int -> Variant ns ps -> Maybe a
asVariant t (Variant t' p)
  | t == t'   = Just (unsafeCoerce p)
  | otherwise = Nothing

-- | Resolve a type-level Nat to an 'Int'. Must be applied at a concrete type.
natToInt :: forall n. KnownNat n => Proxy n -> Int
natToInt _ = fromIntegral (natVal (Proxy @n))

-- | The runtime tag.
tagOf :: Variant ns ps -> Int
tagOf (Variant t _) = t

-- | Widen a variant from a subrow to a superrow, remapping the tag.
--
-- The remapping table is supplied by the caller; a plugin would compute it at
-- compile time. A tag outside the source row is a runtime error.
widenC :: [Int] -> Variant ns ps -> Variant ns' ps'
widenC table (Variant t p) = case drop t table of
  []       -> error "widenC: tag not in source row"
  (t' : _) -> Variant t' p

-- | Case on the runtime tag, for building eliminators.
caseTag :: Variant ns ps -> (Int -> a) -> a
caseTag (Variant t _) k = k t
