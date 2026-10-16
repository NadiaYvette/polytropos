{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE ViewPatterns #-}

{-|
Module      : Polytropos.Plugin
Description : GHC typechecker plugin synthesizing literal row evidence for Polytropos
Copyright   : (c) 2026 The Polytropos Authors
License     : EUPL-1.2 OR Apache-2.0
Maintainer  : nadia.yvette.chambers@ik.me
Stability   : experimental
Portability : non-portable (GHC Typechecker Plugin API)

GHC typechecker plugin for @polytropos@.

This plugin is the operational heart of the @polytropos@ compile-time engine.
It inspects the row types carried in @RowRep@ and synthesizes literal evidence
dictionaries directly into GHC Core during typechecking.

= Architectural Overview & Rationale

== Zero Type-Level Search at Runtime

In conventional type-level row libraries, projecting a field from a record
requires an inductive type-level search (e.g. via @KnownNat@ or recursive class instances)
that produces \(O(N)\) or \(O(N^2)\) Core dictionary trees and compiles to pointer-chasing
loops.

@polytropos-plugin@ eliminates this entire cost:
1. It intercepts wanted constraints for the evidence classes:
   * @FieldIndex@: computes the zero-based literal slot index for a field symbol
   * @ConstructorIndex@: computes the zero-based constructor tag for a variant symbol
   * @RowEq@ and @RowEqSum@: synthesizes unrolled structural equality checks
   * @RowShow@ and @RowShowSum@: synthesizes string formatting routines
   * @AllFields@: synthesizes literal vectors of dictionary witnesses ('Data.Primitive.SmallArray.SmallArray')
2. It solves these constraints immediately by emitting literal Core expressions with
   exact numeric literals (e.g. @0#@, @1#@, @2#@).
3. The resulting code compiles to direct array indexing into contiguous memory with
   zero intermediate allocations.

= How to Use This Plugin

In your consuming project's @.cabal@ file, add @polytropos-plugin@ to @build-depends@
and enable the plugin via @ghc-options@:

@
library
  build-depends:
      base >= 4.18
    , polytropos-core
    , polytropos-plugin
  ghc-options:
    -fplugin=Polytropos.Plugin
@

= Worked Example

Once the plugin is enabled in your @.cabal@ file, field projections and constructor
injections work seamlessly without manual instance declarations:

@
import Polytropos

-- The plugin computes literal index 0 for "name" and 1 for "age"
type User = Record '["name" ':= String, "age" ':= Int]

mkUser :: String -> Int -> User
mkUser n a = insertField (Field \@"name") n
           $ insertField (Field \@"age")  a
           $ emptyRecord

-- Reading fields is compiled to direct O(1) array index lookup:
userName :: User -> String
userName = getField (Field \@"name")
@
-}
module Polytropos.Plugin
  ( -- * GHC Plugin Entry Point
    plugin
  ) where

import Prelude

import Data.Either
  ( partitionEithers
  )

import Data.List
  ( intercalate
  , sortOn
#if !MIN_VERSION_base(4,20,0)
  , foldl'
#endif
  )

import Data.Bits
  ( xor
  )

import Data.Char
  ( ord
  )

import Data.Word
  ( Word64
  )

import Control.Monad
  ( forM
  , zipWithM
  )

import GHC.Core.DataCon
  ( promoteDataCon
  )

import GHC.Core.Make
  ( mkCoreApps
  , mkCoreConApps
  , mkCoreLams
  , mkCharExpr
  , mkStringExpr
  , mkIfThenElse
  , mkListExpr
  )

import GHC.Plugins
  ( Plugin (..)
  , defaultPlugin
  , tcPlugin
  , CoreExpr
  , Expr(..)
  , Type
  , mkTcOcc
  , nameOccName
  , mkTyConTy
  , mkTyConApp
  , splitTyConApp_maybe
  , isStrLitTy
  , mkStrLitTy
  , intDataCon
  , wordDataCon
  , FastString
  , unpackFS
  , Literal(..)
  , LitNumType(..)
  , wordTyCon
  , Var(..)
  , varType
  , intTy
  , stringTy
  , mkVarOcc
  , Module
  , mkModuleName
  , coreView
  , splitFunTy
  , splitFunTys
  , splitForAllTyCoVars
  , piResultTys
  , typeKind
  , mkTyVarTy
  , mkAppTy
  , getOccName
  , occNameString
  , fsLit
  , nullFS
  , nilFS
  , TyCon
  , showSDocUnsafe
  , ppr
  , isEmptyVarSet
  , tyCoVarsOfType
  )

import GHC.Core.Class
  ( classMethods
  , classTyCon
  )

import GHC.Core.Multiplicity
  ( scaledThing
  , scaledMult
  )

import GHC.Core.TyCo.Compare
  ( eqType
  )

import GHC.Builtin.Types
  ( trueDataCon
  , falseDataCon
  , maybeTyCon
  , nothingDataCon
  , justDataCon
  , unitTyCon
  , unitDataCon
  , constraintKind
  , typeSymbolKind
  , liftedTypeKind
  , mkPromotedPairTy
  , mkPromotedListTy
  , mkTupleTy
  )

import Language.Haskell.Syntax.Basic
  ( Boxity(..)
  )

import GHC.Builtin.Names
  ( gHC_CLASSES
  , eqClassName
  , showClassName
  , errorMessageTypeErrorFamName
  , typeErrorTextDataConName
  , typeErrorVAppendDataConName
  )

import Polytropos.Plugin.Compat
  ( modBase
  , modShow
  , modRecords
  )

import GHC.TcPlugin.API
  ( TcPlugin (..)
  , TcPluginSolveResult(..)
  , TcPluginM
  , classifyPredType
  , Pred(..)
  , ctPred
  , ctEvidence
  , isWanted
  , className
  , EvTerm (..)
  , Ct
  , CtLoc
  , TcPluginStage(..)
  , mkTcPlugin
  , listToUFM
  , UniqFM
  , lookupOrig
  , tcLookupId
  , tcLookupTyCon
  , tcLookupDataCon
  , findImportedModule
  , resolveImport
  , FindResult(..)
  , Class
  , classDataCon
  , tcLookupClass
  , evDataConApp
  , newName
  , mkLocalId
  , newWanted
  , ctEvExpr
  , mkNonCanonical
  , ctLoc
  , Role(..)
  , TcPluginRewriteResult(..)
  , mkTyFamAppReduction
  )

import GHC.TcPlugin.API.Internal
  ( unsafeLiftTcM
  , TcPluginRewriter
  )

import Polytropos.Plugin.Source
  ( sourcePlugin
  )

{-
================================================================================
                                GHC NOTES ARCHITECTURE
================================================================================

This module follows GHC's commentary convention:
  https://gitlab.haskell.org/ghc/ghc/-/wikis/commentary/coding-style#2-using-notes

Complex design decisions, theoretical invariants, and row algebra concepts are
explained in self-contained Notes below. Specific solver and rewrite sites in the
code carry cross-references (e.g. "-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]").

Notes defined in this module:
  * Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
  * Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
  * Note [SubRow and SubSum Projection and Narrowing Evidence] [ref:note-subrow-subsum]
  * Note [Type-Level Metadata Rewriting and Defunctionalization] [ref:note-metadata-rewriting]
  * Note [Human-Centric TypeError Diagnostics & Fuzzy Matching] [ref:note-typeerror-diagnostics]
  * Note [OCaml Subtype/Unify Correlation and Row Tail Algebra] [ref:note-ocaml-row-algebra]

External Canonical Design References:
  * docs/notes/POLYTROPOS_DESIGN.md (decisions D1–D10, open questions)
  * docs/notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md (Rémy row calculus & OCaml tails)
  * docs/notes/ROW_ROLE_DEFNS_DRAFT.ott & REVIEWER_WFU_ARGUMENT.md
  * plans/2026-10-09-plugin-gap-roadmap.md & 2026-10-09-plugin-gap-spec.md
================================================================================
-}

{- Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [tag:note-row-anatomy]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
In Didier Rémy's row calculus (and in OCaml's polymorphic variants / object types),
a row type is not merely a static list of fields; it is a structural sequence with
a tail:

    Row ::= '[]                       -- Closed empty row (Tnil in OCaml)
          | (label ':= ty) ': tail    -- Cons cell (Tfield in OCaml)
          | rho                       -- Row variable (Tvar in OCaml)

In Haskell's type system (via DataKinds and TypeOperators), we encode rows as
promoted type-level lists of pairs: `'[ "x" ':= Int, "y" ':= Bool]`.

1. Open vs. Closed Rows:
   - A *closed row* is one that syntactically terminates with `'[]`. Its complete
     field complement and exact arity N are known statically.
   - An *open row* is one whose tail is an uninstantiated type variable `rho`
     (e.g., `( "x" ':= Int ) ': rho`). The row is open because further type
     inference may discover additional fields that unify with `rho`.

2. Fixed vs. Unfixed Tails:
   Following OCaml's subtype/unification algebra (see docs/notes/OCAML_ROW_TAIL_SUBTYPE_MECHANISM.md):
   - An *unfixed tail* is a flexible unification variable (a meta-tyvar) that has
     not yet been pinned down. It can accept fresh fields through unification.
   - A *fixed tail* is a tail that cannot accept further fields without contradiction:
     either it is closed (`'[]`), or it is a universally quantified skolem tyvar,
     or it is an abstract/existential row constructor (`Tconstr`).

3. Solver Implications in Polytropos.Plugin:
   When `Polytropos.Plugin` solves evidence classes:
   - Single-field queries (`FieldIndex "x" r a`, `HasField "x" r a`): If `"x"` occurs
     in the known prefix of an open row, its slot offset from the head is fixed,
     so we can solve immediately. However, if `"x"` is NOT in the prefix and the tail
     is unfixed, we MUST NOT emit a missing-field error! We must defer (leave the wanted
     constraint unsolved), because `"x"` might appear when the unfixed tail is later
     instantiated.
   - Whole-row queries (`RowEq`, `RowShow`, `AllFields`, `SubRow`): These operations
     iterate over or project across the ENTIRE row payload. They fundamentally require
     the row tail to be fixed and closed (`walkRowWithTypes_maybe` returning `Just fields`).
     If the tail is unfixed (`walkRowWithTypes_maybe` returning `Nothing`), the solver
     defers, waiting for GHC's typechecker to complete row inference.
-}

{- Note [Literal Evidence Synthesis vs Type-Level Search] [tag:note-literal-evidence]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Traditional extensible record and variant libraries in Haskell (such as `vinyl`,
`sop-core`, or naive type-level lists) implement evidence resolution through
recursive type-class instances. For a row of N fields:
  * The class dictionary is a recursive chain of pairs: DictCons d1 (DictCons d2 ...)
  * Looking up a field at index k traverses k dictionary steps at runtime (O(N) access).
  * GHC's simplifier must unroll and optimize N nested dictionary applications,
    leading to O(N^2) Core size and severe compilation slowdowns on records with
    30+ fields (see benchmark/variants/README.md).

Polytropos solves this by collapsing products and sums into a single generic runtime
representation:
    data Rep = Rep {-# UNPACK #-} !Word {-# UNPACK #-} !(SmallArray Any)

`Polytropos.Plugin` is a GHC typechecker plugin that intercepts evidence constraints:
  - `FieldIndex label row a`: Computes the 0-based integer slot offset `i`.
  - `ConstructorIndex con row`: Computes the 0-based constructor tag `t` (Word).
  - `RowEq` / `RowShow` / `RowEqSum` / `RowShowSum`: Directly synthesizes unrolled
    Core expressions comparing or showing each slot in sequence, using literal `Int`
    and `Word` constants (see `mkIntExpr` and `mkWordExpr`).
  - `SubRow sub super`: Emits an array of literal integer slot indices mapping
    sub-record slots directly to super-record slots in O(1) jump steps.
  - `KnownHash label`: Emits the compile-time 64-bit FNV-1a hash of the label as
    a literal `Word`.

Zero recursive dictionaries exist in Core. Compiling a 100-field record scales in
strictly O(N) linear time, identical to hand-written nominal Haskell data types.
-}

{- Note [SubRow and SubSum Projection and Narrowing Evidence] [tag:note-subrow-subsum]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Polytropos provides width subtyping for records and coproduct subsumption for variants:
  * `SubRow sub super`: Evidence that every field `(n ':= a)` in `sub` is present in
    `super` with the exact same type `a`.
  * `SubSum sub super`: Evidence that every constructor `(c ':= fs)` in `sub` is
    present in `super` with identical field payload types `fs`.

1. SubRow Index Mapping:
   In `solveSubRow`, for each field in `sub`, the plugin locates its 0-based slot index
   in `super`. It synthesizes an array of literal indices:
       projectionIndices = [idx_super_0, idx_super_1, ..., idx_super_{K-1}]
   At runtime, `projectRecord` uses this index array to copy slots directly from
   the super-record into the sub-record payload using block copy operations.

2. SubSum Injection & Narrowing:
   In `solveSubSum`, the plugin synthesizes two arrays:
   - `injectIndices`: Maps each constructor tag in `sub` to its corresponding tag in `super`.
     Used by `widenVariant` to upcast a variant in O(1).
   - `narrowIndices`: An array indexed by `super` constructor tags, containing `Just subTag`
     if the constructor belongs to `sub`, or `Nothing` if absent.
     Used by `narrowVariant` to downcast a variant in O(1) tag lookup.

Both operations require closed rows (see Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]).
If either row has an unfixed tail, solving is deferred.
-}

{- Note [Type-Level Metadata Rewriting and Defunctionalization] [tag:note-metadata-rewriting]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
GHC provides type families for row reflection:
  * `FieldNames r`: Computes `[Symbol]` of field names in row order.
  * `SimpleFieldTypes r`: Computes `[Type]` of field values.
  * `FieldTypes r f`: Computes `[Type]` under higher-kinded functor `f`.

Normally, closed type families are evaluated via recursive axioms in GHC's constraint
solver, taking O(N) rewrite steps and cluttering solver traces.

`polytroposRewrite` intercepts type family applications during GHC's rewriting phase
(`TcPluginRewrite`). It inspects the row type directly, verifies that the row tail is
closed, constructs the reified promoted list `[Symbol]` or `[Type]`, and returns an
exact `Refl` coercion (`mkPluginCoercion`). This reduces row metadata queries to
O(1) rewrite steps without generating intermediate type family equations.
-}

{- Note [Human-Centric TypeError Diagnostics & Fuzzy Matching] [tag:note-typeerror-diagnostics]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
When a developer writes `rec.nmae` instead of `rec.name`, standard GHC type inference
either leaves an unexplained stuck constraint `HasField "nmae" (Record r) a` or emits
a confusing type mismatch error.

In `solveHasField` and `solveFieldIndex`:
1. When a field `n` is absent from a closed row `r`:
   - We extract all available field names in `r`.
   - We calculate Levenshtein edit distances between `n` and every field name in `r`.
   - If candidates with edit distance <= 2 exist, we format a fuzzy suggestion:
       "Did you mean: ‘name’?"
   - We construct a multi-line formatted schema showing available fields:
       "Available record fields:
          • id :: Int
          • name :: String
          • email :: String"
2. We synthesize a structured GHC `TypeError` constraint (`mkTypeErrorCt`), which GHC
   displays prominently to the user.
3. Crucially, we also emit a dummy dictionary (`mkDummyHasFieldDict`) solving the wanted
   constraint! This prevents cascading secondary errors (e.g. "could not deduce HasField",
   "ambiguous type variable a"), ensuring the user only sees the clean, actionable
   typo diagnostic with fuzzy suggestion.
-}

{- Note [OCaml Subtype/Unify Correlation and Row Tail Algebra] [tag:note-ocaml-row-algebra]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
In OCaml's typechecker (`typecore.ml` and `btype.ml`):
- `subtype_row` filters fields and, upon encountering an unfixed tail (`Tvar`), does NOT
  blindly instantiate or unify it. It emits a deferred constraint, preserving principal
  typing until more context arrives.
- `unify_row` takes two rows and computes the merged fields and the surviving tail.

In Polytropos:
- `walkRowWithTypes_maybe` acts as our `row_repr`: it traverses the cons cells. If the
  tail reaches `Tnil` (`[]`), it succeeds with `Just fields`. If the tail is an
  unfixed type variable, it aborts to `Nothing`.
- Solvers for subtyping (`SubRow`, `SubSum`) behave like OCaml's `subtype_row`: they
  only solve when tails are fixed, and leave wanted constraints deferred when tails
  are unfixed.
-}

-------------------------------------------------------------------------------
-- Plugin entry point
-------------------------------------------------------------------------------

-- | The polytropos GHC plugin entry point.
plugin :: Plugin
plugin = defaultPlugin
  { tcPlugin           = const $ Just $ mkTcPlugin polytroposPlugin
  , parsedResultAction = \opts _modSummary -> sourcePlugin opts
  }

polytroposPlugin :: TcPlugin
polytroposPlugin = TcPlugin
  { tcPluginInit     = polytroposInit
  , tcPluginSolve    = polytroposSolve
  , tcPluginRewrite  = polytroposRewrite
  , tcPluginPostTc   = const (return ())
  , tcPluginShutdown = const (return ())
  }

--------------------------------------------------------------------------------- Plugin state
-------------------------------------------------------------------------------

data PluginState = PluginState

  { psRepTag        :: !Var    -- ^ repTag :: Rep f a -> Word
  , psRepArity      :: !Var    -- ^ repArity :: Rep f a -> Int
  , psFieldAt       :: !Var    -- ^ fieldAt :: Int -> Rep f a -> f x
  , psUnRowRep      :: !Var    -- ^ unRowRep :: RowRep f r row a -> Rep f a
  , psNoInlineCo    :: !Var    -- ^ noInlineUnsafeCo :: a -> b
  , psAnd           :: !Var    -- ^ GHC.Internal.Classes.&&
  , psComp          :: !Var    -- ^ GHC.Internal.Base.(.)
  , psEqClass       :: !Var    -- ^ GHC.Internal.Classes.== (method)
  , psShowsPrecMeth :: !Var    -- ^ GHC.Internal.Show.showsPrec (method)
  , psShowString    :: !Var    -- ^ GHC.Internal.Show.showString
  , psShowChar      :: !Var    -- ^ GHC.Internal.Show.showChar
  , psFEqInt        :: !Var    -- ^ $fEqInt
  , psFEqBool       :: !Var    -- ^ $fEqBool
  , psFEqWord       :: !Var    -- ^ $fEqWord
  , psFShowInt      :: !Var    -- ^ $fShowInt
  , psFShowBool     :: !Var    -- ^ $fShowBool
  , psEqCls         :: !Class  -- ^ GHC.Classes.Eq class
  , psShowCls       :: !Class  -- ^ GHC.Show.Show class
  , psRowFlavourCls   :: !Class  -- ^ RowFlavour class
  , psHasFieldCls     :: !Class  -- ^ GHC.Records.HasField class
  , psDictAnyTyCon    :: !TyCon  -- ^ Polytropos.Core.DictAny
  , psMkDictAny       :: !Var    -- ^ Polytropos.Core.mkDictAny
  , psEvidenceAllFields :: !Var  -- ^ Polytropos.Core.evidenceAllFields
  , psFieldTypesTyCon       :: !TyCon -- ^ Polytropos.Core.FieldTypes
  , psSimpleFieldTypesTyCon :: !TyCon -- ^ Polytropos.Core.SimpleFieldTypes
  , psFieldNamesTyCon       :: !TyCon -- ^ Polytropos.Core.FieldNames
  , psTypeErrorTyCon        :: !TyCon -- ^ GHC.Internal.TypeError.TypeError
  , psPromotedText          :: !TyCon -- ^ promoted 'Text
  , psPromotedVcat          :: !TyCon -- ^ promoted ':$$:
  }

-------------------------------------------------------------------------------
-- Plugin initialisation
-------------------------------------------------------------------------------

polytroposInit :: TcPluginM 'Init PluginState
polytroposInit = do
  coreMod <- findPolytroposCoreModule
  psRepTag     <- lookupIdInModule coreMod "repTag"
  psRepArity   <- lookupIdInModule coreMod "repArity"
  psFieldAt    <- lookupIdInModule coreMod "fieldAt"
  psUnRowRep   <- lookupIdInModule coreMod "unRowRep"
  psNoInlineCo <- lookupIdInModule coreMod "noInlineUnsafeCo"

  psEqClass    <- lookupIdInModule gHC_CLASSES "=="
  psAnd        <- lookupIdInModule gHC_CLASSES "&&"
  psFEqInt     <- lookupIdInModule gHC_CLASSES "$fEqInt"
  psFEqBool    <- lookupIdInModule gHC_CLASSES "$fEqBool"
  psFEqWord    <- lookupIdInModule gHC_CLASSES "$fEqWord"

  psShowsPrecMeth <- lookupIdInModule modShow "showsPrec"
  psShowString    <- lookupIdInModule modShow "showString"
  psShowChar      <- lookupIdInModule modShow "showChar"
  psFShowInt      <- lookupIdInModule modShow "$fShowInt"
  psFShowBool     <- lookupIdInModule modShow "$fShowBool"

  psEqCls   <- tcLookupClass eqClassName
  psShowCls <- tcLookupClass showClassName

  psComp <- lookupIdInModule modBase "."

  rowFlavourName <- lookupOrig coreMod (mkTcOcc "RowFlavour")
  psRowFlavourCls <- tcLookupClass rowFlavourName

  hasFieldOcc <- lookupOrig modRecords (mkTcOcc "HasField")
  psHasFieldCls <- tcLookupClass hasFieldOcc

  dictAnyOcc <- lookupOrig coreMod (mkTcOcc "DictAny")
  psDictAnyTyCon <- tcLookupTyCon dictAnyOcc

  psMkDictAny <- lookupIdInModule coreMod "mkDictAny"
  psEvidenceAllFields <- lookupIdInModule coreMod "evidenceAllFields"

  fieldTypesOcc <- lookupOrig coreMod (mkTcOcc "FieldTypes")
  psFieldTypesTyCon <- tcLookupTyCon fieldTypesOcc

  simpleFieldTypesOcc <- lookupOrig coreMod (mkTcOcc "SimpleFieldTypes")
  psSimpleFieldTypesTyCon <- tcLookupTyCon simpleFieldTypesOcc

  fieldNamesOcc <- lookupOrig coreMod (mkTcOcc "FieldNames")
  psFieldNamesTyCon <- tcLookupTyCon fieldNamesOcc

  psTypeErrorTyCon <- tcLookupTyCon errorMessageTypeErrorFamName
  textDataCon      <- tcLookupDataCon typeErrorTextDataConName
  vcatDataCon      <- tcLookupDataCon typeErrorVAppendDataConName

  let psPromotedText = promoteDataCon textDataCon
      psPromotedVcat = promoteDataCon vcatDataCon

  pure PluginState{..}

findModule :: String -> Maybe String -> TcPluginM 'Init Module
findModule modName mPkg = do
  let modName' = mkModuleName modName
  pkgQual <- resolveImport modName' (fsLit <$> mPkg)
  result <- findImportedModule modName' pkgQual
  case result of
    Found _ mod' -> pure mod'
    _           -> error $ "polytropos: could not find module " ++ modName

findPolytroposCoreModule :: TcPluginM 'Init Module
findPolytroposCoreModule = findModule "Polytropos.Core" (Just "polytropos-core")

lookupIdInModule :: Module -> String -> TcPluginM 'Init Var
lookupIdInModule modName occStr = do
  let occ = mkVarOcc occStr
  name <- lookupOrig modName occ
  tcLookupId name

-------------------------------------------------------------------------------
-- Type family rewriting (FieldNames, SimpleFieldTypes, FieldTypes)
-------------------------------------------------------------------------------

-- | Type family rewriter for FieldNames, SimpleFieldTypes, and FieldTypes.
-- Evaluates closed row reflection queries in O(1) during GHC's type rewriting stage.
-- See Note [Type-Level Metadata Rewriting and Defunctionalization] [ref:note-metadata-rewriting]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
polytroposRewrite :: PluginState -> UniqFM TyCon TcPluginRewriter
polytroposRewrite state = listToUFM
  [ (psFieldTypesTyCon state, rewriteFieldTypes (psFieldTypesTyCon state))
  , (psSimpleFieldTypesTyCon state, rewriteSimpleFieldTypes (psSimpleFieldTypesTyCon state))
  , (psFieldNamesTyCon state, rewriteFieldNames (psFieldNamesTyCon state))
  ]

-- | Extracts fields from a row type. Fails (returns Nothing) if the tail is unfixed or open.
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
-- See Note [OCaml Subtype/Unify Correlation and Row Tail Algebra] [ref:note-ocaml-row-algebra]
walkRowFields_maybe :: Type -> Maybe [(FastString, Type)]
walkRowFields_maybe rowTy = do
  elems <- myExtractPromotedList (unwrapSynonyms rowTy)
  mapM extractField elems
  where
    extractField elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let fieldTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> Just (n, fieldTy)
        _ -> Nothing

rewriteFieldNames :: TyCon -> [Ct] -> [Type] -> TcPluginM 'Rewrite TcPluginRewriteResult
rewriteFieldNames tyCon _givens args
  | not (null args)
  , let rowTy = last args
  , Just fields <- walkRowFields_maybe rowTy
  = do
      let names = map (mkStrLitTy . fst) fields
          reducedTy = mkPromotedListTy typeSymbolKind names
      pure $ TcPluginRewriteTo
        { tcRewriterNewWanteds = []
        , tcPluginReduction    =
            mkTyFamAppReduction "polytropos" Nominal [] tyCon args reducedTy
        }
  | otherwise = pure TcPluginNoRewrite

rewriteSimpleFieldTypes :: TyCon -> [Ct] -> [Type] -> TcPluginM 'Rewrite TcPluginRewriteResult
rewriteSimpleFieldTypes tyCon _givens args
  | not (null args)
  , let rowTy = last args
  , Just fields <- walkRowFields_maybe rowTy
  = do
      let pairKind = mkTupleTy Boxed [typeSymbolKind, liftedTypeKind]
          pairs = [ mkPromotedPairTy typeSymbolKind liftedTypeKind (mkStrLitTy name) ty
                  | (name, ty) <- fields
                  ]
          reducedTy = mkPromotedListTy pairKind pairs
      pure $ TcPluginRewriteTo
        { tcRewriterNewWanteds = []
        , tcPluginReduction    =
            mkTyFamAppReduction "polytropos" Nominal [] tyCon args reducedTy
        }
  | otherwise = pure TcPluginNoRewrite

rewriteFieldTypes :: TyCon -> [Ct] -> [Type] -> TcPluginM 'Rewrite TcPluginRewriteResult
rewriteFieldTypes tyCon _givens args
  | length args >= 2
  , let rowTy = last args
  , let fTy   = args !! (length args - 2)
  , Just fields <- walkRowFields_maybe rowTy
  = do
      let pairKind = mkTupleTy Boxed [typeSymbolKind, liftedTypeKind]
          pairs = [ mkPromotedPairTy typeSymbolKind liftedTypeKind (mkStrLitTy name) (mkAppTy fTy ty)
                  | (name, ty) <- fields
                  ]
          reducedTy = mkPromotedListTy pairKind pairs
      pure $ TcPluginRewriteTo
        { tcRewriterNewWanteds = []
        , tcPluginReduction    =
            mkTyFamAppReduction "polytropos" Nominal [] tyCon args reducedTy
        }
  | otherwise = pure TcPluginNoRewrite

-------------------------------------------------------------------------------
-- Human-Centric TypeError Diagnostics Helpers
-------------------------------------------------------------------------------

levenshtein :: String -> String -> Int
levenshtein s1 s2 =
  let n = length s1
      initRow = [0 .. n]
      stepRow row c2 = case row of
        [] -> []
        d : ds -> scanl (\left (c1, diag, above) ->
                           let cost = if c1 == c2 then 0 else 1
                           in min (diag + cost) (min (left + 1) (above + 1)))
                        (d + 1)
                        (zip3 s1 row ds)
  in case foldl' stepRow initRow s2 of
       [] -> 0
       res -> last res

suggestSimilar :: String -> [String] -> [String]
suggestSimilar target candidates =
  let scored = [ (c, d) | c <- candidates, let d = levenshtein target c, d <= 2 ]
  in map fst (sortOn snd scored)

formatRecordRow :: [(Int, FastString, Type)] -> String
formatRecordRow fields =
  "{ " ++ intercalate ", " [ unpackFS n ++ " :: " ++ showSDocUnsafe (ppr ty) | (_, n, ty) <- fields ] ++ " }"

formatVariantRow :: [(Int, FastString, Type)] -> String
formatVariantRow ctors =
  "< " ++ intercalate " | " (map formatCtor ctors) ++ " >"
  where
    formatCtor (_, n, conRowTy) =
      case walkRowWithTypes conRowTy of
        [] -> unpackFS n
        [(_, fn, ty)] | nullFS fn -> unpackFS n ++ " :: " ++ showSDocUnsafe (ppr ty)
        fs -> unpackFS n ++ " " ++ formatRecordRow fs

formatSuggestion :: String -> [String] -> String
formatSuggestion target candidates =
  case suggestSimilar target candidates of
    [] -> case candidates of
      [] -> "(no fields in record)"
      _  -> "Available fields: " ++ intercalate ", " (map (\c -> "'" ++ c ++ "'") candidates)
    suggs -> "Did you mean: " ++ intercalate " or " (map (\s -> "'" ++ s ++ "'") suggs) ++ "?"

formatCtorSuggestion :: String -> [String] -> String
formatCtorSuggestion target candidates =
  case suggestSimilar target candidates of
    [] -> case candidates of
      [] -> "(no constructors in variant)"
      _  -> "Available constructors: " ++ intercalate ", " (map (\c -> "'" ++ c ++ "'") candidates)
    suggs -> "Did you mean: " ++ intercalate " or " (map (\s -> "'" ++ s ++ "'") suggs) ++ "?"

isClosedType :: Type -> Bool
isClosedType ty = isEmptyVarSet (tyCoVarsOfType (unwrapSynonyms ty))

mkTextMsg :: PluginState -> String -> Type
mkTextMsg state s = mkTyConApp (psPromotedText state) [mkStrLitTy (fsLit s)]

mkVcatMsgs :: PluginState -> [Type] -> Type
mkVcatMsgs _ [] = error "mkVcatMsgs: empty list"
mkVcatMsgs _ [m] = m
mkVcatMsgs state (m : ms) = mkTyConApp (psPromotedVcat state) [m, mkVcatMsgs state ms]

mkTypeErrorCt :: PluginState -> CtLoc -> [String] -> TcPluginM 'Solve Ct
mkTypeErrorCt state loc msgLines = do
  let msgTys = map (mkTextMsg state) msgLines
      fullMsg = mkVcatMsgs state msgTys
      predTy = mkTyConApp (psTypeErrorTyCon state) [constraintKind, fullMsg]
  ev <- newWanted loc predTy
  pure (mkNonCanonical ev)

mkDummyHasFieldDict :: PluginState -> Class -> [Type] -> TcPluginM 'Solve EvTerm
mkDummyHasFieldDict state cls tys = do
  let getFieldId = case classMethods cls of
        (m : _) -> m
        [] -> error "Polytropos.Plugin: HasField has no methods"
      methodFullTy = piResultTys (varType getFieldId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledRTy = argTys !! 0
      fieldTy = last tys
  rName <- unsafeLiftTcM $ newName (mkVarOcc "rec")
  let rVar = mkLocalId rName (scaledMult scaledRTy) (scaledThing scaledRTy)
      dummyVal = mkCoreApps (Var (psNoInlineCo state))
                   [ Type (mkTyConTy unitTyCon)
                   , Type fieldTy
                   , mkCoreConApps unitDataCon []
                   ]
      getFieldExpr = mkCoreLams (tyVars ++ [rVar]) dummyVal
  pure $ EvExpr (evDataConApp (classDataCon cls) tys [getFieldExpr])

-------------------------------------------------------------------------------
-- Constraint solving
-------------------------------------------------------------------------------

polytroposSolve
  :: PluginState
  -> [Ct]
  -> [Ct]
  -> TcPluginM 'Solve TcPluginSolveResult
polytroposSolve state givens wanteds = do
  let allCts = givens ++ wanteds
  results <- mapM (solveOne state) allCts
  let (solvedPairs, _) = partitionEithers results
      solvedCts = map fst solvedPairs
      newCts = concatMap snd solvedPairs
  pure $ TcPluginSolveResult
    { tcPluginInsolubleCts = []
    , tcPluginSolvedCts = solvedCts
    , tcPluginNewCts = newCts
    }

solveOne :: PluginState -> Ct -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveOne state ct
  | not (isWanted (ctEvidence ct))
  = pure $ Right ()
  | otherwise
  = do
    let predTy = ctPred ct
    case classifyPredType predTy of
      ClassPred cls tys -> do
        case className cls of
          name
            | nameOccName name == mkTcOcc "FieldIndex"
            -> solveFieldIndex state ct cls tys
            | nameOccName name == mkTcOcc "ConstructorIndex"
            -> solveConstructorIndex state ct cls tys
            | nameOccName name == mkTcOcc "RowEq"
            -> solveRowEq state ct cls tys
            | nameOccName name == mkTcOcc "RowShow"
            -> solveRowShow state ct cls tys
            | nameOccName name == mkTcOcc "RowEqSum"
            -> solveRowEqSum state ct cls tys
            | nameOccName name == mkTcOcc "RowShowSum"
            -> solveRowShowSum state ct cls tys
            | nameOccName name == mkTcOcc "HasField"
            -> solveHasField state ct cls tys
            | nameOccName name == mkTcOcc "AllFields"
            -> solveAllFields state ct cls tys
            | nameOccName name == mkTcOcc "SubRow"
            -> solveSubRow state ct cls tys
            | nameOccName name == mkTcOcc "SubSum"
            -> solveSubSum state ct cls tys
            | nameOccName name == mkTcOcc "KnownHash"
            -> noNew <$> solveKnownHash ct cls tys
            | otherwise
            -> pure $ Right ()
      _ -> pure $ Right ()
  where
    noNew (Left res) = Left (res, [])
    noNew (Right ()) = Right ()

-------------------------------------------------------------------------------
-- FieldIndex solver
-------------------------------------------------------------------------------

-- | Solves the FieldIndex constraint by statically locating the field's 0-based
-- offset in the row and returning literal Int evidence.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Human-Centric TypeError Diagnostics & Fuzzy Matching] [ref:note-typeerror-diagnostics]
solveFieldIndex
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveFieldIndex state ct cls tys
  | length tys >= 3 = do
      let nTy         = tys !! (length tys - 3)
          rowTy       = tys !! (length tys - 2)
          expectedATy = last tys
          unwrapN     = unwrapSynonyms nTy
          loc         = ctLoc ct
      case isStrLitTy unwrapN of
        Just fieldName -> do
          case findFieldType fieldName rowTy of
            Just (i, actualTy)
              | actualTy `eqType` expectedATy || not (isClosedType expectedATy) -> do
                  let iExpr = mkIntExpr i
                      dictExpr = evDataConApp (classDataCon cls) tys [iExpr]
                  pure $ Left ((EvExpr dictExpr, ct), [])
              | otherwise -> do
                  let dummyExpr = mkIntExpr 0
                      dummyDict = evDataConApp (classDataCon cls) tys [dummyExpr]
                      diagLines =
                        [ "Polytropos Record Error:"
                        , "  Field '" ++ unpackFS fieldName ++ "' in record has type:"
                        , "    " ++ showSDocUnsafe (ppr actualTy)
                        , "  but expected:"
                        , "    " ++ showSDocUnsafe (ppr expectedATy)
                        ]
                  errCt <- mkTypeErrorCt state loc diagLines
                  pure $ Left ((EvExpr dummyDict, ct), [errCt])
            Nothing -> do
              case walkRowWithTypes_maybe rowTy of
                Just fields -> do
                  let dummyExpr = mkIntExpr 0
                      dummyDict = evDataConApp (classDataCon cls) tys [dummyExpr]
                      fNames = [ unpackFS n | (_, n, _) <- fields, not (nullFS n) ]
                      diagLines =
                        [ "Polytropos Record Error:"
                        , "  Field '" ++ unpackFS fieldName ++ "' does not exist in record:"
                        , "    " ++ formatRecordRow fields
                        , "  " ++ formatSuggestion (unpackFS fieldName) fNames
                        ]
                  errCt <- mkTypeErrorCt state loc diagLines
                  pure $ Left ((EvExpr dummyDict, ct), [errCt])
                Nothing -> pure $ Right ()
        Nothing -> do
          case findFieldIndexByType unwrapN rowTy of
            Just i -> do
              let iExpr = mkIntExpr i
                  dictExpr = evDataConApp (classDataCon cls) tys [iExpr]
              pure $ Left ((EvExpr dictExpr, ct), [])
            Nothing -> do
              case walkRowWithTypes_maybe rowTy of
                Just fields -> do
                  let dummyExpr = mkIntExpr 0
                      dummyDict = evDataConApp (classDataCon cls) tys [dummyExpr]
                      diagLines =
                        [ "Polytropos Record Error:"
                        , "  Type '" ++ showSDocUnsafe (ppr unwrapN) ++ "' is not a field in record:"
                        , "    " ++ formatRecordRow fields
                        ]
                  errCt <- mkTypeErrorCt state loc diagLines
                  pure $ Left ((EvExpr dummyDict, ct), [errCt])
                Nothing -> pure $ Right ()
  | otherwise = pure $ Right ()

-------------------------------------------------------------------------------
-- ConstructorIndex solver
-------------------------------------------------------------------------------

-- | Solves the ConstructorIndex constraint by statically locating the constructor's
-- 0-based tag in the sum row and returning literal Word evidence.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Human-Centric TypeError Diagnostics & Fuzzy Matching] [ref:note-typeerror-diagnostics]
solveConstructorIndex
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveConstructorIndex state ct cls tys
  | length tys >= 2 = do
      let nTy   = tys !! (length tys - 2)
          rowTy = tys !! (length tys - 1)
          unwrapN = unwrapSynonyms nTy
          loc = ctLoc ct
      case isStrLitTy unwrapN of
        Just conName -> do
          case findConstructorIndex conName rowTy of
            Just w -> do
              let wExpr = mkWordExpr w
                  dictExpr = evDataConApp (classDataCon cls) tys [wExpr]
              pure $ Left ((EvExpr dictExpr, ct), [])
            Nothing -> do
              case walkSumRowWithTypes_maybe rowTy of
                Just ctors -> do
                  let dummyExpr = mkWordExpr 0
                      dummyDict = evDataConApp (classDataCon cls) tys [dummyExpr]
                      cNames = [ unpackFS n | (_, n, _) <- ctors, not (nullFS n) ]
                      diagLines =
                        [ "Polytropos Variant Error:"
                        , "  Constructor '" ++ unpackFS conName ++ "' is not a member of variant:"
                        , "    " ++ formatVariantRow ctors
                        , "  " ++ formatCtorSuggestion (unpackFS conName) cNames
                        ]
                  errCt <- mkTypeErrorCt state loc diagLines
                  pure $ Left ((EvExpr dummyDict, ct), [errCt])
                Nothing -> pure $ Right ()
        Nothing -> do
          case findConstructorIndexByType unwrapN rowTy of
            Just w -> do
              let wExpr = mkWordExpr w
                  dictExpr = evDataConApp (classDataCon cls) tys [wExpr]
              pure $ Left ((EvExpr dictExpr, ct), [])
            Nothing -> do
              case walkSumRowWithTypes_maybe rowTy of
                Just ctors -> do
                  let dummyExpr = mkWordExpr 0
                      dummyDict = evDataConApp (classDataCon cls) tys [dummyExpr]
                      diagLines =
                        [ "Polytropos Variant Error:"
                        , "  Type '" ++ showSDocUnsafe (ppr unwrapN) ++ "' is not a payload type in variant:"
                        , "    " ++ formatVariantRow ctors
                        ]
                  errCt <- mkTypeErrorCt state loc diagLines
                  pure $ Left ((EvExpr dummyDict, ct), [errCt])
                Nothing -> pure $ Right ()
  | otherwise = pure $ Right ()

-------------------------------------------------------------------------------
-- RowEq solver
-------------------------------------------------------------------------------

-- | Solves the RowEq constraint by synthesizing an unrolled comparison expression over all fields.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
solveRowEq
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveRowEq state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      fields = walkRowWithTypes rowTy
      loc    = ctLoc ct

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repEqId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowEq class has no methods"
      methodFullTy = piResultTys (varType repEqId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledR1Ty = argTys !! 0
      scaledR2Ty = argTys !! 1

  r1Name <- unsafeLiftTcM $ newName (mkVarOcc "r1")
  r2Name <- unsafeLiftTcM $ newName (mkVarOcc "r2")
  let r1Var = mkLocalId r1Name (scaledMult scaledR1Ty) (scaledThing scaledR1Ty)
      r2Var = mkLocalId r2Name (scaledMult scaledR2Ty) (scaledThing scaledR2Ty)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep1 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r1Var])
      rep2 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r2Var])

      repTypeArgs = [Type kATy, Type fTy, Type aTy]
      tag1 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep1])
      tag2 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep2])
      eqTag = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tag1, tag2]

      arity1 = mkCoreApps (Var (psRepArity state)) (repTypeArgs ++ [rep1])
      arity2 = mkCoreApps (Var (psRepArity state)) (repTypeArgs ++ [rep2])
      eqArity = mkCoreApps (Var (psEqClass state)) [Type intTy, Var (psFEqInt state), arity1, arity2]

  wanteds <- forM fields $ \(i, _nameFS, fieldTy) -> do
    ev <- newWanted loc (mkAppTy (mkTyConTy (classTyCon (psEqCls state))) fieldTy)
    pure (i, fieldTy, ev)

  let compareField (i, fieldTy, ev) =
        let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
            idxExpr = mkIntExpr i
            raw1 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep1])
            raw2 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep2])
            fFieldTy = mkAppTy fTy fieldTy
            val1 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw1]
            val2 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw2]
            eqDict = ctEvExpr ev
        in mkCoreApps (Var (psEqClass state)) [Type fieldTy, eqDict, val1, val2]

      fieldComps = map compareField wanteds

      andFn e1 e2 = mkCoreApps (Var (psAnd state)) [e1, e2]
      bodyExpr = foldl andFn (andFn eqTag eqArity) fieldComps
      repEqExpr = mkCoreLams (tyVars ++ [r1Var, r2Var]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repEqExpr]
      newWanteds = [mkNonCanonical ev | (_, _, ev) <- wanteds]
  pure $ Left ((EvExpr dictExpr, ct), newWanteds)

