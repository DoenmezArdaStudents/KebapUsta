-- Every ingredient the shop uses. `stock` = the stock key it consumes, `cost` = purchase price per portion.
-- `color` drives the procedural food visuals.

local IngredientData = {}

IngredientData.Bread = {
	classic = { name = { de = "Kebap-Brot", en = "Kebab bread" }, stock = "bread_classic", color = Color3.fromRGB(222, 184, 120), icon = "🥖" },
	duerum = { name = { de = "Dürüm-Fladen", en = "Dürüm flatbread" }, stock = "bread_duerum", color = Color3.fromRGB(236, 214, 164), icon = "🫓" },
	box = { name = { de = "Kebap-Box", en = "Kebab box" }, stock = "box", color = Color3.fromRGB(245, 245, 240), icon = "📦" },
}

IngredientData.Meat = {
	chicken = { name = { de = "Hühnerfleisch", en = "Chicken" }, stock = "meat_chicken", raw = Color3.fromRGB(236, 196, 160), cooked = Color3.fromRGB(205, 140, 70), icon = "🍗" },
	veal = { name = { de = "Kalbfleisch", en = "Veal" }, stock = "meat_veal", raw = Color3.fromRGB(196, 110, 100), cooked = Color3.fromRGB(130, 72, 40), icon = "🥩" },
}

IngredientData.Veg = {
	lettuce = { name = { de = "Salat", en = "Lettuce" }, stock = "lettuce", color = Color3.fromRGB(120, 190, 70), icon = "🥬" },
	tomato = { name = { de = "Tomaten", en = "Tomatoes" }, stock = "tomato", color = Color3.fromRGB(215, 50, 40), icon = "🍅" },
	onion = { name = { de = "Zwiebeln", en = "Onions" }, stock = "onion", color = Color3.fromRGB(225, 200, 230), icon = "🧅" },
	cabbage = { name = { de = "Rotkraut", en = "Red cabbage" }, stock = "cabbage", color = Color3.fromRGB(130, 40, 110), icon = "🟣" },
	cucumber = { name = { de = "Gurken", en = "Cucumber" }, stock = "cucumber", color = Color3.fromRGB(70, 140, 60), icon = "🥒" },
}
IngredientData.VegOrder = { "lettuce", "tomato", "onion", "cabbage", "cucumber" }

IngredientData.Sauce = {
	garlic = { name = { de = "Knoblauchsauce", en = "Garlic sauce" }, stock = "sauce_garlic", color = Color3.fromRGB(250, 248, 235), icon = "🧄" },
	yogurt = { name = { de = "Joghurtsauce", en = "Yogurt sauce" }, stock = "sauce_yogurt", color = Color3.fromRGB(240, 240, 250), icon = "🥛" },
	cocktail = { name = { de = "Cocktailsauce", en = "Cocktail sauce" }, stock = "sauce_cocktail", color = Color3.fromRGB(240, 150, 120), icon = "🍸" },
	spicy = { name = { de = "Scharfe Sauce", en = "Spicy sauce" }, stock = "sauce_spicy", color = Color3.fromRGB(200, 30, 20), icon = "🌶️" },
	herb = { name = { de = "Kräutersauce", en = "Herb sauce" }, stock = "sauce_herb", color = Color3.fromRGB(190, 220, 160), icon = "🌿" },
}
IngredientData.SauceOrder = { "garlic", "yogurt", "cocktail", "spicy", "herb" }

IngredientData.Extra = {
	cheese = { name = { de = "Käse", en = "Cheese" }, stock = "cheese", color = Color3.fromRGB(250, 250, 245), icon = "🧀" },
}

IngredientData.Drinks = {
	ayran = { name = { de = "Ayran", en = "Ayran" }, stock = "drink_ayran", price = 2.5, color = Color3.fromRGB(245, 245, 245), icon = "🥛" },
	cola = { name = { de = "Cola", en = "Cola" }, stock = "drink_cola", price = 2.8, color = Color3.fromRGB(180, 20, 30), icon = "🥤" },
	almdudler = { name = { de = "Almdudler", en = "Almdudler" }, stock = "drink_almdudler", price = 3.0, color = Color3.fromRGB(240, 200, 60), icon = "🍋" },
}
IngredientData.DrinkOrder = { "ayran", "cola", "almdudler" }

