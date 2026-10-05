-- ---------------------------------------------------------------------------
-- Cooldown bars: up to five rows of icons (seven per row) for the class
-- package, your own race's racials, module entries (e.g. Slice and Dice) and
-- items or spells you add yourself (potions, bandages, trinkets ...).
-- Swipes start from cast events (their spell IDs are not secret) and take
-- the game's cooldown through the secret-safe Duration path where it exists.
-- Abilities with a buff (Sprint, Evasion ...) first count down the buff with
-- an accent border, then show the real cooldown.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local HUD = ns.HUD

local IGAP = 4
local BARS = 5
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local CD = {
    entries = {},      -- key -> entry
    byCast = {},       -- spellID -> entry
    byName = {},       -- localized spell name -> entry
    specials = {},     -- module entries, in registration order
    BARS = BARS,
}
ns.Cooldowns = CD

local function Settings() return ns.Char().cooldowns end

-- look of all cooldown bars (shared style "cooldowns")
local function IconSize() return HUD:Get("cooldowns", "iconSize") or 28 end

-- icons per bar: as many as fit in one row of the frame
function CD.PerBar()
    return math.max(1, math.floor((HUD.WIDTH + IGAP) / (IconSize() + IGAP)))
end

-- ---------------------------------------------------------------------------
-- Icons. Every entry runs a small state machine:
--   ready      plain icon, usable
--   buff       its buff is running (accent frame, the swipe counts the buff)
--   cooldown   the game's cooldown is running
-- When a cooldown ends, an accent ring fades out around the icon.
-- ---------------------------------------------------------------------------
local Apply   -- puts the game's current cooldown of an entry on its swipe (below)

local function Paint(e)
    local o, st = e.frame, e.state
    local c = (st == "buff") and T.accent or T.hudLine
    o.border:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    o.halo:SetShown(st == "buff")
    -- optional: ready icons step back, running ones stand out
    if e.kind ~= "special" then
        o:SetAlpha((st == "ready" and HUD:Get("cooldowns", "dimReady")) and 0.4 or 1)
    end
end

-- to change state from outside (modules driving their own entry)
function CD.SetState(e, st)
    e.state = st
    e.frame.running = (st ~= "ready")
    Paint(e)
end

local function Finish(e)
    if e.state == "buff" and not e.itemID then
        -- the buff is over: now the ability's own cooldown
        CD.SetState(e, "cooldown")
        Apply(e, e.castID)
        return
    end
    local was = e.state
    e.lockoutMode = nil
    CD.SetState(e, "ready")
    if was == "cooldown" then e.frame.readyRing:Play() end
end

local function MakeIcon(entry)
    local o = CreateFrame("Frame", nil, HUD.frame)
    o:SetSize(IconSize(), IconSize())
    o.halo = o:CreateTexture(nil, "BACKGROUND", nil, -8)
    o.halo:SetPoint("TOPLEFT", -3, 3)
    o.halo:SetPoint("BOTTOMRIGHT", 3, -3)
    ns.Color(o.halo, T.accent, 0.25)
    o.border = o:CreateTexture(nil, "BACKGROUND", nil, -7)
    o.border:SetPoint("TOPLEFT", -1, 1)
    o.border:SetPoint("BOTTOMRIGHT", 1, -1)
    o.icon = o:CreateTexture(nil, "ARTWORK")
    o.icon:SetAllPoints()
    o.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    o.sheen = o:CreateTexture(nil, "ARTWORK", nil, 1)
    o.sheen:SetPoint("TOPLEFT")
    o.sheen:SetPoint("TOPRIGHT")
    o.sheen:SetHeight(1)
    o.sheen:SetColorTexture(1, 1, 1, 0.12)
    o.cd = CreateFrame("Cooldown", nil, o, "CooldownFrameTemplate")
    o.cd:SetAllPoints()
    o.cd:SetHideCountdownNumbers(false)
    o.cd:SetDrawEdge(true)
    if o.cd.SetSwipeColor then o.cd:SetSwipeColor(0, 0, 0, 0.75) end
    if ns.FONT and o.cd.GetCountdownFontString then
        local ok, fs = pcall(o.cd.GetCountdownFontString, o.cd)
        if ok and fs then ns.ApplyFont(fs, 13, "OUTLINE") end
    end
    -- short countdowns ("2m", then seconds) fit a small icon better than "1:47"
    if o.cd.SetCountdownAbbrevThreshold then pcall(o.cd.SetCountdownAbbrevThreshold, o.cd, 60) end
    -- ready ring: an accent outline just outside the icon that fades away
    local ring = CreateFrame("Frame", nil, o)
    ring:SetPoint("TOPLEFT", -3, 3)
    ring:SetPoint("BOTTOMRIGHT", 3, -3)
    ring:SetFrameLevel(o.cd:GetFrameLevel() + 3)
    ns.Skin(ring, { 0, 0, 0, 0 }, T.accent)
    ring:SetAlpha(0)
    local fade = ring:CreateAnimationGroup()
    local a = fade:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetDuration(0.9)
    a:SetSmoothing("OUT")
    o.readyRing = fade
    o.cd:SetScript("OnCooldownDone", function()
        if entry.OnCooldownDone then return entry:OnCooldownDone(o) end
        Finish(entry)
    end)
    o:Hide()
    o.entry = entry
    entry.frame = o
    entry.state = "ready"
    Paint(entry)
    return o
