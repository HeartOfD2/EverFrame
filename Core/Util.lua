-- ---------------------------------------------------------------------------
-- Small helpers shared by every file: secret values, spell and item data
-- straight from the client (so names are always in the client language),
-- bags, UTF-8 text and value texts with placeholders.
-- ---------------------------------------------------------------------------
local _, ns = ...

-- ---------------------------------------------------------------------------
-- Secret values: the client may hide some numbers from addons (health, power,
-- auras, ranges in combat). They can be displayed, but never compared or
-- calculated with -- not even "== nil". Always ask first.
-- ---------------------------------------------------------------------------
function ns.IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r and true or false
end

-- ---------------------------------------------------------------------------
-- Spells
-- ---------------------------------------------------------------------------
function ns.SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name or nil
    end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end

function ns.SpellIcon(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id) or nil
end

function ns.IsKnown(id)
    return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end

-- true when any of the ranks is learned
function ns.KnowsAny(ids)
    for _, id in ipairs(ids) do
        if ns.IsKnown(id) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Items (this client has no global GetItemInfo, only C_Item)
-- ---------------------------------------------------------------------------
function ns.ItemName(id)
    if not id then return nil end
    local n
    if C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(id) end
    if not n and GetItemInfo then n = GetItemInfo(id) end
    if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return n
end

function ns.ItemIcon(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id) or nil
end

function ns.ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return 0 end
    local ok, n = pcall(fn, id)
    return (ok and type(n) == "number") and n or 0
end

-- item class/subclass without a server round trip
function ns.ItemSubclass(id)
    if not (id and C_Item and C_Item.GetItemInfoInstant) then return nil end
    return select(7, C_Item.GetItemInfoInstant(id))
end

local NUM_BAGS = 4   -- backpack (0) + four bags

-- calls fn(itemID, name, bag, slot) for every item in the bags
function ns.ForEachBagItem(fn)
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not numSlots then return end
    for bag = 0, NUM_BAGS do
        for slot = 1, (numSlots(bag) or 0) do
            local id, name
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    id = info.itemID
                    name = info.itemName or (info.hyperlink and info.hyperlink:match("%[(.-)%]"))
                end
            elseif GetContainerItemLink then
                local link = GetContainerItemLink(bag, slot)
                if link then id, name = tonumber(link:match("item:(%d+)")), link:match("%[(.-)%]") end
            end
            if id then
                if fn(id, name, bag, slot) then return end
            end
        end
    end
end

