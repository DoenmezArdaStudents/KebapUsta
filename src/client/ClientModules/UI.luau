-- HUD: compact, animated glass interface. Cash / level / reputation (top left), clock pill (top
-- centre), open-order badge + laptop button (top right), preparation checklist & tray (bottom
-- centre), customer dialogue card, toasts, order feedback, tutorial card and the sleep / wake-up
-- screen at the end of a day. Upgrades, stock, goals and settings live on the laptop now.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local MenuData = require(Shared.MenuData)
local OrderLogic = require(Shared.OrderLogic)
local Localization = require(Shared.Localization)
local State = require(script.Parent.State)
local Sound = require(script.Parent.Sound)
local Kit = require(script.Parent.UIKit)
local OrderText = require(script.Parent.OrderText)
local Laptop = require(script.Parent.Laptop)

local UI = {}
UI.OnPanelChanged = function(_open: boolean) end

local player = Players.LocalPlayer
local new, corner, round, stroke, pad, list, label, tween = Kit.new, Kit.corner, Kit.round, Kit.stroke, Kit.pad, Kit.list, Kit.label, Kit.tween
local T, F = Kit.T, Kit.F

local gui: ScreenGui
local sleepGui: ScreenGui
local refs: { [string]: any } = {}

local function L(key, params)
	return Localization.Get(key, State.lang, params)
end

local function money(n)
	return Localization.Money(n or 0)
end

local function ing(id)
	return Localization.Ingredient(id, State.lang)
end

local function fmtClock(h: number)
	local hh = math.floor(h)
	local mm = math.floor((h - hh) * 60 / 5) * 5
	return string.format("%02d:%02d", hh, mm)
end

-- kept for compatibility (other modules may still call it)
function UI.ItemLines(item)
	return OrderText.Lines(item)
end

---------------------------------------------------------------------------
-- top left: cash · level · reputation
---------------------------------------------------------------------------
local shown = { cash = nil :: number?, level = nil :: number?, tickets = 0 }

