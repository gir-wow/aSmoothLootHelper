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
content:SetSize(460, 1000)
scrollFrame:SetScrollChild(content)

local FONT_HEADER = "GameFontNormalLarge"
local FONT_NORMAL = "GameFontHighlight"
local FONT_SMALL  = "GameFontHighlightSmall"
local LEFT_MARGIN = 16

local widgets = {}
local dropdownCount = 0

------------------------------------------------------------------------
-- Helpers — all parented to content (the scroll child)
------------------------------------------------------------------------
local function CreateTitle(y, text)
    local fs = content:CreateFontString(nil, "OVERLAY", FONT_HEADER)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    fs:SetText(text)
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

local function CreateCheckbox(y, label, dbTable, dbKey)
    local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    cb.Text:SetText(label)
    cb:SetScript("OnClick", function(self)
        dbTable[dbKey] = self:GetChecked() and true or false
    end)
    widgets[#widgets + 1] = { type = "check", widget = cb, dbTable = dbTable, dbKey = dbKey }
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

    local valText = slider:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    valText:SetPoint("TOP", slider, "BOTTOM", 0, -2)

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        dbTable[dbKey] = value
        valText:SetText(tostring(value))
    end)

    widgets[#widgets + 1] = { type = "slider", widget = slider, dbTable = dbTable, dbKey = dbKey, valText = valText }
    return slider
end

local function CreateDropdown(y, label, dbTable, dbKey, choices)
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
        return value or "?"
    end

    UIDropDownMenu_SetWidth(dropdown, 160)

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = c.label
            info.value    = c.value
            info.checked  = (dbTable[dbKey] == c.value)
            info.func     = function(btn)
                dbTable[dbKey] = btn.value
                UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                UIDropDownMenu_SetText(dropdown, GetLabel(btn.value))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local val = dbTable[dbKey] or choices[1].value
            UIDropDownMenu_SetSelectedValue(dropdown, val)
            UIDropDownMenu_SetText(dropdown, GetLabel(val))
        end,
    }
    return dropdown
end

