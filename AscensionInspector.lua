-- ============================================================================
-- BuildSpy v5.0 (2026-08-09) -- formerly "AscensionInspector"; renamed for the
-- public release (user quiz 09/08). Internal names (slash /ains, SavedVariables
-- AscensionInspectorDB, _G.AscensionInspector_* bridges) are UNCHANGED so no
-- existing data or integration breaks. v5.0 additions:
--   * everything user-facing and every comment now in ENGLISH;
--   * "Ignore" column in the build table: per-entry checkbox (off by default,
--     stored in rec.ignored[slot][entryId]) -- an ignored entry is INVISIBLE
--     to both exports: not desired NOR undesired for Rapid Roll, and its card
--     is never planned by Skill Cards;
--   * draggable minimap button (shown by default only when the sad0-QoL suite
--     is absent) + "minimap button" toggle in the builds window;
--   * title bar no longer overlaps the top-right buttons (left-anchored,
--     width-capped).
-- ============================================================================
-- v3.0 (2026-08-06) -- FULL BUILDS + browse window (user quiz 06/08):
--   * the probe now captures ALL CA entries (abilities AND talents -- the
--     v2.x IsTalentID filter kept only talents; the inspect Build tab shows
--     both). caSpecs[slot] = { {id, rank, name}... }.
--   * "/ains builds" window (+ sad0 QoL hub button): grabbed builds listed on
--     the left (one line per CHARACTER+SPEC, X = delete, click = browse),
--     SORTABLE TABLE on the right: Level | icon (spell tooltip) | Name |
--     Talent/Spell | Category -- click a header to sort (asc/desc).
--   * category DEDUCED by scanning the spell tooltip (cached per spellID):
--     passive > pet > aura/totem > heal > melee attack > ranged attack >
--     spell (has a range) > buff (the rest). Rich CA entry data:
--     Type ("Ability"/"Talent"), Icon, RequiredLevel, Spells={spellID}.
-- ============================================================================
-- v2.0 (2026-07-25) -- on-demand INSPECTION grabber. A "Grab" button on the
-- inspection window (+ /ains on the target) captures EVERYTHING the client is
-- willing to give, into AscensionInspectorDB (SavedVariables -> readable out
-- of game after /reload):
--   * identity: name, level, class (both UnitClass returns -- CoA custom
--     classes), race, guild, HP/resource; buffs (name + spellID).
--   * CoA talents of ALL spec slots (1..20 -- most empty, one nil sample
--     skips the slot for free): caSpecs[slot] = full build.
--   * gear: links of the 19 slots, filed PER ACTIVE SPEC at capture time
--     (gearBySpec[activeSpecSlot]) -- re-grabbing the person in ANOTHER spec
--     adds their gear under that slot WITHOUT overwriting the others.
-- API discoveries (07/25, memorized):
--   * UnitTalentRankByID(unitToken, entryId, specSlot) -- 3 args, slot 1..20;
--     nil = no data for that slot (not inspected / empty slot), != 0.
--   * OTHER people's data only exists after CA.InspectUnit(unit) succeeds
--     (async) -> passes at 0 s / 1.5 s / +3 s catch-up.
--   * GetAllEntries() ~6000 entries = the list to probe (GetTalentsByClass
--     refuses everything, even the right CA class id).
--   * GetInspectInfo(unit) -> (activeSpecIndex, {slots}).
-- /ains          : capture the target (same as the button).
-- /ains cal      : API signature diagnostics (probes on self + target).
-- /ains api      : dump C_CharacterAdvancement/SpecializationUtil/*nspect* keys.
-- /ains list     : captures in the database.   /ains clear : purge.
-- NO automatic capture on inspection (user choice v2.0): button or /ains.
-- ============================================================================

local function Msg(t)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBuildSpy|r: " .. tostring(t))
end

local MAX_SPEC_SLOTS = 20   -- v2.0: 20 spec slots per character (most empty)

-- v6.1 (user): the builds window refreshes LIVE when a grab lands (no more
-- close/reopen) -- assigned once the window exists, called by every capture
-- completion point
local BuildsChanged   -- forward

local function DB()
    AscensionInspectorDB = AscensionInspectorDB or {}
    AscensionInspectorDB.targets = AscensionInspectorDB.targets or {}
    return AscensionInspectorDB
end

-- unit being inspected: the inspect frame's if present, otherwise the target
local function InspectUnit()
    for _, fr in ipairs({ _G.AscensionInspectFrame, _G.InspectFrame }) do
        local u = fr and fr.unit
        if u and UnitExists(u) then return u end
    end
    if UnitExists("target") and UnitIsPlayer("target") then return "target" end
    return nil
end

local function CopyPlain(v, depth)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" or depth <= 0 then return nil end
    local out, n = {}, 0
    for k, val in pairs(v) do
        if type(k) == "string" or type(k) == "number" then
            local cv = CopyPlain(val, depth - 1)
            if cv ~= nil then
                out[k] = cv
                n = n + 1
                if n >= 500 then break end
            end
        end
    end
    if next(out) == nil then return nil end
    return out
end

local function CaptureBuffs(unit)
    local out = {}
    for i = 1, 40 do
        -- 3.3.5: name, rank, icon, count, debuffType, duration, expirationTime,
        -- unitCaster, isStealable, shouldConsolidate, spellId
        local name, rank, _, count, _, _, _, _, _, _, spellId = UnitBuff(unit, i)
        if not name then break end
        out[#out + 1] = { n = name, r = rank ~= "" and rank or nil, c = count and count > 1 and count or nil, id = spellId }
    end
    return out
end

local function UnitSpecIndex(CA, unit)
    -- v3.1: for SELF the direct APIs win (GetInspectInfo("player") is not
    -- guaranteed)
    if CA and UnitIsUnit(unit, "player") then
        for _, fname in ipairs({ "GetActiveChrSpec", "GetActiveSpecID" }) do
            local fn = CA[fname]
            if fn then
                local ok, v = pcall(fn)
                if ok and type(v) == "number" and v >= 1 and v <= 20 then return v end
            end
        end
    end
    if CA and CA.GetInspectInfo then
        local ok, active = pcall(CA.GetInspectInfo, unit)
        if ok and type(active) == "number" and active >= 1 then return active end
    end
    return 1
end

-- IDs to probe: GetAllEntries WITHOUT filter (v3.0 -- the Build tab shows
-- abilities AND talents; the v2.x IsTalentID filter lost the spells).
-- (GetTalentsByClass refuses every argument, even "Monk"=21 -- 07/25 probe)
local talentIDsCache
local function AllTalentIDs(CA)
    if talentIDsCache then return talentIDsCache end
    if not CA.GetAllEntries then return nil, "GetAllEntries missing" end
    local ok, r = pcall(CA.GetAllEntries)
    if not (ok and type(r) == "table") then return nil, "GetAllEntries empty" end
    local db = DB()
    local ids, n = {}, 0
    for k, v in pairs(r) do
        local id
        if type(v) == "number" then id = v
        elseif type(v) == "table" then
            if not db.caEntrySample then db.caEntrySample = CopyPlain(v, 3) end
            id = v.ID or v.Id or v.id or v.entryID or v.EntryID or v.internalID or (type(k) == "number" and k or nil)
        elseif type(k) == "number" then id = k end
        if type(id) == "number" then
            n = n + 1
            ids[n] = id
            if n >= 9000 then break end
        end
    end
    if n == 0 then return nil, "no usable entry" end
    talentIDsCache = ids
    return ids
end

local function EntryName(CA, id)
    if not CA.GetEntryByInternalID then return nil end
    local ok, e = pcall(CA.GetEntryByInternalID, id)
    if ok and type(e) == "table" then
        return e.name or e.Name or e.spellName or e.SpellName
    end
    return nil
end

-- ============== v3.1: DIRECT CAPTURE (the probing went silent) ==============
-- 08/06: on Darkmoon/Hero, UnitTalentRankByID returns NIL everywhere, EVEN
-- for "player" (/ains self) -- while it worked on the CoA realm on 07/25.
-- The /ains api dump shows direct APIs: GetKnownSpellEntries /
-- GetKnownTalentEntries / GetKnownSpells (self), GetInspectedBuild (others).
-- They are tried FIRST (defensively probed forms, first raw SAMPLE stored in
-- db.buildProbeSample to recalibrate if needed); the old async scan stays as
-- a FALLBACK if everything fails.
local function NormalizeEntryList(r, depth)
    -- accepts: list of IDs, list of tables {ID/Id/id, Rank/rank...}, map
    -- id->rank; v3.2.1: if NOTHING at level 1, DESCEND one level into the
    -- sub-tables (suspected shape { Abilities = {...}, Talents = {...} } --
    -- GetInspectedBuild(unit, spec) returns a table that normalizes to 0)
    local out = {}
    if type(r) ~= "table" then return out end
    for k, v in pairs(r) do
        if type(v) == "table" then
            local id = v.ID or v.Id or v.id or v.entryID or v.EntryID or v.internalID
            local rank = v.Rank or v.rank or v.CurrentRank or v.currentRank or 1
            if type(id) == "number" then
                out[#out + 1] = { id = id, rank = tonumber(rank) or 1 }
            end
        elseif type(v) == "number" then
            if v > 100 then
                out[#out + 1] = { id = v, rank = 1 }
            elseif type(k) == "number" and k > 100 then
                out[#out + 1] = { id = k, rank = v }   -- map id -> rank
            end
        end
    end
    if #out == 0 and (depth or 0) < 2 then
        for _, v in pairs(r) do
            if type(v) == "table" then
                local sub = NormalizeEntryList(v, (depth or 0) + 1)
                for _, h in ipairs(sub) do out[#out + 1] = h end
            end
        end
    end
    return out
end

local function HarvestList(fn, ...)
    if not fn then return nil, nil end
    local ok, r = pcall(fn, ...)
    if not (ok and type(r) == "table") then return nil, nil end
    local n = NormalizeEntryList(r)
    if #n == 0 then return nil, r end
    return n, r
end

local function TryDirectBuild(unit, rec)
    local CA = _G.C_CharacterAdvancement
    if not CA then return 0 end
    local db = DB()
    local hits, src = {}, nil
    -- v3.1.1: samples PER API (the single sample kept being stolen by the
    -- self capture -- GetInspectedBuild's were never recorded)
    local function sample(tag, raw)
        if not raw then return end
        db.buildProbeSamples = db.buildProbeSamples or {}
        if not db.buildProbeSamples[tag] then
            db.buildProbeSamples[tag] = CopyPlain(raw, 4)
        end
    end
    if UnitIsUnit(unit, "player") then
        local s, rs = HarvestList(CA.GetKnownSpellEntries)
        sample("GetKnownSpellEntries", rs)
        local t, rt = HarvestList(CA.GetKnownTalentEntries)
        sample("GetKnownTalentEntries", rt)
        if s then for _, h in ipairs(s) do hits[#hits + 1] = h end end
        if t then for _, h in ipairs(t) do hits[#hits + 1] = h end end
        if #hits > 0 then src = "GetKnown*Entries" end
        -- fallback: known spellIDs -> entries via GetEntryBySpellID
        if #hits == 0 and CA.GetKnownSpells and CA.GetEntryBySpellID then
            local ok, r = pcall(CA.GetKnownSpells)
            if ok and type(r) == "table" then
                sample("GetKnownSpells", r)
                for _, sid in pairs(r) do
                    if type(sid) == "number" then
                        local ok2, e = pcall(CA.GetEntryBySpellID, sid)
                        local id = ok2 and type(e) == "table" and (e.ID or e.Id or e.id) or nil
                        if id then hits[#hits + 1] = { id = id, rank = 1 } end
                    end
                end
                if #hits > 0 then src = "GetKnownSpells" end
            end
        end
    else
        -- v3.1.1: widened forms (name, GUID) + DIAGNOSTIC of each form's
        -- return stored in the record (rec.inspectedBuildDiag)
        local active = UnitSpecIndex(CA, unit)
        local uname = UnitName(unit)
        local guid = UnitGUID and UnitGUID(unit) or nil
        local forms = {
            { d = "()", a = {} }, { d = "(unit)", a = { unit } },
            { d = "(" .. active .. ")", a = { active } }, { d = "(unit," .. active .. ")", a = { unit, active } },
            { d = "(1)", a = { 1 } }, { d = "(unit,1)", a = { unit, 1 } },
        }
        if uname then forms[#forms + 1] = { d = "(name)", a = { uname } } end
        if guid then forms[#forms + 1] = { d = "(guid)", a = { guid } } end
        local diag = {}
        for _, f in ipairs(forms) do
            if not CA.GetInspectedBuild then
                diag[#diag + 1] = "API missing"
                break
            end
            local ok, r = pcall(CA.GetInspectedBuild, unpack(f.a))
            local ty = (not ok) and "ERR" or type(r)
            if ok and type(r) == "table" then
                sample("GetInspectedBuild" .. f.d, r)
                local n = NormalizeEntryList(r)
                ty = "table#" .. #n
                if #n > 0 then
                    hits = n
                    src = "GetInspectedBuild" .. f.d
                end
            end
            diag[#diag + 1] = f.d .. "=" .. ty
            if src then break end
        end
        rec.inspectedBuildDiag = table.concat(diag, "  ")
    end
    if #hits > 0 then
        local CAref = CA
        for _, h in ipairs(hits) do h.name = h.name or EntryName(CAref, h.id) end
        local slot = UnitSpecIndex(CA, unit)
        rec.caSpecs = rec.caSpecs or {}
        rec.caSpecs[slot] = hits
        rec.caProbeNote = "direct " .. src .. " slot" .. slot .. "=" .. #hits
        -- v3.4: a mastery ("Path of ...") among the hits = the Path
        if CA.IsMastery then
            for _, h in ipairs(hits) do
                local okm, m = pcall(CA.IsMastery, h.id)
                if okm and m and h.name then
                    rec.pathBySpec = rec.pathBySpec or {}
                    rec.pathBySpec[slot] = h.name
                    break
                end
            end
        end
        Msg((UnitName(unit) or "?") .. ": |cff40ff40" .. #hits .. " entries via " .. src
            .. " (spec " .. slot .. ")|r.  |cffaaaaaa/ains builds to browse, /reload to write.|r")
        if BuildsChanged then BuildsChanged() end
    end
    return #hits
end

-- v2.1: FULL ASYNC SCAN of slots 1..MAX_SPEC_SLOTS. The v2.0 sampling was
-- WRONG: a talent NOT TAKEN answers nil even in a valid slot (07/25 cal:
-- "player",34372,1 -> nil while Oathkeeper slot 1 has 40+ talents), so a
-- sample can miss a whole slot. Probe EVERYTHING (20 x ~6000 = 120k calls)
-- spread at 4000 probes/frame (~0.5 s total, zero freeze); a zero-result
-- pass is RETRIED once 3 s later (inspection data arrives late from the
-- server).
local scan = CreateFrame("Frame")
scan:Hide()
local SCAN_PER_FRAME = 4000
scan:SetScript("OnUpdate", function(self, elapsed)
    if self.waitRestart then
        self.waitRestart = self.waitRestart - elapsed
        if self.waitRestart <= 0 then
            self.waitRestart = nil
            self.slot, self.i, self.hits = 1, 0, {}
        end
        return
    end
    local CA = _G.C_CharacterAdvancement
    local ids, rec, unit = self.ids, self.rec, self.unit
    if not (CA and ids and rec and unit and UnitExists(unit)) then self:Hide() return end
    local budget = SCAN_PER_FRAME
    while budget > 0 do
        self.i = self.i + 1
        if self.i > #ids then
            if #self.hits > 0 then
                rec.caSpecs = rec.caSpecs or {}
                rec.caSpecs[self.slot] = self.hits   -- overwriting the SAME slot = ok (fresher)
                self.counts[#self.counts + 1] = "slot" .. self.slot .. "=" .. #self.hits
            end
            self.slot = self.slot + 1
            self.i = 0
            self.hits = {}
            if self.slot > MAX_SPEC_SLOTS then
                local total = #self.counts
                rec.caProbeNote = total > 0 and table.concat(self.counts, " ") or "no CA data"
                -- v3.0.1: TWO catch-ups (3 s then 5 s) -- other people's CA
                -- data sometimes arrives very late from the server
                self.retries = (self.retries or 0) + 1
                if total == 0 and self.retries <= 2 then
                    if CA.InspectUnit then pcall(CA.InspectUnit, unit) end
                    if _G.CanInspect and CanInspect(unit) then pcall(NotifyInspect, unit) end
                    self.counts = {}
                    self.waitRestart = self.retries == 1 and 3 or 5
                    Msg(tostring(self.name) .. ": no CA data -- catch-up " .. self.retries .. "/2 in " .. self.waitRestart .. " s (keep the player in range)...")
                    return
                end
                self:Hide()
                Msg(tostring(self.name) .. ": "
                    .. (total > 0 and ("|cff40ff40builds -> " .. rec.caProbeNote .. "|r") or "|cffff8800no CoA build -- open the inspection's BUILD tab (let the list load), then Grab again. Pipeline check: /ains self|r")
                    .. ".  |cffaaaaaa/reload to write the file.|r")
                if total > 0 and BuildsChanged then BuildsChanged() end
                return
            end
        else
            local ok, r = pcall(CA.UnitTalentRankByID, unit, ids[self.i], self.slot)
            local rv = ok and tonumber(r) or nil
            if rv and rv > 0 then
                self.hits[#self.hits + 1] = { id = ids[self.i], rank = rv, name = EntryName(CA, ids[self.i]) }
            end
            budget = budget - 1
        end
    end
end)

local function StartSpecScan(unit, rec, name)
    local CA = _G.C_CharacterAdvancement
    if not (CA and CA.UnitTalentRankByID) then return end
    local ids, why = AllTalentIDs(CA)
    if not ids then
        rec.caProbeNote = "talent list not found: " .. tostring(why)
        return
    end
    scan.ids, scan.rec, scan.unit, scan.name = ids, rec, unit, name
    scan.slot, scan.i, scan.hits, scan.counts = 1, 0, {}, {}
    scan.retries, scan.waitRestart = nil, nil
    scan:Show()
end

-- v3.1.1: REPEATED direct tries for others (inspection data arrives late
-- from the server) -- 3 attempts 3 s apart, with an InspectUnit/NotifyInspect
-- re-ping between each, then fallback to the probing scan.
local directRetry = CreateFrame("Frame")
directRetry:Hide()
directRetry:SetScript("OnUpdate", function(self, e)
    self.left = (self.left or 0) - e
    if self.left > 0 then return end
    self:Hide()
    local unit, rec, name = self.unit, self.rec, self.name
    if not (unit and UnitExists(unit) and rec) then
        Msg("target lost -- Grab again later.")
        return
    end
    if TryDirectBuild(unit, rec) > 0 then return end
    self.tries = (self.tries or 0) + 1
    if self.tries < 3 then
        local CA = _G.C_CharacterAdvancement
        if CA and CA.InspectUnit then pcall(CA.InspectUnit, unit) end
        if _G.CanInspect and CanInspect(unit) then pcall(NotifyInspect, unit) end
        Msg("build not received yet -- direct try " .. (self.tries + 1) .. "/3 in 3 s (stay in range)...")
        self.left = 3
        self:Show()
        return
    end
    Msg("direct APIs silent (diag: " .. tostring(rec.inspectedBuildDiag) .. ") -- falling back to the probing scan...")
    StartSpecScan(unit, rec, name)
end)

local function CaptureCA(unit, rec, pass)
    local CA = _G.C_CharacterAdvancement
    if not CA then return end
    if pass == "event" and CA.InspectUnit then pcall(CA.InspectUnit, unit) end
    if CA.GetInspectInfo then
        local ok, a, b = pcall(CA.GetInspectInfo, unit)
        if ok and a ~= nil then
            rec.caInspectInfo = { a, CopyPlain(b, 3) }
        end
    end
    -- v2.1: build probing runs ASYNC, started from the final pass
end

-- v3.3: order of the PRIMARY stats played, derived from the captured GEAR
-- (UnitStat does not answer for others on 3.3.5 -- the item sum gives the
-- ORDER, amounts deliberately omitted, user request 08/06).
-- v5.0: English labels (older captures keep the French order strings in SV).
local STAT_KEYS = {
    { k = "ITEM_MOD_STRENGTH_SHORT",  label = "str" },
    { k = "ITEM_MOD_AGILITY_SHORT",   label = "agi" },
    { k = "ITEM_MOD_INTELLECT_SHORT", label = "int" },
    { k = "ITEM_MOD_SPIRIT_SHORT",    label = "spi" },
    { k = "ITEM_MOD_STAMINA_SHORT",   label = "sta" },
}
local function GearStatOrder(items)
    if not items then return nil end
    local sums, any = {}, false
    for _, link in pairs(items) do
        local st = GetItemStats and GetItemStats(link)
        if st then
            any = true
            for _, s in ipairs(STAT_KEYS) do
                sums[s.label] = (sums[s.label] or 0) + (st[s.k] or 0)
            end
        end
    end
    if not any then return nil end
    local list = {}
    for _, s in ipairs(STAT_KEYS) do
        if (sums[s.label] or 0) > 0 then
            list[#list + 1] = { l = s.label, v = sums[s.label] }
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.v > b.v end)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.l end
    return table.concat(out, " > ")
end

-- v3.4: WEAPON TYPES played, read from the captured gear (slots 16/17/18 ->
-- item subtype, "2H" marker on two-handers)
local function GearWeaponTypes(items)
    local parts = {}
    for _, slot in ipairs({ 16, 17, 18 }) do
        local link = items and items[slot]
        if link then
            local _, _, _, _, _, _, subType, _, equipLoc = GetItemInfo(link)
            if subType then
                parts[#parts + 1] = subType .. (equipLoc == "INVTYPE_2HWEAPON" and " (2H)" or "")
            end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " + ")
end

-- v3.4: PATH (CA mastery -- "Path of Intelligence"...): masteries are CA
-- entries flagged IsMastery, ABSENT from GetKnown*Entries. For SELF:
-- IsSpellKnown on the entry's spell (reliable), GetTalentRankByID fallback.
-- For OTHERS: UnitTalentRankByID probe (dead on Darkmoon, but free) -- the
-- real path comes from the GetInspectedBuild hits (filtered by IsMastery).
local masteryIDs
local function MasteryIDs(CA)
    if masteryIDs then return masteryIDs end
    if not (CA and CA.IsMastery) then return nil end
    local ids = AllTalentIDs(CA)
    if not ids then return nil end
    masteryIDs = {}
    for _, id in ipairs(ids) do
        local ok, m = pcall(CA.IsMastery, id)
        if ok and m then masteryIDs[#masteryIDs + 1] = id end
    end
    return masteryIDs
end

local function DetectPath(unit, rec, slot)
    local CA = _G.C_CharacterAdvancement
    local ids = MasteryIDs(CA)
    if not ids then return nil end
    for _, id in ipairs(ids) do
        local e
        local ok, r = pcall(CA.GetEntryByInternalID, id)
        if ok and type(r) == "table" then e = r end
        local sid = e and type(e.Spells) == "table" and e.Spells[1] or nil
        local known
        if UnitIsUnit(unit, "player") then
            known = sid and IsSpellKnown and IsSpellKnown(sid) or nil
            if not known and CA.GetTalentRankByID then
                local ok2, rv = pcall(CA.GetTalentRankByID, id)
                known = ok2 and tonumber(rv) and tonumber(rv) > 0
            end
        elseif CA.UnitTalentRankByID then
            local ok2, rv = pcall(CA.UnitTalentRankByID, unit, id, slot)
            known = ok2 and tonumber(rv) and tonumber(rv) > 0
        end
        if known and e and e.Name then
            rec.pathBySpec = rec.pathBySpec or {}
            rec.pathBySpec[slot] = e.Name
            return e.Name
        end
    end
    return nil
end

-- v6.0 (user: "my own grab has no Path"): masteries are ABSENT from
-- GetKnown*Entries -- self-grabs re-detect the chosen Path and APPEND it as
-- a build hit, like inspected builds get theirs from GetInspectedBuild.
-- v6.0.2: the five Paths HARDCODED from the wheel tooltips (user, 09/08) --
-- no more reliance on IsMastery/MasteryIDs (mute on this client). Three
-- detection strategies in order: spellbook passive by name, then
-- GetTalentRankByID on the 5 CA ids, then IsSpellKnown on the 5 spell ids.
local PATH_ENTRIES = {
    { ca = 1149,  sp = 84864,  name = "Path of Strength" },
    { ca = 1150,  sp = 84865,  name = "Path of Agility" },
    { ca = 1151,  sp = 84866,  name = "Path of Intelligence" },
    { ca = 1152,  sp = 84867,  name = "Path of Healing" },
    { ca = 18149, sp = 129243, name = "Path of Duality" },
}
local function AppendSelfPath(rec, slot)
    local CA = _G.C_CharacterAdvancement
    local hits = rec.caSpecs and rec.caSpecs[slot]
    if not (CA and hits) then return end
    for _, h in ipairs(hits) do
        for _, p in ipairs(PATH_ENTRIES) do
            if h.id == p.ca then return end   -- already carries its Path
        end
    end
    local chosen
    -- 1) spellbook: the Path shows as a passive named "Path of ..."
    local bookName
    for i = 1, 1024 do
        local nm = GetSpellName and GetSpellName(i, BOOKTYPE_SPELL or "spell")
        if not nm then break end
        if string.find(nm, "^Path of ") then
            bookName = nm
            break
        end
    end
    if bookName then
        for _, p in ipairs(PATH_ENTRIES) do
            if p.name == bookName then chosen = p break end
        end
    end
    -- 2) CA rank on the five known entries
    if not chosen and CA.GetTalentRankByID then
        for _, p in ipairs(PATH_ENTRIES) do
            local ok, r = pcall(CA.GetTalentRankByID, p.ca)
            if ok and tonumber(r) and tonumber(r) > 0 then chosen = p break end
        end
    end
    -- 3) IsSpellKnown on the five known spell ids
    if not chosen and IsSpellKnown then
        for _, p in ipairs(PATH_ENTRIES) do
            local ok, k = pcall(IsSpellKnown, p.sp)
            if ok and k then chosen = p break end
        end
    end
    if chosen then
        hits[#hits + 1] = { id = chosen.ca, rank = 1, name = chosen.name }
        rec.pathBySpec = rec.pathBySpec or {}
        rec.pathBySpec[slot] = chosen.name
        Msg("Path detected: |cff33ff99" .. chosen.name .. "|r")
        if BuildsChanged then BuildsChanged() end
    else
        Msg("|cffff8800Path not detected (spellbook + CA + IsSpellKnown all silent).|r")
    end
end

-- capture pass: merges into the existing record. GEAR is filed under the
-- target's ACTIVE SPEC (gearBySpec[slot]) -- other slots are never touched.
local function Capture(unit, pass)
    if not (unit and UnitExists(unit) and UnitIsPlayer(unit)) then return nil end
    local name = UnitName(unit)
    if not name or name == UNKNOWN then return nil end
    local db = DB()
    local rec = db.targets[name] or {}
    db.targets[name] = rec
    rec.at = date("%Y-%m-%d %H:%M")
    rec.level = UnitLevel(unit)
    rec.class = { UnitClass(unit) }         -- {display, token}: CoA custom classes
    rec.race = { UnitRace(unit) }
    rec.guild = GetGuildInfo(unit) or rec.guild
    rec.hpMax = UnitHealthMax(unit)
    local ptype, ptoken = UnitPowerType(unit)
    rec.power = { type = ptoken or ptype, max = UnitManaMax(unit) }
    rec.buffs = CaptureBuffs(unit)
    CaptureCA(unit, rec, pass)
    -- gear PER ACTIVE SPEC (read after CaptureCA: fresh GetInspectInfo)
    local active = UnitSpecIndex(_G.C_CharacterAdvancement, unit)
    rec.activeSpec = active
    rec.gearBySpec = rec.gearBySpec or {}
    local slotGear = rec.gearBySpec[active] or {}
    rec.gearBySpec[active] = slotGear
    slotGear.at = rec.at
    slotGear.items = slotGear.items or {}
    local gn = 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink(unit, slot)
        if link then slotGear.items[slot] = link end   -- merge: never a hole over a link
    end
    for _ in pairs(slotGear.items) do gn = gn + 1 end
    -- v3.3: primary stat order of this spec's gear (nil if not cached)
    slotGear.statOrder = GearStatOrder(slotGear.items) or slotGear.statOrder
    -- v3.4: weapon types + Path (mastery) of the active spec
    slotGear.weapons = GearWeaponTypes(slotGear.items) or slotGear.weapons
    DetectPath(unit, rec, active)
    if pass == "final" then
        Msg(name .. " [active spec " .. active .. "]: " .. gn .. " items, " .. #rec.buffs
            .. " buffs -- capturing the build...")
        -- v3.1: direct APIs first; v3.1.1: others = 3 tries 3 s apart
        -- (inspection data arrives late) before the probing fallback
        local direct = TryDirectBuild(unit, rec)
        if direct > 0 and UnitIsUnit(unit, "player") then
            AppendSelfPath(rec, active)   -- v6.0: self path re-detected
        end
        if direct == 0 then
            if UnitIsUnit(unit, "player") then
                Msg("direct APIs silent -- falling back to the probing scan...")
                StartSpecScan(unit, rec, name)
            else
                local CA2 = _G.C_CharacterAdvancement
                if CA2 and CA2.InspectUnit then pcall(CA2.InspectUnit, unit) end
                directRetry.unit, directRetry.rec, directRetry.name = unit, rec, name
                directRetry.tries, directRetry.left = 0, 3
                directRetry:Show()
                Msg("build not received yet -- direct tries running (3 x 3 s, stay in range)...")
            end
        end
    end
    return rec
end

-- deferred pass: identity/gear at 1.5 s (item links arrive late), then the
-- async build scan takes over (with its own +3 s retry)
local delay = CreateFrame("Frame")
delay:Hide()
delay:SetScript("OnUpdate", function(self, e)
    self.left = (self.left or 0) - e
    if self.left <= 0 then
        self:Hide()
        Capture(self.unit, "final")
        self.unit = nil
    end
end)
local function StartCapture(unit)
    -- v3.0.1: systematic NotifyInspect (button included) -- it is what
    -- triggers the server to send the inspection data
    if unit ~= "player" and _G.CanInspect and CanInspect(unit) then pcall(NotifyInspect, unit) end
    Capture(unit, "event")
    delay.unit = unit
    delay.left = 1.5
    delay:Show()
    Msg("grabbing...")
end

-- ========================== "Grab" BUTTON (v2.0) ==========================
-- Placed on the Ascension (or classic) inspection window as soon as it exists.
local grabBtn
local function EnsureButton()
    if grabBtn then return end
    local parent = _G.AscensionInspectFrame or _G.InspectFrame
    if not parent then return end
    grabBtn = CreateFrame("Button", "AscensionInspectorGrab", parent, "UIPanelButtonTemplate")
    grabBtn:SetWidth(80)
    grabBtn:SetHeight(21)
    grabBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -28)
    grabBtn:SetText("Grab")
    grabBtn:SetScript("OnClick", function()
        local u = InspectUnit()
        if u then StartCapture(u) else Msg("no inspected unit.") end
    end)
    grabBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Grab this player: gear (tagged by their ACTIVE spec), builds of all their specs, buffs, identity -- into the SavedVariables.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grabBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- v5.2 (user): Grab button on MY OWN character sheet (= /ains self)
local selfBtn
local function EnsureSelfButton()
    if selfBtn then return end
    local parent = _G.PaperDollFrame or _G.CharacterFrame
    if not parent then return end
    selfBtn = CreateFrame("Button", "BuildSpyGrabSelf", parent, "UIPanelButtonTemplate")
    selfBtn:SetWidth(60) selfBtn:SetHeight(18)
    selfBtn:SetPoint("TOPRIGHT", _G.CharacterFrame or parent, "TOPRIGHT", -42, -40)
    selfBtn:SetText("Grab")
    selfBtn:SetScript("OnClick", function() StartCapture("player") end)
    selfBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Grab MY build (current spec) -- same as /ains self.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    selfBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("INSPECT_TALENT_READY")   -- v2.0: NO auto capture -- only
f:SetScript("OnEvent", function()          -- used to place the buttons
    EnsureButton()
    EnsureSelfButton()
end)

-- ========================== v3.0: BUILDS window ==========================
-- /ains builds: captures listed on the left (one line per character+SPEC,
-- click = browse, X = delete that build), SORTABLE table on the right.
local ENTRY_H = 19
local LIST_ROWS = 21   -- v5.3: one less (sort buttons above the list)
local TAB_ROWS = 22

local bui = CreateFrame("Frame", "AscensionInspectorBuilds", UIParent)
-- v5.3 (user): taller bottom margin (+18) -- the bottom buttons were
-- blending into the table's last row
-- v6.1 (user): wider window -- the builds list gets real aligned columns
-- v6.6 (user): +24 tall for the "selected build's" group (Name + Comment)
bui:SetWidth(880) bui:SetHeight(30 + 26 + TAB_ROWS * ENTRY_H + 58)
bui:SetPoint("CENTER", 0, 20)
bui:SetFrameStrata("HIGH")
bui:SetMovable(true) bui:EnableMouse(true)
bui:RegisterForDrag("LeftButton")
bui:SetScript("OnDragStart", function(self) self:StartMoving() end)
bui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB().buildsPos = { p, rp, x, y }
end)
bui:Hide()
local bbg = bui:CreateTexture(nil, "BACKGROUND")
bbg:SetAllPoints()
bbg:SetTexture(0.05, 0.04, 0.08, 0.95)
local bedges = {}
for i = 1, 4 do bedges[i] = bui:CreateTexture(nil, "BORDER") bedges[i]:SetTexture(0.4, 0.8, 1, 0.9) end
bedges[1]:SetPoint("TOPLEFT") bedges[1]:SetPoint("TOPRIGHT") bedges[1]:SetHeight(2)
bedges[2]:SetPoint("BOTTOMLEFT") bedges[2]:SetPoint("BOTTOMRIGHT") bedges[2]:SetHeight(2)
bedges[3]:SetPoint("TOPLEFT") bedges[3]:SetPoint("BOTTOMLEFT") bedges[3]:SetWidth(2)
bedges[4]:SetPoint("TOPRIGHT") bedges[4]:SetPoint("BOTTOMRIGHT") bedges[4]:SetWidth(2)
local bClose = CreateFrame("Button", nil, bui, "UIPanelCloseButton")
bClose:SetPoint("TOPRIGHT", 2, 2)
-- v5.0 (user: "title runs under the buttons"): LEFT-anchored and WIDTH-CAPPED
-- so the text stops before the two top-right buttons instead of under them
local bTitle = bui:CreateFontString(nil, "ARTWORK", "GameFontNormal")
bTitle:SetPoint("TOPLEFT", 12, -9)
bTitle:SetWidth(555)
bTitle:SetHeight(14)
bTitle:SetJustifyH("LEFT")
if bTitle.SetWordWrap then bTitle:SetWordWrap(false) end
bTitle:SetText("BuildSpy -- grabbed builds")

-- v5.3 (user): the deduced "Category" column is gone ("it does not make much
-- sense") -- the tooltip-scan classifier went with it

-- v3.2: RARITY of CA entries -- entry.Quality ("Epic"...) + entry.Color
-- ("TEAL"... Ascension's custom borders) as fallback; dedicated sort order
local QUAL_COLORS = {
    poor = "9d9d9d", common = "ffffff", uncommon = "1eff00", rare = "0070dd",
    epic = "a335ee", legendary = "ff8000", artifact = "e6cc80", heirloom = "e6cc80",
}
local COLOR_HEX = {
    grey = "9d9d9d", gray = "9d9d9d", white = "ffffff", green = "1eff00",
    blue = "0070dd", purple = "a335ee", orange = "ff8000", gold = "ffcc00",
    yellow = "ffff00", red = "ff4040", teal = "00ffcc",
}
local QUAL_ORDER = {
    poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4,
    legendary = 5, artifact = 6, heirloom = 6,
}
local function QualInfo(e)
    local q = e and e.Quality and tostring(e.Quality) or nil
    local key = q and string.lower(q) or nil
    local hex = (key and QUAL_COLORS[key])
        or (e and e.Color and COLOR_HEX[string.lower(tostring(e.Color))])
        or "ffffff"
    return q or "?", (key and QUAL_ORDER[key]) or -1, hex
end

-- v5.1 (user: "the rarity of grabbed talents does not reflect the CARD
-- rarity"): the Rarity column now shows the SKILL CARD quality when a card
-- exists for the entry (best quality across the 4 pools), falling back to
-- the CA entry quality. Cards are keyed by the spellID OF THEIR RANK, so the
-- match goes through the CA entry (GetEntryBySpellID), same trick as the
-- planner. Map built lazily once per session.
-- v5.2 fix ("talent rarity does not update"): the collection's Quality field
-- may come as "COMMON" or "SKILL_CARD_COMMON" depending on source -- keys are
-- normalized (prefix stripped, uppercased) before lookup
local CARD_QUAL = {
    COMMON    = { 1, "Common",    "ffffff" },
    UNCOMMON  = { 2, "Uncommon",  "1eff00" },
    RARE      = { 3, "Rare",      "0070dd" },
    EPIC      = { 4, "Epic",      "a335ee" },
    LEGENDARY = { 5, "Legendary", "ff8000" },
}
local function EntryKeyOfSpell(spellID)
    local CA = _G.C_CharacterAdvancement
    if CA and CA.GetEntryBySpellID then
        local ok, e = pcall(CA.GetEntryBySpellID, spellID)
        if ok and type(e) == "table" then
            local id = e.ID or e.Id or e.id or e.entryID or e.EntryID or e.internalID
            if id then return id end
        end
    end
    return nil
end

-- v5.5 ("works for Anger Management, must work for ALL"): full spellID ->
-- CA-entry index over EVERY entry and EVERY rank (~6000 local reads, once
-- per session). A talent card's spellID resolves to ITS RANK'S entry, whose
-- CA Name is the bridge to the build's rank-1 entry -- CA names on BOTH
-- sides, no GetSpellInfo involved (it can be mute on custom spell IDs).
local spellIndex
local function SpellIndex()
    if spellIndex then return spellIndex end
    local CA = _G.C_CharacterAdvancement
    if not (CA and CA.GetEntryByInternalID) then return nil end
    local ids = AllTalentIDs(CA)
    if not ids then return nil end
    spellIndex = {}
    for _, id in ipairs(ids) do
        local ok, e = pcall(CA.GetEntryByInternalID, id)
        if ok and type(e) == "table" and type(e.Spells) == "table" then
            for _, sid in ipairs(e.Spells) do
                if spellIndex[sid] == nil then
                    spellIndex[sid] = { id = id, name = e.Name, typ = e.Type }
                end
            end
        end
    end
    return spellIndex
end
_G.AscensionInspector_SpellIndex = SpellIndex   -- consumed by SkillCardPlanner
-- v5.6 (user: "at one point rarities were right, then back to normal" --
-- and the planner, which rebuilds its pools at every click, always sees them
-- right): the once-per-session cache could freeze a PARTIAL harvest (cards
-- enumerated early can miss their SpellID). The map now REBUILDS itself
-- (5 s TTL -- selection clicks get fresh data, repeated refreshes don't
-- hammer the collection).
local cardQualMap, cardQualAt, cardQualWarned
local function CardQualMap()
    if cardQualMap and GetTime and (GetTime() - (cardQualAt or 0)) < 5 then
        return cardQualMap
    end
    -- v5.3 ("talent rarity only half works"): TWO indexes. byEntry resolves
    -- the card's spellID to a CA entry -- but multi-rank talents' cards carry
    -- the spellID OF A RANK that does not always resolve to the build's
    -- entry (only single-rank talents matched). byName is the safety net:
    -- the base spell NAME is rank-independent (GetSpellInfo of any rank
    -- returns the same name).
    -- v5.4 ("can't you really get that with IDs?" -- yes): bySpell = RAW
    -- spellID index. Proof via tooltip: every RANK has its own CA entry ID
    -- (Anger Management max rank = CA 40364, the grabbed build stores rank
    -- 1's entry), but the build entry's Spells table lists the spellIDs of
    -- ALL its ranks -- so matching any of them against the card's spellID
    -- is a pure-ID bridge, no name needed.
    local map = { byEntry = {}, byName = {}, bySpell = {} }
    local found = 0
    local SCC = _G.C_SkillCardCollection
    if SCC and SCC.GetNumSkillCards and SCC.GetSkillCardAtIndex then
        -- v5.9: FIXED category list again -- v5.7's dynamic discovery
        -- harvested every SKILL_CARD_* global INCLUDING LOCALE SENTENCES,
        -- and v5.8 then fed that junk to SetSkillCardFilter, corrupting the
        -- filter state ("nothing works at all"). The 8 real enums, nothing
        -- else; unknown ones (LUCKY) simply answer nil and are skipped.
        for _, cat in ipairs({
            "SKILL_CARD_STARTER_NORMAL", "SKILL_CARD_STARTER_GOLDEN",
            "SKILL_CARD_DEFAULT_NORMAL", "SKILL_CARD_DEFAULT_GOLDEN",
            "SKILL_CARD_TALENT_NORMAL",  "SKILL_CARD_TALENT_GOLDEN",
            "SKILL_CARD_LUCKY_NORMAL",   "SKILL_CARD_LUCKY_GOLDEN",
        }) do
            local ok, n = pcall(SCC.GetNumSkillCards, cat)
            if ok and type(n) == "number" then
                -- v5.8 (USER'S FIND -- "unchecking Collected Only fixes
                -- it"): the collection API honors the UI's "Collected Only"
                -- filter, so uncollected cards were invisible. Captured call
                -- (cardspy 09/08): SetSkillCardFilter(cat, searchText,
                -- {string filters}); empty table = no filter = everything
                -- (proven by the user's own manual fix). Only touched for
                -- categories that ANSWER, and count re-read after clearing.
                if SCC.SetSkillCardFilter then
                    pcall(SCC.SetSkillCardFilter, cat, "", {})
                    local ok2, n2 = pcall(SCC.GetNumSkillCards, cat)
                    if ok2 and type(n2) == "number" then n = n2 end
                end
                for i = 1, n do
                    local ok2, c = pcall(SCC.GetSkillCardAtIndex, cat, i)
                    if ok2 and type(c) == "table" and c.SpellID then
                        local qkey = string.upper(tostring(c.Quality))
                        qkey = string.gsub(qkey, "^SKILL_CARD_", "")
                        local q = CARD_QUAL[qkey]
                        if q then
                            local prevS = map.bySpell[c.SpellID]
                            if (not prevS) or q[1] > prevS[1] then
                                map.bySpell[c.SpellID] = q
                                found = found + 1
                            end
                            -- v5.5: resolve the card's spellID through the
                            -- full CA index -- entry id AND CA name of the
                            -- rank the card points to
                            local si = SpellIndex()
                            local fam = si and si[c.SpellID]
                            local key = (fam and fam.id) or EntryKeyOfSpell(c.SpellID)
                            if key then
                                local prev = map.byEntry[key]
                                if (not prev) or q[1] > prev[1] then
                                    map.byEntry[key] = q
                                    found = found + 1
                                end
                            end
                            local sn = (fam and fam.name) or GetSpellInfo(c.SpellID)
                            if sn then
                                local nk = string.lower(sn)
                                local prev = map.byName[nk]
                                if (not prev) or q[1] > prev[1] then
                                    map.byName[nk] = q
                                    found = found + 1
                                end
                            end
                        end
                    end
                end
            end
            -- restore the UI's default filter state (answering cats only)
            if ok and type(n) == "number" and SCC.SetSkillCardFilter then
                pcall(SCC.SetSkillCardFilter, cat, "", { "FILTER_COLLECTED" })
            end
        end
    end
    -- v5.2 fix: NEVER cache an empty harvest (the collection can answer
    -- empty early in the session) -- retry on the next refresh instead
    if found > 0 then
        cardQualMap, cardQualAt = map, GetTime and GetTime() or 0
    elseif not cardQualWarned then
        cardQualWarned = true
        Msg("|cffff8800card collection answered empty -- open the Skill Cards window once, then reselect the build for card rarities.|r")
    end
    return map
end

-- shared lookup: entry id, then EVERY rank's spellID (v5.4, pure IDs),
-- base-name as last resort
local function CardQualOf(entryId, entryName, spells)
    local qm = CardQualMap()
    local best = qm.byEntry[entryId]
    if type(spells) == "table" then
        for _, s in ipairs(spells) do
            local q = qm.bySpell[s]
            if q and ((not best) or q[1] > best[1]) then best = q end
        end
    end
    if not best and entryName then
        best = qm.byName[string.lower(entryName)]
    end
    return best
end

-- ----- data -----
local selTarget, selSlot
local listOff, tabOff = 0, 0
-- v5.6 (user): default sort = RARITY, legendary on top
local sortCol, sortAsc = "qual", false
local tabRows = {}   -- prepared rows of the selected build

-- v5.0 (user): per-entry IGNORE set of the selected build -- stored in
-- rec.ignored[slot][entryId] = true. An ignored entry is INVISIBLE to the
-- exports: not pushed as desired NOR marked undesired (Rapid Roll), and its
-- card is never planned (Skill Cards). Off by default.
local function IgnoredSet(create)
    local rec = selTarget and DB().targets[selTarget]
    if not (rec and selSlot) then return nil end
    if create then
        rec.ignored = rec.ignored or {}
        rec.ignored[selSlot] = rec.ignored[selSlot] or {}
    end
    return rec.ignored and rec.ignored[selSlot] or nil
end

-- v6.0 (user): the "Path of ..." mastery is pulled OUT of the table -- it
-- shows in the title (replacing the stat/weapon summary), as an icon in the
-- builds list, on line 2 of exports, and the list can sort by it. Detection:
-- CA.IsMastery on the entry, name prefix "Path of " as fallback (imported
-- builds). Cached per build (list refreshes hit this on every scroll).
local pathCache = {}
local function PathInfo(target, slot)
    if not (target and slot) then return nil end
    local rec = DB().targets[target]
    local hits = rec and rec.caSpecs and rec.caSpecs[slot]
    if not hits then return nil end
    local key = target .. "|" .. slot .. "|" .. tostring(rec.at) .. "|" .. #hits
    local hit = pathCache[key]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local CA = _G.C_CharacterAdvancement
    local res = false
    for _, h in ipairs(hits) do
        local e
        if CA and CA.GetEntryByInternalID then
            local ok, r = pcall(CA.GetEntryByInternalID, h.id)
            if ok and type(r) == "table" then e = r end
        end
        local nm = (e and e.Name) or h.name
        local isPath = false
        if CA and CA.IsMastery then
            local ok2, m = pcall(CA.IsMastery, h.id)
            isPath = (ok2 and m) and true or false
        end
        if (not isPath) and nm and string.find(nm, "^Path of ") then isPath = true end
        if isPath then
            res = { name = nm or "Path", hid = h.id,
                icon = e and e.Icon and ("Interface/Icons/" .. e.Icon) or nil }
            break
        end
    end
    pathCache[key] = res
    if res == false then return nil end
    return res
end

-- hits of the selected build MINUS the ignored entries (what the exports see)
local function ActiveHits()
    local rec = selTarget and DB().targets[selTarget]
    local hits = rec and rec.caSpecs and rec.caSpecs[selSlot]
    if not hits then return nil end
    local ign = IgnoredSet(false)
    if not (ign and next(ign)) then return hits end
    local out = {}
    for _, h in ipairs(hits) do
        if not ign[h.id] then out[#out + 1] = h end
    end
    return out
end

local function BuildList()
    local db = DB()
    -- v5.3 (user): list sortable by NAME or DATE (persisted, click = flip)
    local ls = db.listSort or { col = "name", asc = true }
    local out = {}
    for name, r in pairs(db.targets) do
        for s in pairs(r.caSpecs or {}) do
            -- v3.5: build comment shown in the list
            local cm = r.comments and r.comments[s]
            -- v6.0: Path icon + sortable path name
            local pinfo = PathInfo(name, s)
            -- v6.0 (user): label = {path icon} 1H/2H - Name ; handedness
            -- read from the captured gear's weapons ("(2H)", old "(2M)")
            local g = r.gearBySpec and (r.gearBySpec[s]
                or (r.activeSpec and r.gearBySpec[r.activeSpec]))
            local w = g and g.weapons
            local hand = w and ((string.find(w, "(2H)", 1, true)
                or string.find(w, "(2M)", 1, true)) and "2H" or "1H") or nil
            -- v5.1 (user): entry count dropped from the label (always 56)
            -- v6.1: column FIELDS instead of one concatenated label; the
            -- year is stripped from the displayed date (saves the wrap)
            local at = tostring(r.at or "")
            out[#out + 1] = { target = name, slot = s, at = at,
                atShort = (string.len(at) > 5) and string.sub(at, 6) or at,
                path = (pinfo and pinfo.name) or "",
                pathIcon = pinfo and pinfo.icon or nil,
                hand = hand, cm = cm }
        end
    end
    table.sort(out, function(a, b)
        if ls.col == "date" then
            if a.at ~= b.at then
                if ls.asc then return a.at < b.at else return a.at > b.at end
            end
        elseif ls.col == "path" then
            if a.path ~= b.path then
                -- builds without a path always sink to the bottom
                if a.path == "" then return false end
                if b.path == "" then return true end
                if ls.asc then return a.path < b.path else return a.path > b.path end
            end
            -- v6.2 (user): same path -> group by 1H/2H next
            local ha, hb = a.hand or "", b.hand or ""
            if ha ~= hb then return ha < hb end
        else
            local na, nb = string.lower(a.target), string.lower(b.target)
            if na ~= nb then
                if ls.asc then return na < nb else return na > nb end
            end
        end
        if a.target ~= b.target then return string.lower(a.target) < string.lower(b.target) end
        return a.slot < b.slot
    end)
    return out
end

local function PrepareRows()
    tabRows = {}
    local CA = _G.C_CharacterAdvancement
    local rec = selTarget and DB().targets[selTarget]
    local hits = rec and rec.caSpecs and rec.caSpecs[selSlot]
    if not hits then return end
    -- v6.0: the Path mastery lives in the title now, not in the table
    local pinfo = PathInfo(selTarget, selSlot)
    for _, h in ipairs(hits) do
      if not (pinfo and h.id == pinfo.hid) then
        local e
        if CA and CA.GetEntryByInternalID then
            local ok, r = pcall(CA.GetEntryByInternalID, h.id)
            if ok and type(r) == "table" then e = r end
        end
        -- v5.3 (user: "show the MAXED talent"): tooltip/icon use the LAST
        -- spell of the entry (Spells lists the ranks in order), not rank 1
        local sid = e and type(e.Spells) == "table"
            and (e.Spells[#e.Spells] or e.Spells[1]) or nil
        local baseName = (e and e.Name) or h.name
        local nm = baseName or ("entry " .. h.id)
        if h.rank and h.rank > 1 then nm = nm .. " (rank " .. h.rank .. ")" end
        local qual, qOrd, qHex = QualInfo(e)
        -- v5.1: card rarity wins when a card exists for this entry
        local cq = CardQualOf(h.id, baseName, e and e.Spells)
        if cq then qOrd, qual, qHex = cq[1], cq[2], cq[3] end
        local ign = IgnoredSet(false)
        tabRows[#tabRows + 1] = {
            lvl = (e and e.RequiredLevel) or 0,
            -- forward slash on purpose (the client accepts both): a trailing
            -- "\\" in a Lua string breaks check-lua-depth.ps1's naive strip
            icon = e and e.Icon and ("Interface/Icons/" .. e.Icon) or "Interface/Icons/INV_Misc_QuestionMark",
            name = nm,
            typ = (e and e.Type == "Talent") and "Talent" or "Spell",
            qual = qual, qOrd = qOrd, qHex = qHex,
            sid = sid,
            eid = h.id,                       -- v5.0: CA entry id (Ignore key)
            ign = (ign and ign[h.id]) and true or false,
        }
      end
    end
end

local function SortRows()
    local col, asc = sortCol, sortAsc
    table.sort(tabRows, function(a, b)
        local an, bn = string.lower(a.name), string.lower(b.name)
        -- v6.2 (user): Rarity sorts Rarity > Type > Name ; Type sorts
        -- Type > Rarity > Name (secondary keys fixed, arrow = primary only)
        if col == "qual" then
            if a.qOrd ~= b.qOrd then
                if asc then return a.qOrd < b.qOrd else return a.qOrd > b.qOrd end
            end
            if a.typ ~= b.typ then return a.typ < b.typ end
            return an < bn
        elseif col == "typ" then
            if a.typ ~= b.typ then
                if asc then return a.typ < b.typ else return a.typ > b.typ end
            end
            if a.qOrd ~= b.qOrd then return a.qOrd > b.qOrd end
            return an < bn
        end
        local va, vb
        if col == "lvl" then va, vb = a.lvl, b.lvl
        elseif col == "ign" then va, vb = a.ign and 1 or 0, b.ign and 1 or 0
        else va, vb = an, bn end
        if va == vb then return an < bn end
        if asc then return va < vb else return va > vb end
    end)
end

-- ----- left pane: builds list -----
local listPane = CreateFrame("Frame", nil, bui)
listPane:SetWidth(342) listPane:SetHeight(LIST_ROWS * ENTRY_H)
listPane:SetPoint("TOPLEFT", 10, -48)
listPane:EnableMouseWheel(true)
local listRows = {}
local RefreshAll   -- forward

-- v5.3: Name / Date sort buttons above the list -- v6.1: aligned over their
-- actual columns, per-button width
local listSortBtns = {}
local function MkListSort(label, x, w, col, defAsc)
    local b = CreateFrame("Button", nil, bui)
    b:SetWidth(w) b:SetHeight(14)
    b:SetPoint("TOPLEFT", x, -30)
    b.txt = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.txt:SetPoint("LEFT", 2, 0)
    b.base, b.col = label, col
    b.txt:SetText(label)
    b:SetScript("OnClick", function()
        local db = DB()
        local ls = db.listSort or { col = "name", asc = true }
        if ls.col == col then ls.asc = not ls.asc
        else ls.col, ls.asc = col, defAsc end
        db.listSort = ls
        listOff = 0
        RefreshAll()
    end)
    listSortBtns[#listSortBtns + 1] = b
    return b
end
MkListSort("Path", 12, 40, "path", true)
MkListSort("Name", 56, 120, "name", true)
MkListSort("Date", 260, 60, "date", false)   -- first click = newest first
local function ListRow(i)
    local r = listRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, listPane)
    r:SetWidth(338) r:SetHeight(ENTRY_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ENTRY_H)
    -- v6.1 (user): real COLUMNS (path icon | 1H/2H | name | date), each a
    -- single CLIPPED line -- no more wrapped rows; full detail on hover
    r.picon = r:CreateTexture(nil, "ARTWORK")
    r.picon:SetWidth(15) r.picon:SetHeight(15)
    r.picon:SetPoint("LEFT", 2, 0)
    local function FS(x, w)
        local t = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetPoint("LEFT", x, 0)
        t:SetWidth(w)
        t:SetHeight(ENTRY_H)
        t:SetJustifyH("LEFT")
        if t.SetWordWrap then t:SetWordWrap(false) end
        return t
    end
    r.hand = FS(20, 24)
    -- v6.2 (user): wider name ("spec N" spelled out), compact date pinned
    -- to the right
    r.name = FS(46, 200)
    r.date = FS(250, 68)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetTexture(0.3, 0.6, 1, 0.25)
    r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
    r.del:SetWidth(18) r.del:SetHeight(18)
    r.del:SetPoint("RIGHT", 2, 0)
    r:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(d.target .. "  |cffffd100spec " .. d.slot .. "|r")
        if d.path ~= "" then GameTooltip:AddLine(d.path, 0.2, 1, 0.6) end
        if d.cm then GameTooltip:AddLine(d.cm, 0.53, 1, 0.53) end
        GameTooltip:AddLine(d.at, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    listRows[i] = r
    return r
end

-- ----- v4.2: PUSH TO RAPID ROLLING (user, /qol roll dump of 09/08) -----
-- C_Wildcard exposes FULL write access to the "Desired Spells" list:
-- AddDesiredID / CanAddDesiredID / IsDesiredID / RemoveDesiredID /
-- ClearDesiredSpells. Grabbed build hits carry the CA INTERNAL ID (h.id) --
-- the same ID space as the Character Advancement panel -- with the spellID
-- (Spells[1]) as fallback candidate: every add is VERIFIED via IsDesiredID
-- before being counted.
local function PushBuildToRapidRoll()
    local W = _G.C_Wildcard
    if not (W and W.AddDesiredID) then
        Msg("|cffff3333C_Wildcard.AddDesiredID missing -- unexpected client.|r")
        return
    end
    local rec = selTarget and DB().targets[selTarget]
    local allHits = rec and rec.caSpecs and rec.caSpecs[selSlot]
    -- v5.0: ignored entries are INVISIBLE -- not pushed as desired...
    local hits = ActiveHits()
    if not (allHits and #allHits > 0) then
        Msg("select a build on the left first.")
        return
    end
    -- v4.3.2 -- FINAL (/ains rollspy dump of 09/08): the signature is
    -- (ID, TYPE) everywhere -- AddDesiredID(1, "Suggestion"), (14, "Tag")...
    -- -- and IsDesiredID(id, type) answers SYNCHRONOUSLY (false before the
    -- checkbox, true right after, proven by the capture): the initial failure
    -- came ONLY from the missing 2nd argument. A build entry's type = its CA
    -- e.Type ("Ability"/"Talent"); AddDesiredID returns nothing, the verdict
    -- = IsDesiredID re-read (reliable here).
    local CA = _G.C_CharacterAdvancement
    local added, already, refused = 0, 0, {}
    for _, h in ipairs(hits) do
        local typ = "Ability"
        if CA and CA.GetEntryByInternalID then
            local ok, e = pcall(CA.GetEntryByInternalID, h.id)
            if ok and type(e) == "table" and e.Type == "Talent" then typ = "Talent" end
        end
        local okD, isD = pcall(W.IsDesiredID, h.id, typ)
        if okD and isD then
            already = already + 1
        else
            pcall(W.AddDesiredID, h.id, typ)
            local ok2, is2 = pcall(W.IsDesiredID, h.id, typ)
            if ok2 and is2 then
                added = added + 1
            else
                refused[#refused + 1] = (h.name or ("entry " .. tostring(h.id)))
            end
        end
    end
    -- v4.4 (user): UNDESIRED = everything the character KNOWS that is NOT in
    -- the targeted build -- that is what gets rerolled. Sources: GetKnown*
    -- Entries (same IDs as the panel), same (ID, Type) signature, verdict via
    -- IsUndesiredID (synchronous like its Desired twin).
    -- v5.0: ...and NOT marked undesired either -- inBuild is built from ALL
    -- hits (ignored included), so an ignored entry stays untouched both ways.
    local inBuild = {}
    for _, h in ipairs(allHits) do inBuild[h.id] = true end
    local unAdded, unAlready, unRefused = 0, 0, 0
    local function UndesirePass(getter, typ)
        if not (getter and W.AddUndesiredID and W.IsUndesiredID) then return end
        local ok, r = pcall(getter)
        if not (ok and type(r) == "table") then return end
        for _, e in ipairs(NormalizeEntryList(r)) do
            if not inBuild[e.id] then
                local okD, isD = pcall(W.IsUndesiredID, e.id, typ)
                if okD and isD then
                    unAlready = unAlready + 1
                else
                    pcall(W.AddUndesiredID, e.id, typ)
                    local ok2, is2 = pcall(W.IsUndesiredID, e.id, typ)
                    if ok2 and is2 then unAdded = unAdded + 1 else unRefused = unRefused + 1 end
                end
            end
        end
    end
    UndesirePass(CA and CA.GetKnownSpellEntries, "Ability")
    UndesirePass(CA and CA.GetKnownTalentEntries, "Talent")
    local ignored = #allHits - #hits
    Msg("Rapid Rolling: |cff40ff40" .. added .. " added|r"
        .. (already > 0 and ("  " .. already .. " already listed") or "")
        .. (ignored > 0 and ("  |cff999999" .. ignored .. " ignored (checkbox)|r") or "")
        .. (#refused > 0 and ("  |cffff8800" .. #refused .. " refused (already learned/not rollable):|r "
            .. table.concat(refused, ", ")) or ""))
    Msg("Undesired (known OUTSIDE the build -> rerolled): |cffff9955" .. unAdded .. " marked|r"
        .. (unAlready > 0 and ("  " .. unAlready .. " already marked") or "")
        .. (unRefused > 0 and ("  |cffff8800" .. unRefused .. " refused (base kit?)|r") or ""))
end

-- v6.2 (user): open the client's own window BEFORE importing into it.
-- v6.2.1 fix ("no window opens"): the client windows are NOT _G globals --
-- walk EVERY live frame via EnumerateFrames(), case-insensitive name match,
-- shortest name wins (the main window usually beats its children).
local function MatchingFrames(pattern)
    pattern = string.lower(pattern)
    local out = {}
    if not EnumerateFrames then return out end
    local f = EnumerateFrames()
    while f do
        local ok, n = pcall(function() return f.GetName and f:GetName() end)
        if ok and type(n) == "string"
            and string.find(string.lower(n), pattern, 1, true) then
            out[#out + 1] = { f = f, n = n }
        end
        f = EnumerateFrames(f)
    end
    table.sort(out, function(a, b) return string.len(a.n) < string.len(b.n) end)
    return out
end

-- v6.2.2 (measured via /ains frames): exact frame names --
-- SkillCardsFrame (tabs SkillCardsFrameTab1..5, Tab1 = Starter) and
-- WildCardRapidRollingFrame (opened by the client's own
-- CharacterAdvancementContentWCRapidRollButton). Show() alone is NOT enough:
-- these windows sit under hidden ancestors, so the whole parent chain is
-- shown; a TAB is always clicked, a FALLBACK button only if the window
-- still refuses to appear.
local function OpenClientWindow(frameName, tabName, fallbackBtnName)
    local target, tabBtn, fbBtn
    if EnumerateFrames then
        local f = EnumerateFrames()
        while f do
            local ok, n = pcall(function() return f.GetName and f:GetName() end)
            if ok and type(n) == "string" then
                if n == frameName then target = f end
                if tabName and n == tabName then tabBtn = f end
                if fallbackBtnName and n == fallbackBtnName then fbBtn = f end
            end
            f = EnumerateFrames(f)
        end
    end
    if not target then
        Msg("window '" .. frameName .. "' not found -- open it yourself.")
        return false
    end
    local cur, hops = target, 0
    while cur and cur ~= UIParent and hops < 8 do
        local node = cur
        pcall(function() if not node:IsShown() then node:Show() end end)
        local ok, p = pcall(node.GetParent, node)
        cur = ok and p or nil
        hops = hops + 1
    end
    local okS, shown = pcall(target.IsShown, target)
    if not (okS and shown) and fbBtn then
        pcall(function() fbBtn:Click() end)
    end
    if tabBtn then pcall(function() tabBtn:Click() end) end
    return true
end

-- v6.2.1: /ains frames <pattern> -- lists live frames by name for wiring
_G.AscensionInspector_MatchFrames = function(pat)
    local list = MatchingFrames(pat)
    Msg(#list .. " frame(s) matching '" .. pat .. "':")
    for i = 1, math.min(#list, 25) do
        local e = list[i]
        local okS, shown = pcall(function() return e.f:IsShown() end)
        Msg("  " .. e.n .. ((okS and shown) and "  |cff40ff40(shown)|r" or ""))
    end
end

-- v4.2: top-right button (left of the close cross)
local pushBtn = CreateFrame("Button", nil, bui, "UIPanelButtonTemplate")
pushBtn:SetWidth(110) pushBtn:SetHeight(20)
pushBtn:SetPoint("TOPRIGHT", -30, -5)
pushBtn:SetText("-> Rapid Roll")
-- v6.3 (user's trick): the client only re-sorts its Desired/Known lists
-- when a filter changes -- so after the push, the "Abilities" filter is
-- clicked ON then OFF on both panels (same as doing it by hand), and the
-- selected entries float to the top
local function ToggleAbilityFilters()
    for _, menuName in ipairs({ "WildCardRapidRollingFrameDesiredFilterMenu",
        "WildCardRapidRollingFrameUndesiredFilterMenu" }) do
        local menu
        if EnumerateFrames then
            local f = EnumerateFrames()
            while f do
                local ok, n = pcall(function() return f.GetName and f:GetName() end)
                if ok and n == menuName then
                    menu = f
                    break
                end
                f = EnumerateFrames(f)
            end
        end
        local clicked = false
        if menu then
            local kids = { menu:GetChildren() }
            for _, k in ipairs(kids) do
                local ok, txt = pcall(function()
                    return (k.GetText and k:GetText())
                        or (k.Text and k.Text.GetText and k.Text:GetText())
                end)
                if ok and txt == "Abilities" and k.Click then
                    pcall(function()
                        k:Click()
                        k:Click()
                    end)
                    clicked = true
                    break
                end
            end
        end
        if not clicked then
            Msg("|cff888888could not click the Abilities filter of " .. menuName
                .. " -- toggle a filter by hand to refresh that list.|r")
        end
    end
end

pushBtn:SetScript("OnClick", function()
    -- v6.2 (user): show the Rapid Rolling window first, then import
    OpenClientWindow("WildCardRapidRollingFrame", nil,
        "CharacterAdvancementContentWCRapidRollButton")
    PushBuildToRapidRoll()
    ToggleAbilityFilters()
    Msg("|cffffd100Please double-check the Desired/Undesired lists yourself -- make sure the import really landed.|r")
end)

-- v4.3: SKILL CARDS -- optimizes and PLACES the cards for the selected build
-- (SkillCardPlanner v1.0; golden first, decreasing card quality, never a
-- duplicate, starters = level 1 spells)
local cardBtn = CreateFrame("Button", nil, bui, "UIPanelButtonTemplate")
cardBtn:SetWidth(110) cardBtn:SetHeight(20)
cardBtn:SetPoint("TOPRIGHT", -144, -5)
cardBtn:SetText("-> Skill Cards")
cardBtn:SetScript("OnClick", function()
    local rec = selTarget and DB().targets[selTarget]
    local allHits = rec and rec.caSpecs and rec.caSpecs[selSlot]
    if not (allHits and #allHits > 0) then Msg("select a build on the left first.") return end
    -- v6.2 (user): show the Skill Cards window first (Starter tab), then place
    OpenClientWindow("SkillCardsFrame", "SkillCardsFrameTab1", nil)
    if _G.AscensionInspector_CardPlan then
        -- v5.0: the planner only sees the NON-ignored entries
        _G.AscensionInspector_CardPlan(ActiveHits())
        Msg("|cffffd100Please double-check the card slots yourself (all 3 tabs) -- make sure every card really landed.|r")
    else
        Msg("SkillCardPlanner missing (TOC?)")
    end
end)
cardBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Optimizes and PLACES the Skill Cards for this build:\ngolden first, rarest cards first, never a duplicate,\nstarters = level 1 spells. Ignored entries are skipped.\n(Placement possible at prestige start / re-roll.)", 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
cardBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
pushBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Pushes the selected build into Rapid Rolling's\n\"Desired Spells\" list (verified entry by entry) and\nmarks known entries OUTSIDE the build as undesired.\nIgnored entries are left untouched both ways.", 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
pushBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ----- right pane: headers + table -----
-- v5.0: "Ignore" column added -- v5.3: "Category" column removed (user)
local COLS = {
    { key = "lvl",  label = "Lvl",    w = 36 },
    { key = "icon", label = "",       w = 22 },
    { key = "name", label = "Name",   w = 250 },
    { key = "typ",  label = "Type",   w = 60 },
    { key = "qual", label = "Rarity", w = 74 },
    { key = "ign",  label = "Ignore", w = 44 },
}
local tabPane = CreateFrame("Frame", nil, bui)
tabPane:SetWidth(510) tabPane:SetHeight(TAB_ROWS * ENTRY_H)
tabPane:SetPoint("TOPLEFT", 360, -56)   -- v6.1: wider list on the left
tabPane:EnableMouseWheel(true)
local headers = {}
local hx = 0
for ci, col in ipairs(COLS) do
    local h = CreateFrame("Button", nil, bui)
    h:SetWidth(col.w) h:SetHeight(20)
    h:SetPoint("TOPLEFT", 360 + hx, -32)
    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h.text:SetPoint("LEFT", 2, 0)
    h.text:SetText(col.label)
    if col.key ~= "icon" then
        h:SetScript("OnClick", function()
            -- v5.6: first click on Rarity sorts DESC (legendary first)
            if sortCol == col.key then sortAsc = not sortAsc
            else sortCol, sortAsc = col.key, (col.key ~= "qual") end
            SortRows()
            tabOff = 0
            RefreshAll()
        end)
    end
    headers[ci] = h
    hx = hx + col.w + 4
end
local tabLines = {}
local function TabLine(i)
    local r = tabLines[i]
    if r then return r end
    r = CreateFrame("Button", nil, tabPane)
    r:SetWidth(506) r:SetHeight(ENTRY_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ENTRY_H)
    local x = 0
    r.lvl = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.lvl:SetPoint("LEFT", 2, 0) r.lvl:SetWidth(COLS[1].w) r.lvl:SetJustifyH("LEFT")
    x = x + COLS[1].w + 4
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetWidth(17) r.icon:SetHeight(17)
    r.icon:SetPoint("LEFT", x + 2, 0)
    x = x + COLS[2].w + 4
    r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", x + 2, 0) r.name:SetWidth(COLS[3].w) r.name:SetJustifyH("LEFT")
    x = x + COLS[3].w + 4
    r.typ = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.typ:SetPoint("LEFT", x + 2, 0) r.typ:SetWidth(COLS[4].w) r.typ:SetJustifyH("LEFT")
    x = x + COLS[4].w + 4
    r.qual = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.qual:SetPoint("LEFT", x + 2, 0) r.qual:SetWidth(COLS[5].w) r.qual:SetJustifyH("LEFT")
    x = x + COLS[5].w + 4
    -- v5.0: Ignore checkbox -- off by default, stored per entry in
    -- rec.ignored[slot][entryId]; ignored entries are invisible to the
    -- Rapid Roll and Skill Cards exports
    r.ign = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.ign:SetWidth(18) r.ign:SetHeight(18)
    r.ign:SetPoint("LEFT", x + 10, 0)
    r.ign:SetScript("OnClick", function(self)
        local d = self.rowData
        if not d then return end
        local set = IgnoredSet(true)
        if not set then return end
        local on = self:GetChecked() and true or false
        set[d.eid] = on or nil
        d.ign = on
    end)
    r:SetScript("OnEnter", function(self)
        if self.sid then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. self.sid)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tabLines[i] = r
    return r
end

RefreshAll = function()
    local list = BuildList()
    if listOff > math.max(0, #list - LIST_ROWS) then listOff = math.max(0, #list - LIST_ROWS) end
    for i = 1, LIST_ROWS do
        local d = list[i + listOff]
        local r = ListRow(i)
        if d then
            r.data = d
            r.hand:SetText(d.hand and ("|cffffd100" .. d.hand .. "|r") or "")
            r.name:SetText(d.target .. " |cffffd100spec " .. d.slot .. "|r"
                .. (d.cm and ("  |cff88ff88" .. d.cm .. "|r") or ""))
            r.date:SetText("|cff888888" .. d.atShort .. "|r")
            if d.pathIcon then
                r.picon:SetTexture(d.pathIcon)
                r.picon:Show()
            else
                r.picon:Hide()
            end
            if d.target == selTarget and d.slot == selSlot then r.hl:Show() else r.hl:Hide() end
            r:SetScript("OnClick", function()
                selTarget, selSlot = d.target, d.slot
                tabOff = 0
                PrepareRows()
                SortRows()
                RefreshAll()
            end)
            r.del:SetScript("OnClick", function()
                local rec = DB().targets[d.target]
                if rec and rec.caSpecs then
                    rec.caSpecs[d.slot] = nil
                    if not next(rec.caSpecs) then rec.caSpecs = nil end
                end
                -- v5.0: drop the ignore set with its build
                if rec and rec.ignored then
                    rec.ignored[d.slot] = nil
                    if not next(rec.ignored) then rec.ignored = nil end
                end
                if selTarget == d.target and selSlot == d.slot then
                    selTarget, selSlot, tabRows = nil, nil, {}
                end
                Msg("build deleted: " .. d.target .. " spec " .. d.slot)
                RefreshAll()
            end)
            r:Show()
        else
            r.data = nil
            r:Hide()
        end
    end
    if tabOff > math.max(0, #tabRows - TAB_ROWS) then tabOff = math.max(0, #tabRows - TAB_ROWS) end
    for ci, col in ipairs(COLS) do
        local mark = ""
        if sortCol == col.key then mark = sortAsc and "  ^" or "  v" end
        headers[ci].text:SetText(col.label .. mark)
    end
    -- v5.3: list sort arrows
    local ls = DB().listSort or { col = "name", asc = true }
    for _, b in ipairs(listSortBtns) do
        b.txt:SetText(b.base .. (ls.col == b.col and (ls.asc and "  ^" or "  v") or ""))
    end
    for i = 1, TAB_ROWS do
        local d = tabRows[i + tabOff]
        local r = TabLine(i)
        if d then
            r.lvl:SetText(d.lvl > 0 and d.lvl or "-")
            r.icon:SetTexture(d.icon)
            r.name:SetText("|cff" .. (d.qHex or "ffffff") .. d.name .. "|r")
            r.typ:SetText(d.typ == "Talent" and "|cffffd100Talent|r" or "|cff66ccffSpell|r")
            r.qual:SetText("|cff" .. (d.qHex or "ffffff") .. (d.qual or "?") .. "|r")
            r.sid = d.sid
            r.ign.rowData = d
            r.ign:SetChecked(d.ign)
            r:Show()
        else
            r:Hide()
        end
    end
    -- v6.0 (user): the title shows the build's PATH instead of the generic
    -- stat/weapon summary (the Gear pane covers the real numbers now)
    local extra = {}
    if selTarget then
        local pinfo = PathInfo(selTarget, selSlot)
        local rec = DB().targets[selTarget]
        local p = (pinfo and pinfo.name)
            or (rec and rec.pathBySpec and rec.pathBySpec[selSlot])
        if p then extra[#extra + 1] = p end
    end
    bTitle:SetText("BuildSpy -- grabbed builds"
        .. (selTarget and ("  --  |cffffd100" .. selTarget .. " spec " .. selSlot .. "|r (" .. #tabRows .. " entries)") or "")
        .. (#extra > 0 and ("  |cff33ff99[" .. table.concat(extra, "  --  ") .. "]|r") or ""))
    -- v3.5: reload the selected build's comment into the editbox
    local cb = _G.AscensionInspectorComment
    if cb and not cb:HasFocus() then
        local rec = selTarget and DB().targets[selTarget]
        cb:SetText((rec and rec.comments and rec.comments[selSlot]) or "")
    end
    -- v6.6: reload the selected build's name into the rename editbox
    local nb = _G.AscensionInspectorName
    if nb and not nb:HasFocus() then nb:SetText(selTarget or "") end
end

listPane:SetScript("OnMouseWheel", function(_, delta)
    listOff = math.max(0, listOff - delta * 3)
    RefreshAll()
end)
tabPane:SetScript("OnMouseWheel", function(_, delta)
    tabOff = math.max(0, tabOff - delta * 3)
    RefreshAll()
end)
bui:SetScript("OnShow", function()
    local db = DB()
    if db.buildsPos then
        bui:ClearAllPoints()
        bui:SetPoint(db.buildsPos[1], UIParent, db.buildsPos[2], db.buildsPos[3], db.buildsPos[4])
    end
    if selTarget then PrepareRows() SortRows() end
    RefreshAll()
end)
-- v3.5 / v6.6 : "selected build's" group -- Name (rename) + Comment editboxes
-- under the list, each Enter = save. Comment -> rec.comments[slot]. Rename
-- MOVES this build's slot (and its per-slot data) to the new target name.
local grpLbl = bui:CreateFontString(nil, "ARTWORK", "GameFontNormal")
grpLbl:SetPoint("BOTTOMLEFT", 14, 52)
grpLbl:SetText("selected build's  |cff888888(Enter = save)|r")

local nameLbl = bui:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
nameLbl:SetPoint("BOTTOMLEFT", 16, 32)
nameLbl:SetText("Name")
local nameBox = CreateFrame("EditBox", "AscensionInspectorName", bui, "InputBoxTemplate")
nameBox:SetWidth(226) nameBox:SetHeight(18)
nameBox:SetPoint("BOTTOMLEFT", 84, 30)
nameBox:SetAutoFocus(false)
nameBox:SetScript("OnEnterPressed", function(self)
    if not selTarget then Msg("select a build first.") self:ClearFocus() return end
    local newName = string.gsub(self:GetText() or "", "^%s*(.-)%s*$", "%1")
    if newName == "" or newName == selTarget then self:ClearFocus() return end
    local old = DB().targets[selTarget]
    if not (old and old.caSpecs and old.caSpecs[selSlot]) then self:ClearFocus() return end
    -- move this slot (+ its per-slot data) to the new target name
    local rec2 = DB().targets[newName]
    local fresh = rec2 == nil
    rec2 = rec2 or {}
    DB().targets[newName] = rec2
    if fresh then
        rec2.at, rec2.level, rec2.class = old.at, old.level, old.class
        rec2.activeSpec = old.activeSpec
    end
    rec2.caSpecs = rec2.caSpecs or {}
    local ns = selSlot
    if rec2.caSpecs[ns] then ns = 1 while rec2.caSpecs[ns] do ns = ns + 1 end end
    rec2.caSpecs[ns] = old.caSpecs[selSlot]
    old.caSpecs[selSlot] = nil
    local function moveSub(field)
        if old[field] and old[field][selSlot] ~= nil then
            rec2[field] = rec2[field] or {}
            rec2[field][ns] = old[field][selSlot]
            old[field][selSlot] = nil
            if not next(old[field]) then old[field] = nil end
        end
    end
    moveSub("comments") moveSub("pathBySpec") moveSub("ignored") moveSub("gearBySpec")
    if not next(old.caSpecs) then DB().targets[selTarget] = nil end
    Msg("renamed to |cffffd100" .. newName .. " spec " .. ns .. "|r.")
    self:ClearFocus()
    selTarget, selSlot = newName, ns   -- new pathCache key computed lazily
    PrepareRows() SortRows() RefreshAll()
end)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local cmLbl = bui:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
cmLbl:SetPoint("BOTTOMLEFT", 16, 10)
cmLbl:SetText("Comment")
local cmBox = CreateFrame("EditBox", "AscensionInspectorComment", bui, "InputBoxTemplate")
cmBox:SetWidth(226) cmBox:SetHeight(18)
cmBox:SetPoint("BOTTOMLEFT", 84, 8)
cmBox:SetAutoFocus(false)
cmBox:SetScript("OnEnterPressed", function(self)
    if not selTarget then Msg("select a build first.") self:ClearFocus() return end
    local rec = DB().targets[selTarget]
    if not rec then self:ClearFocus() return end
    local txt = string.gsub(self:GetText() or "", "^%s*(.-)%s*$", "%1")
    rec.comments = rec.comments or {}
    rec.comments[selSlot] = (txt ~= "") and txt or nil
    Msg("comment " .. (txt ~= "" and "saved" or "cleared") .. " for " .. selTarget .. " spec " .. selSlot .. ".")
    self:ClearFocus()
    RefreshAll()
end)
cmBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- ==================== v5.1: EXPORT / IMPORT (user request) ====================
-- Plain-text build sharing. Format:
--   [BuildSpy] <player>, spec <n>, <comment or ->, <date>
--   ==Spells==            (one entry name per line)
--   ==Talents==
-- Sections sorted by rarity (card rarity when known) then by required level,
-- both DESCENDING. Import resolves names back to CA entries (name -> entry
-- map built once from GetAllEntries) and stores the build like a grab.
local function ExportText(includeIgnored)
    local rec = selTarget and DB().targets[selTarget]
    local hits = rec and rec.caSpecs and rec.caSpecs[selSlot]
    if not hits then return nil end
    local CA = _G.C_CharacterAdvancement
    -- v6.0: the Path goes on line 2, not in the sections; the "include
    -- ignored entries" toggle strips checked-off entries when unchecked
    local pinfo = PathInfo(selTarget, selSlot)
    local ign = IgnoredSet(false) or {}
    local spells, talents = {}, {}
    for _, h in ipairs(hits) do
      if not (pinfo and h.id == pinfo.hid)
          and (includeIgnored or not ign[h.id]) then
        local e
        if CA and CA.GetEntryByInternalID then
            local ok, r = pcall(CA.GetEntryByInternalID, h.id)
            if ok and type(r) == "table" then e = r end
        end
        local _, qOrd = QualInfo(e)
        local cq = CardQualOf(h.id, (e and e.Name) or h.name, e and e.Spells)
        if cq then qOrd = cq[1] end
        local row = { name = (e and e.Name) or h.name or ("entry " .. h.id),
            q = qOrd or -1, lvl = (e and e.RequiredLevel) or 0 }
        if e and e.Type == "Talent" then talents[#talents + 1] = row
        else spells[#spells + 1] = row end
      end
    end
    local function bySort(a, b)
        if a.q ~= b.q then return a.q > b.q end
        if a.lvl ~= b.lvl then return a.lvl > b.lvl end
        return a.name < b.name
    end
    table.sort(spells, bySort)
    table.sort(talents, bySort)
    local cm = rec.comments and rec.comments[selSlot]
    local out = { "[BuildSpy] " .. selTarget .. ", spec " .. selSlot .. ", "
        .. (cm or "-") .. ", " .. tostring(rec.at) }
    if pinfo then out[#out + 1] = pinfo.name end   -- v6.0: Path = line 2
    out[#out + 1] = "==Spells=="
    for _, r in ipairs(spells) do out[#out + 1] = r.name end
    out[#out + 1] = "==Talents=="
    for _, r in ipairs(talents) do out[#out + 1] = r.name end
    -- v5.2 (user): gear section -- "s<slot> itemID:enchantID  name" (IDs are
    -- the exact identity, the trailing name is only a human comment)
    local g = rec.gearBySpec and (rec.gearBySpec[selSlot]
        or (rec.activeSpec and rec.gearBySpec[rec.activeSpec]))
    if g and g.items and next(g.items) then
        out[#out + 1] = "==Gear=="
        local slots = {}
        for s in pairs(g.items) do slots[#slots + 1] = s end
        table.sort(slots)
        for _, s in ipairs(slots) do
            local link = g.items[s]
            local id, ench = string.match(link, "item:(%d+):(%-?%d+)")
            id = id or string.match(link, "item:(%d+)")
            if id then
                local nm = string.match(link, "|h%[(.-)%]|h") or ""
                out[#out + 1] = "s" .. s .. " " .. id .. ":" .. (ench or "0")
                    .. (nm ~= "" and ("  " .. nm) or "")
            end
        end
    end
    return table.concat(out, "\n")
end

-- v6.4 (user): shareable ascension.nie.one build LINK. Reverse-engineered
-- from a working link + its id export (round-trip verified on 56 ids):
--   <prefix> . <path spellID> ~ <spell spellIDs> ~ <talent spellIDs>
-- every id in BASE 36, dot-separated ; groups split by "~". The prefix
-- "1.s10w60" = version 1 / season 10 / wildcard 60 (metadata shown by the
-- site) -- HARDCODED from the sample, adjust here if the season/mode changes.
local NIE_PREFIX = "1.s10w60"
local NIE_BASE = "https://ascension.nie.one/#b="
local function Base36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local d = "0123456789abcdefghijklmnopqrstuvwxyz"
    local s = ""
    while n > 0 do
        local r = n % 36
        s = string.sub(d, r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end
local function BuildLink(includeIgnored)
    local rec = selTarget and DB().targets[selTarget]
    local hits = rec and rec.caSpecs and rec.caSpecs[selSlot]
    if not hits then return nil end
    local CA = _G.C_CharacterAdvancement
    local pinfo = PathInfo(selTarget, selSlot)
    local ign = IgnoredSet(false) or {}
    -- the Path's spell id from PATH_ENTRIES (rank 1, e.g. 84865)
    local pathSp
    if pinfo then
        for _, p in ipairs(PATH_ENTRIES) do
            if p.ca == pinfo.hid then pathSp = p.sp break end
        end
    end
    local spells, talents, missing = {}, {}, 0
    for _, h in ipairs(hits) do
      if not (pinfo and h.id == pinfo.hid)
          and (includeIgnored or not ign[h.id]) then
        local e
        if CA and CA.GetEntryByInternalID then
            local ok, r = pcall(CA.GetEntryByInternalID, h.id)
            if ok and type(r) == "table" then e = r end
        end
        -- rank-1 spell id (same one the sample link used for the path)
        local sid = e and type(e.Spells) == "table" and e.Spells[1] or nil
        if sid then
            if e and e.Type == "Talent" then talents[#talents + 1] = Base36(sid)
            else spells[#spells + 1] = Base36(sid) end
        else
            missing = missing + 1
        end
      end
    end
    local out = NIE_PREFIX .. "." .. (pathSp and Base36(pathSp) or "0")
        .. "~" .. table.concat(spells, ".")
        .. "~" .. table.concat(talents, ".")
    return NIE_BASE .. out, #spells, #talents, missing, (pathSp ~= nil)
end

-- name -> CA entry map for the import (built once; ~6000 local reads)
local importNameMap
local function ImportNameMap()
    if importNameMap then return importNameMap end
    local CA = _G.C_CharacterAdvancement
    if not (CA and CA.GetEntryByInternalID) then return nil end
    local ids = AllTalentIDs(CA)
    if not ids then return nil end
    importNameMap = {}
    for _, id in ipairs(ids) do
        local ok, e = pcall(CA.GetEntryByInternalID, id)
        if ok and type(e) == "table" and e.Name then
            local key = string.lower(e.Name)
            local typ = (e.Type == "Talent") and "Talent" or "Ability"
            importNameMap[key] = importNameMap[key] or {}
            if not importNameMap[key][typ] then importNameMap[key][typ] = id end
        end
    end
    return importNameMap
end

-- v6.5 (user): import ALSO accepts an ascension.nie.one LINK or the site's
-- comma-separated SPELL-ID list. Both decode to spell ids -> SpellIndex
-- resolves each to its CA entry (all ranks covered), stored as a build under
-- a synthetic "Imported" name. base-36 decoder (mirror of Base36).
local function From36(s)
    local n = 0
    s = string.lower(s or "")
    if s == "" then return nil end
    for i = 1, #s do
        local c = string.byte(s, i)
        local v
        if c >= 48 and c <= 57 then v = c - 48
        elseif c >= 97 and c <= 122 then v = c - 87
        else return nil end
        n = n * 36 + v
    end
    return n
end
local function StoreImportedBuild(ids, srcLabel)
    local CA = _G.C_CharacterAdvancement
    local si = SpellIndex()
    local hits, unresolved = {}, 0
    for _, sid in ipairs(ids) do
        -- v6.7 fix (user: imported DK spells showed lvl 71 / wrong type): a
        -- spell id can belong to SEVERAL CA entries (shared across classes/
        -- levels) and SpellIndex kept only the FIRST -- GetEntryBySpellID is
        -- the game's AUTHORITATIVE resolver (tooltip proves 48266 -> entry
        -- 41932, level 1) so it goes FIRST, SpellIndex only as fallback
        local caId, name
        if CA and CA.GetEntryBySpellID then
            local ok, e = pcall(CA.GetEntryBySpellID, sid)
            if ok and type(e) == "table" then
                caId = e.ID or e.Id or e.id or e.entryID or e.EntryID or e.internalID
                name = e.Name
            end
        end
        if not caId then
            local fam = si and si[sid]
            if fam then caId, name = fam.id, fam.name end
        end
        if caId then hits[#hits + 1] = { id = caId, rank = 1, name = name }
        else unresolved = unresolved + 1 end
    end
    if #hits == 0 then
        Msg("import: no spell id resolved (" .. srcLabel .. ").")
        return
    end
    -- store under "Imported", smallest free spec slot (never clobber)
    local rec = DB().targets["Imported"] or {}
    DB().targets["Imported"] = rec
    rec.at = date("%Y-%m-%d %H:%M")
    rec.caSpecs = rec.caSpecs or {}
    local slot = 1
    while rec.caSpecs[slot] do slot = slot + 1 end
    rec.caSpecs[slot] = hits
    Msg("import (" .. srcLabel .. "): |cff40ff40" .. #hits .. " entries|r -> Imported spec " .. slot
        .. (unresolved > 0 and ("  |cffff8800" .. unresolved .. " unresolved|r") or ""))
    selTarget, selSlot = "Imported", slot
    PrepareRows() SortRows()
    if BuildsChanged then BuildsChanged() else RefreshAll() end
end

local function ImportText(txt)
    txt = txt or ""
    -- v6.5: dispatch by FORMAT before the text parser
    -- 1) ascension.nie.one link (has "~" groups, or the site url/prefix)
    local body = string.match(txt, "#b=(.+)") or txt
    body = string.gsub(body, "%s", "")
    if string.find(body, "~", 1, true) and not string.find(txt, "==Spells==", 1, true) then
        local groups = {}
        for g in string.gmatch(body .. "~", "(.-)~") do groups[#groups + 1] = g end
        local ids = {}
        -- group 1 = "<ver>.<mode>.<path>" : the path is the last dot-token
        if groups[1] then
            local toks = {}
            for t in string.gmatch(groups[1] .. ".", "(.-)%.") do toks[#toks + 1] = t end
            local pid = From36(toks[#toks])
            if pid and pid > 0 then ids[#ids + 1] = pid end
        end
        for gi = 2, #groups do
            for t in string.gmatch(groups[gi] .. ".", "(.-)%.") do
                local v = From36(t)
                if v and v > 0 then ids[#ids + 1] = v end
            end
        end
        StoreImportedBuild(ids, "nie.one link")
        return
    end
    -- 2) comma-separated decimal spell-id list
    if string.find(txt, "^[%d%s,]+$") then
        local ids = {}
        for d in string.gmatch(txt, "%d+") do
            local v = tonumber(d)
            if v and v > 0 then ids[#ids + 1] = v end
        end
        StoreImportedBuild(ids, "id list")
        return
    end
    -- 3) BuildSpy text format
    local lines = {}
    for line in string.gmatch(txt .. "\n", "(.-)\r?\n") do
        line = string.gsub(line, "^%s*(.-)%s*$", "%1")
        if line ~= "" then lines[#lines + 1] = line end
    end
    if #lines < 2 then Msg("import: nothing to parse.") return end
    -- header: [BuildSpy] name, spec N, comment, date
    local header = string.gsub(lines[1], "^%[BuildSpy%]%s*", "")
    local fields = {}
    for f in string.gmatch(header .. ",", "(.-),") do
        fields[#fields + 1] = string.gsub(f, "^%s*(.-)%s*$", "%1")
    end
    local pname = fields[1]
    local slot = fields[2] and tonumber(string.match(fields[2], "spec%s*(%d+)"))
    if not (pname and pname ~= "" and slot) then
        Msg("import: bad header (expected: [BuildSpy] name, spec N, comment, date).")
        return
    end
    local dateStr = fields[#fields]
    local comment = table.concat(fields, ", ", 3, math.max(3, #fields - 1))
    if comment == "-" or comment == "" then comment = nil end
    local map = ImportNameMap()
    if not map then Msg("import: C_CharacterAdvancement unavailable.") return end
    local mode = nil   -- "Ability" / "Talent" / "Gear"
    local hits, missing, gear = {}, {}, {}
    for i = 2, #lines do
        local l = lines[i]
        if l == "==Spells==" then mode = "Ability"
        elseif l == "==Talents==" then mode = "Talent"
        elseif l == "==Gear==" then mode = "Gear"
        elseif mode == "Gear" then
            -- v5.2: "s<slot> itemID:enchantID  <name comment ignored>"
            local s, id, ench = string.match(l, "^s(%d+)%s+(%d+):?(%-?%d*)")
            if s and id then
                gear[tonumber(s)] = "item:" .. id .. ":"
                    .. ((ench and ench ~= "") and ench or "0") .. ":0:0:0:0:0:0"
            end
        elseif mode == nil then
            -- v6.0: any line before the first section = the Path (line 2)
            local entry = map[string.lower(l)]
            local id = entry and (entry.Ability or entry.Talent)
            if id then hits[#hits + 1] = { id = id, rank = 1, name = l }
            else missing[#missing + 1] = l end
        elseif mode then
            local entry = map[string.lower(l)]
            local id = entry and (entry[mode] or entry.Ability or entry.Talent)
            if id then hits[#hits + 1] = { id = id, rank = 1, name = l }
            else missing[#missing + 1] = l end
        end
    end
    if #hits == 0 then
        Msg("import: no entry resolved" .. (#missing > 0 and (" (" .. #missing .. " unknown names)") or "") .. ".")
        return
    end
    local rec = DB().targets[pname] or {}
    DB().targets[pname] = rec
    rec.at = rec.at or dateStr or date("%Y-%m-%d %H:%M")
    rec.caSpecs = rec.caSpecs or {}
    local existed = rec.caSpecs[slot] ~= nil
    rec.caSpecs[slot] = hits
    if comment then
        rec.comments = rec.comments or {}
        rec.comments[slot] = comment
    end
    -- v5.2: imported gear filed under the build's spec slot
    local gn = 0
    for _ in pairs(gear) do gn = gn + 1 end
    if gn > 0 then
        rec.gearBySpec = rec.gearBySpec or {}
        rec.gearBySpec[slot] = rec.gearBySpec[slot] or {}
        rec.gearBySpec[slot].items = gear
        rec.gearBySpec[slot].at = dateStr
        rec.gearBySpec[slot].statOrder = GearStatOrder(gear) or rec.gearBySpec[slot].statOrder
        rec.gearBySpec[slot].weapons = GearWeaponTypes(gear) or rec.gearBySpec[slot].weapons
    end
    Msg("import: |cff40ff40" .. #hits .. " entries|r"
        .. (gn > 0 and (" + " .. gn .. " items") or "") .. " -> " .. pname .. " spec " .. slot
        .. (existed and " |cffff8800(overwrote the existing build)|r" or "")
        .. (#missing > 0 and ("  |cffff8800" .. #missing .. " unknown name(s): "
            .. table.concat(missing, ", ") .. "|r") or ""))
    selTarget, selSlot = pname, slot
    PrepareRows() SortRows() RefreshAll()
end

-- shared dialog: Export fills it (ready to Ctrl+C), Import parses its content
local ioFrame = CreateFrame("Frame", "BuildSpyIO", UIParent)
ioFrame:SetWidth(470) ioFrame:SetHeight(380)
ioFrame:SetPoint("CENTER", 0, 0)
ioFrame:SetFrameStrata("DIALOG")
ioFrame:SetMovable(true) ioFrame:EnableMouse(true)
ioFrame:RegisterForDrag("LeftButton")
ioFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
ioFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
ioFrame:Hide()
local iobg = ioFrame:CreateTexture(nil, "BACKGROUND")
iobg:SetAllPoints() iobg:SetTexture(0.05, 0.04, 0.08, 0.97)
local ioedges = {}
for i = 1, 4 do ioedges[i] = ioFrame:CreateTexture(nil, "BORDER") ioedges[i]:SetTexture(0.4, 0.8, 1, 0.9) end
ioedges[1]:SetPoint("TOPLEFT") ioedges[1]:SetPoint("TOPRIGHT") ioedges[1]:SetHeight(2)
ioedges[2]:SetPoint("BOTTOMLEFT") ioedges[2]:SetPoint("BOTTOMRIGHT") ioedges[2]:SetHeight(2)
ioedges[3]:SetPoint("TOPLEFT") ioedges[3]:SetPoint("BOTTOMLEFT") ioedges[3]:SetWidth(2)
ioedges[4]:SetPoint("TOPRIGHT") ioedges[4]:SetPoint("BOTTOMRIGHT") ioedges[4]:SetWidth(2)
local ioClose = CreateFrame("Button", nil, ioFrame, "UIPanelCloseButton")
ioClose:SetPoint("TOPRIGHT", 2, 2)
local ioTitle = ioFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
ioTitle:SetPoint("TOP", 0, -9)
ioTitle:SetText("BuildSpy -- export / import")
local ioScroll = CreateFrame("ScrollFrame", "BuildSpyIOScroll", ioFrame, "UIPanelScrollFrameTemplate")
ioScroll:SetPoint("TOPLEFT", 12, -30)
ioScroll:SetPoint("BOTTOMRIGHT", -32, 56)   -- v6.5: room for the 2-line hint
local ioEdit = CreateFrame("EditBox", nil, ioScroll)
ioEdit:SetMultiLine(true)
ioEdit:SetFontObject(ChatFontNormal)
ioEdit:SetWidth(420)
ioEdit:SetAutoFocus(false)
ioEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
ioScroll:SetScrollChild(ioEdit)
local ioHint = ioFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
ioHint:SetPoint("BOTTOMLEFT", 14, 26)
-- v6.5 (user): state what Import accepts
ioHint:SetText("Export: Ctrl+C.  Import (then ->) accepts: a BuildSpy text export,\nan ascension.nie.one link, or the site's comma-separated spell-id list.")
local ioGo = CreateFrame("Button", nil, ioFrame, "UIPanelButtonTemplate")
ioGo:SetWidth(90) ioGo:SetHeight(20)
ioGo:SetPoint("BOTTOMRIGHT", -10, 8)
ioGo:SetText("Import")
ioGo:SetScript("OnClick", function()
    ImportText(ioEdit:GetText())
end)
-- v6.0 (user): toggle -- also export the IGNORED entries? (on = full build)
local ioIncl = CreateFrame("CheckButton", nil, ioFrame, "UICheckButtonTemplate")
ioIncl:SetWidth(20) ioIncl:SetHeight(20)
ioIncl:SetPoint("BOTTOMLEFT", 10, 4)
ioIncl:SetChecked(true)
local ioInclL = ioFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
ioInclL:SetPoint("LEFT", ioIncl, "RIGHT", 1, 0)
ioInclL:SetText("include ignored entries")
ioIncl:SetScript("OnClick", function(self)
    if ioFrame.exportMode then
        local t = ExportText(self:GetChecked() and true or false)
        if t then
            ioEdit:SetText(t)
            ioEdit:HighlightText()
        end
    end
end)

-- v6.1 (user): grab MY OWN build from the builds window, left of Export
local myBuildBtn = CreateFrame("Button", nil, bui, "UIPanelButtonTemplate")
myBuildBtn:SetWidth(80) myBuildBtn:SetHeight(18)
myBuildBtn:SetPoint("BOTTOMLEFT", 360, 6)
myBuildBtn:SetText("+ My build")
myBuildBtn:SetScript("OnClick", function() StartCapture("player") end)
myBuildBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Grab MY current build into the list (= /ains self).", 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
myBuildBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local exportBtn = CreateFrame("Button", nil, bui, "UIPanelButtonTemplate")
exportBtn:SetWidth(64) exportBtn:SetHeight(18)
exportBtn:SetPoint("BOTTOMLEFT", 444, 6)
exportBtn:SetText("Export")
exportBtn:SetScript("OnClick", function()
    local t = ExportText(ioIncl:GetChecked() and true or false)
    if not t then Msg("select a build on the left first.") return end
    ioFrame.exportMode = true
    ioFrame:Show()
    ioEdit:SetText(t)
    ioEdit:HighlightText()
    ioEdit:SetFocus()
end)
local importBtn = CreateFrame("Button", nil, bui, "UIPanelButtonTemplate")
importBtn:SetWidth(64) importBtn:SetHeight(18)
importBtn:SetPoint("BOTTOMLEFT", 512, 6)
importBtn:SetText("Import")
importBtn:SetScript("OnClick", function()
    ioFrame.exportMode = false
    ioFrame:Show()
    ioEdit:SetText("")
    ioEdit:SetFocus()
end)

-- v6.4 (user): shareable ascension.nie.one link (Ctrl+C ready)
local linkBtn = CreateFrame("Button", nil, bui, "UIPanelButtonTemplate")
linkBtn:SetWidth(60) linkBtn:SetHeight(18)
linkBtn:SetPoint("BOTTOMLEFT", 580, 6)
linkBtn:SetText("Link")
linkBtn:SetScript("OnClick", function()
    local url, ns, nt, missing, hasPath = BuildLink(ioIncl:GetChecked() and true or false)
    if not url then Msg("select a build on the left first.") return end
    ioFrame.exportMode = false   -- read-only text, not an import target
    ioFrame:Show()
    ioEdit:SetText(url)
    ioEdit:HighlightText()
    ioEdit:SetFocus()
    Msg("link: |cff40ff40" .. ns .. " spells, " .. nt .. " talents"
        .. (hasPath and "" or ", |cffff8800no path|r")
        .. (missing > 0 and ("|r, |cffff8800" .. missing .. " without a spell id skipped") or "")
        .. "|r -- Ctrl+C. |cffffd100Double-check it opens the right build.|r")
end)
linkBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Shareable ascension.nie.one link for the selected build\n(base-36 spell ids). Ctrl+C to copy.", 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
linkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ==================== v5.2: GEAR side pane (user request) ====================
-- "Real equipped items instead of the generic summary": item list on the
-- left (hover = full tooltip, enchants included -- the stored links carry
-- the enchant id), TOTAL equipment stats on the right. Toggled by the
-- [Gear] button; slides out on the right side of the builds window. Gear is
-- captured per ACTIVE spec only, so a note shows when the displayed set was
-- captured on another spec than the selected build.
local gearPane = CreateFrame("Frame", "BuildSpyGearPane", bui)
gearPane:SetWidth(440)
gearPane:SetHeight(30 + 26 + TAB_ROWS * ENTRY_H + 34)
gearPane:SetPoint("TOPLEFT", bui, "TOPRIGHT", 2, 0)
gearPane:Hide()
local gbg = gearPane:CreateTexture(nil, "BACKGROUND")
gbg:SetAllPoints() gbg:SetTexture(0.05, 0.04, 0.08, 0.95)
local gedges = {}
for i = 1, 4 do gedges[i] = gearPane:CreateTexture(nil, "BORDER") gedges[i]:SetTexture(0.4, 0.8, 1, 0.9) end
gedges[1]:SetPoint("TOPLEFT") gedges[1]:SetPoint("TOPRIGHT") gedges[1]:SetHeight(2)
gedges[2]:SetPoint("BOTTOMLEFT") gedges[2]:SetPoint("BOTTOMRIGHT") gedges[2]:SetHeight(2)
gedges[3]:SetPoint("TOPLEFT") gedges[3]:SetPoint("BOTTOMLEFT") gedges[3]:SetWidth(2)
gedges[4]:SetPoint("TOPRIGHT") gedges[4]:SetPoint("BOTTOMRIGHT") gedges[4]:SetWidth(2)
local gTitle = gearPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
gTitle:SetPoint("TOPLEFT", 10, -9)
local gStats = gearPane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
gStats:SetPoint("TOPLEFT", 262, -32)
gStats:SetWidth(168)
gStats:SetJustifyH("LEFT")
gStats:SetJustifyV("TOP")
local gearRows = {}
local function GearRow(i)
    local r = gearRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, gearPane)
    r:SetWidth(246) r:SetHeight(ENTRY_H)
    r:SetPoint("TOPLEFT", 10, -(30 + (i - 1) * ENTRY_H))
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetWidth(16) r.icon:SetHeight(16)
    r.icon:SetPoint("LEFT", 0, 0)
    r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 20, 0) r.name:SetWidth(226) r.name:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gearRows[i] = r
    return r
end

local function RefreshGear()
    if not gearPane:IsShown() then return end
    local rec = selTarget and DB().targets[selTarget]
    local g, gslot
    if rec and rec.gearBySpec then
        if rec.gearBySpec[selSlot] then
            g, gslot = rec.gearBySpec[selSlot], selSlot
        else
            for s, gg in pairs(rec.gearBySpec) do
                if (not gslot) or s == rec.activeSpec then g, gslot = gg, s end
            end
        end
    end
    local items = (g and g.items) or {}
    local slots = {}
    for s in pairs(items) do
        -- v6.0 (user): shirt (4) and tabard (19) are cosmetic -- hidden
        if s ~= 4 and s ~= 19 then slots[#slots + 1] = s end
    end
    table.sort(slots)
    for i = 1, 19 do
        local r = GearRow(i)
        local s = slots[i]
        local link = s and items[s]
        if link then
            r.link = link
            local name, _, _, _, _, _, _, _, _, tex = GetItemInfo(link)
            r.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            local raw = string.match(link, "|h%[(.-)%]|h") or name
                or string.match(link, "item:(%d+)") or "?"
            local color = string.match(link, "(|c%x%x%x%x%x%x%x%x)") or "|cffffffff"
            r.name:SetText(color .. raw .. "|r")
            r:Show()
        else
            r.link = nil
            r:Hide()
        end
    end
    -- total stats of the whole set (labels = the client's own ITEM_MOD_*
    -- globals, so they render in the client's language)
    local sums = {}
    for _, link in pairs(items) do
        local st = GetItemStats and GetItemStats(link)
        if st then
            for k, v in pairs(st) do sums[k] = (sums[k] or 0) + v end
        end
    end
    local list = {}
    for k, v in pairs(sums) do
        if v and v ~= 0 then
            list[#list + 1] = { l = tostring(_G[k] or k), v = v }
        end
    end
    table.sort(list, function(a, b) return a.v > b.v end)
    local lines = {}
    for _, e in ipairs(list) do
        lines[#lines + 1] = string.format("|cff40ff40%.0f|r %s", e.v, e.l)
    end
    gStats:SetText(#lines > 0 and table.concat(lines, "\n")
        or "|cff888888(no stats -- items not cached yet?)|r")
    gTitle:SetText("Gear -- " .. (selTarget or "?")
        .. (gslot and ("  |cffffd100spec " .. gslot .. "|r") or "  |cff888888(none captured)|r")
        .. ((gslot and selSlot and gslot ~= selSlot)
            and "  |cffff8800(captured on that spec)|r" or ""))
end
gearPane:SetScript("OnShow", RefreshGear)

local gearBtn = CreateFrame("Button", nil, bui, "UIPanelButtonTemplate")
gearBtn:SetWidth(84) gearBtn:SetHeight(18)
gearBtn:SetPoint("BOTTOMLEFT", 648, 6)
gearBtn:SetText("Show gear")
gearBtn:SetScript("OnClick", function()
    if gearPane:IsShown() then gearPane:Hide() else gearPane:Show() end
end)
gearBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Equipped items of the selected build (hover = full\ntooltip with enchants) + total stats of the set.", 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
gearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- selection changes repaint the gear pane too (shared RefreshAll upvalue --
-- every closure created earlier sees this reassignment)
local baseRefreshAll = RefreshAll
RefreshAll = function()
    baseRefreshAll()
    RefreshGear()
end

-- v6.1: live refresh on grab completion (see the forward at the top)
BuildsChanged = function()
    pathCache = {}   -- a re-grab may change a build's Path
    if bui:IsShown() then
        if selTarget then PrepareRows() SortRows() end
        RefreshAll()
    end
end

local function ToggleBuilds()
    if bui:IsShown() then bui:Hide() else bui:Show() end
end
_G.AscensionInspector_ShowBuilds = ToggleBuilds   -- consumed by the sad0 QoL hub

-- ======================== v3.5: REVEAL WATCHER (Wildcard) ========================
-- On the Wildcard realm, a spell roll/reroll ("Ability Revealed") goes
-- through the learn system message -> banner under the pentagon listing the
-- GRABBED BUILDS that use this spell (+ comments). No custom-UI frame is
-- touched: we listen to CHAT_MSG_SYSTEM with patterns derived from the
-- client's ERR_LEARN_* globals.
local rev = CreateFrame("Frame", "AscensionInspectorReveal", UIParent)
rev:SetWidth(720) rev:SetHeight(80)
rev:SetPoint("CENTER", 0, -200)
rev:SetFrameStrata("HIGH")
rev.text = rev:CreateFontString(nil, "OVERLAY")
rev.text:SetFont("Fonts/FRIZQT__.TTF", 15, "OUTLINE")
rev.text:SetPoint("TOP")
rev.text:SetWidth(710)
rev:Hide()
local revLeft = 0
rev:SetScript("OnUpdate", function(self, e)
    revLeft = revLeft - e
    if revLeft <= 0 then self:Hide() end
end)

local function UsersOfSpell(spellName)
    local out = {}
    for tname, rec in pairs(DB().targets) do
        for slot, hits in pairs(rec.caSpecs or {}) do
            for _, h in ipairs(hits) do
                if h.name == spellName then
                    local cm = rec.comments and rec.comments[slot]
                    out[#out + 1] = tname .. " [spec " .. slot .. "]"
                        .. (cm and (" |cff88ff88(" .. cm .. ")|r") or "")
                    break
                end
            end
        end
    end
    table.sort(out)
    return out
end

local function LearnPattern(g)
    if type(g) ~= "string" then return nil end
    g = string.gsub(g, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    g = string.gsub(g, "%%%%s", "(.+)")
    return "^" .. g .. "$"
end
local LEARN_PATTERNS = {}
for _, g in ipairs({ _G.ERR_LEARN_ABILITY_S, _G.ERR_LEARN_SPELL_S, _G.ERR_LEARN_PASSIVE_S }) do
    local p = LearnPattern(g)
    if p then LEARN_PATTERNS[#LEARN_PATTERNS + 1] = p end
end

local revEvt = CreateFrame("Frame")
revEvt:RegisterEvent("CHAT_MSG_SYSTEM")
revEvt:SetScript("OnEvent", function(_, _, msg)
    if type(msg) ~= "string" then return end
    for _, pat in ipairs(LEARN_PATTERNS) do
        local sp = string.match(msg, pat)
        if sp then
            local users = UsersOfSpell(sp)
            if #users == 0 then
                rev.text:SetText("|cffffd100" .. sp .. "|r: |cff888888no grabbed build uses it|r")
            else
                rev.text:SetText("|cffffd100" .. sp .. "|r  used by:\n|cff33ff99" .. table.concat(users, "   ") .. "|r")
            end
            revLeft = 12
            rev:Show()
            return
        end
    end
end)

-- ========================= DIAGNOSTIC =========================
local function DumpAPI()
    local db = DB()
    local api = { at = date("%Y-%m-%d %H:%M") }
    local function keysOf(t)
        local out = {}
        for k, v in pairs(t) do out[#out + 1] = tostring(k) .. " (" .. type(v) .. ")" end
        table.sort(out)
        return out
    end
    if _G.C_CharacterAdvancement then api.C_CharacterAdvancement = keysOf(_G.C_CharacterAdvancement) end
    if _G.SpecializationUtil then api.SpecializationUtil = keysOf(_G.SpecializationUtil) end
    local globs = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and string.find(k, "nspect") and (type(v) == "function" or type(v) == "table") then
            globs[#globs + 1] = k .. " (" .. type(v) .. ")"
        end
    end
    table.sort(globs)
    api.inspectGlobals = globs
    db.api = api
    Msg("API captured.  |cffaaaaaa/reload to write the file.|r")
end

local function Calibrate()
    local CA = _G.C_CharacterAdvancement
    if not CA then Msg("no C_CharacterAdvancement") return end
    local function show(d, ok, r)
        Msg("  " .. d .. " -> " .. (ok and tostring(r) or ("|cffff8800ERR " .. tostring(r) .. "|r")))
    end
    Msg("calibration (Templar roots 34372 Crusader / 31173 Oathkeeper):")
    show("GetTalentRankByID(34372)", pcall(CA.GetTalentRankByID, 34372))
    show("GetTalentRankByID(31173)", pcall(CA.GetTalentRankByID, 31173))
    for spec = 1, 5 do
        show('UnitTalentRankByID("player", 34372, ' .. spec .. ")", pcall(CA.UnitTalentRankByID, "player", 34372, spec))
    end
    if UnitExists("target") then
        Msg("  (probes on target, slots 1-5)")
        for spec = 1, 5 do
            show('UnitTalentRankByID("target", 34372, ' .. spec .. ")", pcall(CA.UnitTalentRankByID, "target", 34372, spec))
        end
    end
end

SLASH_ASCINSPECT1 = "/ains"
SlashCmdList["ASCINSPECT"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "api" then
        DumpAPI()
    elseif msg == "cal" then
        Calibrate()
    elseif msg == "list" then
        local n = 0
        for name, r in pairs(DB().targets) do
            n = n + 1
            local specs, gears = {}, {}
            for s, h in pairs(r.caSpecs or {}) do specs[#specs + 1] = s .. "(" .. #h .. ")" end
            -- v3.3/v3.4: stat order + Path + gear weapons, per spec
            for s, g in pairs(r.gearBySpec or {}) do
                local path = r.pathBySpec and r.pathBySpec[s]
                gears[#gears + 1] = s .. (path and (" " .. path) or "")
                    .. (g.statOrder and (" [" .. g.statOrder .. "]") or "")
                    .. (g.weapons and (" [" .. g.weapons .. "]") or "")
            end
            table.sort(gears)
            Msg("  " .. name .. " -- lvl " .. tostring(r.level) .. " " .. tostring(r.class and r.class[1])
                .. ", builds: " .. (next(specs) and table.concat(specs, " ") or "none")
                .. ", spec gear {" .. table.concat(gears, ",") .. "} (" .. tostring(r.at) .. ")")
        end
        if n == 0 then Msg("no capture yet -- Grab button (inspect window) or /ains on a target.") end
    elseif msg == "builds" then
        ToggleBuilds()
    elseif msg == "ui" then
        -- v3.2.1: capture the STRUCTURE of the inspection's Build tab
        -- (*Inspect*Build* globals, each frame's keys) -> plan C: scrape the
        -- UI list directly if the APIs stay silent. Run WITH the Build tab
        -- open and loaded, then /reload.
        local db = DB()
        local out = { at = date("%Y-%m-%d %H:%M"), names = {}, frames = {} }
        local nf = 0
        for k, v in pairs(_G) do
            if type(k) == "string" and string.find(k, "nspect") and string.find(k, "Build") then
                out.names[#out.names + 1] = k .. " (" .. type(v) .. ")"
                if type(v) == "table" and nf < 12 then
                    local keys = {}
                    for kk, vv in pairs(v) do
                        if type(kk) == "string" then keys[#keys + 1] = kk .. ":" .. type(vv) end
                    end
                    table.sort(keys)
                    nf = nf + 1
                    out.frames[k] = table.concat(keys, " ")
                end
            end
        end
        table.sort(out.names)
        db.buildUI = out
        Msg("Build UI captured (" .. #out.names .. " globals, " .. nf .. " frames detailed).  |cffaaaaaaBuild tab must be OPEN. /reload to write.|r")
    elseif msg == "self" then
        -- v3.0.1: pipeline CHECK -- captures MY own build (no inspection
        -- data required). If "self" finds my spells/talents but the target
        -- doesn't, the problem = server-side inspection transfer; if "self"
        -- finds nothing either = Hero entries don't answer
        -- UnitTalentRankByID (recalibrate via /ains api).
        StartCapture("player")
    elseif msg == "clear" then
        DB().targets = {}
        Msg("captures purged.")
    elseif string.find(msg, "^frames ") then
        -- v6.2.1: diagnostic -- list every live frame whose name contains
        -- the pattern (helps wiring OpenClientFrame on this client)
        local pat = string.match(msg, "^frames%s+(.+)$")
        if pat and _G.AscensionInspector_MatchFrames then
            _G.AscensionInspector_MatchFrames(pat)
        end
    else
        local u = InspectUnit()
        if not u then
            Msg("target a PLAYER (friendly preferred) or inspect them first.")
            return
        end
        if CanInspect and CanInspect(u) then pcall(NotifyInspect, u) end
        StartCapture(u)
    end
end

-- ========================= v5.0: minimap button + toggle =========================
-- Same pattern as WFSearch: draggable button around the minimap, shown by
-- default only when the sad0-QoL suite (whose hub has a launcher) is absent;
-- the "minimap button" checkbox in the builds window overrides either way
-- (DB().minimapShow).
local minimapBtn
local function MinimapWanted()
    local v = DB().minimapShow
    if v == nil then return not (IsAddOnLoaded and IsAddOnLoaded("sad0-QoL")) end
    return v and true or false
end

local mmToggle = CreateFrame("CheckButton", nil, bui, "UICheckButtonTemplate")
mmToggle:SetWidth(20) mmToggle:SetHeight(20)
mmToggle:SetPoint("BOTTOMRIGHT", -8, 4)
mmToggle:SetScript("OnClick", function(self)
    DB().minimapShow = self:GetChecked() and true or false
    if minimapBtn then
        if DB().minimapShow then minimapBtn:Show() else minimapBtn:Hide() end
    end
end)
local mmToggleL = bui:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
mmToggleL:SetPoint("RIGHT", mmToggle, "LEFT", 2, 0)
mmToggleL:SetText("minimap button")
bui:HookScript("OnShow", function() mmToggle:SetChecked(MinimapWanted()) end)

local function MakeMinimapButton()
    local btn = CreateFrame("Button", "BuildSpyMinimapButton", Minimap)
    btn:SetWidth(31) btn:SetHeight(31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53) overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20) icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\Ability_Spy")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 6, -6)
    local function Position()
        local a = DB().minimapAngle or 160
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER",
            80 * math.cos(math.rad(a)), 80 * math.sin(math.rad(a)))
    end
    btn:SetScript("OnDragStart", function(self) self.dragging = true end)
    btn:SetScript("OnDragStop", function(self) self.dragging = false end)
    btn:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local mx, my = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        DB().minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        Position()
    end)
    btn:SetScript("OnClick", ToggleBuilds)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("BuildSpy")
        GameTooltip:AddLine("Click: toggle the builds window (/ains builds)", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Position()
    minimapBtn = btn
end

local mmBoot = CreateFrame("Frame")
mmBoot:RegisterEvent("PLAYER_LOGIN")
mmBoot:SetScript("OnEvent", function()
    MakeMinimapButton()
    if not MinimapWanted() then minimapBtn:Hide() end
end)

EnsureButton()
Msg("loaded -- Grab button on the inspection window, /ains, /ains builds|self|list|clear|cal|api.")

