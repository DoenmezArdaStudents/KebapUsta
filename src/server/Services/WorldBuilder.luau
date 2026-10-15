-- Procedurally builds the kebap restaurant, the street outside and all navigation points.
-- Runs once in Edit mode (installer) or at server start if workspace.Restaurant is missing.
-- All gameplay stations are tagged "Station" with attributes; services attach behaviour to them.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local WorldBuilder = {}

local C = {
	tileA = Color3.fromRGB(236, 230, 218),
	tileB = Color3.fromRGB(196, 72, 48),
	wall = Color3.fromRGB(245, 238, 224),
	wallAccent = Color3.fromRGB(176, 52, 38),
	wood = Color3.fromRGB(122, 82, 52),
	darkWood = Color3.fromRGB(74, 50, 34),
	steel = Color3.fromRGB(196, 200, 204),
	darkSteel = Color3.fromRGB(110, 114, 120),
	marble = Color3.fromRGB(232, 228, 222),
	glass = Color3.fromRGB(190, 220, 235),
	asphalt = Color3.fromRGB(52, 54, 58),
	sidewalk = Color3.fromRGB(168, 164, 158),
	curb = Color3.fromRGB(140, 138, 134),
	gold = Color3.fromRGB(230, 180, 60),
	green = Color3.fromRGB(62, 118, 72),
	black = Color3.fromRGB(28, 28, 30),
	white = Color3.fromRGB(250, 250, 250),
}

local current: Instance = workspace

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			(p :: any)[k] = v
		end
	end
	p.Parent = current
	return p
end

local function at(x, y, z)
	return CFrame.new(x, y, z)
end

