{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module      : Polytropos.Aeson
Description : aeson JSON codecs for Polytropos open records and variants
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Linear \(O(N)\) 'A.ToJSON' and 'A.FromJSON' instances for 'Record' and 'Variant'
without standard "GHC.Generics" compile slowdowns: the codecs unroll the
flat @t'Polytropos.Core.Rep'@ payload directly into a JSON object and back,
with no generic-representation tree anywhere.

= Architectural Overview & Rationale

== Encoding Structure

* A record encodes as an anonymous JSON object with one key per field symbol, in row order.
* A variant encodes as a single-member tagged object @{"ctor": fields}@, where the
  member key is the active constructor symbol and the value is the JSON object of that
  constructor's payload fields (or empty object for a nullary constructor).

== Why Avoid GHC.Generics Trees for JSON

Standard @aeson@ deriving walks a nested binary tree of @M1@, @(:*:)@, and @(:+:)@ constructors.
On large schemas (30+ fields or constructors), this causes significant compile-time memory
blow-up. @polytropos-aeson@ walks the flat array of payload slots in a single tight loop
directly into @aeson@'s 'Data.Aeson.KeyMap.KeyMap'.

= When to Use This Module

* When serializing or deserializing @polytropos@ open records and variants to and from JSON.

= Worked Example

Records are most conveniently constructed using the @REC { ... }@ syntax enabled
by the @polytropos@ source plugin (via @-fplugin=Polytropos.Plugin@).

Because the standard instances operate directly over the flat payload buffer using a single
uniform dictionary, records must currently be __homogeneous__ (all fields sharing a single
uniform type @a@, as witnessed by 'AllFieldsAre'):

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE OverloadedStrings #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Data.Aeson (encode, decode)
> import Polytropos
> import Polytropos.Aeson
>
> type ServerConfig = Record '["host" ':= String, "port" ':= String]
>
> cfg :: ServerConfig
> cfg = REC { host = "localhost", port = "8080" }
>
> -- Encodes to JSON: {"host":"localhost","port":"8080"}
> jsonBytes = encode cfg
>
> -- Decodes back to ServerConfig:
> Just cfg' = decode @ServerConfig jsonBytes

__Note on Heterogeneous Records:__ If your record contains heterogeneous types
(e.g., mixing @String@ and @Int@ as in @Record '["host" ':= String, "port" ':= Int]@),
it cannot use the uniform 'AllFieldsAre' instance because a single @ToJSON@ dictionary
cannot serialize both @String@ and @Int@. Heterogeneous serialization across open
rows is provided via the generic dictionary matrix in @polytropos-generics@
or custom field traversals.

Variants are constructed via 'Polytropos.Variant' or 'Polytropos.injectVariant' and encode to single-member
tagged JSON objects:

> type Response = Variant '["Ok" ':= '["body" ':= String], "Err" ':= '["reason" ':= String]]
>
> resp :: Response
> resp = Variant (Field @"Ok") (REC { body = "server ready" })
>
> -- Encodes to JSON: {"Ok":{"body":"server ready"}}
> respBytes = encode resp
-}
module Polytropos.Aeson
  ( -- * Homogeneity Evidence and Row Introspection
    -- $homogeneity
    AllFieldsAre
  , AllCtorsHom (..)
  , FieldNames (..)
  , RowField
  , SumField
  ) where

import Control.Monad         (forM)
import Data.Functor.Identity (Identity (..))
import Data.Kind             (Constraint, Type)
import Data.Proxy            (Proxy (..))
import Data.Void             (Void)
import qualified Data.Text as T
import GHC.Exts              (Any, toList)
import GHC.TypeLits          (KnownSymbol, symbolVal)
import qualified Data.Aeson        as A
import qualified Data.Aeson.Types  as AT
import qualified Data.Aeson.Key    as K
import qualified Data.Aeson.KeyMap as KM
import Polytropos            (Record, Variant)
import Polytropos.Core       (Pair (..), Row, SumRow, RowRep (..), noInlineUnsafeCo,
                              productRep, injectRep, repTag, repVals)

{-------------------------------------------------------------------------------
  Homogeneity evidence and row introspection
-------------------------------------------------------------------------------}

-- $homogeneity
--
-- === Why Homogeneity Evidence?
--
-- In @polytropos@, open records ('Record') and open variants ('Variant') are
-- both newtypes over the same unified runtime representation: 'Polytropos.Core.Rep'.
-- Internally, 'Polytropos.Core.Rep' holds an unboxed constructor tag and a flat,
-- contiguous array of payload slots:
--
-- > data Rep (f :: Type -> Type) a = Rep {-# UNPACK #-} !Word !(SmallArray (f Any))
--
-- Traditional serialization libraries (such as built-in "GHC.Generics" or standard
-- extensible-record libraries) serialize data types by recursively walking a nested
-- binary tree of constructors (@(:*:)@ for products and @(:+:)@ for sums), resolving
-- distinct 'A.ToJSON' and 'A.FromJSON' typeclass dictionaries at every individual leaf.
-- On schemas with dozens of fields or constructors, this recursive tree structure
-- causes severe compile-time code bloat and heavy runtime intermediate allocations.
--
-- @polytropos-aeson@ eliminates the binary tree entirely: it reads the flat
-- payload array directly and unrolls it into an @aeson@ 'Data.Aeson.KeyMap.KeyMap'
-- in a single linear \(O(N)\) loop.
--
-- === The Dictionary Problem and Homogeneous Rows
--
-- In an arbitrary heterogeneous record (such as @Record '["host" ':= Text, "port" ':= Int]@),
-- each slot in the flat array holds a different Haskell type. Serializing each
-- slot requires a distinct typeclass dictionary ('A.ToJSON Text', 'A.ToJSON Int').
-- In Haskell, dispatching heterogeneous dictionaries over an untyped
-- @SmallArray (Identity Any)@ requires either:
--
-- 1. A compiler plugin synthesizing a vector of dictionary pointers at every call site, or
-- 2. A 2D dictionary matrix (as implemented in @polytropos-generics@).
--
-- However, an enormous class of high-throughput serialization workloads—such
-- as sensor telemetry (@Record '["temp" ':= Double, "humidity" ':= Double]@),
-- metric counters (@Record '["requests" ':= Int, "errors" ':= Int]@), tabular
-- data, coordinates, and uniform string-keyed configuration payloads—are __homogeneous__:
-- every field in the row shares the exact same Haskell type @a@.
--
-- For homogeneous rows, a __single__ 'A.ToJSON' @a@ or 'A.FromJSON' @a@ dictionary
-- suffices for the entire record! The entire array can be safely unrolled
-- into an @aeson@ object with zero dictionary overhead, zero intermediate tree
-- allocations, and without requiring the compiler plugin at codec call sites.
--
-- === Role of the Reflection and Evidence Types
--
-- The types in this section serve two distinct roles:
--
-- 1. __Static Safety Witnesses:__
--    * 'AllFieldsAre' is a closed type family asserting that /every/ field in a row
--      has type @a@. If a row contains even a single mismatched type, 'AllFieldsAre'
--      fails to reduce, causing GHC to statically reject the 'A.ToJSON' or
--      'A.FromJSON' instance rather than permitting a runtime type violation.
--    * 'RowField' and 'SumField' compute the uniform payload type directly from
--      the row, eliminating type ambiguity for instance resolution.
--
-- 2. __Runtime Row Reflection:__
--    * 'FieldNames' reifies type-level 'GHC.TypeLits.Symbol' field labels into
--      runtime @['String']@ keys (and @aeson@ 'Data.Aeson.Key.Key's) in exact row order.
--    * 'AllCtorsHom' reifies the entire constructor topology of a sum row into
--      @[(String, [String])]@ (mapping each constructor name to its list of field names).
--      This table drives \(O(1)\) constructor tag dispatch during serialization and
--      schema-guided parser selection during deserialization.
--
-- === Extensibility for Custom Codecs
--
-- These type families and typeclasses are exported publicly so that developers
-- building custom wire encoders (e.g. snake_case translators, field-omitting codecs,
-- alternative tagged/untagged sum encodings, or binary serializers like CBOR or CSV)
-- can inspect @polytropos@ row metadata and safely operate directly on the flat
-- 'Polytropos.Core.Rep' buffer.

-- | Evidence that every field of the row @r@ has type @a@.
--
-- This closed type family serves as a static homogeneity witness. If every
-- field payload matches @a@, it reduces to the satisfied constraint @()@.
-- If any field fails to match @a@, the family gets stuck, preventing the
-- dependent 'A.ToJSON' and 'A.FromJSON' instances from applying at compile time.
type family AllFieldsAre (a :: Type) (r :: Row) :: Constraint where
  AllFieldsAre _  '[]                = ()
  AllFieldsAre a ((n ':= a) ': rest) = AllFieldsAre a rest

-- | Extracts the uniform field type of a homogeneous row: the type of /every/
-- field, or 'Void' for the empty row @'[]@.
--
-- In instance heads, the constraint @a ~ RowField r@ allows GHC to infer the
-- concrete payload type @a@ directly from the row without ambiguity.
type family RowField (r :: Row) :: Type where
  RowField '[]                 = Void
  RowField ((n ':= a) ': rest) = a

-- | Extracts the uniform field type shared by every constructor of a homogeneous
-- sum row, or 'Void' for the empty sum @'[]@.
type family SumField (s :: SumRow) :: Type where
  SumField '[]                = Void
  SumField ((c ':= fs) ': s)  = RowField fs

-- | The field names of a row, in exact row order, reified from type-level
-- 'GHC.TypeLits.Symbol' labels into runtime @['String']@ keys.
class FieldNames (r :: Row) where
  fieldNames :: Proxy r -> [String]

instance FieldNames '[] where
  fieldNames _ = []

instance (KnownSymbol n, FieldNames r) => FieldNames ((n ':= a) ': r) where
  fieldNames _ = symbolVal (Proxy @n) : fieldNames (Proxy @r)

-- | Reflection dictionary for homogeneous sum rows (variants).
--
-- Reifies the full constructor topology into a runtime list pairing each
-- constructor symbol with its ordered field symbols: @[(String, [String])]@.
--
-- The type parameter @a@ appears in the method signature so the dictionary
-- is never ambiguous at call sites (otherwise @a@ would be phantom).
class AllCtorsHom (a :: Type) (s :: SumRow) where
  ctorSpecs :: Proxy a -> Proxy s -> [(String, [String])]

instance AllCtorsHom a '[] where
  ctorSpecs _ _ = []

instance ( KnownSymbol c, FieldNames fs, AllFieldsAre a fs, AllCtorsHom a s )
      => AllCtorsHom a ((c ':= fs) ': s) where
  ctorSpecs pa _ =
    (symbolVal (Proxy @c), fieldNames (Proxy @fs)) : ctorSpecs pa (Proxy @s)

{-------------------------------------------------------------------------------
  Record codecs
-------------------------------------------------------------------------------}

-- | Encode a homogeneous 'Record' into an aeson 'KM.KeyMap'.
--
-- Walks the flat payload array in @repVals rep@ in parallel with the reified
-- 'fieldNames'. Under the static guarantee of 'AllFieldsAre a r', each slot's
-- 'Identity Any' is safely coerced to @a@ via 'noInlineUnsafeCo' and serialized
-- using the single uniform 'A.ToJSON a' dictionary.
recordObject :: forall a r. (a ~ RowField r, AllFieldsAre a r, FieldNames r, A.ToJSON a)
             => Record r -> KM.KeyMap A.Value
recordObject (RowRep rep) = KM.fromList
  [ (K.fromText (T.pack k), A.toJSON (noInlineUnsafeCo (runIdentity v) :: a))
  | (k, v) <- zip (fieldNames (Proxy @r)) (toList (repVals rep)) ]

-- | Parse an aeson 'A.Object' into a homogeneous 'Record'.
--
-- Verifies that the JSON object contains exactly the expected number of keys,
-- parses each field in row order, and packs them directly into flat 'productRep'.
parseRecord :: forall a r. (a ~ RowField r, AllFieldsAre a r, FieldNames r, A.FromJSON a)
            => A.Object -> AT.Parser (Record r)
parseRecord obj
  | KM.size obj /= length ks = fail "polytropos-aeson: field count mismatch"
  | otherwise = do
      vs <- forM ks $ \k -> obj A..: K.fromText (T.pack k)
      pure (RowRep (productRep (map (Identity . noInlineUnsafeCo) (vs :: [a]))))
  where
    ks = fieldNames (Proxy @r)

instance {-# OVERLAPPABLE #-} ( a ~ RowField r
                              , AllFieldsAre a r
                              , FieldNames r
                              , A.ToJSON a
                              )
      => A.ToJSON (Record r) where
  toJSON rec = A.Object (recordObject rec)
  toJSONList xs = AT.listValue (A.Object . recordObject) xs
  toEncoding rec = A.toEncoding (A.Object (recordObject rec))
  toEncodingList xs = AT.listEncoding (A.toEncoding . A.Object . recordObject) xs
  omitField _ = False

instance {-# OVERLAPPABLE #-} ( a ~ RowField r
                              , AllFieldsAre a r
                              , FieldNames r
                              , A.FromJSON a
                              )
      => A.FromJSON (Record r) where
  parseJSON = A.withObject "Record" parseRecord
  parseJSONList v = case v of
    AT.Array vals -> traverse step (toList vals)
      where step = A.withObject "Record" (\o -> parseRecord o :: AT.Parser (Record r))
    _             -> fail "polytropos-aeson: expected an array of records"
  omittedField = Nothing

{-------------------------------------------------------------------------------
  Variant codecs
-------------------------------------------------------------------------------}

-- | Encode the active variant constructor: a single-member JSON object whose
-- key is the constructor name and whose value is that constructor's field object.
--
-- Uses the constructor tag @repTag rep@ as an \(O(1)\) index into 'ctorSpecs'
-- to locate the active constructor label and its field names.
variantValue :: forall a s. (a ~ SumField s, AllCtorsHom a s, A.ToJSON a)
             => Variant s -> A.Value
variantValue (RowRep rep) =
  case drop (fromIntegral (repTag rep)) (ctorSpecs (Proxy @a) (Proxy @s)) of
    (nm, ks) : _ ->
      A.Object (KM.fromList [(K.fromText (T.pack nm),
                              A.Object (fieldsObject @a ks (toList (repVals rep))))])
    [] -> error "polytropos-aeson: constructor tag out of range"

-- | Helper to build a 'KM.KeyMap' from field names and untyped payload slots.
fieldsObject :: forall a. A.ToJSON a => [String] -> [Identity Any] -> KM.KeyMap A.Value
fieldsObject ks vs = KM.fromList
  [ (K.fromText (T.pack k), A.toJSON (noInlineUnsafeCo (runIdentity v) :: a))
  | (k, v) <- zip ks vs ]

-- | Parse a single-member JSON object into a homogeneous 'Variant'.
--
-- Looks up the single JSON key in 'ctorSpecs' to determine the constructor
-- index @i@ and field names @ks@, parses the nested fields object, and
-- constructs the variant via 'injectRep'.
parseVariant :: forall a s. (a ~ SumField s, AllCtorsHom a s, A.FromJSON a)
             => A.Object -> AT.Parser (Variant s)
parseVariant obj = case KM.toList obj of
  [(k, v)] -> go (K.toText k) (zip [0 :: Int ..] specs) v
  _        -> fail "polytropos-aeson: expected a single-member object"
  where
    specs :: [(String, [String])]
    specs = ctorSpecs (Proxy @a) (Proxy @s)

    go nm ((i, (nm', ks)) : rest) v
      | nm == T.pack nm' = do
          vs <- parseFields ks v
          pure (RowRep (injectRep (fromIntegral i)
                                  (map (Identity . noInlineUnsafeCo) (vs :: [a]))))
      | otherwise = go nm rest v
    go _ [] _ = fail "polytropos-aeson: unknown constructor"

    parseFields ks v = case v of
      A.Object o -> forM ks $ \fn -> o A..: K.fromText (T.pack fn)
      _          -> fail "polytropos-aeson: expected an object of constructor fields"

instance {-# OVERLAPPABLE #-} ( a ~ SumField s
                              , AllCtorsHom a s
                              , A.ToJSON a
                              )
      => A.ToJSON (Variant s) where
  toJSON v = variantValue v
  toJSONList xs = AT.listValue variantValue xs
  toEncoding v = A.toEncoding (variantValue v)
  toEncodingList xs = AT.listEncoding (A.toEncoding . variantValue) xs
  omitField _ = False

instance {-# OVERLAPPABLE #-} ( a ~ SumField s
                              , AllCtorsHom a s
                              , A.FromJSON a
                              )
      => A.FromJSON (Variant s) where
  parseJSON = A.withObject "Variant" parseVariant
  parseJSONList v = case v of
    AT.Array vals -> traverse step (toList vals)
      where step = A.withObject "Variant" (\o -> parseVariant o :: AT.Parser (Variant s))
    _             -> fail "polytropos-aeson: expected an array of variants"
  omittedField = Nothing
