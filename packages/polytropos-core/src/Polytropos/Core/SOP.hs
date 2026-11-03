{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

{-|
Module      : Polytropos.Core.SOP
Description : SOP (Sums-of-Products) combinators over flat generic representations
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

High-performance Sums-of-Products (SOP) combinators over the uniform 'Polytropos.Core.Rep'
and 'Polytropos.Core.RowRep' substrates of Polytropos.

= Architectural Overview & Heritage

In traditional SOP libraries such as @generics-sop@ and @sop-core@:
* Products (@NP f xs@) and sums (@NS f xs@) are inductive GADTs.
* Combinators such as @hpure@, @hliftA2@, and @hcollapse@ operate via structural
  recursion over an inductive singleton spine (@SListI xs@) or unary Peano tag
  trees (@Z@, @S@), paying \(\mathcal{O}(N)\) spine allocations and recursion depth.

In @polytropos@, both products ('ProductRowT') and sums ('SumRowT') share a single,
flat, type-erased runtime representation:

@
data Rep (f :: Type -> Type) a = Rep {-# UNPACK #-} !Word !(SmallArray (f Any))
newtype RowRep (f :: Type -> Type) (r :: RowType) (row :: k) a = RowRep (Rep f a)
@

Because 'Polytropos.Core.RowRep' already parameterizes every payload slot by a functor
@f :: Type -> Type@, we obtain:
1. __Zero-Spine Execution:__ 'hcollapse', 'hliftA2', and 'hsequence' operate directly
   over contiguous 'Data.Primitive.SmallArray.SmallArray' slices in \(\mathcal{O}(1)\)
   allocation without intermediate list or GADT node allocations.
2. __Zero-Constraint Primitives:__ Unconstrained combinators like 'hliftA2', 'hsequence',
   and 'hcollapse' require no typeclass evidence (@AllFields@ or @SListI@) because
   the arity and constructor tag are stored directly in the runtime representation.
3. __\(\mathcal{O}(1)\) Sum Operations:__ Sum branch indexing ('hindex'), application ('hapSum'),
   and elimination ('helim') execute in instantaneous \(\mathcal{O}(1)\) time by indexing
   directly via the unboxed runtime 'Polytropos.Core.repTag'.
4. __Zero-Copy Coercions:__ Because all slots have erased runtime layout @f Any@,
   functor changes under 'Data.Coerce.Coercible' ('hcoerce', 'htoI', 'hfromI') are pure \(\mathcal{O}(1)\)
   no-ops that preserve the identical heap array pointer.
-}
module Polytropos.Core.SOP
  ( -- * Functor Types & Aliases
    I(..)
  , type K
  , unK
  , type (:.:)
  , unComp
  , comp
  , type (-.->)(..)
    -- * Universal Constraints & Reflection
  , Top
  , ReifyFieldNames(..)
    -- * Population
  , hpure
  , hpureFromNames
  , hpureArity
  , hcpure
  , hcpure_
    -- * Mapping & Zipping
  , hmap
  , hliftA
  , hcmapProduct
  , hcmapSum
  , HCMap(..)
  , hcmap
  , hcmap_
  , hcliftA
  , hcliftA_
  , hliftA2
  , hzipWith
  , hliftA2Sum
  , hcliftA2
  , hczipWith
  , hcliftA2_
  , hcliftA2Sum
  , hliftA3
  , hzipWith3
  , hcliftA3
  , hczipWith3
  , hcliftA3_
  , hproduct
  , hunzip
    -- * Application & Elimination
  , hapProduct
  , hap
  , hapSum
  , helim
    -- * Folding & Collapsing
  , hcollapse
  , hcollapseFold
  , hfoldMap
  , hcfoldMap
  , hcfoldMap_
  , hcfoldMapSum
    -- * Traversing & Sequencing
  , hsequence'
  , hsequence
  , htraverse
  , hctraverse
  , hctraverse_
    -- * Sum Operations
  , hindex
  , hexpandArity
  , hexpand
  , injectionsArity
  , injections
  , apInjs
  , hhead
    -- * Zero-Copy Coercions & Metadata
  , hcoerce
  , htoI
  , hfromI
  , hunit
  , hdeunit
  , hfieldNames
  ) where

import Control.Monad.ST (runST)
import Data.Coerce (Coercible, coerce)
import Data.Foldable (toList)
import Data.Functor.Compose (Compose(..))
import Data.Functor.Const (Const(..))
import Data.Functor.Identity (Identity(..))
import qualified Data.Functor.Product as FP
import Data.Kind (Constraint)
import Data.Primitive.SmallArray
  ( indexSmallArray
  , newSmallArray
  , runSmallArray
  , sizeofSmallArray
  , smallArrayFromListN
  , unsafeFreezeSmallArray
  , writeSmallArray
  )
import Data.Proxy (Proxy(..))
import GHC.Exts (Any)
import GHC.TypeLits (KnownSymbol, symbolVal)
import Unsafe.Coerce (unsafeCoerce)

import Polytropos.Core
  ( AllFields(..)
  , DictAny(..)
  , Pair(..)
  , Rep(..)
  , RowFlavour
  , RowRep(..)
  , RowType(ProductRowT, SumRowT)
  , fieldAt
  , productRep
  )

{-------------------------------------------------------------------------------
  §1  Functor Types & Aliases
-------------------------------------------------------------------------------}

-- | Identity functor matching @generics-sop@ / @sop-core@ and @Polytropos.Generics@.
newtype I a = I { unI :: a }
  deriving (Eq, Ord, Show, Read)

-- | Constant functor alias matching @generics-sop@ / @sop-core@.
type K = Const

-- | Extract the value from a 'K' ('Const') wrapper.
unK :: K a b -> a
unK (Const x) = x

-- | Functor composition operator matching @generics-sop@ / @sop-core@.
type (:.:) = Compose
infixr 8 :.:

-- | Unpack a composed functor wrapper.
unComp :: (f :.: g) a -> f (g a)
unComp (Compose x) = x

-- | Pack a nested functor value into a composed functor wrapper.
comp :: f (g a) -> (f :.: g) a
comp = Compose

-- | Lifted natural transformation / function arrow between functors.
--
-- Mirrors @generics-sop@'s @(-.->)@.
newtype (-.->) f g a = Fn { apFn :: f a -> g a }
infixr 1 -.->

{-------------------------------------------------------------------------------
  §2  Universal Constraints & Reflection
-------------------------------------------------------------------------------}

-- | Universal constraint that holds trivially for every type and kind.
--
-- Used to instantiate constrained combinators ('hcpure', 'hcmap', etc.)
-- without restricting field types.
class Top (a :: k)
instance Top (a :: k)

-- | Reify field or constructor names from a type-level row into runtime 'String' values.
type ReifyFieldNames :: forall {k}. k -> Constraint
class ReifyFieldNames (r :: k) where
  reifyFieldNames :: [String]

instance ReifyFieldNames '[] where
  reifyFieldNames = []

instance (KnownSymbol n, ReifyFieldNames rest) => ReifyFieldNames ((n ':= a) ': rest) where
  reifyFieldNames = symbolVal (Proxy @n) : reifyFieldNames @rest

instance {-# OVERLAPPABLE #-} (KnownSymbol n, ReifyFieldNames rest) => ReifyFieldNames (n ': rest) where
  reifyFieldNames = symbolVal (Proxy @n) : reifyFieldNames @rest

{-------------------------------------------------------------------------------
  §3  Population
-------------------------------------------------------------------------------}

-- | Populate a product 'RowRep' using an unconstrained rank-2 value generator.
--
-- Requires 'AllFields' 'ProductRowT' @row@ 'Top' to determine the row arity
-- at compile time.
hpure
  :: forall row f a.
     AllFields ProductRowT row Top
  => (forall x. f x)
  -> RowRep f ProductRowT row a
hpure fn =
  let dicts = fieldDicts @ProductRowT @row @Top
      n = sizeofSmallArray dicts
      arr = runSmallArray $ do
        dst <- newSmallArray n (error "hpure: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise = do
                  writeSmallArray dst i (fn @Any)
                  go (i + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arr)

-- | Populate a product 'RowRep' using row field names to determine arity.
--
-- Useful in contexts where 'ReifyFieldNames' is available instead of 'AllFields'.
hpureFromNames
  :: forall row f a.
     ReifyFieldNames row
  => (forall x. f x)
  -> RowRep f ProductRowT row a
hpureFromNames fn = hpureArity (length (reifyFieldNames @row)) fn

-- | Populate a product 'RowRep' of a given explicit integer arity.
hpureArity
  :: Int
  -> (forall x. f x)
  -> RowRep f ProductRowT row a
hpureArity n fn =
  let arr = runSmallArray $ do
        dst <- newSmallArray n (error "hpureArity: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise = do
                  writeSmallArray dst i (fn @Any)
                  go (i + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arr)

-- | Populate a product 'RowRep' using a class-constrained rank-2 builder.
--
-- Uses the dictionary vector emitted by @polytropos-plugin@ to supply
-- the class constraint @c x@ for each slot.
hcpure
  :: forall c row f a.
     AllFields ProductRowT row c
  => (forall x. c x => f x)
  -> RowRep f ProductRowT row a
hcpure fn =
  let dicts = fieldDicts @ProductRowT @row @c
      n = sizeofSmallArray dicts
      arr = runSmallArray $ do
        dst <- newSmallArray n (error "hcpure: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise =
                  case indexSmallArray dicts i of
                    DictAny -> do
                      writeSmallArray dst i (fn @Any)
                      go (i + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arr)

-- | Proxy-passing variant of 'hcpure' for @generics-sop@ API compatibility.
hcpure_
  :: forall c row f a proxy.
     AllFields ProductRowT row c
  => proxy c
  -> (forall x. c x => f x)
  -> RowRep f ProductRowT row a
hcpure_ _ fn = hcpure @c @row fn

{-------------------------------------------------------------------------------
  §4  Mapping & Zipping
-------------------------------------------------------------------------------}

-- | Map a natural transformation over all payload slots of a 'RowRep'.
--
-- Requires zero typeclass constraints. Works uniformly over 'ProductRowT'
-- (records) and 'SumRowT' (variants), preserving the constructor tag.
hmap
  :: (forall x. f x -> g x)
  -> RowRep f r row a
  -> RowRep g r row a
hmap fn (RowRep (Rep tag vals)) =
  let n = sizeofSmallArray vals
      vals' = runSmallArray $ do
        dst <- newSmallArray n (error "hmap: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise = do
                  let !v = indexSmallArray vals i
                  writeSmallArray dst i (fn v)
                  go (i + 1)
        go 0
        pure dst
  in RowRep (Rep tag vals')

-- | Alias for 'hmap' matching the @generics-sop@ naming convention.
hliftA
  :: (forall x. f x -> g x)
  -> RowRep f r row a
  -> RowRep g r row a
hliftA = hmap

-- | Map a class-constrained function over a product 'RowRep'.
hcmapProduct
  :: forall c row f g a.
     AllFields ProductRowT row c
  => (forall x. c x => f x -> g x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
hcmapProduct fn (RowRep (Rep tag vals)) =
  let dicts = fieldDicts @ProductRowT @row @c
      n = sizeofSmallArray dicts
      vals' = runSmallArray $ do
        dst <- newSmallArray n (error "hcmapProduct: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise =
                  case indexSmallArray dicts i of
                    DictAny -> do
                      let !v = indexSmallArray vals i
                      writeSmallArray dst i (fn @Any v)
                      go (i + 1)
        go 0
        pure dst
  in RowRep (Rep tag vals')

-- | Map a class-constrained function over a sum 'RowRep' in \(\mathcal{O}(1)\) time.
--
-- Indexes the dictionary vector directly using the variant's active constructor tag.
hcmapSum
  :: forall c row f g a.
     AllFields SumRowT row c
  => (forall x. c x => f x -> g x)
  -> RowRep f SumRowT row a
  -> RowRep g SumRowT row a
hcmapSum fn (RowRep (Rep tag vals)) =
  let dicts = fieldDicts @SumRowT @row @c
      !d = indexSmallArray dicts (fromIntegral tag)
      n = sizeofSmallArray vals
      vals' = case d of
        DictAny -> runSmallArray $ do
          dst <- newSmallArray n (error "hcmapSum: uninitialized slot")
          let go i
                | i >= n = pure ()
                | otherwise = do
                    let !v = indexSmallArray vals i
                    writeSmallArray dst i (fn @Any v)
                    go (i + 1)
          go 0
          pure dst
  in RowRep (Rep tag vals')

-- | Unified class for constrained mapping over either products or sums.
class RowFlavour r => HCMap (r :: RowType) where
  -- | Internal implementation method for constrained mapping.
  hcmapImpl
    :: forall c row f g a.
       AllFields r row c
    => (forall x. c x => f x -> g x)
    -> RowRep f r row a
    -> RowRep g r row a

instance HCMap ProductRowT where
  hcmapImpl = hcmapProduct

instance HCMap SumRowT where
  hcmapImpl = hcmapSum

-- | Unified constrained map over either a product or sum 'RowRep'.
--
-- The constraint @c@ is passed first via TypeApplications (e.g. @hcmap @Show fn rep@),
-- while the row flavour @r@ and row structure are inferred directly from the argument.
hcmap
  :: forall c r row f g a.
     (HCMap r, AllFields r row c)
  => (forall x. c x => f x -> g x)
  -> RowRep f r row a
  -> RowRep g r row a
hcmap = hcmapImpl @r @c

-- | Proxy-passing variant of 'hcmap' for @generics-sop@ API compatibility.
hcmap_
  :: forall c r row f g a proxy.
     (HCMap r, AllFields r row c)
  => proxy c
  -> (forall x. c x => f x -> g x)
  -> RowRep f r row a
  -> RowRep g r row a
hcmap_ _ = hcmap @c

-- | Alias for 'hcmapProduct' matching @generics-sop@ conventions.
hcliftA
  :: forall c row f g a.
     AllFields ProductRowT row c
  => (forall x. c x => f x -> g x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
hcliftA = hcmapProduct

-- | Proxy-passing variant of 'hcliftA' for @generics-sop@ API compatibility.
hcliftA_
  :: forall c row f g a proxy.
     AllFields ProductRowT row c
  => proxy c
  -> (forall x. c x => f x -> g x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
hcliftA_ _ = hcmapProduct @c

-- | Unconstrained pointwise zip of two product 'RowRep' values.
--
-- Requires zero typeclass constraints.
hliftA2
  :: (forall x. f x -> g x -> h x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
hliftA2 fn (RowRep (Rep _ arrF)) (RowRep (Rep _ arrG)) =
  let n = sizeofSmallArray arrF
      arrH = runSmallArray $ do
        dst <- newSmallArray n (error "hliftA2: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise = do
                  let !fx = indexSmallArray arrF i
                      !gx = indexSmallArray arrG i
                  writeSmallArray dst i (fn fx gx)
                  go (i + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arrH)

-- | Alias for 'hliftA2'.
hzipWith
  :: (forall x. f x -> g x -> h x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
hzipWith = hliftA2

-- | Pointwise zip of two sum 'RowRep' values.
--
-- Succeeds with 'Just' iff both variants share the same active constructor tag.
hliftA2Sum
  :: (forall x. f x -> g x -> h x)
  -> RowRep f SumRowT row a
  -> RowRep g SumRowT row a
  -> Maybe (RowRep h SumRowT row a)
hliftA2Sum fn (RowRep (Rep tagF arrF)) (RowRep (Rep tagG arrG))
  | tagF == tagG =
      let n = sizeofSmallArray arrF
          arrH = runSmallArray $ do
            dst <- newSmallArray n (error "hliftA2Sum: uninitialized slot")
            let go i
                  | i >= n = pure ()
                  | otherwise = do
                      let !fx = indexSmallArray arrF i
                          !gx = indexSmallArray arrG i
                      writeSmallArray dst i (fn fx gx)
                      go (i + 1)
            go 0
            pure dst
      in Just (RowRep (Rep tagF arrH))
  | otherwise = Nothing

-- | Constrained pointwise zip of two product 'RowRep' values.
hcliftA2
  :: forall c row f g h a.
     AllFields ProductRowT row c
  => (forall x. c x => f x -> g x -> h x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
hcliftA2 fn (RowRep (Rep _ arrF)) (RowRep (Rep _ arrG)) =
  let dicts = fieldDicts @ProductRowT @row @c
      n = sizeofSmallArray dicts
      arrH = runSmallArray $ do
        dst <- newSmallArray n (error "hcliftA2: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise =
                  case indexSmallArray dicts i of
                    DictAny -> do
                      let !fx = indexSmallArray arrF i
                          !gx = indexSmallArray arrG i
                      writeSmallArray dst i (fn @Any fx gx)
                      go (i + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arrH)

-- | Alias for 'hcliftA2'.
hczipWith
  :: forall c row f g h a.
     AllFields ProductRowT row c
  => (forall x. c x => f x -> g x -> h x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
hczipWith = hcliftA2

-- | Proxy-passing variant of 'hcliftA2'.
hcliftA2_
  :: forall c row f g h a proxy.
     AllFields ProductRowT row c
  => proxy c
  -> (forall x. c x => f x -> g x -> h x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
hcliftA2_ _ = hcliftA2 @c

-- | Constrained pointwise zip of two sum 'RowRep' values.
--
-- Returns 'Just' iff both variants share the same active constructor tag.
hcliftA2Sum
  :: forall c row f g h a.
     AllFields SumRowT row c
  => (forall x. c x => f x -> g x -> h x)
  -> RowRep f SumRowT row a
  -> RowRep g SumRowT row a
  -> Maybe (RowRep h SumRowT row a)
hcliftA2Sum fn (RowRep (Rep tagF arrF)) (RowRep (Rep tagG arrG))
  | tagF == tagG =
      let dicts = fieldDicts @SumRowT @row @c
          !d = indexSmallArray dicts (fromIntegral tagF)
          n = sizeofSmallArray arrF
          arrH = case d of
            DictAny -> runSmallArray $ do
              dst <- newSmallArray n (error "hcliftA2Sum: uninitialized slot")
              let go i
                    | i >= n = pure ()
                    | otherwise = do
                        let !fx = indexSmallArray arrF i
                            !gx = indexSmallArray arrG i
                        writeSmallArray dst i (fn @Any fx gx)
                        go (i + 1)
              go 0
              pure dst
      in Just (RowRep (Rep tagF arrH))
  | otherwise = Nothing

-- | Unconstrained 3-way zip of product 'RowRep' values.
hliftA3
  :: (forall x. f x -> g x -> h x -> i x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
  -> RowRep i ProductRowT row a
hliftA3 fn (RowRep (Rep _ arrF)) (RowRep (Rep _ arrG)) (RowRep (Rep _ arrH)) =
  let n = sizeofSmallArray arrF
      arrI = runSmallArray $ do
        dst <- newSmallArray n (error "hliftA3: uninitialized slot")
        let go idx
              | idx >= n = pure ()
              | otherwise = do
                  let !fx = indexSmallArray arrF idx
                      !gx = indexSmallArray arrG idx
                      !hx = indexSmallArray arrH idx
                  writeSmallArray dst idx (fn fx gx hx)
                  go (idx + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arrI)

-- | Alias for 'hliftA3'.
hzipWith3
  :: (forall x. f x -> g x -> h x -> i x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
  -> RowRep i ProductRowT row a
hzipWith3 = hliftA3

-- | Constrained 3-way zip of product 'RowRep' values.
hcliftA3
  :: forall c row f g h i a.
     AllFields ProductRowT row c
  => (forall x. c x => f x -> g x -> h x -> i x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
  -> RowRep i ProductRowT row a
hcliftA3 fn (RowRep (Rep _ arrF)) (RowRep (Rep _ arrG)) (RowRep (Rep _ arrH)) =
  let dicts = fieldDicts @ProductRowT @row @c
      n = sizeofSmallArray dicts
      arrI = runSmallArray $ do
        dst <- newSmallArray n (error "hcliftA3: uninitialized slot")
        let go idx
              | idx >= n = pure ()
              | otherwise =
                  case indexSmallArray dicts idx of
                    DictAny -> do
                      let !fx = indexSmallArray arrF idx
                          !gx = indexSmallArray arrG idx
                          !hx = indexSmallArray arrH idx
                      writeSmallArray dst idx (fn @Any fx gx hx)
                      go (idx + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arrI)

-- | Alias for 'hcliftA3'.
hczipWith3
  :: forall c row f g h i a.
     AllFields ProductRowT row c
  => (forall x. c x => f x -> g x -> h x -> i x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
  -> RowRep i ProductRowT row a
hczipWith3 = hcliftA3

-- | Proxy-passing variant of 'hcliftA3'.
hcliftA3_
  :: forall c row f g h i a proxy.
     AllFields ProductRowT row c
  => proxy c
  -> (forall x. c x => f x -> g x -> h x -> i x)
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep h ProductRowT row a
  -> RowRep i ProductRowT row a
hcliftA3_ _ = hcliftA3 @c

-- | Combine two product rows pointwise into a single product of pairs.
hproduct
  :: RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
  -> RowRep (FP.Product f g) ProductRowT row a
hproduct = hliftA2 FP.Pair

-- | Split a product row of pairs into two separate product rows in a single pass.
hunzip
  :: RowRep (FP.Product f g) ProductRowT row a
  -> (RowRep f ProductRowT row a, RowRep g ProductRowT row a)
hunzip (RowRep (Rep tag vals)) =
  let n = sizeofSmallArray vals
      (arrF, arrG) = runST $ do
        dstF <- newSmallArray n (error "hunzip: uninitialized slot")
        dstG <- newSmallArray n (error "hunzip: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise = do
                  case indexSmallArray vals i of
                    FP.Pair fx gx -> do
                      writeSmallArray dstF i fx
                      writeSmallArray dstG i gx
                      go (i + 1)
        go 0
        fFrozen <- unsafeFreezeSmallArray dstF
        gFrozen <- unsafeFreezeSmallArray dstG
        pure (fFrozen, gFrozen)
  in (RowRep (Rep tag arrF), RowRep (Rep tag arrG))

{-------------------------------------------------------------------------------
  §5  Application & Elimination
-------------------------------------------------------------------------------}

-- | Pointwise application of a product of functions to a product of arguments.
--
-- Runs in \(\mathcal{O}(N)\) time with zero typeclass constraints.
hapProduct
  :: RowRep (f -.-> g) ProductRowT row a
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
hapProduct = hliftA2 apFn

-- | Alias for 'hapProduct' matching @generics-sop@ convention.
hap
  :: RowRep (f -.-> g) ProductRowT row a
  -> RowRep f ProductRowT row a
  -> RowRep g ProductRowT row a
hap = hapProduct

-- | Apply a product of branch functions to a sum variant in \(\mathcal{O}(1)\) time.
--
-- Direct jump-table dispatch: indexes into the function product using the variant's
-- unboxed runtime tag.
hapSum
  :: RowRep (f -.-> g) ProductRowT row a
  -> RowRep f SumRowT row a
  -> RowRep g SumRowT row a
hapSum (RowRep (Rep _ fnArr)) (RowRep (Rep tag valArr)) =
  let fn = indexSmallArray fnArr (fromIntegral tag)
      n = sizeofSmallArray valArr
      valArr' = runSmallArray $ do
        dst <- newSmallArray n (error "hapSum: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise = do
                  let !v = indexSmallArray valArr i
                  writeSmallArray dst i (apFn fn v)
                  go (i + 1)
        go 0
        pure dst
  in RowRep (Rep tag valArr')

-- | Eliminate a sum variant using a product of handlers in \(\mathcal{O}(1)\) time.
--
-- Fuses 'hapSum' and 'hcollapse' into a single instantaneous array lookup.
helim
  :: RowRep (f -.-> Const b) ProductRowT row a
  -> RowRep f SumRowT row a
  -> b
helim (RowRep (Rep _ fnArr)) (RowRep (Rep tag valArr)) =
  let fn = indexSmallArray fnArr (fromIntegral tag)
      val = indexSmallArray valArr 0
  in getConst (apFn fn val)

{-------------------------------------------------------------------------------
  §6  Folding & Collapsing
-------------------------------------------------------------------------------}

-- | Extract values from a 'RowRep' parameterized by 'Const' into a list.
--
-- Runs in \(\mathcal{O}(N)\) time with zero typeclass constraints and zero
-- 'unsafeCoerce' calls. Works uniformly on both 'ProductRowT' and 'SumRowT'.
hcollapse :: RowRep (Const a) r row x -> [a]
hcollapse (RowRep (Rep _ vals)) =
  let n = sizeofSmallArray vals
      go i
        | i >= n = []
        | otherwise = getConst (indexSmallArray vals i) : go (i + 1)
  in go 0

-- | Foldable-based variant of 'hcollapse'.
hcollapseFold :: RowRep (Const a) r row x -> [a]
hcollapseFold (RowRep (Rep _ vals)) = map getConst (toList vals)

-- | Unconstrained monoidal fold across all payload slots of a 'RowRep'.
--
-- Works on both 'ProductRowT' and 'SumRowT' without allocating an intermediate array.
hfoldMap
  :: Monoid m
  => (forall x. f x -> m)
  -> RowRep f r row a
  -> m
hfoldMap fn (RowRep (Rep _ vals)) =
  let n = sizeofSmallArray vals
      go i
        | i >= n = mempty
        | otherwise = fn (indexSmallArray vals i) <> go (i + 1)
  in go 0

-- | Fused constrained fold over a product 'RowRep'.
--
-- Evaluates directly into a 'Monoid' without allocating an intermediate 'Const' array.
hcfoldMap
  :: forall c row m f a.
     (AllFields ProductRowT row c, Monoid m)
  => (forall x. c x => f x -> m)
  -> RowRep f ProductRowT row a
  -> m
hcfoldMap fn (RowRep (Rep _ vals)) =
  let dicts = fieldDicts @ProductRowT @row @c
      n = sizeofSmallArray dicts
      go i
        | i >= n = mempty
        | otherwise =
            case indexSmallArray dicts i of
              DictAny -> fn @Any (indexSmallArray vals i) <> go (i + 1)
  in go 0

-- | Proxy-passing variant of 'hcfoldMap'.
hcfoldMap_
  :: forall c row m f a proxy.
     (AllFields ProductRowT row c, Monoid m)
  => proxy c
  -> (forall x. c x => f x -> m)
  -> RowRep f ProductRowT row a
  -> m
hcfoldMap_ _ = hcfoldMap @c

-- | Fused constrained fold over a sum 'RowRep' in \(\mathcal{O}(1)\) time.
hcfoldMapSum
  :: forall c row m f a.
     (AllFields SumRowT row c, Monoid m)
  => (forall x. c x => f x -> m)
  -> RowRep f SumRowT row a
  -> m
hcfoldMapSum fn (RowRep (Rep tag vals)) =
  let dicts = fieldDicts @SumRowT @row @c
      !d = indexSmallArray dicts (fromIntegral tag)
      n = sizeofSmallArray vals
      go i
        | i >= n = mempty
        | otherwise =
            case d of
              DictAny -> fn @Any (indexSmallArray vals i) <> go (i + 1)
  in go 0

{-------------------------------------------------------------------------------
  §7  Traversing & Sequencing
-------------------------------------------------------------------------------}

-- | Sequence an 'Applicative' effect out of a 'Compose'-wrapped 'RowRep'.
--
-- Works polymorphically on both 'ProductRowT' and 'SumRowT' with zero constraints.
hsequence'
  :: Applicative m
  => RowRep (Compose m f) r row a
  -> m (RowRep f r row a)
hsequence' (RowRep (Rep tag vals)) =
  RowRep . Rep tag <$> traverse getCompose vals

-- | Sequence an 'Applicative' effect directly from 'RowRep' @m@ into 'RowRep' 'Identity'.
hsequence
  :: Applicative m
  => RowRep m r row a
  -> m (RowRep Identity r row a)
hsequence (RowRep (Rep tag vals)) =
  RowRep . Rep tag <$> traverse (fmap Identity) vals

-- | Traverse an 'Applicative' effect over all slots of a 'RowRep'.
--
-- Requires zero typeclass constraints; works on both products and sums.
htraverse
  :: Applicative m
  => (forall x. f x -> m (g x))
  -> RowRep f r row a
  -> m (RowRep g r row a)
htraverse fn (RowRep (Rep tag vals)) =
  RowRep . Rep tag <$> traverse fn vals

-- | Fused constrained traversal over a product 'RowRep'.
--
-- Sequences the 'Applicative' effect without allocating an intermediate 'Compose' array.
hctraverse
  :: forall c row m f g a.
     (AllFields ProductRowT row c, Applicative m)
  => (forall x. c x => f x -> m (g x))
  -> RowRep f ProductRowT row a
  -> m (RowRep g ProductRowT row a)
hctraverse fn (RowRep (Rep tag arrF)) =
  let dicts = fieldDicts @ProductRowT @row @c
      n = sizeofSmallArray dicts
      go :: Int -> m [g Any]
      go i
        | i >= n = pure []
        | otherwise =
            case indexSmallArray dicts i of
              DictAny -> (:) <$> fn @Any (indexSmallArray arrF i) <*> go (i + 1)
  in RowRep . Rep tag . smallArrayFromListN n <$> go 0

-- | Proxy-passing variant of 'hctraverse'.
hctraverse_
  :: forall c row m f g a proxy.
     (AllFields ProductRowT row c, Applicative m)
  => proxy c
  -> (forall x. c x => f x -> m (g x))
  -> RowRep f ProductRowT row a
  -> m (RowRep g ProductRowT row a)
hctraverse_ _ = hctraverse @c

{-------------------------------------------------------------------------------
  §8  Sum Operations (O(1))
-------------------------------------------------------------------------------}

-- | Active constructor index of a sum 'RowRep' in \(\mathcal{O}(1)\) time.
hindex :: RowRep f SumRowT row a -> Int
hindex (RowRep (Rep tag _)) = fromIntegral tag

-- | Expand a sum 'RowRep' into a product 'RowRep' with 'Just' at the active tag
-- and 'Nothing' elsewhere, using explicit arity.
hexpandArity
  :: Int
  -> RowRep f SumRowT row a
  -> RowRep (Compose Maybe f) ProductRowT row a
hexpandArity n (RowRep (Rep tag valArr)) =
  let val = indexSmallArray valArr 0
      arr = runSmallArray $ do
        dst <- newSmallArray n (Compose Nothing)
        writeSmallArray dst (fromIntegral tag) (Compose (Just val))
        pure dst
  in RowRep (Rep 0 arr)

-- | Expand a sum 'RowRep' into a product 'RowRep' with 'Just' at the active tag
-- and 'Nothing' elsewhere.
hexpand
  :: forall row f a.
     ReifyFieldNames row
  => RowRep f SumRowT row a
  -> RowRep (Compose Maybe f) ProductRowT row a
hexpand = hexpandArity (length (reifyFieldNames @row))

-- | Produce a product of constructor injection functions for a given arity.
injectionsArity
  :: forall row f a.
     Int
  -> RowRep (f -.-> Const (RowRep f SumRowT row a)) ProductRowT row a
injectionsArity n =
  let arr = runSmallArray $ do
        dst <- newSmallArray n (error "injectionsArity: uninitialized slot")
        let go i
              | i >= n = pure ()
              | otherwise = do
                  let inj = Fn (\val -> Const (RowRep (Rep (fromIntegral i) (smallArrayFromListN 1 [val]))))
                  writeSmallArray dst i inj
                  go (i + 1)
        go 0
        pure dst
  in RowRep (Rep 0 arr)

-- | Produce a product of constructor injection functions.
injections
  :: forall row f a.
     ReifyFieldNames row
  => RowRep (f -.-> Const (RowRep f SumRowT row a)) ProductRowT row a
injections = injectionsArity (length (reifyFieldNames @row))

-- | Convert each slot of a product 'RowRep' into its corresponding sum variant.
apInjs :: RowRep f ProductRowT row a -> [RowRep f SumRowT row a]
apInjs (RowRep (Rep _ arr)) =
  let n = sizeofSmallArray arr
      go i
        | i >= n = []
        | otherwise =
            let v = indexSmallArray arr i
            in RowRep (Rep (fromIntegral i) (smallArrayFromListN 1 [v])) : go (i + 1)
  in go 0

-- | Extract the first slot of a product row.
hhead :: RowRep f ProductRowT row a -> f Any
hhead (RowRep rep) = fieldAt 0 rep

{-------------------------------------------------------------------------------
  §9  Zero-Copy Coercions & Metadata
-------------------------------------------------------------------------------}

-- | \(\mathcal{O}(1)\) zero-copy coercion between representationally identical slot functors
-- (e.g. 'Identity' and 'I', 'Const' and 'K', or newtype wrappers).
--
-- Reuses the identical 'Data.Primitive.SmallArray.SmallArray' pointer without copying
-- or allocating.
hcoerce
  :: forall f g r row a.
     (forall x. Coercible (f x) (g x))
  => RowRep f r row a
  -> RowRep g r row a
hcoerce rep =
  let !_ = coerce (id :: f Any -> f Any) :: g Any -> g Any
  in unsafeCoerce rep

-- | Coerce a functorial 'RowRep' to an 'Identity'-wrapped 'RowRep' in \(\mathcal{O}(1)\) time.
htoI
  :: (forall x. Coercible (f x) (Identity x))
  => RowRep f r row a
  -> RowRep Identity r row a
htoI = hcoerce

-- | Coerce an 'Identity'-wrapped 'RowRep' to another representationally identical functor in \(\mathcal{O}(1)\) time.
hfromI
  :: (forall x. Coercible (Identity x) (f x))
  => RowRep Identity r row a
  -> RowRep f r row a
hfromI = hcoerce

-- | Coerce a 'RowRep' with arbitrary result type @a@ to @()@.
hunit :: RowRep f r row a -> RowRep f r row ()
hunit = unsafeCoerce

-- | Coerce a 'RowRep' with result type @()@ to arbitrary @a@.
hdeunit :: RowRep f r row () -> RowRep f r row a
hdeunit = unsafeCoerce

-- | Reify row field or constructor labels as a 'Const' 'String'-wrapped product 'RowRep',
-- ready to be zipped with values via 'hliftA2' or 'hcliftA2'.
hfieldNames
  :: forall row a.
     ReifyFieldNames row
  => RowRep (Const String) ProductRowT row a
hfieldNames =
  let names = map Const (reifyFieldNames @row)
  in RowRep (productRep names)
