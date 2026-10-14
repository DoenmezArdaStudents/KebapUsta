-- Buying unlocks (ingredients, dishes, equipment, knives) and getting them physically into the shop.
--
-- Flow (all server-authoritative):
--   1. Laptop "Shop-Ausbau" → Request "BuyUnlock" (owner only, level + requirements + cash checked).
--   2. Items that need installing become "delivered": after a short delivery time a cardboard crate
--      drops onto the spot where the equipment will stand (doorbell + bounce).
--   3. Any player holds the prompt on the crate ("Auspacken & einbauen") → state "owned", the crate
--      opens and the equipment builds itself in place piece by piece.
--   4. New ingredients still have 0 stock: customers only start ordering them after the first restock
--      (RestaurantService.AddStock marks data.stocked).
-- Equipment in the world is tagged "Unlockable" with attribute Unlock = <unlock id> (WorldBuilder);
-- everything not owned is kept in ServerStorage so it can neither be seen nor used.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Progression = require(Shared.Progression)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RestaurantService = require(script.Parent.RestaurantService)
local FoodPreparationService = require(script.Parent.FoodPreparationService)

local UnlockService = {}
UnlockService.OnChanged = nil :: ((string) -> ())?

local DELIVERY_SECONDS = 6

local hidden = ServerStorage:FindFirstChild("HiddenUnlocks") or Instance.new("Folder")
hidden.Name = "HiddenUnlocks"
hidden.Parent = ServerStorage

type Home = { parent: Instance, parts: { { part: BasePart, cf: CFrame, t: number, fixed: boolean } } }
local homes: { [Instance]: Home } = {}
local groups: { [string]: { Instance } } = {}
local spots: { [string]: { cf: CFrame, size: Vector3 } } = {}
local crates: { [string]: Model } = {}
local arriving: { [string]: number } = {} -- id -> os.clock() when the crate may appear
local installing: { [string]: boolean } = {}

local function restaurant(): Instance?
	return workspace:FindFirstChild("Restaurant")
end

local function partsOf(inst: Instance): { BasePart }
	local list = {}
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- world-axis bounding box over the solid parts of several instances (labels, glass and other
-- non-colliding details are ignored so the crate sits on the counter, not inside it)
local function bounds(insts: { Instance }, solidOnly: boolean?): (CFrame, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, inst in ipairs(insts) do
		for _, p in ipairs(partsOf(inst)) do
			if p.Transparency < 1 and (p.CanCollide or solidOnly == false) then
				local h = p.Size / 2
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local w = p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
							minV = minV:Min(w)
							maxV = maxV:Max(w)
						end
					end
				end
			end
		end
	end
	if minV.X == math.huge then
		if solidOnly == false then
			return CFrame.new(), Vector3.one
		end
		return bounds(insts, false)
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end

local function scan()
	local r = restaurant()
	for _, inst in ipairs(CollectionService:GetTagged("Unlockable")) do
		local id = inst:GetAttribute("Unlock")
		if type(id) == "string" and not homes[inst] and r and inst:IsDescendantOf(r) then
			local home: Home = { parent = inst.Parent :: Instance, parts = {} }
			for _, p in ipairs(partsOf(inst)) do
				-- spit meat is rotated by the clients: it must replicate at its final position
				local fixed = false
				local a = p.Parent
				while a and a ~= inst.Parent do
					if CollectionService:HasTag(a, "SpitRotor") then
						fixed = true
					end
					a = a.Parent
				end
				table.insert(home.parts, { part = p, cf = p.CFrame, t = p.Transparency, fixed = fixed })
			end
			homes[inst] = home
			groups[id] = groups[id] or {}
			table.insert(groups[id], inst)
		end
	end
	for id, list in pairs(groups) do
		if not spots[id] then
			local cf, size = bounds(list)
			spots[id] = { cf = cf, size = size }
		end
	end
end

---------------------------------------------------------------------------
-- Crates
---------------------------------------------------------------------------
local CARDBOARD = Color3.fromRGB(181, 140, 92)
local TAPE = Color3.fromRGB(214, 186, 130)

local function cardboardMaterial(): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any).Cardboard
	end)
	return ok and m or Enum.Material.Fabric
end

