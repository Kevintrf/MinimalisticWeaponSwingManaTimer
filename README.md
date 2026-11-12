# MinimalisticWeaponSwingManaTimer

A minimal swing timer and mana five-second-rule bar for **WoW: Forever** (Interface `16001`).

A thin bar sits below your character, near screen center, with two lanes:

| Lane | Default size | Shows |
|---|---|---|
| Swing timer | 200 × 4 px | Main-hand swing. Light gray fill (`#D3D1C7`) on a dark track (`#2C2C2A`) that restarts each time a swing lands. |
| Mana (five-second rule) | 200 × 2 px, 2 px below | Blue (`#378ADD`) on the same track. Fills from left to right over 5 s after any spell that costs mana. |

When nothing is counting, the bar fades out.

## Install

Put this folder in your Forever AddOns folder (`<WoW folder>/_forever_/Interface/AddOns/`) as `MinimalisticWeaponSwingManaTimer`. The folder name must match the `.toc` file.

## Settings

Open **Esc → Options → AddOns → Minimalistic Swing Mana Timer**, or type `/minswingmanatimer`. While that page is open, the bar shows as a preview.

All settings are also available as `/minswingmanatimer <command>`:

| Command | Effect |
|---|---|
| `options` | Open the options page (same as no command) |
| `lock` / `unlock` | Unlock to drag the bar. It always starts locked |
| `x <n>` / `y <n>` | Offset of the bar's top edge from screen center (−1500 to 1500 / −1000 to 1000) |
| `width <n>` | Bar width, 20 to 1000 |
| `height <swing> [mana]` | Lane heights, 1 to 30 |
| `swing auto\|combat\|always\|off` | Swing lane visibility (see below) |
| `mana auto\|combat\|always\|off` | Mana lane visibility |
| `native on\|off` | Show or hide Blizzard's built-in swing timer |
| `resets on\|off` | Show swing restarts caused by casts while out of combat |
| `dim on\|off` | Darken the full bar while auto-attack is on but no swing lands |
| `test` | Play two fake swings and the mana timer |
| `reset` | Reset position, width and heights |
| `resetall` | Reset every setting of this addon (also the "Reset everything" button) |
| `debug` | Print events and API checks (see below) |

**Visibility modes:**
- `auto` shows a lane only while it counts. For the swing lane, that includes while auto-attacking and after you've swung in the current fight.
- `combat` also shows the lane for the whole fight.
- `always` keeps it up.
- `off` disables it.

An idle lane that its mode keeps up shows as a full bar.

**Defaults:**
- position `x 0`, `y -150`
- width 200, heights 4 and 2
- both lanes `combat`
- Blizzard's swing timer hidden
- out-of-combat cast resets hidden
- dimming off

## Behavior

- **Mana timer:** starts after a successful cast that costs mana and restarts on the next one. Free spells don't affect it. It never shows for classes without mana, or for druids in Cat or Bear Form.
- **Cast resets:** Classic resets the swing on casts such as Skinning, crafting or War Stomp. Out of combat, those restarts stay hidden unless `resets on` is set.
- **Dimming:** when it's on and no swing lands within 0.3 s of the bar being full, the bar dims to `#5F5E5A`. Turning auto-attack on with no swing running starts dimmed straight away. This also triggers when you're facing away or stunned, because Forever gives addons no working range check.
- **Blizzard's swing timer:** the addon remembers your own `showSwingTimer` value, sets it to 0 while the addon runs, and restores it at logout. Disabling the addon brings Blizzard's bars back. The setting is only changed out of combat.
- **Options page:** Blizzard's shared "Defaults" button resets every game setting, so it's hidden on this page. Use "Reset everything" to reset only this addon.
- **Performance:** while idle the addon does nothing between events. Per-frame updates run only while a lane is filling.

## How it works on Forever

Forever restricts the addon API compared with Classic Era. Everything below was checked in game unless noted.

