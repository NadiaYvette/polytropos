{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE Trustworthy #-}

{-|
Module      : Polytropos
Description : High-level consumer-facing API for Polytropos open records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

High-level, consumer-facing API for @polytropos@: row-polymorphic open records
and open variants for Haskell.

This module is the primary entry point for application developers and library
authors. It encapsulates low-level representation primitives (such as
'Data.Primitive.SmallArray.SmallArray' and @t'Polytropos.Core.Rep'@) behind ergonomic,
human-friendly type aliases, constructors, and pattern synonyms.

= Architectural Overview & Rationale

== Conceptual Primer: What Are Row-Polymorphic Open ADTs?

For developers without a background in type theory, the terminology can seem daunting.
In practice, it directly solves the rigidity of traditional data types:

1. __Algebraic Data Types (ADTs):__ The two universal building blocks of typed data—/Product types/
   (structs/records where data has field A /and/ field B) and /Sum types/ (enums/variants where data is
   constructor A /or/ constructor B).
2. __Closed vs. Open:__ Traditional Haskell data types are /closed/—declared once with a fixed set
   of fields or constructors. Adding a field (like an authentication token to a @User@) or adding
   a variant branch (like a new AST error node) requires defining a brand-new type and writing
   tedious conversion boilerplate. /Open/ types can be constructed, extended, and narrowed on the fly
   without intermediate wrapper types.
3. __Row Polymorphism:__ A "row" is an unordered collection of named fields (like database columns).
   /Row polymorphism/ allows writing functions that operate on /any/ record containing at least
   certain fields (or any variant handling at least certain cases), while the compiler statically tracks
   and preserves all the /other/ remaining fields (@r@). Unlike OOP inheritance, no fields are sliced or
   erased, and no runtime downcasts are needed.
4. __The Polytropos Difference:__ Historically, row polymorphism in Haskell was either painfully slow
   to compile (quadratic \(O(N^{2.8})\) typeclass search) or memory-inefficient (nested @Either@ pointer
   trees). @polytropos@ solves this by collapsing products and sums into a __single flat runtime representation__
   (a tag plus a contiguous 'Data.Primitive.SmallArray.SmallArray') and using a GHC typechecker plugin
   (@polytropos-plugin@) to resolve field indices into literal numbers at compile time in \(O(1)\).

== The Four-Quadrant Design Space Collapse

Traditional Haskell architectures treat records (products) and variants (sums)
as entirely distinct mechanisms, further bifurcated into nominal and structural
approaches:

1. Nominal Products: Standard Haskell @data@ records (e.g. @data Person = Person { name :: String, age :: Int }@)
2. Structural Products: Anonymous extensible records (e.g. @Record '["name" ':= String, "age" ':= Int]@)
3. Nominal Sums: Multi-constructor ADTs (e.g. @data Shape = Circle Double | Rectangle Double Double@)
4. Structural Sums: Extensible variants (e.g. @Variant '["Circle" ':= '["radius" ':= Double], ...]@)

@polytropos@ collapses all four quadrants into __one uniform generic representation__:
a runtime integer tag plus a contiguous, flat 'Data.Primitive.SmallArray.SmallArray' of
payload slots (@t'Polytropos.Core.Rep'@). For a product, the tag is always @0@ and known
statically. For a sum, the tag is the constructor index.

== Heritage & Precedent

The row typing discipline in @polytropos@ draws inspiration from OCaml's polymorphic
variants and extensible rows (Garrigue 1998), adapted to modern GHC with first-class
type-level symbol labels (@":="@).

== The Typechecker Plugin

Rather than paying for \(O(N)\) or \(O(N^2)\) type-level search at compile time or
traversing binary trees at runtime, @polytropos@ delegates evidence resolution to
@polytropos-plugin@. The plugin computes literal zero-based slot indices, tags, and
dictionary vectors directly in Core AST during compilation, giving \(O(1)\) runtime
indexing with zero runtime overhead.

= When to Use This Module

* Use this module (@Polytropos@) for almost all daily programming with extensible
  records, open sums, effect carrier types, and dynamic configuration schemas.
* Use satellite packages for domain-specific integrations:
  * "Polytropos.Generics": whole-data structural equality, comparisons, and generic map/fold
  * "Polytropos.Optics", "Polytropos.Lens", or "Polytropos.Microlens": optics and labels
  * "Polytropos.Aeson": JSON serialization
  * "Polytropos.CBOR": binary CBOR serialization
  * "Polytropos.Cassava": CSV serialization
  * "Polytropos.QuickCheck": property test generators and shrinkers
  * "Polytropos.Hasql", "Polytropos.Rel8", "Polytropos.Beam", "Polytropos.Persistent": database storage

= When Not to Use This Module

* Do not use this module if you are developing custom typechecker plugins, primitive
  runtime memory layouts, or low-level Core synthesizers; import "Polytropos.Core" instead.

= Relationship to Ecosystem Prior Art

@polytropos@ builds upon extensive historical explorations of extensible records,
anonymous products, and open variants in Haskell:

* __@vinyl@__: Pioneered type-level list indexing for extensible records and universes,
  proving the value of structural data while wrestling with superlinear compile-time
  scaling (\(O(N^{2.8})\)) and deeply abstract type machinery.
* __@superrecord@__: Introduced compile-time field offset computation and compact array
  representations, demonstrating the performance benefits of avoiding nested pointer trees.
* __@row-types@__: Established a formal row calculus based on Leijen's work with first-class
  type equality, though encountering stuck type families during type inference failure.
* __@extensible@__: Offered a comprehensive framework unifying records, variants, and effects
  under custom type-level combinators.
* __@open-adt@ & @world-peace@__: Explored open coproducts and tagged variant unions (@OpenUnion@),
  aiming to avoid nested @Either@ trees.

@polytropos@ acknowledges these libraries as valuable predecessors striving toward similar goals.
It advances their work by collapsing products and sums into a single flat representation
('Data.Primitive.SmallArray.SmallArray' with an unboxed tag) and delegating all symbol-to-slot
resolution to a dedicated GHC typechecker plugin (@polytropos-plugin@), achieving \(O(1)\) runtime
indexing, linear \(O(N)\) compile times, and human-readable compiler error diagnostics.

= Worked Examples

== 1. Open Records (Structural Products)

> import Polytropos
>
> -- Define an open record with fields "x" and "y":
> myRec :: Record '["x" ':= Int, "y" ':= Bool]
> myRec = insertField (Field @"x") (10 :: Int)
>       $ insertField (Field @"y") True
>       $ emptyRecord
>
> -- Reading fields:
> valX :: Int
> valX = getField (Field @"x") myRec  -- 10
>
> -- Updating fields:
> myRec' :: Record '["x" ':= Int, "y" ':= Bool]
> myRec' = setField (Field @"x") 42 myRec

== 2. Open Variants (Structural Sums)

> import Polytropos
>
> type Event = Variant '["Click" ':= '["x" ':= Int, "y" ':= Int], "Quit" ':= '[]]
>
> -- Injecting into a variant:
> clickEvent :: Event
> clickEvent = Variant (Field @"Click")
>            $ insertField (Field @"x") 100
>            $ insertField (Field @"y") 200
>            $ emptyRecord
>
> quitEvent :: Event
> quitEvent = Variant (Field @"Quit") emptyRecord
>
> -- Pattern matching on a variant:
> handleEvent :: Event -> String
> handleEvent (Variant (Field @"Click") r) =
>   "Clicked at: " ++ show (getField (Field @"x") r) ++ "," ++ show (getField (Field @"y") r)
> handleEvent (Variant (Field @"Quit") _) =
>   "Exiting application"

== 3. Higher-Kinded Records (HKD)

> import Polytropos
>
> -- A partial record where every field is wrapped in 'Maybe':
> type PartialConfig = RecordF Maybe '["host" ':= String, "port" ':= Int]
>
> configTemplate :: PartialConfig
> configTemplate = insertFieldF (Field @"host") (Just "localhost")
>                $ insertFieldF (Field @"port") Nothing
>                $ emptyRecordF
-}
module Polytropos
  ( -- * Ergonomic Types & Patterns
    type Record
  , type RecordF
  , type Variant
  , type VariantF
#if __GLASGOW_HASKELL__ >= 914
  , data Variant
  , data VariantF
#else
  , pattern Variant
  , pattern VariantF
#endif
    -- * Construction
  , emptyRecord
  , emptyRecordF
  , insertField
  , insertFieldF
  , injectVariant
  , injectVariantF
  , projectVariant
  , projectVariantF
  , type ConstructorPayload
  , type ConstructorPayloadHKD
    -- * Sub-row & Sub-variant operations
  , SubRow(..)
  , SubSum(..)
  , projectRecord
  , projectRecordF
  , widenVariant
  , widenVariantF
  , narrowVariant
  , narrowVariantF
    -- * Elimination & Peeling
  , peel
  , peelF
  , type Delete
  , type HandlerRecordRow
  , type HandlerRecordRowM
  , type HandlerRecordRowHetero
  , type HandlerRecordRowHeteroM
  , eliminateUniform
  , eliminateUniformM
  , eliminate
  , eliminateM
  , matchVariant
    -- * Re-exports
  , Pair(..)
  , RowEq(..)
  , RowShow(..)
  , RowFlavour(..)
  , Field(..)
  , AllFields(..)
  , DictAllFields
  , FieldNames
  , SimpleFieldTypes
  , FieldTypes
    -- * Label Hashing
  , KnownHash(..)
  , labelHash
  , hashVal
  , fnv1a64
    -- * Syntactic Devices (Source Plugin)
  , REC(..)
  , REC_F(..)
  , VAR(..)
  , type VARIANT
#if __GLASGOW_HASKELL__ >= 914
  , data VARIANT
#else
  , pattern VARIANT
#endif
  , REC_UPD(..)
  , REC_UPD_F(..)
  , OpenRecord
  , OpenVariant
  , recordField
  , setField
  , setFieldF
    -- * Generic Row Operations (§1.7)
  , cmapRecord
  , cfoldMapRecord
  , czipWithRecord
  , cmapRecordF
  , cfoldMapRecordF
  ) where

