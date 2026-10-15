-- The office (issue #25): a decorated room behind the kitchen, carved into the left neighbour
-- house, with the shop's laptop on the desk. Built at runtime into Restaurant.Office, so the baked
-- Restaurant asset stays untouched:
--   · a door opening in WallLeft (kitchen side, z -11.4 … -7.6) with a swinging wooden door
--     (tag "SwingDoor", Client/Doors; station "office_door", closes on its own)
--   · the laptop model from the counter (Restaurant.Kitchen.Laptop) moves onto the office desk
--   · a cash register takes its place on the counter (station "register": take the order)
--   · the stock terminal and the upgrade board in the storage room are removed – the laptop apps
--     (supplier, shop upgrades) replace them
--   · desk, chair, lamp, shelves with binders, file cabinet, safe, framed pictures, clock,
--     whiteboard, sofa corner, rug, plants, water cooler, ceiling lights
-- The laptop only works in the office: the client opens it only near the desk (Client/Laptop),
-- and the server refuses the management requests (supplier, upgrades, business) from elsewhere
-- (Net.RequestGate).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Services = script.Parent
local Net = require(Services.Net)
local FoodPreparationService = require(Services.FoodPreparationService)

local OfficeService = {}

-- room (interior): x -47 … -31, z -21.3 … -2.7, floor top y 0.3, ceiling y 10.4
local X0, X1 = -47, -31
local Z0, Z1 = -21.3, -2.7
local FLOOR, CEIL = 0.3, 10.4
local DOOR_Z0, DOOR_Z1, DOOR_H = -11.4, -7.6, 8.4
local AUTO_CLOSE = 12
local GATED = { Restock = true, BuyUpgrade = true, BuyUnlock = true, BizHire = true, BizFire = true, BizTrain = true, BizPrice = true, BizTheme = true, BizBuyStage = true, BizBranch = true }

local C = {
	wallpaper = Color3.fromRGB(226, 214, 192),
	wainscot = Color3.fromRGB(96, 64, 42),
	wood = Color3.fromRGB(128, 84, 52),
	darkWood = Color3.fromRGB(78, 50, 32),
	oak = Color3.fromRGB(176, 128, 82),
	leather = Color3.fromRGB(70, 44, 32),
	black = Color3.fromRGB(28, 28, 32),
	metal = Color3.fromRGB(150, 154, 160),
	brass = Color3.fromRGB(196, 160, 80),
	green = Color3.fromRGB(70, 120, 60),
	white = Color3.fromRGB(245, 244, 240),
	red = Color3.fromRGB(180, 40, 34),
}

local root: Model
local door: Model? = nil
local blocker: BasePart? = nil
local laptopPoint: BasePart? = nil
local lastUse = 0

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, props: { [string]: any }?): Part
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
	p.Parent = root
	return p
end

local function box(name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, mat: Enum.Material?, props: { [string]: any }?): Part
	return part(name, Vector3.new(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1)), CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, mat, props)
end

