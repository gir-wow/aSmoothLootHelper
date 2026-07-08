local _, SLH = ...
SLH.Notify = {}

local Notify = SLH.Notify

------------------------------------------------------------------------
-- Notification frame — shows messages at top-center of screen,
-- similar to zone-change text. Supports stacking multiple messages.
------------------------------------------------------------------------
local DISPLAY_TIME   = 5     -- seconds each message stays visible
local FADE_TIME      = 1.5   -- seconds to fade out
local MAX_LINES      = 4     -- max simultaneous messages
local FONT_SIZE      = 22
local LINE_SPACING   = 30

local container
local lines = {}

local function GetContainer()
    if container then return container end

    container = CreateFrame("Frame", "SLHNotifyFrame", UIParent)
    container:SetPoint("TOP", UIParent, "TOP", 0, -180)
    container:SetSize(600, LINE_SPACING * MAX_LINES)
    container:SetFrameStrata("HIGH")

    for i = 1, MAX_LINES do
        local fs = container:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, FONT_SIZE, "OUTLINE")
        fs:SetPoint("TOP", container, "TOP", 0, -((i - 1) * LINE_SPACING))
        fs:SetShadowOffset(2, -2)
        fs:SetAlpha(0)
        fs:Hide()
        lines[i] = {
            fontString = fs,
            expireAt   = 0,
            fadeStart  = 0,
        }
    end

    -- Update handler for fade animation
    container:SetScript("OnUpdate", function(_, elapsed)
        local now = GetTime()
        for _, line in ipairs(lines) do
            if line.fontString:IsShown() then
                if now >= line.expireAt then
                    line.fontString:SetAlpha(0)
                    line.fontString:Hide()
                elseif now >= line.fadeStart then
                    local remaining = line.expireAt - now
                    local alpha = remaining / FADE_TIME
                    line.fontString:SetAlpha(alpha)
                end
            end
        end
    end)

    return container
end

------------------------------------------------------------------------
-- Find the first available line slot (or recycle the oldest)
------------------------------------------------------------------------
local function GetFreeLine()
    local now = GetTime()
    -- First try to find a hidden/expired line
    for _, line in ipairs(lines) do
        if not line.fontString:IsShown() or now >= line.expireAt then
            return line
        end
    end
    -- All lines busy — use the oldest one
    local oldest = lines[1]
    for _, line in ipairs(lines) do
        if line.fadeStart < oldest.fadeStart then
            oldest = line
        end
    end
    return oldest
end

------------------------------------------------------------------------
-- Show a notification message
------------------------------------------------------------------------
function Notify:Show(text, r, g, b)
    GetContainer()
    local line = GetFreeLine()
    local now  = GetTime()

    line.fontString:SetText(text)
    line.fontString:SetTextColor(r or 0, g or 1, b or 0.5)
    line.fontString:SetAlpha(1)
    line.fontString:Show()
    line.fadeStart = now + DISPLAY_TIME
    line.expireAt  = now + DISPLAY_TIME + FADE_TIME
end

------------------------------------------------------------------------
-- Convenience: show a BiS need notification (green)
------------------------------------------------------------------------
function Notify:BiSNeed(itemLink)
    self:Show("BiS NEED: " .. (itemLink or "?"), 0.1, 1, 0.1)
end

------------------------------------------------------------------------
-- Convenience: show a loot won notification (gold)
------------------------------------------------------------------------
function Notify:LootWon(itemLink)
    self:Show("WON: " .. (itemLink or "?"), 1, 0.84, 0)
end
