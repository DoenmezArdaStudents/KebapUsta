-- Physical logistics: every ordered good arrives as a box from a delivery van, is unloaded onto the
-- loading zone outside, carried by hand into the storage room (shelves) or the cold room (meat),
-- and carried from the shelf to the kitchen station that needs it. Nothing teleports into stock.
--
-- Server authoritative: boxes live in the owner's save (data.logi.boxes) with one location each
-- ("van" | "out" | "shelf" | "carried"). Paid orders are saved too (data.logi.orders), so a
-- disconnect never loses or duplicates goods: on load "van"/"carried" boxes go back outside.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Services = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Net = require(Services.Net)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local RestaurantService = require(Services.RestaurantService)
local FoodPreparationService = require(Services.FoodPreparationService)
local CustomerService = require(Services.CustomerService)
local IngredientData = require(Shared.IngredientData)

local LogisticsService = {}

-- layout --------------------------------------------------------------------
local ZONE_ORIGIN = Vector3.new(20.2, 0.25, 24.6) -- loading zone on the sidewalk, right of the door
local VAN_Z = 37.5
local VAN_PARK_X = 23
local SHELVES = { { x = 17.5, group = 1 }, { x = 23.5, group = 2 } }
local SHELF_Z = -18.9
local BOARD_Y = { 0.8, 3.1, 5.4, 7.7 }
local COLD_DROP = Vector3.new(35, 3.5, -12.6)
local BOX_SIZE = Vector3.new(2, 1.4, 1.6)
local MAX_PER_ITEM = 4 -- boxes of one item in the warehouse (incl. on the way)

local CAT_STYLE = {
	veg = { color = Color3.fromRGB(70, 150, 70), mat = Enum.Material.SmoothPlastic, crate = true, speed = 0.85, emoji = "🥬" },
	sauce = { color = Color3.fromRGB(196, 160, 112), mat = Enum.Material.Cardboard, speed = 0.85, emoji = "🧴" },
	bread = { color = Color3.fromRGB(196, 160, 112), mat = Enum.Material.Cardboard, speed = 0.9, emoji = "🥖" },
	drink = { color = Color3.fromRGB(200, 60, 50), mat = Enum.Material.SmoothPlastic, crate = true, speed = 0.7, emoji = "🥤" },
	meat = { color = Color3.fromRGB(238, 240, 244), mat = Enum.Material.SmoothPlastic, speed = 0.7, emoji = "🥩" },
}
local DELAY_MUL = { meat = 1.3, drink = 1.2 }

-- kitchen station -> stock id
local function stockFor(kind: string, item: any): string?
	if kind == "bread" then
		return item == "box" and "box" or ("bread_" .. tostring(item))
	elseif kind == "veg" then
		return item
	elseif kind == "cheese" then
		return "cheese"
	elseif kind == "sauce" then
		return "sauce_" .. tostring(item)
	elseif kind == "drink" then
		return "drink_" .. tostring(item)
	end
	return nil
end
local HANDS_FULL = { bread = true, veg = true, cheese = true, sauce = true, drink = true, spit = true, board = true, grill = true, trash = true, coldmeat = true, spit_load = true, precut = true, dirt = true, fresh = true }

-- state ---------------------------------------------------------------------
local folder: Folder
local models: { [number]: Model } = {}
local carrying: { [Player]: { u: number, model: Model } } = {} -- arm pose: Client/LogisticsUI
local coldStore: ((any) -> boolean)? = nil
local vanBusy = false
local slots: { { cf: CFrame, group: number } } = {}

local function ownerData()
	local o = RestaurantService.GetOwner()
	return o and DataService.Get(o), o
end

local function logi()
	local d, o = ownerData()
	if not d then
		return nil, nil
	end
	local l = d.logi
	if type(l) ~= "table" then
		l = { boxes = {}, orders = {}, uid = 0 }
		d.logi = l
	end
	l.boxes = type(l.boxes) == "table" and l.boxes or {}
	l.orders = type(l.orders) == "table" and l.orders or {}
	l.uid = type(l.uid) == "number" and l.uid or 0
	return l, o
end

local function dirty()
	local _, o = ownerData()
	if o then
		DataService.MarkDirty(o)
	end
end