local function buildStats()
	local col = new("Frame", { Name = "Stats", Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(230, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui })
	list(false, 6).Parent = col
	refs.stats = col
	-- cash pill
	local cash = Kit.glass({ LayoutOrder = 1, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Parent = col }, 20)
	pad(6, 0, 16, 0).Parent = cash
	list(true, 8, nil, Enum.VerticalAlignment.Center).Parent = cash
	local coin = new("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(28, 28), BackgroundColor3 = T.gold, BorderSizePixel = 0, Parent = cash }, { round() })
	Kit.gradient(Color3.fromRGB(255, 226, 120), Color3.fromRGB(230, 150, 30), 45).Parent = coin
	label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 17, TextColor3 = Color3.fromRGB(110, 60, 0), Text = "€", Parent = coin })
	refs.coin = coin
	refs.cash = label({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Font = F.black, TextSize = 22, Text = "€0,00", Parent = cash })
	refs.cashPill = cash
	-- level + xp + stars
	local lv = Kit.glass({ LayoutOrder = 2, Size = UDim2.fromOffset(230, 44), Parent = col }, 12)
	local badge = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = T.blue, BorderSizePixel = 0, Parent = lv }, { round() })
	Kit.gradient(Color3.fromRGB(120, 180, 255), Color3.fromRGB(60, 110, 240), 45).Parent = badge
	refs.levelNum = label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 15, Text = "1", Parent = badge })
	refs.levelBadge = badge
	refs.role = label({ Position = UDim2.fromOffset(44, 5), Size = UDim2.new(1, -52, 0, 16), TextSize = 13, Font = F.bold, Text = "", Parent = lv })
	refs.rep = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 5), Size = UDim2.fromOffset(90, 16), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 13, TextColor3 = T.gold, Text = "", Parent = lv })
	local _, xpFill = Kit.bar({ Position = UDim2.fromOffset(44, 27), Size = UDim2.new(1, -54, 0, 6), Parent = lv }, T.blue)
	Kit.gradient(Color3.fromRGB(120, 190, 255), Color3.fromRGB(80, 120, 255), 0).Parent = xpFill
	refs.xpFill = xpFill
	-- save warning
	refs.save = label({ LayoutOrder = 3, Size = UDim2.fromOffset(230, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextColor3 = T.orange, TextWrapped = true, Text = "", Parent = col })
end

local function floatText(parent: GuiObject, text: string, color: Color3)
	local f = label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 8, 0.5, 0),
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = F.black,
		TextSize = 18,
		TextColor3 = color,
		TextStrokeTransparency = 0.6,
		Text = text,
		Parent = parent,
	})
	tween(f, 1.2, { Position = UDim2.new(1, 18, 0.5, -26), TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(1.25, function()
		f:Destroy()
	end)
end

local function updateStats()
	local ps, shop = State.player, State.shop
	if ps then
		if shown.cash == nil then
			shown.cash = ps.cash
			refs.cash.Text = money(ps.cash)
		elseif ps.cash ~= shown.cash then
			local diff = ps.cash - (shown.cash :: number)
			Kit.countTo(refs.cash, shown.cash :: number, ps.cash, money, 0.7)
			floatText(refs.cashPill, (diff > 0 and "+" or "") .. money(diff), diff > 0 and T.green or T.red)
			Kit.pop(refs.coin, 1.35, 0.4)
			shown.cash = ps.cash
		end
		refs.levelNum.Text = tostring(ps.level)
		if shown.level and ps.level > shown.level then
			Kit.pop(refs.levelBadge, 1.6, 0.6)
		end
		shown.level = ps.level
		tween(refs.xpFill, 0.6, { Size = UDim2.fromScale(math.clamp(ps.xp / math.max(ps.xpNext, 1), 0, 1), 1) })
		refs.role.Text = (ps.isOwner and ("👑 " .. L("role_owner")) or ("🧑‍🍳 " .. L("role_staff"))) .. string.format("  <font color='#b0aca8'>%d/%d EP</font>", math.floor(ps.xp), ps.xpNext)
		refs.save.Text = ps.saveOk and "" or L("no_save")
	end
	if shop then
		local full = math.floor(shop.reputation + 0.5)
		refs.rep.Text = string.rep("★", full) .. "<font color='#6a6660'>" .. string.rep("★", 5 - full) .. "</font>"
	end
end

---------------------------------------------------------------------------
-- top centre: clock pill
---------------------------------------------------------------------------
local lastPeriod = nil
local lastPhase = nil

local function buildClock()
	local pill = Kit.glass({ Name = "Clock", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Parent = gui }, 18)
	pad(14, 0, 16, 0).Parent = pill
	list(true, 10, nil, Enum.VerticalAlignment.Center).Parent = pill
	refs.dot = new("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(9, 9), BackgroundColor3 = T.green, BorderSizePixel = 0, Parent = pill }, { round() })
	Kit.pulse(refs.dot, "BackgroundTransparency", 0, 0.65, 0.9)
	refs.clock = label({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Font = F.black, TextSize = 20, Text = "10:00", Parent = pill })
	refs.day = label({ LayoutOrder = 3, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Font = F.medium, TextSize = 14, TextColor3 = T.dim, Text = "", Parent = pill })
	refs.clockPill = pill
	-- period line below (cross-fades on change)
	refs.period = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(400, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, Font = F.bold, TextColor3 = T.dim, TextStrokeTransparency = 0.7, Text = "", Parent = gui })
end

local function updateClock()
	local shop = State.shop
	if not shop then
		return
	end
	refs.clock.Text = fmtClock(shop.clock)
	local phase = shop.phase or "open"
	if phase == "after_hours" then
		refs.day.Text = "🔑 " .. (State.lang == "de" and "Laden absperren!" or "Lock the shop!")
		refs.day.TextColor3 = T.orange
	else
		refs.day.Text = string.format("%s %d", L("day"), shop.day)
		refs.day.TextColor3 = T.dim
	end
	refs.dot.BackgroundColor3 = shop.open and T.green or (phase == "after_hours" and T.orange or T.red)
	local periodText = (shop.open and L("open") or L("closed")) .. "  ·  " .. L(shop.period)
	if periodText ~= lastPeriod then
		lastPeriod = periodText
		refs.period.TextTransparency = 1
		refs.period.Position = UDim2.new(0.5, 0, 0, 60)
		refs.period.Text = periodText
		tween(refs.period, 0.5, { TextTransparency = 0.1, Position = UDim2.new(0.5, 0, 0, 54) })
	end
	if phase ~= lastPhase then
		if phase == "after_hours" then
			Kit.pop(refs.clockPill, 1.25, 0.6)
		end
		lastPhase = phase
	end
end

---------------------------------------------------------------------------
-- top right: orders badge + laptop button
---------------------------------------------------------------------------
local function buildBadges()
	local row = new("Frame", { Name = "Badges", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = gui })
	list(true, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center).Parent = row
	local orders = Kit.glass({ LayoutOrder = 1, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Text = "", AutoButtonColor = false, Parent = row }, 20, "TextButton")
	pad(14, 0, 16, 0).Parent = orders
	list(true, 8, nil, Enum.VerticalAlignment.Center).Parent = orders
	label({ LayoutOrder = 1, Size = UDim2.fromOffset(20, 40), TextSize = 18, Text = "🧾", Parent = orders })
	refs.orderCount = label({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Font = F.black, TextSize = 18, Text = "0", Parent = orders })
	local urgent = new("Frame", { LayoutOrder = 3, Size = UDim2.fromOffset(46, 6), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = orders }, { round() })
	refs.urgentFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.green, BorderSizePixel = 0, Parent = urgent }, { round() })
	refs.urgent = urgent
	refs.orders = orders
	Kit.hover(orders, 0.05)
	orders.Activated:Connect(function()
		Sound.Play("click")
		Laptop.Toggle("orders")
	end)
	local lap = Kit.glass({ LayoutOrder = 2, Size = UDim2.fromOffset(40, 40), Text = "", AutoButtonColor = false, Parent = row }, 20, "TextButton")
	label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 19, Text = "💻", Parent = lap })
	Kit.hover(lap, 0.08)
	lap.Activated:Connect(function()
		Sound.Play("click")
		Laptop.Toggle("laptop")
	end)
end

local function updateBadges()
	local n = #State.tickets
	refs.orderCount.Text = tostring(n)
	if n > shown.tickets then
		Kit.pop(refs.orders, 1.25, 0.5)
		Sound.Play("toast")
	end
	shown.tickets = n
	refs.urgent.Visible = n > 0
end

local function updateUrgent()
	local worst = 1
	for _, t in ipairs(State.tickets) do
		worst = math.min(worst, OrderText.Patience(t))
	end
	tween(refs.urgentFill, 0.45, { Size = UDim2.fromScale(worst, 1), BackgroundColor3 = worst > 0.6 and T.green or (worst > 0.3 and T.orange or T.red) }, Enum.EasingStyle.Linear)
end

---------------------------------------------------------------------------
-- bottom centre: preparation checklist + tray
---------------------------------------------------------------------------
local STATE_COLORS = {
	ok = Color3.fromRGB(56, 170, 96),
	missing = Color3.fromRGB(64, 62, 70),
	wrong = Color3.fromRGB(205, 60, 50),
	partial = Color3.fromRGB(215, 135, 35),
	extra = Color3.fromRGB(215, 135, 35),
}
local prevChip: { [string]: string } = {}
local mealShown = false

