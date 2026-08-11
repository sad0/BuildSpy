--[[CA_GATE_TOOLTIP_FORMAT_LOCAL = CA_GATE_TOOLTIP_FORMAT_LOCAL or "Spend |cffFFFFFF%d|r more Talent Essence in |cffFFFFFFcurrent|r tree to unlock this row"
CA_GATE_TOOLTIP_FORMAT_GLOBAL = CA_GATE_TOOLTIP_FORMAT_GLOBAL or "Spend |cffFFFFFF%d|r more Talent Essence points in |cffFFFFFFany|r tree to unlock rows below"
CA_GATE_CLASS_POINTS_TEXT = CA_GATE_CLASS_POINTS_TEXT or "Requires Class Points: %s"
CA_GATE_INFO = CA_GATE_INFO or "You have |cffFFFFFF%s|r %s Talent Essence Invested"
CA_GATE_INFO_CLASS_POINTS = CA_GATE_INFO_CLASS_POINTS or "You have |cffFFFFFF%s|r %s |cffFFFFFFClass Points|r"
CA_GATE_INFO_CLASS_POINTS_HINT = CA_GATE_INFO_CLASS_POINTS_HINT or "Class Points are: TODO: FILL THIS TEXT"]]--

CA_POINTS_GLOBAL_STRING = CA_POINTS_GLOBAL_STRING or "Points: %s"

local CA_GATE_ICON_GLOBAL_TE = "Interface\\Icons\\inv_custom_talentessence"
local CA_GATE_ICON_GLOBAL_AE = "Interface\\Icons\\inv_custom_abilityessence"

-------------------------------------------------------------------------------
--                           Gate Mixin Structure                            --
-------------------------------------------------------------------------------
--
-- gate condition mixin
--
BPCAGateConditionMixin = {}

function BPCAGateConditionMixin:OnLoad()
    self.required = -1 -- filled dynamically
    self.left = 0
    self.isMet = 0
end

function BPCAGateConditionMixin:IsMet()
    return self.isMet
end

function BPCAGateConditionMixin:SetIsMet(value)
    self.isMet = value
end

function BPCAGateConditionMixin:SetLeft(value)
    self.left = value
end

function BPCAGateConditionMixin:GetLeft()
    return self.left
end

function BPCAGateConditionMixin:SetRequired(value)
    self.required = value
end

function BPCAGateConditionMixin:GetRequired()
    return self.required
end

--
-- gate info mixin
--
BPCAGateInfoMixin = {}

function BPCAGateInfoMixin:OnLoad()
    self.tier = -1
    self.topLeftNode = nil
    self.conditions = {}

    self.conditions["TAB"] = CreateFromMixinsAndLoad(BPCAGateConditionMixin)
    --self.conditions["CLASS"] = CreateFromMixinsAndLoad(BPCAGateConditionMixin)
    self.conditions["GLOBAL"] = CreateFromMixinsAndLoad(BPCAGateConditionMixin)
end

function BPCAGateInfoMixin:GetCondition(name)
    return self.conditions[name]
end

function BPCAGateInfoMixin:IsMetCondition(name)
    local condition = self:GetCondition(name)
    return condition and condition:IsMet() or false
end
-------------------------------------------------------------------------------
--                             Gate Frame Mixin                              --
-------------------------------------------------------------------------------
BPCATalentGatesInfoMixin = {}

function BPCATalentGatesInfoMixin:OnLoad()
    self.GatePool = CreateFramePool("FRAME", self, "BPCATalentGateCounterTemplate")
end

function BPCATalentGatesInfoMixin:Refresh(class, spec, treeTESpent, classTESpent, totalTESpent, totalAESpent)
    self.GatePool:ReleaseAll()

    local btn 
    for i = 1, 4 do 
        local btnNew = self.GatePool:Acquire()

        if btn then
            btnNew:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        else
            btnNew:SetPoint("TOP", 10, -20)
        end

        if i == 1 then
            btnNew:Init("TAB", treeTESpent, class, spec)
        elseif i == 2 then
            btnNew:Init("CLASS", classTESpent, class)
        elseif i == 3 then
            btnNew:Init("GLOBAL_TE", totalTESpent)
        elseif i == 4 then
            btnNew:Init("GLOBAL_AE", totalAESpent)
        end

        btnNew:Show()

        btn = btnNew
    end