function ns.EquippedName(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    local name = link and link:match("%[(.-)%]")
    if not name then name = ns.ItemName(GetInventoryItemID("player", slot)) end
    return name
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
function ns.StripColors(s)
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

function ns.Utf8Len(s)
    local n = 0
    for _ in (s or ""):gmatch(UTF8_CHAR) do n = n + 1 end
    return n
end

function ns.Utf8Sub(s, maxChars)
    local out, n = {}, 0
    for ch in (s or ""):gmatch(UTF8_CHAR) do
        n = n + 1
        if n > maxChars then break end
        out[n] = ch
    end
    return table.concat(out)
end

-- lower case for searching. A-Z by hand (string.lower can damage UTF-8 bytes
-- under some C locales), plus Latin-1 accents and Cyrillic capitals.
function ns.Fold(s)
    s = (s or ""):gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
    s = s:gsub("\195([\128-\158])", function(c) return "\195" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    return s
end

function ns.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function ns.IsBlank(s) return not s or s:match("^%s*$") ~= nil end

-- ---------------------------------------------------------------------------
-- Value texts with placeholders: {cur} {max} {pct} {deficit}.
-- Plain numbers are filled in here. Secret numbers only go to the game's own
-- formatter (no arithmetic); what still can't be shown falls back to {cur}.
-- Returns the mode that was used ("plain", "formatted", "current only").
-- ---------------------------------------------------------------------------
ns.VALUE_TOKENS = { "cur", "max", "pct", "deficit" }

function ns.FillValueText(fmt, cur, max)
    local pct = (max and max > 0) and math.floor(cur / max * 100 + 0.5) or 0
    return (fmt:gsub("{(%a+)}", function(k)
        if k == "cur" then return tostring(cur) end
        if k == "max" then return tostring(max) end
        if k == "pct" then return tostring(pct) end
        if k == "deficit" then return tostring(max - cur) end
    end))
end

function ns.SetValueText(fs, fmt, cur, max, pctFn)
    if not ns.IsSecret(cur) and not ns.IsSecret(max) and type(cur) == "number" and type(max) == "number" then
        fs:SetText(ns.FillValueText(fmt, cur, max))
        return "plain"
    end
    local args, missing = {}, false
    local pattern = fmt:gsub("%%", "%%%%"):gsub("{(%a+)}", function(k)
        if k == "cur" then args[#args + 1] = cur return "%s" end
        if k == "max" then args[#args + 1] = max return "%s" end
        if k == "pct" and pctFn then
            local ok, p = pcall(pctFn)
            if ok and (ns.IsSecret(p) or type(p) == "number") then
                args[#args + 1] = p
                return "%.0f"
            end
        end
        if k == "pct" or k == "deficit" then missing = true return "" end
    end)
    if not missing and pcall(fs.SetFormattedText, fs, pattern, unpack(args)) then
        return "formatted"
    end
    fs:SetText(cur)
    return "current only"
end

-- ---------------------------------------------------------------------------
-- A buff or debuff on the player, without touching secret numbers:
--   "exact", start, duration    plain numbers
--   "object", durationObject    only secret; for SetCooldownFromDurationObject
--   "none"                      readable, and not on the player
--   nil                         the client doesn't let us look
-- ---------------------------------------------------------------------------
function ns.ReadPlayerAura(ids)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local aura
    for _, id in ipairs(ids) do
        local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if not ok or ns.IsSecret(a) then return nil end
        if a then aura = a break end
    end
    if not aura then return "none" end
    local ok, exp, dur = pcall(function() return aura.expirationTime, aura.duration end)
    if ok and type(exp) == "number" and type(dur) == "number" and not ns.IsSecret(exp) and not ns.IsSecret(dur)
            and exp > 0 and dur > 0 then
        return "exact", exp - dur, dur
    end
    local okID, instance = pcall(function() return aura.auraInstanceID end)
    if okID and instance and not ns.IsSecret(instance) and C_UnitAuras.GetAuraDuration then
        local okD, d = pcall(C_UnitAuras.GetAuraDuration, "player", instance)
        if okD and d then return "object", d end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Base64 (for sharing templates as text)
-- ---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, 64 do B64_VALUE[B64:byte(i)] = i - 1 end

function ns.Base64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

-- nil when the text isn't valid Base64
function ns.Base64Decode(text)
    text = text:gsub("%s", "")
    if #text == 0 or #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local n, pad = 0, 0
        for j = 0, 3 do
            local ch = text:byte(i + j)
            local v = B64_VALUE[ch]
            if ch == 61 and i + j > #text - 2 then   -- "=" padding at the very end
                v, pad = 0, pad + 1
            elseif not v or pad > 0 then
                return nil
            end
            n = n * 64 + v
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(a) .. (pad < 2 and string.char(b) or "") .. (pad < 1 and string.char(c) or "")
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Macro templates as one line of text: "UER2:" + Base64 (name, description,
-- icon, text, group; "UER1:" codes have no group and still import). Inside,
-- fields are split by ASCII unit/record separators, never found in macro text.
-- ---------------------------------------------------------------------------
local TPL_PREFIX, TPL_PREFIX_V1 = "UER2:", "UER1:"
local FIELD, RECORD = "\31", "\30"

local function Clean(s) return (tostring(s or ""):gsub("[\30\31]", "")) end

function ns.EncodeTemplates(list)
    local records = {}
    for _, t in ipairs(list) do
        records[#records + 1] = table.concat({ Clean(t.name), Clean(t.desc), Clean(t.icon), Clean(t.body), Clean(t.group) }, FIELD)
    end
    return TPL_PREFIX .. ns.Base64Encode(table.concat(records, RECORD))
end

-- list of { name, desc, icon, body, group }, or nil + reason
function ns.DecodeTemplates(text)
    text = ns.Trim(text)
    local fields
    if text:sub(1, #TPL_PREFIX) == TPL_PREFIX then
        fields = 5
    elseif text:sub(1, #TPL_PREFIX_V1) == TPL_PREFIX_V1 then
        fields = 4
    else
        return nil, "prefix"
    end
    local data = ns.Base64Decode(text:sub(#TPL_PREFIX + 1))
    if not data or data == "" then return nil, "data" end
    local list = {}
    for record in (data .. RECORD):gmatch("(.-)" .. RECORD) do
        local f = {}
        for field in (record .. FIELD):gmatch("(.-)" .. FIELD) do f[#f + 1] = field end
        if #f ~= fields or ns.Trim(f[1]) == "" then return nil, "data" end
        local group = f[5] and ns.Trim(f[5]) or ""
        list[#list + 1] = { name = ns.Utf8Sub(ns.Trim(f[1]), 16), desc = f[2], icon = tonumber(f[3]) or (f[3] ~= "" and f[3] or nil),
                            body = ns.Utf8Sub(f[4], 255), group = group ~= "" and group or nil }
    end
    return list
end

-- WoW macros the same way: "UERM1:" + Base64 (name, icon, text, group)
local MACRO_PREFIX = "UERM1:"

function ns.EncodeMacros(list)
    local records = {}
    for _, m in ipairs(list) do
        records[#records + 1] = table.concat({ Clean(m.name), Clean(m.icon), Clean(m.body), Clean(m.group) }, FIELD)
    end
    return MACRO_PREFIX .. ns.Base64Encode(table.concat(records, RECORD))
end

-- list of { name, icon, body, group }, or nil + reason
function ns.DecodeMacros(text)
    text = ns.Trim(text)
    if text:sub(1, #MACRO_PREFIX) ~= MACRO_PREFIX then return nil, "prefix" end
    local data = ns.Base64Decode(text:sub(#MACRO_PREFIX + 1))
    if not data or data == "" then return nil, "data" end
    local list = {}
    for record in (data .. RECORD):gmatch("(.-)" .. RECORD) do
        local f = {}
        for field in (record .. FIELD):gmatch("(.-)" .. FIELD) do f[#f + 1] = field end
        if #f ~= 4 or ns.Trim(f[1]) == "" then return nil, "data" end
        local group = ns.Trim(f[4])
        list[#list + 1] = { name = ns.Utf8Sub(ns.Trim(f[1]), 16), icon = tonumber(f[2]) or (f[2] ~= "" and f[2] or nil),
                            body = ns.Utf8Sub(f[3], 255), group = group ~= "" and group or nil }
    end
    return list
end

-- Notes the same way: "UERN1:" + Base64; one record per note with
-- kind ("g" = notebook group, "p" = player), its group name or Name-Realm,
-- group color or class, title, text, created and updated time
local NOTES_PREFIX = "UERN1:"

function ns.EncodeNotes(list)
    local records = {}
    for _, n in ipairs(list) do
        records[#records + 1] = table.concat({ Clean(n.kind), Clean(n.owner), Clean(n.extra), Clean(n.title),
            Clean(n.text), Clean(n.created), Clean(n.updated) }, FIELD)
    end
    return NOTES_PREFIX .. ns.Base64Encode(table.concat(records, RECORD))
end

-- list of { kind, owner, extra, title, text, created, updated }, or nil + reason
function ns.DecodeNotes(text)
    text = ns.Trim(text)
    if text:sub(1, #NOTES_PREFIX) ~= NOTES_PREFIX then return nil, "prefix" end
    local data = ns.Base64Decode(text:sub(#NOTES_PREFIX + 1))
    if not data or data == "" then return nil, "data" end
    local list = {}
    for record in (data .. RECORD):gmatch("(.-)" .. RECORD) do
        local f = {}
        for field in (record .. FIELD):gmatch("(.-)" .. FIELD) do f[#f + 1] = field end
        if #f ~= 7 or (f[1] ~= "g" and f[1] ~= "p") or ns.Trim(f[2]) == "" then return nil, "data" end
        list[#list + 1] = { kind = f[1], owner = f[2], extra = f[3] ~= "" and f[3] or nil, title = f[4],
                            text = f[5], created = tonumber(f[6]), updated = tonumber(f[7]) }
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------
function ns.CopyTable(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = ns.CopyTable(v) end
    return out
end

function ns.IndexOf(list, item)
    for i, v in ipairs(list) do
        if v == item then return i end
    end
end

function ns.InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end