local function buildMeal()
	local p = Kit.glass({ Name = "Meal", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 140), Size = UDim2.fromOffset(500, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = gui }, 14)
	pad(12, 10, 12, 12).Parent = p
	list(false, 8).Parent = p
	local head = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = p })
	refs.mealTitle = label({ Size = UDim2.new(1, -150, 1, 0), Font = F.bold, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = head })
	refs.tray = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 150, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14, Font = F.medium, Text = "", Parent = head })
	refs.mealSub = label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = T.dim, Text = "", Parent = p })
	local chips = new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = p })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(115, 22), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
	refs.chips = chips
	refs.meal = p
end

local function chip(key: string, text: string, state: string, order: number)
	local c = new("Frame", { LayoutOrder = order, BackgroundColor3 = STATE_COLORS[state] or T.glass2, BorderSizePixel = 0, Parent = refs.chips }, { corner(6) })
	if state == "missing" then
		stroke(Color3.new(1, 1, 1), 0.75).Parent = c
	end
	local icon = state == "ok" and "✓ " or (state == "wrong" and "✗ " or (state == "missing" and "○ " or "◐ "))
	label({ Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -8, 1, 0), TextSize = 12, Font = F.bold, TextTruncate = Enum.TextTruncate.AtEnd, Text = icon .. text, Parent = c })
	if prevChip[key] ~= state then
		Kit.pop(c, prevChip[key] and 1.25 or 0.6, 0.3)
	end
	return state
end

local function entryText(e)
	local k = e.key
	local d = e.data or {}
	if k == "bread" then
		return ing(d.id)
	elseif k == "heat" then
		return d.burnt and L("bread_burnt") or L("heat_req")
	elseif k == "meat" then
		if d.id == "none" then
			return L("meat_none")
		end
		return string.format("%s %d/%d", OrderText.MEAT_SHORT[d.id][State.lang], d.have or 0, d.need or 0)
	elseif string.sub(k, 1, 4) == "veg:" then
		return (d.forbidden and (L("without") .. " ") or "") .. ing(d.id)
	elseif string.sub(k, 1, 6) == "sauce:" then
		local name = ing(d.id)
		if d.forbidden then
			return L("without") .. " " .. name
		end
		return name .. ((d.need or 1) > 1 and string.format(" %d/%d", d.have, d.need) or "")
	elseif k == "cheese" then
		return (d.forbidden and (L("without") .. " ") or "") .. L("cheese")
	elseif k == "close" then
		return L("close_" .. (d.verb or "close"))
	elseif k == "pack" then
		return d.want == "takeaway" and L("takeaway") or L("plate")
	end
	return k
end

local function setMealVisible(v: boolean)
	if v == mealShown then
		return
	end
	mealShown = v
	tween(refs.meal, 0.45, { Position = v and UDim2.new(0.5, 0, 1, -14) or UDim2.new(0.5, 0, 1, 160) }, v and Enum.EasingStyle.Back or Enum.EasingStyle.Quint, v and Enum.EasingDirection.Out or Enum.EasingDirection.In)
end

local function updateMeal()
	local ps = State.player
	if not ps then
		return
	end
	Kit.clear(refs.chips, { "UIGridLayout" })
	local nextChip = {}
	local meal = ps.meal
	local item, ticket = State.SelectedItem()
	if meal then
		local breadDef = IngredientData.Bread[meal.bread]
		local title = breadDef.icon .. " " .. L("meal_title")
		if ps.location == "grill" then
			local elapsed = (ps.grillElapsed or 0) + (os.clock() - State.grillReceivedAt)
			title ..= string.format("  ·  🔥 %.0fs <font color='#b0aca8'>(%d–%ds)</font>", elapsed, Config.Prep.ToastPerfectMin, Config.Prep.ToastPerfectMax)
		end
		refs.mealTitle.Text = title
	else
		refs.mealTitle.Text = "🔪 " .. L("meal_title")
	end
	if item then
		local def = MenuData.Items[item.menu]
		refs.mealSub.Text = L("meal_for", { name = string.format("%s %s – %s", ticket.emoji, ticket.name, def.name[State.lang]) })
		for i, e in ipairs(OrderLogic.Checklist(item, meal)) do
			nextChip[e.key] = chip(e.key, entryText(e), meal and e.state or "missing", i)
		end
	elseif meal then
		refs.mealSub.Text = L("meal_pick")
		local order = 0
		local function add(key, text, state)
			order += 1
			nextChip[key] = chip(key, text, state or "ok", order)
		end
		add("bread", ing(meal.bread))
		if meal.heat == 1 then
			add("heat", L("bread_heated"))
		elseif meal.heat == 2 then
			add("heat", L("bread_burnt"), "wrong")
		end
		for m, n in pairs(meal.meat) do
			add("meat" .. m, string.format("%s ×%d", OrderText.MEAT_SHORT[m][State.lang], n))
		end
		for _, v in ipairs(IngredientData.VegOrder) do
			if (meal.veg[v] or 0) > 0 then
				add("veg" .. v, ing(v) .. (meal.veg[v] > 1 and (" ×" .. meal.veg[v]) or ""))
			end
		end
		for _, s in ipairs(IngredientData.SauceOrder) do
			if (meal.sauces[s] or 0) > 0 then
				add("sauce" .. s, ing(s) .. (meal.sauces[s] > 1 and (" ×" .. meal.sauces[s]) or ""))
			end
		end
		if meal.cheese > 0 then
			add("cheese", L("cheese"))
		end
		if meal.closed then
			add("closed", L("close_close"))
		end
	else
		refs.mealSub.Text = L("meal_empty")
	end
	prevChip = nextChip
	-- tray
	local parts = {}
	for _, t in ipairs(ps.tray or {}) do
		if t.kind == "drink" then
			table.insert(parts, IngredientData.Drinks[t.id].icon)
		else
			local m = t.meal
			table.insert(parts, (m.bread == "duerum" and "🌯" or (m.bread == "box" and "📦" or "🥙")) .. (m.pack == "takeaway" and "🛍️" or "🍽️"))
		end
	end
	refs.tray.Text = string.format("%s  <font color='#b0aca8'>%d/%d</font>", #parts > 0 and table.concat(parts, " ") or "🍽️", #(ps.tray or {}), ps.trayCap or 2)
	setMealVisible(meal ~= nil or item ~= nil or #(ps.tray or {}) > 0)
end

---------------------------------------------------------------------------
-- dialogue card (bottom left)
---------------------------------------------------------------------------
local dialogueToken = 0

local function buildDialogue()
	local d = new("CanvasGroup", { Name = "Dialogue", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -360, 1, -14), Size = UDim2.fromOffset(340, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.glass, BackgroundTransparency = 0.12, BorderSizePixel = 0, GroupTransparency = 1, Parent = gui }, { corner(14), stroke(nil, 0.86) })
	pad(14, 12).Parent = d
	list(false, 6).Parent = d
	refs.dlgName = label({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20), Font = F.black, TextSize = 16, TextColor3 = T.gold, Text = "", Parent = d })
	refs.dlgText = label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 15, TextWrapped = true, Text = "", Parent = d })
	local row = new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = d })
	list(true, 8).Parent = row
	refs.dlgOk = Kit.button({ Size = UDim2.new(0.5, -4, 1, 0), TextSize = 13, Text = "", Parent = row }, function()
		UI.HideDialogue()
	end)
	refs.dlgRepeat = Kit.button({ Size = UDim2.new(0.5, -4, 1, 0), TextSize = 13, BackgroundColor3 = T.glass2, Text = "", Parent = row }, function()
		if refs.dlgCustomer then
			State.Request("RepeatOrder", refs.dlgCustomer)
		end
	end)
	refs.dialogue = d
