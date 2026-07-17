local addonName, SLH = ...

------------------------------------------------------------------------
-- Account-wide saved-variable defaults
------------------------------------------------------------------------
local DB_DEFAULTS = {
    greedHistory = {},
    settings = {
        autoGreedEnabled   = true,
        autoGreedOnHistory = true,
        debugMode          = false,
        ilvlGreedEnabled   = false,
        ilvlGreedThreshold = 0,
        bisNeedEnabled     = false,
    },
}

------------------------------------------------------------------------
-- Per-character saved-variable defaults
------------------------------------------------------------------------
local CHAR_DEFAULTS = {
    playMode           = "raiding",  -- "raiding" / "farming" / "carry" / "custom"
    autoRollMode       = "off",    -- "off" / "pass" / "greed" / "need"
    qualityRollMode    = "off",    -- "off" / "pass" / "greed" / "need"
    qualityThreshold   = 0,        -- 0=off, 2=Uncommon(green) or lower, 3=Rare(blue) or lower
    minimapIconEnabled = true,     -- show / hide the minimap button
    minimapAngle       = 225,      -- saved drag angle (degrees)
    sessionMemoryEnabled = true,
    armorFilterEnabled = true,
    armorFilterAction  = "pass",   -- "greed" / "pass"
    downgradeGreedEnabled = true,
    statWeights        = nil,       -- table of ITEM_MOD_X = weight (legacy, migrated)
    statWeightsName    = nil,       -- display name from Pawn string (legacy, migrated)
    statWeightSource   = "pawn",    -- "pawn" | "import"
    statWeightProfiles = nil,       -- { main = { name, weights }, offspec = { name, weights } }
    statWeightPawnMain    = nil,    -- Pawn scale name selected for main spec
    statWeightPawnOffspec = nil,    -- Pawn scale name selected for offspec
    ilvlGreedEnabled   = false,
    ilvlGreedThreshold = 0,
    bisNeedEnabled     = true,
    bisNotifyEnabled   = true,
    bisOffspecEnabled  = false,
    bisMainSpec        = nil,       -- FrogBiS/BisTooltip spec key for main spec
    bisOffspec         = nil,       -- FrogBiS/BisTooltip spec key for offspec
    bisProviderEnabled = nil,       -- { BisTooltip=true, FrogBiS=true, AtlasLoot=true } or nil (all enabled)
    transmogNeedEnabled  = false,   -- auto-need appearances not yet collected
    tierTokenNeedEnabled = true,    -- auto-need tier tokens for your class
    lockboxRollMode    = "pass",   -- "off" / "pass" / "greed" / "need"
    collectedItems     = {},
}

------------------------------------------------------------------------
-- DB initialisation
------------------------------------------------------------------------
local function InitDB()
    if not aSmoothLootHelperDB then
        aSmoothLootHelperDB = {}
    end
    for k, v in pairs(DB_DEFAULTS) do
        if aSmoothLootHelperDB[k] == nil then
            if type(v) == "table" then
                aSmoothLootHelperDB[k] = {}
                for k2, v2 in pairs(v) do
                    aSmoothLootHelperDB[k][k2] = v2
                end
            else
                aSmoothLootHelperDB[k] = v
            end
        end
    end
    -- Ensure nested settings keys exist
    for k, v in pairs(DB_DEFAULTS.settings) do
        if aSmoothLootHelperDB.settings[k] == nil then
            aSmoothLootHelperDB.settings[k] = v
        end
    end

    if not aSmoothLootHelperCharDB then
        aSmoothLootHelperCharDB = {}
    end
    for k, v in pairs(CHAR_DEFAULTS) do
        if aSmoothLootHelperCharDB[k] == nil then
            if type(v) == "table" then
                aSmoothLootHelperCharDB[k] = {}
            else
                aSmoothLootHelperCharDB[k] = v
            end
        end
    end

    -- Migration: existing characters without playMode were configured
    -- manually under the old UI. Set them to "custom" so we don't
    -- overwrite their settings unexpectedly.
    if aSmoothLootHelperCharDB._migratedPlayMode == nil then
        -- If playMode was just filled in by the default loop above but
        -- the character already had other keys set (old install), use custom.
        if aSmoothLootHelperCharDB.playMode == "raiding"
           and aSmoothLootHelperCharDB.armorFilterEnabled == false then
            aSmoothLootHelperCharDB.playMode = "custom"
        end
        aSmoothLootHelperCharDB._migratedPlayMode = true
    end

    -- Migration: old single statWeights → statWeightProfiles.main
    if aSmoothLootHelperCharDB.statWeights and not aSmoothLootHelperCharDB._migratedStatProfiles then
        aSmoothLootHelperCharDB.statWeightProfiles = {
            main = {
                name    = aSmoothLootHelperCharDB.statWeightsName or "Imported",
                weights = aSmoothLootHelperCharDB.statWeights,
            },
        }
        aSmoothLootHelperCharDB.statWeightSource = "import"
        aSmoothLootHelperCharDB._migratedStatProfiles = true
    end
