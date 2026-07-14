local _, SLH = ...
SLH.History = {}

local History = SLH.History

------------------------------------------------------------------------
-- History is stored per-character in aSmoothLootHelperCharDB.greedHistory.
------------------------------------------------------------------------

local function GetDB()
    local cdb = aSmoothLootHelperCharDB
    if not cdb then return nil end
    if not cdb.greedHistory then
        cdb.greedHistory = {}
    end
    return cdb.greedHistory
end

------------------------------------------------------------------------
-- Check if the player has previously greeded on this itemID.
------------------------------------------------------------------------
function History:HasGreeded(itemID)
    if not itemID then return false end
    local db = GetDB()
    return db and db[itemID] ~= nil
end

------------------------------------------------------------------------
-- Record a greed roll for the given itemID.
------------------------------------------------------------------------
function History:RecordGreed(itemID)
    if not itemID then return end
    local db = GetDB()
    if not db then return end

    local entry = db[itemID]
    if entry then
        entry.count    = entry.count + 1
        entry.lastSeen = time()
    else
        db[itemID] = { count = 1, lastSeen = time() }
    end
end

------------------------------------------------------------------------
-- Return the full greedHistory table (or empty table).
------------------------------------------------------------------------
function History:GetAll()
    return GetDB() or {}
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
-- Wipe the entire greed history for this character.
------------------------------------------------------------------------
function History:Reset()
    if aSmoothLootHelperCharDB then
        aSmoothLootHelperCharDB.greedHistory = {}
    end
end

------------------------------------------------------------------------
-- One-time migration: move account-wide history into this character's
-- DB so every alt starts fresh. Only runs once per character.
------------------------------------------------------------------------
function History:MigrateFromAccount()
    local cdb = aSmoothLootHelperCharDB
    local adb = aSmoothLootHelperDB
    if not cdb or not adb then return end
    if cdb._migratedHistory then return end

    if adb.greedHistory and next(adb.greedHistory) then
        -- Copy account history into this character's history
        if not cdb.greedHistory then cdb.greedHistory = {} end
        for itemID, entry in pairs(adb.greedHistory) do
            if not cdb.greedHistory[itemID] then
                cdb.greedHistory[itemID] = { count = entry.count, lastSeen = entry.lastSeen }
            end
        end
    end
    cdb._migratedHistory = true
end
