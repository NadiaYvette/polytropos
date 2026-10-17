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

Linear \(O(N)\) 'A.ToJSON' and 'A.FromJSON' instances for heterogeneous and
homogeneous 'Record' and 'Variant' types without standard "GHC.Generics"
compile slowdowns: the codecs unroll the flat @Rep@ payload directly into
a JSON object and back, with no generic-representation tree anywhere.

= Architectural Overview & Rationale

== Encoding Structure

* A record encodes as an anonymous JSON object with one key per field symbol, in row order.
* A variant encodes as a single-member tagged object @{"ctor": fields}@, where the
  member key is the active constructor symbol and the value is the JSON object of that
  constructor's payload fields (or empty object for a nullary constructor).

== Truly Heterogeneous Row Support

Unlike satellites restricted to homogeneous types, @polytropos-aeson@ provides genuine
heterogeneous serialization across open rows via 'AllToJSON' and 'AllFromJSON':
every field requires 'A.ToJSON' \/ 'A.FromJSON' at /its own concrete type/, so rows
mixing 'String', 'Int', 'Bool', custom types, or nested rows serialize and deserialize
directly without nominal intermediate wrappers.

== Why Avoid GHC.Generics Trees for JSON

Standard @aeson@ deriving walks a nested binary tree of @M1@, @(:*:)@, and @(:+:)@ constructors.
On large schemas (30+ fields or constructors), this causes significant compile-time memory
blow-up and runtime intermediate allocation overhead. @polytropos-aeson@ walks the flat array of
payload slots in a single tight loop directly into @aeson@'s 'Data.Aeson.KeyMap.KeyMap'.

= When to Use This Module

* When serializing or deserializing @polytropos@ open records and variants to and from JSON.

= Worked Example

Records are most conveniently constructed using the @REC { ... }@ syntax enabled
by the @polytropos@ source plugin (via @-fplugin=Polytropos.Plugin@):

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE OverloadedStrings #-}
> {-# LANGUAGE TypeApplications #-}
> {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
>
> import Data.Aeson (encode, decode)
> import Polytropos
> import Polytropos.Aeson
>
> -- A genuinely heterogeneous record mixing String, Int, and Bool:
> type Config = Record '["host" ':= String, "port" ':= Int, "active" ':= Bool]
>
> cfg :: Config
> cfg = REC { host = "localhost", port = 8080, active = True }
>
> -- Encodes to JSON: {"active":true,"host":"localhost","port":8080}
> jsonBytes = encode cfg
>
> -- Decodes back to Config:
> Just cfg' = decode @Config jsonBytes

Variants with heterogeneous constructors serialize into single-member tagged objects:

> type Response = Variant '["Ok" ':= '["body" ':= String, "status" ':= Int], "Err" ':= '["reason" ':= String]]
>
> resp :: Response
> resp = VAR { Ok = REC { body = "server ready", status = 200 } }
>
> -- Encodes to JSON: {"Ok":{"body":"server ready","status":200}}
> respBytes = encode resp
-}
module Polytropos.Aeson
  ( -- * Heterogeneous Row Codecs
    AllToJSON (..)
  , AllFromJSON (..)
  , AllCtorsToJSON (..)
  , AllCtorsFromJSON (..)

    -- * Homogeneity Evidence and Row Introspection
    -- $homogeneity
  , AllFieldsAre
  , AllCtorsHom (..)
  , FieldNames (..)
  , RowField
  , SumField
  ) where

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
  Heterogeneous row constraint walks
-------------------------------------------------------------------------------}

-- | Evidence that every field of the row @r@ has a 'A.ToJSON' instance
-- at that field's own type. Serializes the erased payload slots in row order.
class AllToJSON (r :: Row) where
  encRecordFields :: Proxy r -> [Identity Any] -> [(K.Key, A.Value)]

instance AllToJSON '[] where
  encRecordFields _ _ = []

