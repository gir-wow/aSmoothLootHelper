local _, SLH = ...
SLH.BisPreview = {}

local BisPreview = SLH.BisPreview
local ItemUtil   = SLH.ItemUtil

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local VARIANT_OFFSETS = { 0, 137, -137, 543, -543 }

local SLOT_ORDER = {
    { key = 1,  label = "Head" },
    { key = 2,  label = "Neck" },
    { key = 3,  label = "Shoulder" },
    { key = 15, label = "Back" },
    { key = 5,  label = "Chest" },
    { key = 9,  label = "Wrist" },
    { key = 10, label = "Hands" },
    { key = 6,  label = "Waist" },
    { key = 7,  label = "Legs" },
    { key = 8,  label = "Feet" },
    { key = 11, label = "Finger" },
    { key = 13, label = "Trinket" },
    { key = 16, label = "Main Hand" },
    { key = 17, label = "Off Hand" },
    { key = 0,  label = "Tier Tokens" },
}

local function NormalizeSlot(slotID)
    if not slotID then return nil end
    if slotID == 12 then return 11 end
    if slotID == 14 then return 13 end
    return slotID
end

------------------------------------------------------------------------
-- Name-based tier token detection (fallback when GetItemInfo itemType
-- is not "Miscellaneous"/"Junk" as expected in some MoP builds)
------------------------------------------------------------------------
local TOKEN_CLASS_MAP = {
    WARRIOR="PROTECTOR", HUNTER="PROTECTOR", SHAMAN="PROTECTOR", MONK="PROTECTOR",
    PALADIN="CONQUEROR", PRIEST="CONQUEROR", WARLOCK="CONQUEROR",
    DEATHKNIGHT="VANQUISHER", DRUID="VANQUISHER", MAGE="VANQUISHER", ROGUE="VANQUISHER",
}