------------------------------------------------------------------------
-- Build panel contents once the DB is ready
------------------------------------------------------------------------
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
    y = y - 24

    ---------- General ----------
    CreateTitle(y, "General")
    y = y - 28
    CreateCheckbox(y, "Enable aSmoothLootHelper", db, "autoGreedEnabled")
    y = y - 28
    CreateCheckbox(y, "Debug mode (print roll decisions to chat)", db, "debugMode")
    y = y - 18
    CreateHelpText(y, "Shows detailed info for every loot roll: item, quality, armor type,\nand which rule was checked / matched.")
    y = y - 34

    local logBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    logBtn:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 30, y)
    logBtn:SetSize(140, 22)
    logBtn:SetText("Show Debug Log")
    logBtn:SetScript("OnClick", function() SLH.DebugLog:Toggle() end)
    y = y - 32

    CreateCheckbox(y, "Auto-greed on previously greeded items", db, "autoGreedOnHistory")
    y = y - 18
    CreateHelpText(y, "Items you've greeded before will be auto-greeded again (account-wide).")
    y = y - 28

    ---------- Auto-Roll Mode ----------
    CreateTitle(y, "Auto-Roll Mode (per character)")
    y = y - 28
    CreateDropdown(y, "Mode:", charDB, "autoRollMode", {
        { value = "off",   label = "Off (normal rolling)" },
        { value = "pass",  label = "Pass on everything" },
        { value = "greed", label = "Greed on everything" },
        { value = "need",  label = "Need on everything" },
    })
    y = y - 46
    CreateHelpText(y, "Override all rolls for this character. Useful when boosting\n(Pass), farming on a geared main (Greed), or soloing old\ncontent (Need). Resets to Off when you log out.")
    y = y - 48

    ---------- Session Memory ----------
    CreateCheckbox(y, "Session memory", charDB, "sessionMemoryEnabled")
    y = y - 18
    CreateHelpText(y, "Remembers what you manually rolled on each item this session.\nIf the same item drops again, repeats your last choice.\nClears when you log out.")
    y = y - 48

    ---------- Armor Type Filter ----------
    CreateTitle(y, "Armor Type Filter (per character)")
    y = y - 28
    CreateCheckbox(y, "Filter by armor type", charDB, "armorFilterEnabled")
    y = y - 18
    CreateHelpText(y,
        "When enabled, items that don't match your class armor type\n" ..
        "(e.g. Cloth dropping for a Plate wearer) are automatically\n" ..
        "greeded or passed. Weapons, rings, trinkets, and cloaks\n" ..
        "are not affected.")
    y = y - 60
    CreateDropdown(y, "Off-type armor action:", charDB, "armorFilterAction", {
        { value = "greed", label = "Greed" },
        { value = "pass",  label = "Pass" },
    })
    y = y - 50

    ---------- Quality Auto-Roll ----------
    CreateTitle(y, "Quality Auto-Roll (per character)")
    y = y - 28
    CreateDropdown(y, "Action:", charDB, "qualityRollMode", {
        { value = "off",   label = "Off" },
        { value = "pass",  label = "Pass" },
        { value = "greed", label = "Greed" },
        { value = "need",  label = "Need" },
    })
    y = y - 46
    CreateDropdown(y, "On items of quality:", charDB, "qualityThreshold", {
        { value = 0, label = "Off" },
        { value = 2, label = "Uncommon (green) or lower" },
        { value = 3, label = "Rare (blue) or lower" },
    })
    y = y - 46
    CreateHelpText(y, "Automatically roll the chosen action on items at or below\nthe selected quality. E.g. set Greed + Uncommon to auto-greed\nall greens and whites.")
    y = y - 44

    ---------- Auto-Greed Downgrades ----------
    CreateTitle(y, "Auto-Greed Downgrades (per character)")
    y = y - 28
    CreateCheckbox(y, "Auto-greed items worse than equipped gear", charDB, "downgradeGreedEnabled")
    y = y - 18
    CreateHelpText(y, "Uses Pawn (if installed) or built-in stat weights (if configured below)\nto compare drops vs equipped gear. Falls back to ilvl comparison.\nItems scored worse get auto-greeded. Potential upgrades are left\nfor manual decision.")
    y = y - 56

    ---------- Stat Weights ----------
    CreateTitle(y, "Stat Weights (per character)")
    y = y - 28
    CreateHelpText(y, "Paste a Pawn import string to set stat weights for this character.\nGet weights from Wowhead, Icy Veins, or wowsims. These are used\nwhen the Pawn addon is not installed. Copy the string to share\nweights with alts of the same class/spec.")
    y = y - 56

    -- Status label
    local swStatusLabel = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    swStatusLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            swStatusLabel:SetText("Current: " .. SLH.StatWeights:GetSummary())
        end,
    }
    y = y - 20

    -- Import/export edit box
    local swBoxLabel = content:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    swBoxLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    swBoxLabel:SetText("|cff999999Paste Pawn string below and click Import:|r")
    y = y - 16

    local swBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    swBox:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 8, y)
    swBox:SetSize(360, 20)
    swBox:SetAutoFocus(false)
    swBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    y = y - 28

    local importBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    importBtn:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    importBtn:SetSize(80, 22)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local text = swBox:GetText()
        local result = SLH.StatWeights:ParsePawnString(text)
        if result then
            charDB.statWeights     = result.weights
            charDB.statWeightsName = result.scaleName
            swStatusLabel:SetText("Current: " .. SLH.StatWeights:GetSummary())
            print("|cff00ccff[SLH]|r Imported stat weights: " .. result.scaleName
                  .. " (" .. (function() local n=0; for _ in pairs(result.weights) do n=n+1 end; return n end)()
                  .. " stats)")
        else
            print("|cffff9900[SLH]|r Failed to parse stat weights. Use Pawn format.")
        end
    end)

    local exportBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    exportBtn:SetSize(80, 22)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local str = SLH.StatWeights:ExportPawnString(charDB.statWeightsName, charDB.statWeights)
        if str and str ~= "" then
            swBox:SetText(str)
            swBox:SetFocus()
            swBox:HighlightText()
        else
            print("|cffff9900[SLH]|r No stat weights configured to export.")
        end
    end)

    local clearSwBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearSwBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    clearSwBtn:SetSize(80, 22)
    clearSwBtn:SetText("Clear")
    clearSwBtn:SetScript("OnClick", function()
        charDB.statWeights     = nil
        charDB.statWeightsName = nil
        swBox:SetText("")
        swStatusLabel:SetText("Current: " .. SLH.StatWeights:GetSummary())
        print("|cff00ccff[SLH]|r Stat weights cleared.")
    end)
    y = y - 36

    ---------- iLvl Greed ----------
    CreateTitle(y, "Item Level Greed (per character)")
    y = y - 28
    CreateCheckbox(y, "Enable iLvl auto-greed", charDB, "ilvlGreedEnabled")
    y = y - 18
    CreateHelpText(y, "Auto-greed on any item at or below the threshold item level.")
    y = y - 24
    CreateSlider(y, "iLvl threshold:", charDB, "ilvlGreedThreshold", 0, 600, 1)
    y = y - 60

    ---------- BiS Auto-Need ----------
    CreateTitle(y, "BiS Auto-Need (per character)")
    y = y - 28
    CreateCheckbox(y, "Enable BiS auto-need (requires BisTooltip or FrogBiS)", charDB, "bisNeedEnabled")
    y = y - 18
    CreateHelpText(y, "Auto-need on items on your BiS list that you haven't collected yet.")
    y = y - 28
    CreateCheckbox(y, "Include offspec items", charDB, "bisOffspecEnabled")
    y = y - 18
    CreateHelpText(y, "Also need on items that are BiS for other specs of your class.")
    y = y - 28
    CreateCheckbox(y, "Show on-screen notification on BiS auto-need", charDB, "bisNotifyEnabled")
    y = y - 18
    CreateHelpText(y, "Displays a large message at the top of the screen when a BiS\nitem is auto-needed, so you don't miss it.")
    y = y - 32

    -- Provider status
    local providerLabel = content:CreateFontString(nil, "OVERLAY", FONT_NORMAL)
    providerLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local providers = SLH.RollManager:GetBiSProviders()
            local names = {}
            for name in pairs(providers) do names[#names + 1] = name end
            if #names > 0 then
                providerLabel:SetText("|cff00ff00Active providers:|r " .. table.concat(names, ", "))
            else
                providerLabel:SetText("|cffff6600No BiS providers detected.|r Install BisTooltip or FrogBiS.")
            end
        end,
    }

    -- Set content height to fit everything
    content:SetHeight(math.abs(y) + 30)

    -- Register with the Blizzard interface options
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    end
end

------------------------------------------------------------------------
-- Refresh widget states from the DB (called when the panel is shown)
------------------------------------------------------------------------
function Options:Refresh()
    for _, w in ipairs(widgets) do
        if w.type == "check" then
            w.widget:SetChecked(w.dbTable[w.dbKey] and true or false)
        elseif w.type == "slider" then
            local val = w.dbTable[w.dbKey] or 0
            w.widget:SetValue(val)
            w.valText:SetText(tostring(val))
        elseif w.type == "custom" and w.refresh then
            w.refresh()
        end
    end
end

panel:SetScript("OnShow", function()
    Options:Refresh()
end)
