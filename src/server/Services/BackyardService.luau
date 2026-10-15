-- Backyard: the service courtyard behind the restaurant, reached through the back door
-- (Server/BackDoorService). Built at runtime into Restaurant.Backyard, so no binary asset changes:
--   · concrete apron along the building, asphalt yard, a back street with sidewalk behind it
--   · brick walls with concrete caps, a chain-link fence section and a wide vehicle gate
--   · a marked delivery unloading area in front of the back door (room for a van to turn in and park)
--   · a separate, walled waste disposal area (containers: Server/WasteService)
--   · purchasable upgrades (lighting, canopy, pavement; rack via LogisticsService): ApplyUpgrades
--   · street lights, wall lamps, drainage grates, puddles, pallets, crates, pipes, AC units, plants
-- Blender props (ServerStorage.Models.Backyard: Pallet, Crate, ACUnit, LampHead – see art/backyard)
-- replace the primitive versions when they exist. Decoration does not collide or cast small shadows,
-- so the yard stays cheap on mobile.

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local BackyardService = {}

-- layout (studs). The restaurant's back wall outer face is z = -21, the neighbours' backs z = -22;
-- the storage room sticks out as an annex x[11,31] down to z = -27.
local X0, X1 = -12, 44 -- yard inside the walls
local Z_WALL, Z_SOUTH = -21, -50
local GATE0, GATE1 = 22, 36 -- vehicle gate in the south wall
local WALL_H = 7

BackyardService.Layout = {
	delivery = { x0 = 21, x1 = 35, z0 = -45, z1 = -32 }, -- unloading area in front of the back door
	waste = { x0 = -11, x1 = 3, z0 = -40, z1 = -28 }, -- waste disposal area (bins: #12)
	gate = { x0 = GATE0, x1 = GATE1, z = Z_SOUTH },
	street = { z0 = -64, z1 = -54 },
}

local C = {
	concrete = Color3.fromRGB(150, 148, 142),
	asphalt = Color3.fromRGB(58, 58, 62),
	brick = Color3.fromRGB(150, 74, 56),
	cap = Color3.fromRGB(170, 166, 158),
	metal = Color3.fromRGB(96, 98, 104),
	darkMetal = Color3.fromRGB(44, 46, 50),
	yellow = Color3.fromRGB(240, 196, 40),
	wood = Color3.fromRGB(176, 136, 88),
	green = Color3.fromRGB(78, 128, 58),
}

local root: Model

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		(p :: any)[k] = v
	end
	p.Parent = root
	return p
end

-- decoration: no collision, no queries, no shadow (cheap)
local DECO = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function box(name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, mat: Enum.Material?, props: { [string]: any }?): BasePart
	return part(name, Vector3.new(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1)), CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, mat, props)
end

local function template(name: string): BasePart?
	local lib = ServerStorage:FindFirstChild("Models")
	local folder = lib and lib:FindFirstChild("Backyard")
	local t = folder and folder:FindFirstChild(name)
	return t and t:IsA("BasePart") and t or nil
end

local function placeTemplate(name: string, size: Vector3, cf: CFrame, collide: boolean): BasePart?
	local t = template(name)
	if not t then
		return nil
	end
	local p = t:Clone()
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = collide
	p.Parent = root
	return p
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 1
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	t.BackgroundColor3 = bg or Color3.new()
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Parent = sg
end

