{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module: Chainweb.Miner.Config
-- Copyright: Copyright © 2018 Kadena LLC.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@kadena.io>
-- Stability: experimental
--
-- Mining configuration for a Chainweb node.
--
module Chainweb.Miner.Config
( MiningConfig(..)
, defaultMining
, miningCoordination
, miningInNode
, validateMinerConfig
, CoordinationConfig(..)
, coordinationEnabled
, coordinationMiners
, NodeMiningConfig(..)
, defaultNodeMining
, nodeMiningEnabled
, nodeMiner
, nodeTestMiners
, MinerCount(..)
, invalidMiner
) where

import Configuration.Utils

import Control.Lens (lens, view)
import Control.Monad (when)
import Control.Monad.Except (throwError)
import Control.Monad.Writer (tell)

import qualified Data.Set as S

import GHC.Generics (Generic)

import Numeric.Natural (Natural)

import Pact.Types.Term (mkKeySet)

-- internal modules

import Chainweb.Miner.Pact (Miner(..), MinerKeys(..), minerId)
import Chainweb.Time (Seconds)

---

-- | Strictly for testing.
--
newtype MinerCount = MinerCount { _minerCount :: Natural }
    deriving stock (Eq, Ord, Show)
    deriving newtype (FromJSON)

validateMinerConfig :: ConfigValidation MiningConfig []
validateMinerConfig c = do
    when (_nodeMiningEnabled nmc) $ tell
        [ "In-node mining is enabled. This should only be used for testing"
        , "In order to use in-node mining, mining-coordination must be enabled, too"
        ]
    when (_nodeMiningEnabled nmc && not (_coordinationEnabled cc))
        $ throwError "In-node mining is enabled but mining coordination is disabled"
    when (_nodeMiningEnabled nmc && view minerId (_nodeMiner nmc) == "")
        $ throwError "In-node Mining is enabled but no miner id is configured"
  where
    nmc = _miningInNode c
    cc = _miningCoordination c

-- | Full configuration for Mining.
--
data MiningConfig = MiningConfig
    { _miningCoordination :: !CoordinationConfig
    , _miningInNode :: !NodeMiningConfig }
    deriving stock (Eq, Show)

miningCoordination :: Lens' MiningConfig CoordinationConfig
miningCoordination = lens _miningCoordination (\m c -> m { _miningCoordination = c })

miningInNode :: Lens' MiningConfig NodeMiningConfig
miningInNode = lens _miningInNode (\m c -> m { _miningInNode = c })

instance ToJSON MiningConfig where
    toJSON o = object
        [ "coordination" .= _miningCoordination o
        , "nodeMining" .= _miningInNode o ]

instance FromJSON (MiningConfig -> MiningConfig) where
    parseJSON = withObject "MiningConfig" $ \o -> id
        <$< miningCoordination %.: "coordination" % o
        <*< miningInNode %.: "nodeMining" % o

defaultMining :: MiningConfig
defaultMining = MiningConfig
    { _miningCoordination = defaultCoordination
    , _miningInNode = defaultNodeMining }

-- | Configuration for Mining Coordination.
data CoordinationConfig = CoordinationConfig
    { _coordinationEnabled :: !Bool
      -- ^ Is mining coordination enabled? If not, the @/mining/@ won't even be
      -- present on the node.
    , _coordinationMiners :: !(S.Set Miner)
      -- ^ This field must contain at least one `Miner` identity in order for
      -- work requests to be made.
    , _coordinationReqLimit :: !Int
      -- ^ The number of @/mining/work/@ requests that can be made to this node
      -- in a 5 minute period.
    , _coordinationUpdateStreamLimit :: !Int
        -- ^ the maximum number of concurrent update streams that is supported
    , _coordinationUpdateStreamTimeout :: !Seconds
        -- ^ the duration that an update stream is kept open in seconds
    } deriving stock (Eq, Show, Generic)

coordinationEnabled :: Lens' CoordinationConfig Bool
coordinationEnabled = lens _coordinationEnabled (\m c -> m { _coordinationEnabled = c })

coordinationLimit :: Lens' CoordinationConfig Int
coordinationLimit = lens _coordinationReqLimit (\m c -> m { _coordinationReqLimit = c })

coordinationMiners :: Lens' CoordinationConfig (S.Set Miner)
coordinationMiners = lens _coordinationMiners (\m c -> m { _coordinationMiners = c })

coordinationUpdateStreamLimit :: Lens' CoordinationConfig Int
coordinationUpdateStreamLimit =
    lens _coordinationUpdateStreamLimit (\m c -> m { _coordinationUpdateStreamLimit = c })

coordinationUpdateStreamTimeout :: Lens' CoordinationConfig Seconds
coordinationUpdateStreamTimeout =
    lens _coordinationUpdateStreamTimeout (\m c -> m { _coordinationUpdateStreamTimeout = c })

instance ToJSON CoordinationConfig where
    toJSON o = object
        [ "enabled" .= _coordinationEnabled o
        , "limit" .= _coordinationReqLimit o
        , "miners" .= _coordinationMiners o
        , "updateStreamLimit" .= _coordinationUpdateStreamLimit o
        , "updateStreamTimeout" .= _coordinationUpdateStreamTimeout o
        ]

instance FromJSON (CoordinationConfig -> CoordinationConfig) where
    parseJSON = withObject "CoordinationConfig" $ \o -> id
        <$< coordinationEnabled ..: "enabled" % o
        <*< coordinationLimit ..: "limit" % o
        <*< coordinationMiners ..: "miners" % o
        <*< coordinationUpdateStreamLimit ..: "updateStreamLimit" % o
        <*< coordinationUpdateStreamTimeout ..: "updateStreamTimeout" % o

defaultCoordination :: CoordinationConfig
defaultCoordination = CoordinationConfig
    { _coordinationEnabled = False
    , _coordinationMiners = mempty
    , _coordinationReqLimit = 1200
    , _coordinationUpdateStreamLimit = 2000
    , _coordinationUpdateStreamTimeout = 240
    }

data NodeMiningConfig = NodeMiningConfig
    { _nodeMiningEnabled :: !Bool
      -- ^ If enabled, this node will mine with a single CPU along with its
      -- other responsibilities.
    , _nodeMiner :: !Miner
      -- ^ If enabled, a `Miner` identity must be supplied in order to assign
      -- mining rewards.
    , _nodeTestMiners :: !MinerCount
      -- ^ Strictly for testing.
    } deriving stock (Eq, Show, Generic)

nodeMiningEnabled :: Lens' NodeMiningConfig Bool
nodeMiningEnabled = lens _nodeMiningEnabled (\m c -> m { _nodeMiningEnabled = c })

nodeMiner :: Lens' NodeMiningConfig Miner
nodeMiner = lens _nodeMiner (\m c -> m { _nodeMiner = c })

nodeTestMiners :: Lens' NodeMiningConfig MinerCount
nodeTestMiners = lens _nodeTestMiners (\m c -> m { _nodeTestMiners = c })

instance ToJSON NodeMiningConfig where
    toJSON o = object
        [ "enabled" .= _nodeMiningEnabled o
        , "miner" .= _nodeMiner o ]

instance FromJSON (NodeMiningConfig -> NodeMiningConfig) where
    parseJSON = withObject "NodeMiningConfig" $ \o -> id
        <$< nodeMiningEnabled ..: "enabled" % o
        <*< nodeMiner ..: "miner" % o
        <*< nodeTestMiners ..: "testMiners" % o

defaultNodeMining :: NodeMiningConfig
defaultNodeMining = NodeMiningConfig
    { _nodeMiningEnabled = False
    , _nodeMiner = invalidMiner
    , _nodeTestMiners = MinerCount 10 }

invalidMiner :: Miner
invalidMiner = Miner "" . MinerKeys $ mkKeySet [] "keys-all"