-- Box from min/max corners (handy for walls)
local function span(name, x1, y1, z1, x2, y2, z2, color, material, props)
	local size = Vector3.new(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1))
	return part(name, size, at((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, material, props)
end

local function folder(name: string, parent: Instance)
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = parent
	return f
end

local function station(p: BasePart, kind: string, item: string?, extra: { [string]: any }?)
	p:SetAttribute("Station", kind)
	if item then
		p:SetAttribute("Item", item)
	end
	if extra then
		for k, v in pairs(extra) do
			p:SetAttribute(k, v)
		end
	end
	CollectionService:AddTag(p, "Station")
	return p
end

-- equipment that has to be bought first (Shared/Progression); UnlockService hides it until installed
local function unlockable(inst: Instance, id: string)
	inst:SetAttribute("Unlock", id)
	CollectionService:AddTag(inst, "Unlockable")
	return inst
end

-- Swaps a procedural spit's visuals for the Blender meshes in ServerStorage.Models.DoenerSpit
-- (tools/blender/doener_spit.py; template origin = base bottom on the rod axis, front = +Z).
-- The stacked "Layer" cylinders stay as invisible helpers: the server still shrinks and colours
-- them, and the cutting FX read slice height, radius and colour from them. No-op without the
-- template or when the spit was already converted, so it can also upgrade an existing world.
function WorldBuilder.ApplySpitModel(m: Model)
	local models = ServerStorage:FindFirstChild("Models")
	local template = models and models:FindFirstChild("DoenerSpit")
	local base = m:FindFirstChild("Base") :: BasePart?
	local meatModel = m:FindFirstChild("Meat")
	local cone = template and template:FindFirstChild("DonerMeat_" .. tostring(m:GetAttribute("Meat")))
	if not cone or not base or not meatModel then
		return
	end
	local origin = CFrame.new(meatModel:GetAttribute("SpinX"), base.Position.Y - base.Size.Y / 2, meatModel:GetAttribute("SpinZ"))
	local function place(src: BasePart, name: string, parent: Instance): BasePart
		local p = src:Clone()
		p.Name = name
		p.CFrame = origin * src.CFrame
		p.Parent = parent
		return p
	end
	for _, name in ipairs({ "Base", "DripTray", "Rod", "TopCap", "BurnerFrame" }) do
		local p = m:FindFirstChild(name)
		if p then
			p:Destroy()
		end
	end
	place(template.SpitMachine, "Machine", m)
	-- invisible stand-in where the slices land (MeatCutting FX + tray pile)
	local tray = Instance.new("Part")
	tray.Name = "DripTray"
	tray.Anchored = true
	tray.CanCollide = false
	tray.CanQuery = false
	tray.Transparency = 1
	tray.Size = Vector3.new(2.5, 0.12, 2.5)
	tray.CFrame = origin * CFrame.new(0, 0.43, 0)
	tray.Parent = m
	-- the burner mesh takes over the old part's name and glow light (FoodPreparationService drives both)
	local oldBurner = m:FindFirstChild("Burner")
	local burner = place(template.Burner, "Burner", m)
	if oldBurner then
		burner.Color = (oldBurner :: BasePart).Color
		local glow = oldBurner:FindFirstChild("Glow")
		if glow then
			glow.Parent = burner
		end
		oldBurner:Destroy()
	end
	for _, layer in ipairs(meatModel:GetChildren()) do
		if layer:IsA("BasePart") then
			layer.Transparency = 1
			layer.CastShadow = false
		end
	end
	local mesh = place(cone, "Cone", meatModel)
	mesh:SetAttribute("BaseSize", mesh.Size)
	-- the name plate moves from the base front (now the control panel) up onto the burner tower
	local plate = m:FindFirstChild("Plate") :: BasePart?
	if plate then
		plate.Size = Vector3.new(2, 0.26, 0.05)
		plate.CFrame = origin * CFrame.new(0, 3.33, -1.14)
	end
	-- the heat knob station becomes the indicator lamp on the control panel
	local knob = m:FindFirstChild("HeatKnob") :: BasePart?
	if knob then
		knob.Size = Vector3.new(0.26, 0.26, 0.26)
		knob.Material = Enum.Material.Neon
		knob.CFrame = origin * CFrame.new(1.15, 0.18, 1.58)
	end
end

local VEG_UNLOCK = { tomato = "veg_tomato", onion = "veg_onion", cabbage = "veg_cabbage", cucumber = "veg_cucumber", cheese = "cheese" }
local SAUCE_UNLOCK = { spicy = "sauce_spicy", cocktail = "sauce_cocktail", herb = "sauce_herb" }
local BREAD_UNLOCK = { duerum = "menu_duerum", box = "menu_box" }

local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, ppu: number?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppu or 40
	sg.LightInfluence = 0.2
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	if bg then
		t.BackgroundColor3 = bg
	end
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	t.Font = font or Enum.Font.GothamBold
	t.Parent = sg
	return sg, t
end

local function light(p: BasePart, range: number, brightness: number, color: Color3?, kind: string?)
	local l
	if kind == "spot" then
		l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Bottom
		l.Angle = 100
	else
		l = Instance.new("PointLight")
	end
	l.Range = range
	l.Brightness = brightness
	l.Color = color or Color3.fromRGB(255, 220, 170)
	l.Shadows = false -- dynamic shadows from dozens of lamps are very expensive
	l.Parent = p
	return l
end

local function navPoint(parent: Instance, name: string, pos: Vector3, attrs: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	if attrs then
		for k, v in pairs(attrs) do
			p:SetAttribute(k, v)
		end
	end
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- Furniture helpers
---------------------------------------------------------------------------
local function chair(x, z, facing: number)
	local m = folder("Chair", current)
	local prev = current
	current = m
	local cf = at(x, 0, z) * CFrame.Angles(0, math.rad(facing), 0)
	part("Seat", Vector3.new(1.8, 0.25, 1.8), cf * at(0, 1.9, 0), C.darkWood, Enum.Material.Wood)
	part("Back", Vector3.new(1.8, 2, 0.2), cf * at(0, 3, 0.85), C.darkWood, Enum.Material.Wood)
	for _, o in ipairs({ { -0.75, -0.75 }, { 0.75, -0.75 }, { -0.75, 0.75 }, { 0.75, 0.75 } }) do
		part("Leg", Vector3.new(0.18, 1.8, 0.18), cf * at(o[1], 0.95, o[2]), C.black, Enum.Material.Metal)
	end
	current = prev
	return m
end

local function dinerTable(name, x, z, seatsAxis: string, tier: number, group: Instance)
	local m = folder(name, group)
	local prev = current
	current = m
	part("Top", Vector3.new(3.4, 0.25, 3), at(x, 3.1, z), C.wood, Enum.Material.WoodPlanks)
	part("Leg", Vector3.new(0.4, 2.9, 0.4), at(x, 1.65, z), C.black, Enum.Material.Metal)
	part("Foot", Vector3.new(1.6, 0.2, 1.6), at(x, 0.3, z), C.black, Enum.Material.Metal)
	-- napkin holder and condiments
	part("Napkins", Vector3.new(0.5, 0.5, 0.25), at(x, 3.48, z), C.steel, Enum.Material.Metal)
	part("Chili", Vector3.new(0.18, 0.45, 0.18), at(x + 0.45, 3.45, z), Color3.fromRGB(190, 30, 20), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })
	part("Salt", Vector3.new(0.18, 0.4, 0.18), at(x - 0.45, 3.43, z), C.white, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })
	local seats = {}
	if seatsAxis == "x" then
		table.insert(seats, { x - 2.3, z, -90 })
		table.insert(seats, { x + 2.3, z, 90 })
	else
		table.insert(seats, { x, z - 2.3, 180 })
		table.insert(seats, { x, z + 2.3, 0 })
	end
	local NY = 3.2 -- root height for nav points
	for i, s in ipairs(seats) do
		chair(s[1], s[2], s[3])
		-- seat nav point: customers sit facing the table
		local look = CFrame.lookAt(Vector3.new(s[1], 0, s[2]), Vector3.new(x, 0, z))
		local sp = navPoint(m, "SeatPoint" .. i, Vector3.new(s[1], 2.05, s[2]), { Tier = tier })
		sp.CFrame = look + Vector3.new(0, 2.05, 0)
		-- explicit approach along the clear aisles (x = -11 and z = 9) so customers never clip tables
		sp:SetAttribute("Entry", "AisleEntry")
		if seatsAxis == "x" then
			sp:SetAttribute("A1", Vector3.new(-11, NY, 9))
			sp:SetAttribute("A2", Vector3.new(s[1], NY, 9))
			sp:SetAttribute("A3", Vector3.new(s[1], NY, z + (z < 9 and 1.7 or -1.7)))
		else
			sp:SetAttribute("A1", Vector3.new(-11, NY, s[2]))
			sp:SetAttribute("A2", Vector3.new(x - 1.9, NY, s[2]))
		end
		CollectionService:AddTag(sp, "SeatPoint")
	end
	current = prev
	return m
end

local function plant(x, z, scale)
	scale = scale or 1
	part("Pot", Vector3.new(1.6, 1.6, 1.6) * scale, at(x, 0.8 * scale + 0.2, z), Color3.fromRGB(180, 96, 60), Enum.Material.Slate)
	for i = 1, 5 do
		local a = i * 72
		local leaf = part("Leaf", Vector3.new(0.4, 2.4, 1.0) * scale, at(x, 2.5 * scale + 0.2, z) * CFrame.Angles(0, math.rad(a), math.rad(25)) * at(0, 0, 0.3 * scale), C.green, Enum.Material.Grass)
		leaf.CanCollide = false
	end
end

---------------------------------------------------------------------------
-- Build sections
---------------------------------------------------------------------------
local function buildStreet(root)
	local street = folder("Street", root)
	current = street
	span("Sidewalk", -160, 0, 20.5, 160, 0.5, 32, C.sidewalk, Enum.Material.Concrete)
	span("Curb", -160, 0, 31.6, 160, 0.6, 32.4, C.curb, Enum.Material.Concrete)
	span("Road", -160, 0, 32.4, 160, 0.15, 52, C.asphalt, Enum.Material.Asphalt)
	span("SidewalkFar", -160, 0, 52, 160, 0.5, 62, C.sidewalk, Enum.Material.Concrete)
	span("CurbFar", -160, 0, 51.6, 160, 0.6, 52.4, C.curb, Enum.Material.Concrete)
	-- tram tracks (Vienna!)
	for _, z in ipairs({ 40.6, 43.4 }) do
		span("Rail", -160, 0.15, z - 0.12, 160, 0.3, z + 0.12, C.darkSteel, Enum.Material.Metal)
	end
	-- lane markings
	for x = -150, 150, 12 do
		span("Marking", x, 0.15, 36.3, x + 5, 0.18, 36.6, C.white, Enum.Material.SmoothPlastic)
		span("Marking", x, 0.15, 47.6, x + 5, 0.18, 47.9, C.white, Enum.Material.SmoothPlastic)
	end
	-- zebra crossing
	for i = 0, 7 do
		span("Zebra", -44 + i * 1.6, 0.15, 33, -43.2 + i * 1.6, 0.18, 51.5, C.white)
	end
	-- street lamps
	for x = -120, 120, 40 do
		for _, z in ipairs({ 31, 53 }) do
			part("LampPole", Vector3.new(0.5, 16, 0.5), at(x, 8.5, z), C.black, Enum.Material.Metal)
			local head = part("LampHead", Vector3.new(1.4, 0.6, 2.4), at(x, 16.4, z + (z < 40 and 0.8 or -0.8)), C.black, Enum.Material.Metal)
			local bulb = part("LampBulb", Vector3.new(1, 0.2, 1.8), head.CFrame * at(0, -0.4, 0), Color3.fromRGB(255, 220, 160), Enum.Material.Neon)
			bulb:SetAttribute("NightLight", true)
			local l = light(bulb, 40, 0, Color3.fromRGB(255, 200, 140), "spot")
			l.Name = "NightLight"
		end
	end
	-- trees on far sidewalk
	for x = -110, 110, 28 do
		part("Trunk", Vector3.new(0.9, 9, 0.9), at(x + 14, 4.9, 57), Color3.fromRGB(92, 64, 44), Enum.Material.Wood)
		part("Crown", Vector3.new(7, 7, 7), at(x + 14, 11, 57), Color3.fromRGB(70, 120, 60), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	-- tram stop opposite
	part("TramShelterRoof", Vector3.new(14, 0.4, 4), at(-60, 9, 56), C.darkSteel, Enum.Material.Metal)
	part("TramShelterBack", Vector3.new(14, 8, 0.2), at(-60, 4.9, 57.9), C.glass, Enum.Material.Glass, { Transparency = 0.5 })
	local stopSign = part("TramStopSign", Vector3.new(2.4, 2.4, 0.2), at(-52, 8, 53.5), Color3.fromRGB(200, 30, 40), Enum.Material.SmoothPlastic)
	surfaceText(stopSign, Enum.NormalId.Front, "H", C.white, nil, Enum.Font.GothamBlack)
	surfaceText(stopSign, Enum.NormalId.Back, "H", C.white, nil, Enum.Font.GothamBlack)
	part("Bench", Vector3.new(8, 0.4, 1.6), at(-60, 2, 56.6), C.wood, Enum.Material.WoodPlanks)

	-- parked cars on our side
	local function car(x, z, color)
		local m = folder("Car", street)
		local prev = current
		current = m
		part("Body", Vector3.new(9, 2.2, 4.2), at(x, 1.9, z), color, Enum.Material.SmoothPlastic, { Reflectance = 0.1 })
		part("Cabin", Vector3.new(5, 1.8, 3.9), at(x - 0.4, 3.9, z), C.glass, Enum.Material.Glass, { Transparency = 0.3 })
		part("Roof", Vector3.new(4.6, 0.25, 3.9), at(x - 0.4, 4.9, z), color, Enum.Material.SmoothPlastic)
		for _, o in ipairs({ { -3, -2 }, { 3, -2 }, { -3, 2 }, { 3, 2 } }) do
			part("Wheel", Vector3.new(0.8, 1.8, 1.8), at(x + o[1], 0.95, z + o[2]), C.black, Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 90, 0) })
		end
		part("LightF", Vector3.new(0.2, 0.5, 0.9), at(x + 4.5, 2.2, z - 1.4), C.white, Enum.Material.Neon)
		part("LightF", Vector3.new(0.2, 0.5, 0.9), at(x + 4.5, 2.2, z + 1.4), C.white, Enum.Material.Neon)
		current = prev
	end
	car(-28, 34.8, Color3.fromRGB(180, 30, 40))
	car(46, 34.8, Color3.fromRGB(40, 70, 140))
	car(-80, 49.6, Color3.fromRGB(220, 220, 220))

	-- buildings across the street (simple Viennese facades)
	local palette = {
		Color3.fromRGB(232, 210, 160), Color3.fromRGB(214, 186, 170), Color3.fromRGB(200, 214, 196),
		Color3.fromRGB(236, 224, 200), Color3.fromRGB(210, 196, 220),
	}
	local idx = 0
	for x = -150, 130, 28 do
		idx += 1
		local col = palette[(idx % #palette) + 1]
		local h = 34 + (idx % 3) * 6
		span("Facade", x, 0, 62, x + 28, h, 76, col, Enum.Material.Plaster)
		span("Cornice", x - 0.3, h - 1.2, 61.5, x + 28.3, h, 62.2, C.white, Enum.Material.Plaster)
		for floor = 0, 3 do
			for wx = 0, 3 do
				local wy = 8 + floor * 7
				if wy + 5 < h then
					local w = span("Window", x + 2.5 + wx * 6.5, wy, 61.8, x + 6 + wx * 6.5, wy + 4.5, 62, Color3.fromRGB(60, 80, 100), Enum.Material.Glass, { Reflectance = 0.2 })
					if (idx + floor + wx) % 3 == 0 then
						w.Color = Color3.fromRGB(255, 214, 150)
						w.Material = Enum.Material.Neon
						w.Transparency = 0.35
						w:SetAttribute("NightWindow", true)
					end
					span("Sill", x + 2.2 + wx * 6.5, wy - 0.3, 61.4, x + 6.3 + wx * 6.5, wy, 62, C.white, Enum.Material.Plaster)
				end
			end
		end
		-- ground floor shop
		span("ShopWindow", x + 3, 1, 61.8, x + 25, 6.5, 62, Color3.fromRGB(80, 100, 110), Enum.Material.Glass, { Reflectance = 0.25 })
	end
	-- side buildings next to the shop
	span("NeighbourL", -70, 0, -22, -31, 40, 20.5, Color3.fromRGB(210, 190, 160), Enum.Material.Plaster)
	span("NeighbourR", 31, 0, -22, 70, 36, 20.5, Color3.fromRGB(196, 206, 214), Enum.Material.Plaster)
	for _, nb in ipairs({ { -70, -31 }, { 31, 70 } }) do
		for floor = 0, 3 do
			for wx = nb[1] + 3, nb[2] - 6, 7 do
				span("Window", wx, 6 + floor * 7.5, 20.4, wx + 3.5, 10.5 + floor * 7.5, 20.6, Color3.fromRGB(60, 80, 100), Enum.Material.Glass, { Reflectance = 0.2 })
			end
		end
	end
	-- invisible boundary walls so players stay near the shop
	for _, b in ipairs({ { -100, 0, 20, -99, 40, 62 }, { 99, 0, 20, 100, 40, 62 }, { -100, 0, 61.5, 100, 40, 62 } }) do
		span("Boundary", b[1], b[2], b[3], b[4], b[5], b[6], C.white, nil, { Transparency = 1, CanQuery = false })
	end
end

local function buildShell(root)
	local shell = folder("Shell", root)
	current = shell
	-- floor tiles (checker)
	span("FloorBase", -30, -0.2, -20, 30, 0.1, 20, C.tileA, Enum.Material.Marble)
	for x = -30, 28, 4 do
		for z = -20, 18, 4 do
			if ((x + z) / 4) % 2 == 0 and z >= -6 then
				span("Tile", x, 0.1, z, x + 4, 0.2, z + 4, Color3.fromRGB(214, 206, 192), Enum.Material.Marble)
			end
		end
	end
	-- kitchen floor (anti-slip steel look)
	span("KitchenFloor", -30, 0.1, -20, 12, 0.2, -6, Color3.fromRGB(150, 150, 154), Enum.Material.DiamondPlate)
	span("StorageFloor", 12, 0.1, -26, 30, 0.2, -8, Color3.fromRGB(120, 110, 100), Enum.Material.Concrete)

	local H = 14
	-- back & side walls
	span("WallBackKitchen", -31, 0, -21, 12, H, -20, C.wall, Enum.Material.Plaster)
	span("WallLeft", -31, 0, -20, -30, H, 20.5, C.wall, Enum.Material.Plaster)
	span("WallRight", 30, 0, -20, 31, H, 20.5, C.wall, Enum.Material.Plaster)
	-- red wainscot strip on dining walls
	span("Wainscot", -29.95, 0.2, -6, -29.8, 4, 19.5, C.wallAccent, Enum.Material.SmoothPlastic)
	span("WainscotR", 29.8, 0.2, -8, 29.95, 4, 19.5, C.wallAccent, Enum.Material.SmoothPlastic)
	-- kitchen wall tiles
	span("KitchenTiles", -30, 3.6, -19.98, 12, 9, -19.9, C.white, Enum.Material.Marble)

	-- front wall with door opening x[11,17] and big windows
	span("FrontPillarL", -31, 0, 19.5, -28, H, 20.5, C.wallAccent, Enum.Material.Brick)
	span("FrontPillarM", 9, 0, 19.5, 11, H, 20.5, C.wallAccent, Enum.Material.Brick)
	span("FrontPillarM2", 17, 0, 19.5, 19, H, 20.5, C.wallAccent, Enum.Material.Brick)
	span("FrontPillarR", 28, 0, 19.5, 31, H, 20.5, C.wallAccent, Enum.Material.Brick)
	span("FrontSillL", -28, 0, 19.5, 9, 2.4, 20.5, C.wallAccent, Enum.Material.Brick)
	span("FrontSillR", 19, 0, 19.5, 28, 2.4, 20.5, C.wallAccent, Enum.Material.Brick)
	span("FrontLintel", -28, 11, 19.5, 28, H, 20.5, C.wallAccent, Enum.Material.Brick)
	span("WindowL", -28, 2.4, 19.85, 9, 11, 20.15, C.glass, Enum.Material.Glass, { Transparency = 0.75, Reflectance = 0.15 })
	span("WindowR", 19, 2.4, 19.85, 28, 11, 20.15, C.glass, Enum.Material.Glass, { Transparency = 0.75, Reflectance = 0.15 })
	for x = -19, 9, 9.25 do
		span("Mullion", x - 0.15, 2.4, 19.8, x + 0.15, 11, 20.2, C.black, Enum.Material.Metal)
	end
	span("DoorFrameTop", 11, 10, 19.4, 17, 11, 20.6, C.black, Enum.Material.Metal)
	-- window lettering
	local wl = span("WindowLetter", -24, 8.6, 20.2, -4, 10.4, 20.25, C.white, nil, { Transparency = 1, CanCollide = false })
	surfaceText(wl, Enum.NormalId.Back, "DÖNER · DÜRÜM · AYRAN", C.gold, nil, Enum.Font.GothamBlack)
	surfaceText(wl, Enum.NormalId.Front, "DÖNER · DÜRÜM · AYRAN", C.gold, nil, Enum.Font.GothamBlack)

	-- key switch next to the door: lock up after closing time to end the day
	local lockPlate = part("DoorLock", Vector3.new(0.8, 1.2, 0.12), at(10.1, 4.6, 19.44), C.steel, Enum.Material.Metal)
	part("KeyCylinder", Vector3.new(0.28, 0.28, 0.14), at(10.1, 4.75, 19.35), Color3.fromRGB(200, 170, 80), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 90, 0), CanCollide = false })
	local lockLed = part("LockLed", Vector3.new(0.12, 0.12, 0.05), at(10.1, 4.3, 19.37), Color3.fromRGB(60, 220, 90), Enum.Material.Neon, { CanCollide = false })
	lockLed:SetAttribute("Led", true)
	station(lockPlate, "shop_lock")

	-- automatic sliding glass door
	local door = folder("Door", root)
	current = door
	local dl = span("DoorLeft", 11, 0.2, 19.9, 14, 10, 20.1, C.glass, Enum.Material.Glass, { Transparency = 0.55 })
	local dr = span("DoorRight", 14, 0.2, 19.9, 17, 10, 20.1, C.glass, Enum.Material.Glass, { Transparency = 0.55 })
	dl:SetAttribute("ClosedX", 12.5)
	dl:SetAttribute("OpenX", 9.6)
	dr:SetAttribute("ClosedX", 15.5)
	dr:SetAttribute("OpenX", 18.4)
	for _, d in ipairs({ dl, dr }) do
		local handle = part("Handle", Vector3.new(0.15, 2.5, 0.4), d.CFrame * at(d.Name == "DoorLeft" and 1.2 or -1.2, -0.5, 0), C.steel, Enum.Material.Metal, { CanCollide = false })
		local w = Instance.new("WeldConstraint")
		w.Part0 = d
		w.Part1 = handle
		w.Parent = handle
		handle.Anchored = false
		handle.Massless = true
		handle.Parent = d
	end
	local hours = span("OpeningHours", 11.6, 6, 20.12, 13.4, 8, 20.13, C.white, nil, { CanCollide = false })
	hours.Parent = dl
	surfaceText(hours, Enum.NormalId.Back, "MO–SO\n10–22 Uhr", C.black, C.white, Enum.Font.Gotham)
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = dl
	w2.Part1 = hours
	w2.Parent = hours
	hours.Anchored = false
	hours.Massless = true
	current = shell

	-- storage room x[12,30] z[-26,-8]: it reaches 6 studs further back than the kitchen, so the
	-- cold-room door (Server/ColdRoomService) swings open in front of the shelves, not into them.
	-- "WallBack" is its back wall (Server/BackDoorService cuts the back door into it).
	span("WallBack", 11, 0, -27, 31, H, -26, C.wall, Enum.Material.Plaster)
	span("StorageWallWOut", 11, 0, -26, 12, H, -21, C.wall, Enum.Material.Plaster)
	span("WallRightBack", 30, 0, -26, 31, H, -20, C.wall, Enum.Material.Plaster)
	-- partition walls; opening in x=12 wall at z[-12.5,-9]
	span("StorageWallW1", 12, 0, -26, 12.6, H, -12.5, C.wall, Enum.Material.Plaster)
	span("StorageWallW2", 12, 0, -9, 12.6, H, -8, C.wall, Enum.Material.Plaster)
	span("StorageWallW3", 12, 9, -12.5, 12.6, H, -9, C.wall, Enum.Material.Plaster)
	span("StorageWallN", 12, 0, -8.6, 30, H, -8, C.wall, Enum.Material.Plaster)
	span("StaffSign", 12.65, 9.6, -12.2, 12.7, 10.8, -9.3, C.black, nil, { CanCollide = false })
	surfaceText(current:FindFirstChild("StaffSign") :: BasePart, Enum.NormalId.Left, "LAGER / PERSONAL", C.white, C.black)

	-- ceiling & roof
	span("Ceiling", -31, H, -21, 31, H + 0.6, 20.5, Color3.fromRGB(250, 246, 238), Enum.Material.SmoothPlastic)
	-- upper floors of the building
	span("UpperFacade", -31, H, 19.5, 31, 40, 20.5, Color3.fromRGB(226, 206, 170), Enum.Material.Plaster)
	span("UpperBody", -31, H + 0.6, -21, 31, 40, 19.5, Color3.fromRGB(226, 206, 170), Enum.Material.Plaster)
	-- the deeper storage room sticks out of the back of the building as a flat-roofed annex
	span("CeilingStorage", 11, H, -27, 31, H + 0.6, -21, Color3.fromRGB(250, 246, 238), Enum.Material.SmoothPlastic)
	span("StorageRoof", 11, H + 0.6, -27.2, 31, H + 1, -21, Color3.fromRGB(226, 206, 170), Enum.Material.Plaster)
	span("Cornice", -31.5, 39, 19.4, 31.5, 40.4, 21.2, C.white, Enum.Material.Plaster)
	for floor = 0, 2 do
		for wx = -26, 22, 8 do
			local y = 19 + floor * 7
			span("UpperWindow", wx, y, 20.45, wx + 4, y + 4.6, 20.6, Color3.fromRGB(60, 80, 100), Enum.Material.Glass, { Reflectance = 0.25 })
			span("UpperSill", wx - 0.3, y - 0.4, 20.4, wx + 4.3, y, 21.0, C.white, Enum.Material.Plaster)
			span("Shutter", wx - 0.9, y, 20.5, wx - 0.3, y + 4.6, 20.7, Color3.fromRGB(70, 110, 80), Enum.Material.Wood)
			span("Shutter", wx + 4.3, y, 20.5, wx + 4.9, y + 4.6, 20.7, Color3.fromRGB(70, 110, 80), Enum.Material.Wood)
		end
	end

	-- shop sign and awning
	local sign = span("ShopSign", -26, 11.4, 20.6, 8, 13.8, 21.4, C.wallAccent, Enum.Material.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Back, "KEBAP HAUS", C.white, nil, Enum.Font.GothamBlack, 30)
	local neon = span("SignNeonStrip", -26, 11.2, 21.3, 8, 11.4, 21.5, C.gold, Enum.Material.Neon)
	neon:SetAttribute("NightLight", true)
	local sub = span("ShopSubSign", 19, 11.6, 20.6, 28, 13.6, 21.2, C.black, Enum.Material.SmoothPlastic)
	surfaceText(sub, Enum.NormalId.Back, "seit 1998 · Wien", C.gold, nil, Enum.Font.Gotham)
	for i = 0, 11 do
		local x = -26 + i * 3
		local col = i % 2 == 0 and C.wallAccent or C.white
		part("Awning", Vector3.new(3, 0.2, 4), at(x + 1.5, 10.6, 22.4) * CFrame.Angles(math.rad(-20), 0, 0), col, Enum.Material.Fabric, { CanCollide = false })
	end
	-- open sign (lit by RestaurantService)
	local openSign = span("OpenSign", 20, 7.4, 20.2, 24, 8.8, 20.3, C.black, Enum.Material.SmoothPlastic, { CanCollide = false })
	openSign.Parent = root
	surfaceText(openSign, Enum.NormalId.Back, "GEÖFFNET", Color3.fromRGB(255, 70, 60), C.black, Enum.Font.GothamBlack)
	-- outdoor menu stand
	local stand = part("MenuStand", Vector3.new(2.4, 3.6, 0.3), at(6, 2.3, 24) * CFrame.Angles(math.rad(-10), math.rad(15), 0), C.black, Enum.Material.Slate)
	surfaceText(stand, Enum.NormalId.Back, "HEUTE:\nDürüm\n+ Ayran\n€9,50", C.white, nil, Enum.Font.Cartoon)
	plant(-29, 23, 1)
	plant(26, 23, 1)
	-- benches out front
	part("BenchFront", Vector3.new(6, 0.4, 1.6), at(-14, 2, 23), C.wood, Enum.Material.WoodPlanks)
	part("BenchLeg", Vector3.new(0.3, 1.5, 1.4), at(-16.5, 1.2, 23), C.black, Enum.Material.Metal)
	part("BenchLeg", Vector3.new(0.3, 1.5, 1.4), at(-11.5, 1.2, 23), C.black, Enum.Material.Metal)
	-- bins outside
	part("StreetBin", Vector3.new(1.6, 3, 1.6), at(4, 2, 30.5), Color3.fromRGB(240, 120, 30), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })
