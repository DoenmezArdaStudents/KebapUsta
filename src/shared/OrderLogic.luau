-- Pure, deterministic order logic shared by server (authoritative) and client (display only).
-- Orders are generated from structured data, and prepared meals are evaluated against them.

local IngredientData = require(script.Parent.IngredientData)
local MenuData = require(script.Parent.MenuData)
local Config = require(script.Parent.Config)

local OrderLogic = {}

export type OrderItem = {
	menu: string,
	bread: string,
	heat: boolean,
	meat: string, -- chicken | veal | mixed | none
	meatPortions: number,
	veg: { [string]: boolean },
	sauces: { [string]: any },
	cheese: boolean,
	takeaway: boolean,
	mods: { string },
	price: number,
	baseVeg: { string }?, -- the dish's standard vegetables as offered by this shop
}

export type Meal = {
	bread: string?,
	heat: number, -- 0 = cold, 1 = warmed/toasted, 2 = burnt
	meat: { [string]: number },
	meatQuality: { number },
	veg: { [string]: number },
	sauces: { [string]: number },
	cheese: number,
	closed: boolean,
	pack: string?, -- "takeaway" | "plate"
	steps: { string },
	fresh: number?, -- lowest freshness (0..1) of the vegetables in it
}

local function weightedPick(rng: Random, weights: { [string]: number }, allowed: { string }): string
	local total = 0
	for _, k in ipairs(allowed) do
		total += weights[k] or 1
	end
	local roll = rng:NextNumber() * total
	for _, k in ipairs(allowed) do
		roll -= weights[k] or 1
		if roll <= 0 then
			return k
		end
	end
	return allowed[#allowed]
end

local MEAT_WEIGHTS = { chicken = 36, veal = 36, mixed = 28, none = 1 }

function OrderLogic.ItemPrice(item: OrderItem): number
	local def = MenuData.Items[item.menu]
	local price = def.price
	if def.meatPortions > 0 and item.meatPortions > def.meatPortions then
		price += Config.Economy.ExtraMeatPrice * (item.meatPortions - def.meatPortions)
	end
	if item.cheese and not def.forceCheese then
		price += Config.Economy.CheesePrice
	end
	for _, n in pairs(item.sauces) do
		if n > 1 then
			price += Config.Economy.ExtraSaucePrice
		end
	end
	return math.floor(price * 100 + 0.5) / 100
end

-- opts: { available = Progression.Available(...)?, picky = number 0..1, simple = bool (tutorial),
--         forceMenu = string?, forceMeat = string? }
-- With `available`, items only ever use dishes, meats, vegetables, sauces and extras the shop has
-- unlocked (and stocked at least once).
function OrderLogic.GenerateItem(rng: Random, opts): OrderItem
	opts = opts or {}
	local av = opts.available
	local function okVeg(v)
		return not av or av.veg[v] == true
	end
	local function okSauce(s)
		return not av or av.sauces[s] == true
	end
	local allowedMenus = {}
	for _, id in ipairs(MenuData.ItemOrder) do
		if (not opts.unlocked or opts.unlocked[id]) and (not av or av.menus[id]) then
			table.insert(allowedMenus, id)
		end
	end
	if #allowedMenus == 0 then
		allowedMenus = { "kebap" }
	end
	local menuId = opts.forceMenu or weightedPick(rng, MenuData.Weights, allowedMenus)
	local def = MenuData.Items[menuId]
	local picky = opts.picky or 0.3
	local mods = {}

	local meats = {}
	for _, m in ipairs(def.allowMeat) do
		if m == "none" or not av or av.meats[m] then
			table.insert(meats, m)
		end
	end
	if #meats == 0 then
		meats = { "chicken" }
	end
	local meat = opts.forceMeat or weightedPick(rng, MEAT_WEIGHTS, meats)

	local item: OrderItem = {
		menu = menuId,
		bread = def.bread,
		heat = def.needsHeat,
		meat = meat,
		meatPortions = def.meatPortions,
		veg = {},
		sauces = {},
		cheese = def.forceCheese == true,
		takeaway = opts.takeaway ~= false,
		mods = mods,
		price = 0,
	}
	-- the dish's standard vegetables / sauces, limited to what the shop has
	local baseVeg = {}
	for _, v in ipairs(def.defaultVeg) do
		if okVeg(v) then
			item.veg[v] = true
			table.insert(baseVeg, v)
		end
	end
	item.baseVeg = baseVeg
	local availSauces = {}
	for _, s in ipairs(IngredientData.SauceOrder) do
		if okSauce(s) then
			table.insert(availSauces, s)
		end
	end
	for _, s in ipairs(def.defaultSauces) do
		if okSauce(s) then
			item.sauces[s] = 1
		end
	end
	if next(item.sauces) == nil and #availSauces > 0 then
		item.sauces[availSauces[1]] = 1
	end

	if opts.simple then
		table.insert(mods, "everything")
		item.price = OrderLogic.ItemPrice(item)
		return item
	end

	local everything = rng:NextNumber() < (0.16 - picky * 0.1)
	if everything then
		table.insert(mods, "everything")
	else
		-- remove some default vegetables
		local removals = 0
		if rng:NextNumber() < 0.6 + picky * 0.3 then
			removals = 1
			if rng:NextNumber() < 0.3 + picky * 0.5 then
				removals = 2
			end
		end
		local vegList = table.clone(baseVeg)
		for _ = 1, removals do
			if #vegList <= 1 then
				break
			end
			local idx = rng:NextInteger(1, #vegList)
			local v = table.remove(vegList, idx)
			item.veg[v] = nil
			table.insert(mods, "no_" .. v)
		end
		-- add optional vegetables
		for _, v in ipairs(def.optionalVeg) do
			if okVeg(v) and rng:NextNumber() < 0.4 then
				item.veg[v] = true
				table.insert(mods, "add_" .. v)
			end
		end
		-- sauce choice
		local r = rng:NextNumber()
		if r < 0.55 and #availSauces > 0 then
			-- swap to one specific sauce
			item.sauces = {}
			local s = availSauces[rng:NextInteger(1, #availSauces)]
			item.sauces[s] = 1
			table.insert(mods, "sauce_only_" .. s)
		elseif r < 0.75 and item.sauces.spicy then
			item.sauces.spicy = nil
			table.insert(mods, "not_spicy")
		end
		if okSauce("spicy") and rng:NextNumber() < 0.16 then
			item.sauces.spicy = 2
			table.insert(mods, "extra_spicy")
		elseif rng:NextNumber() < 0.15 and not string.find(table.concat(mods, ","), "sauce_only_", 1, true) then
			local keys = {}
			for k in pairs(item.sauces) do
				table.insert(keys, k)
			end
			table.sort(keys)
			if #keys > 0 then
				local k = keys[rng:NextInteger(1, #keys)]
				item.sauces[k] = 2
				table.insert(mods, "extra_sauce_" .. k)
			end
		end
		if def.meatPortions > 0 and rng:NextNumber() < 0.22 then
			item.meatPortions = def.meatPortions + 1
			table.insert(mods, "extra_meat")
		end
		if not def.forceCheese and (not av or av.cheese) and rng:NextNumber() < 0.22 then
			item.cheese = true
			table.insert(mods, "cheese")
		end
		if def.toastOption and (not av or av.grill) and rng:NextNumber() < 0.35 then
			item.heat = true
			table.insert(mods, "toasted")
		end
	end
	item.price = OrderLogic.ItemPrice(item)
	return item
end

-- compact text key of an order, used to avoid serving the exact same order back-to-back
function OrderLogic.Signature(order): string
	local parts = {}
	for _, it in ipairs(order.items) do
		local veg, sauces = {}, {}
		for v in pairs(it.veg) do
			table.insert(veg, v)
		end
		for s, n in pairs(it.sauces) do
			table.insert(sauces, s .. n)
		end
		table.sort(veg)
		table.sort(sauces)
		table.insert(parts, table.concat({ it.menu, it.meat, it.meatPortions, tostring(it.heat), tostring(it.cheese), table.concat(veg, "+"), table.concat(sauces, "+") }, "/"))
	end
	return table.concat(parts, "|")
end

function OrderLogic.GenerateOrder(rng: Random, opts)
	opts = opts or {}
	local count = opts.count or 1
	local order = { items = {}, drinks = {}, total = 0 }
	for i = 1, count do
		local itemOpts = table.clone(opts)
		if i > 1 then
			itemOpts.forceMenu = nil
			itemOpts.forceMeat = nil
		end
		table.insert(order.items, OrderLogic.GenerateItem(rng, itemOpts))
	end
	local drinkChance = (opts.simple or (opts.available and not opts.available.drinks)) and 0 or (0.45 + (count - 1) * 0.2)
	for _ = 1, count do
		if rng:NextNumber() < drinkChance then
			local d = IngredientData.DrinkOrder[rng:NextInteger(1, #IngredientData.DrinkOrder)]
			table.insert(order.drinks, d)
		end
	end
	OrderLogic.RecalcTotal(order)
	return order
end

function OrderLogic.RecalcTotal(order)
	local total = 0
	for _, it in ipairs(order.items) do
		total += it.price
	end
	for _, d in ipairs(order.drinks) do
		total += IngredientData.Drinks[d].price
	end
	order.total = math.floor(total * 100 + 0.5) / 100
	return order.total
end

function OrderLogic.NewMeal(bread: string): Meal
	return {
		bread = bread,
		heat = 0,
		meat = {},
		meatQuality = {},
		veg = {},
		sauces = {},
		cheese = 0,
		closed = false,
		pack = nil,
		steps = { "bread:" .. bread },
	}
end

function OrderLogic.MeatTotal(meal: Meal): number
	local n = 0
	for _, v in pairs(meal.meat) do
		n += v
	end
	return n
end

-- Produces a checklist for UI and evaluation.
-- Each entry: { key = string, label = {cat,id,...}, state = "ok"|"missing"|"wrong"|"extra"|"partial", weight = number }
function OrderLogic.Checklist(item: OrderItem, meal: Meal?)
	local list = {}
	local function add(key, state, weight, data)
		table.insert(list, { key = key, state = state, weight = weight, data = data })
	end
	local m: Meal = meal or OrderLogic.NewMeal("")
	if not meal then
		m.steps = {}
		m.bread = nil
	end
	local def = MenuData.Items[item.menu]

	-- bread / container
	if m.bread == nil then
		add("bread", "missing", 3, { id = item.bread })
	elseif m.bread == item.bread then
		add("bread", "ok", 3, { id = item.bread })
	else
		add("bread", "wrong", 3, { id = item.bread, got = m.bread })
	end

	-- heat
	if item.heat then
		if m.heat == 1 then
			add("heat", "ok", 1, {})
		elseif m.heat == 2 then
			add("heat", "partial", 1, { burnt = true })
		else
			add("heat", "missing", 1, {})
		end
	elseif m.heat == 2 then
		add("heat", "partial", 1, { burnt = true })
	end

	-- meat type and amount
	local chicken = m.meat.chicken or 0
	local veal = m.meat.veal or 0
	local total = chicken + veal
	if item.meat == "none" then
		if total > 0 then
			add("meat", "wrong", 2, { id = "none", got = total })
		end
	else
		local typeOk
		if item.meat == "mixed" then
			typeOk = chicken > 0 and veal > 0
		elseif item.meat == "chicken" then
			typeOk = chicken > 0 and veal == 0
		else
			typeOk = veal > 0 and chicken == 0
		end
		local state
		if total == 0 then
			state = "missing"
		elseif not typeOk then
			state = "wrong"
		elseif total < item.meatPortions then
			state = "partial"
		elseif total > item.meatPortions then
			state = "extra"
		else
			state = "ok"
		end
		add("meat", state, 3, { id = item.meat, have = total, need = item.meatPortions, chicken = chicken, veal = veal })
	end

	-- vegetables (both required and forbidden ones count)
	for _, v in ipairs(IngredientData.VegOrder) do
		local need = item.veg[v] == true
		local have = (m.veg[v] or 0) > 0
		if need and have then
			add("veg:" .. v, "ok", 1, { id = v })
		elseif need then
			add("veg:" .. v, "missing", 1, { id = v })
		elseif have then
			add("veg:" .. v, "wrong", 1, { id = v, forbidden = true })
		end
	end

	-- sauces
	for _, s in ipairs(IngredientData.SauceOrder) do
		local need = item.sauces[s] or 0
		local have = m.sauces[s] or 0
		if need > 0 then
			if have == 0 then
				add("sauce:" .. s, "missing", 1, { id = s, need = need, have = have })
			elseif have < need then
				add("sauce:" .. s, "partial", 1, { id = s, need = need, have = have })
			elseif have > need + 1 then
				add("sauce:" .. s, "extra", 1, { id = s, need = need, have = have })
			else
				add("sauce:" .. s, "ok", 1, { id = s, need = need, have = have })
			end
		elseif have > 0 then
			add("sauce:" .. s, "wrong", 1, { id = s, need = 0, have = have, forbidden = true })
		end
	end

	-- cheese
	if item.cheese then
		add("cheese", m.cheese > 0 and "ok" or "missing", 1, {})
	elseif m.cheese > 0 then
		add("cheese", "wrong", 1, { forbidden = true })
	end

	-- closing & packing
	add("close", m.closed and "ok" or "missing", 1, { verb = def.closeVerb })
	local wantPack = item.takeaway and "takeaway" or "plate"
	if m.pack == nil then
		add("pack", "missing", 0.5, { want = wantPack })
	elseif m.pack == wantPack then
		add("pack", "ok", 0.5, { want = wantPack })
	else
		add("pack", "partial", 0.5, { want = wantPack, got = m.pack })
	end
	return list
end

local STATE_SCORE = { ok = 1, partial = 0.5, extra = 0.6, missing = 0, wrong = 0 }

-- Returns accuracy (0..1), quality (0..1), checklist
function OrderLogic.Evaluate(item: OrderItem, meal: Meal)
	local list = OrderLogic.Checklist(item, meal)
	local score, total = 0, 0
	for _, e in ipairs(list) do
		total += e.weight
		score += e.weight * (STATE_SCORE[e.state] or 0)
	end
	-- wrong bread is a dealbreaker
	if meal.bread ~= item.bread then
		score *= 0.3
	end
	local accuracy = total > 0 and score / total or 0

	local quality = 1
	if #meal.meatQuality > 0 then
		local q = 0
		for _, v in ipairs(meal.meatQuality) do
			q += v
		end
		quality = q / #meal.meatQuality
	end
	if meal.heat == 2 then
		quality *= 0.6
	end
	-- wilted vegetables cost quality
	if meal.fresh then
		quality *= 0.55 + 0.45 * math.clamp(meal.fresh, 0, 1)
	end
	return accuracy, math.clamp(quality, 0, 1), list
end

-- Customer satisfaction 0..1 from accuracy, quality and remaining patience fraction
function OrderLogic.Satisfaction(accuracy: number, quality: number, patienceFrac: number): number
	local s = accuracy * 0.55 + quality * 0.25 + math.clamp(patienceFrac, 0, 1) * 0.2
	return math.clamp(s, 0, 1)
end

function OrderLogic.Stars(satisfaction: number): number
	if satisfaction >= 0.92 then
		return 5
	elseif satisfaction >= 0.78 then
		return 4
	elseif satisfaction >= 0.6 then
		return 3
	elseif satisfaction >= 0.4 then
		return 2
	end
	return 1
end

-- Assign prepared meals to order items maximising total accuracy (greedy, orders are small).
-- meals: array of Meal; items: array of OrderItem with `delivered` flags. Returns list of {itemIndex, mealIndex, accuracy, quality}
function OrderLogic.MatchMeals(items, meals)
	local pairsList = {}
	for ii, it in ipairs(items) do
		if not it.delivered then
			for mi, meal in ipairs(meals) do
				local acc, q = OrderLogic.Evaluate(it, meal)
				table.insert(pairsList, { ii = ii, mi = mi, acc = acc, q = q })
			end
		end
	end
	table.sort(pairsList, function(a, b)
		if a.acc == b.acc then
			return a.q > b.q
		end
		return a.acc > b.acc
	end)
	local usedI, usedM, result = {}, {}, {}
	for _, p in ipairs(pairsList) do
		if not usedI[p.ii] and not usedM[p.mi] then
			usedI[p.ii] = true
			usedM[p.mi] = true
			table.insert(result, { itemIndex = p.ii, mealIndex = p.mi, accuracy = p.acc, quality = p.q })
		end
	end
	return result
end

return OrderLogic
