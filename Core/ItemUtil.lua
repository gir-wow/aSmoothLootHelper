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