---------------------------------------------------------------------------
-- ground
---------------------------------------------------------------------------
local function ground()
	-- concrete apron along the building, asphalt yard
	box("Apron", X0, -0.2, -27, 11, 0.2, -22, C.concrete, Enum.Material.Concrete) -- either side of the storage annex
	box("Apron", 31, -0.2, -27, X1, 0.2, -22, C.concrete, Enum.Material.Concrete)
	box("ApronWall", X0, -0.2, -22, 11, 0.2, Z_WALL, C.concrete, Enum.Material.Concrete) -- up to the restaurant (behind the neighbour it ends at -22)
	box("Asphalt", X0, -0.2, Z_SOUTH, X1, 0.15, -27, C.asphalt, Enum.Material.Asphalt)
	box("Kerb", X0, 0.15, -27.3, 11, 0.3, -27, C.cap, Enum.Material.Concrete, DECO)
	box("Kerb", 31, 0.15, -27.3, X1, 0.3, -27, C.cap, Enum.Material.Concrete, DECO)
	-- back street: sidewalk + road with dashed centre line
	local s = BackyardService.Layout.street
	box("Sidewalk", -160, -0.2, s.z1, 160, 0.3, Z_SOUTH - 1, C.concrete, Enum.Material.Concrete)
	box("BackStreet", -160, -0.2, s.z0, 160, 0.1, s.z1, C.asphalt, Enum.Material.Asphalt)
	box("Curb", -160, 0.1, s.z1, 160, 0.35, s.z1 + 0.4, C.cap, Enum.Material.Concrete)
	for x = -150, 150, 12 do
		box("LaneMark", x, 0.1, (s.z0 + s.z1) / 2 - 0.15, x + 6, 0.12, (s.z0 + s.z1) / 2 + 0.15, Color3.fromRGB(235, 235, 230), Enum.Material.SmoothPlastic, DECO)
	end
	-- driveway: the sidewalk is lowered in front of the gate
	box("Driveway", GATE0 - 1, -0.2, s.z1 + 0.4, GATE1 + 1, 0.16, Z_SOUTH - 1, C.concrete, Enum.Material.Concrete)
end

---------------------------------------------------------------------------
-- walls, fence, gate
---------------------------------------------------------------------------
local function wall(name: string, x1: number, z1: number, x2: number, z2: number, h: number)
	box(name, x1, 0, z1, x2, h, z2, C.brick, Enum.Material.Brick)
	-- concrete cap slightly wider than the wall
	local pad = 0.15
	box(name .. "Cap", math.min(x1, x2) - pad, h, math.min(z1, z2) - pad, math.max(x1, x2) + pad, h + 0.35, math.max(z1, z2) + pad, C.cap, Enum.Material.Concrete)
end

local function walls()
	wall("WallWest", X0 - 1, Z_SOUTH - 1, X0, Z_WALL, WALL_H)
	wall("WallSouthW", X0 - 1, Z_SOUTH - 1, GATE0, Z_SOUTH, WALL_H)
	wall("WallSouthE", GATE1, Z_SOUTH - 1, X1 + 1, Z_SOUTH, WALL_H)
	-- east side: low wall with a chain-link fence on top (you can see the alley behind the neighbour)
	wall("WallEast", X1, Z_SOUTH - 1, X1 + 1, -22, 2.5)
	for z = -22, Z_SOUTH, -4 do
		box("FencePost", X1 + 0.35, 2.85, z - 0.15, X1 + 0.65, 8, z + 0.15, C.metal, Enum.Material.Metal)
	end
	local mesh = box("Fence", X1 + 0.45, 2.85, Z_SOUTH - 1, X1 + 0.55, 7.8, -22, Color3.fromRGB(150, 156, 160), Enum.Material.Fabric, { Transparency = 0.55, CastShadow = false })
	mesh:SetAttribute("ChainLink", true)
	box("FenceRail", X1 + 0.4, 7.8, Z_SOUTH - 1, X1 + 0.6, 8, -22, C.metal, Enum.Material.Metal, DECO)
	-- vehicle gate: two pillars, a sliding gate parked open along the wall, rail in the ground
	for _, x in ipairs({ GATE0 - 0.8, GATE1 + 0.8 }) do
		box("GatePillar", x - 0.8, 0, Z_SOUTH - 1.2, x + 0.8, WALL_H + 1, Z_SOUTH + 0.2, C.brick, Enum.Material.Brick)
		box("GatePillarCap", x - 1, WALL_H + 1, Z_SOUTH - 1.4, x + 1, WALL_H + 1.4, Z_SOUTH + 0.4, C.cap, Enum.Material.Concrete)
	end
	box("GateRail", GATE0 - 15, 0.15, Z_SOUTH + 0.4, GATE1, 0.22, Z_SOUTH + 0.6, C.darkMetal, Enum.Material.Metal, DECO)
	local gate = Instance.new("Model")
	gate.Name = "VehicleGate"
	local w = GATE1 - GATE0
	local gx = GATE0 - w / 2 - 0.5 -- parked open, slid to the west along the inside of the wall
	local function g(name: string, size: Vector3, cf: CFrame)
		local p = part(name, size, cf, C.darkMetal, Enum.Material.Metal, { CastShadow = false })
		p.Parent = gate
	end
	g("Frame", Vector3.new(w, 0.25, 0.25), CFrame.new(gx, 0.6, Z_SOUTH + 0.5))
	g("Frame", Vector3.new(w, 0.25, 0.25), CFrame.new(gx, 5.6, Z_SOUTH + 0.5))
	for i = 0, math.floor(w / 0.8) do
		g("Bar", Vector3.new(0.12, 5, 0.12), CFrame.new(GATE0 - w - 0.5 + i * 0.8, 3.1, Z_SOUTH + 0.5))
	end
	g("Motor", Vector3.new(1, 1.2, 0.8), CFrame.new(GATE0 - 0.2, 0.75, Z_SOUTH + 1.3))
	gate:SetAttribute("Open", true) -- functional gate: #11 (delivery van)
	gate.Parent = root
	local sign = box("GateSign", GATE1 + 0.1, 4.5, Z_SOUTH - 1.25, GATE1 + 1.5, 6, Z_SOUTH - 1.2, Color3.fromRGB(240, 240, 235), Enum.Material.SmoothPlastic, DECO)
	label(sign, Enum.NormalId.Front, "🚚 EINFAHRT\nFREIHALTEN", Color3.fromRGB(200, 40, 30))
