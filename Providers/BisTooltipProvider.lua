local _, SLH = ...

------------------------------------------------------------------------
-- BisTooltip provider
--
-- Reads from global tables exposed by the Bistooltip addon:
--   Bistooltip_items[itemID]          → array of { class_name, spec_name, slots }
--   Bistooltip_char_equipment[itemID] → 1 (bags) or 2 (equipped), or nil
--   Bistooltip_classes_indexes        → { ["Death knight"] = 1, ... }
--
-- Bistooltip_items is NOT a static table — BisTooltip reassigns it to either
--   Bistooltip_wh_items    (Wowhead,    data_source = "wh")
--   Bistooltip_wowtbc_items (wowtbc.gg, data_source = "wowtbc")
-- based on the user's "Data source" dropdown in the BisTooltip BiS List UI
-- (stored in BisTooltipAddon.db.char.data_source / BisTooltipDB).
-- Reading Bistooltip_items at call-time therefore always reflects the
-- user's currently active source — no extra handling needed here.
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
-- Extended difficulty offsets for SoO cross-difficulty matching.
------------------------------------------------------------------------
local DIFFICULTY_OFFSETS = { HWF_OFFSET, -HWF_OFFSET, NWF_OFFSET, -NWF_OFFSET,
                             137, -137, 543 + 137, -(543 + 137), 747 + 137, -(747 + 137) }

------------------------------------------------------------------------
-- Map WoW API spec names → BisTooltip spec names (where they differ)
------------------------------------------------------------------------
local BT_SPEC_MAP = {
    ["Blood"] = "Blood tank",
    ["Beast Mastery"] = "Beast mastery",
}

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
-- Return the phase index the user has selected in BisTooltip (1-based).
-- Stored in BistooltipAddon.db.char.phase_index.
-- Returns nil if the DB isn't readable yet (disables phase filtering).
------------------------------------------------------------------------
local function GetBisTooltipPhaseIndex()
    if BistooltipAddon and BistooltipAddon.db and BistooltipAddon.db.char then
        return BistooltipAddon.db.char.phase_index
    end
    return nil
end

