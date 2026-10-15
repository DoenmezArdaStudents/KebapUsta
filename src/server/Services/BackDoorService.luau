-- Back door: a steel service door in the storage room's back wall that leads out to the backyard.
-- Built at runtime (like the cold room): the back wall gets an opening, a frame, the door leaf and a
-- small concrete landing outside. The Blender model ServerStorage.Models.BackDoor (MeshParts
-- "Frame" and "Leaf", see art/backdoor) replaces the primitive parts when it exists.
--
-- Multiplayer: the server owns the state (attribute "Open" on the door model) and the collision
-- (an invisible blocker in the doorway). Every client animates the leaf itself from that state
-- (Client/Doors), so the swing is smooth and identical for everybody. Players carrying boxes, meat
-- cones or bags can use the door: it is not a cooking station, so full hands never block it.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Services = script.Parent
local Net = require(Services.Net)
local FoodPreparationService = require(Services.FoodPreparationService)

local BackDoorService = {}

-- opening in WallBack (z -21 … -20), right of the storage shelves, left of the right wall
local X0, X1 = 26.0, 29.8
local HEIGHT = 8.4
local Z_IN, Z_OUT = -20, -21
local FLOOR_Y = 0.25
local OPEN_ANGLE = -100 -- degrees around the hinge; negative = swings outward into the yard (-Z)
local AUTO_CLOSE = 15 -- seconds without anybody close by

local STEEL = Color3.fromRGB(70, 92, 84)
local FRAME = Color3.fromRGB(58, 60, 64)
local METAL = Color3.fromRGB(176, 178, 182)

local model: Model
local blocker: BasePart
local lastUse = 0

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, props: { [string]: any }?)
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
	p.Parent = parent
	return p
end

-- cut the doorway into the back wall: the wall keeps its left part, gets a right part and a lintel
local function cutWall(): boolean
	local r = workspace:FindFirstChild("Restaurant")
	local shell = r and r:FindFirstChild("Shell")
	local wall = shell and shell:FindFirstChild("WallBack") :: BasePart?
	if not wall or wall:GetAttribute("BackDoorCut") then
		return wall ~= nil
	end
	local left, right = wall.Position.X - wall.Size.X / 2, wall.Position.X + wall.Size.X / 2
	local bottom, top = wall.Position.Y - wall.Size.Y / 2, wall.Position.Y + wall.Size.Y / 2
	local z, depth = wall.Position.Z, wall.Size.Z
	local function piece(name: string, x1: number, x2: number, y1: number, y2: number): BasePart
		local p = wall:Clone()
		p.Name = name
		p.Size = Vector3.new(x2 - x1, y2 - y1, depth)
		p.CFrame = CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, z)
		p:ClearAllChildren()
		p.Parent = wall.Parent
		return p
	end
	piece("WallBack_Right", X1, right, bottom, top)
	piece("WallBack_Lintel", X0, X1, bottom + HEIGHT, top)
	wall.Size = Vector3.new(X0 - left, wall.Size.Y, depth)
	wall.CFrame = CFrame.new((left + X0) / 2, wall.Position.Y, z)
	wall:SetAttribute("BackDoorCut", true)
	return true
end

