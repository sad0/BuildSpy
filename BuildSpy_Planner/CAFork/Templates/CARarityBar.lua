BPCARarityBarMixin = {}

function BPCARarityBarMixin:OnLoad()
    self.Highlight:SetAtlas("search-highlight", Const.TextureKit.IgnoreAtlasSize)
    self.Left:SetAtlas("collapse-button-left", Const.TextureKit.IgnoreAtlasSize)
    self.Right:SetAtlas("collapse-button-right", Const.TextureKit.IgnoreAtlasSize)
    self.Middle:SetAtlas("collapse-button-middle", Const.TextureKit.IgnoreAtlasSize)
    self.RarityGemContainer:SetPoint("LEFT", self.Text, "RIGHT", 4, 0)
    self.RarityGemContainer:SetGemSize(16)
    self.RarityGemContainer:SetOrientation({ "BOTTOMLEFT", "BOTTOMRIGHT", -2, 0 })
    self.RarityGemContainer:SetGemClickHandler(GenerateClosure(self.OnClick, self))
    self.RarityGemContainer:SetGemOnEnterHandler(function() self:LockHighlight() end)
    self.RarityGemContainer:SetGemOnLeaveHandler(function() self:UnlockHighlight() end)
    AttributesToKeyValues(self)
    if self.quality then
        self:SetQuality(self.quality)
    end
end 

function BPCARarityBarMixin:OnShow()
    self:Update()
    self:RegisterEvent("CHARACTER_ADVANCEMENT_PENDING_BUILD_UPDATED")
end

function BPCARarityBarMixin:OnHide()
    self:UnregisterEvent("CHARACTER_ADVANCEMENT_PENDING_BUILD_UPDATED")
end

function BPCARarityBarMixin:OnEvent()
    self:Update()
end

function BPCARarityBarMixin:SetQuality(quality)
    self.quality = quality
    self.RarityGemContainer:SetGemQuality(quality)
    self:SetText(ITEM_QUALITY_COLORS[quality]:WrapText(_G["ITEM_QUALITY" .. quality .. "_DESC"]))
end 

function BPCARarityBarMixin:Update()
    if not self.quality then return end
    if not self:IsVisible() then return end

    local amount
    if BuildCreatorUtil.IsPickingSpells() then
        amount = select(self.quality, C_BuildEditor.GetQualityInfoForLevel()) or 0
    else
        amount = C_CharacterAdvancement.GetQualityCount(self.quality)
    end
    local limit = C_CharacterAdvancement.GetQualityLimit(self.quality)
    self.RarityGemContainer:SetNumGems(limit or amount, amount)
end

function BPCARarityBarMixin:OnClick()
    if self.quality then
        BPCharacterAdvancement:SetSearch(_G["ITEM_QUALITY" .. self.quality .. "_DESC"])
    end
end 