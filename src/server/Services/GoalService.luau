-- "NÄCHSTE ZIELE": always three goals the player can work towards.
--   KURZ   (short)  – a small task for the next minutes (serve 4 orders, 2 perfect orders, earn €40 …),
--                     counted from the moment it appears, rewarded with cash + XP for everyone on shift.
--   MITTEL (medium) – the next concrete step in the progression: unpack a delivered crate, give a newly
--                     installed ingredient its first restock, or save up for the next unlock.
--   LANG   (long)   – the next big milestone: the next major dish/equipment unlock further ahead.
-- Everything is derived from real server state; the client only displays what is sent in ShopState.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local IngredientData = require(Shared.IngredientData)
local Localization = require(Shared.Localization)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RestaurantService = require(script.Parent.RestaurantService)

local GoalService = {}

type Short = { kind: string, target: number, progress: number, cash: number, xp: number }
local short: Short? = nil
local lastKind: string? = nil
local rng = Random.new()

local function ownerData()
	local o = RestaurantService.GetOwner()
	return o and DataService.Get(o)
end

local function level(): number
	local d = ownerData()
	return d and d.level or 1
end

-- short goal templates; `ok` decides whether the shop can actually do it right now
local SHORT = {
	{ kind = "served", icon = "🥙", min = 3, max = 5, per = 0.35 },
	{ kind = "perfect", icon = "💯", min = 2, max = 3, per = 0.15 },
	{ kind = "revenue", icon = "💶", min = 25, max = 45, per = 9, money = true },
	{ kind = "five_star", icon = "⭐", min = 1, max = 2, per = 0.1 },
	{ kind = "portions", icon = "🔪", min = 5, max = 8, per = 0.4 },
	{ kind = "duerum", icon = "🌯", min = 2, max = 3, per = 0.1, ok = function(a)
		return a.menus.duerum
	end },
	{ kind = "toasted", icon = "🔥", min = 2, max = 3, per = 0.1, ok = function(a)
		return a.grill
	end },
	{ kind = "drinks", icon = "🥤", min = 2, max = 4, per = 0.15, ok = function(a)
		return a.drinks
	end },
	{ kind = "restock", icon = "🚚", min = 1, max = 1, per = 0, low = true },
}

local SHORT_TEXT = {
	served = { de = "Bediene %s Kunden", en = "Serve %s customers" },
	perfect = { de = "%s perfekte Bestellungen", en = "%s perfect orders" },
	revenue = { de = "Verdiene %s", en = "Earn %s" },
	five_star = { de = "%s× 5 Sterne bekommen", en = "Get 5 stars %s×" },
	portions = { de = "Schneide %s Portionen Fleisch", en = "Carve %s meat portions" },
	duerum = { de = "Verkaufe %s Dürüm", en = "Sell %s dürüm" },
	toasted = { de = "%s getoastete Bestellungen", en = "%s toasted orders" },
	drinks = { de = "Verkaufe %s Getränke", en = "Sell %s drinks" },
	restock = { de = "Bestelle knappe Ware nach", en = "Restock a low item" },
}

local function lowStock(): boolean
	for id, def in pairs(IngredientData.Stock) do
		local cap = RestaurantService.Capacity(id)
		if Progression.StockUnlocked(RestaurantService.GetUnlocks(), id) and (def.cat ~= "drink" or RestaurantService.Owns("drinks")) then
			if RestaurantService.GetStock(id) < cap * 0.35 then
				return true
			end
		end
	end
	return false
end

