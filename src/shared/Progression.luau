-- Progression catalog: everything the shop can unlock (ingredients, dishes, equipment, knives),
-- the knives' cutting behaviour and pure helpers that turn an unlock table into "what customers may
-- order". Shared by server (authoritative) and client (display).
--
-- Unlock states saved per shop owner: data.unlocks[id] = "delivered" (crate waiting to be unpacked)
-- or "owned" (installed and usable). Items with `base = true` are owned from the start.

local Progression = {}

export type Unlock = {
	id: string,
	cat: string, -- "ingredient" | "menu" | "equipment" | "knife"
	icon: string,
	name: { de: string, en: string },
	desc: { de: string, en: string },
	level: number,
	price: number,
	base: boolean?,
	requires: { string }?,
	install: boolean?, -- needs a delivery crate to be unpacked in the shop
	stock: { string }?, -- stock ids that become orderable
	gives: { [string]: any },
}

local function U(t): Unlock
	return t
end

Progression.Unlocks = {
	-- starting set: one chicken spit, kebap bread, lettuce, garlic & yogurt sauce, an old knife
	U({ id = "base", cat = "menu", base = true, icon = "🥙", level = 1, price = 0, name = { de = "Hühner-Kebap", en = "Chicken kebab" }, desc = { de = "Der Klassiker: Kebap-Brot, Hühnerfleisch, Salat, Knoblauch- & Joghurtsauce.", en = "The classic: kebab bread, chicken, lettuce, garlic & yogurt sauce." }, gives = { menu = "kebap", meat = "chicken", veg = "lettuce", sauces = { "garlic", "yogurt" }, knife = "old" } }),

	U({ id = "knife_standard", cat = "knife", icon = "🔪", level = 1, price = 35, name = { de = "Standard-Kebapmesser", en = "Standard kebab knife" }, desc = { de = "Schärfer und besser ausbalanciert als das alte Küchenmesser.", en = "Sharper and better balanced than the old kitchen knife." }, gives = { knife = "standard" } }),
	U({ id = "veg_tomato", cat = "ingredient", icon = "🍅", level = 2, price = 60, install = true, stock = { "tomato" }, name = { de = "Tomaten", en = "Tomatoes" }, desc = { de = "Neue Kühlwanne für frische Tomaten.", en = "A new cold tray for fresh tomatoes." }, gives = { veg = "tomato" } }),
	U({ id = "veg_onion", cat = "ingredient", icon = "🧅", level = 3, price = 120, install = true, stock = { "onion" }, name = { de = "Zwiebeln", en = "Onions" }, desc = { de = "Fein geschnittene Zwiebeln für den Salat.", en = "Finely cut onions for the salad." }, gives = { veg = "onion" } }),
	U({ id = "grill", cat = "equipment", icon = "🔥", level = 4, price = 200, install = true, name = { de = "Kontaktgrill", en = "Contact grill" }, desc = { de = "Brot toasten – Kunden können „getoastet“ bestellen.", en = "Toast bread – customers can order it toasted." }, gives = { grill = true } }),
	U({ id = "veg_cabbage", cat = "ingredient", icon = "🟣", level = 4, price = 220, install = true, stock = { "cabbage" }, name = { de = "Rotkraut", en = "Red cabbage" }, desc = { de = "Knackiges Rotkraut für mehr Farbe.", en = "Crunchy red cabbage for more colour." }, gives = { veg = "cabbage" } }),
	U({ id = "sauce_spicy", cat = "ingredient", icon = "🌶️", level = 5, price = 320, install = true, stock = { "sauce_spicy" }, name = { de = "Scharfe Sauce", en = "Spicy sauce" }, desc = { de = "Ein dritter Saucenspender – für alle, die es scharf mögen.", en = "A third sauce dispenser – for those who like it hot." }, gives = { sauces = { "spicy" } } }),
	U({ id = "menu_duerum", cat = "menu", icon = "🌯", level = 6, price = 500, install = true, requires = { "grill" }, stock = { "bread_duerum" }, name = { de = "Dürüm", en = "Dürüm" }, desc = { de = "Dürüm-Fladen – am Grill gewärmt und eingerollt.", en = "Dürüm flatbread – warmed on the grill and rolled up." }, gives = { menu = "duerum" } }),
	U({ id = "knife_pro", cat = "knife", icon = "🗡️", level = 7, price = 700, name = { de = "Profi-Langmesser", en = "Professional long knife" }, desc = { de = "Lange Klinge: größere Scheiben, mehr Spielraum im Rhythmus.", en = "Long blade: bigger slices, more room in the rhythm." }, gives = { knife = "pro" } }),
	U({ id = "veg_cucumber", cat = "ingredient", icon = "🥒", level = 7, price = 400, install = true, stock = { "cucumber" }, name = { de = "Gurken", en = "Cucumber" }, desc = { de = "Frische Gurkenscheiben als Extra.", en = "Fresh cucumber slices as an extra." }, gives = { veg = "cucumber" } }),
	U({ id = "cheese", cat = "ingredient", icon = "🧀", level = 8, price = 650, install = true, stock = { "cheese" }, name = { de = "Käse", en = "Cheese" }, desc = { de = "Geriebener Käse – Extra gegen Aufpreis.", en = "Grated cheese – an extra customers pay for." }, gives = { cheese = true } }),
	U({ id = "sauce_cocktail", cat = "ingredient", icon = "🍸", level = 9, price = 600, install = true, stock = { "sauce_cocktail" }, name = { de = "Cocktailsauce", en = "Cocktail sauce" }, desc = { de = "Der vierte Saucenspender.", en = "The fourth sauce dispenser." }, gives = { sauces = { "cocktail" } } }),
	U({ id = "spit_veal", cat = "equipment", icon = "🥩", level = 10, price = 1400, install = true, stock = { "meat_veal" }, name = { de = "Kalbfleisch-Spieß", en = "Veal spit" }, desc = { de = "Ein zweiter Drehspieß – Kalb und „gemischt“ kommen auf die Karte.", en = "A second rotating spit – veal and 'mixed' join the menu." }, gives = { meat = "veal" } }),
	U({ id = "sauce_herb", cat = "ingredient", icon = "🌿", level = 11, price = 900, install = true, stock = { "sauce_herb" }, name = { de = "Kräutersauce", en = "Herb sauce" }, desc = { de = "Hausgemachte Kräutersauce.", en = "Home-made herb sauce." }, gives = { sauces = { "herb" } } }),
	U({ id = "drinks", cat = "equipment", icon = "🥤", level = 12, price = 1900, install = true, stock = { "drink_ayran", "drink_cola", "drink_almdudler" }, name = { de = "Getränke-Kühlschrank", en = "Drinks fridge" }, desc = { de = "Ayran, Cola & Almdudler – Kunden bestellen Getränke dazu.", en = "Ayran, cola & Almdudler – customers add drinks to orders." }, gives = { drinks = true } }),
	U({ id = "menu_box", cat = "menu", icon = "📦", level = 13, price = 1600, install = true, stock = { "box" }, name = { de = "Kebap-Box", en = "Kebab box" }, desc = { de = "Fleisch, Salat & Sauce in der Box – ohne Brot.", en = "Meat, salad & sauce in a box – no bread." }, gives = { menu = "box" } }),
	U({ id = "knife_premium", cat = "knife", icon = "⚔️", level = 14, price = 2800, name = { de = "Premium-Damastmesser", en = "Premium Damascus knife" }, desc = { de = "Rasiermesserscharf: zwei Schnitte pro Portion.", en = "Razor sharp: two cuts per portion." }, gives = { knife = "premium" } }),
	U({ id = "menu_veggie", cat = "menu", icon = "🥗", level = 15, price = 2300, requires = { "cheese", "veg_cucumber", "grill" }, name = { de = "Veggie-Kebap", en = "Veggie kebab" }, desc = { de = "Gemüse, Käse & Kräutersauce, gewärmt – für Vegetarier.", en = "Veg, cheese & herb sauce, warmed – for vegetarians." }, gives = { menu = "veggie" } }),
	U({ id = "knife_electric", cat = "knife", icon = "⚙️", level = 18, price = 6500, name = { de = "Elektrischer Dönerschneider", en = "Electric kebab cutter" }, desc = { de = "Rotierende Klinge – Taste halten und am Spieß führen. Viel schneller.", en = "Rotating blade – hold the key and guide it along the spit. Much faster." }, gives = { knife = "electric" } }),
}