local function GetTokenTypeFromName(name)
    if not name then return nil end
    if name:sub(-#"Protector") == "Protector" then return "PROTECTOR" end
    if name:sub(-#"Conqueror") == "Conqueror" then return "CONQUEROR" end
    if name:sub(-#"Vanquisher") == "Vanquisher" then return "VANQUISHER" end
    return nil
end

local function IsTokenForPlayer(name)
    local tokenType = GetTokenTypeFromName(name)
    if not tokenType then return nil end -- nil = not a token
    local _, classToken = UnitClass("player")
    return TOKEN_CLASS_MAP[classToken] == tokenType
end

local BT_SLOT_TO_ID = {
    ["Head"]      = 1,  ["Neck"]     = 2,  ["Shoulder"] = 3,
    ["Back"]      = 15, ["Chest"]    = 5,  ["Wrist"]    = 9,
    ["Hands"]     = 10, ["Waist"]    = 6,  ["Legs"]     = 7,
    ["Feet"]      = 8,  ["Finger"]   = 11, ["Trinket"]  = 13,
    ["Weapon"]    = 16, ["Main hand"] = 16, ["Off hand"] = 17,
}

local QUALITY_COLORS = {
    [0] = { r=0.62, g=0.62, b=0.62 },
    [1] = { r=1.00, g=1.00, b=1.00 },
    [2] = { r=0.12, g=1.00, b=0.00 },
    [3] = { r=0.00, g=0.44, b=0.87 },
    [4] = { r=0.64, g=0.21, b=0.93 },
    [5] = { r=1.00, g=0.50, b=0.00 },
}

local ROLL_COLORS = {
    NEED  = { r=0.00, g=1.00, b=0.00 },
    GREED = { r=1.00, g=0.82, b=0.00 },
    PASS  = { r=1.00, g=0.30, b=0.30 },
    ["?"] = { r=0.50, g=0.50, b=0.50 },
}

------------------------------------------------------------------------
-- Class / spec helpers
------------------------------------------------------------------------
local CLASS_TOKEN_TO_BT = {
    DEATHKNIGHT = "Death knight", DRUID = "Druid", HUNTER = "Hunter",
    MAGE = "Mage", MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest",
    ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
}

local CLASS_TOKEN_TO_FROG = {
    DEATHKNIGHT = "Death Knight", DRUID = "Druid", HUNTER = "Hunter",
    MAGE = "Mage", MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest",
    ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
}

local BT_SPEC_MAP = {
    ["Blood"]         = "Blood tank",
    ["Beast Mastery"] = "Beast mastery",
}

local function GetPlayerClassToken()
    local _, token = UnitClass("player")
    return token
end

local function GetPlayerSpecName()
    local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
                    or GetSpecialization
    local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
                    or GetSpecializationInfo
    if not getSpec then return nil end
    local idx = getSpec()
    if not idx or idx == 0 then return nil end
    local _, specName = getInfo(idx)
    return specName
end

------------------------------------------------------------------------
-- Item gathering — BisTooltip (structured bislists)
------------------------------------------------------------------------
local function GatherFromBisTooltipBislists(collected, className, specsToCheck)
    local classData = Bistooltip_wh_bislists[className]
    if not classData then return end

    for _, check in ipairs(specsToCheck) do
        -- Try exact match first, then prefix match
        local specKeys = {}
        if classData[check.spec] then
            specKeys[#specKeys + 1] = check.spec
        else
            for specKey in pairs(classData) do
                if specKey:sub(1, #check.spec) == check.spec then
                    specKeys[#specKeys + 1] = specKey
                end
            end
        end

        for _, specKey in ipairs(specKeys) do
            local specData = classData[specKey]
            local phasesToIter = {}
            if check.phase and specData[check.phase] then
                phasesToIter[1] = specData[check.phase]
            else
                for _, v in pairs(specData) do
                    if type(v) == "table" then
                        phasesToIter[#phasesToIter + 1] = v
                    end
                end
            end

            for _, slots in ipairs(phasesToIter) do
                for _, entry in ipairs(slots) do
                    if type(entry) == "table" then
                        local slotID = BT_SLOT_TO_ID[entry.slot_name]
                        for i = 1, 6 do
                            local itemID = entry[i]
                            if itemID and itemID > 0 then
                                if not collected[itemID] then
                                    collected[itemID] = { id = itemID, slotHint = slotID, providers = {} }
                                end
                                collected[itemID].providers["BisTooltip"] = true
                            end
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Item gathering — BisTooltip (flat items table fallback)
------------------------------------------------------------------------
local function GatherFromBisTooltipItems(collected, className, specsToCheck)
    if not Bistooltip_items then return end

    -- Build set of accepted spec names
    local acceptedSpecs = {}
    for _, check in ipairs(specsToCheck) do
        acceptedSpecs[check.spec] = true
    end

    for itemID, entries in pairs(Bistooltip_items) do
        for _, entry in ipairs(entries) do
            if entry.class_name == className then
                local specMatch = (next(acceptedSpecs) == nil) -- empty = accept all
                if not specMatch then
                    if acceptedSpecs[entry.spec_name] then
                        specMatch = true
                    else
                        for base in pairs(acceptedSpecs) do
                            if entry.spec_name:sub(1, #base) == base then
                                specMatch = true
                                break
                            end
                        end
                    end
                end
                if specMatch then
                    if not collected[itemID] then
                        collected[itemID] = { id = itemID, slotHint = nil, providers = {} }
                    end
                    collected[itemID].providers["BisTooltip"] = true
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Item gathering — BisTooltip (combined)
------------------------------------------------------------------------
local function GatherFromBisTooltip(collected)
    local classToken = GetPlayerClassToken()
    local className  = CLASS_TOKEN_TO_BT[classToken]
    if not className then return end

    local charDB = aSmoothLootHelperCharDB
    local specsToCheck = {}

    local mainSpec = charDB and charDB.bisMainSpec
    if mainSpec and mainSpec ~= "" then
        local specName, phaseName = mainSpec:match("^(.-)%s*/%s*(.+)$")
        if specName then
            specsToCheck[#specsToCheck + 1] = { spec = specName, phase = phaseName }
        else
            specsToCheck[#specsToCheck + 1] = { spec = mainSpec, phase = nil }
        end
    else
        local specName = GetPlayerSpecName()
        local btSpec = specName and (BT_SPEC_MAP[specName] or specName)
        if btSpec then
            specsToCheck[#specsToCheck + 1] = { spec = btSpec, phase = nil }
        end
    end

    if charDB and charDB.bisOffspecEnabled then
        local offSpec = charDB and charDB.bisOffspec
        if offSpec and offSpec ~= "" then
            local specName, phaseName = offSpec:match("^(.-)%s*/%s*(.+)$")
            if specName then
                specsToCheck[#specsToCheck + 1] = { spec = specName, phase = phaseName }
            else
                specsToCheck[#specsToCheck + 1] = { spec = offSpec, phase = nil }
            end
        end
    end

    if Bistooltip_wh_bislists then
        GatherFromBisTooltipBislists(collected, className, specsToCheck)
    else
        GatherFromBisTooltipItems(collected, className, specsToCheck)
    end
end

------------------------------------------------------------------------
-- Item gathering — FrogBiS
------------------------------------------------------------------------
local function GatherFromFrogBiS(collected)
    if not FrogBiS_Templates then return end

    local classToken = GetPlayerClassToken()
    local className  = CLASS_TOKEN_TO_FROG[classToken]
    if not className then return end

    local charDB = aSmoothLootHelperCharDB

    local function ParseSpec(setting)
        if not setting then return nil, nil end
        local k, s = setting:match("^(.-)::(.+)$")
        if k then return k, s end
        return setting, nil
    end

    local function GetLists(specKey, setFilter)
        local results = {}
        if FrogBiS_Templates[specKey] then
            local tpl = FrogBiS_Templates[specKey]
            if tpl.items and #tpl.items > 0 and not setFilter then
                results[#results + 1] = tpl.items
            end
        end
        if FrogBiSDB and FrogBiSDB.sets and FrogBiSDB.sets[specKey] then
            for _, s in ipairs(FrogBiSDB.sets[specKey]) do
                if s.items and #s.items > 0 then
                    if not setFilter or s.name == setFilter then
                        results[#results + 1] = s.items
                    end
                end
            end
        end
        return results
    end

    local checks = {}
    local mainRaw = charDB and charDB.bisMainSpec
    if mainRaw and mainRaw ~= "" then
        local k, s = ParseSpec(mainRaw)
        checks[#checks + 1] = { spec = k, setFilter = s }
    else
        local specName = GetPlayerSpecName()
        if specName then
            checks[#checks + 1] = { spec = specName .. " " .. className, setFilter = nil }
        end
    end

    if charDB and charDB.bisOffspecEnabled then
        local offRaw = charDB and charDB.bisOffspec
        if offRaw and offRaw ~= "" then
            local k, s = ParseSpec(offRaw)
            checks[#checks + 1] = { spec = k, setFilter = s }
        else
            for specKey in pairs(FrogBiS_Templates) do
                if specKey:find(className, 1, true) then
                    checks[#checks + 1] = { spec = specKey, setFilter = nil }
                end
            end
        end
    end

    for _, check in ipairs(checks) do
        local lists = GetLists(check.spec, check.setFilter)
        for _, items in ipairs(lists) do
            for _, entry in ipairs(items) do
                if entry.id and entry.id > 0 then
                    if not collected[entry.id] then
                        collected[entry.id] = { id = entry.id, slotHint = entry.slot, providers = {} }
                    end
                    collected[entry.id].providers["FrogBiS"] = true
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Item gathering — AtlasLoot Favourites
------------------------------------------------------------------------
local function GatherFromAtlasLoot(collected)
    local db = AtlasLootClassicDB
    if not db then return end

    local function ScanList(list)
        for itemID in pairs(list) do
            if type(itemID) == "number" and itemID > 0 then
                if not collected[itemID] then
                    collected[itemID] = { id = itemID, slotHint = nil, providers = {} }
                end
                collected[itemID].providers["AtlasLoot"] = true
            end
        end
    end

    local globalFav = db.global and db.global.Addons and db.global.Addons.Favourites
    if globalFav and globalFav.lists then
        for _, list in pairs(globalFav.lists) do ScanList(list) end
    end
    if db.profiles then
        for _, profile in pairs(db.profiles) do
            local profFav = profile.Addons and profile.Addons.Favourites
            if profFav and profFav.lists then
                for _, list in pairs(profFav.lists) do ScanList(list) end
            end
        end
    end
end

------------------------------------------------------------------------
-- Variant generation — expand base items into difficulty versions
------------------------------------------------------------------------
local function GenerateVariants(baseItems)
    local bySlot = {}
    local seen   = {}   -- variantID → itemData reference (for provider merging)

    for _, baseItem in pairs(baseItems) do
        local baseName = GetItemInfo(baseItem.id)

        for _, offset in ipairs(VARIANT_OFFSETS) do
            local vid = baseItem.id + offset
            if vid > 0 then
                if seen[vid] then
                    -- Merge provider tags into existing entry
                    for pName in pairs(baseItem.providers) do
                        seen[vid].providers[pName] = true
                    end
                else
                    local name, link, quality, ilvl, _, itemType, itemSubType, _, equipLoc, icon = GetItemInfo(vid)
                    if name then
                        local sameName = (offset == 0) or (baseName and name:lower() == baseName:lower())
                        if sameName then
                            local slotID
                            if ItemUtil:IsTierToken(link) or GetTokenTypeFromName(name) then
                                slotID = 0
                            elseif equipLoc and equipLoc ~= "" then
                                local slots = ItemUtil:GetEquipSlots(link)
                                if slots then slotID = NormalizeSlot(slots[1]) end
                            end
                            if not slotID and baseItem.slotHint then
                                slotID = NormalizeSlot(baseItem.slotHint)
                            end

                            if slotID then
                                -- Copy providers so variants share the source list
                                local provs = {}
                                for pName in pairs(baseItem.providers) do provs[pName] = true end

                                local itemData = {
                                    id        = vid,
                                    name      = name,
                                    link      = link,
                                    quality   = quality or 0,
                                    ilvl      = ilvl or 0,
                                    icon      = icon,
                                    providers = provs,
                                    isTierToken = (slotID == 0),
                                }
                                seen[vid] = itemData
                                if not bySlot[slotID] then bySlot[slotID] = {} end
                                bySlot[slotID][#bySlot[slotID] + 1] = itemData
                            end
                        end
                    elseif offset == 0 then
                        -- Base item not cached — add placeholder
                        local slotID = baseItem.slotHint and NormalizeSlot(baseItem.slotHint)
                        if slotID then
                            local provs = {}
                            for pName in pairs(baseItem.providers) do provs[pName] = true end
                            local itemData = {
                                id        = vid,
                                name      = nil,
                                link      = nil,
                                quality   = 0,
                                ilvl      = 0,
                                icon      = nil,
                                providers = provs,
                                loading   = true,
                            }
                            seen[vid] = itemData
                            if not bySlot[slotID] then bySlot[slotID] = {} end
                            bySlot[slotID][#bySlot[slotID] + 1] = itemData
                        end
                    end
                end
            end
        end
    end

    -- Sort: name ascending, then ilvl ascending
    for _, items in pairs(bySlot) do
        table.sort(items, function(a, b)
            local na, nb = a.name or "", b.name or ""
            if na ~= nb then return na < nb end
            return (a.ilvl or 0) < (b.ilvl or 0)
        end)
    end

    return bySlot
end

------------------------------------------------------------------------
-- Roll prediction — lightweight simulation (no provider queries)
-- Items are already known-BiS since they came from providers.
-- Returns: action ("NEED"/"GREED"/"PASS"/"?"), reason, isGreyed
------------------------------------------------------------------------
local function IsItemInBagsOrEquipped(itemID)
    for slot = 0, 18 do
        if GetInventoryItemID("player", slot) == itemID then return true end
    end
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemID   = (C_Container and C_Container.GetContainerItemID)   or GetContainerItemID
    if getNumSlots and getItemID then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for s = 1, (getNumSlots(bag) or 0) do
                if getItemID(bag, s) == itemID then return true end
            end
        end
    end
    return false
end

local function Debug(msg)
    if SLH.DebugLog then SLH.DebugLog:Add("[BisPreview] " .. msg) end
end

local function PredictRoll(itemData)
    if not itemData.link then return "?", "loading", false end

    local charDB   = aSmoothLootHelperCharDB
    local db       = aSmoothLootHelperDB
    local itemID   = itemData.id
    local itemLink = itemData.link

    if not db or not db.settings or not db.settings.autoGreedEnabled then
        return "?", "addon disabled", false
    end

    -- Tier token (use isTierToken flag + name-based fallback for MoP itemType quirks)
    local isToken = itemData.isTierToken or ItemUtil:IsTierToken(itemLink)
    if not isToken then
        isToken = (GetTokenTypeFromName(itemData.name) ~= nil)
    end
    if isToken then
        if charDB.tierTokenNeedEnabled ~= false then
            local forPlayer = ItemUtil:IsTierTokenForPlayer(itemLink)
            if not forPlayer then forPlayer = IsTokenForPlayer(itemData.name) end
            if forPlayer then
                if IsItemInBagsOrEquipped(itemID) then
                    Debug(itemData.name .. ": GREED (have token)")
                    return "GREED", "have token", true
                end
                if ItemUtil:IsEquippedBetter(itemLink) then
                    Debug(itemData.name .. ": GREED (token outgeared)")
                    return "GREED", "outgeared", true
                end
                Debug(itemData.name .. ": NEED (tier token)")
                return "NEED", "tier token", false
            else
                Debug(itemData.name .. ": PASS (wrong class token)")
                return "PASS", "wrong class", true
            end
        else
            Debug(itemData.name .. ": GREED (tier-need off)")
            return "GREED", "tier-need off", true
        end
    end

    -- Armor/stat filter — always enforced in preview (you'd never want off-armor or wrong-stat)
    local isOffArmor = ItemUtil:IsOffArmorType(itemLink)
    local isWrongStat = not isOffArmor and ItemUtil:IsWrongPrimaryStatForPlayer(itemLink)

    if isOffArmor then
        local act = charDB.armorFilterAction or "pass"
        Debug(itemData.name .. ": " .. (act == "pass" and "PASS" or "GREED") .. " (off-armor: " .. (ItemUtil:GetArmorSubtype(itemLink) or "?") .. ")")
        return act == "pass" and "PASS" or "GREED", "off-armor", true
    end

    if isWrongStat then
        local act = charDB.armorFilterAction or "pass"
        Debug(itemData.name .. ": " .. (act == "pass" and "PASS" or "GREED") .. " (wrong stat)")
        return act == "pass" and "PASS" or "GREED", "wrong stat", true
    end

    -- Collected: exact ID check (equipped + bags) — no offset guessing
    if charDB.bisNeedEnabled then
        if IsItemInBagsOrEquipped(itemID) then
            Debug(itemData.name .. ": GREED (collected)")
            return "GREED", "collected", true
        end
        -- Outgear guard via ilvl
        if ItemUtil:IsEquippedBetter(itemLink) then
            Debug(itemData.name .. ": GREED (outgeared)")
            return "GREED", "outgeared", true
        end
        Debug(itemData.name .. ": NEED")
        return "NEED", "", false
    end

    -- Downgrade
    if charDB.downgradeGreedEnabled then
        if ItemUtil:IsEquippedBetter(itemLink) then
            Debug(itemData.name .. ": GREED (equipped better)")
            return "GREED", "equipped better", true
        end
    end

    return "NEED", "", false
end

------------------------------------------------------------------------
-- UI — frame, scroll, row/header pools
------------------------------------------------------------------------
local frame, scrollFrame, content
local rowPool    = {}
local headerPool = {}
local filterMode = "all"  -- "all" | "need" | "upgrades" (need+greed, hide pass)

local ROW_HEIGHT     = 36
local HEADER_HEIGHT  = 24
local CONTENT_WIDTH  = 470

local function GetRow(parent, index)
    if rowPool[index] then
        rowPool[index]:Show()
        return rowPool[index]
    end

    local row = CreateFrame("Button", nil, parent)
    row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 4, 0)
    row.icon = icon

    local border = row:CreateTexture(nil, "OVERLAY")
    border:SetSize(36, 36)
    border:SetPoint("CENTER", icon, "CENTER")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAlpha(0.65)
    row.border = border

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFontObject("GameFontNormal")
    nameText:SetPoint("LEFT", icon, "RIGHT", 6, 5)
    nameText:SetPoint("RIGHT", row, "RIGHT", -100, 5)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    local ilvlText = row:CreateFontString(nil, "OVERLAY")
    ilvlText:SetFontObject("GameFontHighlightSmall")
    ilvlText:SetPoint("LEFT", icon, "RIGHT", 6, -8)
    ilvlText:SetJustifyH("LEFT")
    row.ilvlText = ilvlText

    local provText = row:CreateFontString(nil, "OVERLAY")
    provText:SetFontObject("GameFontDisableSmall")
    provText:SetPoint("LEFT", ilvlText, "RIGHT", 6, 0)
    provText:SetJustifyH("LEFT")
    row.provText = provText

    local rollText = row:CreateFontString(nil, "OVERLAY")
    rollText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    rollText:SetPoint("RIGHT", row, "RIGHT", -4, 5)
    rollText:SetJustifyH("RIGHT")
    row.rollText = rollText

    local reasonText = row:CreateFontString(nil, "OVERLAY")
    reasonText:SetFontObject("GameFontDisableSmall")
    reasonText:SetPoint("RIGHT", row, "RIGHT", -4, -8)
    reasonText:SetJustifyH("RIGHT")
    row.reasonText = reasonText

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    rowPool[index] = row
    return row
end

local function GetHeader(parent, index)
    if headerPool[index] then
        headerPool[index]:Show()
        return headerPool[index]
    end

    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetSize(CONTENT_WIDTH, HEADER_HEIGHT)

    local text = hdr:CreateFontString(nil, "OVERLAY")
    text:SetFontObject("GameFontNormalLarge")
    text:SetPoint("LEFT", 4, 0)
    text:SetTextColor(0, 0.8, 1)
    hdr.text = text

    local line = hdr:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)

    headerPool[index] = hdr
    return hdr
end

------------------------------------------------------------------------
-- Populate the scrollable content
------------------------------------------------------------------------
local function PopulateContent(bySlot)
    for _, r in pairs(rowPool)    do r:Hide() end
    for _, h in pairs(headerPool) do h:Hide() end

    local ri, hi = 0, 0
    local yOff   = 0
    local any    = false

    for _, slotInfo in ipairs(SLOT_ORDER) do
        local items = bySlot[slotInfo.key]
        if items and #items > 0 then
            -- Pre-filter items for this slot
            local visibleItems = {}
            for _, itemData in ipairs(items) do
                local rollAction, rollReason, isGreyed = PredictRoll(itemData)
                local show = true
                if filterMode == "need" and rollAction ~= "NEED" then show = false end
                if filterMode == "upgrades" and rollAction == "PASS" then show = false end
                if show then
                    visibleItems[#visibleItems + 1] = { data = itemData, action = rollAction, reason = rollReason, greyed = isGreyed }
                end
            end

            if #visibleItems > 0 then
            any = true

            hi = hi + 1
            local hdr = GetHeader(content, hi)
            hdr.text:SetText(slotInfo.label .. "  |cff888888(" .. #visibleItems .. ")|r")
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOff)
            yOff = yOff + HEADER_HEIGHT + 2

            for _, vis in ipairs(visibleItems) do
                local itemData   = vis.data
                local rollAction = vis.action
                local rollReason = vis.reason
                local isGreyed   = vis.greyed

                ri = ri + 1
                local row = GetRow(content, ri)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOff)

                -- Icon
                if itemData.icon then
                    row.icon:SetTexture(itemData.icon)
                    row.icon:SetDesaturated(isGreyed)
                    row.icon:SetAlpha(isGreyed and 0.5 or 1)
                else
                    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    row.icon:SetDesaturated(false)
                    row.icon:SetAlpha(0.5)
                end

                -- Quality border
                local qc = QUALITY_COLORS[itemData.quality] or QUALITY_COLORS[0]
                row.border:SetVertexColor(qc.r, qc.g, qc.b)

                -- Name
                local dName = itemData.name or ("Item #" .. itemData.id)
                row.nameText:SetText(dName)
                if isGreyed then
                    row.nameText:SetTextColor(qc.r * 0.5, qc.g * 0.5, qc.b * 0.5)
                else
                    row.nameText:SetTextColor(qc.r, qc.g, qc.b)
                end

                -- ilvl
                if itemData.ilvl and itemData.ilvl > 0 then
                    row.ilvlText:SetText("ilvl " .. itemData.ilvl)
                    row.ilvlText:SetTextColor(isGreyed and 0.4 or 0.7, isGreyed and 0.4 or 0.7, isGreyed and 0.4 or 0.7)
                else
                    row.ilvlText:SetText("")
                end

                -- Provider tags
                local pNames = {}
                for p in pairs(itemData.providers) do pNames[#pNames + 1] = p end
                table.sort(pNames)
                row.provText:SetText("[" .. table.concat(pNames, ", ") .. "]")

                -- Roll badge
                local rc = ROLL_COLORS[rollAction] or ROLL_COLORS["?"]
                row.rollText:SetText(rollAction)
                row.rollText:SetTextColor(rc.r, rc.g, rc.b)

                -- Reason
                row.reasonText:SetText((rollReason and rollReason ~= "") and ("(" .. rollReason .. ")") or "")

                -- Tooltip + shift-click
                local link = itemData.link
                local id   = itemData.id
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if link then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                    else
                        GameTooltip:AddLine("Item #" .. id, 1, 1, 1)
                        GameTooltip:AddLine("Loading\226\128\166", 0.7, 0.7, 0.7)
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row:RegisterForClicks("LeftButtonUp")
                row:SetScript("OnClick", function(_, btn)
                    if IsShiftKeyDown() and link then
                        ChatEdit_InsertLink(link)
                    end
                end)

                yOff = yOff + ROW_HEIGHT
            end

            yOff = yOff + 6
            end -- #visibleItems > 0
        end
    end

    if not any then
        hi = hi + 1
        local hdr = GetHeader(content, hi)
        hdr.text:SetText("No BiS items found")
        hdr.text:SetTextColor(0.7, 0.7, 0.7)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        yOff = HEADER_HEIGHT + 8

        ri = ri + 1
        local row = GetRow(content, ri)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOff)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(0.5)
        row.border:SetVertexColor(0.5, 0.5, 0.5)
        row.nameText:SetText("Install BisTooltip, FrogBiS, or AtlasLoot")
        row.nameText:SetTextColor(0.6, 0.6, 0.6)
        row.ilvlText:SetText("and configure your BiS lists")
        row.ilvlText:SetTextColor(0.5, 0.5, 0.5)
        row.provText:SetText("")
        row.rollText:SetText("")
        row.reasonText:SetText("")
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:SetScript("OnClick", nil)
        yOff = yOff + ROW_HEIGHT
    end

    content:SetHeight(yOff + 20)
end

------------------------------------------------------------------------
-- Frame creation
------------------------------------------------------------------------
local function CreateMainFrame()
    if frame then return end

    frame = CreateFrame("Frame", "SLHBisPreviewFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(520, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if aSmoothLootHelperCharDB then
            aSmoothLootHelperCharDB.bisPreviewPos = { point, relPoint, x, y }
        end
    end)
    frame:SetFrameStrata("DIALOG")
    frame.TitleText:SetText("aSmoothLootHelper \226\128\148 BiS Preview")

    -- Restore saved position
    local pos = aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bisPreviewPos
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end

    -- Allow ESC to close
    tinsert(UISpecialFrames, "SLHBisPreviewFrame")

    -- Filter buttons (top bar)
    local function MakeFilterBtn(label, mode, xOff)
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(70, 20)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xOff, -26)
        btn:SetText(label)
        btn:SetScript("OnClick", function()
            filterMode = mode
            BisPreview:RepopulateIfShown()
        end)
        return btn
    end
    frame.btnAll      = MakeFilterBtn("All",      "all",      14)
    frame.btnNeed     = MakeFilterBtn("Need",     "need",     88)
    frame.btnUpgrades = MakeFilterBtn("No Pass",  "upgrades", 162)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() BisPreview:Refresh() end)

    -- Count label
    local countLabel = frame:CreateFontString(nil, "OVERLAY")
    countLabel:SetFontObject("GameFontDisableSmall")
    countLabel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
    frame.countLabel = countLabel

    -- Scroll frame
    scrollFrame = CreateFrame("ScrollFrame", "SLHBisPreviewScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame.InsetBg or frame, "TOPLEFT", 8, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 38)

    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(CONTENT_WIDTH)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    frame:Hide()
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
local lastBySlot = nil  -- cached for filter changes without re-gather

function BisPreview:RepopulateIfShown()
    if frame and frame:IsShown() and lastBySlot then
        PopulateContent(lastBySlot)
    end
end

function BisPreview:Refresh()
    if not frame then return end

    local charDB     = aSmoothLootHelperCharDB
    local provEnabled = charDB and charDB.bisProviderEnabled
    local collected   = {}

    if not provEnabled or provEnabled["BisTooltip"] ~= false then
        GatherFromBisTooltip(collected)
    end
    if not provEnabled or provEnabled["FrogBiS"] ~= false then
        GatherFromFrogBiS(collected)
    end
    if not provEnabled or provEnabled["AtlasLoot"] ~= false then
        GatherFromAtlasLoot(collected)
    end

    -- Populate immediately with whatever is cached
    local function DoPopulate()
        local bySlot     = GenerateVariants(collected)
        lastBySlot = bySlot
        local totalItems  = 0
        local baseCount   = 0
        local loadingCount = 0
        for _ in pairs(collected) do baseCount = baseCount + 1 end
        for _, items in pairs(bySlot) do
            totalItems = totalItems + #items
            for _, item in ipairs(items) do
                if item.loading then loadingCount = loadingCount + 1 end
            end
        end

        if frame.countLabel then
            local msg = totalItems .. " items (" .. baseCount .. " base)"
            if loadingCount > 0 then
                msg = msg .. "  |cffffcc00" .. loadingCount .. " loading...|r"
            end
            frame.countLabel:SetText(msg)
        end

        PopulateContent(bySlot)
        return loadingCount
    end

    DoPopulate()

    -- Request loading ONLY for base items (collected IDs) that aren't cached yet.
    -- Variant IDs from offsets are speculative and crash Item:CreateFromItemID if invalid.
    local repopTimer = nil
    local function ScheduleRepopulate()
        if repopTimer then return end
        repopTimer = C_Timer.After(0.5, function()
            repopTimer = nil
            if frame and frame:IsShown() then
                DoPopulate()
            end
        end)
    end

    for itemID in pairs(collected) do
        if not GetItemInfo(itemID) then
            local ok, itemObj = pcall(Item.CreateFromItemID, Item, itemID)
            if ok and itemObj and itemObj.GetItemID and itemObj:GetItemID() then
                itemObj:ContinueOnItemLoad(function()
                    ScheduleRepopulate()
                end)
            end
        end
    end

    -- Final timeout: after 8s do one last populate regardless
    C_Timer.After(8, function()
        if frame and frame:IsShown() then
            DoPopulate()
        end
    end)
end

function BisPreview:Toggle()
    CreateMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:Refresh()
    end
end

function BisPreview:Show()
    CreateMainFrame()
    frame:Show()
    self:Refresh()
end

function BisPreview:Hide()
    if frame then frame:Hide() end
end

function BisPreview:Init()
    -- Frame created on demand
end
