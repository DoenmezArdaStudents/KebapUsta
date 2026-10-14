-- Menu items and how each is built. A recipe template describes the default build;
-- OrderLogic turns it into concrete requirements with customer modifications.

local MenuData = {}

MenuData.Items = {
	kebap = {
		name = { de = "Kebap", en = "Kebab" },
		price = 6.5,
		bread = "classic",
		closeVerb = "close",
		needsHeat = false, -- only when the customer asks for "getoastet"
		toastOption = true,
		meatPortions = 2,
		defaultVeg = { "lettuce", "tomato", "onion", "cabbage" },
		optionalVeg = { "cucumber" },
		defaultSauces = { "garlic", "spicy" },
		allowMeat = { "chicken", "veal", "mixed" },
		unlock = nil,
		icon = "🥙",
	},
	duerum = {
		name = { de = "Dürüm", en = "Dürüm" },
		price = 7.5,
		bread = "duerum",
		closeVerb = "wrap",
		needsHeat = true, -- flatbread is always warmed
		toastOption = false,
		meatPortions = 2,
		defaultVeg = { "lettuce", "tomato", "onion", "cabbage" },
		optionalVeg = { "cucumber" },
		defaultSauces = { "yogurt", "spicy" },
		allowMeat = { "chicken", "veal", "mixed" },
		unlock = "menu_duerum",
		icon = "🌯",
	},
	veggie = {
		name = { de = "Veggie-Kebap", en = "Veggie Kebab" },
		price = 6.0,
		bread = "classic",
		closeVerb = "close",
		needsHeat = true,
		toastOption = false,
		meatPortions = 0,
		defaultVeg = { "lettuce", "tomato", "onion", "cabbage", "cucumber" },
		optionalVeg = {},
		defaultSauces = { "herb" },
		forceCheese = true,
		allowMeat = { "none" },
		unlock = "menu_veggie",
		icon = "🥗",
	},
	box = {
		name = { de = "Kebap-Box", en = "Kebab Box" },
		price = 8.0,
		bread = "box",
		closeVerb = "lid",
		needsHeat = false,
		toastOption = false,
		meatPortions = 3,
		defaultVeg = { "lettuce", "tomato", "cabbage" },
		optionalVeg = { "onion", "cucumber" },
		defaultSauces = { "garlic" },
		allowMeat = { "chicken", "veal", "mixed" },
		unlock = "menu_box",
		icon = "📦",
	},
}

MenuData.ItemOrder = { "kebap", "duerum", "veggie", "box" }

-- Base popularity weights for order generation
MenuData.Weights = { kebap = 40, duerum = 38, veggie = 14, box = 18 }

-- What players see on the boards: extras pricing (mirrors Config.Economy values)
MenuData.ExtrasBoard = {
	{ de = "Extra Fleisch", en = "Extra meat", key = "ExtraMeatPrice" },
	{ de = "Extra Käse", en = "Extra cheese", key = "CheesePrice" },
	{ de = "Extra Sauce", en = "Extra sauce", key = "ExtraSaucePrice" },
}

-- `unlocks` = the owner's unlock table (see Shared/Progression)
function MenuData.IsUnlocked(itemId: string, unlocks: { [string]: string }?): boolean
	local item = MenuData.Items[itemId]
	if not item then
		return false
	end
	if not item.unlock then
		return true
	end
	return unlocks ~= nil and unlocks[item.unlock] == "owned"
end

return MenuData
