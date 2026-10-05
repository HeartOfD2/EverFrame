-- ---------------------------------------------------------------------------
-- Minimal default package per class: tracked cooldowns and range checks.
-- Spell IDs are rank 1; a spell only shows once the character knows it, and
-- every name comes from the client, so all of this works in any language.
--   cooldowns: { key, ids = { rank IDs }, dur = buff seconds (optional) }
--   range:     far -> near bands { yards, spells, interact = CheckInteractDistance index }
-- WoW: Forever spell IDs can differ from Classic; extend these lists when a
-- spell turns out to report another ID in game.
-- ---------------------------------------------------------------------------
local _, ns = ...

local CLASSES = {}
ns.ClassData = CLASSES

CLASSES.ROGUE = {
    comboPoints = true,
    cooldowns = {
        { key = "evasion",       ids = { 5277 }, dur = 15 },
        { key = "vanish",        ids = { 1856, 1857 } },
        { key = "kick",          ids = { 1766, 1767, 1768, 1769 } },
        { key = "sprint",        ids = { 2983, 8696, 11305 }, dur = 15 },
        { key = "bladeflurry",   ids = { 13877 }, dur = 15 },
        { key = "adrenaline",    ids = { 13750 }, dur = 15 },
        { key = "blind",         ids = { 2094 } },
        { key = "kidney",        ids = { 408, 8643 } },
        { key = "gouge",         ids = { 1776, 1777, 8629, 11285, 11286 } },
        { key = "coldblood",     ids = { 14177 } },
        { key = "ghoststrike",   ids = { 14278 } },
        { key = "premeditation", ids = { 14183 } },
        { key = "preparation",   ids = { 14185 } },
        { key = "riposte",       ids = { 14251 } },
        { key = "feint",         ids = { 1966, 6768, 8637, 11303, 25302 } },
        { key = "distract",      ids = { 1725 } },
    },
    range = {
        { yards = 30, spells = { 2764, 2480, 7918, 7919 }, interact = 4 },   -- Throw, Shoot Bow/Gun/Crossbow
        { yards = 10, spells = { 2094, 6770 }, interact = 3 },               -- Blind, Sap
        { yards = 0,  spells = { 1752, 1776, 1766, 53 } },                   -- Sinister Strike, Gouge, Kick, Backstab
    },
}

CLASSES.DRUID = {
    comboPoints = true,   -- in Cat Form
    cooldowns = {
        { key = "barkskin",      ids = { 22812 }, dur = 15 },
        { key = "innervate",     ids = { 29166 }, dur = 20 },
        { key = "rebirth",       ids = { 20484, 20739, 20742, 20747, 20748 } },
        { key = "tranquility",   ids = { 740, 8918, 9862, 9863 } },
        { key = "naturesswift",  ids = { 17116 } },
        { key = "swiftmend",     ids = { 18562 } },
        { key = "bash",          ids = { 5211, 6798, 8983 } },
        { key = "dash",          ids = { 1850, 9821 }, dur = 15 },
        { key = "tigersfury",    ids = { 5217, 6793, 9845, 9846 }, dur = 6 },
        { key = "feralcharge",   ids = { 16979 } },
        { key = "enrage",        ids = { 5229 } },
        { key = "frenziedregen", ids = { 22842, 22895, 22896 }, dur = 10 },
        { key = "challroar",     ids = { 5209 } },
        { key = "growl",         ids = { 6795 } },
        { key = "hurricane",     ids = { 16914, 17401, 17402 } },
    },
    range = {
        { yards = 30, spells = { 5176, 8921 }, interact = 4 },   -- Wrath, Moonfire
        { yards = 0,  spells = { 1082, 6807, 5221 } },           -- Claw, Maul, Shred
    },
}

CLASSES.WARRIOR = {
    cooldowns = {
        { key = "charge",        ids = { 100, 6178, 11578 } },
        { key = "intercept",     ids = { 20252, 20616, 20617 } },
        { key = "bloodrage",     ids = { 2687 } },
        { key = "berserkerrage", ids = { 18499 }, dur = 10 },
        { key = "pummel",        ids = { 6552, 6554 } },
        { key = "shieldbash",    ids = { 72, 1671, 1672 } },
        { key = "overpower",     ids = { 7384, 7887, 11584, 11585 } },
        { key = "shieldwall",    ids = { 871 }, dur = 10 },
        { key = "recklessness",  ids = { 1719 }, dur = 15 },
        { key = "retaliation",   ids = { 20230 }, dur = 15 },
        { key = "deathwish",     ids = { 12292 }, dur = 30 },
        { key = "laststand",     ids = { 12975 } },
        { key = "sweeping",      ids = { 12328 } },
        { key = "mortalstrike",  ids = { 12294, 21551, 21552, 21553 } },
        { key = "bloodthirst",   ids = { 23881, 23892, 23893, 23894 } },
        { key = "shieldblock",   ids = { 2565 } },
        { key = "intimshout",    ids = { 5246 } },
        { key = "taunt",         ids = { 355 } },
        { key = "whirlwind",     ids = { 1680 } },
    },
    range = {
        { yards = 25, spells = { 100, 20252 }, interact = 4 },   -- Charge, Intercept
        { yards = 0,  spells = { 78, 772, 7384 } },              -- Heroic Strike, Rend, Overpower
    },
}

