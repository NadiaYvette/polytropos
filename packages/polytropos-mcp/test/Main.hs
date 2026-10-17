{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Aeson (Value (..), decode, eitherDecode, encode, object, (.=))
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Data.Text as T

import Polytropos
import Polytropos.MCP

-- Define test tool argument schemas
type SearchArgs = '["query" ':= Text, "limit" ':= Int]
type EchoArgs   = '["message" ':= Text]

-- Tool sum row and variant
type TestToolsRow =
  '[ "search" ':= SearchArgs
   , "echo"   := EchoArgs
   ]

type TestTools = Variant TestToolsRow

testTools :: [McpTool]
testTools =
  [ recordToTool @"search" "Search documents" (Proxy @SearchArgs)
  , recordToTool @"echo"   "Echo back message" (Proxy @EchoArgs)
  ]

serverInfo :: ServerInfo
serverInfo = ServerInfo "polytropos-mcp-test" "0.1.0"

testHandler :: TestTools -> IO [McpContent]
testHandler = eliminateUniform REC
  { search = \args -> pure [TextContent ("results for: " <> args.query <> " (limit=" <> T.pack (show args.limit) <> ")")]
  , echo   = \args -> pure [TextContent ("echo: " <> args.message)]
  }

dispatcher :: Text -> Value -> IO CallToolResult
dispatcher = dispatchToolCall @TestToolsRow testHandler

main :: IO ()
main = defaultMain $ testGroup "Polytropos.MCP Tests"
  [ testCase "recordToTool synthesizes name and schema" $ do
      case testTools of
        (t : _) -> do
          toolName t @?= "search"
          toolDescription t @?= "Search documents"
          case toolInputSchema t of
            Object _ -> pure ()
            _        -> assertFailure "expected Object schema"
        [] -> assertFailure "empty testTools"

  , testCase "toolCallToVariant parses valid arguments" $ do
      let args = object [ "query" .= ("haskell" :: Text), "limit" .= (10 :: Int) ]
      case toolCallToVariant @TestToolsRow "search" args of
        Right (VAR { search = r }) -> do
          r.query @?= "haskell"
          r.limit @?= (10 :: Int)
        Right _ -> assertFailure "unexpected variant branch"
        Left err -> assertFailure ("parse error: " ++ err)

  , testCase "dispatchToolCall executes search tool" $ do
      let args = object [ "query" .= ("rows" :: Text), "limit" .= (5 :: Int) ]
      res <- dispatcher "search" args
      callToolIsError res @?= Nothing
      case callToolContent res of
        [TextContent txt] -> txt @?= "results for: rows (limit=5)"
        _                 -> assertFailure "unexpected content"

  , testCase "dispatchToolCall executes echo tool" $ do
      let args = object [ "message" .= ("hello world" :: Text) ]
      res <- dispatcher "echo" args
      callToolIsError res @?= Nothing
      case callToolContent res of
        [TextContent txt] -> txt @?= "echo: hello world"
        _                 -> assertFailure "unexpected content"

  , testCase "dispatchToolCall reports error on invalid tool" $ do
      let args = object [ "foo" .= ("bar" :: Text) ]
      res <- dispatcher "unknown_tool" args
      callToolIsError res @?= Just True

  , testCase "handleJsonRpcMessage responds to initialize" $ do
      let req = encode $ object
            [ "jsonrpc" .= ("2.0" :: Text)
            , "id"      .= (1 :: Int)
            , "method"  .= ("initialize" :: Text)
            ]
      mResp <- handleJsonRpcMessage serverInfo testTools dispatcher req
      case mResp of
        Just respBytes -> do
          case decode respBytes of
            Just (JsonRpcResponse "2.0" (Just (Number 1)) (Just resVal) Nothing) ->
              case resVal of
                Object _ -> pure ()
                _        -> assertFailure "expected Object result"
            _ -> assertFailure "unexpected response envelope"
        Nothing -> assertFailure "expected response"

  , testCase "handleJsonRpcMessage responds to tools/list" $ do
      let req = encode $ object
            [ "jsonrpc" .= ("2.0" :: Text)
            , "id"      .= (2 :: Int)
            , "method"  .= ("tools/list" :: Text)
            ]
      mResp <- handleJsonRpcMessage serverInfo testTools dispatcher req
      case mResp of
        Just respBytes -> do
          case decode respBytes of
            Just (JsonRpcResponse "2.0" (Just (Number 2)) (Just resVal) Nothing) ->
              case resVal of
                Object _ -> pure ()
                _        -> assertFailure "expected Object result"
            _ -> assertFailure "unexpected response envelope"
        Nothing -> assertFailure "expected response"

  , testCase "handleJsonRpcMessage executes tools/call over JSON-RPC" $ do
      let req = encode $ object
            [ "jsonrpc" .= ("2.0" :: Text)
            , "id"      .= (3 :: Int)
            , "method"  .= ("tools/call" :: Text)
            , "params"  .= object
                [ "name"      .= ("echo" :: Text)
                , "arguments" .= object [ "message" .= ("ping" :: Text) ]
                ]
            ]
      mResp <- handleJsonRpcMessage serverInfo testTools dispatcher req
      case mResp of
        Just respBytes -> do
          case eitherDecode respBytes of
            Right (JsonRpcResponse "2.0" (Just (Number 3)) (Just resVal) Nothing) -> do
              case decode (encode resVal) of
                Just (CallToolResult [TextContent "echo: ping"] Nothing) -> pure ()
                _ -> assertFailure ("unexpected tool result: " ++ show resVal)
            Right other -> assertFailure ("unexpected response: " ++ show other)
            Left err -> assertFailure ("failed decoding response: " ++ err)
        Nothing -> assertFailure "expected response"
  ]
