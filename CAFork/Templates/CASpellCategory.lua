BPCASpellCategoryMixin = CreateFromMixins(ThreeSliceMixin)

function BPCASpellCategoryMixin:OnLoad()
    ThreeSliceMixin.OnLoad(self)

    self.Highlight:SetAtlas("search-highlight", Const.TextureKit.IgnoreAtlasSize)
end