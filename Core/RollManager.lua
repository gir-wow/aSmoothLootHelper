local _, SLH = ...
SLH.RollManager = {}

local RollManager = SLH.RollManager
local ItemUtil    = SLH.ItemUtil
local History     = SLH.History

------------------------------------------------------------------------
-- Roll type constants
------------------------------------------------------------------------
local ROLL_PASS       = 0
local ROLL_NEED       = 1
local ROLL_GREED      = 2
local ROLL_DISENCHANT = 3

local ROLL_LABEL = {
    [ROLL_PASS]  = "PASS",
    [ROLL_NEED]  = "NEED",
    [ROLL_GREED] = "GREED",
}

------------------------------------------------------------------------
-- Session memory — tracks manual rolls this session (cleared on logout)
-- Key: itemID, Value: rollType (0/1/2/3)
------------------------------------------------------------------------
local sessionRolls = {}

-- Pending rolls: rollID → itemID, so we can match manual rolls back
local pendingRolls = {}

-- Auto-need tracking: rollID → itemLink, for win notifications
local autoNeedRolls = {}

------------------------------------------------------------------------
-- BiS provider registry  (Phase 3 API)
------------------------------------------------------------------------
local bisProviders = {}

function RollManager:RegisterBiSProvider(providerName, providerTable)
    if not providerName or not providerTable then return end
    if type(providerTable.IsBiS) ~= "function"
        or type(providerTable.IsCollected) ~= "function"
        or type(providerTable.IsNormalVersionOfBiS) ~= "function" then
        print("|cffff9900[SLH]|r BiS provider '" .. providerName .. "' is missing required methods.")
        return
    end
    bisProviders[providerName] = providerTable
    print("|cff00ccff[SLH]|r BiS provider registered: " .. providerName)
end

function RollManager:GetBiSProviders()
    return bisProviders
end

------------------------------------------------------------------------
-- Session memory API
------------------------------------------------------------------------
function RollManager:GetSessionRolls()
    return sessionRolls
end

function RollManager:ClearSession()
    wipe(sessionRolls)
end

------------------------------------------------------------------------
-- Settings helpers
------------------------------------------------------------------------
local function GetSetting(key)
    local charDB = aSmoothLootHelperCharDB
    local db     = aSmoothLootHelperDB

    if charDB and charDB[key] ~= nil then
        return charDB[key]
    end
    if db and db.settings and db.settings[key] ~= nil then
        return db.settings[key]
    end
    return nil
end

------------------------------------------------------------------------
-- Debug logging
------------------------------------------------------------------------
local function Debug(msg)
    local db = aSmoothLootHelperDB
    if db and db.settings and db.settings.debugMode then
        print("|cff888888[SLH debug]|r " .. msg)
    end
    -- Always log to the debug buffer (even if chat printing is off)
    if SLH.DebugLog then
        SLH.DebugLog:Add(msg)
    end
end

