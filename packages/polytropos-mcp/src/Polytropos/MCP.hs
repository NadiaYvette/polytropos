{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{-|
Module      : Polytropos.MCP
Description : Model Context Protocol (MCP) server integration for Polytropos
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC extensions)

Model Context Protocol (MCP) tool integration and JSON-RPC dispatch for
@polytropos@ open records and variants.

= Architectural Overview & Rationale

== The MCP Schema Problem
In standard Model Context Protocol server implementations, defining tools requires
tedious manual duplication:
1. Declaring a nominal parameter data type.
2. Deriving or writing an OpenAPI / JSON Schema definition.
3. Writing a parser that inspects the tool name string and runs the appropriate decoder.
4. Writing an error-prone dispatcher branch that invokes the handler.

== The Polytropos Solution
@polytropos-mcp@ collapses this entire pipeline into row types:
* __Tool Schemas:__ A tool's parameters are just an open record row type @r@.
  'recordToTool' reifies @r@ into an OpenAPI schema directly via 'Polytropos.OpenApi'.
* __Tool Call Variant:__ The entire suite of registered tools forms an open sum
  variant @Variant s@, where constructor tags match tool names and constructor
  payloads match parameter rows.
* __\(O(1)\) Dispatch:__ Tool calls are parsed into @Variant s@ and dispatched
  using 'Polytropos.eliminateUniform', compiling to an indirect function call
  jump table without string comparisons or branch cascades.
* __Dynamic Extensibility:__ New tools can be added to the server by simply widening
  the variant with 'Polytropos.widenVariant'.

= When to Use This Module

* When exposing @polytropos@ data pipelines, compilers, or database query engines
  to AI coding assistants (such as Claude, Gemini, or custom agent frameworks)
  via the standard Model Context Protocol.

= Worked Example

> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE OverloadedRecordDot #-}
> {-# LANGUAGE TypeApplications #-}
>
> import Data.Proxy (Proxy (..))
> import Data.Text (Text)
> import Polytropos
> import Polytropos.MCP
>
> -- 1. Define parameter rows for tools:
> type SearchArgs = '["query" ':= Text, "limit" ':= Int]
> type EchoArgs   = '["message" ':= Text]
>
> -- 2. Define the tool registry as an open variant:
> type MyTools = Variant
>   '[ "search" ':= SearchArgs
>    , "echo"   := EchoArgs
>    ]
>
> -- 3. Generate tool manifests with OpenAPI schemas:
> toolList :: [McpTool]
> toolList =
>   [ recordToTool @"search" "Search indexed documents" (Proxy @SearchArgs)
>   , recordToTool @"echo"   "Echo back a message"      (Proxy @EchoArgs)
>   ]
>
> -- 4. Dispatch tool calls using O(1) jump tables:
> handleCall :: MyTools -> IO [McpContent]
> handleCall = eliminateUniform REC
>   { search = \args -> pure [TextContent ("Found hits for: " <> args.query)]
>   , echo   = \args -> pure [TextContent ("Echo: " <> args.message)]
>   }
-}
module Polytropos.MCP
  ( -- * MCP Protocol Data Types
    JsonRpcRequest (..)
  , JsonRpcResponse (..)
  , JsonRpcError (..)
  , McpTool (..)
  , CallToolParams (..)
  , CallToolResult (..)
  , McpContent (..)
  , ServerInfo (..)
  , ServerCapabilities (..)
  , InitializeResult (..)

    -- * Tool Schema Synthesis
  , recordToTool

    -- * Tool Call Parsing & Dispatch
  , toolCallToVariant
  , dispatchToolCall
  , handleJsonRpcMessage
  , runStdioServer
  ) where

import Control.Exception (SomeException, try)
import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , Value (..)
  , eitherDecode
  , encode
  , fromJSON
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.=)
  )
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Char8 as BSC8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBC8
import Data.OpenApi (toSchema)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import System.IO (hFlush, isEOF, stdin, stdout)

import Polytropos (Record, Variant)
import Polytropos.Aeson (AllCtorsFromJSON)
import Polytropos.OpenApi (AllToSchema)

{-------------------------------------------------------------------------------
  MCP Protocol Types
-------------------------------------------------------------------------------}

-- | A JSON-RPC 2.0 request or notification envelope.
data JsonRpcRequest = JsonRpcRequest
  { jsonrpcReqVersion :: !Text
  , jsonrpcReqMethod  :: !Text
  , jsonrpcReqId      :: !(Maybe Value)
  , jsonrpcReqParams  :: !(Maybe Value)
  } deriving (Show, Eq, Generic)