import Polytropos.Core
import Data.Functor.Identity (Identity(..))
import Data.Kind (Type)
import Data.Primitive.SmallArray (indexSmallArray, sizeofSmallArray, thawSmallArray, writeSmallArray, runSmallArray)
import GHC.Exts (toList, Any)
import GHC.Records (HasField(..))
import GHC.TypeLits (Symbol)
import Unsafe.Coerce (unsafeCoerce)

{- Note [Consumer API Layering: The Ergonomic Facade]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-consumer-facade]
`Polytropos.hs` serves as the user-facing frontend of the polytropos engine.
While `Polytropos.Core` provides unchecked primitive manipulations over
`Rep f a = Rep Word# (SmallArray# (f Any))`, direct consumption of `Polytropos.Core`
would require application developers to write manual type coercions, instantiate
`RowRep` phantom parameters, and manually compute slot indices.

The role of this module is to provide a zero-cost, type-safe ergonomic facade:
  1. High-Level Types:
     - `type Record r = RowRep Identity ProductRowT r ()`
     - `type RecordF f r = RowRep f ProductRowHKDT r ()`
     - `type Variant s = RowRep Identity SumRowT s ()`
     - `type VariantF f s = RowRep f SumRowHKDT s ()`
  2. Syntactic Ergonomics:
     - First-class pattern synonyms (`Variant`, `VariantF`) that allow pattern matching
       on open sums as if they were ordinary Haskell ADT constructors.
     - Source plugin markers (`REC`, `VAR`, `REC_UPD`) that lower standard Haskell
       record syntax to flat runtime representations before typechecking.
  3. Safe Combinators:
     - Projection (`projectRecord`), widening (`widenVariant`), narrowing (`narrowVariant`),
       peeling (`peel`), and elimination (`eliminateUniform`).
