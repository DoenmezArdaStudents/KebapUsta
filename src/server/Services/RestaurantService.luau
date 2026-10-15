-- The shared restaurant: ownership, ingredient stock & deliveries, reputation, daily stats & goals,
-- menu boards, register screen, automatic door and upgrade visuals in the world.
-- Multiplayer model: the first player is the owner – the restaurant (stock, upgrades, reputation) is
-- loaded from the owner's save. Other players join as staff: they earn their own money/XP but cannot
-- buy upgrades for someone else's shop. If the owner leaves, the next player takes over.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local MenuData = require(Shared.MenuData)
local Progression = require(Shared.Progression)
local Localization = require(Shared.Localization)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local RestaurantService = {}

local owner: Player? = nil
local deliveries: { { id: string, amount: number, arrive: number, by: Player? } } = {}
local hidden = ServerStorage:FindFirstChild("HiddenWorld") or Instance.new("Folder")
hidden.Name = "HiddenWorld"
hidden.Parent = ServerStorage
local shopPushQueued = false
local ownerChanged = Instance.new("BindableEvent")
RestaurantService.OwnerChanged = ownerChanged.Event

RestaurantService.Clock = Config.Day.StartHour
RestaurantService.Open = false
RestaurantService.PeriodKey = "period_morning"
RestaurantService.TutorialActive = false
RestaurantService.Phase = "open"
-- hooks filled by GoalService
RestaurantService.GoalProvider = nil :: (() -> any)?
RestaurantService.RecordHook = nil :: ((string, number) -> ())?
RestaurantService.RestockHook = nil :: ((Player, string) -> ())?
RestaurantService.BizProvider = nil :: (() -> any)?
-- cold room (Server/ColdRoomService): meat deliveries are stored there instead of the spit
RestaurantService.DeliverHook = nil :: ((any) -> boolean)?
RestaurantService.ColdAmount = nil :: ((string) -> number)?

local function newDayStats()
	return {
		revenue = 0,
		tips = 0,
		expenses = 0,
		served = 0,
		perfect = 0,
		walkouts = 0,
		ratingSum = 0,
		ratingCount = 0,
		duerum = 0,
		drinks = 0,
		earnedGoal = 0,
	}
end
RestaurantService.DayStats = newDayStats()
RestaurantService.Goals = {}

---------------------------------------------------------------------------
-- Ownership
---------------------------------------------------------------------------
function RestaurantService.GetOwner(): Player?
	return owner
end

function RestaurantService.IsOwner(player: Player): boolean
	return owner == player
end

local function ownerData()
	return owner and DataService.Get(owner)
end

function RestaurantService.GetUpgrades(): { [string]: number }
	local d = ownerData()
	return d and d.upgrades or {}
end

function RestaurantService.UpgradeValue(id: string)
	return Config.UpgradeValue(RestaurantService.GetUpgrades(), id)
end

-- the owner's unlock table (Shared/Progression): id -> "delivered" | "owned"
function RestaurantService.GetUnlocks(): { [string]: string }
	local d = ownerData()
	return d and d.unlocks or {}
end

function RestaurantService.Owns(id: string): boolean
	return Progression.Owned(RestaurantService.GetUnlocks(), id)
end

-- what customers may order right now (unlocked, installed and stocked at least once)
function RestaurantService.Available()
	local d = ownerData()
	return Progression.Available(d and d.unlocks or {}, d and d.stocked or {})
end

function RestaurantService.UnlockedMenus(): { [string]: boolean? }
	return Progression.Available(RestaurantService.GetUnlocks()).menus
end

function RestaurantService.KnifeId(): string
	return Progression.Knife(RestaurantService.GetUnlocks())
end

function RestaurantService.GetReputation(): number
	local d = ownerData()
	return d and d.reputation or Config.Economy.ReputationStart
end

function RestaurantService.GetDay(): number
	local d = ownerData()
	return d and d.day or 1
end

---------------------------------------------------------------------------
-- Stock
---------------------------------------------------------------------------
function RestaurantService.Capacity(stockId: string): number
	local def = IngredientData.Stock[stockId]
	local base = def and def.meat and Config.Stock.MeatCapacity or Config.Stock.BaseCapacity
	return math.floor(base * RestaurantService.UpgradeValue("storage"))
end

function RestaurantService.GetStock(stockId: string): number
	local d = ownerData()
	return d and d.stock[stockId] or 0
end

function RestaurantService.HasStock(stockId: string, n: number?): boolean
	return RestaurantService.GetStock(stockId) >= (n or 1)
