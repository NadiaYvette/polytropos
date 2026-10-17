{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
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

{-|
Module      : Polytropos.Core
Description : Low-level substrate, row vocabulary, and generic representation for Polytropos
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Core vocabulary and generic representation for @polytropos@.

This module is the foundational substrate of the library. It fixes three
essential architectural components and defers higher-level ergonomics to
"Polytropos" and the canonical design note (@docs\/notes\/POLYTROPOS_DESIGN.md@):

1. The /row vocabulary/: how products and sums are spelled at the type level
   (@'Pair'@ \/ @':='@, @'Row'@, @'ProductRow'@, @'SumRow'@).
2. The /generic representation/: @t'Rep'@, a runtime tag plus a flat array of
   payload slots.
3. The /evidence classes/: @'RowEq'@, @'RowShow'@, @'FieldIndex'@,
   @'ConstructorIndex'@, and @'AllFields'@, whose instance bodies are synthesised
   as literals by the TcPlugin.

= Architectural Overview & Rationale

== Why one @Rep@ for both products and sums

A product is a sum with exactly one constructor. Making that literal rather
than a special case buys one uniform representation, so the four quadrants of
the design space (nominal product, structural product, structural sum of
nominal products, nominal sum of structural products) differ only in what the
/type/ says, never in what the /value/ is:

@
data Rep (f :: Type -> Type) a = Rep {-# UNPACK #-} !Word !(SmallArray (f Any))
@

For a product the tag is always @0@ and is known statically, so tag comparisons
fold away completely in GHC Core. For a sum, the tag is the constructor index.

= When to Use This Module

* When implementing compilers, typechecker plugins, or low-level primitives.
* When writing custom backend adapters (e.g. database decoders or wire encoders)
  that need direct, unboxed access to the underlying 'Data.Primitive.SmallArray.SmallArray' slots.

= When Not to Use This Module

* In ordinary application code or domain modeling; prefer the user-friendly
  primitives and pattern synonyms in "Polytropos".
-}
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
#if !MIN_VERSION_base(4,20,0)
import Data.List                   (foldl')
#endif
import Data.Primitive.SmallArray
import Data.Word                   (Word64)
-- import Data.Tagged                 (Tagged(..))
import GHC.Exts                    (Any)
import GHC.OverloadedLabels        (IsLabel(..))
import GHC.TypeLits                (Symbol)
import Unsafe.Coerce               (unsafeCoerce)

{- Note [The Unified Rep Memory Physics: Quad-Quadrant Collapse]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-rep-memory-physics]
Historically, functional languages treat products (records, tuples, structs)
and sums (variants, coproducts, enums) as dual but structurally disjoint
mechanisms:

  1. Nominal Products:   data Person = Person { name :: String, age :: Int }
  2. Structural Products: Anonymous records (Record '["name" ':= String, ...])
  3. Nominal Sums:       data Shape = Circle Double | Rectangle Double Double
  4. Structural Sums:     Open variants (Variant '["Circle" ':= ..., ...])

In most extensible row libraries (such as vinyl or open-adt), these four
quadrants require distinct runtime architectures:
  - Products use heterogeneous cons-lists (HList) or balanced type-level trees,
    incurring O(N) pointer indirection chains and massive GC nursery churn.
  - Sums use nested binary Either trees (Either a (Either b (Either c ...))),
    incurring O(N) allocation overhead per injection and O(N) pattern cascading.

Polytropos collapses all four quadrants into a single, uniform runtime primitive:
  data Rep f a = Rep {-# UNPACK #-} !Word !(SmallArray (f Any))

Under GHC's STG/heap representation, Rep has the following precise memory physics:
  - 1 word: GHC info table pointer (heap object header).
  - 1 word: Unboxed 64-bit integer (Word#) representing the constructor tag t.
  - 1 word: Pointer to a SmallArray# heap object.

The SmallArray# payload itself consists of:
  - 1 word: GHC info table pointer.
  - 1 word: Size integer (Int#) representing the arity N.
  - N words: Contiguous pointers directly to the field values (f Any).

Total heap footprint: exactly 3 words for Rep + (2 + N) words for SmallArray#.
Crucially:
  * Zero Vector box overhead: Unlike standard Data.Vector, which wraps arrays in
    a 3-word record carrying an offset, length, and array pointer, SmallArray
    indexes the bare contiguous array directly.
  * For Products: The runtime tag is statically fixed to 0 and ignored. Field
    access is direct indexed lookup: indexSmallArray# arr i.
  * For Sums: The tag t indicates the active constructor (0, 1, 2, ...).
    The SmallArray# contains exactly the fields of constructor t.
    Because constructor arities can differ, the array size adapts dynamically
    without padding unused slots.
  * Homogeneity: A product of 10 fields and a sum whose active constructor has
    10 fields share the identical memory layout and garbage collection profile.
-}

{- Note [Transient Builders and In-Place CoW Hardware Vectorization]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-transient-cow]
Persistent data structures in functional languages face a well-known tension:
immutability guarantees thread safety and referential transparency, but single-field
updates naively require copying the entire N-element record (O(N) time and allocation).
For large records (e.g. 50-100 fields in enterprise domain models), repeated single
updates `r { a = 1, b = 2, c = 3 }` produce K * O(N) heap allocations, flooding the
GHC nursery and degrading L1/L2 cache hit rates.

Polytropos addresses this through a two-tiered hardware-conscious update architecture:

1. Ephemeral Transient Builders (MRep):
   When batch mutations or deserializations occur, we introduce an ephemeral mutable
   representation:
     data MRep s f a = MRep {-# UNPACK #-} !Word !(SmallMutableArray s (f Any))
   Inside the ST s monad, fields can be written in-place with zero allocations
   (writeSmallArray). Once construction is complete, unsafeFreezeSmallArray freezes
   the buffer into an immutable Rep with zero copying.

2. SIMD Hardware-Vectorized Copy-on-Write Bifurcation (Threshold N = 32):
   When an immutable record update (setFieldAt or setFieldsAt) is requested,
   the record size N is inspected:

   a. Small Records (N <= 32 fields):
      An array of 32 pointer words occupies 256 bytes (plus 16 bytes header).
      On modern x86-64 and AArch64 processors, L1 data cache lines are 64 bytes.
      A 32-field record fits entirely within 4 to 5 cache lines.
      Here, cloning the array via thawSmallArray and writing the updated slot in-place
      is executed entirely within L1 cache, with minimal branch prediction penalty.

   b. Large Records (N > 32 fields):
      For records exceeding 32 fields, thawing and overwriting causes cache eviction
      and redundant memory writes. Instead, we allocate a fresh array pre-filled with the
      updated value and copy the unchanged segments using copySmallArray:
        - Pre-slice:  copySmallArray m 0 v 0 i (indices 0 to i-1)
        - Post-slice: copySmallArray m (i+1) v (i+1) (n - i - 1) (indices i+1 to n-1)
      Under GHC's runtime system, copySmallArray translates directly to primitive
      memmove / memcpy intrinsics. On modern hardware, this utilizes AVX2 (256-bit)
      or AVX-512 (512-bit) SIMD instructions, streaming 4 to 8 pointer words per CPU
      cycle directly between memory locations without polluting intermediate registers.

3. Multi-Field Batch Updates (setFieldsAt):
   For updates modifying K fields simultaneously:
   - Naive chaining of K single-field updates incurs K * O(N) allocations.
   - setFieldsAt sorts the update indices in O(K log K) time and iterates through
     contiguous unchanged blocks, copying them in vectorized chunks. Total allocation:
     exactly 1 array of size N, reducing multi-field update overhead to 1 * O(N).
-}

{- Note [Single-Constructor Peeling and Total Elimination]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-peeling-elimination]
A critical challenge in extensible sum types (variants) is how to deconstruct them:

1. Total Elimination via Jump Tables:
   Standard Haskell multi-way pattern matching on sum types generates nested cascading
   branch trees (case tag of 0 -> ...; 1 -> ...; 2 -> ...; ...). For variants with
   large constructor rows (e.g. 50 error codes or AST node kinds), branch mispredictions
   severely degrade instruction pipeline throughput.
   Polytropos solves this in Polytropos.hs via eliminateUniform:
   The handler record is represented as an array of functions. The variant's tag t
   is used as an immediate array index into the handler array (indexSmallArray handlers t),
   yielding O(1) jump-table dispatch with zero branching penalty.

2. Single-Constructor Peeling (peelRep and peel):
   In modular compiler pipelines (e.g., Nanopass compilers) or open error handling,
   a function frequently only handles one specific constructor (e.g., Timeout) and
   wishes to forward all other constructors transparently to downstream handlers.
   In nested Either or church-encoded variants, peeling a constructor requires
   re-wrapping the entire value into a smaller type, allocating new wrapper constructors.

   Polytropos achieves O(1) constructor peeling with ZERO heap reallocation:
   Given a variant Rep t arr and a target constructor tag targetTag:
     - If t == targetTag: Match succeeds! Return Right containing the payload arr.
     - If t < targetTag: The active constructor preceded the target constructor.
       In the narrowed row (where targetTag is deleted), its relative tag index is
       unchanged. Return Left (Rep t arr).
     - If t > targetTag: The active constructor followed the target constructor.
       In the narrowed row, all constructors after targetTag shift down by 1.
       Return Left (Rep (t - 1) arr).

   Notice the critical invariant:
   In both Left branches, the underlying SmallArray pointer arr is REUSED DIRECTLY.
   Not a single field pointer is copied or moved. The constructor peeling operation
   is a pure, instantaneous integer comparison and decrement!
-}

{-------------------------------------------------------------------------------
  §1  The row vocabulary
-------------------------------------------------------------------------------}

-- | A type-level pair: a name bound to a type.
--
-- Poly-kinded with independent parameters, mirroring @large-anon@'s
-- @Pair@ / @:=@. Kept deliberately simple; the @f@-functor parameter that
-- @large-anon@ threads through its rows is future work (see note §1, D3).
--
-- Algorithmic Mechanics:
-- In type expressions, @("name" ':= Type)@ provides an ergonomic, readable
-- alternative to tuple pairs @'("name", Type)@. Because ':=' is an ordinary data
-- constructor promoted by DataKinds, GHC treats it as a first-class type constructor
-- of kind @k1 -> k2 -> Type@.
data Pair a b = a := b

-- | A zero-cost witness for a type-level field name.
--
-- Can be constructed ergonomically via @OverloadedLabels@ (e.g. @#foo@).
--
-- Algorithmic Mechanics:
-- 'Field' has no runtime fields and is represented by GHC as a zero-cost singleton.
-- When the user writes @#foo@, GHC desugars this to @fromLabel @"foo"@. The
-- 'IsLabel' instance below matches when the label string @l@ unifies with the
-- expected field symbol @l'@, constructing 'Field' at compile time with zero
-- runtime allocation.
data Field (n :: Symbol) = Field

instance (l ~ l') => IsLabel l (Field l') where
  fromLabel = Field

-- | A poly-kinded row whose entries have kind @k@.
--
-- Poly-kinded over entry kind @k@, mirroring @large-anon@'s @Row k@.
-- A row is represented purely as a standard type-level list @[Pair Symbol k]@.
type RowOf k = [Pair Symbol k]

-- | A /product/ row: an ordered list of field names and field types.
--
-- [ref:note-rep-memory-physics]
-- Order is the identity of the row; two rows with the same fields in a
-- different order are different rows. This is deliberate — it is what lets a
-- field index be a compile-time constant (0, 1, 2, ...) synthesized directly
-- into Core by the @polytropos-plugin@ without runtime linear scanning.
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
--
-- Sum rows map constructor name symbols to their payload specification.
type SumRowOf prod = [Pair Symbol prod]

-- | A /sum/ row: an ordered list of constructor names, each carrying the
-- product row of that constructor's fields.
--
-- [ref:note-rep-memory-physics]
-- The tag of a constructor is its 0-based position in this list. Constructor
-- arities are therefore the lengths of the nested product rows, and may differ
-- (see note §3, D7).
type SumRow = SumRowOf Row

-- | An HKD-aware sum row parameterised by a field functor @f@.
-- Each constructor carries an HKD product row.
type SumRowHKD (f :: Type -> Type) = SumRowOf (ProductRow f)

-- | Synonym for 'SumRowHKD'.
type SumRowF (f :: Type -> Type) = SumRowHKD f

{-------------------------------------------------------------------------------
  §1b  Type-level row metadata (rewritten by TcPlugin)

  [ref:note-metadata-rewriting]
  Closed-form type families without Haskell-level equations. When a row is
  fully known, the TcPlugin rewrites these type families to concrete type-level
  lists, enabling generic programming over field names and field types.

  Why Defunctionalized Closed-Form Families?
  In standard GHC type family programming, recursive equations (e.g. `FieldNames (x ': xs) = ...`)
  incur O(N) evaluation steps during constraint solving and generate large substitution
  forests in Core. If a row contains an unsolved unification variable or row tail,
  standard equations can become stuck or lead to explosive simplification cycles.
  By declaring them as closed type families with NO equations, GHC treats them as
  opaque abstract symbols until @Polytropos.Plugin@ inspects the row structure,
  extracts all field names/types in a single linear pass, and emits a direct
  reduction to a concrete promoted list literal.
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

{-------------------------------------------------------------------------------
  §1b  Row flavours (Option D vocabulary)

  Concrete row flavours, not kind-polymorphic. Each flavour carries a
  type-level list of entries; the flavour tells the plugin what kind of
  entries to expect.

  See PHASE2_SKETCH.md, Piece 1, §1a.
-------------------------------------------------------------------------------}

-- | The kind of row flavours (Option D).
--
-- Promoted by DataKinds: the types @ProductRowT@, @SumRowT@, @HandlerRowT@,
-- @ResultRowT@ have kind @RowType@, and can be used as the row parameter of
-- t'RowRep' and the evidence classes.
--
-- Algorithmic Mechanics:
-- Option D uses concrete, distinct types for each row flavour rather than an
-- open kind-polymorphic family. This allows the @TcPlugin@ to immediately
-- determine whether it is solving for a product row, sum row, HKD variant,
-- or handler vector by inspecting the promoted type constructor, avoiding
-- ambiguity and complex kind unification steps during constraint solving.
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
--
-- [ref:note-rep-memory-physics]
-- Zero-Cost Newtype Erasure:
-- GHC's Core compiler completely unwraps @RowRep@ at compile time. At runtime,
-- all operations on @RowRep@ compile down to direct primitive instructions on
-- the underlying 'Rep'. The type arguments @r@ and @row@ act as purely type-level
-- evidence tags, allowing typeclasses like 'RowEq', 'RowShow', and 'AllFields'
-- to be invoked directly on records without requiring explicit runtime proxies.
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
-- [ref:note-rep-memory-physics]
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
--
-- For sums, this identifies which constructor of the sum row is currently active.
repTag :: Rep f a -> Word
repTag (Rep t _) = t

-- | Payload slots, in row order, of the /selected/ constructor.
--
-- For products, this contains all fields of the record.
-- For sums, this contains only the payload fields of the active constructor.
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

{-------------------------------------------------------------------------------
  §2b  Ephemeral transient representation
-------------------------------------------------------------------------------}

-- | Ephemeral mutable representation for in-place construction and deserialization.
--
-- [ref:note-transient-cow]
-- Allows O(1) in-place slot modification during multi-field updates, bulk parsing,
-- or database row decoding without allocating intermediate immutable 'SmallArray'
-- wrappers.
data MRep s (f :: Type -> Type) a = MRep
  {-# UNPACK #-} !Word
  !(SmallMutableArray s (f Any))

-- | Allocate a new mutable t'MRep' pre-initialized with a default payload.
--
-- Used when building a record or variant from scratch in ST before freezing.
newMRep :: Word -> Int -> f Any -> ST s (MRep s f a)
newMRep tag n defaultVal = do
  m <- newSmallArray n defaultVal
  pure (MRep tag m)

-- | Safely thaw an immutable t'Rep' into a mutable builder.
--
-- Performs a single heap allocation of a 'SmallMutableArray' and copies the N
-- pointers from the source array.
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
--
-- Uses 'unsafeFreezeSmallArray', which is an O(1) zero-copy operation that reuses
-- the mutable buffer directly as an immutable 'SmallArray'. Safe because caller
-- relinquishes all mutable references in the enclosing 'ST' action.
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
--
-- Uses hardware-accelerated memory block transfer ('copySmallArray').
copyFieldsFrom :: Rep f a -> Int -> MRep s f a -> Int -> Int -> ST s ()
copyFieldsFrom (Rep _ src) srcOff (MRep _ dst) dstOff len =
  copySmallArray dst dstOff src srcOff len

-- | In-place batch block copy between mutable builders.
copyMFields :: MRep s f a -> Int -> MRep s f a -> Int -> Int -> ST s ()
copyMFields (MRep _ src) srcOff (MRep _ dst) dstOff len =
  copySmallMutableArray dst dstOff src srcOff len

-- | Scoped pure modification wrapper.
--
-- Safely thaws an immutable 'Rep', runs an ST-scoped mutation callback, and freezes
-- the result back into an immutable 'Rep' without exposing mutable state.
modifyRep :: Rep f a -> (forall s. MRep s f a -> ST s ()) -> Rep f a
modifyRep (Rep t v) act = Rep t $ runSmallArray $ do
  m <- thawSmallArray v 0 (sizeofSmallArray v)
  act (MRep t m)
  pure m

{-------------------------------------------------------------------------------
  §3  Construction
-------------------------------------------------------------------------------}

-- | Build a product from its field values, in row order.
--
-- [ref:note-rep-memory-physics]
-- The tag is @0@: a product is the one-constructor sum. The payload values
-- are placed directly into a contiguous 'SmallArray'.
productRep :: [f Any] -> Rep f a
productRep xs = Rep 0 (smallArrayFromList xs)

-- | Build a sum value carrying the given tag and that constructor's fields.
--
-- [ref:note-rep-memory-physics]
-- The tag @t@ is an unboxed integer identifying the active constructor.
-- The payload array contains exactly the fields required by constructor @t@.
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
--
-- Algorithmic Mechanics:
-- In Core, this lowers directly to @indexSmallArray#@ followed by a no-op cast.
-- Because index @i@ is a compile-time constant emitted by the @TcPlugin@, there
-- is zero runtime dictionary lookup, zero branch instructions, and zero heap allocation.
fieldAt :: forall f a x. Int -> Rep f a -> f x
fieldAt i r = noInlineUnsafeCo (indexSmallArray (repVals r) i)

-- | Replace the payload slot at a compile-time-known index.
--
-- [ref:note-transient-cow]
-- For records with @>32@ fields (Milestone T3), uses hardware-vectorized SIMD
-- non-overlapping block copies ('copySmallArray'), eliminating redundant reads
-- and writes of slot @i@ from the source array.
--
-- For small records (@<=32@ fields), uses direct in-cache 'thawSmallArray'.
setFieldAt :: forall f a. Int -> f Any -> Rep f a -> Rep f a
setFieldAt i !x (Rep t v)
  | n > 32 = Rep t $ runSmallArray $ do
      -- Large Record Path (N > 32):
      -- Pre-fill new array with the target value x, then copy the two non-overlapping
      -- slices [0 .. i-1] and [i+1 .. n-1] via vectorized memmove.
      m <- newSmallArray n x
      when (i > 0) $
        copySmallArray m 0 v 0 i
      let !after = i + 1
          !lenAfter = n - after
      when (lenAfter > 0) $
        copySmallArray m after v after lenAfter
      pure m
  | otherwise = Rep t $ runSmallArray $ do
      -- Small Record Path (N <= 32):
      -- Entire array fits inside 4-5 L1 cache lines (256 bytes). Direct thaw and
      -- in-place slot write executes completely within CPU cache.
      m <- thawSmallArray v 0 n
      writeSmallArray m i x
      pure m
  where
    !n = sizeofSmallArray v

-- | Clone once, apply K updates in-place, freeze once.
--
-- [ref:note-transient-cow]
-- Reduces multi-field update overhead from @K * O(N)@ to @1 * O(N)@.
-- For records with @>32@ fields (Milestone T3), sorts update offsets and copies
-- non-overlapping unchanged slices in contiguous vectorized blocks.
setFieldsAt :: forall f a. [(Int, f Any)] -> Rep f a -> Rep f a
setFieldsAt [] r = r
setFieldsAt [(!i, !x)] r = setFieldAt i x r
setFieldsAt updates (Rep t v)
  | n > 32, (firstUpd : _) <- updates = Rep t $ runSmallArray $ do
      -- Large Record Multi-Update:
      -- Sort update offsets in O(K log K) to determine contiguous unchanged spans.
      let sortedUpds = sortOn fst updates
      m <- newSmallArray n (snd firstUpd)
      -- Recursively copy unchanged spans between update indices using SIMD block copies.
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
      -- Small Record Multi-Update:
      -- Direct thaw, followed by K in-place writes in L1 cache, then freeze.
      m <- thawSmallArray v 0 n
      forM_ updates $ \(i, !x) -> writeSmallArray m i x
      pure m
  where
    !n = sizeofSmallArray v

-- | Partial field update for sum constructors.
--
-- Ensures the runtime tag matches the expected constructor tag before updating.
-- If the sum value is not currently the specified constructor, returns 'Nothing'.
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
-- [ref:note-peeling-elimination]
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

{-------------------------------------------------------------------------------
  §5  Evidence classes

  The instance bodies are intended to be produced as integer literals by the
  TcPlugin, the same way @large-anon@ produces @DictRowHasField@. Until the
  plugin exists, the defaults are @undefined@; the concrete instances in the
  test suite are hand-written and stand in for what the plugin will emit.

  [ref:note-literal-evidence]
  Algorithmic Rationale:
  In traditional Haskell row libraries, operations like record equality or
  hashing require type-level inductive class resolution:
    instance (Eq x, Eq (Record xs)) => Eq (Record (x ': xs))
  This generates nested runtime call stacks of depth N, allocating dictionary
  frames at runtime and causing O(N^2) or O(N^3) compile-time slow-downs.
  In Polytropos, the @TcPlugin@ eliminates all type-level search:
  for any fully-known row, it emits evidence directly as unrolled Core expressions
  using literal indices, executing in a single flat unrolled loop.
-------------------------------------------------------------------------------}

-- | Field-wise equality for a product row.
--
-- The method works over t'RowRep', so the row is in the type and no 'Data.Proxy.Proxy'
-- argument is needed (obligation 4, design note §6). A plugin will build the
-- body by substituting literal slot indices and a literal element count, so
-- there is no type-level search at the use site.
--
-- [ref:note-literal-evidence]
-- The test suite writes these bodies by hand, which makes the tests the
-- specification of what the plugin must emit.
class RowFlavour r => RowEq (r :: RowType) (row :: k) where
  repEq :: RowRep f r row a -> RowRep f r row a -> Bool
  repEq _ _ = undefined

-- | Field-wise @Show@ for a product row. See 'RowEq' for the design.
--
-- [ref:note-literal-evidence]
-- The plugin synthesizes an unrolled sequence of per-field `showsPrec` calls,
-- formatting each field label as a literal string @"fieldname = "@ followed by
-- the field value's `showsPrec`, joined by comma separators.
class RowFlavour r => RowShow (r :: RowType) (row :: k) where
  repShowsPrec :: Int -> RowRep f r row a -> ShowS
  repShowsPrec _ _ = undefined

-- | Field-wise equality for a sum row.
--
-- Sums need their own class because the comparison includes the tag (the
-- constructor index), which products don't have (their tag is always 0 and
-- folds away).
--
-- [ref:note-literal-evidence]
-- Algorithmic Mechanics:
-- Two variant values `v1` and `v2` are equal iff:
--   1. Their runtime tags match: `repTag v1 == repTag v2`
--   2. Their payload fields for that specific active constructor match.
-- The plugin emits a Core `case` expression on the tag, branching into per-constructor
-- literal slot equality comparisons.
class RowFlavour r => RowEqSum (r :: RowType) (row :: k) where
  repEqSum :: RowRep f r row a -> RowRep f r row a -> Bool
  repEqSum _ _ = undefined

-- | Field-wise @Show@ for a sum row.
--
-- [ref:note-literal-evidence]
-- The plugin generates a jump table on `repTag`, emitting the constructor name
-- as a string literal followed by its payload record's field representations.
class RowFlavour r => RowShowSum (r :: RowType) (row :: k) where
  repShowsPrecSum :: Int -> RowRep f r row a -> ShowS
  repShowsPrecSum _ _ = undefined

-- | Evidence that a field name or type @n@ has a slot at a known index in a row.
--
-- The plugin solves this by inspecting the row and emitting the index as a
-- literal (obligation 1, design note §5).
--
-- Algorithmic Mechanics:
-- When GHC encounters a wanted constraint `FieldIndex "foo" r a`, the plugin
-- scans the type-level list `r` for the entry `"foo" ':= a`. It returns the
-- 0-based integer offset directly as a Core literal `Lit (MachInt i)`.
type FieldIndex :: forall {kn} k {ka}. kn -> k -> ka -> Constraint
class FieldIndex (n :: kn) (row :: k) (a :: ka) where
  fieldIndex :: Int
  fieldIndex = undefined

-- | Evidence that a constructor name or type @n@ has a known tag in a row.
--
-- The plugin solves this by inspecting the row and emitting the tag as a
-- literal (obligation 2, design note §5).
--
-- Algorithmic Mechanics:
-- For wanted `ConstructorIndex "Bar" s`, the plugin locates `"Bar"` in the sum
-- row `s` and produces an unboxed integer literal `Lit (MachWord t)`.
type ConstructorIndex :: forall {kn} k. kn -> k -> Constraint
class ConstructorIndex (n :: kn) (row :: k) where
  constructorIndex :: Word
  constructorIndex = undefined

-- | Witness for a class constraint @c a@.
--
-- Standard GADT representation of an explicit typeclass dictionary.
data Dict (c :: Type -> Constraint) (a :: Type) where
  Dict :: c a => Dict c a

-- | Evidence that all fields of a row satisfy some class.
--
-- @DictAny c@ is the type-erased form of @c Any@, mirroring @large-anon@'s
-- dictionary packing. It is what lets one dictionary carry many field
-- dictionaries without a type-level list of them.
--
-- Algorithmic Mechanics:
-- Under the hood, GHC typeclass dictionaries are ordinary record values containing
-- function pointers (vtable). Because all boxed heap objects have identical runtime
-- representation (a pointer), a dictionary for `c a` can be coerced to `c Any` via
-- 'noInlineUnsafeCo'. At point of consumption, passing an `Any` value cast from `a`
-- to a method in `c Any` is completely type-safe because the vtable functions match
-- the actual runtime type of the value.
data DictAny (c :: Type -> Constraint) where
  DictAny :: c Any => DictAny c

-- | Wrap a class dictionary into t'DictAny'.
mkDictAny :: forall c a. c a => DictAny c
mkDictAny = aux (noInlineUnsafeCo (Dict :: Dict c a) :: Dict c Any)
  where
    aux :: Dict c Any -> DictAny c
    aux Dict = DictAny

-- | Construct evidence for the 'AllFields' class.
--
-- Takes a list of type-erased dictionaries and places them into a contiguous
-- 'SmallArray' for O(1) indexed lookup during generic loops.
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
--
-- Algorithmic Mechanics:
-- Walks the field dictionary array and the two value arrays in lockstep from
-- index 0 to N-1. For each slot, unpacks `DictAny`, casts both values to `Any`,
-- and calls `compare`. If `EQ`, advances to the next slot; otherwise immediately
-- terminates with the comparison result.
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
-- [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- @'SubRow' sub super@ holds when every field in @sub@ occurs in @super@ with
-- the same field type. The plugin emits the 0-based projection slot indices
-- as evidence.
--
-- Algorithmic Mechanics:
-- For sub-record projection `projectRecord @sub superRec`, the runtime must extract
-- the subset of fields in @sub@ from @super@. The @subRowIndices@ method returns a
-- precomputed permutation vector `[Int]` containing the exact slot indices in @super@.
-- This allows projection to execute in a single O(|sub|) pass with zero type search.
type SubRow :: forall {k1} {k2}. k1 -> k2 -> Constraint
class SubRow (sub :: k1) (super :: k2) where
  -- | For each field in @sub@, its 0-based slot index in @super@.
  subRowIndices :: [Int]
  subRowIndices = undefined

-- | Sub-sum relationship between two sum rows (variant widening & narrowing).
--
-- [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- @'SubSum' sub super@ holds when every constructor in @sub@ occurs in @super@
-- with identical field rows. The plugin emits the injection tag indices
-- (for widening) and narrowing tag indices (for projection) as evidence.
--
-- Algorithmic Mechanics:
-- 1. Widening (`widenVariant`):
--    Total and O(1). Every constructor in @sub@ is present in @super@. The runtime tag
--    `t` in @sub@ is mapped to `subSumInjectIndices !! fromIntegral t`, which is
--    precomputed by the plugin.
-- 2. Narrowing (`narrowVariant`):
--    Partial and O(1). Inspects `subSumNarrowIndices !! fromIntegral t`. If the constructor
--    is present in @sub@, returns `Just subTag`; otherwise `Nothing`.
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
--
-- Algorithmic Mechanics:
-- The FNV-1a 64-bit algorithm evaluates over the UTF-8 bytes of the label string:
--   hash = 14695981039346656037 (offset basis)
--   for each byte c:
--     hash = (hash `xor` c) * 1099511628211 (prime)
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
--
-- Algorithmic Mechanics & Compiler Safety Invariant:
-- In modern GHC (9.6 through 9.14+), the Core simplifier performs aggressive
-- inlining and floating of coercions. If an unchecked coercion is marked inlineable,
-- GHC's simplifier may attempt to float the cast outside of enclosing lambdas or
-- push it across case branches where the type invariants are not yet established.
-- When running with @-dcore-lint@, this causes fatal Core Lint failures.
-- Marking 'noInlineUnsafeCo' as @{-# NOINLINE #-}@ establishes an impenetrable
-- optimization barrier, preventing the simplifier from inspecting or hoisting
-- the underlying @unsafeCoerce#@ primitive while still emitting zero runtime instructions.
noInlineUnsafeCo :: a -> b
{-# NOINLINE noInlineUnsafeCo #-}
noInlineUnsafeCo = unsafeCoerce
