-- Persistent player data with safe defaults, versioning, retries and graceful degradation.
-- If DataStores are unavailable the game keeps running on session data and never overwrites saves.
--
-- Save slots: every player has 3 independent restaurants. Slot 1 keeps the original key
-- ("player_<id>") so existing progress becomes slot 1; slots 2/3 use "player_<id>_s<n>".
-- A small meta record ("meta_<id>") holds the slot cards for the lobby (name, cash, level, …).
-- Session lock: a loaded slot carries { job, t } so a second server never overwrites a newer
-- session; a stale lock (crashed server) is taken over after a short wait.
-- Guests in a co-op session never load their own slots: their profile is an alias of the host's,
-- so money, unlocks and progress are shared and saved only to the host's selected slot.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local Progression = require(Shared.Progression)

local DataService = {}
DataService.SLOTS = 3
local LOCK_TTL = Config.AutosaveInterval * 2 + 60

type Profile = {
	data: { [string]: any }?,
	loaded: boolean, -- true = data came from (or is allowed to be written to) the DataStore
	dirty: boolean,
	lastSave: number,
	key: string?,
	slot: number?,
	tick: number?,
	alias: Player?, -- guest: reads/writes go to the host's profile
}

local profiles: { [Player]: Profile } = {}
local metas: { [Player]: any } = {}
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
		name = "",
		playtime = 0,
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

local function slotKey(userId: number, slot: number): string
	return slot == 1 and ("player_" .. userId) or ("player_" .. userId .. "_s" .. slot)
end
local function metaKey(userId: number): string
	return "meta_" .. userId
end
local function canStore(): boolean
	return store ~= nil and storeOk and not simulateFailure()
end

local function summary(data, slot: number)
	return {
		exists = true,
		name = (type(data.name) == "string" and data.name ~= "") and data.name or ("Kebap Haus " .. slot),
		cash = data.cash,
		level = data.level,
		day = data.day,
		stage = type(data.biz) == "table" and data.biz.stage or 1,
		playtime = math.floor(data.playtime or 0),
		last = os.time(),
	}
end

-- load with session lock; returns raw table (or nil for a new slot) and whether the store worked
local function loadData(player: Player, k: string)
	if not canStore() then
		return nil, false
	end
	for attempt = 1, 6 do
		local locked, seen = false, nil
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(k, function(old)
				seen = old
				if type(old) ~= "table" then
					return nil -- brand-new slot: nothing to write yet
				end
				local l = old.lock
				if attempt < 5 and type(l) == "table" and l.job ~= game.JobId and os.time() - (tonumber(l.t) or 0) < LOCK_TTL then
					locked = true
					return nil -- another server still holds it (it saves and releases on leave)
				end
				old.lock = { job = game.JobId, t = os.time() }
				return old
			end)
		end)
		if ok and not locked then
			return seen, true
		end
		if not ok then
			warn(string.format("[DataService] load attempt %d failed for %s: %s", attempt, player.Name, tostring(err)))
		end
		task.wait(locked and 5 or attempt * 1.5)
		if not player.Parent then
			return nil, false
		end
	end
	return nil, false
end

function DataService.Load(player: Player, slot: number?)
	slot = math.clamp(math.floor(tonumber(slot) or 1), 1, DataService.SLOTS)
	local k = slotKey(player.UserId, slot :: number)
	local raw, ok = loadData(player, k)
	local data
	if ok and type(raw) == "table" then
		raw.lock = nil
		data = sanitize(reconcile(migrate(raw), defaults()))
	else
		data = defaults()
	end
	if data.name == "" then
		data.name = player.DisplayName .. "s Kebap Haus" .. ((slot :: number) > 1 and (" " .. slot) or "")
	end
	local profile: Profile = { data = data, loaded = ok, dirty = false, lastSave = os.clock(), key = k, slot = slot, tick = os.clock() }
	if not player.Parent then
		return nil
	end
	profiles[player] = profile
	player:SetAttribute("SaveOk", ok)
	player:SetAttribute("Slot", slot)
	loadedSignal:Fire(player, profile.data)
	return profile
end

-- co-op guest: plays on the host's restaurant, never touches their own slots
function DataService.LoadGuest(player: Player, host: Player)
	profiles[player] = { alias = host, loaded = false, dirty = false, lastSave = os.clock() }
	player:SetAttribute("Guest", true)
	player:SetAttribute("SaveOk", true)
	if profiles[host] and profiles[host].data then
		loadedSignal:Fire(player, profiles[host].data)
	end
end

