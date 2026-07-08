local _, SLH = ...
SLH.History = {}

local History = SLH.History

------------------------------------------------------------------------
-- Check if the player has previously greeded on this itemID.
------------------------------------------------------------------------
function History:HasGreeded(itemID)
    if not itemID then return false end
    local db = aSmoothLootHelperDB and aSmoothLootHelperDB.greedHistory
    return db and db[itemID] ~= nil
end

------------------------------------------------------------------------
-- Record a greed roll for the given itemID.
------------------------------------------------------------------------
function History:RecordGreed(itemID)
    if not itemID then return end
    local db = aSmoothLootHelperDB
    if not db then return end
    if not db.greedHistory then
        db.greedHistory = {}
    end

    local entry = db.greedHistory[itemID]
    if entry then
        entry.count    = entry.count + 1
        entry.lastSeen = time()
    else
        db.greedHistory[itemID] = { count = 1, lastSeen = time() }
    end
end

------------------------------------------------------------------------
-- Return the full greedHistory table (or empty table).
------------------------------------------------------------------------
function History:GetAll()
    local db = aSmoothLootHelperDB
    return (db and db.greedHistory) or {}
end

------------------------------------------------------------------------
-- Return the number of tracked items.
------------------------------------------------------------------------
function History:GetCount()
    local n = 0
    for _ in pairs(self:GetAll()) do
        n = n + 1
    end
    return n
end

------------------------------------------------------------------------
-- Wipe the entire greed history.
------------------------------------------------------------------------
function History:Reset()
    if aSmoothLootHelperDB then
        aSmoothLootHelperDB.greedHistory = {}
    end
end