end

-- Realistic laptop (aluminium unibody, keyboard + touchpad, hinged lid). The live screen content is
-- drawn by each client (SurfaceGui on the part tagged "LaptopScreen").
local function buildLaptop(parent: Instance, top: number)
	local m = folder("Laptop", parent)
	local prev = current
	current = m
	local ALU = Color3.fromRGB(150, 153, 158)
	local DARK = Color3.fromRGB(28, 29, 32)
	-- base sits on the counter left of the register spot (so it never blocks the view of the customer),
	-- turned towards the cashier; keyboard side towards the kitchen, hinge towards the customers
	local baseCF = at(1.6, top + 0.045, -6.4) * CFrame.Angles(0, math.rad(-25), 0)
	-- rotated 90° so the Top-face SurfaceGui reads keyboard → hinge side, touchpad → user side
	local base = part("Base", Vector3.new(1.45, 0.09, 2.1), baseCF * CFrame.Angles(0, math.rad(90), 0), ALU, Enum.Material.Metal, { Reflectance = 0.08 })
	part("Foot", Vector3.new(1.9, 0.02, 1.3), baseCF * at(0, -0.05, 0), DARK, Enum.Material.Rubber, { CanCollide = false })
	-- keyboard & touchpad drawn on the deck
	local deck = Instance.new("SurfaceGui")
	deck.Name = "Deck"
	deck.Face = Enum.NormalId.Top
	deck.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	deck.PixelsPerStud = 120
	deck.LightInfluence = 1
	deck.Parent = base
	local kb = Instance.new("Frame")
	kb.Name = "Keyboard"
	kb.AnchorPoint = Vector2.new(0.5, 0)
	kb.Position = UDim2.fromScale(0.5, 0.04)
	kb.Size = UDim2.fromScale(0.86, 0.42)
	kb.BackgroundColor3 = Color3.fromRGB(118, 121, 126)
	kb.BorderSizePixel = 0
	kb.Parent = deck
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0, 6)
	kc.Parent = kb
	local rows = { 14, 14, 13, 12, 8 }
	for r, n in ipairs(rows) do
		local y = (r - 1) / #rows
		for k = 1, n do
			local key = Instance.new("Frame")
			key.BorderSizePixel = 0
			key.BackgroundColor3 = Color3.fromRGB(24, 25, 28)
			local w = 1 / 14
			local x = (k - 1) * w + (14 - n) * w / 2
			local width = w
			if r == 5 then
				-- bottom row: 3 keys, space bar, 4 keys
				if k <= 3 then
					x = 0.5 * w + (k - 1) * w
				elseif k == 4 then
					x, width = 3.5 * w, 6 * w
				else
					x = 9.5 * w + (k - 5) * w
				end
			end
			key.Position = UDim2.new(x, 2, y, 2)
			key.Size = UDim2.new(width, -4, 1 / #rows, -4)
			key.Parent = kb
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 3)
			c.Parent = key
		end
	end
	local pad = Instance.new("Frame")
	pad.Name = "Touchpad"
	pad.AnchorPoint = Vector2.new(0.5, 0)
	pad.Position = UDim2.fromScale(0.5, 0.52)
	pad.Size = UDim2.fromScale(0.38, 0.24)
	pad.BackgroundColor3 = Color3.fromRGB(138, 141, 146)
	pad.BorderSizePixel = 0
	pad.Parent = deck
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 8)
	pc.Parent = pad
	-- hinged lid, opened ~105°
	local hinge = baseCF * at(0, 0.045, 0.7)
	local lidCF = hinge * CFrame.Angles(math.rad(15), 0, 0) * at(0, 0.68, 0)
	local lid = part("Lid", Vector3.new(2.1, 1.36, 0.05), lidCF, ALU, Enum.Material.Metal, { Reflectance = 0.08, CanCollide = false })
	part("Hinge", Vector3.new(1.7, 0.08, 0.08), hinge * at(0, 0.02, 0), DARK, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 0), CanCollide = false })
	-- black bezel + display panel on the inside of the lid
	local bezel = part("Bezel", Vector3.new(2.06, 1.32, 0.01), lidCF * at(0, 0, -0.03), Color3.fromRGB(8, 8, 10), Enum.Material.Glass, { CanCollide = false, Reflectance = 0.05 })
	bezel.CastShadow = false
	local screen = part("LaptopScreen", Vector3.new(1.9, 1.12, 0.01), lidCF * at(0, 0.03, -0.04), Color3.fromRGB(5, 6, 8), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
	CollectionService:AddTag(screen, "LaptopScreen")
	part("Webcam", Vector3.new(0.035, 0.035, 0.01), lidCF * at(0, 0.62, -0.04), Color3.fromRGB(30, 40, 50), Enum.Material.Glass, { CanCollide = false, CastShadow = false })
	-- glowing logo on the back of the lid (seen by customers)
	local logo = Instance.new("SurfaceGui")
	logo.Name = "Logo"
	logo.Face = Enum.NormalId.Back
	logo.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	logo.PixelsPerStud = 80
	logo.LightInfluence = 0
	logo.Parent = lid
	local lt = Instance.new("TextLabel")
	lt.BackgroundTransparency = 1
	lt.AnchorPoint = Vector2.new(0.5, 0.5)
	lt.Position = UDim2.fromScale(0.5, 0.5)
	lt.Size = UDim2.fromScale(0.3, 0.3)
	lt.Text = "◆"
	lt.TextScaled = true
	lt.TextColor3 = Color3.fromRGB(245, 245, 250)
	lt.TextTransparency = 0.15
	lt.Font = Enum.Font.GothamBlack
	lt.Parent = logo
	-- interaction volume
	local point = part("LaptopPoint", Vector3.new(2.6, 2, 2.2), baseCF * at(0, 0.8, -0.2), C.white, nil, { Transparency = 1, CanCollide = false })
	station(point, "laptop")
	current = prev
	return m
end

local function buildKitchen(root, stations)
	local kitchen = folder("Kitchen", root)
	current = kitchen
	local TOP = 3.6
	-- back counter x[-28,1] z[-19,-16]
	span("BackCounterBody", -28, 0.2, -19.4, 1, TOP - 0.3, -16, C.steel, Enum.Material.Metal)
	span("BackCounterTop", -28.1, TOP - 0.3, -19.5, 1.1, TOP, -15.9, C.steel, Enum.Material.Metal, { Reflectance = 0.15 })
	for x = -27, 0, 3 do
		span("DrawerLine", x, 0.6, -15.98, x + 0.05, TOP - 0.5, -15.95, C.darkSteel, Enum.Material.Metal, { CanCollide = false })
	end
	-- front counter x[-28,9] z[-7.5,-4.5]
	span("FrontCounterBody", -28, 0.2, -7.5, 9, TOP - 0.3, -4.5, C.wood, Enum.Material.WoodPlanks)
	span("FrontCounterFace", -28, 0.2, -4.5, 9, TOP - 0.3, -4.3, C.wallAccent, Enum.Material.SmoothPlastic)
	span("FrontCounterTop", -28.2, TOP - 0.3, -7.6, 9.2, TOP, -4.2, C.marble, Enum.Material.Marble, { Reflectance = 0.05 })
	span("FrontCounterKick", -28, 0.2, -4.3, 9, 0.8, -4.2, C.black, Enum.Material.Metal)
	-- customer-side glass display & tray rail near pickup
	span("TrayRail", -16.4, 2.3, -4.2, -6.6, 2.5, -3.6, C.steel, Enum.Material.Metal)
	-- end side panel at kitchen opening
	span("CounterEnd", 9, 0.2, -7.6, 9.3, TOP, -4.2, C.wallAccent, Enum.Material.SmoothPlastic)
	-- customer blocker in kitchen opening x[9,12] (only blocks NPC customers)
	local blocker = span("CustomerBlocker", 9.3, 0, -8, 12, 8, -7.6, C.white, nil, { Transparency = 1, CanQuery = false })
	blocker:SetAttribute("NPCBlocker", true)
	local blocker2 = span("CustomerBlocker", -30, 0, -6.5, 12, 8, -6.2, C.white, nil, { Transparency = 1, CanQuery = false })
	blocker2:SetAttribute("NPCBlocker", true)
	blocker2.CanCollide = false -- only a pathfinding hint; the counter itself blocks

	-- extraction hood over the spits
	span("Hood", -28, 10, -20, -15, 11.2, -15, C.steel, Enum.Material.Metal, { Reflectance = 0.1 })
	part("HoodSlant", Vector3.new(13, 0.3, 3.2), at(-21.5, 9.6, -15.4) * CFrame.Angles(math.rad(35), 0, 0), C.steel, Enum.Material.Metal)

	-- vertical spits
	local function spit(meat: string, x: number, color: Color3)
		local m = folder("Spit_" .. meat, kitchen)
		local prev = current
		current = m
		local z = -17.9
		-- proportions: the meat hangs between the cook's chest and a bit above the head
		part("Base", Vector3.new(3, 0.3, 3), at(x, TOP + 0.15, z), C.darkSteel, Enum.Material.Metal)
		part("DripTray", Vector3.new(2.8, 0.12, 2.8), at(x, TOP + 0.36, z), C.steel, Enum.Material.Metal)
		part("Rod", Vector3.new(0.22, 3.2, 0.22), at(x, TOP + 1.7, z), C.steel, Enum.Material.Metal)
		part("TopCap", Vector3.new(0.9, 0.25, 0.9), at(x, TOP + 3.2, z), C.steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })
		-- meat cone: stacked cylinders, tapered toward the bottom, slightly irregular like real döner
		local rotor = Instance.new("Model")
		rotor.Name = "Meat"
		rotor.Parent = m
		local layers = 7
		for i = 1, layers do
			local t = (i - 1) / (layers - 1)
			local d = 2.45 - t * 0.6 + math.sin(i * 2.3) * 0.05
			local layer = Instance.new("Part")
			layer.Name = "Layer"
			layer.Anchored = true
			layer.CanCollide = false
			layer.Shape = Enum.PartType.Cylinder
			layer.Size = Vector3.new(0.36, d, d)
			layer.CFrame = at(x, TOP + 2.75 - (i - 1) * 0.35, z) * CFrame.Angles(0, math.rad(i * 37), math.rad(90))
			layer.Color = color
			layer.Material = Enum.Material.Sand
			layer.TopSurface = Enum.SurfaceType.Smooth
			layer.BottomSurface = Enum.SurfaceType.Smooth
			layer:SetAttribute("BaseDiameter", d)
			layer.Parent = rotor
		end
		rotor:SetAttribute("SpinX", x)
		rotor:SetAttribute("SpinZ", z)
		CollectionService:AddTag(rotor, "SpitRotor")
		-- vertical burner behind
		part("BurnerFrame", Vector3.new(2.8, 3.6, 0.4), at(x, TOP + 1.95, -19.6), C.darkSteel, Enum.Material.Metal)
		local burner = part("Burner", Vector3.new(2.2, 3.0, 0.15), at(x, TOP + 1.95, -19.35), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
		local fl = light(burner, 10, 1.5, Color3.fromRGB(255, 130, 60))
		fl.Name = "Glow"
		-- name plate
		local plate = part("Plate", Vector3.new(2.2, 0.5, 0.1), at(x, TOP + 0.3, z + 1.55), C.black, Enum.Material.SmoothPlastic, { CanCollide = false })
		surfaceText(plate, Enum.NormalId.Back, meat == "chicken" and "HÄHNCHEN" or "KALB", C.gold)
		-- interaction parts: carve (front) and heat knob (side)
		-- kept at eye height: a prompt only shows while its part is on screen
		local carve = part("CarvePoint", Vector3.new(2.4, 2.2, 1), at(x, TOP + 1.6, z + 1.25), C.white, nil, { Transparency = 1, CanCollide = false })
		station(carve, "spit", meat)
		local knob = part("HeatKnob", Vector3.new(0.5, 0.5, 0.5), at(x + 1.3, TOP + 0.3, z + 1.55), Color3.fromRGB(200, 40, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
		station(knob, "spit_heat", meat)
		m:SetAttribute("Meat", meat)
		CollectionService:AddTag(m, "Spit")
		WorldBuilder.ApplySpitModel(m)
		current = prev
		return m
	end
	stations.spitChicken = spit("chicken", -25, Color3.fromRGB(226, 184, 140))
	stations.spitVeal = spit("veal", -18.5, Color3.fromRGB(180, 110, 90))
	unlockable(stations.spitVeal, "spit_veal")

	-- wooden cook's deck in front of the spits (like the duckboards in real kebab shops): the cook
	-- stands a bit higher so the knife reaches the middle of the meat
	local DECK = 0.6
	local deck = span("CookDeck", -27.8, 0.2, -15.85, -15.2, 0.2 + DECK, -12.6, Color3.fromRGB(128, 88, 56), Enum.Material.WoodPlanks)
	deck:SetAttribute("CookDeck", true)
	for zz = -15.5, -12.9, 0.65 do
		span("DeckSlat", -27.8, 0.2 + DECK, zz, -15.2, 0.2 + DECK + 0.02, zz + 0.08, Color3.fromRGB(70, 48, 30), Enum.Material.WoodPlanks, { CanCollide = false })
	end
	-- gentle ramps so walking on and off never snags
	local function ramp(name: string, size: Vector3, cf: CFrame)
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Anchored = true
		w.Size = size
		w.CFrame = cf
		w.Color = Color3.fromRGB(128, 88, 56)
		w.Material = Enum.Material.WoodPlanks
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Parent = current
		return w
	end
	-- front ramp (high side towards the deck at -Z) and side ramp (high side towards -X)
	ramp("DeckRampFront", Vector3.new(12.6, DECK, 1.2), at(-21.5, 0.2 + DECK / 2, -12.0) * CFrame.Angles(0, math.rad(180), 0))
	ramp("DeckRampSide", Vector3.new(3.25, DECK, 1.2), at(-14.6, 0.2 + DECK / 2, -14.225) * CFrame.Angles(0, math.rad(-90), 0))

	-- bread station: three big crates on back counter, between the veal spit and the contact grill
	local breads = { { "classic", -15.45, Color3.fromRGB(222, 184, 120) }, { "duerum", -13.0, Color3.fromRGB(236, 214, 164) }, { "box", -10.55, C.white } }
	for _, b in ipairs(breads) do
		local unit = folder("BreadUnit_" .. b[1], kitchen)
		if BREAD_UNLOCK[b[1]] then
			unlockable(unit, BREAD_UNLOCK[b[1]])
		end
		current = unit
		local bin = part("BreadBin_" .. b[1], Vector3.new(2.3, 1.1, 3.2), at(b[2], TOP + 0.55, -17.6), C.wood, Enum.Material.WoodPlanks)
		station(bin, "bread", b[1])
		for k = 0, 2 do
			if b[1] == "box" then
				part("Box", Vector3.new(1.2, 0.5, 1.6), at(b[2], TOP + 1.0 + k * 0.5, -17.6), C.white, Enum.Material.SmoothPlastic, { CanCollide = false })
			elseif b[1] == "duerum" then
				part("Flatbread", Vector3.new(0.1, 1.5, 1.5), at(b[2], TOP + 0.95 + k * 0.12, -17.6) * CFrame.Angles(0, 0, math.rad(90)), b[3], Enum.Material.Sand, { Shape = Enum.PartType.Cylinder, CanCollide = false })
			else
				part("Bread", Vector3.new(1.3, 0.5, 0.9), at(b[2], TOP + 1.1 + k * 0.4, -17.6 - 0.4 + k * 0.4), b[3], Enum.Material.Sand, { CanCollide = false })
			end
		end
		local label = part("Label", Vector3.new(1.5, 0.35, 0.05), at(b[2], TOP + 0.65, -15.98), C.black, nil, { CanCollide = false })
		surfaceText(label, Enum.NormalId.Back, b[1] == "classic" and "BROT" or (b[1] == "duerum" and "DÜRÜM" or "BOX"), C.white)
		current = kitchen
	end

	-- contact grill with two slots (bought at level 4)
	current = unlockable(folder("Grill", kitchen), "grill")
	part("GrillBody", Vector3.new(4.4, 1, 2.6), at(-7, TOP + 0.5, -17.6), C.darkSteel, Enum.Material.Metal)
	for i, x in ipairs({ -8, -6 }) do
		local plate = part("GrillPlate" .. i, Vector3.new(1.8, 0.1, 2.2), at(x, TOP + 1.05, -17.6), C.black, Enum.Material.Metal)
		station(plate, "grill", nil, { Slot = i })
		local lid = part("GrillLid" .. i, Vector3.new(1.8, 0.3, 2.2), at(x, TOP + 1.25, -18.7) * CFrame.Angles(math.rad(75), 0, 0) * at(0, 0, 1.1), C.steel, Enum.Material.Metal, { CanCollide = false })
		lid:SetAttribute("Slot", i)
		local lamp = part("GrillLamp" .. i, Vector3.new(0.25, 0.25, 0.1), at(x, TOP + 0.6, -16.28), Color3.fromRGB(40, 40, 40), Enum.Material.Neon, { CanCollide = false })
		lamp:SetAttribute("Slot", i)
	end
	part("GrillHandle", Vector3.new(3.6, 0.15, 0.15), at(-7, TOP + 1.0, -16.2), C.black, Enum.Material.Metal)
	current = kitchen

	-- sink
	span("Sink", -4, TOP - 0.1, -19, -1, TOP + 0.05, -16.6, C.darkSteel, Enum.Material.Metal)
	part("Faucet", Vector3.new(0.2, 1.6, 0.2), at(-2.5, TOP + 0.8, -18.8), C.steel, Enum.Material.Metal)
	part("FaucetArm", Vector3.new(0.2, 0.2, 1), at(-2.5, TOP + 1.6, -18.4), C.steel, Enum.Material.Metal)
	-- utensils rail and knives on wall
	span("Rail", -14, 6.5, -19.9, -4, 6.7, -19.7, C.steel, Enum.Material.Metal)
	for x = -13, -5, 1.6 do
		part("Utensil", Vector3.new(0.15, 1.6, 0.05), at(x, 5.8, -19.75), C.steel, Enum.Material.Metal, { CanCollide = false })
	end
	-- shelf with jars
	span("WallShelf", -14, 8.2, -19.9, 0, 8.4, -18.9, C.steel, Enum.Material.Metal)
	for x = -13.4, -0.8, 1.2 do
		local col = ({ Color3.fromRGB(200, 60, 30), Color3.fromRGB(220, 170, 50), Color3.fromRGB(120, 160, 60), C.white })[(math.floor(x) % 4) + 1]
		part("Jar", Vector3.new(0.8, 0.7, 0.7), at(x, 8.8, -19.4), col, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90), Transparency = 0.2, CanCollide = false })
	end

	-- drinks fridge x[2,6] (bought at level 12)
	current = unlockable(folder("Fridge", kitchen), "drinks")
	local fr = span("DrinksFridge", 2, 0.2, -19.6, 6.2, 8.5, -16.6, C.darkSteel, Enum.Material.Metal)
	span("FridgeGlass", 2.2, 0.8, -16.62, 6, 8, -16.5, C.glass, Enum.Material.Glass, { Transparency = 0.6, CanCollide = false })
	local fridgeLight = span("FridgeLight", 2.3, 7.6, -17, 5.9, 7.8, -16.8, C.white, Enum.Material.Neon, { CanCollide = false })
	light(fridgeLight, 6, 0.8, Color3.fromRGB(220, 240, 255))
	local topSign = part("FridgeTop", Vector3.new(4.2, 0.8, 0.1), at(4.1, 8.1, -16.45), Color3.fromRGB(200, 30, 40), Enum.Material.SmoothPlastic, { CanCollide = false })
	surfaceText(topSign, Enum.NormalId.Back, "GETRÄNKE", C.white)
	local drinkRows = { { "ayran", 6.6, C.white }, { "cola", 4.4, Color3.fromRGB(180, 20, 30) }, { "almdudler", 2.2, Color3.fromRGB(240, 200, 60) } }
	for _, d in ipairs(drinkRows) do
		local shelf = span("Shelf_" .. d[1], 2.3, d[2] - 0.6, -19.2, 5.9, d[2] + 0.9, -16.9, Color3.fromRGB(230, 236, 240), Enum.Material.SmoothPlastic, { Transparency = 0.9, CanCollide = false })
		station(shelf, "drink", d[1])
		for k = 0, 4 do
			part("Bottle", Vector3.new(1.0, 0.45, 0.45), at(2.7 + k * 0.75, d[2] + 0.1, -17.4), d[3], Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90), CanCollide = false })
		end
	end
	fr:SetAttribute("Decor", true)
	current = kitchen

	-- trash bin
	local bin = part("TrashBin", Vector3.new(1.6, 2.6, 1.6), at(7.6, 1.5, -17.5), Color3.fromRGB(70, 70, 75), Enum.Material.Metal)
	part("TrashLid", Vector3.new(1.7, 0.2, 1.7), at(7.6, 2.9, -17.5), C.black, Enum.Material.Metal)
	station(bin, "trash")

	-- salad bar on front counter (kitchen side), refrigerated with glass guard
	span("SaladBarBase", -27.6, TOP, -7.3, -16.6, TOP + 0.2, -5.6, C.steel, Enum.Material.Metal)
	span("SneezeGuard", -27.6, TOP + 1.4, -5.3, -16.6, TOP + 1.5, -4.4, C.glass, Enum.Material.Glass, { Transparency = 0.6, CanCollide = false })
	for x = -27.4, -17, 2.08 do
		part("GuardPost", Vector3.new(0.1, 1.5, 0.1), at(x, TOP + 0.75, -5.1), C.steel, Enum.Material.Metal, { CanCollide = false })
	end
	local vegs = {
		{ "lettuce", Color3.fromRGB(120, 190, 70) },
		{ "tomato", Color3.fromRGB(215, 50, 40) },
		{ "onion", Color3.fromRGB(225, 200, 230) },
		{ "cabbage", Color3.fromRGB(130, 40, 110) },
		{ "cucumber", Color3.fromRGB(70, 140, 60) },
		{ "cheese", Color3.fromRGB(250, 250, 240) },
	}
	for i, v in ipairs(vegs) do
		local x = -26.7 + (i - 1) * 1.8
		local tray = part("Bin_" .. v[1], Vector3.new(1.6, 0.4, 1.4), at(x, TOP + 0.4, -6.5), C.steel, Enum.Material.Metal)
		local fill = part("Fill", Vector3.new(1.4, 0.15, 1.2), at(x, TOP + 0.62, -6.5), v[2], Enum.Material.Grass, { CanCollide = false })
		fill.Parent = tray
		station(tray, v[1] == "cheese" and "cheese" or "veg", v[1])
		-- small name tag on the staff side of each tray
		local tag = part("Tag", Vector3.new(1.5, 0.3, 0.05), at(x, TOP - 0.5, -7.65), C.black, nil, { CanCollide = false })
		tag.Parent = tray
		surfaceText(tag, Enum.NormalId.Front, ({ lettuce = "SALAT", tomato = "TOMATE", onion = "ZWIEBEL", cabbage = "ROTKRAUT", cucumber = "GURKE", cheese = "KÄSE" })[v[1]], C.white)
		if VEG_UNLOCK[v[1]] then
			unlockable(tray, VEG_UNLOCK[v[1]])
		end
	end

	-- prep boards (two players can prepare at once)
	for i, x in ipairs({ -13.6, -10 }) do
		local board = part("PrepBoard" .. i, Vector3.new(3, 0.2, 2), at(x, TOP + 0.1, -6.6), Color3.fromRGB(240, 240, 235), Enum.Material.SmoothPlastic)
		station(board, "board", nil, { Board = i })
		local foil = part("FoilRoll", Vector3.new(2.6, 0.4, 0.4), at(x, TOP + 0.2, -7.3), C.steel, Enum.Material.Foil, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		foil:SetAttribute("Board", i)
	end
	-- packaging shelf (bags & plates)
	part("Bags", Vector3.new(1.2, 0.8, 1.4), at(-7.6, TOP + 0.4, -7), Color3.fromRGB(220, 200, 160), Enum.Material.Fabric)
	part("Plates", Vector3.new(1.2, 0.5, 1.2), at(-7.6, TOP + 0.25, -5.6), C.white, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })

	-- sauce dispensers
	local sauces = {
		{ "garlic", Color3.fromRGB(250, 248, 235) },
		{ "yogurt", Color3.fromRGB(240, 240, 250) },
		{ "cocktail", Color3.fromRGB(240, 150, 120) },
		{ "spicy", Color3.fromRGB(200, 30, 20) },
		{ "herb", Color3.fromRGB(190, 220, 160) },
	}
	span("SauceRack", -6.4, TOP, -7.4, -0.4, TOP + 0.3, -5.8, C.steel, Enum.Material.Metal)
	for i, s in ipairs(sauces) do
		local x = -5.8 + (i - 1) * 1.2
		local unit = folder("SauceUnit_" .. s[1], kitchen)
		if SAUCE_UNLOCK[s[1]] then
			unlockable(unit, SAUCE_UNLOCK[s[1]])
		end
		current = unit
		local bottle = part("Sauce_" .. s[1], Vector3.new(1.6, 0.8, 0.8), at(x, TOP + 1.1, -6.6), s[2], Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })
		part("Nozzle", Vector3.new(0.4, 0.25, 0.25), at(x, TOP + 2.1, -6.6), C.white, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90), CanCollide = false })
		station(bottle, "sauce", s[1])
		current = kitchen
	end

	-- order laptop (point of sale) – screen faces the kitchen, lid logo faces the customers
	buildLaptop(kitchen, TOP)
	-- small customer display showing the order total
	part("DisplayPole", Vector3.new(0.15, 0.9, 0.15), at(2.4, TOP + 0.45, -5.0), C.black, Enum.Material.Metal, { CanCollide = false })
	local screen = part("RegisterScreen", Vector3.new(1.5, 0.85, 0.1), at(2.4, TOP + 1.25, -5.0) * CFrame.Angles(math.rad(-10), math.rad(180), 0), C.black, Enum.Material.SmoothPlastic, { CanCollide = false })
	screen.Parent = root
	part("TipJar", Vector3.new(0.7, 0.9, 0.7), at(7.4, TOP + 0.45, -5.2), C.glass, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90), Transparency = 0.4 })
	part("CardTerminal", Vector3.new(0.5, 0.2, 0.9), at(7.8, TOP + 0.1, -6.4), C.black, Enum.Material.SmoothPlastic)

	-- menu boards above the back counter (filled by RestaurantService)
	local board = span("MenuBoard", -28, 10.6, -19.9, 0, 13.6, -19.7, C.black, Enum.Material.SmoothPlastic)
	board.Parent = root
	local board2 = span("PriceBoard", 2, 10.2, -19.9, 11, 13.6, -19.7, C.black, Enum.Material.SmoothPlastic)
	board2.Parent = root
	for _, b in ipairs({ board, board2 }) do
		local l = Instance.new("SurfaceLight")
		l.Face = Enum.NormalId.Back
		l.Range = 6
		l.Brightness = 0.6
		l.Angle = 120
		l.Color = Color3.fromRGB(255, 240, 220)
		l.Parent = b
	end
