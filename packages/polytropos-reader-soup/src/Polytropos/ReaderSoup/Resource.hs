{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- |
-- Module      : Polytropos.ReaderSoup.Resource
-- Description : ResourceT integration for Polytropos ReaderSoup
-- Copyright   : (c) 2026, Nadia Yvette Chambers
-- License     : EUPL-1.2 OR Apache-2.0
-- Maintainer  : nadia.yvette.chambers@ik.me
-- Stability   : experimental
--
-- Provides turnkey 'ResourceT' integration for 'Polytropos.ReaderSoup.ReaderSoup',
-- connecting @resourcet@'s 'InternalState' to the @"resource"@ labeled context in the
-- soup.
--
-- Applications can simply add @("resource" ':= InternalState)@ to their soup context row
-- to automatically gain 'MonadResource' instances, enabling safe deterministic acquisition
-- and release of sockets, database handles, and file descriptors.
module Polytropos.ReaderSoup.Resource
  ( ContextFromName
  , useResource
  ) where

import Control.Monad.IO.Unlift (MonadUnliftIO)
import Control.Monad.Trans.Reader (ReaderT(..))
import Control.Monad.Trans.Resource
  ( InternalState
  , MonadResource(..)
  , ResourceT
  , runInternalState
  , runResourceT
  , withInternalState
  )
import Polytropos.Core (Field(..), FieldIndex)
import Polytropos.ReaderSoup

-- | Associates the @"resource"@ label with @resourcet@'s 'InternalState'.
type instance ContextFromName "resource" = InternalState

-- | Bridges 'ResourceT' with 'ReaderSoup' via 'InternalState'.
instance SoupContext InternalState ResourceT where
  toReaderT act = ReaderT $ runInternalState act
  fromReaderT (ReaderT act) = withInternalState act

-- | Canonical 'ContextRunner' for 'ResourceT', executing acquired resources safely.
useResource :: MonadUnliftIO m => ContextRunner ResourceT m
useResource = ContextRunner runResourceT

-- | Equips any 'ReaderSoup' carrying @"resource"@ with 'MonadResource'.
instance (FieldIndex "resource" ctxs InternalState)
      => MonadResource (ReaderSoup ctxs) where
  liftResourceT act = picking (Field @"resource") act