CLASSES.MAGE = {
    cooldowns = {
        { key = "blink",         ids = { 1953 } },
        { key = "counterspell",  ids = { 2139 } },
        { key = "frostnova",     ids = { 122, 865, 6131, 10230 } },
        { key = "fireblast",     ids = { 2136, 2137, 2138, 8412, 8413, 10197, 10199 } },
        { key = "coneofcold",    ids = { 120, 8492, 10159, 10160, 10161 } },
        { key = "iceblock",      ids = { 11958 }, dur = 10 },
        { key = "coldsnap",      ids = { 12472 } },
        { key = "evocation",     ids = { 12051 } },
        { key = "arcanepower",   ids = { 12042 }, dur = 15 },
        { key = "presence",      ids = { 12043 } },
        { key = "combustion",    ids = { 11129 } },
        { key = "icebarrier",    ids = { 11426, 13031, 13032, 13033 } },
        { key = "blastwave",     ids = { 11113, 13018, 13019, 13020, 13021 } },
    },
    range = {
        { yards = 30, spells = { 133, 116, 5143 }, interact = 4 },   -- Fireball, Frostbolt, Arcane Missiles
        { yards = 10, spells = { 122 } },                            -- Frost Nova
    },
}

CLASSES.PRIEST = {
    cooldowns = {
        { key = "psychicscream", ids = { 8122, 8124, 10888, 10890 } },
        { key = "fade",          ids = { 586, 9578, 9579, 9592, 10941, 10942 } },
        { key = "innerfocus",    ids = { 14751 } },
        { key = "powerinfusion", ids = { 10060 }, dur = 15 },
        { key = "silence",       ids = { 15487 } },
        { key = "desperate",     ids = { 13908, 19236, 19238, 19240, 19241, 19242, 19243 } },
        { key = "mindblast",     ids = { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 } },
        { key = "fearward",      ids = { 6346 } },
        -- no cooldown of its own: Weakened Soul (15 s) blocks it
        { key = "pwshield",      ids = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },
          lockout = { aura = 6788, dur = 15 } },
    },
    range = {
        { yards = 30, spells = { 585, 589, 8092 }, interact = 4 },   -- Smite, Shadow Word: Pain, Mind Blast
    },
}

CLASSES.WARLOCK = {
    cooldowns = {
        { key = "deathcoil",     ids = { 6789, 17925, 17926 } },
        { key = "howlofterror",  ids = { 5484, 17928 } },
        { key = "shadowburn",    ids = { 17877, 18867, 18868, 18869, 18870, 18871 } },
        { key = "conflagrate",   ids = { 17962, 18930, 18931, 18932 } },
        { key = "amplifycurse",  ids = { 18288 } },
        { key = "feldomination", ids = { 18708 } },
        { key = "shadowward",    ids = { 6229, 11739, 11740, 28610 } },
    },
    range = {
        { yards = 30, spells = { 686, 172, 348 }, interact = 4 },   -- Shadow Bolt, Corruption, Immolate
        { yards = 20, spells = { 6789, 5782 } },                    -- Death Coil, Fear
    },
}

CLASSES.HUNTER = {
    cooldowns = {
        { key = "rapidfire",     ids = { 3045 }, dur = 15 },
        { key = "feigndeath",    ids = { 5384 } },
        { key = "disengage",     ids = { 781, 14272, 14273 } },
        { key = "aimedshot",     ids = { 19434, 20900, 20901, 20902, 20903, 20904 } },
        { key = "arcaneshot",    ids = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 } },
        { key = "multishot",     ids = { 2643, 14288, 14289, 14290 } },
        { key = "concussive",    ids = { 5116 } },
        { key = "scattershot",   ids = { 19503 } },
        { key = "intimidation",  ids = { 19577 } },
        { key = "bestialwrath",  ids = { 19574 }, dur = 18 },
        { key = "deterrence",    ids = { 19263 }, dur = 10 },
        { key = "counterattack", ids = { 19306, 20909, 20910 } },
        { key = "wyvernsting",   ids = { 19386, 24132, 24133 } },
        { key = "freezingtrap",  ids = { 1499, 14310, 14311 } },
        { key = "frosttrap",     ids = { 13809 } },
        { key = "explosivetrap", ids = { 13813, 14316, 14317 } },
    },
    range = {
        { yards = 35, spells = { 75, 3044, 1978 }, interact = 4 },   -- Auto Shot, Arcane Shot, Serpent Sting
        { yards = 0,  spells = { 2973, 1495 } },                     -- Raptor Strike, Mongoose Bite
    },
}

