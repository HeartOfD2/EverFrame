-- ---------------------------------------------------------------------------
-- Spell search for macro text: a small window next to the app that lists the
-- learned spells (every rank) with icon, name, rank and ID. A click puts
-- {s:ID} into the text at the cursor, Shift-click {s:ID:r} (with the rank).
-- Names and ranks come from the client, so the macro follows the language.
--   ns.SpellSearch.Attach(button, editBox, onInsert)
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI = ns.UI

local SpellSearch = {}
ns.SpellSearch = SpellSearch

local ROWS, ROW_H, W, H = 12, 24, 330, 404
local spells       -- { { id, name, rank, icon, key }, ... } read when the window opens
local view = {}
local scroll = 0
local target, onInsert

local win = UI.Window("EverFrameSpellSearch", W, H, L["Find spell"], { strata = "FULLSCREEN" })
win:SetClampedToScreen(true)

local search = UI.LineEdit(win, 13)
search:SetPoint("TOPLEFT", 12, -36)
search:SetPoint("TOPRIGHT", -12, -36)
search:SetHeight(22)
UI.Placeholder(search, L["Name or ID ..."])

local list = CreateFrame("Frame", nil, win)
list:SetPoint("TOPLEFT", 12, -66)
list:SetPoint("TOPRIGHT", -12, -66)
list:SetHeight(ROWS * ROW_H)
list:EnableMouseWheel(true)
ns.Skin(list, T.panel)

local empty = UI.Hint(list, "", W - 40)
empty:SetPoint("TOPLEFT", 8, -8)

local hint = UI.Hint(win, L["Click: {s:ID}  ·  Shift-click: {s:ID:r} with the rank"], W - 24)
hint:SetPoint("BOTTOMLEFT", 12, 12)

local function RankNumber(rank)
    return tonumber(rank and rank:match("(%d+)") or "") or 0
end

local function Read()
    spells = {}
    local seen = {}
    if not ns.ForEachSpellbookSpell then return end
    ns.ForEachSpellbookSpell(function(id, name, passive)
        if ns.IsSecret(id) or seen[id] or passive then return end
        seen[id] = true
        name = name or ns.SpellName(id)
        if type(name) ~= "string" or ns.IsSecret(name) then return end
        local rank = ns.Placeholders.SpellRank(id)
        spells[#spells + 1] = { id = id, name = name, rank = rank, icon = ns.SpellIcon(id), key = ns.Fold(name) }
    end)
    table.sort(spells, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return RankNumber(a.rank) < RankNumber(b.rank)
    end)
end

local rows = {}
local function Render()
    scroll = math.max(0, math.min(scroll, #view - ROWS))
    for i = 1, ROWS do
        local r, s = rows[i], view[scroll + i]
        r.spell = s
        if s then
            r.icon:SetTexture(s.icon)
            r.name:SetText(s.name .. (s.rank and ("  " .. ns.Muted(s.rank)) or ""))
            r.id:SetText(ns.Muted(s.id))
            r:Show()
        else
            r:Hide()
        end
    end
    if #spells == 0 then
        empty:SetText(L["The spellbook can't be read on this client."])
    elseif #view == 0 then
        empty:SetText(L["Nothing found."])
    end
    empty:SetShown(#view == 0)
end

local function Filter()
    local q = ns.Fold(ns.Trim(search:GetText()))
    view = {}
    for _, s in ipairs(spells or {}) do
        if q == "" or s.key:find(q, 1, true) or tostring(s.id) == q then view[#view + 1] = s end
    end
    scroll = 0
    Render()
end
search:SetScript("OnTextChanged", Filter)
list:SetScript("OnMouseWheel", function(_, delta) scroll = scroll - delta * 2 Render() end)

local function Insert(s, withRank)
    if not (target and s) then return end
    local code = ("{s:%d%s}"):format(s.id, withRank and ":r" or "")
    target:Insert(code)
    target:SetFocus()
    if onInsert then onInsert(code) end
    ns.App.Status(L["%s inserted: %s"]:format(ns.Code(code), s.name .. (withRank and s.rank and ("(" .. s.rank .. ")") or "")))
end

for i = 1, ROWS do
    local r = CreateFrame("Button", nil, list)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    r:SetHeight(ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = ns.Text(r, 12)
    r.name:SetPoint("LEFT", 30, 0)
    r.name:SetPoint("RIGHT", -56, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.id = ns.Text(r, 11)
    r.id:SetPoint("RIGHT", -8, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    ns.Color(r.hl, T.hover)
    r:SetScript("OnClick", function(self) Insert(self.spell, IsShiftKeyDown()) end)
    UI.Tooltip(r, function(self)
        local s = self.spell
        if not s then return end
        return { s.name .. (s.rank and ("  " .. s.rank) or ""), ("ID %d"):format(s.id),
                 L["Click: {s:ID}  ·  Shift-click: {s:ID:r} with the rank"] }
    end)
    rows[i] = r
end

function SpellSearch.Open(edit, insertFn)
    target, onInsert = edit, insertFn
    Read()
    win:ClearAllPoints()
    local app = _G.EverFrameApp
    if app and app:IsShown() then
        win:SetPoint("TOPLEFT", app, "TOPRIGHT", 6, 0)
    else
        win:SetPoint("CENTER")
    end
    win:Show()
    win:Raise()
    Filter()
    search:SetFocus()
    search:HighlightText()
end

function SpellSearch.Hide() win:Hide() end
function SpellSearch.IsShown() return win:IsShown() end

-- a small button that opens the search for this edit box
function SpellSearch.Button(parent, edit, insertFn, width, height)
    local b = UI.Button(parent, width or 110, L["Find spell"], function()
        if win:IsShown() and target == edit then win:Hide() else SpellSearch.Open(edit, insertFn) end
    end, height or 20)
    UI.Tooltip(b, { L["Find spell"], L["Search your spellbook (every rank) and put the spell into the text as {s:ID}: the macro shows the name in your game language."] })
    return b
end