Progression.ById = {} :: { [string]: Unlock }
for _, u in ipairs(Progression.Unlocks) do
	Progression.ById[u.id] = u
end

-- Knives: cutting behaviour (used by the MeatCuttingService and the client animation)
--   interval   ideal time between two strokes (rhythm)
--   window     tolerance around the ideal interval for a "perfect" stroke
--   slices     slices that make one portion
--   auto       electric: strokes repeat automatically while the key is held
Progression.Knives = {
	old = { order = 1, name = { de = "Altes Küchenmesser", en = "Old kitchen knife" }, interval = 0.8, window = 0.14, slices = 4, blade = 0.9, color = Color3.fromRGB(150, 150, 150), handle = Color3.fromRGB(110, 75, 45) },
	standard = { order = 2, name = { de = "Standard-Kebapmesser", en = "Standard kebab knife" }, interval = 0.66, window = 0.17, slices = 3, blade = 1.25, color = Color3.fromRGB(205, 208, 212), handle = Color3.fromRGB(30, 30, 32) },
	pro = { order = 3, name = { de = "Profi-Langmesser", en = "Professional long knife" }, interval = 0.58, window = 0.22, slices = 3, blade = 1.75, color = Color3.fromRGB(225, 228, 232), handle = Color3.fromRGB(25, 25, 28) },
	premium = { order = 4, name = { de = "Premium-Damastmesser", en = "Premium Damascus knife" }, interval = 0.52, window = 0.26, slices = 2, blade = 1.6, color = Color3.fromRGB(120, 125, 135), handle = Color3.fromRGB(90, 40, 30) },
	electric = { order = 5, name = { de = "Elektrischer Dönerschneider", en = "Electric kebab cutter" }, interval = 0.24, window = 1, slices = 3, auto = true, blade = 0.7, color = Color3.fromRGB(210, 212, 216), handle = Color3.fromRGB(200, 40, 30) },
}

