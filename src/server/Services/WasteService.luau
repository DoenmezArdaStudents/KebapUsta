-- Waste, the backyard containers and the waste collection (issues #12, #13, #14).
--
-- Waste objects (physical, saved in the owner's slot as data.waste.items):
--   scraps     🥬 vegetable scraps      → organic   (every few vegetable portions at the stations)
--   packaging  🧴 plastic packaging     → plastic   (every few packed meals)
--   cardboard  📦 empty delivery box    → general   (a delivery box emptied at its station)
--   bag        🗑️ full garbage bag      → general   (the kitchen bin is full: discarded meals, wiped trash)
-- Players (and the cleaner, Server/EmployeeService) pick them up, carry them through the back door
-- to the three containers in the backyard waste area and throw them into the right one. The lid
-- opens (tag "SwingDoor", Client/Doors), the item flies in, the fill level on the front label goes
-- up. Wrong container, a full one or something that isn't waste is refused – nothing leaves the
-- hands unless the disposal succeeded.
-- Cleanliness (Server/BusinessService): every object lying around and every full container costs
-- cleanliness (Config.Waste), which feeds customer mood, reviews and demand.
-- Collection (#14): the call point next to the waste area orders the paid garbage truck
-- (Server/GarbageTruckService); it empties every container. Bigger bins = upgrade "yard_bins".
-- Save safety: items stay in the save at their floor position while carried, so a disconnect or a
-- crash never loses or duplicates anything; container fills and counters are saved too.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Services = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Config = require(Shared.Config)
local Net = require(Services.Net)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local RestaurantService = require(Services.RestaurantService)
local FoodPreparationService = require(Services.FoodPreparationService)
local BusinessService = require(Services.BusinessService)
local LogisticsService = require(Services.LogisticsService)
local GarbageTruckService = require(Services.GarbageTruckService)

local WasteService = {}
local W = Config.Waste

export type Item = { u: number, k: string, x: number, y: number, z: number }

local KINDS = {
	scraps = { bin = "organic", de = "Gemüsereste", en = "Vegetable scraps", icon = "🥬", speed = 0.95 },
	packaging = { bin = "plastic", de = "Plastikverpackung", en = "Plastic packaging", icon = "🧴", speed = 0.95 },
	cardboard = { bin = "general", de = "Leerer Karton", en = "Empty cardboard box", icon = "📦", speed = 0.9 },
	bag = { bin = "general", de = "Müllsack", en = "Garbage bag", icon = "🗑️", speed = 0.85 },
}
WasteService.Kinds = KINDS

-- containers in the waste area (Server/BackyardService Layout.waste: x -11..3, z -40..-28), fronts face +X
local BIN_X, BIN_Y = -8.3, 0.3
local BINS = {
	general = { z = -37.8, de = "Restmüll & Karton", en = "General waste & cardboard", short = { de = "Restmüll", en = "General" }, color = Color3.fromRGB(62, 64, 68), text = Color3.fromRGB(235, 235, 235) },
	plastic = { z = -34, de = "Plastik & Verpackung", en = "Plastic & packaging", short = { de = "Plastik", en = "Plastic" }, color = Color3.fromRGB(236, 186, 32), text = Color3.fromRGB(40, 32, 10) },
	organic = { z = -30.2, de = "Bioabfall", en = "Organic waste", short = { de = "Bio", en = "Organic" }, color = Color3.fromRGB(112, 70, 38), text = Color3.fromRGB(240, 230, 210) },
}
local BIN_ORDER = { "general", "plastic", "organic" }
WasteService.Bins = BINS
-- Blender meshes (art/waste/build_bins.py): bounding-box centre / size in bin space
local BIN_MESH = {
	BinBody = { Vector3.new(-0.04, 1.765, 0), Vector3.new(2.44, 2.97, 3.58) },
	BinCastors = { Vector3.new(0, 0.19, 0), Vector3.new(1.68, 0.37, 2.66) },
	BinLid = { Vector3.new(0.07, 3.32, 0), Vector3.new(2.54, 0.38, 3.64) },
}
local LID_HINGE = CFrame.new(-1.2, 3.27, 0) * CFrame.Angles(math.rad(90), 0, 0) -- hinge Y axis = bin +Z
local CALL_POS = Vector3.new(4.6, 0, -26.9) -- call point for the garbage truck, at the waste area entrance

local folder: Folder? = nil -- Restaurant.Waste (items)
local binFolder: Folder? = nil
local itemModels: { [number]: Model } = {}
local binModels: { [string]: { model: Model, lid: Model, label: TextLabel?, bar: Frame?, part: BasePart } } = {}
local carried: { [Player]: { u: number, model: Model } } = {}
local workerCarry: { [number]: Model } = {} -- item u -> model carried by a cleaner
local claims: { [number]: number } = {} -- item u -> os.clock() a cleaner claimed it
local callPart: BasePart? = nil
local rng = Random.new()

---------------------------------------------------------------------------
-- save data
---------------------------------------------------------------------------
local function ownerData()
	local o = RestaurantService.GetOwner()
	return o and DataService.Get(o), o
end

local function state()
	local d = ownerData()
	if not d then
		return nil
	end
	local w = d.waste
	if type(w) ~= "table" then
		w = {}
		d.waste = w
	end
	w.bins = type(w.bins) == "table" and w.bins or {}
	for _, b in ipairs(BIN_ORDER) do
		w.bins[b] = math.max(0, tonumber(w.bins[b]) or 0)
	end
	w.items = type(w.items) == "table" and w.items or {}
	w.kitchen = math.max(0, tonumber(w.kitchen) or 0)
	w.nextU = tonumber(w.nextU) or 1
	w.org = tonumber(w.org) or 0
	w.pla = tonumber(w.pla) or 0
	w.orgAt = tonumber(w.orgAt) or rng:NextInteger(W.ScrapsEvery[1], W.ScrapsEvery[2])
	w.plaAt = tonumber(w.plaAt) or rng:NextInteger(W.PackagingEvery[1], W.PackagingEvery[2])
	return w
end

local function dirty()
	local _, o = ownerData()
	if o then
		DataService.MarkDirty(o)
	end
end

local function findItem(u: any): (Item?, number?)
	local w = state()
	if not w or type(u) ~= "number" then
		return nil, nil
	end
	for i, it in ipairs(w.items) do
		if it.u == u then
			return it, i
		end
	end
	return nil, nil
end

local function isCarried(u: number): boolean
	if workerCarry[u] then
		return true
	end
	for _, c in pairs(carried) do
		if c.u == u then
			return true
		end
	end
	return false
end

function WasteService.Capacity(bin: string): number
	return math.floor((W.BinCap[bin] or 6) * (RestaurantService.UpgradeValue("yard_bins") or 1) + 0.5)
end

local function lang(p: Player?): string
	local d = p and DataService.Get(p)
	return d and d.settings and d.settings.lang == "en" and "en" or "de"
end

local function tr(p: Player?, de: string, en: string): string
	return lang(p) == "en" and en or de
end

---------------------------------------------------------------------------
-- item models
---------------------------------------------------------------------------
local function template(name: string): BasePart?
	local lib = ServerStorage:FindFirstChild("Models")
	local w = lib and lib:FindFirstChild("Waste")
	local t = w and w:FindFirstChild(name)
	return t and t:IsA("BasePart") and t or nil
end

local function bit(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = m
	return p
end

-- cf = ground point under the item
local function buildItem(kind: string, cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Waste_" .. kind
	local r = Random.new(math.floor(cf.Position.X * 13 + cf.Position.Z * 7))
	if kind == "bag" then
		local t = template("BinBag")
		if t then
			local p = t:Clone()
			p.Size = Vector3.new(1.415, 1.37, 1.242)
			p.CFrame = cf * CFrame.new(0, 0.685, 0)
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			p.Parent = m
			m.PrimaryPart = p
		else
			m.PrimaryPart = bit(m, "Bag", Vector3.new(1.3, 1.25, 1.15), cf * CFrame.new(0, 0.62, 0), Color3.fromRGB(22, 22, 24), Enum.Material.Plastic, Enum.PartType.Ball)
			bit(m, "Knot", Vector3.new(0.3, 0.35, 0.3), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(22, 22, 24), Enum.Material.Plastic, Enum.PartType.Ball)
		end
	elseif kind == "cardboard" then
		-- flattened-ish empty box with open flaps
		local base = cf * CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
		m.PrimaryPart = bit(m, "Box", Vector3.new(1.9, 1.1, 1.5), base * CFrame.new(0, 0.55, 0), Color3.fromRGB(190, 150, 100), Enum.Material.Cardboard)
		bit(m, "Inside", Vector3.new(1.8, 0.05, 1.4), base * CFrame.new(0, 1.08, 0), Color3.fromRGB(150, 116, 74), Enum.Material.Cardboard)
		bit(m, "FlapA", Vector3.new(1.9, 0.04, 0.7), base * CFrame.new(0, 1.2, 0.95) * CFrame.Angles(math.rad(-50), 0, 0), Color3.fromRGB(196, 156, 104), Enum.Material.Cardboard)
		bit(m, "FlapB", Vector3.new(1.9, 0.04, 0.7), base * CFrame.new(0, 1.2, -0.95) * CFrame.Angles(math.rad(50), 0, 0), Color3.fromRGB(196, 156, 104), Enum.Material.Cardboard)
	elseif kind == "packaging" then
		local base = cf * CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
		m.PrimaryPart = bit(m, "Foil", Vector3.new(0.9, 0.35, 0.7), base * CFrame.new(0, 0.18, 0), Color3.fromRGB(230, 232, 236), Enum.Material.Foil, Enum.PartType.Ball)
		bit(m, "Bottle", Vector3.new(0.8, 0.32, 0.32), base * CFrame.new(0.35, 0.16, 0.3) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(245, 245, 235), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		bit(m, "Cap", Vector3.new(0.12, 0.2, 0.2), base * CFrame.new(0.78, 0.16, 0.55) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(200, 40, 30), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		bit(m, "Wrap", Vector3.new(0.6, 0.06, 0.5), base * CFrame.new(-0.35, 0.05, -0.25) * CFrame.Angles(0.2, 0.4, 0.1), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic)
	else -- scraps: a little heap of peels and offcuts in a steel bowl
		m.PrimaryPart = bit(m, "Bowl", Vector3.new(0.35, 1.2, 1.2), cf * CFrame.new(0, 0.17, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(180, 184, 190), Enum.Material.Metal, Enum.PartType.Cylinder)
		local cols = { Color3.fromRGB(110, 170, 60), Color3.fromRGB(200, 60, 40), Color3.fromRGB(230, 220, 200), Color3.fromRGB(150, 90, 150), Color3.fromRGB(240, 150, 40) }
		for i = 1, 7 do
			local a = i / 7 * 6.28
			bit(m, "Scrap", Vector3.new(r:NextNumber(0.18, 0.32), r:NextNumber(0.08, 0.14), r:NextNumber(0.2, 0.4)), cf * CFrame.new(math.cos(a) * 0.28, 0.38 + (i % 3) * 0.05, math.sin(a) * 0.28) * CFrame.Angles(r:NextNumber(-0.6, 0.6), r:NextNumber(0, 6.28), r:NextNumber(-0.6, 0.6)), cols[(i % #cols) + 1], Enum.Material.SmoothPlastic)
		end
	end
	return m
end

local function itemPrompt(m: Model, it: Item)
	local def = KINDS[it.k]
	local cf, size = m:GetBoundingBox()
	local p = Instance.new("Part")
	p.Name = "Pick"
	p.Size = size + Vector3.new(0.6, 0.6, 0.6)
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p:SetAttribute("Station", "waste_item")
	p:SetAttribute("Waste", it.u)
	p:SetAttribute("PromptDe", "Aufheben")
	p:SetAttribute("PromptEn", "Pick up")
	p:SetAttribute("PromptObj", def.icon .. " " .. def.de)
	p:SetAttribute("PromptHold", 0.25)
	p:SetAttribute("PromptDist", 7)
	p.Parent = m
	CollectionService:AddTag(p, "Station")
end

local function render()
	local w = state()
	if not folder or not w then
		for u, m in pairs(itemModels) do
			m:Destroy()
			itemModels[u] = nil
		end
		return
	end
	local keep = {}
	for _, it in ipairs(w.items) do
		if KINDS[it.k] and not isCarried(it.u) then
			keep[it.u] = true
			if not itemModels[it.u] then
				local m = buildItem(it.k, CFrame.new(it.x, it.y, it.z))
				itemPrompt(m, it)
				m.Parent = folder
				itemModels[it.u] = m
			end
		end
	end
	for u, m in pairs(itemModels) do
		if not keep[u] then
			m:Destroy()
			itemModels[u] = nil
		end
	end
end

---------------------------------------------------------------------------
-- spawning waste
---------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function floorAt(pos: Vector3): Vector3?
	local exclude: { Instance } = {}
	for _, n in ipairs({ "Customers", "Pedestrians", "Staff", "HandItems" }) do
		local x = workspace:FindFirstChild(n)
		if x then
			table.insert(exclude, x)
		end
	end
	if folder then
		table.insert(exclude, folder)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -10, 0), rayParams)
	return hit and hit.Position or nil
end

local kitchenAdd: (number) -> ()

-- put a waste object on the floor near `pos` (tries a few spots so it never lands on a counter)
function WasteService.Spawn(kind: string, pos: Vector3, reason: string?): boolean
	local w = state()
	if not w or not KINDS[kind] or not folder then
		return false
	end
	if #w.items >= W.MaxItems then
		if kind ~= "bag" then
			kitchenAdd(1) -- the kitchen bin takes it; no endless piles
		end
		return false
	end
	-- sample a ring of spots and keep one on the lowest surface (the floor, not a counter top)
	local hits: { Vector3 } = {}
	for i = 0, 8 do
		local ang = i * 2.4
		local r = i == 0 and 0 or 1.2 + i * 0.25
		local p = floorAt(pos + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r))
		if p then
			table.insert(hits, p)
		end
	end
	if #hits == 0 then
		return false
	end
	local low = math.huge
	for _, p in ipairs(hits) do
		low = math.min(low, p.Y)
	end
	local spot = hits[1]
	for _, p in ipairs(hits) do
		if p.Y < low + 0.3 then
			spot = p
			break
		end
	end
	local u = w.nextU
	w.nextU += 1
	table.insert(w.items, { u = u, k = kind, x = math.floor(spot.X * 100) / 100, y = math.floor(spot.Y * 100) / 100 + 0.02, z = math.floor(spot.Z * 100) / 100 })
	dirty()
	render()
	RestaurantService.PushShop()
	if reason == "kitchen" then
		local def = KINDS[kind]
		Net.NotifyAll("n_waste_new", { icon = def.icon, item = { de = def.de, en = def.en } }, "info")
	end
	return true
end

-- the kitchen bin (station "trash"): when it is full a tied bag appears next to it
local function kitchenBinPos(): Vector3?
	for _, s in ipairs(CollectionService:GetTagged("Station")) do
		if s:GetAttribute("Station") == "trash" and s:IsA("BasePart") then
			return s.Position
		end
	end
	return nil
end

kitchenAdd = function(n: number)
	local w = state()
	if not w then
		return
	end
	w.kitchen += n
	if w.kitchen >= W.KitchenCap then
		w.kitchen = 0
		local p = kitchenBinPos()
		if p then
			WasteService.Spawn("bag", p, "kitchen")
		end
	end
	dirty()
end
WasteService.KitchenAdd = kitchenAdd

---------------------------------------------------------------------------
-- containers
---------------------------------------------------------------------------
local function binCF(bin: string): CFrame
	return CFrame.new(BIN_X, BIN_Y, BINS[bin].z)
end

local function updateLabel(bin: string)
	local b = binModels[bin]
	local w = state()
	if not b or not w then
		return
	end
	local fill, cap = w.bins[bin], WasteService.Capacity(bin)
	b.model:SetAttribute("Fill", fill)
	b.model:SetAttribute("Cap", cap)
	if b.bar then
		b.bar.Size = UDim2.fromScale(math.clamp(fill / cap, 0, 1), 1)
		b.bar.BackgroundColor3 = fill >= cap and Color3.fromRGB(220, 60, 50) or (fill / cap > 0.7 and Color3.fromRGB(240, 160, 40) or Color3.fromRGB(80, 200, 110))
	end
	if b.label then
		b.label.Text = fill >= cap and string.format("VOLL · FULL  %d/%d", fill, cap) or string.format("%d / %d", fill, cap)
	end
	b.part:SetAttribute("PromptObj", string.format("%s  %d/%d", BINS[bin].short.de, fill, cap))
end

local function buildBin(bin: string): Model
	local def = BINS[bin]
	local cf = binCF(bin)
	local m = Instance.new("Model")
	m.Name = "Bin_" .. bin
	local function mesh(name: string, color: Color3): BasePart?
		local t = template(name)
		if not t then
			return nil
		end
		local p = t:Clone()
		p.Size = BIN_MESH[name][2]
		p.CFrame = cf * CFrame.new(BIN_MESH[name][1])
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = name == "BinBody"
		p.Parent = m
		return p
	end
	local body = mesh("BinBody", def.color)
	if body then
		mesh("BinCastors", Color3.fromRGB(25, 25, 25))
	else
		local b = bit(m, "BinBody", Vector3.new(2.2, 2.85, 3.4), cf * CFrame.new(0, 1.85, 0), def.color)
		b.CanCollide = true
		bit(m, "Rim", Vector3.new(2.36, 0.18, 3.56), cf * CFrame.new(0, 3.18, 0), def.color)
		for _, x in ipairs({ -0.65, 0.65 }) do
			for _, z in ipairs({ -1.25, 1.25 }) do
				bit(m, "Castor", Vector3.new(0.16, 0.38, 0.38), cf * CFrame.new(x, 0.19, z) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			end
		end
	end
	-- lid: its own model so Client/Doors can swing it around the hinge at the back
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	local leaf
	local lt = template("BinLid")
	if lt then
		leaf = lt:Clone()
		leaf.Size = BIN_MESH.BinLid[2]
		leaf.CFrame = cf * CFrame.new(BIN_MESH.BinLid[1])
		leaf.Color = def.color:Lerp(Color3.new(0, 0, 0), 0.12)
		leaf.Material = Enum.Material.SmoothPlastic
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.CanQuery = false
		leaf.Parent = lid
	else
		leaf = bit(lid, "Leaf", Vector3.new(2.5, 0.22, 3.62), cf * CFrame.new(0.05, 3.38, 0), def.color:Lerp(Color3.new(0, 0, 0), 0.12))
	end
	leaf.Name = "Leaf"
	lid:SetAttribute("Hinge", cf * LID_HINGE)
	lid:SetAttribute("OpenAngle", 100)
	lid:SetAttribute("Open", false)
	lid.Parent = m
	CollectionService:AddTag(lid, "SwingDoor")
	-- label with the fill level on the front
	local plate = bit(m, "Label", Vector3.new(0.05, 1.3, 2.4), cf * CFrame.new(1.13, 2.15, 0), Color3.fromRGB(250, 250, 248))
	plate.Transparency = 1
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 60
	sg.LightInfluence = 0.3
	sg.Parent = plate
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(250, 250, 246)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 10)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0.42, 0)
	title.Position = UDim2.fromOffset(8, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = def.color:Lerp(Color3.new(0, 0, 0), 0.25)
	title.Text = string.upper(def.short.de) .. " · " .. string.upper(def.short.en)
	title.Parent = bg
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -24, 0.16, 0)
	barBg.Position = UDim2.new(0, 12, 0.5, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(210, 210, 206)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0, 1)
	bar.Parent = barBg
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local count = Instance.new("TextLabel")
	count.Size = UDim2.new(1, -16, 0.26, 0)
	count.Position = UDim2.new(0, 8, 0.7, 0)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBold
	count.TextScaled = true
	count.TextColor3 = Color3.fromRGB(60, 60, 64)
	count.Parent = bg
	-- interaction volume in front of the container
	local hit = Instance.new("Part")
	hit.Name = "Throw"
	hit.Size = Vector3.new(3.2, 4, 3.8)
	hit.CFrame = cf * CFrame.new(0.4, 2, 0)
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanTouch = false
	hit:SetAttribute("Station", "waste_bin")
	hit:SetAttribute("Bin", bin)
	hit:SetAttribute("PromptDe", "Einwerfen")
	hit:SetAttribute("PromptEn", "Throw in")
	hit:SetAttribute("PromptHold", 0.3)
	hit:SetAttribute("PromptDist", 8)
	hit.Parent = m
	CollectionService:AddTag(hit, "Station")
	m:SetAttribute("Bin", bin)
	m.Parent = binFolder
	binModels[bin] = { model = m, lid = lid, label = count, bar = bar, part = hit }
	updateLabel(bin)
	return m
end

local lidTokens: { [string]: number } = {}
local function openLid(bin: string, secs: number)
	local b = binModels[bin]
	if not b then
		return
	end
	lidTokens[bin] = (lidTokens[bin] or 0) + 1
	local token = lidTokens[bin]
	if not b.lid:GetAttribute("Open") then
		b.lid:SetAttribute("Open", true)
		Net.Sound(nil, "door_open", b.part.Position)
	end
	task.delay(secs, function()
		if lidTokens[bin] == token then
			b.lid:SetAttribute("Open", false)
			Net.Sound(nil, "door_close", b.part.Position)
		end
	end)
end

-- the carried model flies in an arc into the open container, then disappears
local function throwInto(model: Model, bin: string)
	local b = binModels[bin]
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			for _, w in ipairs(p:GetChildren()) do
				if w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			p.Anchored = true
		end
	end
	model.Parent = folder or workspace
	local target = binCF(bin) * CFrame.new(0, 2.4, 0)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if b and primary then
		local from = primary.CFrame
		local up = CFrame.new((from.Position + target.Position) / 2 + Vector3.new(0, 2.2, 0)) * (from - from.Position)
		local function moveAll(to: CFrame, t: number, style: Enum.EasingStyle, dir: Enum.EasingDirection)
			local rel = to * primary.CFrame:Inverse()
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					TweenService:Create(p, TweenInfo.new(t, style, dir), { CFrame = rel * p.CFrame }):Play()
				end
			end
		end
		task.spawn(function()
			moveAll(up, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.wait(0.22)
			moveAll(target * CFrame.Angles(0.8, 0.3, 0), 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.27)
			Net.Sound(nil, "wrap", target.Position)
			model:Destroy()
		end)
	else
		model:Destroy()
	end
end

---------------------------------------------------------------------------
-- carrying
---------------------------------------------------------------------------
local function detach(player: Player): Model?
	local c = carried[player]
	if not c then
		return nil
	end
	carried[player] = nil
	player:SetAttribute("Carry", nil)
	player:SetAttribute("CarrySpeed", nil)
	return c.model
end

local function weldTo(model: Model, root: BasePart)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			p.CanQuery = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
end

local function pick(player: Player, part: BasePart)
	if player:GetAttribute("Carry") or carried[player] then
		Net.Notify(player, "n_hands_full", nil, "warn")
		return
	end
	if player:GetAttribute("Tray") then
		Net.Notify(player, "n_waste_tray", nil, "warn")
		return
	end
	local it = findItem(part:GetAttribute("Waste"))
	if not it or isCarried(it.u) then
		return
	end
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not torso then
		return
	end
	local m = buildItem(it.k, torso.CFrame * CFrame.new(0, -1.2, -1.35))
	weldTo(m, torso)
	m.Name = "CarriedWaste_" .. player.UserId
	m.Parent = folder
	carried[player] = { u = it.u, model = m }
	claims[it.u] = nil
	player:SetAttribute("Carry", "waste:" .. it.k)
	player:SetAttribute("CarrySpeed", KINDS[it.k].speed)
	Net.Sound(player, "click")
	render()
end

local function dispose(player: Player, part: BasePart)
	local bin = part:GetAttribute("Bin")
	local c = carried[player]
	if not c then
		if player:GetAttribute("Carry") then
			Net.Notify(player, "n_waste_not_trash", nil, "warn")
		else
			local w = state()
			if w and BINS[bin] then
				Net.Notify(player, "n_waste_bin_info", { bin = { de = BINS[bin].de, en = BINS[bin].en }, fill = w.bins[bin], cap = WasteService.Capacity(bin) }, "info")
			end
		end
		return
	end
	local it, i = findItem(c.u)
	local w = state()
	if not it or not w or not BINS[bin] then
		detach(player)
		if c.model then
			c.model:Destroy()
		end
		render()
		return
	end
	local def = KINDS[it.k]
	if def.bin ~= bin then
		Net.Notify(player, "n_waste_wrong_bin", { item = { de = def.de, en = def.en }, bin = { de = BINS[def.bin].de, en = BINS[def.bin].en } }, "warn")
		Net.Sound(player, "fail")
		return
	end
	if w.bins[bin] >= WasteService.Capacity(bin) then
		Net.Notify(player, "n_waste_bin_full", { bin = { de = BINS[bin].de, en = BINS[bin].en } }, "warn")
		Net.Sound(player, "fail")
		return
	end
	-- success: only now the item leaves the hands
	table.remove(w.items, i :: number)
	w.bins[bin] += 1
	local model = detach(player)
	openLid(bin, 1.6)
	player:SetAttribute("HandAct", "throw")
	player:SetAttribute("HandT", workspace:GetServerTimeNow())
	if model then
		task.delay(0.25, throwInto, model, bin)
	end
	EconomyService.AddXP(player, 2)
	EconomyService.AddStat(player, "cleaned", 1)
	Net.Notify(player, "n_waste_done", { icon = def.icon, bin = { de = BINS[bin].de, en = BINS[bin].en } }, "success")
	if w.bins[bin] >= WasteService.Capacity(bin) then
		Net.NotifyAll("n_waste_bin_now_full", { bin = { de = BINS[bin].de, en = BINS[bin].en } }, "warn")
	end
	updateLabel(bin)
	dirty()
	render()
	RestaurantService.PushShop()
end

-- drop the carried item where the player stands (death, leaving, logistics needing the hands)
local function dropCarried(player: Player, keepSpot: boolean?)
	local c = carried[player]
	if not c then
		return
	end
	local model = detach(player)
	if model then
		model:Destroy()
	end
	local it = findItem(c.u)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if it and root and not keepSpot then
		local p = floorAt(root.Position + root.CFrame.LookVector * 1.5)
		if p then
			it.x, it.y, it.z = p.X, p.Y + 0.02, p.Z
		end
	end
	dirty()
	render()
end
WasteService.Drop = dropCarried

---------------------------------------------------------------------------
-- garbage collection (#14)
---------------------------------------------------------------------------
local function callTruck(player: Player)
	local w = state()
	if not w then
		return
	end
	if GarbageTruckService.Busy() then
		Net.Notify(player, "n_waste_truck_busy", nil, "warn")
		return
	end
	local total = 0
	for _, b in ipairs(BIN_ORDER) do
		total += w.bins[b]
	end
	if total == 0 then
		Net.Notify(player, "n_waste_bins_empty", nil, "info")
		return
	end
	if not EconomyService.Spend(player, W.CollectionPrice) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return
	end
	EconomyService.Push(player)
	Net.NotifyAll("n_waste_truck_called", { name = player.DisplayName, price = W.CollectionPrice }, "info")
	if callPart then
		callPart:SetAttribute("PromptOn", false)
	end
	local stops = {}
	for _, bin in ipairs(BIN_ORDER) do
		if w.bins[bin] > 0 then
			table.insert(stops, {
				stand = (binCF(bin) * CFrame.new(2.6, 3, 0)).Position,
				take = function(): Model?
					openLid(bin, 2.2)
					local m = buildItem("bag", binCF(bin) * CFrame.new(1.6, 1.2, 0))
					m.Parent = folder
					return m
				end,
				taken = function()
					local s = state()
					if s then
						s.bins[bin] = 0
						updateLabel(bin)
						dirty()
						RestaurantService.PushShop()
					end
				end,
			})
		end
	end
	task.spawn(function()
		local ok, err = pcall(GarbageTruckService.Run, stops)
		if not ok then
			warn("[WasteService] garbage truck:", err)
		end
		if callPart then
			callPart:SetAttribute("PromptOn", true)
		end
		Net.NotifyAll("n_waste_collected", nil, "success")
	end)
end

local function buildCallPoint()
	if not binFolder then
		return
	end
	local m = Instance.new("Model")
	m.Name = "CollectionCall"
	local base = CFrame.new(CALL_POS)
	bit(m, "Post", Vector3.new(0.25, 4.6, 0.25), base * CFrame.new(0, 2.3, 0), Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
	local sign = bit(m, "Sign", Vector3.new(1.8, 1.4, 0.12), base * CFrame.new(0, 4.2, 0), Color3.fromRGB(240, 110, 20), Enum.Material.SmoothPlastic)
	bit(m, "Button", Vector3.new(0.4, 0.4, 0.2), base * CFrame.new(0, 3.2, 0.05), Color3.fromRGB(220, 40, 30), Enum.Material.Neon)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 60
		sg.Parent = sign
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Text = "🚛 MÜLLABFUHR\nWASTE PICKUP"
		t.Parent = sg
	end
	local hit = Instance.new("Part")
	hit.Name = "Call"
	hit.Size = Vector3.new(2.4, 4.6, 2.4)
	hit.CFrame = base * CFrame.new(0, 2.6, 0)
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanTouch = false
	hit:SetAttribute("Station", "waste_call")
	hit:SetAttribute("PromptDe", string.format("Müllabfuhr rufen (€%d)", W.CollectionPrice))
	hit:SetAttribute("PromptEn", string.format("Call waste pickup (€%d)", W.CollectionPrice))
	hit:SetAttribute("PromptObj", "🚛")
	hit:SetAttribute("PromptHold", 0.8)
	hit:SetAttribute("PromptDist", 8)
	hit.Parent = m
	CollectionService:AddTag(hit, "Station")
	callPart = hit
	m.Parent = binFolder
end

---------------------------------------------------------------------------
-- cleaners (Server/EmployeeService)
---------------------------------------------------------------------------
-- nearest waste object nobody is carrying or fetching whose container still has room
function WasteService.ClaimForWorker(from: Vector3): (number?, Vector3?)
	local w = state()
	if not w then
		return nil, nil
	end
	local best, bestD, bestPos = nil, math.huge, nil
	for _, it in ipairs(w.items) do
		local def = KINDS[it.k]
		if def and not isCarried(it.u) and (not claims[it.u] or os.clock() - claims[it.u] > 40) and w.bins[def.bin] < WasteService.Capacity(def.bin) then
			local p = Vector3.new(it.x, it.y, it.z)
			local d = (p - from).Magnitude
			if d < bestD then
				best, bestD, bestPos = it.u, d, p
			end
		end
	end
	if best then
		claims[best] = os.clock()
	end
	return best, bestPos
end

function WasteService.WorkerPick(u: number, root: BasePart): string?
	local it = findItem(u)
	if not it or isCarried(u) then
		return nil
	end
	local m = buildItem(it.k, root.CFrame * CFrame.new(0, -1.2, -1.35))
	weldTo(m, root)
	m.Parent = folder
	workerCarry[u] = m
	render()
	return KINDS[it.k].bin
end

function WasteService.BinStand(bin: string): Vector3
	return (binCF(bin) * CFrame.new(2.6, 3, 0)).Position
end

function WasteService.WorkerDispose(u: number): boolean
	local it, i = findItem(u)
	local w = state()
	local m = workerCarry[u]
	workerCarry[u] = nil
	claims[u] = nil
	if not it or not w then
		if m then
			m:Destroy()
		end
		render()
		return false
	end
	local bin = KINDS[it.k].bin
	if w.bins[bin] >= WasteService.Capacity(bin) then
		if m then
			m:Destroy()
		end
		render() -- stays on the floor where it was
		return false
	end
	table.remove(w.items, i :: number)
	w.bins[bin] += 1
	openLid(bin, 1.6)
	if m then
		task.delay(0.2, throwInto, m, bin)
	end
	updateLabel(bin)
	dirty()
	render()
	RestaurantService.PushShop()
	return true
end

-- the cleaner gave up (path blocked …): the item goes back where it was
function WasteService.WorkerAbort(u: number)
	local m = workerCarry[u]
	workerCarry[u] = nil
	claims[u] = nil
	if m then
		m:Destroy()
	end
	render()
end

---------------------------------------------------------------------------
-- cleanliness + client state
---------------------------------------------------------------------------
local function inside(it: Item): boolean
	-- the restaurant's back wall (the storage annex x[11,31] reaches to z -27); south of it is the backyard
	return it.z > ((it.x > 11 and it.x < 31) and -27 or -21)
end

function WasteService.Penalty(): number
	local w = state()
	if not w then
		return 0
	end
	local pen = 0
	for _, it in ipairs(w.items) do
		pen += inside(it) and W.PenaltyInside or W.PenaltyOutside
	end
	for _, b in ipairs(BIN_ORDER) do
		if w.bins[b] >= WasteService.Capacity(b) then
			pen += W.PenaltyFullBin
		end
	end
	return math.min(W.PenaltyMax, pen)
end

local function provide(_player: Player, st)
	local w = state()
	if not w then
		return
	end
	local bins = {}
	for _, b in ipairs(BIN_ORDER) do
		bins[b] = { fill = w.bins[b], cap = WasteService.Capacity(b) }
	end
	local inside_, outside_ = 0, 0
	for _, it in ipairs(w.items) do
		if inside(it) then
			inside_ += 1
		else
			outside_ += 1
		end
	end
	st.waste = { bins = bins, inside = inside_, outside = outside_, kitchen = w.kitchen, kitchenCap = W.KitchenCap, truck = GarbageTruckService.Busy() }
	st.clean = BusinessService.Cleanliness()
end

---------------------------------------------------------------------------
-- hooks into the kitchen actions
---------------------------------------------------------------------------
local function actionSig(player: Player, kind: string, part: BasePart): string?
	if kind == "veg" or kind == "board" or kind == "trash" then
		local s = FoodPreparationService.GetState(player)
		local ok, json = pcall(HttpService.JSONEncode, HttpService, { s.meal, #s.tray })
		return ok and json or nil
	elseif kind == "fresh" then
		return tostring((BusinessService.Fresh() or {})[part:GetAttribute("Item")])
	end
	return nil
end

local function onAction(player: Player, part: BasePart, kind: string)
	local w = state()
	if not w then
		return
	end
	if kind == "veg" or kind == "fresh" then
		w.org += kind == "fresh" and 2 or 1
		if w.org >= w.orgAt then
			w.org = 0
			w.orgAt = rng:NextInteger(W.ScrapsEvery[1], W.ScrapsEvery[2])
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			WasteService.Spawn("scraps", root and (root.Position + root.CFrame.LookVector * -1.2) or part.Position, "prep")
		end
	elseif kind == "board" then
		local s = FoodPreparationService.GetState(player)
		if s.meal and s.meal.closed then
			w.pla += 1
			if w.pla >= w.plaAt then
				w.pla = 0
				w.plaAt = rng:NextInteger(W.PackagingEvery[1], W.PackagingEvery[2])
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				WasteService.Spawn("packaging", root and (root.Position + root.CFrame.LookVector * -1.2) or part.Position, "pack")
			end
		end
	elseif kind == "trash" then
		kitchenAdd(1)
	end
	dirty()
end

local function interactHook(prev: ((Player, BasePart, string) -> boolean)?)
	return function(player: Player, part: BasePart, kind: string): boolean
		if kind == "waste_bin" then
			dispose(player, part)
			return true
		elseif kind == "waste_call" then
			if carried[player] then
				Net.Notify(player, "n_waste_hands", nil, "warn")
			else
				callTruck(player)
			end
			return true
		elseif kind == "waste_item" then
			pick(player, part)
			return true
		end
		if carried[player] and kind ~= "backdoor" then
			Net.Notify(player, "n_waste_hands", nil, "warn")
			return true
		end
		return prev ~= nil and prev(player, part, kind)
	end
end

---------------------------------------------------------------------------
-- world + init
---------------------------------------------------------------------------
local function buildWorld()
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return
	end
	folder = r:FindFirstChild("Waste") :: Folder?
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Waste"
		f.Parent = r
		folder = f
	end
	local yard = r:FindFirstChild("Backyard") or r
	local bf = Instance.new("Folder")
	bf.Name = "WasteBins"
	bf.Parent = yard
	binFolder = bf
	for _, b in ipairs(BIN_ORDER) do
		local ok, err = pcall(buildBin, b)
		if not ok then
			warn("[WasteService] bin", b, err)
		end
	end
	local ok, err = pcall(buildCallPoint)
	if not ok then
		warn("[WasteService] call point", err)
	end
end

local function refreshAll()
	for _, b in ipairs(BIN_ORDER) do
		updateLabel(b)
	end
	render()
end
WasteService.Refresh = refreshAll

function WasteService.Init()
	buildWorld()
	-- interactions: our stations first, then logistics (boxes) and the kitchen
	FoodPreparationService.InteractHook = interactHook(FoodPreparationService.InteractHook)
	-- count kitchen actions: a signature before / after each action tells whether it did something
	local sigs: { [Player]: { kind: string, sig: string } } = {}
	local hook = FoodPreparationService.InteractHook
	FoodPreparationService.InteractHook = function(player: Player, part: BasePart, kind: string): boolean
		local handled = hook(player, part, kind)
		if not handled then
			local sig = actionSig(player, kind, part)
			if sig then
				sigs[player] = { kind = kind, sig = sig }
				task.defer(function()
					local before = sigs[player]
					sigs[player] = nil
					if before and before.kind == kind and actionSig(player, kind, part) ~= before.sig then
						onAction(player, part, kind)
					end
				end)
			end
		end
		return handled
	end
	-- emptied delivery boxes become cardboard waste
	LogisticsService.EmptyBoxHook = function(player: Player, _box: any, at: Vector3)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		WasteService.Spawn("cardboard", root and (root.Position + root.CFrame.LookVector * -1.5) or at, "box")
	end
	-- logistics: picking up a box with waste in the hands is not allowed (checked there)
	LogisticsService.HandsBusyHook = function(player: Player): boolean
		return carried[player] ~= nil
	end
	-- wiping customer trash fills the kitchen bin
	BusinessService.CleanHook = function(part: BasePart)
		if part:GetAttribute("DirtKind") == "trash" then
			kitchenAdd(0.5)
		end
	end
	BusinessService.WastePenaltyHook = WasteService.Penalty
	EconomyService.AddStateProvider(provide)
	table.insert(RestaurantService.WorldUpgradeHooks, function()
		refreshAll()
	end)
	RestaurantService.OwnerChanged:Connect(function()
		for p in pairs(carried) do
			dropCarried(p, true)
		end
		refreshAll()
	end)
	Players.PlayerRemoving:Connect(function(p)
		dropCarried(p, true) -- item stays saved at its floor spot
	end)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			dropCarried(p, true)
		end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function()
			dropCarried(p, true)
		end)
	end
	refreshAll()
end

-- Studio playtests (Main's KebapDebug "waste")
function WasteService.Debug(cmd: string?, arg: any)
	local w = state()
	if cmd == "spawn" and w then
		local p = Players:GetPlayers()[1]
		local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return WasteService.Spawn(arg or "bag", root and root.Position + Vector3.new(0, 0, -3) or Vector3.new(0, 3, -12))
	elseif cmd == "fill" and w then
		for _, b in ipairs(BIN_ORDER) do
			w.bins[b] = math.min(WasteService.Capacity(b), tonumber(arg) or WasteService.Capacity(b))
		end
		refreshAll()
		return true
	end
	return w and { bins = w.bins, items = #w.items, kitchen = w.kitchen, penalty = WasteService.Penalty(), clean = BusinessService.Cleanliness(), truck = GarbageTruckService.Busy() }
end

return WasteService