instance FromJSON JsonRpcRequest where
  parseJSON = withObject "JsonRpcRequest" $ \o ->
    JsonRpcRequest
      <$> o .: "jsonrpc"
      <*> o .: "method"
      <*> o .:? "id"
      <*> o .:? "params"

-- | A JSON-RPC 2.0 response envelope.
data JsonRpcResponse = JsonRpcResponse
  { jsonrpcRespVersion :: !Text
  , jsonrpcRespId      :: !(Maybe Value)
  , jsonrpcRespResult  :: !(Maybe Value)
  , jsonrpcRespError   :: !(Maybe JsonRpcError)
  } deriving (Show, Eq, Generic)

instance ToJSON JsonRpcResponse where
  toJSON (JsonRpcResponse v i res err) =
    object $ [ "jsonrpc" .= v, "id" .= i ]
      ++ maybe [] (\r -> ["result" .= r]) res
      ++ maybe [] (\e -> ["error" .= e]) err

instance FromJSON JsonRpcResponse where
  parseJSON = withObject "JsonRpcResponse" $ \o ->
    JsonRpcResponse
      <$> o .: "jsonrpc"
      <*> o .:? "id"
      <*> o .:? "result"
      <*> o .:? "error"

-- | A JSON-RPC 2.0 protocol error object.
data JsonRpcError = JsonRpcError
  { jsonrpcErrorCode    :: !Int
  , jsonrpcErrorMessage :: !Text
  , jsonrpcErrorData    :: !(Maybe Value)
  } deriving (Show, Eq, Generic)

instance ToJSON JsonRpcError where
  toJSON (JsonRpcError c m d) =
    object $ [ "code" .= c, "message" .= m ]
      ++ maybe [] (\x -> ["data" .= x]) d

instance FromJSON JsonRpcError where
  parseJSON = withObject "JsonRpcError" $ \o ->
    JsonRpcError
      <$> o .: "code"
      <*> o .: "message"
      <*> o .:? "data"

-- | An MCP content item returned by a tool execution.
data McpContent
  = TextContent !Text
  | ImageContent !Text !Text  -- ^ base64 data, mimeType
  | ResourceContent !Text !(Maybe Text) -- ^ uri, optional text
  deriving (Show, Eq, Generic)

instance ToJSON McpContent where
  toJSON (TextContent txt) =
    object [ "type" .= ("text" :: Text), "text" .= txt ]
  toJSON (ImageContent d m) =
    object [ "type" .= ("image" :: Text), "data" .= d, "mimeType" .= m ]
  toJSON (ResourceContent u mt) =
    object $ [ "type" .= ("resource" :: Text), "uri" .= u ]
      ++ maybe [] (\t -> ["text" .= t]) mt

instance FromJSON McpContent where
  parseJSON = withObject "McpContent" $ \o -> do
    t <- o .: "type"
    case (t :: Text) of
      "text"     -> TextContent <$> o .: "text"
      "image"    -> ImageContent <$> o .: "data" <*> o .: "mimeType"
      "resource" -> ResourceContent <$> o .: "uri" <*> o .:? "text"
      _          -> fail ("unknown McpContent type: " ++ T.unpack t)

-- | Result of an MCP @tools/call@ execution.
data CallToolResult = CallToolResult
  { callToolContent :: ![McpContent]
  , callToolIsError :: !(Maybe Bool)
  } deriving (Show, Eq, Generic)

instance ToJSON CallToolResult where
  toJSON (CallToolResult c e) =
    object $ [ "content" .= c ]
      ++ maybe [] (\b -> ["isError" .= b]) e

instance FromJSON CallToolResult where
  parseJSON = withObject "CallToolResult" $ \o ->
    CallToolResult
      <$> o .: "content"
      <*> o .:? "isError"

-- | Parameters passed in an MCP @tools/call@ request.
data CallToolParams = CallToolParams
  { callToolName      :: !Text
  , callToolArguments :: !(Maybe Value)
  } deriving (Show, Eq, Generic)

instance FromJSON CallToolParams where
  parseJSON = withObject "CallToolParams" $ \o ->
    CallToolParams
      <$> o .: "name"
      <*> o .:? "arguments"

