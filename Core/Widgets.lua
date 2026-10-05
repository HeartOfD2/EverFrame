-- ---------------------------------------------------------------------------
-- UI building blocks in the addon's flat style: windows, tabs, buttons,
-- checkboxes, sliders, text boxes, a dropdown menu and a message box.
-- No Blizzard templates are needed, so they look the same on every client.
-- ---------------------------------------------------------------------------
local _, ns = ...
local T, HEX = ns.T, ns.HEX
local Skin, Text, SetEdgeColor = ns.Skin, ns.Text, ns.SetEdgeColor
local UI = {}
ns.UI = UI

-- window with an accent strip on top, a title and a close cross.
-- opts.noEscape: ESC doesn't close it; opts.fixed: not draggable
function UI.Window(name, w, h, title, opts)
    opts = opts or {}
    local p = CreateFrame("Frame", name, UIParent)
    p:SetSize(w, h)
    p:SetFrameStrata(opts.strata or "DIALOG")
    p:EnableMouse(true)
    p:Hide()
    Skin(p, T.window)
    local strip = p:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(2)
    ns.Color(strip, T.accent)
    p.title = Text(p, 13)
    p.title:SetPoint("TOPLEFT", 14, -11)
    p.title:SetText(title or "")
    local close = CreateFrame("Button", nil, p)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -6, -7)
    close.text = Text(close, 16)
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("×")
    ns.Color(close.text, T.muted)
    close:SetScript("OnEnter", function(self) ns.SetColor(self.text, T.text) end)
    close:SetScript("OnLeave", function(self) ns.SetColor(self.text, T.muted) end)
    close:SetScript("OnClick", function() p:Hide() end)
    p.close = close
    if name and not opts.noEscape then table.insert(UISpecialFrames, name) end
    if not opts.fixed then
        p:SetMovable(true)
        p:SetClampedToScreen(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", function(self) self:StartMoving() end)
        p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    end
    return p
end

-- one line of status text at the bottom of a window
function UI.StatusLine(parent, inset)
    local fs = Text(parent, 11)
    fs:SetPoint("BOTTOMLEFT", inset or 14, 10)
    fs:SetPoint("BOTTOMRIGHT", -(inset or 14), 10)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return function(msg, isAlert)
        fs:SetText(msg and ns.Colorize(isAlert and HEX.alert or HEX.muted, msg) or "")
    end, fs
end

-- small muted capital heading above a group of controls
function UI.Label(parent, text, x, y)
    local fs = Text(parent, 11)
    fs:SetPoint("TOPLEFT", x, y)
    ns.Color(fs, T.muted)
    fs:SetText(text)
    return fs
end

-- muted text that wraps at the given width
function UI.Hint(parent, text, width)
    local fs = Text(parent, 11)
    fs:SetJustifyH("LEFT")
    ns.Color(fs, T.muted)
    if width then fs:SetWidth(width) end
    fs:SetText(text or "")
    return fs
end

-- dialogs open in the upper third of the screen
function UI.PlaceDialog(frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -math.floor((UIParent:GetHeight() or 768) * 0.14))
end

function UI.Button(parent, width, label, onClick, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 20)
    Skin(b, T.control)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    ns.Color(b.hl, T.hover)
    b.text = Text(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetText(label or "")
    if onClick then b:SetScript("OnClick", onClick) end
    function b:SetAccent(on)
        SetEdgeColor(self, on and T.accent or nil)
    end
    return b
end

-- attaches a simple tooltip (lines: first is the title)
function UI.Tooltip(frame, lines, anchor)
    frame:SetScript("OnEnter", function(self)
        local l = lines
        if type(l) == "function" then l = l(self) end   -- may return nothing: no tooltip
        if type(l) ~= "table" or #l == 0 then return end
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        for i, line in ipairs(l) do
            if i == 1 then
                GameTooltip:AddLine(line, 1, 1, 1)
            else
                GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
            end
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- two clicks within 3 seconds: the first one only arms the button
function UI.ConfirmButton(parent, width, label, onConfirm, height)
    local b
    local armedUntil = 0
    b = UI.Button(parent, width, label, function()
        if GetTime() > armedUntil then
            armedUntil = GetTime() + 3
            b.text:SetText(ns.Colorize(HEX.alert, ns.L["Click again"]))
            C_Timer.After(3.05, function()
                if GetTime() >= armedUntil then b.text:SetText(b.label) end
            end)
            return
        end
        armedUntil = 0
        b.text:SetText(b.label)
        onConfirm(b)
    end, height)
    b.label = label
    function b:SetLabel(s) self.label = s self.text:SetText(s) end
    return b
end

-- chevron texture: dir "right" | "down" | "left" | "up"
local ARROW_ROT = { right = 0, down = -90, left = 180, up = 90 }
function UI.Arrow(parent, size, dir)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size or 12, size or 12)
    t:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    t:SetDesaturated(true)
    ns.Paint(function() t:SetVertexColor(T.text[1], T.text[2], T.text[3], 0.85) end)
    function t:Point(d) self:SetRotation(math.rad(ARROW_ROT[d])) end
    t:Point(dir or "right")
    return t
end

-- small square button with an up/down chevron
function UI.ArrowButton(parent, up, onClick)
    local b = UI.Button(parent, 18, "", onClick, 18)
    b.arrow = UI.Arrow(b, 12, up and "up" or "down")
    b.arrow:SetPoint("CENTER")
    return b
end

-- flat checkbox: accent square when on
function UI.Check(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(14, 14)
    Skin(c, T.control, T.input)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    ns.Color(c.hl, T.hover)
    c.mark = c:CreateTexture(nil, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    ns.Color(c.mark, T.accent)
    function c:SetOn(on) self.on = on and true or false self.mark:SetShown(self.on) end
    function c:IsOn() return self.on end
    c:SetOn(false)
    return c
end

-- checkbox with a label; get/set read and write the setting
function UI.CheckRow(parent, label, get, set, width)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width or 260, 20)
    row.check = UI.Check(row)
    row.check:SetPoint("LEFT", 0, 0)
    row.label = Text(row, 12)
    row.label:SetPoint("LEFT", 22, 0)
    row.label:SetPoint("RIGHT", 0, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetText(label)
    local function Toggle()
        if row.disabled then return end
        set(not get())
        row:Refresh()
    end
    row:SetScript("OnClick", Toggle)
    row.check:SetScript("OnClick", Toggle)
    function row:Refresh() self.check:SetOn(get()) end
    function row:SetDisabled(d)
        self.disabled = d
        self:SetAlpha(d and 0.4 or 1)
    end
    return row
end

-- click/drag slider: thin track, accent fill, white thumb
function UI.Slider(parent, minV, maxV, step, get, set, width)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width or 192, 12)
    s:EnableMouse(true)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(4)
    ns.Color(s.track, T.control)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("LEFT")
    s.fill:SetHeight(4)
    ns.Color(s.fill, T.accent)
    s.thumb = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.thumb:SetSize(6, 12)
    ns.Color(s.thumb, T.text)
    s.thumbEdge = s:CreateTexture(nil, "OVERLAY", nil, 0)
    s.thumbEdge:SetPoint("TOPLEFT", s.thumb, -1, 1)
    s.thumbEdge:SetPoint("BOTTOMRIGHT", s.thumb, 1, -1)
    ns.Color(s.thumbEdge, T.line)
    local function FromCursor()
        local x = GetCursorPosition() / s:GetEffectiveScale()
        local left, w = s:GetLeft(), s:GetWidth()
        if not left or w <= 0 then return end
        local pct = math.max(0, math.min(1, (x - left) / w))
        set(math.floor((minV + (maxV - minV) * pct) / step + 0.5) * step)
        s:Refresh()
    end
    s:SetScript("OnMouseDown", function(self) self.dragging = true FromCursor() end)
    s:SetScript("OnMouseUp", function(self) self.dragging = false end)
    s:SetScript("OnUpdate", function(self) if self.dragging then FromCursor() end end)
    function s:Refresh()
        local pct = math.max(0, math.min(1, (get() - minV) / (maxV - minV)))
        self.fill:SetWidth(math.max(1, pct * self:GetWidth()))
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self, "LEFT", pct * self:GetWidth(), 0)
    end
    return s
end

-- single-line text box
function UI.LineEdit(parent, size, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    ns.ThemeEdit(e)
    ns.ApplyFont(e, size or 13, "")
    ns.Color(e, T.text)
    e:SetTextInsets(8, 8, 0, 0)
    if maxLetters then e:SetMaxLetters(maxLetters) end
    Skin(e, T.control, T.input)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self) SetEdgeColor(self, T.accent) end)
    e:SetScript("OnEditFocusLost", function(self) SetEdgeColor(self) end)
    return e
end

-- grey placeholder text inside an empty edit box
function UI.Placeholder(edit, text)
    edit.hint = Text(edit, 12)
    edit.hint:SetPoint("LEFT", 8, 0)
    ns.Color(edit.hint, T.muted)
    edit.hint:SetText(text)
    -- watched by a tiny helper frame instead of a script hook: a later
    -- SetScript("OnTextChanged") on the box would remove a hook in game
    local watch = CreateFrame("Frame", nil, edit)
    watch:SetScript("OnUpdate", function() edit.hint:SetShown(edit:GetText() == "") end)
end

-- multi-line editor in a scroll frame that follows its container's size
function UI.TextArea(parent, maxLetters)
    local box = CreateFrame("Frame", nil, parent)
    Skin(box, T.control, T.input)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -6, 6)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    ns.ThemeEdit(e)
    ns.ApplyFont(e, 13, "")
    ns.Color(e, T.text)
    if maxLetters then e:SetMaxLetters(maxLetters) end
    e:SetWidth(100)
    e:SetHeight(50)
    sf:SetScrollChild(e)
    sf:SetScript("OnSizeChanged", function(_, w, h)
        e:SetWidth(math.max(10, w))
        e:SetHeight(math.max(10, h))
    end)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() e:SetFocus() end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 16)))
    end)
    -- keep the cursor in view while typing
    e:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, view, cy = sf:GetVerticalScroll(), sf:GetHeight(), -y
        if cy < top then
            sf:SetVerticalScroll(cy)
        elseif cy + h > top + view then
            sf:SetVerticalScroll(cy + h - view)
        end
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function() SetEdgeColor(box, T.accent) end)
    e:SetScript("OnEditFocusLost", function() SetEdgeColor(box) end)
    box.edit, box.scroll = e, sf
    -- programmatic text: no "user input" flag, back to the top
    function box:SetValue(text)
        e:SetText(text or "")
        e:SetCursorPosition(0)
        sf:SetVerticalScroll(0)
    end
    return box
