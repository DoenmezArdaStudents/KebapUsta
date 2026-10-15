-- Order tickets, serving validation and payment. Everything that decides money lives here, server-side.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local OrderLogic = require(Shared.OrderLogic)
local DialogueConfig = require(Shared.DialogueConfig)
local Localization = require(Shared.Localization)
local Net = require(script.Parent.Net)
local EconomyService = require(script.Parent.EconomyService)
local RestaurantService = require(script.Parent.RestaurantService)
local FoodPreparationService = require(script.Parent.FoodPreparationService)
local DataService = require(script.Parent.DataService)

local OrderService = {}

local tickets: { [number]: any } = {} -- by customer id
local ticketOrder: { number } = {}
local pushQueued = false

local function serializeTicket(c)
	local t = tickets[c.id]
	return {
		id = c.id,
		name = c.name,
		personality = c.personality,
		emoji = DialogueConfig.Personalities[c.personality].emoji,
		vip = c.vip,
		items = t.order.items,
		drinks = t.order.drinks,
		drinksDelivered = t.drinksDelivered,
		total = t.order.total,
		model = c.model,
		createdAt = t.createdAt,
		takerId = t.taker and t.taker.UserId or nil,
		takerName = t.taker and t.taker.DisplayName or nil,
		takeaway = t.order.items[1] and t.order.items[1].takeaway,
	}
end

function OrderService.PushTickets()
	if pushQueued then
		return
	end
	pushQueued = true
	task.defer(function()
		pushQueued = false
		local list = {}
		for _, id in ipairs(ticketOrder) do
			local t = tickets[id]
			if t then
				table.insert(list, serializeTicket(t.customer))
			end
		end
		Net.FireAll("Tickets", list)
	end)
end

function OrderService.CreateTicket(c, order, taker: Player?)
	tickets[c.id] = {
		customer = c,
		order = order,
		taker = taker,
		createdAt = os.time(),
		drinksDelivered = {},
		results = {}, -- per item: {accuracy, quality}
	}
	table.insert(ticketOrder, c.id)
	local premium = RestaurantService.UpgradeValue("premium")
	RestaurantService.RegisterDisplay(Localization.Money(order.total * premium), c.name)
	OrderService.PushTickets()
end

function OrderService.GetTicket(c)
	return tickets[c.id]
end

function OrderService.RemoveTicket(c)
	if tickets[c.id] then
		tickets[c.id] = nil
		local i = table.find(ticketOrder, c.id)
		if i then
			table.remove(ticketOrder, i)
		end
		OrderService.PushTickets()
	end
end

local function allDelivered(t)
	for _, it in ipairs(t.order.items) do
		if not it.delivered then
			return false
		end
	end
	for i in ipairs(t.order.drinks) do
		if not t.drinksDelivered[i] then
			return false
		end
	end
	return true
end

-- Serve the player's tray to customer c.
-- Returns status: "complete" | "partial" | "refused" | "nothing"
function OrderService.Serve(player: Player, c)
	local t = tickets[c.id]
	if not t then
		return "nothing"
	end
	-- every order belongs to the player who took it: nobody else can serve (or get paid for) it
	if t.taker and t.taker ~= player and t.taker.Parent then
		Net.Notify(player, ("🔒 Das ist die Bestellung von %s"):format(t.taker.DisplayName), nil, "warn")
		return "nothing"
	end
	local tray = FoodPreparationService.Tray(player)
	if #tray == 0 then
		Net.Notify(player, "n_tray_empty", nil, "warn")
		return "nothing"
	end
	local mealIdx, meals = {}, {}
	for i, item in ipairs(tray) do
		if item.kind == "meal" then
			table.insert(meals, item.meal)
			table.insert(mealIdx, i)
		end
	end
	local removeIdx = {}
	local deliveredSomething = false
	local refused = false

	-- meals
	local matches = OrderLogic.MatchMeals(t.order.items, meals)
	for _, mt in ipairs(matches) do
		if mt.accuracy >= Config.Economy.RefuseAccuracy then
			local it = t.order.items[mt.itemIndex]
			it.delivered = true
			t.results[mt.itemIndex] = { accuracy = mt.accuracy, quality = mt.quality }
			table.insert(removeIdx, mealIdx[mt.mealIndex])
			deliveredSomething = true
		else
			refused = true
		end
	end
	-- drinks
	for di, d in ipairs(t.order.drinks) do
		if not t.drinksDelivered[di] then
			for ti, item in ipairs(tray) do
				if item.kind == "drink" and item.id == d and not table.find(removeIdx, ti) then
					t.drinksDelivered[di] = true
					table.insert(removeIdx, ti)
					deliveredSomething = true
					break
				end
			end
		end
	end

	if #removeIdx > 0 then
		FoodPreparationService.RemoveTrayItems(player, removeIdx)
	end
	if not deliveredSomething then
		if refused then
			return "refused"
		end
		Net.Notify(player, "n_nothing_for", nil, "warn")
		return "nothing"
	end
	t.lastServer = player
	OrderService.PushTickets()
	if allDelivered(t) then
		return "complete"
	end
	return "partial"
end

