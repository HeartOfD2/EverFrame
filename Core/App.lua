-- ---------------------------------------------------------------------------
-- The app window: one place for settings and tools, laid out like a web app.
--   header    logo, title, breadcrumb of the open page, close
--   sidebar   navigation, grouped into sections
--   content   the open page
--   footer    status messages, version
-- Pages register themselves and are built the first time they open:
--   App:AddPage({ key, section, label, order, Build(self, frame), Refresh(self),
--                 IsVisible() })
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI = ns.UI

local APP_W, APP_H = 820, 540
local HEADER_H, FOOTER_H, SIDEBAR_W, PAD = 48, 28, 196, 16
local NAV_H = 26

local App = {
    pages = {}, byKey = {}, sections = {},
    CONTENT_W = APP_W - SIDEBAR_W - 2 * PAD,
    CONTENT_H = APP_H - HEADER_H - FOOTER_H - 2 * PAD,
}
ns.App = App

function App:AddSection(key, label, order)
    table.insert(self.sections, { key = key, label = label, order = order or 50 })
    table.sort(self.sections, function(a, b) return a.order < b.order end)
end

App:AddSection("hud", L["HUD"], 10)
App:AddSection("macros", L["MACROS"], 20)
App:AddSection("addon", L["ADDON"], 90)

function App:AddPage(def)
    def.order = def.order or 50
    table.insert(self.pages, def)
    self.byKey[def.key] = def
    table.sort(self.pages, function(a, b) return a.order < b.order end)
    return def
end

local function Visible(def) return not def.IsVisible or def.IsVisible() end
local function SectionLabel(key)
    for _, s in ipairs(App.sections) do if s.key == key then return s.label end end
    return ""
end

local win, sidebar, content, crumb, statusText, navButtons
local current

-- ---------------------------------------------------------------------------
-- Footer status
-- ---------------------------------------------------------------------------
function App.Status(msg, isAlert)
    if not statusText then return end
    statusText:SetText(msg and ns.Colorize(isAlert and HEX.alert or HEX.muted, msg) or "")
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local function Geometry() return ns.Acct().app or {} end

local function SaveGeometry()
    local l, t = win:GetLeft(), win:GetTop()
    if not (l and t) then return end
    local g = Geometry()
    g.l, g.t, g.w, g.h = l, t, win:GetWidth(), win:GetHeight()
    ns.Acct().app = g
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end

local function ApplyGeometry()
    local g = Geometry()
    win:ClearAllPoints()
    if g.l and g.t then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.l, g.t)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    win:SetSize(math.max(APP_W, g.w or APP_W), math.max(APP_H, g.h or APP_H))
end

