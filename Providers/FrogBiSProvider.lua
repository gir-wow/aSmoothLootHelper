local _, SLH = ...

------------------------------------------------------------------------
-- FrogBiS provider
--
-- Reads from global tables exposed by the FrogBiS addon:
--   FrogBiS_Templates[specName]  → { specName, tier, items = { {slot, id}, ... } }
--   FrogBiS_SpecItems[itemID]    → { specID1, specID2, ... }
--   FrogBiSDB                    → SavedVariables (custom sets, tracked items, etc.)
--
-- FrogBiS uses composite spec names: "Balance Druid", "Blood Death Knight", etc.
------------------------------------------------------------------------

local provider = {}

------------------------------------------------------------------------
-- WoW class token → FrogBiS class name
------------------------------------------------------------------------
local CLASS_TOKEN_TO_NAME = {
    DEATHKNIGHT = "Death Knight",
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
-- MoP warforged ID offsets
------------------------------------------------------------------------
local HWF_OFFSET = 543
local NWF_OFFSET = 747

------------------------------------------------------------------------
-- Return the player's FrogBiS-style spec key, e.g. "Balance Druid".
------------------------------------------------------------------------
local function GetPlayerSpecKey()
    local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
                    or GetSpecialization
    local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
                    or GetSpecializationInfo
    if not getSpec then return nil end
    local idx = getSpec()
    if not idx or idx == 0 then return nil end
    local _, specName = getInfo(idx)
    if not specName then return nil end

    local _, classToken = UnitClass("player")
    local className = CLASS_TOKEN_TO_NAME[classToken] or classToken
    return specName .. " " .. className   -- e.g. "Balance Druid"
end

------------------------------------------------------------------------
-- Return all spec keys for the player's class.
-- Used when offspec checking is enabled.
------------------------------------------------------------------------
local function GetAllClassSpecKeys()
    local _, classToken = UnitClass("player")
    local className = CLASS_TOKEN_TO_NAME[classToken]
    if not className or not FrogBiS_Templates then return {} end

    local specs = {}
    for specKey in pairs(FrogBiS_Templates) do
        -- Template keys end with the class name (e.g. "Balance Druid")
        if specKey:find(className, 1, true) then
            specs[#specs + 1] = specKey
        end
    end
    return specs
end

------------------------------------------------------------------------
-- FrogBiS charKey: "Name-Realm"
------------------------------------------------------------------------
local function GetCharKey()
    local name  = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

------------------------------------------------------------------------
-- Gather ALL BiS item lists for a given specKey.
-- Returns an array of { source = "name", items = { ... } } tables,
-- covering the template AND every custom/named set.
------------------------------------------------------------------------
local function GetAllBiSListsForSpec(specKey)
    if not specKey then return {} end
    local results = {}
    local db = FrogBiSDB

    -- Bundled template (e.g. T16 BiS)
    if FrogBiS_Templates and FrogBiS_Templates[specKey] then
        local tpl = FrogBiS_Templates[specKey]
        if tpl.items and #tpl.items > 0 then
            results[#results + 1] = { source = "template(" .. (tpl.tier or "?") .. ")", items = tpl.items }
        end
    end

    -- All named sets
    if db and db.sets and db.sets[specKey] then
        for i, s in ipairs(db.sets[specKey]) do
            if s.items and #s.items > 0 then
                results[#results + 1] = { source = "set:" .. (s.name or ("#" .. i)), items = s.items }
            end
        end
    end

    -- Legacy per-character custom
    if db and db.chars then
        local charKey = GetCharKey()
        local custom = db.chars[charKey] and db.chars[charKey][specKey]
        if custom and custom.bisItems and #custom.bisItems > 0 then
            results[#results + 1] = { source = "charCustom", items = custom.bisItems }
        end
    end

    return results
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
-- Check whether the given itemID appears in a BiS item list.
------------------------------------------------------------------------
local function ItemInList(itemID, items)
    if not items then return false end
    for _, entry in ipairs(items) do
        if entry.id and IsMatchingID(itemID, entry.id) then
            return true
        end
    end
    return false
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
-- IsBiS: Is this item on ANY BiS list for the player's current
-- spec (or any class spec if offspec is enabled)?
-- Checks ALL sets (template + custom + named), not just the active one.
------------------------------------------------------------------------
function provider:IsBiS(itemID)
    local checkOffspec = aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bisOffspecEnabled
    local specsToCheck = {}

    if checkOffspec then
        specsToCheck = GetAllClassSpecKeys()
        Debug("    [FrogBiS] checking offspec, specs: " .. table.concat(specsToCheck, ", "))
    else
        local specKey = GetPlayerSpecKey()
        Debug("    [FrogBiS] specKey=" .. tostring(specKey))
        if specKey then
            specsToCheck = { specKey }
        end
    end

    for _, specKey in ipairs(specsToCheck) do
        local allLists = GetAllBiSListsForSpec(specKey)
        Debug("    [FrogBiS] " .. specKey .. ": " .. #allLists .. " list(s)")
        for _, listInfo in ipairs(allLists) do
            if ItemInList(itemID, listInfo.items) then
                Debug("    [FrogBiS] MATCH in " .. specKey .. " / " .. listInfo.source)
                return true
            end
        end
    end

    Debug("    [FrogBiS] item " .. itemID .. " not found in any list")
    return false
end

------------------------------------------------------------------------
-- IsCollected: Does the player already own this item?
-- Checks equipped gear and bags.
------------------------------------------------------------------------
function provider:IsCollected(itemID)
    -- Check equipped
    for slot = 0, 18 do
        local eqID = GetInventoryItemID("player", slot)
        if eqID and IsMatchingID(eqID, itemID) then return true end
    end

    -- Check bags (use MoP-safe API — no C_Container in MoP Classic)
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemID   = (C_Container and C_Container.GetContainerItemID)   or GetContainerItemID
    if getNumSlots and getItemID then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local numSlots = getNumSlots(bag) or 0
            for bagSlot = 1, numSlots do
                local bagItemID = getItemID(bag, bagSlot)
                if bagItemID and IsMatchingID(bagItemID, itemID) then return true end
            end
        end
    end

    return false
end

------------------------------------------------------------------------
-- IsNormalVersionOfBiS: Is this a non-heroic version of a BiS item?
-- FrogBiS already includes warforged variants via offset matching,
-- so IsBiS covers this.
------------------------------------------------------------------------
function provider:IsNormalVersionOfBiS(itemID)
    return self:IsBiS(itemID)
end

------------------------------------------------------------------------
-- Registration: wait for FrogBiS to load, then register.
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon == "FrogBiS" then
        if FrogBiS_Templates then
            SLH.RollManager:RegisterBiSProvider("FrogBiS", provider)
        end
        frame:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Also try immediately in case FrogBiS loaded first
if FrogBiS_Templates then
    SLH.RollManager:RegisterBiSProvider("FrogBiS", provider)
end