end

function RestaurantService.UseStock(stockId: string, n: number?): boolean
	local d = ownerData()
	n = n or 1
	if not d or (d.stock[stockId] or 0) < n then
		return false
	end
	d.stock[stockId] -= n
	DataService.MarkDirty(owner :: Player)
	RestaurantService.PushShop()
	return true
end

function RestaurantService.AddStock(stockId: string, n: number)
	local d = ownerData()
	if not d then
		return
	end
	d.stock[stockId] = math.min(RestaurantService.Capacity(stockId), (d.stock[stockId] or 0) + n)
	if n > 0 and d.stocked and not d.stocked[stockId] then
		-- first delivery of a newly installed ingredient: customers start ordering it now
		d.stocked[stockId] = true
		Net.NotifyAll("n_first_stock", { item = IngredientData.Stock[stockId].name }, "success")
	end
	DataService.MarkDirty(owner :: Player)
	RestaurantService.PushShop()
end

local function inTransit(stockId: string): number
	local n = 0
	for _, d in ipairs(deliveries) do
		if d.id == stockId then
			n += d.amount
		end
	end
	return n
end

function RestaurantService.Restock(player: Player, stockId: any)
	if type(stockId) ~= "string" then
		return { ok = false }
	end
	local def = IngredientData.Stock[stockId]
	if not def or not owner then
		return { ok = false }
	end
	if not Progression.StockUnlocked(RestaurantService.GetUnlocks(), stockId) then
		Net.Notify(player, "n_not_unlocked", nil, "warn")
		return { ok = false, msg = "n_not_unlocked" }
	end
	local cap = RestaurantService.Capacity(stockId)
	local current = RestaurantService.GetStock(stockId) + inTransit(stockId) + (RestaurantService.ColdAmount and RestaurantService.ColdAmount(stockId) or 0)
	local amount = math.min(def.pack, cap - current)
	if RestaurantService.OrderGate then
		local a = RestaurantService.OrderGate(stockId)
		if not a then
			Net.Notify(player, "📦 Kein Platz mehr im Lager", nil, "warn")
			return { ok = false, msg = "n_storage_full" }
		end
		amount = a
	end
	if amount <= 0 then
		Net.Notify(player, "n_storage_full", nil, "warn")
		return { ok = false, msg = "n_storage_full" }
	end
	local cost = math.floor(def.cost * amount * 100 + 0.5) / 100
	if not EconomyService.Spend(player, cost) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return { ok = false, msg = "n_not_enough_cash" }
	end
	RestaurantService.DayStats.expenses += cost
	local delay = RestaurantService.UpgradeValue("delivery")
	if RestaurantService.OrderHook then
		RestaurantService.OrderHook(stockId, amount, delay, player)
	else
		table.insert(deliveries, { id = stockId, amount = amount, arrive = os.clock() + delay, by = player })
	end
	Net.Notify(player, "n_restock_ordered", { item = def.name, s = delay }, "info")
	if RestaurantService.RestockHook then
		RestaurantService.RestockHook(player, stockId)
	end
	Net.Sound(player, "register")
	RestaurantService.PushShop()
	return { ok = true }
end

---------------------------------------------------------------------------
-- Reputation & day stats
---------------------------------------------------------------------------
function RestaurantService.Rate(stars: number, weight: number?)
	local d = ownerData()
	if not d then
		return
	end
	local w = Config.Economy.ReputationWeight * (weight or 1)
	d.reputation = math.clamp(d.reputation + (stars - d.reputation) * w, 1, 5)
	RestaurantService.DayStats.ratingSum += stars
	RestaurantService.DayStats.ratingCount += 1
	DataService.MarkDirty(owner :: Player)
	RestaurantService.PushShop()
end

function RestaurantService.Record(stat: string, amount: number?)
	local s = RestaurantService.DayStats
	s[stat] = (s[stat] or 0) + (amount or 1)
	if RestaurantService.RecordHook and (amount or 1) > 0 then
		RestaurantService.RecordHook(stat, amount or 1)
	end
	RestaurantService.CheckGoals()
	RestaurantService.PushShop()
end