end

function UI.HideDialogue()
	dialogueToken += 1
	tween(refs.dialogue, 0.3, { Position = UDim2.new(0, -360, 1, -14), GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
end

function UI.ShowDialogue(data)
	Laptop.OnDialogue(data)
	local d = refs.dialogue
	refs.dlgCustomer = data.id
	refs.dlgName.Text = string.format("%s%s %s", data.vip and "⭐ " or "", data.emoji or "", data.name or "")
	refs.dlgOk.Text = State.lang == "de" and "👍 Kommt sofort!" or "👍 Coming right up!"
	refs.dlgRepeat.Text = State.lang == "de" and "🔁 Wie bitte?" or "🔁 Sorry, again?"
	tween(d, 0.45, { Position = UDim2.new(0, 14, 1, -14), GroupTransparency = 0 }, Enum.EasingStyle.Back)
	dialogueToken += 1
	local token = dialogueToken
	task.spawn(function()
		for _, line in ipairs(data.lines or {}) do
			local text = line[State.lang] or line.en or ""
			-- typewriter (character-safe for umlauts)
			local chars = {}
			for _, cp in utf8.codes(text) do
				table.insert(chars, utf8.char(cp))
			end
			for i = 1, #chars, 2 do
				if token ~= dialogueToken then
					return
				end
				refs.dlgText.Text = table.concat(chars, "", 1, math.min(i + 1, #chars))
				task.wait(0.014)
			end
			refs.dlgText.Text = text
			task.wait(1.1)
		end
		task.wait(9)
		if token == dialogueToken then
			UI.HideDialogue()
		end
	end)
end

---------------------------------------------------------------------------
-- toasts (right side, slide in)
---------------------------------------------------------------------------
local TOAST = {
	info = { T.blue, "ℹ️" },
	warn = { T.orange, "⚠️" },
	bad = { T.red, "⛔" },
	success = { T.green, "✅" },
	levelup = { Color3.fromRGB(110, 140, 255), "⬆️" },
	achievement = { T.gold, "🏆" },
	goal = { T.green, "🎯" },
	vip = { T.gold, "⭐" },
	rush = { T.accent, "🔥" },
	event = { T.gold, "📣" },
	day = { Color3.fromRGB(150, 130, 255), "🌙" },
}

local function buildToasts()
	local holder = new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 64), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1, Parent = gui })
	list(false, 6, Enum.HorizontalAlignment.Right).Parent = holder
	refs.toasts = holder
end

local toastCount = 0
local lastToast: { [string]: number } = {}

function UI.Toast(key: string, params, kind: string?)
	local text = L(key, params)
	if lastToast[text] and os.clock() - lastToast[text] < 1.2 then
		return
	end
	lastToast[text] = os.clock()
	local style = TOAST[kind or "info"] or TOAST.info
	-- mirror into the laptop's notification centre
	Laptop.Notify(text, "", style[2])
	if Laptop.IsOpen() then
		return
	end
	toastCount += 1
	local holder = refs.toasts
	local items = {}
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	if #items >= 4 then
		items[1]:Destroy()
	end
	local slot = new("Frame", { LayoutOrder = toastCount, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = holder })
	local card = new("CanvasGroup", { Position = UDim2.fromOffset(320, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.glass, BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = slot }, { corner(12), stroke(nil, 0.86) })
	new("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = style[1], BorderSizePixel = 0, Parent = card })
	local inner = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card })
	pad(14, 9, 12, 11).Parent = inner
	label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, Font = F.bold, TextSize = 14, Text = style[2] .. "  " .. text, Parent = inner })
	local timer = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, 0), Size = UDim2.new(1, -4, 0, 2), BackgroundColor3 = style[1], BackgroundTransparency = 0.3, BorderSizePixel = 0, Parent = card })
	local life = kind == "achievement" and 5 or 3.4
	tween(card, 0.5, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	tween(timer, life, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
	if kind == "levelup" or kind == "achievement" then
		Sound.Play("levelup")
	end
	task.delay(life, function()
		if card.Parent then
			tween(card, 0.35, { Position = UDim2.fromOffset(320, 0), GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.36, function()
				slot:Destroy()
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- order feedback (stars pop in one by one, money counts up)
---------------------------------------------------------------------------
local function buildFeedback()
	local f = new("CanvasGroup", { Name = "Feedback", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.fromOffset(270, 168), BackgroundColor3 = T.glass, BackgroundTransparency = 0.1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false, Parent = gui }, { corner(16), stroke(nil, 0.84) })
	local starRow = new("Frame", { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = f })
	list(true, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent = starRow
	refs.fbStars = {}
	for i = 1, 5 do
		refs.fbStars[i] = label({ LayoutOrder = i, Size = UDim2.fromOffset(28, 30), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 28, Font = F.black, Text = "★", Parent = starRow })
	end
	refs.fbMoney = label({ Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 32), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 28, TextColor3 = T.green, Text = "", Parent = f })
	refs.fbDetail = label({ Position = UDim2.fromOffset(10, 76), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, TextColor3 = T.dim, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = f })
	refs.fbBars = {}
	for i, k in ipairs({ "fb_accuracy", "fb_quality", "fb_speed" }) do
		local y = 100 + (i - 1) * 20
		refs.fbBars[k] = {
			label = label({ Position = UDim2.fromOffset(16, y), Size = UDim2.new(0.45, 0, 0, 16), TextSize = 12, Text = "", Parent = f }),
			fill = select(2, Kit.bar({ Position = UDim2.new(0.47, 0, 0, y + 5), Size = UDim2.new(0.47, 0, 0, 6), Parent = f }, T.green)),
		}
	end
	refs.feedback = f
end

local feedbackToken = 0
function UI.ShowFeedback(r)
	local f = refs.feedback
	feedbackToken += 1
	local token = feedbackToken
	f.Visible = true
	f.GroupTransparency = 1
	f.Position = UDim2.fromScale(0.5, 0.38)
	tween(f, 0.4, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.34) }, Enum.EasingStyle.Back)
	for i, s in ipairs(refs.fbStars) do
		s.TextColor3 = i <= r.stars and T.gold or Color3.fromRGB(80, 78, 84)
		if i <= r.stars then
			Kit.pop(s, 0.2, 0.35, 0.15 + i * 0.08)
		end
	end
	Kit.countTo(refs.fbMoney, 0, r.pay + r.tip + r.vipBonus, function(v)
		return "+" .. money(v)
	end, 0.9)
	local detail = string.format("%s %s · %s +%s · %s +%d", r.customer, r.perfect and "💯" or "", L("fb_tip"), money(r.tip), L("fb_xp"), r.xp)
	if r.vipBonus > 0 then
		detail ..= " · ⭐ +" .. money(r.vipBonus)
	end
	refs.fbDetail.Text = detail
	local vals = { fb_accuracy = r.accuracy, fb_quality = r.quality, fb_speed = r.patience }
	for k, e in pairs(refs.fbBars) do
		local v = math.clamp(vals[k] or 0, 0, 1)
		e.label.Text = string.format("%s  <b>%d%%</b>", L(k), math.floor(v * 100 + 0.5))
		e.fill.Size = UDim2.fromScale(0, 1)
		e.fill.BackgroundColor3 = v > 0.8 and T.green or (v > 0.5 and T.orange or T.red)
		tween(e.fill, 0.8, { Size = UDim2.fromScale(v, 1) }, Enum.EasingStyle.Quint, nil, 0.3)
	end
	Sound.Play(r.stars >= 4 and "success" or "click")
	task.delay(3.8, function()
		if token == feedbackToken then
			local tw = tween(f, 0.35, { GroupTransparency = 1, Position = UDim2.fromScale(0.5, 0.31) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw.Completed:Connect(function()
				if token == feedbackToken then
					f.Visible = false
				end
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- NÄCHSTE ZIELE: short / medium / long goal (left, under the stats; hidden during the tutorial)
---------------------------------------------------------------------------
local tutVisible = false
local cutting = false -- meat cutting mode hides the goals panel
local goalsCollapsed = false
local goalRows: { any } = {}
local lastGoalTitles: { [string]: string } = {}
local GOAL_KEYS = { "short", "medium", "long" }
local GOAL_COLORS = { T.blue, Color3.fromRGB(176, 120, 255), T.gold }

local function buildGoals()
	local g = Kit.glass({ Name = "Goals", Position = UDim2.fromOffset(14, 128), Size = UDim2.fromOffset(270, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false }, 14, "CanvasGroup")
	g.Parent = gui
	pad(10, 8, 10, 10).Parent = g
	list(false, 6).Parent = g
	local head = new("TextButton", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = g })
	refs.goalHead = label({ Size = UDim2.new(1, -20, 1, 0), Font = F.black, TextSize = 12, TextColor3 = T.dim, Text = "", Parent = head })
	refs.goalArrow = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(20, 18), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextSize = 12, TextColor3 = T.dim, Text = "▼", Parent = head })
	head.Activated:Connect(function()
		goalsCollapsed = not goalsCollapsed
		Sound.Play("click")
		for _, r in ipairs(goalRows) do
			r.sub.Visible = not goalsCollapsed and r.sub.Text ~= ""
			r.foot.Visible = not goalsCollapsed
		end
		refs.goalArrow.Text = goalsCollapsed and "▶" or "▼"
	end)
	for i = 1, 3 do
		local row = new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = g })
		list(false, 3).Parent = row
		local top = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = row })
		local chipF = new("Frame", { Size = UDim2.fromOffset(52, 16), Position = UDim2.fromOffset(0, 1), BackgroundColor3 = GOAL_COLORS[i], BorderSizePixel = 0, Parent = top }, { round() })
		local chipL = label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 10, TextColor3 = Color3.fromRGB(20, 20, 24), Text = "", Parent = chipF })
		local title = label({ Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -58, 1, 0), Font = F.bold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = top })
		local sub = label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = T.dim, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = row })
		local barBg, fill = Kit.bar({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 5) }, GOAL_COLORS[i])
		barBg.Parent = row
		local foot = new("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Parent = row })
		local prog = label({ Size = UDim2.new(0.45, 0, 1, 0), TextSize = 11, TextColor3 = T.dim, Text = "", Parent = foot })
		local reward = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.55, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11, Font = F.bold, TextColor3 = T.gold, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = foot })
		goalRows[i] = { row = row, chip = chipL, title = title, sub = sub, fill = fill, prog = prog, reward = reward, foot = foot }
	end
	refs.goals = g