end

local function buildDining(root)
	local dining = folder("Dining", root)
	current = dining
	dinerTable("Table1", -24, 5, "x", 0, dining)
	dinerTable("Table2", -24, 13, "x", 0, dining)
	dinerTable("Table3", -16, 5, "x", 0, dining)
	dinerTable("Table4", -16, 13, "x", 0, dining)
	-- window bar with stools
	span("WindowBar", -28, 3.4, 18.2, -10, 3.7, 19.5, C.wood, Enum.Material.WoodPlanks)
	for x = -26, -12, 3.5 do
		part("Stool", Vector3.new(1.4, 0.3, 1.4), at(x, 2.6, 17.2), C.wallAccent, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })
		part("StoolLeg", Vector3.new(0.2, 2.4, 0.2), at(x, 1.4, 17.2), C.black, Enum.Material.Metal)
	end
	-- wall art & clocks on left wall
	local art = { "🕌 ISTANBUL", "🏰 WIEN", "⛰️ ANATOLIA" }
	for i, t in ipairs(art) do
		local frame = span("Picture", -29.95, 6, -2 + (i - 1) * 7, -29.7, 9.5, 2.5 + (i - 1) * 7, C.darkWood, Enum.Material.Wood)
		local inner = span("PictureInner", -29.7, 6.3, -1.7 + (i - 1) * 7, -29.65, 9.2, 2.2 + (i - 1) * 7, Color3.fromRGB(240, 220, 180))
		surfaceText(inner, Enum.NormalId.Right, t, C.darkWood, nil, Enum.Font.Fantasy)
		frame.CanCollide = false
	end
	-- trash station for guests
	part("GuestBin", Vector3.new(1.8, 3, 1.8), at(-28.8, 1.7, -3.5), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	-- condiments shelf
	span("NapkinShelf", -29.9, 3.4, -5.8, -28.6, 3.6, -2.4, C.darkWood, Enum.Material.Wood)
	plant(-28.5, 18, 0.9)
	plant(-9, 18.6, 0.8)
	-- ceiling fans
	for _, p in ipairs({ { -20, 9 }, { -6, 9 } }) do
		part("FanRod", Vector3.new(0.2, 1.5, 0.2), at(p[1], 13.2, p[2]), C.black, Enum.Material.Metal)
		local hub = part("FanHub", Vector3.new(0.8, 0.4, 0.8), at(p[1], 12.4, p[2]), C.darkWood, Enum.Material.Wood)
		for a = 0, 3 do
			local blade = part("FanBlade", Vector3.new(3.5, 0.1, 0.7), hub.CFrame * CFrame.Angles(0, math.rad(a * 90), 0) * at(1.9, 0, 0), C.darkWood, Enum.Material.Wood, { CanCollide = false })
			blade.Parent = hub
		end
		CollectionService:AddTag(hub, "Fan")
	end
end

local function buildUpgradeAreas(root)
	-- extra tables (tier 1 & 2)
	local extra = folder("ExtraTables", root)
	current = extra
	local t5 = dinerTable("Table5", -6, 14.5, "z", 1, extra)
	local t6 = dinerTable("Table6", -6, 4.5, "z", 2, extra)
	t5:SetAttribute("Tier", 1)
	t6:SetAttribute("Tier", 2)

	-- decor upgrade (tier 1: plants & art, tier 2: neon & lanterns)
	local decor = folder("DecorUpgrade", root)
	local d1 = folder("Tier1", decor)
	current = d1
	plant(-29, -5, 1.1)
	plant(8.5, 18.6, 0.9)
	plant(-10.5, 0.5, 0.7)
	local rug = span("Rug", -21, 0.2, 7.6, -19, 0.25, 10.4, Color3.fromRGB(150, 40, 40), Enum.Material.Fabric, { CanCollide = false })
	rug.Size = Vector3.new(14, 0.05, 2.4)
	rug.Position = Vector3.new(-20, 0.23, 9)
	for i = 0, 2 do
		local photo = span("Photo", 29.7, 6, -6 + i * 0, 29.95, 9, -6, C.darkWood)
		photo.Size = Vector3.new(0.2, 3, 4)
		photo.Position = Vector3.new(-29.85, 10.8, -1 + i * 7.5)
		local t = surfaceText(photo, Enum.NormalId.Right, ({ "🌯", "🥙", "🧆" })[i + 1], C.white, Color3.fromRGB(60, 30, 20))
		t.Parent = photo
	end
	local d2 = folder("Tier2", decor)
	current = d2
	local neon = span("NeonSign", -20, 9.6, 19.3, -12, 11, 19.4, Color3.fromRGB(255, 80, 160), Enum.Material.Neon, { CanCollide = false })
	surfaceText(neon, Enum.NormalId.Front, "♥ KEBAP ♥", C.white, nil, Enum.Font.Arcade)
	for x = -26, -6, 5 do
		part("LanternCord", Vector3.new(0.05, 2, 0.05), at(x, 13, 9), C.black, nil, { CanCollide = false })
		local lan = part("Lantern", Vector3.new(1, 1.3, 1), at(x, 11.6, 9), ({ Color3.fromRGB(220, 60, 40), Color3.fromRGB(40, 120, 200), Color3.fromRGB(230, 170, 40) })[(x % 3) + 1], Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false, Transparency = 0.15 })
		light(lan, 10, 0.6, lan.Color)
	end

	-- lounge renovation (x 19..29, z -7..18)
	local lounge = folder("Lounge", root)
	current = lounge
	local loungeOn = folder("Built", lounge)
	current = loungeOn
	span("LoungeFloor", 19, 0.2, -7.9, 29.9, 0.3, 18, Color3.fromRGB(110, 70, 50), Enum.Material.WoodPlanks)
	for i, z in ipairs({ -3, 6, 14 }) do
		local sofa = folder("Sofa" .. i, loungeOn)
		local prev = current
		current = sofa
		span("SofaSeat", 26, 0.3, z - 2.5, 29.5, 2, z + 2.5, Color3.fromRGB(120, 40, 50), Enum.Material.Fabric)
		span("SofaBack", 28.6, 2, z - 2.5, 29.6, 4.6, z + 2.5, Color3.fromRGB(120, 40, 50), Enum.Material.Fabric)
		span("LowTable", 22, 0.3, z - 1.4, 24.5, 1.8, z + 1.4, C.darkWood, Enum.Material.Wood)
		for k, sz in ipairs({ z - 1.2, z + 1.2 }) do
			local look = CFrame.lookAt(Vector3.new(27.2, 0, sz), Vector3.new(20, 0, sz))
			local sp = navPoint(sofa, "SeatPoint" .. k, Vector3.new(27.2, 2.1, sz), { Tier = 3 })
			sp.CFrame = look + Vector3.new(0, 1.85, 0)
			local side = sz < z and -1 or 1
			sp:SetAttribute("Entry", "LoungeEntry")
			sp:SetAttribute("A1", Vector3.new(20.5, 3.3, z + 2.5 * side))
			sp:SetAttribute("A2", Vector3.new(25.2, 3.3, z + 2.5 * side))
			sp:SetAttribute("A3", Vector3.new(25.2, 3.3, sz))
			CollectionService:AddTag(sp, "SeatPoint")
		end
		current = prev
	end
	plant(20, 17, 1)
	local loungeSign = span("LoungeSign", 29.8, 6, 0, 29.95, 9, 12, C.black, nil, { CanCollide = false })
	surfaceText(loungeSign, Enum.NormalId.Left, "LOUNGE", C.gold, nil, Enum.Font.Fantasy)
	local loungeOff = folder("Construction", lounge)
	current = loungeOff
	local sheet = span("ConstructionSheet", 18.6, 0.2, -7.9, 19, 13.9, 18.9, Color3.fromRGB(230, 230, 220), Enum.Material.Fabric, { Transparency = 0.15 })
	surfaceText(sheet, Enum.NormalId.Left, "🚧 RENOVIERUNG 🚧\nLounge kommt bald", Color3.fromRGB(60, 60, 60), nil, Enum.Font.GothamBold, 20)
