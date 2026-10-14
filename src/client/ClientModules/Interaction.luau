-- Client-side ProximityPrompts for stations and customers. Prompts give native keyboard, gamepad and
-- touch support. They only express intent; the server validates distance, state and stock.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local Localization = require(Shared.Localization)
local OrderLogic = require(Shared.OrderLogic)
local Progression = require(Shared.Progression)
local State = require(script.Parent.State)

local Interaction = {}
Interaction.OpenPanel = function(_name: string) end

type Entry = { part: BasePart, prompt: ProximityPrompt, prompt2: ProximityPrompt? }
local stations: { Entry } = {}
local customerPrompts: { [Model]: ProximityPrompt } = {}
local slapPrompts: { [Model]: ProximityPrompt } = {}
Interaction.OnSlap = function(_model: Model) end
Interaction.OnSpit = function(_part: BasePart) end -- opens the cutting mode (MeatCutting)
Interaction.IsCutting = function(): boolean
	return false
end

local function L(key, params)
	return Localization.Get(key, State.lang, params)
end

local function makePrompt(part: BasePart, key: Enum.KeyCode, pad: Enum.KeyCode): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = Config.Prep.PromptDistance
	p.KeyboardKeyCode = key
	p.GamepadKeyCode = pad
	-- custom-drawn prompt (PromptUI) that never captures the mouse in first person
	p.Style = Enum.ProximityPromptStyle.Custom
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	p.ClickablePrompt = false
	p.Parent = part
	return p
end

local function meal()
	return State.player and State.player.meal
end

local function stockText(stockId: string): string
	local n = State.shop and State.shop.stock and State.shop.stock[stockId]
	if n == nil then
		return ""
	end
	return string.format(" (%d)", n)
end

local function donenessText(d: number): string
	if d < Config.Prep.MinCutDoneness then
		return State.lang == "de" and "roh 🔴" or "raw 🔴"
	elseif d > Config.Prep.BurntDoneness then
		return State.lang == "de" and "verbrannt ⚫" or "burnt ⚫"
	elseif d > 1.6 then
		return State.lang == "de" and "knusprig 🟠" or "crispy 🟠"
	end
	return State.lang == "de" and "perfekt 🟢" or "perfect 🟢"
end