end

-- the module side (Slice and Dice) uses this for its active look
function CD.SetActive(o, on)
    if o.entry then
        o.entry.state = on and "buff" or "ready"
        Paint(o.entry)
    end
end

-- ---------------------------------------------------------------------------
-- Entries
-- ---------------------------------------------------------------------------
local function AddEntry(e)
    CD.entries[e.key] = e
    if not e.frame then MakeIcon(e) end
    if e.ids and not e.noCasts then
        for _, id in ipairs(e.ids) do CD.byCast[id] = e end
    end
    return e
end

function CD:RefreshIcon(e)
    local tex
    if e.itemID then tex = ns.ItemIcon(e.itemID)
    elseif e.GetIcon then tex = e:GetIcon()
    elseif e.ids and e.ids[1] then tex = ns.SpellIcon(e.ids[1]) end
    e.frame.icon:SetTexture(tex or FALLBACK_ICON)
end

-- module entries (e.g. Slice and Dice): def.key, def.ids, def.IsAvailable,
-- def.GetName, def.noCasts (the module drives the icon itself)
function CD:RegisterSpecial(def)
    def.kind = "special"
    table.insert(self.specials, def)
    AddEntry(def)
    self:RefreshIcon(def)
    return def
end

function CD:EntryName(e)
    if e.GetName then return e:GetName() end
    if e.itemID then return ns.ItemName(e.itemID) or (L["Item"] .. " " .. e.itemID) end
    return ns.SpellName(e.ids and e.ids[1]) or (L["Spell"] .. " " .. tostring(e.ids and e.ids[1]))
end

-- can it show at all: items always, specials ask, spells once learned
function CD:IsAvailable(e)
    if e.itemID then return true end
    if e.IsAvailable then return e:IsAvailable() and true or false end
    return ns.KnowsAny(e.ids)
end

-- builds the class, racial and custom entries (class/race are known from login)
local built = false
function CD:Build()
    if not built then
        built = true
        for _, s in ipairs(ns.ClassPack().cooldowns or {}) do
            AddEntry({ key = s.key, ids = s.ids, dur = s.dur, lockout = s.lockout, kind = "class" })
        end
        for _, s in ipairs(ns.Racials) do
            AddEntry({ key = s.key, ids = s.ids, dur = s.dur, kind = "racial" })
        end
    end
    for _, key in ipairs(Settings().custom) do self:CreateCustom(key) end
    -- custom entries no longer in the list (after a reset) go away
    for key, e in pairs(self.entries) do
        if e.kind == "custom" and not ns.IndexOf(Settings().custom, key) then self:DropCustom(key) end
    end
    self:RefreshNames()
    for _, e in pairs(self.entries) do self:RefreshIcon(e) end
