local _, SLH = ...
SLH.ItemUtil = {}

local ItemUtil = SLH.ItemUtil

------------------------------------------------------------------------
-- Extract the numeric itemID from an item link string.
-- Item links look like: |cff...|Hitem:12345:...|h[Name]|h|r
------------------------------------------------------------------------
function ItemUtil:GetItemID(itemLink)
    if not itemLink then return nil end
    local id = itemLink:match("item:(%d+)")
    return id and tonumber(id) or nil
end

------------------------------------------------------------------------
-- Return itemLevel for a given item link via GetItemInfo.
-- Returns nil if the item data is not yet cached by the client.
------------------------------------------------------------------------
function ItemUtil:GetItemLevel(itemLink)
    if not itemLink then return nil end
    local _, _, _, itemLevel = GetItemInfo(itemLink)
    return itemLevel
end

------------------------------------------------------------------------
-- Return item quality (rarity) for a given item link.
-- 0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic, 5=Legendary
------------------------------------------------------------------------
function ItemUtil:GetItemQuality(itemLink)
    if not itemLink then return nil end
    local _, _, quality = GetItemInfo(itemLink)
    return quality
end

------------------------------------------------------------------------
-- Return a formatted name string for chat output.
------------------------------------------------------------------------
function ItemUtil:GetDisplayName(itemLink)
    if not itemLink then return "Unknown" end
    local name = GetItemInfo(itemLink)
    return name or itemLink
end

------------------------------------------------------------------------
-- Return the item subtype string (e.g. "Plate", "Cloth", "Leather",
-- "Mail") for equippable armor, or nil for non-armor items.
------------------------------------------------------------------------
function ItemUtil:GetArmorSubtype(itemLink)
    if not itemLink then return nil end
    -- GetItemInfo returns: name, link, quality, ilvl, minLevel,
    --   itemType, itemSubType, stackCount, equipLoc, ...
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if itemType == "Armor" then
        return itemSubType   -- "Cloth", "Leather", "Mail", "Plate", "Miscellaneous", "Shields", ...
    end
    return nil
end

------------------------------------------------------------------------
-- Map class token → primary armor subtype.
------------------------------------------------------------------------
local CLASS_ARMOR = {
    DEATHKNIGHT = "Plate",
    DRUID       = "Leather",
    HUNTER      = "Mail",
    MAGE        = "Cloth",
    MONK        = "Leather",
    PALADIN     = "Plate",
    PRIEST      = "Cloth",
    ROGUE       = "Leather",
    SHAMAN      = "Mail",
    WARLOCK     = "Cloth",
    WARRIOR     = "Plate",
}

function ItemUtil:GetPlayerArmorType()
    local _, classToken = UnitClass("player")
    return CLASS_ARMOR[classToken]
end

------------------------------------------------------------------------
-- Primary-stat detection
--
-- Pure classes never change primary stat regardless of spec:
--   Strength — Death Knight, Warrior
--   Agility  — Rogue, Hunter
--   Intellect — Mage, Priest, Warlock
--
-- Hybrid classes depend on the active spec:
--   Paladin    Holy=Int,  Protection=Str, Retribution=Str
--   Druid      Balance=Int, Feral=Agi, Guardian=Agi, Restoration=Int
--   Shaman     Elemental=Int, Enhancement=Agi, Restoration=Int
--   Monk       Brewmaster=Agi, Mistweaver=Int, Windwalker=Agi
------------------------------------------------------------------------
local PURE_CLASS_STAT = {
    DEATHKNIGHT = "STRENGTH",
    WARRIOR     = "STRENGTH",
    ROGUE       = "AGILITY",
    HUNTER      = "AGILITY",
    MAGE        = "INTELLECT",
    PRIEST      = "INTELLECT",
    WARLOCK     = "INTELLECT",
}

-- Hybrid spec names → primary stat (English client; MoP spec names are stable)
local HYBRID_SPEC_STAT = {
    -- Paladin
    ["Holy"]         = "INTELLECT",
    ["Protection"]   = "STRENGTH",
    ["Retribution"]  = "STRENGTH",
    -- Druid
    ["Balance"]      = "INTELLECT",
    ["Feral"]        = "AGILITY",
    ["Guardian"]     = "AGILITY",
    -- Shaman
    ["Elemental"]    = "INTELLECT",
    ["Enhancement"]  = "AGILITY",
    -- Monk
    ["Brewmaster"]   = "AGILITY",
    ["Mistweaver"]   = "INTELLECT",
    ["Windwalker"]   = "AGILITY",
    -- Restoration covers both Druid and Shaman
    ["Restoration"]  = "INTELLECT",
}

