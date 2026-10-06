-- ---------------------------------------------------------------------------
-- The HUD: one movable frame that stacks "elements" top to bottom (health,
-- resource, combo points, range, cooldown bars, module parts such as the
-- poison tracker). Elements register themselves; the player picks order and
-- visibility in the Layout tab. The frame hangs by its top edge, so its
-- height can change without the frame wandering.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local UI = ns.UI

local W, GAP = 220, 4
local HUD = { elements = {}, byKey = {}, WIDTH = W, GAP = GAP }
ns.HUD = HUD

local f = CreateFrame("Frame", "EverFrameHUD", UIParent)
f:SetSize(W, 40)
-- optional backdrop behind the whole stack
f.backdrop = CreateFrame("Frame", nil, f)
f.backdrop:SetPoint("TOPLEFT", -5, 5)
f.backdrop:SetPoint("BOTTOMRIGHT", 5, -5)
f.backdrop:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
ns.Skin(f.backdrop, T.hudBackdrop, T.hudLine)
f.backdrop:Hide()
f:SetPoint("TOP", UIParent, "CENTER", 0, -120)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
HUD.frame = f

local function Settings() return ns.Char().hud end

-- ---------------------------------------------------------------------------
-- Element registry
--   def.key, def.label, def.order       identity and default position
--   def:Build(parent)                   creates def.region (once)
--   def.height                          stacked height (default Place)
--   def:Place(y) -> usedHeight          custom placement (optional)
--   def:IsAvailable() -> ok, reason     class/module checks (optional)
--   def.secure                          has protected children: no layout in combat
--   def:OnUpdate(elapsed), def:Refresh() optional hooks
-- ---------------------------------------------------------------------------
function HUD:Register(def)
    assert(def.key and not self.byKey[def.key], "duplicate HUD element")
    self.byKey[def.key] = def
    table.insert(self.elements, def)
    table.sort(self.elements, function(a, b) return (a.order or 50) < (b.order or 50) end)
    if def.Build then def:Build(f) end
    if def.region then def.region:Hide() end
    return def
end

-- ---------------------------------------------------------------------------
-- Look: per part (def.style = defaults, saved in style.parts[key]) and for
-- the whole frame (width, spacing, backdrop, edge). Changes apply right away.
-- ---------------------------------------------------------------------------
HUD.FRAME_DEFAULTS = { width = W, gap = GAP, backdrop = false, backdropAlpha = T.hudBackdrop[4] }

-- Edge: every part inside the frame (bars, combo points, range, each
-- cooldown icon, poison tiles) has a 1 px line around it, black by default.
-- Per part ("edge" in its style) it takes the edge color of the frame.
-- Parts hand in their skinned frames (HUD:AddEdge) or a shaped edge texture
-- (HUD:AddEdgeTexture) with their key; others paint with HUD:EdgeColor(key)
-- and register a repaint with HUD:OnEdges(fn).
HUD.edgeFrames, HUD.edgeTextures, HUD.edgeHooks = {}, {}, {}

function HUD:EdgeOn(key) return self:Get(key, "edge") == true end

function HUD:EdgeColor(key)
    if key and self:EdgeOn(key) then return self:FrameGet("edgeColor") or T.accent end
    return T.hudLine
end

function HUD:AddEdge(frame, key)
    frame.edgeKey = key
    table.insert(self.edgeFrames, frame)
    frame.baseEdge = self:EdgeColor(key)
    ns.SetEdgeColor(frame)
end

function HUD:AddEdgeTexture(tex, key)
    tex.edgeKey = key
    table.insert(self.edgeTextures, tex)
    tex:SetVertexColor(unpack(self:EdgeColor(key)))
end

function HUD:OnEdges(fn) table.insert(self.edgeHooks, fn) end

function HUD:ApplyEdges()
    for _, fr in ipairs(self.edgeFrames) do
        fr.baseEdge = self:EdgeColor(fr.edgeKey)
        ns.SetEdgeColor(fr)
    end
    for _, t in ipairs(self.edgeTextures) do t:SetVertexColor(unpack(self:EdgeColor(t.edgeKey))) end
    for _, fn in ipairs(self.edgeHooks) do ns.SafeCall(fn) end
end

-- Layout > Frame: all parts at once. On when every part has its edge on.
function HUD:AllEdges()
    for _, def in ipairs(self.elements) do
        if not self:EdgeOn(def.key) then return false end
    end
    return #self.elements > 0
end