local function cratesFolder(): Instance?
	local r = restaurant()
	if not r then
		return nil
	end
	local f = r:FindFirstChild("Crates")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Crates"
		f.Parent = r
	end
	return f
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function makeCrate(id: string, drop: boolean)
	local u = Progression.ById[id]
	local spot = spots[id]
	local parent = cratesFolder()
	if not u or not spot or not parent or crates[id] then
		return
	end
	local s = spot.size
	local size = Vector3.new(math.clamp(s.X * 0.8, 1.0, 4.2), math.clamp(s.Y * 0.6, 0.9, 3), math.clamp(s.Z * 0.8, 1.0, 3.2))
	local bottom = spot.cf.Position.Y - s.Y / 2
	local target = CFrame.new(spot.cf.Position.X, bottom + size.Y / 2 + 0.02, spot.cf.Position.Z) * CFrame.Angles(0, math.rad(math.random(-8, 8)), 0)
	local model = Instance.new("Model")
	model.Name = "Crate_" .. id
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Size = size
	box.Color = CARDBOARD
	box.Material = cardboardMaterial()
	box.Anchored = true
	box.CanCollide = true
	box.TopSurface = Enum.SurfaceType.Smooth
	box.BottomSurface = Enum.SurfaceType.Smooth
	box.CFrame = drop and (target + Vector3.new(0, 6, 0)) or target
	box.Parent = model
	-- packing tape across the top and down the front/back
	local function strip(name: string, sz: Vector3, offset: CFrame)
		local t = Instance.new("Part")
		t.Name = name
		t.Size = sz
		t.Color = TAPE
		t.Material = Enum.Material.SmoothPlastic
		t.Reflectance = 0.1
		t.Anchored = false
		t.CanCollide = false
		t.Massless = true
		t.CFrame = box.CFrame * offset
		t.Parent = model
		weld(box, t)
		return t
	end
	strip("TapeTop", Vector3.new(0.35, 0.03, size.Z + 0.02), CFrame.new(0, size.Y / 2 + 0.01, 0))
	strip("TapeFront", Vector3.new(0.35, size.Y * 0.4, 0.03), CFrame.new(0, size.Y * 0.3, -size.Z / 2 - 0.01))
	strip("TapeBack", Vector3.new(0.35, size.Y * 0.4, 0.03), CFrame.new(0, size.Y * 0.3, size.Z / 2 + 0.01))
	-- shipping labels on both long sides
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 60
		sg.LightInfluence = 0.6
		sg.Parent = box
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.62)
		holder.Size = UDim2.fromScale(0.7, 0.42)
		holder.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
		holder.Parent = sg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.08, 0)
		corner.Parent = holder
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = Color3.fromRGB(40, 36, 30)
		t.Text = u.icon .. " " .. string.upper(u.name.de)
		t.Parent = holder
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.06, 0)
		pad.PaddingRight = UDim.new(0.06, 0)
		pad.PaddingTop = UDim.new(0.1, 0)
		pad.PaddingBottom = UDim.new(0.1, 0)
		pad.Parent = t
		local arrow = Instance.new("TextLabel")
		arrow.BackgroundTransparency = 1
		arrow.Position = UDim2.fromScale(0.05, 0.04)
		arrow.Size = UDim2.fromScale(0.3, 0.25)
		arrow.TextScaled = true
		arrow.Font = Enum.Font.GothamBold
		arrow.TextColor3 = Color3.fromRGB(70, 50, 30)
		arrow.TextXAlignment = Enum.TextXAlignment.Left
		arrow.Text = "↑↑"
		arrow.Parent = sg
	end
	box:SetAttribute("Station", "crate")
	box:SetAttribute("Item", id)
	model.PrimaryPart = box
	model.Parent = parent
	CollectionService:AddTag(box, "Station")
	crates[id] = model
	if drop then
		TweenService:Create(box, TweenInfo.new(0.9, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = target }):Play()
		Net.Sound(nil, "doorbell", target.Position)
		task.delay(0.35, function()
			Net.Sound(nil, "wrap", target.Position)
		end)
	end
end

local function removeCrate(id: string, animate: boolean)
	local m = crates[id]
	crates[id] = nil
	if not m then
		return
	end
	local box = m:FindFirstChild("Box") :: BasePart?
	if box then
		box:SetAttribute("Station", nil)
		CollectionService:RemoveTag(box, "Station")
	end
	if not animate or not box then
		m:Destroy()
		return
	end
	-- flaps pop open, the box sinks and fades away
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		elseif p:IsA("SurfaceGui") then
			p.Enabled = false
		end
	end
	local b = box :: BasePart
	TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = b.Size * Vector3.new(1.15, 0.2, 1.15), CFrame = b.CFrame - Vector3.new(0, b.Size.Y * 0.4, 0) }):Play()
	task.delay(0.6, function()
		m:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Equipment visibility
---------------------------------------------------------------------------
local function show(inst: Instance, animate: boolean)
	local home = homes[inst]
	if not home or inst.Parent == home.parent then
		return
	end
	if animate then
		for _, e in ipairs(home.parts) do
			e.part.Transparency = 1
			e.part.CFrame = e.fixed and e.cf or (e.cf + Vector3.new(0, 1.2, 0))
		end
	else
		for _, e in ipairs(home.parts) do
			e.part.Transparency = e.t
			e.part.CFrame = e.cf
		end
	end
	inst.Parent = home.parent
	if animate then
		for i, e in ipairs(home.parts) do
			task.delay(0.15 + math.min(i, 30) * 0.035, function()
				TweenService:Create(e.part, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = e.cf, Transparency = e.t }):Play()
			end)
		end
	end
end

local function hide(inst: Instance)
	local home = homes[inst]
	if home and inst.Parent ~= hidden then
		inst.Parent = hidden
	end
end

