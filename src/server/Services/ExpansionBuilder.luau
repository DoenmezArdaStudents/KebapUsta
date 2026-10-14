-- Geometry for the restaurant expansion stages 2–5 (Shared/Business.Stages). Each stage is its own
-- model under workspace.Restaurant.Expansion so it can be built instantly (loading a save) or piece
-- by piece after a purchase (BusinessService plays the construction transition).

local CollectionService = game:GetService("CollectionService")

local ExpansionBuilder = {}

local current: Instance = workspace

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
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

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = font or Enum.Font.GothamBlack
	t.TextColor3 = color
	t.Text = text
	t.Parent = sg
	sg.Parent = p
end

local function navPoint(parent: Instance, name: string, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = cf
	p.Parent = parent
	return p
end

local WOOD = Color3.fromRGB(122, 82, 52)
local DARK = Color3.fromRGB(74, 50, 34)
local BLACK = Color3.fromRGB(28, 28, 30)
local GOLD = Color3.fromRGB(230, 180, 60)
local WHITE = Color3.fromRGB(250, 250, 250)
local RED = Color3.fromRGB(196, 50, 40)

local function plant(x: number, y: number, z: number, s: number)
	part("Planter", Vector3.new(2, 1.4, 2) * s, at(x, y + 0.7 * s, z), Color3.fromRGB(70, 70, 74), Enum.Material.Concrete)
	part("Bush", Vector3.new(2.2, 2.2, 2.2) * s, at(x, y + 2.2 * s, z), Color3.fromRGB(62, 118, 72), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
end

---------------------------------------------------------------------------
-- Stage 2: terrace on the pavement (x -29..5, z 20.6..24.6; the walking lane at z 26 stays free)
---------------------------------------------------------------------------
local FLOOR = 0.7 -- pavement 0.5 + deck boards

local function terraceTable(m: Model, x: number, z: number, colour: Color3)
	part("Top", Vector3.new(3.2, 0.2, 2.6), at(x, FLOOR + 2.9, z), Color3.fromRGB(235, 232, 225), Enum.Material.Marble)
	part("Leg", Vector3.new(0.35, 2.8, 0.35), at(x, FLOOR + 1.45, z), BLACK, Enum.Material.Metal)
	part("Foot", Vector3.new(1.4, 0.15, 1.4), at(x, FLOOR + 0.08, z), BLACK, Enum.Material.Metal)
	-- parasol
	part("Pole", Vector3.new(0.18, 6.2, 0.18), at(x, FLOOR + 6, z), Color3.fromRGB(220, 220, 220), Enum.Material.Metal, { CanCollide = false })
	part("Canopy", Vector3.new(0.35, 7.5, 7.5), at(x, FLOOR + 9.1, z) * CFrame.Angles(0, 0, math.rad(90)), colour, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	part("CanopyTop", Vector3.new(0.6, 1.2, 1.2), at(x, FLOOR + 9.4, z) * CFrame.Angles(0, 0, math.rad(90)), colour, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	for i, sx in ipairs({ x - 2.2, x + 2.2 }) do
		local facing = sx < x and -90 or 90
		local cf = at(sx, FLOOR, z) * CFrame.Angles(0, math.rad(facing), 0)
		part("Seat", Vector3.new(1.7, 0.2, 1.7), cf * at(0, 1.85, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
		part("Back", Vector3.new(1.7, 1.8, 0.15), cf * at(0, 2.85, 0.8), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
		for _, o in ipairs({ { -0.7, -0.7 }, { 0.7, -0.7 }, { -0.7, 0.7 }, { 0.7, 0.7 } }) do
			part("ChairLeg", Vector3.new(0.12, 1.8, 0.12), cf * at(o[1], 0.9, o[2]), BLACK, Enum.Material.Metal)
		end
		-- seat nav point facing the table; guests come in from the pavement side
		local look = CFrame.lookAt(Vector3.new(sx, 0, z), Vector3.new(x, 0, z))
		local sp = navPoint(m, "SeatPoint" .. i, look + Vector3.new(0, FLOOR + 1.85, 0))
		sp:SetAttribute("Tier", 0)
		sp:SetAttribute("Outdoor", true)
		sp:SetAttribute("Entry", "TerraceEntry")
		sp:SetAttribute("A1", Vector3.new(sx, FLOOR + 3, 26.2))
		sp:SetAttribute("A2", Vector3.new(sx, FLOOR + 3, 24.5))
		CollectionService:AddTag(sp, "SeatPoint")
	end
end

local function buildTerrace(m: Model)
	current = m
	part("Deck", Vector3.new(34, 0.2, 4.4), at(-12, 0.6, 22.6), Color3.fromRGB(150, 104, 66), Enum.Material.WoodPlanks)
	for x = -28.5, 4.5, 1.1 do
		part("Board", Vector3.new(0.06, 0.02, 4.4), at(x, 0.71, 22.6), DARK, Enum.Material.Wood, { CanCollide = false })
	end
	local colours = { Color3.fromRGB(200, 40, 40), Color3.fromRGB(240, 240, 235), Color3.fromRGB(200, 40, 40) }
	for i, x in ipairs({ -22, -12, -2 }) do
		local t = model("TerraceTable" .. i, m)
		current = t
		terraceTable(t, x, 22.6, colours[i])
		current = m
	end
	plant(-28, FLOOR, 22.6, 0.9)
	plant(4, FLOOR, 22.6, 0.9)
end

---------------------------------------------------------------------------
-- Stage 3: delivery – scooter on the pavement + shelf for packed orders next to the storage door
---------------------------------------------------------------------------
local function scooter(m: Model, cf: CFrame)
	local s = model("Scooter", m)
	current = s
	local red = Color3.fromRGB(210, 40, 40)
	part("Body", Vector3.new(4, 1.2, 1.4), cf * at(0, 1.6, 0), red, Enum.Material.SmoothPlastic)
	part("Seat", Vector3.new(1.8, 0.4, 1.2), cf * at(-0.6, 2.4, 0), BLACK, Enum.Material.Fabric)
	part("Stem", Vector3.new(0.3, 2.2, 0.3), cf * at(1.8, 2.6, 0) * CFrame.Angles(0, 0, math.rad(-15)), red, Enum.Material.SmoothPlastic)
	part("Bar", Vector3.new(0.2, 0.2, 2), cf * at(2.1, 3.7, 0), BLACK, Enum.Material.Metal)
	for _, x in ipairs({ -1.6, 1.8 }) do
		part("Wheel", Vector3.new(0.5, 1.6, 1.6), cf * at(x, 0.8, 0) * CFrame.Angles(0, math.rad(90), 0), BLACK, Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
	end
	local box = part("Box", Vector3.new(1.8, 1.6, 1.8), cf * at(-1.4, 3.4, 0), Color3.fromRGB(240, 240, 235), Enum.Material.SmoothPlastic)
	label(box, Enum.NormalId.Front, "🥙 KEBAP\nLIEFERDIENST", RED)
	label(box, Enum.NormalId.Back, "🥙 KEBAP\nLIEFERDIENST", RED)
	s.PrimaryPart = s:FindFirstChild("Body") :: BasePart
	current = m
	return s
end

local function buildDelivery(m: Model)
	current = m
	scooter(m, at(24, 0.5, 24.5) * CFrame.Angles(0, math.rad(180), 0))
	-- shelf against the storage wall (x 12.3), customer-free kitchen side
	part("ShelfBack", Vector3.new(0.3, 5.5, 3.4), at(11.9, 3.0, -15.2), DARK, Enum.Material.Wood)
	for _, y in ipairs({ 1.2, 2.8, 4.4 }) do
		part("ShelfBoard", Vector3.new(1.6, 0.15, 3.4), at(11.0, y, -15.2), WOOD, Enum.Material.Wood)
	end
	local top = part("DeliveryShelf", Vector3.new(1.6, 0.3, 3.4), at(11.0, 3.0, -15.2), Color3.fromRGB(240, 240, 235), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
	top:SetAttribute("Station", "delivery")
	top:SetAttribute("PromptDe", "Lieferung einpacken")
	top:SetAttribute("PromptEn", "Pack delivery")
	top:SetAttribute("PromptObj", "🛵")
	top:SetAttribute("PromptDist", 9)
	CollectionService:AddTag(top, "Station")
	local sign = part("DeliverySign", Vector3.new(0.1, 1, 3.2), at(11.7, 6.2, -15.2), RED, Enum.Material.SmoothPlastic, { CanCollide = false })
	label(sign, Enum.NormalId.Left, "🛵 LIEFERUNGEN", WHITE)
	-- the order printer / phone on the top board
	part("Phone", Vector3.new(0.8, 0.3, 1), at(11.0, 4.62, -16.3), BLACK, Enum.Material.SmoothPlastic)
	current = workspace
end

---------------------------------------------------------------------------
-- Stage 4: facade – striped awning, neon lettering, fairy lights and flower boxes
---------------------------------------------------------------------------
local function buildFacade(m: Model)
	current = m
	for i = 0, 15 do
		local x = -29 + i * 2.6
		if x < 9 or x > 19 then -- keep the door free
			part("Awning", Vector3.new(2.6, 0.15, 4), at(x + 1.3, 10.2, 22.1) * CFrame.Angles(math.rad(-18), 0, 0), i % 2 == 0 and RED or WHITE, Enum.Material.Fabric, { CanCollide = false })
		end
	end
	for i = 0, 7 do
		local x = 19.6 + i * 1.3
		if x < 30 then
			part("Awning", Vector3.new(1.3, 0.15, 4), at(x + 0.65, 10.2, 22.1) * CFrame.Angles(math.rad(-18), 0, 0), i % 2 == 0 and RED or WHITE, Enum.Material.Fabric, { CanCollide = false })
		end
	end
	local neon = part("NeonLettering", Vector3.new(9.4, 1.6, 0.3), at(24, 12.9, 21.1), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, { CanCollide = false })
	label(neon, Enum.NormalId.Back, "★ KEBAP USTA ★", WHITE, Enum.Font.Fantasy)
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 150, 80)
	light.Parent = neon
	-- fairy lights along the awning edge
	local colours = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 90), Color3.fromRGB(140, 200, 255) }
	for i = 0, 26 do
		local x = -29 + i * 2.2
		if x < 9 or x > 19 then
			part("FairyLight", Vector3.new(0.35, 0.35, 0.35), at(x, 9.15 - math.abs(math.sin(i)) * 0.25, 24), colours[i % 3 + 1], Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	part("LightCord", Vector3.new(58, 0.05, 0.05), at(0, 9.3, 24), BLACK, Enum.Material.SmoothPlastic, { CanCollide = false })
	for _, x in ipairs({ -26, -18, -6, 23, 27 }) do
		part("FlowerBox", Vector3.new(3.4, 0.8, 0.9), at(x, 5.4, 21.1), DARK, Enum.Material.Wood, { CanCollide = false })
		for k = 0, 3 do
			part("Flower", Vector3.new(0.5, 0.5, 0.5), at(x - 1.2 + k * 0.8, 6, 21.1), colours[(k % 3) + 1], Enum.Material.Plastic, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	current = workspace
end

---------------------------------------------------------------------------
-- Stage 5: palace – golden counter trim, chandeliers, gold carpet and pillars
---------------------------------------------------------------------------
local function chandelier(x: number, z: number)
	part("ChainC", Vector3.new(0.08, 1.8, 0.08), at(x, 12.9, z), GOLD, Enum.Material.Metal, { CanCollide = false })
	local ring = part("Ring", Vector3.new(0.25, 3.2, 3.2), at(x, 11.9, z) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	for a = 0, 5 do
		local cf = ring.CFrame * CFrame.Angles(math.rad(a * 60), 0, 0) * at(0, 1.5, 0)
		local candle = part("Candle", Vector3.new(0.25, 0.25, 0.25), CFrame.new(cf.Position + Vector3.new(0, 0.3, 0)), Color3.fromRGB(255, 230, 170), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		if a % 2 == 0 then
			local l = Instance.new("PointLight")
			l.Range = 12
			l.Brightness = 0.7
			l.Color = Color3.fromRGB(255, 210, 150)
			l.Parent = candle
		end
	end
end

local function buildPalace(m: Model)
	current = m
	part("GoldTrim", Vector3.new(37.4, 0.25, 0.1), at(-9.5, 3.15, -4.15), GOLD, Enum.Material.Metal, { CanCollide = false, Reflectance = 0.25 })
	part("GoldTrimLow", Vector3.new(37.4, 0.12, 0.1), at(-9.5, 1.1, -4.15), GOLD, Enum.Material.Metal, { CanCollide = false, Reflectance = 0.25 })
	chandelier(-13, 4)
	chandelier(-13, 14)
	part("Carpet", Vector3.new(3, 0.04, 17), at(14, 0.24, 9), Color3.fromRGB(150, 25, 35), Enum.Material.Fabric, { CanCollide = false })
	part("CarpetEdgeL", Vector3.new(0.2, 0.05, 17), at(12.5, 0.25, 9), GOLD, Enum.Material.Fabric, { CanCollide = false })
	part("CarpetEdgeR", Vector3.new(0.2, 0.05, 17), at(15.5, 0.25, 9), GOLD, Enum.Material.Fabric, { CanCollide = false })
	for _, p in ipairs({ { 10.5, 19 }, { 17.5, 19 } }) do
		part("Pillar", Vector3.new(1.4, 12, 1.4), at(p[1], 6.2, p[2]), Color3.fromRGB(236, 232, 224), Enum.Material.Marble)
		part("PillarCap", Vector3.new(1.8, 0.6, 1.8), at(p[1], 12.4, p[2]), GOLD, Enum.Material.Metal)
		part("PillarBase", Vector3.new(1.8, 0.6, 1.8), at(p[1], 0.5, p[2]), GOLD, Enum.Material.Metal)
	end
	local vip = part("VIPSign", Vector3.new(6, 1.4, 0.2), at(-20, 12.2, 19.3), BLACK, Enum.Material.SmoothPlastic, { CanCollide = false })
	label(vip, Enum.NormalId.Front, "👑 KEBAP PALAST 👑", GOLD, Enum.Font.Fantasy)
	current = workspace
end

local BUILDERS = { [2] = buildTerrace, [3] = buildDelivery, [4] = buildFacade, [5] = buildPalace }
-- where the construction site goes while a stage is being built
ExpansionBuilder.Sites = {
	[2] = { center = Vector3.new(-12, 0.5, 22.6), size = Vector3.new(34, 6, 4.6) },
	[3] = { center = Vector3.new(16, 0.5, 23.5), size = Vector3.new(14, 6, 3) },
	[4] = { center = Vector3.new(-10, 0.5, 23.6), size = Vector3.new(40, 6, 2.6) },
	[5] = { center = Vector3.new(14, 0.2, 9), size = Vector3.new(8, 6, 16) },
}

function ExpansionBuilder.Folder(): Instance?
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return nil
	end
	local f = r:FindFirstChild("Expansion")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Expansion"
		f.Parent = r
	end
	-- the terrace guests' entry point lives with the other nav points
	local nav = r:FindFirstChild("Nav")
	if nav and not nav:FindFirstChild("TerraceEntry") then
		navPoint(nav, "TerraceEntry", CFrame.new(-12, 3.7, 26.4))
	end
	return f
end

-- Build the stage model (unparented parts are created directly in place). Returns the model.
function ExpansionBuilder.Build(stage: number): Model?
	local f = ExpansionBuilder.Folder()
	local fn = BUILDERS[stage]
	if not f or not fn then
		return nil
	end
	local existing = f:FindFirstChild("Stage" .. stage)
	if existing then
		return existing :: Model
	end
	local m = model("Stage" .. stage, f)
	fn(m)
	current = workspace
	return m
end

function ExpansionBuilder.Clear()
	local f = ExpansionBuilder.Folder()
	if f then
		f:ClearAllChildren()
	end
end

return ExpansionBuilder
