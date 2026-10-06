-- ---------------------------------------------------------------------------
-- Saved settings.
--   EverFrameDB       account-wide: notes, minimap button, templates
--   EverFrameCharDB   per character: HUD, layout, cooldowns, texts,
--                     modules (each character has its own class)
-- Reset categories are registered here; the options' Reset tab lists them.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local DB_VERSION = 1

local function CharDefaults()
    return {
        v = DB_VERSION,
        hud = { locked = true, scale = 1, centerX = false, pos = nil, hide = "never", holdKey = "ALT" },
        layout = { order = nil, hidden = {} },
        style = { frame = {}, parts = {} },
        cooldowns = { order = nil, hidden = {}, shown = {}, bar = {}, custom = {} },
        text = { health = "{cur}", power = "{cur}" },
        range = { interval = 0.1 },
        modules = {},
        ui = {},
    }
end

local function AcctDefaults()
    return {
        v = DB_VERSION,
        notes = nil,          -- created by the notes tool on first use
        minimap = { angle = 200, hide = false },
    }
end

-- fill in what is missing, keep what the player set
local function Merge(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = ns.CopyTable(v)
        elseif type(v) == "table" and type(saved[k]) == "table" then
            Merge(saved[k], v)
        end
    end
    return saved
end

function ns.InitDatabase()
    if type(EverFrameDB) ~= "table" then EverFrameDB = {} end
    if type(EverFrameCharDB) ~= "table" then EverFrameCharDB = {} end
    Merge(EverFrameDB, AcctDefaults())
    Merge(EverFrameCharDB, CharDefaults())
    -- 1.0 had a single "hide out of combat" switch
    local h = EverFrameCharDB.hud
    if h.hideOOC ~= nil then
        if h.hideOOC then h.hide = "combat" end
        h.hideOOC = nil
    end
end

-- before ADDON_LOADED (only during file load) the defaults stand in
local fallbackChar, fallbackAcct
function ns.Char()
    if type(EverFrameCharDB) == "table" and ns.dbReady then return EverFrameCharDB end
    fallbackChar = fallbackChar or CharDefaults()
    return fallbackChar
end
function ns.Acct()
    if type(EverFrameDB) == "table" and ns.dbReady then return EverFrameDB end
    fallbackAcct = fallbackAcct or AcctDefaults()
    return fallbackAcct
end

-- ---------------------------------------------------------------------------
-- Reset categories: { key, label, desc, order, accountWide, danger, reset() }
-- ---------------------------------------------------------------------------
ns.resetCategories = {}

function ns.RegisterReset(def)
    table.insert(ns.resetCategories, def)
    table.sort(ns.resetCategories, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

-- resets the given keys, then tells every part of the addon to re-read
function ns.ResetCategories(keys)
    local done = {}
    for _, def in ipairs(ns.resetCategories) do
        if keys[def.key] then
            def.reset()
            done[#done + 1] = def.label
        end
    end
    if #done > 0 then ns.Fire("SETTINGS_RESET", keys) end
    return done
end

do
    local D = CharDefaults()
    ns.RegisterReset({ key = "position", order = 10, label = L["Position and scale"],
        desc = L["Frame position, scale, lock and horizontal centering."],
        reset = function()
            local h = ns.Char().hud
            h.pos, h.scale, h.locked, h.centerX = nil, D.hud.scale, D.hud.locked, D.hud.centerX
        end })
    ns.RegisterReset({ key = "layout", order = 20, label = L["Layout"],
        desc = L["Order, visibility and look of the frame parts."],
        reset = function()
            ns.Char().layout = ns.CopyTable(D.layout)
            ns.Char().style = ns.CopyTable(D.style)
        end })
    ns.RegisterReset({ key = "cooldowns", order = 30, label = L["Cooldown bars"],
        desc = L["Which cooldowns show, their bar and order. Your own entries stay."],
        reset = function()
            local c = ns.Char().cooldowns
            c.order, c.hidden, c.shown, c.bar = nil, {}, {}, {}
        end })
    ns.RegisterReset({ key = "customCooldowns", order = 31, label = L["Own cooldown entries"],
        desc = L["Removes the items and spells you added yourself."],
        reset = function() ns.Char().cooldowns.custom = {} end })
    ns.RegisterReset({ key = "texts", order = 40, label = L["Texts"],
        desc = L["Health and resource text formats."],
        reset = function() ns.Char().text = ns.CopyTable(D.text) end })
    ns.RegisterReset({ key = "visibility", order = 50, label = L["Visibility"],
        desc = L["When the frame hides and the hold-to-show key."],
        reset = function()
            local h = ns.Char().hud
            h.hide, h.holdKey = D.hud.hide, D.hud.holdKey
        end })
    ns.RegisterReset({ key = "range", order = 60, label = L["Range display"],
        desc = L["How often the range is checked."],
        reset = function() ns.Char().range = ns.CopyTable(D.range) end })
    ns.RegisterReset({ key = "modules", order = 70, label = L["Modules"],
        desc = L["Module on/off switches and module settings."],
        reset = function() ns.Char().modules = {} end })
    ns.RegisterReset({ key = "minimap", order = 80, label = L["Minimap button"], accountWide = true,
        desc = L["Position and visibility of the minimap button."],
        reset = function() ns.Acct().minimap = ns.CopyTable(AcctDefaults().minimap) end })
    ns.RegisterReset({ key = "windows", order = 85, label = L["Window positions"], accountWide = true,
        desc = L["Position and size of the app window and the target popup."],
        reset = function()
            ns.Acct().app = nil
            local n = ns.Acct().notes
            if type(n) == "table" then n.popup = nil end
        end })
    ns.RegisterReset({ key = "notes", order = 90, label = L["All notes"], accountWide = true, danger = true,
        desc = L["Deletes every notebook and player note for good."],
        reset = function()
            -- only the notes: popup position, size, lock, the view switches and
            -- the sticky note settings stay
            local n = ns.Acct().notes
            if type(n) ~= "table" then return end
            ns.Acct().notes = { popup = n.popup, popupOff = n.popupOff, addBarOff = n.addBarOff, page = n.page,
                                sticky = n.sticky }
        end })
end

