-- ---------------------------------------------------------------------------
-- Export / import as one line of text, shared by the templates and the notes:
--   Export   tick entries, copy the code
--   Import   paste a code, look at what it holds, import the ticked ones;
--            entries that exist already ask before they are overwritten
-- ns.Transfer.Build(parent, cfg) puts both panels over a page. cfg:
--   items()               entries offered for export
--   label(item)           list text; color(item) -> dot color, or icon(item)
--   tooltip(item)         lines for the row tooltip (optional)
--   preview(item)         text shown for the selected import entry
--   encode(list) / decode(text) -> list or nil
--   find(item)            the existing entry an import would overwrite
--   add(item), replace(existing, item), done()   (add/replace may return
--                         false when the game refused it)
--   canImport()           optional: false + reason stops the import
--   groupOf(item)         optional: group name -> the lists show group headers,
--                         a ticked header ticks the whole group
--   L = { exportTitle, importTitle, empty, invalid, found, clashTitle, clashText }
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, App = ns.UI, ns.App

local Transfer = {}
Transfer.DEFAULT_GROUP = L["Default"]   -- the group of entries without one
ns.Transfer = Transfer

local ROW_H = 26
Transfer.LIST_W = 220

-- ---------------------------------------------------------------------------
-- Groups: a flat list with a header row before each group's entries.
-- Every entry sits in a group: without one it shows under "Default", which
-- comes first. Empty groups still get their header (Default only when used).
--   names = ordered group names, groupOf(item) -> name or nil, collapsed[name]
-- Header rows: { isHeader = true, group = name, members = { ... } }
-- ---------------------------------------------------------------------------
function Transfer.Flatten(items, names, groupOf, collapsed)
    local out, byGroup, order = {}, {}, {}
    local DEFAULT = Transfer.DEFAULT_GROUP
    byGroup[DEFAULT], order[1] = {}, DEFAULT
    for _, n in ipairs(names or {}) do
        if not byGroup[n] then byGroup[n] = {} order[#order + 1] = n end
    end
    for _, it in ipairs(items) do
        local g = groupOf(it) or DEFAULT
        if not byGroup[g] then   -- a group only the entries know (e.g. from an import)
            byGroup[g] = {}
            order[#order + 1] = g
        end
        table.insert(byGroup[g], it)
    end
    for _, n in ipairs(order) do
        local members = byGroup[n]
        if not (n == DEFAULT and #members == 0) then
            out[#out + 1] = { isHeader = true, group = n, members = members }
            if not (collapsed and collapsed[n]) then
                for _, it in ipairs(members) do out[#out + 1] = it end
            end
        end
    end
    return out
end

-- a header counts as ticked when all of its entries are
local function HeaderChecked(header, checked)
    if #header.members == 0 then return false end
    for _, it in ipairs(header.members) do
        if not checked[it] then return false end
    end
    return true
end
Transfer.HeaderChecked = HeaderChecked

-- ---------------------------------------------------------------------------
-- A list with optional checkboxes
--   opts.checks, opts.onCheck(item), opts.onSelect(item), opts.empty
--   opts.label(item), opts.icon(item), opts.color(item), opts.tooltip(item)
--   opts.onToggle(header)   the arrow of a group header was clicked
--   opts.onMenu(header, button)   right-click on a group header
--   list:Render(items, { checked = set, selected = item, selectedGroup = name,
--                        collapsed = set, badge = fn(item) })
-- ---------------------------------------------------------------------------
function Transfer.MakeList(parent, width, rows, opts)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, rows * ROW_H)
    ns.Skin(list, T.panel)
    list:EnableMouseWheel(true)
    list.empty = UI.Hint(list, opts.empty or "", width - 20)
    list.empty:SetPoint("TOPLEFT", 10, -10)
    list.scroll, list.rows, list.items = 0, {}, {}
    for i = 1, rows do
        local r = CreateFrame("Button", nil, list)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetSize(width, ROW_H)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        ns.Color(r.sel, T.accentSoft)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        ns.Color(r.mark, T.accent)
        local x = 8
        if opts.checks then
            r.check = UI.Check(r)
            r.check:SetPoint("LEFT", x, 0)
            r.check:SetScript("OnClick", function() if r.item then opts.onCheck(r.item) end end)
            x = x + 22
        end
        r.icon = r:CreateTexture(nil, "ARTWORK")
        if opts.color then
            r.icon:SetSize(8, 8)
            r.icon:SetPoint("LEFT", x + 2, 0)
            x = x + 16
        else
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", x, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            x = x + 26
        end
        r.textX = x
        r.text = ns.Text(r, 12)
        r.text:SetPoint("LEFT", x, 0)
        r.text:SetPoint("RIGHT", -70, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.toggle = CreateFrame("Button", nil, r)
        r.toggle:SetSize(18, ROW_H)
        r.toggle:SetPoint("LEFT", x - 22, 0)
        r.toggle.arrow = UI.Arrow(r.toggle, 11)
        r.toggle.arrow:SetPoint("CENTER")
        r.toggle:SetScript("OnClick", function() if r.item and opts.onToggle then opts.onToggle(r.item) end end)
        r.toggle:Hide()
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.badge = ns.Text(r, 10)
        r.badge:SetPoint("RIGHT", -8, 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.hover)
        r:SetScript("OnClick", function(self, button)
            if not r.item then return end
            if button == "RightButton" then
                if r.item.isHeader and opts.onMenu then opts.onMenu(r.item, self) end
                return
            end
            if opts.onSelect then opts.onSelect(r.item) end
        end)
        if opts.tooltip then
            UI.Tooltip(r, function() if r.item and not r.item.isHeader then return opts.tooltip(r.item) end end)
        end
        list.rows[i] = r
    end
    function list:Render(items, state)
        self.items, self.state = items, state or self.state or {}
        local st = self.state
        local maxScroll = math.max(0, #items - rows)
        self.scroll = math.max(0, math.min(self.scroll, maxScroll))
        for i, r in ipairs(self.rows) do
            local item = items[self.scroll + i]
            r.item = item
            if item and item.isHeader then
                -- group header: arrow, name, count
                r.icon:Hide()
                r.toggle:Show()
                r.toggle.arrow:Point((st.collapsed and st.collapsed[item.group]) and "right" or "down")
                r.text:SetText(ns.Colorize(HEX.accent, item.group) .. "  " .. ns.Muted(tostring(#item.members)))
                local on = st.selectedGroup == item.group
                r.sel:SetShown(on)
                r.mark:SetShown(on)
                if r.check then r.check:SetOn(st.checked and HeaderChecked(item, st.checked)) end
                r.badge:SetText("")
                r:Show()
            elseif item then
                r.icon:Show()
                r.toggle:Hide()
                if opts.color then
                    local c = opts.color(item)
                    r.icon:SetColorTexture(c[1], c[2], c[3], 1)
                elseif opts.icon then
                    r.icon:SetTexture(opts.icon(item))
                end
                r.text:SetText(opts.label(item))
                local on = item == st.selected
                r.sel:SetShown(on)
                r.mark:SetShown(on)
                if r.check then r.check:SetOn(st.checked and st.checked[item]) end
                r.badge:SetText(st.badge and st.badge(item) or "")
                r:Show()
            else
                r:Hide()
            end
        end
        self.empty:SetShown(#items == 0)
    end
    list:SetScript("OnMouseWheel", function(self, delta)
        self.scroll = self.scroll - delta
        self:Render(self.items)
    end)
    return list
end

-- an opaque panel over the whole page
local function MakeOverlay(parent, title)
    local o = CreateFrame("Frame", nil, parent)
    o:SetAllPoints(parent)
    o:SetFrameLevel(parent:GetFrameLevel() + 20)
    o:EnableMouse(true)
    o:Hide()
    ns.Skin(o, T.background)
    o.title = ns.Text(o, 13)
    o.title:SetPoint("TOPLEFT", 0, -4)
    o.title:SetText(title)
    ns.Color(o.title, T.accent)
    o.close = UI.Button(o, 90, L["Close"], function() o:Hide() end)
    o.close:SetPoint("TOPRIGHT", 0, 0)
    return o
end

function Transfer.Build(parent, cfg)
    local LIST_W = Transfer.LIST_W
    local X = LIST_W + 16
    local listOpts = { label = cfg.label, icon = cfg.icon, color = cfg.color, tooltip = cfg.tooltip }
    -- with groups the lists show headers; without, the plain entries
    local function Shaped(items)
        if not cfg.groupOf then return items end
        return Transfer.Flatten(items, cfg.groupNames and cfg.groupNames() or {}, cfg.groupOf)
    end
    local function Opts(extra)
        local o = {}
        for k, v in pairs(listOpts) do o[k] = v end
        for k, v in pairs(extra) do o[k] = v end
        return o
    end
    local t = {}

    -- export ---------------------------------------------------------------
    local ex, exChecked = MakeOverlay(parent, cfg.L.exportTitle), {}
    local function RefreshExport()
        local all, chosen = cfg.items(), {}
        for _, it in ipairs(all) do if exChecked[it] then chosen[#chosen + 1] = it end end
        ex.list:Render(Shaped(all), { checked = exChecked })
        ex.code:SetValue(#chosen > 0 and cfg.encode(chosen) or "")
        ex.info:SetText(L["%d of %d selected"]:format(#chosen, #all))
    end
    -- a header ticks or unticks its whole group
    local function Flip(it)
        if it.isHeader then
            local on = not HeaderChecked(it, exChecked)
            for _, m in ipairs(it.members) do exChecked[m] = on or nil end
        else
            exChecked[it] = not exChecked[it] or nil
        end
        RefreshExport()
    end
    ex.list = Transfer.MakeList(ex, LIST_W, 13, Opts({ checks = true, empty = cfg.L.empty, onCheck = Flip, onSelect = Flip }))
    ex.list:SetPoint("TOPLEFT", 0, -32)
    local all = UI.Button(ex, (LIST_W - 6) / 2, L["Select all"], function()
        for _, it in ipairs(cfg.items()) do exChecked[it] = true end
        RefreshExport()
    end, 22)
    all:SetPoint("BOTTOMLEFT", 0, 0)
    local none = UI.Button(ex, (LIST_W - 6) / 2, L["Select none"], function() wipe(exChecked) RefreshExport() end, 22)
    none:SetPoint("LEFT", all, "RIGHT", 6, 0)
    UI.Label(ex, L["CODE"], X, -32)
    ex.info = ns.Text(ex, 11)
    ex.info:SetPoint("TOPRIGHT", 0, -32)
    ns.Color(ex.info, T.muted)
    ex.code = UI.TextArea(ex)
    ex.code:SetPoint("TOPLEFT", X, -46)
    ex.code:SetPoint("BOTTOMRIGHT", 0, 30)
    -- the code is for copying: typing doesn't change it
    ex.code.edit:SetScript("OnTextChanged", function(self, userInput) if userInput then RefreshExport() self:HighlightText() end end)
    ex.code.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    local hint = UI.Hint(ex, L["Click into the code, then Ctrl+C copies it. Paste it into Import on another account or share it."], App.CONTENT_W - X)
    hint:SetPoint("BOTTOMLEFT", X, 0)

    function t.ShowExport(preselect)
        wipe(exChecked)
        for _, it in ipairs(preselect or {}) do exChecked[it] = true end
        ex.list.scroll = 0
        ex:Show()
        RefreshExport()
    end

    -- import ---------------------------------------------------------------
    local im = MakeOverlay(parent, cfg.L.importTitle)
    local found, imChecked, imSel = {}, {}, nil
    local function DoImport(overwrite)
        if cfg.canImport then
            local ok, why = cfg.canImport()
            if not ok then App.Status(why, true) return end
        end
        local added, replaced, skipped, failed = 0, 0, 0, 0
        for _, it in ipairs(found) do
            if imChecked[it] then
                local have = cfg.find(it)
                if have and not overwrite then
                    skipped = skipped + 1
                elseif have then
                    if cfg.replace(have, it) == false then failed = failed + 1 else replaced = replaced + 1 end
                else
                    if cfg.add(it) == false then failed = failed + 1 else added = added + 1 end
                end
            end
        end
        im:Hide()
        if cfg.done then cfg.done() end
        if failed > 0 then
            App.Status(L["Import: %d added, %d overwritten, %d skipped, %d failed."]:format(added, replaced, skipped, failed), true)
        else
            App.Status(L["Import: %d added, %d overwritten, %d skipped."]:format(added, replaced, skipped))
        end
    end
    local function RenderImport()
        im.list:Render(Shaped(found), {
            checked = imChecked, selected = imSel,
            badge = function(it)
                if it.isHeader then return "" end
                return cfg.find(it) and ns.Colorize(HEX.alert, L["EXISTS"]) or ns.Colorize(HEX.good, L["NEW"])
            end,
        })
        local n = 0
        for _, it in ipairs(found) do if imChecked[it] then n = n + 1 end end
        im.go.text:SetText(L["Import %d"]:format(n))
        im.go:SetAlpha(n > 0 and 1 or 0.4)
        im.preview:SetText(imSel and cfg.preview(imSel) or "")
    end
    local function Parse()
        wipe(found)
        wipe(imChecked)
        imSel = nil
        local text = ns.Trim(im.input.edit:GetText())
        if text ~= "" then
            local list = cfg.decode(text)
            if list then
                for _, it in ipairs(list) do
                    found[#found + 1] = it
                    imChecked[it] = true
                end
                imSel = found[1]
                App.Status(cfg.L.found:format(#found))
            else
                App.Status(cfg.L.invalid, true)
            end
        else
            App.Status(nil)
        end
        im.list.scroll = 0
        RenderImport()
    end
    UI.Label(im, L["PASTE THE CODE HERE"], 0, -32)
    im.input = UI.TextArea(im)
    im.input:SetPoint("TOPLEFT", 0, -46)
    im.input:SetPoint("TOPRIGHT", 0, -46)
    im.input:SetHeight(48)
    im.input.edit:SetScript("OnTextChanged", function(_, userInput) if userInput then Parse() end end)
    im.list = Transfer.MakeList(im, LIST_W, 10, Opts({
        checks = true,
        empty = L["Paste a code above."],
        onCheck = function(it)
            if it.isHeader then
                local on = not HeaderChecked(it, imChecked)
                for _, m in ipairs(it.members) do imChecked[m] = on or nil end
            else
                imChecked[it] = not imChecked[it] or nil
            end
            RenderImport()
        end,
        onSelect = function(it) if not it.isHeader then imSel = it RenderImport() end end,
    }))
    im.list:SetPoint("TOPLEFT", 0, -106)
    UI.Label(im, L["PREVIEW"], X, -106)
    local box = CreateFrame("Frame", nil, im)
    box:SetPoint("TOPLEFT", X, -120)
    box:SetPoint("BOTTOMRIGHT", 0, 30)
    ns.Skin(box, T.control, T.input)
    im.preview = ns.Text(box, 12)
    im.preview:SetPoint("TOPLEFT", 8, -6)
    im.preview:SetPoint("BOTTOMRIGHT", -8, 6)
    im.preview:SetJustifyH("LEFT")
    im.preview:SetJustifyV("TOP")
    im.go = UI.Button(im, 160, "", function()
        local clash = {}
        for _, it in ipairs(found) do
            if imChecked[it] and cfg.find(it) then clash[#clash + 1] = cfg.label(it) end
        end
        if #clash == 0 then return DoImport(false) end
        UI.MessageBox(cfg.L.clashTitle, cfg.L.clashText:format(table.concat(clash, ", ")),
            { { L["Cancel"] }, { L["Skip them"], function() DoImport(false) end },
              { L["Overwrite"], function() DoImport(true) end, true } })
    end, 22)
    im.go:SetPoint("BOTTOMRIGHT", 0, 0)
    im.go:SetAccent(true)

    function t.ShowImport()
        im.input:SetValue("")
        Parse()
        im:Show()
        im.input.edit:SetFocus()
    end

    function t.Hide()
        ex:Hide()
        im:Hide()
    end
    t.export, t.import = ex, im
    return t
end

-- ---------------------------------------------------------------------------
-- Group bookkeeping shared by the templates and the macros.
--   g = { names = ordered list, collapsed = set }  (tables kept in saved data)
--   cfg.members(name) -> entries, cfg.setGroup(entry, name or nil), cfg.changed()
-- Group names are unique; entries keep their place when a group goes away.
-- ---------------------------------------------------------------------------
local Groups = {}
Transfer.Groups = Groups
-- entries without a group of their own; stored as nil, never renamed or deleted
Groups.DEFAULT = Transfer.DEFAULT_GROUP
-- the stored form of a group: the default one is nil
function Groups.Stored(name)
    if name == Groups.DEFAULT or name == "" then return nil end
    return name
end
-- the entries of a group, "Default" holding everything without one
function Groups.IsIn(entryGroup, name) return (entryGroup or Groups.DEFAULT) == name end

function Groups.Has(g, name) return name == Groups.DEFAULT or ns.IndexOf(g.names, name) ~= nil end

-- adds a group if it is new (imports, module defaults)
function Groups.Ensure(g, name)
    name = Groups.Stored(name)
    if name and not Groups.Has(g, name) then g.names[#g.names + 1] = name end
end

function Groups.AskNew(g, onDone)
    UI.Prompt(L["New group"], L["Name of the new group:"], "", function(name)
        if Groups.Has(g, name) then
            App.Status(L["A group named \"%s\" exists already."]:format(name), true)
            return
        end
        g.names[#g.names + 1] = name
        onDone(name)
    end, L["Create"])
end

function Groups.Menu(g, header, anchor, cfg)
    local old = header.group
    if old == Groups.DEFAULT then
        UI.OpenMenu(anchor, { { label = old, isTitle = true },
            { label = ns.Muted(L["Everything without a group of its own. Stays."]), isTitle = true } },
            { width = 260, point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
        return
    end
    UI.OpenMenu(anchor, {
        { label = old, isTitle = true },
        { label = L["Rename"], fn = function()
            UI.Prompt(L["Rename group"], L["New name for \"%s\":"]:format(old), old, function(name)
                if name == old then return end
                if Groups.Has(g, name) then
                    App.Status(L["A group named \"%s\" exists already."]:format(name), true)
                    return
                end
                g.names[ns.IndexOf(g.names, old)] = name
                g.collapsed[name], g.collapsed[old] = g.collapsed[old], nil
                for _, it in ipairs(cfg.members(old)) do cfg.setGroup(it, name) end
                cfg.changed()
            end, L["Rename"])
        end },
        { label = L["Delete group"], fn = function()
            UI.MessageBox(L["Delete group"],
                L["Delete the group \"%s\"? Its %d entries move to \"%s\"."]:format(old, #cfg.members(old), Groups.DEFAULT),
                { { L["Cancel"] }, { L["Delete group"], function()
                    table.remove(g.names, ns.IndexOf(g.names, old))
                    g.collapsed[old] = nil
                    for _, it in ipairs(cfg.members(old)) do cfg.setGroup(it, nil) end
                    cfg.changed()
                end, true } })
        end },
    }, { width = 180, point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
end