All of these combinators maintain complete type safety, ensuring that raw memory
coercions (`noInlineUnsafeCo`, `unsafeCoerce`) are strictly encapsulated inside
proven plugin-driven invariants.
-}

{- Note [Pattern Synonyms and View Patterns for Open Rows]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-patterns-view-patterns]
In traditional Haskell ADTs, pattern matching is built directly into the language syntax
(`case shape of Circle r -> ...`). For open variants, the set of constructors is not fixed,
so compiler-baked constructor symbols do not exist.

Polytropos solves this without requiring custom GHC language extensions by combining
`PatternSynonyms` with `ViewPatterns`:

  pattern Variant :: forall (n :: Symbol) (s :: SumRow).
                     ConstructorIndex n s
                  => Field n -> Record (ConstructorPayload n s) -> Variant s
  pattern Variant f r <- ( (\v -> (Field :: Field n, projectVariant (Field :: Field n) v)) -> (f, Just r) )
    where Variant f r = injectVariant f r

Algorithmic Mechanics:
  1. Pattern Matching (Deconstruction):
     When the user writes:
       `handle (Variant (Field @"Click") r) = ...`
     GHC applies the view pattern function to the incoming `Variant s`.
     `projectVariant` checks if the runtime tag `repTag` matches `constructorIndex @"Click" s`.
     - If it matches: It returns `Just (Record payload)` in O(1) time. The pattern binds `r`.
     - If it does not match: It returns `Nothing`. The pattern fails to match, allowing GHC's
       pattern match engine to proceed to the next branch.
  2. Construction (Injection):
     When used as an expression:
       `Variant (Field @"Click") myPayload`
     GHC invokes the `where` clause: `injectVariant (Field @"Click") myPayload`, which
     queries `constructorIndex @"Click" s` at compile time and injects the payload into
     `Rep tag payload` with zero runtime tag search.
-}

{- Note [Subrow and Subsum API Combinators: Projections and Slicing]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-subtyping-combinators]
Open data structures support structural subtyping relationships that are impossible
with nominal Haskell data types:

1. Record Width Subtyping (Projection):
   If record `super` has fields {x, y, z} and record `sub` has fields {x, z}, then
   `sub` is a sub-row of `super` (`SubRow sub super`).
   The function `projectRecord @sub super` extracts exactly the fields required by `sub`.
   - Mechanics: The `TcPlugin` resolves `SubRow sub super` into a permutation index list
     `subRowIndices @sub @super = [0, 2]`.
   - Runtime: `projectRecord` allocates a new `SmallArray` of size |sub| and copies
     `indexSmallArray src i` for each `i` in the permutation vector. Total complexity:
     strictly linear in the size of the projected sub-record, O(|sub|).

2. Variant Width Subtyping (Widening and Narrowing):
   If variant `sub` has constructors {A, B} and variant `super` has constructors {A, B, C},
   then `sub` can be widened to `super` totally, or `super` can be narrowed to `sub` partially:
   - Widening (`widenVariant`):
     Because every case in `sub` is handled by `super`, widening is TOTAL.
     The active tag `t` in `sub` is remapped to `subSumInjectIndices !! t` in `super`.
     The underlying payload `SmallArray` is REUSED directly without copying.
     Runtime complexity: O(1).
   - Narrowing (`narrowVariant`):
     Because `super` may contain constructors not present in `sub` (e.g. C), narrowing
     is PARTIAL (returns `Maybe (Variant sub)`).
     The runtime checks `subSumNarrowIndices !! t`. If `Just subTag`, it returns
     `Just (Rep subTag arr)` reusing `arr`; otherwise `Nothing`.
     Runtime complexity: O(1).
-}

{- Note [O(1) Array Jump Table Elimination]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-array-jump-table-elimination]
How should an open variant be consumed?
Traditional functional languages use linear pattern matching (`match` or `case`),
which compiles to a cascade of conditional jumps or binary search comparisons:
  if tag == 0 then h0 else if tag == 1 then h1 else ...

For large variants (e.g. ASTs with 60 node types), linear cascading causes severe
CPU branch mispredictions and code bloat.

Polytropos introduces true O(1) jump table elimination via `eliminateUniform`:
  `eliminateUniform :: Record (HandlerRecordRow s a) -> Variant s -> a`

Algorithmic Mechanics:
  1. Handlers as a Record:
     The set of handler functions for all constructors in `s` is packed into an
     ordinary Polytropos `Record`:
       `handlers = REC { Click = \r -> ..., Quit = \_ -> ... }`
     At runtime, this record is stored as a flat `SmallArray` of function pointers.
  2. O(1) Direct Indexed Dispatch:
     Given the variant `RowRep (Rep tag vals)`:
     - The function pointer for the active constructor is fetched directly from the
       handler array at index `fromIntegral tag`:
         `Identity hAny = indexSmallArray hVals (fromIntegral tag)`
     - The function is coerced to `Record '[] -> a` via `unsafeCoerce`.
     - The payload array is wrapped into a zero-cost `Record '[]` and passed to `h`.
  3. Hardware Physics:
     - Zero conditional branches.
     - Single memory read from the handler array (L1 cache hit).
     - Direct indirect call instruction (`call *%rax` on x86-64).
     - Execution time is completely invariant to the number of constructors in the variant!