end

local function buildStorage(root)
	local storage = folder("Storage", root)
	current = storage
	-- shelving with boxes
	for i, x in ipairs({ 15, 21 }) do
		span("ShelfFrame", x, 0.2, -25.8, x + 5, 9, -24, C.darkSteel, Enum.Material.Metal, { Transparency = 0.9 })
		for level = 0, 3 do
			local y = 0.6 + level * 2.3
			span("ShelfBoard", x, y, -25.8, x + 5, y + 0.2, -24, C.steel, Enum.Material.Metal)
			for b = 0, 2 do
				local col = ({ Color3.fromRGB(180, 140, 90), Color3.fromRGB(160, 120, 80), Color3.fromRGB(200, 170, 120) })[((b + level + i) % 3) + 1]
				part("Box", Vector3.new(1.4, 1.4, 1.4), at(x + 0.9 + b * 1.6, y + 0.9, -24.9), col, Enum.Material.Cardboard)
			end
		end
	end
	-- cold room door
	span("ColdRoomDoor", 29.6, 0.2, -18, 29.9, 9, -13, C.steel, Enum.Material.DiamondPlate)
	local cr = span("ColdRoomSign", 29.55, 9.5, -17, 29.6, 10.5, -14, Color3.fromRGB(40, 120, 200))
	surfaceText(cr, Enum.NormalId.Left, "KÜHLRAUM", C.white)
	-- (ordering and upgrades are laptop apps in the office – Server/OfficeService)
	-- staff corner: lockers, small table
	for i = 0, 3 do
		span("Locker", 26 + (i % 2) * 0, 0.2, -12 + i * 0.9, 29.8, 8, -11.2 + i * 0.9, Color3.fromRGB(80, 110, 150), Enum.Material.Metal)
	end
	span("StaffTable", 20, 2.8, -12.5, 23, 3.1, -10, C.wood, Enum.Material.Wood)
	part("StaffTableLeg", Vector3.new(0.3, 2.6, 0.3), at(21.5, 1.5, -11.2), C.black, Enum.Material.Metal)
	part("Mug", Vector3.new(0.4, 0.5, 0.4), at(21, 3.35, -11), C.white, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Orientation = Vector3.new(0, 0, 90) })
	-- delivery drop zone near back
	local drop = span("DeliveryArea", 13, 0.2, -16, 18, 0.25, -12.8, Color3.fromRGB(230, 200, 40), Enum.Material.SmoothPlastic, { CanCollide = false })
	drop.Transparency = 0.5
	-- storage light
	local sl = part("StorageLamp", Vector3.new(4, 0.2, 1), at(21, 13.8, -17), C.white, Enum.Material.Neon)
	light(sl, 22, 1.1, Color3.fromRGB(240, 245, 255), "spot")
