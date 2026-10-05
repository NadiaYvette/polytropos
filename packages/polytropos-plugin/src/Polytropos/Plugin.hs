{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}

-- | GHC typechecker plugin for @polytropos@.
--
-- Solves the evidence-class constraints (@'FieldIndex'@, @'ConstructorIndex'@,
-- @'RowEq'@, @'RowShow'@, @'RowEqSum'@, @'RowShowSum'@) by inspecting the row
-- carried in a @'RowRep'@'s type and emitting literal slot indices, tags, and
-- comparison bodies — the same technique @large-anon@ uses for
-- @DictRowHasField@.
--
-- Load with @ghc-options: -fplugin=Polytropos.Plugin@ in the consuming
-- package's .cabal file.
--
-- == Current status
--
-- This plugin is a skeleton that compiles and loads but does not yet solve any
-- constraints. The constraint-solving logic will be added once we have the
-- correct GHC 9.14 API imports.
module Polytropos.Plugin (plugin) where

import GHC.Plugins

import Polytropos.Core

-- | The plugin entry point.
plugin :: Plugin
plugin = defaultPlugin
  { tcPlugin = \args -> Just $ TcPlugin
      { tcPluginInit  = return ()
      , tcPluginSolve = \_ _ _ -> pure $ TcPluginSolveResult [] [] []
      , tcPluginStop  = \_ -> return ()
      }
  , pluginRecompile = purePlugin
  }

-- | Trace a message from the plugin.
tracePlugin :: String -> TcPluginM ()
tracePlugin msg = tcPluginTrace "polytropos-plugin" (text msg)
