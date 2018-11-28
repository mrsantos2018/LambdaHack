{-# LANGUAGE DeriveGeneric, GeneralizedNewtypeDeriving, TupleSections #-}
-- | Weapons, treasure and all the other items in the game.
module Game.LambdaHack.Common.Item
  ( ItemId, Item(..), ItemIdentity(..)
  , ItemKindIx, ItemDisco(..), ItemFull(..), ItemFullKit
  , DiscoveryKind, DiscoveryAspect, ItemIxMap, Benefit(..), DiscoveryBenefit
  , ItemTimer, ItemQuant, ItemBag, ItemDict
  , itemToFull6, aspectRecordFull
  , strongestSlot, hasCharge, strongestMelee, unknownMeleeBonus, tmpMeleeBonus
#ifdef EXPOSE_INTERNAL
    -- * Internal operations
  , valueAtEqpSlot, unknownAspect
#endif
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import           Data.Binary
import qualified Data.EnumMap.Strict as EM
import qualified Data.EnumSet as ES
import           Data.Hashable (Hashable)
import qualified Data.Ix as Ix
import qualified Data.Ord as Ord
import           GHC.Generics (Generic)

import           Game.LambdaHack.Common.Ability (EqpSlot (..))
import qualified Game.LambdaHack.Common.Ability as Ability
import qualified Game.LambdaHack.Common.Dice as Dice
import           Game.LambdaHack.Common.Flavour
import qualified Game.LambdaHack.Common.ItemAspect as IA
import           Game.LambdaHack.Common.Kind
import           Game.LambdaHack.Common.Misc
import           Game.LambdaHack.Common.Time
import qualified Game.LambdaHack.Content.ItemKind as IK

-- | A unique identifier of an item in the dungeon.
newtype ItemId = ItemId Int
  deriving (Show, Eq, Ord, Enum, Binary)

-- | Game items in actor possesion or strewn around the dungeon.
-- The information contained in this time is available to the player
-- from the moment the item is first seen and is never mutated.
--
-- Some items are not created identified (@IdentityCovered@).
-- Then they are presented as having a template kind that is really
-- not their own, though usually close. Full kind information about
-- item's kind is available through the @ItemKindIx@ index once the item
-- is identified and full information about the value of item's aspect record
-- is available elsewhere (both @IdentityObvious@ and @IdentityCovered@
-- items may or may not need identification of their aspect record).
data Item = Item
  { jkind    :: ItemIdentity  -- ^ the kind of the item, or an indiretion
  , jfid     :: Maybe FactionId
                              -- ^ the faction that created the item, if any
  , jflavour :: Flavour       -- ^ flavour, always the real one, not hidden;
                              --   people may not recognize shape, but they
                              --   remember colour and old vs fancy look
  }
  deriving (Show, Eq, Generic)

instance Hashable Item

instance Binary Item

-- | Either the explicit obvious kind of the item or the kind it's hidden under,
-- with the details covered under the index indirection.
data ItemIdentity =
    IdentityObvious (ContentId IK.ItemKind)
  | IdentityCovered ItemKindIx (ContentId IK.ItemKind)
  deriving (Show, Eq, Generic)

instance Hashable ItemIdentity

instance Binary ItemIdentity

-- | The map of item ids to item aspect reocrd. The full map is known
-- by the server.
type DiscoveryAspect = EM.EnumMap ItemId IA.AspectRecord

-- | An index of the kind identifier of an item. Clients have partial knowledge
-- how these idexes map to kind ids. They gain knowledge by identifying items.
-- The indexes and kind identifiers are 1-1.
newtype ItemKindIx = ItemKindIx Word16
  deriving (Show, Eq, Ord, Enum, Ix.Ix, Hashable, Binary)

-- | The secret part of the information about an item. If a faction
-- knows the aspect record of the item, this is the complete secret information.
-- Items that don't need second identification (the @kmConst@ flag is set)
-- may be identified or not and both cases are OK (their display flavour
-- will differ and that may be the point).
--
-- The @itemAspect@ accessor it to be used unconditionally only on the server
-- where it's guaranteed to be safe.
data ItemDisco =
    ItemDiscoFull {itemAspect :: IA.AspectRecord}
  | ItemDiscoMean IA.KindMean
 deriving (Show, Eq, Ord)

-- No speedup from making fields non-strict.
-- | Full information about an item.
data ItemFull = ItemFull
  { itemBase    :: Item
  , itemKindId  :: ContentId IK.ItemKind
  , itemKind    :: IK.ItemKind
  , itemDisco   :: ItemDisco
  , itemSuspect :: Bool
  }
  deriving Show

type ItemFullKit = (ItemFull, ItemQuant)

-- | The map of item kind indexes to item kind ids.
-- The full map, as known by the server, is 1-1.
-- Because it's sparse and changes, we don't represent it as an (unboxed)
-- vector, until it becomes a bottleneck (if ever, likely on JS, where only
-- vectors are fast).
type DiscoveryKind = EM.EnumMap ItemKindIx (ContentId IK.ItemKind)

-- | The map of item kind indexes to identifiers of items that have that kind.
-- Used to update data about items when their kinds become known, e.g.,
-- AI item use benefit data.
type ItemIxMap = EM.EnumMap ItemKindIx (ES.EnumSet ItemId)

-- | Fields are intentionally kept non-strict, because they are recomputed
-- often, but not used every time. The fields are, in order:
-- 1. whether the item should be kept in equipment (not in pack nor stash)
-- 2. the total benefit from picking the item up (to use or to put in equipment)
-- 3. the benefit of applying the item to self
-- 4. the (usually negative, for him) value of hitting a foe in melee with it
-- 5. the (usually negative, for him) value of flinging the item at an opponent
data Benefit = Benefit
  { benInEqp  :: ~Bool
  , benPickup :: ~Double
  , benApply  :: ~Double
  , benMelee  :: ~Double
  , benFling  :: ~Double
  }
  deriving (Show, Generic)

instance Binary Benefit

type DiscoveryBenefit = EM.EnumMap ItemId Benefit

type ItemTimer = [Time]

-- | Number of items in a bag, together with recharging timer, in case of
-- items that need recharging, exists only temporarily or auto-activate
-- at regular intervals.
type ItemQuant = (Int, ItemTimer)

-- | A bag of items, e.g., one of the stores of an actor or the items
-- on a particular floor position or embedded in a particular map tile.
type ItemBag = EM.EnumMap ItemId ItemQuant

-- | All items in the dungeon (including in actor inventories),
-- indexed by item identifier.
type ItemDict = EM.EnumMap ItemId Item

itemToFull6 :: COps -> DiscoveryKind -> DiscoveryAspect -> ItemId -> Item
            -> ItemFull
itemToFull6 COps{coitem, coItemSpeedup} discoKind discoAspect iid itemBase =
  let (itemKindId, itemSuspect) = case jkind itemBase of
        IdentityObvious ik -> (ik, False)
        IdentityCovered ix ik ->
          maybe (ik, True) (, False) $ ix `EM.lookup` discoKind
      itemKind = okind coitem itemKindId
      km = IA.getKindMean itemKindId coItemSpeedup
      -- If the kind is not identified, we know nothing about the real
      -- aspect record, so we at least assume they are variable.
      itemAspectMean | itemSuspect = km {IA.kmConst = False}
                     | otherwise = km
      itemDisco = case EM.lookup iid discoAspect of
        Just itemAspect -> ItemDiscoFull itemAspect
        Nothing -> ItemDiscoMean itemAspectMean
  in ItemFull {..}

aspectRecordFull :: ItemFull -> IA.AspectRecord
aspectRecordFull itemFull =
  case itemDisco itemFull of
    ItemDiscoFull itemAspect -> itemAspect
    ItemDiscoMean itemAspectMean -> IA.kmMean itemAspectMean

-- This ignores items that don't go into equipment, as determined in @inEqp@.
-- They are removed from equipment elsewhere via @harmful@.
strongestSlot :: DiscoveryBenefit -> Ability.EqpSlot -> [(ItemId, ItemFullKit)]
              -> [(Int, (ItemId, ItemFullKit))]
strongestSlot discoBenefit eqpSlot is =
  let f (iid, (itemFull, kit)) =
        let Benefit{benInEqp, benPickup} = discoBenefit EM.! iid
        in if not benInEqp
           then Nothing
           else Just $
             let ben = if eqpSlot == Ability.EqpSlotWeapon
                       -- For equipping/unequipping a weapon we take into
                       -- account not only melee damage, but also aspects, etc.
                       then ceiling benPickup
                       else valueAtEqpSlot eqpSlot $ aspectRecordFull itemFull
             in (ben, (iid, (itemFull, kit)))
  in sortBy (flip $ Ord.comparing fst) $ mapMaybe f is

valueAtEqpSlot :: EqpSlot -> IA.AspectRecord -> Int
valueAtEqpSlot eqpSlot arItem@IA.AspectRecord{..} =
  case eqpSlot of
    EqpSlotMove -> Ability.getSk Ability.SkMove aSkills
    EqpSlotMelee -> Ability.getSk Ability.SkMelee aSkills
    EqpSlotDisplace -> Ability.getSk Ability.SkDisplace aSkills
    EqpSlotAlter -> Ability.getSk Ability.SkAlter aSkills
    EqpSlotWait -> Ability.getSk Ability.SkWait aSkills
    EqpSlotMoveItem -> Ability.getSk Ability.SkMoveItem aSkills
    EqpSlotProject -> Ability.getSk Ability.SkProject aSkills
    EqpSlotApply -> Ability.getSk Ability.SkApply aSkills
    EqpSlotSwimming -> Ability.getSk Ability.SkSwimming aSkills
    EqpSlotFlying -> Ability.getSk Ability.SkFlying aSkills
    EqpSlotHurtMelee -> Ability.getSk Ability.SkHurtMelee aSkills
    EqpSlotArmorMelee -> Ability.getSk Ability.SkArmorMelee aSkills
    EqpSlotArmorRanged -> Ability.getSk Ability.SkArmorRanged aSkills
    EqpSlotMaxHP -> Ability.getSk Ability.SkMaxHP aSkills
    EqpSlotSpeed -> Ability.getSk Ability.SkSpeed aSkills
    EqpSlotSight -> Ability.getSk Ability.SkSight aSkills
    EqpSlotShine -> Ability.getSk Ability.SkShine aSkills
    EqpSlotMiscBonus ->
      aTimeout  -- usually better items have longer timeout
      + Ability.getSk Ability.SkMaxCalm aSkills
      + Ability.getSk Ability.SkSmell aSkills
      + Ability.getSk Ability.SkNocto aSkills
          -- powerful, but hard to boost over aSight
    EqpSlotWeapon -> error $ "" `showFailure` arItem  -- sum of all benefits

hasCharge :: Time -> ItemFull -> ItemQuant -> Bool
hasCharge localTime itemFull (itemK, itemTimer) =
  let timeout = IA.aTimeout $ aspectRecordFull itemFull
      timeoutTurns = timeDeltaScale (Delta timeTurn) timeout
      charging startT = timeShift startT timeoutTurns > localTime
      it1 = filter charging itemTimer
  in length it1 < itemK

strongestMelee :: Maybe DiscoveryBenefit -> Time
               -> [(ItemId, ItemFullKit)]
               -> [(Double, (ItemId, ItemFullKit))]
strongestMelee _ _ [] = []
strongestMelee mdiscoBenefit localTime kitAss =
  -- For fighting, as opposed to equipping, we value weapon only for
  -- its raw damage and harming effects and at this very moment only,
  -- not in the future. Hehce, we exclude discharged weapons.
  let f (iid, (itemFull, kit)) =
        let rawDmg = IK.damageUsefulness $ itemKind itemFull
            knownOrConstantAspects = case itemDisco itemFull of
              ItemDiscoMean IA.KindMean{kmConst} -> kmConst
              ItemDiscoFull{} -> True
            unIDedBonus | knownOrConstantAspects
                          || isNothing mdiscoBenefit = 0
                        | otherwise = 1000  -- == exceptionally strong weapon
            totalValue = case mdiscoBenefit of
              Just discoBenefit ->
                let Benefit{benMelee} = discoBenefit EM.! iid
                in - benMelee + unIDedBonus
              Nothing -> rawDmg  -- special case: not interested about ID
        in ( if hasCharge localTime itemFull kit
             then totalValue
             else -100000
           , (iid, (itemFull, kit)) )
  -- We can't filter out weapons that are not harmful to victim
  -- (@benMelee >= 0), because actors use them if nothing else available,
  -- e.g., geysers, bees. This is intended and fun.
  in sortBy (flip $ Ord.comparing fst)
     $ filter ((> -100000) . fst) $ map f kitAss

unknownAspect :: (IK.Aspect -> [Dice.Dice]) -> ItemFull -> Bool
unknownAspect f ItemFull{itemKind=IK.ItemKind{iaspects}, ..} =
  case itemDisco of
    ItemDiscoMean IA.KindMean{kmConst} ->
      let unknown x = let (minD, maxD) = Dice.infsupDice x
                      in minD /= maxD
      in itemSuspect || not kmConst && or (concatMap (map unknown . f) iaspects)
    ItemDiscoFull{} -> False  -- all known

-- We assume @AbHurtMelee@ never appears inside @Odds@. If it does,
-- not much harm.
unknownMeleeBonus :: [ItemFull] -> Bool
unknownMeleeBonus =
  let p (IK.AddSkill Ability.SkHurtMelee k) = [k]
      p _ = []
      f itemFull b = b || unknownAspect p itemFull
  in foldr f False

tmpMeleeBonus :: [ItemFullKit] -> Int
tmpMeleeBonus kitAss =
  let f (itemFull, (itemK, _)) k =
        let arItem = aspectRecordFull itemFull
        in if IA.looksLikeCondition arItem
           then k + itemK * IA.getSkill Ability.SkHurtMelee arItem
           else k
  in foldr f 0 kitAss
