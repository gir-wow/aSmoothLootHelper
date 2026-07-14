local _, SLH = ...
SLH.Options = {}

local Options = SLH.Options

------------------------------------------------------------------------
-- Options panel (Interface → AddOns → aSmoothLootHelper)
------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "aSmoothLootHelper"

-- Scrollable content area
local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 4, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)

local content = CreateFrame("Frame")
content:SetSize(460, 1400)
scrollFrame:SetScrollChild(content)

local FONT_HEADER = "GameFontNormalLarge"
local FONT_NORMAL = "GameFontHighlight"
local FONT_SMALL  = "GameFontHighlightSmall"
local LEFT_MARGIN = 16

local widgets = {}
local dropdownCount = 0

------------------------------------------------------------------------
-- Mode preset definitions
------------------------------------------------------------------------
local MODE_PRESETS = {
    raiding = {
        armorFilterEnabled    = true,
        armorFilterAction     = "pass",
        bisNeedEnabled        = true,
        downgradeGreedEnabled = true,
        qualityRollMode       = "off",
        qualityThreshold      = 0,
        autoRollMode          = "off",
        sessionMemoryEnabled  = true,
        tierTokenNeedEnabled  = true,
        transmogNeedEnabled   = false,
    },
    farming = {
        armorFilterEnabled    = false,
        bisNeedEnabled        = false,
        downgradeGreedEnabled = false,
        qualityRollMode       = "greed",
        qualityThreshold      = 3,
        autoRollMode          = "greed",
        sessionMemoryEnabled  = true,
        tierTokenNeedEnabled  = false,
        transmogNeedEnabled   = false,
    },
    carry = {
        armorFilterEnabled    = false,
        bisNeedEnabled        = false,
        downgradeGreedEnabled = false,
        qualityRollMode       = "off",
        qualityThreshold      = 0,
        autoRollMode          = "pass",
        sessionMemoryEnabled  = false,
        tierTokenNeedEnabled  = false,
        transmogNeedEnabled   = false,
    },
    -- "custom" does not write any settings
}

------------------------------------------------------------------------
-- Apply a mode preset — writes all relevant charDB keys
------------------------------------------------------------------------
function Options:ApplyMode(modeName)
    local charDB = aSmoothLootHelperCharDB
    charDB.playMode = modeName
    local preset = MODE_PRESETS[modeName]
    if preset then
        for key, value in pairs(preset) do
            charDB[key] = value
        end
    end
    -- Refresh widgets if panel is visible
    if panel:IsVisible() then
        self:Refresh()
    end
end

------------------------------------------------------------------------
-- Helpers — all parented to content (the scroll child)
------------------------------------------------------------------------
local function GetDB(dbTable, dbKey, default)
    local val = dbTable[dbKey]
    if val == nil then return default end
    return val
end

local function CreateTitle(y, text)
    local fs = content:CreateFontString(nil, "OVERLAY", FONT_HEADER)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    fs:SetText(text)
    return fs
end

local function CreateSeparator(y, text)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    fs:SetText("|cffffffff" .. text .. "|r")
    -- Horizontal line below the text
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.6, 0.5, 0.2, 0.6)
    line:SetSize(420, 1)
    line:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y - 16)
    return fs
end

local function CreateHelpText(y, text)
    local fs = content:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 30, y)
    fs:SetWidth(380)
    fs:SetJustifyH("LEFT")
    fs:SetText("|cff999999" .. text .. "|r")
    return fs
end

local function CreateInfoText(y, text)
    local fs = content:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    fs:SetWidth(420)
    fs:SetJustifyH("LEFT")
    fs:SetText("|cffbbbbbb" .. text .. "|r")
    return fs
end

local function CreateCheckbox(y, label, dbTable, dbKey, default)
    local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    cb.Text:SetText(label)
    cb:SetScript("OnClick", function(self)
        dbTable[dbKey] = self:GetChecked() and true or false
    end)
    widgets[#widgets + 1] = { type = "check", widget = cb, dbTable = dbTable, dbKey = dbKey, default = default or false }
    return cb
end

local function CreateSlider(y, label, dbTable, dbKey, minVal, maxVal, step)
    local fs = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    fs:SetText(label)

    local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y - 18)
    slider:SetWidth(200)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    local valBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    valBox:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valBox:SetSize(52, 20)
    valBox:SetAutoFocus(false)
    valBox:SetNumeric(true)
    valBox:SetMaxLetters(4)

    local initVal = GetDB(dbTable, dbKey, minVal)
    initVal = math.floor(initVal + 0.5)
    valBox:SetText(tostring(initVal))
    slider:SetValue(initVal)

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        dbTable[dbKey] = value
        valBox:SetText(tostring(value))
    end)

    valBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or minVal
        val = math.max(minVal, math.min(maxVal, math.floor(val + 0.5)))
        dbTable[dbKey] = val
        slider:SetValue(val)
        self:ClearFocus()
    end)
    valBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(GetDB(dbTable, dbKey, minVal)))
        self:ClearFocus()
    end)

    widgets[#widgets + 1] = { type = "slider", widget = slider, dbTable = dbTable, dbKey = dbKey, valText = valBox, default = minVal }
    return slider
end

local function CreateDropdown(y, label, dbTable, dbKey, choices, default)
    dropdownCount = dropdownCount + 1
    local frameName = "SLHDropdown" .. dropdownCount

    local fs = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    fs:SetText(label)

    local dropdown = CreateFrame("Frame", frameName, content, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN - 12, y - 16)

    local function GetLabel(value)
        for _, c in ipairs(choices) do
            if c.value == value then return c.label end
        end
        return tostring(value or "")
    end

    UIDropDownMenu_SetWidth(dropdown, 180)

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = c.label
            info.value    = c.value
            info.checked  = (GetDB(dbTable, dbKey, default) == c.value)
            info.func     = function(btn)
                dbTable[dbKey] = btn.value
                UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                UIDropDownMenu_SetText(dropdown, GetLabel(btn.value))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local initVal = GetDB(dbTable, dbKey, default or choices[1].value)
    UIDropDownMenu_SetSelectedValue(dropdown, initVal)
    UIDropDownMenu_SetText(dropdown, GetLabel(initVal))

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local val = GetDB(dbTable, dbKey, default or choices[1].value)
            UIDropDownMenu_SetSelectedValue(dropdown, val)
            UIDropDownMenu_SetText(dropdown, GetLabel(val))
        end,
    }
    return dropdown