-- Stock items: name, buy price per unit, pack size bought per restock click, start amount, category
IngredientData.Stock = {
	bread_classic = { name = { de = "Kebap-Brot", en = "Kebab bread" }, cost = 0.4, pack = 10, start = 20, cat = "bread" },
	bread_duerum = { name = { de = "Dürüm-Fladen", en = "Dürüm flatbread" }, cost = 0.35, pack = 10, start = 20, cat = "bread" },
	box = { name = { de = "Kebap-Boxen", en = "Kebab boxes" }, cost = 0.2, pack = 10, start = 15, cat = "bread" },
	meat_chicken = { name = { de = "Hühnerfleisch (Portion)", en = "Chicken (portion)" }, cost = 0.7, pack = 20, start = 40, cat = "meat", meat = true },
	meat_veal = { name = { de = "Kalbfleisch (Portion)", en = "Veal (portion)" }, cost = 0.9, pack = 20, start = 40, cat = "meat", meat = true },
	lettuce = { name = { de = "Salat", en = "Lettuce" }, cost = 0.1, pack = 15, start = 30, cat = "veg" },
	tomato = { name = { de = "Tomaten", en = "Tomatoes" }, cost = 0.12, pack = 15, start = 30, cat = "veg" },
	onion = { name = { de = "Zwiebeln", en = "Onions" }, cost = 0.08, pack = 15, start = 30, cat = "veg" },
	cabbage = { name = { de = "Rotkraut", en = "Red cabbage" }, cost = 0.1, pack = 15, start = 30, cat = "veg" },
	cucumber = { name = { de = "Gurken", en = "Cucumber" }, cost = 0.1, pack = 15, start = 30, cat = "veg" },
	cheese = { name = { de = "Käse", en = "Cheese" }, cost = 0.3, pack = 10, start = 15, cat = "veg" },
	sauce_garlic = { name = { de = "Knoblauchsauce", en = "Garlic sauce" }, cost = 0.08, pack = 20, start = 30, cat = "sauce" },
	sauce_yogurt = { name = { de = "Joghurtsauce", en = "Yogurt sauce" }, cost = 0.08, pack = 20, start = 30, cat = "sauce" },
	sauce_cocktail = { name = { de = "Cocktailsauce", en = "Cocktail sauce" }, cost = 0.08, pack = 20, start = 30, cat = "sauce" },
	sauce_spicy = { name = { de = "Scharfe Sauce", en = "Spicy sauce" }, cost = 0.08, pack = 20, start = 30, cat = "sauce" },
	sauce_herb = { name = { de = "Kräutersauce", en = "Herb sauce" }, cost = 0.08, pack = 20, start = 30, cat = "sauce" },
	drink_ayran = { name = { de = "Ayran", en = "Ayran" }, cost = 0.6, pack = 12, start = 12, cat = "drink" },
	drink_cola = { name = { de = "Cola", en = "Cola" }, cost = 0.7, pack = 12, start = 12, cat = "drink" },
	drink_almdudler = { name = { de = "Almdudler", en = "Almdudler" }, cost = 0.8, pack = 12, start = 12, cat = "drink" },
}
IngredientData.StockOrder = {
	"bread_classic", "bread_duerum", "box", "meat_chicken", "meat_veal",
	"lettuce", "tomato", "onion", "cabbage", "cucumber", "cheese",
	"sauce_garlic", "sauce_yogurt", "sauce_cocktail", "sauce_spicy", "sauce_herb",
	"drink_ayran", "drink_cola", "drink_almdudler",
}

-- Look up any ingredient across categories: returns def, category
function IngredientData.Find(id: string)
	for _, cat in ipairs({ "Bread", "Meat", "Veg", "Sauce", "Extra", "Drinks" }) do
		local def = IngredientData[cat][id]
		if def then
			return def, cat
		end
	end
	return nil, nil
end

return IngredientData