------------------------------------------------------------------------
-- Return the primary stat the current player/spec wants:
-- "STRENGTH", "AGILITY", or "INTELLECT".  Returns nil if undetermined.
------------------------------------------------------------------------
function ItemUtil:GetPlayerExpectedPrimaryStat()
    local _, classToken = UnitClass("player")
    if PURE_CLASS_STAT[classToken] then
        return PURE_CLASS_STAT[classToken]
    end
    -- Hybrid: resolve via active spec name
    local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
                    or GetSpecialization
    local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
                    or GetSpecializationInfo
    if not getSpec then return nil end
    local idx = getSpec()
    if not idx or idx == 0 then return nil end
    local _, specName = getInfo(idx)
    return specName and HYBRID_SPEC_STAT[specName] or nil
end

------------------------------------------------------------------------
-- Return the dominant primary stat of an item: "STRENGTH", "AGILITY",
-- "INTELLECT", or nil if the item has no primary stat (e.g. a ring
-- without Str/Agi/Int, or item data not yet cached).
------------------------------------------------------------------------
function ItemUtil:GetItemPrimaryStat(itemLink)
    if not itemLink or not GetItemStats then return nil end
    local stats = GetItemStats(itemLink)
    if not stats then return nil end
    local str = stats["ITEM_MOD_STRENGTH_SHORT"]  or 0
    local agi = stats["ITEM_MOD_AGILITY_SHORT"]   or 0
    local int = stats["ITEM_MOD_INTELLECT_SHORT"]  or 0
    if str == 0 and agi == 0 and int == 0 then return nil end
    if str >= agi and str >= int then return "STRENGTH"  end
    if agi >= int               then return "AGILITY"   end
    return "INTELLECT"
end

------------------------------------------------------------------------
-- Returns true if the item has a clear primary stat that is wrong for
-- the player's current class/spec.  Only triggers for items that
-- actually have a primary stat (weapons and armor pieces); neutral
-- items (rings without Str/Agi/Int, trinkets, cloaks) return false.
------------------------------------------------------------------------
function ItemUtil:IsWrongPrimaryStatForPlayer(itemLink)
    local itemStat   = self:GetItemPrimaryStat(itemLink)
    if not itemStat then return false end          -- no primary stat, neutral
    local expected   = self:GetPlayerExpectedPrimaryStat()
    if not expected  then return false end          -- can't determine, don't filter
    return itemStat ~= expected
end

------------------------------------------------------------------------
-- Returns true if the item is equippable armor that does NOT match
-- the player's primary armor type.  Non-armor items (weapons, rings,
-- trinkets, cloaks, misc, shields) return false — they are neutral.
------------------------------------------------------------------------
function ItemUtil:IsOffArmorType(itemLink)
    local subType = self:GetArmorSubtype(itemLink)
    if not subType then return false end
    -- "Miscellaneous", "Shields", "Cosmetic" etc. are neutral
    if subType ~= "Cloth" and subType ~= "Leather"
       and subType ~= "Mail" and subType ~= "Plate" then
        return false
    end
    return subType ~= self:GetPlayerArmorType()
end

