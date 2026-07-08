local _, SLH = ...
SLH.DebugLog = {}

local DebugLog = SLH.DebugLog

------------------------------------------------------------------------
-- Log storage (in-memory, not persisted — clears on reload/logout)
------------------------------------------------------------------------
local logEntries = {}
local MAX_ENTRIES = 500

------------------------------------------------------------------------
-- Add a message to the log buffer (called from Debug() everywhere)
------------------------------------------------------------------------
function DebugLog:Add(msg)
    logEntries[#logEntries + 1] = date("%H:%M:%S") .. "  " .. msg
    if #logEntries > MAX_ENTRIES then
        table.remove(logEntries, 1)
    end
    -- Update the frame if it's visible
    if self.frame and self.frame:IsShown() then
        self:RefreshText()
    end
end

------------------------------------------------------------------------
-- Get the full log as a single string
------------------------------------------------------------------------
function DebugLog:GetText()
    if #logEntries == 0 then
        return "No debug entries yet. Enable debug mode and do a loot roll."
    end
    return table.concat(logEntries, "\n")
end

------------------------------------------------------------------------
-- Clear the log
------------------------------------------------------------------------
function DebugLog:Clear()
    wipe(logEntries)
    if self.frame and self.frame:IsShown() then
        self:RefreshText()
    end
end

------------------------------------------------------------------------
-- Scrollable log viewer frame (created on first use)
------------------------------------------------------------------------
local frame

function DebugLog:RefreshText()
    if not frame then return end
    frame.editBox:SetText(self:GetText())
    frame.editBox:SetCursorPosition(frame.editBox:GetNumLetters())
    -- Scroll to bottom
    C_Timer.After(0, function()
        frame.scrollFrame:SetVerticalScroll(
            frame.scrollFrame:GetVerticalScrollRange()
        )
    end)
end

function DebugLog:Show()
    if not frame then
        frame = CreateFrame("Frame", "SLHDebugLogFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(620, 420)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("DIALOG")
        frame.TitleText:SetText("aSmoothLootHelper — Debug Log")

        -- Scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", frame.InsetBg or frame, "TOPLEFT", 8, -30)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)
        frame.scrollFrame = scrollFrame

        -- Editable text box (so user can select & copy)
        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetWidth(scrollFrame:GetWidth() - 10)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scrollFrame:SetScrollChild(editBox)
        frame.editBox = editBox

        -- Clear button
        local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        clearBtn:SetSize(80, 22)
        clearBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            DebugLog:Clear()
        end)

        -- Select All button (for easy copy)
        local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        selectBtn:SetSize(80, 22)
        selectBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
        selectBtn:SetText("Select All")
        selectBtn:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
        end)

        -- Entry count label
        local countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 14)
        frame.countLabel = countLabel

        self.frame = frame
    end

    self:RefreshText()
    local count = #logEntries
    frame.countLabel:SetText(count .. " entries")
    frame:Show()
end

function DebugLog:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:Show()
    end
end