end

-- localized names of all spell entries, so a cast reporting another ID than
-- the spellbook (racials on this client) still finds its icon
function CD:RefreshNames()
    wipe(self.byName)
    for _, e in pairs(self.entries) do
        if e.ids and not e.noCasts and not e.itemID then
            local n = ns.SpellName(e.ids[1])
            if n then self.byName[n] = e end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Spellbook: abilities with a cooldown that no package lists (new ones after
-- a patch, talents ...) are read from the spellbook with their base cooldown.
-- They join the list switched off; the class package stays the default set.
-- ---------------------------------------------------------------------------
local MIN_BOOK_CD = 2000   -- ms; shorter is only the global cooldown

-- calls fn(spellID, name, isPassive) for every learned spellbook entry;
-- returns which API it used (nil: none)
function ns.ForEachSpellbookSpell(fn)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
        local ok, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        for line = 1, (ok and lines or 0) do
            local okL, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
            if okL and info and info.itemIndexOffset and info.numSpellBookItems then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local okI, item = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                    if okI and item and item.spellID and item.itemType == spellType then
                        fn(item.spellID, item.name, item.isPassive)
                    end
                end
            end
        end
        return "C_SpellBook"
    end
    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
                local kind, id = GetSpellBookItemInfo(i, "spell")
                if kind == "SPELL" and id then
                    local passive = IsPassiveSpell and IsPassiveSpell(i, "spell")
                    fn(id, ns.SpellName(id), passive)
                end
            end
        end
        return "GetSpellBookItemInfo"
    end
    return nil
end