end

local function updateGoals()
	local g = refs.goals
	if not g then
		return
	end
	local ng = State.shop and State.shop.nextGoals
	local show = ng ~= nil and not tutVisible and not cutting
	if show ~= g.Visible then
		g.Visible = show
		if show then
			g.GroupTransparency = 1
			g.Position = UDim2.fromOffset(-10, 128)
			tween(g, 0.45, { GroupTransparency = 0, Position = UDim2.fromOffset(14, 128) }, Enum.EasingStyle.Back)
		end
	end
	if not ng then
		return
	end
	refs.goalHead.Text = "🚀 " .. (State.lang == "de" and "NÄCHSTE ZIELE" or "NEXT GOALS")
	local tags = State.lang == "de" and { "KURZ", "MITTEL", "LANG" } or { "SHORT", "MEDIUM", "LONG" }
	for i, key in ipairs(GOAL_KEYS) do
		local r = goalRows[i]
		local goal = ng[key]
		r.row.Visible = goal ~= nil
		if goal then
			local title = goal.icon .. " " .. goal.title[State.lang]
			r.chip.Text = tags[i]
			r.title.Text = title
			local sub = goal.sub and goal.sub[State.lang] or ""
			if goal.money and (goal.need or 0) > 0 then
				sub = (State.lang == "de" and "Noch " or "Need ") .. money(goal.need) .. (sub ~= "" and (" · " .. sub) or "")
			elseif goal.action == "buy" then
				sub = State.lang == "de" and "✅ Genug Geld – Laptop → Shop-Ausbau [U]" or "✅ Enough cash – Laptop → Shop Upgrades [U]"
			end
			r.sub.Text = sub
			r.sub.Visible = sub ~= "" and not goalsCollapsed
			r.prog.Text = goal.money and (money(goal.cur) .. " / " .. money(goal.max)) or string.format("%d / %d", math.floor(goal.cur or 0), goal.max or 1)
			r.reward.Text = "🎁 " .. goal.reward[State.lang]
			tween(r.fill, 0.5, { Size = UDim2.fromScale(math.clamp(goal.progress or 0, 0, 1), 1) }, Enum.EasingStyle.Quint)
			if lastGoalTitles[key] ~= title then
				if lastGoalTitles[key] ~= nil then
					Kit.pop(r.row, 0.92, 0.35)
				end
				lastGoalTitles[key] = title
			end
		end
	end
