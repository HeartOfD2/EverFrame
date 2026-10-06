-- ---------------------------------------------------------------------------
-- Macro Manager: browse, edit, create and delete your WoW macros in the
-- addon's style. General and character macros, sorted into groups of your
-- own (general: account-wide, character: per character), an icon picker that
-- searches spell and item names (in the client language), drag-to-action-bar,
-- and export / import as one line of text ("EFM1:" + Base64).
-- Templates have their own page (Templates.lua). The game blocks macro writes
-- in combat, so every write is guarded.
--   ns.Macros.RegisterTemplates(group)  default templates of a module: { key,
--       title, IsActive(), list = { { name, desc, body } }, Fill(body) }
--   ns.Macros.RegisterAction(action)    header button: { label, width,
--       IsActive(), OnClick(button, mouseButton), Tooltip(button) }
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI = ns.UI
local Text, Skin, SetEdgeColor = ns.Text, ns.Skin, ns.SetEdgeColor

local Macros = { templates = {}, actions = {} }
ns.Macros = Macros

local NAME_MAX, BODY_MAX = 16, 255
local MAX_GENERAL = MAX_ACCOUNT_MACROS or 120
local MAX_CHAR = MAX_CHARACTER_MACROS or 18
local QUESTION_ICON = 134400   -- the question mark: WoW picks the icon from #showtooltip
Macros.NAME_MAX, Macros.BODY_MAX, Macros.QUESTION_ICON = NAME_MAX, BODY_MAX, QUESTION_ICON
local App = ns.App
local PAGE_W, PAGE_H = App.CONTENT_W, App.CONTENT_H
local LIST_W, ROW_H, ROWS = 220, 26, 14
local ED_X = LIST_W + 16
local ED_W = PAGE_W - ED_X

-- old icon APIs return bare names; textures need the full path
local function IconPath(v)
    if type(v) == "string" and not v:find("[/\\]") then return "Interface\\Icons\\" .. v end
    return v
end
Macros.IconPath = IconPath

-- character macros come after the general slots; the count differs between
-- client generations, so check it against a real macro when there is one
local function CharBase()
    local _, numChar = GetNumMacros()
    if (numChar or 0) > 0 and not GetMacroInfo(MAX_GENERAL + 1) then
        for _, base in ipairs({ 120, 36, 72, 54 }) do
            if GetMacroInfo(base + 1) then return base end
        end
    end
    return MAX_GENERAL
end
Macros.CharBase = CharBase

-- the client stores macro text with a trailing newline (and keeps stray
-- trailing spaces): compare what matters, not the bytes
function Macros.SameText(a, b)
    local function norm(s) return ((s or ""):gsub("\r\n", "\n"):gsub("[ \t]+\n", "\n"):gsub("%s+$", "")) end
    return norm(a) == norm(b)
end

-- macro names hold 16 letters at most
function Macros.ShortName(s)
    if not s then return nil end
    return ns.Utf8Sub(s, NAME_MAX)
end

