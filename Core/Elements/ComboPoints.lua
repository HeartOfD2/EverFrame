-- ---------------------------------------------------------------------------
-- Combo points: one pip per point (bars, circles or diamonds); lit pips are
-- crimson, at the maximum every pip turns gold and plays the chosen effect.
-- Shown for classes that have combo points; for druids the row dims outside
-- Cat Form. When the count itself is secret, the game draws it: every pip
-- gets a status bar ranging from point i-1 to i (full from point i on), plus
-- a gold one ranging from max-1 to max -- no comparison on our side.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local HUD = ns.HUD

local PIP_GAP = 5
local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4

-- current combo points: plain number, or nil + the secret value
local function ReadComboPoints()
    local cp
    if GetComboPoints then
        local ok, v = pcall(GetComboPoints, "player", "target")
        if ok then cp = v end
    end
    if (ns.IsSecret(cp) or cp == nil) and UnitPower then
        local ok, v = pcall(UnitPower, "player", COMBO)
        if ok then cp = v end
    end
    if ns.IsSecret(cp) then return nil, cp end
    if type(cp) ~= "number" then return nil end
    return cp
end

local function ReadMax()
    local ok, v = pcall(UnitPowerMax, "player", COMBO)
    if ok and type(v) == "number" and not ns.IsSecret(v) and v > 0 then return v end
    return 5
end

-- the last value and when it last dropped (a finisher spent the points);
-- modules use this to know how many points a finisher just consumed
local state = { cp = 0, before = 0, droppedAt = 0 }
ns.combo = state

-- returns the plain count (last known while secret) and the secret value, if any
local function Poll()
    local cp, hidden = ReadComboPoints()
    if cp then
        if cp < state.cp then state.before, state.droppedAt = state.cp, GetTime() end
        state.cp = cp
    end
    return state.cp, hidden
end
ns.PollComboPoints = Poll

function ns.ComboPointsSpent(window)
    if state.cp > 0 then return state.cp end
    if state.before > 0 and GetTime() - state.droppedAt <= (window or 0.5) then return state.before end
    return nil
end

-- shapes of the points and what happens when all points are full
local SHAPE_FILE = {
    circles  = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Circle",
    diamonds = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Diamond",
}
ns.COMBO_SHAPES = { "bars", "circles", "diamonds" }
ns.COMBO_EFFECTS = { "glow", "pulse", "wave", "none" }

-- a sound when all points are full: { key, label, SOUNDKIT name, kit ID }
ns.COMBO_SOUNDS = {
    { "raid",      L["Raid warning"],        "RAID_WARNING", 8959 },
    { "ready",     L["Ready check"],         "READY_CHECK", 8960 },
    { "boss",      L["Boss warning"],        "RAID_BOSS_EMOTE_WARNING", 12197 },
    { "bossTell",  L["Boss whisper"],        "UI_RAID_BOSS_WHISPER_WARNING", 37666 },
    { "ping",      L["Map ping"],            "MAP_PING", 3175 },
    { "tell",      L["Whisper"],             "TELL_MESSAGE", 3081 },
    { "gm",        L["GM message"],          "GM_CHAT_WARNING", 15273 },
    { "alarm1",    L["Alarm clock 1"],       "ALARM_CLOCK_WARNING_1", 18871 },
    { "alarm2",    L["Alarm clock 2"],       "ALARM_CLOCK_WARNING_2", 12867 },
    { "alarm3",    L["Alarm clock 3"],       "ALARM_CLOCK_WARNING_3", 12889 },
    { "tick",      L["Countdown tick"],      "UI_BATTLEGROUND_COUNTDOWN_TIMER", 25477 },
    { "go",        L["Countdown end"],       "UI_BATTLEGROUND_COUNTDOWN_FINISHED", 25478 },
    { "bg",        L["Battleground ready"],  "PVP_THROUGH_QUEUE", 8459 },
    { "role",      L["Role check"],          "LFG_ROLE_CHECK", 17317 },
    { "reward",    L["Reward"],              "LFG_REWARDS", 17316 },
    { "trap",      L["Trap ready"],          "UI_PET_BATTLES_TRAP_READY", 28814 },
    { "quest",     L["Quest complete"],      "IG_QUEST_LIST_COMPLETE", 878 },
    { "questAuto", L["Quest done (short)"],  "UI_AUTO_QUEST_COMPLETE", 23404 },
    { "coins",     L["Coins"],               "LOOT_WINDOW_COIN_SOUND", 120 },
    { "invite",    L["Invite"],              "IG_PLAYER_INVITE", 880 },
    { "auction",   L["Auction house"],       "AUCTION_WINDOW_OPEN", 5274 },
}
function ns.PlayComboSound(key)
    for _, s in ipairs(ns.COMBO_SOUNDS) do
        if s[1] == key then
            local kit = rawget(_G, "SOUNDKIT")
            local id = (kit and kit[s[3]]) or s[4]
            if PlaySound then pcall(PlaySound, id, "Master") end
            return
        end
    end