-------------------------------------------------------------------------------
-- RowShow solver
-------------------------------------------------------------------------------

-- | Solves the RowShow constraint by synthesizing an unrolled showsPrec expression over all fields.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
solveRowShow
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveRowShow state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      fields = walkRowWithTypes rowTy
      loc    = ctLoc ct

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repShowsPrecId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowShow class has no methods"
      methodFullTy = piResultTys (varType repShowsPrecId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledPrecTy = argTys !! 0
      scaledRTy    = argTys !! 1

  precName <- unsafeLiftTcM $ newName (mkVarOcc "p")
  rName <- unsafeLiftTcM $ newName (mkVarOcc "r")
  let precVar = mkLocalId precName (scaledMult scaledPrecTy) (scaledThing scaledPrecTy)
      rVar    = mkLocalId rName (scaledMult scaledRTy) (scaledThing scaledRTy)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var rVar])

      rowName = case splitTyConApp_maybe rowTy of
        Just (tc, _)
          | let name = occNameString (getOccName tc)
          , name /= ":" && name /= "[]" && name /= "''[]"
          -> name
        _ -> "R" ++ show (length fields)

  prefixExpr <- unsafeLiftTcM $ mkStringExpr (rowName ++ " ")
  let prefixShowS = mkCoreApps (Var (psShowString state)) [prefixExpr]
      spaceShowS  = mkCoreApps (Var (psShowChar state)) [mkCharExpr ' ']

  wanteds <- forM fields $ \(i, _nameFS, fieldTy) -> do
    ev <- newWanted loc (mkAppTy (mkTyConTy (classTyCon (psShowCls state))) fieldTy)
    pure (i, fieldTy, ev)

  let showField (i, fieldTy, ev) =
        let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
            idxExpr = mkIntExpr i
            raw = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep])
            fFieldTy = mkAppTy fTy fieldTy
            val = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw]
            showDict = ctEvExpr ev
            zeroPrec = mkIntExpr 0
        in mkCoreApps (Var (psShowsPrecMeth state)) [Type fieldTy, showDict, zeroPrec, val]

      fieldShows = map showField wanteds
      showParts = case fieldShows of
        [] -> [prefixShowS]
        (f0 : fs) -> prefixShowS : f0 : concatMap (\f -> [spaceShowS, f]) fs

      compFn f g = mkCoreApps (Var (psComp state)) [Type stringTy, Type stringTy, Type stringTy, f, g]
      bodyExpr = foldr1 compFn showParts
      repShowsPrecExpr = mkCoreLams (tyVars ++ [precVar, rVar]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repShowsPrecExpr]
      newWanteds = [mkNonCanonical ev | (_, _, ev) <- wanteds]
  pure $ Left ((EvExpr dictExpr, ct), newWanteds)