---------------------------------------------------------------------------
-- Daily goals
---------------------------------------------------------------------------
local GOAL_TYPES = {
	{ kind = "serve", stat = "served", min = 8, max = 14, reward = 40 },
	{ kind = "perfect", stat = "perfect", min = 3, max = 6, reward = 50 },
	{ kind = "earn", stat = "revenue", min = 60, max = 140, reward = 45, money = true },
	{ kind = "duerum", stat = "duerum", min = 3, max = 6, reward = 35, needs = "duerum" },
	{ kind = "drinks", stat = "drinks", min = 3, max = 6, reward = 30, needs = "drinks" },
	{ kind = "nowalk", stat = "walkouts", min = 1, max = 3, reward = 50, atMost = true },
}

function RestaurantService.RollGoals()
	local rng = Random.new()
	local av = RestaurantService.Available()
	local pool = {}
	for _, g in ipairs(GOAL_TYPES) do
		if g.needs == nil or (g.needs == "duerum" and av.menus.duerum) or (g.needs == "drinks" and av.drinks) then
			table.insert(pool, g)
		end
	end
	local goals = {}
	for _ = 1, math.min(3, #pool) do
		local g = table.remove(pool, rng:NextInteger(1, #pool))
		local target = rng:NextInteger(g.min, g.max)
		if g.money then
			target = math.floor(target / 10) * 10
		end
		table.insert(goals, { kind = g.kind, stat = g.stat, target = target, reward = g.reward, done = false, atMost = g.atMost })
	end
	RestaurantService.Goals = goals
end

local function rewardAll(amount: number)
	for _, p in ipairs(Players:GetPlayers()) do
		EconomyService.AddCash(p, amount, true)
		Net.Notify(p, "n_goal_done", { reward = Localization.Money(amount) }, "goal")
		Net.Sound(p, "success")
	end
end

function RestaurantService.CheckGoals(final: boolean?)
	for _, g in ipairs(RestaurantService.Goals) do
		if not g.done then
			local v = RestaurantService.DayStats[g.stat] or 0
			if g.atMost then
				if final and v <= g.target then
					g.done = true
					rewardAll(g.reward)
				end
			elseif v >= g.target then
				g.done = true
				rewardAll(g.reward)
			end
		end
	end
end

function RestaurantService.ResetDay()
	RestaurantService.DayStats = newDayStats()
	RestaurantService.RollGoals()
	RestaurantService.PushShop()
end

---------------------------------------------------------------------------
-- World visuals
---------------------------------------------------------------------------
local function restaurant()
	return workspace:FindFirstChild("Restaurant")
end

-- move a model between the world and hidden storage
local function setVisible(model: Instance?, visible: boolean, parentIfVisible: Instance)
	if not model then
		return
	end
	if visible and model.Parent ~= parentIfVisible then
		model.Parent = parentIfVisible
	elseif not visible and model.Parent ~= hidden then
		model.Parent = hidden
	end
end

local tracked: { [string]: { model: Instance, parent: Instance } } = {}
local function track(key: string, model: Instance?)
	if model and not tracked[key] then
		tracked[key] = { model = model, parent = model.Parent :: Instance }
	end
	return tracked[key]
end

-- other services add their own upgrade visuals here (BackyardService, WasteService …)
RestaurantService.WorldUpgradeHooks = {} :: { ({ [string]: number }) -> () }

function RestaurantService.ApplyWorldUpgrades()
	local r = restaurant()
	if not r then
		return
	end
	local u = RestaurantService.GetUpgrades()
	local extra = r:FindFirstChild("ExtraTables")
	if extra then
		for _, t in ipairs({ "Table5", "Table6" }) do
			track("tbl_" .. t, extra:FindFirstChild(t))
		end
	end
	for _, t in ipairs({ "Table5", "Table6" }) do
		local tr = tracked["tbl_" .. t]
		if tr then
			local tier = tr.model:GetAttribute("Tier") or 1
			setVisible(tr.model, (u.tables or 0) >= tier, tr.parent)
		end
	end
	local decor = r:FindFirstChild("DecorUpgrade")
	if decor then
		track("decor1", decor:FindFirstChild("Tier1"))
		track("decor2", decor:FindFirstChild("Tier2"))
	end
	for i = 1, 2 do
		local tr = tracked["decor" .. i]
		if tr then
			setVisible(tr.model, (u.decor or 0) >= i, tr.parent)
		end
	end
	local lounge = r:FindFirstChild("Lounge")
	if lounge then
		track("loungeBuilt", lounge:FindFirstChild("Built"))
		track("loungeOff", lounge:FindFirstChild("Construction"))
	end
	local built = (u.lounge or 0) >= 1
	if tracked.loungeBuilt then
		setVisible(tracked.loungeBuilt.model, built, tracked.loungeBuilt.parent)
	end
	if tracked.loungeOff then
		setVisible(tracked.loungeOff.model, not built, tracked.loungeOff.parent)
	end
	for _, hook in ipairs(RestaurantService.WorldUpgradeHooks) do
		local ok, err = pcall(hook, u)
		if not ok then
			warn("[RestaurantService] world upgrade hook:", err)
		end
	end
	RestaurantService.UpdateBoards()
end

local function boardGui(part: BasePart)
	local sg = part:FindFirstChild("BoardGui") :: SurfaceGui?
	if sg then
		sg:ClearAllChildren()
	else
		sg = Instance.new("SurfaceGui")
		sg.Name = "BoardGui"
		sg.Face = Enum.NormalId.Back -- boards hang on the back wall and face into the shop (+Z)
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 50
		sg.LightInfluence = 0
		sg.Brightness = 1.2
		sg.Parent = part
	end
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
	frame.Parent = sg
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = frame
	return sg :: SurfaceGui, frame
end

local function boardText(parent, text, size, color, font, order)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, size)
	t.Text = text
	t.TextColor3 = color
	t.Font = font or Enum.Font.GothamBold
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.LayoutOrder = order or 0
	t.Parent = parent
	return t
end

function RestaurantService.UpdateBoards()
	local r = restaurant()
	if not r then
		return
	end
	local premium = RestaurantService.UpgradeValue("premium")
	local menuBoard = r:FindFirstChild("MenuBoard") :: BasePart?
	if menuBoard then
		local _, frame = boardGui(menuBoard)
		local title = boardText(frame, "🔥 KEBAP HAUS · SPEISEKARTE", 34, Color3.fromRGB(240, 190, 70), Enum.Font.GothamBlack)
		title.Size = UDim2.new(1, 0, 0, 34)
		local list = Instance.new("Frame")
		list.BackgroundTransparency = 1
		list.Position = UDim2.new(0, 0, 0, 40)
		list.Size = UDim2.new(1, 0, 1, -40)
		list.Parent = frame
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0.25, -12, 1, -10)
		grid.CellPadding = UDim2.new(0, 12, 0, 0)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = list
		local unlocked = RestaurantService.Available().menus
		for i, id in ipairs(MenuData.ItemOrder) do
			local def = MenuData.Items[id]
			local cell = Instance.new("Frame")
			cell.LayoutOrder = i
			cell.BackgroundColor3 = unlocked[id] and Color3.fromRGB(60, 30, 24) or Color3.fromRGB(40, 40, 40)
			cell.Parent = list
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 10)
			c.Parent = cell
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Size = UDim2.new(1, -10, 0.42, 0)
			name.Position = UDim2.new(0, 5, 0.04, 0)
			name.TextScaled = true
			name.Font = Enum.Font.GothamBlack
			name.TextColor3 = Color3.new(1, 1, 1)
			name.Text = def.icon .. " " .. string.upper(def.name.de)
			name.Parent = cell
			local price = name:Clone()
			price.Position = UDim2.new(0, 5, 0.5, 0)
			price.Size = UDim2.new(1, -10, 0.4, 0)
			price.TextColor3 = unlocked[id] and Color3.fromRGB(240, 190, 70) or Color3.fromRGB(150, 150, 150)
			local u = def.unlock and Progression.ById[def.unlock]
			price.Text = unlocked[id] and Localization.Money(def.price * premium) or ("🔒 LEVEL " .. (u and u.level or "?"))
			price.Parent = cell
		end
	end
	local priceBoard = r:FindFirstChild("PriceBoard") :: BasePart?
	if priceBoard then
		local _, frame = boardGui(priceBoard)
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 2)
		layout.Parent = frame
		local av = RestaurantService.Available()
		boardText(frame, "🥤 GETRÄNKE", 26, Color3.fromRGB(240, 190, 70), Enum.Font.GothamBlack, 0)
		local order = 1
		if av.drinks then
			for _, d in ipairs(IngredientData.DrinkOrder) do
				local def = IngredientData.Drinks[d]
				boardText(frame, string.format("%s %s  ·  %s", def.icon, def.name.de, Localization.Money(def.price * premium)), 18, Color3.new(1, 1, 1), Enum.Font.GothamMedium, order)
				order += 1
			end
		else
			boardText(frame, "🔒 Getränke-Kühlschrank ab Level " .. Progression.ById.drinks.level, 16, Color3.fromRGB(150, 150, 150), Enum.Font.GothamMedium, order)
			order += 1
		end
		boardText(frame, "➕ EXTRAS", 22, Color3.fromRGB(240, 190, 70), Enum.Font.GothamBlack, order)
		order += 1
		for _, e in ipairs(MenuData.ExtrasBoard) do
			if e.key ~= "CheesePrice" or av.cheese then
				boardText(frame, string.format("%s  ·  +%s", e.de, Localization.Money(Config.Economy[e.key] * premium)), 16, Color3.new(1, 1, 1), Enum.Font.GothamMedium, order)
				order += 1
			end
		end
	end
