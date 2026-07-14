local _, SLH = ...

------------------------------------------------------------------------
-- AtlasLoot Favourites provider
--
-- Reads the player's AtlasLoot Favourites lists so that any item the
-- player has manually starred in AtlasLoot is treated as BiS by
-- aSmoothLootHelper (auto-need if not yet collected).
--
-- Primary API (preferred — resolves active list + all sub-lists):
--   AtlasLoot.Addons.Favourites:IsFavouriteItemID(itemID)
--   → returns the list name (truthy) or nil/false
--
-- SavedVariables fallback structure (used when AtlasLoot hasn't fully
-- initialised yet):
--   AtlasLootClassicDB = {
--     ["global"] = {
--       ["Addons"] = {
--         ["Favourites"] = {
--           ["lists"] = {
--             ["GlobalBase"]  = { [itemID] = true, ... },
--             ["MyCustomList"] = { [itemID] = true, ... },
--           }
--         }
--       }
--     },
--     ["profiles"] = {
--       ["Default"] = {
--         ["Addons"] = {
--           ["Favourites"] = {
--             ["lists"] = {
--               ["ProfileBase"] = { [itemID] = true, ... },
--             }
--           }
--         }
--       }
--     }
--   }
--
-- MoP warforged ID offsets (same as BisTooltipProvider):
--   HWF_OFFSET = 543, NWF_OFFSET = 747
-- If the player wishlisted a base item, a warforged variant that drops
-- is also matched.
------------------------------------------------------------------------

local provider = {}

local HWF_OFFSET = 543
local NWF_OFFSET = 747

------------------------------------------------------------------------
local function Debug(msg)
    local db = aSmoothLootHelperDB
    if db and db.settings and db.settings.debugMode then
        print("|cff888888[SLH debug]|r " .. msg)
    end
    if SLH.DebugLog then
        SLH.DebugLog:Add(msg)
    end
end

------------------------------------------------------------------------
-- Return the live Favourites module once AtlasLoot is ready.
------------------------------------------------------------------------
local function GetFavourites()
    if AtlasLoot
       and AtlasLoot.Addons
       and AtlasLoot.Addons.Favourites
       and AtlasLoot.Addons.Favourites.IsFavouriteItemID then
        return AtlasLoot.Addons.Favourites
    end
    return nil
end

local DIFFICULTY_OFFSETS = { HWF_OFFSET, -HWF_OFFSET, NWF_OFFSET, -NWF_OFFSET,
                             137, -137, 543 + 137, -(543 + 137), 747 + 137, -(747 + 137) }

------------------------------------------------------------------------
-- Check itemID AND its warforged/difficulty variants against a single
-- list table.
------------------------------------------------------------------------
local function CheckListForID(list, itemID)
    if not list then return false end
    if list[itemID] then return true end
    for _, offset in ipairs(DIFFICULTY_OFFSETS) do
        if list[itemID + offset] then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Name-based fallback: check if the dropped item's name matches any
-- favourited item's name (for cross-difficulty variants where ID
-- offsets don't work).
------------------------------------------------------------------------
local function CheckListForName(list, itemName)
    if not list or not itemName then return false end
    local lowerName = itemName:lower()
    for favID in pairs(list) do
        if type(favID) == "number" then
            local favName = GetItemInfo(favID)
            if favName and favName:lower() == lowerName then
                return true
            end
        end
    end
    return false
end

------------------------------------------------------------------------
-- Fallback: scan the raw SavedVariables when the live module isn't ready.
-- Checks ALL lists across ALL profiles and global.
-- If byName is provided, also does name-based matching.
------------------------------------------------------------------------
local function IsFavouriteInDB(itemID, byName)
    local db = AtlasLootClassicDB
    if not db then return false end

    -- Global lists
    local globalFav = db.global
                      and db.global.Addons
                      and db.global.Addons.Favourites
    if globalFav and globalFav.lists then
        for _, list in pairs(globalFav.lists) do
            if CheckListForID(list, itemID) then return true end
            if byName and CheckListForName(list, byName) then return true end
        end
    end

    -- All profile lists
    if db.profiles then
        for _, profile in pairs(db.profiles) do
            local profFav = profile.Addons and profile.Addons.Favourites
            if profFav and profFav.lists then
                for _, list in pairs(profFav.lists) do
                    if CheckListForID(list, itemID) then return true end
                    if byName and CheckListForName(list, byName) then return true end
                end
            end
        end
    end

    return false
end

------------------------------------------------------------------------
-- IsBiS: item is "BiS" if it is in any of the player's Favourites lists.
------------------------------------------------------------------------
function provider:IsBiS(itemID)
    local fav = GetFavourites()
    local dropName = GetItemInfo(itemID)   -- for name-based fallback

    if fav then
        -- Check the exact ID via the live API
        local result = fav:IsFavouriteItemID(itemID)
        if result then
            Debug("    [AtlasLoot] favourited (live): " .. itemID)
            return true
        end
        -- Check all difficulty/warforged variants
        for _, offset in ipairs(DIFFICULTY_OFFSETS) do
            local variant = itemID + offset
            if fav:IsFavouriteItemID(variant) then
                Debug("    [AtlasLoot] favourited via variant " .. variant .. " (live)")
                return true
            end
        end
        -- Name-based fallback against the DB (live API has no name search)
        if dropName and IsFavouriteInDB(itemID, dropName) then
            Debug("    [AtlasLoot] favourited by name '" .. dropName .. "' (DB fallback)")
            return true
        end
        Debug("    [AtlasLoot] not in favourites (live): " .. itemID)
        return false
    end

    -- SavedVariables fallback (with name matching)
    local result = IsFavouriteInDB(itemID, dropName)
    Debug("    [AtlasLoot] not in favourites (DB fallback): " .. itemID .. " = " .. tostring(result))
    return result
end

------------------------------------------------------------------------
-- IsCollected: check bags and equipped slots.
------------------------------------------------------------------------
function provider:IsCollected(itemID)
    -- Equipped
    for slot = 0, 18 do
        if GetInventoryItemID("player", slot) == itemID then return true end
    end
    -- Bags
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemID   = (C_Container and C_Container.GetContainerItemID)   or GetContainerItemID
    if getNumSlots and getItemID then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, (getNumSlots(bag) or 0) do
                if getItemID(bag, slot) == itemID then return true end
            end
        end
    end
    -- Bank cache (populated on BANKFRAME_OPENED — see ADDON_PLAN / future work)
    local bankCache = aSmoothLootHelperCharDB and aSmoothLootHelperCharDB.bankCache
    if bankCache and bankCache[itemID] then return true end
    return false
end

------------------------------------------------------------------------
function provider:IsNormalVersionOfBiS(itemID)
    return self:IsBiS(itemID)
end

------------------------------------------------------------------------
-- Registration — wait for AtlasLootClassic to load, then register.
-- IsBiS calls GetFavourites() at roll-time, so even if the Favourites
-- sub-module initialises a moment after ADDON_LOADED, it will be picked
-- up correctly.
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon == "AtlasLootClassic" then
        if AtlasLootClassicDB then
            SLH.RollManager:RegisterBiSProvider("AtlasLoot", provider)
            Debug("[AtlasLoot] provider registered")
        end
        frame:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Immediate registration if AtlasLootClassic already loaded before us
if AtlasLootClassicDB then
    SLH.RollManager:RegisterBiSProvider("AtlasLoot", provider)
end
