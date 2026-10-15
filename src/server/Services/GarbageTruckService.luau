-- Garbage truck for the paid waste collection (issue #14). Same technique as the delivery van
-- (Server/DeliveryVanService, Shared/VanRoute): the server only sets the timeline attributes
-- (Phase / T0) and moves an invisible hitbox; every client renders the truck (tag "DeliveryVan").
-- Route: along the back street, stop with the rear hopper at the backyard gate, a worker in
-- orange walks to every non-empty container, takes the bags out (lid opens), carries them to the
-- hopper and throws them in; then the truck drives off.
-- Model: ServerStorage.Models.Truck (art/waste/build_truck.py: TruckPaint, TruckDark, TruckGlass,
-- TruckWhite, TruckWheel) or a primitive fallback in the same proportions.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Services = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Services.Net)
local DeliveryVanService = require(Services.DeliveryVanService)
local VanRoute = require(Shared.VanRoute)

local GarbageTruckService = {}
local Kit = DeliveryVanService.Kit

local ORANGE = Color3.fromRGB(240, 110, 20)
local DARK = Color3.fromRGB(30, 30, 34)
local GLASS = Color3.fromRGB(30, 40, 48)
local WHEELS = { { -2.75, -6.9 }, { 2.75, -6.9 }, { -2.75, 1.7 }, { 2.75, 1.7 }, { -2.75, 4.6 }, { 2.75, 4.6 } }
-- bounding-box centres / sizes of the Blender meshes (printed by build_truck.py), truck space
local MESHES = {
	{ "TruckPaint", "Body", Vector3.new(0, 4.899, -0.12), Vector3.new(6.2, 6.998, 18.161) },
	{ "TruckDark", "Dark", Vector3.new(0, 3.65, -0.25), Vector3.new(7.5, 5.9, 18.7) },
	{ "TruckGlass", "Glass", Vector3.new(0, 5.95, -7.125), Vector3.new(6.26, 2.7, 4.25) },
	{ "TruckWhite", "Stripes", Vector3.new(0, 3.45, 0.7), Vector3.new(6.26, 0.9, 9.4) },
}
local WORKER_LOOK = { skin = Color3.fromRGB(196, 150, 110), shirt = Color3.fromRGB(240, 110, 20), pants = Color3.fromRGB(240, 110, 20), shoes = Color3.fromRGB(30, 30, 30), hair = Color3.fromRGB(40, 30, 25), hat = true, hatColor = Color3.fromRGB(240, 110, 20) }

local busy = false

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

local function wheel(p: BasePart)
	p:SetAttribute("Role", "wheel")
	p:SetAttribute("Radius", 1.1)
end

local function fromTemplates(m: Model): boolean
	local lib = ServerStorage:FindFirstChild("Models")
	local t = lib and lib:FindFirstChild("Truck")
	if not t or not t:FindFirstChild("TruckPaint") or not t:FindFirstChild("TruckWheel") then
		return false
	end
	for _, def in ipairs(MESHES) do
		local src = t:FindFirstChild(def[1]) :: BasePart?
		if src then
			local p = src:Clone()
			p.Name = def[2]
			p.Size = def[4]
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p:SetAttribute("Local", CFrame.new(def[3]))
			p.Parent = m
		end
	end
	for _, xz in ipairs(WHEELS) do
		local p = (t.TruckWheel :: BasePart):Clone()
		p.Name = "Wheel"
		p.Size = Vector3.new(0.88, 2.2, 2.2)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p:SetAttribute("Local", CFrame.new(xz[1], 1.1, xz[2]))
		p.Parent = m
		wheel(p)
	end
	return true
end

