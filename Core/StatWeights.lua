local _, SLH = ...
SLH.StatWeights = {}

local StatWeights = SLH.StatWeights

------------------------------------------------------------------------
-- Map Pawn stat names → GetItemStats() key names.
-- GetItemStats returns keys like "ITEM_MOD_STRENGTH_SHORT".
------------------------------------------------------------------------
local PAWN_TO_WOW = {
    Strength       = "ITEM_MOD_STRENGTH_SHORT",
    Agility        = "ITEM_MOD_AGILITY_SHORT",
    Intellect      = "ITEM_MOD_INTELLECT_SHORT",
    Spirit         = "ITEM_MOD_SPIRIT_SHORT",
    Stamina        = "ITEM_MOD_STAMINA_SHORT",
    CritRating     = "ITEM_MOD_CRIT_RATING_SHORT",
    HasteRating    = "ITEM_MOD_HASTE_RATING_SHORT",
    MasteryRating  = "ITEM_MOD_MASTERY_RATING_SHORT",
    HitRating      = "ITEM_MOD_HIT_RATING_SHORT",
    ExpertiseRating = "ITEM_MOD_EXPERTISE_RATING_SHORT",
    DodgeRating    = "ITEM_MOD_DODGE_RATING_SHORT",
    ParryRating    = "ITEM_MOD_PARRY_RATING_SHORT",
    Ap             = "ITEM_MOD_ATTACK_POWER_SHORT",
    SpellPower     = "ITEM_MOD_SPELL_POWER_SHORT",
    Armor          = "RESISTANCE0_NAME",
    Dps            = "ITEM_MOD_DPS_SHORT",
    -- Aliases used by some tools
    CriticalStrike = "ITEM_MOD_CRIT_RATING_SHORT",
    Haste          = "ITEM_MOD_HASTE_RATING_SHORT",
    Mastery        = "ITEM_MOD_MASTERY_RATING_SHORT",
    Hit            = "ITEM_MOD_HIT_RATING_SHORT",
    Expertise      = "ITEM_MOD_EXPERTISE_RATING_SHORT",
    Dodge          = "ITEM_MOD_DODGE_RATING_SHORT",
    Parry          = "ITEM_MOD_PARRY_RATING_SHORT",
    AttackPower    = "ITEM_MOD_ATTACK_POWER_SHORT",
}

-- Reverse: WoW key → short display name
local WOW_TO_SHORT = {}
for pawn, wow in pairs(PAWN_TO_WOW) do
    if not WOW_TO_SHORT[wow] then
        WOW_TO_SHORT[wow] = pawn
    end
end

------------------------------------------------------------------------
-- Parse a Pawn import string into a weights table.
-- Format: ( Pawn: v1: "ScaleName": Stat1=1.5, Stat2=0.8, ... )
-- Also accepts simplified format: Stat1=1.5, Stat2=0.8
-- Returns: { scaleName = "...", weights = { ITEM_MOD_X = value, ... } }
--          or nil on failure.
------------------------------------------------------------------------
function StatWeights:ParsePawnString(input)
    if not input or input == "" then return nil end

    local scaleName = "Custom"
    local weightsRaw = input

    -- Try to extract scale name from full Pawn format
    local name = input:match('"([^"]+)"')
    if name then
        scaleName = name
    end

    -- Strip the Pawn wrapper if present
    local inner = input:match(': ".-":%s*(.+)%s*%)')
    if inner then
        weightsRaw = inner
    else
        -- Maybe just the stats part without wrapper
        weightsRaw = input:gsub("^%s*%(.-:%s*", ""):gsub("%s*%)%s*$", "")
    end

    local weights = {}
    local count = 0
    for stat, val in weightsRaw:gmatch("(%a+)%s*=%s*([%d%.%-]+)") do
        local numVal = tonumber(val)
        if numVal and numVal ~= 0 then
            local wowKey = PAWN_TO_WOW[stat]
            if wowKey then
                weights[wowKey] = numVal
                count = count + 1
            end
        end
    end

    if count == 0 then return nil end
    return { scaleName = scaleName, weights = weights }