end

local function buildLights(root)
	local lights = folder("Lights", root)
	current = lights
	-- warm pendant lights over the dining area
	for x = -24, 4, 7 do
		for _, z in ipairs({ 2, 12 }) do
			part("Cord", Vector3.new(0.05, 2.4, 0.05), at(x, 12.8, z), C.black, nil, { CanCollide = false })
			local shade = part("Shade", Vector3.new(1.6, 0.8, 1.6), at(x, 11.4, z), C.black, Enum.Material.Metal, { CanCollide = false })
			local bulb = part("Bulb", Vector3.new(0.6, 0.4, 0.6), at(x, 10.9, z), Color3.fromRGB(255, 220, 160), Enum.Material.Neon, { CanCollide = false, Shape = Enum.PartType.Ball })
			light(bulb, 18, 0.9, Color3.fromRGB(255, 205, 150), "spot")
			bulb.Parent = shade
		end
	end
	-- kitchen panel lights
	for x = -24, 6, 7.5 do
		local panel = part("KitchenPanel", Vector3.new(5, 0.2, 2), at(x, 13.85, -11.5), C.white, Enum.Material.Neon)
		light(panel, 16, 0.9, Color3.fromRGB(255, 240, 225), "spot")
	end
	-- counter downlights
	for x = -26, 6, 4 do
		local dl = part("Downlight", Vector3.new(0.8, 0.1, 0.8), at(x, 13.9, -6), Color3.fromRGB(255, 230, 190), Enum.Material.Neon)
		light(dl, 11, 0.6, Color3.fromRGB(255, 220, 170), "spot")
	end
	-- right side (queue area)
	for _, p in ipairs({ { 12, 0 }, { 12, 12 }, { 24, 4 }, { 24, 14 } }) do
		local dl = part("Downlight", Vector3.new(1, 0.1, 1), at(p[1], 13.9, p[2]), Color3.fromRGB(255, 230, 190), Enum.Material.Neon)
		light(dl, 18, 0.7, Color3.fromRGB(255, 220, 170), "spot")
	end
