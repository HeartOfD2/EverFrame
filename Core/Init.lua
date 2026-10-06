-- ---------------------------------------------------------------------------
-- EverFrame: namespace, event dispatch, internal messages and the
-- module registry. Every other file builds on what this one sets up.
-- ---------------------------------------------------------------------------
local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "EverFrame"
ns.LOCALE = GetLocale and GetLocale() or "enUS"

do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = getMeta and getMeta(ADDON, "Version")
    -- the packager fills in the real version; a checkout shows "dev"
    ns.VERSION = (type(v) == "string" and v ~= "" and not v:find("^@")) and v or "dev"
end

-- Localization: English text is the key. Missing translations fall back to it.
ns.L = setmetatable({}, { __index = function(_, k) return k end })

-- ---------------------------------------------------------------------------
-- Errors inside one handler must not stop the others
-- ---------------------------------------------------------------------------
local function Report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) else print(err) end
end

local function SafeCall(fn, ...)
    local n = select("#", ...)
    local args = { ... }
    local ok, err = pcall(function() return fn(unpack(args, 1, n)) end)
    if not ok then Report(err) end
end
ns.SafeCall = SafeCall

-- ---------------------------------------------------------------------------
-- Game events: any number of subscribers per event, one shared frame
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventSubs = {}

function ns.RegisterEvent(event, fn)
    local list = eventSubs[event]
    if not list then
        -- unknown events (other client generations) are skipped quietly
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventSubs[event] = list
    end
    list[#list + 1] = fn
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventSubs[event]
    if not list then return end
    for i = 1, #list do SafeCall(list[i], event, ...) end
end)

-- unit events get a frame of their own so the game filters the unit for us
function ns.RegisterUnitEvent(event, unit, fn)
    local f = CreateFrame("Frame")
    if not pcall(f.RegisterUnitEvent, f, event, unit) then return false end
    f:SetScript("OnEvent", function(_, ev, ...) SafeCall(fn, ev, ...) end)
    return true
end

-- ---------------------------------------------------------------------------
-- Internal messages between the files (settings changed, reset, ...)
-- ---------------------------------------------------------------------------
local messageSubs = {}
function ns.On(message, fn)
    messageSubs[message] = messageSubs[message] or {}
    table.insert(messageSubs[message], fn)
end
function ns.Fire(message, ...)
    local list = messageSubs[message]
    if not list then return end
    for i = 1, #list do SafeCall(list[i], ...) end
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------
local PREFIX = "|cffffd140" .. ns.TITLE .. ":|r "
function ns.Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    print(PREFIX .. msg)
end

-- ---------------------------------------------------------------------------
-- Player info (class may only be final at PLAYER_LOGIN on some clients)
-- ---------------------------------------------------------------------------
local function ReadPlayer()
    local _, class = UnitClass("player")
    ns.playerClass = class
    if UnitRace then
        local _, race = UnitRace("player")
        ns.playerRace = race
    end
end
ReadPlayer()

-- ---------------------------------------------------------------------------
-- Modules: optional feature packs. A module may be limited to classes; it
-- is active when the class fits and the player hasn't switched it off.
-- ---------------------------------------------------------------------------
ns.modules, ns.moduleOrder = {}, {}

local Module = {}
Module.__index = Module

function Module:IsClassAllowed()
    if not self.classes then return true end
    return self.classes[ns.playerClass or ""] and true or false
end

-- per-character module settings live in the character DB
function Module:Settings()
    local all = ns.Char().modules
    all[self.key] = all[self.key] or {}
    return all[self.key]
end

function Module:IsEnabledSetting()
    if not ns.Char then return self.defaultEnabled ~= false end
    local s = ns.Char().modules[self.key]
    if s and s.enabled ~= nil then return s.enabled end
    return self.defaultEnabled ~= false
end

function Module:IsActive()
    return ns.ready and self:IsClassAllowed() and self:IsEnabledSetting() or false
end

function Module:SetEnabled(on)
    self:Settings().enabled = on and true or false
    ns.RefreshModules()
end

function ns.NewModule(key, def)
    local m = setmetatable(def or {}, Module)
    m.key = key
    ns.modules[key] = m
    ns.moduleOrder[#ns.moduleOrder + 1] = key
    return m
end

-- (re)evaluate which modules run; called at login and after toggles/resets
function ns.RefreshModules()
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        local active = m:IsActive()
        if active and not m.started then
            m.started = true
            if m.OnEnable then SafeCall(m.OnEnable, m) end
        end
        if active ~= m.wasActive then
            m.wasActive = active
            if m.OnActiveChanged then SafeCall(m.OnActiveChanged, m, active) end
        end
    end
    ns.Fire("MODULES_CHANGED")
end

-- ---------------------------------------------------------------------------
-- Lifecycle
--   ADDON_LOADED (ours)  saved variables exist   -> "DB_READY"
--   PLAYER_LOGIN         the world is about      -> "LOGIN", modules start
-- ---------------------------------------------------------------------------
ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON or ns.dbReady then return end
    ns.dbReady = true
    ns.InitDatabase()
    ns.Fire("DB_READY")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    if not ns.dbReady then   -- should not happen, but never run without settings
        ns.dbReady = true
        ns.InitDatabase()
        ns.Fire("DB_READY")
    end
    ReadPlayer()
    ns.ready = true
    ns.Fire("LOGIN")
    ns.RefreshModules()
end)