end

---------------------------------------------------------------------------
-- tutorial card
---------------------------------------------------------------------------

local function buildTutorial()
	local t = new("CanvasGroup", { Name = "Tutorial", Position = UDim2.fromOffset(14, 128), Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(28, 44, 92), BackgroundTransparency = 0.08, BorderSizePixel = 0, GroupTransparency = 1, Visible = false, Parent = gui }, { corner(14), stroke(Color3.fromRGB(140, 170, 255), 0.6) })
	pad(12, 10).Parent = t
	list(false, 6).Parent = t
	refs.tutTitle = label({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), Font = F.black, TextSize = 14, TextColor3 = Color3.fromRGB(170, 195, 255), Text = "", Parent = t })
	refs.tutText = label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 14, Text = "", Parent = t })
	local barBg, fill = Kit.bar({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 4) }, Color3.fromRGB(140, 170, 255))
	barBg.Parent = t
	refs.tutFill = fill
	refs.tutSkip = Kit.button({ LayoutOrder = 4, Size = UDim2.fromOffset(110, 24), BackgroundColor3 = Color3.fromRGB(60, 80, 140), TextSize = 12, Text = "", Parent = t }, function()
		State.Request("SkipTutorial")
	end)
	refs.tutorial = t
end

local lastTutKey = nil
function UI.SetTutorial(step: number?, total: number, textKey: string?)
	local t = refs.tutorial
	if not step or not textKey then
		if tutVisible then
			tutVisible = false
			local tw = tween(t, 0.3, { GroupTransparency = 1, Position = UDim2.fromOffset(-10, 128) })
			tw.Completed:Connect(function()
				if not tutVisible then
					t.Visible = false
				end
			end)
		end
		lastTutKey = nil
		updateGoals()
		return
	end
	if not tutVisible then
		tutVisible = true
		t.Visible = true
		t.Position = UDim2.fromOffset(-20, 128)
		tween(t, 0.45, { GroupTransparency = 0, Position = UDim2.fromOffset(14, 128) }, Enum.EasingStyle.Back)
		updateGoals()
	end
	refs.tutTitle.Text = string.format("🎓 %s · %d/%d", string.upper(L("tut_title")), step, total)
	refs.tutText.Text = L(textKey)
	refs.tutSkip.Text = L("tut_skip")
	refs.tutSkip.Visible = step < total
	tween(refs.tutFill, 0.5, { Size = UDim2.fromScale(step / total, 1) })
	if textKey ~= lastTutKey then
		lastTutKey = textKey
		Kit.pop(t, 0.96, 0.3)
	end
end