end

------------------------------------------------------------------------
-- Slash commands  /slh
------------------------------------------------------------------------
local function HandleSlash(msg)
    local cmd, arg1 = (msg or ""):lower():trim():match("^(%S*)%s*(.-)$")

    if cmd == "" then
        -- Open options panel
        if InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("aSmoothLootHelper")
            InterfaceOptionsFrame_OpenToCategory("aSmoothLootHelper") -- call twice (Blizzard quirk)
        elseif Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(SLH._settingsCategoryID)
        end

    elseif cmd == "on" then
        aSmoothLootHelperDB.settings.autoGreedEnabled = true
        print("|cff00ccff[SLH]|r Enabled.")

    elseif cmd == "off" then
        aSmoothLootHelperDB.settings.autoGreedEnabled = false
        print("|cff00ccff[SLH]|r Disabled.")

    elseif cmd == "mode" then
        -- New preset modes
        local presets = { raid = "raiding", raiding = "raiding", farm = "farming", farming = "farming",
                          carry = "carry", boost = "carry", custom = "custom" }
        if presets[arg1] then
            SLH.Options:ApplyMode(presets[arg1])
            local labels = { raiding = "Raiding (smart)", farming = "Farming / Solo", carry = "Carry / Boost", custom = "Custom" }
            print("|cff00ccff[SLH]|r Mode set to: " .. labels[presets[arg1]])
        else
            -- Legacy auto-roll override modes
            local valid = { off = true, pass = true, greed = true, need = true }
            if valid[arg1] then
                aSmoothLootHelperCharDB.autoRollMode = arg1
                if arg1 == "off" then
                    print("|cff00ccff[SLH]|r Auto-roll mode disabled.")
                else
                    print("|cff00ccff[SLH]|r Auto-roll mode set to " .. arg1:upper() .. " for this character (resets on logout).")
                end
            else
                print("|cff00ccff[SLH]|r Usage: /slh mode raid|farm|carry|custom  OR  /slh mode off|pass|greed|need")
            end
        end

    elseif cmd == "session" then
        local cdb = aSmoothLootHelperCharDB
        if arg1 == "clear" then
            SLH.RollManager:ClearSession()
            print("|cff00ccff[SLH]|r Session memory cleared.")
        else
            cdb.sessionMemoryEnabled = not cdb.sessionMemoryEnabled
            local state = cdb.sessionMemoryEnabled and "enabled" or "disabled"
            print("|cff00ccff[SLH]|r Session memory " .. state .. ".")
        end

    elseif cmd == "quality" then
        local valid = { off = true, pass = true, greed = true, need = true }
        local parts = { strsplit(" ", arg1) }
        local action = parts[1]
        local qual   = parts[2]
        if valid[action] and (qual == "green" or qual == "rare") then
            aSmoothLootHelperCharDB.qualityRollMode  = action
            aSmoothLootHelperCharDB.qualityThreshold = (qual == "green") and 2 or 3
            if action == "off" then
                print("|cff00ccff[SLH]|r Quality auto-roll disabled.")
            else
                print("|cff00ccff[SLH]|r Auto-" .. action:upper() .. " on " .. qual .. " quality or lower.")
            end
        elseif action == "off" then
            aSmoothLootHelperCharDB.qualityRollMode  = "off"
            aSmoothLootHelperCharDB.qualityThreshold = 0
            print("|cff00ccff[SLH]|r Quality auto-roll disabled.")
        else
            print("|cff00ccff[SLH]|r Usage: /slh quality <pass|greed|need|off> <green|rare>")
        end

    elseif cmd == "armor" then
        local cdb = aSmoothLootHelperCharDB
        if arg1 == "off" then
            cdb.armorFilterEnabled = false
            print("|cff00ccff[SLH]|r Armor-type filter disabled.")
        elseif arg1 == "greed" or arg1 == "pass" then
            cdb.armorFilterEnabled = true
            cdb.armorFilterAction  = arg1
            print("|cff00ccff[SLH]|r Off-armor items will auto-" .. arg1:upper() .. ".")
        else
            print("|cff00ccff[SLH]|r Usage: /slh armor off|greed|pass")
        end

    elseif cmd == "ilvl" then
        if arg1 == "off" then
            aSmoothLootHelperCharDB.ilvlGreedEnabled = false
            print("|cff00ccff[SLH]|r iLvl auto-greed disabled for this character.")
        else
            local threshold = tonumber(arg1)
            if threshold and threshold >= 0 then
                aSmoothLootHelperCharDB.ilvlGreedEnabled   = true
                aSmoothLootHelperCharDB.ilvlGreedThreshold = threshold
                print("|cff00ccff[SLH]|r iLvl auto-greed set to <= " .. threshold .. " for this character.")
            else
                print("|cff00ccff[SLH]|r Usage: /slh ilvl <number> | /slh ilvl off")
            end
        end

    elseif cmd == "history" then
        local history = SLH.History:GetAll()
        local count   = SLH.History:GetCount()
        print("|cff00ccff[SLH]|r Greed history: " .. count .. " unique items tracked.")
        if count > 0 and count <= 20 then
            for itemID, entry in pairs(history) do
                local _, link = GetItemInfo(itemID)
                local display = link or ("itemID:" .. itemID)
                print("  " .. display .. " x" .. entry.count)
            end
        elseif count > 20 then
            print("  (Too many to list. Use /slh reset to clear.)")
        end

    elseif cmd == "bis" then
        SLH.BisPreview:Toggle()

    elseif cmd == "debuglog" then
        SLH.DebugLog:Toggle()

    elseif cmd == "reset" then
        SLH.History:Reset()
        print("|cff00ccff[SLH]|r Greed history cleared.")

    elseif cmd == "status" then
        local db   = aSmoothLootHelperDB.settings
        local cdb  = aSmoothLootHelperCharDB
        print("|cff00ccff[SLH]|r --- Status ---")
        print("  Enabled:          " .. tostring(db.autoGreedEnabled))
        print("  History greed:    " .. tostring(db.autoGreedOnHistory))
        print("  Auto-roll mode:   " .. tostring(cdb.autoRollMode))
        print("  Session memory:   " .. tostring(cdb.sessionMemoryEnabled))
        local qualLabels = { [0] = "off", [2] = "green or lower", [3] = "rare or lower" }
        print("  Quality roll:     " .. tostring(cdb.qualityRollMode) ..
              " (" .. (qualLabels[cdb.qualityThreshold or 0] or "off") .. ")")
        print("  Armor filter:     " .. tostring(cdb.armorFilterEnabled) ..
              " (off-type → " .. tostring(cdb.armorFilterAction) .. ")")
        print("  Downgrade greed:  " .. tostring(cdb.downgradeGreedEnabled))
        print("  iLvl greed:       " .. tostring(cdb.ilvlGreedEnabled) ..
              " (threshold: " .. tostring(cdb.ilvlGreedThreshold) .. ")")
        print("  BiS need:         " .. tostring(cdb.bisNeedEnabled))
        print("  BiS offspec:      " .. tostring(cdb.bisOffspecEnabled))
        local providers = SLH.RollManager:GetBiSProviders()
        local names = {}
        for name in pairs(providers) do names[#names + 1] = name end
        if #names > 0 then
            print("  BiS providers:    " .. table.concat(names, ", "))
        else
            print("  BiS providers:    (none detected)")
        end
        print("  History entries:  " .. SLH.History:GetCount())

    else
        print("|cff00ccff[SLH]|r aSmoothLootHelper commands:")
        print("  /slh            - Open options panel")
        print("  /slh on|off     - Enable / disable addon")
        print("  /slh mode <m>   - Auto-roll mode: off|pass|greed|need (resets on logout)")
        print("  /slh session    - Toggle session memory (repeat your last roll)")
        print("  /slh session clear - Clear session memory")
        print("  /slh quality <action> <green|rare> - Auto-roll on items of quality or lower")
        print("  /slh quality off - Disable quality auto-roll")
        print("  /slh armor greed|pass - Auto-roll off-armor-type items")
        print("  /slh armor off  - Disable armor-type filter")
        print("  /slh ilvl <N>   - Set iLvl threshold for this character")
        print("  /slh ilvl off   - Disable iLvl auto-greed")
        print("  /slh bis        - Open BiS preview window")
        print("  /slh debuglog   - Open/close the debug log viewer")
        print("  /slh history    - Show greed history summary")
        print("  /slh reset      - Clear greed history")
        print("  /slh status     - Show current settings")
    end
end

SLASH_ASMOOTHLOOTHELPER1 = "/slh"
SlashCmdList["ASMOOTHLOOTHELPER"] = HandleSlash

------------------------------------------------------------------------
-- Public API for external addons
------------------------------------------------------------------------
function SLH:RegisterBiSProvider(providerName, providerTable)
    SLH.RollManager:RegisterBiSProvider(providerName, providerTable)
end

-- Global reference so external addons can call:
--   aSmoothLootHelper:RegisterBiSProvider(name, table)
aSmoothLootHelper = SLH

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function()
    InitDB()
    SLH.History:MigrateFromAccount()
    SLH.Options:BuildPanel()
    SLH.BisPreview:Init()
    SLH.MinimapIcon:Init()
    print("|cff00ccff[SLH]|r v1.2.2 loaded. Use /slh for help.")
end)