-------------------------------------------------------------------------------
-- RowEqSum / RowShowSum solvers
-------------------------------------------------------------------------------

-- | Solves the RowEqSum constraint by synthesizing branch comparison Core trees.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
solveRowEqSum
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveRowEqSum state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      constructors = walkSumRowWithTypes rowTy
      loc    = ctLoc ct

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repEqSumId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowEqSum class has no methods"
      methodFullTy = piResultTys (varType repEqSumId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledR1Ty = argTys !! 0
      scaledR2Ty = argTys !! 1

  r1Name <- unsafeLiftTcM $ newName (mkVarOcc "r1")
  r2Name <- unsafeLiftTcM $ newName (mkVarOcc "r2")
  let r1Var = mkLocalId r1Name (scaledMult scaledR1Ty) (scaledThing scaledR1Ty)
      r2Var = mkLocalId r2Name (scaledMult scaledR2Ty) (scaledThing scaledR2Ty)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep1 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r1Var])
      rep2 = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var r2Var])

      repTypeArgs = [Type kATy, Type fTy, Type aTy]
      tag1 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep1])
      tag2 = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep2])
      eqTag = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tag1, tag2]

      falseExpr = mkCoreConApps falseDataCon []
      trueExpr  = mkCoreConApps trueDataCon []
      andFn e1 e2 = mkCoreApps (Var (psAnd state)) [e1, e2]

  ctorWanteds <- forM constructors $ \(i, conName, conRowTy) -> do
    let fields = walkRowWithTypes conRowTy
    fWanteds <- forM fields $ \(fi, _nameFS, fieldTy) -> do
      ev <- newWanted loc (mkAppTy (mkTyConTy (classTyCon (psEqCls state))) fieldTy)
      pure (fi, fieldTy, ev)
    pure (i, conName, fWanteds)

  let compareConFields fWanteds =
        let fieldComps = [ compareField fi fieldTy ev | (fi, fieldTy, ev) <- fWanteds ]
        in foldl andFn trueExpr fieldComps

      compareField fi fieldTy ev =
        let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
            idxExpr = mkIntExpr fi
            raw1 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep1])
            raw2 = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep2])
            fFieldTy = mkAppTy fTy fieldTy
            val1 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw1]
            val2 = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw2]
            eqDict = ctEvExpr ev
        in mkCoreApps (Var (psEqClass state)) [Type fieldTy, eqDict, val1, val2]

      buildTree _ [] = falseExpr
      buildTree tagExpr ((i, _conName, fWanteds) : rest) =
        let iLit = mkWordExpr (fromIntegral i)
            cond = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tagExpr, iLit]
        in mkIfThenElse cond (compareConFields fWanteds) (buildTree tagExpr rest)

      bodyExpr = mkIfThenElse eqTag (buildTree tag1 ctorWanteds) falseExpr
      repEqSumExpr = mkCoreLams (tyVars ++ [r1Var, r2Var]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repEqSumExpr]
      allNewWanteds = [ mkNonCanonical ev | (_, _, fWanteds) <- ctorWanteds, (_, _, ev) <- fWanteds ]

  pure $ Left ((EvExpr dictExpr, ct), allNewWanteds)

