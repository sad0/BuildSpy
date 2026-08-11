-- ============================================================================
-- SkillCardPlanner v0.1 (2026-08-09) -- Skill Cards optimizer driven by a
-- grabbed build (user quiz decisions):
--   * priority = CARD RARITY (GetSkillCardQuality), golden first (the rarest
--     pool), then regular; NEVER a golden/regular duplicate;
--   * Starter Cards = the 4 rarest owned level-1 spells of the build;
--   * AUTOMATIC PLACEMENT via C_SkillCard.SetCardAtIndex + chat report,
--     verification after each placement.
-- STEP 0 (this file): the SIGNATURES of C_SkillCard/C_SkillCardCollection
-- are UNKNOWN (categories? golden flag? index spaces?) and SetCardAtIndex
-- can also REMOVE cards -- nothing is placed blind.
-- /ains cards = READ-ONLY PROBE: argument matrix over every reader, only
-- NON-NIL returns are kept, dump persisted in AscensionInspectorDB.cardprobe
-- (readable after /reload). Placement gets wired on the confirmed forms
-- (v0.2).
-- ============================================================================

local function P(t) DEFAULT_CHAT_FRAME:AddMessage("|cffcc99ffCardPlanner|r: " .. tostring(t)) end

local function Ser(v, depth)
	depth = depth or 0
	if type(v) ~= "table" then return tostring(v) end
	if depth >= 2 then return "table(...)" end
	local parts = {}
	for k, x in pairs(v) do
		parts[#parts + 1] = tostring(k) .. "=" .. Ser(x, depth + 1)
		if #parts >= 12 then parts[#parts + 1] = "..." break end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- v0.15: PROBE 2 (lessons of the v0.1 dump) -- GetSkillCardInfo(cardID)
-- works with 1 argument (full record), cards ENUMERATE by CardID; the SLOT
-- readers refuse numeric arguments and IsCardedID answers "SKILL_CARD_MAX"
-- -> categories are STRING ENUMS. Probe 2: (1) harvests every SKILL_CARD*
-- global, (2) enumerates CardIDs 1-3000 (quality/type stats, FULL record of
-- the 1st, list of PLACED cards via IsCardedID ~= false -- your placed cards
-- calibrate the returns), (3) replays the slot readers with the discovered
-- CONSTANTS as category.
local function SerFull(v)
	if type(v) ~= "table" then return tostring(v) end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function RunProbe2()
	AscensionInspectorDB = AscensionInspectorDB or {}
	local SC = _G.C_SkillCard
	if not (SC and SC.GetSkillCardInfo) then P("C_SkillCard missing.") return end
	local out = { at = date("%Y-%m-%d %H:%M"), consts = {}, cards = {}, carded = {}, slots = {} }
	-- 1) SKILL_CARD* constants
	local catCandidates = {}
	for k, v in pairs(_G) do
		if type(k) == "string" and string.find(k, "SKILL_CARD", 1, true)
			and (type(v) == "string" or type(v) == "number") then
			out.consts[#out.consts + 1] = k .. " = " .. tostring(v)
			catCandidates[#catCandidates + 1] = v
		end
	end
	table.sort(out.consts)
	-- 2) card enumeration
	local total, collected, byQ, byT = 0, 0, {}, {}
	local firstFull, firstCardedFull = nil, nil
	for id = 1, 3000 do
		local ok, info = pcall(SC.GetSkillCardInfo, id)
		if ok and type(info) == "table" then
			total = total + 1
			if info.IsCollected then collected = collected + 1 end
			byQ[tostring(info.Quality)] = (byQ[tostring(info.Quality)] or 0) + 1
			byT[tostring(info.Type)] = (byT[tostring(info.Type)] or 0) + 1
			if not firstFull then firstFull = "card " .. id .. " : " .. SerFull(info) end
			local okc, carded, a2, a3 = pcall(SC.IsCardedID, id)
			if okc and carded then
				local sn = info.SpellID and GetSpellInfo(info.SpellID) or "?"
				out.carded[#out.carded + 1] = "id=" .. id .. " spell=" .. tostring(sn)
					.. " -> IsCardedID = " .. tostring(carded) .. " | " .. tostring(a2) .. " | " .. tostring(a3)
				if not firstCardedFull then firstCardedFull = "CARDED card " .. id .. " : " .. SerFull(info) end
			end
		end
	end
	out.stats = "cards=" .. total .. " collected=" .. collected
	out.byQuality = SerFull(byQ)
	out.byType = SerFull(byT)
	out.firstCard = firstFull
	out.firstCarded = firstCardedFull
	-- 3) slot readers with the constants as category
	for _, cat in ipairs(catCandidates) do
		for _, fn in ipairs({ "GetMaxCardCount", "GetCardCount", "GetCardAtIndex",
			"GetCardID", "GetCardSpellID", "GetSkillCardInfoAtIndex", "IsCardAtIndexActive" }) do
			local f = SC[fn]
			if f then
				local ok, r1, r2 = pcall(f, cat)
				if ok and r1 ~= nil then
					out.slots[#out.slots + 1] = fn .. "(" .. tostring(cat) .. ") = "
						.. SerFull(r1) .. (r2 ~= nil and (" | " .. tostring(r2)) or "")
				end
				for idx = 1, 8 do
					local ok2, s1, s2 = pcall(f, cat, idx)
					if ok2 and s1 ~= nil then
						out.slots[#out.slots + 1] = fn .. "(" .. tostring(cat) .. "," .. idx .. ") = "
							.. SerFull(s1) .. (s2 ~= nil and (" | " .. tostring(s2)) or "")
					end
				end
			end
		end
	end
	table.sort(out.slots)
	AscensionInspectorDB.cardprobe2 = out
	P(total .. " cards enumerated (" .. collected .. " collected), " .. #out.carded
		.. " PLACED detected, " .. #out.slots .. " slot-reader returns -- |cffffd100/reload to write.|r")
end

-- argument matrix: likely categories (1-4), golden flag (bool/num), indices
-- 1-6 -- only the combinations that ANSWER are kept
local ARGSETS = {
	{}, { 1 }, { 2 }, { 3 }, { 4 },
	{ true }, { false },
	{ 1, true }, { 2, true }, { 3, true }, { 1, false }, { 2, false }, { 3, false },
	{ 1, 1 }, { 1, 2 }, { 1, 3 }, { 2, 1 }, { 2, 2 }, { 3, 1 }, { 3, 2 }, { 4, 1 },
	{ 1, 1, true }, { 1, 1, false }, { 2, 1, true }, { 2, 1, false }, { 3, 1, true },
	{ 1, true, 1 }, { 2, true, 1 }, { 3, true, 1 },
}

local READERS = {
	C_SkillCard = { "GetMaxCardCount", "GetCardCount", "GetCardAtIndex", "GetCardID",
		"GetCardSpellID", "GetCardRankAtIndex", "GetSkillCardInfo", "GetSkillCardInfoAtIndex",
		"GetSkillCardQuality", "IsCardAtIndexActive", "IsCardAtIndexBlocked",
		"IsCardedID", "IsCardedSpellID" },
	C_SkillCardCollection = { "GetNumSkillCards", "GetSkillCardAtIndex", "GetMaxRank",
		"HasAnySkillCardsCollected", "GetAppearanceTypes" },
}

local function ArgLabel(a)
	local s = {}
	for i = 1, #a do s[#s + 1] = tostring(a[i]) end
	return "(" .. table.concat(s, ",") .. ")"
end

local function RunProbe()
	AscensionInspectorDB = AscensionInspectorDB or {}
	local out = { at = date("%Y-%m-%d %H:%M"), hits = {} }
	local nCalls, nHits = 0, 0
	for ns, fns in pairs(READERS) do
		local T = _G[ns]
		if T then
			for _, fn in ipairs(fns) do
				local f = T[fn]
				if type(f) == "function" then
					for _, a in ipairs(ARGSETS) do
						nCalls = nCalls + 1
						local ok, r1, r2, r3, r4 = pcall(f, a[1], a[2], a[3])
						if ok and r1 ~= nil then
							nHits = nHits + 1
							out.hits[#out.hits + 1] = ns .. "." .. fn .. ArgLabel(a)
								.. " = " .. Ser(r1)
								.. (r2 ~= nil and (" | " .. Ser(r2)) or "")
								.. (r3 ~= nil and (" | " .. Ser(r3)) or "")
								.. (r4 ~= nil and (" | " .. Ser(r4)) or "")
						end
					end
				end
			end
		else
			out.hits[#out.hits + 1] = ns .. " : ABSENT"
		end
	end
	table.sort(out.hits)
	AscensionInspectorDB.cardprobe = out
	P(nHits .. " non-nil returns over " .. nCalls .. " calls -- |cffffd100dump written: do /reload|r"
		.. " (open the Skill Cards window FIRST if possible).")
end

-- v0.16: CALL SPY -- probe 2 did not crack the slot convention (placed cards
-- invisible to IsCardedID, constants = locale only, 61 cards over 1-3000 =
-- bigger ID space). Decisive method: WRAP every C_SkillCard /
-- C_SkillCardCollection function to LOG the calls the CLIENT'S OWN UI makes
-- when the user removes/replaces a card. /ains cardspy = toggle; each unique
-- "fn(args) -> returns" line is kept (400 max), dump
-- AscensionInspectorDB.cardspy on stop.
local spy = { active = false, log = {}, seen = {}, orig = {} }

local function pk(...) return { n = select("#", ...), ... } end
local function SerArgs(t, from, to)
	local parts = {}
	for i = from, to do
		local v = t[i]
		parts[#parts + 1] = (type(v) == "table") and SerFull(v) or tostring(v)
	end
	return table.concat(parts, ", ")
end

-- v1.2: the spy goes GENERIC (targets + dump key) -- reused for C_Wildcard
-- (Rapid Rolling push: 56/56 refused, yet another opaque CanAdd/verify -> we
-- listen to the UI checking a spell by hand)
local function SpyToggle(targets, dumpKey)
	AscensionInspectorDB = AscensionInspectorDB or {}
	if not spy.active then
		spy.log, spy.seen = {}, {}
		spy.dumpKey = dumpKey or "cardspy"
		local wrapped = 0
		for ns, T in pairs(targets) do
			if type(T) == "table" then
				for k, f in pairs(T) do
					if type(f) == "function" then
						local full = ns .. "." .. k
						spy.orig[full] = { t = T, k = k, f = f }
						local okSet = pcall(function()
							T[k] = function(...)
								local args = pk(...)
								local rets = pk(f(...))
								local line = full .. "(" .. SerArgs(args, 1, args.n) .. ") -> "
									.. SerArgs(rets, 1, rets.n)
								if not spy.seen[line] and #spy.log < 400 then
									spy.seen[line] = true
									spy.log[#spy.log + 1] = line
								end
								return unpack(rets, 1, rets.n)
							end
						end)
						if okSet then wrapped = wrapped + 1 else spy.orig[full] = nil end
					end
				end
			end
		end
		spy.active = true
		P("SPY ACTIVE (" .. wrapped .. " functions) -- REMOVE a card then PUT IT BACK in the window,"
			.. " switch tabs, then /ains cardspy to stop.")
	else
		for _, o in pairs(spy.orig) do pcall(function() o.t[o.k] = o.f end) end
		spy.orig = {}
		spy.active = false
		local key = spy.dumpKey or "cardspy"
		AscensionInspectorDB[key] = { at = date("%Y-%m-%d %H:%M"), calls = spy.log }
		table.sort(AscensionInspectorDB[key].calls)
		P(#spy.log .. " unique calls captured (" .. key .. ") -- |cffffd100/reload to write.|r")
	end
end

-- =============================================================================
-- v1.0: THE PLANNER (09/08 spy = full grammar confirmed on the user's real
-- manipulations):
--   categories (string enums): SKILL_CARD_STARTER_NORMAL/_GOLDEN (2 slots),
--   SKILL_CARD_DEFAULT_NORMAL/_GOLDEN (3, = Ability), SKILL_CARD_TALENT_
--   NORMAL/_GOLDEN (3); GetMaxCardCount(cat); GetSkillCardInfoAtIndex(cat,
--   idx); SetCardAtIndex(cat, idx, cardID) -> true; RemoveCardAtIndex(cat,
--   idx); collection: GetNumSkillCards(cat) + GetSkillCardAtIndex(cat, i)
--   (record: SpellID, Quality COMMON..LEGENDARY, IsCollected, IsStarterCard).
-- Algorithm (user quiz): SPELLID matching with the grabbed build; priority =
-- decreasing CARD quality (tiebreak: decreasing spell RequiredLevel -- later
-- = longer to wait at the roll); GOLDEN first then NORMAL without duplicate;
-- starters = the build's level-1 spells on IsStarterCard cards. Placement
-- verified slot by slot, report per category.
-- v1.4: quality keys normalized -- the collection's Quality comes as "COMMON"
-- or "SKILL_CARD_COMMON" depending on source (BuildSpy v5.2 measurement:
-- with the prefixed-only table every card sorted at 0)
local QORDER = { COMMON = 1, UNCOMMON = 2, RARE = 3, EPIC = 4, LEGENDARY = 5 }
local function QOrderOf(q)
	q = string.upper(tostring(q))
	q = string.gsub(q, "^SKILL_CARD_", "")
	return QORDER[q] or 0
end

-- v1.1: the matching key is THE CA ENTRY (internal ID), no longer the
-- spellID -- TALENT cards carry the spellID OF THEIR RANK (rank 3/5...)
-- while the build references rank 1: GetEntryBySpellID(cards) brings
-- everything back to the same identifier as the grabbed builds' hits.
-- "s<spellID>" fallback if resolution fails.
local function EntryKeyOfSpell(spellID)
	local CA = _G.C_CharacterAdvancement
	if CA and CA.GetEntryBySpellID then
		local ok, e = pcall(CA.GetEntryBySpellID, spellID)
		if ok and type(e) == "table" then
			local id = e.ID or e.Id or e.id or e.entryID or e.EntryID or e.internalID
			if id then return id end
		end
	end
	return "s" .. tostring(spellID)
end

-- collection indexed by CA entry key for a given pool TYPE
-- v1.4: SECOND index by base spell NAME (rank-independent) -- multi-rank
-- talents' card spellIDs do not always resolve to the build's CA entry
-- (BuildSpy v5.3 measurement: only single-rank talents matched)
-- v1.5: THIRD index by raw card spellID -- every RANK has its own CA entry
-- id, but the build entry's Spells table lists all rank spellIDs (pure-ID
-- bridge, measured in BuildSpy v5.4)
local function CollectPool(cat, wantStarter)
	local SC2 = _G.C_SkillCardCollection
	local pool = { p = {}, n = {}, s = {} }
	if not (SC2 and SC2.GetNumSkillCards and SC2.GetSkillCardAtIndex) then return pool end
	local ok, n = pcall(SC2.GetNumSkillCards, cat)
	if not ok or type(n) ~= "number" then return pool end
	for i = 1, n do
		local ok2, c = pcall(SC2.GetSkillCardAtIndex, cat, i)
		if ok2 and type(c) == "table" and c.IsCollected and c.SpellID
			and ((c.IsStarterCard and true or false) == wantStarter) then
			local card = { id = c.CardID, q = QOrderOf(c.Quality),
				quality = tostring(c.Quality), rank = c.CollectedRank or c.Rank or 1 }
			local key = EntryKeyOfSpell(c.SpellID)
			local prev = pool.p[key]
			if (not prev) or card.q > prev.q
				or (card.q == prev.q and (card.rank or 0) > (prev.rank or 0)) then
				pool.p[key] = card
			end
			local ps = pool.s[c.SpellID]
			if (not ps) or card.q > ps.q then pool.s[c.SpellID] = card end
			-- v1.5: CA name via BuildSpy's full spell index (GetSpellInfo
			-- can be mute on custom spell IDs)
			local sidx = _G.AscensionInspector_SpellIndex and _G.AscensionInspector_SpellIndex()
			local sn = (sidx and sidx[c.SpellID] and sidx[c.SpellID].name)
				or GetSpellInfo(c.SpellID)
			if sn then
				local nk = string.lower(sn)
				local pn = pool.n[nk]
				if (not pn) or card.q > pn.q then pool.n[nk] = card end
			end
		end
	end
	return pool
end

-- places the PLAN (sorted list of {spellID, card, name}) into category cat
local function FillCategory(cat, plan, report)
	local SC = _G.C_SkillCard
	local okM, max = pcall(SC.GetMaxCardCount, cat)
	if not okM or type(max) ~= "number" or max <= 0 then return end
	-- current slot state
	local current = {}   -- [idx] = cardID or nil
	local planned = {}   -- cardID -> true (from the plan)
	for i = 1, math.min(#plan, max) do planned[plan[i].card.id] = true end
	for idx = 1, max do
		local ok, c = pcall(SC.GetSkillCardInfoAtIndex, cat, idx)
		current[idx] = (ok and type(c) == "table") and c.CardID or nil
	end
	-- 1) slots ALREADY holding a card from the plan are kept
	local have = {}
	for idx = 1, max do
		if current[idx] and planned[current[idx]] then have[current[idx]] = true end
	end
	-- 2) place the rest of the plan into the remaining slots
	-- v1.1: placement is a SERVER ROUND-TRIP (measured: all 10 "refused"
	-- were actually PLACED on screen) -> the verdict is SetCardAtIndex's
	-- RETURN VALUE (true = accepted, as the spy showed), never a same-frame
	-- re-read again.
	local pi = 1
	for idx = 1, max do
		if not (current[idx] and planned[current[idx]]) then
			-- advance to the next plan card not in place yet
			while pi <= math.min(#plan, max) and have[plan[pi].card.id] do pi = pi + 1 end
			local want = (pi <= math.min(#plan, max)) and plan[pi] or nil
			if want then
				if current[idx] then pcall(SC.RemoveCardAtIndex, cat, idx) end
				local okS, accepted = pcall(SC.SetCardAtIndex, cat, idx, want.card.id)
				if okS and accepted then
					report.set = report.set + 1
					have[want.card.id] = true
				else
					report.fail[#report.fail + 1] = want.name .. " (" .. cat .. ")"
				end
				pi = pi + 1
			end
		else
			report.kept = report.kept + 1
		end
	end
end

local function PlanBuildCards(hits)
	local SC = _G.C_SkillCard
	if not (SC and SC.SetCardAtIndex) then P("C_SkillCard missing.") return end
	local CA = _G.C_CharacterAdvancement
	if not (CA and CA.GetEntryByInternalID) then P("C_CharacterAdvancement missing.") return end
	-- 1) build -> lists of {key = CA entry, reqLevel, name}
	local abilities, talents, starters = {}, {}, {}
	for _, h in ipairs(hits) do
		local ok, e = pcall(CA.GetEntryByInternalID, h.id)
		if ok and type(e) == "table" then
			local ent = { key = h.id, req = e.RequiredLevel or 0,
				name = e.Name or ("entry " .. h.id),
				spells = (type(e.Spells) == "table") and e.Spells or nil }
			if e.Type == "Talent" then talents[#talents + 1] = ent
			else
				abilities[#abilities + 1] = ent
				if ent.req <= 1 then starters[#starters + 1] = ent end
			end
		end
	end
	-- 2) collection pools (6: starter/ability/talent x golden/normal)
	local pools = {
		startG = CollectPool("SKILL_CARD_DEFAULT_GOLDEN", true),
		startN = CollectPool("SKILL_CARD_DEFAULT_NORMAL", true),
		abilG = CollectPool("SKILL_CARD_DEFAULT_GOLDEN", false),
		abilN = CollectPool("SKILL_CARD_DEFAULT_NORMAL", false),
		talG = CollectPool("SKILL_CARD_TALENT_GOLDEN", false),
		talN = CollectPool("SKILL_CARD_TALENT_NORMAL", false),
	}
	-- 3) v1.1: GLOBAL DEDUPLICATION (measured bug: Blood Presence placed as
	-- golden ability THEN re-tried as starter -> server refusal). Order:
	-- STARTERS first (a level-1 guarantee beats an "over the rolls" one),
	-- then abilities, then talents -- each category excludes everything
	-- already covered (shared `covered` set, key = CA entry).
	local covered = {}
	local report = { set = 0, kept = 0, fail = {} }
	local function MakePlan(list, pool)
		local plan = {}
		for _, ent in ipairs(list) do
			-- v1.5: entry match, then EVERY rank's spellID (pure IDs), then
			-- base-name as last resort
			local card = pool.p[ent.key]
			if not card and ent.spells then
				for _, s in ipairs(ent.spells) do
					local c2 = pool.s[s]
					if c2 and ((not card) or c2.q > card.q) then card = c2 end
				end
			end
			card = card or pool.n[string.lower(ent.name or "")]
			if card and not covered[ent.key] then
				plan[#plan + 1] = { key = ent.key, card = card, name = ent.name, req = ent.req }
			end
		end
		table.sort(plan, function(a, b)
			if a.card.q ~= b.card.q then return a.card.q > b.card.q end
			if a.req ~= b.req then return a.req > b.req end
			return a.name < b.name
		end)
		return plan
	end
	local function Apply(cat, list, pool, max)
		local plan = MakePlan(list, pool)
		FillCategory(cat, plan, report)
		for i = 1, math.min(#plan, max) do covered[plan[i].key] = true end
	end
	Apply("SKILL_CARD_STARTER_GOLDEN", starters, pools.startG, 2)
	Apply("SKILL_CARD_STARTER_NORMAL", starters, pools.startN, 2)
	Apply("SKILL_CARD_DEFAULT_GOLDEN", abilities, pools.abilG, 3)
	Apply("SKILL_CARD_DEFAULT_NORMAL", abilities, pools.abilN, 3)
	Apply("SKILL_CARD_TALENT_GOLDEN", talents, pools.talG, 3)
	Apply("SKILL_CARD_TALENT_NORMAL", talents, pools.talN, 3)
	P("Skill Cards: |cff40ff40" .. report.set .. " placed|r"
		.. (report.kept > 0 and ("  " .. report.kept .. " already in place") or "")
		.. (#report.fail > 0 and ("  |cffff8800" .. #report.fail .. " refused: "
			.. table.concat(report.fail, ", ") .. "|r") or ""))
end

_G.AscensionInspector_CardPlan = PlanBuildCards   -- consumed by the builds button

-- exposed for AscensionInspector.lua's /ains slash (loaded before us)
-- v0.15: /ains cards = probe 2 (auto-calibrated on the placed cards)
_G.AscensionInspector_CardProbe = RunProbe2
_G.AscensionInspector_CardProbe1 = RunProbe   -- the old matrix, if needed
_G.AscensionInspector_CardSpy = function()
	SpyToggle({ C_SkillCard = _G.C_SkillCard, C_SkillCardCollection = _G.C_SkillCardCollection }, "cardspy")
end
-- v1.2: /ains rollspy -- spies on C_Wildcard while the user checks ONE spell
-- in "Desired Spells" by hand (and unchecks one): the capture yields
-- AddDesiredID/RemoveDesiredID with their real IDs and returns
-- v1.3 (RollPilot project -- full auto-reroll): targets WIDENED to the roll
-- cycle namespaces (rewards + draft) -- to activate DURING a full manual
-- cycle: Roll 5 Scrolls, then one "Keep Abilities" AND one "Roll Abilities"
-- on the top reveal bar.
_G.AscensionInspector_RollSpy = function()
	SpyToggle({
		C_Wildcard = _G.C_Wildcard,
		C_WildcardRewards = _G.C_WildcardRewards,
		C_BuildDraft = _G.C_BuildDraft,
		C_DraftRewards = _G.C_DraftRewards,
	}, "rollspy")
end
