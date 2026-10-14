-- Server-authoritative money, XP, levels, achievements and the private player-state sync.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)

local EconomyService = {}
EconomyService.LevelHook = nil :: ((Player, number) -> ())?

local providers: { (Player, { [string]: any }) -> () } = {}
local pushQueued: { [Player]: boolean } = {}

-- other services add fields to the private state (meal, tray, role, ...)
function EconomyService.AddStateProvider(fn: (Player, { [string]: any }) -> ())
	table.insert(providers, fn)
end

local function buildState(player: Player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local s = {
		cash = data.cash,
		xp = data.xp,
		level = data.level,
		xpNext = Config.XPForLevel(data.level),
		stats = data.stats,
		achievements = data.achievements,
		settings = data.settings,
		tutorialDone = data.tutorialDone,
		saveOk = DataService.IsSaving(player),
	}
	for _, fn in ipairs(providers) do
		fn(player, s)
	end
	return s
end

-- coalesce many changes in one frame into a single remote
function EconomyService.Push(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		if player.Parent then
			local s = buildState(player)
			if s then
				Net.Fire("PlayerState", player, s)
			end
		end
	end)
end

function EconomyService.GetCash(player: Player): number
	local data = DataService.Get(player)
	return data and data.cash or 0
end

function EconomyService.AddCash(player: Player, amount: number, countAsEarned: boolean?)
	local data = DataService.Get(player)
	if not data or amount ~= amount then
		return
	end
	amount = math.floor(amount * 100 + 0.5) / 100
	data.cash = math.floor((data.cash + amount) * 100 + 0.5) / 100
	if countAsEarned and amount > 0 then
		data.stats.earned = math.floor((data.stats.earned + amount) * 100 + 0.5) / 100
		EconomyService.CheckAchievements(player)
	end
	DataService.MarkDirty(player)
	EconomyService.Push(player)
end

-- co-op: guests share the host's money but big purchases (hiring, expansion, equipment …)
-- need the host. The host can allow it for the session (PartyAllowSpend).
EconomyService.GuestLimit = 150
EconomyService.GuestsMaySpend = false
function EconomyService.Spend(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or amount < 0 or amount ~= amount then
		return false
	end
	if DataService.IsGuest(player) and amount >= EconomyService.GuestLimit and not EconomyService.GuestsMaySpend then
		Net.Notify(player, ("👑 Käufe ab €%d darf nur der Host machen"):format(EconomyService.GuestLimit), nil, "warn")
		return false
	end
	if data.cash + 1e-6 < amount then
		return false
	end
	data.cash = math.floor((data.cash - amount) * 100 + 0.5) / 100
	DataService.MarkDirty(player)
	EconomyService.Push(player)
	return true
end

function EconomyService.AddXP(player: Player, amount: number)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.xp += math.max(0, math.floor(amount))
	local leveled = false
	while data.xp >= Config.XPForLevel(data.level) do
		data.xp -= Config.XPForLevel(data.level)
		data.level += 1
		leveled = true
	end
	if leveled then
		Net.Notify(player, "n_level_up", { level = data.level }, "levelup")
		Net.Sound(player, "levelup")
		if EconomyService.LevelHook then
			task.defer(EconomyService.LevelHook, player, data.level)
		end
	end
	DataService.MarkDirty(player)
	EconomyService.Push(player)
end

function EconomyService.AddStat(player: Player, stat: string, amount: number?)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.stats[stat] = (data.stats[stat] or 0) + (amount or 1)
	DataService.MarkDirty(player)
	EconomyService.CheckAchievements(player)
end

function EconomyService.CheckAchievements(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for _, a in ipairs(Config.Achievements) do
		if not data.achievements[a.id] and (data.stats[a.stat] or 0) >= a.goal then
			data.achievements[a.id] = true
			data.cash += a.reward
			Net.Notify(player, "n_achievement", { name = a.name, reward = Config.CurrencySymbol .. a.reward }, "achievement")
			Net.Sound(player, "levelup")
		end
	end
	EconomyService.Push(player)
end

return EconomyService
