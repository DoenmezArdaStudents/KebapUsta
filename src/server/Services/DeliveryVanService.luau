-- Delivery van: a European panel van drives down the back street, backs in through the backyard
-- gate into the delivery area, the driver gets out, opens the rear cargo doors, carries every box to
-- the unloading area, closes the doors, gets back in and the van drives away.
--
-- Movement is a deterministic timeline (Shared/VanRoute): the server only sets the model attributes
-- Phase / T0 / DoorsOpen and moves an invisible collision box; every client renders the van from the
-- same timeline (Client/DeliveryVan), so the motion is smooth and identical for all players and never
-- teleports. The visual parts carry their van-space CFrame in the "Local" attribute.
--
-- Model: ServerStorage.Models.Van (Blender, art/van: Body, Glass, Wheel, DoorL, DoorR – each with a
-- CFrame attribute "Offset" in van space) or, while that is missing, a primitive van built here.
-- Van space: front = -Z, left = -X, ground at Y = 0, rear face at Z = +6.6.
--
-- Safety: Run() never throws for a broken animation – movement steps time out and snap, the caller
-- (Server/LogisticsService) puts every box that is still "in the van" onto the unloading area.

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Services = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Services.Net)
local CustomerService = require(Services.CustomerService)
local VanRoute = require(Shared.VanRoute)

local DeliveryVanService = {}

local DOOR_SWING = 100 -- degrees each rear door opens
local WHITE = Color3.fromRGB(244, 244, 242)
local BLACK = Color3.fromRGB(34, 34, 36)
local GLASS = Color3.fromRGB(30, 40, 48)