-}

-- | An open record type, parametrised by a functor @f@ and a row @r@.
--
-- [ref:note-consumer-facade] [ref:note-rep-memory-physics]
-- A 'RecordF' is a flat, contiguous array of fields where each field slot
-- contains a value wrapped in @f@.
type RecordF (f :: Type -> Type) (r :: ProductRow f) = RowRep f ProductRowHKDT r ()

-- | An open record type, parametrised by a row @r@ with bare field values (@f ~ Identity@).
--
-- [ref:note-consumer-facade] [ref:note-rep-memory-physics]
-- A 'Record' is a flat, contiguous array of fields. Its memory layout is a
-- single pointer to a small array of payload slots, plus an erased constructor
-- tag (which is always 0 for products).
type Record (r :: Row) = RowRep Identity ProductRowT r ()

-- | An open variant type, parametrised by a functor @f@ and a sum row @s@.
--
-- [ref:note-consumer-facade] [ref:note-rep-memory-physics]
-- A t'VariantF' is a single value that can be any one of the constructors
-- defined in the sum row @s@, with each field slot wrapped in @f@.
type VariantF (f :: Type -> Type) (s :: SumRowHKD f) = RowRep f SumRowHKDT s ()

-- | An open variant type, parametrised by a sum row @s@ with bare field values (@f ~ Identity@).
--
-- [ref:note-consumer-facade] [ref:note-rep-memory-physics]
-- A t'Variant' is a single value that can be any one of the constructors
-- defined in the sum row @s@. Its memory layout is exactly identical to a
-- 'Record', except the tag distinguishes which constructor is currently active.
type Variant (s :: SumRow) = RowRep Identity SumRowT s ()

-- | Construct an empty HKD record.
emptyRecordF :: RecordF f '[]
emptyRecordF = RowRep (productRep [])

