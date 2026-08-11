-- BuildSpy -- Build Planer (v3.0, 11/08)
-- ---------------------------------------------------------------------------
-- Plan a Character Advancement build: the window is a FAITHFUL COPY of the
-- Character Advancement tab, geometry lifted from the client's own XML
-- (E:\Ascension\MPQ\Interface\AddOns\Ascension_CharacterAdvancement) :
--   * frame 1165x758, anchored BOTTOM+8 inside Collections (their panels' way)
--   * far left  : class column x4..128 (CAClassButtonTemplate:SetClass)
--   * middle    : the ca-background BOOK 802x536 -- left page = the plan's
--                 ABILITIES (Ability Essence header), right page = the plan's
--                 TALENTS (Talent Essence header) ; click a row to REMOVE
--   * far right : 198px browser column (Path picker, SearchBoxTemplate
--                 searching NAME + TOOLTIP, filters, entry list) ; click = ADD
--   * footer    : build name + Export to BuildSpy + Clear on the dark strip
-- Real Collections tab via TabSystem (Collections:AddTab). All client
-- templates pcall-guarded with plain fallbacks. /ains plan toggles.
-- ---------------------------------------------------------------------------

local function PDB()
    AscensionInspectorDB = AscensionInspectorDB or {}
    local db = AscensionInspectorDB
    db.planner = db.planner or { picks = {}, path = nil, name = "My Plan" }
    return db.planner
end

local function Msg(t) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffBuild Planer|r: " .. t) end

-- ===================== data =====================
local QUALC = {
    poor = "9d9d9d", common = "ffffff", uncommon = "1eff00", rare = "0070dd",
    epic = "a335ee", legendary = "ff8000", artifact = "e6cc80",
}
local PATHS = {
    { tok = "strength",  ca = 1149,  sp = 84864,  name = "Strength" },
    { tok = "agility",   ca = 1150,  sp = 84865,  name = "Agility" },
    { tok = "intellect", ca = 1151,  sp = 84866,  name = "Intelligence" },
    { tok = "healing",   ca = 1152,  sp = 84867,  name = "Healing" },
    { tok = "duality",   ca = 18149, sp = 129243, name = "Duality" },
}
-- essence budgets AT LEVEL 60 (quiz user) : ability 60 (cost 2), talent 25 (cost 1)
local ABILITY_TOTAL, ABILITY_COST = 60, 2
local TALENT_TOTAL, TALENT_COST = 25, 1

-- only the classes the CA window shows (10 WoW + Hero = the CoA-origin pool)
local CLASS_ORDER = {
    { "DeathKnight", "Death Knight" }, { "Druid", "Druid" }, { "Hunter", "Hunter" },
    { "Mage", "Mage" }, { "Paladin", "Paladin" }, { "Priest", "Priest" },
    { "Rogue", "Rogue" }, { "Shaman", "Shaman" }, { "Warlock", "Warlock" },
    { "Warrior", "Warrior" }, { "Hero", "Hero" },
}
local CLASS_OK = {}
for _, c in ipairs(CLASS_ORDER) do CLASS_OK[c[1]] = c[2] end

local entries = nil
local byId = {}
local function BuildEntries()
    if entries then return entries end
    local CA = _G.C_CharacterAdvancement
    if not (CA and CA.GetAllEntries and CA.GetEntryByInternalID) then
        Msg("|cffff4040C_CharacterAdvancement missing -- planner unavailable.|r")
        return nil
    end
    local ok, r = pcall(CA.GetAllEntries)
    if not (ok and type(r) == "table") then
        Msg("|cffff4040GetAllEntries empty.|r")
        return nil
    end
    local ids, seen = {}, {}
    for k, v in pairs(r) do
        local id
        if type(v) == "number" then id = v
        elseif type(v) == "table" then
            id = v.ID or v.Id or v.id or v.entryID or v.EntryID or v.internalID
                or (type(k) == "number" and k or nil)
        elseif type(k) == "number" then id = k end
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local raw = {}
    for _, id in ipairs(ids) do
        local ok2, e = pcall(CA.GetEntryByInternalID, id)
        if ok2 and type(e) == "table" and (e.Name or e.name) then
            if not AscensionInspectorDB.plannerEntrySample then
                local smp = {}
                for k, v in pairs(e) do smp[tostring(k)] = type(v) .. "=" .. string.sub(tostring(v), 1, 40) end
                AscensionInspectorDB.plannerEntrySample = smp
            end
            local sid, nranks
            if type(e.Spells) == "table" then
                sid = e.Spells[#e.Spells] or e.Spells[1]
                nranks = #e.Spells
            end
            local q = e.Quality and string.lower(tostring(e.Quality)) or nil
            -- couleur = rarete des SKILL CARDS (quiz), repli qualite CA
            local qhex = (q and QUALC[q]) or "ffffff"
            if _G.BuildSpy_CardQual then
                local okq, cq = pcall(_G.BuildSpy_CardQual, id, e.Name or e.name, e.Spells)
                if okq and type(cq) == "table" and cq[3] then qhex = cq[3] end
            end
            local cls = e.Class or e.ClassName or e.className or e.class
            if type(cls) ~= "string" or CLASS_OK[cls] then
                raw[#raw + 1] = {
                    id = id,
                    name = e.Name or e.name,
                    typ = (e.Type == "Talent") and "Talent" or "Ability",
                    lvl = e.RequiredLevel or 0,
                    qhex = qhex,
                    icon = (sid and select(3, GetSpellInfo(sid))) or "Interface\\Icons\\INV_Misc_QuestionMark",
                    sid = sid,
                    nranks = nranks or 0,
                    cls = type(cls) == "string" and cls or nil,
                }
            end
        end
    end
    -- chaque RANG = une entree CA -> collapse par nom+type+classe, entree maxxee
    local best = {}
    for _, e in ipairs(raw) do
        local key = e.name .. "|" .. e.typ .. "|" .. tostring(e.cls)
        local b = best[key]
        if not b or e.nranks > b.nranks or (e.nranks == b.nranks and e.id > b.id) then
            best[key] = e
        end
    end
    entries = {}
    for _, e in pairs(best) do entries[#entries + 1] = e end
    table.sort(entries, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    for _, e in ipairs(entries) do byId[e.id] = e end
    Msg(#entries .. " CA entries loaded.")
    return entries
end

local function IsKnownEntry(e)
    local CA = _G.C_CharacterAdvancement
    if CA and CA.GetTalentRankByID then
        local ok, rv = pcall(CA.GetTalentRankByID, e.id)
        if ok and tonumber(rv) and tonumber(rv) > 0 then return true end
    end
    if e.sid and IsSpellKnown then
        local ok, k = pcall(IsSpellKnown, e.sid)
        if ok and k then return true end
    end
    return false
end

-- ===================== tooltip search cache =====================
local tipCache, tipBuilt = {}, 0
local scanTip = CreateFrame("GameTooltip", "BuildPlannerScanTip", nil, "GameTooltipTemplate")
local function TipText(e)
    local hit = tipCache[e.id]
    if hit ~= nil then return hit end
    if not e.sid then tipCache[e.id] = false tipBuilt = tipBuilt + 1 return false end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    local ok = pcall(scanTip.SetHyperlink, scanTip, "spell:" .. e.sid)
    if not ok then tipCache[e.id] = false tipBuilt = tipBuilt + 1 return false end
    local parts = {}
    for i = 1, scanTip:NumLines() do
        for _, side in ipairs({ "BuildPlannerScanTipTextLeft", "BuildPlannerScanTipTextRight" }) do
            local fs = _G[side .. i]
            local t = fs and fs:GetText()
            if t and t ~= "" then parts[#parts + 1] = t end
        end
    end
    local s = string.lower(table.concat(parts, " "))
    tipCache[e.id] = s
    tipBuilt = tipBuilt + 1
    return s
end

-- ===================== window (geometrie EXACTE du CA) =====================
local ui, themed
do
    local ok, f = pcall(CreateFrame, "Frame", "BuildPlannerFrame", UIParent, "RaisedPortraitFrameTemplate")
    if ok and f then ui, themed = f, true
    else ui = CreateFrame("Frame", "BuildPlannerFrame", UIParent) end
end
ui:SetWidth(1165) ui:SetHeight(758)          -- <Size x="1165" y="758"/> du CA
ui:SetPoint("CENTER", 0, 0)                  -- standalone ; re-ancre dans Collections au tab
ui:SetFrameStrata("HIGH")
ui:SetMovable(true) ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart", function(self) if not self.docked then self:StartMoving() end end)
ui:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
ui:Hide()
tinsert(UISpecialFrames, "BuildPlannerFrame")
if themed then
    pcall(function() PortraitFrame_SetIcon(ui, "Interface\\Icons\\Ability_Spy") end)
    pcall(function() PortraitFrame_SetTitle(ui, "Build Planer") end)
end

local ATLAS_FLAG = (Const and Const.TextureKit and Const.TextureKit.UseAtlasSize)
local function TrySetAtlas(tex, name)
    if _G.AtlasUtil and AtlasUtil.AtlasExists then
        local okE, ex = pcall(AtlasUtil.AtlasExists, AtlasUtil, name)
        if okE and not ex then return false end
    end
    local ok = pcall(tex.SetAtlas, tex, name, ATLAS_FLAG)
    return ok and tex:GetTexture() and true or false
end

-- fallback chrome (sans template portrait)
if not themed then
    local bg = ui:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetTexture(0.08, 0.06, 0.05, 0.97)
    local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 40, -12)
    title:SetText("|cffffd100Build Planer|r")
    local close = CreateFrame("Button", nil, ui, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
end

-- --- colonne CLASSES (Navigation2 du CA : TOPLEFT 4,-68 -> BOTTOMLEFT+128,6) ---
local nav = CreateFrame("Frame", nil, ui)
nav:SetPoint("TOPLEFT", 4, -68)
nav:SetPoint("BOTTOMLEFT", 4, 6)
nav:SetWidth(124)

-- --- CONTENT = le LIVRE (802x536, a droite de la colonne classes) ---
local content = CreateFrame("Frame", nil, ui)
content:SetPoint("TOPLEFT", 128, -68)
content:SetWidth(802) content:SetHeight(536)
local book = content:CreateTexture(nil, "BACKGROUND")
book:SetAllPoints()
if not TrySetAtlas(book, "ca-background") then
    book:SetTexture("Interface\\QuestFrame\\QuestBG")
    book:SetTexCoord(0, 0.58, 0, 0.6)
end

-- --- SIDEBAR droite (198px : Path + recherche + filtres + browser) ---
local rightBar = CreateFrame("Frame", nil, ui)
rightBar:SetPoint("TOPLEFT", content, "TOPRIGHT", 1, 10)
rightBar:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", -6, 40)
local rbBg = rightBar:CreateTexture(nil, "BACKGROUND")
rbBg:SetAllPoints()
rbBg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble")
pcall(function() rbBg:SetHorizTile(true) rbBg:SetVertTile(true) end)

-- calque de LIBELLES au-dessus des fonds (les regions du parent dessinent SOUS
-- ses enfants -- lecon v2.2)
local lbl = CreateFrame("Frame", nil, ui)
lbl:SetAllPoints()

-- headers d'essence, composants du CA (FontString Medium + icone BorderIcon)
local function MakeEssenceHeader(xCenter, iconPath)
    local fs
    local okF = pcall(function() fs = lbl:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium") end)
    if not (okF and fs) then fs = lbl:CreateFontString(nil, "OVERLAY", "GameFontNormal") end
    fs:SetPoint("TOP", content, "TOPLEFT", xCenter, -14)
    local b
    local okB = pcall(function() b = CreateFrame("Button", nil, lbl, "BorderIconTemplate") end)
    if okB and b then
        b:SetWidth(18) b:SetHeight(18)
        b:SetPoint("RIGHT", fs, "LEFT", -6, 0)
        pcall(function()
            MixinAndLoadScripts(b, "BorderIconTemplateMixin")
            b:SetRounded(true)
            b:SetIcon(iconPath)
            b:SetBorderAtlas("pta-icon-border")
            b:SetBorderSize(30, 30)
            b.IconBorder:SetDesaturated(true)
        end)
    end
    return fs
end
local essA = MakeEssenceHeader(200, "Interface\\Icons\\inv_custom_abilityessence")
local essT = MakeEssenceHeader(602, "Interface\\Icons\\inv_custom_Talentessence")

local function EssenceLeft()
    local pl = PDB()
    local a, t = ABILITY_TOTAL, TALENT_TOTAL
    for _, id in ipairs(pl.picks) do
        local e = byId[id]
        if e then
            if e.typ == "Talent" then t = t - TALENT_COST else a = a - ABILITY_COST end
        end
    end
    return a, t
end

-- ===================== filtres / recherche (sidebar droite) =====================
local fType, fKnown = "All", "All"
local fClass = nil
local browserOff, filtered = 0, {}
local RefreshAll

-- Path picker en tete de sidebar (le CA affiche le Path en haut de SA sidebar)
local pathLbl = lbl:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pathLbl:SetPoint("TOPLEFT", rightBar, "TOPLEFT", 10, -10)
pathLbl:SetText("|cffffd100Path|r")
local pathBtns = {}
for i, p in ipairs(PATHS) do
    local b = CreateFrame("Button", nil, rightBar)
    b:SetWidth(28) b:SetHeight(28)
    b:SetPoint("TOPLEFT", rightBar, "TOPLEFT", 8 + (i - 1) * 36, -26)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetTexture(select(3, GetSpellInfo(p.sp)) or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetPoint("TOPLEFT", -2, 2) b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    b.ring:SetTexture(1, 0.85, 0.2, 0.9)
    b.ring:Hide()
    b:SetScript("OnClick", function()
        local pl = PDB()
        pl.path = (pl.path == p.tok) and nil or p.tok
        RefreshAll()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Path of " .. p.name, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pathBtns[i] = b
end

-- SearchBoxTemplate (loupe + placeholder), sous le Path
local search
do
    local ok
    ok, search = pcall(CreateFrame, "EditBox", "BuildPlannerSearch", rightBar, "SearchBoxTemplate")
    if not (ok and search) then
        search = CreateFrame("EditBox", "BuildPlannerSearch", rightBar, "InputBoxTemplate")
    end
end
search:SetWidth(170) search:SetHeight(20)
search:SetPoint("TOPLEFT", rightBar, "TOPLEFT", 16, -64)
search:SetAutoFocus(false)
pcall(function() search.Instructions:SetText("Search name + tooltip") end)

local typeBtn = CreateFrame("Button", nil, rightBar, "UIPanelButtonTemplate")
typeBtn:SetWidth(88) typeBtn:SetHeight(19)
typeBtn:SetPoint("TOPLEFT", rightBar, "TOPLEFT", 8, -88)
local knownBtn = CreateFrame("Button", nil, rightBar, "UIPanelButtonTemplate")
knownBtn:SetWidth(88) knownBtn:SetHeight(19)
knownBtn:SetPoint("LEFT", typeBtn, "RIGHT", 4, 0)
local function FilterCaptions()
    typeBtn:SetText(fType)
    knownBtn:SetText(fKnown)
end

local function MatchesFilters(e, needle)
    if fClass and e.cls ~= fClass then return false end
    if fType ~= "All" and e.typ ~= fType then return false end
    if fKnown ~= "All" then
        local k = IsKnownEntry(e)
        if fKnown == "Known" and not k then return false end
        if fKnown == "Unknown" and k then return false end
    end
    if needle and needle ~= "" then
        if string.find(string.lower(e.name), needle, 1, true) then return true end
        local tip = TipText(e)
        if tip and string.find(tip, needle, 1, true) then return true end
        return false
    end
    return true
end

local function Refilter()
    filtered = {}
    if not entries then return end
    local needle = string.lower(search:GetText() or "")
    if needle == "" or needle == "search name + tooltip" then needle = nil end
    for _, e in ipairs(entries) do
        if MatchesFilters(e, needle) then filtered[#filtered + 1] = e end
    end
    browserOff = 0
end

typeBtn:SetScript("OnClick", function()
    fType = (fType == "All" and "Ability") or (fType == "Ability" and "Talent") or "All"
    FilterCaptions() Refilter() RefreshAll()
end)
knownBtn:SetScript("OnClick", function()
    fKnown = (fKnown == "All" and "Known") or (fKnown == "Known" and "Unknown") or "All"
    FilterCaptions() Refilter() RefreshAll()
end)
search:SetScript("OnTextChanged", function(self, user)
    pcall(SearchBoxTemplate_OnTextChanged, self)
    if user then Refilter() RefreshAll() end
end)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- ===================== colonne classes (vrais boutons du CA) =====================
local classBtns, classList
local RenderSidebar
local function MakeSideButton(i)
    local b
    local ok = pcall(function()
        b = CreateFrame("Button", nil, nav, "CAClassButtonTemplate")
    end)
    if not (ok and b and b.SetClass) then
        b = CreateFrame("Button", nil, nav)
        b.plain = true
        b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.txt:SetPoint("LEFT", 8, 0)
        b.txt:SetPoint("RIGHT", -2, 0)
        b.txt:SetJustifyH("LEFT")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture(1, 0.85, 0.4, 0.12)
    else
        b:SetScale(0.92)
    end
    b:SetWidth(128) b:SetHeight(44)
    b:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, -((i - 1) * 46))
    b:SetScript("OnClick", function(self)
        fClass = self.cls
        Refilter() RefreshAll() RenderSidebar()
    end)
    return b
end
RenderSidebar = function()
    if not (classBtns and classList) then return end
    for i, b in ipairs(classBtns) do
        local c = classList[i]
        local sel = (fClass == nil and c == "All") or (fClass ~= nil and fClass == b.cls)
        if b.plain then
            if b.txt then
                local col = sel and "|cff4dff80" or "|cffffd100"
                b.txt:SetText(col .. (CLASS_OK[c] or c) .. "|r")
            end
        else
            pcall(function()
                if sel then b.Overlay:Show() else b.Overlay:Hide() end
            end)
        end
    end
end
local function BuildSidebar()
    if classList then return end
    if not entries then return end
    local have = {}
    for _, e in ipairs(entries) do if e.cls then have[e.cls] = true end end
    local list = { "All" }
    for _, c in ipairs(CLASS_ORDER) do
        if have[c[1]] then list[#list + 1] = c[1] end
    end
    classList = list
    classBtns = {}
    for i, c in ipairs(list) do
        local b = MakeSideButton(i)
        b.cls = (c ~= "All") and c or nil
        if not b.plain then
            local okC = (c ~= "All") and pcall(b.SetClass, b, string.upper(c))
            if not okC then
                pcall(function() b.Icon:Hide() end)
                b:SetText(CLASS_OK[c] or c)
            end
        end
        classBtns[i] = b
    end
    RenderSidebar()
end

-- ===================== lignes (composants exacts du CA) =====================
-- icone SpellIconTemplate (SetSpell + useQuality = bordure a la qualite) sur
-- la banniere d'ombre "spellbook-text-background" (le Shadow de leurs lignes)
local function MakeRow(relTo, i, x, y0, w)
    local r = CreateFrame("Button", nil, relTo)
    r:SetWidth(w) r:SetHeight(26)
    r:SetPoint("TOPLEFT", relTo, "TOPLEFT", x, -(y0 + (i - 1) * 27))
    r.shadow = r:CreateTexture(nil, "BACKGROUND")
    r.shadow:SetPoint("LEFT", 14, 0)
    r.shadow:SetPoint("RIGHT", -2, 0)
    r.shadow:SetHeight(32)
    local okS = pcall(r.shadow.SetAtlas, r.shadow, "spellbook-text-background")
    if not (okS and r.shadow:GetTexture()) then r.shadow:SetTexture(0, 0, 0, 0.22) end
    local ib
    pcall(function() ib = CreateFrame("Button", nil, r, "SpellIconTemplate") end)
    if ib and ib.SetSpell then
        ib:SetWidth(24) ib:SetHeight(24)
        ib:SetPoint("LEFT", 2, 0)
        ib:EnableMouse(false)
        ib.useQuality = true
        r.ib = ib
    else
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetWidth(22) r.icon:SetHeight(22)
        r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    r.txt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.txt:SetPoint("LEFT", 32, 0)
    r.txt:SetPoint("RIGHT", -2, 0)
    r.txt:SetJustifyH("LEFT")
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetTexture(1, 0.85, 0.4, 0.12)
    r:SetScript("OnEnter", function(self)
        if self.entry and self.entry.sid then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink("spell:" .. self.entry.sid)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    return r
end
local function SetRowIcon(r, e)
    if r.ib then
        pcall(r.ib.SetSpell, r.ib, e.sid or 0)
    elseif r.icon then
        r.icon:SetTexture(e.icon)
    end
end

-- browser (sidebar droite) : 16 lignes etroites sous les filtres
local B_ROWS = 16
local browserRows = {}
for i = 1, B_ROWS do
    local r = MakeRow(rightBar, i, 4, 116, 188)
    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        local pl = PDB()
        for _, id in ipairs(pl.picks) do if id == e.id then Msg(e.name .. " is already in the plan.") return end end
        local a, t = EssenceLeft()
        if e.typ == "Talent" then
            if t - TALENT_COST < 0 then
                Msg("|cffff4040talent essence exhausted|r (" .. TALENT_TOTAL .. " at 60).")
                return
            end
        elseif a - ABILITY_COST < 0 then
            Msg("|cffff4040ability essence exhausted|r (" .. ABILITY_TOTAL .. " at 60).")
            return
        end
        pl.picks[#pl.picks + 1] = e.id
        RefreshAll()
    end)
    browserRows[i] = r
end
rightBar:EnableMouseWheel(true)
rightBar:SetScript("OnMouseWheel", function(_, delta)
    local maxOff = math.max(0, #filtered - B_ROWS)
    browserOff = math.min(maxOff, math.max(0, browserOff - delta * 3))
    RefreshAll()
end)

-- plan : ABILITIES page gauche, TALENTS page droite (15 lignes chacune)
local P_ROWS = 15
local planARows, planTRows = {}, {}
local function MakePlanRow(store, i, x)
    local r = MakeRow(content, i, x, 56, 350)
    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        local pl = PDB()
        for k, id in ipairs(pl.picks) do
            if id == e.id then table.remove(pl.picks, k) break end
        end
        RefreshAll()
    end)
    store[i] = r
end
for i = 1, P_ROWS do MakePlanRow(planARows, i, 28) end
for i = 1, P_ROWS do MakePlanRow(planTRows, i, 428) end

-- ===================== footer =====================
local tipNote = lbl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tipNote:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", 140, 16)
local nameLbl = lbl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
local nameBox = CreateFrame("EditBox", "BuildPlannerName", ui, "InputBoxTemplate")
nameBox:SetWidth(180) nameBox:SetHeight(20)
nameBox:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", -330, 14)
nameBox:SetAutoFocus(false)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
nameBox:SetScript("OnTextChanged", function(self, user)
    if user then PDB().name = self:GetText() end
end)
nameLbl:SetPoint("RIGHT", nameBox, "LEFT", -8, 0)
nameLbl:SetText("build name")
local exportBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
exportBtn:SetWidth(150) exportBtn:SetHeight(22)
exportBtn:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
exportBtn:SetText("Export to BuildSpy")
exportBtn:SetScript("OnClick", function()
    local pl = PDB()
    if #pl.picks == 0 then Msg("plan is empty -- click entries in the right column.") return end
    if not _G.BuildSpy_StoreBuild then Msg("|cffff4040BuildSpy store missing.|r") return end
    local name = (pl.name and pl.name ~= "") and pl.name or "My Plan"
    local a, t = EssenceLeft()
    _G.BuildSpy_StoreBuild(name, pl.path or "", pl.picks, "")
    Msg("plan |cffffd100" .. name .. "|r exported -- open /ains builds."
        .. ((a < 0 or t < 0) and "  |cffff4040(OVER the level-60 essence budget!)|r" or ""))
end)
local clearBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
clearBtn:SetWidth(60) clearBtn:SetHeight(22)
clearBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
clearBtn:SetText("Clear")
clearBtn:SetScript("OnClick", function()
    PDB().picks = {}
    RefreshAll()
end)

-- ===================== rendu =====================
RefreshAll = function()
    local pl = PDB()
    -- browser (colonne droite)
    for i = 1, B_ROWS do
        local r = browserRows[i]
        local e = filtered[browserOff + i]
        r.entry = e
        if e then
            SetRowIcon(r, e)
            r.txt:SetText(("|cff%s%s|r"):format(e.qhex, e.name)
                .. ((e.lvl and e.lvl > 0) and ("  |cff888888" .. e.lvl .. "|r") or "")
                .. (IsKnownEntry(e) and "  |cff40ff40*|r" or ""))
            r:Show()
        else
            r:Hide()
        end
    end
    -- plan : split abilities (page gauche) / talents (page droite)
    local pa, pt = {}, {}
    for _, id in ipairs(pl.picks) do
        local e = byId[id]
        if e then
            if e.typ == "Talent" then pt[#pt + 1] = e else pa[#pa + 1] = e end
        end
    end
    for i = 1, P_ROWS do
        local rA, eA = planARows[i], pa[i]
        rA.entry = eA
        if eA then
            SetRowIcon(rA, eA)
            rA.txt:SetText(("|cff%s%s|r"):format(eA.qhex, eA.name))
            rA:Show()
        else rA:Hide() end
        local rT, eT = planTRows[i], pt[i]
        rT.entry = eT
        if eT then
            SetRowIcon(rT, eT)
            rT.txt:SetText(("|cff%s%s|r"):format(eT.qhex, eT.name))
            rT:Show()
        else rT:Hide() end
    end
    -- essence (style CA : compte courant)
    local a, t = EssenceLeft()
    essA:SetText(("|cff40ff40Ability Essence:|r %s%d / %d|r"):format(
        a < 0 and "|cffff4040" or "|cffffffff", a, ABILITY_TOTAL))
    essT:SetText(("|cffcc66ffTalent Essence:|r %s%d / %d|r"):format(
        t < 0 and "|cffff4040" or "|cffffffff", t, TALENT_TOTAL))
    -- paths
    for i, p in ipairs(PATHS) do
        if pl.path == p.tok then pathBtns[i].ring:Show() pathBtns[i].icon:SetVertexColor(1, 1, 1)
        else pathBtns[i].ring:Hide() pathBtns[i].icon:SetVertexColor(0.55, 0.55, 0.55) end
    end
    -- note footer
    local total = entries and #entries or 0
    if total > 0 and tipBuilt < total then
        tipNote:SetText(("|cff888888scanning tooltips... %d%%  --  %d entries (right column: click to add, pages: click to remove)|r")
            :format(math.floor(tipBuilt / total * 100), #filtered))
    else
        tipNote:SetText(("|cff888888%d entries -- right column: click to add ; pages: click to remove|r"):format(#filtered))
    end
end

-- prefetch des tooltips en fond (completude de la recherche)
local pre = CreateFrame("Frame")
pre.idx = 1
pre:SetScript("OnUpdate", function(self)
    if not ui:IsShown() or not entries then return end
    local total = #entries
    if tipBuilt >= total then return end
    local n = 0
    while n < 40 and self.idx <= total do
        local e = entries[self.idx]
        if tipCache[e.id] == nil then TipText(e) n = n + 1 end
        self.idx = self.idx + 1
    end
    if self.idx > total then self.idx = 1 end
    if math.floor(GetTime() * 2) % 2 == 0 then RefreshAll() end
end)

ui:SetScript("OnShow", function()
    BuildEntries()
    BuildSidebar()
    nameBox:SetText(PDB().name or "My Plan")
    FilterCaptions()
    Refilter()
    RefreshAll()
end)

local plannerTabID
function BuildPlanner_Toggle()
    if type(plannerTabID) == "number" and _G.Collections and Collections.GoToTab then
        if ui:IsShown() then
            HideUIPanel(Collections)
        else
            Collections:GoToTab(plannerTabID)
        end
        return
    end
    if ui:IsShown() then ui:Hide() else ui:Show() end
end

function BuildPlanner_LoadBuild(name, pathToken, ids)
    local pl = PDB()
    pl.name = name or "My Plan"
    pl.path = (pathToken and pathToken ~= "") and pathToken or nil
    pl.picks = {}
    for _, id in ipairs(ids or {}) do pl.picks[#pl.picks + 1] = id end
    if not ui:IsShown() then
        BuildPlanner_Toggle()
    else
        BuildEntries()
        BuildSidebar()
        nameBox:SetText(pl.name)
        Refilter()
        RefreshAll()
    end
    Msg("loaded |cffffd100" .. pl.name .. "|r (" .. #pl.picks .. " entries) -- edit then Export to BuildSpy.")
end

-- ===================== onglet Collections (le VRAI) =====================
-- v3.0 : les panels du CA s'ancrent BOTTOM+8 DANS Collections (leur XML) --
-- c'est l'ancrage qui manquait ("la barre est collee a une fenetre invisible").
local function TryRegisterTab()
    if plannerTabID then return true end
    local C = _G.Collections
    if not (C and C.AddTab) then return false end
    -- v3.1 : l'onglet pointe sur le FORK (BPCharacterAdvancement, CAFork/) --
    -- son XML l'ancre deja BOTTOM+8 dans Collections comme l'original -> meme
    -- position, meme taille, meme echelle que le vrai Character Advancement.
    -- La fenetre maison (BuildPlannerFrame) reste un repli /ains plan-legacy.
    local panelName = _G.BPCharacterAdvancement and "BPCharacterAdvancement" or "BuildPlannerFrame"
    local ok, tab = pcall(C.AddTab, C, "Build Planer", panelName)
    if not (ok and tab) then return false end
    if panelName == "BuildPlannerFrame" then
        pcall(function()
            ui:SetParent(C)
            ui:ClearAllPoints()
            ui:SetPoint("BOTTOM", C, "BOTTOM", 0, 8)
            ui:SetFrameStrata("MEDIUM")
            ui.docked = true
        end)
    end
    pcall(tab.SetIcon, tab, "Interface\\Icons\\Ability_Spy")
    pcall(tab.SetTooltip, tab, "Build Planer",
        "Plan a Character Advancement build: click entries to add them,\nSave exports to BuildSpy.")
    local okId, id = pcall(tab.GetTabID, tab)
    plannerTabID = (okId and id) or true
    return true
end
local watcher = CreateFrame("Frame")
watcher.acc, watcher.tries = 0, 0
watcher:SetScript("OnUpdate", function(self, e)
    self.acc = self.acc + e
    if self.acc < 2 then return end
    self.acc = 0
    self.tries = self.tries + 1
    if TryRegisterTab() or self.tries > 60 then self:SetScript("OnUpdate", nil) end
end)

-- ===================== spy runtime (/ains cadump) =====================
function BuildPlanner_CADump()
    AscensionInspectorDB = AscensionInspectorDB or {}
    local out = {}
    local function node(o, prefix, depth)
        if depth > 5 or #out > 2500 then return end
        local ot, nm = "?", "anon"
        pcall(function() ot = o:GetObjectType() end)
        pcall(function() nm = o:GetName() or "anon" end)
        local extra = {}
        pcall(function() extra[#extra + 1] = o:IsShown() and "shown" or "hidden" end)
        pcall(function() extra[#extra + 1] = math.floor(o:GetWidth()) .. "x" .. math.floor(o:GetHeight()) end)
        pcall(function()
            for _, r in ipairs({ o:GetRegions() }) do
                local t = r.GetText and r:GetText()
                if type(t) == "string" and t ~= "" and #t < 40 then extra[#extra + 1] = "TXT=" .. t end
                local tx = r.GetTexture and r:GetTexture()
                if type(tx) == "string" then extra[#extra + 1] = "TEX=" .. tx end
            end
        end)
        out[#out + 1] = prefix .. ot .. " " .. nm .. " {" .. table.concat(extra, " | ") .. "}"
        pcall(function()
            for _, c in ipairs({ o:GetChildren() }) do node(c, prefix .. "  ", depth + 1) end
        end)
    end
    local root = _G.CharacterAdvancement
    if root then
        out[#out + 1] = "===== CharacterAdvancement ====="
        node(root, "", 0)
    end
    AscensionInspectorDB.cadump = { at = date("%Y-%m-%d %H:%M"), lines = out }
    Msg("CA UI captured (" .. #out .. " lines). /reload to write.")
end
