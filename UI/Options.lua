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

    -- Initialise display text immediately
    local initSliderVal = (dbTable[dbKey] ~= nil) and math.floor(dbTable[dbKey] + 0.5) or minVal
    valText:SetText(tostring(initSliderVal))

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
        return tostring(value)
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

    -- Initialise display immediately (correct value shown before first Refresh)
    local initVal = dbTable[dbKey]
    if initVal == nil then initVal = choices[1].value end
    UIDropDownMenu_SetSelectedValue(dropdown, initVal)
    UIDropDownMenu_SetText(dropdown, GetLabel(initVal))

    widgets[#widgets + 1] = {
        type = "custom",
        refresh = function()
            local val = dbTable[dbKey]
            if val == nil then val = choices[1].value end
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
    y = y - 26
    CreateHelpText(y, "Shows roll decisions in chat: item,\nquality, armor type, and which rule matched.")
    y = y - 40

    local logBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    logBtn:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 30, y)
    logBtn:SetSize(140, 22)
    logBtn:SetText("Show Debug Log")
    logBtn:SetScript("OnClick", function() SLH.DebugLog:Toggle() end)
    y = y - 32

    CreateCheckbox(y, "Auto-greed on previously greeded items", db, "autoGreedOnHistory")
    y = y - 26
    CreateHelpText(y, "Items you've greeded before are auto-greeded\nagain (account-wide).")
    y = y - 40

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
    CreateHelpText(y, "Override all rolls for this character.\nPass = boosting, Greed = farming,\nNeed = old content. Resets on logout.")
    y = y - 56

    ---------- Session Memory ----------
    CreateCheckbox(y, "Session memory", charDB, "sessionMemoryEnabled")
    y = y - 26
    CreateHelpText(y, "Tracks what you roll this session.\nSame item dropping again gets the same\nroll. Clears when you log out.")
    y = y - 56

    ---------- Armor Type Filter ----------
    CreateTitle(y, "Armor Type Filter (per character)")
    y = y - 28
    CreateCheckbox(y, "Filter by armor type", charDB, "armorFilterEnabled")
    y = y - 26
    CreateHelpText(y, "Off-armor-type items are auto-greeded or\npassed. Weapons, rings, trinkets, and\ncloaks are never filtered.")
    y = y - 56
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
    CreateHelpText(y, "Auto-roll on items at or below a set\nquality. E.g. Greed + Uncommon\nauto-greeds all greens and whites.")
    y = y - 56

    ---------- Auto-Greed Downgrades ----------
    CreateTitle(y, "Auto-Greed Downgrades (per character)")
    y = y - 28
    CreateCheckbox(y, "Auto-greed items worse than equipped gear", charDB, "downgradeGreedEnabled")
    y = y - 26
    CreateHelpText(y, "Uses Pawn or stat weights to compare drops\nvs. equipped gear (falls back to ilvl).\nWorse items are greeded; upgrades are not.")
    y = y - 58

    ---------- Stat Weights ----------
    CreateTitle(y, "Stat Weights (per character)")
    y = y - 28
    CreateHelpText(y, "Paste a Pawn string to set weights for\nthis character. Get strings from Wowhead\nor Icy Veins. Used when Pawn is absent.")
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
    y = y - 26
    CreateHelpText(y, "Auto-greeds items at or below the\nset ilvl threshold.")
    y = y - 40
    CreateSlider(y, "iLvl threshold:", charDB, "ilvlGreedThreshold", 0, 600, 1)
    y = y - 60

    ---------- BiS Auto-Need ----------
    CreateTitle(y, "BiS Auto-Need (per character)")
    y = y - 28
    CreateCheckbox(y, "Enable BiS auto-need (requires BisTooltip or FrogBiS)", charDB, "bisNeedEnabled")
    y = y - 26
    CreateHelpText(y, "Auto-needs BiS items not yet collected.")
    y = y - 26
    CreateCheckbox(y, "Include offspec items", charDB, "bisOffspecEnabled")
    y = y - 26
    CreateHelpText(y, "Also need on items BiS for other specs.")
    y = y - 26
    CreateCheckbox(y, "Show on-screen notification on BiS auto-need", charDB, "bisNotifyEnabled")
    y = y - 26
    CreateHelpText(y, "Shows a large on-screen message when\na BiS item is auto-needed.")
    y = y - 40

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
    y = y - 26

    ---------- Lockboxes ----------
    CreateTitle(y, "Lockboxes (per character)")
    y = y - 28
    CreateDropdown(y, "Action on lockboxes:", charDB, "lockboxRollMode", {
        { value = "off",   label = "Off (use normal rules)" },
        { value = "pass",  label = "Pass" },
        { value = "need",  label = "Need" },
        { value = "greed", label = "Greed" },
    })
    y = y - 46
    CreateHelpText(y, "Overrides all rules when a lockbox drops.\nUse Need for rogues, Pass to always skip,\nor Off to let normal rules apply.")
    y = y - 56

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
            local val = (w.dbTable[w.dbKey] ~= nil) and w.dbTable[w.dbKey] or 0
            w.widget:SetValue(val)
            w.valText:SetText(tostring(math.floor(val + 0.5)))
        elseif w.type == "custom" and w.refresh then
            w.refresh()
        end
    end
end

panel:SetScript("OnShow", function()
    Options:Refresh()
end)
