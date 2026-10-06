-- ---------------------------------------------------------------------------
-- Placeholders: words in macro text (templates) that the addon fills in when
-- it writes the macro, so the macro keeps up with the game:
--   {s:1752}    spell name in the client language (highest rank)
--   {s:1752:r}  spell name with its rank, e.g. "Sinister Strike(Rank 3)"
--   {w:W1}      weapon roles W1 / W2: each a weapon type and the weapon of
--   {w:W2}      that type you picked (equipped or in the bags); W1 and W2
--               are never the same weapon
--   {g:t1}      the trinkets (gear) in slot 13 / 14
--   {g:t2}
--   {c:name}    your own: a name with a value (account-wide)
-- Modules add their own through the Fill of their template group (the
-- rogue's {p:MH} / {p:OH}).
-- Changed gear: a dialog suggests W1 / W2 for the new weapons (after combat);
-- confirmed, the macros that use the gear are written anew
-- (sources: Placeholders.RegisterGearMacros).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, App, Macros = ns.UI, ns.App, ns.Macros

local Placeholders = { gearSources = {}, updaters = {} }
ns.Placeholders = Placeholders

local DAGGER = 15   -- Enum.ItemWeaponSubclass.Dagger
local ANY = -1
local WEAPON_CLASS = 2   -- Enum.ItemClass.Weapon
local DUAL_WIELD = 674
local GEAR_SLOTS = { 13, 14, 16, 17 }
local NOT_HELD = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
                   INVTYPE_RELIC = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true }

-- ---------------------------------------------------------------------------
-- Storage: roles per character, own placeholders account-wide
-- ---------------------------------------------------------------------------
local ROLE_DEFAULTS = { W1 = { type = DAGGER }, W2 = { type = ANY } }
Placeholders.ROLES = { "W1", "W2" }

function Placeholders.CharStore()
    local c = ns.Char()
    if not c.placeholders then
        c.placeholders = {}
        -- the weapon types of the roles used to live in the rogue module
        local rogue = c.modules and c.modules.rogue
        if rogue then
            if type(rogue.roles) == "table" then
                c.placeholders.roles = {}
                for r, v in pairs(rogue.roles) do c.placeholders.roles[r] = { type = v.type } end
            end
            rogue.roles, rogue.roleMemo, rogue.gearNotice, rogue.gearNotified = nil, nil, nil, nil
        end
    end
    local s = c.placeholders
    s.roles = s.roles or {}
    for role, def in pairs(ROLE_DEFAULTS) do
        s.roles[role] = s.roles[role] or {}
        if s.roles[role].type == nil then s.roles[role].type = def.type end
    end
    return s
end
function Placeholders.Roles() return Placeholders.CharStore().roles end

local function Custom()
    local a = ns.Acct()
    a.placeholders = a.placeholders or {}
    a.placeholders.custom = a.placeholders.custom or {}
    return a.placeholders.custom
end
Placeholders.Custom = Custom

function Placeholders.FindCustom(name)
    for i, c in ipairs(Custom()) do
        if c.name == name then return c, i end
    end
end

-- ---------------------------------------------------------------------------
-- Weapons you own and the roles W1 / W2
-- ---------------------------------------------------------------------------
-- weapon subclasses (Enum.ItemWeaponSubclass); own names first, because the
-- client calls one- and two-handed swords alike ("Schwert")
Placeholders.WEAPON_TYPES = { ANY, 15, 7, 4, 0, 13, 8, 5, 1, 6, 10 }
local TYPE_NAMES = {
    [15] = L["Dagger"], [7] = L["One-handed sword"], [4] = L["One-handed mace"], [0] = L["One-handed axe"],
    [13] = L["Fist weapon"], [8] = L["Two-handed sword"], [5] = L["Two-handed mace"], [1] = L["Two-handed axe"],
    [6] = L["Polearm"], [10] = L["Staff"],
}
function Placeholders.WeaponTypeName(t)
    if t == ANY then return L["Any weapon"] end
    if TYPE_NAMES[t] then return TYPE_NAMES[t] end
    local get = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    local name = get and get(2, t)
    return (type(name) == "string" and name ~= "") and name or tostring(t)
end

