-- BPPlannerWiring.lua -- v1.0 (11/08)
-- ---------------------------------------------------------------------------
-- Rebranche le clone BPCharacterAdvancement (copie pure, voir les autres
-- fichiers de CAFork/) en BUILD PLANER (demande user) :
--   * le SUMMARY du livre affiche LE PLAN (vierge au depart), pas mes talents
--   * clic GAUCHE sur une entree (browser de droite OU livre) = AJOUT au plan
--     tant qu'il reste de l'essence ; re-clic / clic DROIT = RETRAIT
--   * headers d'essence = budget niveau 60 restant (60 ability / 25 talent)
--   * footer : Rapid Rolling remplace par [New] [Load] [Save] [BuildSpy]
-- Le fork garde ses fichiers d'origine intacts : TOUT le rebranchement vit ici
-- (facile a resynchroniser si le client patch son addon).
-- ---------------------------------------------------------------------------

-- budgets niveau 60 (quiz user, corrige 11/08 : 50 ability, PAS 60)
local ABILITY_TOTAL, ABILITY_COST = 60, 2
local TALENT_TOTAL, TALENT_COST = 25, 1
local PATH_IDS = { [1149] = "strength", [1150] = "agility", [1151] = "intellect",
    [1152] = "healing", [18149] = "duality" }

