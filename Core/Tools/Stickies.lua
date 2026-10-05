-- ---------------------------------------------------------------------------
-- Sticky notes: any note (notebook or player) can sit on the screen as its
-- own small window. The bar in the note's color moves it, the corner resizes
-- it; the bar's buttons fold it to the bar, lock it and close it. Position,
-- size and the open state live on the note itself (note.sticky), so open
-- sticky notes come back after a reload.
-- Dropped at the edge of another sticky note, a note docks there: it takes
-- that note's width and height and moves with it (note.sticky.dock).
-- The text shows formatted, a click switches to editing:
--   [ ] task   [x] done   (a click on the box ticks it)
--   - item     * item     (bullet list)
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, App, Notes = ns.UI, ns.App, ns.Notes
local Text, Muted = ns.Text, ns.Muted

local Stickies = {}
ns.Stickies = Stickies

local BAR_H, FOOT_H, PAD = 26, 24, 10
local MIN_W, MIN_H = 160, 90
local MEDIA = "Interface\\AddOns\\UltimateEverRogue\\Media\\"
Stickies.DEFAULTS = { w = 240, h = 200, size = 12 }

function Stickies.Settings()
    local d = Notes.DB()
    d.sticky = d.sticky or {}
    local s = d.sticky
    for k, v in pairs(Stickies.DEFAULTS) do if s[k] == nil then s[k] = v end end
    return s
end

local function IsOpen(note) return note and note.sticky and note.sticky.open and true or false end
Stickies.IsOpen = IsOpen

-- ---------------------------------------------------------------------------
-- Lines: checkbox, bullet or plain text
-- ---------------------------------------------------------------------------
local function ParseLine(line)
    local mark, rest = line:match("^%s*%[([ xX]?)%]%s?(.*)$")
    if mark then return "check", rest, mark == "x" or mark == "X" end
    local item = line:match("^%s*[%-%*]%s+(.*)$")
    if item then return "bullet", item end
    return "text", line
end
Stickies.ParseLine = ParseLine

local function Lines(text)
    local out = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    return out
end

-- ticked and total checkboxes of a text
function Stickies.Progress(text)
    local done, total = 0, 0
    for _, line in ipairs(Lines(text)) do
        local kind, _, on = ParseLine(line)
        if kind == "check" then
            total = total + 1
            if on then done = done + 1 end
        end
    end
    return done, total
end