---------------------------------------------------------------------------
-- end of day: sleep (fade to black + summary) and wake up (eyelids open)
---------------------------------------------------------------------------
local function buildSleep()
	sleepGui = new("ScreenGui", { Name = "SleepGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	refs.black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(4, 4, 10), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = sleepGui })
	refs.sleepTitle = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromOffset(600, 60), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 44, TextTransparency = 1, Text = "", Parent = sleepGui })
	refs.zzz = {}
	for i = 1, 3 do
		refs.zzz[i] = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + i * 0.03, 0.12), Size = UDim2.fromOffset(60, 60), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 20 + i * 8, TextColor3 = Color3.fromRGB(170, 180, 255), TextTransparency = 1, Text = "z", Parent = sleepGui })
	end
	-- summary card
	local s = new("CanvasGroup", { Name = "Summary", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromOffset(380, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(22, 22, 30), BackgroundTransparency = 0.05, BorderSizePixel = 0, GroupTransparency = 1, Visible = false, Parent = sleepGui }, { corner(18), stroke(nil, 0.84) })
	pad(20, 16).Parent = s
	list(false, 6).Parent = s
	refs.sumTitle = label({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 28), Font = F.black, TextSize = 21, TextColor3 = T.gold, Text = "", Parent = s })
	refs.sumRows = new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = s })
	list(false, 4).Parent = refs.sumRows
	refs.summary = s
	-- eyelids for waking up
	refs.lidTop = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.55), BackgroundColor3 = Color3.fromRGB(4, 4, 10), BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = sleepGui })
	refs.lidBottom = new("Frame", { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.55), BackgroundColor3 = Color3.fromRGB(4, 4, 10), BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = sleepGui })
	for _, lid in ipairs({ refs.lidTop, refs.lidBottom }) do
		local g = new("UIGradient", { Rotation = lid == refs.lidTop and 90 or -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = lid })
		local _ = g
	end
	refs.wakeTitle = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.76), Size = UDim2.fromOffset(600, 50), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 36, TextStrokeTransparency = 0.5, TextTransparency = 1, Text = "", ZIndex = 6, Parent = sleepGui })
	refs.wakeSub = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.fromOffset(600, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = F.medium, TextSize = 20, TextStrokeTransparency = 0.6, TextTransparency = 1, Text = "", ZIndex = 6, Parent = sleepGui })
end

local sleeping = false

local function startSleep()
	sleeping = true
	if Laptop.IsOpen() then
		Laptop.Close()
	end
	tween(refs.black, 1.5, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
	refs.sleepTitle.Text = "🌙 " .. L("sleep_title")
	tween(refs.sleepTitle, 1.2, { TextTransparency = 0 }, nil, nil, 1)
	task.spawn(function()
		while sleeping do
			for i, z in ipairs(refs.zzz) do
				z.Position = UDim2.fromScale(0.56 + i * 0.025, 0.2)
				z.TextTransparency = 1
				tween(z, 1.6, { Position = UDim2.fromScale(0.58 + i * 0.03, 0.1 - i * 0.015), TextTransparency = 0.1 }, Enum.EasingStyle.Sine, nil, i * 0.35)
			end
			task.wait(2.6)
			for _, z in ipairs(refs.zzz) do
				tween(z, 0.5, { TextTransparency = 1 })
			end
			task.wait(0.5)
		end
	end)
end

function UI.ShowSummary(r)
	refs.sumTitle.Text = "📒 " .. L("day_summary", { day = r.day })
	Kit.clear(refs.sumRows, { "UIListLayout" })
	local profitColor = r.profit >= 0 and T.green or T.red
	local rows = {
		{ L("revenue"), money(r.revenue), T.text },
		{ L("fb_tip"), money(r.tips), T.dim },
		{ L("expenses"), "−" .. money(r.expenses), T.dim },
		{ L("rent"), "−" .. money(r.rent), T.dim },
		{ L("profit"), money(r.profit), profitColor },
		{ L("stat_served"), string.format("%d  (💯 %d · 😠 %d)", r.served, r.perfect, r.walkouts), T.text },
		{ L("avg_rating"), string.format("%.1f ★", r.avgRating), T.gold },
		{ L("reputation"), string.format("%.1f ★", r.reputation), T.gold },
	}
	for i, row in ipairs(rows) do
		local f = new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = refs.sumRows })
		label({ Size = UDim2.new(0.5, 0, 1, 0), TextSize = 15, TextColor3 = T.dim, Text = row[1], Parent = f })
		local v = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Font = i == 5 and F.black or F.bold, TextSize = i == 5 and 19 or 15, TextColor3 = row[3], Text = row[2], Parent = f })
		v.TextTransparency = 1
		tween(v, 0.4, { TextTransparency = 0 }, nil, nil, 0.3 + i * 0.12)
	end
	local s = refs.summary
	s.Visible = true
	s.Position = UDim2.fromScale(0.5, 0.62)
	tween(s, 0.6, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.58) }, Enum.EasingStyle.Back)
	if not sleeping then
		-- shown without a sleep transition (fallback)
		task.delay(Config.Day.SummarySeconds, function()
			if not sleeping then
				tween(s, 0.4, { GroupTransparency = 1 })
			end
		end)
	end
end