local function Build()
    if win then return end
    win = CreateFrame("Frame", "UERApp", UIParent)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetResizable(true)
    win:SetClampedToScreen(true)
    if win.SetResizeBounds then win:SetResizeBounds(APP_W, APP_H, 1600, 1100) end
    win:Hide()
    ns.Skin(win, T.window)
    table.insert(UISpecialFrames, "UERApp")

    -- header ------------------------------------------------------------------
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing() SaveGeometry() end)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    ns.Color(hbg, T.panel)
    local strip = header:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(2)
    ns.Color(strip, T.accent)
    local hline = header:CreateTexture(nil, "ARTWORK")
    hline:SetPoint("BOTTOMLEFT")
    hline:SetPoint("BOTTOMRIGHT")
    hline:SetHeight(1)
    ns.Color(hline, T.divider)
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(34, 34)
    logo:SetPoint("LEFT", 10, -1)
    logo:SetTexture("Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Icon")
    local title = ns.Text(header, 14)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -2)
    title:SetText(ns.TITLE)
    ns.Color(title, T.accent)
    local sub = ns.Text(header, 10)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    ns.Color(sub, T.muted)
    sub:SetText(L["Settings and tools"])
    crumb = ns.Text(header, 14)
    crumb:SetPoint("LEFT", header, "LEFT", SIDEBAR_W + PAD, -1)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -10, 0)
    close.text = ns.Text(close, 18)
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("×")
    ns.Color(close.text, T.muted)
    close.hl = close:CreateTexture(nil, "HIGHLIGHT")
    close.hl:SetAllPoints()
    ns.Color(close.hl, T.hover)
    close:SetScript("OnEnter", function(self) ns.SetColor(self.text, T.text) end)
    close:SetScript("OnLeave", function(self) ns.SetColor(self.text, T.muted) end)
    close:SetScript("OnClick", function() win:Hide() end)
    win.close = close
    -- dark / light switch, like the theme toggle of a web app
    local themeBtn = UI.Button(header, 96, "", function()
        ns.SetTheme(ns.ThemeSettings().mode == "dark" and "light" or "dark")
    end, 22)
    themeBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
    ns.Paint(function() themeBtn.text:SetText(T.mode == "dark" and L["Light mode"] or L["Dark mode"]) end)
    UI.Tooltip(themeBtn, { L["Switch between dark and light mode"] }, "ANCHOR_BOTTOM")

    -- footer ------------------------------------------------------------------
    local footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOTER_H)
    local fbg = footer:CreateTexture(nil, "BACKGROUND")
    fbg:SetAllPoints()
    ns.Color(fbg, T.panel)
    local fline = footer:CreateTexture(nil, "ARTWORK")
    fline:SetPoint("TOPLEFT")
    fline:SetPoint("TOPRIGHT")
    fline:SetHeight(1)
    ns.Color(fline, T.divider)
    local version = ns.Text(footer, 11)
    version:SetPoint("RIGHT", -30, 0)
    ns.Color(version, T.muted)
    version:SetText(("%s  ·  /uer"):format(ns.VERSION))
    statusText = ns.Text(footer, 11)
    statusText:SetPoint("LEFT", SIDEBAR_W + PAD, 0)
    statusText:SetPoint("RIGHT", version, "LEFT", -12, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)
    local grip = CreateFrame("Button", nil, footer)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing() SaveGeometry() end)

    -- sidebar -----------------------------------------------------------------
    sidebar = CreateFrame("Frame", nil, win)
    sidebar:SetPoint("TOPLEFT", 0, -HEADER_H)
    sidebar:SetPoint("BOTTOMLEFT", 0, FOOTER_H)
    sidebar:SetWidth(SIDEBAR_W)
    local sbg = sidebar:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    ns.Color(sbg, T.sidebar)
    local sline = sidebar:CreateTexture(nil, "ARTWORK")
    sline:SetPoint("TOPRIGHT")
    sline:SetPoint("BOTTOMRIGHT")
    sline:SetWidth(1)
    ns.Color(sline, T.divider)
    navButtons = {}

    -- content -----------------------------------------------------------------
    content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", SIDEBAR_W + PAD, -HEADER_H - PAD)
    content:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + PAD)

    win:SetScript("OnShow", function()
        App:RenderNav()
        App:Select(current or ns.Char().ui.appPage or "general")
    end)
    win:SetScript("OnHide", function()
        UI.CloseMenu()
        for _, def in ipairs(App.pages) do
            if def.frame and def.OnHide then ns.SafeCall(def.OnHide, def) end
        end
    end)
    ApplyGeometry()
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------
local function NavButton(i)
    local b = navButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, sidebar)
    b:SetHeight(NAV_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.bg:SetAllPoints()
    ns.Color(b.bg, T.accentSoft)
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetPoint("TOPLEFT")
    b.mark:SetPoint("BOTTOMLEFT")
    b.mark:SetWidth(3)
    ns.Color(b.mark, T.accent)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    ns.Color(b.hl, T.hover)
    b.text = ns.Text(b, 12)
    b.text:SetPoint("LEFT", 16, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        if self.pageKey then App:Select(self.pageKey) end
    end)
    navButtons[i] = b
    return b
end

function App:RenderNav()
    if not win then return end
    local i, y = 0, -12
    for _, s in ipairs(self.sections) do
        local any = false
        for _, def in ipairs(self.pages) do
            if def.section == s.key and Visible(def) then any = true break end
        end
        if any then
            i = i + 1
            local h = NavButton(i)
            h.pageKey = nil
            h:EnableMouse(false)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, y)
            h:SetPoint("TOPRIGHT", -1, y)
            h:SetHeight(22)
            h.text:SetText(ns.Muted(s.label))
            ns.ApplyFont(h.text, 10, "")
            h.bg:Hide()
            h.mark:Hide()
            h:Show()
            y = y - 22
            for _, def in ipairs(self.pages) do
                if def.section == s.key and Visible(def) then
                    i = i + 1
                    local b = NavButton(i)
                    b.pageKey = def.key
                    b:EnableMouse(true)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 0, y)
                    b:SetPoint("TOPRIGHT", -1, y)
                    b:SetHeight(NAV_H)
                    b.text:SetText(def.label)
                    ns.ApplyFont(b.text, 13, "")
                    local on = def.key == current
                    b.bg:SetShown(on)
                    b.mark:SetShown(on)
                    b.text:SetTextColor(unpack(on and T.accent or T.text))
                    b:Show()
                    y = y - NAV_H
                end
            end
            y = y - 10
        end
    end
    for j = i + 1, #navButtons do navButtons[j]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------