local function now(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------------
-- model
---------------------------------------------------------------------------
local function vpart(m: Model, name: string, size: Vector3, localCF: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Local", localCF)
	p.Parent = m
	return p
end

local WHEELS = { { -2.75, -4.0 }, { 2.75, -4.0 }, { -2.75, 4.2 }, { 2.75, 4.2 } } -- x, z in van space
local HINGE_L = CFrame.new(-2.8, 0, 6.66)
local HINGE_R = CFrame.new(2.8, 0, 6.66)

local function door(p: BasePart, hinge: CFrame, swing: number)
	p:SetAttribute("Role", "door")
	p:SetAttribute("Hinge", hinge)
	p:SetAttribute("Swing", swing)
end

local function wheel(p: BasePart)
	p:SetAttribute("Role", "wheel")
	p:SetAttribute("Radius", 1.05)
end

local function fromTemplates(m: Model): boolean
	local lib = ServerStorage:FindFirstChild("Models")
	local t = lib and lib:FindFirstChild("Van")
	if not t then
		return false
	end
	for _, name in ipairs({ "Body", "Glass", "Wheel", "DoorL", "DoorR" }) do
		local src = t:FindFirstChild(name)
		if not (src and src:IsA("BasePart") and typeof(src:GetAttribute("Offset")) == "CFrame") then
			return false
		end
	end
	local function clone(name: string, localCF: CFrame): BasePart
		local p = (t :: Instance):FindFirstChild(name):Clone() :: BasePart
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p:SetAttribute("Local", localCF)
		p.Parent = m
		return p
	end
	clone("Body", t.Body:GetAttribute("Offset"))
	clone("Glass", t.Glass:GetAttribute("Offset"))
	local w: CFrame = t.Wheel:GetAttribute("Offset")
	for _, xz in ipairs(WHEELS) do
		-- the template wheel's outer face points to +X; left wheels are turned around
		local cf = CFrame.new(xz[1], 1.05, xz[2]) * (xz[1] < 0 and CFrame.Angles(0, math.pi, 0) or CFrame.identity) * (w - w.Position)
		wheel(clone("Wheel", cf))
	end
	door(clone("DoorL", t.DoorL:GetAttribute("Offset")), HINGE_L, -DOOR_SWING)
	door(clone("DoorR", t.DoorR:GetAttribute("Offset")), HINGE_R, DOOR_SWING)
	return true
end

-- primitive van in the same proportions as the Blender model (used until it is imported)
local function primitive(m: Model)
	vpart(m, "Cargo", Vector3.new(5.6, 6.3, 9.0), CFrame.new(0, 4.1, 2.1), WHITE)
	vpart(m, "CabLower", Vector3.new(5.6, 3.2, 4.0), CFrame.new(0, 2.55, -4.6), WHITE)
	vpart(m, "CabUpper", Vector3.new(5.5, 2.6, 1.6), CFrame.new(0, 5.9, -3.2), WHITE)
	vpart(m, "Windscreen", Vector3.new(5.0, 2.9, 0.1), CFrame.new(0, 5.75, -4.05) * CFrame.Angles(math.rad(38), 0, 0), GLASS, Enum.Material.Glass)
	vpart(m, "Bonnet", Vector3.new(5.5, 0.4, 1.6), CFrame.new(0, 4.05, -5.75) * CFrame.Angles(math.rad(-12), 0, 0), WHITE)
	for _, x in ipairs({ -2.82, 2.82 }) do
		vpart(m, "SideWindow", Vector3.new(0.06, 1.8, 1.5), CFrame.new(x, 5.6, -3.4), GLASS, Enum.Material.Glass)
		vpart(m, "Stripe", Vector3.new(0.04, 0.55, 12.6), CFrame.new(x * 1.004, 3.2, 0.2), Color3.fromRGB(222, 64, 36))
		vpart(m, "StripeThin", Vector3.new(0.04, 0.15, 12.6), CFrame.new(x * 1.004, 2.75, 0.2), Color3.fromRGB(244, 170, 40))
		vpart(m, "Rocker", Vector3.new(0.1, 0.35, 11), CFrame.new(x * 1.01, 1.1, 0), BLACK)
		vpart(m, "Mirror", Vector3.new(0.35, 0.9, 0.25), CFrame.new(x * 1.13, 5.3, -3.25), BLACK)
	end
	local sign = vpart(m, "Lettering", Vector3.new(5.62, 1.0, 6.5), CFrame.new(0, 4.7, 1.5), WHITE)
	sign.Transparency = 1
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 30
		sg.Parent = sign
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(200, 48, 30)
		t.Text = "FRISCH-LIEFERDIENST"
		t.Parent = sg
	end
	vpart(m, "FrontBumper", Vector3.new(5.8, 1.0, 0.5), CFrame.new(0, 1.45, -6.75), BLACK)
	vpart(m, "Grille", Vector3.new(3.2, 1.0, 0.08), CFrame.new(0, 2.75, -6.62), BLACK)
	vpart(m, "RearBumper", Vector3.new(5.8, 0.7, 0.4), CFrame.new(0, 1.25, 6.75), BLACK)
	for _, x in ipairs({ -1.95, 1.95 }) do
		vpart(m, "Headlight", Vector3.new(1.1, 0.42, 0.1), CFrame.new(x, 3.6, -6.62), Color3.fromRGB(250, 246, 226), Enum.Material.Neon)
		vpart(m, "TailLight", Vector3.new(0.45, 1.4, 0.08), CFrame.new(x * 1.25, 2.4, 6.66), Color3.fromRGB(200, 30, 30), Enum.Material.Neon)
	end
	vpart(m, "CargoHold", Vector3.new(5.0, 5.6, 0.06), CFrame.new(0, 4.1, 6.55), BLACK)
	for _, xz in ipairs(WHEELS) do
		local w = vpart(m, "Wheel", Vector3.new(0.8, 2.1, 2.1), CFrame.new(xz[1], 1.05, xz[2]), Color3.fromRGB(24, 24, 26), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		wheel(w)
		local rim = vpart(m, "Rim", Vector3.new(0.82, 1.2, 1.2), CFrame.new(xz[1], 1.05, xz[2]), Color3.fromRGB(180, 182, 186), Enum.Material.Metal, Enum.PartType.Cylinder)
		wheel(rim)
	end
	local dl = vpart(m, "DoorL", Vector3.new(2.75, 6.0, 0.12), CFrame.new(-1.4, 4.05, 6.66), WHITE)
	door(dl, HINGE_L, -DOOR_SWING)
	local dr = vpart(m, "DoorR", Vector3.new(2.75, 6.0, 0.12), CFrame.new(1.4, 4.05, 6.66), WHITE)
	door(dr, HINGE_R, DOOR_SWING)
end

local function build(): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "DeliveryVan"
	if not fromTemplates(m) then
		primitive(m)
	end
	-- the only thing the server moves: an invisible box players bump into
	local hit = Instance.new("Part")
	hit.Name = "Hitbox"
	hit.Size = Vector3.new(5.6, 6.5, 13.4)
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = true
	hit.CanQuery = false
	hit.CanTouch = false
	hit.Parent = m
	m.PrimaryPart = hit
	return m, hit
end

local function setPhase(m: Model, phase: string)
	m:SetAttribute("Phase", phase)
	m:SetAttribute("T0", now())
end

local function pose(m: Model): CFrame
	local cf = VanRoute.Pose(m:GetAttribute("Phase") or "arrive", now() - (m:GetAttribute("T0") or now()))
	return cf
end

-- wait for a phase to finish while keeping the hitbox (and the server copy of the parts) in place
local function runPhase(m: Model, hit: BasePart, phase: string)
	setPhase(m, phase)
	local dur = VanRoute.Duration(phase)
	local t0 = os.clock()
	while os.clock() - t0 < dur do
		hit.CFrame = pose(m) * CFrame.new(0, 3.5, 0)
		task.wait(0.1)
	end
end

---------------------------------------------------------------------------
-- driver
---------------------------------------------------------------------------
local DRIVER_LOOK = { skin = Color3.fromRGB(214, 170, 130), shirt = Color3.fromRGB(222, 64, 36), pants = Color3.fromRGB(46, 50, 60), shoes = Color3.fromRGB(30, 30, 30), hair = Color3.fromRGB(60, 40, 30), hat = true, hatColor = Color3.fromRGB(222, 64, 36) }

local function newDriver(look: { [string]: any }?, name: string?): (Model?, Humanoid?, AnimationTrack?)
	local ok, rig = pcall(CustomerService.NewRig)
	if not ok or not rig then
		return nil
	end
	pcall(CustomerService.Dress, rig, look or DRIVER_LOOK)
	rig.Name = name or "DeliveryDriver"
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if not hum then
		return rig
	end
	hum.WalkSpeed = 10
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local track
	local id = CustomerService.AnimIds and CustomerService.AnimIds.walk
	if id then
		local a = Instance.new("Animation")
		a.AnimationId = id
		pcall(function()
			track = animator:LoadAnimation(a)
		end)
	end
	return rig, hum, track
end

-- walk to a point; snaps there if the path is blocked (never gets stuck)
local function walkTo(rig: Model, hum: Humanoid, track: AnimationTrack?, target: Vector3)
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if track and not track.IsPlaying then
		track:Play(0.15)
	end
	hum:MoveTo(target)
	local t0 = os.clock()
	local limit = (root.Position - target).Magnitude / math.max(hum.WalkSpeed, 1) + 2
	while os.clock() - t0 < limit do
		local flat = (root.Position - target) * Vector3.new(1, 0, 1)
		if flat.Magnitude < 1.2 then
			break
		end
		task.wait(0.1)
	end
	if ((root.Position - target) * Vector3.new(1, 0, 1)).Magnitude > 2 then
		rig:PivotTo(CFrame.new(target) * (root.CFrame - root.Position))
	end
	if track then
		track:Stop(0.2)
	end
end

local function carry(rig: Model, box: Model)
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	box:PivotTo(root.CFrame * CFrame.new(0, 0.2, -1.4))
	for _, p in ipairs(box:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
	box.Parent = rig
end

---------------------------------------------------------------------------
-- run one delivery (blocks until the van has left)
---------------------------------------------------------------------------
-- hooks: spot() -> CFrame where the next box goes, unload(box) when it is put down,
--        model(box, cf) -> Model of the box for the driver to carry
function DeliveryVanService.Run(load: { any }, hooks: { spot: () -> CFrame, unload: (any) -> (), model: (any, CFrame) -> Model })
	local m, hit = build()
	setPhase(m, "arrive")
	local start = pose(m)
	hit.CFrame = start * CFrame.new(0, 3.5, 0)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and typeof(p:GetAttribute("Local")) == "CFrame" then
			p.CFrame = start * p:GetAttribute("Local") -- clients take over from here
		end
	end
	-- always streamed to every client (it starts far away on the back street)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m:SetAttribute("DoorsOpen", false)
	CollectionService:AddTag(m, "DeliveryVan")
	m.Parent = workspace
	local driver: Model? = nil
	local ok, err = pcall(function()
		runPhase(m, hit, "arrive")
		Net.Sound(nil, "van_brake", hit.Position)
		runPhase(m, hit, "reverse")
		setPhase(m, "parked")
		local park = VanRoute.Pose("parked", 0)
		hit.CFrame = park * CFrame.new(0, 3.5, 0)
		task.wait(0.8)
		-- the driver climbs out on the left (driver's) side and walks to the back
		local rig, hum, track = newDriver()
		driver = rig
		local doorPos = (park * CFrame.new(-3.8, 3, -3.6)).Position
		local rear = (park * CFrame.new(-1.2, 3, 8.4)).Position
		if rig then
			rig:PivotTo(CFrame.new(doorPos))
			rig.Parent = workspace
			Net.Sound(nil, "van_door_close", doorPos)
		end
		if rig and hum then
			walkTo(rig, hum, track, rear)
		end
		m:SetAttribute("DoorsOpen", true)
		Net.Sound(nil, "van_door_open", rear)
		task.wait(0.8)
		for _, b in ipairs(load) do
			if b.at ~= "van" then
				continue
			end
			local spot = hooks.spot()
			if rig and hum then
				local held = hooks.model(b, (park * CFrame.new(0, 2.5, 6)))
				carry(rig, held)
				walkTo(rig, hum, track, spot.Position + Vector3.new(0, 2.6, -1.6))
				held:Destroy()
			else
				task.wait(0.4)
			end
			hooks.unload(b)
			if rig and hum then
				walkTo(rig, hum, track, rear)
			end
		end
		m:SetAttribute("DoorsOpen", false)
		Net.Sound(nil, "van_door_close", rear)
		task.wait(0.6)
		if rig and hum then
			walkTo(rig, hum, track, doorPos)
		end
		if rig then
			rig:Destroy()
			driver = nil
		end
		Net.Sound(nil, "van_door_close", doorPos)
		task.wait(0.8)
		runPhase(m, hit, "depart")
	end)
	if driver then
		driver:Destroy()
	end
	m:Destroy()
	if not ok then
		error(err, 0)
	end
end

-- shared with other vehicles (Server/GarbageTruckService): NPC worker, walking, carrying, timeline
DeliveryVanService.Kit = {
	newWorker = newDriver,
	walkTo = walkTo,
	carry = carry,
	setPhase = setPhase,
	runPhase = runPhase,
	pose = pose,
}

return DeliveryVanService
