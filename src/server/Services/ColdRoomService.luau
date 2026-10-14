-- The walk-in cold room behind the storage. Ordered meat no longer lands on the spit by itself:
-- the supplier stores every pack as a raw kebab cone on the cold-room shelves. A cone has to rest
-- overnight (it can be taken from the next day on), then someone carries it to the matching spit
-- and puts it on ([F] at the spit). The carver employee does this on his own when a spit runs low.
-- Packs live in the owner's save (data.cold) so they survive rejoining.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local IngredientData = require(Shared.IngredientData)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local RestaurantService = require(script.Parent.RestaurantService)
local FoodPreparationService = require(script.Parent.FoodPreparationService)

local ColdRoomService = {}

type Pack = { id: string, n: number, day: number, uid: number }

local MEAT_OF = { meat_chicken = "chicken", meat_veal = "veal" }
local SPIT_X = { chicken = -24.9, veal = -18.4 }
local ENTRANCE = Vector3.new(28.2, 3.3, -15.5)
local INSIDE = Vector3.new(34.5, 3.3, -15.5)
ColdRoomService.Entrance = ENTRANCE
ColdRoomService.Inside = INSIDE

local room: Model? = nil
local door: BasePart? = nil
local doorClosedCF: CFrame? = nil
local doorOpen = false
local slots: { CFrame } = {}
local packModels: { [number]: Model } = {}
local loadParts: { [string]: BasePart } = {}
local carried: { [Player]: { pack: Pack, model: Model } } = {}
local staffCarrying: { [string]: boolean } = {}
local nextUid = 1

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------
local function ownerData()
	local o = RestaurantService.GetOwner()
	return o and DataService.Get(o), o
end

local function packs(): { Pack }
	local d = ownerData()
	if not d then
		return {}
	end
	if type(d.cold) ~= "table" then
		d.cold = {}
	end
	local clean = {}
	for _, p in ipairs(d.cold) do
		if type(p) == "table" and MEAT_OF[p.id] and type(p.n) == "number" and p.n > 0 then
			p.day = tonumber(p.day) or 0
			p.uid = p.uid or nextUid
			nextUid = math.max(nextUid, p.uid) + 1
			table.insert(clean, p)
		end
	end
	d.cold = clean
	return clean
end

local function save()
	local _, o = ownerData()
	if o then
		DataService.MarkDirty(o)
	end
end

local function ready(p: Pack): boolean
	return RestaurantService.GetDay() > p.day
end

-- portions of this stock id waiting in the cold room (counts against the storage space)
function ColdRoomService.Amount(stockId: string): number
	local n = 0
	for _, p in ipairs(packs()) do
		if p.id == stockId then
			n += p.n
		end
	end
	for _, c in pairs(carried) do
		if c.pack.id == stockId then
			n += c.pack.n
		end
	end
	return n
end

---------------------------------------------------------------------------
-- building: open up the wall, carve the room out of the neighbour block
---------------------------------------------------------------------------
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function box(parent: Instance, name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, mat: Enum.Material?, props: { [string]: any }?): Part
	return part(parent, name, Vector3.new(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1)), CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, mat, props)
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.LightInfluence = 0
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	t.BackgroundColor3 = bg or Color3.new()
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = color
	t.Text = text
	t.Parent = sg
	sg.Parent = p
end

local ICE = Color3.fromRGB(226, 238, 246)
local STEEL = Color3.fromRGB(190, 196, 202)