end

---------------------------------------------------------------------------
-- zones
---------------------------------------------------------------------------
local function deliveryZone()
	local d = BackyardService.Layout.delivery
	local y = 0.16
	-- yellow frame + diagonal hatching at the door end
	box("DeliveryEdge", d.x0, y, d.z0, d.x0 + 0.3, y + 0.02, d.z1, C.yellow, Enum.Material.SmoothPlastic, DECO)
	box("DeliveryEdge", d.x1 - 0.3, y, d.z0, d.x1, y + 0.02, d.z1, C.yellow, Enum.Material.SmoothPlastic, DECO)
	box("DeliveryEdge", d.x0, y, d.z0, d.x1, y + 0.02, d.z0 + 0.3, C.yellow, Enum.Material.SmoothPlastic, DECO)
	box("DeliveryEdge", d.x0, y, d.z1 - 0.3, d.x1, y + 0.02, d.z1, C.yellow, Enum.Material.SmoothPlastic, DECO)
	for i = 0, 6 do
		local x = d.x0 + 1 + i * 2
		part("DeliveryHatch", Vector3.new(0.35, 0.02, 3.4), CFrame.new(x, y + 0.01, d.z1 - 1.6) * CFrame.Angles(0, math.rad(40), 0), C.yellow, Enum.Material.SmoothPlastic, DECO)
	end
	-- a Top-face SurfaceGui writes along the part's Z axis: long side on Z, readable from the gate
	local text = part("DeliveryText", Vector3.new(3, 0.03, 9), CFrame.new((d.x0 + d.x1) / 2, y + 0.02, d.z0 + 6), C.asphalt, Enum.Material.Asphalt, DECO)
	text.Transparency = 1
	label(text, Enum.NormalId.Top, "LIEFERZONE", C.yellow)
	-- bollards protecting the door and wall
	for _, x in ipairs({ d.x0 + 0.5, d.x1 - 0.5 }) do
		part("Bollard", Vector3.new(3, 0.6, 0.6), CFrame.new(x, 1.6, -30.8), C.yellow, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(x, 1.6, -30.8) * CFrame.Angles(0, 0, math.rad(90)) })
	end
	local zone = box("DeliveryArea", d.x0, y, d.z0, d.x1, y + 0.05, d.z1, C.yellow, Enum.Material.SmoothPlastic, DECO)
	zone.Transparency = 1
	CollectionService:AddTag(zone, "BackyardDelivery")
end