-- the leaf in its closed pose, built around the hinge on the right jamb
local function buildLeaf(m: Model, hinge: CFrame): BasePart
	local w, h = X1 - X0 - 0.5, HEIGHT - 0.3
	local lib = ServerStorage:FindFirstChild("Models")
	local tpl = lib and lib:FindFirstChild("BackDoor")
	local leafTpl = tpl and tpl:FindFirstChild("Leaf") :: BasePart?
	local centre = hinge * CFrame.new(-w / 2, h / 2, 0)
	local leaf: BasePart
	if leafTpl then
		leaf = leafTpl:Clone()
		leaf.Size = Vector3.new(w, h, 0.5)
		leaf.CFrame = centre
		leaf.Anchored = true
		leaf.Parent = m
	else
		leaf = part(m, "Leaf", Vector3.new(w, h, 0.18), centre, STEEL, Enum.Material.Metal)
		local function bit(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
			local p = part(m, name, size, centre * off, color, mat, { CanCollide = false })
			if shape then
				p.Shape = shape
			end
			p.Anchored = false
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = leaf
			wc.Part1 = p
			wc.Parent = p
			return p
		end
		-- embossed panels, kick plate, wired-glass window
		bit("PanelTop", Vector3.new(w - 0.6, h * 0.36, 0.22), CFrame.new(0, h * 0.22, 0), STEEL:Lerp(Color3.new(0, 0, 0), 0.08), Enum.Material.Metal)
		bit("PanelBottom", Vector3.new(w - 0.6, h * 0.3, 0.22), CFrame.new(0, -h * 0.24, 0), STEEL:Lerp(Color3.new(0, 0, 0), 0.08), Enum.Material.Metal)
		bit("KickPlate", Vector3.new(w - 0.1, 0.7, 0.24), CFrame.new(0, -h / 2 + 0.4, 0), METAL, Enum.Material.DiamondPlate)
		bit("Window", Vector3.new(0.9, 1.4, 0.24), CFrame.new(0, h * 0.27, 0), Color3.fromRGB(150, 180, 190), Enum.Material.Glass, nil).Transparency = 0.35
		-- inside (+Z, storage): push bar across the door; outside (-Z, yard): pull handle + lock
		bit("PushBar", Vector3.new(w - 0.9, 0.16, 0.16), CFrame.new(0.1, -0.15, 0.22), METAL, Enum.Material.Metal)
		for _, x in ipairs({ -w / 2 + 0.45, w / 2 - 0.45 }) do
			bit("BarMount", Vector3.new(0.2, 0.3, 0.2), CFrame.new(x, -0.15, 0.14), FRAME, Enum.Material.Metal)
		end
		bit("Handle", Vector3.new(0.12, 0.9, 0.12), CFrame.new(-w / 2 + 0.4, 0, -0.3), METAL, Enum.Material.Metal)
		for _, y in ipairs({ 0.45, -0.45 }) do
			bit("HandleMount", Vector3.new(0.12, 0.12, 0.22), CFrame.new(-w / 2 + 0.4, y, -0.18), METAL, Enum.Material.Metal)
		end
		bit("Lock", Vector3.new(0.18, 0.18, 0.06), CFrame.new(-w / 2 + 0.4, -0.75, -0.12), Color3.fromRGB(200, 170, 70), Enum.Material.Metal, Enum.PartType.Cylinder)
		-- door closer arm at the top (inside)
		bit("Closer", Vector3.new(0.9, 0.25, 0.25), CFrame.new(w / 2 - 0.7, h / 2 - 0.3, 0.2), FRAME, Enum.Material.Metal)
	end
	leaf.Name = "Leaf"
	leaf.CanCollide = false -- the blocker does the collision, clients animate the leaf
	-- three hinges on the right jamb (part of the frame, they do not move)
	for _, y in ipairs({ 0.9, h / 2, h - 0.9 }) do
		local hp = part(m, "Hinge", Vector3.new(0.5, 0.16, 0.16), hinge * CFrame.new(0.02, y, 0) * CFrame.Angles(0, 0, math.rad(90)), METAL, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		hp:SetAttribute("Static", true)
	end
	return leaf
end

local function build()
	local r = workspace:FindFirstChild("Restaurant")
	if not r or r:FindFirstChild("BackDoor") or not cutWall() then
		return
	end
	model = Instance.new("Model")
	model.Name = "BackDoor"
	local midX, midZ = (X0 + X1) / 2, (Z_IN + Z_OUT) / 2
	local lib = ServerStorage:FindFirstChild("Models")
	local tpl = lib and lib:FindFirstChild("BackDoor")
	local frameTpl = tpl and tpl:FindFirstChild("Frame") :: BasePart?
	if frameTpl then
		local f = frameTpl:Clone()
		f.Size = Vector3.new(X1 - X0, HEIGHT, 1.2)
		f.CFrame = CFrame.new(midX, FLOOR_Y + HEIGHT / 2 - 0.05, midZ)
		f.Anchored = true
		f.Parent = model
	else
		part(model, "JambL", Vector3.new(0.25, HEIGHT, 1.2), CFrame.new(X0 + 0.125, FLOOR_Y + HEIGHT / 2 - 0.05, midZ), FRAME, Enum.Material.Metal)
		part(model, "JambR", Vector3.new(0.25, HEIGHT, 1.2), CFrame.new(X1 - 0.125, FLOOR_Y + HEIGHT / 2 - 0.05, midZ), FRAME, Enum.Material.Metal)
		part(model, "Head", Vector3.new(X1 - X0, 0.3, 1.2), CFrame.new(midX, FLOOR_Y + HEIGHT - 0.2, midZ), FRAME, Enum.Material.Metal)
	end
	part(model, "Threshold", Vector3.new(X1 - X0, 0.1, 1.3), CFrame.new(midX, FLOOR_Y - 0.03, midZ), METAL, Enum.Material.DiamondPlate)
	-- hinge line: right jamb, outer face (the leaf swings outward into the yard)
	local hinge = CFrame.new(X1 - 0.25, FLOOR_Y + 0.05, Z_OUT + 0.15)
	local leaf = buildLeaf(model, hinge)
	model.PrimaryPart = leaf
	model:SetAttribute("Hinge", hinge)
	model:SetAttribute("OpenAngle", OPEN_ANGLE)
	model:SetAttribute("Open", false)
	-- invisible blocker in the doorway: collision + the prompt (reachable from both sides)
	blocker = part(model, "Blocker", Vector3.new(X1 - X0 - 0.5, HEIGHT - 0.3, 1), CFrame.new(midX, FLOOR_Y + (HEIGHT - 0.3) / 2, midZ), Color3.new(1, 1, 1), nil, { Transparency = 1 })
	blocker:SetAttribute("Station", "backdoor")
	blocker:SetAttribute("PromptDe", "Tür öffnen")
	blocker:SetAttribute("PromptEn", "Open door")
	blocker:SetAttribute("PromptObj", "🚪 Hinterhof")
	blocker:SetAttribute("PromptDist", 7)
	CollectionService:AddTag(blocker, "Station")
	-- outside: concrete landing with a step and a wall lamp (the backyard continues from here)
	local yard = Instance.new("Model")
	yard.Name = "BackLanding"
	part(yard, "Landing", Vector3.new(12, 0.4, 6), CFrame.new(midX, FLOOR_Y - 0.2, Z_OUT - 3), Color3.fromRGB(150, 148, 142), Enum.Material.Concrete)
	part(yard, "Step", Vector3.new(6, 0.2, 1.2), CFrame.new(midX, 0.0, Z_OUT - 6.6), Color3.fromRGB(140, 138, 132), Enum.Material.Concrete)
	local lamp = part(yard, "WallLamp", Vector3.new(0.9, 0.5, 0.5), CFrame.new(midX, FLOOR_Y + HEIGHT + 0.9, Z_OUT - 0.3), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	local glow = part(yard, "LampGlass", Vector3.new(0.7, 0.18, 0.4), lamp.CFrame * CFrame.new(0, -0.3, 0), Color3.fromRGB(255, 236, 190), Enum.Material.Neon, { CanCollide = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 110
	light.Range = 18
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 226, 170)
	light.Parent = glow
	yard.Parent = model
	model.Parent = r
	CollectionService:AddTag(model, "SwingDoor")
end

function BackDoorService.IsOpen(): boolean
	return model ~= nil and model:GetAttribute("Open") == true
end

function BackDoorService.SetOpen(open: boolean)
	if not model or BackDoorService.IsOpen() == open then
		return
	end
	model:SetAttribute("Open", open)
	blocker.CanCollide = not open
	blocker:SetAttribute("PromptDe", open and "Tür schließen" or "Tür öffnen")
	blocker:SetAttribute("PromptEn", open and "Close door" or "Open door")
	Net.Sound(nil, open and "door_open" or "door_close", blocker.Position)
end

-- staff (cleaners carrying waste out) open the door and keep it open for a moment
function BackDoorService.Use()
	lastUse = os.clock()
	BackDoorService.SetOpen(true)
end

local function anyoneNear(pos: Vector3, dist: number): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - pos).Magnitude < dist then
			return true
		end
	end
	return false
end

function BackDoorService.Init()
	build()
	if not model then
		warn("[BackDoorService] Restaurant.Shell.WallBack not found – no back door")
		return
	end
	FoodPreparationService.ExternalActions.backdoor = function()
		lastUse = os.clock()
		BackDoorService.SetOpen(not BackDoorService.IsOpen())
	end
	-- the door swings shut on its own once nobody is around any more
	task.spawn(function()
		while true do
			task.wait(1)
			if BackDoorService.IsOpen() then
				if anyoneNear(blocker.Position, 9) then
					lastUse = os.clock()
				elseif os.clock() - lastUse > AUTO_CLOSE then
					BackDoorService.SetOpen(false)
				end
			end
		end
	end)
end

return BackDoorService
