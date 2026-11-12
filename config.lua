local _, ns = ...

-- x/y: offset of the bar's top edge from screen center.
local defaults = { x = 0, y = -150, width = 200, swingHeight = 4, manaHeight = 2, hideNative = true,
	swingMode = "combat", manaMode = "combat", showResets = false, dimBlocked = false }
-- Lane visibility modes, in dropdown order.
local MODES = { { "auto", "Only while counting" }, { "combat", "Always while in combat" }, { "always", "Always" }, { "off", "Disabled" } }
local MODE_ARGS = { auto = true, combat = true, always = true, off = true }
-- Ranges shared by the slash command and the options panel sliders.
local LIMITS = { x = { -1500, 1500 }, y = { -1000, 1000 }, width = { 20, 1000 }, swingHeight = { 1, 30 }, manaHeight = { 1, 30 } }
local LAYOUT_KEYS = { "x", "y", "width", "swingHeight", "manaHeight" }
local NATIVE_CVAR = "showSwingTimer"

function ns.Print(...)
	print("|cff378addMinSwing|r", ...)
end

function ns.InitDB()
	MinSwingManaTimerDB = MinSwingManaTimerDB or {}
	local db = MinSwingManaTimerDB
	-- Positions saved before 0.2 used other anchors; drop them so the defaults apply.
	if db.point then db.point, db.relPoint, db.x, db.y = nil, nil, nil, nil end
	-- 0.2's "full swing bar in any combat" became swing mode "combat" ("auto" when it was off).
	if db.readyInAnyCombat ~= nil then
		db.swingMode = db.readyInAnyCombat and "combat" or "auto"
		db.readyInAnyCombat = nil
	end
	for k, v in pairs(defaults) do
		if MinSwingManaTimerDB[k] == nil then MinSwingManaTimerDB[k] = v end
	end
	ns.db = MinSwingManaTimerDB
end

-- Hide Forever's built-in swing timer while the addon runs; db.nativeWas keeps the user's own value.
function ns.ApplyNative()
	local db = ns.db
	if InCombatLockdown() then return ns.Print("can't change the native swing timer in combat") end
	local current = C_CVar.GetCVar(NATIVE_CVAR)
	if current == nil then return ns.Print("native swing timer setting '" .. NATIVE_CVAR .. "' not found") end
	if db.hideNative then
		if current ~= "0" then db.nativeWas = current end
		C_CVar.SetCVar(NATIVE_CVAR, "0")
	elseif db.nativeWas then
		C_CVar.SetCVar(NATIVE_CVAR, db.nativeWas)
		db.nativeWas = nil
	end
end

-- Give the native timer back on logout so disabling the addon restores it; ApplyNative re-hides at login.
function ns.RestoreNative()
	local db = ns.db
	if db and db.hideNative and db.nativeWas and not InCombatLockdown() then
		C_CVar.SetCVar(NATIVE_CVAR, db.nativeWas)
	end
end

local HELP = "commands: options, lock, unlock, test, debug, reset, resetall, x <n>, y <n>, width <n>, height <swing> [mana], swing|mana auto|combat|always|off, native on|off, resets on|off, dim on|off"

local function Layout()
	ns.Layout()
	local db = ns.db
	ns.Print(("x %d, y %d, width %d, height %d/%d"):format(db.x, db.y, db.width, db.swingHeight, db.manaHeight))
end

local function InRange(key, n)
	return n and n >= LIMITS[key][1] and n <= LIMITS[key][2]
end

local function Usage(key)
	return ns.Print(("usage: %s <%d to %d>"):format(key, LIMITS[key][1], LIMITS[key][2]))
end

-- Esc > Options > AddOns page (Blizzard Settings API; usage checked against the Forever UI source).
-- Settings write straight into the saved table; the callbacks apply the change.
local settings, syncing, category = {}, false, nil

local function ApplySetting(key)
	if syncing then return end
	if LIMITS[key] then ns.Layout()
	elseif key == "hideNative" then ns.ApplyNative()
	elseif key == "swingMode" or key == "dimBlocked" then ns.RefreshSwing()
	elseif key == "manaMode" then ns.RefreshMana() end
end

-- Let open panel controls re-read values changed by slash commands or the Reset button.
local function SyncOptions()
	syncing = true
	for _, setting in pairs(settings) do setting:NotifyUpdate() end
	syncing = false
end

local function Slash(cmd)
	SlashCmdList.MINSWINGMANATIMER(cmd)
end

