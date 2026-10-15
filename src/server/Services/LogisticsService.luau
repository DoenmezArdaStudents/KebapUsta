-- Physical logistics: every ordered good arrives as a box from a delivery van (Server/DeliveryVanService,
-- it drives into the backyard), is unloaded onto the unloading area behind the restaurant, carried
-- by hand through the back door into the storage room (shelves) or the cold room (meat),
-- and carried from the shelf to the kitchen station that needs it. Nothing teleports into stock.
--
-- Server authoritative: boxes live in the owner's save (data.logi.boxes) with one location each
-- ("van" | "out" | "shelf" | "carried"). Paid orders are saved too (data.logi.orders), so a
-- disconnect never loses or duplicates goods: on load "van"/"carried" boxes go back outside.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Services = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Net = require(Services.Net)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local RestaurantService = require(Services.RestaurantService)
local FoodPreparationService = require(Services.FoodPreparationService)
local DeliveryVanService = require(Services.DeliveryVanService)
local IngredientData = require(Shared.IngredientData)

local LogisticsService = {}
LogisticsService.EmptyBoxHook = nil :: ((Player, any, Vector3) -> ())?
LogisticsService.HandsBusyHook = nil :: ((Player) -> boolean)?

-- layout --------------------------------------------------------------------
-- unloading spots in the backyard (Server/BackyardService): a row on the asphalt between the
-- parked van's rear doors and the building, then a second row on the landing at the back door
local UNLOAD_ROWS = { { x = 22.6, z = -29.1, y = 0.15 }, { x = 22.6, z = -25.4, y = 0.25 } }
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
	local k = i - 1
	local row = UNLOAD_ROWS[math.min(#UNLOAD_ROWS, math.floor(k / 18) + 1)]
	local within = k % 18
	local col, layer = within % 6, math.floor(within / 6)
	return CFrame.new(row.x + col * 2.3, row.y + BOX_SIZE.Y / 2 + layer * BOX_SIZE.Y, row.z)
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
	if carrying[player] or (player.Character and player.Character:FindFirstChild("CarriedCone")) or FoodPreparationService.HandsBusy(player) or (LogisticsService.HandsBusyHook and LogisticsService.HandsBusyHook(player)) then
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
			if LogisticsService.EmptyBoxHook then
				task.spawn(LogisticsService.EmptyBoxHook, player, b, part.Position) -- cardboard waste (Server/WasteService)
			end
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

local function outCount(): number
	local n = 0
	local l = logi()
	for _, b in ipairs(l and l.boxes or {}) do
		if b.at == "out" then
			n += 1
		end
	end
	return n
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
	render() -- the delivery tracker shows "van is unloading" instead of the paid orders
	if #load == 0 then
		vanBusy = false
		return
	end
	if owner and owner.Parent then
		Net.Notify(owner, ("🚚 Lieferwagen kommt in den Hinterhof – %d Kiste(n)"):format(#load), nil, "info")
	end
	-- 2) the van drives into the backyard and the driver unloads every box (Server/DeliveryVanService).
	-- Each box changes "van" -> "out" exactly once, when the driver puts it down.
	local ok, err = pcall(DeliveryVanService.Run, load, {
		spot = function()
			return zoneCF(outCount() + 1)
		end,
		unload = function(b)
			if b.at == "van" then
				b.at = "out"
				dirty()
				render()
			end
		end,
		model = function(b, cf)
			return buildBox(b, cf)
		end,
	})
	if not ok then
		warn("[LogisticsService] delivery van failed: " .. tostring(err))
	end
	-- 3) safety net: whatever is still "in the van" (error, timeout) lands on the unloading area
	local missed = false
	for _, b in ipairs(load) do
		if b.at == "van" then
			b.at = "out"
			missed = true
		end
	end
	if missed then
		dirty()
		render()
	end
	if owner and owner.Parent then
		Net.Notify(owner, ("📦 %d Kiste(n) im Hinterhof abgeladen"):format(#load), nil, "success")
	end
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
end

-- upgrade "yard_storage": an extra rack against the back wall in the backyard (8 more slots).
-- Its slots are appended, so saved slot numbers of the indoor racks never change.
local YARD_SHELF = { x = 38.6, z = -22.4, group = 3 }
local yardShelf = false
function LogisticsService.AddYardShelf()
	if yardShelf or not folder then
		return
	end
	yardShelf = true
	for _, y in ipairs(BOARD_Y) do
		for _, dx in ipairs({ -1.2, 1.2 }) do
			table.insert(slots, { cf = CFrame.new(YARD_SHELF.x + dx, y - 0.1 + BOX_SIZE.Y / 2, YARD_SHELF.z), group = YARD_SHELF.group })
		end
	end
	dropPart("ShelfDropYard", Vector3.new(5.2, 8.8, 0.6), Vector3.new(YARD_SHELF.x, 4.5, YARD_SHELF.z - 1.3), "logi_shelf", "Ins Regal stellen", YARD_SHELF.group)
	local lib = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("Logistics")
	local rack = lib and lib:FindFirstChild("Shelf") :: BasePart?
	if rack then
		local r2 = rack:Clone()
		r2.Size = Vector3.new(5, 8.8, 1.8)
		r2.CFrame = CFrame.new(YARD_SHELF.x, 4.5, YARD_SHELF.z) * CFrame.Angles(0, math.pi, 0)
		r2.Anchored = true
		r2.Parent = folder
	else
		-- primitive rack: posts and four boards
		local m = Instance.new("Model")
		m.Name = "YardRack"
		for _, x in ipairs({ -2.45, 2.45 }) do
			for _, z in ipairs({ -0.8, 0.8 }) do
				local p = Instance.new("Part")
				p.Size = Vector3.new(0.18, 9, 0.18)
				p.CFrame = CFrame.new(YARD_SHELF.x + x, 4.6, YARD_SHELF.z + z)
				p.Color = Color3.fromRGB(40, 90, 170)
				p.Material = Enum.Material.Metal
				p.Anchored = true
				p.Parent = m
			end
		end
		for _, y in ipairs(BOARD_Y) do
			local b = Instance.new("Part")
			b.Size = Vector3.new(5, 0.15, 1.8)
			b.CFrame = CFrame.new(YARD_SHELF.x, y - 0.1, YARD_SHELF.z)
			b.Color = Color3.fromRGB(240, 140, 30)
			b.Material = Enum.Material.Metal
			b.Anchored = true
			b.Parent = m
		end
		m.Parent = folder
	end
	render()
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