-- | Solves the RowShowSum constraint by synthesizing constructor branch showsPrec Core trees.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
solveRowShowSum
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveRowShowSum state ct cls tys = do
  let rowTy  = last tys
      rTy    = tys !! (length tys - 2)
      constructors = walkSumRowWithTypes rowTy
      loc    = ctLoc ct

      scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      repShowsPrecSumId = case classMethods cls of
        (m : _) -> m
        []      -> error "Polytropos.Plugin: RowShowSum class has no methods"
      methodFullTy = piResultTys (varType repShowsPrecSumId) tys
      (_, _, methodInDictTy) = splitFunTy methodFullTy
      (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
      (argTys, _) = splitFunTys tauTy
      scaledPrecTy = argTys !! 0
      scaledRTy    = argTys !! 1

  precName <- unsafeLiftTcM $ newName (mkVarOcc "p")
  rName <- unsafeLiftTcM $ newName (mkVarOcc "r")
  let precVar = mkLocalId precName (scaledMult scaledPrecTy) (scaledThing scaledPrecTy)
      rVar    = mkLocalId rName (scaledMult scaledRTy) (scaledThing scaledRTy)

      kATy   = mkTyVarTy (tyVars !! 0)
      fTy    = mkTyVarTy (tyVars !! 1)
      aTy    = mkTyVarTy (tyVars !! 2)
      kRowTy = typeKind rowTy

      unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
      rep = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var rVar])

      repTypeArgs = [Type kATy, Type fTy, Type aTy]
      tag = mkCoreApps (Var (psRepTag state)) (repTypeArgs ++ [rep])

      spaceShowS  = mkCoreApps (Var (psShowChar state)) [mkCharExpr ' ']
      compFn f g = mkCoreApps (Var (psComp state)) [Type stringTy, Type stringTy, Type stringTy, f, g]

  ctorWanteds <- forM constructors $ \(i, conNameFS, conRowTy) -> do
    let fields = walkRowWithTypes conRowTy
    fWanteds <- forM fields $ \(fi, _nameFS, fieldTy) -> do
      ev <- newWanted loc (mkAppTy (mkTyConTy (classTyCon (psShowCls state))) fieldTy)
      pure (fi, fieldTy, ev)
    pure (i, conNameFS, fWanteds)

  let showField fi fieldTy ev =
        let fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type fieldTy]
            idxExpr = mkIntExpr fi
            raw = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep])
            fFieldTy = mkAppTy fTy fieldTy
            val = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw]
            showDict = ctEvExpr ev
            zeroPrec = mkIntExpr 0
        in mkCoreApps (Var (psShowsPrecMeth state)) [Type fieldTy, showDict, zeroPrec, val]

      showConFields conNameFS fWanteds = do
        let conName = unpackFS conNameFS
        prefixExpr <- unsafeLiftTcM $ mkStringExpr (conName ++ " ")
        let prefixShowS = mkCoreApps (Var (psShowString state)) [prefixExpr]
            fieldShows = [ showField fi fieldTy ev | (fi, fieldTy, ev) <- fWanteds ]
            showParts = case fieldShows of
              [] -> [prefixShowS]
              (f0 : fs) -> prefixShowS : f0 : concatMap (\f -> [spaceShowS, f]) fs
        pure $ foldr1 compFn showParts

  let buildTree _tagExpr [] = do
        errorPrefix <- unsafeLiftTcM $ mkStringExpr "??? "
        pure $ mkCoreApps (Var (psShowString state)) [errorPrefix]
      buildTree tagExpr ((i, conNameFS, fWanteds) : rest) = do
        let iLit = mkWordExpr (fromIntegral i)
            cond = mkCoreApps (Var (psEqClass state)) [Type (mkTyConTy wordTyCon), Var (psFEqWord state), tagExpr, iLit]
        trueBranch <- showConFields conNameFS fWanteds
        falseBranch <- buildTree tagExpr rest
        pure $ mkIfThenElse cond trueBranch falseBranch

  bodyExpr <- buildTree tag ctorWanteds
  let repShowsPrecSumExpr = mkCoreLams (tyVars ++ [precVar, rVar]) bodyExpr

      dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, repShowsPrecSumExpr]
      allNewWanteds = [ mkNonCanonical ev | (_, _, fWanteds) <- ctorWanteds, (_, _, ev) <- fWanteds ]

  pure $ Left ((EvExpr dictExpr, ct), allNewWanteds)