-- copies des LOCALS du fichier fork (invisibles d'ici -- leur absence faisait
-- planter les overrides du Summary, et le SetAtlas("ca-background") qui suit
-- l'appel ne tournait plus : fond de page disparu, screenshot user)
local NUM_SPELLS_PER_ROW_SUMMARY = 8
local CA_COMPACT_SPELL_BUTTON_HEIGHT = 32
local function CharacterAdvancement_GetSummaryListStartY(self)
    local isDefaultClass = C_Player:IsDefaultClass()
    if not self.normalFooter and not isDefaultClass then
        return (HEADER_PRIMARY_STAT_HEIGHT or 60) + 8
    end
    local isCompactMode = C_GameMode:IsGameModeActive(Enum.GameMode.Draft, Enum.GameMode.WildCard)
    if isDefaultClass or self.normalFooter or isCompactMode then
        return 42
    end
    return 68
end

local function Msg(t) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffBuild Planer|r: " .. t) end

local function PDB()
    AscensionInspectorDB = AscensionInspectorDB or {}
    local db = AscensionInspectorDB
    db.planner = db.planner or { picks = {}, path = nil, name = "My Plan" }
    return db.planner
end

local function EntryOf(id)
    local CA = _G.C_CharacterAdvancement
    if not (CA and CA.GetEntryByInternalID) then return nil end
    local ok, e = pcall(CA.GetEntryByInternalID, id)
    if ok and type(e) == "table" then return e end
    return nil
end

local function EssenceLeft()
    local a, t = ABILITY_TOTAL, TALENT_TOTAL
    for _, id in ipairs(PDB().picks) do
        local e = EntryOf(id)
        if e then
            if e.Type == "Talent" then t = t - TALENT_COST else a = a - ABILITY_COST end
        end
    end
    return a, t
end

local function InPlan(id)
    for k, v in ipairs(PDB().picks) do if v == id then return k end end
    return nil
end

-- picks du plan pour une classe DBC donnee (le Summary du CA groupe par classe,
-- "Hero" cote ordre = "General" cote DBC -- meme regle que leur code)
local function PicksForClass(classDBC, wantTalent)
    local out = {}
    for _, id in ipairs(PDB().picks) do
        local e = EntryOf(id)
        if e then
            local isTal = (e.Type == "Talent")
            local cls = e.Class or e.ClassName or e.className or "General"
            if isTal == wantTalent and tostring(cls) == tostring(classDBC) then
                out[#out + 1] = e
            end
        end
    end
    return out
end

-- forwards, assignes en section 8 (keywords + tri "plan en tete de liste")
local KWIndex = function(i) return i end
local KWRebuild = function() end

local function RefreshAllViews()
    local f = _G.BPCharacterAdvancement
    if f and f:IsShown() then
        KWRebuild() -- re-partitionne la liste (picks du plan en haut)
        pcall(function() f:FullUpdate(true) end)
        pcall(function() f:RefreshCurrencies() end)
        -- rows visibles du browser (bordure "connu" = dans le plan)
        pcall(function() f.SideBar.SpellList:UpdateButtonsAndRefresh() end)
    end
end

-- ===================== 1) SUMMARY = LE PLAN =====================
-- copies exactes des boucles SetSpellSummary/SetTalentSummary du fork, avec la
-- SOURCE remplacee : GetKnown*EntriesForClass -> PicksForClass (le plan).
local function WireSummaries(mix)
    function mix:SetSpellSummary()
        local yStarting = CharacterAdvancement_GetSummaryListStartY(self)
        local height = self.Content:GetHeight()
        local button, x, y
        local index = 1
        for _, class in ipairs(CHARACTER_ADVANCEMENT_SUMMARY_CLASS_ORDER) do
            local classDBC = CharacterAdvancementUtil.GetClassDBCByFile(class)
            if classDBC == "Hero" then classDBC = "General" end
            local planSpells = PicksForClass(classDBC, false)
            if #planSpells > 0 then
                local remainder = (index - 1) % NUM_SPELLS_PER_ROW_SUMMARY
                if remainder ~= 0 then
                    index = index + (NUM_SPELLS_PER_ROW_SUMMARY - remainder)
                end
                local classIcon = self.SpellClassIconsPool:Acquire()
                x = 22 + ((index - 1) % NUM_SPELLS_PER_ROW_SUMMARY) * 44
                y = yStarting + (math.floor((index - 1) / NUM_SPELLS_PER_ROW_SUMMARY) * 48)
                classIcon.class = class
                classIcon:SetIcon("Interface\\Icons\\classicon_" .. class:lower())
                classIcon.Count:SetText(LOCALIZED_CLASS_NAMES_MALE[class:upper()] or "")
                classIcon:ClearAndSetPoint("TOPLEFT", self.Content.ScrollChild.Spells, "TOPLEFT", 22, -y - 4)
                classIcon:Show()
                index = index + 1
                for _, entry in ipairs(planSpells) do
                    button = self.CompactSpellPool:Acquire()
                    x = 22 + ((index - 1) % NUM_SPELLS_PER_ROW_SUMMARY) * 44
                    y = yStarting + (math.floor((index - 1) / NUM_SPELLS_PER_ROW_SUMMARY) * 48)
                    button:SetEntry(entry)
                    button:ClearAndSetPoint("TOPLEFT", self.Content.ScrollChild.Spells, "TOPLEFT", x, -y)
                    button:Show()
                    height = math.max(height, y + CA_COMPACT_SPELL_BUTTON_HEIGHT)
                    index = index + 1
                end
            end
        end
        return height
    end

    function mix:SetTalentSummary()
        local PER_ROW = 6  -- page de droite plus etroite : 6 talents par ligne (user 11/08)
        local yStarting = CharacterAdvancement_GetSummaryListStartY(self)
        local height = self.Content:GetHeight()
        local button, x, y
        local index = 1
        for _, class in ipairs(CHARACTER_ADVANCEMENT_SUMMARY_CLASS_ORDER) do
            local classDBC = CharacterAdvancementUtil.GetClassDBCByFile(class)
            if classDBC == "Hero" then classDBC = "General" end
            local planTalents = PicksForClass(classDBC, true)
            if #planTalents > 0 then
                local remainder = (index - 1) % PER_ROW
                if remainder ~= 0 then
                    index = index + (PER_ROW - remainder)
                end
                local classIcon = self.SpellClassIconsPool:Acquire()
                x = 22 + ((index - 1) % PER_ROW) * 44
                y = yStarting + (math.floor((index - 1) / PER_ROW) * 48)
                classIcon.class = class
                classIcon:SetIcon("Interface\\Icons\\classicon_" .. class:lower())
                classIcon.Count:SetText(LOCALIZED_CLASS_NAMES_MALE[class:upper()] or "")
                classIcon:ClearAndSetPoint("TOPLEFT", self.Content.ScrollChild.Talents, "TOPLEFT", 22, -y - 4)
                classIcon:Show()
                index = index + 1
                for _, entry in ipairs(planTalents) do
                    button = self.CompactSpellPool:Acquire()
                    x = 22 + ((index - 1) % PER_ROW) * 44
                    y = yStarting + (math.floor((index - 1) / PER_ROW) * 48)
                    button:SetEntry(entry)
                    button:ClearAndSetPoint("TOPLEFT", self.Content.ScrollChild.Talents, "TOPLEFT", x, -y)
                    button:Show()
                    height = math.max(height, y + CA_COMPACT_SPELL_BUTTON_HEIGHT)
                    index = index + 1
                end
            end
        end
        return height
    end
end

-- ===================== 2) essence = budget niveau 60 =====================
local function WireCurrencies(mix)
    local orig = mix.RefreshCurrencies
    function mix:RefreshCurrencies(...)
        if orig then pcall(orig, self, ...) end
        local a, t = EssenceLeft()
        pcall(function()
            self.Content.HeaderSpells.Total:SetText(
                string.format("%s / %d", string.format(ABILITY_ESSENCE_TOTAL, math.max(a, 0)), ABILITY_TOTAL)
                .. (a < 0 and " |cffff4040(over!)|r" or ""))
            self.Content.HeaderSpells.Total:Show()
            self.Content.HeaderTalents.Total:SetText(
                string.format("%s / %d", string.format(TALENT_ESSENCE_TOTAL, math.max(t, 0)), TALENT_TOTAL)
                .. (t < 0 and " |cffff4040(over!)|r" or ""))
        end)
    end
end