CLASSES.SHAMAN = {
    cooldowns = {
        { key = "earthshock",    ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } },
        { key = "flameshock",    ids = { 8050, 8052, 8053, 10447, 10448, 29228 } },
        { key = "frostshock",    ids = { 8056, 8058, 10472, 10473 } },
        { key = "grounding",     ids = { 8177 } },
        { key = "manatide",      ids = { 16190, 17354, 17359 } },
        { key = "elemastery",    ids = { 16166 } },
        { key = "naturesswift",  ids = { 16188 } },
        { key = "stormstrike",   ids = { 17364 } },
        { key = "firenova",      ids = { 1535, 8498, 8499, 11314, 11315 } },
        { key = "earthbind",     ids = { 2484 } },
        { key = "stoneclaw",     ids = { 5730, 6390, 6391, 6392, 10427, 10428 } },
        { key = "chainlight",    ids = { 421, 930, 2860, 10605 } },
    },
    range = {
        { yards = 30, spells = { 403, 421 }, interact = 4 },   -- Lightning Bolt, Chain Lightning
        { yards = 20, spells = { 8042, 8050, 8056 } },         -- shocks
    },
}

CLASSES.PALADIN = {
    cooldowns = {
        { key = "divineshield",  ids = { 642, 1020 }, dur = 10 },
        { key = "divineprot",    ids = { 498, 5573 }, dur = 6 },
        { key = "blessingprot",  ids = { 1022, 5599, 10278 } },
        { key = "layonhands",    ids = { 633, 2800, 10310 } },
        { key = "hammerjustice", ids = { 853, 5588, 5589, 10308 } },
        { key = "hammerwrath",   ids = { 24275, 24274, 24239 } },
        { key = "consecration",  ids = { 26573, 20116, 20922, 20923, 20924 } },
        { key = "exorcism",      ids = { 879, 5614, 5615, 10312, 10313, 10314 } },
        { key = "holyshock",     ids = { 20473, 20929, 20930 } },
        { key = "repentance",    ids = { 20066 } },
        { key = "divinefavor",   ids = { 20216 } },
        { key = "freedom",       ids = { 1044 } },
        { key = "holyshield",    ids = { 20925, 20927, 20928 } },
        { key = "judgement",     ids = { 20271 } },
    },
    range = {
        { yards = 30, spells = { 879, 24275 }, interact = 4 },   -- Exorcism, Hammer of Wrath
        { yards = 10, spells = { 853, 20271 } },                 -- Hammer of Justice, Judgement
    },
}

-- lockouts: debuffs that block an ability or item although it has no cooldown
--   aura = the debuff's spell ID, dur = its length when the game hides it
ns.Lockouts = {
    bandage = { aura = 11196, dur = 60 },   -- Recently Bandaged
}
-- bandages of Classic (item IDs); others are recognized by their item subclass
ns.BANDAGES = {}
for _, id in ipairs({ 1251, 2581, 3530, 3531, 6450, 6451, 8544, 8545, 14529, 14530, 19307,
                      19066, 19067, 19068, 20065, 20066, 20067, 20232, 20234, 20235, 20237, 20243, 20244 }) do
    ns.BANDAGES[id] = true
end

-- racial abilities (WoW: Forever IDs where known). Only the ones your own
-- character knows ever show. A racial can report another spell ID when cast
-- than in the spellbook, so the tracker also matches casts by name.
ns.Racials = {
    { key = "willtosurvive", ids = { 1259718 } },             -- Human
    { key = "perception",    ids = { 20600 }, dur = 20 },     -- Human
    { key = "stoneform",     ids = { 20594 }, dur = 8 },      -- Dwarf
    { key = "eluneslight",   ids = { 1259799 }, dur = 15 },   -- Night Elf
    { key = "shadowmeld",    ids = { 20580 } },               -- Night Elf
    { key = "escapeartist",  ids = { 20589 } },               -- Gnome
    { key = "eureka",        ids = { 1259812 } },             -- Gnome
    { key = "bloodfury",     ids = { 20572 }, dur = 15 },     -- Orc
    { key = "shattercurse",  ids = { 1299026 }, dur = 8 },    -- Orc
    { key = "willforsaken",  ids = { 7744 } },                -- Undead
    { key = "cannibalize",   ids = { 20577 } },               -- Undead
    { key = "warstomp",      ids = { 20549 } },               -- Tauren
    { key = "berserking",    ids = { 20554 }, dur = 10 },     -- Troll
    { key = "rapidregen",    ids = { 1260270 } },             -- Troll
}

function ns.ClassPack()
    return CLASSES[ns.playerClass or ""] or { cooldowns = {}, range = {} }
end