-- | An MCP Tool specification describing a callable tool.
data McpTool = McpTool
  { toolName        :: !Text
  , toolDescription :: !Text
  , toolInputSchema :: !Value
  } deriving (Show, Eq, Generic)

instance ToJSON McpTool where
  toJSON (McpTool n d s) =
    object [ "name" .= n, "description" .= d, "inputSchema" .= s ]

instance FromJSON McpTool where
  parseJSON = withObject "McpTool" $ \o ->
    McpTool
      <$> o .: "name"
      <*> o .: "description"
      <*> o .: "inputSchema"

-- | Server information reported during the @initialize@ handshake.
data ServerInfo = ServerInfo
  { serverName    :: !Text
  , serverVersion :: !Text
  } deriving (Show, Eq, Generic)

instance ToJSON ServerInfo where
  toJSON (ServerInfo n v) =
    object [ "name" .= n, "version" .= v ]

-- | Server capabilities announced during initialization.
data ServerCapabilities = ServerCapabilities
  { capTools :: !(Maybe Value)
  } deriving (Show, Eq, Generic)

instance ToJSON ServerCapabilities where
  toJSON (ServerCapabilities t) =
    object $ maybe [] (\x -> ["tools" .= x]) t

-- | The payload returned to the client upon a successful @initialize@ handshake.
data InitializeResult = InitializeResult
  { initProtocolVersion :: !Text
  , initCapabilities    :: !ServerCapabilities
  , initServerInfo      :: !ServerInfo
  } deriving (Show, Eq, Generic)

instance ToJSON InitializeResult where
  toJSON (InitializeResult p c s) =
    object
      [ "protocolVersion" .= p
      , "capabilities"    .= c
      , "serverInfo"      .= s
      ]

{-------------------------------------------------------------------------------
  Tool Schema Synthesis
-------------------------------------------------------------------------------}

-- | Synthesizes an MCP @t'McpTool'@ definition from an open record row type @r@.
-- The tool's parameter schema is generated via 'Polytropos.OpenApi.toSchema'.
recordToTool
  :: forall (name :: Symbol) r.
     (KnownSymbol name, Typeable r, AllToSchema r)
  => Text                -- ^ Human-readable tool description
  -> Proxy r             -- ^ Parameter row proxy
  -> McpTool
recordToTool desc _ =
  McpTool
    { toolName        = T.pack (symbolVal (Proxy @name))
    , toolDescription = desc
    , toolInputSchema = toJSON (toSchema (Proxy @(Record r)))
    }

{-------------------------------------------------------------------------------
  Tool Call Parsing & Dispatch
-------------------------------------------------------------------------------}

-- | Parses tool call arguments into a Polytropos 'Variant' sum row @s@.
-- Constructs a tagged singleton object @{"toolName": arguments}@ and decodes
-- via 'Polytropos.Aeson.AllCtorsFromJSON'.
toolCallToVariant
  :: forall s. (AllCtorsFromJSON s)
  => Text               -- ^ Invoked tool name
  -> Value              -- ^ JSON argument object
  -> Either String (Variant s)
toolCallToVariant tName args =
  let taggedObj = Object (KM.singleton (Key.fromText tName) args)
  in case fromJSON taggedObj of
       Aeson.Success v -> Right v
       Aeson.Error err -> Left ("Invalid arguments for tool '" <> T.unpack tName <> "': " <> err)

-- | Dispatches a tool execution request by decoding into @Variant s@ and
-- invoking the provided handler (typically constructed via 'Polytropos.eliminateUniform').
dispatchToolCall
  :: forall s. (AllCtorsFromJSON s)
  => (Variant s -> IO [McpContent])
  -> Text
  -> Value
  -> IO CallToolResult
dispatchToolCall handler tName args =
  case toolCallToVariant @s tName args of
    Left parseErr ->
      pure CallToolResult
        { callToolContent = [TextContent (T.pack parseErr)]
        , callToolIsError = Just True
        }
    Right variantVal -> do
      res <- try (handler variantVal)
      case res of
        Left (ex :: SomeException) ->
          pure CallToolResult
            { callToolContent = [TextContent ("Tool execution failed: " <> T.pack (show ex))]
            , callToolIsError = Just True
            }
        Right contents ->
          pure CallToolResult
            { callToolContent = contents
            , callToolIsError = Nothing
            }