function DataService.IsGuest(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and p.alias ~= nil
end

local function writeMeta(userId: number, fn: (any) -> ())
	if not canStore() then
		return
	end
	pcall(function()
		(store :: DataStore):UpdateAsync(metaKey(userId), function(m)
			m = type(m) == "table" and m or { slots = {} }
			m.slots = type(m.slots) == "table" and m.slots or {}
			fn(m)
			return m
		end)
	end)
end

function DataService.Save(player: Player, final: boolean?)
	local profile = profiles[player]
	if not profile or profile.alias or not profile.data then
		return false
	end
	if not profile.loaded or not canStore() then
		player:SetAttribute("SaveOk", false)
		return false -- never overwrite real data with defaults after a failed load
	end
	local data = profile.data :: any
	data.playtime = (data.playtime or 0) + (os.clock() - (profile.tick or os.clock()))
	profile.tick = os.clock()
	local snapshot = table.clone(data)
	snapshot.lock = (not final) and { job = game.JobId, t = os.time() } or nil
	local stolen = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(profile.key :: string, function(old)
			-- refuse to downgrade data written by a newer game version
			if type(old) == "table" and type(old.version) == "number" and old.version > Config.DataVersion then
				return nil
			end
			-- another server took this slot over: never overwrite its newer session
			if type(old) == "table" and type(old.lock) == "table" and old.lock.job ~= game.JobId then
				stolen = true
				return nil
			end
			return snapshot
		end)
	end)
	if ok and stolen then
		warn("[DataService] slot is used by another server, stop saving", player.Name)
		profile.loaded = false
		player:SetAttribute("SaveOk", false)
		return false
	end
	if ok then
		profile.dirty = false
		profile.lastSave = os.clock()
		player:SetAttribute("SaveOk", true)
		local sum = summary(data, profile.slot :: number)
		writeMeta(player.UserId, function(m)
			m.slots[profile.slot :: number] = sum
			m.lastSlot = profile.slot
		end)
	else
		warn("[DataService] save failed for", player.Name, err)
		player:SetAttribute("SaveOk", false)
	end
	return ok
end

function DataService.Get(player: Player)
	local p = profiles[player]
	if p and p.alias then
		local hp = profiles[p.alias]
		return hp and hp.data
	end
	return p and p.data
end

function DataService.MarkDirty(player: Player)
	local p = profiles[player]
	if p and p.alias then
		p = profiles[p.alias]
	end
	if p then
		p.dirty = true
	end
end

function DataService.IsSaving(player: Player): boolean
	local p = profiles[player]
	if p and p.alias then
		p = profiles[p.alias]
	end
	return p ~= nil and p.loaded and canStore()
end

function DataService.Release(player: Player)
	DataService.Save(player, true)
	profiles[player] = nil
	metas[player] = nil
end

---------------------------------------------------------------------------
-- lobby: slot cards
---------------------------------------------------------------------------
function DataService.LoadMeta(player: Player)
	local meta = { slots = {} }
	if canStore() then
		local ok, m = pcall(function()
			return (store :: DataStore):GetAsync(metaKey(player.UserId))
		end)
		if ok and type(m) == "table" and type(m.slots) == "table" then
			meta = m
		elseif ok then
			-- first visit since save slots exist: the old save becomes slot 1
			local ok2, old = pcall(function()
				return (store :: DataStore):GetAsync(slotKey(player.UserId, 1))
			end)
			if ok2 and type(old) == "table" then
				meta.slots[1] = summary(old, 1)
				meta.slots[1].name = player.DisplayName .. "s Kebap Haus"
				writeMeta(player.UserId, function(mm)
					mm.slots[1] = meta.slots[1]
				end)
			end
		end
	end
	metas[player] = meta
	return meta
end

function DataService.GetMeta(player: Player)
	return metas[player]
end

function DataService.CreateSlot(player: Player, slot: number): boolean
	local meta = metas[player]
	if not meta or slot < 1 or slot > DataService.SLOTS or (meta.slots[slot] and meta.slots[slot].exists) then
		return false
	end
	local sum = summary(defaults(), slot)
	sum.name = player.DisplayName .. "s Kebap Haus" .. (slot > 1 and (" " .. slot) or "")
	meta.slots[slot] = sum
	writeMeta(player.UserId, function(m)
		m.slots[slot] = sum
	end)
	return true
end

function DataService.DeleteSlot(player: Player, slot: number): boolean
	local meta = metas[player]
	if not meta or slot < 1 or slot > DataService.SLOTS then
		return false
	end
	if canStore() then
		local ok = pcall(function()
			(store :: DataStore):RemoveAsync(slotKey(player.UserId, slot))
		end)
		if not ok then
			return false
		end
	end
	meta.slots[slot] = nil
	writeMeta(player.UserId, function(m)
		m.slots[slot] = nil
	end)
	return true
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
				if profile.dirty and not profile.alias then
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
		for player, profile in pairs(profiles) do
			if not profile.alias then
				pending += 1
				task.spawn(function()
					DataService.Save(player, true)
					pending -= 1
				end)
			end
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 20 do
			task.wait(0.2)
		end
	end)
end

return DataService