end

-- register display: shows the latest order total or payment
function RestaurantService.RegisterDisplay(line1: string, line2: string?, color: Color3?)
	local r = restaurant()
	local screen = r and r:FindFirstChild("RegisterScreen") :: BasePart?
	if not screen then
		return
	end
	local sg = screen:FindFirstChild("RegGui") :: SurfaceGui?
	local label: TextLabel
	if not sg then
		local newSg = Instance.new("SurfaceGui")
		newSg.Name = "RegGui"
		newSg.Face = Enum.NormalId.Back
		newSg.PixelsPerStud = 60
		newSg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		newSg.LightInfluence = 0
		newSg.Parent = screen
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = Color3.fromRGB(10, 30, 20)
		t.TextScaled = true
		t.Font = Enum.Font.Code
		t.RichText = true
		t.Parent = newSg
		local front = newSg:Clone()
		front.Face = Enum.NormalId.Front
		front.Name = "RegGuiFront"
		front.Parent = screen
		sg = newSg
	end
	for _, g in ipairs({ screen:FindFirstChild("RegGui"), screen:FindFirstChild("RegGuiFront") }) do
		if g then
			label = g:FindFirstChild("Text") :: TextLabel
			label.Text = line1 .. (line2 and ("\n" .. line2) or "")
			label.TextColor3 = color or Color3.fromRGB(120, 255, 160)
		end
	end
