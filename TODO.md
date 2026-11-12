# TODO

## Test in game

- [ ] **Mana timer in a dungeon.** Instanced combat may hide more values; the swing library saw a spell ID go secret mid-fight on another spell event. Run `debug` and watch the `cast` lines. If one shows `spellID SECRET` or `cost table SECRET`, the mana timer won't start, and needs a fallback such as caching costs per spell out of combat (scan the spellbook at login and on `SPELLS_CHANGED`).
- [ ] **Druid in Cat and Bear Form.** The mana lane should hide on shifting and return on leaving the form. Check that `UNIT_DISPLAYPOWER` or `UPDATE_SHAPESHIFT_FORM` show up in `debug`.
- [ ] **Blizzard's swing timer comes back:** disable the addon and relog.
- [ ] **No "interface action blocked" message** after `/reload` in combat followed by opening the options page. Hiding Blizzard's Defaults button touches a Blizzard frame.
- [ ] **Swing edge cases:**
  - weapon swap mid-fight (restarts the swing)
  - dying and resurrecting mid-swing
  - Slam-type spells that pause the swing
  - changing UI scale (lines should stay sharp)

## Features

- [ ] Off-hand line for dual wielding.
- [ ] Amber bar while Heroic Strike or Cleave is queued. Candidate APIs: `C_Spell.IsCurrentSpell`, or the library's next-melee tables. Unverified on Forever.
- [ ] Ranged and wand mode. The library already tracks `ranged`, so this mostly needs a lane.

## Fixes to try

- [ ] **Real out-of-range dimming** to replace the "no swing landed" rule.
  - Recheck `C_SwingTimer.IsTargetWithinSwingRange(0)` after each patch; `debug` prints it.
  - Still to probe: `C_Item.IsItemInRange`, and `IsSpellInRange` with a class melee spell.
- [ ] Blizzard's timed status bars (`StatusBar:SetTimerDuration`) could replace per-frame updates. Unverified on Forever.
- [ ] Dim delay (0.3 s): raise it or make it a setting if it flickers on high latency.
- [ ] The Defaults button reappears if you type in the settings search box and clear it on this addon's page. Harmless; leaving and reopening the page hides it again.

## Release

- [ ] **Working release through the [BigWigs packager](https://github.com/BigWigsMods/packager).** `.pkgmeta` is in place, and a local dry run built a correct Forever package (game version `1.60.1`). Still to do:
  - Commit everything; the packager only packages committed files.
  - Add `.github/workflows/release.yml` that runs the packager when a `v*` tag is pushed. Check out with `fetch-depth: 0`, and run `lua5.1 tests/smoke.lua` first so a failing test stops the release.
  - Push a `v1.0.0` tag and check the GitHub release and its zip.
- [ ] **Publish on CurseForge.**
  - Create the project on CurseForge by hand (new projects need approval), with game version Forever.
  - Add `## X-Curse-Project-ID: <id>` to the `.toc`.
  - Create a CurseForge API token and save it as the `CF_API_KEY` secret in the GitHub repo.
  - Push a tag and confirm the packager uploads the file.
- [ ] **Publish on Wago** (addons.wago.io, a second addon site that lists Forever `1.60.1`). The packager uploads to it from the same release.
  - Create the project on Wago.
  - Add `## X-Wago-ID: <id>` to the `.toc`.
  - Create a Wago API token and save it as the `WAGO_API_TOKEN` secret in the GitHub repo.

## Housekeeping

- [ ] After Forever patches, check for a newer LibClassicSwingTimerAPI (we embed 2.3.0).
