-- Persistent player data with safe defaults, versioning, retries and graceful degradation.
-- If DataStores are unavailable the game keeps running on session data and never overwrites saves.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local Progression = require(Shared.Progression)

local DataService = {}

type Profile = {
	data: { [string]: any },
	loaded: boolean, -- true = data came from (or is allowed to be written to) the DataStore
	dirty: boolean,
	lastSave: number,
}

local profiles: { [Player]: Profile } = {}
local loadedSignal = Instance.new("BindableEvent")
DataService.ProfileLoaded = loadedSignal.Event

local store: DataStore? = nil
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function defaults()
	-- a new shop only has the basics in stock; everything else arrives after it is unlocked
	local stock, stocked = {}, {}
	for id, def in pairs(IngredientData.Stock) do
		local base = Progression.StockUnlocked(nil, id)
		stock[id] = base and def.start or 0
		stocked[id] = base or nil
	end
	return {
		version = Config.DataVersion,
		cash = Config.StartingCash,
		xp = 0,
		level = 1,
		upgrades = {},
		unlocks = {}, -- id -> "delivered" | "owned" (Shared/Progression)
		stocked = stocked, -- stock ids that have been delivered at least once
		reputation = Config.Economy.ReputationStart,
		stock = stock,
		day = 1,
		stats = { served = 0, perfect = 0, earned = 0, days = 0, walkouts = 0, tips = 0 },
		achievements = {},
		settings = { lang = "de", ambience = 0.5, sfx = 0.7, hints = true },
		tutorialDone = false,
	}
end
DataService.Defaults = defaults

-- fill in missing keys without touching existing ones
local function reconcile(target, template)
	for k, v in pairs(template) do
		if target[k] == nil then
			target[k] = type(v) == "table" and table.clone(v) or v
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil then
			-- only recurse into dictionaries with fixed keys (not upgrades/achievements which start empty)
			reconcile(target[k], v)
		end
	end
	return target
end

local function migrate(data)
	data.version = data.version or 0
	if data.version < 2 then
		-- v2: progression catalog. Existing shops keep every unlock their level would allow and
		-- all stock they already had.
		data.unlocks = data.unlocks or {}
		for _, u in ipairs(Progression.Unlocks) do
			if not u.base and (data.level or 1) >= u.level then
				data.unlocks[u.id] = "owned"
			end
		end
		data.stocked = data.stocked or {}
		for id, n in pairs(data.stock or {}) do
			if type(n) == "number" and n > 0 then
				data.stocked[id] = true
			end
		end
	end
	data.version = Config.DataVersion
	return data
end

-- validate types so corrupted values can never break the economy
local function sanitize(data)
	local function num(v, default, lo, hi)
		if type(v) ~= "number" or v ~= v then
			return default
		end
		return math.clamp(v, lo, hi)
	end
	data.cash = num(data.cash, Config.StartingCash, -1e6, 1e9)
	data.xp = num(data.xp, 0, 0, 1e9)
	data.level = math.floor(num(data.level, 1, 1, 999))
	data.reputation = num(data.reputation, Config.Economy.ReputationStart, 1, 5)
	data.day = math.floor(num(data.day, 1, 1, 1e6))
	for id, tier in pairs(data.upgrades) do
		local def = Config.Upgrades[id]
		if not def or type(tier) ~= "number" then
			data.upgrades[id] = nil
		else
			data.upgrades[id] = math.clamp(math.floor(tier), 0, #def.prices)
		end
	end
	for id, st in pairs(data.unlocks) do
		local u = Progression.ById[id]
		if not u or u.base or (st ~= "owned" and st ~= "delivered") then
			data.unlocks[id] = nil
		end
	end
	for id, v in pairs(data.stocked) do
		if not IngredientData.Stock[id] or v ~= true then
			data.stocked[id] = nil
		end
	end
	for id, amount in pairs(data.stock) do
		if not IngredientData.Stock[id] or type(amount) ~= "number" then
			data.stock[id] = nil
		else
			data.stock[id] = math.max(0, math.floor(amount))
		end
	end
	if data.settings.lang ~= "de" and data.settings.lang ~= "en" then
		data.settings.lang = "de"
	end
	return data
end

local function simulateFailure(): boolean
	return ServerScriptService:GetAttribute("SimulateDataStoreFailure") == true
end

local function key(player: Player)
	return "player_" .. player.UserId
end

local function loadData(player: Player)
	if not store or not storeOk or simulateFailure() then
		return nil, false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			return result, true
		end
		warn(string.format("[DataService] load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
		task.wait(attempt * 1.5)
		if not player.Parent then
			return nil, false
		end
	end
	return nil, false
end

function DataService.Load(player: Player)
	local raw, ok = loadData(player)
	local data
	if ok and type(raw) == "table" then
		data = sanitize(reconcile(migrate(raw), defaults()))
	else
		data = defaults()
	end
	local profile: Profile = { data = data, loaded = ok, dirty = false, lastSave = os.clock() }
	if not player.Parent then
		return nil
	end
	profiles[player] = profile
	player:SetAttribute("SaveOk", ok)
	loadedSignal:Fire(player, profile.data)
	return profile
end

function DataService.Save(player: Player, final: boolean?)
	local profile = profiles[player]
	if not profile then
		return false
	end
	if not profile.loaded or not store or simulateFailure() then
		player:SetAttribute("SaveOk", false)
		return false -- never overwrite real data with defaults after a failed load
	end
	local snapshot = table.clone(profile.data)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function(old)
			-- refuse to downgrade data written by a newer game version
			if type(old) == "table" and type(old.version) == "number" and old.version > Config.DataVersion then
				return nil
			end
			return snapshot
		end)
	end)
	if ok then
		profile.dirty = false
		profile.lastSave = os.clock()
		player:SetAttribute("SaveOk", true)
	else
		warn("[DataService] save failed for", player.Name, err)
		player:SetAttribute("SaveOk", false)
	end
	return ok
end

function DataService.Get(player: Player)
	local p = profiles[player]
	return p and p.data
end

function DataService.MarkDirty(player: Player)
	local p = profiles[player]
	if p then
		p.dirty = true
	end
end

function DataService.IsSaving(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and p.loaded and not simulateFailure()
end

function DataService.Release(player: Player)
	DataService.Save(player, true)
	profiles[player] = nil
end

function DataService.Init()
	Players.PlayerRemoving:Connect(function(player)
		DataService.Release(player)
	end)
	-- autosave
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player, profile in pairs(profiles) do
				if profile.dirty then
					task.spawn(DataService.Save, player)
					task.wait(1) -- spread requests
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 20 do
			task.wait(0.2)
		end
	end)
end

return DataService
