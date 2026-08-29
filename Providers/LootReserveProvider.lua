local _, SLH = ...
SLH.LootReserve = {}

local LootReserveProvider = SLH.LootReserve

------------------------------------------------------------------------
-- LootReserve personal-reserve integration
--
-- LootReserve.Client.ItemReserves is synchronized to every raid member:
--   [itemID] = { "Player-Realm", ... }
-- GetReservesData returns the current player's reserve count as its
-- second result, using LootReserve's own canonical player name.
------------------------------------------------------------------------
function LootReserveProvider:IsPlayerReserve(itemID)
    if not itemID
       or not LootReserve
       or not LootReserve.Client
       or not LootReserve.Client.GetItemReservers
       or not LootReserve.Me
       or not LootReserve.GetReservesData then
        return false
    end

    local players = LootReserve.Client:GetItemReservers(itemID)
    if not players or #players == 0 then return false end

    local _, reserveCount = LootReserve:GetReservesData(players, LootReserve:Me())
    return reserveCount and reserveCount > 0
end
