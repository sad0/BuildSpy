-- ============================================================================
-- SkillCardPlanner (BuildSpy public build) -- Skill Cards optimizer driven
-- by a grabbed build: priority = CARD RARITY, golden pools first, never a
-- duplicate, starters = the build's level-1 spells; placement verified slot
-- by slot via C_SkillCard.SetCardAtIndex (its return value is the verdict).
-- The development probes/spies of the private build are stripped here.
-- ============================================================================

local function P(t) DEFAULT_CHAT_FRAME:AddMessage("|cffcc99ffCardPlanner|r: " .. tostring(t)) end

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
