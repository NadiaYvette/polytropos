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
-- This plugin is a skeleton that compiles and loads. The constraint-solving
-- logic is stubbed out. Full implementation requires more work on the GHC 9.14
-- typechecker plugin API.
module Polytropos.Plugin (plugin) where

import GHC.Plugins

import Polytropos.Core

-- | The plugin entry point.
plugin :: Plugin
plugin = defaultPlugin
  { tcPlugin = \_args -> Just $ TcPlugin
      { tcPluginInit  = return ()
      , tcPluginSolve  = \_ _ _ -> pure TcPluginOk
      , tcPluginRewrite = const emptyUFM
      , tcPluginStop   = \_ -> return ()
      }
  , pluginRecompile = purePlugin
  }

-- | Empty UniqFM for the rewrite field.
emptyUFM :: UniqFM TyCon TcPluginRewriter
emptyUFM = nilUFM

-- | Stub: the TcPlugin type from GHC.Driver.Plugins.
type TcPlugin = [CommandLineOption] -> Maybe TcPlugin

-- | Stub: the TcPluginM type.
type TcPluginM a = IO a

-- | Stub: the TcPluginSolver type.
type TcPluginSolver = IO ()

-- | Stub: the TcPluginSolveResult type.
data TcPluginSolveResult = TcPluginOk [(EvTerm, Ct)] [Ct]

-- | Stub: the EvTerm type.
data EvTerm

-- | Stub: the Ct type.
data Ct

-- | Stub: the TyCon type.
data TyCon

-- | Stub: the TcPluginRewriter type.
type TcPluginRewriter = IO ()
