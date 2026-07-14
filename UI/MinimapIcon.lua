local _, SLH = ...
SLH.MinimapIcon = {}

------------------------------------------------------------------------
-- Minimap icon — uses Blizzard's INV_Misc_Dice_02 art asset
------------------------------------------------------------------------
local MIN_RADIUS = 80

local function AngleToPosition(angle)
    local rad = math.rad(angle)
    return MIN_RADIUS * math.cos(rad), -MIN_RADIUS * math.sin(rad)
end

local function CreateMinimapButton()
    local charDB = aSmoothLootHelperCharDB

    if not charDB.minimapIconEnabled then return end

    local btn = CreateFrame("Button", "SLHMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameLevel(8)
    btn:SetFrameStrata("MEDIUM")

    -- Icon texture — Blizzard dice icon with circular mask
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Dice_02")

    -- Circular mask overlay to hide the square corners
    local mask = btn:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    -- Highlight ring (standard Blizzard minimap button look)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Border texture
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")

    -- Initial position from saved angle
    local x, y = AngleToPosition(charDB.minimapAngle or 225)
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)

    --------------------------------------------------------------------
    -- Drag to reposition, save angle on release
    --------------------------------------------------------------------
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    btn:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = Minimap:GetCenter()
        local bx, by = self:GetCenter()
        local angle  = math.deg(math.atan2(-(by - cy), bx - cx))
        charDB.minimapAngle = angle % 360
        local nx, ny = AngleToPosition(charDB.minimapAngle)
        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", nx, ny)
    end)

    --------------------------------------------------------------------
    -- Clicks
    --------------------------------------------------------------------
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            local db = aSmoothLootHelperDB.settings
            db.autoGreedEnabled = not db.autoGreedEnabled
            if db.autoGreedEnabled then
                print("|cff00ccff[SLH]|r Enabled.")
            else
                print("|cff00ccff[SLH]|r Disabled.")
            end
            SLH.MinimapIcon:UpdateIcon()
        elseif button == "RightButton" then
            SLH.MinimapIcon:ShowMenu(self)
        end
    end)

    --------------------------------------------------------------------
    -- Tooltip
    --------------------------------------------------------------------
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("aSmoothLootHelper", 0, 0.8, 1)
        local enabled = aSmoothLootHelperDB.settings.autoGreedEnabled
        GameTooltip:AddLine(enabled and "|cff00ff00Enabled|r" or "|cffff4444Disabled|r")
        local modeLabels = { raiding = "Raiding", farming = "Farming", carry = "Carry", custom = "Custom" }
        local mode = aSmoothLootHelperCharDB.playMode or "raiding"
        GameTooltip:AddLine("Mode: " .. (modeLabels[mode] or mode), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffff00Left-click|r toggle on/off", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffff00Right-click|r quick options", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    SLH.MinimapIcon._btn = btn
    SLH.MinimapIcon:UpdateIcon()
end

------------------------------------------------------------------------
-- Right-click dropdown menu
------------------------------------------------------------------------
local menuFrame = CreateFrame("Frame", "SLHMinimapMenu", UIParent, "UIDropDownMenuTemplate")

local function BuildMenu()
    local db     = aSmoothLootHelperDB.settings
    local charDB = aSmoothLootHelperCharDB
    local info

    -- Title
    info = UIDropDownMenu_CreateInfo()
    info.text          = "aSmoothLootHelper"
    info.isTitle       = true
    info.notCheckable  = true
    UIDropDownMenu_AddButton(info)

    -- Enable/Disable
    info = UIDropDownMenu_CreateInfo()
    info.text    = "Enabled"
    info.checked = db.autoGreedEnabled
    info.keepShownOnClick = true
    info.func    = function()
        db.autoGreedEnabled = not db.autoGreedEnabled
        SLH.MinimapIcon:UpdateIcon()
    end
    UIDropDownMenu_AddButton(info)

    UIDropDownMenu_AddSeparator()

    -- Mode presets
    info = UIDropDownMenu_CreateInfo()
    info.text          = "Mode"
    info.isTitle       = true
    info.notCheckable  = true
    UIDropDownMenu_AddButton(info)

    local modes = {
        { value = "raiding", label = "Raiding (smart)" },
        { value = "farming", label = "Farming / Solo" },
        { value = "carry",   label = "Carry / Boost" },
        { value = "custom",  label = "Custom" },
    }
    for _, m in ipairs(modes) do
        info = UIDropDownMenu_CreateInfo()
        info.text    = m.label
        info.checked = (charDB.playMode == m.value)
        info.isRadio = true
        info.func    = function()
            SLH.Options:ApplyMode(m.value)
        end
        UIDropDownMenu_AddButton(info)
    end

    UIDropDownMenu_AddSeparator()

    -- BiS auto-need toggle
    info = UIDropDownMenu_CreateInfo()
    info.text    = "BiS auto-need"
    info.checked = charDB.bisNeedEnabled
    info.keepShownOnClick = true
    info.func    = function()
        charDB.bisNeedEnabled = not charDB.bisNeedEnabled
    end
    UIDropDownMenu_AddButton(info)

    -- Transmog need toggle
    info = UIDropDownMenu_CreateInfo()
    info.text    = "Transmog need"
    info.checked = charDB.transmogNeedEnabled
    info.keepShownOnClick = true
    info.func    = function()
        charDB.transmogNeedEnabled = not charDB.transmogNeedEnabled
    end
    UIDropDownMenu_AddButton(info)

    UIDropDownMenu_AddSeparator()

    -- Open full options
    info = UIDropDownMenu_CreateInfo()
    info.text          = "Open full options\226\128\166"
    info.notCheckable  = true
    info.func          = function()
        if InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("aSmoothLootHelper")
            InterfaceOptionsFrame_OpenToCategory("aSmoothLootHelper")
        elseif Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(SLH._settingsCategoryID)
        end
    end
    UIDropDownMenu_AddButton(info)

    -- Debug log
    info = UIDropDownMenu_CreateInfo()
    info.text          = "Show debug log"
    info.notCheckable  = true
    info.func          = function() SLH.DebugLog:Toggle() end
    UIDropDownMenu_AddButton(info)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function SLH.MinimapIcon:Init()
    CreateMinimapButton()
end

function SLH.MinimapIcon:ShowMenu(anchor)
    -- Toggle: if the menu is already open for this anchor, close it
    if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == menuFrame then
        CloseDropDownMenus()
    else
        UIDropDownMenu_Initialize(menuFrame, BuildMenu, "MENU")
        ToggleDropDownMenu(1, nil, menuFrame, anchor, 0, -4)
    end
end

function SLH.MinimapIcon:UpdateIcon()
    local btn = self._btn
    if not btn then return end
    local enabled = aSmoothLootHelperDB.settings.autoGreedEnabled
    local icon = btn:GetRegions()
    if icon and icon.SetVertexColor then
        if enabled then
            icon:SetVertexColor(1, 1, 1)
        else
            icon:SetVertexColor(1, 0.3, 0.3)
        end
    end
end

function SLH.MinimapIcon:SetVisible(show)
    local btn = self._btn
    if btn then
        if show then btn:Show() else btn:Hide() end
    end
end