-- Compute and pay out. Returns stars and result table (also sent to the client as feedback).
function OrderService.Complete(player: Player, c)
	local t = tickets[c.id]
	if not t then
		return 3
	end
	local premium = RestaurantService.UpgradeValue("premium")
	local accSum, qSum, n = 0, 0, 0
	local pay = 0
	local allPerfect = true
	for i, it in ipairs(t.order.items) do
		local r = t.results[i] or { accuracy = 0, quality = 0 }
		accSum += r.accuracy
		qSum += r.quality
		n += 1
		local factor = (r.accuracy ^ 1.5) * (0.7 + 0.3 * r.quality)
		pay += it.price * premium * factor
		if r.accuracy < 0.99 or r.quality < 0.9 then
			allPerfect = false
		end
	end
	for _, d in ipairs(t.order.drinks) do
		pay += IngredientData.Drinks[d].price * premium
	end
	local accuracy = n > 0 and accSum / n or 1
	local quality = n > 0 and qSum / n or 1
	local patienceFrac = math.clamp(c.patience / c.maxPatience, 0, 1)
	local satisfaction = OrderLogic.Satisfaction(accuracy, quality, patienceFrac)
	-- business modifiers (cleanliness, price policy, freshness) – Server/BusinessService
	local payMul, tipMul = 1, 1
	if OrderService.ModHook then
		local mood
		mood, payMul, tipMul = OrderService.ModHook(c)
		satisfaction = math.clamp(satisfaction + mood, 0, 1)
	end
	if c.eventTip then
		tipMul *= 1 + c.eventTip -- day event bonus (Shared/Events reward)
	end
	local stars = OrderLogic.Stars(satisfaction)
	local personality = DialogueConfig.Personalities[c.personality]

	local tip = 0
	if satisfaction > 0.7 then
		local rep = RestaurantService.GetReputation()
		tip = t.order.total * (0.05 + (satisfaction - 0.7) * 0.5) * personality.tip * premium * (0.6 + rep / 7.5)
	end
	local vipBonus = 0
	if c.vip and allPerfect then
		vipBonus = pay
	end
	pay = math.floor(pay * 100 + 0.5) / 100
	tip = math.floor(tip * 100 + 0.5) / 100
	pay *= payMul
	tip *= tipMul
	pay = math.floor(pay * 100 + 0.5) / 100
	tip = math.floor(tip * 100 + 0.5) / 100
	vipBonus = math.floor(vipBonus * 100 + 0.5) / 100
	local total = pay + tip + vipBonus

	local xp = Config.Economy.XPBase + stars * Config.Economy.XPPerStar + (n - 1) * 3
	if allPerfect then
		xp += Config.Economy.XPPerfectBonus
	end
	if c.vip then
		xp *= 2
	end

	EconomyService.AddCash(player, total, true)
	EconomyService.AddXP(player, xp)
	EconomyService.AddStat(player, "served", 1)
	EconomyService.AddStat(player, "tips", tip)
	if allPerfect then
		EconomyService.AddStat(player, "perfect", 1)
		RestaurantService.Record("perfect", 1)
	end
	RestaurantService.Record("served", 1)
	RestaurantService.Record("revenue", total)
	RestaurantService.Record("tips", tip)
	local veal = false
	for _, it in ipairs(t.order.items) do
		if it.menu == "duerum" then
			RestaurantService.Record("duerum", 1)
		end
		if it.heat and it.menu ~= "duerum" and it.menu ~= "veggie" then
			RestaurantService.Record("toasted", 1)
		end
		if it.meat == "veal" or it.meat == "mixed" then
			veal = true
		end
	end
	if veal then
		EconomyService.AddStat(player, "veal", 1)
	end
	if stars >= 4 then
		EconomyService.AddStat(player, "satisfied", 1)
	end
	if stars >= 5 then
		RestaurantService.Record("five_star", 1)
	end
	RestaurantService.Record("drinks", #t.order.drinks)
	RestaurantService.Rate(stars, c.vip and 2 or 1)
	RestaurantService.RegisterDisplay("+" .. Localization.Money(total), string.rep("★", stars) .. string.rep("☆", 5 - stars), stars >= 4 and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(255, 200, 80))

	-- tutorial completes on the first successful serve
	local data = DataService.Get(player)
	if data and not data.tutorialDone then
		data.tutorialDone = true
		DataService.MarkDirty(player)
		EconomyService.Push(player)
	end

	local result = {
		customer = c.name,
		stars = stars,
		pay = pay,
		tip = tip,
		vipBonus = vipBonus,
		xp = xp,
		accuracy = accuracy,
		quality = quality,
		patience = patienceFrac,
		perfect = allPerfect,
	}
	Net.Fire("Feedback", player, result)
	Net.Sound(player, stars >= 3 and "success" or "fail")
	Net.Sound(player, "register")
	OrderService.RemoveTicket(c)
	if OrderService.CompletedHook then
		task.spawn(OrderService.CompletedHook, player, c, stars, result, t.order)
	end
	return stars, result
end

OrderService.ModHook = nil :: ((any) -> (number, number, number))?
OrderService.CompletedHook = nil :: ((Player, any, number, any, any) -> ())?

function OrderService.Init()
	-- a player who disconnects keeps their orders for 20 s (rejoin), then they are free for everyone
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		task.delay(20, function()
			for _, t in pairs(tickets) do
				if t.taker == p then
					t.taker = nil
					Net.NotifyAll(("🔓 Die Bestellung von %s ist jetzt frei"):format(t.customer.name), nil, "info")
				end
			end
			OrderService.PushTickets()
		end)
	end)
	Net.OnRequest("GetTickets", function()
		OrderService.PushTickets()
		return { ok = true }
	end)
end

return OrderService