local function primitive(m: Model)
	vpart(m, "Body", Vector3.new(6.2, 6.5, 9.8), CFrame.new(0, 5.15, 0.7), ORANGE)
	vpart(m, "Tailgate", Vector3.new(6.0, 6.2, 2.4), CFrame.new(0, 4.9, 6.8), ORANGE)
	vpart(m, "Cab", Vector3.new(6.2, 6.0, 4.6), CFrame.new(0, 4.4, -6.9), ORANGE)
	vpart(m, "Windscreen", Vector3.new(5.6, 2.2, 0.1), CFrame.new(0, 6.0, -9.2) * CFrame.Angles(math.rad(-12), 0, 0), GLASS, Enum.Material.Glass)
	vpart(m, "Chassis", Vector3.new(4.8, 0.7, 17.2), CFrame.new(0, 1.25, 0), DARK)
	vpart(m, "Hopper", Vector3.new(5.6, 3.0, 1.4), CFrame.new(0, 2.5, 8.3), DARK)
	vpart(m, "Bumper", Vector3.new(6.3, 0.9, 0.5), CFrame.new(0, 1.15, -9.35), DARK)
	for _, x in ipairs({ -3.12, 3.12 }) do
		vpart(m, "Stripe", Vector3.new(0.04, 0.3, 9.4), CFrame.new(x, 3.15, 0.7), Color3.fromRGB(235, 235, 230), Enum.Material.Neon)
		vpart(m, "SideWindow", Vector3.new(0.05, 2.2, 2.8), CFrame.new(x, 5.8, -6.6), GLASS, Enum.Material.Glass)
	end
	for _, xz in ipairs(WHEELS) do
		wheel(vpart(m, "Wheel", Vector3.new(0.85, 2.2, 2.2), CFrame.new(xz[1], 1.1, xz[2]), Color3.fromRGB(22, 22, 24), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
	end
end

local function build(): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "GarbageTruck"
	if not fromTemplates(m) then
		primitive(m)
	end
	local hit = Instance.new("Part")
	hit.Name = "Hitbox"
	hit.Size = Vector3.new(6.2, 7, 18.4)
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = true
	hit.CanQuery = false
	hit.CanTouch = false
	hit.Parent = m
	m.PrimaryPart = hit
	return m, hit
end

function GarbageTruckService.Busy(): boolean
	return busy
end

-- stops: list of { stand: Vector3, take: () -> Model?, taken: () -> () }
--   stand  where the worker stands in front of the container
--   take   opens the lid and returns the bag model for the worker to carry (nil = nothing)
--   taken  called once the bags are in the hopper (empties the container)
-- Blocks until the truck has left. Never leaves things half done: on an error every stop not yet
-- emptied is emptied anyway (the player paid), then the error is re-raised.
function GarbageTruckService.Run(stops: { any })
	if busy then
		return false
	end
	busy = true
	local m, hit = build()
	Kit.setPhase(m, "truck_arrive")
	local start = Kit.pose(m)
	hit.CFrame = start * CFrame.new(0, 3.5, 0)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and typeof(p:GetAttribute("Local")) == "CFrame" then
			p.CFrame = start * p:GetAttribute("Local")
		end
	end
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m:SetAttribute("DoorsOpen", false)
	CollectionService:AddTag(m, "DeliveryVan")
	m.Parent = workspace
	local done = {}
	local worker: Model? = nil
	local ok, err = pcall(function()
		Kit.runPhase(m, hit, "truck_arrive")
		Net.Sound(nil, "van_brake", hit.Position)
		Kit.setPhase(m, "truck_parked")
		local park = VanRoute.Pose("truck_parked", 0)
		hit.CFrame = park * CFrame.new(0, 3.5, 0)
		task.wait(0.8)
		-- the loader jumps off the step at the back
		local hopper = (park * CFrame.new(0, 3, 10.6)).Position
		local inYard = Vector3.new(VanRoute.GATE_X - 3, hopper.Y, -46)
		local rig, hum, track = Kit.newWorker(WORKER_LOOK, "WasteCollector")
		worker = rig
		if rig then
			rig:PivotTo(CFrame.new(hopper))
			rig.Parent = workspace
		end
		for i, stop in ipairs(stops) do
			if rig and hum then
				Kit.walkTo(rig, hum, track, inYard)
				Kit.walkTo(rig, hum, track, stop.stand)
			end
			local bag = stop.take()
			task.wait(0.6)
			if bag and rig and hum then
				Kit.carry(rig, bag)
				Kit.walkTo(rig, hum, track, inYard)
				Kit.walkTo(rig, hum, track, hopper)
				-- throw the bags into the hopper
				for _, p in ipairs(bag:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Anchored = true
						for _, w in ipairs(p:GetChildren()) do
							if w:IsA("WeldConstraint") then
								w:Destroy()
							end
						end
					end
				end
				bag.Parent = workspace
				local target = park * CFrame.new(0, 2.6, 8.4)
				local primary = bag.PrimaryPart or bag:FindFirstChildWhichIsA("BasePart")
				if primary then
					local offset = target * primary.CFrame:Inverse()
					for _, p in ipairs(bag:GetDescendants()) do
						if p:IsA("BasePart") then
							TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = offset * p.CFrame }):Play()
						end
					end
				end
				Net.Sound(nil, "wrap", hopper)
				task.wait(0.5)
				bag:Destroy()
				Net.Sound(nil, "van_door_close", hopper)
			elseif bag then
				bag:Destroy()
			end
			stop.taken()
			done[i] = true
		end
		if rig and hum then
			Kit.walkTo(rig, hum, track, hopper)
		end
		if rig then
			rig:Destroy()
			worker = nil
		end
		task.wait(0.8)
		Kit.runPhase(m, hit, "truck_depart")
	end)
	for i, stop in ipairs(stops) do
		if not done[i] then
			pcall(stop.taken)
		end
	end
	if worker then
		worker:Destroy()
	end
	m:Destroy()
	busy = false
	if not ok then
		error(err, 0)
	end
	return true
end

return GarbageTruckService
