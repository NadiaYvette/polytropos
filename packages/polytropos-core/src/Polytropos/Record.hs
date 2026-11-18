{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RoleAnnotations #-}

-- |
-- Module      : Polytropos.Record
-- Description : Reified Record wrapper and Skew Boolean re-exports
module Polytropos.Record
  ( Record
  , RecordF
  , RowRep(..)
  , emptyRecord
  , emptyRecordF
  , (//>)
  , (<//)
  , (<+>)
  , (//~)
  , (|<)
  , (/-/)
  , (\^/)
  ) where

import Polytropos (Record, RecordF, emptyRecord, emptyRecordF)
import Polytropos.Core (RowRep(..))
import Polytropos.MergeMorph
