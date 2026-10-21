{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- |
-- Module      : Polytropos.ReaderSoup
-- Description : Composable multi-context Reader monad with zero-overhead row polymorphism
-- Copyright   : (c) 2026, Nadia Yvette Chambers
-- License     : EUPL-1.2 OR Apache-2.0
-- Maintainer  : nadia.yvette.chambers@ik.me
-- Stability   : experimental
--
-- A composable, extensible multi-context Reader environment for
-- <https://hackage.haskell.org/package/polytropos polytropos>.
--
-- In traditional application architectures, applications requiring multiple capabilities
-- (e.g. database connections, metrics collectors, logging handles, configuration schemas)
-- are often forced to choose between two unappealing designs:
--
-- 1. __The MTL class explosion__: Defining a dedicated type class (@MonadDB@, @MonadLogger@,
--    @MonadMetrics@) for every capability and writing $O(N^2)$ quadratic passthrough instances
--    for every layer of the transformer stack.
-- 2. __The monolithic AppEnv__: Defining a single massive record containing all subsystem
--    handles, tightly coupling isolated subroutines to the entire application's footprint.
--
-- 'ReaderSoup' solves this dilemma by adapting Yves Parès's pioneering @reader-soup@
-- package from the <https://github.com/funflow/porcupine porcupine> pipeline ecosystem
-- to Polytropos's high-performance contiguous flat array representation ('Polytropos.Core.Rep')
-- and compile-time dictionary synthesis ('Polytropos.Plugin').
--
-- Key Properties:
--
-- * __Flat Storage__: All contexts live in a single contiguous @SmallArray@ inside 'Record'.
--   Field retrieval via 'askSoup' resolves at compile time to a direct slot offset ($O(1)$).
-- * __Sub-soup Projection__: Sub-actions declare only the contexts they need. Structural
--   narrowing via 'filtering' copies the required slice in $O(K)$ time via 'SubRow' evidence.
-- * __Context Isolation__: 'Spoon' extracts any labeled context into a standard 'MonadReader'
--   instance supporting 'ask' and 'local'.
-- * __Third-Party Monad Bridging__: 'SoupContext' connects external monads (such as
--   'Control.Monad.Trans.Resource.ResourceT') using 'picking', 'scooping', and 'pouring'.
-- * __Modular Consumption__: 'ContextRunner' and 'consumeSoup' allow contexts to be peeled
--   and evaluated in dependency order until the base broth is reached.
--
-- = When to Use This Module
--
-- * When developing modular services requiring access to multiple independent
--   subsystems (databases, loggers, metrics, config handles) without monolithic
--   environment records.
-- * When avoiding quadratic $O(N^2)$ instance boilerplate of classic MTL typeclass
--   hierarchies across multiple transformer layers.
-- * When composing sub-routines that require only a localized subset of capabilities,
--   narrowing environments via zero-cost structural sub-row projections ('filtering').
--
-- = Worked Example
--
-- Managing multi-capability application environments and narrowing to sub-actions:
--
-- > {-# LANGUAGE DataKinds #-}
-- > {-# LANGUAGE OverloadedStrings #-}
-- > {-# OPTIONS_GHC -fplugin=Polytropos.Plugin #-}
-- >
-- > import Control.Monad.Reader.Class (ask, local)
-- > import Polytropos
-- > import Polytropos.ReaderSoup
-- >
-- > data DBConn = DBConn String deriving (Eq, Show)
-- >
-- > type AppCtx =
-- >   '[ "db"       ':= DBConn
-- >    , "port"     ':= Int
-- >    , "greeting" ':= String
-- >    ]
-- >
-- > mkAppEnv :: DBConn -> Int -> String -> Record AppCtx
-- > mkAppEnv db p g =
-- >   insertField (Field @"db") db
-- >     $ insertField (Field @"port") p
-- >     $ insertField (Field @"greeting") g
-- >     $ emptyRecord
-- >
-- > -- A sub-worker declaring only the capabilities it actually needs:
-- > subWorker :: ReaderSoup '[ "db" ':= DBConn, "greeting" ':= String ] String
-- > subWorker = do
-- >   db <- askSoup (Field @"db")
-- >   g  <- askSoup (Field @"greeting")
-- >   pure (g ++ " connected to " ++ show db)
-- >
-- > main :: IO ()
-- > main = do
-- >   let env = mkAppEnv (DBConn "pg://cluster") 8080 "Welcome"
-- >   -- Run localized subWorker against full AppCtx via structural sub-row filtering:
-- >   msg <- runReaderSoup (filtering subWorker) env
-- >   putStrLn msg
-- >
-- >   -- Project a single context into standard MonadReader with ask and local:
-- >   port <- runReaderSoup (dipping (Field @"port") (local (+ 100) ask)) env
-- >   print port  -- 8180
module Polytropos.ReaderSoup
  ( -- * Core ReaderSoup Monad
    ReaderSoupT(..)
  , ReaderSoup
  , CookedReaderSoup
  , runReaderSoup
  , runReaderSoupT

    -- * Context Access & Narrowing
  , Label
  , askSoup
  , filtering

    -- * Single Context Projection (Spoon)
  , Spoon(..)
  , LookupContext
  , dipping
  , rioToSpoon
  , spoonToReaderT

    -- * Third-Party Monad Bridging (SoupContext)
  , ContextFromName
  , SoupContext(..)
  , CanBeScoopedIn
  , withSpoon
  , picking
  , scooping
  , pouring

    -- * Modular Context Peeling & Runner Composition
  , ContextRunner(..)
  , splitRecordHead
  , consRecord
  , pickTopping
  , eatTopping
  , finishBroth
  , ArgsForSoupConsumption(..)
  ) where

import Control.Applicative (Alternative(..))
import Control.Monad (MonadPlus(..))
import Control.Monad.Base (MonadBase(..))
import Control.Monad.Catch (MonadCatch, MonadMask, MonadThrow)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.IO.Unlift (MonadUnliftIO(..))
import Control.Monad.Reader.Class (MonadReader(..))
import Control.Monad.Trans.Class (MonadTrans(..))
import Control.Monad.Trans.Control (MonadBaseControl(..))
import Control.Monad.Trans.Reader (ReaderT(..), asks)
import Data.Functor.Identity (Identity(..))
import Data.Kind (Type)
import Data.Primitive.SmallArray (indexSmallArray)
import GHC.Exts (toList)
import GHC.TypeLits (KnownSymbol, Symbol)
import Polytropos.Core
  ( Pair(..), RowRep(..), Rep(..), productRep
  , FieldIndex(..), SubRow, Field(..)
  )
import Polytropos (Record, emptyRecord, setField, projectRecord)
import Unsafe.Coerce (unsafeCoerce)

-- | Fetch a field value from a 'Record' using its compile-time synthesized index.
getField :: forall n a r. FieldIndex n r a => Field n -> Record r -> a
getField _ (RowRep (Rep _ v)) =
  case indexSmallArray v (fieldIndex @_ @n @r @a) of
    Identity val -> unsafeCoerce val

--------------------------------------------------------------------------------
-- 1. Core ReaderSoup Monad
--------------------------------------------------------------------------------

-- | 'ReaderSoupT' holds a row-polymorphic collection of Reader contexts within
-- a single 'ReaderT' layer over a base monad @m@.
--
-- Unlike deeply nested transformer stacks, all contexts reside in a single flat
-- contiguous 'Record', eliminating pointer chasing and wrapper allocations.
newtype ReaderSoupT (ctxs :: [Pair Symbol Type]) m a = ReaderSoupT
  { unReaderSoupT :: ReaderT (Record ctxs) m a }
  deriving
    ( Functor
    , Applicative
    , Alternative
    , Monad
    , MonadFail
    , MonadPlus
    , MonadIO
    , MonadUnliftIO
    , MonadThrow
    , MonadCatch
    , MonadMask
    )

-- | The canonical 'ReaderSoup' type operating over 'IO'.
type ReaderSoup ctxs = ReaderSoupT ctxs IO

-- | In Porcupine, 'CookedReaderSoup' denoted a soup ready to have its toppings peeled.
-- In Polytropos, both cooked and raw representations share the same flat 'Record'.
type CookedReaderSoup ctxs = ReaderSoup ctxs

-- | Convenient alias for field labels.
type Label = Field

instance MonadTrans (ReaderSoupT ctxs) where
  lift = ReaderSoupT . lift

instance (MonadBase b m) => MonadBase b (ReaderSoupT ctxs m) where
  liftBase = ReaderSoupT . liftBase

instance (MonadBaseControl b m) => MonadBaseControl b (ReaderSoupT ctxs m) where
  type StM (ReaderSoupT ctxs m) a = StM (ReaderT (Record ctxs) m) a
  liftBaseWith f = ReaderSoupT $ liftBaseWith $ \runInBase ->
    f (runInBase . unReaderSoupT)
  restoreM = ReaderSoupT . restoreM

-- | Access the full underlying 'Record' environment.
instance (Monad m) => MonadReader (Record ctxs) (ReaderSoupT ctxs m) where
  ask = ReaderSoupT ask
  local f (ReaderSoupT act) = ReaderSoupT (local f act)

-- | Run a 'ReaderSoup' action by supplying the full contiguous context 'Record'.
runReaderSoup :: ReaderSoup ctxs a -> Record ctxs -> IO a
runReaderSoup (ReaderSoupT (ReaderT act)) = act

-- | Run a transformer 'ReaderSoupT' action over any base monad @m@.
runReaderSoupT :: ReaderSoupT ctxs m a -> Record ctxs -> m a
runReaderSoupT (ReaderSoupT (ReaderT act)) = act

--------------------------------------------------------------------------------
-- 2. Context Access & Narrowing
--------------------------------------------------------------------------------

-- | Type-level lookup of the context type associated with label @l@ in row @ctxs@.
type family LookupContext (l :: Symbol) (ctxs :: [Pair Symbol Type]) :: Type where
  LookupContext l ((l ':= c) ': _) = c
  LookupContext l (_ ': rest)      = LookupContext l rest

-- | Retrieve a specific context @c@ labeled @l@ from the soup in $O(1)$ time.
--
-- The compiler plugin synthesizes the literal slot index for @l@ at compile time,
-- ensuring zero dictionary traversal overhead at runtime.
--
-- Example:
--
-- >>> askSoup (Field @"db")
-- >>> askSoup #db
askSoup :: forall l c ctxs. (c ~ LookupContext l ctxs, FieldIndex l ctxs c)
        => Field l -> ReaderSoup ctxs c
askSoup fld = ReaderSoupT (asks (getField fld))

-- | Locally restrict a 'ReaderSoup' computation to a smaller sub-soup @sub@.
--
-- 'filtering' enables clean modularity: a self-contained helper function can specify
-- only the subset of contexts it actually touches. When invoked within an application
-- carrying a larger @super@ row, 'filtering' projects the flat array in $O(K)$ time
-- (where $K = |sub|$) via compile-time synthesized 'SubRow' evidence.
filtering :: forall sub super a. SubRow sub super
          => ReaderSoup sub a -> ReaderSoup super a
filtering (ReaderSoupT (ReaderT act)) =
  ReaderSoupT (ReaderT (act . projectRecord))

--------------------------------------------------------------------------------
-- 3. Single Context Projection (Spoon)
--------------------------------------------------------------------------------

-- | 'Spoon' isolates a single labeled context @l@ from the soup, equipping it with
-- a standard 'MonadReader' instance.
--
-- This bridges the multi-context soup with standard MTL code expecting @MonadReader c@,
-- while retaining the full global environment for downstream calls.
newtype Spoon (ctxs :: [Pair Symbol Type]) (l :: Symbol) a = Spoon
  { unSpoon :: ReaderSoup ctxs a }
  deriving
    ( Functor
    , Applicative
    , Alternative
    , Monad
    , MonadFail
    , MonadPlus
    , MonadIO
    , MonadUnliftIO
    , MonadThrow
    , MonadCatch
    , MonadMask
    )

instance (MonadBase IO (ReaderSoup ctxs)) => MonadBase IO (Spoon ctxs l) where
  liftBase = Spoon . liftBase

instance (MonadBaseControl IO (ReaderSoup ctxs)) => MonadBaseControl IO (Spoon ctxs l) where
  type StM (Spoon ctxs l) a = StM (ReaderSoup ctxs) a
  liftBaseWith f = Spoon $ liftBaseWith $ \runInBase ->
    f (runInBase . unSpoon)
  restoreM = Spoon . restoreM

-- | Expose a standard 'MonadReader' instance for the selected context @l@.
--
-- 'local' modifies only field @l@ in the flat array while leaving all other
-- contexts intact.
instance (c ~ LookupContext l ctxs, FieldIndex l ctxs c) => MonadReader c (Spoon ctxs l) where
  ask = Spoon (askSoup (Field @l))
  local f (Spoon (ReaderSoupT (ReaderT act))) =
    Spoon $ ReaderSoupT $ ReaderT $ \rec ->
      let !old = getField (Field @l) rec
          !new = f old
          !rec' = setField (Field @l) new rec
      in act rec'

-- | Bring forth a single context from the soup to run a 'Spoon' computation.
dipping :: Field l -> Spoon ctxs l a -> ReaderSoup ctxs a
dipping _ = unSpoon

-- | Convert a legacy @ReaderT c IO@ action directly into a 'Spoon'.
rioToSpoon :: forall l c ctxs a. (c ~ ContextFromName l, FieldIndex l ctxs c)
           => ReaderT c IO a -> Spoon ctxs l a
rioToSpoon (ReaderT act) = Spoon $ ReaderSoupT $ ReaderT $ \rec ->
  act (getField (Field @l) rec)

-- | Convert a 'Spoon' action into a 'ReaderT' running inside the outer 'ReaderSoup'.
spoonToReaderT :: forall l c ctxs a. (c ~ ContextFromName l, KnownSymbol l, FieldIndex l ctxs c)
               => Spoon ctxs l a -> ReaderT c (ReaderSoup ctxs) a
spoonToReaderT (Spoon (ReaderSoupT (ReaderT act))) =
  ReaderT $ \v -> ReaderSoupT $ ReaderT $ \rec ->
    act (setField (Field @l) v rec)

--------------------------------------------------------------------------------
-- 4. Third-Party Monad Bridging (SoupContext)
--------------------------------------------------------------------------------

-- | Type family mapping a label symbol to its canonical context type.
--
-- Applications can instantiate this family to establish global naming conventions:
--
-- > type instance ContextFromName "resource" = InternalState
-- > type instance ContextFromName "db"       = ConnectionPool
type family ContextFromName (l :: Symbol) :: Type

-- | Type class identifying monad transformers that can be converted to and from
-- a 'ReaderT' of their context.
class SoupContext c t | c -> t where
  -- | Convert transformer to 'ReaderT'.
  toReaderT   :: Monad m => t m a -> ReaderT c m a
  -- | Reconstruct transformer from 'ReaderT'.
  fromReaderT :: Monad m => ReaderT c m a -> t m a


-- | Constraint required to scoop a Reader-like monad @t@ from context @l@.
type CanBeScoopedIn t ctxs l =
  ( KnownSymbol l
  , FieldIndex l ctxs (ContextFromName l)
  , SoupContext (ContextFromName l) t
  )

-- | Convert an action in a Reader-like monad @t@ into a 'Spoon'.
withSpoon :: forall l ctxs t a. (CanBeScoopedIn t ctxs l)
          => t (ReaderSoup ctxs) a -> Spoon ctxs l a
withSpoon act = Spoon $ ReaderSoupT $ ReaderT $ \rec ->
  let val = getField (Field @l) rec :: ContextFromName l
  in runReaderSoup (runReaderT (toReaderT @(ContextFromName l) act) val) rec

-- | Run a single-context Reader-like monad (such as @ResourceT IO@) inside 'ReaderSoup'.
picking :: forall l ctxs t a. (CanBeScoopedIn t ctxs l)
        => Field l -> t IO a -> ReaderSoup ctxs a
picking lbl = dipping lbl . rioToSpoon @l . toReaderT @(ContextFromName l)

-- | Run a Reader-like monad over the whole 'ReaderSoup' (preserving access to all contexts).
scooping :: (CanBeScoopedIn t ctxs l)
         => Field l -> t (ReaderSoup ctxs) a -> ReaderSoup ctxs a
scooping lbl act = dipping lbl (withSpoon act)

-- | The dual of 'scooping': lift a 'ReaderSoup' action into the target monad @t@.
pouring :: forall l ctxs t a. (CanBeScoopedIn t ctxs l)
        => Field l -> ReaderSoup ctxs a -> t (ReaderSoup ctxs) a
pouring _ act = fromReaderT $ spoonToReaderT (Spoon act :: Spoon ctxs l a)

--------------------------------------------------------------------------------
-- 5. Modular Context Peeling & Runner Composition
--------------------------------------------------------------------------------

-- | Splits the first field off a contiguous 'Record'.
splitRecordHead :: Record ((n ':= a) ': rest) -> (a, Record rest)
splitRecordHead (RowRep (Rep _ v)) =
  let !h = unsafeCoerce (indexSmallArray v 0)
      !tl = drop 1 (toList v)
  in (h, RowRep (productRep tl))

-- | Conses a field onto the front of a 'Record'.
consRecord :: forall n a rest. Field n -> a -> Record rest -> Record ((n ':= a) ': rest)
consRecord _ val (RowRep (Rep _ v)) =
  RowRep (productRep (unsafeCoerce val : toList v))

-- | Extract a 'ReaderT' of the first context from the soup, leaving the remaining toppings.
pickTopping :: forall l c rest a.
               ReaderSoup ((l ':= c) ': rest) a
            -> ReaderT c (ReaderSoup rest) a
pickTopping (ReaderSoupT (ReaderT actInSoup)) =
  ReaderT $ \ctx1 -> ReaderSoupT $ ReaderT $ \restCtxs ->
    actInSoup (consRecord (Field @l) ctx1 restCtxs)

-- | Consume the head context @c@ from the soup, leaving a smaller soup of remaining contexts.
eatTopping :: forall l c rest a.
              ReaderSoup ((l ':= c) ': rest) a
           -> c
           -> ReaderSoup rest a
eatTopping soup c = runReaderT (pickTopping soup) c

-- | When all contexts have been consumed, finish the broth by executing the empty record in 'IO'.
finishBroth :: ReaderSoup '[] a -> IO a
finishBroth (ReaderSoupT (ReaderT act)) = act emptyRecord

-- | Encapsulates a runner function capable of executing a monad transformer @t@.
newtype ContextRunner t m = ContextRunner
  { runContext :: forall r. t m r -> m r }

-- | Class for peeling contexts iteratively using an extensible record of 'ContextRunner's.
class ArgsForSoupConsumption args where
  -- | Maps runner arguments to the corresponding context row.
  type ContextsFromArgs args :: [Pair Symbol Type]
  -- | Iteratively consume and execute contexts until 'finishBroth' is reached.
  consumeSoup :: Record args -> ReaderSoup (ContextsFromArgs args) a -> IO a

instance ArgsForSoupConsumption '[] where
  type ContextsFromArgs '[] = '[]
  consumeSoup _ = finishBroth

instance ( KnownSymbol l
         , SoupContext (ContextFromName l) t
         , ArgsForSoupConsumption rest
         , m ~ ReaderSoup (ContextsFromArgs rest)
         ) => ArgsForSoupConsumption ((l ':= ContextRunner t m) ': rest) where
  type ContextsFromArgs ((l ':= ContextRunner t m) ': rest) =
    (l ':= ContextFromName l) ': ContextsFromArgs rest
  consumeSoup runnerRec soup =
    let (!runner, !restRunners) = splitRecordHead runnerRec
    in consumeSoup restRunners (runContext runner (fromReaderT (pickTopping soup)))