function App:Select(key)
    local def = self.byKey[key]
    if not def or not Visible(def) then def = self.byKey.general end
    if not def then return end
    -- exactly one page visible: hide every other one that is still shown
    for _, other in ipairs(self.pages) do
        if other ~= def and other.frame and other.frame:IsShown() then
            other.frame:Hide()
            if other.OnHide then ns.SafeCall(other.OnHide, other) end
        end
    end
    current = def.key
    ns.Char().ui.appPage = def.key
    if not def.frame then
        def.frame = CreateFrame("Frame", nil, content)
        def.frame:SetAllPoints(content)
        def:Build(def.frame)
    end
    def.frame:Show()
    App:UpdateCrumb()
    App.Status(nil)
    self:RenderNav()
    if def.Refresh then ns.SafeCall(def.Refresh, def) end
end

function App:UpdateCrumb()
    local def = current and self.byKey[current]
    if crumb and def then crumb:SetText(ns.Muted(SectionLabel(def.section) .. "  ›  ") .. def.label) end
end

function App:Open(key)
    Build()
    if key then current = key end
    if win:IsShown() then
        self:Select(key or current)
    else
        win:Show()
    end
end

function App:Toggle(key)
    Build()
    if win:IsShown() and (not key or key == current) then
        win:Hide()
    else
        self:Open(key)
    end
end

function App:IsOpen(key)
    return win and win:IsShown() and (not key or current == key) or false
end

function App:Current() return current end

-- the open page re-reads its data
function App:RefreshCurrent()
    if not self:IsOpen() then return end
    local def = self.byKey[current]
    if def and def.Refresh then ns.SafeCall(def.Refresh, def) end
end

function ns.ToggleOptions() App:Toggle() end

ns.On("MODULES_CHANGED", function()
    if not App:IsOpen() then return end
    App:RenderNav()
    local def = App.byKey[current]
    if def and not Visible(def) then App:Select("modules") end
end)
ns.On("THEME_CHANGED", function()
    if not win then return end
    App:RenderNav()
    App:UpdateCrumb()
    App:RefreshCurrent()
end)
ns.On("SETTINGS_RESET", function(keys) if win and keys.windows then ApplyGeometry() end end)
for _, msg in ipairs({ "HUD_SETTINGS_CHANGED", "LAYOUT_APPLIED", "SETTINGS_RESET" }) do
    ns.On(msg, function() App:RefreshCurrent() end)
end