end

local function buildNav(root)
	local nav = Instance.new("Folder")
	nav.Name = "Nav"
	nav.Parent = root
	local Y = 3.2 -- HumanoidRootPart height for R15 default rigs standing on floor (y = 0.2)
	navPoint(nav, "SpawnL", Vector3.new(-92, 3.5, 26))
	navPoint(nav, "SpawnR", Vector3.new(92, 3.5, 26))
	navPoint(nav, "DoorOut", Vector3.new(14, 3.5, 25))
	navPoint(nav, "DoorIn", Vector3.new(14, Y, 16.5))
	navPoint(nav, "OrderSpot", Vector3.new(5, Y, -2.4))
	local queue = { { 5, 1.4 }, { 7.6, 4.8 }, { 10.2, 8.2 }, { 12.6, 11.6 }, { 14.6, 14.6 } }
	for i, q in ipairs(queue) do
		navPoint(nav, "Queue" .. i, Vector3.new(q[1], Y, q[2]))
	end
	-- pickup spots sit right in front of the prep boards, where the food gets wrapped & packed
	local pickup = { -10, -13.2, -7.6, -15.6 }
	for i, x in ipairs(pickup) do
		navPoint(nav, "Pickup" .. i, Vector3.new(x, Y, -2.4))
	end
	navPoint(nav, "AisleEntry", Vector3.new(-11, Y, 0))
	navPoint(nav, "AisleMid", Vector3.new(-11, Y, 9))
	navPoint(nav, "LoungeEntry", Vector3.new(16.6, Y, 2))
	navPoint(nav, "ExitA", Vector3.new(9, Y, -1))
	navPoint(nav, "ExitB", Vector3.new(16.6, Y, 9))
	navPoint(nav, "WakePoint", Vector3.new(14, 3.5, 28))
	navPoint(nav, "PedL", Vector3.new(-98, 3.5, 57))
	navPoint(nav, "PedR", Vector3.new(98, 3.5, 57))
	navPoint(nav, "PedL2", Vector3.new(-98, 3.5, 28.5))
	navPoint(nav, "PedR2", Vector3.new(98, 3.5, 28.5))
	-- queue floor markers
	current = root
	for i, q in ipairs(queue) do
		local m = part("QueueMarker", Vector3.new(1.6, 0.05, 1.6), at(q[1], 0.23, q[2]), C.gold, Enum.Material.SmoothPlastic, { CanCollide = false, Transparency = 0.3 })
		m:SetAttribute("Index", i)
		m.Parent = nav
	end
	local ws = part("PickupSign", Vector3.new(6, 1, 0.1), at(-11.6, 7.5, -4.4), C.black, nil, { CanCollide = false })
	surfaceText(ws, Enum.NormalId.Front, "ABHOLUNG / PICK-UP", C.gold)
	surfaceText(ws, Enum.NormalId.Back, "ABHOLUNG / PICK-UP", C.gold)
	local os = part("OrderSign", Vector3.new(4, 1, 0.1), at(5, 7.5, -4.4), Color3.fromRGB(200, 30, 40), nil, { CanCollide = false })
	surfaceText(os, Enum.NormalId.Front, "HIER BESTELLEN", C.white)
	surfaceText(os, Enum.NormalId.Back, "HIER BESTELLEN", C.white)
	for _, s in ipairs({ ws, os }) do
		part("Hanger", Vector3.new(0.05, 6, 0.05), s.CFrame * at(-1.5, 3.5, 0), C.black, nil, { CanCollide = false })
		part("Hanger", Vector3.new(0.05, 6, 0.05), s.CFrame * at(1.5, 3.5, 0), C.black, nil, { CanCollide = false })
	end
