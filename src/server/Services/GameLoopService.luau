-- Day cycle (10:00–22:00), rush periods, customer spawning, events, closing & daily summary,
-- day/night lighting and the first-time tutorial customer. At 22:00 the clock pauses until a
-- player locks the shop; then everyone sleeps and wakes up at 10:00 in front of the shop.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RestaurantService = require(script.Parent.RestaurantService)
local CustomerService = require(script.Parent.CustomerService)

local GameLoopService = {}
GameLoopService.DemandHook = nil :: (() -> number)?
GameLoopService.SpecialSpawnHook = nil :: (() -> any)?
GameLoopService.WageHook = nil :: (() -> number)?

local rng = Random.new()
local nightApplied: boolean? = nil
local closeRequested = false

local function periodFor(hour: number)
	for _, p in ipairs(Config.Periods) do
		if hour >= p.from and hour < p.to then
			return p
		end
	end
	return Config.Periods[#Config.Periods]
end

local function applyLighting(hour: number)
	-- shop hours 10–22 map onto daylight → dusk → night
	Lighting.ClockTime = hour
	local night = hour >= 19.5
	if night == nightApplied then
		return
	end
	nightApplied = night
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return
	end
	for _, p in ipairs(r:GetDescendants()) do
		if p:IsA("SpotLight") and p.Name == "NightLight" then
			p.Brightness = night and 2.5 or 0
		elseif p:IsA("BasePart") and p:GetAttribute("NightWindow") then
			p.Transparency = night and 0.1 or 0.6
		end
	end
	Lighting.OutdoorAmbient = night and Color3.fromRGB(60, 62, 80) or Color3.fromRGB(120, 115, 110)
end

local function ownerTutorialPending(): boolean
	local owner = RestaurantService.GetOwner()
	local data = owner and DataService.Get(owner)
	return data ~= nil and not data.tutorialDone
end

local function spawnInterval(periodMul: number): number
	local rep = RestaurantService.GetReputation()
	local repMul = 1.25 - (rep - 1) * 0.12 -- rep 1 → 1.25, rep 5 → 0.77
	local base = Config.Customers.BaseSpawnInterval * periodMul * repMul / (GameLoopService.DemandHook and GameLoopService.DemandHook() or 1)
	return math.max(Config.Customers.MinSpawnInterval, base * rng:NextNumber(0.75, 1.25))
end

local function spawnRegular(period)
	-- regulars, critics & co. (Server/BusinessService)
	if GameLoopService.SpecialSpawnHook then
		local c = GameLoopService.SpecialSpawnHook()
		if c then
			return c
		end
	end
	local groupChance = period.rush and Config.Customers.GroupChanceRush or Config.Customers.GroupChance
	local opts = {}
	if rng:NextNumber() < Config.Customers.VIPChance and RestaurantService.GetDay() >= 2 then
		opts.vip = true
		opts.personality = "picky"
	elseif rng:NextNumber() < groupChance then
		opts.groupSize = rng:NextNumber() < 0.7 and 2 or 3
	end
	return CustomerService.Spawn(opts)
end

local function summary()
	local s = RestaurantService.DayStats
	RestaurantService.CheckGoals(true)
	local owner = RestaurantService.GetOwner()
	local ownerData = owner and DataService.Get(owner)
	local rent = Config.Economy.BaseRent + Config.Economy.RentPerLevel * (ownerData and ownerData.level or 1)
	if owner then
		EconomyService.AddCash(owner, -rent, false)
	end
	-- staff wages are paid at closing time and show up in the expenses
	if GameLoopService.WageHook then
		s.expenses += GameLoopService.WageHook()
	end
	local report = {
		day = RestaurantService.GetDay(),
		revenue = s.revenue,
		tips = s.tips,
		expenses = s.expenses,
		rent = rent,
		profit = s.revenue - s.expenses - rent,
		served = s.served,
		perfect = s.perfect,
		walkouts = s.walkouts,
		avgRating = s.ratingCount > 0 and s.ratingSum / s.ratingCount or 0,
		reputation = RestaurantService.GetReputation(),
		goals = RestaurantService.Goals,
	}
	Net.FireAll("DaySummary", report)
	for _, p in ipairs(Players:GetPlayers()) do
		EconomyService.AddStat(p, "days", 1)
	end
	if ownerData then
		ownerData.day += 1
		DataService.MarkDirty(owner :: Player)
	end
end

local function runTutorialIfNeeded()
	if not ownerTutorialPending() then
		return
	end
	RestaurantService.TutorialActive = true
	RestaurantService.PushShop()
	local c = CustomerService.Spawn({ tutorial = true, personality = "friendly" })
	-- wait until the tutorial customer is gone or the owner finished/skipped the tutorial
	while c and c.alive and ownerTutorialPending() do
		task.wait(0.5)
	end
	RestaurantService.TutorialActive = false
	RestaurantService.PushShop()
end

local function runDay()
	RestaurantService.ResetDay()
	RestaurantService.Open = true
	RestaurantService.SetOpenSign(true)
	RestaurantService.Clock = Config.Day.StartHour
	Net.NotifyAll("n_day_start", { day = RestaurantService.GetDay() }, "day")
	local hoursPerSecond = (Config.Day.EndHour - Config.Day.StartHour) / Config.Day.LengthSeconds
	local nextSpawn = os.clock() + Config.Customers.FirstSpawnDelay
	local lastPeriodKey = nil
	local lastPush = 0
	while RestaurantService.Clock < Config.Day.EndHour do
		local dt = task.wait(0.5)
		if not RestaurantService.GetOwner() then
			-- nobody to run the shop; idle
			continue
		end
		if RestaurantService.TutorialActive then
			nextSpawn = os.clock() + 4
		else
			if ownerTutorialPending() then
				task.spawn(runTutorialIfNeeded)
				task.wait(0.5)
				continue
			end
			RestaurantService.Clock += dt * hoursPerSecond
		end
		local period = periodFor(RestaurantService.Clock)
		if period.key ~= lastPeriodKey then
			lastPeriodKey = period.key
			RestaurantService.PeriodKey = period.key
			if period.rush then
				Net.NotifyAll("n_rush", { period = { de = "Ansturm!", en = "Rush hour!" } }, "rush")
			end
			RestaurantService.PushShop()
		end
		if not RestaurantService.TutorialActive and os.clock() >= nextSpawn then
			if CustomerService.CanSpawn() then
				spawnRegular(period)
			end
			nextSpawn = os.clock() + spawnInterval(period.spawn)
		end
		applyLighting(RestaurantService.Clock)
		if os.clock() - lastPush > 3 then
			lastPush = os.clock()
			RestaurantService.PushShop()
		end
	end
	-- 22:00 – closing time. The clock pauses; the day only ends once someone locks the shop
	-- (key switch at the door or "Feierabend" on the laptop).
	RestaurantService.Clock = Config.Day.EndHour
	RestaurantService.Open = false
	RestaurantService.Phase = "after_hours"
	RestaurantService.PeriodKey = "period_closed"
	RestaurantService.SetOpenSign(false)
	applyLighting(RestaurantService.Clock)
	RestaurantService.PushShop()
	Net.NotifyAll("n_closing_lock", nil, "day")
	closeRequested = false
	local t0 = os.clock()
	local cleared = false
	local lastReminder = os.clock()
	while not closeRequested do
		task.wait(0.5)
		-- customers still inside get a grace period to collect their food
		if not cleared and (CustomerService.WaitingCount() == 0 or os.clock() - t0 > Config.Day.ClosingGrace) then
			cleared = true
			if CustomerService.WaitingCount() > 0 then
				CustomerService.ForceLeaveAll()
			end
		end
		if os.clock() - lastReminder > 45 then
			lastReminder = os.clock()
			Net.NotifyAll("n_lock_reminder", nil, "day")
		end
	end
	closeRequested = false
	-- lock up → summary → sleep → wake up at 10:00 in front of the shop
	RestaurantService.Phase = "sleeping"
	RestaurantService.PushShop()
	CustomerService.ForceLeaveAll()
	Net.FireAll("DayPhase", "sleep", { day = RestaurantService.GetDay() + 1 })
	task.wait(1.6) -- screen fades to black
	summary()
	task.wait(Config.Day.SummarySeconds)
	RestaurantService.Clock = Config.Day.StartHour
	applyLighting(RestaurantService.Clock)
	-- everyone wakes up on the pavement in front of the shop
	local r = workspace:FindFirstChild("Restaurant")
	local wake = r and r:FindFirstChild("WakePoint", true) :: BasePart?
	local doorIn = r and r:FindFirstChild("DoorIn", true) :: BasePart?
	if wake then
		for i, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if char and char.PrimaryPart then
				local offset = Vector3.new((i - 1) % 4 * 2.5 - 3.75, 0, math.floor((i - 1) / 4) * 2.5)
				local pos = wake.Position + offset
				local look = doorIn and Vector3.new(doorIn.Position.X, pos.Y, doorIn.Position.Z) or (pos - Vector3.new(0, 0, 10))
				char:PivotTo(CFrame.lookAt(pos, look))
			end
		end
	end
	RestaurantService.Phase = "open"
	Net.FireAll("DayPhase", "wake", { day = RestaurantService.GetDay() })
end

-- lock the shop (only after 22:00); returns ok + reason
function GameLoopService.RequestClose(player: Player): (boolean, string?)
	if RestaurantService.Phase == "sleeping" then
		return false, "sleeping"
	end
	if RestaurantService.Phase ~= "after_hours" then
		Net.Notify(player, "n_lock_too_early", nil, "warn")
		return false, "too_early"
	end
	closeRequested = true
	Net.NotifyAll("n_locked", { name = player.DisplayName }, "day")
	Net.Sound(nil, "doorbell")
	return true
end

function GameLoopService.Init()
	applyLighting(Config.Day.StartHour)
	task.spawn(function()
		-- wait for at least one player
		while not RestaurantService.GetOwner() do
			task.wait(0.5)
		end
		task.wait(2)
		while true do
			local ok, err = pcall(runDay)
			if not ok then
				warn("[GameLoop] day loop error:", err)
				task.wait(2)
			end
		end
	end)
	Net.OnRequest("CloseShop", function(player)
		local ok, reason = GameLoopService.RequestClose(player)
		return { ok = ok, reason = reason }
	end)
	-- key switch at the door
	local FoodPreparationService = require(script.Parent.FoodPreparationService)
	FoodPreparationService.ExternalActions.shop_lock = function(player)
		GameLoopService.RequestClose(player)
	end
	Net.OnRequest("SkipTutorial", function(player)
		local data = DataService.Get(player)
		if data then
			data.tutorialDone = true
			DataService.MarkDirty(player)
			EconomyService.Push(player)
		end
		return { ok = true }
	end)
	Net.OnRequest("ReplayTutorial", function(player)
		local data = DataService.Get(player)
		if data and RestaurantService.IsOwner(player) then
			data.tutorialDone = false
			DataService.MarkDirty(player)
			EconomyService.Push(player)
		end
		return { ok = true }
	end)
	local _ = CollectionService
end

return GameLoopService