------------------------------------------------------------------------
-- Return true if the ranks string has a non-"-" rank for phaseIndex.
-- Ranks format from BisTooltip data: "N / M"  (slash-separated).
-- Returns true (no filtering) when phaseIndex or ranksStr is absent.
------------------------------------------------------------------------
local function IsRankedForPhase(ranksStr, phaseIndex)
    if not phaseIndex or not ranksStr or ranksStr == "" then return true end
    local parts = { strsplit("/", ranksStr) }
    local part  = parts[phaseIndex]
    if not part then return true end          -- phase index out of range
    part = part:match("^%s*(.-)%s*$")         -- trim surrounding whitespace
    return part ~= "-" and part ~= ""
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
-- Check the Bistooltip_wh_bislists table directly for a given
-- class/spec/phase combination. Returns true if itemID is in that list.
------------------------------------------------------------------------
local function IsInBislist(itemID, className, specName, phaseName)
    local bislists = Bistooltip_wh_bislists
    if not bislists then return false end
    local classData = bislists[className]
    if not classData then return false end
    local specData = classData[specName]
    if not specData then return false end

    -- If phaseName specified, check only that phase
    local phasesToCheck = {}
    if phaseName then
        phasesToCheck[1] = specData[phaseName]
    else
        -- Check all phases
        for _, phaseSlots in pairs(specData) do
            if type(phaseSlots) == "table" then
                phasesToCheck[#phasesToCheck + 1] = phaseSlots
            end
        end
    end

    for _, slots in ipairs(phasesToCheck) do
        for _, slotEntry in ipairs(slots) do
            if type(slotEntry) == "table" then
                -- Item IDs are at numeric keys 1-6 in each slot entry
                for i = 1, 6 do
                    local bisID = slotEntry[i]
                    if bisID and bisID > 0 then
                        if IsMatchingID(itemID, bisID) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

------------------------------------------------------------------------
-- Check whether the given itemID is BiS for the player's current
-- class/spec (or any of their specs if offspec is enabled).
-- Respects bisMainSpec/bisOffspec overrides from Options.
------------------------------------------------------------------------
function provider:IsBiS(itemID)
    if not Bistooltip_items and not Bistooltip_wh_bislists then
        Debug("    [BisTooltip] Bistooltip_items not loaded")
        return false
    end

    local className = GetPlayerClassName()
    local charDB    = aSmoothLootHelperCharDB
    if not className then return false end

    -- Direct bislists check: if the user selected a "spec / phase" combo,
    -- we can look up directly in Bistooltip_wh_bislists without needing
    -- the flattened Bistooltip_items table.
    if Bistooltip_wh_bislists then
        local function CheckBislistSetting(setting)
            if not setting or setting == "" then return nil end
            -- Parse "Blood tank / P5" format
            local specName, phaseName = setting:match("^(.-)%s*/%s*(.+)$")
            if specName and phaseName then
                if IsInBislist(itemID, className, specName, phaseName) then
                    Debug("    [BisTooltip] MATCH in bislists: " .. className .. "/" .. specName .. "/" .. phaseName)
                    return true
                end
                return false
            end
            -- Plain spec name (no phase) — check all phases
            if IsInBislist(itemID, className, setting, nil) then
                Debug("    [BisTooltip] MATCH in bislists: " .. className .. "/" .. setting .. " (all phases)")
                return true
            end
            return false
        end

        local mainSpec = charDB and charDB.bisMainSpec
        local checkOffspec = charDB and charDB.bisOffspecEnabled
        local offSpec = charDB and charDB.bisOffspec

        -- If user has explicitly selected a bislist spec (with or without phase)
        if mainSpec and mainSpec ~= "" then
            local mainResult = CheckBislistSetting(mainSpec)
            if mainResult == true then return true end
            if checkOffspec and offSpec and offSpec ~= "" then
                local offResult = CheckBislistSetting(offSpec)
                if offResult == true then return true end
            end
            -- If explicit settings didn't match but we have bislists data,
            -- still fall through to Bistooltip_items check below for coverage
        else
            -- Auto-detect: use GetPlayerSpecName mapped to BT name
            local autoSpec = GetPlayerSpecName()
            local btSpec = autoSpec and (BT_SPEC_MAP[autoSpec] or autoSpec)
            if btSpec and IsInBislist(itemID, className, btSpec, nil) then
                Debug("    [BisTooltip] MATCH in bislists (auto): " .. className .. "/" .. btSpec)
                return true
            end
        end
    end

    -- Fall through to Bistooltip_items check for broader coverage
    if not Bistooltip_items then return false end

    local entries = Bistooltip_items[itemID]
    local matchedVariant = nil
    if not entries then
        -- Try all difficulty/warforged offsets
        for _, offset in ipairs(DIFFICULTY_OFFSETS) do
            if Bistooltip_items[itemID + offset] then
                matchedVariant = itemID + offset
                break
            end
        end
        if matchedVariant then
            entries = Bistooltip_items[matchedVariant]
            Debug("    [BisTooltip] item " .. itemID .. " not found directly, matched variant " .. matchedVariant)
        end
    end
    -- Name-based fallback: if ID offsets didn't find it, search by name
    if not entries then
        local dropName = GetItemInfo(itemID)
        if dropName then
            local lowerName = dropName:lower()
            for bisID, bisEntries in pairs(Bistooltip_items) do
                local bisName = GetItemInfo(bisID)
                if bisName and bisName:lower() == lowerName then
                    entries = bisEntries
                    matchedVariant = bisID
                    Debug("    [BisTooltip] item " .. itemID .. " matched by name '" .. dropName .. "' → " .. bisID)
                    break
                end
            end
        end
    end
    if not entries then
        Debug("    [BisTooltip] item " .. itemID .. " not in BiS database")
        return false
    end

    local className = GetPlayerClassName()
    local charDB    = aSmoothLootHelperCharDB

    -- Determine which spec(s) to check
    local mainSpec = charDB and charDB.bisMainSpec
    if not mainSpec or mainSpec == "" then
        mainSpec = GetPlayerSpecName()  -- auto-detect
    end
    Debug("    [BisTooltip] class=" .. tostring(className) .. "  spec=" .. tostring(mainSpec))

    if not className then return false end

    local checkOffspec = charDB and charDB.bisOffspecEnabled
    local offSpec      = charDB and charDB.bisOffspec
    local phaseIndex   = GetBisTooltipPhaseIndex()

    -- Build set of accepted spec names
    -- Build set of accepted spec names.
    -- If the user explicitly set a spec with a phase suffix (e.g. "Blood tank - PR"),
    -- we match that exactly. If using auto-detect (WoW API name like "Blood"),
    -- we match any BisTooltip spec that starts with the mapped base name.
    local acceptedSpecs = {}
    local acceptedBaseSpecs = {}  -- for prefix matching
    if mainSpec then
        acceptedSpecs[mainSpec] = true
        acceptedBaseSpecs[mainSpec] = true
    end
    if checkOffspec then
        if offSpec and offSpec ~= "" then
            acceptedSpecs[offSpec] = true
            acceptedBaseSpecs[offSpec] = true
        else
            acceptedSpecs = nil
            acceptedBaseSpecs = nil
        end
    end

    -- Helper: check if an entry's spec_name matches our accepted specs
    -- Supports both exact match and prefix match (for auto-detect base names)
    local function IsSpecAccepted(entrySpecName)
        if acceptedSpecs == nil then return true end  -- accept all
        if acceptedSpecs[entrySpecName] then return true end  -- exact match
        -- Prefix match: "Blood tank - PR" starts with "Blood tank"
        for base in pairs(acceptedBaseSpecs) do
            if entrySpecName:sub(1, #base) == base then
                return true
            end
        end
        return false
    end

    local specList = {}
    for _, entry in ipairs(entries) do
        specList[#specList + 1] = entry.class_name .. "/" .. entry.spec_name
        if entry.class_name == className then
            local rankedForPhase = false
            if entry.slots then
                for _, slot in ipairs(entry.slots) do
                    if IsRankedForPhase(slot.ranks, phaseIndex) then
                        rankedForPhase = true
                        break
                    end
                end
            else
                rankedForPhase = true
            end

            if not rankedForPhase then
                Debug("    [BisTooltip] SKIP (not ranked in phase " .. tostring(phaseIndex) .. "): "
                      .. entry.class_name .. "/" .. entry.spec_name)
            elseif IsSpecAccepted(entry.spec_name) then
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
        if Bistooltip_items or Bistooltip_wowtbc_items or Bistooltip_wh_bislists then
            SLH.RollManager:RegisterBiSProvider("BisTooltip", provider)
        end
        frame:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Also try registering immediately in case BisTooltip already loaded
if Bistooltip_items or Bistooltip_wowtbc_items or Bistooltip_wh_bislists then
    SLH.RollManager:RegisterBiSProvider("BisTooltip", provider)
end
