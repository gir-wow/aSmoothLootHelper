local _, SLH = ...
SLH.BossLootOverlay = {}

local BossLootOverlay = SLH.BossLootOverlay

local frame
local text
local itemRows = {}
local lastEncounterBoss
local testBoss
local testDifficulty
local updateTimer

local DEFAULT_TEXT = "Current boss: none\nWanted:\n- no matching drops"

local function NormalizeName(name)
    if not name then return nil end
    name = tostring(name):lower()
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("[^%w%s']", " ")
    name = name:gsub("%s+", " ")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function BossMatches(bossName, query)
    local boss = NormalizeName(bossName)
    local q    = NormalizeName(query)
    if not boss or not q or q == "" then return false end
    return boss == q or boss:find(q, 1, true) or q:find(boss, 1, true)
end

local function GetWantedItemsFromLootReserve()
    local wanted = {}
    if not LootReserve or not LootReserve.Client then return wanted end

    local function Mark(itemID)
        wanted[itemID] = wanted[itemID] or {}
        wanted[itemID].favorite = true
    end

    local function AddFrom(src)
        if not src then return end
        for itemID, enabled in pairs(src) do
            if enabled then Mark(itemID) end
        end
    end

    AddFrom(LootReserve.Client.CharacterFavorites)
    AddFrom(LootReserve.Client.GlobalFavorites)
    return wanted
end

local function GetWantedItemsFromBiS()
    local wanted = {}
    if not SLH.BisPreview or not SLH.BisPreview.GetActiveItemIDs then return wanted end

    local items = SLH.BisPreview:GetActiveItemIDs()
    for itemID in pairs(items) do
        wanted[itemID] = wanted[itemID] or {}
        wanted[itemID].bis = true
    end
    return wanted
end

local function MergeSources(dst, src)
    if not src then return end
    if src.favorite then dst.favorite = true end
    if src.bis then dst.bis = true end
end

local function GetWantedItems()
    local wanted = GetWantedItemsFromLootReserve()
    local bis = GetWantedItemsFromBiS()
    for itemID, sources in pairs(bis) do
        wanted[itemID] = wanted[itemID] or {}
        MergeSources(wanted[itemID], sources)
    end
    return wanted
end

local function GetWantedSourcesForLoot(wanted, lootID)
    local sources = {}
    MergeSources(sources, wanted[lootID])

    if LootReserve and LootReserve.Data then
        if LootReserve.Data.GetTokenRewards then
            local rewards = LootReserve.Data:GetTokenRewards(lootID)
            if rewards then
                for _, rewardID in ipairs(rewards) do
                    MergeSources(sources, wanted[rewardID])
                end
            end
        end

        if LootReserve.Data.GetToken then
            for wantedID, wantedSources in pairs(wanted) do
                if LootReserve.Data:GetToken(wantedID) == lootID then
                    MergeSources(sources, wantedSources)
                end
            end
        end
    end

    if AtlasLoot and AtlasLoot.Data and AtlasLoot.Data.Token and AtlasLoot.Data.Token.GetClassItemsForToken then
        local _, classToken = UnitClass("player")
        local rewards = AtlasLoot.Data.Token.GetClassItemsForToken(lootID, classToken)
        if rewards then
            for _, rewardID in ipairs(rewards) do
                MergeSources(sources, wanted[rewardID])
            end
        end
    end

    if sources.favorite or sources.bis then return sources end
    return nil
end

local function AddAtlasLootTokenListMatches(matches, wanted, tokenListName)
    if not tokenListName
       or not AtlasLoot
       or not AtlasLoot.Data
       or not AtlasLoot.Data.Token
       or not AtlasLoot.Data.Token.GetTokenData then
        return
    end

    local tokenList = AtlasLoot.Data.Token.GetTokenData(tokenListName)
    if not tokenList then return end

    for _, tokenID in ipairs(tokenList) do
        if type(tokenID) == "number" then
            local sources = GetWantedSourcesForLoot(wanted, tokenID)
            if sources then
                matches[tokenID] = matches[tokenID] or {}
                MergeSources(matches[tokenID], sources)
            end
        end
    end