local function build()
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return
	end
	if r:FindFirstChild("ColdRoom") then
		room = r.ColdRoom :: Model
	else
		-- the neighbour house behind the storage gets a hollow for the room
		local street = r:FindFirstChild("Street")
		local nb = street and street:FindFirstChild("NeighbourR") :: BasePart?
		if nb and nb.Size.X > 30 then
			local col, mat = nb.Color, nb.Material
			box(street :: Instance, "NeighbourR", 41.5, 0, -22, 70, 36, 20.5, col, mat)
			box(street :: Instance, "NeighbourR_Front", 31, 0, -8.5, 41.5, 36, 20.5, col, mat)
			box(street :: Instance, "NeighbourR_Back", 31, 0, -22, 41.5, 36, -21.5, col, mat)
			box(street :: Instance, "NeighbourR_Top", 31, 10.5, -21.5, 41.5, 36, -8.5, col, mat)
			nb:Destroy()
		end
		-- a real door opening in the storage wall
		local shell = r:FindFirstChild("Shell")
		local wall = shell and shell:FindFirstChild("WallRight") :: BasePart?
		if wall and wall.Size.Z > 30 then
			local col, mat = wall.Color, wall.Material
			box(shell :: Instance, "WallRight", 30, 0, -20, 31, 14, -18.4, col, mat)
			box(shell :: Instance, "WallRight", 30, 0, -12.6, 31, 14, 20.5, col, mat)
			box(shell :: Instance, "WallRight", 30, 9.4, -18.4, 31, 14, -12.6, col, mat)
			wall:Destroy()
		end
		local storage = r:FindFirstChild("Storage")
		local fake = storage and storage:FindFirstChild("ColdRoomDoor")
		if fake then
			fake:Destroy()
		end

		local m = Instance.new("Model")
		m.Name = "ColdRoom"
		box(m, "ColdFloor", 30, -0.2, -21.5, 41.5, 0.2, -8.5, Color3.fromRGB(176, 186, 196), Enum.Material.DiamondPlate)
		box(m, "LiningE", 41.2, 0.2, -21.3, 41.5, 10.4, -8.7, ICE, Enum.Material.SmoothPlastic)
		box(m, "LiningN", 31, 0.2, -21.5, 41.5, 10.4, -21.2, ICE, Enum.Material.SmoothPlastic)
		box(m, "LiningS", 31, 0.2, -8.8, 41.5, 10.4, -8.5, ICE, Enum.Material.SmoothPlastic)
		box(m, "Ceiling", 31, 10.2, -21.5, 41.5, 10.5, -8.5, ICE, Enum.Material.SmoothPlastic)
		for z = -20.5, -9.5, 2 do
			box(m, "Rib", 41.0, 0.2, z - 0.1, 41.2, 10.2, z + 0.1, STEEL, Enum.Material.Metal, { CanCollide = false })
		end
		-- door frame + insulated door on a hinge
		box(m, "Frame", 29.6, 0.2, -18.6, 30, 9.6, -18.3, STEEL, Enum.Material.Metal)
		box(m, "Frame", 29.6, 0.2, -12.7, 30, 9.6, -12.4, STEEL, Enum.Material.Metal)
		box(m, "Frame", 29.6, 9.3, -18.6, 30, 9.6, -12.4, STEEL, Enum.Material.Metal)
		local d = box(m, "ColdDoor", 29.55, 0.25, -18.3, 29.95, 9.3, -12.7, Color3.fromRGB(205, 212, 218), Enum.Material.DiamondPlate)
		d:SetAttribute("Station", "colddoor")
		d:SetAttribute("PromptDe", "Kühlraum öffnen")
		d:SetAttribute("PromptEn", "Open cold room")
		d:SetAttribute("PromptObj", "❄️")
		d:SetAttribute("PromptDist", 8)
		CollectionService:AddTag(d, "Station")
		local handle = part(m, "Handle", Vector3.new(0.25, 1.6, 0.25), CFrame.new(29.35, 4.5, -13.4), STEEL, Enum.Material.Metal, { CanCollide = false })
		local w = Instance.new("WeldConstraint")
		w.Part0 = d
		w.Part1 = handle
		w.Parent = handle
		handle.Anchored = false
		local window = part(m, "DoorWindow", Vector3.new(0.1, 1.6, 1.4), CFrame.new(29.5, 6.4, -15.5), Color3.fromRGB(180, 220, 240), Enum.Material.Glass, { Transparency = 0.4, CanCollide = false })
		local w2 = Instance.new("WeldConstraint")
		w2.Part0 = d
		w2.Part1 = window
		w2.Parent = window
		window.Anchored = false
		-- plastic strip curtain inside the opening
		for i = 0, 7 do
			part(m, "Strip", Vector3.new(0.05, 8.6, 0.7), CFrame.new(31.3, 4.7, -18.0 + i * 0.72), Color3.fromRGB(200, 225, 240), Enum.Material.Glass, { Transparency = 0.55, CanCollide = false, CanQuery = false })
		end
		-- steel racks along the back and the right wall
		for _, rack in ipairs({ { x1 = 32, x2 = 41, z = -20.3, along = "x" }, { x1 = -19.2, x2 = -10.2, z = 40.3, along = "z" } }) do
			for _, y in ipairs({ 1.2, 4.6, 8.0 }) do
				if rack.along == "x" then
					box(m, "Shelf", rack.x1, y - 0.1, -21.1, rack.x2, y + 0.1, -19.5, STEEL, Enum.Material.Metal)
				else
					box(m, "Shelf", 39.5, y - 0.1, rack.x1, 41.1, y + 0.1, rack.x2, STEEL, Enum.Material.Metal)
				end
			end
			for k = 0, 3 do
				if rack.along == "x" then
					box(m, "Post", rack.x1 + k * 3 - 0.08, 0.2, -21.1, rack.x1 + k * 3 + 0.08, 8.2, -20.95, STEEL, Enum.Material.Metal)
				else
					box(m, "Post", 40.95, 0.2, rack.x1 + k * 3 - 0.08, 41.1, 8.2, rack.x1 + k * 3 + 0.08, STEEL, Enum.Material.Metal)
				end
			end
		end
		-- cold light, frost and the thermometer
		local strip = box(m, "ColdLight", 33, 10.0, -16, 40, 10.2, -15, Color3.fromRGB(230, 245, 255), Enum.Material.Neon, { CanCollide = false })
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(200, 228, 255)
		l.Range = 18
		l.Brightness = 1.4
		l.Parent = strip
		local frost = Instance.new("ParticleEmitter")
		frost.Rate = 6
		frost.Lifetime = NumberRange.new(4, 6)
		frost.Speed = NumberRange.new(0.3, 0.8)
		frost.SpreadAngle = Vector2.new(180, 180)
		frost.Size = NumberSequence.new(1.5, 3)
		frost.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.85), NumberSequenceKeypoint.new(1, 1) })
		frost.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
		frost.Parent = strip
		local thermo = box(m, "Thermometer", 31.2, 6, -9.0, 33.6, 7.4, -8.85, Color3.fromRGB(30, 40, 50))
		label(thermo, Enum.NormalId.Front, "❄️ -2 °C", Color3.fromRGB(140, 220, 255))
		m.Parent = r
		room = m
	end
	door = (room :: Model):FindFirstChild("ColdDoor") :: BasePart?
	doorClosedCF = door and door.CFrame
	-- 9 shelf slots (back rack: 2 levels × 3, right rack: 1 level × 3)
	table.clear(slots)
	for _, y in ipairs({ 1.3, 4.7 }) do
		for k = 0, 2 do
			table.insert(slots, CFrame.new(33.5 + k * 3, y, -20.3))
		end
	end
	for k = 0, 2 do
		table.insert(slots, CFrame.new(40.3, 1.3, -17.7 + k * 3))
	end