- **The combat log is hidden from addons.** Swings come from the embedded [LibClassicSwingTimerAPI](https://github.com/Ralgathor/LibClassicSwingTimerAPI) 2.3.0. On Forever, it's driven by Blizzard's `PLAYER_SWING` event, whose swing duration stays readable in combat.
- **Health and mana are secret, even out of combat.** `UnitHealth` and `UnitPower` return secret values. Their maximums are readable. `UnitAttackSpeed` is secret in combat only. The mana timer therefore never reads mana. It uses `UNIT_SPELLCAST_SUCCEEDED` plus `C_Spell.GetSpellPowerCost`, both of which stay readable in combat. Values that might be secret are checked with `issecretvalue` before use.
- **Has mana:** `UnitPowerType("player")` is readable in combat.
- **Blizzard's range checks don't work for addons.** `C_SwingTimer.IsTargetWithinSwingRange(0)` and `C_Spell.IsSpellInRange(6603, "target")` both return nil. That's why dimming uses the "no swing landed" rule.
- **Pixel snapping:** `PixelUtil` exists and keeps the 2 px lines sharp.
- **Options page:** uses Blizzard's Settings API (`Settings.RegisterVerticalLayoutCategory`, `RegisterAddOnSetting`, `CreateSlider`, `CreateCheckbox`, `CreateDropdown`). Its use was checked against Blizzard's Forever UI source mirror (Gethe/wow-ui-source, `forever` branch).
- **`debug`** prints library swing events, casts with their mana cost, and an API probe. The probe reports whether health, mana and attack speed are secret, and whether the range APIs and `PixelUtil` exist. It runs when debug is turned on, 1 s into each fight, and when the fight ends.

## Files

```
MinimalisticWeaponSwingManaTimer.toc
config.lua   saved variables, Blizzard swing timer setting, slash command, options page
bar.lua      frames, pixel snapping, dragging, lane animation, fading
core.lua     events, swing and mana logic, test, debug
libs/        LibStub, CallbackHandler-1.0, LibClassicSwingTimerAPI
```

## Development

On Linux, symlink your clone into the AddOns folder instead of copying it, so the game loads your working copy:

```sh
ln -s /path/to/MinimalisticWeaponSwingManaTimer \
  "<WoW folder>/_forever_/Interface/AddOns/MinimalisticWeaponSwingManaTimer"
```

When WoW runs under Wine or Proton, `<WoW folder>` is inside the Wine prefix, for example `<prefix>/drive_c/Program Files (x86)/World of Warcraft`. If the game doesn't follow the link, copy the folder instead.

After editing code, `/reload` in game picks up the changes. A new or renamed file in the `.toc` needs a full game restart.

To check the logic without the game, run the headless smoke test from the repo root with Lua 5.1:

```sh
lua5.1 tests/smoke.lua
```

It loads the addon with stubbed WoW functions and drives swings, casts, combat, slash commands and the options page through fake time. It ends with `ALL OK`, or stops at the first failed check. It covers the addon's own logic only, so behavior of the real Forever APIs still needs testing in game. The test isn't listed in the `.toc`, so the game never loads it.

## License

Released under the **GNU General Public License v3.0 or later** (GPL-3.0-or-later). The full text is in [LICENSE](LICENSE).

> Copyright (C) 2026 the MinimalisticWeaponSwingManaTimer authors.
>
> This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
>
> This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

### Bundled libraries

| Library | Author | License |
|---|---|---|
| [LibClassicSwingTimerAPI](https://github.com/Ralgathor/LibClassicSwingTimerAPI) 2.3.0 | Ralgathor | GPL-3 ([`libs/LibClassicSwingTimerAPI/LICENSE`](libs/LibClassicSwingTimerAPI/LICENSE)) |
| [CallbackHandler-1.0](https://github.com/WoWUIDev/Ace3) | Ace3 Development Team | Ace3 license: BSD-style, and the library may not be redistributed on its own ([`libs/CallbackHandler-1.0/LICENSE.txt`](libs/CallbackHandler-1.0/LICENSE.txt)) |
| LibStub | WowAce community | Public domain (stated in the file) |
