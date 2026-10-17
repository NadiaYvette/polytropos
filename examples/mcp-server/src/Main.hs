{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

-- | Worked Tutorial Capstone: Federated Context & Memory MCP Server.
--
-- This executable demonstrates:
--   1. Schema definition for tool inputs using open product rows.
--   2. Sum-of-tools representation as an open variant.
--   3. Automatic OpenAPI 3.0 input schema synthesis via 'recordToTool'.
--   4. Type-safe argument validation and deserialization with 'toolCallToVariant'.
--   5. O(1) jump table dispatch using 'eliminateUniform'.
--   6. Token-budget-aware result compression using 'projectRecord'.
--   7. Standard Model Context Protocol (MCP) JSON-RPC 2.0 server lifecycle.
--
-- Running:
--   $ cabal run example-mcp-server
-- Or for stdio MCP JSON-RPC protocol mode:
--   $ cabal run example-mcp-server -- --stdio
module Main (main) where

import Data.Aeson (Value, encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as LBSC
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Environment (getArgs)

import Polytropos
import Polytropos.MCP

{-------------------------------------------------------------------------------
  1. Tool Argument Schemas as Open Rows
-------------------------------------------------------------------------------}

-- | Arguments for searching Contextful's SQLite FTS5 index.
type SearchArgs =
  '[ "query"     ':= Text
   , "workspace" ':= Text
   , "budget"    ':= Int
   ]

-- | Arguments for recalling memories from Kioku's PostgreSQL event store.
type RecallArgs =
  '[ "scope"     ':= Text
   , "claim"     ':= Text
   ]

-- | Sum row of all registered MCP tools.
type ServerToolsRow =
  '[ "contextful_search" ':= SearchArgs
   , "kioku_recall"      ':= RecallArgs
   ]

type ServerTools = Variant ServerToolsRow

{-------------------------------------------------------------------------------
  2. Search Result Views & Token-Budget Compression
-------------------------------------------------------------------------------}

-- | Full search result with extensive metadata.
type FullResultRow =
  '[ "title"     ':= Text
   , "path"      ':= Text
   , "snippet"   ':= Text
   , "score"     ':= Double
   , "workspace" ':= Text
   ]

-- | Compact search view (sub-row of FullResultRow).
-- Slices away verbose scoring and workspace metadata to fit tight token budgets.
type CompactResultRow =
  '[ "title"     ':= Text
   , "path"      ':= Text
   , "snippet"   ':= Text
   ]

{-------------------------------------------------------------------------------
  3. Tool Registration & Jump-Table Handler
-------------------------------------------------------------------------------}

serverInfo :: ServerInfo
serverInfo = ServerInfo "polytropos-federated-mcp" "0.1.0"

serverTools :: [McpTool]
serverTools =
  [ recordToTool @"contextful_search"
      "Search Contextful codebase FTS5 index across chunks and symbols"
      (Proxy @SearchArgs)
  , recordToTool @"kioku_recall"
      "Recall agent memory and knowledge claims from Kioku PostgreSQL event store"
      (Proxy @RecallArgs)
  ]

-- | O(1) jump table dispatch using 'eliminateUniform'.
-- Notice how each tool handler receives its strongly-typed open record directly.
serverHandler :: ServerTools -> IO [McpContent]
serverHandler = eliminateUniform REC
  { contextful_search = \args -> do
      let rawResult :: Record FullResultRow
          rawResult = REC
            { title     = "Plugin Architecture Invariants"
            , path      = "docs/notes/POLYTROPOS_DESIGN.md"
            , snippet   = "Decisions D1-D10 collapse the four-quadrant design space into Rep."
            , score     = 0.982
            , workspace = args.workspace
            }

      -- Token-budget compression: if budget < 100 tokens, project to CompactResultRow!
      if (args.budget :: Int) < 100
        then do
          let compact :: Record CompactResultRow
              compact = projectRecord rawResult
          pure [TextContent $
            "[COMPACT SEARCH] " <> compact.title <> " (" <> compact.path <> "): " <> compact.snippet]
        else do
          pure [TextContent $
            "[FULL SEARCH (score " <> T.pack (show (rawResult.score :: Double)) <> ")] "
            <> rawResult.title <> " in " <> rawResult.workspace <> " [" <> rawResult.path <> "]: "
            <> rawResult.snippet]

  , kioku_recall = \args -> do
      pure [TextContent $
        "[KIOKU MEMORY] Recall from scope '" <> args.scope <> "': Verified claim regarding '"
        <> args.claim <> "' in event log."]
  }