function ns.InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
	local db, layout = ns.db, nil
	category, layout = Settings.RegisterVerticalLayoutCategory("Minimalistic Swing Mana Timer")

	local function Header(name)
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
	end
	local function Button(name, text, onClick, tooltip)
		layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
	end
	local function Add(key, name, tooltip)
		local varType = ({ boolean = Settings.VarType.Boolean, number = Settings.VarType.Number, string = Settings.VarType.String })[type(defaults[key])]
		local setting = Settings.RegisterAddOnSetting(category, "MinSwingManaTimer_" .. key, key, db, varType, name, defaults[key])
		setting:SetValueChangedCallback(function() ApplySetting(key) end)
		settings[key] = setting
		if LIMITS[key] then
			local options = Settings.CreateSliderOptions(LIMITS[key][1], LIMITS[key][2], 1)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return math.floor(v + 0.5) end)
			Settings.CreateSlider(category, setting, options, tooltip)
		elseif varType == Settings.VarType.String then
			Settings.CreateDropdown(category, setting, function()
				local container = Settings.CreateControlTextContainer()
				for _, mode in ipairs(MODES) do container:Add(mode[1], mode[2]) end
				return container:GetData()
			end, tooltip)
		else
			Settings.CreateCheckbox(category, setting, tooltip)
		end
	end

	Header("Position and size")
	Button("Move the bar", "Lock / Unlock", function() Slash(ns.locked and "unlock" or "lock") end,
		"Unlock, close this window, then drag the bar. Lock again when done.")
	Add("x", "X offset", "Horizontal offset of the bar from screen center.")
	Add("y", "Y offset", "Vertical offset of the bar's top edge from screen center.")
	Add("width", "Width", "Bar width in pixels.")
	Add("swingHeight", "Swing lane height", "Height of the swing timer lane in pixels.")
	Add("manaHeight", "Mana lane height", "Height of the five-second-rule lane in pixels.")
	Button("Reset position and size", "Reset", function() Slash("reset") end, "Restore the default position, width and heights.")

	Header("Behavior")
	Add("hideNative", "Hide Blizzard's swing timer", "Turns off the built-in swing timer while this addon runs (can't change in combat).")
	Add("swingMode", "Show swing timer", "Only while counting: while a swing runs, while auto-attacking, and after swinging in a fight.\nAlways while in combat: also a full bar for the whole fight.")
	Add("manaMode", "Show mana timer", "Only while counting: during the 5 s after a mana spell. Never shown for classes without mana or in Cat/Bear Form.")
	Add("dimBlocked", "Dim when the swing can't land", "Darken the full swing bar while auto-attack is on but no swing lands: out of range, facing away, or stunned.")
	Add("showResets", "Show cast resets out of combat", "Show the swing restarting after casts such as Skinning or crafting while out of combat.")
	Button("Preview", "Test", function() ns.Test() end, "Play two fake swings and the five-second-rule timer.")
	Button("Reset this addon", "Reset everything", function() Slash("resetall") end, "Restore every setting of this addon (only this addon) to its default.")

	Settings.RegisterAddOnCategory(category)

	-- Blizzard's shared "Defaults" header button resets the whole game's settings, so hide it on this
	-- page, and show the bar as a preview while the page is open.
	-- shortcut: clearing the search box on this page brings Defaults back; ignored as harmless.
	local function OnCategory(_, shown)
		local ours = shown == category
		SettingsPanel:GetSettingsList().Header.DefaultsButton:SetShown(not ours)
		ns.SetPreview(ours)
	end
	EventRegistry:RegisterCallback("Settings.CategoryChanged", OnCategory, ns)
	EventRegistry:RegisterCallback("SettingsPanel.OnHide", function() OnCategory(nil, nil) end, ns)
end

SLASH_MINSWINGMANATIMER1 = "/minswingmanatimer"
SlashCmdList.MINSWINGMANATIMER = function(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	local db = ns.db
	if cmd == "" or cmd == "options" then
		if category then return Settings.OpenToCategory(category:GetID()) end
		ns.Print(HELP)
	elseif cmd == "lock" or cmd == "unlock" then
		ns.SetLocked(cmd == "lock")
		ns.Print(cmd == "lock" and "locked" or "unlocked: drag the bar to move it")
	elseif cmd == "test" then
		ns.Test()
	elseif cmd == "debug" then
		ns.debug = not ns.debug
		ns.Print("debug " .. (ns.debug and "on" or "off"))
		if ns.debug then ns.Probe() end
	elseif cmd == "reset" then
		for _, k in ipairs(LAYOUT_KEYS) do db[k] = defaults[k] end
		Layout()
	elseif cmd == "width" then
		local n = tonumber(arg)
		if not InRange("width", n) then return Usage("width") end
		db.width = math.floor(n)
		Layout()
	elseif cmd == "x" or cmd == "y" then
		local n = tonumber(arg)
		if not InRange(cmd, n) then return Usage(cmd) end
		db[cmd] = math.floor(n + 0.5)
		Layout()
	elseif cmd == "height" then
		local s, m = strsplit(" ", arg or "")
		s, m = tonumber(s), tonumber(m or db.manaHeight)
		if not (InRange("swingHeight", s) and InRange("manaHeight", m)) then
			return ns.Print(("usage: height <swing %d-%d> [mana %d-%d]"):format(LIMITS.swingHeight[1], LIMITS.swingHeight[2], LIMITS.manaHeight[1], LIMITS.manaHeight[2]))
		end
		db.swingHeight, db.manaHeight = math.floor(s), math.floor(m)
		Layout()
	elseif cmd == "native" and (arg == "on" or arg == "off") then
		db.hideNative = arg == "off"
		ns.ApplyNative()
		ns.Print("native swing timer " .. (db.hideNative and "hidden" or "restored"))
	elseif (cmd == "swing" or cmd == "mana") and MODE_ARGS[arg] then
		db[cmd .. "Mode"] = arg
		if cmd == "swing" then ns.RefreshSwing() else ns.RefreshMana() end
		ns.Print(cmd .. " timer: " .. arg)
	elseif cmd == "resetall" then
		for k, v in pairs(defaults) do db[k] = v end
		ns.ApplyNative()
		ns.RefreshSwing()
		ns.RefreshMana()
		Layout()
		ns.Print("all settings reset")
	elseif cmd == "resets" and (arg == "on" or arg == "off") then
		db.showResets = arg == "on"
		ns.Print("out of combat, cast-reset swings are " .. (db.showResets and "shown" or "hidden"))
	elseif cmd == "dim" and (arg == "on" or arg == "off") then
		db.dimBlocked = arg == "on"
		ns.RefreshSwing()
		ns.Print("dimming when the swing can't land: " .. arg)
	else
		ns.Print(HELP)
	end
	SyncOptions()
end