-------------------------------------------------------------------------------
-- HasField solver
-------------------------------------------------------------------------------

-- | Solves GHC's HasField class for records, returning a record selector function
-- using literal slot indices.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Human-Centric TypeError Diagnostics & Fuzzy Matching] [ref:note-typeerror-diagnostics]
solveHasField
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveHasField state ct cls tys = do
  let len = length tys
  if len >= 3 then do
    let fieldTy = last tys
        recTy   = tys !! (len - 2)
        nTy     = tys !! (len - 3)
        loc     = ctLoc ct
    case isStrLitTy (unwrapSynonyms nTy) of
      Just fieldName -> do
        case splitTyConApp_maybe (unwrapSynonyms recTy) of
          Just (tc, args)
            | occNameString (getOccName tc) == "RowRep"
            , length args >= 4 -> do
              let aTy   = last args
                  rowTy = args !! (length args - 2)
                  rTy   = args !! (length args - 3)
                  fTy   = args !! (length args - 4)
                  kATy  = typeKind aTy
                  kRowTy = typeKind rowTy
              case splitTyConApp_maybe (unwrapSynonyms rTy) of
                Just (tcR, []) | occNameString (getOccName tcR) `elem` ["ProductRowT", "ProductRowHKDT"] -> do
                  case findFieldType fieldName rowTy of
                    Just (i, actualFieldTy) -> do
                      let getFieldId = case classMethods cls of
                            (m : _) -> m
                            [] -> error "Polytropos.Plugin: HasField has no methods"
                          methodFullTy = piResultTys (varType getFieldId) tys
                          (_, _, methodInDictTy) = splitFunTy methodFullTy
                          (tyVars, tauTy) = splitForAllTyCoVars methodInDictTy
                          (argTys, _) = splitFunTys tauTy
                          scaledRTy = argTys !! 0

                      rName <- unsafeLiftTcM $ newName (mkVarOcc "rec")
                      let rVar = mkLocalId rName (scaledMult scaledRTy) (scaledThing scaledRTy)

                          unRowRepTypeArgs = [Type kRowTy, Type kATy, Type fTy, Type rTy, Type rowTy, Type aTy]
                          rep = mkCoreApps (Var (psUnRowRep state)) (unRowRepTypeArgs ++ [Var rVar])

                          fieldAtTypeArgs = [Type kATy, Type fTy, Type aTy, Type actualFieldTy]
                          idxExpr = mkIntExpr i
                          raw = mkCoreApps (Var (psFieldAt state)) (fieldAtTypeArgs ++ [idxExpr, rep])

                          fFieldTy = mkAppTy fTy actualFieldTy
                          validTy  = fieldTy `eqType` actualFieldTy
                                  || fieldTy `eqType` fFieldTy
                          val = mkCoreApps (Var (psNoInlineCo state)) [Type fFieldTy, Type fieldTy, raw]

                          getFieldExpr = mkCoreLams (tyVars ++ [rVar]) val
                          dictExpr = evDataConApp (classDataCon cls) tys [getFieldExpr]

                      if isClosedType fieldTy && not validTy
                        then do
                          let diagLines =
                                [ "Polytropos Record Error:"
                                , "  Field '" ++ unpackFS fieldName ++ "' in record has type:"
                                , "    " ++ showSDocUnsafe (ppr actualFieldTy)
                                , "  but context expected:"
                                , "    " ++ showSDocUnsafe (ppr fieldTy)
                                ]
                          errCt <- mkTypeErrorCt state loc diagLines
                          pure $ Left ((EvExpr dictExpr, ct), [errCt])
                        else
                          pure $ Left ((EvExpr dictExpr, ct), [])
                    Nothing -> do
                      case walkRowWithTypes_maybe rowTy of
                        Just fields -> do
                          dummyDict <- mkDummyHasFieldDict state cls tys
                          let fNames = [ unpackFS n | (_, n, _) <- fields, not (nullFS n) ]
                              diagLines =
                                [ "Polytropos Record Error:"
                                , "  Field '" ++ unpackFS fieldName ++ "' does not exist in record:"
                                , "    " ++ formatRecordRow fields
                                , "  " ++ formatSuggestion (unpackFS fieldName) fNames
                                ]
                          errCt <- mkTypeErrorCt state loc diagLines
                          pure $ Left ((dummyDict, ct), [errCt])
                        Nothing -> pure $ Right ()
                _ -> pure $ Right ()
          _ -> pure $ Right ()
      Nothing -> pure $ Right ()
  else pure $ Right ()