local function wasteZone()
	local w = BackyardService.Layout.waste
	box("WastePad", w.x0, 0.15, w.z0, w.x1, 0.24, w.z1, Color3.fromRGB(128, 126, 122), Enum.Material.Concrete)
	-- enclosure: low brick walls on three sides, open towards the yard (east)
	wall("WasteWallN", w.x0, w.z1, w.x1, w.z1 + 0.6, 3.2)
	wall("WasteWallS", w.x0, w.z0 - 0.6, w.x1, w.z0, 3.2)
	box("WasteRoof", w.x0 - 0.3, 5.6, w.z0 - 0.9, w.x1 + 0.3, 5.8, w.z1 + 0.9, Color3.fromRGB(80, 84, 90), Enum.Material.Metal, { CastShadow = true })
	for _, x in ipairs({ w.x1 - 0.2 }) do
		for _, z in ipairs({ w.z0 - 0.3, w.z1 + 0.3 }) do
			box("WasteRoofPost", x - 0.15, 3.2, z - 0.15, x + 0.15, 5.6, z + 0.15, C.metal, Enum.Material.Metal)
		end
	end
	local sign = box("WasteSign", w.x0 + 4, 3.7, w.z1 + 0.62, w.x0 + 10, 5.1, w.z1 + 0.66, Color3.fromRGB(40, 110, 60), Enum.Material.SmoothPlastic, DECO)
	label(sign, Enum.NormalId.Front, "♻ MÜLLPLATZ", Color3.fromRGB(250, 250, 245))
	local area = box("WasteArea", w.x0, 0.24, w.z0, w.x1, 0.3, w.z1, C.concrete, Enum.Material.Concrete, DECO)
	area.Transparency = 1
	CollectionService:AddTag(area, "BackyardWaste")
end

---------------------------------------------------------------------------
-- details: lights, drains, puddles, pallets, crates, pipes, plants
---------------------------------------------------------------------------
local function lampHead(cf: CFrame, range: number, shadows: boolean)
	local head = placeTemplate("LampHead", Vector3.new(1.6, 0.5, 0.9), cf, false)
		or part("LampHead", Vector3.new(1.6, 0.4, 0.9), cf, C.darkMetal, Enum.Material.Metal, DECO)
	local glass = part("LampGlass", Vector3.new(1.3, 0.1, 0.7), cf * CFrame.new(0, -0.25, 0), Color3.fromRGB(255, 232, 180), Enum.Material.Neon, DECO)
	local l = Instance.new("SpotLight")
	l.Face = Enum.NormalId.Bottom
	l.Angle = 120
	l.Range = range
	l.Brightness = 2.2
	l.Color = Color3.fromRGB(255, 222, 168)
	l.Shadows = shadows
	l.Parent = glass
	return head
end

local function lights()
	-- two street lights inside the yard
	for _, x in ipairs({ -3, 40 }) do
		local z = -46.5
		part("LightPole", Vector3.new(0.45, 13, 0.45), CFrame.new(x, 6.6, z), C.darkMetal, Enum.Material.Metal)
		local dir = x < 16 and 1 or -1
		part("LightArm", Vector3.new(3, 0.25, 0.25), CFrame.new(x + dir * 1.4, 12.9, z), C.darkMetal, Enum.Material.Metal, DECO)
		lampHead(CFrame.new(x + dir * 2.8, 12.8, z), 34, true)
	end
	-- wall lamps on the back of the restaurant (the door has its own)
	for _, l in ipairs({ { -4, Z_WALL }, { 20, -27 } }) do -- -24: the storage annex
		part("WallLampArm", Vector3.new(0.2, 0.2, 0.8), CFrame.new(l[1], 9.2, l[2] - 0.4), C.darkMetal, Enum.Material.Metal, DECO)
		lampHead(CFrame.new(l[1], 9.1, l[2] - 0.9), 22, false)
	end
end

local function drains()
	for _, p in ipairs({ Vector3.new(10, 0, -38), Vector3.new(28, 0, -46), Vector3.new(-3, 0, -45) }) do
		part("Drain", Vector3.new(1.8, 0.04, 1.2), CFrame.new(p.X, 0.16, p.Z), Color3.fromRGB(34, 34, 36), Enum.Material.DiamondPlate, DECO)
		part("DrainFrame", Vector3.new(2.1, 0.03, 1.5), CFrame.new(p.X, 0.15, p.Z), Color3.fromRGB(70, 70, 74), Enum.Material.Metal, DECO)
	end
	-- puddles collect around the drains
	local puddles = { { 11.5, -38.6, 3.2, 2.2 }, { 26.6, -45.4, 4.5, 2.6 }, { -1.5, -44.2, 2.6, 1.8 }, { 16, -31.5, 2.2, 1.4 } }
	for i, q in ipairs(puddles) do
		local p = part("Puddle", Vector3.new(0.03, q[3], q[4]), CFrame.new(q[1], 0.17, q[2]) * CFrame.Angles(0, math.rad(i * 37), math.rad(90)), Color3.fromRGB(46, 52, 58), Enum.Material.Glass, DECO)
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.03, math.max(q[3], q[4]), math.max(q[3], q[4]))
		p.Transparency = 0.5
		p.Reflectance = 0.08
	end
