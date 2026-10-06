-- ---------------------------------------------------------------------------
-- Range to the target as distance bands (the game gives addons no exact
-- distance to enemies). Each band asks whether one of its spells is in range.
-- Every band has an opaque layer, nearest on top, shown only while its check
-- says "in range" -- so the visible layer is the nearest band. Answers can be
-- secret in combat: those are only passed to SetAlphaFromBoolean.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local HUD = ns.HUD

local BAND_COLORS = { { 0.22, 0.80, 0.45 }, { 1.00, 0.80, 0.22 }, { 1.00, 0.58, 0.22 }, { 1.00, 0.45, 0.30 } }

local range = HUD:Register({
    key = "range", order = 40, height = 16,
    label = L["Range display"],
    style = { height = 16, textSize = 11 },
    Build = function(self, parent)
        local r = CreateFrame("Frame", nil, parent)
        ns.Skin(r, T.hudTrack, T.hudLine)
        HUD:AddEdge(r, "range")
        r.base = ns.HudText(r, 11)
        r.base:SetPoint("CENTER", 0, 0)
        self.region = r
        self.layers = {}
        self.elapsed = 0
        self.mode = "—"
    end,
})

function range:Bands()
    return ns.ClassPack().range or {}
end

function range:ApplyStyle()
    local size = HUD:Get("range", "textSize") or 11
    ns.ApplyFont(self.region.base, size, "")
    for _, l in ipairs(self.layers) do ns.ApplyFont(l.text, size, "") end
end

function range:IsRelevant() return #self:Bands() > 0 end

function range:IsAvailable()
    if #self:Bands() > 0 then return true end
    return false, L["no range checks for this class yet"]
end

local function BandLabel(band)
    if band.yards == 0 then return L["MELEE"] end
    return L["WITHIN %d YD"]:format(band.yards)
end

-- one opaque layer per band; bands come from the class, so build at login
function range:BuildLayers()
    local bands = self:Bands()
    for i, band in ipairs(bands) do
        local l = self.layers[i]
        if not l then
            l = CreateFrame("Frame", nil, self.region)
            l:SetAllPoints()
            l.bg = l:CreateTexture(nil, "BACKGROUND", nil, -7)
            l.bg:SetAllPoints()
            l.bg:SetColorTexture(0.075, 0.08, 0.095, 1)
            l.tint = l:CreateTexture(nil, "BACKGROUND", nil, -6)
            l.tint:SetAllPoints()
            l.edge = l:CreateTexture(nil, "ARTWORK")
            l.edge:SetPoint("TOPLEFT")
            l.edge:SetPoint("BOTTOMLEFT")
            l.edge:SetWidth(3)
            l.text = ns.HudText(l, 11)
            l.text:SetPoint("CENTER", 0, 0)
            self.layers[i] = l
        end
        -- bands run far -> near: nearer ones sit higher and get the greener color
        l:SetFrameLevel(self.region:GetFrameLevel() + i)
        local c = BAND_COLORS[#bands - i + 1] or BAND_COLORS[#BAND_COLORS]
        l.tint:SetColorTexture(c[1], c[2], c[3], 0.16)
        l.edge:SetColorTexture(c[1], c[2], c[3], 1)
        l.text:SetTextColor(c[1], c[2], c[3])
        l.text:SetText(BandLabel(band))
        l:SetAlpha(0)
        l:Show()
    end
    for i = #bands + 1, #self.layers do self.layers[i]:Hide() end
end

-- what a band asks with: each known spell as ID, then by its localized name
-- (that resolves to the known rank). Rebuilt when the spellbook changes.
local candidates = {}
local function Candidates(band)
    local list = candidates[band]
    if list then return list end
    list = {}
    for _, id in ipairs(band.spells) do
        if ns.IsKnown(id) then
            list[#list + 1] = id
            local name = ns.SpellName(id)
            if name then list[#list + 1] = name end
        end
    end
    candidates[band] = list
    return list
end
ns.RegisterEvent("SPELLS_CHANGED", function() wipe(candidates) end)

-- a band's answer: value + "plain" | "secret", or nil when nothing can tell
local function Ask(band)
    if C_Spell and C_Spell.IsSpellInRange then
        for _, spell in ipairs(Candidates(band)) do
            local ok, r = pcall(C_Spell.IsSpellInRange, spell, "target")
            if ok then
                if ns.IsSecret(r) then return r, "secret" end
                if r ~= nil then return (r == true or r == 1), "plain" end
            end
        end
    end
    -- interact distances are restricted on enemies in combat: out of combat only
    if band.interact and CheckInteractDistance and not ns.InCombat() then
        local ok, r = pcall(CheckInteractDistance, "target", band.interact)
        if ok then
            if ns.IsSecret(r) then return r, "secret" end
            if r ~= nil then return r and true or false, "plain" end
        end
    end
end

function range:Update()
    local r = self.region
    if not UnitExists("target") then
        self.mode = L["no target"]
        self:SetBase(ns.Colorize(HEX.hudMuted, L["NO TARGET"]))
        for _, l in ipairs(self.layers) do l:SetAlpha(0) end
        return
    end
    local farthest, mode
    for i, band in ipairs(self:Bands()) do
        local layer = self.layers[i]
        local answer, kind = Ask(band)
        if kind == "secret" then
            mode = L["secret values"]
            if not (layer.SetAlphaFromBoolean and pcall(layer.SetAlphaFromBoolean, layer, answer, 1, 0)) then
                layer:SetAlpha(0)
                mode = L["secret values, but SetAlphaFromBoolean is missing"]
            end
        elseif kind == "plain" then
            mode = mode or L["plain values"]
            layer:SetAlpha(answer and 1 or 0)
        else
            layer:SetAlpha(0)
        end
        if kind and not farthest then farthest = { band = band, first = (i == 1) } end
    end
    self.mode = mode or L["no range data for this target"]
    local text
    if not farthest then
        text = ns.Colorize(HEX.hudMuted, "—")
    elseif farthest.first and farthest.band.yards > 0 then
        text = ns.Colorize(HEX.hudAlert, L["OUT OF RANGE"])
    elseif farthest.band.yards > 0 then
        text = ns.Colorize(HEX.hudAlert, L["BEYOND %d YD"]:format(farthest.band.yards))
    else
        text = ns.Colorize(HEX.hudAlert, L["BEYOND MELEE"])
    end
    self:SetBase(text)
end

-- the text under the layers, only touched when it changes
function range:SetBase(text)
    if text == self.baseText then return end
    self.baseText = text
    self.region.base:SetText(text)
end

function range:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= (ns.Char().range.interval or 0.1) then
        self.elapsed = 0
        self:Update()
    end
end

function range:Refresh()
    self:BuildLayers()
    self:ApplyStyle()
    if self:IsAvailable() then self:Update() end
end

ns.RANGE_RATES = { { 0.05, "20/s" }, { 0.1, "10/s" }, { 0.2, "5/s" }, { 0.5, "2/s" }, { 1, "1/s" } }