end

local combo = HUD:Register({
    key = "combo", order = 30, height = 12,
    label = L["Combo points"],
    style = { height = 12, shape = "bars", maxEffect = "glow", soundOn = false, sound = "raid" },
    Build = function(self, parent)
        self.region = CreateFrame("Frame", nil, parent)
        self.region:SetHeight(self.height)
        self.sets = {}     -- shape -> its pips
        self.pips = {}
        self.count = 0
        self.effect = "glow"
        self.clock = 0
        self.elapsed = 0
    end,
})

function combo:IsRelevant() return ns.ClassPack().comboPoints and true or false end

function combo:IsAvailable()
    if ns.ClassPack().comboPoints then return true end
    return false, L["only for classes with combo points"]
end

-- the effect at the maximum (1.0 only knew glow on/off)
local function MaxEffect()
    local saved = ns.Char().style.parts.combo
    if saved and saved.maxEffect == nil and saved.glow == false then return "none" end
    return HUD:Get("combo", "maxEffect") or "glow"
end

local function Overlay(p, layer, sub, file, inset)
    local t = p:CreateTexture(nil, layer, nil, sub)
    t:SetPoint("TOPLEFT", -inset, inset)
    t:SetPoint("BOTTOMRIGHT", inset, -inset)
    t:SetTexture(file or ns.WHITE)
    return t
end

local function MakePip(parent, shape)
    local file = SHAPE_FILE[shape]
    local p = CreateFrame("Frame", nil, parent)
    p.file = file
    if file then
        p.edge = Overlay(p, "BACKGROUND", -7, file, 1)       -- outline: the shape, 1 px larger
        HUD:AddEdgeTexture(p.edge, "combo")
        p.track = Overlay(p, "BACKGROUND", -6, file, 0)
        p.track:SetVertexColor(unpack(T.hudTrack))
    else
        ns.Skin(p, T.hudTrack, T.hudLine)
        HUD:AddEdge(p, "combo")
    end
    p.glow = Overlay(p, "BACKGROUND", -8, file, file and 3 or 2)   -- halo just outside
    p.glow:SetBlendMode("ADD")
    p.glow:Hide()
    p.fill = Overlay(p, "ARTWORK", 1, file, 0)
    p.fill:Hide()
    if not file then
        p.sheen = p:CreateTexture(nil, "ARTWORK", nil, 3)
        p.sheen:SetPoint("TOPLEFT")
        p.sheen:SetPoint("TOPRIGHT")
        p.sheen:SetHeight(1)
        p.sheen:SetColorTexture(unpack(T.sheen))
    end
    p.shine = Overlay(p, "OVERLAY", 1, file, 0)
    p.shine:SetBlendMode("ADD")
    p.shine:SetAlpha(0)
    p.flash = Overlay(p, "OVERLAY", 2, file, 0)        -- quick pop when a point lands
    p.flash:SetBlendMode("ADD")
    p.flash:SetAlpha(0)
    -- secret counts: the game fills these (see the top of the file)
    for _, key in ipairs({ "sbar", "sbarMax" }) do
        local b = CreateFrame("StatusBar", nil, p)
        b:SetAllPoints()
        b:SetStatusBarTexture(file or ns.WHITE)
        b:SetFrameLevel(p:GetFrameLevel() + (key == "sbar" and 1 or 2))
        b:Hide()
        p[key] = b
    end
    local ag = p.flash:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.75)
    a:SetToAlpha(0)
    a:SetDuration(0.3)
    p.pop = ag
    return p
end

-- pips hang by their center, so the pulse can scale them in place
local function Place(p, scale)
    p:SetScale(scale)
    p:ClearAllPoints()
    p:SetPoint("CENTER", p:GetParent(), "TOPLEFT", p.cx / scale, -p.cy / scale)
    p.scaled = scale ~= 1
end

function combo:BuildPips(n)
    local shape = HUD:Get("combo", "shape") or "bars"
    if not SHAPE_FILE[shape] then shape = "bars" end
    for key, set in pairs(self.sets) do
        if key ~= shape then for _, p in ipairs(set) do p:Hide() end end
    end
    self.sets[shape] = self.sets[shape] or {}
    self.pips = self.sets[shape]
    local h = HUD:Height(self)
    local slot = (HUD.WIDTH - (n - 1) * PIP_GAP) / n
    local w, ph = slot, h
    if shape ~= "bars" then w, ph = math.min(slot, h), math.min(slot, h) end
    local mc = HUD:Get("combo", "maxColor") or T.comboMax
    for i = 1, n do
        local p = self.pips[i] or MakePip(self.region, shape)
        self.pips[i] = p
        p.glow:SetVertexColor(mc[1], mc[2], mc[3], 0.55)
        p:SetSize(w, ph)
        p.cx, p.cy = (i - 1) * (slot + PIP_GAP) + slot / 2, h / 2
        Place(p, 1)
        p.shine:SetAlpha(0)
        p.state = nil
        p:Show()
    end
    for i = n + 1, #self.pips do self.pips[i]:Hide() end
    self.count = n
