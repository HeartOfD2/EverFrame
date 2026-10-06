-- ---------------------------------------------------------------------------
-- Look and feel. Two modes (dark, light) and three accents (teal, amber,
-- blue), taken from the project's color palette ("Refined Dev-Tool").
--
-- Every color lives in the table T. The tables inside T never change identity:
-- a theme switch rewrites their values in place and repaints everything that
-- registered with ns.Paint / ns.Color / ns.Skin. Code that colors something
-- during a render just reads T again on the next refresh.
--
-- The combat frame (HUD) keeps its own dark tiles in both modes so it stays
-- readable over the game world; only the accent follows the theme there.
-- ---------------------------------------------------------------------------
local _, ns = ...

ns.WHITE = "Interface\\Buttons\\WHITE8X8"

-- Arial Narrow for addon text; clients whose script it lacks keep the default font
ns.FONT = not ({ koKR = true, zhCN = true, zhTW = true, ruRU = true })[ns.LOCALE] and "Fonts\\ARIALN.TTF" or nil

local function RGB(hex, a)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, a or 1 }
end

-- neutral surfaces per mode (background < card/muted), sRGB values of the palette
local MODES = {
    dark = {
        background = RGB("0c0f10"), foreground = RGB("e5e9e9"), card = RGB("141819"),
        popover = RGB("181d1e"), secondary = RGB("202527"), mutedFg = RGB("8a9092"),
        destructive = RGB("ff6467"), border = { 1, 1, 1, 0.09 }, input = { 1, 1, 1, 0.13 },
        sidebar = RGB("101315"), hover = { 1, 1, 1, 0.05 }, shadow = 0.9,
        tags = { "f7857d", "f39762", "e6b55d", "79c77c", "5cc6b9", "74a6ef", "b199f4", "ee8dbd", "98a0a3", "5fc0dd" },
    },
    light = {
        background = RGB("f5f7f7"), foreground = RGB("0f1213"), card = RGB("ffffff"),
        popover = RGB("ffffff"), secondary = RGB("e9ecec"), mutedFg = RGB("5e6466"),
        destructive = RGB("e7000b"), border = RGB("d8dbdc"), input = RGB("d8dbdc"),
        sidebar = RGB("f0f2f2"), hover = { 0, 0, 0, 0.04 }, shadow = 0,
        tags = { "c92f33", "c85d00", "a87600", "308639", "00867a", "3370c7", "7b57c8", "c04688", "5d6567", "007f9e" },
    },
}
-- tag order: red, orange, amber, green, teal, blue, violet, pink, gray, cyan

local ACCENTS = {
    teal  = { brand = "29bdac", fg = "070c0d", mark = "amber" },
    amber = { brand = "efa831", fg = "140b05", mark = "blue" },
    blue  = { brand = "3d84ea", fg = "f6f9fc", mark = "amber" },
}
ns.THEME_MODES = { "dark", "light" }
ns.THEME_ACCENTS = { "teal", "amber", "blue" }
ns.ACCENT_SAMPLES = {}
for k, v in pairs(ACCENTS) do ns.ACCENT_SAMPLES[k] = RGB(v.brand) end

-- the token tables (identity stays, values change with the theme)
local T = {
    -- app surfaces
    window = {}, background = {}, panel = {}, popover = {}, control = {}, sidebar = {},
    line = {}, input = {}, divider = {}, hover = {},
    text = {}, muted = {}, alert = {}, good = {},
    accent = {}, accentText = {}, accentSoft = {}, accentRing = {},
    mark = {},   -- a second accent that stands apart from the selection (template macros)
    tags = {},
    -- combat frame: dark in every mode
    hudPanel = { 0.055, 0.058, 0.07, 0.85 },
    hudBackdrop = { 0.03, 0.035, 0.045, 0.72 },   -- the optional background behind the frame
    hudTrack = { 0.085, 0.09, 0.105, 0.90 },
    hudLine  = { 0, 0, 0, 1 },
    hudText  = { 0.94, 0.95, 0.97, 1 },
    hudMuted = { 0.55, 0.58, 0.64, 1 },
    hudAlert = { 1.00, 0.36, 0.36, 1 },
    sheen    = { 1, 1, 1, 0.08 },
    health   = { 0.22, 0.80, 0.45, 1 },
    combo    = { 0.92, 0.24, 0.30, 1 },
    comboMax = { 1.00, 0.80, 0.22, 1 },
    danger   = { 0.90, 0.12, 0.18, 1 },
}
for i = 1, 10 do T.tags[i] = {} end
ns.T = T
ns.HEX = {}

local function Set(dst, src, alpha)
    dst[1], dst[2], dst[3], dst[4] = src[1], src[2], src[3], alpha or src[4] or 1
