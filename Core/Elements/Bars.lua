-- ---------------------------------------------------------------------------
-- Health and resource bars. Both texts take placeholders ({cur}, {max},
-- {pct}, {deficit}). The resource bar follows the current power type, so a
-- druid's bar turns from mana to energy or rage when the form changes.
-- Health and power may be secret in combat: they only ever go to the bar and
-- the game's own formatter, never into our own arithmetic.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local HUD = ns.HUD

local function MakeBar(parent, color, textSize, key)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(ns.WHITE)
    bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    bar:SetStatusBarColor(color[1], color[2], color[3])
    ns.Skin(bar, T.hudTrack, T.hudLine)
    ns.HUD:AddEdge(bar, key)
    local shade = bar:CreateTexture(nil, "ARTWORK", nil, 5)   -- over fill and track alike
    shade:SetAllPoints()
    ns.Gradient(shade, 0, 0, 0, 0.38, 0, 0, 0, 0)
    local sheen = bar:CreateTexture(nil, "ARTWORK", nil, 6)
    sheen:SetPoint("TOPLEFT")
    sheen:SetPoint("TOPRIGHT")
    sheen:SetHeight(1)
    sheen:SetColorTexture(unpack(T.sheen))
    bar.text = ns.HudText(bar, textSize)
    bar.text:SetPoint("CENTER", 0, 0)
    return bar
end

-- which formatting path the last update took (shown in the layout editor and /ef status)
ns.textModes = {}

-- the bar color a style asks for: "default" (the part's own), "class", "custom"
local function StyleColor(key, default)
    local mode = HUD:Get(key, "colorMode")
    if mode == "class" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[ns.playerClass or ""]
        if c then return { c.r, c.g, c.b } end
    elseif mode == "custom" then
        local c = HUD:Get(key, "color")
        if type(c) == "table" then return c end
    end
    return default
end
ns.StyleColor = StyleColor

-- text size, alignment and visibility of a bar's text
local function StyleText(key, fs)
    ns.ApplyFont(fs, HUD:Get(key, "textSize") or 12, "")
    local align = HUD:Get(key, "textAlign") or "CENTER"
    fs:ClearAllPoints()
    if align == "LEFT" then
        fs:SetPoint("LEFT", 6, 0)
    elseif align == "RIGHT" then
        fs:SetPoint("RIGHT", -6, 0)
    else
        fs:SetPoint("CENTER", 0, 0)
    end
    fs:SetJustifyH(align)
    fs:SetShown(HUD:Get(key, "showText") ~= false)
end

-- ---------------------------------------------------------------------------
-- Health
-- ---------------------------------------------------------------------------
local health = HUD:Register({
    key = "health", order = 10, height = 18,
    label = L["Health bar"],
    style = { height = 18, colorMode = "default", textSize = 12, textAlign = "CENTER", showText = true,
              warn = true, warnPct = 30 },
    Build = function(self, parent)
        local bar = MakeBar(parent, T.health, 12, "health")
        -- warning zone: the left 30% of the empty track glows red. It sits under
        -- the fill, so it only shows once health drops below it -- the game
        -- draws that comparison, we never touch the (secret) value
        local zone = CreateFrame("Frame", nil, bar)
        zone:SetPoint("TOPLEFT")
        zone:SetPoint("BOTTOMLEFT")
        zone:SetWidth(HUD.WIDTH * 0.3)
        bar.zoneFrame = zone
        zone:SetFrameLevel(bar:GetFrameLevel())
        local glow = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
        glow:SetAllPoints(zone)
        ns.Gradient(glow, T.danger[1], T.danger[2], T.danger[3], 0.55, T.danger[1], T.danger[2], T.danger[3], 1)
        bar.zone, bar.zoneGlow = zone, glow
        local breathe = glow:CreateAnimationGroup()
        breathe:SetLooping("BOUNCE")
        local a = breathe:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.35)
        a:SetDuration(0.7)
        a:SetSmoothing("IN_OUT")
        bar.breathe = breathe
        -- the zone's width comes from the frame width (ApplyStyle), never from
        -- the bar: a bar holding a secret value reports secret sizes
        self.region = bar
        self.elapsed = 0
    end,
})

function health:Update()
    local bar = self.region
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    ns.textModes.health = ns.SetValueText(bar.text, ns.Char().text.health or "{cur}", cur, max, function()
        return UnitHealthPercent("player", false, CurveConstants and CurveConstants.ScaleTo100)
    end)
end

-- events bring every change; the slow tick is only a safety net and keeps
-- the warning zone in step with the frame's fading
function health:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.2 then return end
    self.elapsed = 0
    self:Update()
    -- the zone rests while dead or while the frame fades
    local bar = self.region
    local on = self.warn ~= false and not UnitIsDeadOrGhost("player") and HUD.frame:GetAlpha() >= 0.99
    bar.zoneGlow:SetShown(on)
    if on and not bar.breathe:IsPlaying() then bar.breathe:Play() end
    if not on and bar.breathe:IsPlaying() then bar.breathe:Stop() end
end

function health:ApplyStyle()
    local bar = self.region
    local c = StyleColor("health", T.health)
    bar:SetStatusBarColor(c[1], c[2], c[3])
    StyleText("health", bar.text)
    bar.zoneFrame:SetWidth(HUD.WIDTH * (HUD:Get("health", "warnPct") or 30) / 100)
    self.warn = HUD:Get("health", "warn") ~= false
    if not self.warn then
        bar.zoneGlow:Hide()
        bar.breathe:Stop()
    end
end

health.Refresh = health.Update

-- ---------------------------------------------------------------------------
-- Resource (mana, rage, energy ...)
-- ---------------------------------------------------------------------------
local power = HUD:Register({
    key = "power", order = 20, height = 20,
    label = L["Resource bar"],
    style = { height = 20, colorMode = "default", textSize = 13, textAlign = "CENTER", showText = true },
    Build = function(self, parent)
        local bar = MakeBar(parent, ns.PowerColor("ENERGY"), 13, "power")
        -- crisp leading edge riding the end of the fill (anchored: no value math)
        bar.spark = bar:CreateTexture(nil, "ARTWORK", nil, 7)
        bar.spark:SetColorTexture(1, 1, 1, 0.5)
        bar.spark:SetWidth(1)
        bar.spark:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT")
        bar.spark:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
        self.region = bar
        self.elapsed = 0
    end,
})

function power:CurrentType()
    local pType, token = UnitPowerType("player")
    return pType, token
end

function power:Update()
    local bar = self.region
    local pType, token = self:CurrentType()
    if token ~= self.token then
        self.token = token
        local c = StyleColor("power", ns.PowerColor(token))
        bar:SetStatusBarColor(c[1], c[2], c[3])
    end
    local cur, max = UnitPower("player", pType), UnitPowerMax("player", pType)
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    ns.textModes.power = ns.SetValueText(bar.text, ns.Char().text.power or "{cur}", cur, max, function()
        return UnitPowerPercent("player", pType, false, CurveConstants and CurveConstants.ScaleTo100)
    end)
end

function power:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= 0.2 then
        self.elapsed = 0
        self:Update()
    end
end

function power:ApplyStyle()
    self.token = nil   -- recolor on the next update
    StyleText("power", self.region.text)
    self:Update()
end

power.Refresh = power.Update

for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT" }) do
    ns.RegisterUnitEvent(ev, "player", function() if health.shown then health:Update() end end)
end
for _, ev in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
    ns.RegisterUnitEvent(ev, "player", function() if power.shown then power:Update() end end)
end
