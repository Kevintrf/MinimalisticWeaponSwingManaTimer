-- Headless smoke test: loads the addon and the embedded libraries with stubbed WoW functions,
-- then drives swings, casts, combat, slash commands and the options page through fake time.
-- It checks the addon's own logic only; real API behavior on Forever still needs in-game testing.
--
-- Run from the repo root with Lua 5.1 (WoW's Lua version):  lua5.1 tests/smoke.lua
-- Prints each step and ends with "ALL OK"; any failed check stops with an assertion error.
local now = 100
function GetTime() return now end
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers+1] = {t = now + d, fn = fn} end,
  NewTimer = function(d, fn) local h = {c=false}; function h:Cancel() self.c=true end; function h:IsCancelled() return self.c end
    timers[#timers+1] = {t = now + d, fn = function() if not h.c then fn() end end}; return h end }
local function advance(dt) local target = now + dt
  while true do table.sort(timers, function(a,b) return a.t < b.t end)
    local t = timers[1]; if not t or t.t > target then break end
    table.remove(timers, 1); now = t.t; t.fn() end
  now = target end
local frames = {}
anims = {}
function settle() for a in pairs(anims) do if a.playing then a.playing = false; if a.scripts.OnFinished then a.scripts.OnFinished(a) end end end end
local function region()
  local r = {shown=true, alpha=1, scripts={}}
  return setmetatable(r, {__index = function(t, k)
    if k:match("^%l") then return nil end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "GetCenter" then return function() return 500, 400 end end
    if k == "GetTop" then return function() return 300 end end
    if k == "Play" then return function(s) s.playing = true; anims[s] = true end end
    if k == "Stop" then return function(s) s.playing = false end end
    if k == "IsPlaying" then return function(s) return s.playing == true end end
    if k == "SetValue" then return function(s, v) s.value = v end end
    if k == "SetStatusBarColor" then return function(s, r,g,b) s.color = string.format("%.2f", r) end end
    if k == "SetScript" then return function(s, n, f) s.scripts[n] = f end end
    if k == "GetScript" then return function(s, n) return s.scripts[n] end end
    if k == "RegisterEvent" or k == "RegisterUnitEvent" then return function(s, e) frames[e] = frames[e] or {}; table.insert(frames[e], s) end end
    if k == "GetPoint" then return function() return "TOPLEFT", nil, "BOTTOMLEFT", 10, 20 end end
    if k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return region() end end
    return function() end end})
end
function CreateFrame() return region() end
UIParent = region(); WorldFrame = region()
function fire(e, ...) for _, f in ipairs(frames[e] or {}) do if f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end end
_G.print = function(...) local t = {} for i=1,select('#',...) do t[i]=tostring((select(i,...))) end io.write("  > ", table.concat(t," "), "\n") end
SlashCmdList = {}
function strtrim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
function strsplit(sep, s, n) local a, b = s:match("^(%S*)%s*(.-)$"); return a, b ~= "" and b or nil end
function InCombatLockdown() return incombat end
local cvars = {showSwingTimer = "1"}
C_CVar = {GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = v end}
function UnitAttackSpeed() return 2.4, nil end
function UnitGUID() return "Player-1" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitHealth() return 100 end UnitHealthMax = UnitHealth UnitPower = UnitHealth UnitPowerMax = UnitHealth
ptype = 1
function UnitPowerType() return ptype end
function GetBuildInfo() return "1.6", "1", "", 16001 end
function GetInventoryItemID() end function GetSpellInfo() end function UnitRangedDamage() return 0 end
function issecretvalue() return false end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
C_Spell = {GetSpellPowerCost = function(id) return id == 1 and {{type=0, cost=50}} or {} end}
INVSLOT_RANGED = 18
GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR" end; UnitAura = function() end; GetItemInfo = function() end; C_Item = {GetItemInfo = function() end}
strmatch = string.match; geterrorhandler = function() return error end; securecallfunction = function(f, ...) return f(...) end; unpack = unpack or table.unpack; wipe = function(t) for k in pairs(t) do t[k]=nil end return t end; tinsert = table.insert

MinSwingManaTimerDB = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 800, y = 600, width = 250, readyInAnyCombat = true }