CD.bookKeys = {}
-- in combat the base cooldowns can be secret: scan after the fight instead;
-- a secret answer outside combat keeps what was found before
function CD:ScanSpellbook()
    if not GetSpellBaseCooldown then return end
    if UnitAffectingCombat("player") then
        self.scanPending = true
        return
    end
    self.scanPending = nil
    -- names the packages already cover (any rank)
    local covered = {}
    for _, e in pairs(self.entries) do
        if e.kind ~= "book" and e.ids and not e.itemID then
            for _, id in ipairs(e.ids) do
                local n = ns.SpellName(id)
                if n then covered[n] = true end
            end
        end
    end
    local found, names, sawSecret = {}, {}, false
    self.bookMode = ns.ForEachSpellbookSpell(function(id, name, passive)
        if passive or not name or covered[name] then return end
        local ok, ms = pcall(GetSpellBaseCooldown, id)
        if ok and ns.IsSecret(ms) then sawSecret = true return end
        if not ok or type(ms) ~= "number" or ms < MIN_BOOK_CD then return end
        if not found[name] then
            found[name] = {}
            names[#names + 1] = name
        end
        table.insert(found[name], id)
    end)
    local before = sawSecret and { unpack(self.bookKeys) } or nil
    wipe(self.bookKeys)
    for _, name in ipairs(names) do
        local ids = found[name]
        table.sort(ids)
        local key = "book:" .. ids[1]
        local e = self.entries[key]
        if e then
            for _, id in ipairs(ids) do
                if not ns.IndexOf(e.ids, id) then table.insert(e.ids, id) end
            end
            table.sort(e.ids)
            AddEntry(e)
        else
            e = AddEntry({ key = key, ids = ids, kind = "book" })
            self:RefreshIcon(e)
            self.byName[name] = e
        end
        self.bookKeys[#self.bookKeys + 1] = key
    end
    for _, key in ipairs(before or {}) do
        if not ns.IndexOf(self.bookKeys, key) then self.bookKeys[#self.bookKeys + 1] = key end
    end
end

-- ---------------------------------------------------------------------------
-- Order and bars
-- ---------------------------------------------------------------------------
function CD:Order()
    local defaults = {}
    for _, s in ipairs(self.specials) do defaults[#defaults + 1] = s.key end
    for _, s in ipairs(ns.ClassPack().cooldowns or {}) do defaults[#defaults + 1] = s.key end
    for _, s in ipairs(ns.Racials) do
        if ns.KnowsAny(s.ids) then defaults[#defaults + 1] = s.key end
    end
    for _, k in ipairs(self.bookKeys) do defaults[#defaults + 1] = k end
    for _, k in ipairs(Settings().custom) do defaults[#defaults + 1] = k end
    local valid = {}
    for _, k in ipairs(defaults) do valid[k] = self.entries[k] ~= nil end
    local order, seen = {}, {}
    local saved = Settings().order
    if type(saved) == "table" then
        for _, k in ipairs(saved) do
            if valid[k] and not seen[k] then seen[k] = true order[#order + 1] = k end
        end
    end
    for _, k in ipairs(defaults) do
        if valid[k] and not seen[k] then seen[k] = true order[#order + 1] = k end
    end
    Settings().order = order
    return order
end

function CD:Bar(key) return Settings().bar[key] or 1 end
-- spellbook finds are off until switched on, everything else on until switched off
local function IsBookKey(key) return key:sub(1, 5) == "book:" end
function CD:IsHidden(key)
    if IsBookKey(key) then return not Settings().shown[key] end
    return Settings().hidden[key] and true or false
end

-- counts toward a bar's limit: available and not switched off
function CD:IsShownEntry(e)
    return not self:IsHidden(e.key) and self:IsAvailable(e)
end

-- at most PerBar() icons per bar: what doesn't fit moves to the first bar with room
function CD:Normalize()
    local count, PER_BAR = {}, CD.PerBar()
    for _, k in ipairs(self:Order()) do
        local e = self.entries[k]
        if e and self:IsShownEntry(e) then
            local bar = self:Bar(k)
            if (count[bar] or 0) >= PER_BAR then
                for b = 1, BARS do
                    if (count[b] or 0) < PER_BAR then bar = b break end
                end
                Settings().bar[k] = (bar ~= 1) and bar or nil
            end
            count[bar] = (count[bar] or 0) + 1
        end
    end
    return count
end

function CD:BarCount(bar) return self:Normalize()[bar] or 0 end

-- sorted for the options list: by bar, then order
function CD:List()
    local count = self:Normalize()
    local list = {}
    for pos, k in ipairs(self:Order()) do
        local e = self.entries[k]
        local learnable = e and (e.kind == "class" or e.kind == "racial" or e.kind == "book")
        if e and (not e.IsRelevant or e:IsRelevant()) and not (learnable and not self:IsAvailable(e)) then
            e.pos, e.bar, e.shownEntry = pos, self:Bar(k), self:IsShownEntry(e)
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        if a.bar ~= b.bar then return a.bar < b.bar end
        return a.pos < b.pos
    end)
    return list, count
end

function CD:SetHidden(key, hidden)
    if IsBookKey(key) then
        Settings().shown[key] = (not hidden) or nil
    else
        Settings().hidden[key] = hidden and true or nil
    end
    HUD:ApplyLayout()
end

-- returns false + reason when the target bar is full
function CD:SetBar(key, bar)
    local e = self.entries[key]
    if not e then return false end
    if self:Bar(key) ~= bar and self:IsShownEntry(e) and self:BarCount(bar) >= CD.PerBar() then
        return false, L["Bar %d is full (%d cooldowns at most)."]:format(bar, CD.PerBar())
    end
    Settings().bar[key] = (bar ~= 1) and bar or nil
    HUD:ApplyLayout()
    return true
end

-- move within its own bar: swap with the nearest entry on the same bar
function CD:Move(key, dir)
    local order = self:Order()
    local i = ns.IndexOf(order, key)
    if not i then return end
    local bar, j = self:Bar(key), i + dir
    while order[j] and self:Bar(order[j]) ~= bar do j = j + dir end
    if not order[j] then return end
    order[i], order[j] = order[j], order[i]
    HUD:ApplyLayout()
end

-- ---------------------------------------------------------------------------
-- HUD elements "cd1" .. "cd5": each places the icons of its own bar, centered
-- ---------------------------------------------------------------------------
local function PlaceBar(bar, y)
    CD:Normalize()
    local visible = {}
    for _, k in ipairs(CD:Order()) do
        local e = CD.entries[k]
        if e and CD:Bar(k) == bar then
            if CD:IsShownEntry(e) then visible[#visible + 1] = e else e.frame:Hide() end
        end
    end
    local ICON = IconSize()
    local perRow = CD.PerBar()
    for i, e in ipairs(visible) do
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        local rowCount = math.min(perRow, #visible - row * perRow)
        local x0 = (HUD.WIDTH - (rowCount * ICON + (rowCount - 1) * IGAP)) / 2
        e.frame:ClearAllPoints()
        e.frame:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", x0 + col * (ICON + IGAP), y - row * (ICON + IGAP))
        e.frame:Show()
    end
    if #visible == 0 then return 0 end
    local rows = math.ceil(#visible / perRow)
    return rows * ICON + (rows - 1) * IGAP
end

local function HideBar(bar)
    for k, e in pairs(CD.entries) do
        if CD:Bar(k) == bar then e.frame:Hide() end
    end
end

HUD:RegisterSharedStyle("cooldowns", { iconSize = 28, numbers = true, dimReady = false }, function()
    local size, numbers = IconSize(), HUD:Get("cooldowns", "numbers") ~= false
    for _, e in pairs(CD.entries) do
        e.frame:SetSize(size, size)
        e.frame.cd:SetHideCountdownNumbers(not numbers)
        Paint(e)
    end
end)

for b = 1, BARS do
    HUD:Register({
        key = "cd" .. b, order = 60 + b,
        label = L["Cooldown bar %d"]:format(b),
        cooldownBar = b,
        Place = function(_, y) return PlaceBar(b, y) end,
        HideAll = function() HideBar(b) end,
    })
end

-- ---------------------------------------------------------------------------
-- Swipes: what the game knows about a cooldown, without touching secrets
-- ---------------------------------------------------------------------------
-- the game's cooldown of a spell or item as (kind, a, b):
--   "object", durationObject      secret-safe, straight to the cooldown frame
--   "times", start, duration      plain or secret numbers
local function Source(e, id)
    if e.itemID then
        local getter = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        if getter then
            local ok, start, dur = pcall(getter, e.itemID)
            -- (a secret start is fine; only a plain nil means "no data")
            if ok and (ns.IsSecret(start) or start ~= nil) then return "times", start, dur end
        end
        return nil
    end
    id = id or e.ids[1]
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id)
        if ok and d then return "object", d end
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(id)
        if info then return "times", info.startTime, info.duration end
    elseif GetSpellCooldown then
        return "times", GetSpellCooldown(id)
    end
end

-- true when the numbers are known to describe nothing (or only the global cooldown)
local function Idle(start, dur)
    if ns.IsSecret(start) or ns.IsSecret(dur) then return false end
    return type(dur) ~= "number" or dur <= 1.5 or (start or 0) <= 0
end

Apply = function(e, id)
    local cd = e.frame.cd
    local kind, a, b = Source(e, id)
    if kind == "object" and cd.SetCooldownFromDurationObject then
        return pcall(cd.SetCooldownFromDurationObject, cd, a)
    end
    if kind == "times" then
        if Idle(a, b) then
            if e.itemID and e.state ~= "ready" then
                if cd.Clear then cd:Clear() end
                CD.SetState(e, "ready")
            end
            return false
        end
        return pcall(cd.SetCooldown, cd, a, b)
    end
    return false
end

-- lockout debuffs (Recently Bandaged ...): the swipe follows the debuff;
-- where the game hides it, our own timer of its known length
local function ShowLockout(e, fromCast)
    local cd = e.frame.cd
    local kind, a, b = ns.ReadPlayerAura({ e.lockout.aura })
    if kind == "exact" then
        CD.SetState(e, "cooldown")
        cd:SetCooldown(a, b)
        e.lockoutMode = "exact"
    elseif kind == "object" and cd.SetCooldownFromDurationObject and pcall(cd.SetCooldownFromDurationObject, cd, a) then
        CD.SetState(e, "cooldown")
        e.lockoutMode = "object"
    elseif kind == "none" then
        if e.state ~= "ready" and e.lockoutMode ~= "timer" then
            if cd.Clear then cd:Clear() end
            CD.SetState(e, "ready")
        end
    elseif fromCast then
        CD.SetState(e, "cooldown")
        cd:SetCooldown(GetTime(), e.lockout.dur)
        e.lockoutMode = "timer"
    end
end

-- debuffs can also come from elsewhere (someone else bandages you)
function CD:CheckLockouts()
    for _, e in pairs(self.entries) do
        if e.lockout and self:IsAvailable(e) and e.lockoutMode ~= "timer" then ShowLockout(e, false) end
    end
end

-- a cast of this entry's spell
function CD:Start(e, id)
    e.castID = id
    if e.lockout then
        -- a moment later the debuff is on the player
        C_Timer.After(0.1, function() ShowLockout(e, true) end)
        return
    end
    -- a moment later the game has registered the cooldown
    C_Timer.After(0.05, function()
        if e.dur then
            CD.SetState(e, "buff")
            e.frame.cd:SetCooldown(GetTime(), e.dur)   -- the buff time: our own plain numbers
        else
            CD.SetState(e, "cooldown")
            Apply(e, id)
        end
    end)
end

-- login and newly learned spells: hand every entry the game's current
-- cooldown; a cooldown frame with nothing to show stays empty
function CD:Sync(onlyNew)
    for _, e in pairs(self.entries) do
        if e.kind ~= "special" and not e.itemID and e.state == "ready" and self:IsAvailable(e) then
            if not onlyNew or not e.synced then
                e.synced = true
                if Apply(e) then e.frame.running = true end
            end
        end
    end
end

local function ItemSwipe(e)
    if e.lockout and e.state ~= "ready" then return end   -- the debuff decides
    if Apply(e) then CD.SetState(e, "cooldown") end
end

-- ---------------------------------------------------------------------------
-- Your own entries: "item:<id>" or "spell:<id>"
-- ---------------------------------------------------------------------------
function CD:CreateCustom(key)
    if self.entries[key] then return self.entries[key] end
    local kind, id = key:match("^(%a+):(%d+)$")
    id = tonumber(id)
    if not id then return end
    local e = { key = key, kind = "custom" }
    if kind == "item" then
        e.itemID = id
        local sub = ns.ItemSubclass(id)
        local class = C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(id))
        if ns.BANDAGES[id] or (class == 0 and sub == 7) then e.lockout = ns.Lockouts.bandage end
    else
        e.ids = { id }
    end
    AddEntry(e)
    local o = e.frame
    if e.itemID then
        o.countFrame = CreateFrame("Frame", nil, o)   -- the count sits above the swipe
        o.countFrame:SetAllPoints()
        o.countFrame:SetFrameLevel(o.cd:GetFrameLevel() + 2)
        o.count = ns.HudText(o.countFrame, 12, "OUTLINE")
        o.count:SetPoint("BOTTOMRIGHT", -1, 2)
        self:MapItemCast(e)
    end
    self:RefreshIcon(e)
    return e
end

-- the item's use effect is a spell: casting it restarts the swipe
function CD:MapItemCast(e)
    if not (e.itemID and C_Item and C_Item.GetItemSpell) then return end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, e.itemID)
    if ok and spellID then self.byCast[spellID] = e end
end

function CD:DropCustom(key)
    local e = self.entries[key]
    if not e then return end
    e.frame:Hide()
    self.entries[key] = nil
    for id, x in pairs(self.byCast) do if x == e then self.byCast[id] = nil end end
end

-- text from the add box: link, "item:123", "spell:123", a number or a name
function CD:Parse(text)
    text = ns.Trim(text)
    if text == "" then return nil, L["Drag an item or spell here, shift-click its link, or type its name or ID."] end
    local id = text:match("|Hitem:(%d+)") or text:match("^[Ii]tem:(%d+)$")
    if id then return "item", tonumber(id) end
    id = text:match("|Hspell:(%d+)") or text:match("^[Ss]pell:(%d+)$")
    if id then return "spell", tonumber(id) end
    local name = ns.StripColors(text):gsub("^%[", ""):gsub("%]$", "")
    name = ns.Trim(name)
    local n = tonumber(name)
    if n then
        if C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(n) then return "item", n end
        if ns.SpellName(n) then return "spell", n end
        return nil, L["Nothing found with the ID %d."]:format(n)
    end
    -- by name: bags and gear first (localized names off the items), then spells
    local want, found = ns.Fold(name), nil
    ns.ForEachBagItem(function(itemID, itemName)
        if itemName and ns.Fold(itemName) == want then found = itemID return true end
    end)
    if found then return "item", found end
    for slot = 1, 19 do
        local equipped = ns.EquippedName(slot)
        if equipped and ns.Fold(equipped) == want then return "item", GetInventoryItemID("player", slot) end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        if info and info.spellID then return "spell", info.spellID end
    end
    return nil, L["\"%s\" was not found. Drag it in or shift-click it instead."]:format(name)
end

function CD:AddCustom(kind, id)
    local key = kind .. ":" .. id
    local list = Settings().custom
    if ns.IndexOf(list, key) then return nil, L["That one is already tracked."] end
    if kind == "spell" and self.byCast[id] then return nil, L["That spell is tracked already."] end
    list[#list + 1] = key
    local e = self:CreateCustom(key)
    self:RefreshItems()
    HUD:ApplyLayout()
    return e
end

function CD:RemoveCustom(key)
    local list = Settings().custom
    local i = ns.IndexOf(list, key)
    if i then table.remove(list, i) end
    self:DropCustom(key)
    Settings().bar[key], Settings().hidden[key] = nil, nil
    HUD:ApplyLayout()
end

function CD:RefreshItems()
    for _, e in pairs(self.entries) do
        if e.itemID then
            ItemSwipe(e)
            local n = ns.ItemCount(e.itemID)
            e.frame.count:SetText(n > 0 and tostring(n) or "")
            e.frame.icon:SetDesaturated(n == 0)
            e.frame.icon:SetAlpha(n == 0 and 0.5 or 1)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function FindByCast(spellID)
    local e = CD.byCast[spellID]
    if e then return e end
    local n = ns.SpellName(spellID)
    return n and CD.byName[n]
end

local function Rebuild()
    CD:Build()
    CD:ScanSpellbook()
    HUD:ApplyLayout()
    CD:Sync()
    CD:RefreshItems()
end

ns.On("LOGIN", Rebuild)
ns.On("SETTINGS_RESET", Rebuild)

ns.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
    -- a secret ID could not even serve as a table key: skip it
    if ns.IsSecret(spellID) or not spellID then return end
    local e = FindByCast(spellID)
    if e and not e.noCasts then CD:Start(e, spellID) end
    ns.Fire("PLAYER_CAST", spellID)
end)

ns.RegisterUnitEvent("UNIT_AURA", "player", function() if ns.ready then CD:CheckLockouts() end end)
ns.On("LOGIN", function() CD:CheckLockouts() end)

local function SpellsChanged()
    CD:ScanSpellbook()
    CD:RefreshNames()
    for _, e in pairs(CD.entries) do CD:RefreshIcon(e) end
    HUD:ApplyLayout()   -- newly learned abilities appear
    CD:Sync(true)
end
ns.RegisterEvent("SPELLS_CHANGED", function() if ns.ready then SpellsChanged() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if ns.ready and CD.scanPending then SpellsChanged() end end)

for _, ev in ipairs({ "BAG_UPDATE", "BAG_UPDATE_COOLDOWN" }) do
    ns.RegisterEvent(ev, function() if ns.ready then CD:RefreshItems() end end)
end

ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if not ns.ready then return end
    for _, e in pairs(CD.entries) do
        if e.itemID then
            CD:RefreshIcon(e)
            CD:MapItemCast(e)
        end
    end
end)

-- talents can grant abilities (Cold Blood ...)
for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
    ns.RegisterEvent(ev, function() if ns.ready then HUD:ApplyLayout() end end)
end