function UnlockService.ApplyWorld()
	scan()
	local unlocks = RestaurantService.GetUnlocks()
	for id, list in pairs(groups) do
		local st = Progression.State(unlocks, id)
		if st == "owned" then
			if not installing[id] then
				for _, inst in ipairs(list) do
					show(inst, false)
				end
			end
			removeCrate(id, false)
		else
			for _, inst in ipairs(list) do
				hide(inst)
			end
			if st == "delivered" then
				if not crates[id] and os.clock() >= (arriving[id] or 0) then
					makeCrate(id, arriving[id] ~= nil)
					arriving[id] = nil
				end
			else
				removeCrate(id, false)
			end
		end
	end
	-- installs without a world model (e.g. only a stock item) never leave a crate behind
	for id in pairs(crates) do
		if not groups[id] or Progression.State(unlocks, id) ~= "delivered" then
			removeCrate(id, false)
		end
	end
	FoodPreparationService.PushSpits()
end

---------------------------------------------------------------------------
-- Buying & installing
---------------------------------------------------------------------------
local function ownerData()
	local o = RestaurantService.GetOwner()
	return o, o and DataService.Get(o)
end

function UnlockService.Buy(player: Player, id: any)
	if type(id) ~= "string" or not Progression.ById[id] then
		return { ok = false }
	end
	if not RestaurantService.IsOwner(player) then
		Net.Notify(player, "n_owner_only", nil, "warn")
		return { ok = false, msg = "n_owner_only" }
	end
	local data = DataService.Get(player)
	if not data then
		return { ok = false }
	end
	local u = Progression.ById[id]
	local ok, why = Progression.CanBuy(data.unlocks, id, data.level, data.cash)
	if not ok then
		local key = ({ level = "n_level_req", requires = "n_unlock_requires", cash = "n_not_enough_cash" })[why or ""] or "n_unlock_owned"
		local need = {}
		for _, r in ipairs(u.requires or {}) do
			if not Progression.Owned(data.unlocks, r) then
				table.insert(need, Progression.ById[r].name.de)
			end
		end
		Net.Notify(player, key, { level = u.level, need = table.concat(need, ", ") }, "warn")
		return { ok = false, msg = key }
	end
	if not EconomyService.Spend(player, u.price) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return { ok = false, msg = "n_not_enough_cash" }
	end
	RestaurantService.DayStats.expenses += u.price
	local needsCrate = u.install and groups[id] ~= nil
	if needsCrate then
		data.unlocks[id] = "delivered"
		arriving[id] = os.clock() + DELIVERY_SECONDS
		Net.NotifyAll("n_unlock_shipping", { name = u.name, s = DELIVERY_SECONDS }, "info")
		task.delay(DELIVERY_SECONDS + 0.1, function()
			UnlockService.ApplyWorld()
			if Progression.State(RestaurantService.GetUnlocks(), id) == "delivered" then
				Net.NotifyAll("n_unlock_arrived", { name = u.name }, "success")
			end
		end)
	else
		data.unlocks[id] = "owned"
		Net.NotifyAll(u.cat == "knife" and "n_knife_ready" or "n_unlock_ready", { name = u.name }, "success")
		Net.FireAll("Installed", id, nil)
	end
	EconomyService.AddStat(player, "unlocks", 1)
	DataService.MarkDirty(player)
	Net.Sound(player, "register")
	if UnlockService.OnChanged then
		UnlockService.OnChanged(id)
	end
	RestaurantService.UpdateBoards()
	RestaurantService.PushShop()
	EconomyService.Push(player)
	return { ok = true, state = data.unlocks[id] }
end

local function install(player: Player, part: BasePart)
	local id = part:GetAttribute("Item")
	if type(id) ~= "string" or installing[id] then
		return
	end
	local owner, data = ownerData()
	if not owner or not data or data.unlocks[id] ~= "delivered" then
		return
	end
	local u = Progression.ById[id]
	installing[id] = true
	data.unlocks[id] = "owned"
	DataService.MarkDirty(owner)
	local spot = spots[id]
	removeCrate(id, true)
	Net.FireAll("Installed", id, spot and spot.cf.Position)
	Net.Sound(nil, "levelup", spot and spot.cf.Position)
	task.delay(0.35, function()
		for _, inst in ipairs(groups[id] or {}) do
			show(inst, true)
		end
		task.delay(1.6, function()
			installing[id] = nil
			UnlockService.ApplyWorld()
		end)
	end)
	local key = (u.stock and #u.stock > 0) and "n_installed_restock" or "n_installed"
	Net.NotifyAll(key, { name = u.name, by = player.DisplayName }, "success")
	EconomyService.AddXP(player, 15)
	if UnlockService.OnChanged then
		UnlockService.OnChanged(id)
	end
	RestaurantService.UpdateBoards()
	RestaurantService.PushShop()
end

function UnlockService.Init()
	scan()
	FoodPreparationService.ExternalActions.crate = install
	Net.OnRequest("BuyUnlock", UnlockService.Buy)
	RestaurantService.OwnerChanged:Connect(function()
		arriving = {}
		UnlockService.ApplyWorld()
	end)
	UnlockService.ApplyWorld()
	Players.PlayerAdded:Connect(function()
		task.delay(2, UnlockService.ApplyWorld)
	end)
end

return UnlockService