end

local function pallet(cf: CFrame)
	if placeTemplate("Pallet", Vector3.new(4, 0.5, 3.2), cf * CFrame.new(0, 0.25, 0), true) then
		return
	end
	for i = -2, 2 do
		part("PalletBoard", Vector3.new(0.7, 0.08, 3.2), cf * CFrame.new(i * 0.83, 0.46, 0), C.wood, Enum.Material.WoodPlanks, DECO)
	end
	for _, z in ipairs({ -1.4, 0, 1.4 }) do
		part("PalletBlock", Vector3.new(4, 0.34, 0.4), cf * CFrame.new(0, 0.25, z), C.wood:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Wood, { CastShadow = false })
	end
end

local function crate(cf: CFrame)
	if placeTemplate("Crate", Vector3.new(2.2, 1.8, 2.2), cf * CFrame.new(0, 0.9, 0), true) then
		return
	end
	part("Crate", Vector3.new(2.2, 1.8, 2.2), cf * CFrame.new(0, 0.9, 0), C.wood, Enum.Material.WoodPlanks)
	for _, y in ipairs({ 0.2, 1.6 }) do
		part("CrateBand", Vector3.new(2.25, 0.18, 2.25), cf * CFrame.new(0, y, 0), C.wood:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Wood, DECO)
	end
end

