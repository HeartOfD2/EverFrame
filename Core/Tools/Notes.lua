-- ---------------------------------------------------------------------------
-- Notes: a notebook (colored groups holding notes) plus player notes (several
-- per player, kept under Name-Realm). Targeting a player pops their notes up
-- in a small window you can move, resize and lock; players without notes get
-- a slim "+ Note" bar there instead. Every note has a title plus created and
-- updated times. Saved account-wide; unit data is screened for secret values.
-- Any note can also sit on the screen as a sticky note (Stickies.lua), and
-- notes travel as a text code (Export / Import).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, App = ns.UI, ns.App
local Text, Skin, SetEdgeColor = ns.Text, ns.Skin, ns.SetEdgeColor
local Muted, IsBlank = ns.Muted, ns.IsBlank

-- group colors: the theme's tag palette (red, orange, amber, green, teal,
-- blue, violet, pink, gray, cyan), tuned per mode
local PALETTE = T.tags
local DATE_LONG = ns.LOCALE == "deDE" and "%d.%m.%Y %H:%M" or "%Y-%m-%d %H:%M"
local DATE_SHORT = ns.LOCALE == "deDE" and "%d.%m." or "%m-%d"

local function Now() return time and time() or 0 end
local function Stamp(t, short)
    if not t or t == 0 or not date then return "" end
    return date(short and DATE_SHORT or DATE_LONG, t)
end
local function Hex(c) return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local function Untitled(n) return (n.title and n.title ~= "") and n.title or L["(untitled)"] end

-- ---------------------------------------------------------------- storage
local NOTES_VERSION = 2

local function Migrate(d)
    -- a single notepad (older format) becomes the first note of a "General" group
    if not d.groups then
        d.groups = { { name = L["General"], color = 3, seq = 0, notes = {} } }
        if not IsBlank(d.pad) then
            local g = d.groups[1]
            g.seq = 1
            g.notes[1] = { title = L["Notepad"], text = d.pad, created = Now(), updated = Now(), titled = true }
        end
    end
    d.pad = nil
    -- one text per player (older format) -> that player's first note
    for key, p in pairs(d.players) do
        if not p.notes then
            p.notes = {}
            if not IsBlank(p.text) then
                p.notes[1] = { title = L["Note %d"]:format(1), text = p.text, created = p.t or Now(), updated = p.t or Now() }
            end
            p.seq, p.text, p.t = #p.notes, nil, nil
        end
        if #p.notes == 0 then d.players[key] = nil end
    end
    d.v = NOTES_VERSION
end

local function DB()
    local acct = ns.Acct()
    local d = acct.notes
    if type(d) ~= "table" then
        d = {}
        acct.notes = d
    end
    d.players = d.players or {}
    if d.v ~= NOTES_VERSION then Migrate(d) end
    return d
end

