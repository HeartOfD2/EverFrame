-- ---------------------------------------------------------------------------
-- Chat commands: /ef (and /everframe). Modules add their own with
-- ns.AddCommand and their own lines for /ef status with ns.AddStatus.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local HUD, App = ns.HUD, ns.App

local commands, order = {}, {}
local statusLines = {}

-- names: list of words that run it; help: shown by /ef help (nil = hidden)
function ns.AddCommand(names, fn, help)
    local def = { names = names, fn = fn, help = help }
    for _, n in ipairs(names) do commands[n] = def end
    order[#order + 1] = def
end

-- fn() returns a line (or nil) for /ef status
function ns.AddStatus(fn) statusLines[#statusLines + 1] = fn end

function ns.CommandHelpText()
    local lines = {}
    for _, def in ipairs(order) do
        if def.help then
            lines[#lines + 1] = ns.Code("/ef " .. def.names[1]) .. "  " .. def.help
        end
    end
    return table.concat(lines, "\n")
end

ns.AddCommand({ "settings", "options", "config" }, function() App:Open("general") end, L["open the settings"])
ns.AddCommand({ "macros", "macro", "mm" }, function() App:Toggle("macros") end, L["macro manager"])
ns.AddCommand({ "update" }, function() ns.Placeholders.UpdateAll() end, L["rewrite the macros named like a template with the current values"])
ns.AddCommand({ "notes" }, function() App:Toggle("notes") end, L["notes"])
ns.AddCommand({ "note" }, function() ns.NoteForTarget() end, L["new note for your target (works as a macro)"])
ns.AddCommand({ "lock" }, function()
    HUD:SetLocked(true)
    ns.Print(L["Frame locked."])
end, L["lock the frame"])
ns.AddCommand({ "unlock" }, function()
    HUD:SetLocked(false)
    ns.Print(L["Frame unlocked: drag it with the left mouse button."])
end, L["unlock the frame to move it"])
ns.AddCommand({ "reset" }, function()
    HUD:ResetPosition()
    ns.Print(L["Position reset."])
end, L["put the frame back to its default position"])
ns.AddCommand({ "scale" }, function(arg)
    local n = tonumber(arg)
    if not n then
        ns.Print(L["Usage: /ef scale 0.5 - 2.0"])
        return
    end
    HUD:SetScale(n)
    ns.Print(L["Scale: %d%%."]:format(math.max(0.5, math.min(2, n)) * 100 + 0.5))
end, L["frame scale, e.g. /ef scale 1.2"])
ns.AddCommand({ "minimap" }, function()
    ns.SetMinimapButtonShown(not ns.IsMinimapButtonShown())
end, L["show or hide the minimap button"])
ns.AddCommand({ "theme" }, function(arg)
    if arg == "dark" or arg == "light" then
        ns.SetTheme(arg, nil)
    elseif arg == "teal" or arg == "amber" or arg == "blue" then
        ns.SetTheme(nil, arg)
    else
        ns.Print(L["Usage: /ef theme dark | light | teal | amber | blue"])
        return
    end
    ns.Print(L["Theme: %s, %s."]:format(ns.ThemeSettings().mode, ns.ThemeSettings().accent))
end, L["dark, light, teal, amber or blue"])
ns.AddCommand({ "status" }, function()
    ns.Print(L["Status:"])
    print("   " .. L["Class: %s  ·  Version: %s"]:format(ns.playerClass or "?", ns.VERSION))
    local active = {}
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        active[#active + 1] = (m.title or key) .. ": " .. (m:IsActive() and L["active"] or L["off"])
    end
    if #active > 0 then print("   " .. L["Modules"] .. ": " .. table.concat(active, ", ")) end
    print("   " .. L["Health text: %s  ·  Resource text: %s"]:format(ns.textModes.health or "—", ns.textModes.power or "—"))
    local range = HUD.byKey.range
    if range then
        if range.shown then range:Update() end
        print("   " .. L["Range checks: %s"]:format(range.mode or "—"))
    end
    local combo = HUD.byKey.combo
    if combo and combo:IsRelevant() and combo.mode then
        print("   " .. L["Combo points: %s"]:format(combo.mode == "secret" and L["secret (drawn by the game)"] or L["plain values"]))
    end
    local CD = ns.Cooldowns
    print("   " .. L["Spellbook: %s  ·  base cooldowns: %s  ·  found: %d"]:format(CD.bookMode or "—",
        GetSpellBaseCooldown and L["yes"] or L["no"], #CD.bookKeys))
    local picker = ColorPickerFrame and (ColorPickerFrame.SetupColorPickerAndShow and "SetupColorPickerAndShow" or "legacy")
    print("   " .. L["Color picker: %s"]:format(picker or "—"))
    local hidden, shown, compartment = ns.MinimapState()
    print("   " .. L["Minimap button: saved %s  ·  on screen: %s  ·  addon list entry: %s"]:format(
        hidden and L["hidden"] or L["shown"], shown and L["yes"] or L["no"], compartment and L["yes"] or L["no"]))
    for _, fn in ipairs(statusLines) do
        local ok, line = pcall(fn)
        if ok and line then print("   " .. line) end
    end
end, L["what the game allows right now (secret values, range checks ...)"])
ns.AddCommand({ "help", "?" }, function()
    ns.Print(L["Commands:"])
    for line in (ns.CommandHelpText() .. "\n"):gmatch("(.-)\n") do print("   " .. line) end
end)

SLASH_EVERFRAME1 = "/ef"
SLASH_EVERFRAME2 = "/everframe"
SlashCmdList.EVERFRAME = function(msg)
    msg = ns.Trim(msg or "")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = ns.Fold(cmd or "")
    if cmd == "" then
        App:Toggle()
        return
    end
    local def = commands[cmd]
    if def then
        def.fn(arg ~= "" and ns.Fold(arg) or nil)
    else
        ns.Print(L["Unknown command. /ef help lists all commands."])
    end
end