local function ItemInfo(id)
    if not (id and C_Item and C_Item.GetItemInfoInstant) then return end
    local _, _, _, equipLoc, _, classID, subID = C_Item.GetItemInfoInstant(id)
    return classID, subID, equipLoc
end

-- every weapon in the hands and the bags: { id, name, sub, slot (16/17/nil) }
function Placeholders.Weapons()
    local out, seen = {}, {}
    local function add(id, name, slot)
        if not id or seen[id] then return end
        local classID, sub, loc = ItemInfo(id)
        if classID ~= WEAPON_CLASS or NOT_HELD[loc or ""] then return end
        seen[id] = true
        out[#out + 1] = { id = id, name = name or ns.ItemName(id) or ("item:" .. id), sub = sub, slot = slot }
    end
    for _, slot in ipairs({ 16, 17 }) do add(GetInventoryItemID("player", slot), ns.EquippedName(slot), slot) end
    ns.ForEachBagItem(function(id, name) add(id, name) end)
    return out
end

local function Fits(w, roleType) return roleType == ANY or w.sub == roleType end

-- the best guess for a role: equipped before bags; W1 prefers the main hand,
-- W2 takes what W1 left. avoid = the item ID the other role holds
function Placeholders.Suggest(role, roleType, avoid, weapons)
    weapons = weapons or Placeholders.Weapons()
    local order = role == "W1" and { 16, 17, false } or { 17, 16, false }
    for _, want in ipairs(order) do
        for _, w in ipairs(weapons) do
            if w.id ~= avoid and Fits(w, roleType) and ((want and w.slot == want) or (not want and not w.slot)) then
                return w
            end
        end
    end
end

-- suggestions for both roles from what you carry now: { W1 = id, W2 = id }
function Placeholders.SuggestAll(types)
    local weapons = Placeholders.Weapons()
    local roles = Placeholders.Roles()
    local t1 = types and types.W1 or roles.W1.type
    local t2 = types and types.W2 or roles.W2.type
    local w1 = Placeholders.Suggest("W1", t1, nil, weapons)
    local w2 = Placeholders.Suggest("W2", t2, w1 and w1.id, weapons)
    return { W1 = w1 and w1.id, W2 = w2 and w2.id }
end

-- { W1 = { id, name, slot }, W2 = ... }, { W1 = reason, ... }
function Placeholders.ResolveWeapons(roles)
    roles = roles or Placeholders.Roles()
    local weapons = Placeholders.Weapons()
    local byId = {}
    for _, w in ipairs(weapons) do byId[w.id] = w end
    local out, why, taken = {}, {}, nil
    for _, role in ipairs(Placeholders.ROLES) do
        local r = roles[role]
        local pick = r.item and byId[r.item]
        if pick and (pick.id == taken or not Fits(pick, r.type)) then pick = nil end
        pick = pick or Placeholders.Suggest(role, r.type, taken, weapons)
        if pick then
            out[role], taken = pick, pick.id
        else
            why[role] = L["%s: no %s"]:format(role, Placeholders.WeaponTypeName(r.type))
        end
    end
    return out, why
end

-- picks a role's type or weapon; the other role never holds the same weapon
function Placeholders.SetRole(role, field, value, roles)
    roles = roles or Placeholders.Roles()
    local r = roles[role]
    r[field] = value
    if field == "type" then
        -- the best weapon of the new type, rather not the other role's; if it
        -- is the only one, the other role makes room
        local other = roles[role == "W1" and "W2" or "W1"]
        local w = Placeholders.Suggest(role, value, other.item) or Placeholders.Suggest(role, value)
        r.item = w and w.id or nil
    end
    local otherRole = role == "W1" and "W2" or "W1"
    if r.item and roles[otherRole].item == r.item then
        local w = Placeholders.Suggest(otherRole, roles[otherRole].type, r.item)
        roles[otherRole].item = w and w.id or nil
    end
end

-- the weapon list of a role (for the drop-down): { { id, label } }
function Placeholders.WeaponItems(role, roles)
    roles = roles or Placeholders.Roles()
    local r = roles[role]
    local items = {}
    for _, w in ipairs(Placeholders.Weapons()) do
        if Fits(w, r.type) then
            local where = w.slot == 16 and L["main hand"] or w.slot == 17 and L["off hand"] or L["bags"]
            items[#items + 1] = { w.id, w.name .. "  " .. ns.Muted("(" .. where .. ")") }
        end
    end
    if #items == 0 then items[1] = { false, ns.Muted(L["none in the bags or hands"]) } end
    return items
end

-- can this character carry a weapon in the off hand?
function Placeholders.CanDualWield()
    if ns.IsKnown(DUAL_WIELD) then return true end
    local classID, _, loc = ItemInfo(GetInventoryItemID("player", 17))
    return classID == WEAPON_CLASS and not NOT_HELD[loc or ""]
end

-- the trinket in slot 13 (n = 1) or 14 (n = 2)
function Placeholders.Trinket(n)
    local slot = 12 + n
    if not GetInventoryItemID("player", slot) then return nil end
    return ns.EquippedName(slot)
end

-- one row: {w:W1}  [type v]  [weapon v]; source = roles table (the saved
-- one or the dialog's draft), onChange() after a pick
function Placeholders.RoleRow(parent, role, getRoles, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(430, 24)
    row.code = ns.Text(row, 13)
    row.code:SetPoint("LEFT", 0, 0)
    row.code:SetText(ns.Code("{w:" .. role .. "}"))
    local types = {}
    for _, t in ipairs(Placeholders.WEAPON_TYPES) do types[#types + 1] = { t, Placeholders.WeaponTypeName(t) } end
    row.type = UI.Dropdown(row, types, function() return getRoles()[role].type end, function(v)
        Placeholders.SetRole(role, "type", v, getRoles())
        onChange()
    end, 140)
    row.type:SetPoint("LEFT", 50, 0)
    row.weapon = UI.Dropdown(row, function() return Placeholders.WeaponItems(role, getRoles()) end,
        function()
            local found = Placeholders.ResolveWeapons(getRoles())
            return found[role] and found[role].id or false
        end, function(v)
            if not v then return end
            Placeholders.SetRole(role, "item", v, getRoles())
            onChange()
        end, 234)
    row.weapon:SetPoint("LEFT", row.type, "RIGHT", 6, 0)
    UI.Tooltip(row.weapon, { L["Weapon"], L["Your weapons of this type, in your hands or bags. W1 and W2 are never the same weapon."] })
    function row:Refresh()
        self.type:Refresh()
        self.weapon:Refresh()
    end
    return row
end

-- ---------------------------------------------------------------------------
-- Filling in
-- ---------------------------------------------------------------------------
function Placeholders.SpellRank(id)
    local get = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
    local ok, rank = pcall(get or function() end, id)
    if ok and type(rank) == "string" and not ns.IsSecret(rank) and rank ~= "" then return rank end
end

local function SpellText(id, withRank)
    id = tonumber(id)
    local name = ns.SpellName(id)
    if not name then return nil end
    local rank = withRank and Placeholders.SpellRank(id)
    return rank and (name .. "(" .. rank .. ")") or name
end

-- macro text with every placeholder filled in that has a value right now;
-- the rest stays as it is (Placeholders.Unfilled lists it)
function Placeholders.Fill(body)
    local text = (body or ""):gsub("{s:(%d+):[rR]}", function(id) return SpellText(id, true) or ("spell " .. id) end)
    text = text:gsub("{s:(%d+)}", function(id) return SpellText(id) or ("spell " .. id) end)
    if text:find("{w:", 1, true) then
        local found = Placeholders.ResolveWeapons()
        text = text:gsub("{w:[wW]([12])}", function(n) return found["W" .. n] and found["W" .. n].name or nil end)
    end
    text = text:gsub("{g:[tT]([12])}", function(n) return Placeholders.Trinket(tonumber(n)) end)
    if text:find("{c:", 1, true) then
        text = text:gsub("{c:([^}]+)}", function(name)
            local c = Placeholders.FindCustom(name)
            return c and c.value or nil
        end)
    end
    for _, group in ipairs(Macros.templates) do
        if group.Fill and (not group.IsActive or group.IsActive()) then text = group.Fill(text) end
    end
    return ns.Utf8Sub(text, Macros.BODY_MAX)
end

-- placeholders left in a filled text: { "{w:W1}", ... }
function Placeholders.Unfilled(text)
    local out = {}
    for p in (text or ""):gmatch("{%a:[^}\n]*}") do
        if not ns.IndexOf(out, p) then out[#out + 1] = p end
    end
    return out
end

-- does this template text depend on the gear? (weapons, trinkets)
function Placeholders.UsesGear(body)
    return body and (body:find("{w:", 1, true) or body:find("{g:", 1, true)) and true or false
end

-- ---------------------------------------------------------------------------
-- Writing after combat (macro writes are blocked in combat), one job per key
-- ---------------------------------------------------------------------------
local afterCombat, afterOrder = {}, {}
function Placeholders.AfterCombat(key, fn)
    if not afterCombat[key] then afterOrder[#afterOrder + 1] = key end
    afterCombat[key] = fn
end
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    C_Timer.After(0.1, function()
        local order = afterOrder
        afterOrder = {}
        for _, key in ipairs(order) do
            local fn = afterCombat[key]
            afterCombat[key] = nil
            if fn then fn() end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Changed gear: { Outdated() -> { names }, Update() -> { updated names } }
-- ---------------------------------------------------------------------------
function Placeholders.RegisterGearMacros(src) table.insert(Placeholders.gearSources, src) end
-- extra jobs for /ef update (the rogue's built-in macros)
function Placeholders.RegisterUpdater(fn) table.insert(Placeholders.updaters, fn) end

local function GearOutdated()
    local out = {}
    for _, src in ipairs(Placeholders.gearSources) do
        if not src.IsActive or src.IsActive() then
            for _, n in ipairs(src.Outdated()) do out[#out + 1] = n end
        end
    end
    return out
end

-- rewrites every macro that uses the gear; one line in the chat
function Placeholders.UpdateGearMacros()
    if ns.InCombat() then
        Placeholders.AfterCombat("gear", Placeholders.UpdateGearMacros)
        return
    end
    local updated = {}
    for _, src in ipairs(Placeholders.gearSources) do
        if not src.IsActive or src.IsActive() then
            for _, n in ipairs(src.Update() or {}) do updated[#updated + 1] = n end
        end
    end
    if #updated > 0 then ns.Print(L["Gear changed, macros updated: %s"]:format(table.concat(updated, ", "))) end
    Macros.Reload()
    if Placeholders.RefreshPage then Placeholders.RefreshPage() end
end

-- everything: templates, the modules' own macros (Placeholders page, /ef update)
function Placeholders.UpdateAll()
    if ns.Templates then ns.Templates.UpdateMacros() end
    for _, fn in ipairs(Placeholders.updaters) do fn() end
end

-- the weapons and trinkets worn right now, as one key
local function GearKey()
    local ids = {}
    for _, slot in ipairs(GEAR_SLOTS) do ids[#ids + 1] = tostring(GetInventoryItemID("player", slot) or 0) end
    return table.concat(ids, ":")
end

-- ---------------------------------------------------------------------------
-- Dialog: new weapons or trinkets. Shows W1 / W2 with the suggestion; the
-- player confirms or changes it, then the macros follow.
-- ---------------------------------------------------------------------------
local dlg, draft
local function BuildDialog()
    dlg = UI.Window("EverFrameGearDialog", 470, 236, L["New gear"], { strata = "FULLSCREEN_DIALOG" })
    dlg.text = UI.Hint(dlg, "", 442)
    dlg.text:SetPoint("TOPLEFT", 14, -36)
    ns.Color(dlg.text, T.text)
    dlg.rows = {}
    for i, role in ipairs(Placeholders.ROLES) do
        local r = Placeholders.RoleRow(dlg, role, function() return draft end, function()
            for _, x in ipairs(dlg.rows) do x:Refresh() end
        end)
        r:SetPoint("TOPLEFT", 14, -96 - (i - 1) * 30)
        dlg.rows[i] = r
    end
    dlg.note = UI.Hint(dlg, L["Macros with weapons or trinkets are written anew with this choice."], 442)
    dlg.note:SetPoint("TOPLEFT", 14, -160)
    local ok = UI.Button(dlg, 120, L["Apply"], function()
        local roles = Placeholders.Roles()
        for _, role in ipairs(Placeholders.ROLES) do
            roles[role].type, roles[role].item = draft[role].type, draft[role].item
        end
        Placeholders.CharStore().seen = GearKey()
        dlg:Hide()
        Placeholders.UpdateGearMacros()
    end, 24)
    ok:SetPoint("BOTTOMRIGHT", -14, 14)
    ok:SetAccent(true)
    local later = UI.Button(dlg, 100, L["Later"], function()
        Placeholders.CharStore().seen = GearKey()   -- not again for this gear
        dlg:Hide()
    end, 24)
    later:SetPoint("RIGHT", ok, "LEFT", -6, 0)
end

-- the suggestion after a weapon change: a role whose weapon is still in a
-- hand keeps it; a new weapon takes the place of a role whose weapon left
-- the hands (one of its own type first) and brings its type along
function Placeholders.DraftForNewGear()
    local roles = Placeholders.Roles()
    local d = {}
    for _, role in ipairs(Placeholders.ROLES) do d[role] = { type = roles[role].type, item = roles[role].item } end
    local equipped, new = {}, {}
    for _, slot in ipairs({ 16, 17 }) do
        local id = GetInventoryItemID("player", slot)
        local classID, sub, loc = ItemInfo(id)
        if id and classID == WEAPON_CLASS and not NOT_HELD[loc or ""] then
            equipped[id] = true
            if id ~= roles.W1.item and id ~= roles.W2.item then new[#new + 1] = { id = id, sub = sub } end
        end
    end
    local free = {}
    for _, role in ipairs(Placeholders.ROLES) do
        if not (d[role].item and equipped[d[role].item]) then free[#free + 1] = role end
    end
    for _, w in ipairs(new) do
        local pick
        for i, role in ipairs(free) do
            if d[role].type == w.sub then pick = i break end
        end
        pick = pick or (#free > 0 and 1)
        local role = pick and table.remove(free, pick) or "W2"
        d[role].item, d[role].type = w.id, w.sub
    end
    return d
end

function Placeholders.ShowGearDialog(newNames)
    draft = Placeholders.DraftForNewGear()
    if not dlg then BuildDialog() end
    dlg.text:SetText(L["New gear: %s.\nPlease check which weapon is W1 and which is W2:"]:format(
        ns.Colorize(HEX.good, table.concat(newNames, ", "))))
    for _, r in ipairs(dlg.rows) do r:Refresh() end
    UI.PlaceDialog(dlg)
    dlg:Show()
    dlg:Raise()
end

local checkAfterCombat = false
local function CheckGear()
    if not ns.ready then return end
    if ns.InCombat() then checkAfterCombat = true return end
    if not GetInventoryItemID("player", 16) then return end   -- mid-swap: wait for the weapon
    local s = Placeholders.CharStore()
    local roles = s.roles
    -- first time: take the suggestion without asking
    if not (roles.W1.item or roles.W2.item) then
        local sug = Placeholders.SuggestAll()
        roles.W1.item, roles.W2.item = sug.W1, sug.W2
        s.seen = GearKey()
    end
    -- weapons in the hands that are neither W1 nor W2 (swapping the two is fine)
    local new = {}
    for _, slot in ipairs({ 16, 17 }) do
        local id = GetInventoryItemID("player", slot)
        local classID, _, loc = ItemInfo(id)
        if id and classID == WEAPON_CLASS and not NOT_HELD[loc or ""] and id ~= roles.W1.item and id ~= roles.W2.item then
            new[#new + 1] = ns.EquippedName(slot) or ("item:" .. id)
        end
    end
    local outdated = GearOutdated()
    if #new == 0 and #outdated == 0 then return end
    if s.seen == GearKey() then return end   -- asked for this gear already
    if #new == 0 then
        -- trinkets (or a weapon back in its role): name what changed
        for _, slot in ipairs({ 13, 14 }) do
            local n = ns.EquippedName(slot)
            if n then new[#new + 1] = n end
        end
    end
    Placeholders.ShowGearDialog(new)
end
Placeholders.CheckGear = CheckGear

local token = 0
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
    if not ns.IndexOf(GEAR_SLOTS, slot) then return end
    if Placeholders.RefreshPage then Placeholders.RefreshPage() end
    -- a swap fires several events: judge the gear once it has settled
    token = token + 1
    local mine = token
    C_Timer.After(1.5, function() if mine == token then CheckGear() end end)
end)
ns.On("LOGIN", function() C_Timer.After(3, CheckGear) end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if checkAfterCombat then
        checkAfterCombat = false
        C_Timer.After(0.2, CheckGear)
    end
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    -- the dialog waits for the end of combat
    if dlg and dlg:IsShown() then dlg:Hide() checkAfterCombat = true end
end)

-- ---------------------------------------------------------------------------
-- Page: Macros › Placeholders
-- ---------------------------------------------------------------------------
local CUSTOM_ROWS, ROW = 6, 28

local function BuildPage(p)
    local W = App.CONTENT_W

    UI.Label(p, L["GEAR"], 0, 0)
    local roleRows = {}
    local function RolesChanged()
        for _, r in ipairs(roleRows) do r:Refresh() end
        Placeholders.CharStore().seen = GearKey()
        Placeholders.UpdateGearMacros()
    end
    for i, role in ipairs(Placeholders.ROLES) do
        local r = Placeholders.RoleRow(p, role, Placeholders.Roles, RolesChanged)
        r:SetPoint("TOPLEFT", 0, -18 - (i - 1) * ROW)
        roleRows[i] = r
    end
    -- trinkets: fixed slots
    local trinkets = {}
    for n = 1, 2 do
        local y = -18 - (n + 1) * ROW - 4
        local t = {}
        t.code = ns.Text(p, 13)
        t.code:SetPoint("TOPLEFT", 0, y)
        t.code:SetText(ns.Code("{g:t" .. n .. "}"))
        t.slot = ns.Text(p, 12)
        t.slot:SetPoint("TOPLEFT", 50, y)
        ns.Color(t.slot, T.muted)
        t.slot:SetText(L["Trinket %d (slot %d)"]:format(n, 12 + n))
        t.found = ns.Text(p, 12)
        t.found:SetPoint("TOPLEFT", 196, y)
        t.found:SetPoint("TOPRIGHT", 0, y)
        t.found:SetJustifyH("LEFT")
        t.found:SetWordWrap(false)
        trinkets[n] = t
    end

    local GY = -18 - 4 * ROW - 6
    local refreshAll = UI.Button(p, 130, L["Refresh"], function() Placeholders.UpdateAll() end, 22)
    refreshAll:SetPoint("TOPLEFT", 0, GY)
    refreshAll:SetAccent(true)
    UI.Tooltip(refreshAll, { L["Refresh"], L["Rewrites every macro named exactly like a template (general or character) and the rogue's macros with the current values."] })
    local gearTpl = UI.Button(p, 172, "+  " .. L["Template with gear"], function()
        ns.Templates.New({ group = L["Gear"], body = "#showtooltip\n/equipslot 16 {w:W1}\n/equipslot 17 {w:W2}" })
        App.Status(L["Name it and save: macros with this name follow your gear."])
    end, 22)
    gearTpl:SetPoint("LEFT", refreshAll, "RIGHT", 6, 0)
    UI.Tooltip(gearTpl, { L["Template with gear"], L["A template with {w:W1} and {w:W2}: they become the weapons picked above. Export and import it with the templates."] })

    -- own placeholders
    local CY = GY - 36
    UI.Label(p, L["YOUR PLACEHOLDERS"], 0, CY)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, CY - 18)
    list:SetSize(W, CUSTOM_ROWS * ROW)
    list:EnableMouseWheel(true)
    local empty = UI.Hint(list, L["None yet. \"+ Placeholder\" adds one: a name and a value, e.g. {c:me} = Ketchup."], W)
    empty:SetPoint("TOPLEFT", 0, -4)
    local scroll = 0
    local cRows = {}
    local Render

    local function Commit(r)
        local c = r.entry
        if not c then return end
        local name = ns.Trim(r.name:GetText())
        local value = r.value:GetText()
        if name ~= c.name then
            if name == "" or name:find("[{}:%s]") then
                App.Status(L["A name without spaces, braces or colons, please."], true)
                r.name:SetText(c.name)
            elseif Placeholders.FindCustom(name) then
                App.Status(L["{c:%s} exists already."]:format(name), true)
                r.name:SetText(c.name)
            else
                c.name = name
            end
        end
        if value ~= c.value then
            c.value = value
            -- macros with this placeholder take the new value
            if ns.Templates then ns.Templates.UpdateMacros(function(t) return t.body:find("{c:" .. c.name .. "}", 1, true) end) end
        end
        r.code:SetText(ns.Code("{c:" .. c.name .. "}"))
    end

    for i = 1, CUSTOM_ROWS do
        local r = CreateFrame("Frame", nil, list)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetSize(W, ROW)
        r.name = UI.LineEdit(r, 12, 24)
        r.name:SetPoint("LEFT", 0, 0)
        r.name:SetSize(130, 22)
        r.eq = ns.Text(r, 12)
        r.eq:SetPoint("LEFT", 136, 0)
        r.eq:SetText("=")
        r.value = UI.LineEdit(r, 12, 200)
        r.value:SetPoint("LEFT", 150, 0)
        r.value:SetSize(W - 150 - 30 - 150, 22)
        r.code = ns.Text(r, 11)
        r.code:SetPoint("LEFT", r.value, "RIGHT", 8, 0)
        r.code:SetWidth(140)
        r.code:SetJustifyH("LEFT")
        r.code:SetWordWrap(false)
        r.del = UI.ConfirmButton(r, 24, "×", function()
            local _, idx = Placeholders.FindCustom(r.entry and r.entry.name)
            if idx then table.remove(Custom(), idx) end
            Render()
        end, 22)
        r.del:SetPoint("RIGHT", 0, 0)
        UI.Tooltip(r.del, { L["Delete"], L["Click twice to confirm."] })
        for _, e in ipairs({ r.name, r.value }) do
            e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            e:HookScript("OnEditFocusLost", function() Commit(r) end)
        end
        cRows[i] = r
    end

    Render = function()
        local all = Custom()
        scroll = math.max(0, math.min(scroll, #all - CUSTOM_ROWS))
        empty:SetShown(#all == 0)
        for i, r in ipairs(cRows) do
            local c = all[scroll + i]
            r.entry = c
            if c then
                if not r.name:HasFocus() then r.name:SetText(c.name) end
                if not r.value:HasFocus() then r.value:SetText(c.value or "") end
                r.code:SetText(ns.Code("{c:" .. c.name .. "}"))
                r:Show()
            else
                r:Hide()
            end
        end
    end
    list:SetScript("OnMouseWheel", function(_, delta) scroll = scroll - delta Render() end)

    local add = UI.Button(p, 130, "+  " .. L["Placeholder"], function()
        local all, n = Custom(), 1
        while Placeholders.FindCustom(L["name"] .. n) do n = n + 1 end
        all[#all + 1] = { name = L["name"] .. n, value = "" }
        scroll = #all
        Render()
        for _, r in ipairs(cRows) do
            if r.entry == all[#all] then r.name:SetFocus() r.name:HighlightText() end
        end
    end, 22)
    add:SetPoint("TOPRIGHT", 0, CY + 4)

    local note = UI.Hint(p, L["Use them in templates. Refresh rewrites every macro named exactly like a template, general or character, with the current values; other macros are never changed."], W)
    note:SetPoint("BOTTOMLEFT", 0, 0)
    note:SetSpacing(2)

    Placeholders.RefreshPage = function()
        if not p:IsVisible() then return end
        for _, r in ipairs(roleRows) do r:Refresh() end
        for n, t in ipairs(trinkets) do
            local name = Placeholders.Trinket(n)
            t.found:SetText(name and ("= " .. ns.Colorize(HEX.good, name)) or ns.Muted(L["(nothing in this slot)"]))
        end
        Render()
    end
end

App:AddPage({
    key = "placeholders", section = "macros", label = L["Placeholders"], order = 100,
    Build = function(_, frame) BuildPage(frame) end,
    Refresh = function() if Placeholders.RefreshPage then Placeholders.RefreshPage() end end,
})

ns.RegisterReset({ key = "gear", order = 76, label = L["Weapon roles"],
    desc = L["W1 / W2 back to dagger / any weapon, picked anew from what you carry."],
    reset = function() ns.Char().placeholders = nil end })
ns.RegisterReset({ key = "customPlaceholders", order = 87, label = L["Own placeholders"], accountWide = true,
    desc = L["Deletes your own placeholders {c:...}."],
    reset = function()
        local a = ns.Acct()
        if a.placeholders then a.placeholders.custom = nil end
    end })
