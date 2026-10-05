-- ---------------------------------------------------------------------------
-- Weapon macros. Rogues swap two weapons between the hands: Backstab and
-- Ambush need a dagger in front. The two weapons are the roles W1 and W2 from
-- the placeholders page; the dagger abilities put whichever is a dagger in
-- front (two daggers: the one with "prefer main hand", else W1), everything
-- else the weapon with "prefer main hand" (none ticked: W1).
-- Macros can't hold variables, so the names are written into the macros --
-- this file keeps them up to date.
--   Create missing   makes the macros that don't exist yet (General macros)
--   Refresh          rewrites every macro of the list by its name
-- Without Dual Wield (before level 10) the swap macros only change the main
-- hand. Spell and weapon names come from the client, so the macro names
-- follow the game language. Macro writes are blocked in combat and wait for
-- its end.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, App, Macros, Rogue = ns.UI, ns.App, ns.Macros, ns.Rogue
local Placeholders = ns.Placeholders

local DAGGER = 15   -- Enum.ItemWeaponSubclass.Dagger
local TARGETS = "[@mouseover,harm,nodead][@focus,harm,nodead][] "
local QUESTION = Macros.QUESTION_ICON
local SUFFIX = " UER"
local SPELLS = { backstab = 53, ambush = 8676, sinister = 1752, kick = 1766, blind = 2094, gouge = 1776 }

-- "<spell> UER" from the client's spell name; too long for a macro name
-- (16 letters): the first words that fit ("Sinister UER")
local function SpellMacroName(id)
    local s = ns.SpellName(id)
    if type(s) ~= "string" or s == "" or ns.IsSecret(s) then return ("%d"):format(id) .. SUFFIX end
    local room = Macros.NAME_MAX - #SUFFIX
    if ns.Utf8Len(s) <= room then return s .. SUFFIX end
    local out = ""
    for w in s:gmatch("%S+") do
        local try = out == "" and w or (out .. " " .. w)
        if ns.Utf8Len(try) > room then break end
        out = try
    end
    if out == "" then out = ns.Utf8Sub(s, room) end
    return out .. SUFFIX
end

-- macro names: "UER" at the end, the spells in the game language
local function Names()
    local n = {
        dagger = "W1 MH" .. SUFFIX, weapon = "W2 MH" .. SUFFIX,
        poisonMH = L["Poison MH UER"], poisonOH = L["Poison OH UER"],
    }
    for key, id in pairs(SPELLS) do n[key] = SpellMacroName(id) end
    return n
end
-- names used before: such macros are renamed once (action bars keep them);
-- ns.OLD_MACRO_NAMES adds the names only a translation had
local OLD_NAMES = {
    dagger = { L["UER Dagger MH"], L["Dagger MH UER"] }, weapon = { L["UER Weapon MH"], L["Weapon MH UER"] },
    backstab = { L["UER Backstab"] }, ambush = { L["UER Ambush"] }, sinister = { L["UER Sinister"], L["Sinister UER"] },
    kick = { L["UER Kick"] }, blind = { L["UER Blind"] }, gouge = { L["UER Gouge"] },
    poisonMH = { L["UER Poison MH"] }, poisonOH = { L["UER Poison OH"] },
}
for key, list in pairs(ns.OLD_MACRO_NAMES or {}) do
    for _, old in ipairs(list) do table.insert(OLD_NAMES[key], old) end
end

-- the weapon that goes into the main hand unless an ability needs a dagger
-- there: "W1", "W2" or nil (none ticked: W1)
function Rogue:PreferredRole()
    local r = self:Settings().preferMH
    return (r == "W1" or r == "W2") and r or nil
end
function Rogue:SetPreferredRole(role) self:Settings().preferMH = role end
local function Other(role) return role == "W1" and "W2" or "W1" end

-- front and back role for an ability: wantDagger = Backstab / Ambush
local function FrontFor(found, wantDagger)
    local lead = Rogue:PreferredRole() or "W1"
    if wantDagger then
        local d1 = found.W1 and found.W1.sub == DAGGER
        local d2 = found.W2 and found.W2.sub == DAGGER
        if not (d1 or d2) then return nil end   -- no dagger at all
        if d1 ~= d2 then lead = d1 and "W1" or "W2" end
    end
    return lead, Other(lead)
end

