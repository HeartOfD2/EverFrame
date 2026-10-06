-- ---------------------------------------------------------------------------
-- Templates: your own macro templates (account-wide), sorted into groups.
-- Create, edit and delete them, turn one into a macro, and share them as one
-- line of text (names are unique across all groups):
--   Export   pick templates or whole groups, copy the code ("EF2:" + Base64)
--   Import   paste a code, look at what it holds, import the ticked ones;
--            names that exist already ask before they are overwritten
-- Modules bring default templates (ns.Macros.RegisterTemplates); they are
-- added once and then belong to the player like any other.
-- Placeholders: {s:<spell ID>} becomes the spell name in the client language;
-- modules add their own (the rogue's {p:MH} / {p:OH} = poison of that hand).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, App, Macros, Placeholders = ns.UI, ns.App, ns.Macros, ns.Placeholders

local Templates = {}
ns.Templates = Templates

local PAGE_W = App.CONTENT_W
local LIST_W = ns.Transfer.LIST_W
local QUESTION = Macros.QUESTION_ICON

local Groups = ns.Transfer.Groups
local page, Status

local function Store()
    local acct = ns.Acct()
    acct.templates = acct.templates or { list = {}, seeded = {} }
    local s = acct.templates
    s.list = s.list or {}
    s.seeded = s.seeded or {}
    s.groups = s.groups or {}
    s.collapsed = s.collapsed or {}
    return s
end
function Templates.List() return Store().list end

-- the group store in the shape Transfer.Groups works with
local function G()
    local s = Store()
    return { names = s.groups, collapsed = s.collapsed }
end
function Templates.Groups() return Store().groups end

local function Members(name)
    local out = {}
    for _, t in ipairs(Store().list) do if Groups.IsIn(t.group, name) then out[#out + 1] = t end end
    return out
end

function Templates.Find(name)
    for i, t in ipairs(Store().list) do
        if t.name == name then return t, i end
    end
end

-- the default templates of active modules, once per module
function Templates.Seed()
    local s = Store()
    for _, group in ipairs(Macros.templates) do
        local key = group.key or group.title
        if not s.seeded[key] and (not group.IsActive or group.IsActive()) then
            s.seeded[key] = true
            Groups.Ensure(G(), group.groupName)
            for _, t in ipairs(group.list) do
                if not Templates.Find(Macros.ShortName(t.name)) then
                    table.insert(s.list, { name = Macros.ShortName(t.name), desc = t.desc, body = t.body,
                                           group = group.groupName })
                end
            end
        end
    end
end

-- macro text with the placeholders filled in (Placeholders.lua)
function Templates.Fill(body) return ns.Placeholders.Fill(body) end

-- ---------------------------------------------------------------------------
-- Refresh: every macro named exactly like a template (general or character)
-- is written anew with the current placeholder values. filter(t) limits it
-- to some templates. Returns the updated macro names (nil in combat: the
-- job waits for the end of combat).
-- ---------------------------------------------------------------------------
local function Plan(filter)
    local out = {}
    for _, t in ipairs(Store().list) do
        if not filter or filter(t) then
            local body = Templates.Fill(t.body)
            for _, idx in ipairs(Macros.IndicesByName(t.name)) do
                local _, _, cur = GetMacroInfo(idx)
                out[#out + 1] = { t = t, index = idx, body = body, same = Macros.SameText(cur, body) }
            end
        end
    end
    return out
end

function Templates.Outdated(filter)
    local names = {}
    for _, m in ipairs(Plan(filter)) do
        if not m.same and not ns.IndexOf(names, m.t.name) then names[#names + 1] = m.t.name end
    end
    return names
end

function Templates.UpdateMacros(filter, quiet)
    if ns.InCombat() then
        Placeholders.AfterCombat(filter and ("templates:" .. tostring(filter)) or "templates",
            function() Templates.UpdateMacros(filter, quiet) end)
        if not quiet then ns.Print(L["In combat: the macros are updated when combat ends."]) end
        return nil
    end
    local updated, failed, same, open = {}, {}, 0, {}
    for _, m in ipairs(Plan(filter)) do
        for _, ph in ipairs(Placeholders.Unfilled(m.body)) do
            if not ns.IndexOf(open, ph) then open[#open + 1] = ph end
        end
        if m.same then
            same = same + 1
        elseif pcall(EditMacro, m.index, nil, nil, m.body) then
            updated[#updated + 1] = m.t.name
        else
            failed[#failed + 1] = m.t.name
        end
    end
    Macros.Reload()
    if not quiet then
        ns.Print(L["Templates: %d macros updated, %d up to date."]:format(#updated, same))
        if #updated > 0 then print("   " .. L["updated: %s"]:format(table.concat(updated, ", "))) end
        if #open > 0 then print("   " .. L["without a value right now: %s"]:format(table.concat(open, ", "))) end
        if #failed > 0 then print("   " .. ns.Colorize(HEX.alert, L["failed: %s"]:format(table.concat(failed, ", ")))) end
        if Status and page and page:IsVisible() then
            Status(L["Templates: %d macros updated, %d up to date."]:format(#updated, same), #failed > 0)
        end
    end
    return updated
end

-- macros from templates follow the gear ({w:..} / {g:..})
local function UsesGear(t) return Placeholders.UsesGear(t.body) end
Placeholders.RegisterGearMacros({
    Outdated = function() return Templates.Outdated(UsesGear) end,
    Update = function() return Templates.UpdateMacros(UsesGear, true) end,
})

function Templates.Icon(t)
    if t.icon then return t.icon end
    local id = (t.body or ""):match("{s:(%d+)}")
    return id and ns.SpellIcon(tonumber(id)) or QUESTION
end

-- ---------------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------------
local list, editor
local transfer, BuildTransfer

local function TemplateTip(t)
    local lines = { t.name }
    if t.desc and t.desc ~= "" then lines[#lines + 1] = t.desc end
    lines[#lines + 1] = t.body
    return lines
end

local current          -- the template in the editor (nil = a new one)
local selGroup         -- a group header picked in the list (new templates go there)
local RenderMain

local function BuildPage(p)
    page = p
    Status = App.Status
    local X = LIST_W + 16
    local W = PAGE_W - X

    UI.Label(p, L["YOUR TEMPLATES"], 0, -4)
    local exportBtn, importBtn
    importBtn = UI.Button(p, 110, L["Import"], function() Templates.ShowImport() end, 22)
    importBtn:SetPoint("TOPRIGHT", 0, 0)
    exportBtn = UI.Button(p, 110, L["Export"], function() Templates.ShowExport() end, 22)
    exportBtn:SetPoint("RIGHT", importBtn, "LEFT", -6, 0)
    local refreshBtn = UI.Button(p, 110, L["Refresh"], function() Templates.UpdateMacros() end, 22)
    refreshBtn:SetPoint("RIGHT", exportBtn, "LEFT", -6, 0)
    refreshBtn:SetAccent(true)
    UI.Tooltip(refreshBtn, { L["Refresh"], L["Rewrites every macro named exactly like a template (general or character) with the current placeholder values. Other macros stay as they are."] })

    local groupCfg = {
        members = Members,
        setGroup = function(t, name) t.group = Groups.Stored(name) end,
        changed = function()
            if selGroup and not Groups.Has(G(), selGroup) then selGroup = nil end
            Templates.Edit(current)
        end,
    }
    list = ns.Transfer.MakeList(p, LIST_W, 13, {
        empty = L["No templates yet. \"+ New template\" or Import adds some."],
        label = function(t) return t.name end,
        icon = Templates.Icon,
        tooltip = TemplateTip,
        onSelect = function(t)
            if t.isHeader then
                selGroup = (selGroup ~= t.group) and t.group or nil
                RenderMain()
            else
                selGroup = nil
                Templates.Edit(t)
            end
        end,
        onToggle = function(h)
            local c = Store().collapsed
            c[h.group] = not c[h.group] or nil
            RenderMain()
        end,
        onMenu = function(h, anchor) Groups.Menu(G(), h, anchor, groupCfg) end,
    })
    list:SetPoint("TOPLEFT", 0, -32)
    local half = (LIST_W - 6) / 2
    local newBtn = UI.Button(p, half, "+  " .. L["Template"], function() Templates.Edit(nil) end, 22)
    newBtn:SetPoint("BOTTOMLEFT", 0, 0)
    local groupBtn = UI.Button(p, half, "+  " .. L["Group"], function()
        Groups.AskNew(G(), function(name)
            selGroup = name
            RenderMain()
            Status(L["Group \"%s\" created. Right-click a group to rename or delete it."]:format(name))
        end)
    end, 22)
    groupBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
    UI.Tooltip(groupBtn, { L["New group"], L["Right-click a group to rename or delete it."] })

    editor = {}
    local Count
    UI.Label(p, L["NAME"], X, -32)
    editor.name = UI.LineEdit(p, 13, Macros.NAME_MAX)
    editor.name:SetPoint("TOPLEFT", X, -46)
    editor.name:SetSize(W, 22)
    UI.Label(p, L["DESCRIPTION"], X, -76)
    editor.desc = UI.LineEdit(p, 12, 60)
    editor.desc:SetPoint("TOPLEFT", X, -90)
    editor.desc:SetSize(W - 166, 22)
    UI.Label(p, L["GROUP"], X + W - 160, -76)
    editor.group = UI.Dropdown(p, function()
        local items = { { false, Groups.DEFAULT } }
        for _, n in ipairs(Store().groups) do items[#items + 1] = { n, n } end
        return items
    end, function() return editor.groupValue or false end, function(v)
        editor.groupValue = v or nil
        -- an existing template moves at once; a new one on Save
        if current then
            current.group = editor.groupValue
            RenderMain()
        end
    end, 160)
    editor.group:SetPoint("TOPLEFT", X + W - 160, -90)
    UI.Label(p, L["MACRO TEXT"], X, -120)
    editor.counter = ns.Text(p, 11)
    editor.counter:SetPoint("TOPRIGHT", 0, -120)
    editor.body = UI.TextArea(p, Macros.BODY_MAX)
    editor.body:SetPoint("TOPLEFT", X, -134)
    editor.body:SetPoint("BOTTOMRIGHT", 0, 74)
    local hint = UI.Hint(p, L["{s:ID} spell ({s:ID:r} with rank) · {w:W1} {w:W2} weapons · {g:t1} {g:t2} trinkets · {c:name} your own · Rogue: {p:MH} {p:OH} poison"], W - 118)
    hint:SetPoint("TOPLEFT", editor.body, "BOTTOMLEFT", 0, -6)
    -- right under the text it fills
    local spellBtn = ns.SpellSearch.Button(p, editor.body.edit, function() Count() end, 110, 22)
    spellBtn:SetPoint("TOPRIGHT", editor.body, "BOTTOMRIGHT", 0, -6)
    Count = function()
        local n = editor.body.edit:GetNumLetters()
        editor.counter:SetText(ns.Colorize(n >= Macros.BODY_MAX and HEX.alert or HEX.muted, ("%d/%d"):format(n, Macros.BODY_MAX)))
    end
    editor.body.edit:SetScript("OnTextChanged", Count)

    editor.save = UI.Button(p, 80, L["Save"], function() Templates.SaveEditor() end, 22)
    editor.save:SetPoint("BOTTOMLEFT", X, 0)
    editor.save:SetAccent(true)
    editor.delete = UI.ConfirmButton(p, 80, L["Delete"], function()
        if not current then return end
        local _, i = Templates.Find(current.name)
        if i then table.remove(Store().list, i) end
        Status(L["Deleted \"%s\"."]:format(current.name))
        Templates.Edit(Store().list[math.min(i or 1, #Store().list)])
    end, 22)
    editor.delete:SetPoint("LEFT", editor.save, "RIGHT", 6, 0)
    editor.make = UI.Button(p, 170, L["Create as macro"] .. "  ›", function(self)
        UI.OpenMenu(self, {
            { label = L["Create as macro"], isTitle = true },
            { label = L["General"], fn = function() Templates.MakeMacro(false) end },
            { label = L["Character"], fn = function() Templates.MakeMacro(true) end },
        }, { width = 180 })
    end, 22)
    editor.make:SetPoint("BOTTOMRIGHT", 0, 0)

    BuildTransfer(p)
end

RenderMain = function()
    if not list then return end
    local s = Store()
    list:Render(ns.Transfer.Flatten(s.list, s.groups, function(t) return t.group end, s.collapsed),
        { selected = current, selectedGroup = selGroup, collapsed = s.collapsed })
end

function Templates.Edit(t)
    current = t
    if t then editor.groupValue = t.group else editor.groupValue = Groups.Stored(selGroup) end
    editor.group:Refresh()
    editor.name:SetText(t and t.name or "")
    editor.desc:SetText(t and t.desc or "")
    editor.body:SetValue(t and t.body or "#showtooltip\n")
    editor.delete:SetAlpha(t and 1 or 0.4)
    editor.make:SetAlpha(t and 1 or 0.4)
    if not t then editor.name:SetFocus() end
    RenderMain()
end

function Templates.SaveEditor()
    local name = Macros.ShortName(ns.Trim(editor.name:GetText()))
    if name == "" then Status(L["Enter a name first."], true) editor.name:SetFocus() return end
    local other = Templates.Find(name)
    if other and other ~= current then
        Status(L["A template named \"%s\" exists already."]:format(name), true)
        return
    end
    local t = current
    if not t then
        t = {}
        table.insert(Store().list, t)
    end
    t.name, t.desc, t.body = name, ns.Trim(editor.desc:GetText()), editor.body.edit:GetText()
    t.group = editor.groupValue
    current = t
    RenderMain()
    Status(L["Saved \"%s\"."]:format(name))
end

function Templates.MakeMacro(perChar)
    if not current then return end
    local idx, why = Macros.Create(current.name, Templates.Fill(current.body), perChar)
    if not idx then Status(why, true) return end
    Macros.Reload()
    Status(L["Macro \"%s\" created under %s. Drag it from the macro list onto an action bar."]:format(
        current.name, perChar and L["Character"] or L["General"]))
end

-- ---------------------------------------------------------------------------
-- Export / import (ns.Transfer)
-- ---------------------------------------------------------------------------
BuildTransfer = function(p)
    transfer = ns.Transfer.Build(p, {
        items = function() return Store().list end,
        label = function(t) return t.name end,
        icon = Templates.Icon,
        tooltip = TemplateTip,
        preview = function(t)
            return ns.Colorize(HEX.accent, t.name)
                .. ((t.desc and t.desc ~= "") and ("\n" .. ns.Muted(t.desc)) or "")
                .. "\n\n" .. t.body
        end,
        encode = ns.EncodeTemplates,
        decode = ns.DecodeTemplates,
        groupOf = function(t) return t.group end,
        groupNames = function() return Store().groups end,
        find = function(t) return Templates.Find(t.name) end,
        add = function(t)
            Groups.Ensure(G(), t.group)
            table.insert(Store().list, { name = t.name, desc = t.desc, body = t.body, icon = t.icon, group = t.group })
        end,
        replace = function(have, t)
            Groups.Ensure(G(), t.group)
            have.desc, have.body, have.icon = t.desc, t.body, t.icon
            have.group = t.group or have.group
        end,
        done = function() RenderMain() end,
        L = {
            exportTitle = L["Export templates"],
            importTitle = L["Import templates"],
            empty = L["No templates yet."],
            invalid = L["That is no template code (it starts with EF2:)."],
            found = L["%d templates in the code. Untick what you don't want."],
            clashTitle = L["Templates exist already"],
            clashText = L["These templates exist already:\n%s\n\nOverwrite them with the imported ones?"],
        },
    })
end

function Templates.ShowExport()
    -- a picked group starts ticked as a whole, else the template in the editor
    local pre = selGroup and Members(selGroup) or { current }
    transfer.ShowExport(pre)
end

-- opens the page with a new template, prefilled (e.g. from the weapon macros)
function Templates.New(prefill)
    App:Open("templates")
    if prefill.group then Groups.Ensure(G(), prefill.group) end
    selGroup = prefill.group
    Templates.Edit(nil)
    editor.name:SetText(prefill.name or "")
    editor.desc:SetText(prefill.desc or "")
    editor.body:SetValue(prefill.body or "#showtooltip\n")
    editor.name:SetFocus()
end
function Templates.ShowImport() transfer.ShowImport() end

-- ---------------------------------------------------------------------------
App:AddPage({
    key = "templates", section = "macros", label = L["Templates"], order = 115,
    Build = function(_, frame) BuildPage(frame) end,
    Refresh = function()
        Templates.Seed()
        local list = Store().list
        if not (current and ns.IndexOf(list, current)) then current = nil end
        Templates.Edit(current or list[1])
    end,
    OnHide = function()
        if transfer then transfer.Hide() end
        ns.SpellSearch.Hide()
    end,
})

ns.On("LOGIN", function() Templates.Seed() end)
ns.On("MODULES_CHANGED", function() if ns.ready then Templates.Seed() end end)

ns.RegisterReset({ key = "templates", order = 88, label = L["Templates"], accountWide = true,
    desc = L["Deletes your templates and adds the default ones again."],
    reset = function()
        ns.Acct().templates = nil
        current = nil
        Templates.Seed()
        if App:IsOpen("templates") then App:RefreshCurrent() end
    end })