end

local function AddLootMatches(matches, wanted, loot)
    if not loot then return end

    for _, lootEntry in ipairs(loot) do
        local itemID = lootEntry
        if type(lootEntry) == "table" then
            itemID = lootEntry.ID or lootEntry.id or lootEntry[1]
        end

        if type(itemID) == "number" then
            local sources = GetWantedSourcesForLoot(wanted, itemID)
            if sources then
                matches[itemID] = matches[itemID] or {}
                MergeSources(matches[itemID], sources)
            end
        end
    end
end

local function AddAtlasLootRowMatches(matches, wanted, row)
    if not row then return end

    for i = 2, #row do
        local itemID = row[i]
        if type(itemID) == "number" then
            local sources = GetWantedSourcesForLoot(wanted, itemID)
            if sources then
                matches[itemID] = matches[itemID] or {}
                MergeSources(matches[itemID], sources)
            end
        elseif type(itemID) == "string" then
            AddAtlasLootTokenListMatches(matches, wanted, itemID)
        end
    end

    local factionID
    if ATLASLOOT_IT_ALLIANCE then factionID = row[ATLASLOOT_IT_ALLIANCE] end
    if not factionID and ATLASLOOT_IT_HORDE then factionID = row[ATLASLOOT_IT_HORDE] end
    if type(factionID) == "number" then
        local sources = GetWantedSourcesForLoot(wanted, factionID)
        if sources then
            matches[factionID] = matches[factionID] or {}
            MergeSources(matches[factionID], sources)
        end
    end
end

local function GetAtlasLootDifficultyName(difficulty)
    if difficulty == "Heroic" then return "h" end
    if difficulty == "Celestial" then return "c" end
    return "n"
end

local function AddAtlasLootMatches(matches, wanted, bossQuery, difficulty)
    if not AtlasLoot or not AtlasLoot.ItemDB then return end

    local moduleName = "AtlasLootClassic_DungeonsAndRaids"
    local module = AtlasLoot.ItemDB:Get(moduleName)
    if not module and AtlasLoot.Loader and AtlasLoot.Loader.LoadModule then
        AtlasLoot.Loader:LoadModule(moduleName, function()
            BossLootOverlay:Refresh()
        end, "itemDB")
        module = AtlasLoot.ItemDB:Get(moduleName)
    end
    if not module or not AtlasLoot.ItemDB.GetModuleList then return end

    local diffNames = {}
    if difficulty == "Combined" then
        diffNames[1] = "n"
        diffNames[2] = "h"
        diffNames[3] = "c"
    else
        diffNames[1] = GetAtlasLootDifficultyName(difficulty)
    end
    local okList, contentList = pcall(AtlasLoot.ItemDB.GetModuleList, AtlasLoot.ItemDB, moduleName)
    if not okList or not contentList then return end

    for i = 1, #contentList do
        local contentName = contentList[i]
        local content = module[contentName]
        if content and content.items then
            for bossIndex, bossTable in ipairs(content.items) do
                local bossName = content:GetNameForItemTable(bossIndex, true)
                if bossName and BossMatches(bossName, bossQuery) and not bossTable.ExtraList then
                    for _, diffName in ipairs(diffNames) do
                        local okDiff, diff = pcall(module.GetDifficultyByName, module, diffName)
                        if okDiff and diff then
                            local okItems, rows = pcall(AtlasLoot.ItemDB.GetItemTable, AtlasLoot.ItemDB, moduleName, contentName, bossIndex, diff)
                            if okItems and rows then
                                for _, row in ipairs(rows) do
                                    AddAtlasLootRowMatches(matches, wanted, row)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function ScanCategoriesForBoss(matches, wanted, children, bossQuery, difficulty)
    if not children then return end

    local currentBoss
    for _, child in ipairs(children) do
        if child.Header and child.Name then
            currentBoss = child.Name
        elseif child.Loot and currentBoss and BossMatches(currentBoss, bossQuery) then
            if not difficulty or difficulty == "" or child.Name == difficulty then
                AddLootMatches(matches, wanted, child.Loot)
            end
        end

        if child.Children then
            ScanCategoriesForBoss(matches, wanted, child.Children, bossQuery, difficulty)
        end
    end
