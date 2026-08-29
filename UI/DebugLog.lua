local _, SLH = ...
SLH.DebugLog = {}

local DebugLog = SLH.DebugLog

------------------------------------------------------------------------
-- Log storage: multi-session ring buffer persisted in SavedVariables
------------------------------------------------------------------------
local logEntries = {}          -- current session (in-memory)
local MAX_ENTRIES = 500
local MAX_SESSIONS = 10
local viewMode = "current"    -- "all" | "current" | "previous" | "history"
local sessionIdx = nil         -- 1-based index when browsing sessions in "all"

------------------------------------------------------------------------
-- Session management: each reload/login starts a new session
------------------------------------------------------------------------
function DebugLog:InitStorage()
    if not aSmoothLootHelperDB then aSmoothLootHelperDB = {} end
    local db = aSmoothLootHelperDB

    -- Migrate old format → sessions array
    if not db.debugSessions then
        db.debugSessions = {}
        if db.debugLogPrevious and #db.debugLogPrevious > 0 then
            table.insert(db.debugSessions, {
                time = "Older",
                entries = db.debugLogPrevious,
            })
        end
        if db.debugLogCurrent and #db.debugLogCurrent > 0 then
            table.insert(db.debugSessions, {
                time = "Previous",
                entries = db.debugLogCurrent,
            })
        end
        db.debugLogPrevious = nil
        db.debugLogCurrent = nil
    end

    -- Start a new session
    table.insert(db.debugSessions, {
        time = date("%Y-%m-%d %H:%M"),
        entries = {},
    })

    -- Trim old sessions
    while #db.debugSessions > MAX_SESSIONS do
        table.remove(db.debugSessions, 1)
    end
end

local function GetSessions()
    return (aSmoothLootHelperDB and aSmoothLootHelperDB.debugSessions) or {}
end

