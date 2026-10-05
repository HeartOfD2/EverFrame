-- ---------------------------------------------------------------------------
-- Poison tracker: one tile per hand with time left and charges. The button in
-- each tile applies the poison (left-click) or opens the poison choice
-- (right-click). Time and charges come from GetWeaponEnchantInfo; the weapon
-- tooltip only tells which poison it is (matched by the localized item names).
-- A tile turns red and blinks when a poison runs low or is missing in combat.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local HUD, UI, Rogue = ns.HUD, ns.UI, ns.Rogue

local TILE_H = 22
local LOW_MINUTES, LOW_CHARGES = 5, 5
local HAND_LABEL = { MH = L["MH"], OH = L["OH"] }
local HAND_NAME = { MH = L["Main hand"], OH = L["Off hand"] }

-- ---------------------------------------------------------------------------
-- Reading the weapons
-- ---------------------------------------------------------------------------
local function TooltipLines(slot)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
        if ok and data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if not ns.IsSecret(text) and type(text) == "string" then lines[#lines + 1] = ns.StripColors(text) end
            end
        end
    end
    return lines
end

-- which poison is on the weapon: the line naming one of our poisons
local function IdentifyPoison(lines)
    for _, text in ipairs(lines) do
        for _, p in ipairs(Rogue.POISONS) do
            local name = Rogue:PoisonName(p.key)
            if name ~= p.key and text:find(name, 1, true) then return p.key, text end
        end
    end
end

-- minutes from a "(<number> <unit>)" group; hours first: German "Std." would
-- otherwise read as seconds ("Sek.")
local function Minutes(n, unit)
    local u = ns.Fold(unit)
    if u:find("^std") or u:find("^h") or u:find("^ч") or u:find("^시") or u:find("^小") then return n * 60 end
    if u:find("^s") or u:find("^с") or u:find("^초") or u:find("^秒") then return math.ceil(n / 60) end
    if u:find("^m") or u:find("^м") or u:find("^분") or u:find("^分") then return n end
end

-- fallback for clients without GetWeaponEnchantInfo: time and charges from
-- the poison's tooltip line, e.g. "Instant Poison VI (28 min) (45 Charges)"
local function ParseLine(text)
    local mins, charges
    for num, rest in text:gmatch("%((%d+)%s*([^%)]*)%)") do
        local n = tonumber(num)
        if not mins then
            local unit = rest:match("^(%S+)")
            mins = unit and Minutes(n, unit)
        elseif not charges then
            charges = n
        end
    end
    return mins, charges
end

-- poison per enchant ID, learned from the tooltip once: later reads skip the
-- tooltip scan as long as the same enchant sits on the weapon
local keyByEnchant = {}

-- per hand: { active, mins, charges, key } or nil when no weapon
local function ReadHands()
    local out = {}
    local enchant
    if GetWeaponEnchantInfo then
        local ok, hasMH, mhExp, mhCh, mhID, hasOH, ohExp, ohCh, ohID = pcall(GetWeaponEnchantInfo)
        if ok and not (ns.IsSecret(hasMH) or ns.IsSecret(mhExp) or ns.IsSecret(hasOH) or ns.IsSecret(ohExp)
                or ns.IsSecret(mhCh) or ns.IsSecret(ohCh) or ns.IsSecret(mhID) or ns.IsSecret(ohID)) then
            enchant = { MH = { hasMH, mhExp, mhCh, mhID }, OH = { hasOH, ohExp, ohCh, ohID } }
        end
    end
    Rogue.readMode = enchant and L["weapon enchant info"] or L["tooltip text"]
    for hand, slot in pairs(Rogue.HANDS) do
        if GetInventoryItemID("player", slot) then
            local e = enchant and enchant[hand]
            local id = e and e[1] and e[4]
            local key, line = id and keyByEnchant[id], nil
            -- an empty weapon needs no tooltip scan
            if not key and not (e and not e[1]) then
                key, line = IdentifyPoison(TooltipLines(slot))
                if id and key then keyByEnchant[id] = key end
            end
            local h = { key = key }
            if e then
                if e[1] then
                    h.active = true
                    h.mins = math.max(0, math.ceil((e[2] or 0) / 60000))
                    h.charges = (e[3] and e[3] > 0) and e[3] or nil
                end
            elseif line then
                h.mins, h.charges = ParseLine(line)
                h.active = h.mins ~= nil
            end
            if h.active and key then Rogue.lastSeen[hand] = key end
            out[hand] = h
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Element
-- ---------------------------------------------------------------------------
local el = HUD:Register({
    key = "poisons", order = 50, label = L["Poison tracker"], secure = true,
})
Rogue.poisonElement = el

function el:IsRelevant() return Rogue:IsClassAllowed() end

function el:IsAvailable()
    if Rogue:IsActive() then return true end
    return false, Rogue:IsClassAllowed() and L["rogue module is off"] or L["only for rogues"]
end

local function MakeTile(hand)
    local c = CreateFrame("Frame", nil, HUD.frame)
    c:SetSize((HUD.WIDTH - HUD.GAP) / 2, TILE_H)
    ns.Skin(c, T.hudPanel, T.hudLine)
    c.label = ns.HudText(c, 11)
    c.label:SetPoint("LEFT", TILE_H + 1, 0)
    c.label:SetTextColor(unpack(T.hudMuted))
    c.label:SetText(HAND_LABEL[hand])
    c.value = ns.HudText(c, 12)
    c.value:SetPoint("RIGHT", -6, 0)
    c.value:SetJustifyH("RIGHT")
    c:Hide()
    return c
end

local OpenChoice

local function MakeButton(hand, tile)
    local b = CreateFrame("Button", "UERPoison" .. hand, HUD.frame, "SecureActionButtonTemplate")
    b:SetSize(TILE_H - 6, TILE_H - 6)
    b:SetFrameLevel(tile:GetFrameLevel() + 2)
    b:RegisterForClicks("AnyDown")   -- this client only runs secure actions on press
    ns.Skin(b, T.hudTrack, T.hudLine)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetTexture(Rogue.POISON_ICON)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.2)
    -- PostClick is the secure-safe hook for the right-click choice
    b:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and down ~= false then OpenChoice(self, hand) end
    end)
    b:SetScript("OnEnter", function(self) el:ShowTooltip(self, hand) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

-- built on first use: secure buttons protect the HUD in combat, which only
-- rogues need (a druid's frame must stay free to change in combat)
function el:Ensure()
    if self.tiles or ns.InCombat() then return self.tiles ~= nil end
    self.tiles = { MH = MakeTile("MH"), OH = MakeTile("OH") }
    self.buttons = { MH = MakeButton("MH", self.tiles.MH), OH = MakeButton("OH", self.tiles.OH) }
    return true
end
el.hands, el.alert = {}, {}
el.elapsed, el.clock = 0, 0

function el:Place(y)
    if not self:Ensure() then return 0 end
    local w = (HUD.WIDTH - HUD.GAP) / 2
    self.tiles.MH:SetWidth(w)
    self.tiles.OH:SetWidth(w)
    self.tiles.MH:ClearAllPoints()
    self.tiles.MH:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", 0, y)
    self.tiles.OH:ClearAllPoints()
    self.tiles.OH:SetPoint("TOPRIGHT", HUD.frame, "TOPRIGHT", 0, y)
    -- the secure buttons hang from the HUD itself, not from the tiles
    self.buttons.MH:ClearAllPoints()
    self.buttons.MH:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", 3, y - 3)
    self.buttons.OH:ClearAllPoints()
    self.buttons.OH:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", w + HUD.GAP + 3, y - 3)
    for _, hand in ipairs({ "MH", "OH" }) do
        self.tiles[hand]:Show()
        self.buttons[hand]:Show()
    end
    return TILE_H
end

function el:HideAll()
    if not self.tiles then return end
    for _, hand in ipairs({ "MH", "OH" }) do
        self.tiles[hand]:Hide()
        self.buttons[hand]:Hide()
    end
end

-- the apply macro of each button (secure attributes: out of combat only)
function el:UpdateButtons()
    if ns.InCombat() or not self.tiles then return end
    for hand, slot in pairs(Rogue.HANDS) do
        local b = self.buttons[hand]
        local key = Rogue:EffectiveKey(hand)
        local _, id = Rogue:FindPoison(key)
        if id then
            local macro = ("/use item:%d\n/use %d"):format(id, slot)
            -- modified clicks don't fall back to the plain attributes on this
            -- client, so every variant is set explicitly
            for _, prefix in ipairs({ "", "*", "alt-", "ctrl-", "shift-" }) do
                b:SetAttribute(prefix .. "type1", "macro")
                b:SetAttribute(prefix .. "macrotext1", macro)
            end
            b:SetAttribute("type", "macro")
            b:SetAttribute("macrotext", macro)
            b.icon:SetTexture(ns.ItemIcon(id) or Rogue.POISON_ICON)
            b.icon:SetDesaturated(false)
            b.icon:SetAlpha(1)
        else
            for _, prefix in ipairs({ "", "*", "alt-", "ctrl-", "shift-" }) do
                b:SetAttribute(prefix .. "type1", nil)
            end
            b:SetAttribute("type", nil)
            b.icon:SetTexture(Rogue:PoisonIcon(key))
            b.icon:SetDesaturated(true)
            b.icon:SetAlpha(0.45)
        end
    end
end

-- tile texts: "28m · 45" (minutes · charges), red when low, "missing" in combat
function el:Update()
    if not self.tiles then return end
    if UnitLevel("player") < 20 then
        for _, hand in ipairs({ "MH", "OH" }) do
            self.alert[hand] = false
            self.tiles[hand].value:SetText(ns.Colorize(HEX.hudMuted, "—"))
            ns.SetEdgeColor(self.tiles[hand])
        end
        return
    end
    local ok, hands = pcall(ReadHands)
    self.hands = ok and hands or {}
    local inCombat = UnitAffectingCombat("player")
    local warn = Rogue:Settings().poisonWarn ~= false
    for _, hand in ipairs({ "MH", "OH" }) do
        local h, tile = self.hands[hand], self.tiles[hand]
        local text, alert
        if h and h.active then
            local low = warn and ((h.mins or 99) <= LOW_MINUTES or (h.charges ~= nil and h.charges <= LOW_CHARGES))
            local hex = low and HEX.hudAlert or HEX.hudValue
            text = ns.Colorize(hex, ("%dm"):format(h.mins or 0))
            if h.charges then text = text .. ns.Colorize(HEX.hudMuted, " · ") .. ns.Colorize(hex, h.charges) end
            alert = low and "low" or false
        elseif h and inCombat and warn then
            text, alert = ns.Colorize(HEX.hudAlert, L["missing"]), "missing"
        else
            text, alert = ns.Colorize(HEX.hudMuted, "—"), false
        end
        tile.value:SetText(text)
        self.alert[hand] = alert
        ns.SetEdgeColor(tile, alert and T.hudAlert or nil)
    end
    self:UpdateButtons()
end

function el:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= 1 then
        self.elapsed = 0
        self:Update()
    end
    -- warnings: a low poison breathes softly, a missing one blinks hard
    self.clock = self.clock + elapsed
    local breathe = 0.4 + 0.6 * (0.5 + 0.5 * math.cos(self.clock * 3))
    local blinkOn = math.floor(self.clock * 4) % 2 == 0
    for _, hand in ipairs({ "MH", "OH" }) do
        local a, value = self.alert[hand], self.tiles[hand].value
        if a == "missing" then
            value:SetAlpha(blinkOn and 1 or 0.15)
        elseif a == "low" then
            value:SetAlpha(breathe)
        else
            value:SetAlpha(1)
        end
    end
end

function el:Refresh()
    if not self:IsAvailable() then return end
    Rogue:RefreshPoisonNames()
    self:Ensure()
    self:Update()
end

function el:ShowTooltip(owner, hand)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local slot = Rogue.HANDS[hand]
    GameTooltip:AddLine(("%s: %s"):format(HAND_NAME[hand], ns.EquippedName(slot) or "—"), 1, 1, 1)
    local key = Rogue:EffectiveKey(hand)
    local name = Rogue:FindPoison(key)
    if name then
        GameTooltip:AddLine(L["Applies: %s"]:format(name), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(L["No matching poison in your bags (%s)."]:format(Rogue:PoisonName(key)), 1, 0.4, 0.4, true)
    end
    local h = self.hands[hand]
    if h and h.active then
        local now = L["On the weapon: %s, %d min"]:format(h.key and Rogue:PoisonName(h.key) or L["a poison"], h.mins or 0)
        if h.charges then now = now .. ", " .. L["%d charges"]:format(h.charges) end
        GameTooltip:AddLine(now, 0.45, 0.85, 0.55)
    end
    GameTooltip:AddLine(L["Left-click: apply  ·  Right-click: choose poison"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Poison choice (right-click)
-- ---------------------------------------------------------------------------
OpenChoice = function(anchor, hand)
    if ns.InCombat() then
        ns.Print(L["Poisons can't be chosen during combat."])
        return
    end
    local current = Rogue:Choice(hand)
    local items = { { label = hand == "MH" and L["Main hand: choose poison"] or L["Off hand: choose poison"], isTitle = true } }
    for _, p in ipairs(Rogue.POISONS) do
        local have = Rogue:FindPoison(p.key) ~= nil
        items[#items + 1] = {
            label = Rogue:PoisonName(p.key), icon = Rogue:PoisonIcon(p.key), checked = current == p.key,
            desc = not have and L["none in bags"] or nil,
            fn = function() Rogue:SetChoice(hand, p.key) end,
        }
    end
    items[#items + 1] = {
        label = L["Best available"], icon = Rogue.POISON_ICON, checked = current == nil, divider = true,
        desc = L["highest rank"],
        fn = function() Rogue:SetChoice(hand, nil) end,
    }
    UI.OpenMenu(anchor, items, { point = "TOPLEFT", relPoint = "BOTTOMRIGHT", x = 2, y = -4, width = 320 })
end

ns.On("ROGUE_POISON_CHOICE", function() el:UpdateButtons() end)
for _, ev in ipairs({ "BAG_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
    ns.RegisterEvent(ev, function() if el.shown then el:Update() end end)
end
ns.RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player", function() if el.shown then el:Update() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if el.shown then el:UpdateButtons() end end)

ns.AddStatus(function()
    if not Rogue:IsActive() then return end
    return L["Poisons read from: %s"]:format(Rogue.readMode or "—")
end)
