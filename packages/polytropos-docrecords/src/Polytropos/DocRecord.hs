{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- |
-- Module      : Polytropos.DocRecord
-- Description : Self-documenting extensible records with provenance tracking and CLI synthesis
-- Copyright   : (c) 2026 Nadia Yvette Chambers
-- License     : EUPL-1.2 OR Apache-2.0
-- Maintainer  : nadia.yvette.chambers@ik.me
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--
-- Self-documenting extensible configuration records for the 'Polytropos' open record ecosystem.
--
-- = Precedents & Attribution
-- This package is an architectural reimplementation inspired by Yves Parès's pioneering
-- @docrecords@ package from the <https://github.com/funflow/porcupine porcupine> workflow library.
-- Where the original @docrecords@ used Vinyl linked lists ('Data.Vinyl.Core.Rec') with
-- \(O(N)\) inductive dictionary resolution, @polytropos-docrecords@ rebuilds these capabilities
-- directly on top of Polytropos's high-performance flat contiguous array representation
-- ('Polytropos.Core.Rep') and compile-time dictionary synthesis ('Polytropos.Plugin').
--
-- = Key Architecture
-- 1. 'DocRec': Extensible documented record ('RecordF DocItem r') stored in contiguous memory.
-- 2. 'PossiblyEmpty': Tri-state value semantics distinguishing unconfigured defaults from missing values.
-- 3. 'SourceTag': Strict priority provenance tracking (@CLI > YAML > Default@).
-- 4. 'showDocumentation': Automated generation of formatted Markdown schema tables.
-- 5. 'fromJSONAs' & 'fromYamlAs': Schema-guided JSON/YAML deserialization with source attribution.
-- 6. 'parseRecFromCLI': Zero-boilerplate @optparse-applicative@ CLI option synthesis.
--
-- = When to Use This Module
--
-- * When building configuration layers combining default values, environment
--   profiles (JSON/YAML), and CLI flags with deterministic priority precedence.
-- * When generating automated, human-readable Markdown documentation tables of
--   configuration schemas for manuals or repository documentation.
-- * When synthesizing @optparse-applicative@ CLI argument parsers directly from
--   open row definitions without manual flag boilerplate.
--
-- = Worked Example
--
-- Constructing a documented configuration record, extracting documentation,
-- and merging with partial JSON:
--
-- > {-# LANGUAGE DataKinds #-}
-- > {-# LANGUAGE OverloadedRecordDot #-}
-- > {-# LANGUAGE OverloadedStrings #-}
-- > {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
-- >
-- > import Data.Aeson (object, (.=))
-- > import Polytropos
-- > import Polytropos.DocRecord
-- >
-- > type ServerConfig =
-- >   '[ "host"    ':= String
-- >    , "port"    ':= Int
-- >    , "verbose" ':= Bool
-- >    ]
-- >
-- > defaultConfig :: DocRec ServerConfig
-- > defaultConfig =
-- >   consDoc (Field @"host") (docField "127.0.0.1" "Listening host IP")
-- >     $ consDoc (Field @"port") (docField (8080 :: Int) "TCP listen port")
-- >     $ consDoc (Field @"verbose") (docField False "Enable debug logs")
-- >     $ emptyDocRec
-- >
-- > -- 1. Render Markdown documentation table:
-- > docTable = showDocumentation defaultConfig
-- >
-- > -- 2. Merge partial JSON configuration (e.g. from a config file):
-- > Right cfg = case fromJSONAs defaultConfig (object ["port" .= (9090 :: Int)]) of
-- >   Data.Aeson.Success c -> Right c
-- >   Data.Aeson.Error e   -> Left e
-- >
-- > -- 3. Inspect values and provenance using OverloadedRecordDot:
-- > currentPort = getDocVal cfg.port       -- Just 9090
-- > portSource  = diSource cfg.port        -- YamlSource
-- > currentHost = getDocVal cfg.host       -- Just "127.0.0.1"
-- > hostSource  = diSource cfg.host        -- DefaultSource
module Polytropos.DocRecord
  ( -- * Core Documented Record Types
    DocRec
  , DocItem(..)
  , PossiblyEmpty(.., Present, Missing)
  , MissingValueReason(..)
  , SourceTag(..)

    -- * Field Constructors & Utilities
  , docField
  , fieldNoDef
  , docItemWithSource
  , getDocVal
  , requireDocVal
  , emptyDocRec
  , consDoc

    -- * Schema Inspection & Markdown Documentation
  , DocFieldEntry(..)
  , DocSchema(..)
  , showDocumentation
  , schemaMarkdownTable

    -- * JSON / YAML Parsing with Provenance
  , DocJsonMerge(..)
  , fromJSONAs
  , fromYamlAs

    -- * Priority Merging
  , DocMerge(..)

    -- * CLI Synthesis via Optparse-Applicative
  , CliField(..)
  , CliRecord(..)
  , execDocRecParser
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), Result(..), fromJSON)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import Data.Kind (Type)
import Data.Primitive.SmallArray (indexSmallArray)
import Data.Proxy (Proxy(..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Y
import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import GHC.Exts (toList)
import Options.Applicative hiding (Success)
import Polytropos.Core (Pair(..), RowRep(..), Rep(..), productRep, repVals)
import Polytropos (RecordF, emptyRecordF, Field(..))
import Type.Reflection (Typeable, typeRep)
import Unsafe.Coerce (unsafeCoerce)

--------------------------------------------------------------------------------
-- 1. Core Documented Record Types
--------------------------------------------------------------------------------

-- | Explains why a configuration field currently holds no value.
data MissingValueReason
  = NoDefault
  -- ^ Field was declared without a default value ('fieldNoDef').
  | MissingValueInJSON
  -- ^ Field was expected during JSON/YAML parsing but was absent from the payload.
  | MissingValueInCLI
  -- ^ Field was expected from the CLI options but was omitted.
  deriving (Show, Eq, Ord)

-- | Wraps a value to represent tri-state configuration existence:
-- 1. A present value ('Present').
-- 2. An empty field with an explicit missing reason ('Missing').
newtype PossiblyEmpty a = PE { unPE :: Either MissingValueReason a }
  deriving (Functor, Eq, Ord)

pattern Present :: a -> PossiblyEmpty a
pattern Present x = PE (Right x)

pattern Missing :: MissingValueReason -> PossiblyEmpty a
pattern Missing r = PE (Left r)

{-# COMPLETE Present, Missing #-}

instance Applicative PossiblyEmpty where
  pure = Present
  PE (Right f) <*> PE (Right x) = PE (Right (f x))
  PE (Left r)  <*> _            = PE (Left r)
  _            <*> PE (Left r)  = PE (Left r)

instance Semigroup a => Semigroup (PossiblyEmpty a) where
  PE (Right a) <> PE (Right b) = PE (Right (a <> b))
  PE (Right a) <> PE (Left _)  = PE (Right a)
  PE (Left _)  <> PE (Right b) = PE (Right b)
  PE (Left a)  <> PE (Left b)  = PE (Left (max a b))

instance Semigroup a => Monoid (PossiblyEmpty a) where
  mempty = PE (Left NoDefault)

instance Show a => Show (PossiblyEmpty a) where
  show (PE (Right x)) = show x
  show (PE (Left r))  = "(empty: " ++ show r ++ ")"

instance ToJSON a => ToJSON (PossiblyEmpty a) where
  toJSON (PE (Right x)) = toJSON x
  toJSON (PE (Left _))  = Null

instance FromJSON a => FromJSON (PossiblyEmpty a) where
  parseJSON Null = pure (PE (Left MissingValueInJSON))
  parseJSON v    = Present <$> parseJSON v

-- | Provenance tracking for configuration values.
--
-- The 'Ord' instance enforces strict configuration precedence:
-- @DefaultSource < YamlSource < CliSource@.
-- Command line arguments always override configuration files, which override in-code defaults.
data SourceTag
  = DefaultSource
  -- ^ In-code fallback default.
  | YamlSource
  -- ^ Sourced from a YAML/JSON configuration file.
  | CliSource
  -- ^ Sourced from a command-line flag or argument.
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | A self-documenting field payload wrapper for higher-kinded records.
data DocItem a = DocItem
  { diValue  :: !(PossiblyEmpty a)
  -- ^ The optional or defaulted payload value.
  , diDoc    :: !Text
  -- ^ Human-readable documentation for this field.
  , diSource :: !SourceTag
  -- ^ The provenance source of the current value.
  } deriving (Show, Eq, Functor)

instance ToJSON a => ToJSON (DocItem a) where
  toJSON di = toJSON (diValue di)

-- | An open, self-documenting record parametrised by row @r@.
-- Backed by Polytropos's $O(1)$ contiguous 'Polytropos.Core.Rep' array.
type DocRec r = RecordF DocItem r

--------------------------------------------------------------------------------
-- 2. Field Constructors & Utilities
--------------------------------------------------------------------------------

-- | Construct a documented field with an initial default value and 'DefaultSource'.
docField :: a -> Text -> DocItem a
docField val doc = DocItem (Present val) doc DefaultSource

-- | Construct an unconfigured documented field with no default value.
fieldNoDef :: Text -> DocItem a
fieldNoDef doc = DocItem (Missing NoDefault) doc DefaultSource

-- | Construct a documented field with explicit source provenance.
docItemWithSource :: SourceTag -> PossiblyEmpty a -> Text -> DocItem a
docItemWithSource src val doc = DocItem val doc src

-- | Extract the present value of a documented field, if set.
getDocVal :: DocItem a -> Maybe a
getDocVal (DocItem (Present x) _ _) = Just x
getDocVal _                        = Nothing

-- | Require a documented field to be present, returning an error message if missing.
requireDocVal :: Text -> DocItem a -> Either Text a
requireDocVal _ (DocItem (Present x) _ _) = Right x
requireDocVal fieldName (DocItem (Missing r) doc _) =
  Left $ "Configuration field '" <> fieldName <> "' is missing (" <> T.pack (show r) <> "). " <> doc

-- | Empty documented record.
emptyDocRec :: DocRec '[]
emptyDocRec = emptyRecordF

-- | Prepend a documented field to a documented record.
consDoc :: forall (n :: Symbol) a r. Field n -> DocItem a -> DocRec r -> DocRec ((n ':= a) ': r)
consDoc _ val (RowRep r) =
  RowRep (productRep (unsafeCoerce val : toList (repVals r)))

--------------------------------------------------------------------------------
-- 3. Schema Inspection & Markdown Documentation
--------------------------------------------------------------------------------

-- | Metadata entry describing a single record field.
data DocFieldEntry = DocFieldEntry
  { dfeName        :: !Text
  -- ^ The type-level field symbol.
  , dfeType        :: !Text
  -- ^ Human-readable name of the Haskell payload type.
  , dfeDoc         :: !Text
  -- ^ Field documentation string.
  , dfeDefaultText :: !(Maybe Text)
  -- ^ Rendered default value representation, if present.
  , dfeCurrentSrc  :: !SourceTag
  -- ^ Provenance source of the active value.
  } deriving (Show, Eq)

-- | Inductive class to reflect field metadata across a documented row.
class DocSchema (r :: [Pair Symbol Type]) where
  docSchemaEntries :: DocRec r -> [DocFieldEntry]

instance DocSchema '[] where
  docSchemaEntries _ = []

-- | Deconstruct the first documented field and remaining tail from a 'DocRec'.
splitDocHead :: forall n a rest. DocRec ((n ':= a) ': rest) -> (DocItem a, DocRec rest)
splitDocHead (RowRep (Rep _ v)) =
  let h = unsafeCoerce (indexSmallArray v 0) :: DocItem a
      restVals = drop 1 (toList v)
  in (h, RowRep (productRep restVals))

instance (KnownSymbol n, Typeable a, Show a, DocSchema rest)
      => DocSchema ((n ':= a) ': rest) where
  docSchemaEntries rec =
    let name = T.pack (symbolVal (Proxy @n))
        tyName = T.pack (show (typeRep @a))
        (firstVal, restRec) = splitDocHead rec
        entry = DocFieldEntry
          { dfeName        = name
          , dfeType        = tyName
          , dfeDoc         = diDoc firstVal
          , dfeDefaultText = case diValue firstVal of
              Present x -> Just (T.pack (show x))
              Missing _ -> Nothing
          , dfeCurrentSrc  = diSource firstVal
          }
    in entry : docSchemaEntries restRec

-- | Render a documented record's schema into a formatted Markdown table.
showDocumentation :: forall r. DocSchema r => DocRec r -> Text
showDocumentation rec = schemaMarkdownTable (docSchemaEntries rec)

-- | Render a list of field entries into a GitHub-flavored Markdown table.
schemaMarkdownTable :: [DocFieldEntry] -> Text
schemaMarkdownTable entries =
  T.unlines $
    [ "| Field | Type | Default | Source | Description |"
    , "|:---|:---|:---|:---|:---|"
    ] ++ map formatRow entries
  where
    formatRow e =
      "| `" <> dfeName e <> "` | `" <> dfeType e <> "` | "
      <> maybe "*none*" (\d -> "`" <> d <> "`") (dfeDefaultText e) <> " | "
      <> T.pack (show (dfeCurrentSrc e)) <> " | "
      <> dfeDoc e <> " |"

--------------------------------------------------------------------------------
-- 4. JSON / YAML Parsing with Provenance
--------------------------------------------------------------------------------

-- | Typeclass for schema-guided JSON/YAML deserialization into a 'DocRec'.
class DocJsonMerge (r :: [Pair Symbol Type]) where
  mergeFromJsonValue :: DocRec r -> Value -> Result (DocRec r)

instance DocJsonMerge '[] where
  mergeFromJsonValue _ _ = pure emptyDocRec

instance (KnownSymbol n, FromJSON a, DocJsonMerge rest)
      => DocJsonMerge ((n ':= a) ': rest) where
  mergeFromJsonValue rec val = do
    let name = symbolVal (Proxy @n)
        k = Key.fromString name
        (itemHead, restRec) = splitDocHead rec
    updatedHead <- case val of
      Object obj -> case KM.lookup k obj of
        Just fieldVal -> do
          parsed <- fromJSON fieldVal
          pure $ DocItem (Present parsed) (diDoc itemHead) YamlSource
        Nothing ->
          -- Field missing in JSON: preserve default if present, else mark missing
          case diValue itemHead of
            Present _ -> pure itemHead
            Missing _ -> pure $ DocItem (Missing MissingValueInJSON) (diDoc itemHead) (diSource itemHead)
      _ -> pure itemHead
    updatedRest <- mergeFromJsonValue restRec val
    pure (consDoc (Field @n) updatedHead updatedRest)

-- | Deserialize JSON into a 'DocRec' guided by an initial default schema.
-- Fields present in the JSON are updated and marked with 'YamlSource'.
fromJSONAs :: DocJsonMerge r => DocRec r -> Value -> Result (DocRec r)
fromJSONAs = mergeFromJsonValue

-- | Parse YAML byte content into a 'DocRec' guided by an initial default schema.
fromYamlAs :: DocJsonMerge r => DocRec r -> BS.ByteString -> Either Y.ParseException (DocRec r)
fromYamlAs schema bs = do
  val <- Y.decodeEither' bs
  case fromJSONAs schema val of
    Success r -> Right r
    Error err -> Left (Y.AesonException err)

--------------------------------------------------------------------------------
-- 5. Priority Merging (CLI > YAML > Default)
--------------------------------------------------------------------------------

-- | Inductive class to merge two documented records field-by-field, choosing
-- the value with highest 'SourceTag' priority.
class DocMerge (r :: [Pair Symbol Type]) where
  mergeDocRec :: DocRec r -> DocRec r -> DocRec r

instance DocMerge '[] where
  mergeDocRec _ _ = emptyDocRec

instance (KnownSymbol n, DocMerge rest) => DocMerge ((n ':= a) ': rest) where
  mergeDocRec r1 r2 =
    let (h1, t1) = splitDocHead r1
        (h2, t2) = splitDocHead r2
        winner = if diSource h1 >= diSource h2 then h1 else h2
        mergedRest = mergeDocRec t1 t2
    in consDoc (Field @n) winner mergedRest

--------------------------------------------------------------------------------
-- 6. CLI Option Parser Synthesis via Optparse-Applicative
--------------------------------------------------------------------------------

-- | Defines how a field type is parsed from command-line arguments.
class CliField a where
  cliOptionModifier :: String -> Text -> PossiblyEmpty a -> Parser (PossiblyEmpty a)

instance {-# OVERLAPPING #-} CliField Bool where
  cliOptionModifier name doc defVal =
    let opt = switch (long name <> help (T.unpack doc))
    in fmap toVal opt
    where
      toVal True = Present True
      toVal False = defVal

instance {-# OVERLAPPABLE #-} (Read a, Show a) => CliField a where
  cliOptionModifier name doc defVal =
    let docWithDef = case defVal of
          Present x -> doc <> " (default: " <> T.pack (show x) <> ")"
          Missing _ -> doc
        p = option auto (long name <> help (T.unpack docWithDef))
    in fmap Present p <|> pure defVal

-- | Automatically synthesizes an @optparse-applicative@ 'Parser' for a 'DocRec'.
class CliRecord (r :: [Pair Symbol Type]) where
  parseRecFromCLI :: DocRec r -> Parser (DocRec r)

instance CliRecord '[] where
  parseRecFromCLI _ = pure emptyDocRec

instance (KnownSymbol n, Eq a, CliField a, CliRecord rest)
      => CliRecord ((n ':= a) ': rest) where
  parseRecFromCLI rec =
    let name = symbolVal (Proxy @n)
        (itemHead, restRec) = splitDocHead rec
        cliParser = cliOptionModifier @a name (diDoc itemHead) (diValue itemHead)
        makeItem val =
          let src = if val /= diValue itemHead then CliSource else diSource itemHead
          in DocItem val (diDoc itemHead) src
        headParser = fmap makeItem cliParser
        restParser = parseRecFromCLI restRec
    in consDoc (Field @n) <$> headParser <*> restParser

-- | Helper to run an synthesized CLI parser with standard header and help.
execDocRecParser :: CliRecord r => Text -> DocRec r -> IO (DocRec r)
execDocRecParser desc schema =
  execParser (info (parseRecFromCLI schema <**> helper) (fullDesc <> progDesc (T.unpack desc)))