-- | Handles a single incoming JSON-RPC raw message line, producing a response
-- (or 'Nothing' for notifications that expect no reply).
handleJsonRpcMessage
  :: ServerInfo
  -> [McpTool]
  -> (Text -> Value -> IO CallToolResult)
  -> LBS.ByteString
  -> IO (Maybe LBS.ByteString)
handleJsonRpcMessage sInfo tools toolDispatcher rawMsg =
  case eitherDecode rawMsg of
    Left parseErr ->
      pure $ Just $ encode $ JsonRpcResponse
        { jsonrpcRespVersion = "2.0"
        , jsonrpcRespId      = Nothing
        , jsonrpcRespResult  = Nothing
        , jsonrpcRespError   = Just $ JsonRpcError (-32700) ("Parse error: " <> T.pack parseErr) Nothing
        }
    Right (JsonRpcRequest _ "initialize" reqId _) ->
      pure $ Just $ encode $ JsonRpcResponse
        { jsonrpcRespVersion = "2.0"
        , jsonrpcRespId      = reqId
        , jsonrpcRespResult  = Just $ toJSON $ InitializeResult
            { initProtocolVersion = "2024-11-05"
            , initCapabilities    = ServerCapabilities (Just (object ["listChanged" .= False]))
            , initServerInfo      = sInfo
            }
        , jsonrpcRespError   = Nothing
        }
    Right (JsonRpcRequest _ "notifications/initialized" _ _) ->
      pure Nothing
    Right (JsonRpcRequest _ "ping" reqId _) ->
      pure $ Just $ encode $ JsonRpcResponse
        { jsonrpcRespVersion = "2.0"
        , jsonrpcRespId      = reqId
        , jsonrpcRespResult  = Just (object [])
        , jsonrpcRespError   = Nothing
        }
    Right (JsonRpcRequest _ "tools/list" reqId _) ->
      pure $ Just $ encode $ JsonRpcResponse
        { jsonrpcRespVersion = "2.0"
        , jsonrpcRespId      = reqId
        , jsonrpcRespResult  = Just $ object [ "tools" .= tools ]
        , jsonrpcRespError   = Nothing
        }
    Right (JsonRpcRequest _ "tools/call" reqId mParams) -> do
      case mParams of
        Just pVal ->
          case fromJSON pVal of
            Aeson.Success (CallToolParams tName mArgs) -> do
              let args = maybe (Object KM.empty) id mArgs
              res <- toolDispatcher tName args
              pure $ Just $ encode $ JsonRpcResponse
                { jsonrpcRespVersion = "2.0"
                , jsonrpcRespId      = reqId
                , jsonrpcRespResult  = Just (toJSON res)
                , jsonrpcRespError   = Nothing
                }
            Aeson.Error err ->
              pure $ Just $ encode $ JsonRpcResponse
                { jsonrpcRespVersion = "2.0"
                , jsonrpcRespId      = reqId
                , jsonrpcRespResult  = Nothing
                , jsonrpcRespError   = Just $ JsonRpcError (-32602) ("Invalid params: " <> T.pack err) Nothing
                }
        Nothing ->
          pure $ Just $ encode $ JsonRpcResponse
            { jsonrpcRespVersion = "2.0"
            , jsonrpcRespId      = reqId
            , jsonrpcRespResult  = Nothing
            , jsonrpcRespError   = Just $ JsonRpcError (-32602) "Missing params for tools/call" Nothing
            }
    Right (JsonRpcRequest _ method reqId _) ->
      pure $ Just $ encode $ JsonRpcResponse
        { jsonrpcRespVersion = "2.0"
        , jsonrpcRespId      = reqId
        , jsonrpcRespResult  = Nothing
        , jsonrpcRespError   = Just $ JsonRpcError (-32601) ("Method not found: " <> method) Nothing
        }

-- | Runs an MCP server over standard input/output using newline-delimited JSON-RPC messages.
runStdioServer
  :: ServerInfo
  -> [McpTool]
  -> (Text -> Value -> IO CallToolResult)
  -> IO ()
runStdioServer sInfo tools toolDispatcher = loop
  where
    loop = do
      done <- isEOF
      if done
        then pure ()
        else do
          raw <- BSC8.hGetLine stdin
          let line = LBS.fromStrict raw
          if LBS.null line
            then loop
            else do
              mResp <- handleJsonRpcMessage sInfo tools toolDispatcher line
              case mResp of
                Just resp -> do
                  LBC8.putStrLn resp
                  hFlush stdout
                Nothing -> pure ()
              loop