-- Settings API stubs (shape taken from the Forever UI source readme)
panel = { settings = {}, buttons = {}, opened = nil }
local function mksetting(tbl, key, default)
  if tbl[key] == nil then tbl[key] = default end
  local st = { cbs = {} }
  function st:SetValueChangedCallback(cb) self.cbs[#self.cbs+1] = cb end
  function st:NotifyUpdate() for _, cb in ipairs(self.cbs) do cb(self, tbl[key]) end end
  function st:SetValue(v) tbl[key] = v; for _, cb in ipairs(self.cbs) do cb(self, v) end end
  return st
end
Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  CreateDropdown = function(cat, st, getOptions) local d = getOptions(); assert(#d == 4 and d[2].value == "combat") end,
  CreateControlTextContainer = function() local d = {}; return { Add = function(_, v, l) d[#d+1] = { value = v, label = l } end, GetData = function() return d end } end,
  RegisterVerticalLayoutCategory = function(name) panel.category = { GetID = function() return 42 end }; return panel.category, { AddInitializer = function(_, i) if i.click then panel.buttons[i.text] = i.click end end } end,
  RegisterAddOnSetting = function(cat, var, key, tbl, vt, name, default) assert(type(default) == vt, key); local st = mksetting(tbl, key, default); panel.settings[key] = st; return st end,
  CreateSliderOptions = function(a, b, step) return { SetLabelFormatter = function(_, _, f) assert(f(149.6) == 150) end } end,
  CreateSlider = function() end, CreateCheckbox = function() end, RegisterAddOnCategory = function() end,
  OpenToCategory = function(id) panel.opened = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
function CreateSettingsListSectionHeaderInitializer(name) return {} end
local cbs = {}
EventRegistry = { RegisterCallback = function(_, ev, fn, owner) cbs[ev] = function(...) fn(owner, ...) end end }
function ns_category() return panel.category end
function triggerEvent(ev, ...) cbs[ev](...) end
defaultsBtn = { shown = true, SetShown = function(self, v) self.shown = v end }
SettingsPanel = { GetSettingsList = function() return { Header = { DefaultsButton = defaultsBtn } } end }
function CreateSettingsButtonInitializer(name, text, click, tip, tags) assert(tags ~= nil); return { text = text, click = click } end
local ns = {}
local root = arg[1] or arg[0]:match("^(.*)/tests/[^/]*$") or "."
for _, f in ipairs{"libs/LibStub/LibStub.lua","libs/CallbackHandler-1.0/CallbackHandler-1.0.lua","libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua","config.lua","bar.lua","core.lua"} do
  assert(loadfile(root.."/"..f))("MinimalisticWeaponSwingManaTimer", ns)
end
fire("ADDON_LOADED", "MinimalisticWeaponSwingManaTimer"); fire("PLAYER_LOGIN"); assert(cvars.showSwingTimer == "0", "native hidden by default"); fire("PLAYER_ENTERING_WORLD")
assert(MinSwingManaTimerDB.x == 0 and MinSwingManaTimerDB.y == -150 and MinSwingManaTimerDB.width == 250 and not MinSwingManaTimerDB.point and MinSwingManaTimerDB.swingMode == "combat" and MinSwingManaTimerDB.readyInAnyCombat == nil, "migration")
local swing = ns.swing
local function st(label) settle() print(string.format("%-34s shown=%-5s value=%-4s color=%s", label, tostring(swing.shown), tostring(swing.value and string.format("%.2f", swing.value)), tostring(swing.color))) end
local function frame() local ou = ns.bar.scripts.OnUpdate; if ou then ou() end end
local function rawshown(l) return l.shown end
st("idle")
assert(not swing.shown)

-- test command
SlashCmdList.MINSWINGMANATIMER("test"); st("test start")
assert(swing.shown and ns.bar.scripts.OnUpdate)
advance(1.2); frame(); st("test half"); assert(math.abs(swing.value-0.5)<0.01)
advance(2.4); frame(); st("test 2nd swing half")
advance(1.3); frame(); st("test done"); assert(not swing.shown, "out of combat must hide")
advance(0.2); frame(); assert(not ns.bar.scripts.OnUpdate, "OnUpdate must detach when idle")

-- real flow via library: enter combat, auto-attack, swings
incombat = true; fire("PLAYER_REGEN_DISABLED"); st("combat (any), no swing yet"); assert(swing.shown and swing.value == 1)
SlashCmdList.MINSWINGMANATIMER("swing auto"); st("combat (swing auto), no swing yet"); assert(not swing.shown)
fire("PLAYER_ENTER_COMBAT"); st("attack on, dim off (default)"); assert(swing.shown and swing.color == "0.83", "no dim by default")
SlashCmdList.MINSWINGMANATIMER("dim on"); st("attack on, dim on"); assert(swing.shown and swing.color == "0.37", "starts dim")
fire("PLAYER_SWING", 2.4, 0); st("swing landed"); assert(swing.color=="0.83")
advance(2.4); frame(); st("swing ready (lib STOP)"); assert(swing.shown and swing.value==1 and swing.color=="0.83", "grace after a swing")
advance(0.31); st("overdue 0.31s"); assert(swing.color=="0.37")
advance(0.1); fire("PLAYER_SWING", 2.4, 0); st("next swing landed")
fire("PLAYER_LEAVE_COMBAT"); advance(2.4); frame(); st("attack off, ready, in combat"); assert(swing.shown and swing.color=="0.83")
incombat = false; fire("PLAYER_REGEN_ENABLED"); st("combat over"); assert(not swing.shown)
SlashCmdList.MINSWINGMANATIMER("swing combat"); assert(MinSwingManaTimerDB.swingMode == "combat" and not swing.shown)

-- slash commands
SlashCmdList.MINSWINGMANATIMER("native off"); assert(cvars.showSwingTimer == "0")
fire("PLAYER_LOGOUT"); assert(cvars.showSwingTimer == "1")
SlashCmdList.MINSWINGMANATIMER("width 300"); assert(MinSwingManaTimerDB.width == 300)
SlashCmdList.MINSWINGMANATIMER("x 40"); SlashCmdList.MINSWINGMANATIMER("y -200.4"); SlashCmdList.MINSWINGMANATIMER("height 6")
local db = MinSwingManaTimerDB; assert(db.x == 40 and db.y == -200 and db.swingHeight == 6 and db.manaHeight == 2)
SlashCmdList.MINSWINGMANATIMER("height 5 3"); assert(db.swingHeight == 5 and db.manaHeight == 3)
SlashCmdList.MINSWINGMANATIMER("height 0"); assert(db.swingHeight == 5)
ns.bar.scripts.OnDragStop(ns.bar); assert(db.x == 0 and db.y == -100, "drag saves top-edge offset from center")
SlashCmdList.MINSWINGMANATIMER("reset"); assert(db.width == 200 and db.y == -150 and db.swingHeight == 4 and db.manaHeight == 2)
SlashCmdList.MINSWINGMANATIMER("debug"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1)
local mana = ns.mana
local function ms(label) settle() print(string.format("%-34s mana shown=%-5s value=%s", label, tostring(mana.shown), tostring(mana.value and string.format("%.2f", mana.value)))) end
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 1); ms("rage class casts mana spell"); assert(not mana.shown)
ptype = 0
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2); ms("free spell"); assert(not mana.shown)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 1); ms("mana spell"); assert(mana.shown and mana.value == 0)
advance(2.5); frame(); ms("2.5 s"); assert(math.abs(mana.value - 0.5) < 0.01)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2); frame(); ms("free spell mid-window"); assert(math.abs(mana.value - 0.5) < 0.01)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 1); ms("mana spell resets"); assert(mana.value == 0)
advance(1); ptype = 3; fire("UPDATE_SHAPESHIFT_FORM"); frame(); ms("cat form"); assert(not mana.shown)
ptype = 0; fire("UNIT_DISPLAYPOWER", "player"); frame(); ms("caster form again"); assert(mana.shown)
advance(4.1); frame(); assert(rawshown(mana), "fade keeps lane during fade"); ms("5 s over"); assert(not mana.shown and mana.value == 1)
assert(not ns.bar.scripts.OnUpdate, "OnUpdate must detach")
SlashCmdList.MINSWINGMANATIMER("test"); ms("test"); assert(mana.shown and swing.shown)
advance(5); frame(); advance(0.1); frame(); ms("test over"); assert(not mana.shown and not swing.shown)
-- swing ends while mana still counts: swing hides at once, no fade
SlashCmdList.MINSWINGMANATIMER("test"); advance(4.85); frame()
assert(not rawshown(swing) and rawshown(mana), "swing hides immediately while mana counts")
advance(1); frame(); settle(); assert(not rawshown(mana))
-- out-of-combat cast resets hidden by default, shown with resets on
fire("PLAYER_EQUIPMENT_CHANGED", 16); st("ooc reset (default)"); assert(not swing.shown)
SlashCmdList.MINSWINGMANATIMER("resets on"); fire("PLAYER_EQUIPMENT_CHANGED", 16); st("ooc reset (resets on)"); assert(swing.shown)
advance(2.5); frame(); st("reset swing done"); assert(not swing.shown)
SlashCmdList.MINSWINGMANATIMER("resets off")
incombat = true; fire("PLAYER_REGEN_DISABLED"); fire("PLAYER_EQUIPMENT_CHANGED", 16); st("in-combat reset"); assert(swing.shown and swing.value < 0.01)
-- options panel
SlashCmdList.MINSWINGMANATIMER(""); assert(panel.opened == 42, "empty command opens panel")
panel.settings.width:SetValue(321); assert(MinSwingManaTimerDB.width == 321)
incombat = false
panel.settings.hideNative:SetValue(true); assert(C_CVar.GetCVar("showSwingTimer") == "0")
panel.settings.hideNative:SetValue(false); assert(C_CVar.GetCVar("showSwingTimer") == "1")
panel.buttons["Lock / Unlock"](); assert(ns.locked == false); panel.buttons["Lock / Unlock"](); assert(ns.locked == true)
panel.buttons["Reset"](); assert(MinSwingManaTimerDB.width == 200)
SlashCmdList.MINSWINGMANATIMER("width 5000"); assert(MinSwingManaTimerDB.width == 200)
SlashCmdList.MINSWINGMANATIMER("height 31"); assert(MinSwingManaTimerDB.swingHeight == 4)
panel.buttons["Test"]()
advance(6); frame(); settle(); incombat = false; fire("PLAYER_REGEN_ENABLED"); settle()
assert(not swing.shown and not mana.shown, "idle before mode tests")
-- modes
SlashCmdList.MINSWINGMANATIMER("swing always"); settle(); assert(swing.shown and swing.value == 1, "swing always idle = full")
SlashCmdList.MINSWINGMANATIMER("mana always"); settle(); assert(mana.shown and mana.value == 1, "mana always idle = full")
SlashCmdList.MINSWINGMANATIMER("swing off"); SlashCmdList.MINSWINGMANATIMER("mana combat"); settle()
assert(not swing.shown and not mana.shown)
SlashCmdList.MINSWINGMANATIMER("test"); settle(); assert(not swing.shown and mana.shown, "swing off hides test swing")
advance(6); frame(); settle(); assert(not mana.shown)
incombat = true; fire("PLAYER_REGEN_DISABLED"); settle(); assert(mana.shown and not swing.shown, "mana combat shows in combat")
incombat = false; fire("PLAYER_REGEN_ENABLED"); settle(); assert(not mana.shown)
-- preview while our page is open, Defaults hidden there
triggerEvent("Settings.CategoryChanged", "other"); assert(defaultsBtn.shown and not swing.shown)
triggerEvent("Settings.CategoryChanged", ns_category()); settle()
assert(swing.shown and mana.shown and mana.value == 1 and not defaultsBtn.shown, "preview")
triggerEvent("SettingsPanel.OnHide"); settle(); assert(defaultsBtn.shown and not swing.shown and not mana.shown)
-- reset everything
SlashCmdList.MINSWINGMANATIMER("native on"); assert(C_CVar.GetCVar("showSwingTimer") == "1")
SlashCmdList.MINSWINGMANATIMER("mana auto"); SlashCmdList.MINSWINGMANATIMER("width 300")
panel.buttons["Reset everything"]()
local db = MinSwingManaTimerDB
assert(not db.dimBlocked and db.swingMode == "combat" and db.manaMode == "combat" and db.hideNative and db.width == 200 and C_CVar.GetCVar("showSwingTimer") == "0")
print("ALL OK")