end

---------------------------------------------------------------------------
-- door
---------------------------------------------------------------------------
function ColdRoomService.SetDoor(open: boolean)
	if not door or not doorClosedCF or open == doorOpen then
		return
	end
	doorOpen = open
	-- hinge on the back edge (z -18.3), swings into the storage
	local hinge = doorClosedCF * CFrame.new(0, 0, -door.Size.Z / 2)
	local target = open and (hinge * CFrame.Angles(0, math.rad(-100), 0) * CFrame.new(0, 0, door.Size.Z / 2)) or doorClosedCF
	door.CanCollide = not open
	TweenService:Create(door, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
	door:SetAttribute("PromptDe", open and "Kühlraum schließen" or "Kühlraum öffnen")
	door:SetAttribute("PromptEn", open and "Close cold room" or "Open cold room")
	Net.Sound(nil, "click", door.Position)
end

---------------------------------------------------------------------------
-- visuals
---------------------------------------------------------------------------
local function cone(parent: Instance, meat: string, base: CFrame, scale: number): Model
	local m = Instance.new("Model")
	m.Name = "MeatCone"
	local def = IngredientData.Meat[meat]
	local lib = game:GetService("ServerStorage"):FindFirstChild("Models") and game:GetService("ServerStorage").Models:FindFirstChild("Logistics")
	local tpl = lib and lib:FindFirstChild("MeatCone") :: BasePart?
	if tpl then
		local p = tpl:Clone()
		p.Size = Vector3.new(1.9, 3.2, 1.9) * scale
		p.CFrame = base * CFrame.new(0, 1.6 * scale, 0)
		p.Anchored = true
		p.CanCollide = false
		local sa = p:FindFirstChildOfClass("SurfaceAppearance")
		if sa then
			sa.Color = meat == "veal" and Color3.fromRGB(235, 175, 165) or Color3.fromRGB(255, 240, 225)
		end
		p.Parent = m
		part(m, "Wrap", Vector3.new(2.7 * scale, 1.85 * scale, 1.85 * scale), base * CFrame.new(0, 1.45 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(230, 240, 250), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.8, CanCollide = false, CanQuery = false })
		m.Parent = parent
		return m
	end
	part(m, "Tray", Vector3.new(1.9, 0.12, 1.9) * scale, base * CFrame.new(0, 0.06 * scale, 0), STEEL, Enum.Material.Metal, { CanCollide = false })
	for i = 1, 5 do
		local dia = (1.7 - i * 0.18) * scale
		part(m, "Layer", Vector3.new(0.5 * scale, dia, dia), base * CFrame.new(0, (0.12 + (i - 0.5) * 0.5) * scale, 0) * CFrame.Angles(0, math.rad(i * 37), math.rad(90)), def.raw, Enum.Material.Sand, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	part(m, "Rod", Vector3.new(0.12, 3.1 * scale, 0.12) * 1, base * CFrame.new(0, 1.6 * scale, 0), STEEL, Enum.Material.Metal, { CanCollide = false })
	part(m, "Wrap", Vector3.new(2.7 * scale, 1.85 * scale, 1.85 * scale), base * CFrame.new(0, 1.45 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(230, 240, 250), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.75, CanCollide = false, CanQuery = false })
	m.Parent = parent
	return m
end

local function refreshLoadPrompts()
	for meat, p in pairs(loadParts) do
		local someone = staffCarrying[meat] == true
		for _, c in pairs(carried) do
			if MEAT_OF[c.pack.id] == meat then
				someone = true
			end
		end
		p:SetAttribute("PromptOn", someone)
	end
end

local function refreshShelves()
	if not room then
		return
	end
	for uid, m in pairs(packModels) do
		m:Destroy()
		packModels[uid] = nil
	end
	for i, p in ipairs(packs()) do
		local slot = slots[i]
		if not slot then
			break
		end
		local meat = MEAT_OF[p.id]
		local m = cone(room :: Model, meat, slot, 0.8)
		local hit = part(m, "Grab", Vector3.new(2, 2.6, 1.6), slot * CFrame.new(0, 1.3, 0), Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false })
		local isReady = ready(p)
		hit:SetAttribute("Station", "coldmeat")
		hit:SetAttribute("PackUid", p.uid)
		hit:SetAttribute("PromptDe", isReady and "Spieß nehmen" or "Muss über Nacht ruhen")
		hit:SetAttribute("PromptEn", isReady and "Take cone" or "Must rest overnight")
		hit:SetAttribute("PromptObj", string.format("%s %s · %d", IngredientData.Meat[meat].icon, IngredientData.Meat[meat].name.de, p.n))
		hit:SetAttribute("PromptHold", 0.5)
		hit:SetAttribute("PromptOn", isReady)
		CollectionService:AddTag(hit, "Station")
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(150, 40)
		bb.StudsOffset = Vector3.new(0, 1.2, 0)
		bb.MaxDistance = 22
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = isReady and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(40, 90, 150)
		t.BackgroundTransparency = 0.15
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.Text = string.format("%s %d Port.\n%s", IngredientData.Meat[meat].icon, p.n, isReady and "✅ bereit" or "❄️ ab morgen")
		t.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = t
		bb.Parent = hit
		packModels[p.uid] = m
	end
end
ColdRoomService.Refresh = refreshShelves

local unloadParts: { [string]: BasePart } = {}
local function buildLoadParts()
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return
	end
	local f = r:FindFirstChild("SpitLoad") or Instance.new("Folder")
	f.Name = "SpitLoad"
	f.Parent = r
	for meat, x in pairs(SPIT_X) do
		if not loadParts[meat] then
			local p = part(f, "Load_" .. meat, Vector3.new(1.6, 1.6, 1.6), CFrame.new(x, 6.6, -17.2), Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
			p:SetAttribute("Station", "spit_load")
			p:SetAttribute("Item", meat)
			p:SetAttribute("PromptKey", "F")
			p:SetAttribute("PromptDe", "Fleischspieß aufstecken")
			p:SetAttribute("PromptEn", "Mount meat cone")
			p:SetAttribute("PromptObj", IngredientData.Meat[meat].icon)
			p:SetAttribute("PromptOn", false)
			CollectionService:AddTag(p, "Station")
			loadParts[meat] = p
			local u = part(f, "Unload_" .. meat, Vector3.new(1.6, 1.4, 1.6), CFrame.new(x, 4.4, -17.2), Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, CanQuery = false })
			u:SetAttribute("Station", "spit_unload")
			u:SetAttribute("Item", meat)
			u:SetAttribute("PromptKey", "F")
			u:SetAttribute("PromptDe", "Spieß abnehmen")
			u:SetAttribute("PromptEn", "Take the cone off")
			u:SetAttribute("PromptObj", IngredientData.Meat[meat].icon)
			u:SetAttribute("PromptHold", 1)
			u:SetAttribute("PromptOn", false)
			CollectionService:AddTag(u, "Station")
			unloadParts[meat] = u
		end
	end
end

---------------------------------------------------------------------------
-- carrying & loading
---------------------------------------------------------------------------
local function attachCarry(char: Model, meat: string): Model?
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	local m = cone(workspace:FindFirstChild("Restaurant") or workspace, meat, torso.CFrame * CFrame.new(0, -1.25, -1.45), 0.7)
	m.Name = "CarriedCone"
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
	return m
end
ColdRoomService.AttachCarry = attachCarry

local function spitPresent(meat: string): boolean
	local r = workspace:FindFirstChild("Restaurant")
	for _, m in ipairs(CollectionService:GetTagged("Spit")) do
		if m:GetAttribute("Meat") == meat and r and m:IsDescendantOf(r) then
			return true
		end
	end
	return false
end

local function room4(stockId: string, n: number): boolean
	return RestaurantService.GetStock(stockId) + n <= RestaurantService.Capacity(stockId)
end

local function takePack(uid: number): Pack?
	local list = packs()
	for i, p in ipairs(list) do
		if p.uid == uid then
			table.remove(list, i)
			save()
			return p
		end
	end
	return nil
end

function ColdRoomService.ReturnPack(p: Pack)
	table.insert(packs(), p)
	save()
	refreshShelves()
end

local function dropCarry(player: Player, giveBack: boolean)
	local c = carried[player]
	if not c then
		return
	end
	carried[player] = nil
	if c.model.Parent then
		c.model:Destroy()
	end
	if player.Character then
		player.Character:SetAttribute("CarryMeat", nil)
	end
	player:SetAttribute("Carry", nil)
	player:SetAttribute("CarrySpeed", nil)
	if giveBack then
		ColdRoomService.ReturnPack(c.pack)
	end
	refreshLoadPrompts()
end

local function onTake(player: Player, part: BasePart)
	if carried[player] or player:GetAttribute("Carry") then
		Net.Notify(player, "n_carry_full", nil, "warn")
		return
	end
	if FoodPreparationService.HandsBusy(player) then
		Net.Notify(player, "n_hands_full", nil, "warn")
		return
	end
	local uid = part:GetAttribute("PackUid")
	local list = packs()
	local p
	for _, x in ipairs(list) do
		if x.uid == uid then
			p = x
		end
	end
	if not p then
		return
	end
	if not ready(p) then
		Net.Notify(player, "n_cone_resting", nil, "warn")
		return
	end
	local char = player.Character
	if not char then
		return
	end
	takePack(p.uid)
	local m = attachCarry(char, MEAT_OF[p.id])
	if not m then
		ColdRoomService.ReturnPack(p)
		return
	end
	carried[player] = { pack = p, model = m }
	char:SetAttribute("CarryMeat", MEAT_OF[p.id])
	player:SetAttribute("Carry", p.id)
	player:SetAttribute("CarrySpeed", 0.75)
	Net.Sound(player, "add")
	Net.Notify(player, "n_cone_taken", { item = IngredientData.Meat[MEAT_OF[p.id]].name }, "info")
	refreshShelves()
	refreshLoadPrompts()
end

local function loadSpit(meat: string, p: Pack): boolean
	RestaurantService.AddStock(p.id, p.n)
	FoodPreparationService.UpdateSpitVisual(meat)
	FoodPreparationService.PushSpits()
	Net.Sound(nil, "add", Vector3.new(SPIT_X[meat], 5, -17.9))
	Net.FireAll("Installed", "spit_" .. meat, Vector3.new(SPIT_X[meat], 6, -17.4))
	return true
end

local function onLoad(player: Player, part: BasePart)
	local meat = part:GetAttribute("Item")
	local c = carried[player]
	if not c then
		Net.Notify(player, "n_no_cone", nil, "warn")
		return
	end
	if MEAT_OF[c.pack.id] ~= meat then
		Net.Notify(player, "n_wrong_spit", nil, "warn")
		return
	end
	if not spitPresent(meat) then
		return
	end
	if not room4(c.pack.id, c.pack.n) then
		Net.Notify(player, "n_spit_full", nil, "warn")
		return
	end
	local pack = c.pack
	dropCarry(player, false)
	loadSpit(meat, pack)
	Net.Notify(player, "n_cone_loaded", { item = IngredientData.Meat[meat].name }, "success")
end

-- put a carried cone back into the cold room
function ColdRoomService.IsCarrying(player: Player): boolean
	return carried[player] ~= nil
end
function ColdRoomService.ReturnCarried(player: Player): boolean
	local c = carried[player]
	if not c then
		return false
	end
	dropCarry(player, true)
	Net.Sound(nil, "add", INSIDE)
	Net.Notify(player, "❄️ Fleischspieß zurück im Kühlraum", nil, "success")
	return true
end

-- take what is left on a spit off the grill and carry it (back to the cold room or another spit)
local function onUnload(player: Player, part: BasePart)
	local meat = part:GetAttribute("Item")
	local id = "meat_" .. tostring(meat)
	if carried[player] or player:GetAttribute("Carry") then
		Net.Notify(player, "n_carry_full", nil, "warn")
		return
	end
	if FoodPreparationService.HandsBusy(player) then
		Net.Notify(player, "n_hands_full", nil, "warn")
		return
	end
	local n = RestaurantService.GetStock(id)
	if n <= 0 or not IngredientData.Stock[id] then
		Net.Notify(player, "Auf dem Spieß ist kein Fleisch mehr", nil, "warn")
		return
	end
	local char = player.Character
	if not char or not RestaurantService.UseStock(id, n) then
		return
	end
	nextUid += 1
	local p = { id = id, n = n, day = RestaurantService.GetDay() - 1, uid = nextUid } -- already rested
	local m = attachCarry(char, meat)
	if not m then
		RestaurantService.AddStock(id, n)
		return
	end
	carried[player] = { pack = p, model = m }
	char:SetAttribute("CarryMeat", meat)
	player:SetAttribute("Carry", id)
	player:SetAttribute("CarrySpeed", 0.75)
	FoodPreparationService.UpdateSpitVisual(meat)
	FoodPreparationService.PushSpits()
	Net.Sound(nil, "add", part.Position)
	Net.Notify(player, ("🥩 Spieß abgenommen (%d Portionen) – zurück in den Kühlraum oder wieder aufstecken"):format(n), nil, "info")
	refreshLoadPrompts()
end

---------------------------------------------------------------------------
-- API for the carver employee
---------------------------------------------------------------------------
-- a ready cone for this meat exists and fits on the spit
function ColdRoomService.CanLoad(meat: string): boolean
	if not spitPresent(meat) then
		return false
	end
	for _, p in ipairs(packs()) do
		if MEAT_OF[p.id] == meat and ready(p) and room4(p.id, p.n) then
			return true
		end
	end
	return false
end

function ColdRoomService.StaffTake(meat: string): Pack?
	for _, p in ipairs(packs()) do
		if MEAT_OF[p.id] == meat and ready(p) then
			takePack(p.uid)
			staffCarrying[meat] = true
			refreshShelves()
			refreshLoadPrompts()
			return p
		end
	end
	return nil
end

function ColdRoomService.StaffLoad(meat: string, p: Pack): boolean
	staffCarrying[meat] = nil
	refreshLoadPrompts()
	if not room4(p.id, p.n) or not spitPresent(meat) then
		ColdRoomService.ReturnPack(p)
		return false
	end
	return loadSpit(meat, p)
end

function ColdRoomService.StaffAbort(meat: string, p: Pack)
	staffCarrying[meat] = nil
	refreshLoadPrompts()
	ColdRoomService.ReturnPack(p)
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------
function ColdRoomService.Init()
	build()
	buildLoadParts()
	-- every meat delivery is stored in the cold room instead of going straight onto the spit
	RestaurantService.DeliverHook = function(d)
		if not MEAT_OF[d.id] then
			return false
		end
		local list = packs()
		local left = d.amount
		local pack = IngredientData.Stock[d.id].pack
		while left > 0 do
			local n = math.min(pack, left)
			left -= n
			nextUid += 1
			table.insert(list, { id = d.id, n = n, day = RestaurantService.GetDay(), uid = nextUid })
		end
		save()
		refreshShelves()
		if d.by and d.by.Parent then
			Net.Notify(d.by, "n_meat_coldroom", { item = IngredientData.Stock[d.id].name }, "success")
		end
		return true
	end
	RestaurantService.ColdAmount = ColdRoomService.Amount
	FoodPreparationService.ExternalActions.colddoor = function()
		ColdRoomService.SetDoor(not doorOpen)
	end
	FoodPreparationService.ExternalActions.coldmeat = onTake
	FoodPreparationService.ExternalActions.spit_load = onLoad
	FoodPreparationService.ExternalActions.spit_unload = onUnload
	task.spawn(function()
		while true do
			task.wait(1)
			for meat, u in pairs(unloadParts) do
				u:SetAttribute("PromptOn", spitPresent(meat) and RestaurantService.GetStock("meat_" .. meat) > 0)
			end
		end
	end)
	RestaurantService.OwnerChanged:Connect(function()
		for pl in pairs(carried) do
			dropCarry(pl, true)
		end
		refreshShelves()
	end)
	Players.PlayerRemoving:Connect(function(pl)
		dropCarry(pl, true)
	end)
	local function watchChar(pl: Player)
		pl.CharacterRemoving:Connect(function()
			dropCarry(pl, true)
		end)
	end
	Players.PlayerAdded:Connect(watchChar)
	for _, pl in ipairs(Players:GetPlayers()) do
		watchChar(pl)
	end
	-- a new day makes yesterday's cones ready
	local lastDay = RestaurantService.GetDay()
	task.spawn(function()
		while true do
			task.wait(2)
			local day = RestaurantService.GetDay()
			if day ~= lastDay then
				lastDay = day
				refreshShelves()
			end
		end
	end)
	refreshShelves()
end

return ColdRoomService