-------------------------------------------------------------------------------
-- AllFields solver (generic field-class dictionary supply)
-------------------------------------------------------------------------------

-- | Solves AllFields by synthesizing an array of DictAny evidence dictionaries.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
solveAllFields
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveAllFields state ct cls tys
  | length tys >= 3
  , let rowTy = tys !! (length tys - 2)
  , Just _ <- myExtractPromotedList (unwrapSynonyms rowTy)
  = do
      let cTy    = last tys
          rTy    = tys !! (length tys - 3)
          fields = walkRowWithTypes rowTy
          loc    = ctLoc ct
          dictAnyTy = mkAppTy (mkTyConTy (psDictAnyTyCon state)) cTy

      -- For each field, create a new wanted constraint for (c fieldTy)
      wanteds <- forM fields $ \(_i, _nameFS, fieldTy) -> do
        ev <- newWanted loc (mkAppTy cTy fieldTy)
        pure (fieldTy, ev)

      -- For each field, construct: mkDictAny @c @fieldTy dict
      let dictAnys = [ mkCoreApps (Var (psMkDictAny state))
                                  [Type cTy, Type fieldTy, ctEvExpr ev]
                     | (fieldTy, ev) <- wanteds
                     ]

      -- Construct: evidenceAllFields @c [dictAny_0, dictAny_1, ...]
      let listExpr = mkListExpr dictAnyTy dictAnys
          arrExpr  = mkCoreApps (Var (psEvidenceAllFields state)) [Type cTy, listExpr]

      -- Superclass evidence for RowFlavour r
      let scEvidence = evDataConApp (classDataCon (psRowFlavourCls state)) [rTy] []

      -- Class dictionary: AllFields r row c
      let dictExpr = evDataConApp (classDataCon cls) tys [scEvidence, arrExpr]
          newWanteds = [mkNonCanonical ev | (_fieldTy, ev) <- wanteds]

      pure $ Left ((EvExpr dictExpr, ct), newWanteds)
  | otherwise = pure $ Right ()