dispatcher :: Text -> Value -> IO CallToolResult
dispatcher = dispatchToolCall @ServerToolsRow serverHandler

{-------------------------------------------------------------------------------
  4. Execution Modes
-------------------------------------------------------------------------------}

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--stdio"] -> runStdioServer serverInfo serverTools dispatcher
    _           -> runInteractiveDemo

runInteractiveDemo :: IO ()
runInteractiveDemo = do
  TIO.putStrLn "============================================================"
  TIO.putStrLn " Addendum E: Federated Context & Memory MCP Server Capstone"
  TIO.putStrLn "============================================================"
  TIO.putStrLn ""

  -- 1. Tool Metadata Discovery
  TIO.putStrLn "--- 1. Auto-Generated OpenAPI Schemas (tools/list) ---"
  mapM_ (\t -> do
    TIO.putStrLn $ "Tool: " <> toolName t <> " -- " <> toolDescription t
    putStr "  Schema: "
    LBSC.putStrLn (encode (toolInputSchema t))
    ) serverTools
  TIO.putStrLn ""

  -- 2. Dispatching tool call with generous token budget
  TIO.putStrLn "--- 2. Call contextful_search (Token Budget: 500) ---"
  let searchArgsGenerous = object
        [ "query"     .= ("design invariants" :: Text)
        , "workspace" .= ("polytropos" :: Text)
        , "budget"    .= (500 :: Int)
        ]
  resGenerous <- dispatcher "contextful_search" searchArgsGenerous
  case callToolContent resGenerous of
    [TextContent txt] -> TIO.putStrLn txt
    _                 -> TIO.putStrLn "Unexpected response content"
  TIO.putStrLn ""

  -- 3. Dispatching tool call with tight token budget (demonstrates projectRecord)
  TIO.putStrLn "--- 3. Call contextful_search (Token Budget: 50 -> triggers sub-row compression) ---"
  let searchArgsTight = object
        [ "query"     .= ("design invariants" :: Text)
        , "workspace" .= ("polytropos" :: Text)
        , "budget"    .= (50 :: Int)
        ]
  resTight <- dispatcher "contextful_search" searchArgsTight
  case callToolContent resTight of
    [TextContent txt] -> TIO.putStrLn txt
    _                 -> TIO.putStrLn "Unexpected response content"
  TIO.putStrLn ""

  -- 4. Dispatching kioku_recall
  TIO.putStrLn "--- 4. Call kioku_recall (Postgres agent memory recall) ---"
  let recallArgs = object
        [ "scope" .= ("architecture" :: Text)
        , "claim" .= ("row-role-invariants" :: Text)
        ]
  resRecall <- dispatcher "kioku_recall" recallArgs
  case callToolContent resRecall of
    [TextContent txt] -> TIO.putStrLn txt
    _                 -> TIO.putStrLn "Unexpected response content"
  TIO.putStrLn ""

  -- 5. Standard MCP JSON-RPC protocol round-trip simulation
  TIO.putStrLn "--- 5. JSON-RPC 2.0 Protocol Envelope Roundtrip ---"
  let rpcReq = encode $ object
        [ "jsonrpc" .= ("2.0" :: Text)
        , "id"      .= (42 :: Int)
        , "method"  .= ("tools/call" :: Text)
        , "params"  .= object
            [ "name"      .= ("kioku_recall" :: Text)
            , "arguments" .= object
                [ "scope" .= ("rfc-2822" :: Text)
                , "claim" .= ("commit-attribution" :: Text)
                ]
            ]
        ]
  mRpcResp <- handleJsonRpcMessage serverInfo serverTools dispatcher rpcReq
  case mRpcResp of
    Nothing       -> TIO.putStrLn "No response generated"
    Just respLBS  -> do
      putStrLn "JSON-RPC Response:"
      LBSC.putStrLn respLBS

  TIO.putStrLn ""
  TIO.putStrLn "MCP server capstone demonstration completed cleanly!"