-- ingredients only go into the bread you are holding (issue #3)
local function canAdd(): boolean
	local m = meal()
	return m ~= nil and not m.closed and State.player.location == "hand"
end

-- one pair of hands: held bread, carried tray or a box / meat cone
local function handsBusy(): boolean
	local ps = State.player
	local held = ps ~= nil and ((ps.meal ~= nil and ps.location == "hand") or ps.trayAt == "hand")
	return held or game:GetService("Players").LocalPlayer:GetAttribute("Carry") ~= nil
end

local function refreshStation(e: Entry)
	local part, prompt = e.part, e.prompt
	local kind = part:GetAttribute("Station")
	local item = part:GetAttribute("Item")
	local ps = State.player
	if not ps then
		prompt.Enabled = false
		return
	end
	local m = ps.meal
	prompt.HoldDuration = 0
	if kind == "bread" then
		local def = IngredientData.Bread[item]
		prompt.ActionText = L("p_take")
		prompt.ObjectText = def.name[State.lang] .. stockText(def.stock)
		prompt.Enabled = m == nil and not handsBusy()
	elseif kind == "grill" then
		local slot = part:GetAttribute("Slot")
		if ps.location == "grill" and ps.grillSlot == slot then
			local elapsed = (ps.grillElapsed or 0) + (os.clock() - State.grillReceivedAt)
			prompt.ActionText = L("p_toast_out")
			prompt.ObjectText = string.format("%.0fs (%d–%ds)", elapsed, Config.Prep.ToastPerfectMin, Config.Prep.ToastPerfectMax)
			prompt.Enabled = not handsBusy()
		else
			prompt.ActionText = L("p_toast_in")
			prompt.ObjectText = State.lang == "de" and "Kontaktgrill" or "Contact grill"
			prompt.Enabled = m ~= nil and not m.closed and m.bread ~= "box" and ps.location == "hand"
		end
	elseif kind == "spit" then
		local spitModel = part.Parent
		local d = spitModel and spitModel:GetAttribute("Doneness") or 0
		local def = IngredientData.Meat[item]
		prompt.ActionText = L("p_cut")
		prompt.ObjectText = def.name[State.lang] .. " · " .. donenessText(d) .. stockText(def.stock)
		prompt.Enabled = canAdd() and not Interaction.IsCutting()
	elseif kind == "spit_heat" then
		local spitModel = part.Parent
		local heat = spitModel and spitModel:GetAttribute("Heat") or "low"
		prompt.ActionText = L("p_heat")
		prompt.ObjectText = (State.lang == "de" and "Hitze: " or "Heat: ") .. (heat == "high" and "🔥🔥" or "🔥")
		prompt.Enabled = true
	elseif kind == "veg" or kind == "sauce" or kind == "cheese" then
		local def = IngredientData.Find(item)
		local count = 0
		if m then
			if kind == "veg" then
				count = m.veg[item] or 0
			elseif kind == "sauce" then
				count = m.sauces[item] or 0
			else
				count = m.cheese
			end
		end
		prompt.ActionText = L("p_add") .. (count > 0 and string.format(" (%d→%d)", count, count + 1) or "")
		prompt.ObjectText = (def and def.name[State.lang] or item) .. stockText(def and def.stock or item)
		prompt.Enabled = canAdd()
	elseif kind == "board" then
		-- [E] main action, [R] second one; a board someone else works at stays closed
		local i = part:GetAttribute("Board")
		local user = part:GetAttribute("User")
		local p2 = e.prompt2 :: ProximityPrompt
		local function set(p: ProximityPrompt, action: string?, text: string?, obj: string?)
			p.Enabled = action ~= nil
			if action then
				p.ActionText = text or ""
				p.ObjectText = obj or ""
				p:SetAttribute("Action", action)
			end
		end
		local mine = m ~= nil and ps.location == "board" and ps.board == i
		local free = user == nil or user == game:GetService("Players").LocalPlayer.UserId
		if free and mine and m and not m.closed then
			local verb = m.bread == "duerum" and "close_wrap" or (m.bread == "box" and "close_lid" or "close_close")
			set(prompt, "close", L(verb), L("meal_title"))
			set(p2, not handsBusy() and "pickup" or nil, L("p_pickup_meal"), "✋")
		elseif free and mine then
			set(prompt, "pack_takeaway", L("p_pack_takeaway"), "🛍️")
			set(p2, "pack_plate", L("p_pack_plate"), "🍽️")
		elseif free and m and ps.location == "hand" then
			set(prompt, "place", L("p_place_meal"), L("meal_title"))
			set(p2, nil)
		elseif free and ps.trayAt == "hand" then
			set(prompt, "tray_down", L("p_tray_down"), "🍽️")
			set(p2, nil)
		elseif free and ps.trayAt == i and not handsBusy() then
			set(prompt, "tray_up", L("p_tray_up"), "🍽️")
			set(p2, nil)
		else
			set(prompt, nil)
			set(p2, nil)
		end
	elseif kind == "drink" then
		local def = IngredientData.Drinks[item]
		prompt.ActionText = L("p_drink")
		prompt.ObjectText = def.name[State.lang] .. stockText(def.stock)
		-- onto the tray in your hands (or a new one)
		local heldMeal = m ~= nil and ps.location == "hand"
		prompt.Enabled = #(ps.tray or {}) < (ps.trayCap or 2) and not heldMeal and type(ps.trayAt) ~= "number"
	elseif kind == "trash" then
		-- only what you carry to the bin
		local heldMeal = m ~= nil and ps.location == "hand"
		prompt.ActionText = L("p_discard")
		prompt.ObjectText = heldMeal and L("meal_title") or L("tray")
		prompt.Enabled = heldMeal or (ps.trayAt == "hand" and #(ps.tray or {}) > 0)
	elseif kind == "register" then
		local ordering = false
		for _, c in ipairs(CollectionService:GetTagged("Customer")) do
			if c:GetAttribute("State") == "Ordering" then
				ordering = true
			end
		end
		prompt.ActionText = L("p_take_order")
		prompt.ObjectText = State.lang == "de" and "Kassa" or "Register"
		prompt.Enabled = ordering
	elseif kind == "laptop" then
		prompt.ActionText = L("p_laptop")
		prompt.ObjectText = "💻"
		prompt.Enabled = true
	elseif kind == "shop_lock" then
		local after = State.shop and State.shop.phase == "after_hours"
		prompt.ActionText = after and L("p_lock") or L("p_lock_early")
		prompt.ObjectText = "🔑"
		prompt.HoldDuration = after and 1 or 0
		prompt.Enabled = not (State.shop and State.shop.phase == "sleeping")
	elseif kind == "stock_terminal" then
		prompt.ActionText = L("p_stock")
		prompt.ObjectText = "📦"
		prompt.Enabled = true
	elseif kind == "upgrade_board" then
		prompt.ActionText = L("p_upgrades")
		prompt.ObjectText = "📋"
		prompt.Enabled = true
	elseif kind == "crate" then
		local u = Progression.ById[item]
		prompt.ActionText = L("p_unpack")
		prompt.ObjectText = u and ("📦 " .. u.name[State.lang]) or "📦"
		prompt.HoldDuration = 1.2
		prompt.Enabled = true
	elseif part:GetAttribute("PromptDe") then
		-- generic stations (cleaning, warming pan, delivery shelf …): the server describes the prompt
		local de = part:GetAttribute("PromptDe")
		prompt.ActionText = State.lang == "de" and de or (part:GetAttribute("PromptEn") or de)
		prompt.ObjectText = part:GetAttribute("PromptObj") or ""
		prompt.HoldDuration = part:GetAttribute("PromptHold") or 0
		prompt.Enabled = part:GetAttribute("PromptOn") ~= false
	end
	-- carrying a box: only drop spots and the matching kitchen station react
	local carry = game:GetService("Players").LocalPlayer:GetAttribute("Carry")
	if kind == "logi_shelf" or kind == "logi_cold" then
		prompt.Enabled = carry ~= nil
	elseif kind == "logi_box" then
		prompt.Enabled = carry == nil
	elseif kind == "spit_unload" then
		prompt.Enabled = carry == nil and part:GetAttribute("PromptOn") ~= false
	elseif carry and (kind == "bread" or kind == "veg" or kind == "cheese" or kind == "sauce" or kind == "drink") then
		local sid = kind == "veg" and item or kind == "cheese" and "cheese" or (kind == "bread" and item == "box") and "box" or (kind == "bread" and "bread_" or kind == "sauce" and "sauce_" or "drink_") .. tostring(item)
		prompt.Enabled = sid == carry
		prompt.ActionText = State.lang == "de" and "Auffüllen" or "Restock"
		prompt.ObjectText = "📦"
		prompt.HoldDuration = 0.4
	end
end

local function addStation(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	for _, e in ipairs(stations) do
		if e.part == part then
			return
		end
	end
	local kind = part:GetAttribute("Station")
	-- the heat knob sits right next to the carving spot: its own key so [E] always means "cut"
	local altKey = kind == "spit_heat" or part:GetAttribute("PromptKey") == "R"
	local prompt = altKey and makePrompt(part, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
		or (part:GetAttribute("PromptKey") == "F" and makePrompt(part, Enum.KeyCode.F, Enum.KeyCode.ButtonL1))
		or makePrompt(part, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	local e: Entry = { part = part, prompt = prompt }
	if part:GetAttribute("PromptDe") then
		prompt.MaxActivationDistance = part:GetAttribute("PromptDist") or prompt.MaxActivationDistance
		part.AttributeChanged:Connect(function()
			refreshStation(e)
		end)
	end
	if kind == "board" then
		e.prompt2 = makePrompt(part, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
		;(e.prompt2 :: ProximityPrompt).UIOffset = Vector2.new(0, 80)
		part:GetAttributeChangedSignal("User"):Connect(function()
			refreshStation(e)
		end)
	end
	if kind == "spit" then
		prompt.MaxActivationDistance = Config.Prep.PromptDistance + 1
	elseif kind == "stock_terminal" or kind == "upgrade_board" or kind == "register" or kind == "laptop" or kind == "shop_lock" or kind == "crate" then
		prompt.MaxActivationDistance = 8
	end
	local function fire(p: ProximityPrompt)
		local action = p:GetAttribute("Action")
		if kind == "stock_terminal" then
			Interaction.OpenPanel("stock")
			return
		elseif kind == "upgrade_board" then
			Interaction.OpenPanel("upgrades")
			return
		elseif kind == "laptop" then
			Interaction.OpenPanel("laptop")
			return
		elseif kind == "spit" then
			Interaction.OnSpit(part)
			return
		end
		State.Remote("Interact"):FireServer(part, action)
	end
	prompt.Triggered:Connect(function()
		fire(prompt)
	end)
	if e.prompt2 then
		local p2 = e.prompt2 :: ProximityPrompt
		p2.Triggered:Connect(function()
			fire(p2)
		end)
	end
	table.insert(stations, e)
	refreshStation(e)
end

---------------------------------------------------------------------------
-- Customers
---------------------------------------------------------------------------
local function refreshCustomer(model: Model, prompt: ProximityPrompt)
	local st = model:GetAttribute("State")
	local ps = State.player
	local name = model:GetAttribute("CustomerName") or ""
	prompt.ObjectText = name
	if st == "Ordering" then
		prompt.ActionText = L("p_take_order")
		prompt:SetAttribute("Action", "take")
		prompt.Enabled = true
	elseif st == "WaitingForFood" then
		prompt.ActionText = L("p_serve")
		prompt:SetAttribute("Action", "serve")
		prompt.Enabled = ps ~= nil and #(ps.tray or {}) > 0
	else
		prompt.Enabled = false
	end
end

local function addCustomer(model: Instance)
	if not model:IsA("Model") or customerPrompts[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = Config.Customers.InteractDistance - 1
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ClickablePrompt = false
	prompt.UIOffset = Vector2.new(0, -40)
	prompt.Parent = root
	customerPrompts[model] = prompt
	prompt.Triggered:Connect(function()
		State.Remote("CustomerAction"):FireServer(model, prompt:GetAttribute("Action"))
	end)
	model:GetAttributeChangedSignal("State"):Connect(function()
		refreshCustomer(model, prompt)
	end)
	refreshCustomer(model, prompt)
	-- "Backpfeife" for aggressive customers
	local slap = Instance.new("ProximityPrompt")
	slap.Name = "SlapPrompt"
	slap.RequiresLineOfSight = false
	slap.MaxActivationDistance = Config.Aggro.SlapDistance - 1
	slap.KeyboardKeyCode = Enum.KeyCode.Q
	slap.GamepadKeyCode = Enum.KeyCode.ButtonR1
	slap.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	slap.Style = Enum.ProximityPromptStyle.Custom
	slap.ClickablePrompt = false
	slap.UIOffset = Vector2.new(0, 80)
	slap.ActionText = L("p_slap")
	slap.Enabled = false
	slap.Parent = root
	slapPrompts[model] = slap
	local function refreshSlap()
		slap.ActionText = L("p_slap")
		local angry = model:GetAttribute("Aggressive") == true
		slap.ObjectText = (angry and "😡 " or "") .. tostring(model:GetAttribute("CustomerName") or "")
		local st = model:GetAttribute("State")
		-- every guest can be slapped (peaceful ones cost reputation – see Server/CustomerService)
		slap.Enabled = model:GetAttribute("Slapped") ~= true and st ~= nil
	end
	model:GetAttributeChangedSignal("Aggressive"):Connect(refreshSlap)
	model:GetAttributeChangedSignal("Slapped"):Connect(refreshSlap)
	model:GetAttributeChangedSignal("State"):Connect(refreshSlap)
	refreshSlap()
	slap.Triggered:Connect(function()
		slap.Enabled = false
		Interaction.OnSlap(model)
		State.Remote("CustomerAction"):FireServer(model, "slap")
	end)
end

local function removeCustomer(model: Instance)
	local p = customerPrompts[model :: Model]
	if p then
		p:Destroy()
		customerPrompts[model :: Model] = nil
	end
	local sp = slapPrompts[model :: Model]
	if sp then
		sp:Destroy()
		slapPrompts[model :: Model] = nil
	end
end

function Interaction.RefreshAll()
	for _, e in ipairs(stations) do
		if e.part.Parent then
			refreshStation(e)
		end
	end
	for m, p in pairs(customerPrompts) do
		refreshCustomer(m, p)
	end
end

function Interaction.Init()
	CollectionService:GetInstanceAddedSignal("Station"):Connect(addStation)
	-- equipment that gets packed away / crates that are unpacked
	CollectionService:GetInstanceRemovedSignal("Station"):Connect(function(part)
		for i = #stations, 1, -1 do
			local e = stations[i]
			if e.part == part then
				e.prompt:Destroy()
				if e.prompt2 then
					e.prompt2:Destroy()
				end
				table.remove(stations, i)
			end
		end
	end)
	for _, p in ipairs(CollectionService:GetTagged("Station")) do
		addStation(p)
	end
	CollectionService:GetInstanceAddedSignal("Customer"):Connect(function(m)
		task.spawn(addCustomer, m)
	end)
	CollectionService:GetInstanceRemovedSignal("Customer"):Connect(removeCustomer)
	for _, m in ipairs(CollectionService:GetTagged("Customer")) do
		task.spawn(addCustomer, m)
	end
	-- coalesce bursts of state updates into one refresh per frame
	local queued = false
	local function queueRefresh()
		if not queued then
			queued = true
			task.defer(function()
				queued = false
				Interaction.RefreshAll()
			end)
		end
	end
	State.Changed:Connect(function(what)
		if what == "player" or what == "shop" then
			queueRefresh()
		end
	end)
	-- picking up / putting down a box or meat cone frees or fills the hands
	game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("Carry"):Connect(queueRefresh)
	-- periodic refresh only for live values (spit doneness, grill timer, register) close to the player
	local LIVE = { spit = true, grill = true, register = true }
	task.spawn(function()
		while true do
			task.wait(0.5)
			local char = game:GetService("Players").LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				for _, e in ipairs(stations) do
					if LIVE[e.part:GetAttribute("Station")] and e.part.Parent and (e.part.Position - root.Position).Magnitude < 20 then
						refreshStation(e)
					end
				end
			end
		end
	end)
	local _ = OrderLogic
end

return Interaction
