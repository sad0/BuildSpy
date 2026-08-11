-- ===================== Build Planer : load on demand =====================
-- The planner is a fork of the client's Character Advancement window. The real
-- Ascension_CharacterAdvancement addon is "LoadOnDemand: 1" and is only pulled
-- in when its Collections tab is opened -- we now do the same, and it is NOT a
-- cosmetic choice.
--
-- Loading the fork during the login sequence taints the shared EventRegistry
-- dispatch: secureexecuterange() carries the taint from one callback to the
-- next, so the client's own PLAYER_LOGIN / PLAYER_ENTERING_WORLD handlers then
-- run as BuildSpy. Proven with taintLog 2 -- it blocked GetCurrentTicket()
-- (the "BuildSpy has been blocked" popup) and CanPerformAction(), the latter
-- aborting NewCharacterSetupUtil so a brand new character silently lost its
-- transmog flag and archetype build. With the fork out of the TOC, a login is
-- completely clean.
--
-- So: nothing of the planner may load before the player is in the world.

local PLANNER = "BuildSpy_Planner"

local function Msg(t)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBuildSpy|r: " .. tostring(t))
end

local loadFailed
local function EnsurePlanner()
    if IsAddOnLoaded(PLANNER) then return true end
    if loadFailed then return false end
    local ok, reason = LoadAddOn(PLANNER)
    if not ok then
        loadFailed = true
        Msg("|cffff4040could not load the Build Planer|r (" .. tostring(reason) ..
            ") -- is the " .. PLANNER .. " folder next to BuildSpy in Interface\\AddOns?")
        return false
    end
    return true
end
_G.BuildSpy_EnsurePlanner = EnsurePlanner

-- Stubs under the planner's real names: load, then hand over to the function
-- the addon just installed over us. The identity check is what stops the call
-- recursing if the load silently did not replace the global.
local function Forward(name)
    local stub
    stub = function(...)
        if not EnsurePlanner() then return end
        local real = _G[name]
        if real and real ~= stub then return real(...) end
    end
    _G[name] = stub
end
Forward("BuildPlanner_Toggle")
Forward("BuildPlanner_LoadBuild")
Forward("BuildPlanner_CADump")

-- The planner lives in a Collections tab, so it has to be loaded by the time
-- that window is up. Polled rather than hooked: reading IsShown() touches no
-- client state, where a HookScript on Collections would taint it.
local watcher = CreateFrame("Frame")
watcher.acc = 0
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self.armed = true
end)
watcher:SetScript("OnUpdate", function(self, elapsed)
    if not self.armed then return end
    self.acc = self.acc + elapsed
    if self.acc < 0.5 then return end
    self.acc = 0
    if IsAddOnLoaded(PLANNER) or loadFailed then
        self:SetScript("OnUpdate", nil)
        return
    end
    local C = _G.Collections
    if C and C.IsShown and C:IsShown() then
        EnsurePlanner()
        self:SetScript("OnUpdate", nil)
    end
end)
