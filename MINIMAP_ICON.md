# aSmoothLootHelper — Minimap Icon Implementation

No third-party libraries required. Everything below uses only the WoW native API.

---

## SavedVariable fields (already in CHAR_DEFAULTS)

```lua
minimapIconEnabled = true,   -- show/hide; toggled from the Options panel
minimapAngle       = 225,    -- drag position in degrees, persisted per character
```

---

## Full implementation (add to aSmoothLootHelper.lua or a new UI/MinimapIcon.lua)

```lua
------------------------------------------------------------------------
-- Minimap icon
------------------------------------------------------------------------
local MIN_RADIUS = 80   -- distance from minimap centre (px)

local function AngleToPosition(angle)
    local rad = math.rad(angle)
    return MIN_RADIUS * math.cos(rad), -MIN_RADIUS * math.sin(rad)
end

local function CreateMinimapButton()
    local charDB = aSmoothLootHelperCharDB

    -- Respect the user's show/hide preference
    if not charDB.minimapIconEnabled then return end

    local btn = CreateFrame("Button", "SLHMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameLevel(8)
    btn:SetFrameStrata("MEDIUM")

    -- Icon texture — replace with a custom icon path when available
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Dice_02")   -- placeholder

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
        -- Snap back to minimap edge at the new angle
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
            -- Toggle master enable/disable
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
        GameTooltip:AddLine("|cffffff00Left-click|r to toggle on/off", 1, 1, 1)
        GameTooltip:AddLine("|cffffff00Right-click|r for quick options", 1, 1, 1)
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
    local info   = UIDropDownMenu_CreateInfo()

    -- Title
    info.text      = "aSmoothLootHelper"
    info.isTitle   = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)

    -- Enable/Disable
    info = UIDropDownMenu_CreateInfo()
    info.text    = "Enabled"
    info.checked = db.autoGreedEnabled
    info.keepShownOnClick = true
    info.func    = function()
        db.autoGreedEnabled = not db.autoGreedEnabled
        SLH.MinimapIcon:UpdateIcon()
        UIDropDownMenu_Refresh(menuFrame)
    end
    UIDropDownMenu_AddButton(info)

    UIDropDownMenu_AddSeparator()

    -- Mode submenu header
    local modes = {
        { value = "off",   label = "Normal rolling" },
        { value = "pass",  label = "Pass everything" },
        { value = "greed", label = "Greed everything" },
        { value = "need",  label = "Need everything"  },
    }
    for _, m in ipairs(modes) do
        info = UIDropDownMenu_CreateInfo()
        info.text    = m.label
        info.checked = (charDB.autoRollMode == m.value)
        info.isRadio = true
        info.func    = function()
            charDB.autoRollMode = m.value
            UIDropDownMenu_Refresh(menuFrame)
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
        UIDropDownMenu_Refresh(menuFrame)
    end
    UIDropDownMenu_AddButton(info)

    -- Transmog need toggle
    info = UIDropDownMenu_CreateInfo()
    info.text    = "Transmog need"
    info.checked = charDB.transmogNeedEnabled
    info.keepShownOnClick = true
    info.func    = function()
        charDB.transmogNeedEnabled = not charDB.transmogNeedEnabled
        UIDropDownMenu_Refresh(menuFrame)
    end
    UIDropDownMenu_AddButton(info)

    UIDropDownMenu_AddSeparator()

    -- Open full options
    info = UIDropDownMenu_CreateInfo()
    info.text    = "Open full options…"
    info.notCheckable = true
    info.func    = function()
        if InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("aSmoothLootHelper")
            InterfaceOptionsFrame_OpenToCategory("aSmoothLootHelper")
        elseif Settings and Settings.OpenToCategory then
            Settings.OpenToCategory("aSmoothLootHelper")
        end
    end
    UIDropDownMenu_AddButton(info)

    -- Debug log
    info = UIDropDownMenu_CreateInfo()
    info.text    = "Show debug log"
    info.notCheckable = true
    info.func    = function() SLH.DebugLog:Toggle() end
    UIDropDownMenu_AddButton(info)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
SLH.MinimapIcon = {}

function SLH.MinimapIcon:Init()
    CreateMinimapButton()
end

function SLH.MinimapIcon:ShowMenu(anchor)
    UIDropDownMenu_Initialize(menuFrame, BuildMenu, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, anchor, 0, -4)
end

function SLH.MinimapIcon:UpdateIcon()
    -- Tint icon red when disabled, white when enabled
    local btn = self._btn
    if not btn then return end
    local enabled = aSmoothLootHelperDB.settings.autoGreedEnabled
    local icon    = btn:GetRegions()   -- first region is the background texture
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
```

---

## Wiring into the main addon file

In `aSmoothLootHelper.lua`, inside the `PLAYER_LOGIN` (or after `InitDB`) block:

```lua
SLH.MinimapIcon:Init()
```

The Options panel "Show minimap icon" checkbox already writes `charDB.minimapIconEnabled`. On reload the button is simply not created if the flag is false. If you want live hide/show without a reload, call `SLH.MinimapIcon:SetVisible(val)` from the checkbox's `OnClick`.

---

## What the icon shows

| State | Appearance |
|---|---|
| Addon **enabled** | Normal icon colour |
| Addon **disabled** | Icon tinted red |

Left-click toggles the master enable/disable and updates the tint immediately.  
Right-click opens the quick-access dropdown (same entries as the OPTIONS_REDESIGN.md minimap menu spec).

---

## Changing the icon texture

Replace the placeholder path with a custom icon once artwork is ready:

```lua
icon:SetTexture("Interface\\AddOns\\aSmoothLootHelper\\icon")
```

Drop a 64×64 (or 256×256) TGA/BLP file named `icon.tga` into the addon root and add it to the TOC:

```
## Art
icon.tga
```

---

## Why no LibDBIcon?

LibDBIcon-1.0 adds drag-snapping, icon registration, and multi-addon icon management. It is a convenience, not a requirement. The 60-line native implementation above covers everything needed:

- Drag to reposition, angle saved per character
- Show/hide via the Options panel toggle (`minimapIconEnabled`)
- Tooltip on hover
- Left-click master toggle + right-click dropdown menu
- Red tint when disabled

If LibDBIcon is ever desired (e.g. to share the minimap space nicely with other addons), it is already bundled in the BisTooltip addon on disk and can be declared as `OptionalDeps: LibDBIcon-1.0` without bundling a copy.