-------------------------------------------------------------------------------
-- SubRow and SubSum solvers
-------------------------------------------------------------------------------

-- | Solves the SubRow constraint by synthesizing literal index projection lists.
-- See Note [SubRow and SubSum Projection and Narrowing Evidence] [ref:note-subrow-subsum]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
solveSubRow
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveSubRow state ct cls tys
  | length tys >= 2
  , let subTy   = tys !! (length tys - 2)
  , let superTy = last tys
  , let loc     = ctLoc ct
  , Just subFields   <- walkRowWithTypes_maybe subTy
  , Just superFields <- walkRowWithTypes_maybe superTy
  = case matchFields subFields superFields of
      Just indices -> do
        let indicesExpr = mkListExpr intTy (map mkIntExpr indices)
            dictExpr    = evDataConApp (classDataCon cls) tys [indicesExpr]
        pure $ Left ((EvExpr dictExpr, ct), [])
      Nothing -> do
        let dummyDict = evDataConApp (classDataCon cls) tys [mkListExpr intTy []]
            mismatchDiag = findSubRowMismatch subFields superFields
        errCt <- mkTypeErrorCt state loc mismatchDiag
        pure $ Left ((EvExpr dummyDict, ct), [errCt])
  | otherwise = pure $ Right ()
  where
    matchFields :: [(Int, FastString, Type)] -> [(Int, FastString, Type)] -> Maybe [Int]
    matchFields [] _ = Just []
    matchFields ((_, name, fieldTy) : rest) sFields =
      case [ j | (j, sName, sFieldTy) <- sFields
               , (if nullFS name || nullFS sName then True else sName == name)
               , fieldTy `eqType` sFieldTy ] of
        (j : _) -> (j :) <$> matchFields rest sFields
        []      -> Nothing

    findSubRowMismatch :: [(Int, FastString, Type)] -> [(Int, FastString, Type)] -> [String]
    findSubRowMismatch [] _ =
      [ "Polytropos SubRow Error:"
      , "  Sub-record row does not match super-record row."
      ]
    findSubRowMismatch ((_, name, fieldTy) : rest) sFields =
      case [ sFieldTy | (_, sName, sFieldTy) <- sFields
                      , if nullFS name || nullFS sName then True else sName == name ] of
        [] ->
          let sNames = [ unpackFS n | (_, n, _) <- sFields, not (nullFS n) ]
          in [ "Polytropos SubRow Error:"
             , "  Cannot project record: field '" ++ unpackFS name ++ "' from sub-record is missing in super-record:"
             , "    " ++ formatRecordRow sFields
             , "  " ++ formatSuggestion (unpackFS name) sNames
             ]
        (sFieldTy : _)
          | not (fieldTy `eqType` sFieldTy) ->
              [ "Polytropos SubRow Error:"
              , "  Cannot project record: field '" ++ unpackFS name ++ "' has type:"
              , "    " ++ showSDocUnsafe (ppr fieldTy)
              , "  in sub-record, but has type:"
              , "    " ++ showSDocUnsafe (ppr sFieldTy)
              , "  in super-record."
              ]
          | otherwise -> findSubRowMismatch rest sFields

-- | Solves the SubSum constraint by synthesizing literal injection and narrowing arrays.
-- See Note [SubRow and SubSum Projection and Narrowing Evidence] [ref:note-subrow-subsum]
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
solveSubSum
  :: PluginState
  -> Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either ((EvTerm, Ct), [Ct]) ())
