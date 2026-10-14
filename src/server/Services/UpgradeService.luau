-- Upgrade purchases (owner only), fully validated on the server.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RestaurantService = require(script.Parent.RestaurantService)

local UpgradeService = {}

function UpgradeService.Buy(player: Player, id: any)
	if type(id) ~= "string" then
		return { ok = false }
	end
	local def = Config.Upgrades[id]
	if not def then
		return { ok = false }
	end
	if not RestaurantService.IsOwner(player) then
		Net.Notify(player, "n_owner_only", nil, "warn")
		return { ok = false, msg = "n_owner_only" }
	end
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	if def.needs and not RestaurantService.Owns(def.needs) then
		Net.Notify(player, "n_upgrade_needs", { name = Progression.ById[def.needs].name }, "warn")
		return { ok = false, msg = "n_upgrade_needs" }
	end
	local tier = data.upgrades[id] or 0
	if tier >= #def.prices then
		return { ok = false }
	end
	local nextTier = tier + 1
	local req = def.req[nextTier] or 1
	if data.level < req then
		Net.Notify(player, "n_level_req", { level = req }, "warn")
		return { ok = false, msg = "n_level_req" }
	end
	local price = def.prices[nextTier]
	if not EconomyService.Spend(player, price) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return { ok = false, msg = "n_not_enough_cash" }
	end
	data.upgrades[id] = nextTier
	DataService.MarkDirty(player)
	Net.Notify(player, "n_upgrade_bought", { name = def.name }, "success")
	Net.Sound(player, "levelup")
	RestaurantService.ApplyWorldUpgrades()
	RestaurantService.PushShop()
	EconomyService.Push(player)
	return { ok = true }
end

function UpgradeService.Init()
	Net.OnRequest("BuyUpgrade", UpgradeService.Buy)
end

return UpgradeService