------------------------------------------------------------------------
-- Core decision engine
------------------------------------------------------------------------
function RollManager:EvaluateRoll(rollID, retryCount)
    retryCount = retryCount or 0

    local itemLink = GetLootRollItemLink(rollID)
    if not itemLink then
        Debug("rollID " .. rollID .. ": no item link")
        return
    end

    local itemID = ItemUtil:GetItemID(itemLink)
    if not itemID then
        Debug("rollID " .. rollID .. ": could not parse itemID")
        return
    end

    -- GetLootRollItemInfo always has data for active rolls.
    -- GetItemInfo may return nil if the item isn't cached yet.
    local _, _, _, rollQuality = GetLootRollItemInfo(rollID)
    local name, _, infoQuality, ilvl, _, itemType, itemSubType = GetItemInfo(itemLink)

    -- Use rollQuality as the reliable source; fall back to GetItemInfo
    local quality = rollQuality or infoQuality

    local qualNames = { [0]="Poor", [1]="Common", [2]="Uncommon", [3]="Rare", [4]="Epic", [5]="Legendary" }
    Debug("--- Roll on " .. itemLink .. " (id=" .. itemID .. ")")
    Debug("  quality=" .. (qualNames[quality] or tostring(quality))
        .. "  ilvl=" .. tostring(ilvl or "?")
        .. "  type=" .. tostring(itemType or "?")
        .. "  subType=" .. tostring(itemSubType or "?")
        .. "  cached=" .. tostring(name ~= nil)
        .. "  retry=" .. retryCount)

    -- If GetItemInfo hasn't cached yet (name==nil), retry up to 3 times
    -- so armor-type filter, ilvl threshold, etc. can work.
    if not name and retryCount < 3 then
        C_Timer.After(0.3, function()
            -- Make sure the roll is still active
            local link = GetLootRollItemLink(rollID)
            if link then
                self:EvaluateRoll(rollID, retryCount + 1)
            end
        end)
        return
    end

    -- Track this rollID → itemID for session memory
    pendingRolls[rollID] = itemID

    -- Master toggle
    if not GetSetting("autoGreedEnabled") then
        Debug("  SKIP: addon disabled")
        return
    end

    --------------------------------------------------------------------
    -- Armor-type filter
    --------------------------------------------------------------------
    if GetSetting("armorFilterEnabled") and itemSubType then
        local isOff = ItemUtil:IsOffArmorType(itemLink)
        Debug("  Armor filter: subType=" .. tostring(itemSubType) .. "  playerType=" .. tostring(ItemUtil:GetPlayerArmorType()) .. "  isOff=" .. tostring(isOff))
        if isOff then
            local action = GetSetting("armorFilterAction") or "greed"
            local rollType = (action == "pass") and ROLL_PASS or ROLL_GREED
            RollOnLoot(rollID, rollType)
            if rollType == ROLL_GREED then History:RecordGreed(itemID) end
            self:Announce(itemLink, ROLL_LABEL[rollType] .. " (off-armor)")
            return
        end
    end

    --------------------------------------------------------------------
    -- Quality-based auto-roll: auto-roll on items at or below a
    -- quality threshold (2 = Uncommon/green, 3 = Rare/blue).
    --------------------------------------------------------------------
    local qualMode      = GetSetting("qualityRollMode")
    local qualThreshold = GetSetting("qualityThreshold") or 0
    if qualMode and qualMode ~= "off" and qualThreshold > 0 and quality then
        Debug("  Quality filter: quality=" .. tostring(quality) .. "  threshold=" .. qualThreshold .. "  mode=" .. qualMode)
        if quality <= qualThreshold then
            local qualNames = { [0]="Poor", [1]="Common", [2]="Uncommon", [3]="Rare" }
            local rollType = ROLL_GREED
            if qualMode == "pass" then rollType = ROLL_PASS
            elseif qualMode == "need" then rollType = ROLL_NEED
            end
            RollOnLoot(rollID, rollType)
            if rollType == ROLL_GREED then History:RecordGreed(itemID) end
            self:Announce(itemLink, ROLL_LABEL[rollType] .. " (" .. (qualNames[quality] or "?") .. " quality)")
            return
        end
    end

    --------------------------------------------------------------------
    -- BiS check: need if not collected, greed if already collected.
    --------------------------------------------------------------------
    if GetSetting("bisNeedEnabled") then
        local bisMatched   = false
        local bisCollected = false
        for pName, provider in pairs(bisProviders) do
            local isBiS      = provider:IsBiS(itemID)
            local isCollected = provider:IsCollected(itemID)
            local isNormal    = provider:IsNormalVersionOfBiS(itemID)
            Debug("  BiS check [" .. pName .. "]: isBiS=" .. tostring(isBiS) .. "  collected=" .. tostring(isCollected) .. "  normalOfBiS=" .. tostring(isNormal))

            if isBiS or isNormal then
                bisMatched = true
                if not isCollected then
                    RollOnLoot(rollID, ROLL_NEED)
                    self:Announce(itemLink, "NEED (BiS via " .. pName .. ")")
                    if GetSetting("bisNotifyEnabled") ~= false and SLH.Notify then
                        SLH.Notify:BiSNeed(itemLink)
                    end
                    return
                else
                    bisCollected = true
                end
            end
        end
        -- BiS item but already collected → auto-greed
        if bisMatched and bisCollected then
            Debug("  BiS item already collected → GREED")
            RollOnLoot(rollID, ROLL_GREED)
            History:RecordGreed(itemID)
            self:Announce(itemLink, "GREED (BiS already collected)")
            return
        end
    end

    --------------------------------------------------------------------
    -- Auto-roll mode (per character): off / pass / greed / need
    --------------------------------------------------------------------
    local autoMode = GetSetting("autoRollMode")
    if autoMode and autoMode ~= "off" then
        Debug("  Auto-mode: " .. autoMode)
        local rollType = ROLL_GREED
        if autoMode == "pass" then rollType = ROLL_PASS
        elseif autoMode == "need" then rollType = ROLL_NEED
        end
        RollOnLoot(rollID, rollType)
        if rollType == ROLL_GREED then History:RecordGreed(itemID) end
        self:Announce(itemLink, ROLL_LABEL[rollType] .. " (auto-mode)")
        return
    end

    --------------------------------------------------------------------
    -- Session memory: repeat whatever the player rolled last session
    --------------------------------------------------------------------
    if GetSetting("sessionMemoryEnabled") then
        local prevRoll = sessionRolls[itemID]
        if prevRoll then
            RollOnLoot(rollID, prevRoll)
            if prevRoll == ROLL_GREED then History:RecordGreed(itemID) end
            self:Announce(itemLink, ROLL_LABEL[prevRoll] .. " (session)")
            return
        end
    end

    --------------------------------------------------------------------
    -- History-based auto-greed
    --------------------------------------------------------------------
    if GetSetting("autoGreedOnHistory") and History:HasGreeded(itemID) then
        Debug("  History match: greeded before")
        RollOnLoot(rollID, ROLL_GREED)
        History:RecordGreed(itemID)
        self:Announce(itemLink, "GREED (history)")
        return
    end

    --------------------------------------------------------------------
    -- iLvl threshold auto-greed
    --------------------------------------------------------------------
    if GetSetting("ilvlGreedEnabled") and ilvl then
        local threshold = GetSetting("ilvlGreedThreshold") or 0
        if threshold > 0 and ilvl <= threshold then
            Debug("  iLvl match: " .. ilvl .. " <= " .. threshold)
            RollOnLoot(rollID, ROLL_GREED)
            History:RecordGreed(itemID)
            self:Announce(itemLink, "GREED (ilvl " .. ilvl .. " <= " .. threshold .. ")")
            return
        end
    end

    --------------------------------------------------------------------
    -- Auto-greed downgrades: uses Pawn → built-in stat weights → ilvl.
    --------------------------------------------------------------------
    if GetSetting("downgradeGreedEnabled") then
        -- 1) Try Pawn addon first (full stat weight analysis)
        local pawnUpgrade = ItemUtil:PawnIsUpgrade(itemLink)
        if pawnUpgrade ~= nil then
            Debug("  Pawn check: isUpgrade=" .. tostring(pawnUpgrade))
            if pawnUpgrade == false then
                RollOnLoot(rollID, ROLL_GREED)
                History:RecordGreed(itemID)
                self:Announce(itemLink, "GREED (Pawn: not an upgrade)")
                return
            else
                Debug("  Pawn says upgrade — leaving for manual roll")
            end
        else
            -- 2) Try built-in stat weights
            local StatWeights = SLH.StatWeights
            local weights = StatWeights and StatWeights:GetActiveWeights()
            if weights and next(weights) then
                local isDown = StatWeights:IsDropDowngrade(itemLink, weights)
                Debug("  StatWeights check: isDowngrade=" .. tostring(isDown))
                if isDown == true then
                    RollOnLoot(rollID, ROLL_GREED)
                    History:RecordGreed(itemID)
                    self:Announce(itemLink, "GREED (stat weights: not an upgrade)")
                    return
                elseif isDown == false then
                    Debug("  StatWeights says potential upgrade — leaving for manual roll")
                end
            else
                -- 3) Fall back to ilvl comparison
                local isBetter = ItemUtil:IsEquippedBetter(itemLink)
                Debug("  Downgrade check (ilvl): equippedBetter=" .. tostring(isBetter) .. "  dropIlvl=" .. tostring(ilvl))
                if isBetter then
                    RollOnLoot(rollID, ROLL_GREED)
                    History:RecordGreed(itemID)
                    self:Announce(itemLink, "GREED (equipped ilvl is better)")
                    return
                end
            end
        end
    end

    Debug("  No rule matched — manual roll.")