solveSubSum state ct cls tys
  | length tys >= 2
  , let subTy   = tys !! (length tys - 2)
  , let superTy = last tys
  , let loc     = ctLoc ct
  , Just subCons   <- walkSumRowWithTypes_maybe subTy
  , Just superCons <- walkSumRowWithTypes_maybe superTy
  = case matchCons subCons superCons of
      Just injectIndices -> do
        let wordTy = mkTyConTy wordTyCon
            injectExpr = mkListExpr wordTy (map mkWordExpr injectIndices)

            narrowIndices =
              [ case [ fromIntegral i :: Word
                     | (i, sName, sConRowTy) <- subCons
                     , (if nullFS sName || nullFS superName then True else sName == superName)
                     , sameRow sConRowTy superConRowTy
                     ] of
                  (subIdx : _) -> Just subIdx
                  []           -> Nothing
              | (_j, superName, superConRowTy) <- superCons
              ]

            maybeWordTy = mkAppTy (mkTyConTy maybeTyCon) wordTy
            narrowDataExpr Nothing = mkCoreConApps nothingDataCon [Type wordTy]
            narrowDataExpr (Just w) = mkCoreConApps justDataCon [Type wordTy, mkWordExpr w]
            narrowExpr = mkListExpr maybeWordTy (map narrowDataExpr narrowIndices)

            dictExpr = evDataConApp (classDataCon cls) tys [injectExpr, narrowExpr]
        pure $ Left ((EvExpr dictExpr, ct), [])
      Nothing -> do
        let wordTy = mkTyConTy wordTyCon
            maybeWordTy = mkAppTy (mkTyConTy maybeTyCon) wordTy
            dummyDict = evDataConApp (classDataCon cls) tys [mkListExpr wordTy [], mkListExpr maybeWordTy []]
            mismatchDiag = findSubSumMismatch subCons superCons
        errCt <- mkTypeErrorCt state loc mismatchDiag
        pure $ Left ((EvExpr dummyDict, ct), [errCt])
  | otherwise = pure $ Right ()
  where
    matchCons :: [(Int, FastString, Type)] -> [(Int, FastString, Type)] -> Maybe [Word]
    matchCons [] _ = Just []
    matchCons ((_, conName, conRowTy) : rest) sCons =
      case [ j | (j, sName, sRowTy) <- sCons
               , (if nullFS conName || nullFS sName then True else sName == conName)
               , sameRow conRowTy sRowTy ] of
        (j : _) -> (fromIntegral j :) <$> matchCons rest sCons
        []      -> Nothing

    sameRow r1 r2
      | r1 `eqType` r2 = True
      | Just fs1 <- walkRowWithTypes_maybe r1
      , Just fs2 <- walkRowWithTypes_maybe r2
      = length fs1 == length fs2 &&
        and [ (if nullFS n1 || nullFS n2 then True else n1 == n2) && t1 `eqType` t2 | ((_, n1, t1), (_, n2, t2)) <- zip fs1 fs2 ]
      | otherwise = False

    findSubSumMismatch :: [(Int, FastString, Type)] -> [(Int, FastString, Type)] -> [String]
    findSubSumMismatch [] _ =
      [ "Polytropos SubSum Error:"
      , "  Sub-variant row does not match super-variant row."
      ]
    findSubSumMismatch ((_, conName, conRowTy) : rest) sCons =
      case [ sRowTy | (_, sName, sRowTy) <- sCons
                    , if nullFS conName || nullFS sName then True else sName == conName ] of
        [] ->
          let sNames = [ unpackFS n | (_, n, _) <- sCons, not (nullFS n) ]
          in [ "Polytropos SubSum Error:"
             , "  Cannot widen variant: constructor '" ++ unpackFS conName ++ "' from sub-variant is missing in super-variant:"
             , "    " ++ formatVariantRow sCons
             , "  " ++ formatCtorSuggestion (unpackFS conName) sNames
             ]
        (sRowTy : _)
          | not (sameRow conRowTy sRowTy) ->
              let subFs   = walkRowWithTypes conRowTy
                  superFs = walkRowWithTypes sRowTy
              in [ "Polytropos SubSum Error:"
                 , "  Cannot widen variant: constructor '" ++ unpackFS conName ++ "' has different payload rows:"
                 , "    sub-variant payload:   " ++ formatRecordRow subFs
                 , "    super-variant payload: " ++ formatRecordRow superFs
                 ]
          | otherwise -> findSubSumMismatch rest sCons

-------------------------------------------------------------------------------
-- KnownHash solver
-------------------------------------------------------------------------------

-- | FNV-1a 64-bit hash for a type-level label symbol.
--
-- Standard FNV-1a 64-bit parameters:
--   offset_basis = 14695981039346656037 (0xcbf29ce484222325)
--   prime        = 1099511628211        (0x100000001b3)
fnv1a64FS :: FastString -> Word
fnv1a64FS fs = fromIntegral (foldl' step (14695981039346656037 :: Word64) (unpackFS fs))
  where
    step !h !c = (h `xor` fromIntegral (ord c)) * 1099511628211

-- | Solves the KnownHash constraint by computing compile-time 64-bit FNV-1a hash
-- and emitting literal Word evidence.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
solveKnownHash
  :: Ct
  -> Class
  -> [Type]
  -> TcPluginM 'Solve (Either (EvTerm, Ct) ())
solveKnownHash ct cls tys = do
  let mSTy = case tys of
        [s]    -> Just s
        [_, s] -> Just s
        _      -> Nothing
  case mSTy of
    Just sTy -> case isStrLitTy (unwrapSynonyms sTy) of
      Just fs -> do
        let h = fnv1a64FS fs
            wExpr = mkWordExpr h
            dictExpr = evDataConApp (classDataCon cls) tys [wExpr]
        pure $ Left (EvExpr dictExpr, ct)
      Nothing -> pure $ Right ()
    Nothing -> pure $ Right ()

-- | Walks a record row type. Fails (returns Nothing) if the row tail is unfixed or open.
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
-- See Note [OCaml Subtype/Unify Correlation and Row Tail Algebra] [ref:note-ocaml-row-algebra]
walkRowWithTypes_maybe :: Type -> Maybe [(Int, FastString, Type)]
walkRowWithTypes_maybe rowTy = do
  xs <- myExtractPromotedList (unwrapSynonyms rowTy)
  zipWithM extractField [0..] xs
  where
    extractField i elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let fieldTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> Just (i, n, fieldTy)
        _ -> Just (i, nilFS, elemTy)

-- | Walks a variant sum row type. Fails (returns Nothing) if the row tail is unfixed or open.
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
-- See Note [OCaml Subtype/Unify Correlation and Row Tail Algebra] [ref:note-ocaml-row-algebra]
walkSumRowWithTypes_maybe :: Type -> Maybe [(Int, FastString, Type)]
walkSumRowWithTypes_maybe rowTy = do
  xs <- myExtractPromotedList (unwrapSynonyms rowTy)
  zipWithM extractCon [0..] xs
  where
    extractCon i elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let conRowTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> Just (i, n, conRowTy)
        _ -> Just (i, nilFS, elemTy)

-------------------------------------------------------------------------------
-- Row walking
-------------------------------------------------------------------------------

unwrapSynonyms :: Type -> Type
unwrapSynonyms ty = case coreView ty of
  Just ty' -> unwrapSynonyms ty'
  Nothing  -> ty


-- | Extracts elements from a promoted type-level list.
-- Returns Nothing if the list has an unfixed type variable tail (an open row).
-- See Note [Row Type Anatomy: Open vs Closed Rows and Fixed vs Unfixed Tails] [ref:note-row-anatomy]
-- See Note [OCaml Subtype/Unify Correlation and Row Tail Algebra] [ref:note-ocaml-row-algebra]
myExtractPromotedList :: Type -> Maybe [Type]
myExtractPromotedList ty = case splitTyConApp_maybe (unwrapSynonyms ty) of
  Just (tc, [_, x, xs]) | occNameString (getOccName tc) == ":" -> do
    rest <- myExtractPromotedList xs
    return (x : rest)
  Just (tc, [_]) | occNameString (getOccName tc) == "[]" -> Just []
  _ -> Nothing

walkRowWithTypes :: Type -> [(Int, FastString, Type)]
walkRowWithTypes rowTy =
  case myExtractPromotedList (unwrapSynonyms rowTy) of { Just xs -> zipWith extractField [0..] xs; Nothing -> [] }
  where
    extractField i elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let fieldTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> (i, n, fieldTy)
        _ -> (i, nilFS, elemTy)

walkSumRowWithTypes :: Type -> [(Int, FastString, Type)]
walkSumRowWithTypes rowTy =
  case myExtractPromotedList (unwrapSynonyms rowTy) of { Just xs -> zipWith extractCon [0..] xs; Nothing -> [] }
  where
    extractCon i elemTy =
      case splitTyConApp_maybe (unwrapSynonyms elemTy) of
        Just (_, args)
          | length args >= 2
          , let nameTy = args !! (length args - 2)
          , let conRowTy = args !! (length args - 1)
          , Just n <- isStrLitTy (unwrapSynonyms nameTy)
          -> (i, n, conRowTy)
        _ -> (i, nilFS, elemTy)


findConstructorIndex :: FastString -> Type -> Maybe Word
findConstructorIndex conName rowTy =
  case [fromIntegral i | (i, n, _) <- walkSumRowWithTypes rowTy, n == conName] of
    (w : _) -> Just w
    []      -> Nothing

findFieldIndexByType :: Type -> Type -> Maybe Int
findFieldIndexByType targetTy rowTy =
  case [i | (i, _, ty) <- walkRowWithTypes rowTy, targetTy `eqType` ty] of
    (i : _) -> Just i
    []      -> Nothing

findConstructorIndexByType :: Type -> Type -> Maybe Word
findConstructorIndexByType targetTy rowTy =
  case [fromIntegral i | (i, _, ty) <- walkSumRowWithTypes rowTy, targetTy `eqType` ty] of
    (w : _) -> Just w
    []      -> Nothing

findFieldType :: FastString -> Type -> Maybe (Int, Type)
findFieldType fieldName rowTy =
  case [(i, ty) | (i, n, ty) <- walkRowWithTypes rowTy, n == fieldName] of
    (res : _) -> Just res
    []      -> Nothing

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------

-- | Construct a boxed Int Core expression from an Int value.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
mkIntExpr :: Int -> CoreExpr
mkIntExpr i = mkCoreConApps intDataCon [Lit (LitNumber LitNumInt (toInteger i))]

-- | Construct a boxed Word Core expression from a Word value.
-- See Note [Literal Evidence Synthesis vs Type-Level Search] [ref:note-literal-evidence]
mkWordExpr :: Word -> CoreExpr
mkWordExpr w = mkCoreConApps wordDataCon [Lit (LitNumber LitNumWord (toInteger w))]