end
-------------------------------------------------------------------------------
--                            Gate Counter Mixin                             --
-------------------------------------------------------------------------------
BPCATalentGateCounterMixin = {}

function BPCATalentGateCounterMixin:OnLoad()
    self.LockIcon:ClearAndSetPoint("CENTER", 0, 0)
    self.Line:Hide()
    self:SetWidth(40)
    self:SetHeight(24)

    --real icons 
    self.LockIconAdd:ClearAndSetPoint("CENTER", 0, 0)
    self.LockIconAdd:SetAtlas("category-icon-ring", Const.TextureKit.IgnoreAtlasSize)

    self.GateText:SetVertexColor(1, 1, 1)
    self.GateText:SetText("0")
    self.GateText:SetJustifyH("LEFT")
    self.GateText:ClearAndSetPoint("LEFT", self.LockIcon, "RIGHT", 6, -1)
end

function BPCATalentGateCounterMixin:Init(gateType, total, class, spec, minimized)
    self.class = class
    self.spec = spec
    self.total = total
    
    self.LockIcon:SetPortraitTexture(self:DefineIcon(gateType, class, spec))

    if minimized then
        self.GateText:SetText(total)
    else
        self.GateText:SetText(self:DefineText(gateType, class, spec):format(total))
    end

    self.tooltipTitle, self.tooltipText = self:DefineTooltip(gateType, class, spec)
end

function BPCATalentGateCounterMixin:CompareAndPlayAnim(oldAmount, oldClass, oldSpec)
    --dprint("BPCATalentGateCounterMixin:CompareAndPlayAnim o - "..(oldAmount or "NO OLD AMOUNT").." n - "..(self.total or "NO NEW AMOUNT").." oClass - "..(oldClass or "NO OLD CLASS").." nClass - "..(self.class or "NO NEW CLASS"))
    if oldAmount and (oldAmount < self.total) and (oldClass and (oldClass == self.class)) then
        --dprint("|cff00FF00pass main check")
        if not oldSpec or (self.spec == oldSpec) then
            if self:IsVisible() then
                --dprint("|cff00FFFFplay anim")
                self.AnimatedText:SetText("+"..(self.total - oldAmount))
                self.AnimatedText.Animation:Stop()
                self.AnimatedText.Animation:Play()
            end
        end
    end
end

function BPCATalentGateCounterMixin:DefineText(gateType, class, spec)
    class = string.gsub(class:lower(), "reborn", "")
    if gateType == "TAB" and class and spec then
        local classInfo = C_ClassInfo.GetSpecInfo(string.upper(class), string.upper(spec))
        return classInfo.Name.." "..CA_POINTS_GLOBAL_STRING
    elseif gateType == "CLASS" and class then
        return LOCALIZED_CLASS_NAMES_MALE[string.upper(class)].." "..CA_POINTS_GLOBAL_STRING
    end

    return "%d"
end

function BPCATalentGateCounterMixin:DefineIcon(gateType, class, spec)
    if gateType == "TAB" and class and spec then
        local classInfo = C_ClassInfo.GetSpecInfo(string.upper(class), string.upper(spec))
        if classInfo then
            return "Interface\\Icons\\"..classInfo.SpecFilename
        end
    elseif gateType == "CLASS" and class then
        return "interface\\icons\\classicon_"..class
    elseif gateType == "GLOBAL_AE" then
        return CA_GATE_ICON_GLOBAL_AE
    else
        return CA_GATE_ICON_GLOBAL_TE
    end
end

function BPCATalentGateCounterMixin:DefineTooltip(gateType, class, spec)
    if gateType == "TAB" and class and spec then
        local classInfo = C_ClassInfo.GetSpecInfo(string.upper(class), string.upper(spec))
        if classInfo then
            return CA_GATE_INFO:format(self.GateText:GetText(), classInfo.Name)
        end
    elseif gateType == "CLASS" and class then
        return CA_GATE_INFO_CLASS_POINTS:format(self.GateText:GetText(), AccessibilityUtil.GetClassPointsMarkup(class)), CA_GATE_INFO_CLASS_POINTS_HINT
    elseif gateType == "GLOBAL_AE" then
        return CA_GATE_INFO_GLOBAL_AE:format(self.GateText:GetText())
    else
        return CA_GATE_INFO:format(self.GateText:GetText(), "")
    end

    return ""
