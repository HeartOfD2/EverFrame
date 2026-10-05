-- ---------------------------------------------------------------------------
-- Slice and Dice in the cooldown bars. The timer is read from the buff
-- itself wherever the client allows it:
--   1. exact      the aura's expiration time is a plain number
--   2. game timer the aura's duration only as a secret Duration object; the
--                 cooldown frame displays it without us touching the value
--   3. estimate   no readable aura: 6 + 3 seconds per combo point, plus 15%
--                 per Improved Slice and Dice rank, read from the talents
-- There is no setting for any of it; /uer status shows the path in use.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local CD, Rogue = ns.Cooldowns, ns.Rogue

local SND_IDS = { 5171, 6774 }
local IS_SND = { [5171] = true, [6774] = true }
local IMPROVED_SND = 14165            -- one spell for every rank on this client
local IMPROVED_SND_NODE = 105739      -- its talent node (found in game)
local PER_RANK = 0.15

local snd = CD:RegisterSpecial({
    key = "snd", ids = SND_IDS, noCasts = true,
    IsAvailable = function() return Rogue:IsActive() and ns.KnowsAny(SND_IDS) end,
    IsRelevant = function() return Rogue:IsClassAllowed() end,
})
Rogue.snd = snd
snd.mode = L["not used yet"]

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------
local function SetRunning(on)
    local o = snd.frame
    o:SetAlpha(on and 1 or 0.35)
    CD.SetActive(o, on)
    o.running = on
end

local function Stop()
    SetRunning(false)
    snd.expires = nil
    if snd.frame.cd.Clear then snd.frame.cd:Clear() end
end

-- the buff ran out (or our estimate did): dim, no ready flash
function snd:OnCooldownDone() Stop() end

-- ---------------------------------------------------------------------------
-- 1 + 2: the aura
-- ---------------------------------------------------------------------------
-- returns true when the aura could be read (running or not), false when the
-- client didn't let us look
local function ReadAura()
    local kind, a, b = ns.ReadPlayerAura(SND_IDS)
    if not kind then return false end
    if kind == "none" then
        if snd.frame.running and snd.mode ~= L["estimate"] then Stop() end
        return true
    end
    local cd = snd.frame.cd
    if kind == "exact" then
        snd.mode = L["exact (from the buff)"]
        SetRunning(true)
        snd.expires = a + b
        cd:SetCooldown(a, b)
        return true
    end
    -- only a secret timer: the cooldown frame shows it without us reading it
    if cd.SetCooldownFromDurationObject and pcall(cd.SetCooldownFromDurationObject, cd, a) then
        snd.mode = L["game timer (secret, shown by the game)"]
        SetRunning(true)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 3: the estimate
-- ---------------------------------------------------------------------------
-- does this talent node grant the given spell? (checks every entry, so it
-- also works while no point is spent)
local function NodeGrants(config, node, spellID)
    if type(node) ~= "table" or type(node.entryIDs) ~= "table" then return false end
    for _, entryID in ipairs(node.entryIDs) do
        local okE, entry = pcall(C_Traits.GetEntryInfo, config, entryID)
        local def = okE and entry and entry.definitionID
        if def then
            local okD, info = pcall(C_Traits.GetDefinitionInfo, def)
            if okD and info and info.spellID == spellID then return true end
        end
    end
    return false
end

local function NodeRank(node)
    return node.activeRank or node.ranksPurchased or node.currentRank or 0
end

-- rank of Improved Slice and Dice, or nil when the talents can't be read yet
local function ImprovedRank()
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetNodeInfo then
        local config = C_ClassTalents.GetActiveConfigID()
        if config then
            local ok, node = pcall(C_Traits.GetNodeInfo, config, IMPROVED_SND_NODE)
            if ok and NodeGrants(config, node, IMPROVED_SND) then return NodeRank(node) end
            -- the node moved: look through the class tree
            local treeID
            if C_ClassTalents.GetTraitTreeForSpec and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
                local spec = C_SpecializationInfo.GetSpecialization()
                local specID = spec and C_SpecializationInfo.GetSpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(spec)
                if specID then
                    local okT, t = pcall(C_ClassTalents.GetTraitTreeForSpec, specID)
                    if okT then treeID = t end
                end
            end
            local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
            if okN and type(nodes) == "table" and #nodes > 0 then
                for _, nodeID in ipairs(nodes) do
                    local okI, info = pcall(C_Traits.GetNodeInfo, config, nodeID)
                    if okI and NodeGrants(config, info, IMPROVED_SND) then
                        IMPROVED_SND_NODE = nodeID
                        return NodeRank(info)
                    end
                end
                return 0   -- tree read: talent not in it / not taken
            end
        end
    end
    -- classic talent tabs
    if GetNumTalentTabs and GetTalentInfo then
        local sndIcon = ns.SpellIcon(5171)
        for tab = 1, GetNumTalentTabs() or 0 do
            for i = 1, (GetNumTalents and GetNumTalents(tab)) or 0 do
                local ok, _, icon, _, _, rank = pcall(GetTalentInfo, tab, i)
                if ok and icon and sndIcon and icon == sndIcon then return rank or 0 end
            end
        end
        return 0
    end
    return nil
end

local knownRank
local function UpdateRank()
    local r = ImprovedRank()
    if r then knownRank = r end
end

local function Estimate()
    if not knownRank then UpdateRank() end
    local cp = ns.ComboPointsSpent(0.5) or 1
    cp = math.max(1, math.min(5, cp))
    return (6 + 3 * cp) * (1 + PER_RANK * (knownRank or 0)), cp
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function OnCast()
    -- a moment later the buff exists (and the points are spent)
    local dur, cp = Estimate()
    C_Timer.After(0.1, function()
        if ReadAura() and snd.frame.running then return end
        snd.mode = L["estimate"]
        SetRunning(true)
        snd.expires = GetTime() + dur
        snd.frame.cd:SetCooldown(GetTime(), dur)
        snd.lastEstimate = ("%d CP, %.0f s"):format(cp, dur)
    end)
end

ns.On("PLAYER_CAST", function(spellID)
    if IS_SND[spellID] and Rogue:IsActive() then OnCast() end
end)

ns.RegisterUnitEvent("UNIT_AURA", "player", function()
    if Rogue:IsActive() and snd.mode ~= L["estimate"] then ReadAura() end
end)

for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED" }) do
    ns.RegisterEvent(ev, function() if Rogue:IsActive() then UpdateRank() end end)
end

ns.On("LOGIN", function()
    Stop()
    if Rogue:IsActive() then
        UpdateRank()
        ReadAura()
    end
end)

ns.AddStatus(function()
    if not Rogue:IsActive() then return end
    local line = L["Slice and Dice: %s"]:format(snd.mode)
    if knownRank then line = line .. "  ·  " .. L["Improved Slice and Dice: %d/3"]:format(knownRank) end
    return line
end)