-- turns the line under the cursor into a checkbox / bullet line, or back
function Stickies.ToggleLine(text, cursor, want)
    local before = text:sub(1, cursor)
    local start = (before:match(".*()\n") or 0) + 1
    local stop = (text:find("\n", start, true) or (#text + 1)) - 1
    local line = text:sub(start, stop)
    local kind, rest = ParseLine(line)
    local new = (kind == want) and rest or ((want == "check" and "[ ] " or "- ") .. rest)
    return text:sub(1, start - 1) .. new .. text:sub(stop + 1), start - 1 + #new
end

-- ---------------------------------------------------------------------------
-- Windows (pooled; one per open note)
-- ---------------------------------------------------------------------------
local frames, byNote, cascade = {}, {}, 0
local Render, SetEditing, ApplyGeometry

local function Geo(note)
    note.sticky = note.sticky or {}
    return note.sticky
end

-- ---------------------------------------------------------------------------
-- Docking: a note hangs at one side of another (its "host")
-- ---------------------------------------------------------------------------
local DOCK_GAP, SNAP = 4, 18
local DOCK_POINTS = {   -- side of the host -> our point, host point, x, y
    RIGHT  = { "TOPLEFT", "TOPRIGHT", DOCK_GAP, 0 },
    LEFT   = { "TOPRIGHT", "TOPLEFT", -DOCK_GAP, 0 },
    BOTTOM = { "TOPLEFT", "BOTTOMLEFT", 0, -DOCK_GAP },
    TOP    = { "BOTTOMLEFT", "TOPLEFT", 0, DOCK_GAP },
}

-- a stable number per note (docks survive reloads by it)
local function NoteId(note)
    if not note.id then
        local d = Notes.DB()
        d.nextId = (d.nextId or 0) + 1
        note.id = d.nextId
    end
    return note.id
end

-- the open window a note is docked to, if any
local function HostOf(f)
    local dock = f.note and f.note.sticky and f.note.sticky.dock
    if not dock then return end
    for note, x in pairs(byNote) do
        if note.id == dock.id and x ~= f then return x end
    end
end

-- open windows docked to f
local function DockedTo(f)
    local out, id = {}, f.note and f.note.id
    if not id then return out end
    for note, x in pairs(byNote) do
        local dock = note.sticky and note.sticky.dock
        if dock and dock.id == id and x ~= f then out[#out + 1] = x end
    end
    return out
end

-- does a hang (directly or further up) on b?
local function HangsOn(a, b)
    local x, guard = a, 0
    while x and guard < 50 do
        if x == b then return true end
        x, guard = HostOf(x), guard + 1
    end
    return false
end

local function FullHeight(f)
    local g = Geo(f.note)
    if g.collapsed then return math.max(MIN_H, g.h or Stickies.Settings().h) end
    return f:GetHeight()
end

-- puts a docked window at its host and gives it the host's size; then its own
-- docked windows follow
local function Relayout(f, depth)
    if (depth or 0) > 20 then return end   -- broken saved data must not loop
    for _, x in ipairs(DockedTo(f)) do
        local g = Geo(x.note)
        local pt = DOCK_POINTS[g.dock.side]
        x:ClearAllPoints()
        x:SetPoint(pt[1], f, pt[2], pt[3], pt[4])
        x:SetWidth(f:GetWidth())
        x:SetHeight(g.collapsed and BAR_H or FullHeight(f))
        Relayout(x, (depth or 0) + 1)
    end
end

local function SaveGeometry(f)
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t and f.note) then return end
    if HostOf(f) then return end   -- docked: the host decides
    local g = Geo(f.note)
    g.l, g.t, g.w = l, t, f:GetWidth()
    if not g.collapsed then g.h = f:GetHeight() end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end

local function IconButton(parent, size, file, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(size - 6, size - 6)
    b.icon:SetPoint("CENTER")
    if file then b.icon:SetTexture(file) end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.18)
    if tip then UI.Tooltip(b, tip, "ANCHOR_TOP") end
    return b
end

-- dark text on light note colors, white on dark ones
local function InkFor(c)
    local lum = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
    return lum > 0.5 and { 0.07, 0.08, 0.10 } or { 1, 1, 1 }
end

local function Row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f.content)
    r.check = CreateFrame("Button", nil, r)
    r.check:SetSize(14, 14)
    r.check:SetPoint("TOPLEFT", 1, -1)   -- 1 px in: the scroll frame clips its left edge
    ns.Skin(r.check, T.control, T.muted)   -- a clear outline in both modes
    r.check.mark = r.check:CreateTexture(nil, "ARTWORK")
    r.check.mark:SetPoint("TOPLEFT", 3, -3)
    r.check.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    ns.Color(r.check.mark, T.accent)
    r.check.hl = r.check:CreateTexture(nil, "HIGHLIGHT")
    r.check.hl:SetAllPoints()
    ns.Color(r.check.hl, T.hover)
    r.check:SetScript("OnClick", function() Stickies.Tick(f, r.index) end)
    r.dot = Text(r, 12)
    r.dot:SetPoint("TOPLEFT", 3, 0)
    r.dot:SetText("•")
    r.text = Text(r, 12)
    r.text:SetJustifyH("LEFT")
    r.text:SetJustifyV("TOP")
    r.text:SetWordWrap(true)
    f.rows[i] = r
    return r
end

-- all sticky notes sit on one layer: it steps aside in combat if wanted
local layer = Notes.Layer("stickies")

local function Create()
    local i = #frames + 1
    local f = CreateFrame("Frame", "UERSticky" .. i, layer)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, 1000, 1000) end
    ns.Skin(f, T.window, T.line)
    f.rows = {}

    -- bar in the note's color: drag to move
    local bar = CreateFrame("Button", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_H)
    bar:RegisterForDrag("LeftButton")
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar:SetScript("OnDragStart", function()
        if Geo(f.note).locked then return end
        if HostOf(f) then Stickies.Undock(f) end   -- pulled away: free again
        f:StartMoving()
        bar:SetScript("OnUpdate", function() Stickies.ShowSnap(f) end)
    end)
    bar:SetScript("OnDragStop", function()
        bar:SetScript("OnUpdate", nil)
        f:StopMovingOrSizing()
        Stickies.HideSnap()
        local x, side = Stickies.FindSnap(f)
        if x then Stickies.Dock(f, x, side) else SaveGeometry(f) end
    end)
    bar:SetScript("OnDoubleClick", function() Stickies.Fold(f) end)
    f.bar = bar

    f.menu = IconButton(bar, 22, nil, { L["More"] })
    f.menu:SetPoint("LEFT", 4, 0)
    f.menu.label = Text(f.menu, 14)
    f.menu.label:SetPoint("CENTER", 0, 0)
    f.menu.label:SetText("···")
    f.menu:SetScript("OnClick", function(self)
        local items = { { label = L["Open in the notes"], fn = function() Notes.Reveal(f.note) end } }
        if HostOf(f) then
            items[#items + 1] = { label = L["Undock"], fn = function() Stickies.Undock(f) end }
        else
            items[#items + 1] = { label = L["Default size"], fn = function()
                local s, g = Stickies.Settings(), Geo(f.note)
                g.w, g.h, g.collapsed = s.w, s.h, nil
                ApplyGeometry(f)
                Render(f)
            end }
        end
        items[#items + 1] = { label = L["Close"], fn = function() Stickies.Close(f.note) end }
        UI.OpenMenu(self, items, { width = 170, point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
    end)
    f.close = IconButton(bar, 22, nil, { L["Close"], L["The note stays in your notes."] })
    f.close:SetPoint("RIGHT", -4, 0)
    f.close.label = Text(f.close, 16)
    f.close.label:SetPoint("CENTER", 0, 1)
    f.close.label:SetText("×")
    f.close:SetScript("OnClick", function() Stickies.Close(f.note) end)
    f.lock = IconButton(bar, 22, nil, function()
        return { Geo(f.note).locked and L["Unlock: allow moving and resizing"] or L["Lock position and size"] }
    end)
    f.lock:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    f.lock:SetScript("OnClick", function()
        local g = Geo(f.note)
        g.locked = not g.locked or nil
        Stickies.Paint(f)
    end)
    f.fold = IconButton(bar, 22, nil, { L["Fold to the bar"] })
    f.fold:SetPoint("RIGHT", f.lock, "LEFT", -2, 0)
    f.fold.arrow = UI.Arrow(f.fold, 12, "up")
    f.fold.arrow:SetPoint("CENTER")
    f.fold:SetScript("OnClick", function() Stickies.Fold(f) end)
    f.title = Text(bar, 12)
    f.title:SetPoint("LEFT", f.menu, "RIGHT", 4, 0)
    f.title:SetPoint("RIGHT", f.fold, "LEFT", -6, 0)
    f.title:SetJustifyH("CENTER")
    f.title:SetWordWrap(false)
    -- ink on a colored bar: no shadow
    for _, fs in ipairs({ f.title, f.menu.label, f.close.label }) do
        fs.uerThemed = nil   -- keep it shadow-free in both modes
        fs:SetShadowOffset(0, 0)
    end

    -- formatted text; a click anywhere on it starts editing
    local body = CreateFrame("Button", nil, f)
    body:SetPoint("TOPLEFT", 0, -BAR_H)
    body:SetPoint("BOTTOMRIGHT", 0, FOOT_H)
    body:SetScript("OnClick", function() SetEditing(f, true) end)
    body:EnableMouseWheel(true)
    f.body = body
    body.tint = body:CreateTexture(nil, "BACKGROUND")   -- a breath of the note's color
    body.tint:SetPoint("TOPLEFT", 0, 0)
    body.tint:SetPoint("BOTTOMRIGHT", 0, -FOOT_H)
    local sf = CreateFrame("ScrollFrame", nil, body)
    sf:SetPoint("TOPLEFT", PAD, -8)
    sf:SetPoint("BOTTOMRIGHT", -PAD, 4)
    f.content = CreateFrame("Frame", nil, sf)
    f.content:SetSize(100, 10)
    sf:SetScrollChild(f.content)
    f.scroll = sf
    body:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, f.content:GetHeight() - sf:GetHeight())
        sf:SetVerticalScroll(math.max(0, math.min(max, sf:GetVerticalScroll() - delta * 18)))
    end)
    f.empty = Text(body, 12)
    f.empty:SetPoint("TOPLEFT", PAD, -8)
    f.empty:SetPoint("TOPRIGHT", -PAD, -8)
    f.empty:SetJustifyH("LEFT")
    f.empty:SetWordWrap(true)

    -- editing: the raw text
    local ed = UI.TextArea(f)
    ed:SetPoint("TOPLEFT", 4, -BAR_H - 4)
    ed:SetPoint("BOTTOMRIGHT", -4, FOOT_H)
    ns.SetFill(ed, { 0, 0, 0, 0 })
    ed:Hide()
    ed.edit:SetScript("OnTextChanged", function(self, userInput)
        if not (userInput and f.note) then return end
        f.note.text = self:GetText()
        Notes.Touch(f.note)
        Stickies.Paint(f)
        Notes.Changed("sticky")
    end)
    ed.edit:SetScript("OnEditFocusGained", function() ns.SetEdgeColor(ed, T.accent) end)
    ed.edit:SetScript("OnEditFocusLost", function()
        ns.SetEdgeColor(ed)
        SetEditing(f, false)
    end)
    f.editor = ed

    -- footer: checkbox and list buttons, progress, resize corner
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(FOOT_H)
    f.foot = foot
    local function LineButton(kind, tip)
        local b = IconButton(foot, 20, nil, tip)
        if kind == "check" then
            b.box = CreateFrame("Frame", nil, b)
            b.box:SetSize(11, 11)
            b.box:SetPoint("CENTER")
            ns.Skin(b.box, { 0, 0, 0, 0 }, T.muted)
        else
            b.label = Text(b, 13)
            b.label:SetPoint("CENTER", 0, 1)
            b.label:SetText("•")
            ns.Color(b.label, T.muted)
        end
        b:SetScript("OnClick", function() Stickies.LineButton(f, kind) end)
        return b
    end
    f.checkBtn = LineButton("check", { L["Checkbox"], L["Turns the line into a checkbox: [ ] text"] })
    f.checkBtn:SetPoint("LEFT", 6, 0)
    f.listBtn = LineButton("bullet", { L["List"], L["Turns the line into a list item: - text"] })
    f.listBtn:SetPoint("LEFT", f.checkBtn, "RIGHT", 2, 0)
    f.done = UI.Button(foot, 60, L["Done"], function() SetEditing(f, false) end, 18)
    f.done:SetPoint("LEFT", f.listBtn, "RIGHT", 6, 0)
    f.progress = Text(foot, 11)
    f.progress:SetPoint("RIGHT", -24, 0)
    ns.Color(f.progress, T.muted)
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(16, 16)
    f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    f.grip:SetFrameLevel(f:GetFrameLevel() + 10)
    f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    f.grip:SetScript("OnMouseDown", function() if not Geo(f.note).locked then f:StartSizing("BOTTOMRIGHT") end end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveGeometry(f)
        Render(f)
    end)
    f:SetScript("OnSizeChanged", function()
        if not f.note then return end
        if not f.editing then Render(f) end
        Relayout(f)   -- docked notes keep the same size
    end)
    -- snap preview: a bold accent line along the edge where the notes meet,
    -- on both notes, exactly as long as the edge (drawn above the content)
    f.snapBar = CreateFrame("Frame", nil, f)
    f.snapBar:SetAllPoints()
    f.snapBar:SetFrameLevel(f:GetFrameLevel() + 30)
    f.snapLine = f.snapBar:CreateTexture(nil, "OVERLAY")
    ns.Color(f.snapLine, T.accent)
    f.snapLine:Hide()

    frames[i] = f
    return f
end

-- bar color, title, lock and fold state, progress
function Stickies.Paint(f)
    local note = f.note
    if not note then return end
    local kind, c = Notes.Owner(note)
    local color = kind and Notes.Color(kind, c) or T.muted
    f.bar.bg:SetColorTexture(color[1], color[2], color[3], 1)
    f.body.tint:SetColorTexture(color[1], color[2], color[3], T.mode == "light" and 0.07 or 0.05)
    local ink = InkFor(color)
    f.title:SetTextColor(ink[1], ink[2], ink[3], 1)
    f.close.label:SetTextColor(ink[1], ink[2], ink[3], 1)
    f.menu.label:SetTextColor(ink[1], ink[2], ink[3], 1)
    f.fold.arrow:SetVertexColor(ink[1], ink[2], ink[3], 0.9)
    local g = Geo(note)
    f.lock.icon:SetTexture(MEDIA .. (g.locked and "Lock" or "Unlock"))
    f.lock.icon:SetVertexColor(ink[1], ink[2], ink[3], g.locked and 1 or 0.55)
    f.fold.arrow:Point(g.collapsed and "down" or "up")
    local title = Notes.Untitled(note)
    if kind == "p" then title = Notes.OwnerName(kind, c) .. " · " .. title end
    f.title:SetText(title)
    local done, total = Stickies.Progress(note.text)
    f.progress:SetText(total > 0 and ("%d/%d"):format(done, total) or "")
    f.grip:SetShown(not g.locked and not g.collapsed and not HostOf(f))
    f.done:SetShown(f.editing and true or false)
end

ApplyGeometry = function(f)
    local g, s = Geo(f.note), Stickies.Settings()
    local host = HostOf(f)
    if host then
        f.body:SetShown(not g.collapsed)
        f.foot:SetShown(not g.collapsed)
        if g.collapsed then f.editor:Hide() end
        Relayout(host)   -- places f (and what hangs on it)
        return
    end
    f:ClearAllPoints()
    if not (g.l and g.t) then
        -- new on screen: a little cascade around the middle
        cascade = (cascade % 8) + 1
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        g.l, g.t = w / 2 - (g.w or s.w) / 2 + cascade * 24 - 96, h / 2 + 120 - cascade * 24
    end
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.l, g.t)
    f:SetWidth(math.max(MIN_W, g.w or s.w))
    f:SetHeight(g.collapsed and BAR_H or math.max(MIN_H, g.h or s.h))
    f.body:SetShown(not g.collapsed)
    f.foot:SetShown(not g.collapsed)
    if g.collapsed then f.editor:Hide() end
    Relayout(f)
end

-- ---------------------------------------------------------------------------
-- Snapping while dragging
-- ---------------------------------------------------------------------------
-- the open window and side f would dock to if dropped now
function Stickies.FindSnap(f)
    local fl, fr, ft, fb = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (fl and ft) then return end
    local best, bestSide, bestDist
    for note, x in pairs(byNote) do
        if x ~= f and x:IsShown() and not HangsOn(x, f) then
            local xl, xr, xt, xb = x:GetLeft(), x:GetRight(), x:GetTop(), x:GetBottom()
            if xl and xt then
                local taken = {}
                for _, y in ipairs(DockedTo(x)) do taken[Geo(y.note).dock.side] = true end
                local vOverlap = ft > xb and fb < xt
                local hOverlap = fr > xl and fl < xr
                local tries = {
                    { "RIGHT", math.abs(fl - (xr + DOCK_GAP)), vOverlap },
                    { "LEFT", math.abs(fr - (xl - DOCK_GAP)), vOverlap },
                    { "BOTTOM", math.abs(ft - (xb - DOCK_GAP)), hOverlap },
                    { "TOP", math.abs(fb - (xt + DOCK_GAP)), hOverlap },
                }
                for _, t in ipairs(tries) do
                    if t[3] and t[2] <= SNAP and not taken[t[1]] and (not bestDist or t[2] < bestDist) then
                        best, bestSide, bestDist = x, t[1], t[2]
                    end
                end
            end
        end
    end
    return best, bestSide
end

local SNAP_W = 3
local OPPOSITE = { LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP" }
local snapShown = {}
function Stickies.HideSnap()
    for _, x in ipairs(snapShown) do x.snapLine:Hide() end
    wipe(snapShown)
end

local function EdgeLine(x, side)
    local tex = x.snapLine
    tex:ClearAllPoints()
    if side == "LEFT" or side == "RIGHT" then
        tex:SetPoint("TOP" .. side)
        tex:SetPoint("BOTTOM" .. side)
        tex:SetWidth(SNAP_W)
    else
        tex:SetPoint(side .. "LEFT")
        tex:SetPoint(side .. "RIGHT")
        tex:SetHeight(SNAP_W)
    end
    tex:Show()
    snapShown[#snapShown + 1] = x
end

-- the edge of the other note and the matching edge of the dragged one light up
function Stickies.ShowSnap(f)
    local x, side = Stickies.FindSnap(f)
    Stickies.HideSnap()
    if not x then return end
    EdgeLine(x, side)
    EdgeLine(f, OPPOSITE[side])
end

function Stickies.Dock(f, host, side)
    local g = Geo(f.note)
    g.dock = { id = NoteId(host.note), side = side }
    ApplyGeometry(f)
    Stickies.Paint(f)
    Render(f)
end

-- free again where it is now, at the size it has now
function Stickies.Undock(f)
    local g = Geo(f.note)
    local l, t = f:GetLeft(), f:GetTop()
    g.dock = nil
    if l and t then
        g.l, g.t = l, t
        g.w = f:GetWidth()
        if not g.collapsed then g.h = f:GetHeight() end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.l or 0, g.t or 0)
    Stickies.Paint(f)
end

-- the formatted text
Render = function(f)
    local note = f.note
    if not note then return end
    Stickies.Paint(f)
    local size = Stickies.Settings().size
    local width = math.max(40, f:GetWidth() - 2 * PAD)
    f.content:SetWidth(width)
    local lines = Lines(note.text)
    local y, shown = 0, 0
    local blank = ns.IsBlank(note.text)
    for i, line in ipairs(blank and {} or lines) do
        local r = Row(f, i)
        r.index = i
        local kind, text, on = ParseLine(line)
        local indent = (kind == "text") and 0 or 20
        r.check:SetShown(kind == "check")
        if kind == "check" then r.check.mark:SetShown(on) end
        r.dot:SetShown(kind == "bullet")
        ns.ApplyFont(r.dot, size, "")
        ns.ApplyFont(r.text, size, "")
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT", indent, 0)
        r.text:SetWidth(width - indent)
        r.text:SetText(text ~= "" and text or " ")
        local c = on and T.muted or T.text
        r.text:SetTextColor(c[1], c[2], c[3], 1)
        local h = (text == "" and kind == "text") and math.floor(size * 0.6)
            or math.max(r.text:GetStringHeight(), kind == "check" and 16 or size) + 3
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetSize(width, h)
        r:Show()
        y = y + h
        shown = i
    end
    for i = shown + 1, #f.rows do f.rows[i]:Hide() end
    f.content:SetHeight(math.max(1, y))
    f.empty:SetShown(blank)
    if blank then
        ns.ApplyFont(f.empty, size, "")
        f.empty:SetText(Muted(L["Click to write.  [ ] makes a checkbox, - a list."]))
    end
end

SetEditing = function(f, on)
    if not f.note or (on and Geo(f.note).collapsed) then return end
    if f.editing == on then return end
    f.editing = on
    f.scroll:SetShown(not on)
    f.empty:SetShown(false)
    f.editor:SetShown(on)
    if on then
        ns.ApplyFont(f.editor.edit, Stickies.Settings().size, "")
        f.editor:SetValue(f.note.text)
        f.editor.edit:SetFocus()
        f.editor.edit:SetCursorPosition(#(f.note.text or ""))
    else
        if f.editor.edit:HasFocus() then f.editor.edit:ClearFocus() end
        Render(f)
    end
    Stickies.Paint(f)
end
Stickies.SetEditing = SetEditing
-- stepping aside in combat ends the writing (the text is saved as you type)
layer:SetScript("OnHide", function()
    for _, f in pairs(byNote) do if f.editing then SetEditing(f, false) end end
end)

-- the checkbox in line i flips
function Stickies.Tick(f, i)
    local note = f.note
    if not note then return end
    local lines = Lines(note.text)
    local line = lines[i]
    if not line then return end
    local _, _, on = ParseLine(line)
    lines[i] = line:gsub("%[[ xX]?%]", on and "[ ]" or "[x]", 1)
    note.text = table.concat(lines, "\n")
    Notes.Touch(note)
    Render(f)
    Notes.Changed("sticky")
end

-- footer buttons: change the cursor's line while editing, else add a line
function Stickies.LineButton(f, kind)
    local note = f.note
    if not note or Geo(note).collapsed then return end
    if f.editing then
        local e = f.editor.edit
        local text, cursor = Stickies.ToggleLine(e:GetText(), e:GetCursorPosition(), kind)
        e:SetText(text)
        e:SetCursorPosition(cursor)
        note.text = text
    else
        local text = note.text or ""
        if text ~= "" and not text:find("\n$") then text = text .. "\n" end
        note.text = text .. (kind == "check" and "[ ] " or "- ")
        SetEditing(f, true)
    end
    Notes.Touch(note)
    Stickies.Paint(f)
    Notes.Changed("sticky")
end

function Stickies.Fold(f)
    local g = Geo(f.note)
    if f.editing then SetEditing(f, false) end
    if not g.collapsed then SaveGeometry(f) end
    g.collapsed = not g.collapsed or nil
    ApplyGeometry(f)
    if not g.collapsed then Render(f) else Stickies.Paint(f) end
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------
function Stickies.Frame(note) return byNote[note] end

function Stickies.Open(note)
    if not note then return end
    local f = byNote[note]
    if not f then
        for _, x in ipairs(frames) do
            if not x.note then f = x break end
        end
        f = f or Create()
        f.note = note
        byNote[note] = f
    end
    Geo(note).open = true
    f.editing = nil
    f.editor:Hide()
    f.scroll:Show()
    ApplyGeometry(f)
    f:Show()
    f:Raise()
    Render(f)
    -- notes that were docked here and are already open come back to it
    for _, x in ipairs(DockedTo(f)) do ApplyGeometry(x) Stickies.Paint(x) end
    return f
end

function Stickies.Close(note)
    local f = byNote[note]
    if note and note.sticky then note.sticky.open = nil end
    if f then
        -- what hangs here stays where it is, as a free note
        for _, x in ipairs(DockedTo(f)) do Stickies.Undock(x) end
        if HostOf(f) then
            local l, t = f:GetLeft(), f:GetTop()
            if l and t then note.sticky.l, note.sticky.t = l, t end
        end
        if f.editing then SetEditing(f, false) end
        f:Hide()
        f.note = nil
        byNote[note] = nil
    end
    Notes.Changed("sticky")
end

function Stickies.Toggle(note)
    if IsOpen(note) then Stickies.Close(note) else Stickies.Open(note) end
end

function Stickies.CloseAll()
    local list = {}
    for note in pairs(byNote) do list[#list + 1] = note end
    for _, note in ipairs(list) do Stickies.Close(note) end
end

function Stickies.Count()
    local n = 0
    for _ in pairs(byNote) do n = n + 1 end
    return n
end

-- after any change: drop windows of deleted notes, show new text
local function Sync(source)
    if not next(byNote) then return end   -- nothing on the screen
    local alive = {}
    Notes.ForEach(function(note) alive[note] = true end)
    for note, f in pairs(byNote) do
        if not alive[note] then
            for _, x in ipairs(DockedTo(f)) do Stickies.Undock(x) end
            f:Hide()
            f.note = nil
            byNote[note] = nil
        elseif source ~= "sticky" and not f.editing then
            Render(f)
        else
            Stickies.Paint(f)
        end
    end
end
Notes.OnChange(Sync)

-- ---------------------------------------------------------------------------
-- Settings tab in the notes page
-- ---------------------------------------------------------------------------
local settings
function Stickies.ShowSettings(p)
    if not settings then
        settings = {}
        local W = 300
        UI.Label(p, L["NEW STICKY NOTES"], 0, -4)
        local function Slider(label, field, minV, maxV, step, fmt, y, apply)
            local s = UI.ValueSlider(p, label, minV, maxV, step,
                function() return Stickies.Settings()[field] end,
                function(v)
                    Stickies.Settings()[field] = v
                    if apply then apply() end
                end, W, fmt)
            s:SetPoint("TOPLEFT", 0, y)
            settings[#settings + 1] = s
        end
        Slider(L["Width"], "w", MIN_W, 500, 10, "%d px", -24)
        Slider(L["Height"], "h", MIN_H, 500, 10, "%d px", -64)
        UI.Label(p, L["ALL STICKY NOTES"], 0, -112)
        Slider(L["Text size"], "size", 10, 18, 1, "%d pt", -132, function()
            for note, f in pairs(byNote) do if not f.editing then Render(f) end end
        end)
        settings.count = ns.Text(p, 12)
        settings.count:SetPoint("TOPLEFT", 0, -182)
        local closeAll = UI.Button(p, 140, L["Close all"], function()
            Stickies.CloseAll()
            Stickies.ShowSettings(p)
        end, 22)
        closeAll:SetPoint("TOPLEFT", 0, -202)

        local X = W + 40
        UI.Label(p, L["HOW IT WORKS"], X, -4)
        local help = UI.Hint(p, "", App.CONTENT_W - X)
        help:SetPoint("TOPLEFT", X, -24)
        help:SetSpacing(4)
        ns.Paint(function()
            help:SetText(table.concat({
                L["\"Sticky\" above a note puts it on the screen."],
                L["Drag the colored bar to move it, the corner to resize it. The lock keeps both."],
                L["Drop it at the edge of another sticky note to dock it there: same size, moves along. Pull it away to undock."],
                L["Click the text to write; Esc or \"Done\" shows it formatted again."],
                "",
                ns.Code("[ ]") .. "  " .. L["checkbox (click it to tick)"],
                ns.Code("[x]") .. "  " .. L["ticked"],
                ns.Code("- ") .. "  " .. L["list item"],
            }, "\n"))
        end)
    end
    for _, s in ipairs(settings) do s:Refresh() end
    settings.count:SetText(L["Open right now: %d"]:format(Stickies.Count()))
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ns.On("LOGIN", function()
    Notes.ForEach(function(note) if IsOpen(note) then Stickies.Open(note) end end)
    -- docks: every host is open now
    for _, f in pairs(byNote) do
        if HostOf(f) then ApplyGeometry(f) Stickies.Paint(f) end
    end
end)
ns.On("THEME_CHANGED", function()
    for _, f in pairs(byNote) do if not f.editing then Render(f) end end
end)
ns.On("SETTINGS_RESET", function(keys)
    if keys.notes then Sync("reset") end
end)