end

local function HexOf(c) return ("%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end

local function Compute(mode, accent)
    local m = MODES[mode] or MODES.dark
    local a = ACCENTS[accent] or ACCENTS.teal
    Set(T.window, m.background, 0.97)
    Set(T.background, m.background)
    Set(T.panel, m.card)
    Set(T.popover, m.popover)
    Set(T.control, m.secondary)
    Set(T.sidebar, m.sidebar)
    Set(T.line, m.border)
    Set(T.input, m.input)
    Set(T.divider, m.border)
    Set(T.hover, m.hover)
    Set(T.text, m.foreground)
    Set(T.muted, m.mutedFg)
    Set(T.alert, m.destructive)
    Set(T.good, RGB(m.tags[4]))
    local brand = RGB(a.brand)
    Set(T.accent, brand)
    Set(T.accentText, RGB(a.fg))
    Set(T.accentSoft, brand, 0.14)
    Set(T.accentRing, brand, 0.5)
    Set(T.mark, RGB(ACCENTS[a.mark].brand))
    for i, hex in ipairs(m.tags) do Set(T.tags[i], RGB(hex)) end
    T.shadowAlpha = m.shadow
    T.mode, T.accentName = mode, accent
    local H = ns.HEX
    H.accent, H.muted, H.alert, H.value, H.good = HexOf(T.accent), HexOf(T.muted), HexOf(T.alert), HexOf(T.text), HexOf(T.good)
    H.hudMuted, H.hudAlert, H.hudValue = HexOf(T.hudMuted), HexOf(T.hudAlert), HexOf(T.hudText)
end
Compute("dark", "teal")

-- ---------------------------------------------------------------------------
-- Painting: register a function that colors something; it runs now and again
-- after every theme change
-- ---------------------------------------------------------------------------
local painters = {}
function ns.Paint(fn)
    painters[#painters + 1] = fn
    fn()
end

-- colors a texture or a font string from a token (optionally with own alpha)
function ns.Color(region, color, alpha)
    ns.Paint(function()
        if region.SetTextColor and not region.SetColorTexture then
            region:SetTextColor(color[1], color[2], color[3], alpha or color[4] or 1)
        else
            region:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
        end
    end)
end

-- one-off color (render code): no repaint registration
function ns.SetColor(region, color, alpha)
    if region.SetTextColor and not region.SetColorTexture then
        region:SetTextColor(color[1], color[2], color[3], alpha or color[4] or 1)
    else
        region:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
    end
end

function ns.ThemeSettings()
    local acct = ns.Acct()
    acct.theme = acct.theme or { mode = "dark", accent = "teal" }
    return acct.theme
end

function ns.ApplyTheme()
    local s = ns.ThemeSettings()
    Compute(s.mode, s.accent)
    for i = 1, #painters do ns.SafeCall(painters[i]) end
    ns.Fire("THEME_CHANGED")
end

function ns.SetTheme(mode, accent)
    local s = ns.ThemeSettings()
    s.mode = mode or s.mode
    s.accent = accent or s.accent
    ns.ApplyTheme()
end

-- the saved theme arrives with the saved variables
ns.On("DB_READY", function() ns.ApplyTheme() end)

function ns.Colorize(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end
function ns.Muted(s) return "|cff" .. ns.HEX.muted .. tostring(s) .. "|r" end
-- commands and placeholders inside help texts
function ns.Code(s) return "|cff" .. ns.HEX.accent .. tostring(s) .. "|r" end

-- resource colors by power token (the game's own table wins when present)
local POWER = {
    MANA = { 0.25, 0.50, 1.00 }, RAGE = { 0.90, 0.20, 0.22 }, FOCUS = { 1.00, 0.55, 0.25 },
    ENERGY = { 1.00, 0.80, 0.22 }, RUNIC_POWER = { 0.00, 0.82, 1.00 },
}
function ns.PowerColor(token)
    local c = PowerBarColor and token and PowerBarColor[token]
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return POWER[token or ""] or POWER.MANA
end

-- vertical gradient (bottom color -> top color) on a white texture
-- (file: an optional shape texture to tint instead of plain white)
function ns.Gradient(tex, r1, g1, b1, a1, r2, g2, b2, a2, file)
    tex:SetTexture(file or ns.WHITE)
    if CreateColor and pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then
        return
    end
    if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, "VERTICAL", r1, g1, b1, a1, r2, g2, b2, a2) then
        return
    end
    tex:SetVertexColor((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end

-- background fill plus a 1px outline just outside the frame (four edge strips,
-- so translucent fills stay translucent). fill/edge are color tables; T tokens
-- follow the theme.
function ns.Skin(frame, fill, edge)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    local e = {}
    for i = 1, 4 do e[i] = frame:CreateTexture(nil, "BACKGROUND", nil, -6) end
    e[1]:SetPoint("TOPLEFT", -1, 1)     e[1]:SetPoint("TOPRIGHT", 1, 1)     e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", -1, -1) e[2]:SetPoint("BOTTOMRIGHT", 1, -1) e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", -1, 0)     e[3]:SetPoint("BOTTOMLEFT", -1, 0)  e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", 1, 0)     e[4]:SetPoint("BOTTOMRIGHT", 1, 0)  e[4]:SetWidth(1)
    frame.skinBg, frame.edges = bg, e
    frame.skinFill, frame.edgeColor, frame.baseEdge = fill or T.panel, edge or T.line, edge or T.line
    ns.Paint(function()
        local f = frame.skinFill
        bg:SetColorTexture(f[1], f[2], f[3], f[4] or 1)
        local c = frame.edgeColor
        for _, t in ipairs(e) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    end)
    return frame
end

-- c: a color table, or nil for the frame's own outline color
function ns.SetEdgeColor(frame, c)
    c = c or frame.baseEdge or T.line
    frame.edgeColor = c
    for _, e in ipairs(frame.edges) do e:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

function ns.SetFill(frame, c)
    frame.skinFill = c
    frame.skinBg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- ---------------------------------------------------------------------------
-- Fonts. Arial Narrow has no Korean, Chinese or Cyrillic letters, but player
-- names and notes can contain them. A font family (as the game's own fonts
-- use) takes Arial Narrow for Latin letters and the game's fonts for the
-- other scripts. Without CreateFontFamily the plain font is used.
-- ---------------------------------------------------------------------------
local OTHER_SCRIPTS = {
    { "korean", "Fonts\\2002.TTF" },
    { "simplifiedchinese", "Fonts\\ARKai_T.ttf" },
    { "traditionalchinese", "Fonts\\blei00d.TTF" },
    { "russian", "Fonts\\FRIZQT___CYR.TTF" },
}
local families = {}

local function Family(size, flags)
    if type(CreateFontFamily) ~= "function" then return nil end
    local key = size .. "|" .. flags
    if families[key] == nil then
        local members = { { alphabet = "roman", file = ns.FONT, height = size, flags = flags } }
        for _, s in ipairs(OTHER_SCRIPTS) do
            members[#members + 1] = { alphabet = s[1], file = s[2], height = size, flags = flags }
        end
        local name = ("EverFrameFont%d%s"):format(size, (flags:gsub("%W", "")))
        local ok, fam = pcall(CreateFontFamily, name, members)
        families[key] = (ok and fam) or false
    end
    return families[key] or nil
end

-- app text gets a shadow only in dark mode: on light surfaces a black shadow
-- smears dark letters. Regions marked uerThemed keep this through re-fonting.
function ns.ThemeShadow(region)
    local a = T.shadowAlpha or 1
    region:SetShadowColor(0, 0, 0, a)
    if a > 0 then region:SetShadowOffset(1, -1) else region:SetShadowOffset(0, 0) end
end

-- the addon font on a font string or edit box (clients of the other scripts
-- keep their own default font)
function ns.ApplyFont(region, size, flags)
    if ns.FONT then
        size, flags = size or 12, flags or ""
        local fam = Family(size, flags)
        if not (fam and pcall(region.SetFontObject, region, fam)) then region:SetFont(ns.FONT, size, flags) end
    end
    -- a font object brings its own shadow: put the theme's back
    if region.uerThemed then ns.ThemeShadow(region) end
end

local function NewText(parent, size, flags, layer, themed)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
    fs.uerThemed = themed
    ns.ApplyFont(fs, size or 12, flags or "")
    if not themed then fs:SetShadowOffset(1, -1) end
    return fs
end

-- app text: follows the theme (text color, shadow only in dark mode)
function ns.Text(parent, size, flags, layer)
    local fs = NewText(parent, size, flags, layer, true)
    ns.Paint(function()
        if fs.uerThemed then ns.ThemeShadow(fs) end
        fs:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
    end)
    return fs
end

-- edit boxes: the same rule (they start from GameFontHighlight's shadow)
function ns.ThemeEdit(e)
    e.uerThemed = true
    ns.Paint(function() ns.ThemeShadow(e) end)
end

-- combat frame text: always light with a dark shadow
function ns.HudText(parent, size, flags, layer)
    local fs = NewText(parent, size, flags, layer)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(T.hudText[1], T.hudText[2], T.hudText[3], 1)
    return fs
end