end

------------------------------------------------------------------------
-- Build panel contents once the DB is ready
------------------------------------------------------------------------

-- Two panels: main (General) and child (Advanced)
local advPanel = CreateFrame("Frame")
advPanel.name = "Advanced"

-- Scrollable content for advanced panel
local advScrollFrame = CreateFrame("ScrollFrame", nil, advPanel, "UIPanelScrollFrameTemplate")
advScrollFrame:SetPoint("TOPLEFT", 4, -4)
advScrollFrame:SetPoint("BOTTOMRIGHT", -26, 4)

local advContent = CreateFrame("Frame")
advContent:SetSize(460, 1400)
advScrollFrame:SetScrollChild(advContent)

function Options:BuildPanel()
    local db      = aSmoothLootHelperDB.settings
    local charDB  = aSmoothLootHelperCharDB

    local y = -16

    -- Title
    CreateTitle(y, "aSmoothLootHelper")
    y = y - 28

    local desc = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    desc:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    desc:SetText("Automatically roll on loot based on rules, history, and BiS lists.")
    y = y - 30

    ---------- General ----------
    CreateCheckbox(y, "Enable aSmoothLootHelper", db, "autoGreedEnabled", true)
    y = y - 28
    CreateCheckbox(y, "Show minimap icon", charDB, "minimapIconEnabled", true)
    y = y - 34

    ---------- PLAY MODE ----------
    CreateSeparator(y, "PLAY MODE")
    y = y - 24

    local modeChoices = {
        { value = "raiding", label = "Raiding (smart)" },
        { value = "farming", label = "Farming / Solo" },
        { value = "carry",   label = "Carry / Boost" },
        { value = "custom",  label = "Custom" },
    }

    dropdownCount = dropdownCount + 1
    local modeFrameName = "SLHDropdown" .. dropdownCount

    local modeFs = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    modeFs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    modeFs:SetText("Mode:")

    local modeDropdown = CreateFrame("Frame", modeFrameName, content, "UIDropDownMenuTemplate")
    modeDropdown:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN - 12, y - 16)
    UIDropDownMenu_SetWidth(modeDropdown, 180)

    local function GetModeLabel(value)
        for _, c in ipairs(modeChoices) do
            if c.value == value then return c.label end
        end
        return tostring(value or "")
    end

    UIDropDownMenu_Initialize(modeDropdown, function(self, level)
        for _, c in ipairs(modeChoices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = c.label
            info.value    = c.value
            info.checked  = (GetDB(charDB, "playMode", "raiding") == c.value)
            info.func     = function(btn)
                Options:ApplyMode(btn.value)
                UIDropDownMenu_SetSelectedValue(modeDropdown, btn.value)
                UIDropDownMenu_SetText(modeDropdown, GetModeLabel(btn.value))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local modeInit = GetDB(charDB, "playMode", "raiding")
    UIDropDownMenu_SetSelectedValue(modeDropdown, modeInit)
    UIDropDownMenu_SetText(modeDropdown, GetModeLabel(modeInit))

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local val = GetDB(charDB, "playMode", "raiding")
            UIDropDownMenu_SetSelectedValue(modeDropdown, val)
            UIDropDownMenu_SetText(modeDropdown, GetModeLabel(val))
        end,
    }
    y = y - 46

    CreateInfoText(y, "Raiding — armor filter on, BiS need, downgrade greed, tier tokens")
    y = y - 16
    CreateInfoText(y, "Farming — greed everything, skip trash quality checks")
    y = y - 16
    CreateInfoText(y, "Carry — pass everything to your group")
    y = y - 16
    CreateInfoText(y, "Custom — use the advanced settings below as-is")
    y = y - 28

    ---------- ARMOR TYPE ----------
    CreateSeparator(y, "ARMOR TYPE")
    y = y - 24

    local armorInfoLabel = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    armorInfoLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local armorType = SLH.ItemUtil and SLH.ItemUtil:GetPlayerArmorType() or "?"
            local className = UnitClass("player")
            armorInfoLabel:SetText("Detected: |cffffffff" .. (armorType or "?") .. "|r  (" .. (className or "?") .. ")")
        end,
    }
    y = y - 22

    CreateDropdown(y, "Off-type armor action:", charDB, "armorFilterAction", {
        { value = "pass",  label = "Pass" },
        { value = "greed", label = "Greed" },
    }, "pass")
    y = y - 46

    CreateInfoText(y, "In MoP, wearing your main armor type grants +5% primary stat.\nOff-type items are handled automatically when in Raiding mode.")
    y = y - 36

    ---------- BIS AUTO-NEED ----------
    CreateSeparator(y, "BIS AUTO-NEED")
    y = y - 24

    CreateCheckbox(y, "Auto-need BiS items", charDB, "bisNeedEnabled", true)
    y = y - 26
    CreateHelpText(y, "All enabled providers are queried; first match wins.")
    y = y - 24

    -- Per-provider enable/disable checkboxes
    -- Ensure the table exists
    if not charDB.bisProviderEnabled then
        charDB.bisProviderEnabled = {}
    end

    local knownProviders = { "BisTooltip", "FrogBiS", "AtlasLoot" }
    for _, pName in ipairs(knownProviders) do
        local providers = SLH.RollManager:GetBiSProviders()
        local isInstalled = providers[pName] ~= nil

        -- Default to enabled if not explicitly set
        if charDB.bisProviderEnabled[pName] == nil then
            charDB.bisProviderEnabled[pName] = true
        end

        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 24, y)
        if isInstalled then
            local isEnabled = charDB.bisProviderEnabled[pName]
            cb.Text:SetText("|cff00ff00" .. pName .. "|r")
            cb:SetChecked(isEnabled)
        else
            cb.Text:SetText("|cff666666" .. pName .. "  (not installed)|r")
            cb:SetChecked(false)
            cb:Disable()
        end
        cb:SetScript("OnClick", function(self)
            charDB.bisProviderEnabled[pName] = self:GetChecked() and true or false
        end)

        -- Store for refresh
        local capturedName = pName
        widgets[#widgets + 1] = {
            type = "custom",
            refresh = function()
                local provs = SLH.RollManager:GetBiSProviders()
                local installed = provs[capturedName] ~= nil
                if installed then
                    cb.Text:SetText("|cff00ff00" .. capturedName .. "|r")
                    cb:Enable()
                    cb:SetChecked(charDB.bisProviderEnabled[capturedName] ~= false)
                else
                    cb.Text:SetText("|cff666666" .. capturedName .. "  (not installed)|r")
                    cb:SetChecked(false)
                    cb:Disable()
                end
            end,
        }
        y = y - 22
    end
    y = y - 4

    -- BisTooltip phase info
    local btPhaseLabel = content:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    btPhaseLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 30, y)
    btPhaseLabel:SetWidth(380)
    btPhaseLabel:SetJustifyH("LEFT")
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            if BistooltipAddon and BistooltipAddon.db and BistooltipAddon.db.char then
                local phase = BistooltipAddon.db.char.phase_index or "?"
                local src = BistooltipAddon.db.char.data_source or "?"
                btPhaseLabel:SetText("|cff999999BisTooltip phase: |cffffffff" .. tostring(phase)
                    .. "|cff999999  source: |cffffffff" .. tostring(src)
                    .. "|cff999999\n(Change phase/source in BisTooltip's own settings)|r")
            else
                btPhaseLabel:SetText("")
            end
        end,
    }
    y = y - 32

    -- Spec selection for BiS lists (main + offspec)

    -- BisTooltip spec names per class (MoP — static data)
    -- Maps WoW API spec name → BisTooltip spec name where they differ
    local BT_SPEC_MAP = {
        -- DK
        ["Blood"]         = "Blood tank",
        ["Frost"]         = "Frost",
        ["Unholy"]        = "Unholy",
        -- Druid
        ["Balance"]       = "Balance",
        ["Feral"]         = "Feral",
        ["Guardian"]      = "Guardian",
        ["Restoration"]   = "Restoration",
        -- Hunter
        ["Beast Mastery"]  = "Beast mastery",
        ["Marksmanship"]  = "Marksmanship",
        ["Survival"]      = "Survival",
        -- Mage
        ["Arcane"]        = "Arcane",
        ["Fire"]          = "Fire",
        -- Monk
        ["Brewmaster"]    = "Brewmaster",
        ["Mistweaver"]    = "Mistweaver",
        ["Windwalker"]    = "Windwalker",
        -- Paladin
        ["Holy"]          = "Holy",
        ["Protection"]    = "Protection",
        ["Retribution"]   = "Retribution",
        -- Priest
        ["Discipline"]    = "Discipline",
        ["Shadow"]        = "Shadow",
        -- Rogue
        ["Assassination"] = "Assassination",
        ["Combat"]        = "Combat",
        ["Subtlety"]      = "Subtlety",
        -- Shaman
        ["Elemental"]     = "Elemental",
        ["Enhancement"]   = "Enhancement",
        -- Warlock
        ["Affliction"]    = "Affliction",
        ["Demonology"]    = "Demonology",
        ["Destruction"]   = "Destruction",
        -- Warrior
        ["Arms"]          = "Arms",
        ["Fury"]          = "Fury",
    }

    local CLASS_TOKEN_TO_FROG = {
        DEATHKNIGHT = "Death Knight", DRUID = "Druid", HUNTER = "Hunter",
        MAGE = "Mage", MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest",
        ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
    }

    -- Get the player's dual spec names (MoP dual spec)
    local function GetPlayerSpecNames()
        local specs = {}
        local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
                        or GetSpecialization
        local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
                        or GetSpecializationInfo
        local getGroup = GetActiveSpecGroup

        if getSpec and getInfo then
            -- Active spec group
            local activeGroup = getGroup and getGroup() or 1
            for group = 1, 2 do
                local idx = getSpec(false, false, group)
                if idx and idx > 0 then
                    local _, specName = getInfo(idx)
                    if specName then
                        if group == activeGroup then
                            specs.active = specName
                        else
                            specs.inactive = specName
                        end
                    end
                end
            end
        end
        return specs
    end

    -- Show all class specs toggle (persisted in charDB)
    local showAllSpecs = charDB.bisShowAllSpecs or false

    local function GetBiSSpecChoices(forOffspec)
        local choices = {}
        if forOffspec then
            choices[#choices + 1] = { value = "_none_", label = "None (disabled)" }
        end
        choices[#choices + 1] = { value = "", label = "(auto-detect)" }

        local seen = {}
        local _, classToken = UnitClass("player")
        local playerSpecs = GetPlayerSpecNames()
        local frogClass = CLASS_TOKEN_TO_FROG[classToken]

        -- Determine which WoW spec names to show
        local allowedSpecs = nil  -- nil = show all
        if not showAllSpecs and (playerSpecs.active or playerSpecs.inactive) then
            allowedSpecs = {}
            if playerSpecs.active then allowedSpecs[playerSpecs.active] = true end
            if playerSpecs.inactive then allowedSpecs[playerSpecs.inactive] = true end
        end

        -- Add BisTooltip entries from Bistooltip_wh_bislists (or active source)
        -- Structure: bislists[className][specName][phaseName] = { slot items }
        local btBislists = Bistooltip_wh_bislists
        if btBislists then
            local CLASS_TOKEN_TO_BT = {
                DEATHKNIGHT = "Death knight", DRUID = "Druid", HUNTER = "Hunter",
                MAGE = "Mage", MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest",
                ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
            }
            local btClass = CLASS_TOKEN_TO_BT[classToken]
            local classData = btClass and btBislists[btClass]

            if classData then
                for specName, phaseTable in pairs(classData) do
                    if type(phaseTable) == "table" then
                        -- Check if this spec matches allowed specs (filtered mode)
                        local specMatched = true
                        if allowedSpecs then
                            specMatched = false
                            local btBase = BT_SPEC_MAP[playerSpecs.active] or playerSpecs.active
                            local btInactive = playerSpecs.inactive and (BT_SPEC_MAP[playerSpecs.inactive] or playerSpecs.inactive)
                            if specName == btBase or specName == btInactive then
                                specMatched = true
                            end
                        end

                        if specMatched then
                            -- Add each phase as a separate entry
                            for phaseName, phaseData in pairs(phaseTable) do
                                if type(phaseData) == "table" then
                                    local key = specName .. " / " .. phaseName
                                    if not seen[key] then
                                        seen[key] = true
                                        choices[#choices + 1] = { value = key, label = key .. "  (BisTooltip)" }
                                    end
                                end
                            end
                            -- Also add the base spec name (matches all phases)
                            if not seen[specName] then
                                seen[specName] = true
                                choices[#choices + 1] = { value = specName, label = specName .. " (all phases)  (BisTooltip)" }
                            end
                        end
                    end
                end
            end
        elseif Bistooltip_items then
            -- Fallback: scan Bistooltip_items for spec names if bislists not available
            local CLASS_TOKEN_TO_BT = {
                DEATHKNIGHT = "Death knight", DRUID = "Druid", HUNTER = "Hunter",
                MAGE = "Mage", MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest",
                ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
            }
            local btClass = CLASS_TOKEN_TO_BT[classToken]
            if btClass then
                local discoveredSpecs = {}
                for itemID, entries in pairs(Bistooltip_items) do
                    for _, entry in ipairs(entries) do
                        if entry.class_name == btClass and entry.spec_name then
                            discoveredSpecs[entry.spec_name] = true
                        end
                    end
                end
                for specName in pairs(discoveredSpecs) do
                    if not seen[specName] then
                        seen[specName] = true
                        choices[#choices + 1] = { value = specName, label = specName .. "  (BisTooltip)" }
                    end
                end
            end
        end

        -- Add FrogBiS entries for matching specs + custom named sets
        if FrogBiS_Templates and frogClass then
            local frogSpecsToList = {}
            if allowedSpecs then
                for wowName in pairs(allowedSpecs) do
                    local frogKey = wowName .. " " .. frogClass
                    if FrogBiS_Templates[frogKey] then
                        frogSpecsToList[#frogSpecsToList + 1] = frogKey
                    end
                end
            else
                for specKey in pairs(FrogBiS_Templates) do
                    if specKey:find(frogClass, 1, true) then
                        frogSpecsToList[#frogSpecsToList + 1] = specKey
                    end
                end
            end

            for _, frogKey in ipairs(frogSpecsToList) do
                -- Add the base spec template
                if not seen[frogKey] then
                    seen[frogKey] = true
                    choices[#choices + 1] = { value = frogKey, label = frogKey .. "  (FrogBiS)" }
                end

                -- Add all custom named sets for this spec from FrogBiSDB
                if FrogBiSDB and FrogBiSDB.sets and FrogBiSDB.sets[frogKey] then
                    for i, s in ipairs(FrogBiSDB.sets[frogKey]) do
                        if s.name and s.items and #s.items > 0 then
                            local setKey = frogKey .. "::" .. s.name
                            if not seen[setKey] then
                                seen[setKey] = true
                                choices[#choices + 1] = { value = setKey, label = "  " .. s.name .. "  (FrogBiS set)" }
                            end
                        end
                    end
                end
            end
        end

        table.sort(choices, function(a, b)
            if a.value == "_none_" then return true end
            if b.value == "_none_" then return false end
            if a.value == "" then return true end
            if b.value == "" then return false end
            return a.label < b.label
        end)
        return choices
    end

    -- "Show all class specs" checkbox
    local showAllCb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    showAllCb:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 24, y)
    showAllCb.Text:SetText("Show all class specs")
    showAllCb:SetChecked(showAllSpecs)
    showAllCb:SetScript("OnClick", function(self)
        showAllSpecs = self:GetChecked() and true or false
        charDB.bisShowAllSpecs = showAllSpecs
    end)
    widgets[#widgets + 1] = { type = "check", widget = showAllCb, dbTable = charDB, dbKey = "bisShowAllSpecs", default = false }
    y = y - 26

    -- Main spec BiS list dropdown
    local bisMainLabel = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    bisMainLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    bisMainLabel:SetText("Main spec BiS list:")

    dropdownCount = dropdownCount + 1
    local bisMainDD = CreateFrame("Frame", "SLHDropdown" .. dropdownCount, content, "UIDropDownMenuTemplate")
    bisMainDD:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN - 12, y - 16)
    UIDropDownMenu_SetWidth(bisMainDD, 200)

    UIDropDownMenu_Initialize(bisMainDD, function(self, level)
        local choices = GetBiSSpecChoices(false)
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = c.label
            info.value   = c.value
            info.checked = ((charDB.bisMainSpec or "") == c.value)
            info.func    = function(btn)
                charDB.bisMainSpec = (btn.value ~= "") and btn.value or nil
                UIDropDownMenu_SetText(bisMainDD, c.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(bisMainDD, charDB.bisMainSpec or "(auto-detect)")

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            UIDropDownMenu_SetText(bisMainDD, charDB.bisMainSpec or "(auto-detect)")
        end,
    }
    y = y - 44

    -- Offspec BiS list dropdown
    local bisOffLabel = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    bisOffLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    bisOffLabel:SetText("Offspec BiS list:")

    dropdownCount = dropdownCount + 1
    local bisOffDD = CreateFrame("Frame", "SLHDropdown" .. dropdownCount, content, "UIDropDownMenuTemplate")
    bisOffDD:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN - 12, y - 16)
    UIDropDownMenu_SetWidth(bisOffDD, 200)

    UIDropDownMenu_Initialize(bisOffDD, function(self, level)
        local choices = GetBiSSpecChoices(true)
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = c.label
            info.value   = c.value
            info.checked = ((charDB.bisOffspec or "_none_") == c.value)
            info.func    = function(btn)
                charDB.bisOffspec = (btn.value ~= "_none_" and btn.value ~= "") and btn.value or nil
                UIDropDownMenu_SetText(bisOffDD, c.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(bisOffDD, charDB.bisOffspec or "None (disabled)")

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            UIDropDownMenu_SetText(bisOffDD, charDB.bisOffspec or "None (disabled)")
        end,
    }
    y = y - 44

    CreateHelpText(y, "Select which spec's BiS list to track.\nAuto-detect uses your current active spec.")
    y = y - 28

    CreateCheckbox(y, "Include off-spec items", charDB, "bisOffspecEnabled", false)
    y = y - 26
    CreateCheckbox(y, "On-screen notification on BiS need", charDB, "bisNotifyEnabled", true)
    y = y - 30

    ---------- TIER TOKENS ----------
    CreateSeparator(y, "TIER TOKENS")
    y = y - 24

    CreateCheckbox(y, "Auto-need tier tokens for your class", charDB, "tierTokenNeedEnabled", true)
    y = y - 26
    CreateHelpText(y, "Needs tokens matching your class group\n(Protector/Conqueror/Vanquisher). Skips if the\nequipped slot's ilvl is already higher.\nPasses wrong-class tokens automatically.")
    y = y - 56

    ---------- TRANSMOG ----------
    CreateSeparator(y, "TRANSMOG")
    y = y - 24

    CreateCheckbox(y, "Need appearances not yet collected", charDB, "transmogNeedEnabled", false)
    y = y - 26
    CreateHelpText(y, "Auto-needs any item whose appearance you\nhaven't learned yet. Runs before the armor\nfilter so off-type appearances are included.")
    y = y - 44

    -- Set main panel content height
    content:SetHeight(math.abs(y) + 30)

    ---------- ADVANCED SETTINGS (separate sub-panel) ----------
    local advancedFrame = advContent

    local ay = -16

    -- Advanced panel title
    local advTitleFs = advancedFrame:CreateFontString(nil, "OVERLAY", FONT_HEADER)
    advTitleFs:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN, ay)
    advTitleFs:SetText("aSmoothLootHelper — Advanced")
    ay = ay - 28

    local function AdvCreateTitle(text)
        local fs = advancedFrame:CreateFontString(nil, "OVERLAY", FONT_HEADER)
        fs:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN, ay)
        fs:SetText(text)
        ay = ay - 28
        return fs
    end

    local function AdvCreateHelpText(text)
        local fs = advancedFrame:CreateFontString(nil, "OVERLAY", FONT_SMALL)
        fs:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 30, ay)
        fs:SetWidth(380)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cff999999" .. text .. "|r")
        return fs
    end

    local function AdvCreateCheckbox(label, dbTable, dbKey, default)
        local cb = CreateFrame("CheckButton", nil, advancedFrame, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN, ay)
        cb.Text:SetText(label)
        cb:SetScript("OnClick", function(self)
            dbTable[dbKey] = self:GetChecked() and true or false
        end)
        widgets[#widgets + 1] = { type = "check", widget = cb, dbTable = dbTable, dbKey = dbKey, default = default or false }
        ay = ay - 26
        return cb
    end

    local function AdvCreateDropdown(label, dbTable, dbKey, choices, default)
        dropdownCount = dropdownCount + 1
        local frameName = "SLHDropdown" .. dropdownCount

        local fs = advancedFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
        fs:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 4, ay)
        fs:SetText(label)

        local dropdown = CreateFrame("Frame", frameName, advancedFrame, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN - 12, ay - 16)

        local function GetLabel(value)
            for _, c in ipairs(choices) do
                if c.value == value then return c.label end
            end
            return tostring(value or "")
        end

        UIDropDownMenu_SetWidth(dropdown, 160)
        UIDropDownMenu_Initialize(dropdown, function(self, level)
            for _, c in ipairs(choices) do
                local info = UIDropDownMenu_CreateInfo()
                info.text     = c.label
                info.value    = c.value
                info.checked  = (GetDB(dbTable, dbKey, default) == c.value)
                info.func     = function(btn)
                    dbTable[dbKey] = btn.value
                    UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                    UIDropDownMenu_SetText(dropdown, GetLabel(btn.value))
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        local initVal = GetDB(dbTable, dbKey, default or choices[1].value)
        UIDropDownMenu_SetSelectedValue(dropdown, initVal)
        UIDropDownMenu_SetText(dropdown, GetLabel(initVal))

        widgets[#widgets + 1] = {
            type = "custom",
            refresh = function()
                local val = GetDB(dbTable, dbKey, default or choices[1].value)
                UIDropDownMenu_SetSelectedValue(dropdown, val)
                UIDropDownMenu_SetText(dropdown, GetLabel(val))
            end,
        }
        ay = ay - 46
        return dropdown
    end

    -- Session Memory
    AdvCreateCheckbox("Session memory (repeat last roll)", charDB, "sessionMemoryEnabled", true)
    AdvCreateHelpText("Tracks what you roll this session.\nSame item dropping again gets the same\nroll. Clears on logout.")
    ay = ay - 40

    -- History auto-greed
    AdvCreateCheckbox("Auto-greed previously greeded items", db, "autoGreedOnHistory", true)
    AdvCreateHelpText("Items you've greeded before on this character\nare auto-greeded again.")
    ay = ay - 40

    -- Downgrade greed
    AdvCreateCheckbox("Auto-greed downgrades (Pawn / stat weights / ilvl)", charDB, "downgradeGreedEnabled", true)
    AdvCreateHelpText("Uses Pawn or stat weights to compare drops\nvs. equipped gear. Worse items are greeded.")
    ay = ay - 40

    -- Stat Weights (multi-spec)
    AdvCreateTitle("Stat Weights")

    -- Source selector
    local srcLabel = advancedFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    srcLabel:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 4, ay)
    srcLabel:SetText("Source:")

    dropdownCount = dropdownCount + 1
    local srcDropdown = CreateFrame("Frame", "SLHDropdown" .. dropdownCount, advancedFrame, "UIDropDownMenuTemplate")
    srcDropdown:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 50, ay + 4)
    UIDropDownMenu_SetWidth(srcDropdown, 140)

    -- Frames for each source mode (show/hide based on selection)
    local pawnFrame   = CreateFrame("Frame", nil, advancedFrame)
    local importFrame = CreateFrame("Frame", nil, advancedFrame)

    local function UpdateSourceFrames()
        local src = charDB.statWeightSource or "pawn"
        if src == "pawn" then
            pawnFrame:Show()
            importFrame:Hide()
        else
            pawnFrame:Hide()
            importFrame:Show()
        end
    end

    UIDropDownMenu_Initialize(srcDropdown, function(self, level)
        local choices = {
            { value = "pawn",   label = "Pawn addon" },
            { value = "import", label = "Import strings" },
        }
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = c.label
            info.value   = c.value
            info.checked = ((charDB.statWeightSource or "pawn") == c.value)
            info.func    = function(btn)
                charDB.statWeightSource = btn.value
                UIDropDownMenu_SetSelectedValue(srcDropdown, btn.value)
                UIDropDownMenu_SetText(srcDropdown, c.label)
                UpdateSourceFrames()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local srcInit = charDB.statWeightSource or "pawn"
    UIDropDownMenu_SetSelectedValue(srcDropdown, srcInit)
    UIDropDownMenu_SetText(srcDropdown, srcInit == "pawn" and "Pawn addon" or "Import strings")

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local val = charDB.statWeightSource or "pawn"
            UIDropDownMenu_SetSelectedValue(srcDropdown, val)
            UIDropDownMenu_SetText(srcDropdown, val == "pawn" and "Pawn addon" or "Import strings")
            UpdateSourceFrames()
        end,
    }
    ay = ay - 40

    ---- PAWN SOURCE FRAME ----
    pawnFrame:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", 0, ay)
    pawnFrame:SetSize(460, 140)

    local py = -4

    local pawnDetectLabel = pawnFrame:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    pawnDetectLabel:SetPoint("TOPLEFT", pawnFrame, "TOPLEFT", LEFT_MARGIN + 4, py)
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            if PawnGetAllScales then
                pawnDetectLabel:SetText("|cff00ff00Pawn detected.|r Select scales below.")
            else
                pawnDetectLabel:SetText("|cffff6600Pawn addon not loaded.|r Switch source to Import.")
            end
        end,
    }
    py = py - 18

    -- Main spec Pawn scale dropdown
    local pawnMainLabel = pawnFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    pawnMainLabel:SetPoint("TOPLEFT", pawnFrame, "TOPLEFT", LEFT_MARGIN + 4, py)
    pawnMainLabel:SetText("Main spec scale:")

    dropdownCount = dropdownCount + 1
    local pawnMainDD = CreateFrame("Frame", "SLHDropdown" .. dropdownCount, pawnFrame, "UIDropDownMenuTemplate")
    pawnMainDD:SetPoint("TOPLEFT", pawnFrame, "TOPLEFT", LEFT_MARGIN - 12, py - 16)
    UIDropDownMenu_SetWidth(pawnMainDD, 200)

    UIDropDownMenu_Initialize(pawnMainDD, function(self, level)
        local scales = SLH.StatWeights:GetPawnScales()
        -- "None" option
        local info = UIDropDownMenu_CreateInfo()
        info.text    = "None"
        info.value   = ""
        info.checked = (not charDB.statWeightPawnMain or charDB.statWeightPawnMain == "")
        info.func    = function(btn)
            charDB.statWeightPawnMain = nil
            UIDropDownMenu_SetText(pawnMainDD, "None")
        end
        UIDropDownMenu_AddButton(info, level)
        for _, name in ipairs(scales) do
            info = UIDropDownMenu_CreateInfo()
            info.text    = name
            info.value   = name
            info.checked = (charDB.statWeightPawnMain == name)
            info.func    = function(btn)
                charDB.statWeightPawnMain = btn.value
                UIDropDownMenu_SetText(pawnMainDD, btn.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(pawnMainDD, charDB.statWeightPawnMain or "None")

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            UIDropDownMenu_SetText(pawnMainDD, charDB.statWeightPawnMain or "None")
        end,
    }
    py = py - 44

    -- Offspec Pawn scale dropdown
    local pawnOffLabel = pawnFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    pawnOffLabel:SetPoint("TOPLEFT", pawnFrame, "TOPLEFT", LEFT_MARGIN + 4, py)
    pawnOffLabel:SetText("Offspec scale:")

    dropdownCount = dropdownCount + 1
    local pawnOffDD = CreateFrame("Frame", "SLHDropdown" .. dropdownCount, pawnFrame, "UIDropDownMenuTemplate")
    pawnOffDD:SetPoint("TOPLEFT", pawnFrame, "TOPLEFT", LEFT_MARGIN - 12, py - 16)
    UIDropDownMenu_SetWidth(pawnOffDD, 200)

    UIDropDownMenu_Initialize(pawnOffDD, function(self, level)
        local scales = SLH.StatWeights:GetPawnScales()
        local info = UIDropDownMenu_CreateInfo()
        info.text    = "None"
        info.value   = ""
        info.checked = (not charDB.statWeightPawnOffspec or charDB.statWeightPawnOffspec == "")
        info.func    = function(btn)
            charDB.statWeightPawnOffspec = nil
            UIDropDownMenu_SetText(pawnOffDD, "None")
        end
        UIDropDownMenu_AddButton(info, level)
        for _, name in ipairs(scales) do
            info = UIDropDownMenu_CreateInfo()
            info.text    = name
            info.value   = name
            info.checked = (charDB.statWeightPawnOffspec == name)
            info.func    = function(btn)
                charDB.statWeightPawnOffspec = btn.value
                UIDropDownMenu_SetText(pawnOffDD, btn.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(pawnOffDD, charDB.statWeightPawnOffspec or "None")

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            UIDropDownMenu_SetText(pawnOffDD, charDB.statWeightPawnOffspec or "None")
        end,
    }
    py = py - 44

    pawnFrame:SetHeight(math.abs(py) + 8)

    ---- IMPORT SOURCE FRAME ----
    importFrame:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", 0, ay)
    importFrame:SetSize(460, 260)

    local iy = -4

    -- Status label
    local swStatusLabel = importFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    swStatusLabel:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 4, iy)
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            swStatusLabel:SetText("Status: " .. SLH.StatWeights:GetSummary())
        end,
    }
    iy = iy - 22

    -- Main spec import
    local mainSpecLabel = importFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    mainSpecLabel:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 4, iy)
    mainSpecLabel:SetText("Main spec:")
    iy = iy - 18

    local mainBox = CreateFrame("EditBox", nil, importFrame, "InputBoxTemplate")
    mainBox:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 8, iy)
    mainBox:SetSize(340, 20)
    mainBox:SetAutoFocus(false)
    mainBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    iy = iy - 24

    local mainImportBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
    mainImportBtn:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 4, iy)
    mainImportBtn:SetSize(80, 22)
    mainImportBtn:SetText("Import")
    mainImportBtn:SetScript("OnClick", function()
        local text = mainBox:GetText()
        local result = SLH.StatWeights:ParsePawnString(text)
        if result then
            if not charDB.statWeightProfiles then charDB.statWeightProfiles = {} end
            charDB.statWeightProfiles.main = { name = result.scaleName, weights = result.weights }
            -- Also keep legacy fields for backward compat
            charDB.statWeights     = result.weights
            charDB.statWeightsName = result.scaleName
            swStatusLabel:SetText("Status: " .. SLH.StatWeights:GetSummary())
            local n = 0; for _ in pairs(result.weights) do n = n + 1 end
            print("|cff00ccff[SLH]|r Main spec weights imported: " .. result.scaleName .. " (" .. n .. " stats)")
        else
            print("|cffff9900[SLH]|r Failed to parse. Use Pawn format: ( Pawn: v1: \"Name\": Stat=X, ... )")
        end
    end)

    local mainExportBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
    mainExportBtn:SetPoint("LEFT", mainImportBtn, "RIGHT", 8, 0)
    mainExportBtn:SetSize(80, 22)
    mainExportBtn:SetText("Export")
    mainExportBtn:SetScript("OnClick", function()
        local prof = charDB.statWeightProfiles and charDB.statWeightProfiles.main
        if prof and prof.weights then
            local str = SLH.StatWeights:ExportPawnString(prof.name, prof.weights)
            mainBox:SetText(str)
            mainBox:SetFocus()
            mainBox:HighlightText()
        else
            print("|cffff9900[SLH]|r No main spec weights configured.")
        end
    end)

    -- Show current main profile name
    local mainStatusFs = importFrame:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    mainStatusFs:SetPoint("LEFT", mainExportBtn, "RIGHT", 8, 0)
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local prof = charDB.statWeightProfiles and charDB.statWeightProfiles.main
            if prof and prof.name then
                mainStatusFs:SetText("|cff00ff00" .. prof.name .. "|r")
            else
                mainStatusFs:SetText("|cff666666(empty)|r")
            end
        end,
    }
    iy = iy - 32

    -- Offspec import
    local offSpecLabel = importFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    offSpecLabel:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 4, iy)
    offSpecLabel:SetText("Offspec:")
    iy = iy - 18

    local offBox = CreateFrame("EditBox", nil, importFrame, "InputBoxTemplate")
    offBox:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 8, iy)
    offBox:SetSize(340, 20)
    offBox:SetAutoFocus(false)
    offBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    iy = iy - 24

    local offImportBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
    offImportBtn:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 4, iy)
    offImportBtn:SetSize(80, 22)
    offImportBtn:SetText("Import")
    offImportBtn:SetScript("OnClick", function()
        local text = offBox:GetText()
        local result = SLH.StatWeights:ParsePawnString(text)
        if result then
            if not charDB.statWeightProfiles then charDB.statWeightProfiles = {} end
            charDB.statWeightProfiles.offspec = { name = result.scaleName, weights = result.weights }
            swStatusLabel:SetText("Status: " .. SLH.StatWeights:GetSummary())
            local n = 0; for _ in pairs(result.weights) do n = n + 1 end
            print("|cff00ccff[SLH]|r Offspec weights imported: " .. result.scaleName .. " (" .. n .. " stats)")
        else
            print("|cffff9900[SLH]|r Failed to parse. Use Pawn format: ( Pawn: v1: \"Name\": Stat=X, ... )")
        end
    end)

    local offExportBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
    offExportBtn:SetPoint("LEFT", offImportBtn, "RIGHT", 8, 0)
    offExportBtn:SetSize(80, 22)
    offExportBtn:SetText("Export")
    offExportBtn:SetScript("OnClick", function()
        local prof = charDB.statWeightProfiles and charDB.statWeightProfiles.offspec
        if prof and prof.weights then
            local str = SLH.StatWeights:ExportPawnString(prof.name, prof.weights)
            offBox:SetText(str)
            offBox:SetFocus()
            offBox:HighlightText()
        else
            print("|cffff9900[SLH]|r No offspec weights configured.")
        end
    end)

    -- Show current offspec profile name
    local offStatusFs = importFrame:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    offStatusFs:SetPoint("LEFT", offExportBtn, "RIGHT", 8, 0)
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local prof = charDB.statWeightProfiles and charDB.statWeightProfiles.offspec
            if prof and prof.name then
                offStatusFs:SetText("|cff00ff00" .. prof.name .. "|r")
            else
                offStatusFs:SetText("|cff666666(empty)|r")
            end
        end,
    }
    iy = iy - 32

    -- Clear all button
    local clearAllBtn = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
    clearAllBtn:SetPoint("TOPLEFT", importFrame, "TOPLEFT", LEFT_MARGIN + 4, iy)
    clearAllBtn:SetSize(100, 22)
    clearAllBtn:SetText("Clear All")
    clearAllBtn:SetScript("OnClick", function()
        charDB.statWeightProfiles = nil
        charDB.statWeights        = nil
        charDB.statWeightsName    = nil
        charDB.statWeightPawnMain    = nil
        charDB.statWeightPawnOffspec = nil
        mainBox:SetText("")
        offBox:SetText("")
        swStatusLabel:SetText("Status: " .. SLH.StatWeights:GetSummary())
        print("|cff00ccff[SLH]|r All stat weights cleared.")
    end)
    iy = iy - 30

    importFrame:SetHeight(math.abs(iy) + 8)

    -- Advance ay past the taller of the two frames
    ay = ay - 160

    UpdateSourceFrames()
    ay = ay - 8

    -- iLvl threshold greed
    AdvCreateTitle("Item Level Greed")
    AdvCreateCheckbox("Enable iLvl auto-greed", charDB, "ilvlGreedEnabled", false)
    AdvCreateHelpText("Auto-greeds items at or below the set ilvl threshold.")
    ay = ay - 24

    local ilvlSliderFs = advancedFrame:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    ilvlSliderFs:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 4, ay)
    ilvlSliderFs:SetText("iLvl threshold:")

    local ilvlSlider = CreateFrame("Slider", nil, advancedFrame, "OptionsSliderTemplate")
    ilvlSlider:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 4, ay - 18)
    ilvlSlider:SetWidth(200)
    ilvlSlider:SetMinMaxValues(0, 600)
    ilvlSlider:SetValueStep(1)
    ilvlSlider:SetObeyStepOnDrag(true)
    ilvlSlider.Low:SetText("0")
    ilvlSlider.High:SetText("600")

    local ilvlValBox = CreateFrame("EditBox", nil, advancedFrame, "InputBoxTemplate")
    ilvlValBox:SetPoint("LEFT", ilvlSlider, "RIGHT", 8, 0)
    ilvlValBox:SetSize(52, 20)
    ilvlValBox:SetAutoFocus(false)
    ilvlValBox:SetNumeric(true)
    ilvlValBox:SetMaxLetters(4)
    ilvlValBox:SetJustifyH("CENTER")

    local function SetIlvlText(value)
        local text = tostring(value)
        ilvlValBox:SetText(text)
        ilvlValBox:SetCursorPosition(#text)
    end

    local ilvlInit = GetDB(charDB, "ilvlGreedThreshold", 0)

    ilvlSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        charDB.ilvlGreedThreshold = value
        SetIlvlText(value)
    end)

    ilvlSlider:SetValue(ilvlInit)
    SetIlvlText(ilvlInit)

    ilvlValBox:SetScript("OnShow", function(self)
        local val = GetDB(aSmoothLootHelperCharDB, "ilvlGreedThreshold", 0)
        local text = tostring(val)
        self:SetText(text)
        self:SetCursorPosition(#text)
    end)
    ilvlValBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 0
        val = math.max(0, math.min(600, math.floor(val + 0.5)))
        charDB.ilvlGreedThreshold = val
        ilvlSlider:SetValue(val)
        self:ClearFocus()
    end)
    ilvlValBox:SetScript("OnEscapePressed", function(self)
        SetIlvlText(GetDB(charDB, "ilvlGreedThreshold", 0))
        self:ClearFocus()
    end)

    widgets[#widgets + 1] = { type = "slider", widget = ilvlSlider, dbTable = charDB, dbKey = "ilvlGreedThreshold", valText = ilvlValBox, default = 0 }
    ay = ay - 56

    -- Quality auto-roll
    AdvCreateTitle("Quality Auto-Roll")
    AdvCreateDropdown("Action:", charDB, "qualityRollMode", {
        { value = "off",   label = "Off" },
        { value = "pass",  label = "Pass" },
        { value = "greed", label = "Greed" },
        { value = "need",  label = "Need" },
    }, "off")
    AdvCreateDropdown("On items of quality:", charDB, "qualityThreshold", {
        { value = 0, label = "Off" },
        { value = 2, label = "Uncommon (green) or lower" },
        { value = 3, label = "Rare (blue) or lower" },
    }, 0)
    AdvCreateHelpText("Auto-roll on items at or below a set quality.\nE.g. Greed + Uncommon auto-greeds all greens.")
    ay = ay - 40

    -- Auto-roll override
    AdvCreateTitle("Auto-Roll Override")
    AdvCreateDropdown("Override:", charDB, "autoRollMode", {
        { value = "off",   label = "Off (normal rolling)" },
        { value = "pass",  label = "Pass on everything" },
        { value = "greed", label = "Greed on everything" },
        { value = "need",  label = "Need on everything" },
    }, "off")
    AdvCreateHelpText("Overrides all other rules. Normally controlled\nby the Mode preset above.")
    ay = ay - 40

    -- Lockboxes
    AdvCreateTitle("Lockboxes")
    AdvCreateDropdown("Action on lockboxes:", charDB, "lockboxRollMode", {
        { value = "off",   label = "Off (use normal rules)" },
        { value = "pass",  label = "Pass" },
        { value = "need",  label = "Need" },
        { value = "greed", label = "Greed" },
    }, "pass")
    AdvCreateHelpText("Overrides all rules when a lockbox drops.\nUse Need for rogues, Pass to skip.")
    ay = ay - 40

    -- Debug
    AdvCreateTitle("Debug")
    AdvCreateCheckbox("Debug mode (print roll decisions to chat)", db, "debugMode", false)
    ay = ay - 8

    local logBtn = CreateFrame("Button", nil, advancedFrame, "UIPanelButtonTemplate")
    logBtn:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 30, ay)
    logBtn:SetSize(140, 22)
    logBtn:SetText("Show Debug Log")
    logBtn:SetScript("OnClick", function() SLH.DebugLog:Toggle() end)
    ay = ay - 36

    -- Reset history
    local resetBtn = CreateFrame("Button", nil, advancedFrame, "UIPanelButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", advancedFrame, "TOPLEFT", LEFT_MARGIN + 4, ay)
    resetBtn:SetSize(140, 22)
    resetBtn:SetText("Clear Greed History")
    resetBtn:SetScript("OnClick", function()
        SLH.History:Reset()
        print("|cff00ccff[SLH]|r Greed history cleared.")
    end)
    ay = ay - 40

    -- Set advanced frame height
    advContent:SetHeight(math.abs(ay) + 30)

    -- Register with the Blizzard interface options
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        advPanel.parent = panel.name
        InterfaceOptions_AddCategory(advPanel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        SLH._settingsCategoryID = category:GetID()

        local advCategory = Settings.RegisterCanvasLayoutSubcategory(category, advPanel, advPanel.name)
    end
end

------------------------------------------------------------------------
-- Refresh widget states from the DB (called when the panel is shown)
------------------------------------------------------------------------
function Options:Refresh()
    for _, w in ipairs(widgets) do
        if w.type == "check" then
            local val = GetDB(w.dbTable, w.dbKey, w.default)
            w.widget:SetChecked(val and true or false)
        elseif w.type == "slider" then
            local val = GetDB(w.dbTable, w.dbKey, w.default or 0)
            local text = tostring(math.floor(val + 0.5))
            w.widget:SetValue(val)
            w.valText:SetText(text)
            w.valText:SetCursorPosition(0)
            C_Timer.After(0, function()
                if w.valText and w.valText:IsShown() then
                    w.valText:SetText(text)
                    w.valText:SetCursorPosition(0)
                end
            end)
        elseif w.type == "custom" and w.refresh then
            w.refresh()
        end
    end
end

panel:SetScript("OnShow", function()
    Options:Refresh()
end)

advPanel:SetScript("OnShow", function()
    Options:Refresh()
end)