local function GetCurrentSavedSession()
    local sessions = GetSessions()
    return sessions[#sessions]
end

local function SaveEntry(entry)
    local session = GetCurrentSavedSession()
    if not session then return end
    session.entries[#session.entries + 1] = entry
    if #session.entries > MAX_ENTRIES then
        table.remove(session.entries, 1)
    end
end

------------------------------------------------------------------------
-- Add a message to the log buffer
------------------------------------------------------------------------
function DebugLog:Add(msg)
    local entry = date("%H:%M:%S") .. "  " .. msg
    logEntries[#logEntries + 1] = entry
    if #logEntries > MAX_ENTRIES then
        table.remove(logEntries, 1)
    end
    SaveEntry(entry)
    if self.frame and self.frame:IsShown() then
        self:RefreshText()
    end
end

------------------------------------------------------------------------
-- Build history view lines
------------------------------------------------------------------------
local function BuildHistoryLines()
    local history = SLH.RollManager and SLH.RollManager:GetLootHistory() or {}
    local lines = {}
    for _, e in ipairs(history) do
        if e.action == "SEPARATOR" then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cffffff00" .. (e.item or "") .. "|r"
            lines[#lines + 1] = ""
        elseif e.action == "MODE" then
            lines[#lines + 1] = "|cff88ccff" .. e.time .. "  " .. (e.item or "") .. "|r"
        else
            local color = "|cff66ff66"
            if e.action == "NEED" then color = "|cffff6666"
            elseif e.action == "PASS" then color = "|cff999999" end
            lines[#lines + 1] = e.time .. "  " .. color .. e.action .. "|r  " .. (e.link or e.item or "?") .. "  " .. (e.reason or "")
        end
    end
    return lines
end

------------------------------------------------------------------------
-- Get entries for the current view
------------------------------------------------------------------------
local function GetSessionEntries(idx)
    local sessions = GetSessions()
    local s = sessions[idx]
    if not s then return {} end
    if idx == #sessions then return logEntries end  -- current = live
    return s.entries or {}
end

local function GetViewEntries()
    if viewMode == "current" then
        return logEntries
    elseif viewMode == "previous" then
        local sessions = GetSessions()
        if #sessions >= 2 then
            return sessions[#sessions - 1].entries or {}
        end
        return {}
    elseif viewMode == "history" then
        return BuildHistoryLines()
    else -- "all"
        if sessionIdx then
            return GetSessionEntries(sessionIdx)
        end
        -- Combined view
        local sessions = GetSessions()
        local all = {}
        for i, s in ipairs(sessions) do
            if #all > 0 then
                all[#all + 1] = ""
                all[#all + 1] = "|cffffff00--- Session " .. i .. ": " .. (s.time or "?") .. " ---|r"
                all[#all + 1] = ""
            end
            local entries = (i == #sessions) and logEntries or (s.entries or {})
            for _, e in ipairs(entries) do
                all[#all + 1] = e
            end
        end
        return all
    end
end

local function GetViewTitle()
    local sessions = GetSessions()
    if viewMode == "current" then
        return "Current Session"
    elseif viewMode == "previous" then
        if #sessions >= 2 then
            return "Previous Session — " .. (sessions[#sessions - 1].time or "?")
        end
        return "Previous Session"
    elseif viewMode == "history" then
        return "Loot History"
    elseif sessionIdx then
        local s = sessions[sessionIdx]
        return "Session " .. sessionIdx .. " / " .. #sessions .. " — " .. (s and s.time or "?")
    else
        return "All Sessions (" .. #sessions .. ")"
    end
end

------------------------------------------------------------------------
-- Text access
------------------------------------------------------------------------
function DebugLog:GetText()
    local entries = GetViewEntries()
    if #entries == 0 then
        if viewMode == "previous" then
            return "No previous session log available."
        elseif viewMode == "history" then
            return "No loot history yet. Auto-rolled items will appear here."
        end
        return "No debug entries yet. Enable debug mode and do a loot roll."
    end
    return table.concat(entries, "\n")
end

function DebugLog:Clear()
    wipe(logEntries)
    if self.frame and self.frame:IsShown() then
        self:RefreshText()
    end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------
local frame

function DebugLog:RefreshText()
    if not frame then return end
    local entries = GetViewEntries()
    frame.editBox:SetText(self:GetText())
    frame.editBox:SetCursorPosition(frame.editBox:GetNumLetters())
    frame.countLabel:SetText(#entries .. " entries")
    frame.TitleText:SetText("aSmoothLootHelper — " .. GetViewTitle())

    -- Tab highlights (native WoW tab style)
    if frame.tabFrames then
        for _, t in ipairs(frame.tabFrames) do
            if t.mode == viewMode then
                PanelTemplates_SelectTab(t)
            else
                PanelTemplates_DeselectTab(t)
            end
        end
    end

    -- Previous/Next button state
    local sessions = GetSessions()
    local hasSessions = #sessions > 0
    local canPrev = viewMode == "all" and hasSessions and (not sessionIdx or sessionIdx > 1)
    local canNext = viewMode == "all" and hasSessions and (not sessionIdx or sessionIdx < #sessions)
    frame.prevBtn:SetEnabled(canPrev and true or false)
    frame.nextBtn:SetEnabled(canNext and true or false)

    if viewMode == "all" and sessionIdx then
        frame.navLabel:SetText(sessionIdx .. " / " .. #sessions)
    elseif viewMode == "all" then
        frame.navLabel:SetText(#sessions .. " sessions — click < > to browse")
    else
        frame.navLabel:SetText("")
    end

    -- Scroll to bottom
    C_Timer.After(0, function()
        if frame and frame.scrollFrame then
            frame.scrollFrame:SetVerticalScroll(frame.scrollFrame:GetVerticalScrollRange())
        end
    end)
end

function DebugLog:Show()
    if not frame then
        frame = CreateFrame("Frame", "SLHDebugLogFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(740, 460)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("DIALOG")

        -- Scroll frame — bottom anchored above the button row
        local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", frame.InsetBg or frame, "TOPLEFT", 8, -30)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 42)
        frame.scrollFrame = scrollFrame

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetWidth(scrollFrame:GetWidth() - 10)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        editBox:SetHyperlinksEnabled(true)
        editBox:SetScript("OnHyperlinkEnter", function(self, link)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(link)
        end)
        editBox:SetScript("OnHyperlinkLeave", function()
            GameTooltip:Hide()
        end)
        scrollFrame:SetScrollChild(editBox)
        frame.editBox = editBox

        ----------------------------------------------------------------
        -- Bottom bar: < Previous | Clear | nav label | Select All | Next >
        ----------------------------------------------------------------
        local R1 = 10

        local prevBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        prevBtn:SetSize(90, 22)
        prevBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, R1)
        prevBtn:SetText("< Previous")
        prevBtn:SetScript("OnClick", function()
            local sessions = GetSessions()
            if viewMode == "all" then
                if not sessionIdx then
                    sessionIdx = #sessions
                end
                if sessionIdx > 1 then
                    sessionIdx = sessionIdx - 1
                end
                DebugLog:RefreshText()
            end
        end)
        frame.prevBtn = prevBtn

        local nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        nextBtn:SetSize(90, 22)
        nextBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, R1)
        nextBtn:SetText("Next >")
        nextBtn:SetScript("OnClick", function()
            local sessions = GetSessions()
            if viewMode == "all" then
                if not sessionIdx then
                    sessionIdx = 1  -- enter browse at first
                elseif sessionIdx < #sessions then
                    sessionIdx = sessionIdx + 1
                end
                DebugLog:RefreshText()
            end
        end)
        frame.nextBtn = nextBtn

        local navLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        navLabel:SetPoint("CENTER", frame, "BOTTOM", 0, R1 + 11)
        frame.navLabel = navLabel

        local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        clearBtn:SetSize(70, 22)
        clearBtn:SetPoint("RIGHT", navLabel, "LEFT", -50, 0)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            if viewMode == "history" then
                if SLH.RollManager then SLH.RollManager:ClearLootHistory() end
            else
                DebugLog:Clear()
            end
            DebugLog:RefreshText()
        end)

        local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        selectBtn:SetSize(70, 22)
        selectBtn:SetPoint("LEFT", navLabel, "RIGHT", 50, 0)
        selectBtn:SetText("Select All")
        selectBtn:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
        end)

        ----------------------------------------------------------------
        -- WoW-style tabs below the window (CharacterFrameTabButtonTemplate)
        ----------------------------------------------------------------
        local tabData = {
            { name = "SLHLogTabAll",  label = "All Sessions",  mode = "all" },
            { name = "SLHLogTabCur",  label = "Current",       mode = "current" },
            { name = "SLHLogTabPrev", label = "Previous",      mode = "previous" },
            { name = "SLHLogTabHist", label = "Loot History",  mode = "history" },
        }

        local tabFrames = {}
        local function OnTabClick(tab)
            viewMode = tab.mode
            sessionIdx = nil
            for _, t in ipairs(tabFrames) do
                PanelTemplates_DeselectTab(t)
            end
            PanelTemplates_SelectTab(tab)
            DebugLog:RefreshText()
        end

        for i, td in ipairs(tabData) do
            local tab = CreateFrame("Button", td.name, frame, "CharacterFrameTabButtonTemplate")
            tab:SetText(td.label)
            tab.mode = td.mode
            tab:SetScript("OnLoad", nil)
            tab:SetScript("OnShow", nil)
            tab:SetScript("OnClick", OnTabClick)
            if i == 1 then
                tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 8)
            else
                tab:SetPoint("LEFT", tabFrames[i - 1], "RIGHT")
            end
            tabFrames[i] = tab
        end

        -- Size tabs evenly and set IDs
        local tabWidth = 740 / #tabData
        for i, t in ipairs(tabFrames) do
            t:SetID(i)
            PanelTemplates_TabResize(t, nil, tabWidth, tabWidth)
            if t.mode == viewMode then
                PanelTemplates_SelectTab(t)
            else
                PanelTemplates_DeselectTab(t)
            end
        end

        frame.tabFrames = tabFrames
        frame.tabAll  = tabFrames[1]
        frame.tabCur  = tabFrames[2]
        frame.tabPrev = tabFrames[3]
        frame.tabHist = tabFrames[4]

        -- Entry count
        local countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, R1 + 5)
        frame.countLabel = countLabel

        self.frame = frame
    end

    self:RefreshText()
    frame:Show()
end

function DebugLog:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:Show()
    end
end
