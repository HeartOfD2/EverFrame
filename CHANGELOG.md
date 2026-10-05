# Changelog

## 0.9.0 (Beta)

First public release of Ultimate EverRogue for World of Warcraft: Forever.

### Combat frame
- Health, resource (mana, rage, energy) with your own text format, combo points for rogues and druids in Cat Form, range bands to your target.
- Up to five cooldown bars with seven icons each: the class package, abilities found in your spellbook, your own potions, bandages and trinkets.
- Combo points as bars, circles or diamonds; at full points they glow, pulse, run a light wave or only change color, optionally with a sound (21 to pick from).
- Hide the frame out of combat, without a target or in a vehicle; holding ALT, CTRL or SHIFT shows it.
- Layout editor: order and visibility of every part, height, bar colors with a color picker (class color included), text format, size and alignment, warning zone, icon size, frame width, spacing and a background with color and opacity.

### Settings and tools in one window
- Sidebar with HUD (General, Layout, Cooldowns, Notes), Macros (Placeholders, Player macros, Templates, Rogue) and Addon pages; dark and light mode, teal, amber or blue accent.
- Macro manager: general and character macros in groups, icon search by spell or item name, spell search that puts `{s:ID}` into the text, export and import as one line of text.
- Templates with placeholders: spells in your game language (`{s:ID}`, with rank `{s:ID:r}`), weapon roles `{w:W1}` / `{w:W2}`, trinkets `{g:t1}` / `{g:t2}`, values of your own `{c:name}`. **Refresh** (or `/uer update`) rewrites every macro named exactly like a template; other macros are never touched. Macros made from a template carry a colored frame.
- New weapons or trinkets: after combat a short question suggests W1 / W2, and the macros follow.

### Notes
- Notebook with colored groups, notes per player and a popup when you target a player with notes (movable, resizable, lockable).
- Sticky notes on the screen with checkboxes and lists; they dock to each other. Sticky notes and the popup can step aside in combat.
- Export and import of notes and templates as a text code.

### Rogue module
- Poison tiles with time and charges: apply with a click, choose the poison with a right-click, warnings when low or missing.
- Slice and Dice timer, read from the buff where the game allows it.
- Weapon macros: swap macros "W1 MH UER" / "W2 MH UER", Backstab and Ambush with the dagger in the main hand, everything else with the weapon marked "Prefer main hand", Kick, Blind, Gouge and poison macros. Spell names come from the game; the macros are created and kept up to date for you, also without Dual Wield.

### General
- English and German; spell and item names always come from the game client.
- Settings per character; notes, theme and window position account-wide. Reset per category.
