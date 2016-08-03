-- | Semantics of requests that are sent to the server.
--
-- See
-- <https://github.com/LambdaHack/LambdaHack/wiki/Client-server-architecture>.
module Game.LambdaHack.Server
  ( -- * Re-exported from "Game.LambdaHack.Server.LoopServer"
    loopSer
    -- * Re-exported from "Game.LambdaHack.Server.Commandline"
  , debugArgs
    -- * Re-exported from "Game.LambdaHack.Server.State"
  , sdebugCli
  ) where

import Prelude ()

import Game.LambdaHack.Server.Commandline
import Game.LambdaHack.Server.LoopM
import Game.LambdaHack.Server.State