end

------------------------------------------------------------------------
-- Chat announcement for auto-rolls
------------------------------------------------------------------------
function RollManager:Announce(itemLink, reason)
    print("|cff00ccff[SLH]|r Auto-rolled " .. reason .. " on " .. (itemLink or "?"))
end

------------------------------------------------------------------------
-- Event frame
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("START_LOOT_ROLL")
frame:RegisterEvent("CONFIRM_LOOT_ROLL")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "START_LOOT_ROLL" then
        RollManager:EvaluateRoll(arg1)   -- arg1 = rollID

    elseif event == "CONFIRM_LOOT_ROLL" then
        -- Auto-dismiss the "Are you sure?" popup for all rolls
        ConfirmLootRoll(arg1, arg2)      -- arg1 = rollID, arg2 = rollType
        StaticPopup_Hide("CONFIRM_LOOT_ROLL")

    elseif event == "PLAYER_LOGOUT" then
        -- Reset auto-roll mode to "off" so next login starts clean
        if aSmoothLootHelperCharDB then
            aSmoothLootHelperCharDB.autoRollMode = "off"
        end
        wipe(sessionRolls)
    end
end)

------------------------------------------------------------------------
-- Hook RollOnLoot to track manual rolls for session memory.
-- hooksecurefunc doesn't cause taint — it fires AFTER the original.
------------------------------------------------------------------------
hooksecurefunc("RollOnLoot", function(rollID, rollType)
    local itemID = pendingRolls[rollID]
    if itemID and rollType then
        sessionRolls[itemID] = rollType
        pendingRolls[rollID] = nil
    end
end)