-- ===================== 3) clic = ajout/retrait au plan =====================
local function WireClicks()
    local base = _G.BPCASpellButtonBaseMixin
    if not base then return false end
    function base:OnClick(button)
        CloseDropDownMenus()
        if IsModifiedClick("CHATLINK") and self.spellID then
            local spellLink = LinkUtil and LinkUtil:GetSpellLink(self.spellID)
            if spellLink and ChatEdit_InsertLink(spellLink) then return end
        end
        local e = self.entry
        local id = e and (e.ID or e.Id or e.id)
        if not id then return end
        local pl = PDB()
        local at = InPlan(id)
        if button == "RightButton" or at then
            -- retrait (clic droit, ou re-clic d'une entree deja prise)
            if at then
                table.remove(pl.picks, at)
                RefreshAllViews()
            end
            return
        end
        -- ajout, gate budget niveau 60
        local isTal = (e.Type == "Talent")
        local a, t = EssenceLeft()
        if isTal then
            if t - TALENT_COST < 0 then
                Msg("|cffff4040talent essence exhausted|r (" .. TALENT_TOTAL .. " at 60).")
                return
            end
        elseif a - ABILITY_COST < 0 then
            Msg("|cffff4040ability essence exhausted|r (" .. ABILITY_TOTAL .. " at 60).")
            return
        end
        pl.picks[#pl.picks + 1] = id
        RefreshAllViews()
    end
    -- CreateFromMixins COPIE les fonctions a la creation : les mixins derives
    -- (compact du livre...) portent encore l'ancien OnClick -> re-pointer.
    if _G.BPCACompactSpellButtonMixin then _G.BPCACompactSpellButtonMixin.OnClick = base.OnClick end
    if _G.BPCASpellButtonMixin then _G.BPCASpellButtonMixin.OnClick = base.OnClick end
    return true
end

-- ===================== 4) footer : New / Load / Save / BuildSpy =====================
StaticPopupDialogs["BPPLANNER_NEW"] = {
    text = "Start a new empty plan? (current picks are discarded)",
    button1 = OKAY, button2 = CANCEL,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function()
        local pl = PDB()
        pl.picks, pl.path, pl.name = {}, nil, "My Plan"
        RefreshAllViews()
        Msg("new empty plan.")
    end,
}
StaticPopupDialogs["BPPLANNER_SAVE"] = {
    text = "Save the plan to BuildSpy as:",
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = 1, maxLetters = 40,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self) self.editBox:SetText(PDB().name or "My Plan") end,
    OnAccept = function(self)
        local name = self.editBox and self.editBox:GetText() or ""
        if name == "" then name = "My Plan" end
        PDB().name = name
        if not _G.BuildSpy_StoreBuild then Msg("|cffff4040BuildSpy store missing.|r") return end
        local pl = PDB()
        _G.BuildSpy_StoreBuild(name, pl.path or "", pl.picks, "")
        Msg("plan |cffffd100" .. name .. "|r saved to BuildSpy (/ains builds).")
    end,
}