-- decoration: no collision / queries / shadows
local DECO = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function text(p: BasePart, face: Enum.NormalId, s: string, color: Color3, bg: Color3?, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0.6
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	t.BackgroundColor3 = bg or Color3.new()
	t.TextScaled = true
	t.Font = font or Enum.Font.GothamBold
	t.TextColor3 = color
	t.Text = s
	t.Parent = sg
	sg.Parent = p
	return t
end

local function lamp(p: BasePart, range: number, brightness: number, color: Color3?)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color or Color3.fromRGB(255, 226, 180)
	l.Shadows = false
	l.Parent = p
	return l
end

---------------------------------------------------------------------------
-- shell: carve the room out of the neighbour block, open the restaurant wall
---------------------------------------------------------------------------
local function carve(r: Instance)
	local street = r:FindFirstChild("Street")
	local nb = street and street:FindFirstChild("NeighbourL") :: BasePart?
	if nb and nb.Size.X > 30 then
		local col, mat = nb.Color, nb.Material
		local top = nb.Position.Y + nb.Size.Y / 2
		local front = nb.Position.Z + nb.Size.Z / 2
		local saved = root
		root = street :: any
		box("NeighbourL", -70, 0, -22, X0 - 0.5, top, front, col, mat)
		box("NeighbourL_Back", X0 - 0.5, 0, -22, X1, top, Z0, col, mat)
		box("NeighbourL_Front", X0 - 0.5, 0, Z1, X1, top, front, col, mat)
		box("NeighbourL_Top", X0 - 0.5, CEIL + 0.1, Z0, X1, top, Z1, col, mat)
		root = saved
		nb:Destroy()
	end
	local shell = r:FindFirstChild("Shell")
	local wall = shell and shell:FindFirstChild("WallLeft") :: BasePart?
	if wall and wall.Size.Z > 30 then
		local col, mat = wall.Color, wall.Material
		local x0, x1 = wall.Position.X - wall.Size.X / 2, wall.Position.X + wall.Size.X / 2
		local y1 = wall.Position.Y + wall.Size.Y / 2
		local z0, z1 = wall.Position.Z - wall.Size.Z / 2, wall.Position.Z + wall.Size.Z / 2
		local saved = root
		root = shell :: any
		box("WallLeft", x0, 0, z0, x1, y1, DOOR_Z0, col, mat)
		box("WallLeft", x0, 0, DOOR_Z1, x1, y1, z1, col, mat)
		box("WallLeft_Lintel", x0, DOOR_H, DOOR_Z0, x1, y1, DOOR_Z1, col, mat)
		root = saved
		wall:Destroy()
	end
end

---------------------------------------------------------------------------
-- room
---------------------------------------------------------------------------
local function room()
	-- floor, walls (wallpaper above dark wood panelling), ceiling, skirting
	box("Floor", X0 - 0.5, -0.2, Z0, X1 + 1, FLOOR, Z1, C.oak, Enum.Material.WoodPlanks)
	box("Ceiling", X0 - 0.5, CEIL, Z0, X1, CEIL + 0.1, Z1, Color3.fromRGB(240, 236, 228), Enum.Material.Plaster)
	local walls = {
		{ "WallW", X0 - 0.3, Z0, X0, Z1 },
		{ "WallN", X0, Z0, X1, Z0 + 0.3 },
		{ "WallS", X0, Z1 - 0.3, X1, Z1 },
	}
	for _, w in ipairs(walls) do
		box(w[1], w[2], FLOOR, w[3], w[4], CEIL, w[5], C.wallpaper, Enum.Material.Plaster)
	end
	-- the kitchen wall seen from inside the office gets the same finish (both sides of the door)
	box("WallE", X1 - 0.02, FLOOR, Z0 + 0.3, X1, CEIL, DOOR_Z0, C.wallpaper, Enum.Material.Plaster, DECO)
	box("WallE", X1 - 0.02, FLOOR, DOOR_Z1, X1, CEIL, Z1 - 0.3, C.wallpaper, Enum.Material.Plaster, DECO)
	box("WallE_Top", X1 - 0.02, DOOR_H, DOOR_Z0, X1, CEIL, DOOR_Z1, C.wallpaper, Enum.Material.Plaster, DECO)
	-- wainscot + rail on all four walls
	local function panel(x1: number, z1: number, x2: number, z2: number)
		box("Wainscot", x1, FLOOR, z1, x2, 3.2, z2, C.wainscot, Enum.Material.Wood, DECO)
		local dx, dz = x2 - x1, z2 - z1
		box("ChairRail", x1 - (dx < 0.5 and 0.04 or 0), 3.2, z1 - (dz < 0.5 and 0.04 or 0), x2 + (dx < 0.5 and 0.04 or 0), 3.4, z2 + (dz < 0.5 and 0.04 or 0), C.darkWood, Enum.Material.Wood, DECO)
	end
	panel(X0, Z0 + 0.3, X0 + 0.12, Z1 - 0.3)
	panel(X0, Z0 + 0.3, X1, Z0 + 0.42)
	panel(X0, Z1 - 0.42, X1, Z1 - 0.3)
	panel(X1 - 0.14, Z0 + 0.42, X1 - 0.02, DOOR_Z0 - 0.3)
	panel(X1 - 0.14, DOOR_Z1 + 0.3, X1 - 0.02, Z1 - 0.42)
	-- vertical wallpaper stripes for some texture
	for z = Z0 + 1.2, Z1 - 1, 1.6 do
		box("Stripe", X0 + 0.01, 3.4, z - 0.25, X0 + 0.02, CEIL, z + 0.25, Color3.fromRGB(214, 200, 176), Enum.Material.Plaster, DECO)
	end
	-- crown moulding
	box("Crown", X0, CEIL - 0.3, Z0 + 0.3, X0 + 0.2, CEIL, Z1 - 0.3, C.white, Enum.Material.SmoothPlastic, DECO)
	box("Crown", X0, CEIL - 0.3, Z0 + 0.3, X1, CEIL, Z0 + 0.5, C.white, Enum.Material.SmoothPlastic, DECO)
	box("Crown", X0, CEIL - 0.3, Z1 - 0.5, X1, CEIL, Z1 - 0.3, C.white, Enum.Material.SmoothPlastic, DECO)
	-- ceiling lights (two flush panels + a warm pendant over the sofa)
	for _, z in ipairs({ -16.5, -8.5 }) do
		local l = box("CeilingLight", -41, CEIL - 0.12, z - 1.2, -37, CEIL, z + 1.2, Color3.fromRGB(255, 246, 228), Enum.Material.Neon, DECO)
		lamp(l, 18, 0.9)
	end
	box("PendantCord", -42.65, CEIL - 2.6, -7.55, -42.55, CEIL, -7.45, C.black, Enum.Material.SmoothPlastic, DECO)
	local shade = part("PendantShade", Vector3.new(1.4, 0.9, 1.4), CFrame.new(-42.6, CEIL - 3, -7.5), C.brass, Enum.Material.Metal, DECO)
	shade.Shape = Enum.PartType.Ball
	local bulb = part("PendantBulb", Vector3.new(0.5, 0.5, 0.5), CFrame.new(-42.6, CEIL - 3.45, -7.5), Color3.fromRGB(255, 220, 160), Enum.Material.Neon, DECO)
	bulb.Shape = Enum.PartType.Ball
	lamp(bulb, 12, 0.8)
	-- rug
	box("Rug", -44.5, FLOOR, -15.5, -36.5, FLOOR + 0.04, -7, Color3.fromRGB(140, 40, 36), Enum.Material.Fabric, DECO)
	box("RugBorder", -44.2, FLOOR + 0.04, -15.2, -36.8, FLOOR + 0.05, -7.3, Color3.fromRGB(214, 168, 80), Enum.Material.Fabric, DECO)
	box("RugInner", -43.8, FLOOR + 0.05, -14.8, -37.2, FLOOR + 0.06, -7.7, Color3.fromRGB(150, 44, 40), Enum.Material.Fabric, DECO)
end

---------------------------------------------------------------------------
-- furniture & decoration
---------------------------------------------------------------------------
local DESK_X, DESK_Z, DESK_TOP = -43.2, -11.3, 3.25

local function desk()
	-- executive desk facing the door (+X)
	box("DeskTop", DESK_X - 1.6, DESK_TOP - 0.2, DESK_Z - 3.4, DESK_X + 1.6, DESK_TOP, DESK_Z + 3.4, C.wood, Enum.Material.Wood)
	box("DeskInlay", DESK_X - 1.1, DESK_TOP, DESK_Z - 2.6, DESK_X + 1.1, DESK_TOP + 0.02, DESK_Z + 2.6, Color3.fromRGB(40, 70, 50), Enum.Material.Fabric, DECO)
	for _, z in ipairs({ DESK_Z - 3.1, DESK_Z + 1.9 }) do
		box("DeskPedestal", DESK_X - 1.5, FLOOR, z - 0.1, DESK_X + 1.5, DESK_TOP - 0.2, z + 1.3, C.darkWood, Enum.Material.Wood)
		for k = 0, 2 do
			box("Drawer", DESK_X + 1.5, FLOOR + 0.3 + k * 0.9, z, DESK_X + 1.54, FLOOR + 1.0 + k * 0.9, z + 1.1, C.wood, Enum.Material.Wood, DECO)
			box("DrawerKnob", DESK_X + 1.54, FLOOR + 0.6 + k * 0.9, z + 0.45, DESK_X + 1.64, FLOOR + 0.7 + k * 0.9, z + 0.65, C.brass, Enum.Material.Metal, DECO)
		end
	end
	box("ModestyPanel", DESK_X - 1.5, 1, DESK_Z - 1.8, DESK_X - 1.3, DESK_TOP - 0.2, DESK_Z + 1.9, C.darkWood, Enum.Material.Wood)
	-- desk lamp (banker's lamp)
	local lx, lz = DESK_X - 0.6, DESK_Z + 2.6
	box("LampBase", lx - 0.3, DESK_TOP, lz - 0.3, lx + 0.3, DESK_TOP + 0.1, lz + 0.3, C.brass, Enum.Material.Metal, DECO)
	box("LampStem", lx - 0.05, DESK_TOP + 0.1, lz - 0.05, lx + 0.05, DESK_TOP + 1.1, lz + 0.05, C.brass, Enum.Material.Metal, DECO)
	local shade = box("LampShade", lx - 0.25, DESK_TOP + 1.05, lz - 0.6, lx + 0.25, DESK_TOP + 1.35, lz + 0.6, Color3.fromRGB(30, 110, 60), Enum.Material.Glass, DECO)
	shade.Transparency = 0.15
	local glow = box("LampGlow", lx - 0.15, DESK_TOP + 1.0, lz - 0.5, lx + 0.15, DESK_TOP + 1.05, lz + 0.5, Color3.fromRGB(255, 230, 170), Enum.Material.Neon, DECO)
	lamp(glow, 9, 1.1)
	-- things on the desk: paper stack, pen cup, mug, phone, name plate, small plant
	for k = 0, 4 do
		box("Paper", DESK_X - 0.4, DESK_TOP + 0.02 + k * 0.03, DESK_Z - 2.9, DESK_X + 0.5, DESK_TOP + 0.04 + k * 0.03, DESK_Z - 2.2, C.white, Enum.Material.SmoothPlastic, DECO)
	end
	local cup = part("PenCup", Vector3.new(0.5, 0.35, 0.35), CFrame.new(DESK_X - 0.9, DESK_TOP + 0.25, DESK_Z - 1.7) * CFrame.Angles(0, 0, math.rad(90)), C.black, Enum.Material.SmoothPlastic, DECO)
	cup.Shape = Enum.PartType.Cylinder
	for k, col in ipairs({ C.red, Color3.fromRGB(40, 80, 200), C.black }) do
		box("Pen", DESK_X - 0.95 + k * 0.04, DESK_TOP + 0.4, DESK_Z - 1.75 + k * 0.03, DESK_X - 0.91 + k * 0.04, DESK_TOP + 0.85, DESK_Z - 1.71 + k * 0.03, col, Enum.Material.SmoothPlastic, DECO)
	end
	local mug = part("Mug", Vector3.new(0.42, 0.36, 0.36), CFrame.new(DESK_X + 0.7, DESK_TOP + 0.21, DESK_Z + 1.6) * CFrame.Angles(0, 0, math.rad(90)), C.white, Enum.Material.SmoothPlastic, DECO)
	mug.Shape = Enum.PartType.Cylinder
	box("Coffee", DESK_X + 0.62, DESK_TOP + 0.38, DESK_Z + 1.48, DESK_X + 0.78, DESK_TOP + 0.39, DESK_Z + 1.72, Color3.fromRGB(70, 40, 20), Enum.Material.SmoothPlastic, DECO)
	box("Phone", DESK_X - 0.2, DESK_TOP + 0.02, DESK_Z + 1.3, DESK_X + 0.4, DESK_TOP + 0.2, DESK_Z + 2.0, C.black, Enum.Material.SmoothPlastic, DECO)
	local plate = box("NamePlate", DESK_X + 1.25, DESK_TOP, DESK_Z - 0.9, DESK_X + 1.45, DESK_TOP + 0.3, DESK_Z + 0.9, C.brass, Enum.Material.Metal, DECO)
	text(plate, Enum.NormalId.Right, "CHEF · BOSS", C.black, nil, Enum.Font.GothamBlack)
	-- executive chair facing the desk (seat at x -40.3)
	local cx, cz = DESK_X + 2.9, DESK_Z
	local base = part("ChairBase", Vector3.new(0.3, 1.8, 1.8), CFrame.new(cx, FLOOR + 0.25, cz) * CFrame.Angles(0, 0, math.rad(90)), C.black, Enum.Material.Metal)
	base.Shape = Enum.PartType.Cylinder
	box("ChairPost", cx - 0.1, FLOOR + 0.3, cz - 0.1, cx + 0.1, 1.9, cz + 0.1, C.metal, Enum.Material.Metal, DECO)
	local seat = box("ChairSeat", cx - 0.9, 1.9, cz - 1, cx + 0.9, 2.4, cz + 1, C.leather, Enum.Material.Leather)
	local s = Instance.new("Seat")
	s.Name = "Seat"
	s.Anchored = true
	s.Size = Vector3.new(1.6, 0.2, 1.8)
	s.CFrame = CFrame.new(cx, 2.45, cz) * CFrame.Angles(0, math.rad(90), 0) -- sit facing the desk (-X)
	s.Transparency = 1
	s.CanCollide = false
	s.Parent = root
	local _ = seat
	box("ChairBack", cx + 0.7, 2.4, cz - 0.95, cx + 1.0, 5.2, cz + 0.95, C.leather, Enum.Material.Leather)
	for _, z in ipairs({ cz - 1.05, cz + 1.05 }) do
		box("ChairArm", cx - 0.6, 3.0, z - 0.12, cx + 0.8, 3.15, z + 0.12, C.black, Enum.Material.SmoothPlastic, DECO)
	end
end

local function shelves()
	-- bookshelf with colourful binders on the north wall
	local sx0, sx1 = -45.8, -39.6
	box("ShelfSideL", sx0, FLOOR, Z0 + 0.3, sx0 + 0.2, 8.2, Z0 + 1.8, C.darkWood, Enum.Material.Wood)
	box("ShelfSideR", sx1 - 0.2, FLOOR, Z0 + 0.3, sx1, 8.2, Z0 + 1.8, C.darkWood, Enum.Material.Wood)
	box("ShelfBack", sx0, FLOOR, Z0 + 0.3, sx1, 8.2, Z0 + 0.4, C.wood, Enum.Material.Wood, DECO)
	local colors = { Color3.fromRGB(200, 50, 40), Color3.fromRGB(40, 90, 180), Color3.fromRGB(60, 140, 70), Color3.fromRGB(230, 180, 40), Color3.fromRGB(120, 60, 150), Color3.fromRGB(240, 240, 235) }
	local r = Random.new(25)
	for level = 0, 3 do
		local y = FLOOR + 0.2 + level * 2
		box("ShelfBoard", sx0, y - 0.15, Z0 + 0.4, sx1, y, Z0 + 1.8, C.darkWood, Enum.Material.Wood)
		if level < 3 then
			local x = sx0 + 0.35
			while x < sx1 - 0.6 do
				local w = r:NextNumber(0.28, 0.42)
				local h = r:NextNumber(1.3, 1.65)
				if r:NextNumber() < 0.12 then
					x += 0.5 -- gap
				else
					local b = box("Binder", x, y, Z0 + 0.6, x + w, y + h, Z0 + 1.6, colors[r:NextInteger(1, #colors)], Enum.Material.SmoothPlastic, DECO)
					box("BinderLabel", x + 0.05, y + h * 0.55, Z0 + 1.6, x + w - 0.05, y + h * 0.75, Z0 + 1.62, C.white, Enum.Material.SmoothPlastic, DECO)
					local _ = b
					x += w + 0.03
				end
			end
		end
	end
	-- top shelf: trophy and a framed photo
	local ty = FLOOR + 0.2 + 3 * 2
	box("TrophyBase", -44.6, ty, Z0 + 0.8, -43.8, ty + 0.3, Z0 + 1.4, C.darkWood, Enum.Material.Wood, DECO)
	box("TrophyStem", -44.3, ty + 0.3, Z0 + 1.0, -44.1, ty + 0.8, Z0 + 1.2, C.brass, Enum.Material.Metal, DECO)
	local cup = part("TrophyCup", Vector3.new(0.7, 0.7, 0.7), CFrame.new(-44.2, ty + 1.1, Z0 + 1.1), Color3.fromRGB(230, 190, 70), Enum.Material.Metal, DECO)
	cup.Shape = Enum.PartType.Ball
	cup.Reflectance = 0.3
	local photo = box("Photo", -42.4, ty, Z0 + 0.9, -41, ty + 1.1, Z0 + 1.0, C.black, Enum.Material.SmoothPlastic, DECO)
	text(photo, Enum.NormalId.Back, "👨‍🍳🥙", C.white, Color3.fromRGB(200, 150, 90))
	-- file cabinet + safe on the north wall, near the door side
	box("FileCabinet", -38.4, FLOOR, Z0 + 0.4, -36.4, 5.0, Z0 + 2.4, Color3.fromRGB(110, 116, 124), Enum.Material.Metal)
	for k = 0, 3 do
		box("CabinetDrawer", -38.2, FLOOR + 0.25 + k * 1.15, Z0 + 2.4, -36.6, FLOOR + 1.25 + k * 1.15, Z0 + 2.44, Color3.fromRGB(126, 132, 140), Enum.Material.Metal, DECO)
		box("CabinetHandle", -37.7, FLOOR + 0.95 + k * 1.15, Z0 + 2.44, -37.1, FLOOR + 1.05 + k * 1.15, Z0 + 2.52, C.metal, Enum.Material.Metal, DECO)
	end
	local safe = box("Safe", -35.8, FLOOR, Z0 + 0.4, -33.8, 2.4, Z0 + 2.2, Color3.fromRGB(50, 54, 60), Enum.Material.DiamondPlate)
	local dial = part("SafeDial", Vector3.new(0.1, 0.5, 0.5), CFrame.new(-34.8, 1.4, Z0 + 2.25) * CFrame.Angles(0, math.rad(90), 0), C.brass, Enum.Material.Metal, DECO)
	dial.Shape = Enum.PartType.Cylinder
	local _ = safe
	-- printer on the safe
	box("Printer", -35.6, 2.4, Z0 + 0.6, -34, 3.1, Z0 + 1.9, C.white, Enum.Material.SmoothPlastic, DECO)
	box("PrinterTray", -35.3, 3.1, Z0 + 1.6, -34.3, 3.14, Z0 + 2.2, C.white, Enum.Material.SmoothPlastic, DECO)
end

local function frames()
	-- behind the desk (west wall): big logo, certificate and a city picture
	local logo = box("LogoFrame", X0 + 0.02, 4.4, DESK_Z - 2.2, X0 + 0.14, 8.0, DESK_Z + 2.2, C.brass, Enum.Material.Metal, DECO)
	local inner = box("Logo", X0 + 0.14, 4.6, DESK_Z - 2.0, X0 + 0.16, 7.8, DESK_Z + 2.0, Color3.fromRGB(150, 30, 26), Enum.Material.SmoothPlastic, DECO)
	text(inner, Enum.NormalId.Right, "🥙\nKEBAP USTA\nseit 2026", Color3.fromRGB(255, 220, 140), nil, Enum.Font.GothamBlack)
	local _ = logo
	local cert = box("Certificate", X0 + 0.02, 5.0, DESK_Z + 3.2, X0 + 0.12, 7.4, DESK_Z + 5.0, C.darkWood, Enum.Material.Wood, DECO)
	local paper = box("CertPaper", X0 + 0.12, 5.15, DESK_Z + 3.35, X0 + 0.14, 7.25, DESK_Z + 4.85, Color3.fromRGB(250, 244, 220), Enum.Material.SmoothPlastic, DECO)
	text(paper, Enum.NormalId.Right, "🏅 URKUNDE\nBester Döner\nder Stadt", Color3.fromRGB(110, 70, 20), nil, Enum.Font.Garamond)
	local _2 = cert
	local pic = box("Picture", X0 + 0.02, 5.0, DESK_Z - 5.0, X0 + 0.12, 7.4, DESK_Z - 3.2, C.darkWood, Enum.Material.Wood, DECO)
	local art = box("PictureArt", X0 + 0.12, 5.15, DESK_Z - 4.85, X0 + 0.14, 7.25, DESK_Z - 3.35, Color3.fromRGB(80, 140, 200), Enum.Material.SmoothPlastic, DECO)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Right
	g.LightInfluence = 0.6
	g.Parent = art
	local sky = Instance.new("Frame")
	sky.Size = UDim2.fromScale(1, 1)
	sky.BorderSizePixel = 0
	sky.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 170, 90)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(240, 110, 90)), ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 60, 120)) })
	grad.Rotation = 90
	grad.Parent = sky
	local city = Instance.new("TextLabel")
	city.Size = UDim2.fromScale(1, 1)
	city.BackgroundTransparency = 1
	city.TextScaled = true
	city.Text = "🌇🕌"
	city.Parent = sky
	local _3 = pic
	-- wall clock on the north wall above the cabinet
	local clock = part("Clock", Vector3.new(0.12, 1.6, 1.6), CFrame.new(-37.4, 7.6, Z0 + 0.38) * CFrame.Angles(0, math.rad(90), 0), C.white, Enum.Material.SmoothPlastic, DECO)
	clock.Shape = Enum.PartType.Cylinder
	local rim = part("ClockRim", Vector3.new(0.1, 1.75, 1.75), CFrame.new(-37.4, 7.6, Z0 + 0.34) * CFrame.Angles(0, math.rad(90), 0), C.black, Enum.Material.Metal, DECO)
	rim.Shape = Enum.PartType.Cylinder
	box("HandH", -37.45, 7.6, Z0 + 0.45, -37.35, 8.05, Z0 + 0.47, C.black, Enum.Material.SmoothPlastic, DECO)
	box("HandM", -37.45, 7.55, Z0 + 0.47, -36.85, 7.65, Z0 + 0.49, C.black, Enum.Material.SmoothPlastic, DECO)
	-- whiteboard with a sales chart on the east wall (kitchen side, left of the door)
	local wb = box("Whiteboard", X1 - 0.12, 4.0, -19.6, X1 - 0.05, 8.2, -13.2, C.white, Enum.Material.SmoothPlastic, DECO)
	box("WhiteboardFrame", X1 - 0.13, 3.9, -19.7, X1 - 0.11, 8.3, -13.1, C.metal, Enum.Material.Metal, DECO)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Left
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0.6
	sg.Parent = wb
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.22, 0)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.PermanentMarker
	title.TextColor3 = Color3.fromRGB(30, 60, 160)
	title.Text = "UMSATZ 📈  Ziele!"
	title.Parent = sg
	for i, h in ipairs({ 0.25, 0.35, 0.3, 0.5, 0.45, 0.65, 0.8 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0.08 + (i - 1) * 0.12, 0, 0.95, 0)
		bar.Size = UDim2.new(0.08, 0, h * 0.7, 0)
		bar.BackgroundColor3 = i == 7 and Color3.fromRGB(40, 160, 70) or Color3.fromRGB(220, 60, 50)
		bar.BorderSizePixel = 0
		bar.Parent = sg
	end
	box("Marker", X1 - 0.3, 3.95, -16, X1 - 0.12, 4.05, -15.4, Color3.fromRGB(30, 60, 160), Enum.Material.SmoothPlastic, DECO)
end

local function lounge()
	-- sofa corner on the south side with a coffee table and an armchair
	local sz = Z1 - 1.6
	box("SofaBase", -45.6, FLOOR, sz - 1.1, -39.6, 1.6, sz + 1.1, C.leather, Enum.Material.Leather)
	box("SofaBack", -45.6, 1.6, sz + 0.5, -39.6, 3.6, sz + 1.1, C.leather, Enum.Material.Leather)
	for _, x in ipairs({ -45.6, -40.2 }) do
		box("SofaArm", x, 1.6, sz - 1.1, x + 0.6, 2.5, sz + 1.1, C.leather, Enum.Material.Leather)
	end
	for _, x in ipairs({ -44.9, -42.6 }) do
		box("Cushion", x, 1.6, sz - 0.9, x + 2.2, 2.0, sz + 0.5, Color3.fromRGB(96, 60, 44), Enum.Material.Fabric, DECO)
	end
	box("Pillow", -45, 2.0, sz + 0.1, -44.2, 2.8, sz + 0.5, Color3.fromRGB(214, 168, 80), Enum.Material.Fabric, DECO)
	box("Pillow", -41, 2.0, sz + 0.1, -40.2, 2.8, sz + 0.5, Color3.fromRGB(150, 44, 40), Enum.Material.Fabric, DECO)
	for _, x in ipairs({ -45.4, -40.0 }) do
		for _, z in ipairs({ sz - 0.9, sz + 0.9 }) do
			box("SofaFoot", x - 0.1, FLOOR - 0.1, z - 0.1, x + 0.1, FLOOR + 0.2, z + 0.1, C.darkWood, Enum.Material.Wood, DECO)
		end
	end
	-- coffee table with magazines and a bowl
	local tz = sz - 3.2
	box("CoffeeTable", -44.2, 1.4, tz - 0.8, -41, 1.6, tz + 0.8, C.darkWood, Enum.Material.Wood)
	for _, x in ipairs({ -44, -41.2 }) do
		for _, z in ipairs({ tz - 0.6, tz + 0.6 }) do
			box("TableLeg", x - 0.1, FLOOR, z - 0.1, x + 0.1, 1.4, z + 0.1, C.darkWood, Enum.Material.Wood, DECO)
		end
	end
	box("Magazine", -43.8, 1.6, tz - 0.5, -42.9, 1.63, tz + 0.2, Color3.fromRGB(40, 90, 180), Enum.Material.SmoothPlastic, DECO)
	box("Magazine", -43.6, 1.63, tz - 0.3, -42.7, 1.66, tz + 0.4, C.red, Enum.Material.SmoothPlastic, DECO)
	local bowl = part("Bowl", Vector3.new(0.3, 0.9, 0.9), CFrame.new(-41.8, 1.75, tz) * CFrame.Angles(0, 0, math.rad(90)), C.white, Enum.Material.Glass, DECO)
	bowl.Shape = Enum.PartType.Cylinder
	for k = 0, 3 do
		local f = part("Fruit", Vector3.new(0.3, 0.3, 0.3), CFrame.new(-41.9 + (k % 2) * 0.25, 1.95, tz - 0.15 + (k // 2) * 0.3), k % 2 == 0 and Color3.fromRGB(230, 60, 40) or Color3.fromRGB(240, 170, 30), Enum.Material.SmoothPlastic, DECO)
		f.Shape = Enum.PartType.Ball
	end
	-- armchair facing the sofa
	local ax, az = -37.6, sz - 1.4
	box("ArmchairBase", ax - 1.1, FLOOR, az - 1.1, ax + 1.1, 1.6, az + 1.1, Color3.fromRGB(140, 40, 36), Enum.Material.Fabric)
	box("ArmchairBack", ax + 0.6, 1.6, az - 1.1, ax + 1.1, 3.6, az + 1.1, Color3.fromRGB(140, 40, 36), Enum.Material.Fabric)
	for _, z in ipairs({ az - 1.1, az + 0.6 }) do
		box("ArmchairArm", ax - 1.1, 1.6, z, ax + 1.1, 2.4, z + 0.5, Color3.fromRGB(120, 34, 30), Enum.Material.Fabric)
	end
end

local function plant(x: number, z: number, h: number)
	local pot = part("Pot", Vector3.new(1.4, 1.2, 1.2), CFrame.new(x, FLOOR + 0.6, z), Color3.fromRGB(190, 110, 70), Enum.Material.Concrete)
	local _ = pot
	box("Soil", x - 0.55, FLOOR + 1.2, z - 0.55, x + 0.55, FLOOR + 1.25, z + 0.55, Color3.fromRGB(60, 40, 26), Enum.Material.Ground, DECO)
	box("Trunk", x - 0.08, FLOOR + 1.2, z - 0.08, x + 0.08, FLOOR + h * 0.6, z + 0.08, Color3.fromRGB(110, 80, 50), Enum.Material.Wood, DECO)
	local r = Random.new(math.floor(x * 10 + z))
	for k = 1, 9 do
		local a = k / 9 * math.pi * 2
		local y = FLOOR + h * (0.45 + r:NextNumber() * 0.5)
		local leaf = part("Leaf", Vector3.new(0.9, 0.1, 0.45), CFrame.new(x + math.cos(a) * 0.45, y, z + math.sin(a) * 0.45) * CFrame.Angles(0, -a, math.rad(r:NextNumber(15, 40))), Color3.fromRGB(60 + r:NextInteger(0, 30), 130 + r:NextInteger(0, 40), 60), Enum.Material.Grass, DECO)
		local _2 = leaf
	end
end

local function extras()
	plant(-46, Z0 + 3, 6)
	plant(-32.2, Z1 - 1.2, 5)
	plant(-46.1, Z1 - 4.4, 4.5)
	-- water cooler next to the door (inside)
	local wx, wz = -32, -14.4
	box("CoolerBody", wx - 0.6, FLOOR, wz - 0.6, wx + 0.6, 3.2, wz + 0.6, C.white, Enum.Material.SmoothPlastic)
	local bottle = part("CoolerBottle", Vector3.new(1.6, 1, 1), CFrame.new(wx, 4.0, wz) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 180, 240), Enum.Material.Glass, DECO)
	bottle.Shape = Enum.PartType.Cylinder
	bottle.Transparency = 0.35
	box("CoolerTap", wx - 0.75, 2.4, wz - 0.1, wx - 0.6, 2.6, wz + 0.1, Color3.fromRGB(40, 90, 200), Enum.Material.SmoothPlastic, DECO)
	-- coat stand by the door
	local hx, hz = -32.2, -6.4
	box("CoatPole", hx - 0.08, FLOOR, hz - 0.08, hx + 0.08, 6.4, hz + 0.08, C.darkWood, Enum.Material.Wood)
	box("CoatFoot", hx - 0.6, FLOOR, hz - 0.6, hx + 0.6, FLOOR + 0.15, hz + 0.6, C.darkWood, Enum.Material.Wood, DECO)
	box("Coat", hx - 0.5, 4.2, hz - 0.3, hx + 0.1, 6.1, hz + 0.3, Color3.fromRGB(150, 110, 70), Enum.Material.Fabric, DECO)
	box("Apron", hx, 4.6, hz - 0.35, hx + 0.45, 6.2, hz + 0.25, C.white, Enum.Material.Fabric, DECO)
end

---------------------------------------------------------------------------
-- door
---------------------------------------------------------------------------
local function setOpen(open: boolean)
	if not door or not blocker or (door:GetAttribute("Open") == true) == open then
		return
	end
	door:SetAttribute("Open", open)
	blocker.CanCollide = not open
	blocker:SetAttribute("PromptDe", open and "Tür schließen" or "Tür öffnen")
	blocker:SetAttribute("PromptEn", open and "Close door" or "Open door")
	Net.Sound(nil, open and "door_open" or "door_close", blocker.Position)
end

local function buildDoor()
	local zc = (DOOR_Z0 + DOOR_Z1) / 2
	local xc = X1 + 0.5 -- middle of the wall (WallLeft x -31 … -30)
	-- frame
	box("DoorFrameL", X1 - 0.1, FLOOR - 0.1, DOOR_Z0, X1 + 1.1, DOOR_H, DOOR_Z0 + 0.2, C.darkWood, Enum.Material.Wood)
	box("DoorFrameR", X1 - 0.1, FLOOR - 0.1, DOOR_Z1 - 0.2, X1 + 1.1, DOOR_H, DOOR_Z1, C.darkWood, Enum.Material.Wood)
	box("DoorFrameTop", X1 - 0.1, DOOR_H - 0.25, DOOR_Z0, X1 + 1.1, DOOR_H, DOOR_Z1, C.darkWood, Enum.Material.Wood)
	box("Threshold", X1 - 0.1, 0.15, DOOR_Z0 + 0.2, X1 + 1.1, 0.3, DOOR_Z1 - 0.2, C.darkWood, Enum.Material.Wood, DECO)
	-- sign on the kitchen side above the door
	local sign = box("OfficeSign", X1 + 1.02, DOOR_H + 0.25, zc - 1.4, X1 + 1.08, DOOR_H + 1.15, zc + 1.4, Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, DECO)
	text(sign, Enum.NormalId.Right, "🗄️ BÜRO · OFFICE", Color3.fromRGB(255, 210, 120), nil, Enum.Font.GothamBlack)
	-- leaf (swings into the office, hinge at the north jamb)
	local m = Instance.new("Model")
	m.Name = "OfficeDoor"
	local w = DOOR_Z1 - DOOR_Z0 - 0.45
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.Size = Vector3.new(0.25, DOOR_H - 0.5, w)
	leaf.CFrame = CFrame.new(xc, FLOOR + (DOOR_H - 0.5) / 2, zc)
	leaf.Color = C.wood
	leaf.Material = Enum.Material.Wood
	leaf.Parent = m
	-- panels, window and handle welded to the leaf (they follow it)
	local function onLeaf(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material, transparency: number?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = leaf.CFrame * offset
		p.Color = color
		p.Material = mat
		p.Transparency = transparency or 0
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.Parent = m
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = leaf
		wc.Part1 = p
		wc.Parent = p
		return p
	end
	for _, side in ipairs({ -1, 1 }) do
		onLeaf("Panel", Vector3.new(0.05, 2.2, w - 0.8), CFrame.new(side * 0.14, -1.8, 0), C.darkWood, Enum.Material.Wood)
		onLeaf("Window", Vector3.new(0.05, 2.4, w - 1.0), CFrame.new(side * 0.14, 1.6, 0), Color3.fromRGB(200, 220, 230), Enum.Material.Glass, 0.45)
		local knob = onLeaf("Knob", Vector3.new(0.25, 0.25, 0.25), CFrame.new(side * 0.25, -0.4, w / 2 - 0.35), C.brass, Enum.Material.Metal)
		knob.Shape = Enum.PartType.Ball
	end
	local plate = onLeaf("NamePlate", Vector3.new(0.05, 0.5, 1.4), CFrame.new(0.15, 3.1, 0), C.brass, Enum.Material.Metal)
	text(plate, Enum.NormalId.Right, "BÜRO", C.black, nil, Enum.Font.GothamBlack)
	m:SetAttribute("Hinge", CFrame.new(xc, FLOOR, DOOR_Z0 + 0.25))
	m:SetAttribute("OpenAngle", -95) -- swings into the office (-X)
	m:SetAttribute("Open", false)
	m.Parent = root
	CollectionService:AddTag(m, "SwingDoor")
	door = m
	-- invisible blocker = collision + prompt
	local b = box("DoorBlocker", X1 + 0.1, FLOOR, DOOR_Z0 + 0.2, X1 + 0.9, DOOR_H - 0.3, DOOR_Z1 - 0.2, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1 })
	b:SetAttribute("Station", "office_door")
	b:SetAttribute("PromptDe", "Tür öffnen")
	b:SetAttribute("PromptEn", "Open door")
	b:SetAttribute("PromptObj", "🗄️ Büro")
	b:SetAttribute("PromptDist", 7)
	CollectionService:AddTag(b, "Station")
	blocker = b
end

---------------------------------------------------------------------------
-- laptop & storage clean-up
---------------------------------------------------------------------------
-- where the laptop stood on the counter there is now a cash register: [E] takes the waiting
-- customer's order (station "register", Server/CustomerService)
local function buildRegister(r: Instance, at: CFrame)
	local m = Instance.new("Model")
	m.Name = "Register"
	local saved = root
	root = m :: any
	local base = at * CFrame.new(0, 0.18, 0)
	part("RegisterBase", Vector3.new(1.8, 0.36, 1.6), base, C.black, Enum.Material.SmoothPlastic)
	part("CashDrawer", Vector3.new(1.7, 0.08, 0.05), base * CFrame.new(0, 0, -0.82), Color3.fromRGB(60, 60, 66), Enum.Material.Metal, DECO)
	part("Stand", Vector3.new(0.18, 0.7, 0.18), base * CFrame.new(0, 0.5, 0.3), C.metal, Enum.Material.Metal, DECO)
	local screen = part("RegisterDisplay", Vector3.new(1.5, 1.0, 0.08), base * CFrame.new(0, 1.05, 0.25) * CFrame.Angles(math.rad(-18), 0, 0), C.black, Enum.Material.SmoothPlastic)
	text(screen, Enum.NormalId.Front, "🧾 KASSA", Color3.fromRGB(120, 230, 150), Color3.fromRGB(16, 24, 22), Enum.Font.GothamBlack)
	part("Keypad", Vector3.new(0.9, 0.05, 0.6), base * CFrame.new(0.25, 0.2, -0.35) * CFrame.Angles(math.rad(10), 0, 0), Color3.fromRGB(80, 80, 88), Enum.Material.SmoothPlastic, DECO)
	local point = part("RegisterPoint", Vector3.new(2.6, 2, 2.2), base * CFrame.new(0, 0.8, -0.2), C.white, nil, { Transparency = 1, CanCollide = false })
	point:SetAttribute("Station", "register")
	CollectionService:AddTag(point, "Station")
	root = saved
	local kitchen = r:FindFirstChild("Kitchen")
	m.Parent = kitchen or r
end

local function moveLaptop(r: Instance)
	local kitchen = r:FindFirstChild("Kitchen")
	local laptop = kitchen and kitchen:FindFirstChild("Laptop") :: Model?
	if not laptop then
		laptop = r:FindFirstChild("Laptop", true) :: Model?
	end
	if not laptop or not laptop:IsA("Model") then
		warn("[OfficeService] no laptop model found")
		return
	end
	local base = laptop:FindFirstChild("Base") :: BasePart?
	if base then
		-- a cash register takes the laptop's place on the counter
		-- (world-aligned: the display and the cash drawer face the kitchen, -Z)
		local spot = CFrame.new(base.Position - Vector3.new(0, base.Size.Y / 2 + 0.05, 0))
		local okReg, errReg = pcall(buildRegister, r, spot)
		if not okReg then
			warn("[OfficeService] register: " .. tostring(errReg))
		end
		local rel = base.CFrame:Inverse() * laptop:GetPivot()
		-- the screen faced -Z at the counter; on the desk it faces the chair (+X)
		local target = CFrame.new(DESK_X + 0.1, DESK_TOP + 0.145, DESK_Z) * CFrame.Angles(0, -math.pi / 2, 0) * base.CFrame.Rotation
		laptop:PivotTo(target * rel)
	end
	laptop.Parent = root
	laptopPoint = laptop:FindFirstChild("LaptopPoint") :: BasePart?
	if laptopPoint then
		laptopPoint:SetAttribute("PromptObj", "💻 Büro-Laptop")
	end
end

local function clearStorage(r: Instance)
	local storage = r:FindFirstChild("Storage")
	if not storage then
		return
	end
	for _, name in ipairs({ "StockTerminal", "TerminalStand", "UpgradeBoard", "UpgradePoint" }) do
		for _, c in ipairs(storage:GetChildren()) do
			if c.Name == name then
				c:Destroy()
			end
		end
	end
end

function OfficeService.LaptopPosition(): Vector3?
	return laptopPoint and laptopPoint.Position or nil
end

function OfficeService.InOffice(player: Player): boolean
	local p = OfficeService.LaptopPosition()
	return p ~= nil and Net.Near(player, p, 16)
end

function OfficeService.Init()
	local r = workspace:FindFirstChild("Restaurant")
	if not r or r:FindFirstChild("Office") then
		return
	end
	root = Instance.new("Model")
	root.Name = "Office"
	for name, step in pairs({ carve = function()
		carve(r)
	end }) do
		local ok, err = pcall(step)
		if not ok then
			warn("[OfficeService] " .. name .. ": " .. tostring(err))
		end
	end
	for _, step in ipairs({ { "room", room }, { "desk", desk }, { "shelves", shelves }, { "frames", frames }, { "lounge", lounge }, { "extras", extras }, { "door", buildDoor } }) do
		local ok, err = pcall(step[2])
		if not ok then
			warn("[OfficeService] " .. step[1] .. ": " .. tostring(err))
		end
	end
	root.Parent = r
	local ok, err = pcall(moveLaptop, r)
	if not ok then
		warn("[OfficeService] laptop: " .. tostring(err))
	end
	pcall(clearStorage, r)

	FoodPreparationService.ExternalActions.office_door = function()
		lastUse = os.clock()
		setOpen(not (door and door:GetAttribute("Open") == true))
	end
	-- management requests only from the office (the laptop apps)
	local prevGate = Net.RequestGate
	Net.RequestGate = function(player: Player, action: string): boolean
		if prevGate and not prevGate(player, action) then
			return false
		end
		if GATED[action] and laptopPoint and not OfficeService.InOffice(player) then
			return false
		end
		return true
	end
	-- the door closes on its own once nobody is around
	task.spawn(function()
		while true do
			task.wait(1)
			if door and blocker and door:GetAttribute("Open") then
				local near = false
				for _, p in ipairs(Players:GetPlayers()) do
					local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hrp and (hrp.Position - blocker.Position).Magnitude < 7 then
						near = true
					end
				end
				if near then
					lastUse = os.clock()
				elseif os.clock() - lastUse > AUTO_CLOSE then
					setOpen(false)
				end
			end
		end
	end)
end

return OfficeService