end

function BPCATalentGateCounterMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT", 4, -4)
    if self.tooltipText and self.tooltipTitle then
        GameTooltip:AddLine(self.tooltipTitle, 1, 0.82, 0, true)
        GameTooltip:AddLine(self.tooltipText, 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(self.tooltipTitle, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

function BPCATalentGateCounterMixin:OnLeave()
    GameTooltip:Hide()
end
-------------------------------------------------------------------------------
--                                Gate Mixin                                 --
-------------------------------------------------------------------------------
BPCATalentGateMixin = {}

function BPCATalentGateMixin:OnLoad()
    self.Line:SetVertexColor(1, 0.44, 0.26)
    self.Line:SetAtlas("levelup-line-white", Const.TextureKit.IgnoreAtlasSize)
    self.LockIconAdd:SetAtlas("category-icon-ring", Const.TextureKit.IgnoreAtlasSize)

    self.Shadow:SetAtlas("talents-node-choiceflyout-circle-shadow", Const.TextureKit.IgnoreAtlasSize)
end

function BPCATalentGateMixin:Init(gateInfo, class, spec, gateType)
    self.gateInfo = gateInfo

    class = string.gsub(class:lower(), "reborn", "")

    if gateType == "GLOBAL" then
        local left = gateInfo:GetCondition("GLOBAL"):GetLeft()
        self.LockIcon:SetPortraitTexture(BPCATalentGateCounterMixin:DefineIcon("GLOBAL_TE"))
        self.tooltip = CA_GATE_TOOLTIP_FORMAT_GLOBAL:format(left)
        self.GateText:SetText(left)
    elseif gateType == "TAB" then
        local left = gateInfo:GetCondition("TAB"):GetLeft()
        self.LockIcon:SetPortraitTexture(BPCATalentGateCounterMixin:DefineIcon("TAB", class, spec))
        self.tooltip = CA_GATE_TOOLTIP_FORMAT_LOCAL:format(left)
        self.GateText:SetText(left)
    end
end

function BPCATalentGateMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT", 4, -4)
    GameTooltip:AddLine(self.tooltip, 1, 0, 0, true)
    GameTooltip:Show()
end

function BPCATalentGateMixin:OnLeave()
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
--                     Gates attached to talents Mixin                       --
-------------------------------------------------------------------------------
BPCATalentFrameGatesMixin = {}

function BPCATalentFrameGatesMixin:OnLoad()
    self.GatePool = CreateFramePool("Frame", self, "BPCATalentGateTemplate")

    self.tiers = {}

    for i = 1, 11 do
        self.tiers[i] = CreateFromMixinsAndLoad(BPCAGateInfoMixin)
        self.tiers[i].tier = i
    end
end

function BPCATalentFrameGatesMixin:DefineGateConditionsRequired(gate, entry)
    local conditionGlobal = gate:GetCondition("GLOBAL")
    local conditionTab = gate:GetCondition("TAB")
    --local conditionClass = gate:GetCondition("CLASS")

    conditionGlobal:SetRequired(entry.RequiredTEInvestment)
    conditionTab:SetRequired(entry.RequiredTabTEInvestment)
    --conditionClass:SetRequired(entry.RequiredClassPoints)
end

function BPCATalentFrameGatesMixin:DefineGateTopLeftNode(gate, entry, button)
    if not (gate) then 
        return
    end

    if not gate.topLeftNode then
        gate.topLeftNode = button
        self:DefineGateConditionsRequired(gate, entry)
    else
        if gate.topLeftNode.entry and (gate.topLeftNode.entry.Column > entry.Column) then
            gate.topLeftNode = button
            self:DefineGateConditionsRequired(gate, entry)
        end
    end
end

function BPCATalentFrameGatesMixin:DefineGatesForButton(row)
    local gate = nil

    for _, gateInfo in ipairs(self.tiers) do
        if gateInfo.tier <= row then
            gate = gateInfo
        else
            break
        end
    end

    return gate
end

function BPCATalentFrameGatesMixin:RefreshGateInfo(class, spec, hardReset)
    local totalTESpent = C_CharacterAdvancement.GetGlobalTEInvestment() or 0
    local treeTESpent = C_CharacterAdvancement.GetTabTEInvestment(class, spec, 0) or 0

    for _, gateInfo in pairs(self.tiers) do
        if hardReset then
            gateInfo.topLeftNode = nil -- to be later filled in :SetTalents
        end

        local conditionGlobal = gateInfo:GetCondition("GLOBAL")
        local conditionTab = gateInfo:GetCondition("TAB")

        local diffGlobal = conditionGlobal:GetRequired() - totalTESpent
        local diffTab = conditionTab:GetRequired() - treeTESpent

        conditionGlobal:SetLeft(diffGlobal > 0 and diffGlobal or 0)
        conditionTab:SetLeft(diffTab > 0 and diffTab or 0)

        conditionTab:SetIsMet(diffTab <= 0)
        conditionGlobal:SetIsMet(diffGlobal <= 0)
    end

    if self.RefreshGateInfoCallBack then
        self:RefreshGateInfoCallBack()
    end
end

function BPCATalentFrameGatesMixin:RefreshGates(classFile, specFile)
    if not CharacterAdvancementUtil.AreTalentGatesEnabled() then
        self.GatePool:ReleaseAll()
        return
    end

    local oldRequirement, oldPoint

    for gate in self.GatePool:EnumerateActive() do
        oldRequirement = gate.gateInfo:GetCondition("TAB").required
        oldPoint = {gate:GetPoint()}
    end

    self.GatePool:ReleaseAll()

    -- global lock 
    local hasGate, oldGateInfo

    --[[for i, gateInfo in ipairs(self.tiers) do
        if not(gateInfo:IsMetCondition("GLOBAL")) and gateInfo.topLeftNode then -- show lock  at first global requirement
            local gate = self.GatePool:Acquire()
            gate:Init(gateInfo, classFile, specFile, "GLOBAL")
            gate:SetPoint("RIGHT", gateInfo.topLeftNode, "LEFT", 0, 0)
            gate.Line:Show()
            gate:SetWidth(82 + math.abs(gateInfo.topLeftNode.entry.Column - 1)*52)
            gate:Show()

            hasGate = gate
            oldGateInfo = gateInfo.topLeftNode

            break
        end
    end]]--

    -- local lock
    for i, gateInfo in ipairs(self.tiers) do
        if not(gateInfo:IsMetCondition("TAB")) and gateInfo.topLeftNode then

            if oldRequirement and (oldRequirement < gateInfo:GetCondition("TAB").required) then
                PlaySound(SOUNDKIT.COMMON_UI_MISSION_SELECT)
                self.GateDisappearanceFrame:ClearAndSetPoint(unpack(oldPoint))
                self.GateDisappearanceFrame.Shockwave.Explosion:Stop()
                self.GateDisappearanceFrame.Shockwave.Explosion:Play()
                self.GateDisappearanceFrame.Glow.Explosion:Stop()
                self.GateDisappearanceFrame.Glow.Explosion:Play()
            end

            if not gateInfo:IsMetCondition("GLOBAL") then
                return
            end

            local gate = self.GatePool:Acquire()
            gate:Init(gateInfo, classFile, specFile, "TAB")
            gate:SetPoint("RIGHT", gateInfo.topLeftNode, "LEFT", 0, 0)
            gate.Line:Show()
            gate:Show()

            if oldGateInfo and (oldGateInfo == gateInfo.topLeftNode) then
                gate:Hide()
               -- gate.Line:Hide()
                --gate:SetWidth(45 + 82 + math.abs(gateInfo.topLeftNode.entry.Column - 1)*52)
            else
                gate:SetWidth(82 + math.abs(gateInfo.topLeftNode.entry.Column - 1)*52)
            end

            break
        end
    end

end