function HUD:SetAllEdges(on)
    local parts = ns.Char().style.parts
    for _, def in ipairs(self.elements) do
        parts[def.key] = parts[def.key] or {}
        parts[def.key].edge = on and true or nil
    end
    self:ApplyEdges()
    ns.Fire("HUD_STYLE_CHANGED", "frame", "edge")
end

function HUD:Get(key, field)
    local saved = ns.Char().style.parts[key]
    local v = saved and saved[field]
    if v ~= nil then return v end
    local def = self.byKey[key]
    local defaults = (def and def.style) or self.sharedStyles[key]
    return defaults and defaults[field]
end

function HUD:Set(key, field, value)
    local parts = ns.Char().style.parts
    parts[key] = parts[key] or {}
    parts[key][field] = value
    local def = self.byKey[key]
    if def and def.ApplyStyle then def:ApplyStyle() end
    if self.sharedApply[key] then self.sharedApply[key]() end
    if field == "edge" then self:ApplyEdges() end
    self:ApplyLayout()
    ns.Fire("HUD_STYLE_CHANGED", key, field)
end

-- styles shared by several parts (all cooldown bars use "cooldowns")
HUD.sharedStyles, HUD.sharedApply = {}, {}
function HUD:RegisterSharedStyle(key, defaults, apply)
    self.sharedStyles[key] = defaults
    self.sharedApply[key] = apply
end

function HUD:FrameGet(field)
    local v = ns.Char().style.frame[field]
    if v == nil then v = self.FRAME_DEFAULTS[field] end
    return v
end

function HUD:ApplyFrameStyle()
    self.WIDTH = self:FrameGet("width")
    self.GAP = self:FrameGet("gap")
    f:SetWidth(self.WIDTH)
    f.backdrop:SetShown(self:FrameGet("backdrop") and true or false)
    local c = self:FrameGet("backdropColor") or T.hudBackdrop
    ns.SetFill(f.backdrop, { c[1], c[2], c[3], self:FrameGet("backdropAlpha") })
    self:ApplyEdges()
    for _, def in ipairs(self.elements) do
        if def.ApplyStyle then ns.SafeCall(def.ApplyStyle, def) end
    end
    for _, fn in pairs(self.sharedApply) do ns.SafeCall(fn) end
end

function HUD:SetFrame(field, value)
    ns.Char().style.frame[field] = value
    self:ApplyFrameStyle()
    self:ApplyLayout()
    ns.Fire("HUD_STYLE_CHANGED", "frame", field)
end

-- back to the default look of one part ("frame" = the whole frame)
function HUD:ResetStyle(key)
    local style = ns.Char().style
    if key == "frame" then
        style.frame = {}
    else
        style.parts[key] = nil
    end
    self:ApplyFrameStyle()
    self:ApplyLayout()
    ns.Fire("HUD_STYLE_CHANGED", key)
end

-- stacked height of a part: its style, else its fixed height
function HUD:Height(def)
    return self:Get(def.key, "height") or def.height
end

function HUD:IsAvailable(def)
    if not def.IsAvailable then return true end
    return def:IsAvailable()
end

function HUD:IsHidden(key)
    return ns.Char().layout.hidden[key] and true or false
end

function HUD:SetHidden(key, hidden)
    ns.Char().layout.hidden[key] = hidden and true or nil
    self:ApplyLayout()
end

