local _, SLH = ...

------------------------------------------------------------------------
-- BisTooltip provider
--
-- Reads from global tables exposed by the Bistooltip addon:
--   Bistooltip_items[itemID]          → array of { class_name, spec_name, slots }
--   Bistooltip_char_equipment[itemID] → 1 (bags) or 2 (equipped), or nil
--   Bistooltip_classes_indexes        → { ["Death knight"] = 1, ... }
--
-- BisTooltip uses class names like "Death knight" and spec names like
-- "Blood tank", "Balance", "Retribution", etc.
------------------------------------------------------------------------

local provider = {}

------------------------------------------------------------------------
-- WoW class token → BisTooltip class name
------------------------------------------------------------------------
local CLASS_TOKEN_TO_NAME = {
    DEATHKNIGHT = "Death knight",
    DRUID       = "Druid",
    HUNTER      = "Hunter",
    MAGE        = "Mage",
    MONK        = "Monk",
    PALADIN     = "Paladin",
    PRIEST      = "Priest",
    ROGUE       = "Rogue",
    SHAMAN      = "Shaman",
    WARLOCK     = "Warlock",
    WARRIOR     = "Warrior",
}

------------------------------------------------------------------------
-- MoP warforged ID offsets (same constants FrogBiS uses)
------------------------------------------------------------------------
local HWF_OFFSET = 543
local NWF_OFFSET = 747

------------------------------------------------------------------------
-- Return the player's BisTooltip-style class name.
------------------------------------------------------------------------
local function GetPlayerClassName()
    local _, classToken = UnitClass("player")
    return CLASS_TOKEN_TO_NAME[classToken]
end

------------------------------------------------------------------------
-- Return the player's current spec name in BisTooltip format.
-- BisTooltip uses short spec names: "Balance", "Blood tank", etc.
------------------------------------------------------------------------
local function GetPlayerSpecName()
    local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
                    or GetSpecialization
    local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
                    or GetSpecializationInfo
    if not getSpec then return nil end
    local idx = getSpec()
    if not idx or idx == 0 then return nil end
    local _, specName = getInfo(idx)
    return specName   -- e.g. "Balance", "Frost", "Retribution"
end

------------------------------------------------------------------------
-- Check if an itemID matches target, accounting for warforged variants.
------------------------------------------------------------------------
local function IsMatchingID(itemID, targetID)
    if itemID == targetID then return true end
    return itemID == targetID + HWF_OFFSET
        or itemID == targetID - HWF_OFFSET
        or itemID == targetID + NWF_OFFSET
        or itemID == targetID - NWF_OFFSET
end

------------------------------------------------------------------------
local function Debug(msg)
    local db = aSmoothLootHelperDB
    if db and db.settings and db.settings.debugMode then
        print("|cff888888[SLH debug]|r " .. msg)
    end
    if SLH.DebugLog then
        SLH.DebugLog:Add(msg)
    end
end

------------------------------------------------------------------------
-- Check whether the given itemID is BiS for the player's current
-- class/spec (or any of their specs if offspec is enabled).
------------------------------------------------------------------------
function provider:IsBiS(itemID)
    if not Bistooltip_items then
        Debug("    [BisTooltip] Bistooltip_items not loaded")
        return false
    end

    local entries = Bistooltip_items[itemID]
    local matchedVariant = nil
    if not entries then
        -- Try warforged variants
        if Bistooltip_items[itemID + HWF_OFFSET] then matchedVariant = itemID + HWF_OFFSET end
        if not matchedVariant and Bistooltip_items[itemID - HWF_OFFSET] then matchedVariant = itemID - HWF_OFFSET end
        if not matchedVariant and Bistooltip_items[itemID + NWF_OFFSET] then matchedVariant = itemID + NWF_OFFSET end
        if not matchedVariant and Bistooltip_items[itemID - NWF_OFFSET] then matchedVariant = itemID - NWF_OFFSET end
        if matchedVariant then
            entries = Bistooltip_items[matchedVariant]
            Debug("    [BisTooltip] item " .. itemID .. " not found directly, matched variant " .. matchedVariant)
        end
    end
    if not entries then
        Debug("    [BisTooltip] item " .. itemID .. " not in BiS database")
        return false
    end

    local className = GetPlayerClassName()
    local specName  = GetPlayerSpecName()
    Debug("    [BisTooltip] class=" .. tostring(className) .. "  spec=" .. tostring(specName))

    if not className then return false end

    local checkOffspec = aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bisOffspecEnabled

    local specList = {}
    for _, entry in ipairs(entries) do
        specList[#specList + 1] = entry.class_name .. "/" .. entry.spec_name
        if entry.class_name == className then
            if checkOffspec then
                Debug("    [BisTooltip] MATCH (offspec): " .. entry.spec_name)
                return true
            end
            if entry.spec_name == specName then
                Debug("    [BisTooltip] MATCH: " .. entry.class_name .. "/" .. entry.spec_name)
                return true
            end
        end
    end
    Debug("    [BisTooltip] No spec match. Item specs: " .. table.concat(specList, ", "))
    return false
end

------------------------------------------------------------------------
-- Check whether the player already owns (equipped or in bags) the item.
-- Uses Bistooltip_char_equipment which is maintained by BisTooltip's
-- equipment watcher.
------------------------------------------------------------------------
function provider:IsCollected(itemID)
    if not Bistooltip_char_equipment then return false end
    if Bistooltip_char_equipment[itemID] then return true end
    -- Check warforged variants
    return (Bistooltip_char_equipment[itemID + HWF_OFFSET] ~= nil)
        or (Bistooltip_char_equipment[itemID - HWF_OFFSET] ~= nil)
        or (Bistooltip_char_equipment[itemID + NWF_OFFSET] ~= nil)
        or (Bistooltip_char_equipment[itemID - NWF_OFFSET] ~= nil)
end

------------------------------------------------------------------------
-- Check whether the item is a normal/lower-difficulty version of a BiS
-- item. BisTooltip's ranked lists inherently include these variants
-- (items ranked 2+), so IsBiS already covers them.
------------------------------------------------------------------------
function provider:IsNormalVersionOfBiS(itemID)
    return self:IsBiS(itemID)
end

------------------------------------------------------------------------
-- Registration: wait for BisTooltip to load, then register.
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, loadedAddon)
    -- BisTooltip's folder is "Bistooltip"
    if loadedAddon == "Bistooltip" then
        if Bistooltip_items or Bistooltip_wowtbc_items then
            SLH.RollManager:RegisterBiSProvider("BisTooltip", provider)
        end
        frame:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Also try registering immediately in case BisTooltip already loaded
if Bistooltip_items or Bistooltip_wowtbc_items then
    SLH.RollManager:RegisterBiSProvider("BisTooltip", provider)
end