local function findBox(u: number)
	local l = logi()
	if not l then
		return nil, nil
	end
	for i, b in ipairs(l.boxes) do
		if b.u == u then
			return b, i
		end
	end
	return nil, nil
end

local function cat(id: string): string
	local def = IngredientData.Stock[id]
	return def and def.cat or "bread"
end

-- box model -----------------------------------------------------------------
local function label(parent: BasePart, face: Enum.NormalId, text: string)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.CanvasSize = Vector2.new(150, 110)
	sg.LightInfluence = 1
	sg.Parent = parent
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.new(0.9, 0, 0.62, 0)
	t.Position = UDim2.fromScale(0.05, 0.19)
	t.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
	t.TextColor3 = Color3.fromRGB(30, 30, 30)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.Parent = sg
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = t
end

local function boxText(b): string
	local def = IngredientData.Stock[b.id]
	local st = CAT_STYLE[cat(b.id)] or CAT_STYLE.bread
	local n = def and def.name.de:gsub(" %(Portion%)", ""):upper():gsub("ü", "Ü"):gsub("ä", "Ä"):gsub("ö", "Ö") or b.id
	return ("%s %s\n×%d"):format(st.emoji, n, b.n)
end

local function bit(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = m
	return p
end

local function buildBox(b, cf: CFrame): Model
	local c = cat(b.id)
	local st = CAT_STYLE[c] or CAT_STYLE.bread
	local m = Instance.new("Model")
	m.Name = "Box_" .. b.u
	local lib = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("Logistics")
	local tpl = lib and (lib:FindFirstChild("Box_" .. c) or ((c == "bread" or c == "sauce") and lib:FindFirstChild("Box_cardboard"))) :: BasePart?
	local body: BasePart
	if tpl then
		body = tpl:Clone()
		body.Size = BOX_SIZE
		body.CFrame = cf
		body.Anchored = true
		body.CanCollide = false
		body.Parent = m
	else
		body = bit(m, "Body", BOX_SIZE, cf, st.color, st.mat)
		if st.crate then
			-- open plastic crate with the goods inside
			local def = IngredientData.Veg[b.id] or IngredientData.Drinks and IngredientData.Drinks[b.id:gsub("drink_", "")]
			local fill = def and (def.color or def.raw) or Color3.fromRGB(120, 200, 90)
			bit(m, "Goods", BOX_SIZE * Vector3.new(0.86, 0.2, 0.84), cf * CFrame.new(0, BOX_SIZE.Y * 0.42, 0), fill, Enum.Material.Grass)
		else
			bit(m, "Tape", Vector3.new(0.3, 0.02, BOX_SIZE.Z + 0.02), cf * CFrame.new(0, BOX_SIZE.Y / 2, 0), Color3.fromRGB(150, 110, 70), Enum.Material.Plastic)
		end
		if c == "meat" then
			bit(m, "Lid", BOX_SIZE * Vector3.new(1.04, 0.14, 1.04), cf * CFrame.new(0, BOX_SIZE.Y / 2, 0), Color3.fromRGB(60, 120, 200))
		end
	end
	body.Name = "Body"
	m.PrimaryPart = body
	label(body, Enum.NormalId.Front, boxText(b))
	label(body, Enum.NormalId.Back, boxText(b))
	return m
end

-- rendering -----------------------------------------------------------------
local function zoneCF(i: number): CFrame
	local col = (i - 1) % 3
	local row = math.floor((i - 1) / 3) % 2
	local layer = math.floor((i - 1) / 6)
	return CFrame.new(ZONE_ORIGIN + Vector3.new(col * 2.3, BOX_SIZE.Y / 2 + layer * BOX_SIZE.Y, row * 1.9))
end

local function render()
	for u, m in pairs(models) do
		m:Destroy()
		models[u] = nil
	end
	local l = logi()
	if not l then
		return
	end
	local outIdx = 0
	for _, b in ipairs(l.boxes) do
		local cf
		if b.at == "out" then
			outIdx += 1
			cf = zoneCF(outIdx)
		elseif b.at == "shelf" and slots[b.slot] then
			cf = slots[b.slot].cf
		end
		if cf then
			local m = buildBox(b, cf)
			local body = m.PrimaryPart :: BasePart
			body:SetAttribute("Station", "logi_box")
			body:SetAttribute("Box", b.u)
			body:SetAttribute("PromptDe", b.at == "out" and "Aufheben" or "Herausnehmen")
			body:SetAttribute("PromptEn", "Pick up")
			body:SetAttribute("PromptObj", (boxText(b):gsub("\n", " ")))
			body:SetAttribute("PromptHold", 0.3)
			body:SetAttribute("PromptDist", 7)
			body.CanQuery = true
			m.Parent = folder
			game:GetService("CollectionService"):AddTag(body, "Station")
			models[b.u] = m
		end
	end
	RestaurantService.PushShop()
	for _, p in ipairs(Players:GetPlayers()) do
		EconomyService.Push(p)
	end
end

-- carrying ------------------------------------------------------------------
local function detach(player: Player)
	local c = carrying[player]
	if not c then
		return
	end
	carrying[player] = nil
	if c.model then
		c.model:Destroy()
	end
	player:SetAttribute("Carry", nil)
	player:SetAttribute("CarrySpeed", nil)
end

local function attach(player: Player, b): boolean
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not torso then
		return false
	end
	local m = buildBox(b, torso.CFrame * CFrame.new(0, -0.2, -1.45))
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			p.CanQuery = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = torso
			w.Part1 = p
			w.Parent = p
		end
	end
	m.Name = "CarriedBox_" .. player.UserId
	m.Parent = folder -- outside the character so first person does not hide it
	carrying[player] = { u = b.u, model = m }
	local st = CAT_STYLE[cat(b.id)] or CAT_STYLE.bread
	player:SetAttribute("Carry", b.id)
	player:SetAttribute("CarrySpeed", st.speed)
	return true
end

local function refreshCarryLabel(player: Player, b)
	local c = carrying[player]
	local body = c and c.model and c.model.PrimaryPart
	if body then
		for _, sg in ipairs(body:GetChildren()) do
			if sg:IsA("SurfaceGui") and sg:FindFirstChild("Text") then
				(sg.Text :: TextLabel).Text = boxText(b)
			end
		end
	end
end

local function carried(player: Player)
	local c = carrying[player]
	if not c then
		return nil
	end
	local b, i = findBox(c.u)
	if not b then
		detach(player)
		return nil, nil
	end
	return b, i
end

-- actions -------------------------------------------------------------------
local function onPick(player: Player, part: BasePart)
	if carrying[player] or (player.Character and player.Character:FindFirstChild("CarriedCone")) or FoodPreparationService.HandsBusy(player) then
		Net.Notify(player, "🙌 Du hast schon die Hände voll", nil, "warn")
		return
	end
	local b = findBox(part:GetAttribute("Box"))
	if not b or (b.at ~= "out" and b.at ~= "shelf") then
		return
	end
	b.at = "carried"
	b.slot = nil
	if not attach(player, b) then
		b.at = "out"
		return
	end
	Net.Sound(player, "click")
	dirty()
	render()
end

local function freeSlot(group: number?): number?
	local l = logi()
	local used = {}
	for _, b in ipairs(l.boxes) do
		if b.at == "shelf" and b.slot then
			used[b.slot] = true
		end
	end
	for pass = 1, 2 do
		for i, s in ipairs(slots) do
			if not used[i] and (pass == 2 or s.group == group) then
				return i
			end
		end
	end
	return nil
end

local function onShelf(player: Player, part: BasePart)
	local b = carried(player)
	if not b then
		return
	end
	if cat(b.id) == "meat" then
		Net.Notify(player, "❄️ Fleisch gehört in den Kühlraum", nil, "warn")
		return
	end
	local slot = freeSlot(part:GetAttribute("Group"))
	if not slot then
		Net.Notify(player, "📦 Das Lager ist voll", nil, "warn")
		return
	end
	b.at = "shelf"
	b.slot = slot
	detach(player)
	Net.Notify(player, "✅ Eingelagert: " .. boxText(b):gsub("\n", " "), nil, "success")
	Net.Sound(nil, "add", slots[slot].cf.Position)
	dirty()
	render()
end

local function onCold(player: Player)
	local ColdRoomService = require(script.Parent.ColdRoomService)
	if ColdRoomService.IsCarrying(player) then
		ColdRoomService.ReturnCarried(player)
		return
	end
	local b, i = carried(player)
	if not b then
		return
	end
	if cat(b.id) ~= "meat" then
		Net.Notify(player, "📦 Das kommt ins Regal im Lager", nil, "warn")
		return
	end
	local l = logi()
	table.remove(l.boxes, i)
	detach(player)
	if coldStore then
		coldStore({ id = b.id, amount = b.n, by = player })
	else
		RestaurantService.AddStock(b.id, b.n)
	end
	Net.Sound(nil, "add", COLD_DROP)
	dirty()
	render()
end

-- carrying a box to its kitchen station refills it; anything else needs free hands
local function interactHook(player: Player, part: BasePart, kind: string): boolean
	local b, i = carried(player)
	if not b then
		-- carrying a meat cone: no cooking with full hands either
		if player:GetAttribute("Carry") and HANDS_FULL[kind] and kind ~= "spit_load" then
			Net.Notify(player, "🙌 Erst den Fleischspieß abstellen", nil, "warn")
			return true
		end
		return false
	end
	local sid = stockFor(kind, part:GetAttribute("Item"))
	if sid and sid == b.id then
		local cap = RestaurantService.Capacity(sid)
		local add = math.min(b.n, cap - RestaurantService.GetStock(sid))
		if add <= 0 then
			Net.Notify(player, "Die Station ist schon voll", nil, "warn")
			return true
		end
		RestaurantService.AddStock(sid, add)
		b.n -= add
		Net.Sound(nil, "add", part.Position)
		if b.n <= 0 then
			table.remove(logi().boxes, i)
			detach(player)
			Net.Notify(player, ("✅ Aufgefüllt (+%d) – Kiste ist leer"):format(add), nil, "success")
		else
			refreshCarryLabel(player, b)
			Net.Notify(player, ("✅ Aufgefüllt (+%d) – Rest zurück ins Regal"):format(add), nil, "success")
		end
		dirty()
		render()
		return true
	end
	if HANDS_FULL[kind] then
		Net.Notify(player, "🙌 Erst die Kiste abstellen", nil, "warn")
		return true
	end
	return false
end

-- orders & van ---------------------------------------------------------------
local function countBoxes(pred: (string) -> boolean): number
	local l = logi()
	if not l then
		return 0
	end
	local n = 0
	for _, b in ipairs(l.boxes) do
		if pred(b.id) then
			n += 1
		end
	end
	for _, o in ipairs(l.orders) do
		if pred(o.id) then
			n += 1
		end
	end
	return n
end

-- how much one order of this item brings (nil = no room in the warehouse / cold room)
local function orderGate(stockId: string): number?
	local def = IngredientData.Stock[stockId]
	if not def or not logi() then
		return nil
	end
	if countBoxes(function(id)
		return id == stockId
	end) >= MAX_PER_ITEM then
		return nil
	end
	if def.meat then
		local cold = 0
		for id, d in pairs(IngredientData.Stock) do
			if d.meat and RestaurantService.ColdAmount then
				cold += math.ceil(RestaurantService.ColdAmount(id) / d.pack)
			end
		end
		if cold + countBoxes(function(id)
			return cat(id) == "meat"
		end) >= 9 then
			return nil
		end
	elseif countBoxes(function(id)
		return cat(id) ~= "meat"
	end) >= #slots then
		return nil
	end
	return def.pack
end

local function orderHook(stockId: string, amount: number, delay: number, player: Player)
	local l = logi()
	if not l then
		return
	end
	local d = delay * (DELAY_MUL[cat(stockId)] or 1)
	table.insert(l.orders, { id = stockId, n = amount, due = os.time() + math.ceil(d) })
	dirty()
	render()
end

local function newRig(): Model?
	local ok, rig = pcall(CustomerService.NewRig)
	if not ok or not rig then
		return nil
	end
	pcall(CustomerService.Dress, rig, { shirt = Color3.fromRGB(240, 200, 40), pants = Color3.fromRGB(50, 50, 60), skin = Color3.fromRGB(214, 170, 130), shoes = Color3.fromRGB(30, 30, 30), hat = true, hatColor = Color3.fromRGB(230, 70, 40) })
	rig.Name = "DeliveryDriver"
	return rig
end

local function buildVan(): Model
	local m = Instance.new("Model")
	m.Name = "DeliveryVan"
	local lib = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("Logistics")
	local tpl = lib and lib:FindFirstChild("Van")
	local base = CFrame.new(0, 0, VAN_Z)
	if tpl then
		local v = tpl:Clone()
		for _, p in ipairs(v:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
			end
		end
		v:PivotTo(base)
		v.Parent = m
		local root = v:IsA("BasePart") and v or v:FindFirstChildWhichIsA("BasePart", true)
		m.PrimaryPart = root
		return m
	end
	local white, glass = Color3.fromRGB(245, 245, 245), Color3.fromRGB(40, 60, 80)
	local body = bit(m, "Body", Vector3.new(12, 6, 5.6), base * CFrame.new(-1, 4.1, 0), white)
	bit(m, "Cab", Vector3.new(3, 4, 5.6), base * CFrame.new(6.5, 3.1, 0), white)
	bit(m, "Windshield", Vector3.new(0.2, 2, 5), base * CFrame.new(8.05, 4, 0) * CFrame.Angles(0, 0, math.rad(-15)), glass, Enum.Material.Glass)
	bit(m, "SideWindow", Vector3.new(2, 1.6, 5.7), base * CFrame.new(6.5, 4.2, 0), glass, Enum.Material.Glass)
	bit(m, "Stripe", Vector3.new(12.02, 0.8, 5.62), base * CFrame.new(-1, 3.2, 0), Color3.fromRGB(230, 70, 40))
	for _, x in ipairs({ -5, 5.5 }) do
		for _, z in ipairs({ -2.6, 2.6 }) do
			local w = bit(m, "Wheel", Vector3.new(0.8, 2.2, 2.2), base * CFrame.new(x, 1.1, z) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(25, 25, 25))
			w.Shape = Enum.PartType.Cylinder
		end
	end
	local sign = bit(m, "Sign", Vector3.new(8, 2, 0.05), base * CFrame.new(-1, 4.8, -2.83), white)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.Parent = sign
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(230, 70, 40)
	t.Text = "FRISCH-LIEFERDIENST"
	t.Parent = sg
	m.PrimaryPart = body
	return m
end

local function driveVan(van: Model, fromX: number, toX: number, secs: number)
	local v = Instance.new("NumberValue")
	v.Value = fromX
	local conn = v.Changed:Connect(function(x)
		van:PivotTo(CFrame.new(x, 0, VAN_Z))
	end)
	local tw = TweenService:Create(v, TweenInfo.new(secs, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = toX })
	tw:Play()
	tw.Completed:Wait()
	conn:Disconnect()
	v:Destroy()
end

local function runVan()
	vanBusy = true
	local l, owner = logi()
	-- 1) due orders become boxes "in the van" (saved, so nothing is lost if the server stops now)
	local now = os.time()
	local load = {}
	for i = #l.orders, 1, -1 do
		local o = l.orders[i]
		if now >= (o.due or 0) then
			table.remove(l.orders, i)
			local def = IngredientData.Stock[o.id]
			local left = o.n
			while def and left > 0 do
				local n = math.min(def.pack, left)
				left -= n
				l.uid += 1
				local b = { u = l.uid, id = o.id, n = n, at = "van" }
				table.insert(l.boxes, b)
				table.insert(load, b)
			end
		end
	end
	dirty()
	if #load == 0 then
		vanBusy = false
		return
	end
	-- 2) the van drives up, the driver unloads every box onto the loading zone
	local van = buildVan()
	van:PivotTo(CFrame.new(-170, 0, VAN_Z))
	van.Parent = folder
	driveVan(van, -170, VAN_PARK_X, 7)
	Net.Sound(nil, "doorbell", Vector3.new(VAN_PARK_X, 3, VAN_Z))
	if owner and owner.Parent then
		Net.Notify(owner, ("🚚 Lieferung ist da – %d Kiste(n) werden abgeladen"):format(#load), nil, "success")
	end
	local driver = newRig()
	local hum = driver and driver:FindFirstChildOfClass("Humanoid")
	local door = Vector3.new(VAN_PARK_X - 7.5, 3, VAN_Z - 1)
	if driver and hum then
		driver:PivotTo(CFrame.new(door))
		driver.Parent = folder
		hum.WalkSpeed = 14
	end
	for _, b in ipairs(load) do
		if b.at ~= "van" then
			continue
		end
		local held
		if driver and hum then
			local root = driver:FindFirstChild("HumanoidRootPart") :: BasePart
			held = buildBox(b, root.CFrame * CFrame.new(0, 0, -1.3))
			for _, p in ipairs(held:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = false
					p.Massless = true
					local w = Instance.new("WeldConstraint")
					w.Part0 = root
					w.Part1 = p
					w.Parent = p
				end
			end
			held.Parent = driver
			hum:MoveTo(ZONE_ORIGIN + Vector3.new(2, 0, 1))
			local t0 = os.clock()
			while os.clock() - t0 < 4 and (root.Position - (ZONE_ORIGIN + Vector3.new(2, 3, 1))).Magnitude > 3.5 do
				task.wait(0.1)
			end
			task.wait(0.3)
		else
			task.wait(0.6)
		end
		if held then
			held:Destroy()
		end
		b.at = "out"
		dirty()
		render()
		if driver and hum then
			hum:MoveTo(door)
			task.wait(1.2)
		end
	end
	if driver then
		driver:Destroy()
	end
	task.wait(0.5)
	driveVan(van, VAN_PARK_X, 190, 6)
	van:Destroy()
	vanBusy = false
end

-- world ----------------------------------------------------------------------
local function dropPart(name: string, size: Vector3, pos: Vector3, kind: string, de: string, group: number?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p:SetAttribute("Station", kind)
	p:SetAttribute("PromptDe", de)
	p:SetAttribute("PromptEn", de)
	p:SetAttribute("PromptObj", "📦")
	p:SetAttribute("PromptHold", 0.2)
	p:SetAttribute("PromptDist", 7)
	if group then
		p:SetAttribute("Group", group)
	end
	p.Parent = folder
	game:GetService("CollectionService"):AddTag(p, "Station")
	return p
end

local function buildWorld()
	local r = workspace:FindFirstChild("Restaurant")
	folder = Instance.new("Folder")
	folder.Name = "Logistics"
	folder.Parent = r
	-- the decorative boxes on the storage shelves make room for real ones
	local storage = r and r:FindFirstChild("Storage")
	if storage then
		for _, c in ipairs(storage:GetChildren()) do
			if c.Name == "Box" then
				c:Destroy()
			end
		end
	end
	slots = {}
	for _, s in ipairs(SHELVES) do
		for _, y in ipairs(BOARD_Y) do
			for _, dx in ipairs({ -1.2, 1.2 }) do
				table.insert(slots, { cf = CFrame.new(s.x + dx, y + BOX_SIZE.Y / 2, SHELF_Z), group = s.group })
			end
		end
		dropPart("ShelfDrop" .. s.group, Vector3.new(5.2, 8.8, 0.6), Vector3.new(s.x, 4.6, SHELF_Z + 1.3), "logi_shelf", "Ins Regal stellen", s.group)
	end
	-- Blender pallet racks replace the primitive shelf frames (same footprint, same deck heights)
	local lib = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("Logistics")
	local rack = lib and lib:FindFirstChild("Shelf") :: BasePart?
	if rack and storage then
		for _, c in ipairs(storage:GetChildren()) do
			if (c.Name == "ShelfFrame" or c.Name == "ShelfBoard") and c:IsA("BasePart") then
				c.Transparency = 1
			end
		end
		for _, s in ipairs(SHELVES) do
			local r2 = rack:Clone()
			r2.Size = Vector3.new(5, 8.8, 1.8)
			r2.CFrame = CFrame.new(s.x, 4.6, SHELF_Z)
			r2.Anchored = true
			r2.Parent = folder
		end
	end
	dropPart("ColdDrop", Vector3.new(4, 6, 4), COLD_DROP, "logi_cold", "Im Kühlraum einlagern")
	-- loading zone markings + sign
	local zone = Instance.new("Part")
	zone.Name = "LoadingZone"
	zone.Size = Vector3.new(7.4, 0.05, 4.8)
	zone.Position = ZONE_ORIGIN + Vector3.new(2.1, -0.2, 0.95)
	zone.Color = Color3.fromRGB(240, 196, 40)
	zone.Material = Enum.Material.SmoothPlastic
	zone.Anchored = true
	zone.CanCollide = false
	zone.Parent = folder
	for i = 0, 4 do
		local s = Instance.new("Part")
		s.Name = "ZoneStripe"
		s.Size = Vector3.new(0.5, 0.06, 4.8)
		s.CFrame = CFrame.new(zone.Position + Vector3.new(-3.2 + i * 1.6, 0.01, 0)) * CFrame.Angles(0, math.rad(30), 0)
		s.Color = Color3.fromRGB(30, 30, 30)
		s.Material = Enum.Material.SmoothPlastic
		s.Anchored = true
		s.CanCollide = false
		s.Parent = folder
	end
	local post = Instance.new("Part")
	post.Name = "ZoneSign"
	post.Size = Vector3.new(3.4, 1.2, 0.15)
	post.Position = ZONE_ORIGIN + Vector3.new(2.1, 3.6, -1.2)
	post.Color = Color3.fromRGB(240, 196, 40)
	post.Anchored = true
	post.CanCollide = false
	post.Parent = folder
	label(post, Enum.NormalId.Back, "🚚 LIEFERZONE")
	label(post, Enum.NormalId.Front, "🚚 LIEFERZONE")
	local pole = Instance.new("Part")
	pole.Name = "ZonePole"
	pole.Size = Vector3.new(0.2, 3.6, 0.2)
	pole.Position = ZONE_ORIGIN + Vector3.new(2.1, 1.6, -1.2)
	pole.Color = Color3.fromRGB(90, 90, 95)
	pole.Material = Enum.Material.Metal
	pole.Anchored = true
	pole.Parent = folder
end

-- client state: incoming orders, boxes waiting, warehouse fill
local function provide(player: Player, state)
	local l = logi()
	if not l then
		return
	end
	local orders, out, shelf = {}, 0, 0
	for _, o in ipairs(l.orders) do
		table.insert(orders, { id = o.id, n = o.n, due = o.due })
	end
	for _, b in ipairs(l.boxes) do
		if b.at == "out" or b.at == "van" then
			out += 1
		elseif b.at == "shelf" then
			shelf += 1
		end
	end
	state.logi = { orders = orders, out = out, shelf = shelf, slots = #slots, van = vanBusy }
end

local function normalize()
	local l = logi()
	if not l then
		return
	end
	for _, b in ipairs(l.boxes) do
		if b.at ~= "out" and b.at ~= "shelf" or (b.at == "shelf" and not slots[b.slot]) then
			b.at = "out"
			b.slot = nil
		end
	end
end

function LogisticsService.Init()
	buildWorld()
	coldStore = RestaurantService.DeliverHook
	RestaurantService.OrderGate = orderGate
	RestaurantService.OrderHook = orderHook
	-- direct deliveries (anything still using the old path) also come as boxes
	RestaurantService.DeliverHook = function(d)
		orderHook(d.id, d.amount, 0, d.by)
		return true
	end
	FoodPreparationService.InteractHook = interactHook
	FoodPreparationService.ExternalActions.logi_box = onPick
	FoodPreparationService.ExternalActions.logi_shelf = onShelf
	FoodPreparationService.ExternalActions.logi_cold = onCold
	EconomyService.AddStateProvider(provide)
	local function ownerReset()
		for p in pairs(carrying) do
			detach(p)
		end
		normalize()
		render()
	end
	RestaurantService.OwnerChanged:Connect(ownerReset)
	task.defer(ownerReset)
	local function dropCarried(p: Player)
		local c = carrying[p]
		if c then
			local b = findBox(c.u)
			if b then
				b.at = "out"
			end
			detach(p)
			dirty()
			render()
		end
	end
	Players.PlayerRemoving:Connect(dropCarried)
	local function hookChar(p: Player)
		p.CharacterRemoving:Connect(function()
			dropCarried(p)
		end)
	end
	Players.PlayerAdded:Connect(hookChar)
	for _, p in ipairs(Players:GetPlayers()) do
		hookChar(p)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local l = logi()
			if l and not vanBusy then
				local now = os.time()
				for _, o in ipairs(l.orders) do
					if now >= (o.due or 0) then
						task.spawn(runVan)
						break
					end
				end
			end
		end
	end)
end

LogisticsService.Render = render
return LogisticsService