local function LoadBuildIntoPlan(target, slot)
    local db = AscensionInspectorDB or {}
    local rec = db.targets and db.targets[target]
    local hits = rec and rec.caSpecs and rec.caSpecs[slot]
    if not hits then Msg("build not found.") return end
    local pl = PDB()
    pl.picks, pl.path = {}, nil
    for _, h in ipairs(hits) do
        if PATH_IDS[h.id] then
            pl.path = PATH_IDS[h.id]
        else
            pl.picks[#pl.picks + 1] = h.id
        end
    end
    pl.name = target .. " (edit)"
    RefreshAllViews()
    Msg("loaded |cffffd100" .. target .. " spec " .. slot .. "|r (" .. #pl.picks .. " entries) as a copy.")
end

local loadMenu = CreateFrame("Frame", "BPPlannerLoadMenu", UIParent, "UIDropDownMenuTemplate")
local function ShowLoadMenu(anchor)
    local builds = {}
    local db = AscensionInspectorDB or {}
    for t, rec in pairs(db.targets or {}) do
        for slot in pairs(rec.caSpecs or {}) do
            builds[#builds + 1] = { t = t, slot = slot }
        end
    end
    table.sort(builds, function(x, y)
        if x.t ~= y.t then return x.t < y.t end
        return x.slot < y.slot
    end)
    if #builds == 0 then Msg("no BuildSpy build stored yet (/ains on a target, or Import).") return end
    UIDropDownMenu_Initialize(loadMenu, function()
        for _, b in ipairs(builds) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = b.t .. "  |cff888888spec " .. b.slot .. "|r"
            info.notCheckable = true
            info.func = function() LoadBuildIntoPlan(b.t, b.slot) end
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, loadMenu, anchor, 0, 0)
end

local footerDone
local function WireFooter(f)
    if footerDone then return end
    footerDone = true
    -- Rapid Rolling n'a pas sa place dans un planner : cache en permanence
    local rr = f.Content and f.Content.WCRapidRollButton
    if rr then
        rr:Hide()
        pcall(function() rr.Show = function() end end)
    end
    local defs = {
        { "New", 64, function() StaticPopup_Show("BPPLANNER_NEW") end },
        { "Load", 64, function(self) ShowLoadMenu(self) end },
        { "Save", 64, function() StaticPopup_Show("BPPLANNER_SAVE") end },
        { "BuildSpy", 84, function()
            if SlashCmdList["ASCINSPECT"] then SlashCmdList["ASCINSPECT"]("builds") end
        end },
    }
    local total = 0
    for _, d in ipairs(defs) do total = total + d[2] + 6 end
    local x = -(total / 2) + 3
    for _, d in ipairs(defs) do
        local b = CreateFrame("Button", nil, f.Content, "UIPanelButtonTemplate")
        b:SetWidth(d[2]) b:SetHeight(22)
        b:SetPoint("TOP", f.Content, "BOTTOM", x + d[2] / 2, -2)
        b:SetText(d[1])
        b:SetScript("OnClick", d[3])
        x = x + d[2] + 6
    end
end

-- ===================== 6) "connu" = "DANS LE PLAN" =====================
-- (user : "c'est toujours MES sorts qui sont selectionnes") -- tout le rendu
-- des boutons (bordures, rangs 3/3, desaturation) lit C_CharacterAdvancement.
-- IsKnownID / GetTalentRankByID / IsKnownSpellID = l'etat DU PERSO. On donne
-- aux fonctions des mixins DU FORK (setfenv -- jamais le vrai CA ni le client)
-- un environnement ou ces trois lectures repondent depuis LE PLAN : une entree
-- du plan s'affiche connue/maxxee, tout le reste grise.
-- ops plan partagees (clics talents/Path passent par le shim, pas par notre OnClick)
local function PlanAdd(id)
    local pl = PDB()
    if PATH_IDS[id] then
        pl.path = PATH_IDS[id]  -- pl.path = NOM ("strength"...), format BuildSpy
        RefreshAllViews()
        return true
    end
    if InPlan(id) then return false end
    local e = EntryOf(id)
    local isTal = e and e.Type == "Talent"
    local a, t = EssenceLeft()
    if isTal then
        if t - TALENT_COST < 0 then
            Msg("|cffff4040talent essence exhausted|r (" .. TALENT_TOTAL .. " at 60).")
            return false
        end
    elseif a - ABILITY_COST < 0 then
        Msg("|cffff4040ability essence exhausted|r (" .. ABILITY_TOTAL .. " at 60).")
        return false
    end
    pl.picks[#pl.picks + 1] = id
    RefreshAllViews()
    return true
end
local function PlanRemove(id)
    local pl = PDB()
    if PATH_IDS[id] and pl.path == PATH_IDS[id] then
        pl.path = nil
        RefreshAllViews()
        return true
    end
    local at = InPlan(id)
    if at then
        table.remove(pl.picks, at)
        RefreshAllViews()
        return true
    end
    return false
end

local planCA = setmetatable({}, { __index = _G.C_CharacterAdvancement })
-- lectures d'etat "connu" -> le plan
function planCA.IsKnownID(id)
    if InPlan(id) then return true end
    return PATH_IDS[id] ~= nil and PDB().path == PATH_IDS[id]
end
function planCA.IsKnownSpellID(sid)
    local ok, e = pcall(_G.C_CharacterAdvancement.GetEntryBySpellID, sid)
    local id = ok and type(e) == "table" and (e.ID or e.Id or e.id) or nil
    return (id and planCA.IsKnownID(id)) or false
end
function planCA.GetTalentRankByID(id)
    local cur, max
    pcall(function() cur, max = _G.C_CharacterAdvancement.GetTalentRankByID(id) end)
    max = max or 1
    if planCA.IsKnownID(id) then return max, max end
    return 0, max
end
-- prerequis d'arbre : dans le planner tout est prenable (l'ordre des rolls est aleatoire)
function planCA.KnowsConnectedNodesFor() return true end
-- ecritures -> operations sur LE PLAN (jamais le vrai apprentissage)
function planCA.CanAddByEntryID(id)
    if PATH_IDS[id] then return true end
    if InPlan(id) then return false end
    local e = EntryOf(id)
    local a, t = EssenceLeft()
    if e and e.Type == "Talent" then return t - TALENT_COST >= 0 end
    return a - ABILITY_COST >= 0
end
function planCA.AddByEntryID(id) return PlanAdd(id) end
function planCA.CanRemoveByEntryID(id)
    if InPlan(id) then return true end
    return PATH_IDS[id] ~= nil and PDB().path == PATH_IDS[id]
end
function planCA.RemoveByEntryID(id) return PlanRemove(id) end
function planCA.CanUnlearnID(id) return planCA.CanRemoveByEntryID(id) end
function planCA.CanLearnID(id) -- recoit un ENTRY ID (cf. CanLearnID(self.entry.ID))
    return planCA.CanAddByEntryID(id)
end
-- neutraliser les ecritures reelles restantes
function planCA.ApplyPendingBuild() end
function planCA.CancelPendingBuild() end
function planCA.LockID() end
function planCA.UnlockID() end
function planCA.PickupSpell() end

-- CharacterAdvancementUtil : Ctrl+clic talent = ConfirmOrLearnID -> APPRENTISSAGE
-- REEL. Proxy : learn/unlearn -> plan, gates de talents desactivees (elles lisent
-- l'investissement du PERSO), swap neutralise. Tout le reste passe-plat.
local planUtil = setmetatable({}, { __index = _G.CharacterAdvancementUtil })
function planUtil.ConfirmOrLearnID(ids)
    if type(ids) ~= "table" then ids = { ids } end
    local seen = {}
    for _, id in ipairs(ids) do
        if not seen[id] then
            seen[id] = true
            PlanAdd(id)
        end
    end
end
function planUtil.ConfirmOrUnlearnID(id) PlanRemove(id) end
function planUtil.MarkForSwap() end
function planUtil.AreTalentGatesEnabled() return false end

local planEnv = setmetatable(
    { C_CharacterAdvancement = planCA, CharacterAdvancementUtil = planUtil },
    { __index = _G, __newindex = _G })
local function ApplyPlanView()
    -- tous les mixins du fork (BPCA...Mixin) -- et EUX SEULS, jamais le client
    for name, t in pairs(_G) do
        if type(name) == "string" and type(t) == "table"
            and string.find(name, "^BPCA%u") and string.find(name, "Mixin$") then
            for _, v in pairs(t) do
                if type(v) == "function" then pcall(setfenv, v, planEnv) end
            end
        end
    end
end

-- ===================== 7) rows de la SpellList = template CLIENT =====================
-- SideBar.SpellList utilise SpellListItemTemplate (mixin PARTAGE avec le vrai CA :
-- pas de setfenv possible). Etat "connu", rang ET clics (shift-clic = VRAI learn !)
-- lisent le perso. On remplace les methodes PAR INSTANCE sur les rows de NOTRE
-- liste uniquement (les copies de fonctions posees par Mixin() se shadowent
-- champ par champ sans toucher le mixin global).
local function RowSetKnown(self, known)
    self.known = known
    self.Text:SetTextColor((known and NORMAL_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
    self.cannotLearn, self.cannotUnlearn = nil, nil
    if self.Icon.RankUp then self.Icon.RankUp:Hide() end
    self.Icon:SetIconDesaturated(not known)
    self.Icon:SetIconColor(1, 1, 1)
end

local function RowUpdate(self)
    self.entry = _G.C_CharacterAdvancement.GetFilteredEntryAtIndex(KWIndex(self.index))
    if not self.entry then
        self:SetText("BAD ENTRY " .. self.index)
        return
    end
    local id = self.entry.ID
    local inPlan = InPlan(id) ~= nil
    if _G.C_CharacterAdvancement.IsTalentID(id) then
        self.maxRank = #self.entry.Spells
        self.rank = inPlan and self.maxRank or 0
    else
        self.rank, self.maxRank = nil, nil
    end
    if self:IsSelected() then
        self:LockHighlight()
        self:GetHighlightTexture():SetAtlas("spell-list-button-selected", Const.TextureKit.IgnoreAtlasSize)
    else
        self:UnlockHighlight()
        self:GetHighlightTexture():SetAtlas("spell-list-button-highlight", Const.TextureKit.IgnoreAtlasSize)
    end
    if not self.rank or self.rank < 1 then
        self:SetSpell(self.entry.Spells[1])
    else
        self:SetSpell(self.entry.Spells[self.rank])
    end
    if self.Icon.PendingChange then self.Icon.PendingChange:Hide() end
    self:SetKnown(inPlan)
    self:UpdateExpandedContent()
    if GameTooltip:IsOwned(self) then self:OnEnter() end
end

local function RowOnClick(self, button)
    PlaySound(SOUNDKIT.UCHATSCROLLBUTTON)
    CloseDropDownMenus()
    if IsModifiedClick("CHATLINK") and self.spellID then
        local spellLink = LinkUtil and LinkUtil:GetSpellLink(self.spellID)
        if spellLink and ChatEdit_InsertLink(spellLink) then return end
    end
    local id = self.entry and self.entry.ID
    if not id then return end
    if button == "RightButton" or InPlan(id) then
        PlanRemove(id)
    else
        PlanAdd(id)
    end
end

local function WireRow(row)
    if row.bpPlanWired then return end
    row.bpPlanWired = true
    row.Update = RowUpdate
    row.OnClick = RowOnClick
    row.SetKnown = RowSetKnown
    row.OnDoubleClick = nop
    row.OnDragStart = nop
    row.ToggleLocked = nop
    row.SetLock = function(self) self.LockButton:Hide() end
    row.Learn = function(self)
        local id = self.entry and self.entry.ID
        if id then PlanAdd(id) end
    end
    row.Unlearn = function(self)
        local id = self.entry and self.entry.ID
        if id then PlanRemove(id) end
    end
    -- MixinAndLoadScripts a fait SetScript(k, mixinFunc) : les SCRIPTS sont figes
    -- sur les fonctions du mixin client -> re-poser les scripts par instance
    row:SetScript("OnClick", RowOnClick)
    row:SetScript("OnDoubleClick", nil)
    row:SetScript("OnDragStart", nil)
    -- OnLoad a fige Icon.OnClickHandler sur l'ANCIEN OnClick -> re-pointer
    row.Icon.OnClickHandler = GenerateClosure(RowOnClick, row)
end

local function WireSpellListRows(f)
    local list = f.SideBar and f.SideBar.SpellList
    if not list then return end
    local function WireAll()
        local btns = list.ScrollFrame and list.ScrollFrame.buttons
        if not btns then return end
        for _, b in ipairs(btns) do WireRow(b) end
    end
    -- hooks PAR INSTANCE (la table 'list'), le ScrollListMixin global reste intact ;
    -- de nouveaux boutons naissent a chaque resize -> re-passer apres chaque creation
    hooksecurefunc(list, "UpdateButtons", WireAll)
    hooksecurefunc(list, "UpdateButtonsAndRefresh", WireAll)
    WireAll()
end

-- ===================== 5) sidebar = TOUT le pool =====================
-- le defaut du CA (recherche vide, aucun filtre) = { FILTER_KNOWN = true } ->
-- la liste de droite ne montrait QUE les skills du perso. Pour PLANIFIER il
-- faut tout le pool roulable : filtre vide par defaut (recherche et menu
-- Filter continuent de marcher par-dessus).
local function WireSearch(f)
    function f:Search()
        local header = self.SideBar.SpellList.Header
        local text = header.SearchBox:GetText():trim()
        local hasFilter = header.Filter:HasAnyFilters()
        if string.isNilOrEmpty(text) and not hasFilter then
            C_CharacterAdvancement.SetFilteredEntries("", {})   -- TOUT (planner)
        else
            C_CharacterAdvancement.SetFilteredEntries(text, header.Filter:GetFilter())
        end
        local selectedButton = self.SideBar.SpellList:GetSelectedButton()
        if selectedButton then selectedButton:OnDeselected() end
        self.SideBar.SpellList:SetSelectedIndex(nil)
        self.SideBar.SpellList:RefreshScrollFrame()
    end
    -- re-liste immediatement si la fenetre est deja ouverte
    if f:IsShown() then pcall(function() f:Search() end) end
end

-- ===================== 8) panneau KEYWORDS =====================
-- la recherche moteur ne matche qu'UNE sous-chaine dans les tooltips ("rage
-- attack" ne trouve rien). Chaque mot allume = une sous-chaine cherchee dans
-- nom+tooltip du sort, ET entre tous les mots allumes. Type/Rarete = predicats
-- exacts. Post-filtre par index-map au-dessus du resultat moteur (les rows
-- passent par KWIndex).
local kwActive = {}          -- [label] = def
local kwMap, kwUse = {}, false
local kwTextCache = {}       -- [spellID] = "nom tooltip" minuscules

local kwScan = CreateFrame("GameTooltip", "BPKWScanTip", nil, "GameTooltipTemplate")
kwScan:SetOwner(UIParent, "ANCHOR_NONE")
local function KWText(sid)
    local t = kwTextCache[sid]
    if t then return t end
    local parts = { (GetSpellInfo(sid)) or "" }
    if type(GetSpellDescription) == "function" then
        local ok, d = pcall(GetSpellDescription, sid)
        if ok and d and d ~= "" then parts[#parts + 1] = d end
    end
    if #parts < 2 then -- fallback : scan du tooltip cache
        kwScan:ClearLines()
        kwScan:SetHyperlink("spell:" .. sid)
        for i = 2, kwScan:NumLines() do
            local fs = _G["BPKWScanTipTextLeft" .. i]
            local s = fs and fs:GetText()
            if s then parts[#parts + 1] = s end
        end
    end
    t = string.lower(table.concat(parts, " "))
    kwTextCache[sid] = t
    return t
end

-- cooldown par PROPRIETE du sort (GetSpellBaseCooldown si le client l'a),
-- tooltip en dernier recours seulement
local function KWHasCD(sid)
    if type(_G.GetSpellBaseCooldown) == "function" then
        local ok, cd = pcall(_G.GetSpellBaseCooldown, sid)
        if ok and type(cd) == "number" then return cd > 1500 end -- > GCD = vrai CD
    end
    return string.find(KWText(sid), "cooldown", 1, true) ~= nil
end

-- cout : rage/energy/mana par GetSpellInfo (cost+powerType) ; sinon on ne matche
-- QUE la LIGNE DE COUT du tooltip (ligne courte des lignes 2-5 qui, videe de tous
-- ses jetons de cout, ne laisse rien) -- "deals 340 frost damage" ne matche plus
local COST_TOKENS = {
    "%d+%% of base mana", "%d+ mana", "%d+ rage", "%d+ energy", "%d+ focus",
    "%d+ runic power", "%d+ blood", "%d+ unholy", "%d+ frost",
}
local kwCostCache = {} -- [spellID] = ligne(s) de cout en minuscules ("" si aucune)
local function KWCostLine(sid)
    local c = kwCostCache[sid]
    if c then return c end
    kwScan:ClearLines()
    kwScan:SetHyperlink("spell:" .. sid)
    c = ""
    for i = 2, math.min(kwScan:NumLines(), 5) do
        local fs = _G["BPKWScanTipTextLeft" .. i]
        local s = fs and fs:GetText()
        if s and #s < 40 and not string.find(s, "%.") then
            local l = string.lower(s)
            local rest = l
            for _, tok in ipairs(COST_TOKENS) do rest = string.gsub(rest, tok, "") end
            rest = string.gsub(rest, "[%s,]", "")
            if rest == "" and l ~= "" then c = c .. " " .. l end
        end
    end
    kwCostCache[sid] = c
    return c
end

local function KWCost(sid, def)
    if def.ptype then
        local _, _, _, cost, _, ptype = GetSpellInfo(sid)
        if (cost or 0) > 0 and ptype == def.ptype then return true end
    end
    local line = KWCostLine(sid)
    for _, pat in ipairs(def.patterns or {}) do
        if string.find(line, pat) then return true end
    end
    return false
end

local function KWPass(e)
    local sid = e.Spells[1]
    for _, def in pairs(kwActive) do
        if def.etype then
            local isTal = (e.Type == "Talent")
            if def.etype == "Talent" and not isTal then return false end
            if def.etype == "Ability" and isTal then return false end
        elseif def.quality then
            local q = _G.C_CharacterAdvancement.GetQualityInfo(sid)
            if q ~= def.quality then return false end
        elseif def.cd ~= nil then
            if KWHasCD(sid) ~= def.cd then return false end
        elseif def.any then -- OU de sous-chaines (+ castTime en propriete si demande)
            local hit = false
            if def.castTime then
                local ct = select(7, GetSpellInfo(sid))
                hit = (ct or 0) > 0
            end
            if not hit then
                local t = KWText(sid)
                for _, m in ipairs(def.any) do
                    if string.find(t, m, 1, true) then hit = true break end
                end
            end
            if not hit then return false end
        elseif def.ptype or def.patterns then
            if not KWCost(sid, def) then return false end
        elseif not string.find(KWText(sid), def.match, 1, true) then
            return false
        end
    end
    return true
end

-- map de vue : filtre keywords + picks du plan REMONTES EN TETE de liste
KWRebuild = function()
    wipe(kwMap)
    kwUse = next(kwActive) ~= nil or #(PDB().picks) > 0
    if not kwUse then return end
    local n = _G.C_CharacterAdvancement.GetNumFilteredEntries() or 0
    local tail = {}
    for i = 1, n do
        local e = _G.C_CharacterAdvancement.GetFilteredEntryAtIndex(i)
        if e and e.Spells and e.Spells[1] and KWPass(e) then
            if InPlan(e.ID) then
                kwMap[#kwMap + 1] = i     -- dans le plan -> en haut
            else
                tail[#tail + 1] = i
            end
        end
    end
    for _, i in ipairs(tail) do kwMap[#kwMap + 1] = i end
end

KWIndex = function(i)
    if kwUse then return kwMap[i] or i end
    return i
end

-- groupes de mots (3 par ligne) ; match = sous-chaine tooltip sauf etype/quality
local KW_GROUPS = {
    { "Type", {
        { "Ability", etype = "Ability" }, { "Talent", etype = "Talent" }, { "Spell" },
    } },
    { "Card Rarity", {
        { "Common", quality = 1 }, { "Uncommon", quality = 2 }, { "Rare", quality = 3 },
        { "Epic", quality = 4 }, { "Legendary", quality = 5 },
    } },
    { "School", {
        { "Fire" }, { "Frost" }, { "Shadow" },
        { "Nature" }, { "Arcane" }, { "Holy" },
        { "Physical" }, { "Damage" },
    } },
    { "Combat", {
        { "Melee" }, { "Range" }, { "Weapon" },
        { "Attack" }, { "Casting", any = { "sec cast", "channel" }, castTime = true },
        { "Instant" },
    } },
    { "Control", {
        { "Stun" }, { "Slow" }, { "Root" },
        { "Silence" }, { "Interrupt" }, { "Fear" },
        { "Taunt" }, { "Charge" }, { "Immune" },
    } },
    { "Defense", {
        { "Armor" }, { "Block" }, { "Dodge" },
        { "Parry" }, { "Absorb" }, { "Threat" },
    } },
    { "Healing", {
        { "Heal" }, { "Restore" }, { "Drain" },
    } },
    { "Stats", {
        { "Attack Pwr", match = "attack power" }, { "Spell Pwr", match = "spell power" }, { "Haste" },
        { "Critical" }, { "Stamina" }, { "Strength" },
        { "Agility" }, { "Intellect" }, { "Spirit" },
    } },
    { "Cooldown", {
        { "Has CD", cd = true }, { "No CD", cd = false },
    } },
    { "Cost", {
        { "Rage", ptype = 1, patterns = { "%d+ rage" } },
        { "Energy", ptype = 3, patterns = { "%d+ energy" } },
        { "Mana", ptype = 0, patterns = { "%d+ mana", "of base mana" } },
        { "Blood", patterns = { "%d+ blood" } },
        { "Unholy", patterns = { "%d+ unholy" } },
        { "Frost", patterns = { "%d+ frost" } },
    } },
    { "Misc", {
        { "Pet" }, { "Summon" }, { "Totem" },
        { "Aura" }, { "Form" }, { "Stealth" },
        { "Poison" }, { "Disease" }, { "Curse" },
        { "Speed" },
    } },
}

local QCOLORS = { [1] = { 0.9, 0.9, 0.9 }, [2] = { 0.1, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }

local function KWRestyle(b)
    local qc = b.def.quality and QCOLORS[b.def.quality]
    if kwActive[b.key] then
        b:SetBackdropColor(1, 0.82, 0, 0.30)
        b:SetBackdropBorderColor(1, 0.82, 0, 1)
        if qc then b.Label:SetTextColor(qc[1], qc[2], qc[3])
        else b.Label:SetTextColor(1, 0.95, 0.6) end
    else
        b:SetBackdropColor(0, 0, 0, 0.55)
        b:SetBackdropBorderColor(0.45, 0.40, 0.30, 0.9)
        if qc then b.Label:SetTextColor(qc[1] * 0.6, qc[2] * 0.6, qc[3] * 0.6)
        else b.Label:SetTextColor(0.72, 0.72, 0.72) end
    end
end

local function WireKeywords(f)
    if f.BPKeywords then return end
    -- fenetre detachee draggable, ancree PAR DEFAUT au bord droit de la fenetre
    -- (clamp ecran : si pas la place, elle glisse par-dessus le bord au lieu de
    -- sortir de l'ecran) ; position retenue dans la DB
    local p = CreateFrame("Frame", "BPPlannerKeywords", f)
    p:SetWidth(252)
    local pl = PDB()
    p:SetPoint("TOPLEFT", f, "TOPRIGHT", pl.kwX or 1, pl.kwY or -14)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetClampedToScreen(true)
    p:SetScript("OnDragStart", function(self) self:StartMoving() end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local d = PDB()
        d.kwX = self:GetLeft() - f:GetRight()
        d.kwY = self:GetTop() - f:GetTop()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", f, "TOPRIGHT", d.kwX, d.kwY)
    end)
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
    p:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
    f.BPKeywords = p
    p.buttons = {}

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Keywords")

    local clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    clear:SetSize(46, 16)
    clear:SetPoint("TOPRIGHT", -8, -6)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function()
        wipe(kwActive)
        for _, b in ipairs(p.buttons) do KWRestyle(b) end
        f:Search()
    end)

    local y = -26
    for _, group in ipairs(KW_GROUPS) do
        local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", 10, y)
        h:SetText(group[1])
        h:SetTextColor(1, 0.82, 0)
        y = y - 14
        for idx, def in ipairs(group[2]) do
            def.match = def.match or string.lower(def[1])
            local col = (idx - 1) % 3
            if col == 0 and idx > 1 then y = y - 21 end
            local b = CreateFrame("Button", nil, p)
            b:SetSize(76, 19)
            b:SetPoint("TOPLEFT", 8 + col * 79, y)
            b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9,
                insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.Label:SetPoint("CENTER", 0, 0)
            b.Label:SetText(def[1])
            b.def = def
            b.key = group[1] .. "/" .. def[1] -- unique (Frost existe en School ET Cost)
            p.buttons[#p.buttons + 1] = b
            KWRestyle(b)
            b:SetScript("OnClick", function(self)
                kwActive[self.key] = not kwActive[self.key] and self.def or nil
                KWRestyle(self)
                f:Search()
            end)
        end
        y = y - 21 - 6
    end
    p:SetHeight(-y + 6)

    -- compte de resultats vu par la scroll list = post-filtre
    local list = f.SideBar.SpellList
    local orig = list.getNumResultsFunction or _G.C_CharacterAdvancement.GetNumFilteredEntries
    function list:SetGetNumResultsFunction(fn)
        self.getNumResultsFunction = function()
            if kwUse then return #kwMap end
            return fn()
        end
    end
    list:SetGetNumResultsFunction(orig)

    -- apres chaque Search (SetFilteredEntries fraiche), reconstruire la map
    hooksecurefunc(f, "Search", function(self)
        KWRebuild()
        if kwUse then self.SideBar.SpellList:RefreshScrollFrame() end
    end)

    -- etat initial (le f:Search() de WireSearch a tourne AVANT ce hook)
    KWRebuild()
    if f:IsShown() then list:RefreshScrollFrame() end
end

-- ===================== application =====================
local applied
local function Apply()
    if applied then return true end
    local f = _G.BPCharacterAdvancement
    local mix = _G.BPCharacterAdvancementMixin
    if not (f and mix) then return false end
    local ok = pcall(function()
        WireSummaries(f)          -- sur L'INSTANCE (le mixin est deja copie dessus)
        WireCurrencies(f)
        WireFooter(f)
        WireSearch(f)
        WireSpellListRows(f)
        WireKeywords(f)
        -- onglet Specs retire : redondant avec BuildSpy (user 11/08)
        f.SideBar:HideTabID(f.SideBar.SpecTab)
        f.SideBar:SelectTabID(f.SideBar.SpellsTab)
    end)
    local ok2 = WireClicks()
    ApplyPlanView()               -- vue "connu = dans le plan" sur les mixins du fork
    applied = ok and ok2
    if applied then
        Msg("planner wiring active -- Summary = your PLAN, click entries to add/remove.")
    end
    return applied
end
if not Apply() then
    local w = CreateFrame("Frame")
    w.acc = 0
    w:SetScript("OnUpdate", function(self, e)
        self.acc = self.acc + e
        if self.acc < 1 then return end
        self.acc = 0
        if Apply() then self:SetScript("OnUpdate", nil) end
    end)
end