end

local function GetBossQuery()
    if testBoss then return testBoss end
    if lastEncounterBoss then return lastEncounterBoss end

    for i = 1, 5 do
        local unit = (i == 1) and "target" or ("boss" .. (i - 1))
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name then return name end
        end
    end

    return nil
end

local function GetDifficulty()
    if testDifficulty then return testDifficulty end

    local charDB = aSmoothLootHelperCharDB
    local configured = (charDB and charDB.bossLootOverlayDifficulty) or "Auto"
    if configured ~= "Auto" then return configured end

    local _, _, difficultyID, difficultyName = GetInstanceInfo()
    local name = difficultyName and difficultyName:lower() or ""

    if name:find("celestial", 1, true) or difficultyID == 237 then
        return "Celestial"
    end
    if name:find("heroic", 1, true) or difficultyID == 2 or difficultyID == 5 or difficultyID == 6 or difficultyID == 15 then
        return "Heroic"
    end
    if name:find("normal", 1, true) or difficultyID == 1 or difficultyID == 3 or difficultyID == 4 then
        return "Normal"
    end

    return "Normal"
end

local function GetDisplayName(itemID)
    local link = select(2, GetItemInfo(itemID))
    if link then return link end
    return "item:" .. tostring(itemID)
end

local function GetDisplaySortName(itemID)
    local name = GetItemInfo(itemID)
    if name then return name end
    return tostring(itemID)
end

local function GetSourceText(sources)
    if sources.favorite and sources.bis then return "Favorite, BiS" end
    if sources.favorite then return "Favorite" end
    if sources.bis then return "BiS" end
    return "Wanted"
end

local function SortedItems(matches)
    local byName = {}
    for itemID, sources in pairs(matches) do
        local name = GetItemInfo(itemID)
        local key = name and NormalizeName(name) or tostring(itemID)
        byName[key] = byName[key] or { itemID = itemID, sources = {}, sortName = GetDisplaySortName(itemID) }
        MergeSources(byName[key].sources, sources)
    end

    local items = {}
    for _, item in pairs(byName) do
        items[#items + 1] = item
    end
    table.sort(items, function(a, b)
        return a.sortName < b.sortName
    end)
    return items
end

local function BuildDisplay()
    local difficulty = GetDifficulty()
    local bossQuery = GetBossQuery()

    if not bossQuery or bossQuery == "" then
        return DEFAULT_TEXT, nil
    end

    local wanted = GetWantedItems()
    local wantedCount = 0
    for _ in pairs(wanted) do wantedCount = wantedCount + 1 end

    if wantedCount == 0 then
        return "Current boss: " .. bossQuery .. " (" .. difficulty .. ")\nWanted:\n- no items configured", nil
    end

    local matches = {}
    local hasLootSource = false
    if LootReserve and LootReserve.Data and LootReserve.Data.Categories then
        hasLootSource = true
        for _, category in pairs(LootReserve.Data.Categories) do
            if category.Children then
                ScanCategoriesForBoss(matches, wanted, category.Children, bossQuery, difficulty)
            end
        end
    end
    if AtlasLoot and AtlasLoot.ItemDB then
        hasLootSource = true
        AddAtlasLootMatches(matches, wanted, bossQuery, difficulty)
    end

    if not hasLootSource then
        return "Current boss: " .. bossQuery .. " (" .. difficulty .. ")\nWanted:\n- loot data not loaded", nil
    end

    local items = SortedItems(matches)
    local lines = {
        "Current boss: " .. bossQuery .. " (" .. difficulty .. ")",
        "Wanted:",
    }

    if #items == 0 then
        lines[#lines + 1] = "- no matching drops"
        return table.concat(lines, "\n"), nil
    else
        return table.concat(lines, "\n"), items
    end
end

local function SavePosition()
    if not frame or not aSmoothLootHelperCharDB then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    aSmoothLootHelperCharDB.bossLootOverlayPos = { point, relPoint, x, y }
end

local function ApplyOpacity()
    if not frame or not frame.bg then return end
    local opacity = (aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bossLootOverlayOpacity) or 35
    opacity = math.max(0, math.min(100, opacity))
    frame.bg:SetColorTexture(0, 0, 0, opacity / 100)
    frame.bg:SetShown(opacity > 0)
end

local function CreateOverlay()
    if frame then return end

    frame = CreateFrame("Frame", "SLHBossLootOverlayFrame", UIParent)
    frame:SetSize(360, 90)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetFrameStrata("DIALOG")

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
    frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)

    text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetTextColor(1, 0.92, 0.55)
    text:SetText(DEFAULT_TEXT)

    local pos = aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bossLootOverlayPos
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end

    ApplyOpacity()
    frame:Hide()
end

local function GetItemRow(index)
    if itemRows[index] then return itemRows[index] end

    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(16)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. tostring(self.itemID))
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.text:SetJustifyH("LEFT")

    itemRows[index] = row
    return row
