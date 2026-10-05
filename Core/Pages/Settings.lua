-- ---------------------------------------------------------------------------
-- Settings pages of the app window: General, Layout, Cooldowns (HUD section)
-- and Modules, Reset, About (Addon section). Modules can add their own block
-- to the Modules page (module:BuildOptions(parent, width) -> height).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, HUD, App = ns.UI, ns.HUD, ns.App

local CW = App.CONTENT_W
local refresh, leave = {}, {}
local function Status(msg, isAlert) App.Status(msg, isAlert) end
local function Char() return ns.Char() end

-- ---------------------------------------------------------------------------
-- General
-- ---------------------------------------------------------------------------
local function BuildGeneral(p)
    local COL2 = 292
    local COLW = CW - COL2

    UI.Label(p, L["FRAME"], 0, 0)
    local scaleLbl = ns.Text(p, 12)
    scaleLbl:SetPoint("TOPLEFT", 0, -20)
    scaleLbl:SetText(L["Scale"])
    local scaleVal = ns.Text(p, 12)
    scaleVal:SetPoint("TOPLEFT", 214, -20)
    local slider = UI.Slider(p, 0.5, 2.0, 0.05,
        function() return Char().hud.scale or 1 end,
        function(v)
            HUD:SetScale(v)
            scaleVal:SetText(("%d%%"):format(v * 100 + 0.5))
        end, 250)
    slider:SetPoint("TOPLEFT", 0, -40)

    local lockBtn
    lockBtn = UI.Button(p, 122, "", function()
        HUD:SetLocked(not HUD:IsLocked())
        lockBtn.text:SetText(HUD:IsLocked() and L["Unlock"] or L["Lock"])
    end)
    lockBtn:SetPoint("TOPLEFT", 0, -62)
    local resetPos = UI.Button(p, 122, L["Reset position"], function()
        HUD:ResetPosition()
        Status(L["Position reset."])
    end)
    resetPos:SetPoint("LEFT", lockBtn, "RIGHT", 6, 0)
    local center = UI.CheckRow(p, L["Center horizontally (only up/down)"],
        function() return Char().hud.centerX end, function(v) HUD:SetCenterX(v) end)
    center:SetPoint("TOPLEFT", 0, -90)

    UI.Label(p, L["VISIBILITY"], 0, -126)
    local holdLbl, holdBtn, holdHint
    local function RefreshHold()
        holdBtn.text:SetText(L[Char().hud.holdKey or "ALT"])
        local a = (Char().hud.hide or "never") ~= "never" and 1 or 0.4
        holdLbl:SetAlpha(a)
        holdBtn:SetAlpha(a)
        holdHint:SetAlpha(a)
    end
    local hideLbl = ns.Text(p, 12)
    hideLbl:SetPoint("TOPLEFT", 0, -148)
    hideLbl:SetText(L["Hide the frame"])
    local hideBox = UI.Dropdown(p, {
        { "never",   L["Never (always show)"] },
        { "combat",  L["Out of combat"] },
        { "target",  L["Without a target"] },
        { "vehicle", L["In a vehicle"] },
    }, function() return Char().hud.hide or "never" end,
    function(v) Char().hud.hide = v RefreshHold() end, 160)
    hideBox:SetPoint("TOPLEFT", 90, -144)
    holdLbl = ns.Text(p, 12)
    holdLbl:SetPoint("TOPLEFT", 0, -176)
    holdLbl:SetText(L["Hold to show"])
    holdBtn = UI.Button(p, 70, "", function()
        local keys = HUD.HOLD_KEYS
        local i = ns.IndexOf(keys, Char().hud.holdKey) or 0
        Char().hud.holdKey = keys[i % #keys + 1]
        RefreshHold()
    end)
    holdBtn:SetPoint("TOPLEFT", 180, -172)
    holdHint = UI.Hint(p, L["While hidden, holding this key shows the frame. Unlocked, the frame always shows."], 250)
    holdHint:SetPoint("TOPLEFT", 0, -198)

    UI.Label(p, L["MINIMAP"], COL2, 0)
    local mmRow = UI.CheckRow(p, L["Minimap button"],
        function() return ns.IsMinimapButtonShown() end,
        function(v) ns.SetMinimapButtonShown(v) end)
    mmRow:SetPoint("TOPLEFT", COL2, -18)
    local mmHint = UI.Hint(p, L["Left-click: settings  ·  Shift-click: notes  ·  Right-click: macros"], COLW)
    mmHint:SetPoint("TOPLEFT", COL2, -42)

    UI.Label(p, L["RANGE CHECKS"], COL2, -86)
    local rateBtns = {}
    local function RefreshRates()
        local cur = Char().range.interval or 0.1
        for i, b in ipairs(rateBtns) do
            local on = math.abs(ns.RANGE_RATES[i][1] - cur) < 1e-3
            b:SetAccent(on)
            b.text:SetTextColor(unpack(on and T.accent or T.text))
        end
    end
    local rateW = (COLW - 4 * 4) / 5
    for i, r in ipairs(ns.RANGE_RATES) do
        local b = UI.Button(p, rateW, r[2], function()
            Char().range.interval = r[1]
            RefreshRates()
        end)
        b:SetPoint("TOPLEFT", COL2 + (i - 1) * (rateW + 4), -104)
        rateBtns[i] = b
    end
    local rateHint = UI.Hint(p, L["Checks per second. 10/s feels instant; fewer saves a little work."], COLW)
    rateHint:SetPoint("TOPLEFT", COL2, -130)

    UI.Label(p, L["NOTES IN COMBAT"], 0, -244)
    local noteRows = {
        UI.CheckRow(p, L["Hide the sticky notes"],
            function() return ns.Notes.HideInCombat("stickies") end,
            function(v) ns.Notes.SetHideInCombat("stickies", v) end, 270),
        UI.CheckRow(p, L["Hide the player notes (target popup)"],
            function() return ns.Notes.HideInCombat("popup") end,
            function(v) ns.Notes.SetHideInCombat("popup", v) end, 270),
        UI.CheckRow(p, L["Holding the key shows them too"],
            function() return ns.Notes.DB().holdShowsNotes and true or false end,
            function(v) ns.Notes.DB().holdShowsNotes = v and true or nil end, 270),
    }
    for i, r in ipairs(noteRows) do r:SetPoint("TOPLEFT", 0, -262 - (i - 1) * 22) end
    UI.Tooltip(noteRows[3], { L["Holding the key shows them too"],
        L["The key of \"Hold to show\" (left) brings hidden notes back while you hold it."] })

    UI.Label(p, L["APPEARANCE"], COL2, -176)
    local modeBtns, accentBtns = {}, {}
    local function RefreshAppearance()
        local th = ns.ThemeSettings()
        for key, b in pairs(modeBtns) do
            b:SetAccent(th.mode == key)
            ns.SetColor(b.text, th.mode == key and T.accent or T.text)
        end
        for key, b in pairs(accentBtns) do
            b:SetAccent(th.accent == key)
            ns.SetColor(b.text, th.accent == key and T.accent or T.text)
        end
    end
    for i, key in ipairs(ns.THEME_MODES) do
        local b = UI.Button(p, 122, key == "dark" and L["Dark"] or L["Light"], function()
            ns.SetTheme(key, nil)
            RefreshAppearance()
        end)
        b:SetPoint("TOPLEFT", COL2 + (i - 1) * 128, -194)
        modeBtns[key] = b
    end
    local ACCENT_LABEL = { teal = L["Teal"], amber = L["Amber"], blue = L["Blue"] }
    for i, key in ipairs(ns.THEME_ACCENTS) do
        local b = UI.Button(p, 80, ACCENT_LABEL[key], function()
            ns.SetTheme(nil, key)
            RefreshAppearance()
        end)
        b:SetPoint("TOPLEFT", COL2 + (i - 1) * 86, -222)
        b.text:ClearAllPoints()
        b.text:SetPoint("CENTER", 6, 0)
        b.swatch = b:CreateTexture(nil, "ARTWORK")
        b.swatch:SetSize(8, 8)
        b.swatch:SetPoint("RIGHT", b.text, "LEFT", -5, 0)
        local c = ns.ACCENT_SAMPLES[key]
        b.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        accentBtns[key] = b
    end
    local themeHint = UI.Hint(p, L["The combat frame keeps its dark tiles in both modes; the accent color applies everywhere."], COLW)
    themeHint:SetPoint("TOPLEFT", COL2, -250)

    refresh.general = function()
        RefreshAppearance()
        slider:Refresh()
        scaleVal:SetText(("%d%%"):format((Char().hud.scale or 1) * 100 + 0.5))
        lockBtn.text:SetText(HUD:IsLocked() and L["Unlock"] or L["Lock"])
        center:Refresh()
        for _, r in ipairs(noteRows) do r:Refresh() end
        hideBox:Refresh()
        mmRow:Refresh()
        RefreshHold()
        RefreshRates()
    end
end

-- ---------------------------------------------------------------------------
-- Layout: the parts of the frame on the left (show, order, pick one), the
-- look of the picked part on the right. Every change shows on the frame at
-- once; while this page is open the frame stays visible out of combat.
-- ---------------------------------------------------------------------------
local PRESETS = { "{cur}", "{cur} / {max}", "{cur} / {max} ({pct}%)", "{pct}%", "-{deficit}" }
local LIST_W, ROW_H = 214, 26
local INS_X = LIST_W + 20
local INS_W = CW - INS_X

-- a style field as get/set pair; set skips unchanged values (sliders call often)
local function StyleField(key, field)
    return function() return HUD:Get(key, field) end,
        function(v)
            if HUD:Get(key, field) == v then return end
            HUD:Set(key, field, v)
            if HUD:IsLayoutPending() then Status(L["In combat: the frame updates when combat ends."], true) end
        end
end

local function BuildLayout(p)
    HUD.preview = true
    leave.layout = function() HUD.preview = false end
    local selected = "frame"
    local panels, rows = {}, {}
    local Select

    -- ---------------------------------------------------------------- list
    UI.Label(p, L["PARTS, TOP TO BOTTOM"], 0, 0)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, -18)
    list:SetSize(LIST_W, 8 + 11 * ROW_H)
    ns.Skin(list, T.panel, T.line)

    local function PaintRow(row)
        local on = row.key == selected
        row.bg:SetShown(on)
        row.bar:SetShown(on)
    end
    local function Row(i)   -- 0 = the frame itself
        if rows[i] then return rows[i] end
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", 4, -4 - i * ROW_H)
        row:SetPoint("TOPRIGHT", -4, -4 - i * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        ns.Color(row.bg, T.accentSoft)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT")
        row.bar:SetPoint("BOTTOMLEFT")
        row.bar:SetWidth(2)
        ns.Color(row.bar, T.accent)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        ns.Color(row.hl, T.hover)
        row.label = ns.Text(row, 12)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.hint = ns.Text(row, 11)
        ns.Color(row.hint, T.muted)
        if i == 0 then
            row.label:SetPoint("LEFT", 10, 0)
            row.hint:SetPoint("RIGHT", -8, 0)
        else
            local check = UI.Check(row)
            check:SetPoint("LEFT", 8, 0)
            check:SetScript("OnClick", function()
                HUD:SetHidden(row.key, not HUD:IsHidden(row.key))
                refresh.layout()
                if HUD:IsLayoutPending() then Status(L["In combat: the frame updates when combat ends."], true) end
            end)
            row.check = check
            row.label:SetPoint("LEFT", 30, 0)
            row.down = UI.ArrowButton(row, false, function() HUD:Move(row.key, 1) refresh.layout() end)
            row.down:SetPoint("RIGHT", -2, 0)
            row.up = UI.ArrowButton(row, true, function() HUD:Move(row.key, -1) refresh.layout() end)
            row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
            row.hint:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
        end
        row.label:SetPoint("RIGHT", row.hint, "LEFT", -6, 0)
        row:SetScript("OnClick", function(self) Select(self.key) end)
        rows[i] = row
        return row
    end

    local resetAll = UI.ConfirmButton(p, 130, L["Reset layout"], function()
        ns.ResetCategories({ layout = true })
        Status(L["Layout reset."])
    end)
    resetAll:SetPoint("BOTTOMLEFT", 0, 0)
    UI.Tooltip(resetAll, { L["Reset layout"], L["Order, visibility and look of the frame parts."] })

    -- ---------------------------------------------------------------- inspector
    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", INS_X - 10, 0)
    divider:SetPoint("BOTTOMLEFT", INS_X - 10, 0)
    divider:SetWidth(1)
    ns.Color(divider, T.divider)

    local function Panel(key, title, sub)
        local panel = CreateFrame("Frame", nil, p)
        panel:SetPoint("TOPLEFT", INS_X, 0)
        panel:SetPoint("BOTTOMRIGHT", 0, 0)
        panel:Hide()
        panel.widgets = {}
        panel.title = ns.Text(panel, 15)
        panel.title:SetPoint("TOPLEFT", 0, 0)
        panel.title:SetText(title)
        panel.sub = UI.Hint(panel, sub or "", INS_W)
        panel.sub:SetPoint("TOPLEFT", 0, -20)
        panel.y = sub and -42 or -28
        panels[key] = panel
        return panel
    end
    local function Put(panel, w, h, x)
        w:SetPoint("TOPLEFT", x or 0, panel.y)
        panel.y = panel.y - h
        if w.Refresh then panel.widgets[#panel.widgets + 1] = w end
        return w
    end
    local function Section(panel, text)
        panel.y = panel.y - 6
        UI.Label(panel, text, 0, panel.y)
        panel.y = panel.y - 18
    end
    local function Slider(panel, key, field, label, minV, maxV, fmt)
        local get, set = StyleField(key, field)
        return Put(panel, UI.ValueSlider(panel, label, minV, maxV, 1, get, set, INS_W, fmt or "%d px"), 38)
    end
    local function Check(panel, key, field, label, tip)
        local get, set = StyleField(key, field)
        local row = UI.CheckRow(panel, label, function() return get() ~= false end,
            function(v) set(v and true or false) end, INS_W)
        if tip then UI.Tooltip(row, { label, tip }) end
        return Put(panel, row, 24)
    end
    -- bar color: own / class / custom, the swatch shows what the bar uses
    local function ColorRow(panel, key, ownLabel, ownColor)
        Section(panel, L["COLOR"])
        local seg, swatch
        seg = UI.Segmented(panel, {
            { "default", ownLabel }, { "class", L["Class color"] }, { "custom", L["Custom"] },
        }, function() return HUD:Get(key, "colorMode") or "default" end,
        function(v)
            if v == "custom" and not HUD:Get(key, "color") then
                local c = ns.StyleColor(key, ownColor())
                HUD:Set(key, "color", { c[1], c[2], c[3] })
            end
            HUD:Set(key, "colorMode", v)
            swatch:Refresh()
        end, INS_W - 58)
        Put(panel, seg, 0)
        swatch = UI.ColorSwatch(panel, L["Bar color"],
            function() return ns.StyleColor(key, ownColor()) end,
            function(c)
                if c then
                    HUD:Set(key, "color", c)
                    HUD:Set(key, "colorMode", "custom")
                else
                    HUD:Set(key, "color", nil)
                    HUD:Set(key, "colorMode", "default")
                end
                seg:Refresh()
            end, ownColor)
        swatch:SetPoint("LEFT", seg, "RIGHT", 12, 0)
        panel.widgets[#panel.widgets + 1] = swatch
        panel.y = panel.y - 26
    end
    -- a labelled color swatch (nil = the default color)
    local function SwatchRow(panel, key, field, label, default)
        local text = ns.Text(panel, 12)
        text:SetPoint("TOPLEFT", 0, panel.y - 3)
        text:SetText(label)
        local get, set = StyleField(key, field)
        local sw = UI.ColorSwatch(panel, label, get, set, default)
        sw:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
        panel.widgets[#panel.widgets + 1] = sw
        panel.y = panel.y - 26
    end
    -- a labelled listbox for a style field
    local function DropRow(panel, key, field, label, items, fallback)
        local text = ns.Text(panel, 12)
        text:SetPoint("TOPLEFT", 0, panel.y - 4)
        text:SetText(label)
        local get, set = StyleField(key, field)
        local dd = UI.Dropdown(panel, items, function() return get() or fallback end, set, 190)
        dd:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
        panel.widgets[#panel.widgets + 1] = dd
        panel.y = panel.y - 28
        return dd
    end
    -- text format with presets, size, alignment, on/off
    local function TextBlock(panel, key, field, sample)
        Section(panel, L["TEXT"])
        local box = UI.LineEdit(panel, 13, 60)
        box:SetSize(INS_W - 92, 24)
        Put(panel, box, 0)
        local preview = UI.Hint(panel, "", INS_W)
        local function RefreshPreview()
            preview:SetText(L["Preview:"] .. " " .. ns.FillValueText(Char().text[field] or "{cur}", sample[1], sample[2])
                .. "   " .. ns.Code("{cur} {max} {pct} {deficit}"))
        end
        local function Apply(fmt)
            Char().text[field] = fmt
            RefreshPreview()
            local def = HUD.byKey[key]
            if def.shown then def:Update() end   -- no game event tells the bar
        end
        box:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local v = self:GetText()
            Apply((v ~= "") and v or "{cur}")
        end)
        UI.Tooltip(box, function()
            return { L["Text format"],
                ns.Code("{cur}") .. "  " .. L["current value"],
                ns.Code("{max}") .. "  " .. L["maximum"],
                ns.Code("{pct}") .. "  " .. L["percent, rounded"],
                ns.Code("{deficit}") .. "  " .. L["missing to maximum"],
                L["Any other text stays as typed, e.g. \"HP {cur}\". If the game hides the values in combat, the text falls back to what it still allows."] }
        end)
        local presets
        presets = UI.Button(panel, 86, L["Presets"], function()
            local items = {}
            for _, fmt in ipairs(PRESETS) do
                items[#items + 1] = { label = ns.FillValueText(fmt, sample[1], sample[2]), desc = fmt,
                    checked = Char().text[field] == fmt,
                    fn = function()
                        box:SetText(fmt)
                        Apply(fmt)
                    end }
            end
            UI.OpenMenu(presets, items)
        end, 24)
        presets:SetPoint("LEFT", box, "RIGHT", 6, 0)
        panel.y = panel.y - 28
        Put(panel, preview, 20)
        Slider(panel, key, "textSize", L["Text size"], 8, 20, "%d pt")
        local get, set = StyleField(key, "textAlign")
        local align = UI.Segmented(panel, {
            { "LEFT", L["Left"] }, { "CENTER", L["Center"] }, { "RIGHT", L["Right"] },
        }, function() return get() or "CENTER" end, set, 192)
        Put(panel, align, 0)
        local showGet, showSet = StyleField(key, "showText")
        local show = UI.CheckRow(panel, L["Show text"], function() return showGet() ~= false end,
            function(v) showSet(v and true or false) end, INS_W - 206)
        show:SetPoint("LEFT", align, "RIGHT", 14, 0)
        panel.widgets[#panel.widgets + 1] = show
        panel.y = panel.y - 26
        panel.widgets[#panel.widgets + 1] = { Refresh = function()
            if not box:HasFocus() then box:SetText(Char().text[field] or "{cur}") end
            RefreshPreview()
        end }
    end

    -- frame
    do
        local panel = Panel("frame", L["Frame"], L["Size, spacing and background. Position: General."])
        Put(panel, UI.ValueSlider(panel, L["Width"], 160, 340, 2,
            function() return HUD:FrameGet("width") end,
            function(v) if HUD:FrameGet("width") ~= v then HUD:SetFrame("width", v) end end, INS_W, "%d px"), 38)
        Put(panel, UI.ValueSlider(panel, L["Spacing between parts"], 0, 12, 1,
            function() return HUD:FrameGet("gap") end,
            function(v) if HUD:FrameGet("gap") ~= v then HUD:SetFrame("gap", v) end end, INS_W, "%d px"), 38)
        Section(panel, L["BACKGROUND"])
        local bg = Put(panel, UI.CheckRow(panel, L["Background behind the frame"],
            function() return HUD:FrameGet("backdrop") end,
            function(v) HUD:SetFrame("backdrop", v and true or false) end, INS_W - 58), 0)
        local bgSwatch = UI.ColorSwatch(panel, L["Background color"],
            function() return HUD:FrameGet("backdropColor") end,
            function(c)
                HUD:SetFrame("backdropColor", c)
                if c and not HUD:FrameGet("backdrop") then HUD:SetFrame("backdrop", true) bg:Refresh() end
            end, function() return T.hudBackdrop end)
        bgSwatch:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y + 1)
        panel.widgets[#panel.widgets + 1] = bgSwatch
        panel.y = panel.y - 26
        Put(panel, UI.ValueSlider(panel, L["Opacity"], 10, 100, 5,
            function() return math.floor(HUD:FrameGet("backdropAlpha") * 100 + 0.5) end,
            function(v) HUD:SetFrame("backdropAlpha", v / 100) end, INS_W, "%d%%"), 38)
        panel.y = panel.y - 10
        Put(panel, UI.Hint(panel, L["Tip: the frame stays visible while this page is open, so you can watch every change."], INS_W), 30)
    end

    -- health
    do
        local panel = Panel("health", L["Health"])
        Slider(panel, "health", "height", L["Height"], 10, 36)
        ColorRow(panel, "health", L["Default"], function() return T.health end)
        TextBlock(panel, "health", "health", { 300, 471 })
        Section(panel, L["LOW HEALTH"])
        Check(panel, "health", "warn", L["Mark the warning zone and pulse below it"])
        Slider(panel, "health", "warnPct", L["Warning below"], 10, 60, "%d%%")
    end

    -- resource
    do
        local panel = Panel("power", L["Resource"], L["Mana, rage or energy: the bar follows your current resource."])
        Slider(panel, "power", "height", L["Height"], 10, 36)
        ColorRow(panel, "power", L["Resource color"], function()
            local _, token = UnitPowerType("player")
            return ns.PowerColor(token)
        end)
        TextBlock(panel, "power", "power", { 64, 100 })
    end

    -- combo points
    do
        local panel = Panel("combo", L["Combo points"])
        Slider(panel, "combo", "height", L["Height"], 6, 24)
        DropRow(panel, "combo", "shape", L["Shape"], {
            { "bars", L["Bars"] }, { "circles", L["Circles"] }, { "diamonds", L["Diamonds"] },
        }, "bars")
        Put(panel, UI.Hint(panel, L["Circles and diamonds take the height as their size."], INS_W), 18)
        Section(panel, L["COLOR"])
        SwatchRow(panel, "combo", "color", L["Filled points"], function() return T.combo end)
        SwatchRow(panel, "combo", "maxColor", L["All points full"], function() return T.comboMax end)
        Section(panel, L["ALL POINTS FULL"])
        local fx = DropRow(panel, "combo", "maxEffect", L["Effect"], {
            { "glow",  L["Glow"],  L["halo breathes"] },
            { "pulse", L["Pulse"], L["points beat"] },
            { "wave",  L["Wave"],  L["light runs across"] },
            { "none",  L["None"],  L["color only"] },
        }, "glow")
        -- a sound when the points fill up
        local soundGet, soundSet = StyleField("combo", "soundOn")
        local soundRow = UI.CheckRow(panel, L["Sound"], function() return soundGet() and true or false end,
            function(v) soundSet(v and true or false) end, INS_W - 196)
        soundRow:SetPoint("TOPLEFT", 0, panel.y - 1)
        panel.widgets[#panel.widgets + 1] = soundRow
        local items = {}
        for _, s in ipairs(ns.COMBO_SOUNDS) do items[#items + 1] = { s[1], s[2] } end
        local sGet, sSet = StyleField("combo", "sound")
        local soundDD = UI.Dropdown(panel, items, function() return sGet() or "raid" end, function(v)
            sSet(v)
            ns.PlayComboSound(v)   -- hear what you picked
            if not soundGet() then soundSet(true) soundRow:Refresh() end
        end, 190)
        soundDD:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
        panel.widgets[#panel.widgets + 1] = soundDD
        UI.Tooltip(soundRow, { L["Sound"], L["Plays once when all combo points are full (not while the game hides them)."] })
        panel.y = panel.y - 28
        local baseRefresh = fx.Refresh
        function fx:Refresh()   -- 1.0 stored "glow off" instead of an effect
            local saved = Char().style.parts.combo
            if saved and saved.maxEffect == nil and saved.glow == false then
                self.text:SetText(L["None"])
            else
                baseRefresh(self)
            end
        end
    end

    -- range
    do
        local panel = Panel("range", L["Range"], L["Distance to your target in bands of your class's abilities."])
        Slider(panel, "range", "height", L["Height"], 12, 28)
        Slider(panel, "range", "textSize", L["Text size"], 8, 16, "%d pt")
    end

    -- poison tiles: nothing to style
    Panel("poisons", L["Poison tracker"], L["The poison tiles have a fixed look. Show, hide and move them in the list."])

    -- cooldown bars: one shared look
    do
        local panel = Panel("cooldowns", "", L["These settings apply to all cooldown bars."])
        Slider(panel, "cooldowns", "iconSize", L["Icon size"], 20, 40)
        Check(panel, "cooldowns", "numbers", L["Countdown numbers on the icons"])
        Check(panel, "cooldowns", "dimReady", L["Dim icons that are ready"],
            L["Only cooldowns that are running stand out."])
        panel.y = panel.y - 8
        local count = Put(panel, UI.Hint(panel, "", INS_W), 36)
        local open = UI.Button(panel, 180, L["Choose cooldowns ›"], function() App:Select("cooldowns") end)
        Put(panel, open, 26)
        panel.widgets[#panel.widgets + 1] = { Refresh = function()
            local bar = HUD.byKey[selected] and HUD.byKey[selected].cooldownBar
            panel.title:SetText(HUD.byKey[selected] and HUD.byKey[selected].label or "")
            if bar then
                count:SetText(L["On this bar: %d of %d cooldowns. Bigger icons leave room for fewer."]:format(
                    ns.Cooldowns:BarCount(bar), ns.Cooldowns.PerBar()))
            end
        end }
    end

    local resetPart = UI.Button(p, 150, L["Default look"], function()
        HUD:ResetStyle(HUD.byKey[selected] and HUD.byKey[selected].cooldownBar and "cooldowns" or selected)
        refresh.layout()
        Status(L["Default look restored."])
    end)
    resetPart:SetPoint("BOTTOMRIGHT", 0, 0)

    local function PanelKey(key)
        local def = HUD.byKey[key]
        if def and def.cooldownBar then return "cooldowns" end
        return key
    end
    function Select(key)
        selected = key
        refresh.layout()
    end

    refresh.layout = function()
        HUD.preview = true
        local order = HUD:VisibleOrder()
        if selected ~= "frame" and not ns.IndexOf(order, selected) then selected = "frame" end
        local frameRow = Row(0)
        frameRow.key = "frame"
        frameRow.label:SetText(L["Frame"])
        frameRow.hint:SetText(("%d px"):format(HUD:FrameGet("width")))
        PaintRow(frameRow)
        for i, key in ipairs(order) do
            local def = HUD.byKey[key]
            local row = Row(i)
            row.key = key
            local hidden = HUD:IsHidden(key)
            local ok, why = HUD:IsAvailable(def)
            row.label:SetText(def.label)
            row.check:SetOn(not hidden)
            row.label:SetAlpha((hidden or not ok) and 0.45 or 1)
            if not ok then
                row.hint:SetText(why or L["not available"])
            elseif def.cooldownBar then
                local n = ns.Cooldowns:BarCount(def.cooldownBar)
                row.hint:SetText(("%d/%d"):format(n, ns.Cooldowns.PerBar()))
            else
                row.hint:SetText("")
            end
            row.up.arrow:SetAlpha(i == 1 and 0.25 or 1)
            row.down.arrow:SetAlpha(i == #order and 0.25 or 1)
            PaintRow(row)
            row:Show()
        end
        for i = #order + 1, #rows do rows[i]:Hide() end
        local show = PanelKey(selected)
        for key, panel in pairs(panels) do
            panel:SetShown(key == show)
            if key == show then
                for _, w in ipairs(panel.widgets) do w:Refresh() end
            end
        end
        resetPart:SetShown(show ~= "poisons")
    end
    ns.On("HUD_STYLE_CHANGED", function()
        if p:IsShown() then refresh.layout() end
    end)
end

-- ---------------------------------------------------------------------------
-- Cooldowns: which ones, which bar, which order; add your own
-- ---------------------------------------------------------------------------
local function BuildCooldowns(p)
    local CD = ns.Cooldowns
    local ROW_H, ROWS = 24, 11
    UI.Label(p, L["COOLDOWN"], 26, 0)
    local barLabel = UI.Label(p, L["BAR"], CW - 154, 0)
    barLabel:SetWidth(98)
    barLabel:SetJustifyH("CENTER")
    local orderLabel = UI.Label(p, L["ORDER"], 0, 0)
    orderLabel:ClearAllPoints()
    orderLabel:SetPoint("TOPRIGHT", 0, 0)
    orderLabel:SetJustifyH("RIGHT")
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, -18)
    list:SetSize(CW, ROW_H * ROWS)
    list:EnableMouseWheel(true)
    local rows, entries, scroll, counts = {}, {}, 0, {}

    local function Render()
        entries, counts = CD:List()
        local maxScroll = math.max(0, #entries - ROWS)
        scroll = math.max(0, math.min(scroll, maxScroll))
        for i, row in ipairs(rows) do
            local e = entries[scroll + i]
            row.entry = e
            if e then
                local available = CD:IsAvailable(e)
                local hidden = CD:IsHidden(e.key)
                CD:RefreshIcon(e)
                row.icon:SetTexture(e.frame.icon:GetTexture())
                row.icon:SetDesaturated(hidden or not available)
                local name = CD:EntryName(e)
                local tag
                if e.kind == "racial" then tag = L["racial"]
                elseif e.kind == "special" then tag = L["module"]
                elseif e.kind == "book" then tag = L["spellbook"]
                elseif e.kind == "custom" then tag = e.itemID and L["item"] or L["spell"] end
                if tag then name = name .. "  " .. ns.Muted(tag) end
                if not available then name = name .. "  " .. ns.Muted(L["not learned"]) end
                row.label:SetText(name)
                row.label:SetAlpha(hidden and 0.45 or 1)
                row.check:SetOn(not hidden)
                row.remove:SetShown(e.kind == "custom")
                row.bg:SetColorTexture(T.hover[1], T.hover[2], T.hover[3], (e.bar % 2 == 0) and T.hover[4] or 0)
                for b, btn in ipairs(row.bars) do
                    local on = b == e.bar
                    btn:SetAccent(on)
                    btn.text:SetTextColor(unpack(on and T.accent or T.muted))
                    btn:SetAlpha((on or (counts[b] or 0) < CD.PerBar()) and 1 or 0.35)
                end
                local first, last = true, true
                for _, o in ipairs(entries) do
                    if o.bar == e.bar and o ~= e then
                        if o.pos < e.pos then first = false else last = false end
                    end
                end
                row.up.arrow:SetAlpha(first and 0.25 or 1)
                row.down.arrow:SetAlpha(last and 0.25 or 1)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(CW, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.check = UI.Check(row)
        row.check:SetPoint("LEFT", 4, 0)
        row.check:SetScript("OnClick", function()
            CD:SetHidden(row.entry.key, not CD:IsHidden(row.entry.key))
            Render()
        end)
        row.iconEdge = row:CreateTexture(nil, "ARTWORK")
        row.iconEdge:SetSize(20, 20)
        row.iconEdge:SetPoint("LEFT", 26, 0)
        ns.Color(row.iconEdge, T.line)
        row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("CENTER", row.iconEdge)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label = ns.Text(row, 12)
        row.label:SetPoint("LEFT", 52, 0)
        row.label:SetPoint("RIGHT", -178, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.remove = UI.Button(row, 18, "×", function()
            local e = row.entry
            if not (e and e.kind == "custom") then return end
            local name = CD:EntryName(e)
            CD:RemoveCustom(e.key)
            Render()
            Status(L["Removed %s."]:format(name))
        end, 18)
        row.remove:SetPoint("RIGHT", -158, 0)
        UI.Tooltip(row.remove, { L["Remove"] })
        row.bars = {}
        for b = 1, CD.BARS do
            local btn = UI.Button(row, 18, tostring(b), function()
                local ok, why = CD:SetBar(row.entry.key, b)
                if not ok and why then Status(why, true) end
                Render()
            end, 18)
            btn:SetPoint("RIGHT", -(52 + (CD.BARS - b) * 20), 0)
            row.bars[b] = btn
        end
        row.up = UI.ArrowButton(row, true, function() CD:Move(row.entry.key, -1) Render() end)
        row.up:SetPoint("RIGHT", -26, 0)
        row.down = UI.ArrowButton(row, false, function() CD:Move(row.entry.key, 1) Render() end)
        row.down:SetPoint("RIGHT", -4, 0)
        rows[i] = row
    end
    list:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta
        Render()
    end)

    -- add your own: drag in, shift-click a link, or type a name or ID
    local addY = -18 - ROWS * ROW_H - 10
    UI.Label(p, L["ADD AN ITEM OR SPELL  (potions, bandages, trinkets ...)"], 0, addY)
    local box = UI.LineEdit(p, 13)
    box:SetPoint("TOPLEFT", 0, addY - 16)
    box:SetSize(CW - 76, 24)
    UI.Placeholder(box, L["Drag it here, shift-click its link, or type its name or ID"])
    local function Add(text)
        local kind, id = CD:Parse(text or box:GetText())
        if not kind then Status(id, true) return end
        local e, why = CD:AddCustom(kind, id)
        if not e then Status(why, true) return end
        box:SetText("")
        box:ClearFocus()
        scroll = 1e6   -- new entries land at the end
        Render()
        Status(L["Added %s to bar %d."]:format(CD:EntryName(e), CD:Bar(e.key)))
    end
    local function AddFromCursor()
        if not GetCursorInfo then return end
        local kind, a, _, c = GetCursorInfo()
        if kind == "item" and a then
            ClearCursor()
            Add("item:" .. a)
        elseif kind == "spell" and (c or a) then
            ClearCursor()
            Add("spell:" .. (c or a))
        end
    end
    box:SetScript("OnReceiveDrag", AddFromCursor)
    box:SetScript("OnMouseDown", function() if GetCursorInfo and GetCursorInfo() then AddFromCursor() end end)
    box:SetScript("OnEnterPressed", function() Add() end)
    -- shift-clicking an item while the box has focus drops its link in here
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if box:HasFocus() and type(link) == "string" then box:Insert(link) end
        end)
    end
    local addBtn = UI.Button(p, 70, L["Add"], function() Add() end, 24)
    addBtn:SetPoint("LEFT", box, "RIGHT", 6, 0)
    addBtn:SetAccent(true)

    local hint = UI.Hint(p, "", CW)
    hint:SetPoint("BOTTOMLEFT", 0, 0)

    refresh.cooldowns = function()
        hint:SetText(L["Up to %d per bar. Abilities found in your spellbook are listed, but not shown on a bar until you tick them."]:format(CD.PerBar()))
        Render()
    end
end

-- ---------------------------------------------------------------------------
-- Modules: switch feature packs on and off, plus their own settings
-- ---------------------------------------------------------------------------
local function BuildModules(p)
    UI.Label(p, L["MODULES"], 0, 0)
    local intro = UI.Hint(p, L["Modules add features for a class. A module for another class stays off on this character."], CW)
    intro:SetPoint("TOPLEFT", 0, -18)
    local sections = {}
    local y = -48
    local shown = 0
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        if m:IsClassAllowed() then
        shown = shown + 1
        local s = CreateFrame("Frame", nil, p)
        s:SetPoint("TOPLEFT", 0, y)
        s:SetSize(CW, 60)
        ns.Skin(s, T.panel)
        s.row = UI.CheckRow(s, m.title or key,
            function() return m:IsEnabledSetting() end,
            function(v)
                m:SetEnabled(v)
                refresh.modules()
            end, 240)
        s.row:SetPoint("TOPLEFT", 10, -8)
        s.row.label:SetFontObject(GameFontHighlight)
        ns.ApplyFont(s.row.label, 13, "")
        s.status = ns.Text(s, 11)
        s.status:SetPoint("TOPRIGHT", -10, -12)
        s.desc = UI.Hint(s, m.desc or "", CW - 20)
        s.desc:SetPoint("TOPLEFT", 10, -30)
        local h = 52
        if m.BuildOptions then
            local box = CreateFrame("Frame", nil, s)
            box:SetPoint("TOPLEFT", 10, -h)
            box:SetSize(CW - 20, 10)
            local used = m:BuildOptions(box, CW - 20) or 0
            box:SetHeight(used)
            s.options = box
            h = h + used + 8
        end
        s:SetHeight(h)
        y = y - h - 10
        s.module = m
        sections[#sections + 1] = s
        end
    end
    if shown == 0 then
        local none = UI.Hint(p, L["There is no module for this class yet."], CW)
        none:SetPoint("TOPLEFT", 0, -48)
    end
    refresh.modules = function()
        for _, s in ipairs(sections) do
            local m = s.module
            s.row:Refresh()
            local allowed = m:IsClassAllowed()
            s.row:SetDisabled(not allowed)
            if not allowed then
                s.status:SetText(ns.Muted(m.classHint or L["not for this class"]))
            elseif m:IsActive() then
                s.status:SetText(ns.Colorize(HEX.good, L["active"]))
            else
                s.status:SetText(ns.Muted(L["off"]))
            end
            if s.options then
                if m.RefreshOptions then m:RefreshOptions() end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Reset: tick what to reset
-- ---------------------------------------------------------------------------
local function BuildReset(p)
    UI.Label(p, L["CHOOSE WHAT TO RESET"], 0, 0)
    local selected = {}
    local rows = {}
    local ROW_H = 24
    local i = 0
    for _, def in ipairs(ns.resetCategories) do
        if not def.IsVisible or def.IsVisible() then
        i = i + 1
        local row = UI.CheckRow(p, def.label,
            function() return selected[def.key] end,
            function(v) selected[def.key] = v or nil end, 200)
        row:SetPoint("TOPLEFT", 0, -20 - (i - 1) * ROW_H)
        if def.danger then ns.Color(row.label, T.alert) end
        row.desc = ns.Text(p, 11)
        row.desc:SetPoint("LEFT", row, "RIGHT", 6, 0)
        row.desc:SetWidth(CW - 206)
        row.desc:SetJustifyH("LEFT")
        row.desc:SetWordWrap(false)
        ns.Color(row.desc, T.muted)
        row.desc:SetText((def.accountWide and (L["All characters"] .. " · ") or "") .. def.desc)
        UI.Tooltip(row, { def.label, def.desc, def.accountWide and L["Applies to all characters of this account."]
            or L["Applies to this character only."] })
        rows[#rows + 1] = row
        end
    end
    local function RefreshRows() for _, r in ipairs(rows) do r:Refresh() end end
    local all = UI.Button(p, 110, L["Select all"], function()
        for _, def in ipairs(ns.resetCategories) do
            if not def.danger and (not def.IsVisible or def.IsVisible()) then selected[def.key] = true end
        end
        RefreshRows()
    end)
    all:SetPoint("BOTTOMLEFT", 0, 0)
    local none = UI.Button(p, 110, L["Select none"], function()
        wipe(selected)
        RefreshRows()
    end)
    none:SetPoint("LEFT", all, "RIGHT", 6, 0)
    local go = UI.ConfirmButton(p, 150, L["Reset selected"], function()
        if not next(selected) then Status(L["Nothing selected."], true) return end
        local done = ns.ResetCategories(selected)
        wipe(selected)
        RefreshRows()
        Status(L["Reset: %s."]:format(table.concat(done, ", ")))
        ns.Print(L["Reset: %s."]:format(table.concat(done, ", ")))
    end)
    go:SetPoint("BOTTOMRIGHT", 0, 0)
    go:SetAccent(true)
    local hint = UI.Hint(p, L["A setup wizard will follow once the features are settled."], CW)
    hint:SetPoint("BOTTOMLEFT", all, "TOPLEFT", 0, 12)
    refresh.reset = RefreshRows
end

-- ---------------------------------------------------------------------------
-- About
-- ---------------------------------------------------------------------------
local function BuildAbout(p)
    local logo = p:CreateTexture(nil, "ARTWORK")
    logo:SetSize(128, 128)
    logo:SetPoint("TOPLEFT", 0, 0)
    logo:SetTexture("Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Logo")
    local title = ns.Text(p, 20)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 18, -10)
    title:SetText(ns.TITLE)
    ns.Color(title, T.accent)
    local version = ns.Text(p, 12)
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    version:SetText(L["Version"] .. " " .. ns.VERSION .. "  ·  " .. L["for WoW: Forever"])
    ns.Color(version, T.muted)
    local desc = UI.Hint(p, L["A compact combat frame for health, resource, combo points, range and cooldowns, with a macro manager and player notes. Class features come as modules; the rogue module adds poisons, Slice and Dice and weapon macros."], CW - 146)
    desc:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -12)
    ns.Color(desc, T.text)
    desc:SetSpacing(3)

    UI.Label(p, L["CREDITS"], 0, -150)
    local credits = UI.Hint(p, table.concat({
        L["Author: %s"]:format("HeartOfD2"),
        L["License: MIT  ·  Source: github.com/HeartOfD2/Ultimate-EverRogue"],
        L["Inspired by %s by %s"]:format("RogueEnergyCombo", "Goldfire86"),
    }, "\n"), CW)
    credits:SetPoint("TOPLEFT", 0, -168)
    credits:SetSpacing(4)

    UI.Label(p, L["CHAT COMMANDS"], 0, -236)
    local help = UI.Hint(p, "", CW)
    help:SetPoint("TOPLEFT", 0, -254)
    help:SetSpacing(3)
    ns.Paint(function() help:SetText(ns.CommandHelpText and ns.CommandHelpText() or "") end)
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
local function Page(key, section, label, order, build)
    App:AddPage({
        key = key, section = section, label = label, order = order,
        Build = function(_, frame) build(frame) end,
        Refresh = function() if refresh[key] then refresh[key]() end end,
        OnHide = function() if leave[key] then leave[key]() end end,
    })
end

Page("general",   "hud",   L["General"],   10, BuildGeneral)
Page("layout",    "hud",   L["Layout"],    20, BuildLayout)
Page("cooldowns", "hud",   L["Cooldowns"], 30, BuildCooldowns)
Page("modules",   "addon", L["Modules"],   910, BuildModules)
Page("reset",     "addon", L["Reset"],     920, BuildReset)
Page("about",     "addon", L["About"],     990, BuildAbout)