end

-- a secret count: hand it to the pips' status bars
function combo:ShowHidden(v, max)
    self.mode = "secret"
    local c = HUD:Get("combo", "color") or T.combo
    local mc = HUD:Get("combo", "maxColor") or T.comboMax
    for i = 1, self.count do
        local p = self.pips[i]
        if p.state ~= "hidden" then
            p.fill:Hide()
            p.glow:Hide()
            p.shine:SetAlpha(0)
            if p.scaled then Place(p, 1) end
            p.sbar:SetStatusBarColor(c[1], c[2], c[3])
            p.sbarMax:SetStatusBarColor(mc[1], mc[2], mc[3])
            p.sbar:Show()
            p.sbarMax:Show()
            p.state = "hidden"
        end
        p.sbar:SetMinMaxValues(i - 1, i)
        p.sbar:SetValue(v)
        p.sbarMax:SetMinMaxValues(max - 1, max)
        p.sbarMax:SetValue(v)
    end
end

-- pip states: 0 = empty, 1 = lit, 2 = lit at maximum, "hidden" = drawn by the game
function combo:Update()
    local max = ReadMax()
    if max ~= self.count then self:BuildPips(max) end
    local cp, hidden = Poll()
    if hidden ~= nil then return self:ShowHidden(hidden, max) end
    if self.mode == "secret" then
        for i = 1, self.count do
            local p = self.pips[i]
            p.sbar:Hide()
            p.sbarMax:Hide()
            p.state = nil
        end
    end
    self.mode = "plain"
    local atMax = cp >= max
    -- the moment the points fill up (only readable values; secret ones stay quiet)
    if atMax and cp > 0 and not self.wasMax and HUD:Get("combo", "soundOn") then
        ns.PlayComboSound(HUD:Get("combo", "sound"))
    end
    self.wasMax = atMax and cp > 0
    for i = 1, self.count do
        local p = self.pips[i]
        local s = (i > cp) and 0 or (atMax and 2 or 1)
        if s ~= p.state then
            if s == 0 then
                p.fill:Hide()
            else
                local c = (s == 2) and (HUD:Get("combo", "maxColor") or T.comboMax) or (HUD:Get("combo", "color") or T.combo)
                ns.Gradient(p.fill, c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 1, c[1], c[2], c[3], 1, p.file)
                p.fill:SetAlpha(1)
                p.fill:Show()
                if (p.state or 0) == 0 then p.pop:Play() end
            end
            p.glow:SetShown(s == 2 and self.effect == "glow")
            if s ~= 2 then
                p.shine:SetAlpha(0)
                if p.scaled then Place(p, 1) end
            end
            p.state = s
        end
    end
    -- druids: points only matter in Cat Form (the energy form)
    if ns.playerClass == "DRUID" then
        local _, token = UnitPowerType("player")
        self.region:SetAlpha(token == "ENERGY" and 1 or 0.35)
    end
end

function combo:ApplyStyle()
    self.effect = MaxEffect()
    self.count = 0   -- rebuild the pips at the new size, shape and colors
end

-- at the maximum: glow = the halo breathes, pulse = the points beat,
-- wave = a light runs across the points, none = only the color changes
function combo:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= 0.05 then
        self.elapsed = 0
        self:Update()
    end
    local effect = self.effect
    if effect == "none" then return end
    self.clock = self.clock + elapsed
    local n = self.count
    local breathe = math.abs(math.sin(self.clock * 4))
    local beat = math.sin(self.clock * 7)
    beat = beat > 0 and beat or 0
    local head = (self.clock * 6) % (n + 3) - 1   -- the light's position, a short pause between runs
    for i = 1, n do
        local p = self.pips[i]
        if p.state == 2 then
            if effect == "glow" then
                p.glow:SetAlpha(0.3 + 0.7 * breathe)
                p.shine:SetAlpha(0.3 * breathe)
            elseif effect == "pulse" then
                Place(p, 1 + 0.18 * beat)
                p.shine:SetAlpha(0.35 * beat)
            elseif effect == "wave" then
                local near = math.max(0, 1 - math.abs(i - head) / 1.2)
                p.shine:SetAlpha(0.65 * near)
            end
        end
    end
end

function combo:Refresh()
    if self:IsAvailable() then self:Update() end
end

-- keep the count current even while the row is hidden (finisher timers need it)
local poller = CreateFrame("Frame")
local pollElapsed = 0
poller:SetScript("OnUpdate", function(_, elapsed)
    if combo.shown or not ns.ready or not ns.ClassPack().comboPoints then return end
    pollElapsed = pollElapsed + elapsed
    if pollElapsed >= 0.05 then
        pollElapsed = 0
        Poll()
    end
end)

ns.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    -- points belong to the target on this client: a retarget is no spend
    state.droppedAt = 0
end)