end

------------------------------------------------------------------------
-- Export the current weights as a Pawn-format string.
------------------------------------------------------------------------
function StatWeights:ExportPawnString(scaleName, weights)
    if not weights then return "" end
    scaleName = scaleName or "Custom"
    local parts = {}
    for wowKey, val in pairs(weights) do
        local pawnName = WOW_TO_SHORT[wowKey]
        if pawnName and val ~= 0 then
            parts[#parts + 1] = pawnName .. "=" .. string.format("%.2f", val)
        end
    end
    table.sort(parts)
    return '( Pawn: v1: "' .. scaleName .. '": ' .. table.concat(parts, ", ") .. " )"
end

------------------------------------------------------------------------
-- Score an item using the given weights table.
-- Uses GetItemStats() which is available in MoP Classic.
-- Returns a numeric score, or nil if the item can't be scored.
------------------------------------------------------------------------
function StatWeights:ScoreItem(itemLink, weights)
    if not itemLink or not weights then return nil end

    local stats = GetItemStats(itemLink)
    if not stats then return nil end

    local score = 0
    for statKey, statVal in pairs(stats) do
        local weight = weights[statKey]
        if weight then
            score = score + (statVal * weight)
        end
    end
    return score
end

------------------------------------------------------------------------
-- Compare drop vs equipped using stat weights.
-- Returns true if ALL equipped items in the matching slots score
-- higher than the drop (drop is a downgrade).
-- Returns false if the drop could be an upgrade in any slot.
-- Returns nil if we can't determine (no weights configured, etc.).
------------------------------------------------------------------------
function StatWeights:IsDropDowngrade(itemLink, weights)
    if not weights or not next(weights) then return nil end

    local ItemUtil = SLH.ItemUtil
    local slots = ItemUtil:GetEquipSlots(itemLink)
    if not slots then return nil end

    local dropScore = self:ScoreItem(itemLink, weights)
    if not dropScore then return nil end

    for _, slotID in ipairs(slots) do
        local eqLink = GetInventoryItemLink("player", slotID)
        if not eqLink then
            return false   -- empty slot = upgrade
        end
        local eqScore = self:ScoreItem(eqLink, weights)
        if not eqScore or eqScore <= dropScore then
            return false   -- equipped is same or worse = potential upgrade
        end
    end
    return true   -- all slots have better scored gear
end

------------------------------------------------------------------------
-- Get the active weights for the current character (main spec).
-- Checks source preference: Pawn addon first, then imported profiles.
-- Returns weights table or nil.
------------------------------------------------------------------------
function StatWeights:GetActiveWeights()
    local cdb = aSmoothLootHelperCharDB
    if not cdb then return nil end

    local source = cdb.statWeightSource or "pawn"

    -- Pawn source: use Pawn's live scoring (no local weights needed)
    if source == "pawn" and cdb.statWeightPawnMain then
        -- Return a sentinel so callers know Pawn is handling it
        -- Actual scoring goes through PawnGetScaleValue in the downgrade check
        return nil  -- let PawnIsUpgrade handle it
    end

    -- Import source: use stored profile
    if cdb.statWeightProfiles and cdb.statWeightProfiles.main then
        return cdb.statWeightProfiles.main.weights
    end

    -- Legacy fallback
    if cdb.statWeights then return cdb.statWeights end
    return nil
end

------------------------------------------------------------------------
-- Get offspec weights (import source only).
------------------------------------------------------------------------
function StatWeights:GetOffspecWeights()
    local cdb = aSmoothLootHelperCharDB
    if not cdb then return nil end
    if cdb.statWeightProfiles and cdb.statWeightProfiles.offspec then
        return cdb.statWeightProfiles.offspec.weights
    end
    return nil
end

------------------------------------------------------------------------
-- Get available Pawn scale names (requires Pawn addon loaded).
-- Returns a list of scale name strings, or empty table if Pawn absent.
------------------------------------------------------------------------
function StatWeights:GetPawnScales()
    if not PawnGetAllScales then return {} end
    local scales = PawnGetAllScales()
    if not scales then return {} end

    -- Get the player's class for filtering
    local _, playerClass = UnitClass("player")
    local className = (playerClass or ""):lower()
    -- Also get localised class name for matching scale display names
    local localisedClass = UnitClass("player") or ""
    local localisedLower = localisedClass:lower()

    local allScales = {}
    if scales[1] then
        for _, name in ipairs(scales) do
            allScales[#allScales + 1] = name
        end
    else
        for name in pairs(scales) do
            allScales[#allScales + 1] = name
        end
    end
    table.sort(allScales)

    -- Filter: keep scales that match the player's class.
    -- Strategy 1: PawnGetScaleClassID (if available) returns classID.
    -- Strategy 2: Check if scale name contains the class name.
    -- Strategy 3: Check if the scale is marked as visible/enabled for this char.
    local filtered = {}
    local playerClassID = select(3, UnitClass("player"))

    for _, name in ipairs(allScales) do
        local dominated = false

        -- Try PawnGetScaleClassID (Pawn 2.x+)
        if PawnGetScaleClassID then
            local scaleClassID = PawnGetScaleClassID(name)
            if scaleClassID and scaleClassID > 0 and scaleClassID ~= playerClassID then
                dominated = true
            end
        elseif PawnGetScaleData then
            -- PawnGetScaleData returns a table with .ClassID field
            local data = PawnGetScaleData(name)
            if data and data.ClassID and data.ClassID > 0 and data.ClassID ~= playerClassID then
                dominated = true
            end
        end

        -- Fallback: name-based matching if no API data found the class
        if not dominated and not PawnGetScaleClassID and not PawnGetScaleData then
            local lower = name:lower()
            if not lower:find(className, 1, true) and not lower:find(localisedLower, 1, true) then
                -- Heuristic: if the scale name contains another class name, skip it
                local otherClasses = {"warrior","paladin","hunter","rogue","priest","shaman",
                                      "mage","warlock","monk","druid","death knight","deathknight"}
                for _, other in ipairs(otherClasses) do
                    if other ~= className and lower:find(other, 1, true) then
                        dominated = true
                        break
                    end
                end
            end
        end

        if not dominated then
            filtered[#filtered + 1] = name
        end
    end

    -- If filtering removed everything, fall back to full list
    if #filtered == 0 then return allScales end
    return filtered
end

------------------------------------------------------------------------
-- Get a display summary of configured weights.
------------------------------------------------------------------------
function StatWeights:GetSummary()
    local cdb = aSmoothLootHelperCharDB
    if not cdb then return "Not configured" end

    local source = cdb.statWeightSource or "pawn"

    if source == "pawn" then
        local main = cdb.statWeightPawnMain
        local off  = cdb.statWeightPawnOffspec
        if main then
            local txt = "Pawn: " .. main
            if off then txt = txt .. " / " .. off end
            return txt
        end
        -- No Pawn scale selected but source is pawn
        if PawnGetAllScales then
            return "Pawn (no scale selected)"
        end
        return "Pawn not detected"
    end

    -- Import source
    if cdb.statWeightProfiles and cdb.statWeightProfiles.main then
        local prof = cdb.statWeightProfiles.main
        local count = 0
        if prof.weights then
            for _ in pairs(prof.weights) do count = count + 1 end
        end
        local txt = (prof.name or "Custom") .. " (" .. count .. " stats)"
        if cdb.statWeightProfiles.offspec then
            txt = txt .. " + offspec"
        end
        return txt
    end

    -- Legacy
    local name = cdb.statWeightsName or "Custom"
    local w = cdb.statWeights
    if not w or not next(w) then return "Not configured" end
    local count = 0
    for _ in pairs(w) do count = count + 1 end
    return name .. " (" .. count .. " stats)"
end