local function wakeUp(day: number)
	sleeping = false
	-- hide summary & sleep texts
	tween(refs.summary, 0.4, { GroupTransparency = 1 })
	tween(refs.sleepTitle, 0.4, { TextTransparency = 1 })
	for _, z in ipairs(refs.zzz) do
		z.TextTransparency = 1
	end
	task.wait(0.5)
	refs.summary.Visible = false
	-- eyelids closed, then blink open
	local top, bottom = refs.lidTop, refs.lidBottom
	top.Visible, bottom.Visible = true, true
	top.Position, bottom.Position = UDim2.fromScale(0, 0.55), UDim2.fromScale(0, 0.45)
	refs.black.BackgroundTransparency = 1
	local blur = new("BlurEffect", { Size = 24, Parent = workspace.CurrentCamera })
	local function lids(openAmount: number, t: number)
		tween(top, t, { Position = UDim2.fromScale(0, 0.55 - openAmount * 0.55) }, Enum.EasingStyle.Sine)
		tween(bottom, t, { Position = UDim2.fromScale(0, 0.45 + openAmount * 0.55) }, Enum.EasingStyle.Sine)
	end
	lids(0.25, 0.9)
	task.wait(1.1)
	lids(0.05, 0.25)
	task.wait(0.35)
	lids(0.6, 0.7)
	task.wait(0.8)
	lids(0.35, 0.3)
	task.wait(0.35)
	lids(1.05, 1.1)
	tween(blur, 2.2, { Size = 0 }, Enum.EasingStyle.Sine)
	refs.wakeTitle.Text = "☀️ " .. L("wake_title", { day = day })
	refs.wakeSub.Text = L("wake_sub")
	tween(refs.wakeTitle, 0.8, { TextTransparency = 0 }, nil, nil, 0.4)
	tween(refs.wakeSub, 0.8, { TextTransparency = 0.1 }, nil, nil, 0.7)
	task.wait(3.2)
	tween(refs.wakeTitle, 0.8, { TextTransparency = 1 })
	tween(refs.wakeSub, 0.8, { TextTransparency = 1 })
	task.wait(1.2)
	top.Visible, bottom.Visible = false, false
	blur:Destroy()
end

---------------------------------------------------------------------------
-- panels → laptop apps
---------------------------------------------------------------------------
function UI.TogglePanel(name: string)
	Laptop.Toggle(name)
end

function UI.SetCutting(active: boolean)
	cutting = active
	updateGoals()
end

function UI.OpenPanel(name: string)
	if name == "laptop" then
		Laptop.Open("pos")
		return
	end
	Laptop.Open(({ upgrades = "upgrades", stock = "supplier", goals = "stats", settings = "settings" })[name])
end

---------------------------------------------------------------------------
-- scaling & entrance animation
---------------------------------------------------------------------------
local function applyScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	refs.scale.Scale = math.clamp(math.min(vp.X / 1500, vp.Y / 860), 0.6, 1.05)
end

local function entrance()
	local items = { { refs.stats, UDim2.fromOffset(-260, 14), UDim2.fromOffset(14, 14) }, { refs.clockPill, UDim2.new(0.5, 0, 0, -60), UDim2.new(0.5, 0, 0, 14) }, { gui:FindFirstChild("Badges"), UDim2.new(1, 260, 0, 14), UDim2.new(1, -14, 0, 14) } }
	for i, e in ipairs(items) do
		local obj = e[1]
		if obj then
			obj.Position = e[2]
			tween(obj, 0.8, { Position = e[3] }, Enum.EasingStyle.Back, nil, 0.15 * i)
		end
	end
end

local lastLang = nil

function UI.Init()
	gui = new("ScreenGui", { Name = "KebapUI", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	refs.scale = new("UIScale", { Parent = gui })
	buildStats()
	buildClock()
	buildBadges()
	buildMeal()
	buildDialogue()
	buildToasts()
	buildFeedback()
	buildGoals()
	buildTutorial()
	buildSleep()
	Laptop.Init()
	Laptop.OnOpenChanged = function(open)
		-- the HUD steps aside while the laptop is open
		gui.Enabled = not open
		UI.OnPanelChanged(open)
	end
	applyScale()
	entrance()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end

	State.Changed:Connect(function(what)
		if what == "player" then
			updateStats()
			updateMeal()
			if State.player and State.player.settings then
				Sound.SetVolumes(State.player.settings.sfx, State.player.settings.ambience)
			end
			if State.lang ~= lastLang then
				lastLang = State.lang
				updateClock()
				updateGoals()
			end
		elseif what == "shop" then
			updateStats()
			updateClock()
			updateGoals()
		elseif what == "tickets" or what == "selection" then
			updateBadges()
			updateMeal()
		end
	end)
	State.Remote("Notify").OnClientEvent:Connect(UI.Toast)
	State.Remote("Feedback").OnClientEvent:Connect(UI.ShowFeedback)
	State.Remote("DaySummary").OnClientEvent:Connect(UI.ShowSummary)
	State.Remote("Dialogue").OnClientEvent:Connect(UI.ShowDialogue)
	State.Remote("DayPhase").OnClientEvent:Connect(function(phase, info)
		if phase == "sleep" then
			startSleep()
		elseif phase == "wake" then
			task.spawn(wakeUp, info and info.day or 1)
		end
	end)

	-- keyboard / gamepad shortcuts open the laptop apps
	local binds = {
		{ "KebapUpgrades", "upgrades", Enum.KeyCode.U, Enum.KeyCode.DPadUp },
		{ "KebapStock", "stock", Enum.KeyCode.L, Enum.KeyCode.DPadLeft },
		{ "KebapGoals", "goals", Enum.KeyCode.G, Enum.KeyCode.DPadRight },
		{ "KebapSettings", "settings", Enum.KeyCode.O, Enum.KeyCode.DPadDown },
	}
	for _, b in ipairs(binds) do
		ContextActionService:BindAction(b[1], function(_, inputState)
			if inputState == Enum.UserInputState.Begin and not GuiService.MenuIsOpen then
				Laptop.Toggle(b[2])
			end
			return Enum.ContextActionResult.Sink
		end, false, b[3], b[4])
	end
	ContextActionService:BindAction("KebapClosePanel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and Laptop.IsOpen() then
			Laptop.Close()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)

	-- live values
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateUrgent()
			if State.player and State.player.location == "grill" then
				updateMeal()
			end
		end
	end)
end

return UI