end

local function HideUnusedRows(startIndex)
    for i = startIndex, #itemRows do
        itemRows[i]:Hide()
    end
end

function BossLootOverlay:Refresh()
    CreateOverlay()
    if not frame:IsShown() then return end

    local header, items = BuildDisplay()
    text:SetText(header)

    local width = math.max(text:GetStringWidth() + 20, 220)
    local height = text:GetStringHeight() + 20
    if items then
        local startY = -text:GetStringHeight() - 6
        for i, item in ipairs(items) do
            local row = GetItemRow(i)
            row.itemID = item.itemID
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, startY - ((i - 1) * 16))
            row:SetWidth(360)
            row.text:SetText("- " .. GetDisplayName(item.itemID) .. " (" .. GetSourceText(item.sources) .. ")")
            row:SetWidth(row.text:GetStringWidth() + 4)
            row:Show()
            width = math.max(width, row.text:GetStringWidth() + 20)
        end
        height = height + (#items * 16)
        HideUnusedRows(#items + 1)
    else
        HideUnusedRows(1)
    end

    frame:SetSize(width, math.max(height, 60))
    ApplyOpacity()
end

function BossLootOverlay:SetVisible(enabled)
    CreateOverlay()
    if aSmoothLootHelperCharDB then
        aSmoothLootHelperCharDB.bossLootOverlayEnabled = enabled and true or false
    end

    if enabled then
        frame:Show()
        self:Refresh()
    else
        frame:Hide()
    end
end

function BossLootOverlay:Toggle()
    CreateOverlay()
    self:SetVisible(not frame:IsShown())
end

function BossLootOverlay:SetTestBoss(bossName, difficulty)
    testBoss = bossName
    testDifficulty = difficulty
    self:SetVisible(true)
    self:Refresh()
end

function BossLootOverlay:ClearTestBoss()
    testBoss = nil
    testDifficulty = nil
    self:Refresh()
end

function BossLootOverlay:ApplyOpacity()
    ApplyOpacity()
end

function BossLootOverlay:Init()
    CreateOverlay()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ENCOUNTER_START")
    ev:RegisterEvent("ENCOUNTER_END")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    ev:RegisterEvent("INSTANCE_GROUP_SIZE_CHANGED")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "ENCOUNTER_START" then
            lastEncounterBoss = arg2
        elseif event == "ENCOUNTER_END" then
            lastEncounterBoss = nil
        end
        BossLootOverlay:Refresh()
    end)

    if aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bossLootOverlayEnabled then
        frame:Show()
        self:Refresh()
    end

    updateTimer = C_Timer.NewTicker(2, function()
        BossLootOverlay:Refresh()
    end)
end