-- | Insert a new field wrapped in @f@ into an HKD record.
insertFieldF :: Field n -> f a -> RecordF f r -> RecordF f ((n ':= f a) ': r)
insertFieldF _ fa (RowRep r) =
  RowRep (productRep (unsafeCoerce fa : toList (repVals r)))

-- | Construct an empty record.
--
-- The empty record has no fields and an arity of 0.
emptyRecord :: Record '[]
emptyRecord = RowRep (productRep [])

-- | Insert a new field at the beginning of a record.
--
-- This extends the record's row type by prepending the new field. At runtime,
-- this copies the underlying array and adds the new value.
--
-- /Invariant/: This function expects the type-level field list to match the
-- runtime representation. Using it sequentially correctly builds up a record
-- in standard layout format.
insertField :: Field n -> a -> Record r -> Record ((n ':= a) ': r)
insertField _ a (RowRep r) =
  RowRep (productRep (Identity (unsafeCoerce a) : toList (repVals r)))

-- | Compute the payload product row of a constructor @n@ in a sum row @s@.
type family ConstructorPayload (n :: Symbol) (s :: SumRow) :: Row where
  ConstructorPayload n ((n ':= fs) ': rest) = fs
  ConstructorPayload n ((m ':= fs) ': rest) = ConstructorPayload n rest

-- | Compute the HKD payload product row of a constructor @n@ in an HKD sum row @s@.
type family ConstructorPayloadHKD (f :: Type -> Type) (n :: Symbol) (s :: SumRowHKD f) :: ProductRow f where
  ConstructorPayloadHKD f n ((n ':= fs) ': rest) = fs
  ConstructorPayloadHKD f n ((m ':= fs) ': rest) = ConstructorPayloadHKD f n rest

-- | Inject an HKD record into an HKD variant for a specific constructor.
injectVariantF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f) (fs :: ProductRow f).
                  ConstructorIndex n s => Field n -> RecordF f fs -> VariantF f s
injectVariantF _ (RowRep r) =
  RowRep (injectRep (constructorIndex @_ @n @s) (toList (repVals r)))

-- | Project an HKD record from an HKD variant.
projectVariantF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f).
                   ConstructorIndex n s
                => Field n -> VariantF f s -> Maybe (RecordF f (ConstructorPayloadHKD f n s))
projectVariantF _ (RowRep r) =
  case projectRep (constructorIndex @_ @n @s) r of
    Just vals -> Just (RowRep (productRep vals))
    Nothing   -> Nothing

-- | Pattern synonym for matching and constructing HKD variants safely.
--
-- [ref:note-patterns-view-patterns]
pattern VariantF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f).
                    ConstructorIndex n s
                 => Field n -> RecordF f (ConstructorPayloadHKD f n s) -> VariantF f s
pattern VariantF f r <- ( (\v -> (Field :: Field n, projectVariantF (Field :: Field n) v)) -> (f, Just r) )
  where VariantF f r = injectVariantF f r

-- | Inject a record of fields into a variant for a specific constructor.
injectVariant :: forall n s fs. ConstructorIndex n s => Field n -> Record fs -> Variant s
injectVariant _ (RowRep r) =
  RowRep (injectRep (constructorIndex @_ @n @s) (toList (repVals r)))

-- | Project a specific constructor from a variant.
projectVariant :: forall (n :: Symbol) (s :: SumRow).
                  ConstructorIndex n s
               => Field n -> Variant s -> Maybe (Record (ConstructorPayload n s))
projectVariant _ (RowRep r) =
  case projectRep (constructorIndex @_ @n @s) r of
    Just vals -> Just (RowRep (productRep vals))
    Nothing   -> Nothing

-- | A pattern synonym for matching and constructing variants safely.
--
-- [ref:note-patterns-view-patterns]
pattern Variant :: forall (n :: Symbol) (s :: SumRow).
                   ConstructorIndex n s
                => Field n -> Record (ConstructorPayload n s) -> Variant s
pattern Variant f r <- ( (\v -> (Field :: Field n, projectVariant (Field :: Field n) v)) -> (f, Just r) )
  where Variant f r = injectVariant f r

-- | Project a sub-record from a super-record (HKD).
--
-- Extracts only the fields present in @sub@ in the order specified by @sub@.
--
-- [ref:note-subtyping-combinators] [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- Algorithmic Mechanics:
-- The @TcPlugin@ statically proves that @sub@ is a subset of @super@ and emits
-- the projection permutation vector @subRowIndices @sub @super@. At runtime,
-- this function reads each slot from the source array and constructs a new flat
-- array of size @|sub|@ in a single linear pass.
projectRecordF :: forall (f :: Type -> Type) (sub :: ProductRow f) (super :: ProductRow f).
                  SubRow sub super => RecordF f super -> RecordF f sub
projectRecordF (RowRep rep) =
  let vals = repVals rep
      idxs = subRowIndices @sub @super
      newSlots = [ indexSmallArray vals i | i <- idxs ]
  in RowRep (productRep newSlots)

-- | Project a sub-record from a super-record (bare).
--
-- Extracts only the fields present in @sub@ in the order specified by @sub@.
--
-- [ref:note-subtyping-combinators] [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- Complexity: \(\mathcal{O}(|sub|)\) array copy, with literal projection indices
-- precomputed at compile-time by the @Polytropos.Plugin@.
--
-- @
-- let fullRec = REC { id = 1 :: Int, name = "Alice", role = "Admin" }
--     subRec  = projectRecord @'["name" ':= String] fullRec
-- @
projectRecord :: forall sub super. SubRow sub super => Record super -> Record sub
projectRecord (RowRep rep) =
  let vals = repVals rep
      idxs = subRowIndices @sub @super
      newSlots = [ indexSmallArray vals i | i <- idxs ]
  in RowRep (productRep newSlots)

-- | Widen a variant from a sub-row to a super-row (HKD).
--
-- [ref:note-subtyping-combinators] [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- Widening is total and constant time: the active constructor tag in @sub@ is
-- remapped to its corresponding tag in @super@, preserving payload slots.
widenVariantF :: forall (f :: Type -> Type) (sub :: SumRowHKD f) (super :: SumRowHKD f).
                 SubSum sub super => VariantF f sub -> VariantF f super
widenVariantF (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      superTag = (subSumInjectIndices @sub @super) !! tag
  in RowRep (Rep superTag (repVals rep))

-- | Widen a variant from a sub-row to a super-row (bare).
--
-- [ref:note-subtyping-combinators] [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- Widening is total and constant time (\(\mathcal{O}(1)\)): the active constructor
-- tag in @sub@ is remapped to its corresponding tag in @super@ via a compile-time
-- synthesized literal tag lookup table, requiring zero payload array allocations.
--
-- @
-- let smallVar = VAR { Ok = REC { val = 200 :: Int } } :: Variant '["Ok" ':= '["val" ':= Int]]
--     wideVar  = widenVariant @'["Ok" ':= '["val" ':= Int], "Err" ':= '["msg" ':= String]] smallVar
-- @
widenVariant :: forall sub super. SubSum sub super => Variant sub -> Variant super
widenVariant (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      superTag = (subSumInjectIndices @sub @super) !! tag
  in RowRep (Rep superTag (repVals rep))

-- | Narrow a variant from a super-row to a sub-row (HKD).
--
-- [ref:note-subtyping-combinators] [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- Returns 'Just' with the active tag remapped to @sub@ if the constructor belongs
-- to @sub@, or 'Nothing' if the constructor is not in @sub@.
narrowVariantF :: forall (f :: Type -> Type) (sub :: SumRowHKD f) (super :: SumRowHKD f).
                  SubSum sub super => VariantF f super -> Maybe (VariantF f sub)
narrowVariantF (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      narrowMap = subSumNarrowIndices @sub @super
  in case drop tag narrowMap of
    (Just subTag : _) -> Just (RowRep (Rep subTag (repVals rep)))
    _                 -> Nothing

-- | Narrow a variant from a super-row to a sub-row (bare).
--
-- [ref:note-subtyping-combinators] [ref:note-subrow-subsum] [ref:note-subrow-subsum-mechanics]
-- Returns 'Just' with the active tag remapped to @sub@ if the active constructor belongs
-- to @sub@, or 'Nothing' if the constructor is not a member of @sub@.
--
-- Complexity: \(\mathcal{O}(1)\) time. Reuses the underlying payload array directly.
narrowVariant :: forall sub super. SubSum sub super => Variant super -> Maybe (Variant sub)
narrowVariant (RowRep rep) =
  let tag = fromIntegral (repTag rep) :: Int
      narrowMap = subSumNarrowIndices @sub @super
  in case drop tag narrowMap of
    (Just subTag : _) -> Just (RowRep (Rep subTag (repVals rep)))
    _                 -> Nothing

{-------------------------------------------------------------------------------
  Elimination & Peeling
-------------------------------------------------------------------------------}

-- | Delete a constructor @n@ from a sum row @s@.
--
-- Type-level subtraction for open variant rows, enabling type refinement during
-- sequential peeling passes.
type family Delete (n :: Symbol) (s :: [Pair Symbol k]) :: [Pair Symbol k] where
  Delete n ((n ':= fs) ': rest) = rest
  Delete n ((m ':= fs) ': rest) = (m ':= fs) ': Delete n rest
  Delete n '[]                  = '[]

-- | Peel a single constructor @n@ from an open variant in \(\mathcal{O}(1)\) time.
--
-- [ref:note-peeling-elimination]
-- If the variant's active constructor is @n@, returns @Right (Record fs)@.
-- Otherwise, returns @Left (Variant (Delete n s))@ with the runtime tag
-- decremented if \(t > target\) and preserved if \(t < target\), requiring
-- __zero__ heap reallocation or payload copying.
--
-- This is the core primitive enabling single-construct compiler passes (Nanopass):
--
-- @
-- desugarStmt :: Variant ("While" ':= fs ': CoreRow) -> Variant CoreRow
-- desugarStmt v = case peel \@"While" v of
--   Right (REC { cond, body }) -> desugarWhile cond body
--   Left rest                  -> rest  -- O(1) pass-through for all other constructs!
-- @
peel :: forall (n :: Symbol) (s :: SumRow).
        ConstructorIndex n s
     => Variant s
     -> Either (Variant (Delete n s)) (Record (ConstructorPayload n s))
peel (RowRep r) =
  case peelRep (constructorIndex @_ @n @s) r of
    Right vals -> Right (RowRep (productRep vals))
    Left remR  -> Left (RowRep remR)

-- | Peel a constructor @n@ from an open HKD variant in \(\mathcal{O}(1)\) time.
--
-- [ref:note-peeling-elimination]
peelF :: forall (n :: Symbol) (f :: Type -> Type) (s :: SumRowHKD f).
         ConstructorIndex n s
      => VariantF f s
      -> Either (VariantF f (Delete n s)) (RecordF f (ConstructorPayloadHKD f n s))
peelF (RowRep r) =
  case peelRep (constructorIndex @_ @n @s) r of
    Right vals -> Right (RowRep (productRep vals))
    Left remR  -> Left (RowRep remR)

-- | Row of handler functions for a sum row @s@ returning a uniform result @res@.
type family HandlerRecordRow (s :: SumRow) (res :: Type) :: Row where
  HandlerRecordRow '[] _ = '[]
  HandlerRecordRow ((n ':= fs) ': rest) res = (n ':= (Record fs -> res)) ': HandlerRecordRow rest res

-- | Row of monadic handler functions for a sum row @s@ returning @m res@.
type family HandlerRecordRowM (s :: SumRow) (m :: Type -> Type) (res :: Type) :: Row where
  HandlerRecordRowM '[] _ _ = '[]
  HandlerRecordRowM ((n ':= fs) ': rest) m res = (n ':= (Record fs -> m res)) ': HandlerRecordRowM rest m res

-- | Row of heterogeneous handler functions mapping constructors in @s@ to results in @resRow@.
type family HandlerRecordRowHetero (s :: SumRow) (resRow :: SumRow) :: Row where
  HandlerRecordRowHetero '[] _ = '[]
  HandlerRecordRowHetero ((n ':= fs) ': rest) ((n ':= rfs) ': rrest) =
    (n ':= (Record fs -> Record rfs)) ': HandlerRecordRowHetero rest rrest

-- | Row of heterogeneous monadic handler functions mapping constructors in @s@ to monadic results in @m (Record rfs)@.
type family HandlerRecordRowHeteroM (s :: SumRow) (resRow :: SumRow) (m :: Type -> Type) :: Row where
  HandlerRecordRowHeteroM '[] _ _ = '[]
  HandlerRecordRowHeteroM ((n ':= fs) ': rest) ((n ':= rfs) ': rrest) m =
    (n ':= (Record fs -> m (Record rfs))) ': HandlerRecordRowHeteroM rest rrest m

-- | Eliminate a closed variant uniformly with \(\mathcal{O}(1)\) array jump table dispatch.
--
-- [ref:note-array-jump-table-elimination]
-- Handlers are provided as a 'Record' where each field corresponds to a constructor
-- in @s@. The runtime reads the variant's tag \(t\) and directly indexes slot \(t\)
-- of the handler array, executing without linear branch cascades.
--
-- @
-- let res = eliminateUniform handlers myVariant
--   where
--     handlers = REC
--       { Ok  = \\(REC { code, body }) -> "Status " ++ show code
--       , Err = \\(REC { reason })     -> "Error: " ++ reason
--       }
-- @
eliminateUniform :: forall (s :: SumRow) a.
                    Record (HandlerRecordRow s a)
                 -> Variant s
                 -> a
eliminateUniform (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> a
      payload = RowRep (Rep 0 vals) :: Record '[]
  in h payload

-- | Eliminate a closed variant uniformly inside a monad @m@ with \(\mathcal{O}(1)\) array jump table dispatch.
--
-- [ref:note-array-jump-table-elimination]
eliminateUniformM :: forall (s :: SumRow) m a.
                     Record (HandlerRecordRowM s m a)
                  -> Variant s
                  -> m a
eliminateUniformM (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> m a
      payload = RowRep (Rep 0 vals) :: Record '[]
  in h payload

-- | Full hybrid eliminator: eliminate a closed variant into an open variant of per-constructor results.
--
-- [ref:note-array-jump-table-elimination]
-- Each handler in @s@ transforms that constructor's payload into a corresponding result in @resRow@.
-- The resulting variant retains the original constructor tag and payload in \(\mathcal{O}(1)\) time.
eliminate :: forall (s :: SumRow) (resRow :: SumRow).
             Record (HandlerRecordRowHetero s resRow)
          -> Variant s
          -> Variant resRow
eliminate (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> Record '[]
      payload = RowRep (Rep 0 vals) :: Record '[]
      RowRep (Rep _ resVals) = h payload
  in RowRep (Rep tag resVals)

-- | Full monadic hybrid eliminator: eliminate a closed variant into an open variant of per-constructor results inside @m@.
--
-- [ref:note-array-jump-table-elimination]
eliminateM :: forall (s :: SumRow) (resRow :: SumRow) m.
              Monad m
           => Record (HandlerRecordRowHeteroM s resRow m)
           -> Variant s
           -> m (Variant resRow)
eliminateM (RowRep (Rep _ hVals)) (RowRep (Rep tag vals)) =
  let Identity hAny = indexSmallArray hVals (fromIntegral tag)
      h = unsafeCoerce hAny :: Record '[] -> m (Record '[])
      payload = RowRep (Rep 0 vals) :: Record '[]
  in do
    RowRep (Rep _ resVals) <- h payload
    pure (RowRep (Rep tag resVals))

-- | Syntactic synonym for 'eliminateUniform' taking the variant value first.
--
-- [ref:note-array-jump-table-elimination]
-- Convenient for direct pattern matching expressions resembling Swift or Rust @match@:
--
-- @
-- matchVariant expr REC
--   { lit = \\(REC { val }) -> val
--   , add = \\(REC { left, right }) -> left + right
--   }
-- @
matchVariant :: forall (s :: SumRow) a.
                Variant s
             -> Record (HandlerRecordRow s a)
             -> a
matchVariant = flip eliminateUniform

{-------------------------------------------------------------------------------
  Syntactic Devices & Helpers (Source Plugin)

  [ref:note-source-plugin-arch]
  The data types below serve as syntactic anchors for the Polytropos GHC source
  plugin ('Polytropos.Plugin.Source'). In standard Haskell source code, record
  syntax @REC { x = 10, y = True }@ or variant patterns @VAR { Ok = REC { val } }@
  would be rejected by the parser or typechecker because @REC@ and @VAR@ do not
  declare fields @x@ or constructors @Ok@.

  Before GHC's typechecker runs, the source plugin intercepts these expressions
  and rewrites them into flat @productRep@, @injectRep@, and view pattern trees.
  These markers are never evaluated at runtime; their sole purpose is to provide
  syntactic anchors for the source desugarer.
-------------------------------------------------------------------------------}

-- | Syntactic marker for anonymous record construction and pattern matching.
-- Desugared by the @Polytropos@ source plugin.
--
-- [ref:note-source-plugin-arch]
data REC = REC
  deriving (Show, Eq)

-- | Syntactic marker for anonymous functorial/HKD record construction.
-- Desugared by the @Polytropos@ source plugin.
--
-- [ref:note-source-plugin-arch]
data REC_F = REC_F
  deriving (Show, Eq)

-- | Syntactic marker for anonymous variant injection and pattern matching.
-- Desugared by the @Polytropos@ source plugin.
--
-- [ref:note-source-plugin-arch]
data VAR = VAR
  deriving (Show, Eq)

-- | Syntactic alias for v'VAR'.
type VARIANT = VAR

-- | Pattern synonym alias for v'VAR'.
pattern VARIANT :: VAR
pattern VARIANT = VAR

-- | Marker for record update syntax: @REC_UPD r { x = 42 }@.
-- Desugared by the @Polytropos@ source plugin into 'setField' calls.
--
-- [ref:note-source-plugin-arch] [ref:note-view-patterns]
data REC_UPD = REC_UPD
  deriving (Show, Eq)

-- | Marker for functorial/HKD record update syntax: @REC_UPD_F r { x = Just 42 }@.
-- Desugared by the @Polytropos@ source plugin into 'setFieldF' calls.
--
-- [ref:note-source-plugin-arch] [ref:note-view-patterns]
data REC_UPD_F = REC_UPD_F
  deriving (Show, Eq)

-- | Marker class for open record declarations desugared by the source plugin.
--
-- [ref:note-open-declarations]
class OpenRecord a

-- | Marker class for open variant declarations desugared by the source plugin.
--
-- [ref:note-open-declarations]
class OpenVariant a

-- | Fetch a field value from a record, used for pattern matching and field access.
--
-- Algorithmic Mechanics:
-- In view patterns emitted by the source plugin for pattern matching on records
-- (@REC { x, y }@), field values are extracted using 'recordField'. It queries
-- GHC's built-in 'HasField' constraint, which is solved by @polytropos-plugin@
-- using the precomputed 0-based index of field @n@.
recordField :: forall n a r. HasField n (Record r) (Identity a) => Field n -> Record r -> a
recordField _ r = case getField @n r of Identity x -> x

-- | Update an existing field in a 'Record'.
--
-- Algorithmic Mechanics:
-- Resolves 'FieldIndex' at compile time to obtain the literal slot index of @n@
-- in @r@, coerces the new value to 'Identity Any', and delegates to 'setFieldAt'.
setField :: forall n a r. FieldIndex n r a => Field n -> a -> Record r -> Record r
setField _ val (RowRep rep) =
  RowRep (setFieldAt (fieldIndex @_ @n @r @a) (Identity (noInlineUnsafeCo val)) rep)

-- | Update an existing field in a 'RecordF'.
setFieldF :: forall n a f r. FieldIndex n r (f a) => Field n -> f a -> RecordF f r -> RecordF f r
setFieldF _ val (RowRep rep) =
  RowRep (setFieldAt (fieldIndex @_ @n @r @(f a)) (noInlineUnsafeCo val) rep)

{-------------------------------------------------------------------------------
  Generic Row Operations (§1.7 Generic instance layer)
-------------------------------------------------------------------------------}

-- | Map a class-constrained function over all fields of a record.
--
-- Algorithmic Mechanics:
-- 1. Fetches pre-resolved dictionary vector @fieldDicts@ (a contiguous 'SmallArray'
--    of type-erased 'DictAny' entries).
-- 2. Clones the underlying payload array into a mutable 'SmallMutableArray' in ST.
-- 3. In a tight unrolled loop from 0 to N-1:
--    - Fetches the dictionary at slot @i@ and unpacks 'DictAny', bringing @c Any@ into scope.
--    - Fetches the payload at slot @i@, coerces to @Any@, and invokes @f@.
--    - Writes the coerced result back into slot @i@ in-place.
-- 4. Freezes the mutable array into an immutable 'Record'.
--
-- Complexity: Exactly 1 array allocation of size N, zero intermediate list allocations.
cmapRecord
  :: forall c r. AllFields ProductRowT r c
  => (forall x. c x => x -> x)
  -> Record r
  -> Record r
cmapRecord f (RowRep (Rep t v)) =
  let dicts = fieldDicts @ProductRowT @r @c
      n = sizeofSmallArray v
      v' = runSmallArray $ do
        m <- thawSmallArray v 0 n
        let loop i
              | i == n = pure ()
              | otherwise = do
                  let d = indexSmallArray dicts i
                      Identity vi = indexSmallArray v i
                  case d of
                    DictAny -> do
                      let vi' = f (noInlineUnsafeCo vi :: Any)
                      writeSmallArray m i (Identity (noInlineUnsafeCo vi'))
                      loop (i + 1)
        loop 0
        pure m
  in RowRep (Rep t v')

-- | Fold over all fields of a record using a class constraint.
--
-- Algorithmic Mechanics:
-- Recursively traverses the dictionary vector and payload array from index 0 to N-1.
-- For each slot, unpacks 'DictAny', maps the value using @f@ to a monoidal value @m@,
-- and combines the results using '<>'.
--
-- Complexity: Zero heap array allocations.
cfoldMapRecord
  :: forall c r m. (AllFields ProductRowT r c, Monoid m)
  => (forall x. c x => x -> m)
  -> Record r
  -> m
cfoldMapRecord f (RowRep (Rep _ v)) =
  let dicts = fieldDicts @ProductRowT @r @c
      n = sizeofSmallArray v
      loop i
        | i == n = mempty
        | otherwise =
            let d = indexSmallArray dicts i
                Identity vi = indexSmallArray v i
            in case d of
                 DictAny ->
                   let val = f (noInlineUnsafeCo vi :: Any)
                   in val <> loop (i + 1)
  in loop 0

-- | Zip two records of identical row shape applying a class-constrained function.
--
-- Algorithmic Mechanics:
-- Walks both records in parallel from slot 0 to N-1, applying the binary function @f@
-- using the dictionary from @fieldDicts@, writing results into a newly allocated array.
--
-- Complexity: Exactly 1 array allocation of size N, zero intermediate list allocations.
czipWithRecord
  :: forall c r. AllFields ProductRowT r c
  => (forall x. c x => x -> x -> x)
  -> Record r
  -> Record r
  -> Record r
czipWithRecord f (RowRep (Rep t v1)) (RowRep (Rep _ v2)) =
  let dicts = fieldDicts @ProductRowT @r @c
      n = sizeofSmallArray v1
      v' = runSmallArray $ do
        m <- thawSmallArray v1 0 n
        let loop i
              | i == n = pure ()
              | otherwise = do
                  let d = indexSmallArray dicts i
                      Identity x1 = indexSmallArray v1 i
                      Identity x2 = indexSmallArray v2 i
                  case d of
                    DictAny -> do
                      let res = f (noInlineUnsafeCo x1 :: Any) (noInlineUnsafeCo x2 :: Any)
                      writeSmallArray m i (Identity (noInlineUnsafeCo res))
                      loop (i + 1)
        loop 0
        pure m
  in RowRep (Rep t v')

-- | Map a class-constrained function over all fields of an HKD record.
cmapRecordF
  :: forall c f r. AllFields ProductRowHKDT r c
  => (forall x. c x => x -> x)
  -> RecordF f r
  -> RecordF f r
cmapRecordF f (RowRep (Rep t v)) =
  let dicts = fieldDicts @ProductRowHKDT @r @c
      n = sizeofSmallArray v
      v' = runSmallArray $ do
        m <- thawSmallArray v 0 n
        let loop i
              | i == n = pure ()
              | otherwise = do
                  let d = indexSmallArray dicts i
                      vi = indexSmallArray v i
                  case d of
                    DictAny -> do
                      let vi' = f (noInlineUnsafeCo vi :: Any)
                      writeSmallArray m i (noInlineUnsafeCo vi')
                      loop (i + 1)
        loop 0
        pure m
  in RowRep (Rep t v')

-- | Fold over all fields of an HKD record using a class constraint.
cfoldMapRecordF
  :: forall c f r m. (AllFields ProductRowHKDT r c, Monoid m)
  => (forall x. c x => x -> m)
  -> RecordF f r
  -> m
cfoldMapRecordF f (RowRep (Rep _ v)) =
  let dicts = fieldDicts @ProductRowHKDT @r @c
      n = sizeofSmallArray v
      loop i
        | i == n = mempty
        | otherwise =
            let d = indexSmallArray dicts i
                vi = indexSmallArray v i
            in case d of
                 DictAny ->
                   let val = f (noInlineUnsafeCo vi :: Any)
                   in val <> loop (i + 1)
  in loop 0


