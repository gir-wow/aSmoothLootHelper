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
-- SoO difficulty item ID offsets.
-- In MoP SoO, the same item at different difficulties uses different
-- item IDs. These are the most common offsets between versions:
--   LFR base → Normal: +137   (or Normal → LFR: -137)
--   Normal → Heroic: +543     (HWF_OFFSET)
--   LFR → Heroic: varies
--   Celestial items share LFR IDs
-- Because offsets are not perfectly consistent across all items, we
-- also do a name-based fallback match.
------------------------------------------------------------------------
local DIFFICULTY_OFFSETS = { 0, 137, -137, HWF_OFFSET, -HWF_OFFSET, NWF_OFFSET, -NWF_OFFSET,
                             543 + 137, -(543 + 137), 747 + 137, -(747 + 137) }

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
-- Check if an itemID matches target, accounting for warforged variants
-- AND cross-difficulty variants (LFR/Normal/Heroic have different IDs
-- in SoO).
------------------------------------------------------------------------
local function IsMatchingID(itemID, targetID)
    if itemID == targetID then return true end
    for _, offset in ipairs(DIFFICULTY_OFFSETS) do
        if offset ~= 0 and itemID == targetID + offset then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Name-based item matching cache.  Built lazily from the BiS lists.
-- Maps normalised item name → true for all items in any active list.
------------------------------------------------------------------------
local nameCache = {}
local nameCacheBuilt = false

local function BuildNameCache(specsToCheck)
    wipe(nameCache)
    for _, specKey in ipairs(specsToCheck) do
        local allLists = GetAllBiSListsForSpec(specKey)
        for _, listInfo in ipairs(allLists) do
            if listInfo.items then
                for _, entry in ipairs(listInfo.items) do
                    if entry.id then
                        local name = GetItemInfo(entry.id)
                        if name then
                            nameCache[name:lower()] = entry.id
                        end
                    end
                end
            end
        end
    end
    nameCacheBuilt = true
end

------------------------------------------------------------------------
-- Check whether the given itemID appears in a BiS item list.
-- Falls back to name matching if ID matching fails.
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

local function ItemInListByName(itemName, items)
    if not itemName or not items then return false end
    local lower = itemName:lower()
    for _, entry in ipairs(items) do
        if entry.id then
            local entryName = GetItemInfo(entry.id)
            if entryName and entryName:lower() == lower then
                return true
            end
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
-- Parse a bisMainSpec/bisOffspec value which may be either:
--   "Blood Death Knight"              → check all lists for that spec
--   "Blood Death Knight::SetName"     → check only the named set
-- Returns: specKey, setName (setName is nil for all-lists mode)
------------------------------------------------------------------------
local function ParseSpecSetting(setting)
    if not setting then return nil, nil end
    local specKey, setName = setting:match("^(.-)::(.+)$")
    if specKey and setName then
        return specKey, setName
    end
    return setting, nil
end

------------------------------------------------------------------------
-- Get lists filtered by an optional set name restriction.
-- If setName is nil, returns all lists for the spec.
-- If setName is specified, returns only the matching named set.
------------------------------------------------------------------------
local function GetFilteredLists(specKey, setName)
    if setName then
        -- Only check the specific named set
        if FrogBiSDB and FrogBiSDB.sets and FrogBiSDB.sets[specKey] then
            for _, s in ipairs(FrogBiSDB.sets[specKey]) do
                if s.name == setName and s.items and #s.items > 0 then
                    return { { source = "set:" .. setName, items = s.items } }
                end
            end
        end
        return {}
    end
    return GetAllBiSListsForSpec(specKey)
end

------------------------------------------------------------------------
-- IsBiS: Is this item on ANY BiS list for the player's current
-- spec (or any class spec if offspec is enabled)?
-- Respects bisMainSpec/bisOffspec overrides from Options.
-- Supports "specKey::setName" format for specific set selection.
-- Checks ALL sets (template + custom + named), not just the active one.
------------------------------------------------------------------------
function provider:IsBiS(itemID)
    local charDB = aSmoothLootHelperCharDB
    local checkOffspec = charDB and charDB.bisOffspecEnabled

    -- Parse main spec setting
    local mainRaw = charDB and charDB.bisMainSpec
    local mainSpec, mainSetName
    if mainRaw and mainRaw ~= "" then
        mainSpec, mainSetName = ParseSpecSetting(mainRaw)
    else
        mainSpec = GetPlayerSpecKey()
    end

    -- Build list of {specKey, setName} pairs to check
    local checksToRun = {}
    if mainSpec then
        checksToRun[#checksToRun + 1] = { spec = mainSpec, setFilter = mainSetName }
    end

    if checkOffspec then
        local offRaw = charDB and charDB.bisOffspec
        if offRaw and offRaw ~= "" then
            local offSpec, offSetName = ParseSpecSetting(offRaw)
            checksToRun[#checksToRun + 1] = { spec = offSpec, setFilter = offSetName }
            Debug("    [FrogBiS] main=" .. tostring(mainSpec) .. (mainSetName and ("::" .. mainSetName) or "")
                  .. " offspec=" .. offSpec .. (offSetName and ("::" .. offSetName) or ""))
        else
            -- No explicit offspec: check all class specs (all lists)
            local allSpecs = GetAllClassSpecKeys()
            for _, sk in ipairs(allSpecs) do
                checksToRun[#checksToRun + 1] = { spec = sk, setFilter = nil }
            end
            Debug("    [FrogBiS] checking all class specs")
        end
    else
        Debug("    [FrogBiS] specKey=" .. tostring(mainSpec) .. (mainSetName and ("::" .. mainSetName) or ""))
    end

    for _, check in ipairs(checksToRun) do
        local allLists = GetFilteredLists(check.spec, check.setFilter)
        Debug("    [FrogBiS] " .. check.spec .. (check.setFilter and ("::" .. check.setFilter) or "") .. ": " .. #allLists .. " list(s)")
        for _, listInfo in ipairs(allLists) do
            if ItemInList(itemID, listInfo.items) then
                Debug("    [FrogBiS] MATCH in " .. check.spec .. " / " .. listInfo.source)
                return true
            end
        end
    end

    -- Fallback: name-based matching for cross-difficulty variants
    -- (e.g. Celestial/LFR version of a Normal BiS item)
    local dropName = GetItemInfo(itemID)
    if dropName then
        for _, check in ipairs(checksToRun) do
            local allLists = GetFilteredLists(check.spec, check.setFilter)
            for _, listInfo in ipairs(allLists) do
                if ItemInListByName(dropName, listInfo.items) then
                    Debug("    [FrogBiS] NAME MATCH '" .. dropName .. "' in " .. check.spec .. " / " .. listInfo.source)
                    return true
                end
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