local function NewNote(container)
    container.seq = (container.seq or #container.notes) + 1
    local n = { title = L["Note %d"]:format(container.seq), text = "", created = Now(), updated = Now() }
    table.insert(container.notes, n)
    return n
end

local function RemoveNote(container, note)
    local i = ns.IndexOf(container.notes, note)
    if i then table.remove(container.notes, i) end
    return i
end

local function IsSticky(note) return note and note.sticky and note.sticky.open and true or false end

-- a fresh note nobody wrote into (no text, default title) goes away again
-- (unless it sits on the screen as a sticky note)
local function Discard(container, note)
    if container and note and IsBlank(note.text) and not note.titled and not IsSticky(note)
            and ns.IndexOf(container.notes, note) then
        RemoveNote(container, note)
        return true
    end
end

local function Touch(note) note.updated = Now() end

local function Latest(container)
    local best
    for _, n in ipairs(container.notes) do
        if not best or (n.updated or 0) >= (best.updated or 0) then best = n end
    end
    return best
end

-- ---------------------------------------------------------------- players
local function MyRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = ((GetRealmName and GetRealmName()) or ""):gsub("[%s%-]", "") end
    return r
end

-- class colors; darker in light mode so white and yellow names stay readable
local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "ff" .. HEX.value end
    if T.mode == "light" then return Hex({ c.r * 0.62, c.g * 0.62, c.b * 0.62 }) end
    return c.colorStr or Hex({ c.r, c.g, c.b })
end

local function DisplayName(p, short)
    local n = p.name or "?"
    if not short and p.realm and p.realm ~= MyRealm() then n = n .. "-" .. p.realm end
    return "|c" .. ClassHex(p.class) .. n .. "|r"
end

-- current target as a note key ("Name-Realm") + info; players only
local function TargetKey()
    if not UnitExists("target") then return end
    local isPlayer = UnitIsPlayer("target")
    if ns.IsSecret(isPlayer) or not isPlayer then return end
    local name, realm = UnitName("target")
    if ns.IsSecret(name) or ns.IsSecret(realm) or not name then return end
    if not realm or realm == "" then realm = MyRealm() end
    local _, class = UnitClass("target")
    if ns.IsSecret(class) then class = nil end
    return name .. "-" .. realm, { name = name, realm = realm, class = class }
end

local function Player(key) return key and DB().players[key] end

local function EnsurePlayer(key, info)
    local players = DB().players
    local p = players[key]
    if not p then
        p = { notes = {}, seq = 0 }
        players[key] = p
    end
    if info then
        p.name, p.realm = info.name, info.realm
        p.class = info.class or p.class
    end
    p.name = p.name or key:match("^(.-)%-") or key
    p.realm = p.realm or key:match("%-(.+)$")
    return p
end

local function DropPlayerIfEmpty(key)
    local p = Player(key)
    if p and #p.notes == 0 then DB().players[key] = nil end
end

local function KeyOf(p)
    for k, v in pairs(DB().players) do if v == p then return k end end
end

-- views register here and redraw when another view changed the data
local listeners = {}
local function Changed(source)
    for _, fn in ipairs(listeners) do fn(source) end
end

-- ---------------------------------------------------------------------------
-- For the sticky notes and the export: where a note lives, its color, name
-- ---------------------------------------------------------------------------
local Notes = { DB = DB, Untitled = Untitled, Touch = Touch, Stamp = Stamp, Changed = Changed }
ns.Notes = Notes
function Notes.OnChange(fn) listeners[#listeners + 1] = fn end

-- ---------------------------------------------------------------------------
-- In combat the sticky notes and the target popup can step aside, each with
-- its own switch (DB().hideInCombat); the HUD's "hold to show" key brings
-- them back while held, if wanted (DB().holdShowsNotes). Each sits on its
-- own layer frame, so hiding keeps every note's own shown state.
-- ---------------------------------------------------------------------------
local layers = {}
function Notes.Layer(key)
    local f = CreateFrame("Frame", "EverFrameNotesLayer_" .. key, UIParent)
    f:SetAllPoints(UIParent)
    layers[key] = f
    return f
end
function Notes.HideInCombat(key)
    local d = DB()
    d.hideInCombat = d.hideInCombat or {}
    return d.hideInCombat[key] and true or false
end
function Notes.SetHideInCombat(key, on)
    local d = DB()
    d.hideInCombat = d.hideInCombat or {}
    d.hideInCombat[key] = on and true or nil
end
local layerDriver = CreateFrame("Frame")
layerDriver:SetScript("OnUpdate", function()
    if not ns.ready then return end
    local inCombat = ns.InCombat()
    local held = inCombat and DB().holdShowsNotes and ns.HUD:IsHoldKeyDown()
    for key, layer in pairs(layers) do
        local show = not (inCombat and Notes.HideInCombat(key)) or held
        if layer:IsShown() ~= show then layer:SetShown(show) end
    end
end)

-- fn(note, kind, container, key): kind "g" = notebook group, "p" = player
function Notes.ForEach(fn)
    for _, g in ipairs(DB().groups) do
        for _, n in ipairs(g.notes) do fn(n, "g", g) end
    end
    for key, p in pairs(DB().players) do
        for _, n in ipairs(p.notes) do fn(n, "p", p, key) end
    end
end

function Notes.Owner(note)
    for _, g in ipairs(DB().groups) do
        if ns.IndexOf(g.notes, note) then return "g", g end
    end
    for key, p in pairs(DB().players) do
        if ns.IndexOf(p.notes, note) then return "p", p, key end
    end
end

function Notes.Color(kind, container)
    if kind == "g" then return PALETTE[container.color] or PALETTE[3] end
    local c = container and container.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[container.class]
    return c and { c.r, c.g, c.b } or { 0.62, 0.65, 0.70 }
end

-- the group name or the player's name, plain text
function Notes.OwnerName(kind, container)
    if kind == "g" then return (container.name ~= "") and container.name or L["(group)"] end
    return container.name or "?"
end

-- ---------------------------------------------------------------------------
-- Target popup: movable, resizable and lockable; geometry in DB().popup
-- ---------------------------------------------------------------------------
local COMPACT_H = 30
local POPUP_DEF = { point = "CENTER", x = 260, y = 120, w = 280, h = 170 }
local POPUP_MIN_W, POPUP_MIN_H = 220, 120

local pop = UI.Window("EverFrameTargetNote", POPUP_DEF.w, POPUP_DEF.h, "", { noEscape = true, fixed = true })
local popLayer = Notes.Layer("popup")
pop:SetParent(popLayer)
pop:SetFrameStrata("MEDIUM")
-- stepping aside in combat ends the writing (the text is saved as you type)
popLayer:SetScript("OnHide", function() if pop.body.edit:HasFocus() then pop.body.edit:ClearFocus() end end)
pop:SetMovable(true)
pop:SetResizable(true)
pop:SetClampedToScreen(true)
if pop.SetResizeBounds then pop:SetResizeBounds(POPUP_MIN_W, POPUP_MIN_H, 1200, 900) end
pop:RegisterForDrag("LeftButton")
pop:SetPoint(POPUP_DEF.point, UIParent, POPUP_DEF.point, POPUP_DEF.x, POPUP_DEF.y)
pop.title:SetPoint("TOPRIGHT", -112, -11)   -- long names stop short of the buttons
pop.title:SetJustifyH("LEFT")
pop.title:SetWordWrap(false)

local function Geom()
    local d = DB()
    d.popup = d.popup or {}
    return d.popup
end
function pop:IsLocked() return Geom().locked and true or false end
-- re-anchor by the top-left corner so the compact bar keeps its top edge
function pop:SaveGeometry()
    local l, t = self:GetLeft(), self:GetTop()
    if not (l and t) then return end
    local g = Geom()
    g.l, g.t, g.w = l, t, self:GetWidth()
    if not self.compact then g.h = self:GetHeight() end
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end
function pop:FullHeight() return math.max(POPUP_MIN_H, Geom().h or POPUP_DEF.h) end
function pop:ApplyGeometry()
    local g = Geom()
    self:ClearAllPoints()
    if g.l and g.t then
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.l, g.t)
    else
        self:SetPoint(POPUP_DEF.point, UIParent, POPUP_DEF.point, POPUP_DEF.x, POPUP_DEF.y)
    end
    self:SetWidth(math.max(POPUP_MIN_W, g.w or POPUP_DEF.w))
    self:SetHeight(self.compact and COMPACT_H or self:FullHeight())
    self:UpdateLock()
end

pop.grip = CreateFrame("Button", nil, pop)
pop.grip:SetSize(16, 16)
pop.grip:SetPoint("BOTTOMRIGHT", -2, 2)
pop.grip:SetFrameLevel(pop:GetFrameLevel() + 10)
pop.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
pop.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
pop.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
pop.grip:SetScript("OnMouseDown", function() if not pop:IsLocked() then pop:StartSizing("BOTTOMRIGHT") end end)
pop.grip:SetScript("OnMouseUp", function()
    pop:StopMovingOrSizing()
    pop:SaveGeometry()
end)

-- the lock, as on the sticky notes; shown in the compact bar too
pop.lockBtn = CreateFrame("Button", nil, pop)
pop.lockBtn:SetSize(18, 18)
pop.lockBtn:SetPoint("TOPRIGHT", -28, -6)
pop.lockBtn.icon = pop.lockBtn:CreateTexture(nil, "ARTWORK")
pop.lockBtn.icon:SetSize(14, 14)
pop.lockBtn.icon:SetPoint("CENTER")
pop.lockBtn.hl = pop.lockBtn:CreateTexture(nil, "HIGHLIGHT")
pop.lockBtn.hl:SetAllPoints()
ns.Color(pop.lockBtn.hl, T.hover)
pop.lockBtn:SetScript("OnClick", function()
    local g = Geom()
    g.locked = not g.locked or nil
    pop:UpdateLock()
end)
UI.Tooltip(pop.lockBtn, function()
    return { pop:IsLocked() and L["Unlock: allow moving and resizing"] or L["Lock position and size"] }
end, "ANCHOR_TOP")
function pop:UpdateLock()
    local locked = self:IsLocked()
    local c = locked and T.accent or T.muted
    self.lockBtn.icon:SetTexture("Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\" .. (locked and "Lock" or "Unlock"))
    self.lockBtn.icon:SetVertexColor(c[1], c[2], c[3], 1)
    self.grip:SetShown(not locked and not self.compact)
end
ns.Paint(function() if ns.ready then pop:UpdateLock() end end)
pop:SetScript("OnDragStart", function(self) if not self:IsLocked() then self:StartMoving() end end)
pop:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SaveGeometry()
end)

local popKey, popNote, dismissedKey
local RefreshPopup, NoteForTarget, OpenInNotes

-- the title opens this player's notes in the app (and still drags the popup)
pop.titleBtn = CreateFrame("Button", nil, pop)
pop.titleBtn:SetPoint("TOPLEFT", 8, -5)
pop.titleBtn:SetPoint("TOPRIGHT", -112, -5)
pop.titleBtn:SetHeight(22)
pop.titleBtn:RegisterForDrag("LeftButton")
pop.titleBtn.hl = pop.titleBtn:CreateTexture(nil, "HIGHLIGHT")
pop.titleBtn.hl:SetAllPoints()
ns.Color(pop.titleBtn.hl, T.hover)
pop.titleBtn:SetScript("OnClick", function() OpenInNotes() end)
pop.titleBtn:SetScript("OnDragStart", function() if not pop:IsLocked() then pop:StartMoving() end end)
pop.titleBtn:SetScript("OnDragStop", function()
    pop:StopMovingOrSizing()
    pop:SaveGeometry()
end)
UI.Tooltip(pop.titleBtn, function()
    local who = pop.who
    return { who and DisplayName(who) or L["NOTES"], L["Open in the notes"] }
end, "ANCHOR_TOP")

local function NavButton(dir, x)
    local b = CreateFrame("Button", nil, pop)
    b:SetSize(16, 16)
    b:SetPoint("TOPLEFT", x, -33)
    b.arrow = UI.Arrow(b, 12, dir)
    b.arrow:SetPoint("CENTER")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.1)
    return b
