local addonName, ns = ...

local lib = LibStub("LibClassicSwingTimerAPI", true)
local issecretvalue = issecretvalue or function() return false end

-- shortcut: "can't swing" stands in for "out of range" (Forever's range API is broken); see TODO.md.
local DIM_GRACE = 0.3

-- swungInCombat: a swing ran during this combat, so a full (ready) bar stays up until combat ends.
-- preview: the options page is open, so every lane shows.
local inCombat, attacking, inFlight, swungInCombat, readyAt, preview = false, false, false, false, 0, false

local MANA = 0 -- Enum.PowerType.Mana; UnitPowerType stays readable in combat (debug-verified)
local FIVE_SECOND_RULE = 5
local manaEnd = 0

local function show(v)
	return issecretvalue(v) and "SECRET" or tostring(v)
end

-- Lane visibility from its mode (db.swingMode / db.manaMode): "auto" only while counting,
-- "combat" also whenever in combat, "always", "off".
local function Want(mode, counting)
	if preview then return true end
	if mode == "off" then return false end
	return counting or mode == "always" or (mode == "combat" and inCombat)
end

-- Swing lane when no swing is in flight: full while auto-attacking or after swinging in combat (or
-- as its mode says), dimmed once a swing is overdue while auto-attacking, hidden otherwise.
-- Idempotent, so stale timers may call it.
local function RefreshSwing()
	local swing = ns.swing
	if inFlight then return ns.ShowLane(swing, Want(ns.db.swingMode, true)) end
	if not Want(ns.db.swingMode, attacking or (inCombat and swungInCombat)) then return ns.ShowLane(swing, false) end
	local wait = attacking and ns.db.dimBlocked and readyAt + DIM_GRACE - GetTime()
	ns.SetSwingColor(wait and wait <= 0 and "dim" or "fill")
	swing:SetValue(1)
	ns.ShowLane(swing, true)
	if wait and wait > 0 then C_Timer.After(wait, RefreshSwing) end
end

ns.RefreshSwing = RefreshSwing

local function SwingStop()
	inFlight = false
	readyAt = GetTime()
	ns.Animate(ns.swing)
	RefreshSwing()
end

local function SwingStart(speed, expiration, reason)
	-- Out of combat, cast resets (skinning, crafting, War Stomp...) stay hidden unless db.showResets.
	if reason ~= "swing" and not (inCombat or attacking or ns.db.showResets) then
		inFlight = false
		ns.Animate(ns.swing)
		return RefreshSwing()
	end
	inFlight, swungInCombat = true, true
	ns.SetSwingColor("fill")
	ns.ShowLane(ns.swing, Want(ns.db.swingMode, true))
	ns.Animate(ns.swing, expiration - speed, expiration)
end

local function SwingUpdate(speed, expiration)
	-- The library re-arms no timer (so sends no STOP) for an expiration already in the past.
	if expiration <= GetTime() then return SwingStop() end
	inFlight = true
	ns.Animate(ns.swing, expiration - speed, expiration)
end

-- Mana lane: visible while the 5 s window runs and the player is on mana (hides in Cat/Bear Form).
-- When shown idle (mode or preview), it shows full.
local function RefreshMana()
	local running = GetTime() < manaEnd
	if not running then ns.mana:SetValue(1) end -- idle (kept up by mode, preview, or fading): full blue
	ns.ShowLane(ns.mana, (preview or UnitPowerType("player") == MANA) and Want(ns.db.manaMode, running))
end
ns.mana.onDone = RefreshMana
ns.RefreshMana = RefreshMana

function ns.SetPreview(on)
	if preview == on then return end
	preview = on
	RefreshSwing()
	RefreshMana()
end

local function ManaStart()
	local now = GetTime()
	manaEnd = now + FIVE_SECOND_RULE
	ns.Animate(ns.mana, now, manaEnd)
	RefreshMana()
end

-- Whether a spell costs mana (from its cost table, never from mana values), plus a debug description.
local function ManaCost(spellID)
	if issecretvalue(spellID) then return false, "spellID SECRET" end
	local costs = C_Spell.GetSpellPowerCost(spellID)
	if costs == nil then return false, "no cost table" end
	if issecrettable and issecrettable(costs) then return false, "cost table SECRET" end
	local mana, out = false, {}
	for _, c in ipairs(costs) do
		out[#out + 1] = "type " .. show(c.type) .. " cost " .. show(c.cost)
		-- A secret cost on a mana entry still means mana was spent.
		if not issecretvalue(c.type) and c.type == MANA and (issecretvalue(c.cost) or c.cost > 0) then mana = true end
	end
	return mana, #out > 0 and table.concat(out, ", ") or "free"
end

if lib then
	local function on(event, handler)
		lib.RegisterCallback(ns, event, function(e, unit, ...)
			if ns.debug then ns.Print(e, unit, ...) end
			if unit == "player" then handler(...) end
		end)
	end
	on("UNIT_SWING_TIMER_START", function(speed, expiration, hand, reason)
		if hand == "mainhand" then SwingStart(speed, expiration, reason) end
	end)
	on("UNIT_SWING_TIMER_UPDATE", function(speed, expiration, hand)
		if hand == "mainhand" then SwingUpdate(speed, expiration) end
	end)
	on("UNIT_SWING_TIMER_PAUSED", function(hand)
		if hand == "mainhand" then ns.Animate(ns.swing) end
	end)
	on("UNIT_SWING_TIMER_STOP", function(hand)
		if hand == "mainhand" then SwingStop() end
	end)
end

function ns.Test()
	local speed = 2.4
	ns.Print("test: two fake swings of " .. speed .. " s, plus the 5 s mana timer")
	ManaStart()
	SwingStart(speed, GetTime() + speed, "swing")
	C_Timer.After(speed, function() SwingStart(speed, GetTime() + speed, "swing") end)
	C_Timer.After(speed * 2, SwingStop)
end

-- Prints which APIs exist on this client and whether their values are readable right now.
function ns.Probe()
	local P = ns.Print
	P("--- probe, " .. (InCombatLockdown() and "IN combat" or "out of combat") .. ", interface " .. select(4, GetBuildInfo()))
	P("UnitHealth", show(UnitHealth("player")), "UnitHealthMax", show(UnitHealthMax("player")))
	P("UnitPower mana", show(UnitPower("player", 0)), "UnitPowerMax mana", show(UnitPowerMax("player", 0)))
	P("UnitPowerType", show(UnitPowerType("player")), "GetShapeshiftFormID", GetShapeshiftFormID and show(GetShapeshiftFormID()) or "missing")
	P("swing speed (library)", lib and show(lib:UnitSwingTimerInfo("player", "mainhand")) or "LIBRARY NOT LOADED")
	P("UnitAttackSpeed", show(UnitAttackSpeed("player")))
	P("C_Spell.GetSpellPowerCost", C_Spell and C_Spell.GetSpellPowerCost and "exists" or "missing")
	P("PixelUtil", PixelUtil and "exists" or "MISSING (bars may blur)")
	P("native timer CVar showSwingTimer", show(C_CVar.GetCVar("showSwingTimer")))
	if C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange then
		C_SwingTimer.EnableRangeCheck(0, true)
		P("C_SwingTimer in range (target)", show(C_SwingTimer.IsTargetWithinSwingRange(0)))
	else
		P("C_SwingTimer range API missing")
	end
	if C_Spell and C_Spell.IsSpellInRange then
		P("C_Spell.IsSpellInRange(Attack, target)", show(C_Spell.IsSpellInRange(6603, "target")))
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ENTER_COMBAT")
f:RegisterEvent("PLAYER_LEAVE_COMBAT")
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

f:SetScript("OnEvent", function(_, event, arg1, _, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		ns.InitDB()
		ns.InitOptions()
		ns.Layout()
		ns.SetLocked(true)
		if not lib then ns.Print("LibClassicSwingTimerAPI did not load; swing lane disabled") end
		return
	end
	if ns.debug and event ~= "UNIT_SPELLCAST_SUCCEEDED" then ns.Print(event) end
	if event == "PLAYER_LOGIN" then
		if ns.db.hideNative then ns.ApplyNative() end
	elseif event == "PLAYER_LOGOUT" then
		ns.RestoreNative()
	elseif event == "PLAYER_ENTERING_WORLD" then
		inCombat = InCombatLockdown()
		ns.Layout()
		RefreshSwing()
		RefreshMana()
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		inCombat = event == "PLAYER_REGEN_DISABLED"
		swungInCombat = inCombat and inFlight
		RefreshSwing()
		RefreshMana()
		-- Secrets can switch on a moment after combat starts, so probe a little later.
		if ns.debug then C_Timer.After(inCombat and 1 or 0, ns.Probe) end
	elseif event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
		attacking = event == "PLAYER_ENTER_COMBAT"
		-- Turning auto-attack on with no swing running starts dimmed (no light-then-dim flash); a swing
		-- that lands right away restores the normal color.
		if attacking and not inFlight then readyAt = GetTime() - DIM_GRACE end
		RefreshSwing()
	elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		ns.Layout()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local costsMana, desc = ManaCost(arg3)
		if ns.debug then ns.Print("cast", show(arg3), desc, costsMana and "-> 5SR" or "") end
		if costsMana then ManaStart() end
	elseif event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
		RefreshMana()
	end
end)
