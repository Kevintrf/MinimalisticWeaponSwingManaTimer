local _, ns = ...

-- Non-crisp fallback in case Forever lacks PixelUtil (debug reports which one is active).
local PU = PixelUtil or {
	SetSize = function(r, w, h) r:SetSize(w, h) end,
	SetPoint = function(r, ...) r:SetPoint(...) end,
}

local function hex(s)
	return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end
local COLORS = { track = hex("2C2C2A"), fill = hex("D3D1C7"), dim = hex("5F5E5A"), mana = hex("378ADD") }
local GAP = 2

-- Unnamed so the client's layout cache never saves its position; we keep it in our saved variables.
local bar = CreateFrame("Frame", nil, UIParent)
bar:SetFrameStrata("MEDIUM")
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:RegisterForDrag("LeftButton")
bar:SetHitRectInsets(0, 0, -6, -6) -- the bar is only a few px tall; give the mouse some slack
bar:SetScript("OnDragStart", bar.StartMoving)
bar:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	-- Save as the bar's top edge relative to screen center, the same anchor the x/y commands use.
	local cx, cy = UIParent:GetCenter()
	local db = ns.db
	db.x = math.floor(self:GetCenter() - cx + 0.5)
	db.y = math.floor(self:GetTop() - cy + 0.5)
	ns.Layout()
end)
ns.bar = bar

local unlockBg = bar:CreateTexture(nil, "BACKGROUND")
unlockBg:SetAllPoints()
unlockBg:SetColorTexture(1, 1, 1, 0.2)
unlockBg:Hide()

local swing = CreateFrame("StatusBar", nil, bar)
swing:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
swing:SetMinMaxValues(0, 1)
swing:Hide()
local track = swing:CreateTexture(nil, "BACKGROUND")
track:SetAllPoints()
track:SetColorTexture(unpack(COLORS.track))
ns.swing = swing

local mana = CreateFrame("StatusBar", nil, bar)
mana:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
mana:SetStatusBarColor(unpack(COLORS.mana))
mana:SetMinMaxValues(0, 1)
mana:Hide()
local manaTrack = mana:CreateTexture(nil, "BACKGROUND")
manaTrack:SetAllPoints()
manaTrack:SetColorTexture(unpack(COLORS.track))
ns.mana = mana

function ns.SetSwingColor(kind)
	swing:SetStatusBarColor(unpack(COLORS[kind]))
end

function ns.Layout()
	local db = ns.db
	bar:ClearAllPoints()
	PU.SetPoint(bar, "TOP", UIParent, "CENTER", db.x, db.y)
	PU.SetSize(bar, db.width, db.swingHeight + GAP + db.manaHeight)
	swing:ClearAllPoints()
	PU.SetPoint(swing, "TOPLEFT", bar, "TOPLEFT", 0, 0)
	PU.SetSize(swing, db.width, db.swingHeight)
	mana:ClearAllPoints()
	PU.SetPoint(mana, "TOPLEFT", swing, "BOTTOMLEFT", 0, -GAP)
	PU.SetSize(mana, db.width, db.manaHeight)
end

function ns.SetLocked(locked)
	ns.locked = locked
	bar:EnableMouse(not locked)
	unlockBg:SetShown(not locked)
end

-- Lane visibility: a lane that stops counting hides at once while the other lane still counts;
-- when neither counts, the whole bar fades out and the lanes hide at the end of the fade.
local lanes = { swing, mana }
local fadeOut = bar:CreateAnimationGroup()
local fadeAlpha = fadeOut:CreateAnimation("Alpha")
fadeAlpha:SetFromAlpha(1)
fadeAlpha:SetToAlpha(0)
fadeAlpha:SetDuration(0.5)
fadeOut:SetToFinalAlpha(true)

local function HideUnwanted()
	for _, lane in ipairs(lanes) do
		if not lane.wanted then lane:Hide() end
	end
end
fadeOut:SetScript("OnFinished", function()
	HideUnwanted()
	bar:SetAlpha(1) -- lanes are hidden now; full alpha keeps the unlock background visible
end)

function ns.ShowLane(lane, shown)
	lane.wanted = shown
	if shown then
		fadeOut:Stop()
		bar:SetAlpha(1)
		HideUnwanted() -- a lane kept for a fade that just got cancelled
		lane:Show()
	elseif swing.wanted or mana.wanted then
		lane:Hide()
	elseif lane:IsShown() and not fadeOut:IsPlaying() then
		fadeOut:Play()
	end
end

-- Lane animation: OnUpdate is attached only while at least one lane is moving.
-- A lane's optional onDone runs when it reaches the end (not when frozen).
local animating, done = {}, {}

local function OnUpdate()
	local now = GetTime()
	for lane in pairs(animating) do
		local p = (now - lane.startT) / (lane.endT - lane.startT)
		if p >= 1 then
			p = 1
			animating[lane] = nil
			done[#done + 1] = lane
		end
		lane:SetValue(p)
	end
	if not next(animating) then bar:SetScript("OnUpdate", nil) end
	-- Callbacks after the loop: they may start new animations, which can't be added mid-traversal.
	for i = #done, 1, -1 do
		local lane = table.remove(done, i)
		if lane.onDone then lane.onDone() end
	end
end

-- Animate lane from startT to endT (GetTime() clock); call with no times to freeze it.
function ns.Animate(lane, startT, endT)
	lane.startT, lane.endT = startT, endT
	animating[lane] = startT and endT > startT or nil
	if animating[lane] then
		bar:SetScript("OnUpdate", OnUpdate)
		OnUpdate()
	end
end