end
pop.prev = NavButton("left", 8)
pop.next = NavButton("right", 26)
pop.noteTitle = Text(pop, 12)
pop.noteTitle:SetPoint("TOPLEFT", 48, -34)
pop.noteTitle:SetPoint("TOPRIGHT", -126, -34)
pop.noteTitle:SetJustifyH("LEFT")
pop.noteTitle:SetWordWrap(false)
pop.date = CreateFrame("Frame", nil, pop)
pop.date:SetSize(100, 16)
pop.date:SetPoint("TOPRIGHT", -30, -33)
pop.date.text = Text(pop.date, 10)
pop.date.text:SetPoint("RIGHT")
pop.date:EnableMouse(true)
UI.Tooltip(pop.date, function()
    if not popNote then return end
    return { Untitled(popNote), L["Created: %s"]:format(Stamp(popNote.created)), L["Updated: %s"]:format(Stamp(popNote.updated)) }
end, "ANCHOR_TOP")

-- small red delete button right of the date: the first click arms it, the second deletes
pop.del = CreateFrame("Button", nil, pop)
pop.del:SetSize(16, 16)
pop.del:SetPoint("TOPRIGHT", -10, -33)
pop.del.bg = pop.del:CreateTexture(nil, "BACKGROUND")
pop.del.bg:SetAllPoints()
pop.del.x = Text(pop.del, 13)
pop.del.x:SetPoint("CENTER", 0, 1)
pop.del.x:SetText("×")
pop.del.hl = pop.del:CreateTexture(nil, "HIGHLIGHT")
pop.del.hl:SetAllPoints()
pop.del.hl:SetColorTexture(1, 1, 1, 0.15)
local delArmedUntil = 0
local function DisarmDelete()
    delArmedUntil = 0
    pop.del.bg:SetColorTexture(0.55, 0.12, 0.14, 1)
end
DisarmDelete()
UI.Tooltip(pop.del, { L["Delete this note"], L["Click twice to confirm."] }, "ANCHOR_TOP")

pop.body = UI.TextArea(pop)
pop.body:SetPoint("TOPLEFT", 10, -54)
pop.body:SetPoint("BOTTOMRIGHT", -10, 10)

pop.addBtn = UI.Button(pop, 64, "+ " .. L["Note"], function() NoteForTarget() end, 18)
pop.addBtn:SetPoint("TOPRIGHT", -50, -6)
pop.newBtn = UI.Button(pop, 22, "+", function() NoteForTarget() end, 18)
pop.newBtn:SetPoint("TOPRIGHT", -50, -6)
UI.Tooltip(pop.newBtn, { L["New note for this player"] }, "ANCHOR_TOP")

pop.close:SetScript("OnClick", function()
    dismissedKey = popKey   -- stays closed until you target someone else
    pop.body.edit:ClearFocus()
    pop:Hide()
end)

local function SetCompact(compact)
    pop.compact = compact
    for _, r in ipairs({ pop.body, pop.prev, pop.next, pop.noteTitle, pop.date, pop.del, pop.newBtn }) do
        r:SetShown(not compact)
    end
    pop.addBtn:SetShown(compact)
    pop:SetHeight(compact and COMPACT_H or pop:FullHeight())
    pop:UpdateLock()
end

