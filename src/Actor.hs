module Actor where

import Level
import Monster
import State

data Actor = AMonster Int  -- offset in monster list
           | APlayer
  deriving (Show, Eq)

getActor :: State -> Actor -> Movable
getActor (State { slevel = lvl, splayer = p }) a =
  case a of
    AMonster n -> lmonsters lvl !! n
    APlayer    -> p

updateActor :: (Movable -> Movable) ->        -- the update
               (Movable -> State -> IO a) ->  -- continuation
               Actor ->                       -- who to update
               State -> IO a                  -- transformed continuation
updateActor f k (AMonster n) state@(State { slevel = lvl, splayer = p }) =
  let (m,ms) = updateMonster f n (lmonsters lvl)
  in  k m (updateLevel (updateMonsters (const ms)) state)
updateActor f k APlayer      state@(State { slevel = lvl, splayer = p }) =
  k p (updatePlayer f state)

updateMonster :: (Monster -> Monster) -> Int -> [Monster] ->
                 (Monster, [Monster])
updateMonster f n ms =
  case splitAt n ms of
    (pre, x : post) -> let m = f x
                           mtimeChanged = mtime x /= mtime m
                       in (m, if mtimeChanged then snd (insertMonster m (pre ++ post))
                                              else pre ++ [m] ++ post)
    xs              -> error "updateMonster"
