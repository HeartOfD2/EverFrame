-- ---------------------------------------------------------------------------
-- Rogue module: poison tracker, Slice and Dice timer, weapon swap macros and
-- rogue macro templates. Active on rogues only (and only while switched on).
-- Poisons are identified by item ID and their names are read off the items,
-- so everything works in any client language.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local Rogue = ns.NewModule("rogue", {
    title = L["Rogue"],
    desc = L["Poison tracker with one-click apply, Slice and Dice timer, weapon swap macros and macro templates."],
    classes = { ROGUE = true },
    classHint = L["only for rogues"],
})
ns.Rogue = Rogue

-- poison types and their item IDs, lowest rank first
Rogue.POISONS = {
    { key = "instant",   ids = { 6947, 6949, 6950, 8926, 8927, 8928 } },
    { key = "deadly",    ids = { 2892, 2893, 8984, 8985, 20844, 22053, 22054 } },
    { key = "wound",     ids = { 10918, 10920, 10921, 10922 } },
    { key = "mindnumb",  ids = { 5237, 6951, 9186 } },
    { key = "crippling", ids = { 3775, 3776 } },
}
Rogue.POISON_ICON = "Interface\\Icons\\Trade_BrewPoison"
Rogue.HANDS = { MH = 16, OH = 17 }

local KEY_OF_ITEM, RANK_OF_ITEM = {}, {}
for _, p in ipairs(Rogue.POISONS) do
    for rank, id in ipairs(p.ids) do
        KEY_OF_ITEM[id], RANK_OF_ITEM[id] = p.key, rank
    end
end

function Rogue:PoisonKeyOfItem(id) return KEY_OF_ITEM[id] end

function Rogue:Settings()
    local s = ns.Char().modules.rogue
    if not s then
        s = {}
        ns.Char().modules.rogue = s
    end
    s.poison = s.poison or {}
    return s
end

-- ---------------------------------------------------------------------------
-- Names: from the items in the bags, else from the client's item cache
-- ---------------------------------------------------------------------------
local baseName = {}   -- key -> localized name without the rank numeral

local function StripRank(name) return (name:gsub("%s+[IVXLCDM]+$", "")) end

function Rogue:RefreshPoisonNames()
    wipe(baseName)
    ns.ForEachBagItem(function(id, name)
        local key = KEY_OF_ITEM[id]
        if key and name then baseName[key] = StripRank(name) end
    end)
    for _, p in ipairs(self.POISONS) do
        if not baseName[p.key] then
            local n = ns.ItemName(p.ids[1])
            if n then baseName[p.key] = StripRank(n) end
        end
    end
end

function Rogue:PoisonName(key)
    if not key then return L["Best available"] end
    return baseName[key] or key
end

function Rogue:PoisonIcon(key)
    for _, p in ipairs(self.POISONS) do
        if p.key == key then return ns.ItemIcon(p.ids[1]) or self.POISON_ICON end
    end
    return self.POISON_ICON
end

-- highest rank in the bags of one type (nil = of any type): name, itemID
function Rogue:FindPoison(key)
    local bestName, bestID, bestRank
    ns.ForEachBagItem(function(id, name)
        local k = KEY_OF_ITEM[id]
        if k and (not key or k == key) then
            local rank = RANK_OF_ITEM[id]
            if not bestRank or rank > bestRank or (rank == bestRank and id > bestID) then
                bestName, bestID, bestRank = name or ns.ItemName(id), id, rank
            end
        end
    end)
    return bestName, bestID
end

-- the player's pick per hand (nil = whatever fits best)
function Rogue:Choice(hand) return self:Settings().poison[hand] end
function Rogue:SetChoice(hand, key)
    self:Settings().poison[hand] = key
    ns.Fire("ROGUE_POISON_CHOICE", hand)
end

-- what a hand gets: the pick, else what was last seen on that weapon
Rogue.lastSeen = {}
function Rogue:EffectiveKey(hand) return self:Choice(hand) or self.lastSeen[hand] end

-- what the weapon macros use: the pick, else Instant (main) / Crippling (off hand)
local MACRO_DEFAULT = { MH = "instant", OH = "crippling" }
function Rogue:MacroPoison(hand)
    local key = self:Choice(hand) or MACRO_DEFAULT[hand]
    local name, id = self:FindPoison(key)
    return name, id, key
end