function Progression.State(unlocks: { [string]: string }?, id: string): string?
	local u = Progression.ById[id]
	if u and u.base then
		return "owned"
	end
	return unlocks and unlocks[id] or nil
end

function Progression.Owned(unlocks: { [string]: string }?, id: string): boolean
	return Progression.State(unlocks, id) == "owned"
end

-- best owned knife id
function Progression.Knife(unlocks: { [string]: string }?): string
	local best, bestOrder = "old", 1
	for _, u in ipairs(Progression.Unlocks) do
		local k = u.gives.knife
		if k and Progression.Owned(unlocks, u.id) and Progression.Knives[k].order > bestOrder then
			best, bestOrder = k, Progression.Knives[k].order
		end
	end
	return best
end

-- Is a stock item usable at all (its unlock is installed)?
function Progression.StockUnlocked(unlocks: { [string]: string }?, stockId: string): boolean
	for _, u in ipairs(Progression.Unlocks) do
		if u.stock and table.find(u.stock, stockId) then
			return Progression.Owned(unlocks, u.id)
		end
	end
	return true -- base items (bread_classic, meat_chicken, lettuce, garlic, yogurt)
end

export type Available = {
	menus: { [string]: boolean? },
	meats: { [string]: boolean },
	veg: { [string]: boolean },
	sauces: { [string]: boolean },
	cheese: boolean,
	grill: boolean,
	drinks: boolean,
}

-- What customers may order. `stocked` (optional) = stock ids that have been delivered at least once;
-- a freshly installed ingredient only shows up in orders after its first restock.
function Progression.Available(unlocks: { [string]: string }?, stocked: { [string]: boolean }?): Available
	local a: Available = { menus = {}, meats = {}, veg = {}, sauces = {}, cheese = false, grill = false, drinks = false }
	for _, u in ipairs(Progression.Unlocks) do
		if Progression.Owned(unlocks, u.id) then
			local ready = true
			if stocked and u.stock and not u.base then
				ready = false
				for _, s in ipairs(u.stock) do
					if stocked[s] then
						ready = true
					end
				end
			end
			if ready then
				local g = u.gives
				if g.menu then
					a.menus[g.menu] = true
				end
				if g.meat then
					a.meats[g.meat] = true
				end
				if g.veg then
					a.veg[g.veg] = true
				end
				if g.sauces then
					for _, s in ipairs(g.sauces) do
						a.sauces[s] = true
					end
				end
				if g.cheese then
					a.cheese = true
				end
				if g.grill then
					a.grill = true
				end
				if g.drinks then
					a.drinks = true
				end
			end
		end
	end
	if a.meats.chicken and a.meats.veal then
		a.meats.mixed = true
	end
	-- dishes need their equipment
	if a.menus.duerum and not a.grill then
		a.menus.duerum = nil
	end
	if a.menus.veggie and not (a.cheese and a.grill) then
		a.menus.veggie = nil
	end
	return a
end

-- Can `id` be bought now? Returns ok, reason ("owned" | "delivered" | "level" | "requires" | "cash")
function Progression.CanBuy(unlocks: { [string]: string }?, id: string, level: number, cash: number): (boolean, string?)
	local u = Progression.ById[id]
	if not u or u.base then
		return false, "owned"
	end
	local st = Progression.State(unlocks, id)
	if st == "owned" or st == "delivered" then
		return false, st
	end
	if level < u.level then
		return false, "level"
	end
	for _, r in ipairs(u.requires or {}) do
		if not Progression.Owned(unlocks, r) then
			return false, "requires"
		end
	end
	if cash < u.price then
		return false, "cash"
	end
	return true, nil
end

-- the next unlock worth saving for (cheapest not-yet-bought whose requirements are met)
function Progression.NextUnlock(unlocks: { [string]: string }?, level: number): Unlock?
	local best: Unlock? = nil
	for _, u in ipairs(Progression.Unlocks) do
		local st = Progression.State(unlocks, u.id)
		if not u.base and st == nil then
			local reqOk = true
			for _, r in ipairs(u.requires or {}) do
				if not Progression.Owned(unlocks, r) then
					reqOk = false
				end
			end
			if reqOk and u.level <= level + 1 then
				if not best or u.price < best.price then
					best = u
				end
			end
		end
	end
	return best
end

return Progression
