-- Human-readable lines for an order item (shared by the HUD, the laptop POS app and the screen
-- on the in-world laptop).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local IngredientData = require(Shared.IngredientData)
local MenuData = require(Shared.MenuData)
local Localization = require(Shared.Localization)
local State = require(script.Parent.State)

local OrderText = {}

OrderText.MEAT_SHORT = {
	chicken = { de = "Huhn", en = "Chicken" },
	veal = { de = "Kalb", en = "Veal" },
	mixed = { de = "Gemischt", en = "Mixed" },
	none = { de = "ohne Fleisch", en = "no meat" },
}

local function L(key, params)
	return Localization.Get(key, State.lang, params)
end

local function ing(id)
	return Localization.Ingredient(id, State.lang)
end

-- one-line title, e.g. "🥙 Kebap · Huhn ×3"
function OrderText.Title(item): string
	local def = MenuData.Items[item.menu]
	local head = string.format("%s %s · %s", def.icon, def.name[State.lang], OrderText.MEAT_SHORT[item.meat][State.lang])
	if item.meat ~= "none" and item.meatPortions ~= 2 then
		head ..= string.format(" ×%d", item.meatPortions)
	end
	return head
end

-- detailed lines (rich text). `warn` is the colour used for "ohne …" (differs on light backgrounds)
function OrderText.Lines(item, warn: string?): { string }
	local def = MenuData.Items[item.menu]
	local lines = {}
	table.insert(lines, "<b>" .. OrderText.Title(item) .. "</b>")
	local veg, without = {}, {}
	for _, v in ipairs(IngredientData.VegOrder) do
		if item.veg[v] then
			table.insert(veg, ing(v))
		elseif table.find(item.baseVeg or def.defaultVeg, v) then
			table.insert(without, ing(v))
		end
	end
	if #veg > 0 then
		table.insert(lines, "🥗 " .. table.concat(veg, ", "))
	end
	if #without > 0 then
		table.insert(lines, string.format("<font color='%s'><b>%s</b> %s</font>", warn or "#ff7a66", L("without"), table.concat(without, ", ")))
	end
	local sauces = {}
	for _, s in ipairs(IngredientData.SauceOrder) do
		local n = item.sauces[s]
		if n and n > 0 then
			table.insert(sauces, ing(s) .. (n > 1 and " <b>×2</b>" or ""))
		end
	end
	if #sauces > 0 then
		table.insert(lines, "🥫 " .. table.concat(sauces, ", "))
	else
		table.insert(lines, State.lang == "de" and "🥫 keine Sauce" or "🥫 no sauce")
	end
	local extras = {}
	if item.cheese then
		table.insert(extras, "🧀 " .. L("cheese"))
	end
	if item.heat then
		table.insert(extras, "🔥 " .. (def.toastOption and L("toasted") or L("warmed")))
	end
	table.insert(extras, item.takeaway and ("🛍️ " .. L("takeaway")) or ("🍽️ " .. L("plate")))
	table.insert(lines, table.concat(extras, "  "))
	return lines
end

function OrderText.Drinks(t): string?
	if not t.drinks or #t.drinks == 0 then
		return nil
	end
	local parts = {}
	for di, d in ipairs(t.drinks) do
		local def = IngredientData.Drinks[d]
		local done = t.drinksDelivered and t.drinksDelivered[di]
		table.insert(parts, (done and "✅ " or "") .. def.icon .. " " .. def.name[State.lang])
	end
	return table.concat(parts, "   ")
end

function OrderText.Patience(t): number
	if typeof(t.model) == "Instance" and t.model.Parent then
		return math.clamp(tonumber(t.model:GetAttribute("Patience")) or 1, 0, 1)
	end
	return 1
end

return OrderText