local function ShowPopNote(p)
    local i = ns.IndexOf(p.notes, popNote) or 1
    pop.noteTitle:SetText(Untitled(popNote) .. "  " .. Muted(i .. "/" .. #p.notes))
    pop.date.text:SetText(Muted(Stamp(popNote.updated)))
    DisarmDelete()
    local many = #p.notes > 1
    pop.prev:SetAlpha(many and 1 or 0.3)
    pop.next:SetAlpha(many and 1 or 0.3)
    if not pop.body.edit:HasFocus() then pop.body:SetValue(popNote.text) end
end

local function Browse(step)
    local p = Player(popKey)
    if not (p and popNote and #p.notes > 1) then return end
    pop.body.edit:ClearFocus()
    local i = ns.IndexOf(p.notes, popNote) or 1
    popNote = p.notes[(i - 1 + step) % #p.notes + 1]
    ShowPopNote(p)
end
pop.prev:SetScript("OnClick", function() Browse(-1) end)
pop.next:SetScript("OnClick", function() Browse(1) end)

pop.del:SetScript("OnClick", function()
    local p = Player(popKey)
    if not (p and popNote) then return end
    if GetTime() > delArmedUntil then
        delArmedUntil = GetTime() + 3
        pop.del.bg:SetColorTexture(0.95, 0.22, 0.24, 1)
        pop.date.text:SetText(ns.Colorize(HEX.alert, L["click again to delete"]))
        local armedNote = popNote
        C_Timer.After(3.05, function()
            if popNote == armedNote and GetTime() >= delArmedUntil and pop:IsShown() then ShowPopNote(p) end
        end)
        return
    end
    pop.body.edit:ClearFocus()
    RemoveNote(p, popNote)
    popNote = Latest(p)
    DropPlayerIfEmpty(popKey)
    RefreshPopup()
    Changed("popup")
end)

pop.body.edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and popNote then
        popNote.text = self:GetText()
        Touch(popNote)
        pop.date.text:SetText(Muted(Stamp(popNote.updated)))
        Changed("popup")
    end
end)

RefreshPopup = function()
    if not ns.ready then return end
    local key, info = TargetKey()
    if key ~= popKey then
        -- leaving a player: drop a note that was created but never written
        local p = Player(popKey)
        if p and Discard(p, popNote) then
            DropPlayerIfEmpty(popKey)
            Changed("popup")
        end
        if pop.body.edit:HasFocus() then pop.body.edit:ClearFocus() end
        dismissedKey, popNote = nil, nil
    end
    popKey = key
    local d = DB()
    if not key or d.popupOff or dismissedKey == key then
        pop:Hide()
        return
    end
    local p = Player(key)
    pop.title:SetText(Muted(L["NOTES"] .. "  ·") .. "  " .. DisplayName(p or info, true))
    pop.who = p or info
    if p and #p.notes > 0 then
        if not (popNote and ns.IndexOf(p.notes, popNote)) then popNote = Latest(p) end
        SetCompact(false)
        ShowPopNote(p)
        pop:Show()
    elseif not d.addBarOff then
        popNote = nil
        SetCompact(true)
        pop:Show()
    else
        pop:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Notes page: Notebook (groups) and Players, both as a tree + editor
-- ---------------------------------------------------------------------------
local page = CreateFrame("Frame", "EverFrameNotes", UIParent)
page:SetSize(App.CONTENT_W, App.CONTENT_H)
page:Hide()
local function Status(msg, alert) App.Status(msg, alert) end

local subpages, views = {}, {}
local ShowSub, LastSub
local tabs = UI.Tabs(page, { { "book", L["Notebook"] }, { "players", L["Players"] }, { "stickies", L["Sticky notes"] } },
    0, 0, 120, function(key) ShowSub(key) end)

local TREE_W, ROW_H, BAR_H = 220, 22, 30

-- one tree + editor view. cfg:
--   headers()           ordered list of { ref = container, label = text, color = rgb }
--   headerPanel(view)   builds the right-hand panel for a selected header
--   noteMenu, noteMenuLabel   optional "move to" dropdown for notes
--   afterRemove, afterRender  optional hooks
local function MakeView(key, cfg)
    local sub = CreateFrame("Frame", nil, page)
    sub:SetPoint("TOPLEFT", 0, -32)
    sub:SetPoint("BOTTOMRIGHT", 0, 0)
    sub:Hide()
    subpages[key] = sub
    local v = { page = sub, items = {}, rows = {}, scroll = 0, cfg = cfg }
    views[key] = v

    -- tree ------------------------------------------------------------------
    local tree = CreateFrame("Frame", nil, sub)
    tree:SetPoint("TOPLEFT")
    tree:SetPoint("BOTTOMLEFT", 0, BAR_H)
    tree:SetWidth(TREE_W)
    Skin(tree, T.panel)
    tree:EnableMouseWheel(true)
    tree.thumb = tree:CreateTexture(nil, "OVERLAY")
    tree.thumb:SetWidth(2)
    ns.Color(tree.thumb, T.accent, 0.6)
    tree.empty = UI.Hint(tree, cfg.emptyText)
    tree.empty:SetPoint("TOPLEFT", 10, -10)
    tree.empty:SetPoint("TOPRIGHT", -10, -10)
    v.tree = tree

    -- editor for a selected note ---------------------------------------------
    local ed = CreateFrame("Frame", nil, sub)
    ed:SetPoint("TOPLEFT", TREE_W + 12, 0)
    ed:SetPoint("BOTTOMRIGHT", 0, BAR_H)
    ed.title = UI.LineEdit(ed, 14)
    ed.title:SetPoint("TOPLEFT")
    ed.title:SetPoint("TOPRIGHT", -164, 0)
    ed.title:SetHeight(24)
    ed.del = UI.ConfirmButton(ed, 72, L["Delete"], function()
        local note, c = v.sel, v.selC
        if not (note and c) then return end
        local i = RemoveNote(c, note)
        if cfg.afterRemove then cfg.afterRemove(v, c) end
        Status(L["Deleted \"%s\"."]:format(Untitled(note)))
        v.sel = c.notes[math.min(i or 1, #c.notes)] or c
        v.selC = (v.sel ~= c) and c or nil
        Changed(key)
        v:Refresh()
    end, 24)
    ed.del:SetPoint("TOPRIGHT")
    ed.sticky = UI.Button(ed, 80, L["Sticky"], function()
        if not (v.sel and v.selC) then return end
        ns.Stickies.Toggle(v.sel)
        ed.sticky:SetAccent(IsSticky(v.sel))
    end, 24)
    ed.sticky:SetPoint("RIGHT", ed.del, "LEFT", -6, 0)
    UI.Tooltip(ed.sticky, { L["Sticky note"], L["Puts this note on the screen. Drag its colored bar to move it, its corner to resize it."] })
    ed.meta = Text(ed, 10)
    ed.meta:SetPoint("TOPLEFT", 2, -30)
    ed.meta:SetPoint("TOPRIGHT", -124, -30)
    ed.meta:SetJustifyH("LEFT")
    ed.meta:SetWordWrap(false)
    if cfg.noteMenu then
        ed.move = UI.Button(ed, 120, "", function(self) cfg.noteMenu(v, self) end, 18)
        ed.move:SetPoint("TOPRIGHT", 0, -28)
    end
    ed.body = UI.TextArea(ed)
    ed.body:SetPoint("TOPLEFT", 0, -50)
    ed.body:SetPoint("BOTTOMRIGHT")
    v.ed = ed

    -- panel for a selected group / player ------------------------------------
    v.head = CreateFrame("Frame", nil, sub)
    v.head:SetPoint("TOPLEFT", TREE_W + 12, 0)
    v.head:SetPoint("BOTTOMRIGHT", 0, BAR_H)
    cfg.headerPanel(v)

    local function MetaText(note)
        return Muted(L["Created %s   ·   Updated %s"]:format(Stamp(note.created), Stamp(note.updated)))
    end

    ed.title:SetScript("OnTextChanged", function(self, userInput)
        local note = v.sel
        if not (userInput and v.selC and note) then return end
        note.title, note.titled = self:GetText(), true
        Touch(note)
        ed.meta:SetText(MetaText(note))
        v:Render()
        Changed(key)
    end)
    ed.body.edit:SetScript("OnTextChanged", function(self, userInput)
        local note = v.sel
        if not (userInput and v.selC and note) then return end
        note.text = self:GetText()
        Touch(note)
        ed.meta:SetText(MetaText(note))
        v:Render()
        Changed(key)
    end)

    -- rows ------------------------------------------------------------------
    local function GetRow(i)
        local r = v.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, tree)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -4, -(i - 1) * ROW_H)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        ns.Color(r.sel, T.accentSoft)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        ns.Color(r.mark, T.accent)
        r.toggle = CreateFrame("Button", nil, r)
        r.toggle:SetSize(18, ROW_H)
        r.toggle:SetPoint("LEFT", 2, 0)
        r.toggle.arrow = UI.Arrow(r.toggle, 11)
        r.toggle.arrow:SetPoint("CENTER")
        r.toggle:SetScript("OnClick", function()
            local it = r.item
            if it and it.kind == "header" then
                it.h.ref.collapsed = not it.h.ref.collapsed or nil
                v:Refresh()
            end
        end)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("LEFT", 22, 0)
        r.text = Text(r, 12)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.meta = Text(r, 10)
        r.meta:SetPoint("RIGHT", -6, 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.hover)
        r:SetScript("OnClick", function(self)
            local it = self.item
            if not it then return end
            if it.kind == "header" then
                it.h.ref.collapsed = nil
                v:Select(it.h.ref, nil)
            else
                v:Select(it.note, it.h.ref)
            end
        end)
        UI.Tooltip(r, function(self)
            local it = self.item
            if not (it and it.kind == "note") then return end
            local lines = { Untitled(it.note) }
            if not IsBlank(it.note.text) then lines[#lines + 1] = it.note.text end
            lines[#lines + 1] = L["Created: %s"]:format(Stamp(it.note.created))
            lines[#lines + 1] = L["Updated: %s"]:format(Stamp(it.note.updated))
            return lines
        end)
        v.rows[i] = r
        return r
    end

    function v:Rebuild()
        wipe(self.items)
        for _, h in ipairs(cfg.headers()) do
            self.items[#self.items + 1] = { kind = "header", h = h }
            if not h.ref.collapsed then
                for _, n in ipairs(h.ref.notes) do
                    self.items[#self.items + 1] = { kind = "note", h = h, note = n }
                end
            end
        end
    end

    function v:Render()
        local visible = math.max(1, math.floor((tree:GetHeight() or 0) / ROW_H))
        local maxScroll = math.max(0, #self.items - visible)
        self.scroll = math.max(0, math.min(self.scroll, maxScroll))
        for i = 1, math.max(visible, #self.rows) do
            local it = (i <= visible) and self.items[self.scroll + i] or nil
            if it then
                local r = GetRow(i)
                r.item = it
                local isSel
                r.text:ClearAllPoints()
                if it.kind == "header" then
                    local c = it.h.ref
                    isSel = self.sel == c
                    r.toggle:Show()
                    r.toggle.arrow:Point(c.collapsed and "right" or "down")
                    r.dot:Show()
                    r.dot:SetColorTexture(unpack(it.h.color))
                    r.text:SetPoint("LEFT", 36, 0)
                    r.text:SetPoint("RIGHT", -28, 0)
                    r.text:SetText(it.h.label)
                    r.meta:SetText(Muted(tostring(#c.notes)))
                else
                    isSel = self.sel == it.note
                    r.toggle:Hide()
                    r.dot:Hide()
                    r.text:SetPoint("LEFT", 36, 0)
                    r.text:SetPoint("RIGHT", -50, 0)
                    r.text:SetText((it.note.title and it.note.title ~= "") and it.note.title or Muted(L["(untitled)"]))
                    r.meta:SetText(Muted(Stamp(it.note.updated, true)))
                end
                r.sel:SetShown(isSel)
                r.mark:SetShown(isSel)
                r:Show()
            elseif self.rows[i] then
                self.rows[i]:Hide()
            end
        end
        tree.empty:SetShown(#self.items == 0)
        if maxScroll > 0 then
            local trackH = tree:GetHeight()
            local thumbH = math.max(16, trackH * visible / #self.items)
            tree.thumb:ClearAllPoints()
            tree.thumb:SetPoint("TOPRIGHT", tree, "TOPRIGHT", -1, -(trackH - thumbH) * self.scroll / maxScroll)
            tree.thumb:SetHeight(thumbH)
            tree.thumb:Show()
        else
            tree.thumb:Hide()
        end
        if cfg.afterRender then cfg.afterRender(self) end
    end

    -- the right side follows the selection: note editor or header panel
    function v:ShowSelection()
        local note, c = self.sel, self.selC
        if note and c then
            self.head:Hide()
            ed:Show()
            if not ed.title:HasFocus() then ed.title:SetText(note.title or "") end
            ed.meta:SetText(MetaText(note))
            if not ed.body.edit:HasFocus() then ed.body:SetValue(note.text) end
            if ed.move and cfg.noteMenuLabel then ed.move.text:SetText(cfg.noteMenuLabel(self)) end
            ed.sticky:SetAccent(IsSticky(note))
        else
            ed:Hide()
            if self.sel then
                self.head:Show()
                self.head:Fill(self.sel)
            else
                self.head:Hide()
            end
        end
    end

    function v:Select(ref, container)
        -- leaving a fresh, unwritten note: drop it
        local old, oldC = self.sel, self.selC
        if oldC and old ~= ref and Discard(oldC, old) then
            if cfg.afterRemove then cfg.afterRemove(self, oldC) end
            Changed(key)
        end
        ed.title:ClearFocus()
        ed.body.edit:ClearFocus()
        self.sel, self.selC = ref, container
        self:Rebuild()
        for i, it in ipairs(self.items) do
            if (it.kind == "note" and it.note == ref) or (it.kind == "header" and it.h.ref == ref) then
                local visible = math.max(1, math.floor((tree:GetHeight() or 0) / ROW_H))
                if i <= self.scroll then self.scroll = i - 1 elseif i > self.scroll + visible then self.scroll = i - visible end
                break
            end
        end
        self:Render()
        self:ShowSelection()
    end

    -- redraw after outside changes; a selection that vanished falls back
    function v:Refresh()
        local exists = false
        for _, h in ipairs(cfg.headers()) do
            if h.ref == self.sel then exists = true end
            if self.selC == h.ref and ns.IndexOf(h.ref.notes, self.sel) then exists = true end
        end
        if not exists then self.sel, self.selC = nil, nil end
        self:Rebuild()
        self:Render()
        self:ShowSelection()
    end

    tree:SetScript("OnMouseWheel", function(_, delta)
        v.scroll = v.scroll - delta
        v:Render()
    end)
    tree:SetScript("OnSizeChanged", function() if sub:IsVisible() then v:Render() end end)
    return v
end

local function HeadLabel(parent, text, y) return UI.Label(parent, text, 2, y) end

-- ---------------------------------------------------------------- notebook view
local book
local function GroupLabel(g)
    return "|c" .. Hex(PALETTE[g.color] or PALETTE[3]) .. ((g.name ~= "") and g.name or L["(group)"]) .. "|r"
end

-- the group new notes go into: the selected group, the selected note's, or the first
local function TargetGroup()
    if book.selC then return book.selC end
    for _, g in ipairs(DB().groups) do if g == book.sel then return g end end
    return DB().groups[1]
end

local function NewGroup()
    local groups = DB().groups
    local g = { name = L["Group %d"]:format(#groups + 1), color = (#groups % #PALETTE) + 1, seq = 0, notes = {} }
    groups[#groups + 1] = g
    book:Select(g, nil)
    book.head.name:SetFocus()
    book.head.name:HighlightText()
    Changed("book")
end

local function NewBookNote()
    local g = TargetGroup()
    if not g then
        NewGroup()
        g = DB().groups[#DB().groups]
    end
    g.collapsed = nil
    local n = NewNote(g)
    book:Select(n, g)
    book.ed.body.edit:SetFocus()
    Changed("book")
end

local function Plural(n, one, many) return (n == 1 and one or many):format(n) end

book = MakeView("book", {
    emptyText = L["No groups yet. Use \"+ Group\"."],
    headers = function()
        local out = {}
        for _, g in ipairs(DB().groups) do
            out[#out + 1] = { ref = g, label = GroupLabel(g), color = PALETTE[g.color] or PALETTE[3] }
        end
        return out
    end,
    noteMenuLabel = function(v) return GroupLabel(v.selC) .. "  " .. Muted("›") end,
    noteMenu = function(v, anchor)
        local items = { { label = L["Move to group"], isTitle = true } }
        for _, g in ipairs(DB().groups) do
            items[#items + 1] = { label = GroupLabel(g), checked = g == v.selC, fn = function()
                if g == v.selC then return end
                RemoveNote(v.selC, v.sel)
                table.insert(g.notes, v.sel)
                g.collapsed = nil
                v:Select(v.sel, g)
                Changed("book")
            end }
        end
        UI.OpenMenu(anchor, items)
    end,
    headerPanel = function(v)
        local h = v.head
        HeadLabel(h, L["GROUP NAME"], 0)
        h.name = UI.LineEdit(h, 14)
        h.name:SetPoint("TOPLEFT", 0, -16)
        h.name:SetPoint("TOPRIGHT", 0, -16)
        h.name:SetHeight(24)
        h.name:SetScript("OnTextChanged", function(self, userInput)
            if userInput and h.group then
                h.group.name = self:GetText()
                v:Render()
                Changed("book")
            end
        end)
        HeadLabel(h, L["COLOR"], -52)
        h.swatches = {}
        for i, c in ipairs(PALETTE) do
            local s = CreateFrame("Button", nil, h)
            s:SetSize(20, 20)
            s:SetPoint("TOPLEFT", 1 + (i - 1) * 26, -68)
            Skin(s, c)
            s.hl = s:CreateTexture(nil, "HIGHLIGHT")
            s.hl:SetAllPoints()
            s.hl:SetColorTexture(1, 1, 1, 0.25)
            s:SetScript("OnClick", function()
                if not h.group then return end
                h.group.color = i
                h:Fill(h.group)
                v:Render()
                Changed("book")
            end)
            h.swatches[i] = s
        end
        h.info = Text(h, 11)
        h.info:SetPoint("TOPLEFT", 2, -102)
        h.info:SetJustifyH("LEFT")
        h.add = UI.Button(h, 130, "+ " .. L["Note in group"], NewBookNote)
        h.add:SetPoint("TOPLEFT", 0, -126)
        h.del = UI.ConfirmButton(h, 120, L["Delete group"], function()
            local g = h.group
            local i = g and ns.IndexOf(DB().groups, g)
            if not i then return end
            table.remove(DB().groups, i)
            Status(L["Deleted group \"%s\" with %s."]:format(g.name, Plural(#g.notes, L["%d note"], L["%d notes"])))
            local nextG = DB().groups[math.min(i, #DB().groups)]
            v:Select(nextG, nil)
            Changed("book")
        end)
        h.del:SetPoint("LEFT", h.add, "RIGHT", 6, 0)
        function h:Fill(g)
            self.group = g
            if not self.name:HasFocus() then self.name:SetText(g.name or "") end
            for i, s in ipairs(self.swatches) do SetEdgeColor(s, i == g.color and T.text or nil) end
            local last = Latest(g)
            self.info:SetText(Muted(Plural(#g.notes, L["%d note"], L["%d notes"])
                .. (last and ("   ·   " .. L["last update %s"]:format(Stamp(last.updated))) or "")))
        end
    end,
})

local bookAddGroup = UI.Button(book.page, 106, "+ " .. L["Group"], NewGroup)
bookAddGroup:SetPoint("BOTTOMLEFT", 0, 0)
local bookAddNote = UI.Button(book.page, 106, "+ " .. L["Note"], NewBookNote)
bookAddNote:SetPoint("LEFT", bookAddGroup, "RIGHT", 8, 0)

-- ---------------------------------------------------------------- players view
local players

NoteForTarget = function()
    local key, info = TargetKey()
    if not key then
        Status(L["Target a player first."], true)
        ns.Print(L["Target a player first."])
        return
    end
    local p = EnsurePlayer(key, info)
    p.collapsed = nil
    local note = NewNote(p)
    -- with the popup switched off, the notes page is where you type
    if DB().popupOff and not App:IsOpen("notes") then App:Open("notes") end
    if App:IsOpen("notes") then
        ShowSub("players")
        players:Select(note, p)
    end
    dismissedKey = nil
    popNote = note
    RefreshPopup()
    popNote = note
    if pop:IsShown() then
        ShowPopNote(p)
        pop.body.edit:SetFocus()
    else
        players.ed.body.edit:SetFocus()
    end
    Changed("new")
end
ns.NoteForTarget = NoteForTarget

-- from the popup title: this player in the Players tab, the shown note selected
OpenInNotes = function()
    App:Open("notes")
    ShowSub("players")
    local p = Player(popKey)
    if not p then return end
    p.collapsed = nil
    if popNote and ns.IndexOf(p.notes, popNote) then
        players:Select(popNote, p)
    else
        players:Select(p, nil)
    end
end

players = MakeView("players", {
    emptyText = L["No player notes yet. Target a player and press \"+ Note for target\"."],
    headers = function()
        local out = {}
        for key, p in pairs(DB().players) do
            local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            out[#out + 1] = { ref = p, label = DisplayName(p), sort = ns.Fold(p.name or key),
                color = c and { c.r, c.g, c.b } or { 0.62, 0.65, 0.70 } }
        end
        table.sort(out, function(a, b) return a.sort < b.sort end)
        return out
    end,
    afterRemove = function(_, p)
        local key = KeyOf(p)
        if key then DropPlayerIfEmpty(key) end
    end,
    afterRender = function()
        local n = 0
        for _ in pairs(DB().players) do n = n + 1 end
        tabs.buttons.players.text:SetText(L["Players"] .. "  " .. Muted(tostring(n)))
    end,
    headerPanel = function(v)
        local h = v.head
        h.name = Text(h, 16)
        h.name:SetPoint("TOPLEFT", 2, -2)
        h.info = Text(h, 11)
        h.info:SetPoint("TOPLEFT", 2, -26)
        h.info:SetJustifyH("LEFT")
        h.add = UI.Button(h, 110, "+ " .. L["Note"], function()
            local p = h.player
            if not p then return end
            p.collapsed = nil
            local note = NewNote(p)
            v:Select(note, p)
            v.ed.body.edit:SetFocus()
            Changed("players")
        end)
        h.add:SetPoint("TOPLEFT", 0, -50)
        h.del = UI.ConfirmButton(h, 110, L["Delete all"], function()
            local key = KeyOf(h.player)
            if not key then return end
            DB().players[key] = nil
            Status(L["Deleted all notes for %s."]:format(h.player.name or key))
            v:Refresh()
            Changed("players")
        end)
        h.del:SetPoint("LEFT", h.add, "RIGHT", 6, 0)
        function h:Fill(p)
            self.player = p
            self.name:SetText(DisplayName(p))
            local last = Latest(p)
            self.info:SetText(Muted(("%s   ·   %s%s"):format(p.realm or "", Plural(#p.notes, L["%d note"], L["%d notes"]),
                last and ("   ·   " .. L["last update %s"]:format(Stamp(last.updated))) or "")))
        end
    end,
})

local addForTarget = UI.Button(players.page, TREE_W, "+ " .. L["Note for target"], NoteForTarget)
addForTarget:SetPoint("BOTTOMLEFT", 0, 0)

local function Toggle(label, get, set)
    local row = UI.CheckRow(players.page, label, get, function(v)
        set(v)
        RefreshPopup()
    end, 150)
    return row
end
local showTog = Toggle(L["Show on target"],
    function() return not DB().popupOff end, function(v) DB().popupOff = not v or nil end)
showTog:SetPoint("LEFT", addForTarget, "RIGHT", 16, 0)
local barTog = Toggle(L["\"+ Note\" bar"],
    function() return not DB().addBarOff end, function(v) DB().addBarOff = not v or nil end)
barTog:SetPoint("LEFT", showTog, "RIGHT", 8, 0)
UI.Tooltip(barTog, { L["\"+ Note\" bar"], L["Players without notes get a slim bar to add one."] })

-- sticky note settings (built by ns.Stickies when first shown)
subpages.stickies = CreateFrame("Frame", nil, page)
subpages.stickies:SetPoint("TOPLEFT", 0, -32)
subpages.stickies:SetPoint("BOTTOMRIGHT", 0, 0)
subpages.stickies:Hide()

function LastSub()
    local k = DB().page
    return (k == "players" or k == "stickies") and k or "book"
end

-- this note in its tab, selected (from a sticky note's menu)
function Notes.Reveal(note)
    local kind, c = Notes.Owner(note)
    if not kind then return end
    App:Open("notes")
    local key = kind == "g" and "book" or "players"
    ShowSub(key)
    c.collapsed = nil
    views[key]:Select(note, c)
end

-- ---------------------------------------------------------------- export / import
local exportItems = {}
local function Item(note, kind, c, key)
    -- a group without a name still needs one in the code
    local owner = (kind == "g") and (ns.Trim(c.name or "") ~= "" and c.name or L["(group)"]) or key
    return { note = note, kind = kind, owner = owner,
             extra = kind == "g" and tostring(c.color or 3) or c.class,
             title = note.title, text = note.text, created = note.created, updated = note.updated }
end
-- the group or player an entry belongs to (nil: not there yet)
local function OwnerOf(it)
    if it.kind == "p" then return DB().players[it.owner] end
    for _, g in ipairs(DB().groups) do if g.name == it.owner then return g end end
end
local function ItemColor(it)
    if it.kind == "g" then return PALETTE[tonumber(it.extra) or 3] or PALETTE[3] end
    return Notes.Color("p", { class = it.extra })
end
local function ItemOwnerName(it)
    if it.kind == "g" then return it.owner end
    return it.owner:match("^(.-)%-") or it.owner
end
local function ItemLabel(it)
    return "|c" .. Hex(ItemColor(it)) .. ItemOwnerName(it) .. "|r  " .. ((it.title ~= "" and it.title) or L["(untitled)"])
end

local transfer = ns.Transfer.Build(page, {
    items = function() return exportItems end,
    label = ItemLabel,
    color = ItemColor,
    tooltip = function(it)
        local lines = { (it.title ~= "" and it.title) or L["(untitled)"], ItemOwnerName(it) }
        if not IsBlank(it.text) then lines[#lines + 1] = it.text end
        return lines
    end,
    preview = function(it)
        return ns.Colorize(HEX.accent, (it.title ~= "" and it.title) or L["(untitled)"]) .. "\n"
            .. Muted((it.kind == "g" and L["Group: %s"] or L["Player: %s"]):format(it.owner)) .. "\n\n" .. (it.text or "")
    end,
    encode = ns.EncodeNotes,
    decode = ns.DecodeNotes,
    find = function(it)
        local c = OwnerOf(it)
        if not c then return end
        for _, n in ipairs(c.notes) do
            if (n.title or "") == (it.title or "") then return n end
        end
    end,
    add = function(it)
        local c = OwnerOf(it)
        if not c then
            if it.kind == "g" then
                c = { name = it.owner, color = tonumber(it.extra) or 3, seq = 0, notes = {} }
                table.insert(DB().groups, c)
            else
                c = EnsurePlayer(it.owner, { name = it.owner:match("^(.-)%-") or it.owner,
                    realm = it.owner:match("%-(.+)$"), class = it.extra })
            end
        end
        c.seq = (c.seq or #c.notes) + 1
        table.insert(c.notes, { title = it.title, text = it.text or "", titled = true,
            created = it.created or Now(), updated = it.updated or Now() })
    end,
    replace = function(have, it)
        have.text = it.text or ""
        have.updated = it.updated or Now()
    end,
    done = function()
        Changed("import")
        ShowSub(LastSub())
    end,
    L = {
        exportTitle = L["Export notes"],
        importTitle = L["Import notes"],
        empty = L["No notes yet."],
        invalid = L["That is no notes code (it starts with EFN1:)."],
        found = L["%d notes in the code. Untick what you don't want."],
        clashTitle = L["Notes exist already"],
        clashText = L["These notes exist already (same group or player, same title):\n%s\n\nOverwrite their text with the imported one?"],
    },
})

local importBtn = UI.Button(page, 100, L["Import"], function() transfer.ShowImport() end, 22)
importBtn:SetPoint("TOPRIGHT", 0, 0)
local exportBtn = UI.Button(page, 100, L["Export"], function()
    wipe(exportItems)
    local pre = {}
    Notes.ForEach(function(note, kind, c, key)
        local it = Item(note, kind, c, key)
        exportItems[#exportItems + 1] = it
        local v = views[DB().page]
        if v and v.sel == note then pre[1] = it end
    end)
    transfer.ShowExport(pre)
end, 22)
exportBtn:SetPoint("RIGHT", importBtn, "LEFT", -6, 0)

ShowSub = function(key)
    DB().page = key
    for k, p in pairs(subpages) do p:SetShown(k == key) end
    tabs:Select(key)
    local v = views[key]
    if not v then
        if key == "stickies" then ns.Stickies.ShowSettings(subpages.stickies) end
        return
    end
    v:Refresh()
    if not v.sel then
        local first = v.items[1]
        if first then v:Select(first.h.ref, nil) end
    end
    if key == "players" then
        showTog:Refresh()
        barTog:Refresh()
    end
end

page:SetScript("OnShow", function()
    ShowSub(LastSub())
end)
page:SetScript("OnHide", function()
    transfer.Hide()
    for _, v in pairs(views) do
        v.ed.title:ClearFocus()
        v.ed.body.edit:ClearFocus()
        if v.selC and Discard(v.selC, v.sel) then
            if v.cfg.afterRemove then v.cfg.afterRemove(v, v.selC) end
            v.sel, v.selC = v.selC, nil
            Changed("hide")
        end
    end
end)

-- keep the views in sync with each other and the popup
listeners[#listeners + 1] = function(source)
    if page:IsVisible() then
        for key, v in pairs(views) do
            if key ~= source and v.page:IsShown() then v:Refresh() end
        end
    end
    if source ~= "popup" then RefreshPopup() end
end

App:AddPage({
    key = "notes", section = "hud", label = L["Notes"], order = 40,
    Build = function(_, frame)
        page:SetParent(frame)
        page:ClearAllPoints()
        page:SetAllPoints(frame)
        page:Show()
    end,
})

function ns.ToggleNotes() App:Toggle("notes") end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ns.On("LOGIN", function()
    -- drop empty leftovers, restore the popup
    local d = DB()
    for key, p in pairs(d.players) do
        for i = #p.notes, 1, -1 do
            local n = p.notes[i]
            if IsBlank(n.text) and not n.titled and not IsSticky(n) then table.remove(p.notes, i) end
        end
        if #p.notes == 0 then d.players[key] = nil end
    end
    pop:ApplyGeometry()
    RefreshPopup()
end)
ns.On("SETTINGS_RESET", function(keys)
    if keys.notes or keys.windows then
        popKey, popNote = nil, nil
        pop:ApplyGeometry()
        RefreshPopup()
        if page:IsVisible() then
            for _, v in pairs(views) do v.sel, v.selC = nil, nil end
            ShowSub(LastSub())
        end
    end
end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() RefreshPopup() end)
ns.On("THEME_CHANGED", function()
    if pop:IsShown() then
        local p = Player(popKey)
        if p and popNote then ShowPopNote(p) end
        pop:UpdateLock()
        RefreshPopup()
    end
    if page:IsVisible() then ShowSub(LastSub()) end
end)