local function props()
	-- pallet stacks along the east fence, a crate stack beside the unloading area
	for i = 0, 3 do
		pallet(CFrame.new(41.5, 0.15 + i * 0.5, -30))
	end
	for i = 0, 1 do
		pallet(CFrame.new(41.5, 0.15 + i * 0.5, -34.5) * CFrame.Angles(0, math.rad(8), 0))
	end
	part("LeaningPallet", Vector3.new(4, 3.2, 0.5), CFrame.new(41.6, 1.9, -38) * CFrame.Angles(math.rad(-12), math.rad(90), 0), C.wood, Enum.Material.WoodPlanks, { CastShadow = false })
	crate(CFrame.new(38.2, 0.15, -44))
	crate(CFrame.new(38.4, 0.15, -46.5) * CFrame.Angles(0, math.rad(12), 0))
	crate(CFrame.new(38.3, 1.95, -45.2) * CFrame.Angles(0, math.rad(-6), 0))
	-- pipes on the restaurant's back wall: two downpipes from the roof and a horizontal line
	for _, x in ipairs({ -10.5, 10.5 }) do
		part("Downpipe", Vector3.new(40, 0.5, 0.5), CFrame.new(x, 20.2, Z_WALL - 0.4), Color3.fromRGB(130, 132, 136), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(x, 20.2, Z_WALL - 0.4) * CFrame.Angles(0, 0, math.rad(90)), CanCollide = false, CastShadow = false })
		part("PipeShoe", Vector3.new(0.6, 0.6, 1), CFrame.new(x, 0.6, Z_WALL - 0.7), Color3.fromRGB(130, 132, 136), Enum.Material.Metal, DECO)
	end
	part("WallPipe", Vector3.new(21, 0.32, 0.32), CFrame.new(0, 11.5, Z_WALL - 0.3), Color3.fromRGB(176, 166, 120), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
	-- air-conditioning units on wall brackets (kitchen exhaust side)
	for i, x in ipairs({ 2.5, 7 }) do
		local cf = CFrame.new(x, 5.4 + (i - 1) * 0.2, Z_WALL - 1.1)
		if not placeTemplate("ACUnit", Vector3.new(3.4, 2.4, 1.6), cf, true) then
			part("ACUnit", Vector3.new(3.4, 2.4, 1.6), cf, Color3.fromRGB(228, 228, 224), Enum.Material.SmoothPlastic)
			part("ACFan", Vector3.new(0.1, 1.8, 1.8), cf * CFrame.new(-0.6, 0, -0.8) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(60, 62, 66), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		end
		part("ACBracket", Vector3.new(3.2, 0.2, 1.8), cf * CFrame.new(0, -1.3, 0.1), C.metal, Enum.Material.Metal, DECO)
	end
	part("ACDrain", Vector3.new(0.15, 4.3, 0.15), CFrame.new(5, 2.2, Z_WALL - 0.4), Color3.fromRGB(230, 230, 230), Enum.Material.SmoothPlastic, DECO)
end

local function plants()
	-- weeds along the walls, a planter with a shrub, ivy on the west wall
	local spots = { { -11.2, -30 }, { -11.3, -42 }, { -11.1, -48.5 }, { 5, -49.2 }, { 14, -49.3 }, { 43.2, -41 }, { 43.3, -49 }, { -6, -27.7 }, { 15, -27.6 } }
	for i, s in ipairs(spots) do
		for k = 0, 2 do
			part("Weed", Vector3.new(0.35, 0.8 + (k % 2) * 0.4, 0.12), CFrame.new(s[1] + k * 0.25, 0.55, s[2] + (k - 1) * 0.2) * CFrame.Angles(math.rad((k - 1) * 18), math.rad(i * 40 + k * 70), math.rad((k - 1) * 14)), C.green:Lerp(Color3.fromRGB(150, 160, 70), (i % 3) * 0.25), Enum.Material.Grass, DECO)
		end
	end
	box("Planter", -10.5, 0.15, -47.8, -6.5, 1.4, -45.8, C.cap, Enum.Material.Concrete)
	part("Shrub", Vector3.new(3.4, 2.4, 2.2), CFrame.new(-8.5, 2.5, -46.8), C.green, Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false })
	for i = 0, 5 do
		part("Ivy", Vector3.new(0.12, 1.4 + (i % 3) * 0.6, 1.6 + (i % 2)), CFrame.new(X0 + 0.07, 1.2 + i * 0.8, -33 - i * 0.7) * CFrame.Angles(math.rad(i * 9), 0, 0), C.green:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Grass, DECO)
	end
end

---------------------------------------------------------------------------
-- purchasable upgrades (#14, Config.Upgrades yard_*): rebuilt whenever the upgrades change
---------------------------------------------------------------------------
local function upLights()
	for _, p in ipairs({ Vector3.new(6, 0, -31), Vector3.new(16, 0, -45), Vector3.new(38, 0, -44), Vector3.new(-6, 0, -26) }) do
		part("FloodPole", Vector3.new(0.4, 11, 0.4), CFrame.new(p.X, 5.5, p.Z), C.darkMetal, Enum.Material.Metal)
		part("FloodBase", Vector3.new(1.1, 0.4, 1.1), CFrame.new(p.X, 0.35, p.Z), C.concrete, Enum.Material.Concrete)
		for _, a in ipairs({ 0, math.pi }) do
			local cf = CFrame.new(p.X, 11.2, p.Z) * CFrame.Angles(0, a + 0.6, 0) * CFrame.new(0, 0, -0.6) * CFrame.Angles(math.rad(-25), 0, 0)
			lampHead(cf, 42, false)
		end
	end
end

local function upRoof()
	-- canopy over the unloading area and the back entrance; high enough for the delivery van
	local x0, x1, z0, z1, h = 19.4, 36.6, -46.5, -27.2, 9.8
	for _, x in ipairs({ x0 + 0.3, x1 - 0.3 }) do
		for _, z in ipairs({ z0 + 0.3, (z0 + z1) / 2 }) do
			part("CanopyPost", Vector3.new(0.45, h, 0.45), CFrame.new(x, h / 2, z), C.darkMetal, Enum.Material.Metal)
		end
		part("CanopyBeam", Vector3.new(0.4, 0.5, z1 - z0), CFrame.new(x, h - 0.1, (z0 + z1) / 2), C.darkMetal, Enum.Material.Metal)
	end
	local roof = part("CanopyRoof", Vector3.new(x1 - x0 + 0.6, 0.18, z1 - z0 + 0.4), CFrame.new((x0 + x1) / 2, h + 0.35, (z0 + z1) / 2) * CFrame.Angles(math.rad(-2), 0, 0), Color3.fromRGB(150, 154, 160), Enum.Material.CorrodedMetal, { CastShadow = true })
	roof.Reflectance = 0.05
	for i = 0, 10 do
		part("CanopyRib", Vector3.new(0.12, 0.12, z1 - z0 + 0.4), CFrame.new(x0 + i * (x1 - x0) / 10, h + 0.48, (z0 + z1) / 2) * CFrame.Angles(math.rad(-2), 0, 0), Color3.fromRGB(120, 124, 130), Enum.Material.Metal, DECO)
	end
	-- a lamp under the canopy
	lampHead(CFrame.new((x0 + x1) / 2, h - 0.5, -33), 28, false)
end

local function upPavement()
	-- paved path from the back door to the waste area, flower tubs and a bench by the wall
	box("PavedPath", 2.5, 0.16, -30.2, 26.5, 0.22, -27.2, Color3.fromRGB(160, 128, 108), Enum.Material.Cobblestone, DECO)
	box("PavedApron", 3, 0.16, -40, 3.6, 0.22, -30.2, Color3.fromRGB(160, 128, 108), Enum.Material.Cobblestone, DECO)
	for _, x in ipairs({ -9, -2, 3 }) do
		box("FlowerTub", x - 0.9, 0.15, -23.1, x + 0.9, 1.5, -21.3, Color3.fromRGB(120, 112, 104), Enum.Material.Concrete)
		box("TubSoil", x - 0.75, 1.5, -22.95, x + 0.75, 1.6, -21.45, Color3.fromRGB(70, 50, 34), Enum.Material.Ground, DECO)
		for k = 0, 4 do
			local a = k * 1.3
			part("Flower", Vector3.new(0.45, 0.45, 0.45), CFrame.new(x + math.cos(a) * 0.45, 1.85 + (k % 2) * 0.15, -22.2 + math.sin(a) * 0.4), k % 2 == 0 and Color3.fromRGB(230, 70, 90) or Color3.fromRGB(250, 200, 60), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false })
		end
		part("Leaves", Vector3.new(1.4, 0.5, 1.3), CFrame.new(x, 1.75, -22.2), C.green, Enum.Material.Grass, DECO)
	end
	-- bench for the break
	local bx, bz = 7.6, -22.6
	box("BenchSeat", bx - 2.2, 1.5, bz - 0.7, bx + 2.2, 1.7, bz + 0.5, C.wood, Enum.Material.Wood)
	box("BenchBack", bx - 2.2, 1.7, bz + 0.35, bx + 2.2, 3.2, bz + 0.55, C.wood, Enum.Material.Wood)
	for _, x in ipairs({ bx - 1.9, bx + 1.9 }) do
		box("BenchLeg", x - 0.12, 0.15, bz - 0.6, x + 0.12, 1.5, bz + 0.4, C.darkMetal, Enum.Material.Metal)
	end
end

local UPGRADES = { yard_light = upLights, yard_roof = upRoof, yard_pavement = upPavement }

function BackyardService.ApplyUpgrades(u: { [string]: number })
	local r = workspace:FindFirstChild("Restaurant")
	local yard = r and r:FindFirstChild("Backyard")
	if not yard then
		return
	end
	local saved = root
	for id, build in pairs(UPGRADES) do
		local name = "Upgrade_" .. id
		local have = yard:FindFirstChild(name)
		local want = (u[id] or 0) >= 1
		if want and not have then
			local m = Instance.new("Model")
			m.Name = name
			root = m
			local ok, err = pcall(build)
			if not ok then
				warn("[BackyardService] " .. id .. ": " .. tostring(err))
			end
			m.Parent = yard
		elseif have and not want then
			have:Destroy()
		end
	end
	root = saved
	if (u.yard_storage or 0) >= 1 then
		local LogisticsService = require(script.Parent.LogisticsService)
		LogisticsService.AddYardShelf()
	end
end

function BackyardService.Init()
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return
	end
	local RestaurantService = require(script.Parent.RestaurantService)
	table.insert(RestaurantService.WorldUpgradeHooks, BackyardService.ApplyUpgrades)
	if r:FindFirstChild("Backyard") then
		BackyardService.ApplyUpgrades(RestaurantService.GetUpgrades())
		return
	end
	root = Instance.new("Model")
	root.Name = "Backyard"
	-- each section on its own: a broken decoration must never stop the game from starting
	for name, step in pairs({ ground = ground, walls = walls, delivery = deliveryZone, waste = wasteZone, lights = lights, drains = drains, props = props, plants = plants }) do
		local ok, err = pcall(step)
		if not ok then
			warn("[BackyardService] " .. name .. " failed: " .. tostring(err))
		end
	end
	root.Parent = r
	BackyardService.ApplyUpgrades(RestaurantService.GetUpgrades())
end

return BackyardService