-- saved order + elements the saved order doesn't know yet (slotted in behind
-- the element that precedes them by default)
function HUD:Order()
    local layout = ns.Char().layout
    local order, seen = {}, {}
    if type(layout.order) == "table" then
        for _, k in ipairs(layout.order) do
            if self.byKey[k] and not seen[k] then
                seen[k] = true
                order[#order + 1] = k
            end
        end
    end
    for i, def in ipairs(self.elements) do
        if not seen[def.key] then
            local pos = #order + 1
            local prev = self.elements[i - 1]
            if prev then
                for j, k in ipairs(order) do
                    if k == prev.key then pos = j + 1 break end
                end
            else
                pos = 1
            end
            table.insert(order, pos, def.key)
            seen[def.key] = true
        end
    end
    layout.order = order
    return order
end

-- does this part concern the character at all? (poison tiles for rogues,
-- combo points for classes that have them) Other parts stay out of sight.
function HUD:IsRelevant(def)
    if not def.IsRelevant then return true end
    return def:IsRelevant() and true or false
end

-- the order as the Layout tab shows it: only parts that concern the character
function HUD:VisibleOrder()
    local out = {}
    for _, k in ipairs(self:Order()) do
        if self:IsRelevant(self.byKey[k]) then out[#out + 1] = k end
    end
    return out
end

-- swaps with the nearest neighbour the player can see
function HUD:Move(key, dir)
    local order = self:Order()
    local i = ns.IndexOf(order, key)
    if not i then return end
    local j = i + dir
    while order[j] and not self:IsRelevant(self.byKey[order[j]]) do j = j + dir end
    if not order[j] then return end
    order[i], order[j] = order[j], order[i]
    self:ApplyLayout()
end

-- would a layout pass touch protected frames right now?
local function NeedsSecureLayout()
    for _, def in ipairs(HUD.elements) do
        if def.secure and (def.shown or HUD:IsAvailable(def)) then return true end
    end
    return false
end

local pendingLayout = false

function HUD:ApplyLayout()
    if ns.InCombat() and NeedsSecureLayout() then
        pendingLayout = true
        return false
    end
    pendingLayout = false
    local y = 0
    for _, key in ipairs(self:Order()) do
        local def = self.byKey[key]
        local show = not self:IsHidden(key) and self:IsAvailable(def)
        local used
        if show then
            if def.Place then
                used = def:Place(y)
            elseif def.region then
                def.region:ClearAllPoints()
                def.region:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
                def.region:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
                local h = self:Height(def)
                def.region:SetHeight(h)
                def.region:Show()
                used = h
            end
        end
        if used and used > 0 then
            def.shown = true
            y = y - used - self.GAP
        else
            def.shown = false
            if def.HideAll then def:HideAll() elseif def.region then def.region:Hide() end
        end
    end
    f:SetHeight(math.max(8, -y - self.GAP))
    ns.Fire("LAYOUT_APPLIED")
    return true
end

function HUD:IsLayoutPending() return pendingLayout end

-- ---------------------------------------------------------------------------
-- Position: TOP of the frame at (x, y) from the bottom center of the screen
-- ---------------------------------------------------------------------------
local pendingPosition = false

function HUD:ApplyPosition()
    if ns.InCombat() and NeedsSecureLayout() then pendingPosition = true return end
    pendingPosition = false
    local h = Settings()
    f:ClearAllPoints()
    if h.pos then
        f:SetPoint("TOP", UIParent, "BOTTOM", h.centerX and 0 or h.pos.x, h.pos.y)
    else
        f:SetPoint("TOP", UIParent, "CENTER", 0, -120)
    end
end

-- turn wherever the frame is now into the saved top-center form
local function SaveFromFrame()
    local top, cx = f:GetTop(), f:GetCenter()
    if not (top and cx) then return end
    local uiW = UIParent:GetWidth() * UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    local h = Settings()
    h.pos = { x = h.centerX and 0 or (cx - uiW / 2), y = top }
    HUD:ApplyPosition()
end

function HUD:ResetPosition()
    local h = Settings()
    h.pos = nil
    self:ApplyPosition()
end

function HUD:SetCenterX(on)
    local h = Settings()
    h.centerX = on and true or false
    if on then
        if h.pos then h.pos.x = 0 else SaveFromFrame() end
    end
    self:ApplyPosition()
    self:UpdateMover()
    ns.Fire("HUD_SETTINGS_CHANGED")
end

function HUD:SetScale(v)
    v = math.max(0.5, math.min(2, v))
    local h = Settings()
    local old = h.scale or 1
    -- offsets scale with the frame: keep its top edge where it is
    if h.pos then
        h.pos.x, h.pos.y = h.pos.x * old / v, h.pos.y * old / v
    end
    h.scale = v
    f:SetScale(v)
    self:ApplyPosition()
end

-- ---------------------------------------------------------------------------
-- Moving: a tinted plate marks the drag area while unlocked
-- ---------------------------------------------------------------------------
f.mover = CreateFrame("Frame", nil, f)
f.mover:SetPoint("TOPLEFT", -6, 6)
f.mover:SetPoint("BOTTOMRIGHT", 6, -6)
f.mover:SetFrameLevel(f:GetFrameLevel())
ns.Skin(f.mover, T.accentSoft, T.accent)
f.mover.text = ns.HudText(f.mover, 11)
f.mover.text:SetPoint("BOTTOM", f.mover, "TOP", 0, 4)
ns.Color(f.mover.text, T.accent)
f.mover:Hide()
f.mover.center = UI.CheckRow(f.mover, L["Center horizontally"],
    function() return Settings().centerX end,
    function(v) HUD:SetCenterX(v) end, 150)
f.mover.center:SetPoint("TOP", f.mover, "BOTTOM", 0, -4)
ns.Color(f.mover.center.label, T.accent)

function HUD:UpdateMover()
    local h = Settings()
    f.mover.text:SetText(h.centerX and L["Drag up or down  ·  /ef lock"] or L["Drag to move  ·  /ef lock"])
    f.mover.center:Refresh()
end

function HUD:SetLocked(locked)
    Settings().locked = locked and true or false
    f:EnableMouse(not locked)
    f.mover:SetShown(not locked)
    self:UpdateMover()
    ns.Fire("HUD_SETTINGS_CHANGED")
end

function HUD:IsLocked() return Settings().locked and true or false end

-- while centered, dragging follows the cursor vertically only
local vDrag = CreateFrame("Frame")
vDrag:Hide()
vDrag:SetScript("OnUpdate", function(self)
    local _, cy = GetCursorPosition()
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "BOTTOM", 0, self.top + cy / f:GetEffectiveScale() - self.cy)
end)

f:SetScript("OnDragStart", function(self)
    if Settings().locked or ns.InCombat() then return end
    if Settings().centerX then
        local _, cy = GetCursorPosition()
        vDrag.cy, vDrag.top = cy / self:GetEffectiveScale(), self:GetTop() or 0
        vDrag:Show()
    else
        self:StartMoving()
    end
end)
f:SetScript("OnDragStop", function(self)
    if vDrag:IsShown() then
        vDrag:Hide()
    else
        self:StopMovingOrSizing()
    end
    SaveFromFrame()
end)

-- ---------------------------------------------------------------------------
-- Visibility: optional fade out of combat; holding the chosen key shows it
-- ---------------------------------------------------------------------------
HUD.HOLD_KEYS = { "ALT", "CTRL", "SHIFT" }
local function HoldKeyDown(key)
    if key == "ALT" then return IsAltKeyDown() end
    if key == "CTRL" then return IsControlKeyDown() end
    if key == "SHIFT" then return IsShiftKeyDown() end
    return false
end
function HUD:IsHoldKeyDown() return HoldKeyDown(Settings().holdKey or "ALT") end

-- when the frame steps aside (hud.hide); unlocked or in the layout editor it always shows
HUD.HIDE_MODES = { "never", "combat", "target", "vehicle" }
local function InVehicle()
    local ok, v = pcall(function()
        return (UnitInVehicle and UnitInVehicle("player")) or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
    end)
    return ok and not ns.IsSecret(v) and v and true or false
end
function HUD:ShouldHide()
    local h = Settings()
    if not h.locked or HUD.preview then return false end
    local mode = h.hide or "never"
    if mode == "combat" then return not UnitAffectingCombat("player") end
    if mode == "target" then return not UnitExists("target") end
    if mode == "vehicle" then return InVehicle() end
    return false
end

local held = false
f:SetScript("OnUpdate", function(self, elapsed)
    local h = Settings()
    local wanted = 1
    if HUD:ShouldHide() then wanted = 0 end
    local holding = wanted == 0 and HoldKeyDown(h.holdKey)
    if holding then
        self:SetAlpha(1)
        held = true
    else
        if held then
            held = false
            self:SetAlpha(wanted)
        end
        local a = self:GetAlpha()
        if a ~= wanted then
            local step = elapsed * 4
            a = (a < wanted) and math.min(wanted, a + step) or math.max(wanted, a - step)
            self:SetAlpha(a)
        end
    end
    -- faded out completely: the parts rest until the frame shows again
    if wanted == 0 and not holding and self:GetAlpha() == 0 then return end
    for _, def in ipairs(HUD.elements) do
        if def.shown and def.OnUpdate then def:OnUpdate(elapsed) end
    end
end)

-- ---------------------------------------------------------------------------
-- Settings arrive with the login; resets re-read everything
-- ---------------------------------------------------------------------------
local function ApplyAll()
    local h = Settings()
    f:SetScale(h.scale or 1)
    HUD:ApplyFrameStyle()
    HUD:SetLocked(h.locked)
    HUD:ApplyPosition()
    for _, def in ipairs(HUD.elements) do
        if def.Refresh then ns.SafeCall(def.Refresh, def) end
    end
    HUD:ApplyLayout()
end

ns.On("LOGIN", ApplyAll)
ns.On("SETTINGS_RESET", ApplyAll)
ns.On("MODULES_CHANGED", function() if ns.ready then HUD:ApplyLayout() end end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingLayout then HUD:ApplyLayout() end
    if pendingPosition then HUD:ApplyPosition() end
end)