end

-- automatic sliding door (opens for any character nearby)
local function runDoor()
	local r = restaurant()
	local door = r and r:FindFirstChild("Door")
	if not door then
		return
	end
	local left = door:FindFirstChild("DoorLeft") :: BasePart
	local right = door:FindFirstChild("DoorRight") :: BasePart
	if not left or not right then
		return
	end
	local isOpen = false
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- everything relative to the door's own placement, so moving the restaurant model is safe
	local closedCF = { [left] = left.CFrame, [right] = right.CFrame }
	local doorPos = (left.Position + right.Position) / 2
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	while true do
		task.wait(0.2)
		local near = false
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(list, p.Character)
			end
		end
		local npcs = workspace:FindFirstChild("Customers")
		if npcs then
			table.insert(list, npcs)
		end
		local peds = workspace:FindFirstChild("Pedestrians")
		if peds then
			table.insert(list, peds)
		end
		overlap.FilterDescendantsInstances = list
		local parts = workspace:GetPartBoundsInBox(CFrame.new(doorPos), Vector3.new(8, 8, 9), overlap)
		near = #parts > 0
		if near ~= isOpen then
			isOpen = near
			for _, d in ipairs({ left, right }) do
				local slide = (d:GetAttribute("OpenX") or 0) - (d:GetAttribute("ClosedX") or 0)
				local target = near and (closedCF[d] + Vector3.new(slide, 0, 0)) or closedCF[d]
				TweenService:Create(d, info, { CFrame = target }):Play()
				d.CanCollide = not near
			end
			if near then
				Net.Sound(nil, "doorbell", doorPos)
			end
		end
	end
end

function RestaurantService.SetOpenSign(open: boolean)
	local r = restaurant()
	-- key switch LED next to the door: green = open, amber blinking handled by clients via phase
	local led = r and r:FindFirstChild("LockLed", true) :: BasePart?
	if led then
		led.Color = open and Color3.fromRGB(60, 220, 90) or Color3.fromRGB(255, 170, 40)
	end
	local sign = r and r:FindFirstChild("OpenSign")
	if sign then
		local sg = sign:FindFirstChildOfClass("SurfaceGui")
		local t = sg and sg:FindFirstChildOfClass("TextLabel")
		if t then
			t.Text = open and "GEÖFFNET" or "GESCHLOSSEN"
			t.TextColor3 = open and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(120, 120, 120)
		end
	end
end

