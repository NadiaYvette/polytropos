{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- |
-- Module      : Polytropos.OpenApi
-- Description : OpenAPI 3.0 schema generation for polytropos records and variants
-- Copyright   : (c) 2026 The Polytropos Authors
-- License     : EUPL-1.2 OR Apache-2.0
--
-- Generates OpenAPI 3.0 schema specifications directly from @polytropos@
-- open records and variants.
--
-- = Shape
--
-- A record declares an anonymous object schema whose @properties@ carry one
-- entry per field (reified from the row symbols) and whose @required@ list
-- contains every field: a row-typed record is total, so all fields are
-- required. A variant declares an anonymous @oneOf@ schema with one entry
-- per constructor, each a single-member tagged object @{"ctor": fields}@ —
-- the same wire shape the 'Polytropos.Aeson' satellite uses, so a REST API
-- documented by these schemas round-trips through those codecs.
--
-- = Why not Generic
--
-- The standard @ToSchema@ deriving walks a GHC.Generics tree; on large
-- schema objects (50+ fields) that tree is what explodes compile times.
-- Here the schema is assembled by walking the row type — one 'Declare'
-- step per field — with no generic representation anywhere. Field types
-- may differ across the row ('AllToSchema' collects a schema per field);
-- constructors may differ across the sum ('AllCtorsToSchema').
module Polytropos.OpenApi
  ( -- * Row schema walkers
    AllToSchema (..)
  , AllCtorsToSchema (..)
  ) where

import Control.Lens ((&), (.~), (?~))
import Data.Proxy            (Proxy (..))
import Data.Typeable         (Typeable)
import Data.Text             (Text)
import qualified Data.Text as T
import GHC.TypeLits          (KnownSymbol, symbolVal)
import Data.OpenApi
import Data.OpenApi.Declare (Declare)
import qualified Data.HashMap.Strict.InsOrd.Compat as IOHM
import Polytropos            (Record, Variant)
import Polytropos.Core       (Pair (..), Row, SumRow)

{-------------------------------------------------------------------------------
  Row schema walkers
-------------------------------------------------------------------------------}

-- | One property entry per field of the row, in row order.
class AllToSchema (r :: Row) where
  fieldSchemas :: Proxy r -> Declare (Definitions Schema) [(Text, Referenced Schema)]

instance AllToSchema '[] where
  fieldSchemas _ = pure []

instance (KnownSymbol n, ToSchema a, AllToSchema r)
      => AllToSchema ((n ':= a) ': r) where
  fieldSchemas _ = do
    s  <- declareSchemaRef (Proxy @a)
    ss <- fieldSchemas (Proxy @r)
    pure ((T.pack (symbolVal (Proxy @n)), s) : ss)

-- | One tagged object schema per constructor of the sum row.
class AllCtorsToSchema (s :: SumRow) where
  ctorSchemas :: Proxy s -> Declare (Definitions Schema) [Schema]

instance AllCtorsToSchema '[] where
  ctorSchemas _ = pure []

instance (KnownSymbol c, AllToSchema fs, AllCtorsToSchema s)
      => AllCtorsToSchema ((c ':= fs) ': s) where
  ctorSchemas _ = do
    fields <- fieldSchemas (Proxy @fs)
    let fieldsObj = mempty
          & type_ ?~ OpenApiObject
          & properties .~ IOHM.fromList fields
          & required .~ map fst fields
        tagged = mempty
          & type_ ?~ OpenApiObject
          & properties .~ IOHM.fromList [(T.pack (symbolVal (Proxy @c)), Inline fieldsObj)]
          & required .~ [T.pack (symbolVal (Proxy @c))]
    (tagged :) <$> ctorSchemas (Proxy @s)

{-------------------------------------------------------------------------------
  Instances
-------------------------------------------------------------------------------}

instance (Typeable r, AllToSchema r) => ToSchema (Record r) where
  declareNamedSchema _ = do
    fields <- fieldSchemas (Proxy @r)
    pure $ NamedSchema Nothing $ mempty
      & type_ ?~ OpenApiObject
      & properties .~ IOHM.fromList fields
      & required .~ map fst fields

instance (Typeable s, AllCtorsToSchema s) => ToSchema (Variant s) where
  declareNamedSchema _ = do
    ctors <- ctorSchemas (Proxy @s)
    pure $ NamedSchema Nothing $ mempty
      & oneOf ?~ map Inline ctors