end

-- tab row: tabs = { { key, label }, ... }; onSelect(key)
function UI.Tabs(parent, tabs, x, y, width, onSelect)
    local row = { buttons = {} }
    for i, t in ipairs(tabs) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", x + (i - 1) * (width + 4), y)
        b.text = Text(b, 12)
        b.text:SetPoint("CENTER")
        b.text:SetText(t[2])
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT")
        b.line:SetPoint("BOTTOMRIGHT")
        b.line:SetHeight(2)
        ns.Color(b.line, T.accent)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        ns.Color(b.hl, T.hover)
        b.key = t[1]
        b:SetScript("OnClick", function() onSelect(t[1]) end)
        row.buttons[t[1]] = b
    end
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", x, y - 22)
    line:SetPoint("TOPRIGHT", -x, y - 22)
    line:SetHeight(1)
    ns.Color(line, T.divider)
    function row:Select(key)
        for k, b in pairs(self.buttons) do
            b.text:SetAlpha(k == key and 1 or 0.55)
            b.line:SetShown(k == key)
        end
    end
    return row
end

-- ---------------------------------------------------------------------------
-- Dropdown menu (one shared instance). items = { { label, fn, checked, icon,
-- isTitle, divider } }. A full-screen catcher closes it on any outside click.
-- ---------------------------------------------------------------------------
do
    local ROW_H, PAD = 20, 4
    local menu = CreateFrame("Frame", "UERMenu", UIParent)
    menu:SetFrameStrata("TOOLTIP")
    menu:EnableMouse(true)
    menu:Hide()
    Skin(menu, T.popover)
    menu.rows = {}
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints()
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()
    local function Close() menu:Hide() catcher:Hide() end
    catcher:SetScript("OnClick", Close)
    UI.CloseMenu = Close
    UI.menu = menu

    local function Row(i)
        local r = menu.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, menu)
        r:SetHeight(ROW_H)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        ns.Color(r.sel, T.accentSoft)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        ns.Color(r.mark, T.accent)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14)
        r.icon:SetPoint("LEFT", 8, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = Text(r, 12)
        r.text:SetJustifyH("LEFT")
        r.desc = Text(r, 11)
        r.desc:SetPoint("RIGHT", -8, 0)
        ns.Color(r.desc, T.muted)
        r.div = r:CreateTexture(nil, "ARTWORK")
        r.div:SetPoint("TOPLEFT")
        r.div:SetPoint("TOPRIGHT")
        r.div:SetHeight(1)
        ns.Color(r.div, T.divider)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.hover)
        menu.rows[i] = r
        return r
    end

    -- opts.point/relPoint/x/y place it next to the anchor; opts.width
    function UI.OpenMenu(anchor, items, opts)
        opts = opts or {}
        if menu:IsShown() and menu.anchor == anchor then Close() return end
        local anyIcon = false
        for _, it in ipairs(items) do if it.icon then anyIcon = true end end
        for i, it in ipairs(items) do
            local r = Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", -PAD, -PAD - (i - 1) * ROW_H)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", anyIcon and 28 or 10, 0)
            if it.isTitle then
                r.text:SetText(ns.Muted(it.label))
                r:EnableMouse(false)
                r:SetScript("OnClick", nil)
                r:SetScript("OnEnter", nil)
                r:SetScript("OnLeave", nil)
            else
                r.text:SetText(it.label)
                r:EnableMouse(true)
                r:SetScript("OnClick", function() Close() if it.fn then it.fn() end end)
                if it.tooltip then UI.Tooltip(r, it.tooltip) else
                    r:SetScript("OnEnter", nil)
                    r:SetScript("OnLeave", nil)
                end
            end
            r.icon:SetShown(it.icon ~= nil)
            if it.icon then r.icon:SetTexture(it.icon) end
            r.desc:SetText(it.desc or "")
            r.sel:SetShown(it.checked and true or false)
            r.mark:SetShown(it.checked and true or false)
            r.div:SetShown(it.divider and true or false)
            r:Show()
        end
        for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
        menu:SetSize(opts.width or 190, PAD * 2 + #items * ROW_H)
        menu:ClearAllPoints()
        menu:SetPoint(opts.point or "TOPRIGHT", anchor, opts.relPoint or "BOTTOMRIGHT", opts.x or 0, opts.y or -4)
        menu.anchor = anchor
        catcher:Show()
        menu:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Segmented control: a row of buttons, the active one in the accent color.
-- items = { { value, label }, ... }
-- ---------------------------------------------------------------------------
function UI.Segmented(parent, items, get, set, width)
    local seg = CreateFrame("Frame", nil, parent)
    local w = (width - (#items - 1) * 4) / #items
    seg:SetSize(width, 22)
    seg.buttons = {}
    for i, it in ipairs(items) do
        local b = UI.Button(seg, w, it[2], function()
            set(it[1])
            seg:Refresh()
        end, 22)
        b:SetPoint("TOPLEFT", (i - 1) * (w + 4), 0)
        b.value = it[1]
        seg.buttons[i] = b
    end
    function seg:Refresh()
        local cur = get()
        for _, b in ipairs(self.buttons) do
            local on = b.value == cur
            b:SetAccent(on)
            ns.SetColor(b.text, on and T.accent or T.text)
        end
    end
    return seg
end

-- listbox: shows the chosen entry, a click opens the list to pick another.
-- items = { { value, label, desc? }, ... } or a function returning that list
function UI.Dropdown(parent, items, get, set, width)
    local dd
    local function Items() return type(items) == "function" and items() or items end
    dd = UI.Button(parent, width, "", function()
        local list = {}
        local cur = get()
        for _, it in ipairs(Items()) do
            list[#list + 1] = { label = it[2], desc = it[3], checked = it[1] == cur,
                fn = function() set(it[1]) dd:Refresh() end }
        end
        UI.OpenMenu(dd, list, { width = math.max(width, 190), point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
    end, 22)
    dd.items = items
    dd.text:ClearAllPoints()
    dd.text:SetPoint("LEFT", 10, 0)
    dd.text:SetPoint("RIGHT", -24, 0)
    dd.text:SetJustifyH("LEFT")
    dd.text:SetWordWrap(false)
    dd.arrow = UI.Arrow(dd, 12, "down")
    dd.arrow:SetPoint("RIGHT", -6, 0)
    function dd:Refresh()
        local cur, list = get(), Items()
        for _, it in ipairs(list) do
            if it[1] == cur then self.text:SetText(it[2]) return end
        end
        self.text:SetText(list[1] and list[1][2] or "")
    end
    dd:Refresh()
    return dd
end

-- slider with its label on the left and the value on the right (height 34)
function UI.ValueSlider(parent, label, minV, maxV, step, get, set, width, fmt)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, 34)
    box.label = Text(box, 12)
    box.label:SetPoint("TOPLEFT", 0, 0)
    box.label:SetText(label)
    box.value = Text(box, 12)
    box.value:SetPoint("TOPRIGHT", 0, 0)
    ns.Color(box.value, T.muted)
    local function Show(v) box.value:SetText((fmt or "%d"):format(v)) end
    box.slider = UI.Slider(box, minV, maxV, step, get, function(v)
        set(v)
        Show(v)
    end, width)
    box.slider:SetPoint("TOPLEFT", 0, -18)
    function box:Refresh()
        self.slider:Refresh()
        Show(get())
    end
    return box
end

-- ---------------------------------------------------------------------------
-- Color swatch: shows a color; a click opens a small popover with the theme's
-- palette, "Default" and (where the game has one) its full color picker.
-- get() -> color or nil (= default), set(color or nil); fallback = the default
-- ---------------------------------------------------------------------------
do
    local pop = CreateFrame("Frame", "UERColorPopover", UIParent)
    pop:SetFrameStrata("TOOLTIP")
    pop:EnableMouse(true)
    pop:Hide()
    Skin(pop, T.popover)
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints()
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()
    local function Close() pop:Hide() catcher:Hide() end
    catcher:SetScript("OnClick", Close)
    UI.CloseColorPopover = Close

    local EXTRA = { { 1, 1, 1 }, { 0.62, 0.65, 0.70 }, { 0.22, 0.80, 0.45 }, { 1.00, 0.80, 0.22 },
                    { 0.25, 0.50, 1.00 }, { 0.92, 0.24, 0.30 } }
    local SW, GAP, COLS = 20, 6, 8
    pop.cells = {}
    local current
    local function Cell(i)
        local c = pop.cells[i]
        if c then return c end
        c = CreateFrame("Button", nil, pop)
        c:SetSize(SW, SW)
        Skin(c, { 1, 1, 1, 1 }, T.line)
        c.hl = c:CreateTexture(nil, "HIGHLIGHT")
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 1, 1, 0.25)
        c:SetScript("OnClick", function(self)
            current.set({ self.color[1], self.color[2], self.color[3] })
            Close()
        end)
        pop.cells[i] = c
        return c
    end
    pop.title = Text(pop, 11)
    pop.title:SetPoint("TOPLEFT", 10, -8)
    ns.Color(pop.title, T.muted)
    pop.more = UI.Button(pop, 10, ns.L["More colors ..."], function()
        local cur = current.get() or current.fallback
        if type(cur) == "function" then cur = cur() end
        local set = current.set
        Close()
        local before = { cur[1], cur[2], cur[3] }
        local function Changed()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            set({ r, g, b })
        end
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({ r = cur[1], g = cur[2], b = cur[3], hasOpacity = false,
                swatchFunc = Changed, cancelFunc = function() set(before) end })
        elseif ColorPickerFrame then
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = Changed
            ColorPickerFrame.cancelFunc = function() set(before) end
            ColorPickerFrame:SetColorRGB(cur[1], cur[2], cur[3])
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end, 20)
    pop.default = UI.Button(pop, 10, ns.L["Default"], function()
        current.set(nil)
        Close()
    end, 20)

    local function Open(anchor, spec)
        current = spec
        pop.title:SetText(spec.title or ns.L["Color"])
        local colors = {}
        for i = 1, #T.tags do colors[#colors + 1] = T.tags[i] end
        for _, c in ipairs(EXTRA) do colors[#colors + 1] = c end
        for i, col in ipairs(colors) do
            local c = Cell(i)
            local row, column = math.floor((i - 1) / COLS), (i - 1) % COLS
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 10 + column * (SW + GAP), -26 - row * (SW + GAP))
            c.color = col
            ns.SetFill(c, { col[1], col[2], col[3], 1 })
            c:Show()
        end
        local rows = math.ceil(#colors / COLS)
        local width = 20 + COLS * SW + (COLS - 1) * GAP
        local y = -26 - rows * (SW + GAP) - 4
        local hasPicker = ColorPickerFrame ~= nil
        pop.default:ClearAllPoints()
        pop.default:SetPoint("TOPLEFT", 10, y)
        pop.default:SetWidth(hasPicker and 70 or (width - 20))
        pop.more:SetShown(hasPicker)
        pop.more:ClearAllPoints()
        pop.more:SetPoint("TOPRIGHT", -10, y)
        pop.more:SetWidth(width - 20 - 76)
        pop:SetSize(width, -y + 30)
        -- open towards the middle of the screen
        pop:ClearAllPoints()
        local x = anchor:GetCenter()
        if x and x > UIParent:GetWidth() / 2 then
            pop:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        else
            pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        end
        catcher:Show()
        pop:Show()
    end
    UI.OpenColorPopover = Open

    function UI.ColorSwatch(parent, title, get, set, fallback)
        local b = CreateFrame("Button", nil, parent)
        b.isSwatch = true
        b:SetSize(46, 20)
        Skin(b, { 1, 1, 1, 1 }, T.input)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.15)
        local spec = { title = title, get = get, fallback = fallback }
        spec.set = function(c)
            set(c)
            b:Refresh()
        end
        b:SetScript("OnClick", function(self) Open(self, spec) end)
        function b:Refresh()
            local c = get() or (type(fallback) == "function" and fallback() or fallback)
            ns.SetFill(self, { c[1], c[2], c[3], 1 })
        end
        b:Refresh()
        return b
    end
end

-- ---------------------------------------------------------------------------
-- Message box. Deliberately not a Blizzard StaticPopup: the poison macros
-- click StaticPopup1 to confirm "replace enchantment?".
-- buttons = { { label, fn, primary }, ... } up to three, right-aligned
-- ---------------------------------------------------------------------------
do
    local box = CreateFrame("Frame", "UERMessageBox", UIParent)
    box:SetSize(400, 190)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    box:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the app window (DIALOG)
    box:EnableMouse(true)
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function(self) self:StartMoving() end)
    box:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    box:Hide()
    Skin(box, T.popover)
    local strip = box:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(2)
    ns.Color(strip, T.accent)
    table.insert(UISpecialFrames, "UERMessageBox")
    box.title = Text(box, 14)
    box.title:SetPoint("TOPLEFT", 16, -14)
    ns.Color(box.title, T.accent)
    box.text = Text(box, 12)
    box.text:SetPoint("TOPLEFT", 16, -38)
    box.text:SetPoint("BOTTOMRIGHT", -16, 44)
    box.text:SetJustifyH("LEFT")
    box.text:SetJustifyV("TOP")
    box.buttons = {}
    for i = 1, 3 do
        local b = UI.Button(box, 118, "", function(self)
            box:Hide()
            if self.fn then self.fn() end
        end, 22)
        b:SetPoint("BOTTOMRIGHT", -16 - (3 - i) * 124, 14)
        box.buttons[i] = b
    end
    -- optional text field (UI.Prompt)
    box.input = UI.LineEdit(box, 13, 40)
    box.input:SetPoint("BOTTOMLEFT", 16, 48)
    box.input:SetPoint("BOTTOMRIGHT", -16, 48)
    box.input:SetHeight(24)
    box.input:Hide()
    function UI.MessageBox(title, text, buttons)
        UI.PlaceDialog(box)
        box.input:Hide()
        box.input:ClearFocus()
        box.text:SetPoint("BOTTOMRIGHT", -16, 44)
        box.title:SetText(title)
        box.text:SetText(text)
        for i, b in ipairs(box.buttons) do
            local spec = buttons[#buttons - 3 + i]
            if spec then
                b.text:SetText(spec[1])
                b.fn = spec[2]
                b:SetAccent(spec[3])
                b:Show()
            else
                b:Hide()
            end
        end
        box:Show()
    end
    -- asks for one line of text; onOK(text) gets it trimmed (not called when empty)
    function UI.Prompt(title, text, default, onOK, okLabel)
        local function OK()
            local v = ns.Trim(box.input:GetText())
            box:Hide()
            if v ~= "" then onOK(v) end
        end
        UI.MessageBox(title, text, { { ns.L["Cancel"] }, { okLabel or ns.L["OK"], OK, true } })
        box.text:SetPoint("BOTTOMRIGHT", -16, 80)
        box.input:SetText(default or "")
        box.input:Show()
        box.input:SetFocus()
        box.input:HighlightText()
        box.input:SetScript("OnEnterPressed", OK)
        box.input:SetScript("OnEscapePressed", function() box:Hide() end)
    end
    UI.messageBox = box
end