---------------------------------------------------------------------------
-- Shop state sync
---------------------------------------------------------------------------
function RestaurantService.BuildShopState()
	local stock = {}
	local transit = {}
	local caps = {}
	for id in pairs(IngredientData.Stock) do
		stock[id] = RestaurantService.GetStock(id)
		transit[id] = inTransit(id)
		caps[id] = RestaurantService.Capacity(id)
	end
	return {
		owner = owner and owner.UserId or 0,
		ownerName = owner and owner.DisplayName or "",
		day = RestaurantService.GetDay(),
		clock = RestaurantService.Clock,
		open = RestaurantService.Open,
		period = RestaurantService.PeriodKey,
		reputation = RestaurantService.GetReputation(),
		stock = stock,
		transit = transit,
		caps = caps,
		upgrades = RestaurantService.GetUpgrades(),
		unlocked = RestaurantService.UnlockedMenus(),
		dayStats = RestaurantService.DayStats,
		goals = RestaurantService.Goals,
		premium = RestaurantService.UpgradeValue("premium"),
		tutorial = RestaurantService.TutorialActive,
		unlocks = RestaurantService.GetUnlocks(),
		available = RestaurantService.Available(),
		knife = RestaurantService.KnifeId(),
		nextGoals = RestaurantService.GoalProvider and RestaurantService.GoalProvider() or nil,
		biz = RestaurantService.BizProvider and RestaurantService.BizProvider() or nil,
		phase = RestaurantService.Phase, -- "open" | "after_hours" | "sleeping"
	}
end

function RestaurantService.PushShop(player: Player?)
	if player then
		Net.Fire("ShopState", player, RestaurantService.BuildShopState())
		return
	end
	if shopPushQueued then
		return
	end
	shopPushQueued = true
	task.delay(0.1, function()
		shopPushQueued = false
		Net.FireAll("ShopState", RestaurantService.BuildShopState())
	end)
end

-- In a lobby session the host (teleport data) owns the restaurant; their save holds the shop.
RestaurantService.PreferredOwnerId = nil :: number?

local function chooseOwner()
	local preferred = RestaurantService.PreferredOwnerId and Players:GetPlayerByUserId(RestaurantService.PreferredOwnerId)
	if preferred and owner ~= preferred and DataService.Get(preferred) then
		owner = nil -- the host arrived: hand the shop back to them
	end
	if owner and owner.Parent then
		return
	end
	owner = nil
	if preferred and DataService.Get(preferred) then
		owner = preferred
	end
	for _, p in ipairs(Players:GetPlayers()) do
		-- guests play on the host's save and can never own the shop themselves
		if not owner and DataService.Get(p) and not DataService.IsGuest(p) then
			owner = p
			break
		end
	end
	if owner then
		Net.NotifyAll("n_new_owner", { name = owner.DisplayName }, "info")
	end
	for _, p in ipairs(Players:GetPlayers()) do
		EconomyService.Push(p)
	end
	RestaurantService.ApplyWorldUpgrades()
	ownerChanged:Fire(owner)
	RestaurantService.PushShop()
end
RestaurantService.ChooseOwner = chooseOwner

function RestaurantService.Init()
	EconomyService.AddStateProvider(function(player, s)
		s.isOwner = owner == player
	end)
	DataService.ProfileLoaded:Connect(function(player)
		if not owner or player.UserId == RestaurantService.PreferredOwnerId then
			chooseOwner()
		else
			EconomyService.Push(player)
		end
		RestaurantService.PushShop(player)
	end)
	Players.PlayerRemoving:Connect(function(p)
		if p == owner then
			-- save already happens in DataService; hand over the shop
			task.defer(function()
				owner = nil
				chooseOwner()
			end)
		end
	end)
	-- deliveries
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for i = #deliveries, 1, -1 do
				local d = deliveries[i]
				if now >= d.arrive then
					table.remove(deliveries, i)
					if not (RestaurantService.DeliverHook and RestaurantService.DeliverHook(d)) then
						RestaurantService.AddStock(d.id, d.amount)
						local def = IngredientData.Stock[d.id]
						if d.by and d.by.Parent then
							Net.Notify(d.by, "n_restock_arrived", { item = def.name }, "success")
						end
					end
				end
			end
		end
	end)
	task.spawn(runDoor)
	RestaurantService.RollGoals()
	RestaurantService.ApplyWorldUpgrades()
	RestaurantService.RegisterDisplay("KEBAP HAUS", "Willkommen!")
	Net.OnRequest("Restock", RestaurantService.Restock)
end

return RestaurantService