------------------------------------------------------------------------
-- Map GetItemInfo equipLoc strings to inventory slot IDs.
-- Returns a list of slot IDs the item can go into.
------------------------------------------------------------------------
local EQUIP_LOC_TO_SLOTS = {
    INVTYPE_HEAD           = { 1 },
    INVTYPE_NECK           = { 2 },
    INVTYPE_SHOULDER       = { 3 },
    INVTYPE_BODY           = { 4 },
    INVTYPE_CHEST          = { 5 },
    INVTYPE_ROBE           = { 5 },
    INVTYPE_WAIST          = { 6 },
    INVTYPE_LEGS           = { 7 },
    INVTYPE_FEET           = { 8 },
    INVTYPE_WRIST          = { 9 },
    INVTYPE_HAND           = { 10 },
    INVTYPE_FINGER         = { 11, 12 },
    INVTYPE_TRINKET        = { 13, 14 },
    INVTYPE_CLOAK          = { 15 },
    INVTYPE_WEAPON         = { 16, 17 },
    INVTYPE_SHIELD         = { 17 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_HOLDABLE       = { 17 },
    INVTYPE_RANGED         = { 16 },
    INVTYPE_RANGEDRIGHT    = { 16 },
    INVTYPE_THROWN         = { 16 },
    INVTYPE_TABARD         = { 19 },
}

function ItemUtil:GetEquipSlots(itemLink)
    if not itemLink then return nil end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" then return nil end
    return EQUIP_LOC_TO_SLOTS[equipLoc]
end

------------------------------------------------------------------------
-- Compare the item's ilvl to what the player has equipped in the
-- same slot(s). Returns true if ALL matching equipped slots have
-- a higher ilvl than the drop (i.e. the drop is a downgrade).
-- Returns false if any slot would be an upgrade, or if we can't
-- determine the slots.
------------------------------------------------------------------------
function ItemUtil:IsEquippedBetter(itemLink)
    local slots = self:GetEquipSlots(itemLink)
    if not slots then return false end

    local _, _, _, dropIlvl = GetItemInfo(itemLink)
    if not dropIlvl then return false end

    for _, slotID in ipairs(slots) do
        local eqLink = GetInventoryItemLink("player", slotID)
        if not eqLink then
            return false   -- empty slot = upgrade
        end
        local _, _, _, eqIlvl = GetItemInfo(eqLink)
        if not eqIlvl or eqIlvl <= dropIlvl then
            return false   -- equipped is same or worse = potential upgrade
        end
    end
    return true   -- all slots have better gear
end

------------------------------------------------------------------------
-- Pawn integration: check if Pawn considers an item an upgrade.
-- Returns:
--   true   → Pawn says it IS an upgrade (don't auto-greed)
--   false  → Pawn says it is NOT an upgrade (safe to auto-greed)
--   nil    → Pawn not available or can't determine
------------------------------------------------------------------------
function ItemUtil:PawnIsUpgrade(itemLink)
    if not PawnIsReady or not PawnIsReady() then return nil end
    if not PawnGetItemData then return nil end
    if not PawnIsItemAnUpgrade then return nil end

    local item = PawnGetItemData(itemLink)
    if not item then return nil end

    local upgradeInfo = PawnIsItemAnUpgrade(item)
    if upgradeInfo then
        return true    -- Pawn says upgrade
    else
        return false   -- Pawn says not an upgrade
    end
end

------------------------------------------------------------------------
-- Returns true if the item is a lockbox (Container > Lockbox subtype,
-- or name contains "lockbox" as a locale-independent fallback).
------------------------------------------------------------------------
function ItemUtil:IsLockbox(itemLink)
    if not itemLink then return false end
    local name, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if itemType == "Container" and itemSubType == "Lockbox" then
        return true
    end
    -- Fallback: name-based check (covers "Strong Junkbox", "Gnomish Lock Box", etc.)
    if name and name:lower():find("lockbox") then
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Detect which inventory slot a tier token represents by matching
-- keywords in the item name.  Returns a slot ID (1-based), or nil if
-- the slot cannot be determined.
--
-- MoP tier tokens and Celestial tokens always name the slot first:
--   "Crown/Helm/Hood/…"        → head   (1)
--   "Spaulders/Mantle/…"       → shoulders (3)
--   "Chest/Robe/Hauberk/…"     → chest  (5)
--   "Leggings/Legguards/Kilt…" → legs   (7)
--   "Gloves/Gauntlets/…"       → hands  (10)
------------------------------------------------------------------------
local TOKEN_SLOT_KEYWORDS = {
    { pattern = "crown",       slot = 1  },
    { pattern = "helm",        slot = 1  },
    { pattern = "hood",        slot = 1  },
    { pattern = "headguard",   slot = 1  },
    { pattern = "headpiece",   slot = 1  },
    { pattern = "coif",        slot = 1  },
    { pattern = "circlet",     slot = 1  },
    { pattern = "cover",       slot = 1  },
    { pattern = "cap",         slot = 1  },
    { pattern = "spaulder",    slot = 3  },
    { pattern = "shoulder",    slot = 3  },
    { pattern = "mantle",      slot = 3  },
    { pattern = "pauldron",    slot = 3  },
    { pattern = "chest",       slot = 5  },
    { pattern = "robe",        slot = 5  },
    { pattern = "tunic",       slot = 5  },
    { pattern = "breastplate", slot = 5  },
    { pattern = "hauberk",     slot = 5  },
    { pattern = "vest",        slot = 5  },
    { pattern = "leg",         slot = 7  },
    { pattern = "breeche",     slot = 7  },
    { pattern = "kilt",        slot = 7  },
    { pattern = "trouser",     slot = 7  },
    { pattern = "glove",       slot = 10 },
    { pattern = "gauntlet",    slot = 10 },
    { pattern = "handguard",   slot = 10 },
    { pattern = "grip",        slot = 10 },
    { pattern = "mitts",       slot = 10 },
    { pattern = "fist",        slot = 10 },
}

function ItemUtil:GetTierTokenSlot(itemLink)
    if not itemLink then return nil end
    local name = GetItemInfo(itemLink)
    if not name then return nil end
    local lower = name:lower()
    for _, entry in ipairs(TOKEN_SLOT_KEYWORDS) do
        if lower:find(entry.pattern, 1, true) then
            return entry.slot
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Returns true when the equipped item in the slot the token represents
-- is more than `delta` ilvl (default 30) ahead of the token's ilvl.
-- Falls back to average equipped ilvl when the slot cannot be detected.
-- Used by the tier-token outgear guard because tokens have no equip
-- slot and cannot use IsSignificantDowngrade directly.
------------------------------------------------------------------------
function ItemUtil:IsTokenSignificantDowngrade(itemLink, delta)
    delta = delta or 30
    local _, _, _, tokenIlvl = GetItemInfo(itemLink)
    if not tokenIlvl or tokenIlvl == 0 then return false end

    -- Primary path: compare against the specific slot the token covers.
    local slot = self:GetTierTokenSlot(itemLink)
    if slot then
        local eqLink = GetInventoryItemLink("player", slot)
        if not eqLink then return false end   -- slot empty → could be an upgrade
        local _, _, _, eqIlvl = GetItemInfo(eqLink)
        if not eqIlvl then return false end
        local diff = eqIlvl - tokenIlvl
        Debug("  Token slot check: slot=" .. slot
              .. "  equippedIlvl=" .. eqIlvl
              .. "  tokenIlvl=" .. tokenIlvl
              .. "  diff=" .. diff)
        return diff > delta
    end

    -- Fallback: slot keyword not found — compare against average ilvl
    -- across main gear slots (requires ≥8 slots to be confident).
    -- Use delta=0 here too: if average gear is ahead of the token at
    -- all, the player should not be auto-needing it.
    local CHECK_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
    local totalIlvl, count = 0, 0
    for _, slotID in ipairs(CHECK_SLOTS) do
        local eqLink = GetInventoryItemLink("player", slotID)
        if eqLink then
            local _, _, _, eqIlvl = GetItemInfo(eqLink)
            if eqIlvl and eqIlvl > 0 then
                totalIlvl = totalIlvl + eqIlvl
                count     = count + 1
            end
        end
    end
    if count < 8 then return false end
    local avgIlvl = totalIlvl / count
    Debug("  Token avg-ilvl fallback: avg=" .. string.format("%.1f", avgIlvl)
          .. "  tokenIlvl=" .. tokenIlvl)
    return avgIlvl > tokenIlvl
end

------------------------------------------------------------------------
-- Returns true when every slot the item could fill already has gear
-- equipped whose ilvl exceeds the drop's ilvl by more than `delta`
-- (default 30). Used by the BiS guard so a fully-geared player does
-- not auto-need a clearly outclassed BiS item.
-- Returns false if any slot is empty, within range, or data is missing.
------------------------------------------------------------------------
function ItemUtil:IsSignificantDowngrade(itemLink, delta)
    delta = delta or 30
    local slots = self:GetEquipSlots(itemLink)
    if not slots then return false end

    local _, _, _, dropIlvl = GetItemInfo(itemLink)
    if not dropIlvl then return false end

    for _, slotID in ipairs(slots) do
        local eqLink = GetInventoryItemLink("player", slotID)
        if not eqLink then
            return false   -- empty slot: item could fill it
        end
        local _, _, _, eqIlvl = GetItemInfo(eqLink)
        if not eqIlvl or (eqIlvl - dropIlvl) <= delta then
            return false   -- this slot is within range → allow need
        end
    end
    return true   -- every slot is significantly ahead of the drop
end

------------------------------------------------------------------------
-- Returns true if the player already has the given itemID in their
-- bags (0-4) or equipped (slots 0-18).  Checks exact ID only — no
-- warforged offsets — because for "do I already own this token" we
-- want an exact match.
------------------------------------------------------------------------
function ItemUtil:IsInBagsOrEquipped(itemID)
    if not itemID then return false end
    -- Equipped
    for slot = 0, 18 do
        if GetInventoryItemID("player", slot) == itemID then return true end
    end
    -- Bags
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemID   = (C_Container and C_Container.GetContainerItemID)   or GetContainerItemID
    if getNumSlots and getItemID then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, (getNumSlots(bag) or 0) do
                if getItemID(bag, slot) == itemID then return true end
            end
        end
    end
    return false
end

------------------------------------------------------------------------
-- Tier token detection
--
-- In MoP, tier tokens are Miscellaneous/Junk items whose name ends with
-- "Protector", "Conqueror", or "Vanquisher".  Each token type maps to a
-- fixed set of classes across all MoP tiers (T14 Mogu'shan/HoF/TES,
-- T15 ToT, T16 SoO):
--
--   PROTECTOR  → Warrior, Hunter, Shaman, Monk
--   CONQUEROR  → Paladin, Priest, Warlock
--   VANQUISHER → Death Knight, Druid, Mage, Rogue
------------------------------------------------------------------------
local TIER_TOKEN_SUFFIXES = {
    ["Protector"] = "PROTECTOR",
    ["Conqueror"]  = "CONQUEROR",
    ["Vanquisher"] = "VANQUISHER",
}

local CLASS_TO_TOKEN_TYPE = {
    WARRIOR     = "PROTECTOR",
    HUNTER      = "PROTECTOR",
    SHAMAN      = "PROTECTOR",
    MONK        = "PROTECTOR",
    PALADIN     = "CONQUEROR",
    PRIEST      = "CONQUEROR",
    WARLOCK     = "CONQUEROR",
    DEATHKNIGHT = "VANQUISHER",
    DRUID       = "VANQUISHER",
    MAGE        = "VANQUISHER",
    ROGUE       = "VANQUISHER",
}

------------------------------------------------------------------------
-- Return "PROTECTOR", "CONQUEROR", or "VANQUISHER" if the item is a
-- MoP tier token, or nil if it is not.
-- Guards:
--   1. Item type must be Miscellaneous/Junk (tokens are not armor).
--   2. The suffix must appear at the END of the name to avoid false
--      positives like "Shield of the Protectorate" matching "Protector".
------------------------------------------------------------------------
function ItemUtil:GetTierTokenType(itemLink)
    if not itemLink then return nil end
    local name, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if not name then return nil end
    -- Tier tokens are typed as Miscellaneous/Junk, not Armor
    if itemType ~= "Miscellaneous" and itemType ~= "Junk" then return nil end
    for suffix, tokenType in pairs(TIER_TOKEN_SUFFIXES) do
        -- Match only when the name ends with the suffix
        if name:sub(-#suffix) == suffix then
            return tokenType
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Returns true if the item is any MoP tier token.
------------------------------------------------------------------------
function ItemUtil:IsTierToken(itemLink)
    return self:GetTierTokenType(itemLink) ~= nil
end

------------------------------------------------------------------------
-- Returns true if the tier token is for the player's class/token group.
------------------------------------------------------------------------
function ItemUtil:IsTierTokenForPlayer(itemLink)
    local tokenType = self:GetTierTokenType(itemLink)
    if not tokenType then return false end
    local _, classToken = UnitClass("player")
    return CLASS_TO_TOKEN_TYPE[classToken] == tokenType
end
