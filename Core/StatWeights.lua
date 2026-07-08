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
-- Get the active weights for the current character.
-- Returns weights table or nil.
------------------------------------------------------------------------
function StatWeights:GetActiveWeights()
    local cdb = aSmoothLootHelperCharDB
    if not cdb or not cdb.statWeights then return nil end
    return cdb.statWeights
end

------------------------------------------------------------------------
-- Get a display summary of configured weights.
------------------------------------------------------------------------
function StatWeights:GetSummary()
    local cdb = aSmoothLootHelperCharDB
    if not cdb then return "Not configured" end
    local name = cdb.statWeightsName or "Custom"
    local w = cdb.statWeights
    if not w or not next(w) then return "Not configured" end

    local count = 0
    for _ in pairs(w) do count = count + 1 end
    return name .. " (" .. count .. " stats)"
end