-- ---------------------------------------------------------------------------
-- Settings shown in the Modules tab
-- ---------------------------------------------------------------------------
local UI = ns.UI
function Rogue:BuildOptions(box, width)
    local rows = {}
    local function Row(label, field, y, tip)
        local r = UI.CheckRow(box, label,
            function() return Rogue:Settings()[field] ~= false end,
            function(v) Rogue:Settings()[field] = v and true or false end, width)
        r:SetPoint("TOPLEFT", 0, y)
        if tip then UI.Tooltip(r, { label, tip }) end
        rows[#rows + 1] = r
    end
    Row(L["Warn when a poison runs low (5 minutes or 5 charges)"], "poisonWarn", 0)
    function Rogue:RefreshOptions()
        for _, r in ipairs(rows) do
            r:Refresh()
            r:SetDisabled(not Rogue:IsActive())   -- the module is switched off
        end
    end
    return 22
end

ns.RegisterReset({ key = "poisons", order = 75, label = L["Poison choices"],
    IsVisible = function() return Rogue:IsClassAllowed() end,
    desc = L["The poison picked for each hand goes back to \"best available\"."],
    reset = function()
        local s = ns.Char().modules.rogue
        if s then s.poison = {} end
    end })

-- ---------------------------------------------------------------------------
-- Macro templates ({s:ID} = spell name, {p:MH}/{p:OH} = poison for that hand)
-- ---------------------------------------------------------------------------
ns.Macros.RegisterTemplates({
    key = "rogue",
    title = L["ROGUE TEMPLATES"],
    groupName = L["Rogue"],
    IsActive = function() return Rogue:IsActive() end,
    Fill = function(body)
        return (body:gsub("{p:(%u%u)}", function(hand)
            local name, id = Rogue:FindPoison(Rogue:EffectiveKey(hand))
            return id and ("item:" .. id) or Rogue:PoisonName(Rogue:EffectiveKey(hand) or "instant")
        end))
    end,
    list = {
        { name = L["Stealth Opener"], desc = L["Stealth, then Cheap Shot"], body = "#showtooltip\n/cast [nostealth] {s:1784}; {s:1833}" },
        { name = L["Builder"], desc = L["Sinister Strike + auto attack"], body = "#showtooltip\n/startattack\n/cast {s:1752}" },
        { name = L["Gouge"], desc = L["Stops auto attack first"], body = "#showtooltip\n/stopattack\n/cast {s:1776}" },
        { name = L["Kick Mouseover"], desc = L["Mouseover, else target"], body = "#showtooltip {s:1766}\n/cast [@mouseover,harm,nodead][] {s:1766}" },
        { name = L["Blind Mouseover"], desc = L["Mouseover, else target"], body = "#showtooltip {s:2094}\n/cast [@mouseover,harm,nodead][] {s:2094}" },
        { name = L["Sap Mouseover"], desc = L["Mouseover, else target"], body = "#showtooltip {s:6770}\n/cast [@mouseover,harm,nodead][] {s:6770}" },
        { name = L["Distract Cursor"], desc = L["Lands at the mouse cursor"], body = "#showtooltip\n/cast [@cursor] {s:1725}" },
        { name = L["Vanish"], desc = L["Stops auto attack first"], body = "#showtooltip\n/stopattack\n/cast {s:1856}" },
        { name = L["Burst"], desc = L["Both trinkets + Adrenaline Rush"], body = "#showtooltip {s:13750}\n/use 13\n/use 14\n/cast {s:13750}" },
        { name = L["Poison MH"], desc = L["Apply main-hand poison"], body = "#showtooltip\n/use {p:MH}\n/use 16" },
        { name = L["Poison OH"], desc = L["Apply off-hand poison"], body = "#showtooltip\n/use {p:OH}\n/use 17" },
    },
})

-- icon picker: rogue abilities and poisons first
do
    local spells = { 1752, 53, 2098, 5171, 1784, 1776, 1766, 2983, 5277, 1856, 2094, 6770, 1833, 408,
        8676, 703, 1943, 8647, 1966, 1725, 921, 1804, 2836, 1842, 14251, 13877, 13750,
        14177, 14278, 16511, 14183, 14185, 2764 }
    ns.Rogue.FEATURED_SPELLS = spells
    function Rogue:OnEnable()
        for _, id in ipairs(spells) do table.insert(ns.Macros.featuredSpells, id) end
        for _, p in ipairs(Rogue.POISONS) do table.insert(ns.Macros.featuredItems, p.ids[1]) end
        Rogue:RefreshPoisonNames()
    end
end

ns.RegisterEvent("BAG_UPDATE", function() if Rogue:IsActive() then Rogue:RefreshPoisonNames() end end)
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function() if Rogue:IsActive() then Rogue:RefreshPoisonNames() end end)