-- every macro with this name, general and character: { index, ... }
function Macros.IndicesByName(name)
    local out = {}
    local numGeneral, numChar = GetNumMacros()
    local base = CharBase()
    local function scan(first, count)
        for i = first, first + (count or 0) - 1 do
            if GetMacroInfo(i) == name then out[#out + 1] = i end
        end
    end
    scan(1, numGeneral)
    scan(base + 1, numChar)
    return out
end

function Macros.RegisterTemplates(group) table.insert(Macros.templates, group) end
function Macros.RegisterAction(action) table.insert(Macros.actions, action) end

local data = {}   -- macros of the current tab: { index, name, icon, body }
local view = {}   -- what the list shows: group headers and macros
local state = { tab = "general", sel = nil, isNew = false, dirty = false, icon = QUESTION_ICON,
                iconChanged = false, scroll = 0, selGroup = nil, groupValue = nil }

-- groups of the current tab: { names, collapsed, of = { [macro name] = group } }
local Groups = ns.Transfer.Groups
local function MG()
    local owner = (state.tab == "general") and ns.Acct() or ns.Char()
    owner.macroGroups = owner.macroGroups or {}
    local g = owner.macroGroups
    g.names, g.collapsed, g.of = g.names or {}, g.collapsed or {}, g.of or {}
    return g
end
local function GroupOf(m) return MG().of[m.name] end
local function GroupMembers(name)
    local out = {}
    for _, m in ipairs(data) do if Groups.IsIn(GroupOf(m), name) then out[#out + 1] = m end end
    return out
end
local function BuildView()
    local g = MG()
    view = ns.Transfer.Flatten(data, g.names, GroupOf, g.collapsed)
end

local function LoadMacros()
    wipe(data)
    local numGeneral, numChar = GetNumMacros()
    local first, count
    if state.tab == "general" then
        first, count = 1, numGeneral or 0
    else
        first, count = CharBase() + 1, numChar or 0
    end
    for i = first, first + count - 1 do
        local name, icon, body = GetMacroInfo(i)
        if name then data[#data + 1] = { index = i, name = name, icon = icon, body = body or "" } end
    end
end

-- ---------------------------------------------------------------------------
-- Page (built at load, moved into the app window the first time it opens)
-- ---------------------------------------------------------------------------
local mm = CreateFrame("Frame", "EverFrameMacroManager", UIParent)
mm:SetSize(PAGE_W, PAGE_H)
mm:Hide()
Macros.page = mm
local function Status(msg, isAlert) App.Status(msg, isAlert) end
Macros.Status = Status

local function MakeEdit(parent, multi)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    ns.ThemeEdit(e)
    ns.ApplyFont(e, 13, "")
    ns.Color(e, T.text)
    if multi then e:SetMultiLine(true) end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

local SetTab
local tabs = UI.Tabs(mm, { { "general", L["General"] }, { "character", L["Character"] } }, 0, 0, 104,
    function(key) SetTab(key) end)

local function UpdateTabs()
    local numGeneral, numChar = GetNumMacros()
    tabs.buttons.general.text:SetText(("%s  %s"):format(L["General"],
        ns.Muted(("%d/%d"):format(numGeneral or 0, CharBase()))))
    tabs.buttons.character.text:SetText(("%s  %s"):format(L["Character"],
        ns.Muted(("%d/%d"):format(numChar or 0, MAX_CHAR))))
    tabs:Select(state.tab)
end

-- ---------------------------------------------------------------------------
-- Macro list (ROWS row buttons, the mouse wheel scrolls the data)
-- ---------------------------------------------------------------------------
local list = CreateFrame("Frame", nil, mm)
list:SetPoint("TOPLEFT", 0, -32)
list:SetSize(LIST_W, ROW_H * ROWS)
Skin(list, T.panel)
list:EnableMouseWheel(true)
list.empty = Text(list, 12)
list.empty:SetPoint("CENTER")
ns.Color(list.empty, T.muted)
list.empty:SetText(L["No macros here yet"])
list.thumb = list:CreateTexture(nil, "OVERLAY")
list.thumb:SetWidth(2)
ns.Color(list.thumb, T.accent, 0.6)

local rows = {}
local Select, RenderList, RevealSelection

for i = 1, ROWS do
    local r = CreateFrame("Button", nil, list)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetSize(LIST_W, ROW_H)
    r:RegisterForDrag("LeftButton")
    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.sel:SetAllPoints()
    ns.Color(r.sel, T.accentSoft)
    r.mark = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(2)
    ns.Color(r.mark, T.accent)
    r.iconEdge = r:CreateTexture(nil, "ARTWORK")
    r.iconEdge:SetSize(22, 22)
    r.iconEdge:SetPoint("CENTER", r, "LEFT", 18, 0)
    ns.Color(r.iconEdge, T.line)
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("CENTER", r.iconEdge)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = Text(r, 12)
    r.text:SetPoint("LEFT", 36, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.arrow = UI.Arrow(r, 11, "down")
    r.arrow:SetPoint("LEFT", 12, 0)
    r.arrow:Hide()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    ns.Color(r.hl, T.hover)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        local h = self.header
        if h then
            if button == "RightButton" then
                Groups.Menu(MG(), h, self, {
                    members = GroupMembers,
                    setGroup = function(m, name) MG().of[m.name] = Groups.Stored(name) end,
                    changed = function()
                        if state.selGroup and not Groups.Has(MG(), state.selGroup) then state.selGroup = nil end
                        if state.sel then Select(state.sel) else RenderList() end
                    end,
                })
                return
            end
            -- a click folds the group and makes it the one new macros go into
            local c = MG().collapsed
            c[h.group] = not c[h.group] or nil
            state.selGroup = h.group
            RenderList()
            return
        end
        if self.macro and button ~= "RightButton" then
            state.selGroup = nil   -- a macro picked: export starts from it, not the group
            Select(self.macro.index)
        end
    end)
    r:SetScript("OnDragStart", function(self) if self.macro then PickupMacro(self.macro.index) end end)
    r:SetScript("OnEnter", function(self)
        local m = self.macro
        if not m then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(m.name, 1, 1, 1)
        GameTooltip:AddLine(m.body, 0.8, 0.8, 0.8, true)
        if ns.Templates and ns.Templates.Find(m.name) then
            GameTooltip:AddLine(L["From a template of the same name: Refresh on the templates page writes it anew."], T.accent[1], T.accent[2], T.accent[3], true)
        end
        GameTooltip:AddLine(L["Drag onto an action bar"], T.muted[1], T.muted[2], T.muted[3])
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
end

RenderList = function()
    BuildView()
    local maxScroll = math.max(0, #view - ROWS)
    state.scroll = math.max(0, math.min(state.scroll, maxScroll))
    local collapsed = MG().collapsed
    for i, r in ipairs(rows) do
        local m = view[state.scroll + i]
        r.macro = (m and not m.isHeader) and m or nil
        r.header = (m and m.isHeader) and m or nil
        if m and m.isHeader then
            r.icon:Hide()
            r.iconEdge:Hide()
            r.arrow:Show()
            r.arrow:Point(collapsed[m.group] and "right" or "down")
            r.text:SetText(ns.Colorize(HEX.accent, m.group) .. "  " .. ns.Muted(tostring(#m.members)))
            local on = state.selGroup == m.group
            r.sel:SetShown(on)
            r.mark:SetShown(on)
            r:Show()
        elseif m then
            r.icon:Show()
            r.iconEdge:Show()
            r.arrow:Hide()
            r.icon:SetTexture(IconPath(m.icon) or QUESTION_ICON)
            r.text:SetText(m.name)
            -- made from a template: a 2 px accent frame (Refresh keeps it up to date)
            local fromTemplate = ns.Templates and ns.Templates.Find(m.name) and true or false
            ns.SetColor(r.iconEdge, fromTemplate and T.mark or T.line)
            r.iconEdge:SetSize(fromTemplate and 24 or 22, fromTemplate and 24 or 22)
            r.fromTemplate = fromTemplate
            local on = m.index == state.sel
            r.sel:SetShown(on)
            r.mark:SetShown(on)
            r:Show()
        else
            r:Hide()
        end
    end
    list.empty:SetShown(#view == 0 and not state.isNew)
    if maxScroll > 0 then
        local trackH = ROW_H * ROWS
        local thumbH = math.max(16, trackH * ROWS / #view)
        list.thumb:ClearAllPoints()
        list.thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -(trackH - thumbH) * state.scroll / maxScroll)
        list.thumb:SetHeight(thumbH)
        list.thumb:Show()
    else
        list.thumb:Hide()
    end
end

list:SetScript("OnMouseWheel", function(_, delta)
    state.scroll = state.scroll - delta
    RenderList()
end)

-- ---------------------------------------------------------------------------
-- Editor: icon, name, text with a letter counter
-- ---------------------------------------------------------------------------
local iconBtn = CreateFrame("Button", nil, mm)
iconBtn:SetSize(36, 36)
iconBtn:SetPoint("TOPLEFT", ED_X, -32)
Skin(iconBtn, T.control, T.input)
iconBtn.icon = iconBtn:CreateTexture(nil, "ARTWORK")
iconBtn.icon:SetAllPoints()
iconBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
iconBtn.icon:SetTexture(QUESTION_ICON)
iconBtn.hl = iconBtn:CreateTexture(nil, "HIGHLIGHT")
iconBtn.hl:SetAllPoints()
iconBtn.hl:SetColorTexture(1, 1, 1, 0.15)
UI.Tooltip(iconBtn, { L["Choose icon"], L["The question mark follows #showtooltip."] })

UI.Label(mm, L["NAME"], ED_X + 46, -32)
local nameBox = MakeEdit(mm)
nameBox:SetPoint("TOPLEFT", ED_X + 46, -46)
nameBox:SetSize(ED_W - 46 - 158, 22)
nameBox:SetMaxLetters(NAME_MAX)
nameBox:SetTextInsets(6, 6, 0, 0)
Skin(nameBox, T.control, T.input)

UI.Label(mm, L["GROUP"], PAGE_W - 150, -32)
local groupDD = UI.Dropdown(mm, function()
    local items = { { false, Groups.DEFAULT } }
    for _, n in ipairs(MG().names) do items[#items + 1] = { n, n } end
    return items
end, function() return state.groupValue or false end, function(v)
    state.groupValue = v or nil
    -- a saved macro moves at once; a new one on Save
    if state.sel and not state.isNew then
        local name = GetMacroInfo(state.sel)
        if name then MG().of[name] = state.groupValue end
        RevealSelection()   -- it moved to its group: keep it in view
        RenderList()
    end
end, 150)
groupDD:SetPoint("TOPLEFT", PAGE_W - 150, -46)

UI.Label(mm, L["MACRO TEXT"], ED_X, -80)
local counter = Text(mm, 11)
counter:SetPoint("TOPRIGHT", 0, -80)

local bodyBox = UI.TextArea(mm, BODY_MAX)
bodyBox:SetPoint("TOPLEFT", ED_X, -94)
bodyBox:SetPoint("BOTTOMRIGHT", 0, 32)
local body = bodyBox.edit
local MarkDirty, UpdateCounter
local spellBtn = ns.SpellSearch.Button(mm, body, function() MarkDirty() UpdateCounter() end, 110, 20)

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
local Save, Delete, PickUp, NewMacro, ToggleIconPicker
local saveBtn = UI.Button(mm, 64, L["Save"], function() Save() end)
saveBtn:SetPoint("BOTTOMLEFT", ED_X, 0)
local delBtn = UI.Button(mm, 64, L["Delete"], function() Delete() end)
delBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
local pickBtn = UI.Button(mm, 72, L["Pick up"], function() PickUp() end)
pickBtn:SetPoint("LEFT", delBtn, "RIGHT", 6, 0)
spellBtn:SetPoint("LEFT", pickBtn, "RIGHT", 6, 0)
local newBtn = UI.Button(mm, (LIST_W - 6) / 2, "+  " .. L["Macro"], function() NewMacro() end)
newBtn:SetPoint("BOTTOMLEFT", 0, 0)
local groupBtn = UI.Button(mm, (LIST_W - 6) / 2, "+  " .. L["Group"], function()
    Groups.AskNew(MG(), function(name)
        state.selGroup = name
        RenderList()
        Status(L["Group \"%s\" created. Right-click a group to rename or delete it."]:format(name))
    end)
end)
groupBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
UI.Tooltip(groupBtn, { L["New group"], L["Right-click a group to rename or delete it."] })

local function UpdateButtons()
    local canWrite = not ns.InCombat()
    saveBtn:SetAlpha((canWrite and (state.dirty or state.isNew)) and 1 or 0.4)
    saveBtn:SetAccent(state.dirty)
    ns.SetColor(saveBtn.text, state.dirty and T.accent or T.text)
    delBtn:SetAlpha((canWrite and state.sel) and 1 or 0.4)
    pickBtn:SetAlpha(state.sel and 1 or 0.4)
    newBtn:SetAlpha(canWrite and 1 or 0.4)
end

UpdateCounter = function()
    local n = body:GetNumLetters()
    counter:SetText(ns.Colorize(n >= BODY_MAX and HEX.alert or HEX.muted, ("%d/%d"):format(n, BODY_MAX)))
end

MarkDirty = function()
    if not state.sel then state.isNew = true end
    state.dirty = true
    UpdateButtons()
end

local function SetEditor(name, icon, text)
    nameBox:SetText(name or "")
    bodyBox:SetValue(text or "")
    state.icon = icon or QUESTION_ICON
    state.iconChanged = false
    state.dirty = false
    iconBtn.icon:SetTexture(IconPath(state.icon))
    UpdateCounter()
    UpdateButtons()
end

RevealSelection = function()
    -- a macro inside a folded group: open the group first
    for _, m in ipairs(data) do
        if m.index == state.sel then
            local g = GroupOf(m)
            if g then MG().collapsed[g] = nil end
        end
    end
    BuildView()
    for pos, m in ipairs(view) do
        if not m.isHeader and m.index == state.sel then
            if pos <= state.scroll then
                state.scroll = pos - 1
            elseif pos > state.scroll + ROWS then
                state.scroll = pos - ROWS
            end
            return
        end
    end
end

Select = function(index)
    local name, icon, text = GetMacroInfo(index)
    if not name then return end
    text = (text or ""):gsub("\n$", "")   -- the client adds one; it comes back on save anyway
    if state.dirty and index ~= state.sel then Status(L["Unsaved changes discarded."]) end
    state.sel, state.isNew = index, false
    state.groupValue = MG().of[name]
    groupDD:Refresh()
    SetEditor(name, icon, text)
    RevealSelection()
    RenderList()
end

local function ClearEditor()
    state.sel, state.isNew = nil, false
    state.groupValue = nil
    groupDD:Refresh()
    SetEditor("", QUESTION_ICON, "")
    RenderList()
end

local function SelectFirstOrClear()
    if data[1] then Select(data[1].index) else ClearEditor() end
end

SetTab = function(key)
    state.tab, state.scroll, state.selGroup = key, 0, nil
    LoadMacros()
    UpdateTabs()
    SelectFirstOrClear()
end

local IN_COMBAT = L["Macros can't be changed in combat."]

NewMacro = function()
    if ns.InCombat() then Status(IN_COMBAT, true) return end
    state.sel, state.isNew = nil, true
    state.groupValue = Groups.Stored(state.selGroup)
    groupDD:Refresh()
    SetEditor("", QUESTION_ICON, "#showtooltip\n")
    UpdateButtons()
    RenderList()
    nameBox:SetFocus()
    Status(L["New macro: enter a name and text, then Save."])
end

Save = function()
    if ns.InCombat() then Status(IN_COMBAT, true) return end
    if not (state.dirty or state.isNew) then return end
    local name = ns.Trim(nameBox:GetText())
    local text = body:GetText() or ""
    if name == "" then
        Status(L["Enter a name first."], true)
        nameBox:SetFocus()
        return
    end
    -- one name per list; a general and a character macro may share it
    for _, m in ipairs(data) do
        if m.name == name and m.index ~= state.sel then
            Status(L["A macro named \"%s\" exists already."]:format(name), true)
            return
        end
    end
    local oldName = state.sel and not state.isNew and GetMacroInfo(state.sel)
    if state.isNew or not state.sel then
        local numGeneral, numChar = GetNumMacros()
        local perChar = state.tab == "character"
        if (perChar and (numChar or 0) >= MAX_CHAR) or (not perChar and (numGeneral or 0) >= CharBase()) then
            Status(L["This macro list is full."], true)
            return
        end
        local ok, idx = pcall(CreateMacro, name, state.icon, text, perChar)
        if not (ok and idx) and state.icon == QUESTION_ICON then
            ok, idx = pcall(CreateMacro, name, "INV_MISC_QUESTIONMARK", text, perChar)
        end
        if not (ok and idx) then
            Status(L["Couldn't create the macro."], true)
            return
        end
        state.dirty = false
        MG().of[name] = Groups.Stored(state.groupValue)
        LoadMacros()
        Select(idx)
        Status(L["Created \"%s\". Drag it onto an action bar."]:format(name))
    else
        -- nil keeps the icon: a "?" macro stays dynamic unless you picked a new one
        local ok, idx = pcall(EditMacro, state.sel, name, state.iconChanged and state.icon or nil, text)
        if not ok then
            Status(L["Couldn't save the macro."], true)
            return
        end
        state.dirty = false
        if oldName and oldName ~= name then   -- renamed: the group goes along
            local of = MG().of
            of[name], of[oldName] = of[oldName], nil
        end
        LoadMacros()
        Select(idx or GetMacroIndexByName(name) or state.sel)   -- edits can re-sort the list
        Status(L["Saved \"%s\"."]:format(name))
    end
    UpdateTabs()
end

-- two-step delete: the first click arms the button for 3 seconds
local deleteArmedUntil = 0
Delete = function()
    if not state.sel then return end
    if ns.InCombat() then Status(IN_COMBAT, true) return end
    if GetTime() > deleteArmedUntil then
        deleteArmedUntil = GetTime() + 3
        delBtn.text:SetText(ns.Colorize(HEX.alert, L["Sure?"]))
        C_Timer.After(3.05, function()
            if GetTime() >= deleteArmedUntil then delBtn.text:SetText(L["Delete"]) end
        end)
        return
    end
    deleteArmedUntil = 0
    delBtn.text:SetText(L["Delete"])
    local name = GetMacroInfo(state.sel)
    local pos = 1
    for p, m in ipairs(data) do if m.index == state.sel then pos = p break end end
    DeleteMacro(state.sel)
    if name then MG().of[name] = nil end
    state.dirty = false
    LoadMacros()
    local nextMacro = data[math.min(pos, #data)]
    if nextMacro then Select(nextMacro.index) else ClearEditor() end
    UpdateTabs()
    Status(L["Deleted \"%s\"."]:format(name or "?"))
end

PickUp = function()
    if not state.sel then return end
    PickupMacro(state.sel)
    if state.dirty then
        Status(L["Picked up the saved version. Save first to include your edits."], true)
    else
        Status(L["Macro on the cursor: click an action button to place it."])
    end
end

nameBox:SetScript("OnTextChanged", function(_, userInput) if userInput then MarkDirty() end end)
nameBox:SetScript("OnTabPressed", function() body:SetFocus() end)
nameBox:SetScript("OnEnterPressed", function() body:SetFocus() end)
nameBox:SetScript("OnEditFocusGained", function(self) SetEdgeColor(self, T.accent) end)
nameBox:SetScript("OnEditFocusLost", function(self) SetEdgeColor(self) end)
body:SetScript("OnTextChanged", function(_, userInput)
    UpdateCounter()
    if userInput then MarkDirty() end
end)

-- ---------------------------------------------------------------------------
-- Icon picker (docked to the right). Icons have no searchable names, so the
-- search looks at the names of the spells and items that use them -- straight
-- from the client, so it works in every language. The name index is built in
-- the background the first time you type.
-- ---------------------------------------------------------------------------
local ICON, IGAP = 30, 4
local COLS = math.floor((PAGE_W - 12 + IGAP) / (ICON + IGAP))
local GRID_TOP = -64
local IROWS = math.floor((PAGE_H + GRID_TOP - 24 + IGAP) / (ICON + IGAP))
local picker = CreateFrame("Frame", "EverFrameMacroIconPicker", mm)
picker:SetAllPoints(mm)
picker:SetFrameLevel(mm:GetFrameLevel() + 20)
picker:EnableMouse(true)
picker:EnableMouseWheel(true)
picker:Hide()
ns.Skin(picker, T.background)
picker.title = Text(picker, 13)
picker.title:SetPoint("TOPLEFT", 0, -4)
picker.title:SetText(L["Choose icon"])
ns.Color(picker.title, T.accent)
picker.done = UI.Button(picker, 90, L["Done"], function() picker:Hide() end)
picker.done:SetPoint("TOPRIGHT", 0, 0)
picker.done:SetAccent(true)
picker.thumb = picker:CreateTexture(nil, "OVERLAY")
picker.thumb:SetWidth(2)
ns.Color(picker.thumb, T.accent, 0.6)
picker.info = UI.Hint(picker, "")
picker.info:SetPoint("BOTTOMLEFT", 0, 0)
picker.info:SetPoint("BOTTOMRIGHT", 0, 0)

local icons, iconScroll = nil, 0
local view, query = nil, ""
local cells = {}
-- spells whose icons lead the list; modules add theirs (rank-1 IDs)
Macros.featuredSpells = {}
Macros.featuredItems = {}

local nameIndex, indexDone, indexNext = nil, false, 1
local INDEX_MAX_SPELL, INDEX_STEP = 40000, 2500
local function AddName(icon, name)
    if not icon or type(name) ~= "string" or name == "" then return end
    local e = nameIndex[icon]
    if not e then
        e = { names = {}, key = "" }
        nameIndex[icon] = e
    end
    for _, n in ipairs(e.names) do if n == name then return end end
    if #e.names < 6 then e.names[#e.names + 1] = name end
    e.key = e.key .. "\n" .. ns.Fold(name)
end

local function IndexQuickSources()
    -- the spellbook (covers this client's own spell IDs, however high)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local ok, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        for line = 1, (ok and lines or 0) do
            local okL, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
            if okL and info and info.itemIndexOffset and info.numSpellBookItems then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local okI, item = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                    if okI and item then AddName(item.iconID, item.name) end
                end
            end
        end
    end
    for _, id in ipairs(Macros.featuredSpells) do AddName(ns.SpellIcon(id), ns.SpellName(id)) end
    ns.ForEachBagItem(function(id, name) AddName(ns.ItemIcon(id), name) end)
    for slot = 1, 19 do
        local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
        local name = ns.EquippedName(slot)
        if tex and name then AddName(tex, name) end
    end
end

local RunSearch
local indexer = CreateFrame("Frame", nil, picker)
indexer:Hide()
indexer:SetScript("OnUpdate", function(self)
    if not (C_Spell and C_Spell.GetSpellInfo) then indexDone = true self:Hide() RunSearch() return end
    local last = math.min(INDEX_MAX_SPELL, indexNext + INDEX_STEP - 1)
    pcall(function()
        for id = indexNext, last do
            local info = C_Spell.GetSpellInfo(id)
            if info and info.iconID then AddName(info.iconID, info.name) end
        end
    end)
    indexNext = last + 1
    if indexNext > INDEX_MAX_SPELL then
        indexDone = true
        self:Hide()
    end
    RunSearch()
end)

local function EnsureIndex()
    if nameIndex then return end
    nameIndex = {}
    IndexQuickSources()
    indexer:Show()
end

local function BuildIcons()
    icons = {}
    local seen = {}
    local function add(v)
        if v and not seen[v] then
            seen[v] = true
            icons[#icons + 1] = v
        end
    end
    add(QUESTION_ICON)
    for _, id in ipairs(Macros.featuredSpells) do add(ns.SpellIcon(id)) end
    for _, id in ipairs(Macros.featuredItems) do add(ns.ItemIcon(id)) end
    -- the game's own macro icon lists (fill a table on modern clients)
    for _, fname in ipairs({ "GetLooseMacroIcons", "GetMacroIcons", "GetLooseMacroItemIcons", "GetMacroItemIcons" }) do
        local fn = _G[fname]
        if fn then
            local t = {}
            local ok, ret = pcall(fn, t)
            if ok and type(ret) == "table" then t = ret end
            for _, v in ipairs(t) do add(v) end
        end
    end
    if #icons < 100 and GetNumMacroIcons and GetMacroIconInfo then
        for i = 1, GetNumMacroIcons() do add(GetMacroIconInfo(i)) end
    end
    view = icons
end

local function RenderIcons()
    local maxRow = math.max(0, math.ceil(#view / COLS) - IROWS)
    iconScroll = math.max(0, math.min(iconScroll, maxRow))
    for i, c in ipairs(cells) do
        local v = view[iconScroll * COLS + i]
        c.value = v
        if v then
            c.tex:SetTexture(IconPath(v))
            c.edge:SetColorTexture(unpack(v == state.icon and T.accent or T.line))
            c:Show()
        else
            c:Hide()
        end
    end
    if maxRow > 0 then
        local trackH = IROWS * (ICON + IGAP) - IGAP
        local thumbH = math.max(16, trackH * IROWS / (maxRow + IROWS))
        picker.thumb:ClearAllPoints()
        picker.thumb:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -1, GRID_TOP - (trackH - thumbH) * iconScroll / maxRow)
        picker.thumb:SetHeight(thumbH)
        picker.thumb:Show()
    else
        picker.thumb:Hide()
    end
    if query == "" then
        picker.info:SetText(L["%d icons"]:format(#view))
    elseif not indexDone and not query:match("^%d+$") then
        picker.info:SetText(L["%d matches  ·  indexing names %d%%"]:format(#view,
            math.floor(math.min(1, indexNext / INDEX_MAX_SPELL) * 100)))
    else
        picker.info:SetText(#view > 0 and L["%d matches"]:format(#view) or L["No icon matches that name."])
    end
end

RunSearch = function()
    if not icons then BuildIcons() end
    if query == "" then
        view = icons
    elseif query:match("^%d+$") then
        view = {}
        for _, v in ipairs(icons) do
            if tostring(v):find(query, 1, true) then view[#view + 1] = v end
        end
    else
        EnsureIndex()
        local hits = {}
        for icon, e in pairs(nameIndex) do
            local pos = e.key:find(query, 1, true)
            if pos then
                -- names that start with the query rank first
                local prefix = e.key:sub(pos - 1, pos - 1) == "\n" and 0 or 1
                hits[#hits + 1] = { icon = icon, rank = prefix, name = e.names[1] or "" }
            end
        end
        table.sort(hits, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.name < b.name
        end)
        view = {}
        for i, h in ipairs(hits) do view[i] = h.icon end
    end
    RenderIcons()
end

local search = UI.LineEdit(picker, 13)
search:SetPoint("TOPLEFT", 0, -28)
search:SetPoint("TOPRIGHT", 0, -28)
search:SetHeight(22)
UI.Placeholder(search, L["Search spell or item name ..."])
search:SetScript("OnTextChanged", function(self)
    query = ns.Fold(ns.Trim(self:GetText()))
    iconScroll = 0
    RunSearch()
end)

for i = 1, COLS * IROWS do
    local c = CreateFrame("Button", nil, picker)
    c:SetSize(ICON, ICON)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    c:SetPoint("TOPLEFT", 1 + col * (ICON + IGAP), GRID_TOP - row * (ICON + IGAP))
    c.edge = c:CreateTexture(nil, "BACKGROUND")
    c.edge:SetPoint("TOPLEFT", -1, 1)
    c.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    ns.Color(c.edge, T.line)
    c.tex = c:CreateTexture(nil, "ARTWORK")
    c.tex:SetAllPoints()
    c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    c.hl:SetColorTexture(1, 1, 1, 0.2)
    c:SetScript("OnClick", function(self)
        if not self.value then return end
        state.icon, state.iconChanged = self.value, true
        iconBtn.icon:SetTexture(IconPath(self.value))
        MarkDirty()
        RenderIcons()
        Status(L["Icon chosen. Save to keep it."])
    end)
    c:SetScript("OnEnter", function(self)
        local e = nameIndex and nameIndex[self.value]
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, n in ipairs(e.names) do GameTooltip:AddLine(n, 1, 1, 1) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cells[i] = c
end

picker:SetScript("OnMouseWheel", function(_, delta)
    iconScroll = iconScroll - delta * 2
    RenderIcons()
end)
picker:SetScript("OnShow", function()
    if not icons then BuildIcons() end
    RunSearch()
end)
picker:SetScript("OnHide", function() search:ClearFocus() end)

ToggleIconPicker = function()
    if picker:IsShown() then picker:Hide() else picker:Show() end
end
iconBtn:SetScript("OnClick", function() ToggleIconPicker() end)

-- ---------------------------------------------------------------------------
-- Creating a macro from outside (the templates page)
-- ---------------------------------------------------------------------------
-- returns the new macro's index, or nil + reason
function Macros.Create(name, body, perChar)
    if ns.InCombat() then return nil, IN_COMBAT end
    name = Macros.ShortName(ns.Trim(name))
    if name == "" then return nil, L["Enter a name first."] end
    local numGeneral, numChar = GetNumMacros()
    if (perChar and (numChar or 0) >= MAX_CHAR) or (not perChar and (numGeneral or 0) >= CharBase()) then
        return nil, L["This macro list is full."]
    end
    local ok, idx = pcall(CreateMacro, name, QUESTION_ICON, ns.Utf8Sub(body or "", BODY_MAX), perChar)
    if not (ok and idx) then return nil, L["Couldn't create the macro."] end
    return idx
end

-- ---------------------------------------------------------------------------
-- Export / import of the macros of the open tab (ns.Transfer)
-- ---------------------------------------------------------------------------
local exportItems = {}
local function TabLabel() return state.tab == "general" and L["General"] or L["Character"] end
local function Room()
    local numGeneral, numChar = GetNumMacros()
    if state.tab == "character" then return (numChar or 0) < MAX_CHAR end
    return (numGeneral or 0) < CharBase()
end
local transfer = ns.Transfer.Build(mm, {
    items = function() return exportItems end,
    label = function(m) return m.name end,
    icon = function(m) return IconPath(m.icon) or QUESTION_ICON end,
    tooltip = function(m) return { m.name, m.body } end,
    preview = function(m) return ns.Colorize(HEX.accent, m.name) .. "\n\n" .. (m.body or "") end,
    encode = ns.EncodeMacros,
    decode = ns.DecodeMacros,
    groupOf = function(m) return m.group end,
    groupNames = function() return MG().names end,
    find = function(m)
        for _, x in ipairs(data) do if x.name == m.name then return x end end
    end,
    canImport = function()
        if ns.InCombat() then return false, IN_COMBAT end
        return true
    end,
    add = function(m)
        if not Room() then return false end
        local perChar = state.tab == "character"
        local ok, idx = pcall(CreateMacro, m.name, m.icon or QUESTION_ICON, m.body or "", perChar)
        if not (ok and idx) then ok, idx = pcall(CreateMacro, m.name, QUESTION_ICON, m.body or "", perChar) end
        if not (ok and idx) then return false end
        Groups.Ensure(MG(), m.group)
        MG().of[m.name] = m.group
        return true
    end,
    replace = function(have, m)
        -- creating macros re-sorts the list: look the index up now
        local idx = GetMacroIndexByName(have.name)
        if not (idx and idx > 0) or not pcall(EditMacro, idx, nil, m.icon, m.body or "") then return false end
        if m.group then
            Groups.Ensure(MG(), m.group)
            MG().of[have.name] = m.group
        end
        return true
    end,
    done = function()
        LoadMacros()
        UpdateTabs()
        if state.sel and GetMacroInfo(state.sel) then Select(state.sel) else SelectFirstOrClear() end
    end,
    L = {
        exportTitle = L["Export macros"],
        importTitle = L["Import macros"],
        empty = L["No macros here yet"],
        invalid = L["That is no macro code (it starts with EFM1:)."],
        found = L["%d macros in the code. Untick what you don't want."],
        clashTitle = L["Macros exist already"],
        clashText = L["These macros exist already:\n%s\n\nOverwrite them with the imported ones?"],
    },
})

function Macros.ShowExport()
    wipe(exportItems)
    local pre = {}
    for _, m in ipairs(data) do
        local it = { name = m.name, icon = m.icon, body = (m.body or ""):gsub("\n$", ""), group = GroupOf(m) }
        exportItems[#exportItems + 1] = it
        if (state.selGroup and Groups.IsIn(it.group, state.selGroup)) or (not state.selGroup and m.index == state.sel) then
            pre[#pre + 1] = it
        end
    end
    transfer.export.title:SetText(L["Export macros"] .. "  " .. ns.Muted("· " .. TabLabel()))
    transfer.ShowExport(pre)
end

function Macros.ShowImport()
    transfer.import.title:SetText(L["Import macros"] .. "  " .. ns.Muted("· " .. L["into: %s"]:format(TabLabel())))
    transfer.ShowImport()
end

-- ---------------------------------------------------------------------------
-- Header actions from modules (e.g. the rogue's weapon macros)
-- ---------------------------------------------------------------------------
local actionButtons = {}
local function LayoutActions()
    local x = 0
    for i, a in ipairs(Macros.actions) do
        local b = actionButtons[i]
        if not b then
            b = UI.Button(mm, a.width or 120, a.label, nil, 22)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", function(self, button) a.OnClick(self, button) end)
            if a.Tooltip then UI.Tooltip(b, function(self) return a.Tooltip(self) end, "ANCHOR_BOTTOM") end
            b:SetAccent(a.accent)
            actionButtons[i] = b
        end
        local active = not a.IsActive or a.IsActive()
        b:SetShown(active)
        if active then
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", x, 0)
            x = x - (a.width or 120) - 6
        end
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Macros.Reload()
    if not mm:IsShown() then return end
    local selName = state.sel and GetMacroInfo(state.sel)
    LoadMacros()
    UpdateTabs()
    if selName then
        local idx = GetMacroIndexByName(selName)
        if idx and idx > 0 then
            if state.dirty then state.sel = idx else Select(idx) end
        end
    end
    RenderList()
end

mm:SetScript("OnShow", function()
    LoadMacros()
    UpdateTabs()
    LayoutActions()
    if state.sel and GetMacroInfo(state.sel) then
        RevealSelection()
        RenderList()
    elseif not state.isNew then
        SelectFirstOrClear()
    else
        RenderList()
    end
    UpdateButtons()
    Status(L["Drag a macro from the list onto an action bar."])
end)
mm:SetScript("OnHide", function()
    transfer.Hide()
    ns.SpellSearch.Hide()
    picker:Hide()
    UI.CloseMenu()
end)

ns.RegisterEvent("UPDATE_MACROS", function()
    if not mm:IsShown() then return end
    -- changed here or in Blizzard's macro UI: re-read, keep the selection if it survived
    LoadMacros()
    UpdateTabs()
    if state.sel and not GetMacroInfo(state.sel) then
        state.sel = nil
        if not state.isNew then SelectFirstOrClear() end
    end
    RenderList()
    UpdateButtons()
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if not mm:IsShown() then return end
    Status(L["In combat: macros are read-only until combat ends."], true)
    UpdateButtons()
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not mm:IsShown() then return end
    Status(nil)
    UpdateButtons()
end)
ns.On("MODULES_CHANGED", function() if mm:IsShown() then LayoutActions() UpdateButtons() end end)

-- export / import sit right in the header, before the module buttons
Macros.RegisterAction({ label = L["Import"], width = 96, OnClick = function() Macros.ShowImport() end })
Macros.RegisterAction({ label = L["Export"], width = 96, OnClick = function() Macros.ShowExport() end })

App:AddPage({
    key = "macros", section = "macros", label = L["Player macros"], order = 110,
    Build = function(_, frame)
        mm:SetParent(frame)
        mm:ClearAllPoints()
        mm:SetAllPoints(frame)
        mm:Show()
    end,
})

function ns.ToggleMacroManager() App:Toggle("macros") end