end

local function setupLighting()
	-- Technology can only be changed by Studio itself (not scripts); set it manually to Future for best results
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	Lighting.Ambient = Color3.fromRGB(70, 60, 55)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 115, 110)
	Lighting.Brightness = 2.2
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ClockTime = 12
	Lighting.GeographicLatitude = 48
	local cc = Lighting:FindFirstChild("KebapColor") or Instance.new("ColorCorrectionEffect")
	cc.Name = "KebapColor"
	cc.Saturation = 0.08
	cc.Contrast = 0.05
	cc.TintColor = Color3.fromRGB(255, 248, 238)
	cc.Parent = Lighting
end

function WorldBuilder.Build(yieldFn: (() -> ())?)
	local y = yieldFn or function() end
	local old = workspace:FindFirstChild("Restaurant")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "Restaurant"
	local stations = {}

	-- each section is parented separately to keep edit-time insertion cheap
	local sections = {
		function()
			buildStreet(root)
		end,
		function()
			buildShell(root)
		end,
		function()
			buildKitchen(root, stations)
		end,
		function()
			buildDining(root)
		end,
		function()
			buildUpgradeAreas(root)
		end,
		function()
			buildStorage(root)
		end,
		function()
			buildLights(root)
		end,
		function()
			buildNav(root)
		end,
	}
	root.Parent = workspace
	for _, fn in ipairs(sections) do
		fn()
		y()
	end
	current = workspace

	-- player spawn inside the kitchen
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	local sp = Instance.new("SpawnLocation")
	sp.Name = "StaffSpawn"
	sp.Anchored = true
	sp.Size = Vector3.new(4, 0.2, 4)
	sp.CFrame = CFrame.new(-4, 0.25, -12)
	sp.Color = Color3.fromRGB(150, 150, 154)
	sp.Material = Enum.Material.DiamondPlate
	sp.Transparency = 1
	sp.CanCollide = false
	sp.Duration = 0
	sp.Neutral = true
	local decal = sp:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	sp.Parent = root -- inside the restaurant model so it moves with it

	-- lock everything so a stray click-drag in Studio can't move the whole building
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Locked = true
			if d.Size.Magnitude < 2 then
				d.CastShadow = false -- tiny props don't need shadows (performance)
			end
		end
	end

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Color = Color3.fromRGB(90, 96, 88)
		baseplate.Material = Enum.Material.Concrete
		local tex = baseplate:FindFirstChildOfClass("Texture")
		if tex then
			tex:Destroy()
		end
	end
	setupLighting()
	return root
end

return WorldBuilder