-- W1 / W2 right now: "W1: name · W2: name"
local function RolesText(sep)
    local found, why = Placeholders.ResolveWeapons()
    local parts = {}
    for _, role in ipairs(Placeholders.ROLES) do
        parts[#parts + 1] = ns.Colorize(HEX.good, role .. ":") .. " "
            .. (found[role] and found[role].name or ns.Colorize(HEX.alert, why[role] or "—"))
    end
    return table.concat(parts, sep or "   ·   ")
end

-- the set: { name, icon, body, weapon, note } or { name, skip = reason }
local function Build()
    local out = {}
    local NAMES = Names()
    local found, why = Placeholders.ResolveWeapons()
    local w1, w2 = found.W1 and found.W1.name, found.W2 and found.W2.name
    local dual = Placeholders.CanDualWield()
    local function add(name, body, skip, weapon, note)
        if body and ns.Utf8Len(body) > Macros.BODY_MAX then body, skip = nil, L["longer than 255 letters"] end
        out[#out + 1] = { name = Macros.ShortName(name), icon = QUESTION, body = body, skip = skip, weapon = weapon, note = note }
    end
    -- front into the main hand; with Dual Wield the other one into the off hand
    local function swap(name, front, frontRole, back, cast)
        if not front then return add(name, nil, why[frontRole], true) end
        local body = "#showtooltip " .. (cast or front) .. "\n/equipslot 16 " .. front
        if dual and back then body = body .. "\n/equipslot 17 " .. back end
        if cast then body = body .. "\n/cast " .. cast end
        add(name, body, nil, true)
    end
    swap(NAMES.dagger, w1, "W1", w2)
    swap(NAMES.weapon, w2, "W2", w1)
    local function ability(name, spell, wantDagger)
        local front, back = FrontFor(found, wantDagger)
        if not front then return add(name, nil, L["no dagger as W1 or W2"], true) end
        swap(name, found[front] and found[front].name, front, found[back] and found[back].name, ns.SpellName(spell))
    end
    ability(NAMES.backstab, SPELLS.backstab, true)
    ability(NAMES.ambush, SPELLS.ambush, true)
    ability(NAMES.sinister, SPELLS.sinister, false)
    local kick, blind, gouge = ns.SpellName(SPELLS.kick), ns.SpellName(SPELLS.blind), ns.SpellName(SPELLS.gouge)
    add(NAMES.kick, kick and ("#showtooltip\n/cast " .. TARGETS .. kick))
    add(NAMES.blind, blind and ("#showtooltip\n/stopattack\n/cast " .. TARGETS .. blind))
    add(NAMES.gouge, gouge and ("#showtooltip\n/cast " .. gouge .. "\n/stopattack"))
    for _, g in ipairs({ { NAMES.poisonMH, "MH", 16 }, { NAMES.poisonOH, "OH", 17 } }) do
        local name, id, key = Rogue:MacroPoison(g[2])
        if id then
            -- the item ID keeps it short; the click confirms "replace enchantment?"
            add(g[1], ("/use item:%d\n/use %d\n/click StaticPopup1Button1"):format(id, g[3]), nil, nil, name)
        else
            add(g[1], nil, L["no %s in the bags"]:format(Rogue:PoisonName(key)))
        end
    end
    return out
end

-- each macro with a state: "change" | "same" | "missing" | "skip"
local function Plan()
    local list = Build()
    for _, m in ipairs(list) do
        -- a general and a character macro may share the name: both follow
        m.indices = Macros.IndicesByName(m.name)
        m.index = m.indices[1]
        m.current = m.index and (select(3, GetMacroInfo(m.index)) or "") or nil
        if not m.index then
            m.state = "missing"
        elseif m.skip then
            m.state = "skip"
        else
            m.state = "same"
            for _, idx in ipairs(m.indices) do
                if not Macros.SameText(select(3, GetMacroInfo(idx)), m.body) then m.state = "change" end
            end
        end
    end
    return list
end
Rogue.WeaponMacroPlan = Plan

local RefreshPage
local Placeholders = ns.Placeholders

local function Report(summary, isAlert, lines)
    App.Status(summary, isAlert)
    ns.Print(summary)
    for _, l in ipairs(lines) do print("   " .. l) end
end

local function AfterWrites()
    Macros.Reload()
    if RefreshPage then RefreshPage() end
end

-- only = { [name] = true } limits the update to those macros; quiet: no
-- report (the gear check prints its own line). Returns the updated names.
local function Update(only, quiet)
    if ns.InCombat() then
        Placeholders.AfterCombat("rogueMacros", function() Update(only, quiet) end)
        if not quiet then Report(L["In combat: the weapon macros update when combat ends."], false, {}) end
        return nil
    end
    local list = Plan()
    local updated, failed, missing, skipped, same = {}, {}, {}, {}, 0
    for _, m in ipairs(list) do
        if m.state == "change" then
            if not only or only[m.name] then
                local ok = true
                for _, idx in ipairs(m.indices) do
                    if not pcall(EditMacro, idx, nil, m.icon, m.body) then ok = false end
                end
                if ok then updated[#updated + 1] = m.name else failed[#failed + 1] = m.name end
            end
        elseif m.state == "same" then
            same = same + 1
        elseif m.state == "missing" then
            missing[#missing + 1] = m.name
        else
            skipped[#skipped + 1] = m.name .. " (" .. m.skip .. ")"
        end
    end
    AfterWrites()
    if quiet then return updated end
    local lines = {}
    lines[#lines + 1] = RolesText("   |   ")
    if #updated > 0 then lines[#lines + 1] = L["updated: %s"]:format(table.concat(updated, ", ")) end
    if #missing > 0 then lines[#lines + 1] = L["missing: %s (Create missing)"]:format(table.concat(missing, ", ")) end
    if #skipped > 0 then lines[#lines + 1] = L["skipped: %s"]:format(table.concat(skipped, ", ")) end
    if #failed > 0 then lines[#lines + 1] = ns.Colorize(HEX.alert, L["failed: %s"]:format(table.concat(failed, ", "))) end
    Report(L["Weapon macros: %d updated, %d up to date, %d missing, %d skipped."]:format(
        #updated, same, #missing, #skipped + #failed), #failed > 0, lines)
    return updated
end
Rogue.UpdateWeaponMacros = function() Update() end

-- only = { [name] = true } limits it to those macros
local function CreateMissing(only)
    if ns.InCombat() then
        Placeholders.AfterCombat("rogueCreate", function() CreateMissing(only) end)
        Report(L["In combat: the macros are created when combat ends."], false, {})
        return
    end
    local created, empty, failed, existed = {}, {}, {}, 0
    for _, m in ipairs((Plan())) do
        if m.state == "missing" and (not only or only[m.name]) then
            -- without the gear for it yet the macro starts empty; Update fills it later
            local body = m.body or "#showtooltip"
            if (GetNumMacros() or 0) < Macros.CharBase() and pcall(CreateMacro, m.name, m.icon, body, false) then
                created[#created + 1] = m.name
                if not m.body then empty[#empty + 1] = m.name .. " (" .. m.skip .. ")" end
            else
                failed[#failed + 1] = m.name
            end
        else
            existed = existed + 1
        end
    end
    AfterWrites()
    local lines = {}
    if #created > 0 then lines[#lines + 1] = L["created: %s"]:format(table.concat(created, ", ")) end
    if #empty > 0 then lines[#lines + 1] = L["still empty: %s"]:format(table.concat(empty, ", ")) end
    if #failed > 0 then lines[#lines + 1] = ns.Colorize(HEX.alert, L["failed (macro list full?): %s"]:format(table.concat(failed, ", "))) end
    Report(L["Weapon macros: %d created, %d already there."]:format(#created, existed), #failed > 0, lines)
end
Rogue.CreateWeaponMacros = CreateMissing

-- ---------------------------------------------------------------------------
-- Page: Macros › Rogue
-- ---------------------------------------------------------------------------
local STATE = {
    change = { L["UPDATE"], "accent" }, same = { L["UP TO DATE"], "muted" },
    missing = { L["MISSING"], "alert" }, skip = { L["SKIPPED"], "alert" },
}

local function BuildPage(p)
    local W = App.CONTENT_W
    local LIST_W, ROWS, ROW = 250, 8, 28
    local TOP = -66   -- below the two weapon rows
    local plan, sel, scroll = {}, nil, 0
    local rows = {}

    -- W1 / W2: the same choice as on the placeholders page
    local roleRows = {}
    for i, role in ipairs(Placeholders.ROLES) do
        local r = Placeholders.RoleRow(p, role, Placeholders.Roles, function()
            Placeholders.UpdateGearMacros()
            RefreshPage()
        end)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
        roleRows[i] = r
    end
    -- "prefer main hand": at most one of the two (a second click clears it)
    local fronts = {}
    for i, role in ipairs(Placeholders.ROLES) do
        local c = UI.CheckRow(p, L["Prefer main hand"], function() return Rogue:PreferredRole() == role end, function()
            Rogue:SetPreferredRole(Rogue:PreferredRole() ~= role and role or nil)
            for _, x in ipairs(fronts) do x:Refresh() end
            if Rogue.UpdateWeaponMacros then Rogue.UpdateWeaponMacros() end
        end, 170)
        c:SetPoint("TOPLEFT", 446, -(i - 1) * 28 - 2)
        UI.Tooltip(c, { L["Prefer main hand"], L["This weapon goes into the main hand for everything that doesn't need a dagger there (Sinister Strike, say), and leads when both are daggers. None ticked: W1."] })
        fronts[i] = c
    end
    local dualHint = UI.Hint(p, "", W)

    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, TOP)
    list:SetSize(LIST_W, ROWS * ROW)
    ns.Skin(list, T.panel)
    list:EnableMouseWheel(true)

    local X = LIST_W + 16
    local BOX_W = W - X
    local function Box(label, y, h)
        UI.Label(p, label, X, y)
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", X, y - 16)
        f:SetSize(BOX_W, h)
        ns.Skin(f, T.control, T.input)
        f.text = ns.Text(f, 12)
        f.text:SetPoint("TOPLEFT", 8, -6)
        f.text:SetPoint("BOTTOMRIGHT", -8, 6)
        f.text:SetJustifyH("LEFT")
        f.text:SetJustifyV("TOP")
        return f
    end
    local curBox = Box(L["CURRENT"], TOP, 92)
    local newBox = Box(L["NEW"], TOP - 116, 92)

    local applyBtn, createBtn, selBtn
    local function Render()
        local changes, missing = 0, 0
        for _, m in ipairs(plan) do
            if m.state == "change" then changes = changes + 1 end
            if m.state == "missing" then missing = missing + 1 end
        end
        scroll = math.max(0, math.min(scroll, #plan - ROWS))
        for i = 1, ROWS do
            local r, m = rows[i], plan[scroll + i]
            r.entry = m
            if m then
                r.name:SetText(m.name)
                local st = STATE[m.state]
                r.badge:SetText(ns.Colorize(HEX[st[2]], st[1]))
                r.sel:SetShown(m == sel)
                r.mark:SetShown(m == sel)
                r:Show()
            else
                r:Hide()
            end
        end
        if sel then
            curBox.text:SetText(sel.current and (sel.current ~= "" and sel.current or ns.Muted(L["(empty)"]))
                or ns.Colorize(HEX.alert, L["This macro doesn't exist yet."]))
            if sel.body then
                newBox.text:SetText(sel.body .. (sel.note and ("\n\n" .. ns.Muted(L["item: %s"]:format(sel.note))) or ""))
            else
                newBox.text:SetText(ns.Colorize(HEX.alert, L["Can't be built right now: %s."]:format(sel.skip)))
            end
        else
            curBox.text:SetText("")
            newBox.text:SetText("")
        end
        applyBtn.text:SetText(changes > 0 and L["Refresh all (%d)"]:format(changes) or L["Refresh all"])
        -- the selected macro: create or refresh just this one
        local st = sel and sel.state
        selBtn.text:SetText(st == "missing" and L["Create \"%s\""]:format(sel.name)
            or L["Refresh \"%s\""]:format(sel and sel.name or "—"))
        selBtn:SetAlpha((st == "missing" or st == "change") and 1 or 0.4)
        createBtn.text:SetText(L["Create %d missing"]:format(missing))
        createBtn:SetAlpha(missing > 0 and 1 or 0.4)
    end

    RefreshPage = function()
        if not p:IsVisible() then return end
        local selName = sel and sel.name
        plan = Plan()
        sel = nil
        for _, m in ipairs(plan) do if m.name == selName then sel = m end end
        if not sel then
            for _, m in ipairs(plan) do if m.state == "change" then sel = m break end end
            sel = sel or plan[1]
        end
        for _, r in ipairs(roleRows) do r:Refresh() end
        for _, c in ipairs(fronts) do c:Refresh() end
        dualHint:SetText(Placeholders.CanDualWield() and L["Backstab and Ambush put the dagger in front, everything else the weapon with \"Prefer main hand\" (none ticked: W1). The swap macros put one in each hand."]
            or L["Without Dual Wield (level 10) the swap macros change the main hand only."])
        Render()
    end

    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetSize(LIST_W, ROW)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        ns.Color(r.sel, T.accentSoft)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        ns.Color(r.mark, T.accent)
        r.name = ns.Text(r, 12)
        r.name:SetPoint("LEFT", 12, 0)
        r.name:SetJustifyH("LEFT")
        r.badge = ns.Text(r, 10)
        r.badge:SetPoint("RIGHT", -8, 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.hover)
        r:SetScript("OnClick", function(self) sel = self.entry Render() end)
        rows[i] = r
    end

    list:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta
        Render()
    end)

    selBtn = UI.Button(p, LIST_W, "", function()
        if not sel then return end
        if sel.state == "missing" then CreateMissing({ [sel.name] = true })
        elseif sel.state == "change" then Update({ [sel.name] = true }) end
    end, 22)
    selBtn:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -10)
    UI.Tooltip(selBtn, { L["Selected macro"], L["Creates the selected macro, or writes it anew when it is out of date."] })
    createBtn = UI.Button(p, LIST_W, "", function() CreateMissing() end, 22)
    createBtn:SetPoint("TOPLEFT", selBtn, "BOTTOMLEFT", 0, -6)
    applyBtn = UI.Button(p, 170, "", function() Update() end, 22)
    applyBtn:SetPoint("TOPLEFT", newBox, "BOTTOMLEFT", 0, -10)
    applyBtn:SetAccent(true)
    UI.Tooltip(applyBtn, { L["Refresh all"], L["Rewrites every macro of this list (general or character) with your current weapons, spells and poisons."] })

    local note = UI.Hint(p, L["\"Refresh all\" writes every macro of this list anew that exists under its name (general or character); macros with other names are never changed. Drag new ones from the macro list onto your action bars."], W)
    note:SetPoint("BOTTOMLEFT", 0, 0)
    note:SetSpacing(2)
    dualHint:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -12)
end

App:AddPage({
    key = "weaponMacros", section = "macros", label = L["Rogue"], order = 120,
    IsVisible = function() return Rogue:IsActive() end,
    Build = function(_, frame) BuildPage(frame) end,
    Refresh = function() if RefreshPage then RefreshPage() end end,
})

local function ShowPlan() App:Open("weaponMacros") end
Rogue.ShowWeaponMacros = ShowPlan

-- buttons in the macro manager header
Macros.RegisterAction({
    label = L["Rogue"], width = 130, accent = true,
    IsActive = function() return Rogue:IsActive() end,
    OnClick = function(_, button)
        if button == "RightButton" then Update() else ShowPlan() end
    end,
    Tooltip = function()
        local list = Plan()
        local lines = { L["Weapon macros"] }
        lines[#lines + 1] = RolesText("\n")
        local changes = {}
        for _, m in ipairs(list) do if m.state == "change" then changes[#changes + 1] = m.name end end
        lines[#lines + 1] = #changes > 0 and L["Would update: %s"]:format(table.concat(changes, ", ")) or L["Everything is up to date."]
        lines[#lines + 1] = L["Left-click: show the changes  ·  Right-click: update all now"]
        return lines
    end,
})

-- ---------------------------------------------------------------------------
-- Changed weapons: the swap macros follow (Placeholders asks first for new ones)
-- ---------------------------------------------------------------------------
local function WeaponOutdated()
    local only, names = {}, {}
    for _, m in ipairs((Plan())) do
        if m.weapon and m.state == "change" then
            only[m.name] = true
            names[#names + 1] = m.name
        end
    end
    return names, only
end
Placeholders.RegisterGearMacros({
    IsActive = function() return Rogue:IsActive() end,
    Outdated = function() return (WeaponOutdated()) end,
    Update = function()
        local _, only = WeaponOutdated()
        if not next(only) then return {} end
        return Update(only, true)
    end,
})
Placeholders.RegisterUpdater(function() if Rogue:IsActive() then Update() end end)

ns.RegisterEvent("UPDATE_MACROS", function() if App:IsOpen("weaponMacros") and RefreshPage then RefreshPage() end end)
ns.RegisterEvent("BAG_UPDATE", function() if App:IsOpen("weaponMacros") and RefreshPage then RefreshPage() end end)
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() if App:IsOpen("weaponMacros") and RefreshPage then RefreshPage() end end)

-- the old names ("UER ..." in front) become the new ones, once; renaming
-- keeps the macros on the action bars
local function RenameOld()
    if not Rogue:IsActive() then return end
    if ns.InCombat() then Placeholders.AfterCombat("rogueRename", RenameOld) return end
    local renamed = {}
    local NAMES = Names()
    for key, olds in pairs(OLD_NAMES) do
        local new = Macros.ShortName(NAMES[key])
        for _, old in ipairs(olds) do
            old = Macros.ShortName(old)
            if #Macros.IndicesByName(new) == 0 then
                for _ = 1, 4 do
                    local idx = Macros.IndicesByName(old)[1]
                    if not idx or not pcall(EditMacro, idx, new) then break end
                    renamed[#renamed + 1] = new
                end
            end
        end
    end
    if #renamed > 0 then
        ns.Print(L["Rogue macros renamed: %s"]:format(table.concat(renamed, ", ")))
        Macros.Reload()
    end
end
Rogue.RenameOldMacros = RenameOld
ns.On("LOGIN", function() C_Timer.After(2, RenameOld) end)

ns.AddCommand({ "defaults" }, function() CreateMissing() end, L["rogue: create the missing weapon macros"])