instance (KnownSymbol n, A.ToJSON a, AllToJSON r) => AllToJSON ((n ':= a) ': r) where
  encRecordFields _ (Identity x : xs) =
    (K.fromText (T.pack (symbolVal (Proxy @n))), A.toJSON (noInlineUnsafeCo x :: a))
    : encRecordFields (Proxy @r) xs
  encRecordFields _ [] = error "polytropos-aeson: payload arity mismatch"

-- | Evidence that every field of the row @r@ has a 'A.FromJSON' instance
-- at that field's own type. Decodes each field by name from the JSON object.
class AllFromJSON (r :: Row) where
  decRecordFields :: Proxy r -> A.Object -> AT.Parser [Identity Any]

instance AllFromJSON '[] where
  decRecordFields _ _ = pure []

instance (KnownSymbol n, A.FromJSON a, AllFromJSON r) => AllFromJSON ((n ':= a) ': r) where
  decRecordFields _ obj = do
    v <- obj A..: K.fromText (T.pack (symbolVal (Proxy @n))) :: AT.Parser a
    vs <- decRecordFields (Proxy @r) obj
    pure (Identity (noInlineUnsafeCo v :: Any) : vs)

-- | Evidence that every constructor of the sum row @s@ has a heterogeneous
-- field row satisfying 'AllToJSON', paired with its constructor tag index.
class AllCtorsToJSON (s :: SumRow) where
  encVariantTag :: Proxy s -> Word -> [Identity Any] -> A.Value

instance AllCtorsToJSON '[] where
  encVariantTag _ _ _ = error "polytropos-aeson: empty variant has no constructors"

instance (KnownSymbol c, AllToJSON fs, AllCtorsToJSON s)
      => AllCtorsToJSON ((c ':= fs) ': s) where
  encVariantTag _ 0 slots =
    let cName = symbolVal (Proxy @c)
        fields = KM.fromList (encRecordFields (Proxy @fs) slots)
    in A.Object (KM.singleton (K.fromText (T.pack cName)) (A.Object fields))
  encVariantTag _ tag slots =
    encVariantTag (Proxy @s) (tag - 1) slots

-- | Evidence that every constructor of the sum row @s@ has a heterogeneous
-- field row satisfying 'AllFromJSON', paired with its constructor tag index.
class AllCtorsFromJSON (s :: SumRow) where
  decVariantVal :: Proxy s -> Word -> T.Text -> A.Value -> AT.Parser (Word, [Identity Any])

instance AllCtorsFromJSON '[] where
  decVariantVal _ _ _ _ = fail "polytropos-aeson: unknown constructor"

instance (KnownSymbol c, AllFromJSON fs, AllCtorsFromJSON s)
      => AllCtorsFromJSON ((c ':= fs) ': s) where
  decVariantVal _ idx cKey val
    | cKey == T.pack (symbolVal (Proxy @c)) = case val of
        A.Object o -> do
          slots <- decRecordFields (Proxy @fs) o
          pure (idx, slots)
        _ -> fail "polytropos-aeson: expected an object of constructor fields"
    | otherwise =
        decVariantVal (Proxy @s) (idx + 1) cKey val

{-------------------------------------------------------------------------------
  Record codecs
-------------------------------------------------------------------------------}

instance AllToJSON r => A.ToJSON (Record r) where
  toJSON (RowRep rep) =
    A.Object (KM.fromList (encRecordFields (Proxy @r) (toList (repVals rep))))
  toJSONList xs = AT.listValue A.toJSON xs
  toEncoding (RowRep rep) =
    A.toEncoding (A.Object (KM.fromList (encRecordFields (Proxy @r) (toList (repVals rep)))))
  toEncodingList xs = AT.listEncoding A.toEncoding xs
  omitField _ = False

instance AllFromJSON r => A.FromJSON (Record r) where
  parseJSON = A.withObject "Record" $ \obj -> do
    vs <- decRecordFields (Proxy @r) obj
    pure (RowRep (productRep vs))
  parseJSONList v = case v of
    AT.Array vals -> traverse (A.withObject "Record" (\o -> RowRep . productRep <$> decRecordFields (Proxy @r) o)) (toList vals)
    _             -> fail "polytropos-aeson: expected an array of records"
  omittedField = Nothing

{-------------------------------------------------------------------------------
  Variant codecs
-------------------------------------------------------------------------------}

instance AllCtorsToJSON s => A.ToJSON (Variant s) where
  toJSON (RowRep rep) = encVariantTag (Proxy @s) (repTag rep) (toList (repVals rep))
  toJSONList xs = AT.listValue A.toJSON xs
  toEncoding v = A.toEncoding (A.toJSON v)
  toEncodingList xs = AT.listEncoding A.toEncoding xs
  omitField _ = False

instance AllCtorsFromJSON s => A.FromJSON (Variant s) where
  parseJSON = A.withObject "Variant" $ \obj ->
    case KM.toList obj of
      [(k, v)] -> do
        (idx, slots) <- decVariantVal (Proxy @s) 0 (K.toText k) v
        pure (RowRep (injectRep (fromIntegral idx) slots))
      _ -> fail "polytropos-aeson: expected a single-member object"
  parseJSONList v = case v of
    AT.Array vals -> traverse (A.withObject "Variant" $ \obj ->
      case KM.toList obj of
        [(k, val)] -> do
          (idx, slots) <- decVariantVal (Proxy @s) 0 (K.toText k) val
          pure (RowRep (injectRep (fromIntegral idx) slots))
        _ -> fail "polytropos-aeson: expected a single-member object") (toList vals)
    _             -> fail "polytropos-aeson: expected an array of variants"
  omittedField = Nothing

{-------------------------------------------------------------------------------
  Homogeneity evidence and row introspection (Reflection helpers)
-------------------------------------------------------------------------------}

-- $homogeneity
--
-- === Homogeneity Evidence and Introspection Helpers
--
-- In addition to the primary heterogeneous codecs ('AllToJSON', 'AllFromJSON'),
-- this module provides closed type families and reflection classes for
-- inspecting row metadata and enforcing uniform payload types.
--
-- 1. 'AllFieldsAre' is a closed type family asserting that /every/ field in a row
--    has the uniform type @a@.
-- 2. 'RowField' and 'SumField' compute the uniform payload type directly from
--    the row or sum row, eliminating type ambiguity for custom instances.
-- 3. 'FieldNames' reifies type-level 'GHC.TypeLits.Symbol' field labels into
--    runtime @['String']@ keys in exact row order.
-- 4. 'AllCtorsHom' reifies the constructor topology of a homogeneous sum row into
--    @[(String, [String])]@ (mapping each constructor name to its list of field names).

-- | Evidence that every field of the row @r@ has type @a@.
type family AllFieldsAre (a :: Type) (r :: Row) :: Constraint where
  AllFieldsAre _  '[]                = ()
  AllFieldsAre a ((n ':= a) ': rest) = AllFieldsAre a rest

-- | Extracts the uniform field type of a homogeneous row: the type of /every/
-- field, or 'Void' for the empty row @'[]@.
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
class AllCtorsHom (a :: Type) (s :: SumRow) where
  ctorSpecs :: Proxy a -> Proxy s -> [(String, [String])]

instance AllCtorsHom a '[] where
  ctorSpecs _ _ = []

instance ( KnownSymbol c, FieldNames fs, AllFieldsAre a fs, AllCtorsHom a s )
      => AllCtorsHom a ((c ':= fs) ': s) where
  ctorSpecs pa _ =
    (symbolVal (Proxy @c), fieldNames (Proxy @fs)) : ctorSpecs pa (Proxy @s)
