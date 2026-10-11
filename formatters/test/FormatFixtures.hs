{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}

{-|
Module      : FormatFixtures
Description : Formatter test fixtures asserting AST-preserving row formatting
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : BSD-3-Clause

This module exercises row type declarations, record dot access, variant
dispatch, and constructor peeling to assert idempotence and syntax preservation
across Fourmolu, Ormolu, Brittany, and Floskell.
-}
module FormatFixtures (
    UserRow
  , User
  , StatusVariant
  , formatUser
  , bumpId
  , mkUser
  , testPeel
  ) where

import Polytropos

-- | Type-level row list with leading commas and column alignment
type UserRow =
  '[ "id" := Int
   , "name" := String
   , "email" := String
   , "active" := Bool
   ]

-- | Open record type synonym
type User = Record UserRow

-- | Open variant coproduct type
type StatusVariant =
  Variant
    '[ "pending" ':= '["code" ':= Int]
     , "active" ':= '["token" ':= String]
     , "completed" ':= '["flag" ':= Bool]
     ]

-- | Formatted record dot projection
formatUser :: User -> String
formatUser u = u.name ++ " <" ++ u.email ++ ">"

-- | Type-safe field update
bumpId :: User -> User
bumpId u = setField (Field @"id") (recordField (Field @"id") u + 1) u

-- | Record construction pipeline
mkUser :: Int -> String -> String -> Bool -> User
mkUser uid uname uemail uact =
  insertField (Field @"id") uid
    . insertField (Field @"name") uname
    . insertField (Field @"email") uemail
    . insertField (Field @"active") uact
    $ emptyRecord

-- | Variant peeling combinator
testPeel
  :: StatusVariant
  -> Either
       (Variant '[ "active" ':= '["token" ':= String], "completed" ':= '["flag" ':= Bool] ])
       (Record '["code" ':= Int])
testPeel = peel @"pending"