local function rollShort()
	local a = RestaurantService.Available()
	local pool = {}
	for _, t in ipairs(SHORT) do
		if t.kind ~= lastKind and (not t.ok or t.ok(a)) and (not t.low or lowStock()) then
			table.insert(pool, t)
		end
	end
	local t = pool[rng:NextInteger(1, #pool)]
	local lv = level()
	local target = rng:NextInteger(t.min, t.max) + math.floor((lv - 1) * t.per)
	if t.money then
		target = math.floor(target / 5) * 5
	end
	short = {
		kind = t.kind,
		target = target,
		progress = 0,
		cash = math.floor(8 + lv * 4 + (t.money and target * 0.15 or 0)),
		xp = 20 + lv * 5,
	}
	lastKind = t.kind
end

local function completeShort()
	local s = short :: Short
	for _, p in ipairs(Players:GetPlayers()) do
		if DataService.Get(p) then
			EconomyService.AddCash(p, s.cash, true)
			EconomyService.AddXP(p, s.xp)
			Net.Notify(p, "n_short_goal_done", { reward = Localization.Money(s.cash), xp = s.xp }, "goal")
			Net.Sound(p, "success")
		end
	end
	short = nil
	task.delay(2.5, function()
		if not short then
			rollShort()
			RestaurantService.PushShop()
		end
	end)
end

local function progress(kind: string, amount: number)
	if short and short.kind == kind then
		short.progress = math.min(short.target, short.progress + amount)
		if short.progress >= short.target then
			completeShort()
		end
	end
end

---------------------------------------------------------------------------
-- medium & long
---------------------------------------------------------------------------
local function unlockGoal(u, d, isLong: boolean)
	local lv, cash = d.level, d.cash
	local needLevel = lv < u.level
	local p
	if needLevel then
		-- long goals: level fills the first half of the bar, money the second
		p = (isLong and 0.5 or 1) * math.clamp((lv + d.xp / math.max(1, Config.XPForLevel(lv))) / u.level, 0, 1)
	else
		p = (isLong and 0.5 or 0) + (isLong and 0.5 or 1) * math.clamp(cash / math.max(u.price, 1), 0, 1)
	end
	return {
		icon = u.icon,
		id = u.id,
		title = needLevel and { de = string.format("Level %d erreichen", u.level), en = string.format("Reach level %d", u.level) } or { de = "Kaufe: " .. u.name.de, en = "Buy: " .. u.name.en },
		sub = needLevel and { de = "Dann für " .. Localization.Money(u.price) .. " freischalten: " .. u.name.de, en = "Then unlock for " .. Localization.Money(u.price) .. ": " .. u.name.en } or u.desc,
		progress = p,
		cur = needLevel and lv or cash,
		max = needLevel and u.level or u.price,
		money = not needLevel,
		need = math.max(0, u.price - cash),
		reward = { de = "Neu: " .. u.name.de, en = "New: " .. u.name.en },
		action = (not needLevel and cash >= u.price) and "buy" or nil,
	}
end

local function mediumGoal(d)
	local unlocks = d.unlocks
	-- 1) a delivered crate waits in the shop
	for _, u in ipairs(Progression.Unlocks) do
		if unlocks[u.id] == "delivered" then
			return {
				icon = "📦",
				id = u.id,
				title = { de = "Lieferung auspacken: " .. u.name.de, en = "Unpack the delivery: " .. u.name.en },
				sub = { de = "Die Kiste steht in der Küche – halte [E] zum Einbauen.", en = "The crate is in the kitchen – hold [E] to install it." },
				progress = 0,
				cur = 0,
				max = 1,
				reward = { de = u.name.de .. " einsatzbereit", en = u.name.en .. " ready to use" },
				action = "crate",
			}
		end
	end
	-- 2) installed but never stocked
	for _, u in ipairs(Progression.Unlocks) do
		if u.stock and unlocks[u.id] == "owned" then
			local any = false
			for _, s in ipairs(u.stock) do
				if d.stocked[s] then
					any = true
				end
			end
			if not any then
				return {
					icon = "🚚",
					id = u.id,
					title = { de = "Erste Lieferung bestellen: " .. u.name.de, en = "Order the first delivery: " .. u.name.en },
					sub = { de = "Laptop → Lieferant. Erst dann bestellen Kunden es.", en = "Laptop → Supplier. Only then customers order it." },
					progress = 0.5,
					cur = 0,
					max = 1,
					reward = { de = "Kunden bestellen " .. u.name.de, en = "Customers order " .. u.name.en },
					action = "supplier",
				}
			end
		end
	end
	-- 3) save up for the next unlock
	local nextU = Progression.NextUnlock(unlocks, d.level)
	if nextU then
		return unlockGoal(nextU, d, false)
	end
	return nil
end

local MAJOR = { menu = true, equipment = true }

local function longGoal(d, medium)
	-- prefer a milestone a few levels ahead; fall back to the nearest one still missing
	local best
	for pass = 1, 2 do
		for _, u in ipairs(Progression.Unlocks) do
			if not u.base and MAJOR[u.cat] and Progression.State(d.unlocks, u.id) == nil and (not medium or medium.id ~= u.id) then
				if (pass == 2 or u.level >= d.level + 3) and (not best or u.level < best.level) then
					best = u
				end
			end
		end
		if best then
			break
		end
	end
	if best then
		return unlockGoal(best, d, true)
	end
	-- everything bought: lifetime milestone
	local served = d.stats.satisfied or 0
	return {
		icon = "🏆",
		title = { de = "1.000 zufriedene Gäste", en = "1,000 happy guests" },
		sub = { de = "Bewertungen mit 4★ oder mehr.", en = "Ratings of 4★ or more." },
		progress = math.clamp(served / 1000, 0, 1),
		cur = served,
		max = 1000,
		reward = { de = "€2.500 Bonus", en = "€2,500 bonus" },
	}
end

function GoalService.Build()
	local d = ownerData()
	if not d then
		return nil
	end
	if not short then
		rollShort()
	end
	local s = short :: Short
	local tpl = SHORT_TEXT[s.kind]
	local isMoney = s.kind == "revenue"
	local n = isMoney and Localization.Money(s.target) or tostring(s.target)
	local icon = "🎯"
	for _, t in ipairs(SHORT) do
		if t.kind == s.kind then
			icon = t.icon
		end
	end
	local medium = mediumGoal(d)
	return {
		short = {
			icon = icon,
			title = { de = string.format(tpl.de, n), en = string.format(tpl.en, n) },
			progress = s.progress / math.max(1, s.target),
			cur = s.progress,
			max = s.target,
			money = isMoney,
			reward = { de = string.format("+%s · +%d XP", Localization.Money(s.cash), s.xp), en = string.format("+%s · +%d XP", Localization.Money(s.cash), s.xp) },
		},
		medium = medium,
		long = longGoal(d, medium),
	}
end

function GoalService.Init()
	RestaurantService.GoalProvider = GoalService.Build
	RestaurantService.RecordHook = function(stat: string, amount: number)
		progress(stat, amount)
	end
	RestaurantService.RestockHook = function(_player: Player, _stockId: string)
		progress("restock", 1)
	end
	RestaurantService.OwnerChanged:Connect(function()
		short = nil
	end)
	-- level-ups announce what just became buyable
	EconomyService.LevelHook = function(player: Player, lv: number)
		if not RestaurantService.IsOwner(player) then
			return
		end
		local d = DataService.Get(player)
		for _, u in ipairs(Progression.Unlocks) do
			if not u.base and u.level == lv and d and Progression.State(d.unlocks, u.id) == nil then
				Net.Notify(player, "n_new_available", { name = u.name, price = Localization.Money(u.price) }, "levelup")
			end
		end
	end
end

return GoalService
