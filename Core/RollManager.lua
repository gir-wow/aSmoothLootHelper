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
    -- Tier token auto-need
    --
    -- Need a tier token when:
    --   1. It is for the player's class/token-group.
    --   2. Player is NOT already carrying a copy in bags/equipped.
    --
    -- TODO (future): also skip when the player already owns the tier
    -- piece(s) this token grants for main spec OR offspec.  This
    -- requires a token-ID → tier-piece-IDs lookup table for MoP
    -- T14/T15/T16 that does not yet exist in the codebase.  Once that
    -- table is added, check bisProviders[*]:IsCollected() for each
    -- piece the token can produce.
    --------------------------------------------------------------------
    if GetSetting("tierTokenNeedEnabled") then
        if ItemUtil:IsTierTokenForPlayer(itemLink) then
            if ItemUtil:IsInBagsOrEquipped(itemID) then
                Debug("  Tier token: already carrying this token — skip")
                -- fall through to normal rules (will likely greed or manual)
            else
                -- Outgear guard: don't auto-need a token the player has
                -- clearly outgeared (e.g. 496 Celestial token on a SoO-geared
                -- character).  Mirror the same Pawn → ilvl fallback used in
                -- the BiS section.
                -- delta=0: greed if the equipped item in that slot is
                -- strictly better by even 1 ilvl.  For tier tokens the
                -- set-bonus argument only holds when ilvl is equal or
                -- the slot is empty; if anything better is already there,
                -- another player should get priority.
                local pawnUpg = ItemUtil:PawnIsUpgrade(itemLink)
                local outgeared = false
                if pawnUpg == false then
                    outgeared = true
                    Debug("  Tier token: Pawn says not an upgrade — outgeared")
                elseif pawnUpg == nil and ItemUtil:IsTokenSignificantDowngrade(itemLink, 0) then
                    outgeared = true
                    Debug("  Tier token: equipped slot ilvl > token ilvl — outgeared")
                end

                if outgeared then
                    Debug("  Tier token: outgeared — GREED")
                    RollOnLoot(rollID, ROLL_GREED)
                    History:RecordGreed(itemID)
                    self:Announce(itemLink, "GREED (tier token: outgeared)")
                    return
                end

                Debug("  Tier token: for player class, not in bags — NEED")
                RollOnLoot(rollID, ROLL_NEED)
                self:Announce(itemLink, "NEED (tier token for your class)")
                return
            end
        elseif ItemUtil:IsTierToken(itemLink) then
            -- Token is not for this class — pass it
            Debug("  Tier token: wrong class token — PASS")
            RollOnLoot(rollID, ROLL_PASS)
            self:Announce(itemLink, "PASS (tier token, wrong class)")
            return
        end
    end

    --------------------------------------------------------------------
    -- Transmog need: auto-need any item whose appearance the player
    -- hasn't collected yet.  Runs before the armor filter so the player
    -- can collect off-type appearances when transmog mode is on.
    -- Uses C_TransmogCollection.PlayerHasTransmog (available in MoP Classic).
    --
    -- C_Transmog.CanTransmogItem returns:
    --   canBeChanged, noChangeReason, canBeSource, noSourceReason
    -- We need the 3rd return value (canBeSource) — it returns false for
    -- BoP items this class cannot equip, which is exactly the right gate.
    --------------------------------------------------------------------
    if GetSetting("transmogNeedEnabled") then
        local canSource = false
        if C_Transmog and C_Transmog.CanTransmogItem then
            local _, _, canBeSource = C_Transmog.CanTransmogItem(itemLink)
            canSource = canBeSource == true
        end
        Debug("  Transmog check: canSource=" .. tostring(canSource))
        if canSource then
            local hasTransmog = C_TransmogCollection
                                and C_TransmogCollection.PlayerHasTransmog
                                and C_TransmogCollection.PlayerHasTransmog(itemID)
            Debug("  Transmog check: hasTransmog=" .. tostring(hasTransmog))
            if not hasTransmog then
                RollOnLoot(rollID, ROLL_NEED)
                self:Announce(itemLink, "NEED (transmog: appearance not collected)")
                return
            else
                Debug("  Transmog: appearance already collected")
            end
        end
    end

    --------------------------------------------------------------------
    -- Lockbox handling — explicit per-character setting, bypasses all
    -- other rules so rogues can always Need or everyone can always Pass.
    --------------------------------------------------------------------
    local lockboxMode = GetSetting("lockboxRollMode")
    if lockboxMode and lockboxMode ~= "off" then
        if ItemUtil:IsLockbox(itemLink) then
            local rollType = ROLL_PASS
            if lockboxMode == "greed" then rollType = ROLL_GREED
            elseif lockboxMode == "need" then rollType = ROLL_NEED
            end
            RollOnLoot(rollID, rollType)
            if rollType == ROLL_GREED then History:RecordGreed(itemID) end
            self:Announce(itemLink, ROLL_LABEL[rollType] .. " (lockbox)")
            return
        end
    end

    --------------------------------------------------------------------
    -- Armor-type filter
    --------------------------------------------------------------------
    if GetSetting("armorFilterEnabled") and itemSubType then
        local isOffType = ItemUtil:IsOffArmorType(itemLink)
        local isWrongStat = not isOffType and ItemUtil:IsWrongPrimaryStatForPlayer(itemLink)
        Debug("  Armor filter: subType=" .. tostring(itemSubType)
              .. "  playerType=" .. tostring(ItemUtil:GetPlayerArmorType())
              .. "  isOffType=" .. tostring(isOffType)
              .. "  isWrongStat=" .. tostring(isWrongStat))
        if isOffType or isWrongStat then
            local reason = isWrongStat and "wrong-stat" or "off-armor"
            local action = GetSetting("armorFilterAction") or "greed"
            local rollType = (action == "pass") and ROLL_PASS or ROLL_GREED
            RollOnLoot(rollID, rollType)
            if rollType == ROLL_GREED then History:RecordGreed(itemID) end
            self:Announce(itemLink, ROLL_LABEL[rollType] .. " (" .. reason .. ")")
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
    -- Guard: never auto-need if Pawn says the item is not an upgrade,
    -- or if every relevant slot already has gear >30 ilvl above the
    -- drop (player has clearly outgeared this version of the item).
    --------------------------------------------------------------------
    if GetSetting("bisNeedEnabled") then
        local bisMatched       = false
        local bisCollected     = false
        local bisBlockReason   = nil   -- set when the outgear guard fires
        local providerEnabled  = aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bisProviderEnabled
        for pName, provider in pairs(bisProviders) do
            -- Skip providers the player has disabled
            if providerEnabled and providerEnabled[pName] == false then
                Debug("  BiS check [" .. pName .. "]: DISABLED by user")
            else
            local isBiS       = provider:IsBiS(itemID)
            local isCollected = provider:IsCollected(itemID)
            local isNormal    = provider:IsNormalVersionOfBiS(itemID)
            Debug("  BiS check [" .. pName .. "]: isBiS=" .. tostring(isBiS) .. "  collected=" .. tostring(isCollected) .. "  normalOfBiS=" .. tostring(isNormal))

            if isBiS or isNormal then
                bisMatched = true
                if not isCollected then
                    -- Outgear guard ------------------------------------------------
                    -- 1. Pawn (most accurate): if it says not an upgrade, block.
                    -- 2. Fallback ilvl check: block if every slot is >30 ilvl ahead.
                    local pawnUpg = ItemUtil:PawnIsUpgrade(itemLink)
                    local blocked = false
                    if pawnUpg == false then
                        blocked = true
                        bisBlockReason = "not an upgrade (Pawn)"
                        Debug("  BiS via " .. pName .. " blocked: Pawn says not an upgrade")
                    elseif pawnUpg == nil and ItemUtil:IsSignificantDowngrade(itemLink) then
                        blocked = true
                        bisBlockReason = "outgeared (ilvl >" .. (ilvl or "?") .. ")"
                        Debug("  BiS via " .. pName .. " blocked: equipped ilvl significantly higher than " .. tostring(ilvl))
                    end
                    -- -------------------------------------------------------------

                    if blocked then
                        bisCollected = true   -- fall through to greed path below
                    else
                        RollOnLoot(rollID, ROLL_NEED)
                        self:Announce(itemLink, "NEED (BiS via " .. pName .. ")")
                        if GetSetting("bisNotifyEnabled") ~= false and SLH.Notify then
                            SLH.Notify:BiSNeed(itemLink)
                        end
                        return
                    end
                else
                    bisCollected = true
                end
            end
            end  -- provider enabled check
        end
        -- BiS item but already collected or outgeared → auto-greed
        if bisMatched and bisCollected then
            local reason = bisBlockReason or "already collected"
            Debug("  BiS item → GREED (" .. reason .. ")")
            RollOnLoot(rollID, ROLL_GREED)
            History:RecordGreed(itemID)
            self:Announce(itemLink, "GREED (BiS: " .. reason .. ")")
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
    -- Session memory: repeat whatever the player rolled last session.
    -- Guard: if the previous roll was greed but the item is now an
    -- upgrade for this character, skip and let the user decide.
    --------------------------------------------------------------------
    if GetSetting("sessionMemoryEnabled") then
        local prevRoll = sessionRolls[itemID]
        if prevRoll then
            if prevRoll == ROLL_GREED and not ItemUtil:IsEquippedBetter(itemLink) then
                Debug("  Session memory: was GREED but item is not a downgrade — skip")
            else
                RollOnLoot(rollID, prevRoll)
                if prevRoll == ROLL_GREED then History:RecordGreed(itemID) end
                self:Announce(itemLink, ROLL_LABEL[prevRoll] .. " (session)")
                return
            end
        end
    end

    --------------------------------------------------------------------
    -- History-based auto-greed
    -- Guard: do not auto-greed from history if the item could actually
    -- be an upgrade (Pawn says upgrade, or equipped ilvl is worse).
    --------------------------------------------------------------------
    if GetSetting("autoGreedOnHistory") and History:HasGreeded(itemID) then
        local historyBlocked = false
        local pawnUpg = ItemUtil:PawnIsUpgrade(itemLink)
        if pawnUpg == true then
            historyBlocked = true
            Debug("  History match: greeded before BUT Pawn says upgrade — skip history")
        elseif pawnUpg == nil and not ItemUtil:IsEquippedBetter(itemLink) then
            historyBlocked = true
            Debug("  History match: greeded before BUT equipped is not better — skip history")
        end
        if not historyBlocked then
            Debug("  History match: greeded before")
            RollOnLoot(rollID, ROLL_GREED)
            History:RecordGreed(itemID)
            self:Announce(itemLink, "GREED (history)")
            return
        end
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
