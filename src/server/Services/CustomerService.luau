-- Customer NPCs: appearance, navigation (direct moves + PathfindingService + teleport fallback),
-- the behaviour state machine, patience, dialogue, eating and leaving. Also street pedestrians.
--
-- States: Entering -> Queuing -> Ordering -> WaitingForFood -> ReceivingFood -> Eating -> Leaving
--         any waiting state -> Cancelled -> Leaving

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local OrderLogic = require(Shared.OrderLogic)
local DialogueConfig = require(Shared.DialogueConfig)
local Net = require(script.Parent.Net)
local RestaurantService = require(script.Parent.RestaurantService)
local OrderService = require(script.Parent.OrderService)
local FoodPreparationService = require(script.Parent.FoodPreparationService)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)

local CustomerService = {}

local rng = Random.new()
local nextId = 0
local customers: { [number]: any } = {}
local queue: { any } = {} -- customers in Entering/Queuing, in queue order
local orderingCustomer: any = nil
local pickupOwner: { [number]: any } = {}
local seatOwner: { [Instance]: any } = {}
local pool: { Model } = {}
local pedestrians = 0
local customerFolder: Folder
local pedFolder: Folder
local poolFolder: Folder
local animIds: { [string]: string } = {}

local recentOrders: { string } = {} -- signatures of the last orders, to keep orders varied
local WAITING_STATES = { Entering = true, Queuing = true, Ordering = true, WaitingForFood = true }

---------------------------------------------------------------------------
-- Collision groups
---------------------------------------------------------------------------
local function setupCollisionGroups()
	for _, g in ipairs({ "Customers", "Players", "NPCBlocker" }) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(g)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Customers", "Customers", false)
	PhysicsService:CollisionGroupSetCollidable("Customers", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("NPCBlocker", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("NPCBlocker", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("NPCBlocker", "Customers", true)
	local r = workspace:FindFirstChild("Restaurant")
	if r then
		for _, p in ipairs(r:GetDescendants()) do
			if p:IsA("BasePart") and p:GetAttribute("NPCBlocker") then
				p.CollisionGroup = "NPCBlocker"
			end
		end
	end
	local function setPlayerGroup(char: Model)
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CollisionGroup = "Players"
			end
		end
		char.DescendantAdded:Connect(function(p)
			if p:IsA("BasePart") then
				p.CollisionGroup = "Players"
			end
		end)
	end
	local function onPlayer(pl: Player)
		pl.CharacterAdded:Connect(setPlayerGroup)
		if pl.Character then
			setPlayerGroup(pl.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, pl in ipairs(Players:GetPlayers()) do
		onPlayer(pl)
	end
end

---------------------------------------------------------------------------
-- Appearance
---------------------------------------------------------------------------
local SKIN = {
	Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 192, 160), Color3.fromRGB(204, 150, 110),
	Color3.fromRGB(160, 110, 75), Color3.fromRGB(110, 75, 50), Color3.fromRGB(245, 205, 175),
}
local SHIRT = {
	Color3.fromRGB(40, 80, 160), Color3.fromRGB(180, 40, 40), Color3.fromRGB(40, 130, 80), Color3.fromRGB(230, 230, 230),
	Color3.fromRGB(30, 30, 35), Color3.fromRGB(240, 180, 40), Color3.fromRGB(120, 60, 150), Color3.fromRGB(230, 120, 60),
	Color3.fromRGB(90, 140, 200), Color3.fromRGB(150, 150, 150),
}
local PANTS = {
	Color3.fromRGB(40, 50, 80), Color3.fromRGB(30, 30, 35), Color3.fromRGB(110, 90, 60), Color3.fromRGB(70, 70, 75),
	Color3.fromRGB(60, 90, 130), Color3.fromRGB(150, 130, 100),
}
local HAIR = {
	Color3.fromRGB(30, 25, 20), Color3.fromRGB(90, 60, 30), Color3.fromRGB(200, 160, 90), Color3.fromRGB(140, 80, 40),
	Color3.fromRGB(180, 180, 180), Color3.fromRGB(60, 40, 30),
}

local function readAnimIds(rig: Model)
	if next(animIds) then
		return
	end
	local animate = rig:FindFirstChild("Animate")
	if not animate then
		return
	end
	for _, name in ipairs({ "walk", "idle", "sit", "wave", "cheer", "laugh", "point" }) do
		local v = animate:FindFirstChild(name)
		local a = v and v:FindFirstChildWhichIsA("Animation")
		if a and a.AnimationId ~= "" then
			animIds[name] = a.AnimationId
		end
	end
end

local function addAccessoryPart(rig: Model, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
	local head = rig:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = head.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = head
	w.Part1 = p
	w.Parent = p
	p:SetAttribute("Accessory", true)
	p.Parent = rig
	return p
end

-- accessory on any body part; size/offset are fractions of that part's size
local function addRel(rig: Model, partName: string, name: string, sizeF: Vector3, offF: Vector3, color: Color3, material: Enum.Material?, rot: CFrame?)
	local base = rig:FindFirstChild(partName) :: BasePart?
	if not base then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = base.Size * sizeF
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = base.CFrame * CFrame.new(base.Size * offF) * (rot or CFrame.identity)
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p:SetAttribute("Accessory", true)
	p.Parent = rig
	return p
end

-- eyebrows (welded with a Weld so the mood can tilt them), hairstyles, beards, jackets, bags …
local function dressExtras(rig: Model, look)
	local head = rig:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum and look.scale then
		for name, v in pairs({ BodyHeightScale = look.scale[1], BodyWidthScale = look.scale[2], BodyDepthScale = look.scale[2] }) do
			local nv = hum:FindFirstChild(name)
			if nv and nv:IsA("NumberValue") then
				nv.Value = v
			end
		end
	end
	for i, x in ipairs({ -0.2, 0.2 }) do
		local b = Instance.new("Part")
		b.Name = i == 1 and "BrowL" or "BrowR"
		b.Size = Vector3.new(0.3, 0.07, 0.05)
		b.Color = look.hair or Color3.fromRGB(40, 30, 20)
		b.Material = Enum.Material.SmoothPlastic
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.Massless = true
		local w = Instance.new("Weld")
		w.Name = "BrowWeld"
		w.Part0 = head
		w.Part1 = b
		w.C0 = CFrame.new(x, 0.24, -0.6)
		w:SetAttribute("Base", w.C0)
		w.Parent = b
		b.CFrame = head.CFrame * w.C0
		b:SetAttribute("Accessory", true)
		b.Parent = rig
	end
	if not look.hat then
		local style = look.hairStyle
		local hair = look.hair
		if style == "bald" then
			local h = rig:FindFirstChild("Hair")
			if h then
				h:Destroy()
			end
		elseif style == "bun" then
			addAccessoryPart(rig, "Bun", Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, 0.7, 0.45), hair, Enum.Material.Fabric)
		elseif style == "ponytail" then
			addAccessoryPart(rig, "Ponytail", Vector3.new(0.3, 0.9, 0.3), CFrame.new(0, 0.05, 0.72) * CFrame.Angles(math.rad(-20), 0, 0), hair, Enum.Material.Fabric)
		elseif style == "curly" then
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2
				addAccessoryPart(rig, "Curl", Vector3.new(0.5, 0.5, 0.5), CFrame.new(math.cos(a) * 0.45, 0.55, math.sin(a) * 0.45), hair, Enum.Material.Fabric)
			end
		elseif style == "mohawk" then
			local h = rig:FindFirstChild("Hair")
			if h then
				h:Destroy()
			end
			addAccessoryPart(rig, "Mohawk", Vector3.new(0.25, 0.45, 1.25), CFrame.new(0, 0.72, 0.05), hair, Enum.Material.Fabric)
		elseif style == "side" then
			addAccessoryPart(rig, "Fringe", Vector3.new(0.9, 0.22, 0.25), CFrame.new(0.18, 0.38, -0.58) * CFrame.Angles(0, 0, math.rad(-12)), hair, Enum.Material.Fabric)
		end
	end
	if look.beard then
		addAccessoryPart(rig, "Beard", Vector3.new(0.95, 0.42, 0.3), CFrame.new(0, -0.42, -0.5), look.hair, Enum.Material.Fabric)
	end
	if look.headphones then
		addAccessoryPart(rig, "Headphones", Vector3.new(1.4, 0.12, 0.22), CFrame.new(0, 0.66, 0), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic)
		for _, x in ipairs({ -0.66, 0.66 }) do
			addAccessoryPart(rig, "Earcup", Vector3.new(0.18, 0.45, 0.45), CFrame.new(x, 0.05, 0), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic)
		end
	end
	if look.jacket then
		-- open jacket: sleeves + two front panels, the shirt shows in the middle
		for _, n in ipairs({ "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm" }) do
			local p = rig:FindFirstChild(n) :: BasePart?
			if p then
				p.Color = look.jacket
			end
		end
		addRel(rig, "UpperTorso", "JacketL", Vector3.new(0.4, 1.02, 1.08), Vector3.new(-0.31, 0, 0), look.jacket)
		addRel(rig, "UpperTorso", "JacketR", Vector3.new(0.4, 1.02, 1.08), Vector3.new(0.31, 0, 0), look.jacket)
		addRel(rig, "UpperTorso", "JacketBack", Vector3.new(1.04, 1.02, 0.2), Vector3.new(0, 0, 0.47), look.jacket)
	end
	if look.scarf then
		addRel(rig, "UpperTorso", "Scarf", Vector3.new(0.75, 0.2, 1.15), Vector3.new(0, 0.45, 0), look.scarf, Enum.Material.Fabric)
	end
	if look.backpack then
		addRel(rig, "UpperTorso", "Backpack", Vector3.new(0.7, 0.85, 0.55), Vector3.new(0, -0.05, 0.75), look.backpack, Enum.Material.Fabric)
	end
	if look.bag then
		addRel(rig, "UpperTorso", "BagStrap", Vector3.new(0.12, 1.25, 1.06), Vector3.new(0, 0, 0), Color3.fromRGB(80, 50, 30), Enum.Material.Leather, CFrame.Angles(0, 0, math.rad(35)))
		addRel(rig, "LowerTorso", "Bag", Vector3.new(0.4, 0.9, 0.9), Vector3.new(-0.62, -0.3, 0), Color3.fromRGB(110, 70, 40), Enum.Material.Leather)
	end
	if look.watch then
		addRel(rig, "LeftLowerArm", "Watch", Vector3.new(1.08, 0.12, 1.08), Vector3.new(0, -0.35, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	end
end

local function dress(rig: Model, look)
	for _, p in ipairs(rig:GetChildren()) do
		if p:GetAttribute("Accessory") then
			p:Destroy()
		end
	end
	for _, p in ipairs(rig:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local n = p.Name
			if n == "Head" or string.find(n, "Hand") then
				p.Color = look.skin
			elseif string.find(n, "Torso") or string.find(n, "Arm") then
				p.Color = (n == "LowerTorso") and look.pants or look.shirt
			elseif string.find(n, "Leg") then
				p.Color = look.pants
			elseif string.find(n, "Foot") then
				p.Color = look.shoes
			end
		end
	end
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end
	local head = rig:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	if look.hat then
		addAccessoryPart(rig, "Cap", Vector3.new(1.25, 0.4, 1.25), CFrame.new(0, 0.55, 0), look.hatColor, Enum.Material.Fabric)
		addAccessoryPart(rig, "Brim", Vector3.new(1.1, 0.1, 0.6), CFrame.new(0, 0.4, -0.7), look.hatColor, Enum.Material.Fabric)
	else
		addAccessoryPart(rig, "Hair", Vector3.new(1.3, 0.45, 1.3), CFrame.new(0, 0.5, 0.05), look.hair, Enum.Material.Fabric)
		if look.longHair then
			addAccessoryPart(rig, "HairBack", Vector3.new(1.25, 1.2, 0.35), CFrame.new(0, -0.05, 0.55), look.hair, Enum.Material.Fabric)
		end
	end
	if look.glasses then
		addAccessoryPart(rig, "Glasses", Vector3.new(1.05, 0.22, 0.1), CFrame.new(0, 0.1, -0.62), Color3.fromRGB(20, 20, 20), Enum.Material.Metal)
	end
	if look.vip then
		addAccessoryPart(rig, "Beret", Vector3.new(1.35, 0.25, 1.35), CFrame.new(0, 0.65, 0), Color3.fromRGB(20, 20, 20), Enum.Material.Fabric)
	end
	dressExtras(rig, look)
end

local function randomLook(vip: boolean, r: Random?)
	local rng = r or rng
	return {
		skin = SKIN[rng:NextInteger(1, #SKIN)],
		shirt = vip and Color3.fromRGB(25, 25, 30) or SHIRT[rng:NextInteger(1, #SHIRT)],
		pants = PANTS[rng:NextInteger(1, #PANTS)],
		shoes = Color3.fromRGB(30, 30, 30):Lerp(Color3.fromRGB(240, 240, 240), rng:NextNumber() < 0.3 and 1 or 0),
		hair = HAIR[rng:NextInteger(1, #HAIR)],
		longHair = rng:NextNumber() < 0.4,
		hat = rng:NextNumber() < 0.25,
		hatColor = SHIRT[rng:NextInteger(1, #SHIRT)],
		glasses = rng:NextNumber() < 0.2,
		vip = vip,
		-- extra variety (appended so older looks stay the same)
		hairStyle = ({ "short", "short", "long", "bun", "ponytail", "curly", "mohawk", "side", "bald" })[rng:NextInteger(1, 9)],
		beard = rng:NextNumber() < 0.25,
		scale = { rng:NextNumber(0.94, 1.06), rng:NextNumber(0.9, 1.12) },
		jacket = rng:NextNumber() < 0.35 and PANTS[rng:NextInteger(1, #PANTS)] or nil,
		scarf = rng:NextNumber() < 0.15 and SHIRT[rng:NextInteger(1, #SHIRT)] or nil,
		backpack = rng:NextNumber() < 0.2 and SHIRT[rng:NextInteger(1, #SHIRT)] or nil,
		headphones = rng:NextNumber() < 0.15,
		bag = rng:NextNumber() < 0.15,
		watch = rng:NextNumber() < 0.4,
	}
end

local function newRig(): Model?
	local rig = table.remove(pool)
	if rig then
		return rig
	end
	local ok, res = pcall(function()
		local d = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	if not ok or not res then
		warn("[CustomerService] rig creation failed:", res)
		return nil
	end
	rig = res :: Model
	readAnimIds(rig)
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy() -- client-side script; animations are driven from the server below
	end
	local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	for _, p in ipairs(rig:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Customers"
			p.CanQuery = p.Name == "HumanoidRootPart" or p.Name == "Head" or string.find(p.Name, "Torso") ~= nil
			p.CanTouch = false
		end
	end
	return rig
end

local function releaseRig(rig: Model)
	if #pool < 10 then
		local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
		end
		local hum = rig:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				t:Stop(0)
			end
		end
		for a in pairs(rig:GetAttributes()) do
			rig:SetAttribute(a, nil)
		end
		-- undo slap / rant joint offsets
		for _, m in ipairs(rig:GetDescendants()) do
			if m:IsA("Motor6D") and m:GetAttribute("BaseC0") then
				m.C0 = m:GetAttribute("BaseC0")
			end
		end
		CollectionService:RemoveTag(rig, "Customer")
		CollectionService:RemoveTag(rig, "Pedestrian")
		rig.Parent = poolFolder
		table.insert(pool, rig)
	else
		rig:Destroy()
	end
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------
local function setupAnims(c)
	local hum: Humanoid = c.humanoid
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	c.tracks = {}
	for name, id in pairs(animIds) do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if ok and track then
			c.tracks[name] = track
			if name == "walk" or name == "idle" then
				track.Looped = true
				track.Priority = name == "walk" and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Idle
			elseif name == "sit" then
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Action
			else
				track.Priority = Enum.AnimationPriority.Action
			end
		end
	end
	if c.tracks.idle then
		c.tracks.idle:Play()
	end
	if c.runConn then
		c.runConn:Disconnect()
	end
	c.runConn = hum.Running:Connect(function(speed)
		local walk = c.tracks.walk
		if not walk or c.sitting then
			return
		end
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.15)
			end
			walk:AdjustSpeed(speed / 12)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
end

local function playOnce(c, name: string)
	local t = c.tracks and c.tracks[name]
	if t then
		t:Play(0.1)
	end
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
local function nav(name: string): Vector3
	local r = workspace:FindFirstChild("Restaurant")
	local n = r and r:FindFirstChild("Nav")
	local p = n and n:FindFirstChild(name) :: BasePart?
	return p and p.Position or Vector3.zero
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- direct MoveTo with re-issue and timeout; returns reached
local function moveDirect(c, pos: Vector3, token: number): boolean
	local hum: Humanoid = c.humanoid
	local root: BasePart = c.root
	local dist = flatDist(root.Position, pos)
	local timeout = dist / math.max(hum.WalkSpeed, 1) + 2.5
	local start = os.clock()
	local lastIssue = 0
	local lastPos = root.Position
	local stuckTime = 0
	while c.moveToken == token and c.alive do
		if flatDist(root.Position, pos) < 1.3 then
			return true
		end
		if os.clock() - lastIssue > 5 then
			hum:MoveTo(pos)
			lastIssue = os.clock()
		end
		local dt = task.wait(0.15)
		if (root.Position - lastPos).Magnitude < 0.05 then
			stuckTime += dt
		else
			stuckTime = 0
		end
		lastPos = root.Position
		if stuckTime > 1.2 or os.clock() - start > timeout then
			return false
		end
	end
	return false
end

-- the kitchen blockers carry a PassThrough PathfindingModifier (staff walk through), customers never
local agentParams = { AgentRadius = 1.3, AgentHeight = 5.2, AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 5, Costs = { NPCBlocker = math.huge } }

local function movePath(c, pos: Vector3, token: number): boolean
	local path = PathfindingService:CreatePath(agentParams)
	local ok = pcall(function()
		path:ComputeAsync(c.root.Position, pos)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end
	for _, wp in ipairs(path:GetWaypoints()) do
		if c.moveToken ~= token or not c.alive then
			return false
		end
		if not moveDirect(c, wp.Position, token) then
			return false
		end
	end
	return true
end

-- Walk through a list of points. mode "path" uses pathfinding first.
-- Fallback chain: direct -> pathfinding -> teleport, so customers can never get stuck permanently.
local function walk(c, points: { Vector3 }, mode: string?): boolean
	c.moveToken += 1
	local token = c.moveToken
	c.root.Anchored = false
	c.humanoid.AutoRotate = true
	for _, p in ipairs(points) do
		if c.moveToken ~= token or not c.alive then
			return false
		end
		local reached
		if mode == "path" then
			reached = movePath(c, p, token) or moveDirect(c, p, token)
		else
			reached = moveDirect(c, p, token) or movePath(c, p, token)
		end
		if c.moveToken ~= token or not c.alive then
			return false
		end
		if not reached then
			c.teleports = (c.teleports or 0) + 1
			c.model:PivotTo(CFrame.new(p) * (c.root.CFrame - c.root.Position))
			task.wait(0.1)
		end
	end
	return c.moveToken == token
end

local function face(c, target: Vector3)
	local root: BasePart = c.root
	local pos = root.Position
	local look = Vector3.new(target.X, pos.Y, target.Z)
	if (look - pos).Magnitude < 0.1 then
		return
	end
	c.humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(pos, look)
end

local function nearestPlayer(pos: Vector3, maxDist: number): Vector3?
	local best, bestD = nil, maxDist
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			local d = (r.Position - pos).Magnitude
			if d < bestD then
				best, bestD = r.Position, d
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Speech
---------------------------------------------------------------------------
local speakHook: ((any) -> ())? = nil -- turns the head toward the nearest player (set below)
local function say(c, category: string, kind: string?)
	local line = DialogueConfig.Line(category, c.personality, rng)
	Net.FireAll("Say", c.model, line, kind or category)
	if speakHook then
		speakHook(c)
	end
	return line
end

local function sayText(c, line, kind: string?)
	Net.FireAll("Say", c.model, line, kind or "say")
	if speakHook then
		speakHook(c)
	end
end

---------------------------------------------------------------------------
-- Queue management
---------------------------------------------------------------------------
local eventLog: { string } = {}
local function log(msg: string)
	table.insert(eventLog, string.format("%.1f %s", os.clock(), msg))
	if #eventLog > 60 then
		table.remove(eventLog, 1)
	end
end
CustomerService.EventLog = eventLog

local function setState(c, state: string)
	if c.state ~= state then
		log(string.format("#%d %s -> %s", c.id or -1, tostring(c.state), state))
	end
	c.state = state
	c.model:SetAttribute("State", state)
end

local function freePickup(): number?
	for i = 1, Config.Customers.MaxPickupSpots do
		if not pickupOwner[i] then
			return i
		end
	end
	return nil
end

local relayout

local function goToQueueSlot(c, index: number)
	if c.queueIndex == index and c.queueArrived then
		return
	end
	c.queueIndex = index
	c.queueArrived = false
	local target = nav("Queue" .. math.min(index, 5))
	task.spawn(function()
		local points = {}
		if c.state == "Entering" then
			table.insert(points, nav("DoorOut"))
			table.insert(points, nav("DoorIn"))
		end
		table.insert(points, target)
		if walk(c, points) and c.queueIndex == index then
			c.queueArrived = true
			if c.state == "Entering" then
				setState(c, "Queuing")
			end
			face(c, nav("OrderSpot") + Vector3.new(0, 0, -6))
			relayout()
		end
	end)
end

local function promoteToOrdering()
	if orderingCustomer then
		return
	end
	local first = queue[1]
	if not first or first.state ~= "Queuing" or not first.queueArrived then
		return
	end
	table.remove(queue, 1)
	orderingCustomer = first
	first.queueIndex = nil
	-- everyone behind moves up one spot
	for i, c in ipairs(queue) do
		goToQueueSlot(c, i)
	end
	task.spawn(function()
		if walk(first, { nav("OrderSpot") }) then
			setState(first, "Ordering")
			first.orderArrived = true
			face(first, nav("OrderSpot") + Vector3.new(0, 0, -8))
			if rng:NextNumber() < 0.6 then
				say(first, "greet", "greet")
				playOnce(first, "wave")
			end
		end
	end)
end

function relayout()
	for i, c in ipairs(queue) do
		goToQueueSlot(c, i)
	end
	promoteToOrdering()
end

local function assignPickup(c)
	local idx = freePickup()
	if not idx then
		return false
	end
	pickupOwner[idx] = c
	c.pickup = idx
	task.spawn(function()
		if walk(c, { nav("Pickup" .. idx) }) then
			face(c, nav("Pickup" .. idx) + Vector3.new(0, 0, -8))
		end
	end)
	return true
end

local function releaseSpots(c)
	local qi = table.find(queue, c)
	if qi then
		table.remove(queue, qi)
	end
	if orderingCustomer == c then
		orderingCustomer = nil
	end
	if c.pickup and pickupOwner[c.pickup] == c then
		pickupOwner[c.pickup] = nil
	end
	c.pickup = nil
	if c.seat and seatOwner[c.seat] == c then
		seatOwner[c.seat] = nil
	end
	c.seat = nil
	relayout()
	-- anyone waiting at the order spot for a free pickup slot can move now
	for _, other in pairs(customers) do
		if other.state == "WaitingForFood" and not other.pickup then
			if assignPickup(other) and orderingCustomer == other then
				orderingCustomer = nil
				relayout()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function despawn(c)
	if not c.alive then
		return
	end
	log(string.format("#%d despawn", c.id or -1))
	c.alive = false
	c.moveToken += 1
	customers[c.id] = nil
	if c.runConn then
		c.runConn:Disconnect()
	end
	if c.eatModel then
		c.eatModel:Destroy()
	end
	releaseRig(c.model)
end

local function leave(c, angry: boolean?)
	if c.state == "Leaving" then
		return
	end
	log(string.format("#%d leave from %s angry=%s\n%s", c.id, tostring(c.state), tostring(angry), debug.traceback("", 2)))
	local wasSeated = c.sitting
	if CustomerService.LeaveHook then
		pcall(CustomerService.LeaveHook, c, angry, wasSeated and c.seat or nil)
	end
	if c.sitting then
		c.sitting = false
		if c.tracks.sit then
			c.tracks.sit:Stop(0.2)
		end
		c.root.Anchored = false
		c.model:PivotTo(CFrame.new(c.seatStand or c.root.Position + Vector3.new(0, 1, 0)))
	end
	if c.eatModel then
		c.eatModel:Destroy()
		c.eatModel = nil
	end
	setState(c, angry and "Cancelled" or "Leaving")
	releaseSpots(c)
	OrderService.RemoveTicket(c)
	c.state = "Leaving"
	c.model:SetAttribute("State", angry and "Cancelled" or "Leaving")
	task.spawn(function()
		if angry then
			task.wait(1.2)
		end
		local exitSide = rng:NextNumber() < 0.5 and "SpawnL" or "SpawnR"
		local points = {}
		local pos = c.root.Position
		if wasSeated and c.approach and c.seat and c.seat:GetAttribute("Outdoor") then
			-- terrace guests are already outside: straight back to the street
			for i = #c.approach - 1, 1, -1 do
				table.insert(points, c.approach[i])
			end
			table.insert(points, nav(exitSide))
			walk(c, points)
			despawn(c)
			return
		elseif wasSeated and c.approach then
			-- retrace the seat approach back to the aisle
			for i = #c.approach - 1, 1, -1 do
				table.insert(points, c.approach[i])
			end
			table.insert(points, nav(c.seatEntry or "AisleEntry"))
		elseif pos.X < -9 then
			table.insert(points, nav("AisleEntry"))
		elseif pos.X > 18 then
			table.insert(points, nav("LoungeEntry"))
		end
		if pos.Z < 1 then
			table.insert(points, nav("ExitA"))
		end
		table.insert(points, nav("ExitB"))
		table.insert(points, nav("DoorIn"))
		table.insert(points, nav("DoorOut"))
		table.insert(points, nav(exitSide))
		walk(c, points)
		despawn(c)
	end)
end

local function cancel(c)
	if not WAITING_STATES[c.state] then
		return
	end
	say(c, "leave_angry", "angry")
	playOnce(c, "point")
	Net.NotifyAll("n_walkout", { name = c.name }, "bad")
	Net.Sound(nil, "complain", c.root.Position)
	RestaurantService.Record("walkouts", 1)
	RestaurantService.Rate(1, 0.5)
	for _, p in ipairs(Players:GetPlayers()) do
		EconomyService.AddStat(p, "walkouts", 1)
	end
	leave(c, true)
end

---------------------------------------------------------------------------
-- Aggressive customers & slapping ("Backpfeife")
---------------------------------------------------------------------------
local slapCooldown: { [Player]: number } = {}

local function motor(model: Instance, partName: string, motorName: string): Motor6D?
	local p = model:FindFirstChild(partName)
	local m = p and p:FindFirstChild(motorName)
	if m and m:IsA("Motor6D") then
		return m
	end
	return nil
end

-- offset a joint (C0) and ease back; the original C0 is remembered so overlapping kicks never drift
local function jointKick(m: Motor6D?, offset: CFrame, tIn: number, hold: number, tOut: number)
	if not m then
		return
	end
	local base = m:GetAttribute("BaseC0")
	if typeof(base) ~= "CFrame" then
		base = m.C0
		m:SetAttribute("BaseC0", base)
	end
	TweenService:Create(m, TweenInfo.new(tIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = base * offset }):Play()
	task.delay(tIn + hold, function()
		if m.Parent then
			TweenService:Create(m, TweenInfo.new(tOut, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { C0 = base }):Play()
		end
	end)
end

-- angry head shaking + fist raised
local function headShake(c)
	local neck = motor(c.model, "Head", "Neck")
	task.spawn(function()
		for i = 1, 4 do
			jointKick(neck, CFrame.Angles(math.rad(-6), math.rad(i % 2 == 0 and 16 or -16), 0), 0.07, 0.02, 0.06)
			task.wait(0.13)
		end
	end)
	jointKick(motor(c.model, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(120), 0, math.rad(-15)), 0.15, 0.7, 0.35)
	jointKick(motor(c.model, "RightLowerArm", "RightElbow"), CFrame.Angles(math.rad(70), 0, 0), 0.15, 0.7, 0.35)
end

-- facial mood: eyebrows tilt (happy raised, annoyed / angry pulled together)
local MOOD = { happy = { 0.04, 10 }, neutral = { 0, 0 }, annoyed = { -0.02, -14 }, angry = { -0.05, -28 } }
local function setMood(c, mood: string)
	if c.mood == mood then
		return
	end
	c.mood = mood
	local d = MOOD[mood] or MOOD.neutral
	for _, n in ipairs({ "BrowL", "BrowR" }) do
		local b = c.model:FindFirstChild(n)
		local w = b and b:FindFirstChild("BrowWeld") :: Weld?
		local base = w and w:GetAttribute("Base")
		if w and typeof(base) == "CFrame" then
			local side = n == "BrowL" and 1 or -1
			TweenService:Create(w, TweenInfo.new(0.35), { C0 = base * CFrame.new(0, d[1], 0) * CFrame.Angles(0, 0, math.rad(d[2] * side)) }):Play()
		end
	end
end
CustomerService.SetMood = setMood

-- look at the player you are talking to
speakHook = function(c)
	if not c.root or c.sitting then
		return
	end
	local pos = nearestPlayer(c.root.Position, 16)
	if not pos then
		return
	end
	local rel = c.root.CFrame:PointToObjectSpace(pos + Vector3.new(0, 1.5, 0))
	local yaw = math.clamp(math.atan2(-rel.X, -rel.Z), math.rad(-65), math.rad(65))
	local pitch = math.clamp(math.atan2(rel.Y - 1.5, math.sqrt(rel.X ^ 2 + rel.Z ^ 2)), math.rad(-20), math.rad(25))
	jointKick(motor(c.model, "Head", "Neck"), CFrame.Angles(pitch, yaw, 0), 0.25, 2.2, 0.45)
end

local function armsCrossed(m: Model, hold: number)
	jointKick(motor(m, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(65), math.rad(38), 0), 0.4, hold, 0.5)
	jointKick(motor(m, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(math.rad(60), math.rad(-38), 0), 0.4, hold, 0.5)
	jointKick(motor(m, "RightLowerArm", "RightElbow"), CFrame.Angles(math.rad(95), 0, 0), 0.4, hold, 0.5)
	jointKick(motor(m, "LeftLowerArm", "LeftElbow"), CFrame.Angles(math.rad(95), 0, 0), 0.4, hold, 0.5)
end

local function extraGesture(c)
	local m = c.model
	local neck = motor(m, "Head", "Neck")
	local pick = rng:NextInteger(1, 6)
	if pick == 1 then
		armsCrossed(m, 2.6)
	elseif pick == 2 then
		-- hands on the hips
		jointKick(motor(m, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(-15), 0, math.rad(38)), 0.35, 2, 0.45)
		jointKick(motor(m, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(math.rad(-15), 0, math.rad(-38)), 0.35, 2, 0.45)
		jointKick(motor(m, "RightLowerArm", "RightElbow"), CFrame.Angles(math.rad(70), 0, 0), 0.35, 2, 0.45)
		jointKick(motor(m, "LeftLowerArm", "LeftElbow"), CFrame.Angles(math.rad(70), 0, 0), 0.35, 2, 0.45)
	elseif pick == 3 then
		-- scratch the head
		jointKick(motor(m, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(150), 0, math.rad(20)), 0.35, 1.4, 0.4)
		jointKick(motor(m, "RightLowerArm", "RightElbow"), CFrame.Angles(math.rad(110), 0, 0), 0.35, 1.4, 0.4)
		task.spawn(function()
			task.wait(0.4)
			for i = 1, 4 do
				jointKick(motor(m, "RightHand", "RightWrist"), CFrame.Angles(math.rad(i % 2 == 0 and 25 or -10), 0, 0), 0.12, 0.05, 0.1)
				task.wait(0.25)
			end
		end)
		jointKick(neck, CFrame.Angles(math.rad(-8), 0, math.rad(8)), 0.35, 1.4, 0.4)
	elseif pick == 4 then
		-- tap the foot
		task.spawn(function()
			for _ = 1, 5 do
				jointKick(motor(m, "RightFoot", "RightAnkle"), CFrame.Angles(math.rad(22), 0, 0), 0.1, 0.05, 0.12)
				task.wait(0.32)
			end
		end)
	elseif pick == 5 then
		-- stretch / yawn
		jointKick(motor(m, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(165), 0, math.rad(15)), 0.6, 0.9, 0.7)
		jointKick(motor(m, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(math.rad(165), 0, math.rad(-15)), 0.6, 0.9, 0.7)
		jointKick(neck, CFrame.Angles(math.rad(18), 0, 0), 0.6, 0.9, 0.7)
	else
		-- look around the room
		task.spawn(function()
			for _, y in ipairs({ -45, 35, 0 }) do
				jointKick(neck, CFrame.Angles(math.rad(rng:NextNumber(-5, 12)), math.rad(y), 0), 0.45, 0.6, 0.3)
				task.wait(1.1)
			end
		end)
	end
end

-- a bite while eating: hand to the mouth, chewing nod
local function biteGesture(c)
	local m = c.model
	jointKick(motor(m, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(95), math.rad(28), 0), 0.3, 0.5, 0.35)
	jointKick(motor(m, "RightLowerArm", "RightElbow"), CFrame.Angles(math.rad(115), 0, 0), 0.3, 0.5, 0.35)
	task.delay(0.5, function()
		for i = 1, 3 do
			jointKick(motor(m, "Head", "Neck"), CFrame.Angles(math.rad(i % 2 == 0 and -6 or 4), 0, 0), 0.12, 0.05, 0.12)
			task.wait(0.3)
		end
	end)
end

-- small idle behaviour while queuing / waiting so guests never stand frozen:
-- checking the phone, glancing at the watch, reading the menu board, shifting weight
local function idleGesture(c)
	local m = c.model
	local frac = c.patience / c.maxPatience
	local roll = rng:NextNumber()
	local neck = motor(m, "Head", "Neck")
	setMood(c, c.aggressive and "angry" or frac < 0.3 and "annoyed" or frac > 0.75 and "happy" or "neutral")
	if frac < 0.35 and rng:NextNumber() < 0.45 then
		armsCrossed(m, 3)
		return
	elseif rng:NextNumber() < 0.45 then
		extraGesture(c)
		return
	end
	if frac < 0.5 and roll < 0.5 then
		-- impatient: look at the watch, then sigh at the kitchen
		jointKick(motor(m, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(math.rad(80), 0, math.rad(40)), 0.3, 1.3, 0.4)
		jointKick(motor(m, "LeftLowerArm", "LeftElbow"), CFrame.Angles(math.rad(90), 0, 0), 0.3, 1.3, 0.4)
		jointKick(neck, CFrame.Angles(math.rad(-25), math.rad(15), 0), 0.3, 1.3, 0.4)
		if rng:NextNumber() < 0.4 then
			sayText(c, ({ "*seufz*", "Na komm schon …", "Dauert's noch lange?" })[rng:NextInteger(1, 3)], "impatient")
		end
	elseif roll < 0.4 then
		-- phone: a small phone appears in the right hand for a few seconds
		local hand = m:FindFirstChild("RightHand") :: BasePart?
		if hand then
			local ph = Instance.new("Part")
			ph.Name = "Phone"
			ph.Size = Vector3.new(0.35, 0.65, 0.06)
			ph.Color = Color3.fromRGB(20, 20, 24)
			ph.Material = Enum.Material.Glass
			ph.CanCollide = false
			ph.CanQuery = false
			ph.Massless = true
			ph.CFrame = hand.CFrame * CFrame.new(0, -0.15, -0.2)
			local w = Instance.new("WeldConstraint")
			w.Part0 = hand
			w.Part1 = ph
			w.Parent = ph
			ph:SetAttribute("Accessory", true)
			ph.Parent = m
			task.delay(3.6, function()
				ph:Destroy()
			end)
		end
		jointKick(motor(m, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(55), 0, math.rad(-12)), 0.35, 2.8, 0.4)
		jointKick(motor(m, "RightLowerArm", "RightElbow"), CFrame.Angles(math.rad(75), 0, 0), 0.35, 2.8, 0.4)
		jointKick(neck, CFrame.Angles(math.rad(-30), 0, 0), 0.35, 2.8, 0.4)
	elseif roll < 0.7 then
		-- read the menu board above the counter
		jointKick(neck, CFrame.Angles(math.rad(20), math.rad(rng:NextNumber(-25, 25)), 0), 0.5, 1.8, 0.5)
		if rng:NextNumber() < 0.35 then
			playOnce(c, "point")
		end
	else
		-- shift weight / look around
		jointKick(motor(m, "LowerTorso", "Root"), CFrame.Angles(0, 0, math.rad(rng:NextNumber() < 0.5 and 5 or -5)), 0.5, 1.5, 0.5)
		jointKick(neck, CFrame.Angles(0, math.rad(rng:NextNumber(-40, 40)), 0), 0.4, 1, 0.5)
	end
end

local function rant(c)
	c.nextRant = os.clock() + rng:NextNumber(Config.Aggro.RantMin, Config.Aggro.RantMax)
	sayText(c, DialogueConfig.Line("rant", c.personality, rng), "rant")
	local head = c.model:FindFirstChild("Head") :: BasePart?
	Net.Sound(nil, "angry" .. rng:NextInteger(1, 3), head and head.Position or c.root.Position)
	if rng:NextNumber() < 0.4 then
		playOnce(c, "point")
	else
		headShake(c)
	end
end

local function setAggressive(c)
	if c.aggressive then
		return
	end
	c.aggressive = true
	c.model:SetAttribute("Aggressive", true)
	setMood(c, "angry")
	-- face turns red with anger
	local head = c.model:FindFirstChild("Head") :: BasePart?
	if head then
		TweenService:Create(head, TweenInfo.new(1.5), { Color = head.Color:Lerp(Color3.fromRGB(215, 70, 60), 0.35) }):Play()
	end
	c.nextRant = os.clock() + rng:NextNumber(0.3, 1.5)
end

-- the slapper's arm swings (visible to everyone)
local function swingArm(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local sh = motor(char, "RightUpperArm", "RightShoulder")
	if not sh then
		return
	end
	jointKick(sh, CFrame.Angles(math.rad(85), math.rad(-55), 0), 0.1, 0.02, 0.01)
	task.delay(0.12, function()
		jointKick(sh, CFrame.Angles(math.rad(85), math.rad(45), 0), 0.08, 0.15, 0.3)
	end)
end

function CustomerService.Slap(player: Player, c)
	-- any guest can get one – but slapping a peaceful guest costs reputation
	if not c or not c.alive or c.slapped then
		return
	end
	if os.clock() < (slapCooldown[player] or 0) then
		return
	end
	if not Net.Near(player, c.root.Position, Config.Aggro.SlapDistance) then
		return
	end
	slapCooldown[player] = os.clock() + Config.Aggro.SlapCooldown
	c.slapped = true
	c.model:SetAttribute("Slapped", true)
	local innocent = not c.aggressive
	c.talking = true -- stops ordering / patience while reacting
	c.moveToken += 1
	c.humanoid:MoveTo(c.root.Position)
	local char = player.Character :: Model
	local from = char:GetPivot().Position
	-- which side the hand comes from (slap with the right hand → head turns to the slapper's left)
	local toCustomer = (c.root.Position - from) * Vector3.new(1, 0, 1)
	local dir = toCustomer.Magnitude > 0.01 and toCustomer.Unit or Vector3.new(0, 0, 1)
	Net.FireAll("Slap", player, c.model)
	swingArm(player)
	EconomyService.AddStat(player, "slaps", 1)
	log(string.format("#%d slapped by %s", c.id, player.Name))
	task.delay(0.2, function()
		if not c.alive then
			return
		end
		-- impact: head snaps, body twists and stumbles back a little
		local neck = motor(c.model, "Head", "Neck")
		local waist = motor(c.model, "UpperTorso", "Waist")
		local side = rng:NextNumber() < 0.5 and 1 or -1
		jointKick(neck, CFrame.Angles(math.rad(-10), math.rad(55 * side), math.rad(18 * side)), 0.06, 0.35, 0.5)
		jointKick(waist, CFrame.Angles(0, math.rad(22 * side), math.rad(6 * side)), 0.08, 0.3, 0.5)
		jointKick(motor(c.model, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(math.rad(60), 0, math.rad(25)), 0.1, 0.4, 0.4)
		jointKick(motor(c.model, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(60), 0, math.rad(-25)), 0.1, 0.4, 0.4)
		if not c.root.Anchored then
			c.root:ApplyImpulse((dir * 22 + Vector3.new(0, 6, 0)) * c.root.AssemblyMass)
		end
		local head = c.model:FindFirstChild("Head") :: BasePart?
		Net.Sound(nil, "ow", head and head.Position or c.root.Position)
		task.wait(0.7)
		if not c.alive then
			return
		end
		-- hand on the cheek, a last remark, then off they go
		jointKick(motor(c.model, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(math.rad(150), 0, math.rad(-30)), 0.2, 1.0, 0.4)
		jointKick(motor(c.model, "LeftLowerArm", "LeftElbow"), CFrame.Angles(math.rad(110), 0, 0), 0.2, 1.0, 0.4)
		if innocent then
			sayText(c, ({ "Spinnst du?! Ich wollte nur essen!", "Aua! Das melde ich!", "Was soll das denn?!" })[rng:NextInteger(1, 3)], "angry")
			RestaurantService.Rate(1, 1.5)
			Net.Notify(player, "n_slapped_innocent", { name = c.name }, "bad")
			if CustomerService.SlapHook then
				task.spawn(CustomerService.SlapHook, c)
			end
		else
			sayText(c, DialogueConfig.Line("slapped", c.personality, rng), "angry")
			Net.Notify(player, "n_slapped", { name = c.name }, "info")
		end
		task.wait(1.1)
		if c.alive then
			c.model:SetAttribute("Aggressive", false)
			if c.state ~= "Leaving" then
				leave(c, false)
			end
		end
	end)
end

-- Studio debug: make a customer aggressive right away
function CustomerService.DebugAggro(id: number?)
	for cid, c in pairs(customers) do
		if (id == nil or cid == id) and c.alive and WAITING_STATES[c.state] then
			setAggressive(c)
			return cid
		end
	end
	return nil
end

local function findSeat(c)
	local seats = {}
	for _, sp in ipairs(CollectionService:GetTagged("SeatPoint")) do
		if sp:IsDescendantOf(workspace) and not seatOwner[sp] then
			table.insert(seats, sp)
		end
	end
	if #seats == 0 then
		return nil
	end
	local sp = seats[rng:NextInteger(1, #seats)]
	seatOwner[sp] = c
	return sp
end

local function startEating(c)
	local seat = findSeat(c)
	if not seat then
		leave(c)
		return
	end
	c.seat = seat
	setState(c, "Eating")
	if c.pickup and pickupOwner[c.pickup] == c then
		pickupOwner[c.pickup] = nil
		c.pickup = nil
	end
	releaseSpots(c)
	c.seat = seat
	seatOwner[seat] = c
	task.spawn(function()
		local seatCF = (seat :: BasePart).CFrame
		-- approach waypoints stored on the seat by the world builder (fallback: stand behind the chair)
		local approach = {}
		for _, key in ipairs({ "A1", "A2", "A3" }) do
			local v = seat:GetAttribute(key)
			if typeof(v) == "Vector3" then
				table.insert(approach, v)
			end
		end
		if #approach == 0 then
			local behind = (seatCF * CFrame.new(0, 0, 1.6)).Position
			table.insert(approach, Vector3.new(behind.X, seatCF.Position.Y + 1.35, behind.Z))
		end
		c.approach = approach
		c.seatStand = approach[#approach]
		local entryName = seat:GetAttribute("Entry") or (seatCF.Position.X > 18 and "LoungeEntry" or "AisleEntry")
		c.seatEntry = entryName
		local points = { nav(entryName) }
		for _, v in ipairs(approach) do
			table.insert(points, v)
		end
		if not walk(c, points) or c.state ~= "Eating" then
			return
		end
		-- sit down
		c.sitting = true
		c.root.Anchored = true
		if c.tracks.walk then
			c.tracks.walk:Stop(0.1)
		end
		c.model:PivotTo(seatCF * CFrame.new(0, 1.15, 0))
		if c.tracks.sit then
			c.tracks.sit:Play(0.2)
		end
		-- food on the table
		local tableTarget = seatCF * CFrame.new(0, 1.15, -1.7)
		if c.mealForEating then
			c.eatModel = FoodPreparationService.BuildMealModel(c.mealForEating, tableTarget, 0.8)
		end
		local eatTime = rng:NextNumber(Config.Customers.EatTimeMin, Config.Customers.EatTimeMax)
		local t0 = os.clock()
		local spoke = false
		local nextBite = os.clock() + rng:NextNumber(1, 2.5)
		while c.alive and c.state == "Eating" and os.clock() - t0 < eatTime do
			task.wait(1)
			if os.clock() >= nextBite then
				nextBite = os.clock() + rng:NextNumber(2.5, 4.5)
				biteGesture(c)
			end
			if not spoke and os.clock() - t0 > eatTime * 0.4 then
				spoke = true
				say(c, "eating", "eating")
			end
		end
		if c.alive and c.state == "Eating" then
			-- reaction to the food before leaving
			local stars = c.lastStars or 3
			if stars >= 4 then
				setMood(c, "happy")
				jointKick(motor(c.model, "RightUpperArm", "RightShoulder"), CFrame.Angles(math.rad(70), 0, math.rad(-10)), 0.25, 1, 0.4) -- thumbs up
				jointKick(motor(c.model, "RightLowerArm", "RightElbow"), CFrame.Angles(math.rad(80), 0, 0), 0.25, 1, 0.4)
			elseif stars <= 2 then
				setMood(c, "annoyed")
				headShake(c)
			end
			task.wait(1)
			if rng:NextNumber() < 0.5 then
				say(c, "goodbye", "goodbye")
			end
			leave(c)
		end
	end)
end

---------------------------------------------------------------------------
-- Ordering & serving (player actions)
---------------------------------------------------------------------------
local function playerNear(player: Player, c): boolean
	return Net.Near(player, c.root.Position, Config.Customers.InteractDistance)
end

function CustomerService.TakeOrder(player: Player, c, viaLaptop: boolean?, staff: Model?)
	if not c or not c.alive or c.state ~= "Ordering" or not c.orderArrived or c.talking then
		return
	end
	-- at the laptop the distance to the laptop was already validated by the interaction handler
	if not viaLaptop and not playerNear(player, c) then
		return
	end
	c.talking = true
	c.taker = player
	if staff then
		face(c, staff:GetPivot().Position)
	elseif player.Character then
		face(c, (player.Character :: Model):GetPivot().Position)
	end
	-- generate the order from structured data
	local opts = {
		available = RestaurantService.Available(),
		picky = DialogueConfig.Personalities[c.personality].picky,
		count = c.groupSize,
		takeaway = c.takeaway,
		simple = c.tutorial,
		forceMenu = c.tutorial and "kebap" or (c.favorite and c.favorite.menu) or nil,
		forceMeat = c.tutorial and "chicken" or (c.favorite and c.favorite.meat) or nil,
	}
	-- a regular only orders their favourite while it is still on the menu
	if c.favorite and opts.forceMenu and not (opts.available and opts.available.menus and opts.available.menus[opts.forceMenu]) then
		opts.forceMenu, opts.forceMeat = nil, nil
	end
	local order = OrderLogic.GenerateOrder(rng, opts)
	if not c.tutorial then
		for _ = 1, 6 do
			local sig = OrderLogic.Signature(order)
			if not table.find(recentOrders, sig) then
				break
			end
			order = OrderLogic.GenerateOrder(rng, opts)
		end
		table.insert(recentOrders, OrderLogic.Signature(order))
		if #recentOrders > 6 then
			table.remove(recentOrders, 1)
		end
	end
	c.order = order
	local greet = DialogueConfig.Line("greet", c.personality, rng)
	if c.regularVisits then
		greet = string.format("Hallo, ich bin's wieder – %s! Wie immer, bitte.", c.name)
	elseif c.critic then
		greet = "Guten Tag. Ich schreibe für den Stadtanzeiger – mal sehen, was Sie können."
	end
	local speech = DialogueConfig.OrderSpeech(order, c.personality, rng)
	local lines = { greet }
	if c.vip then
		table.insert(lines, DialogueConfig.Line("vip", c.personality, rng))
	end
	if c.groupSize > 1 then
		table.insert(lines, DialogueConfig.Line("group", c.personality, rng))
	end
	table.insert(lines, speech)
	c.lastSpeech = speech
	c.takenByStaff = staff ~= nil
	if not staff then Net.Fire("Dialogue", player, {
		id = c.id,
		name = c.name,
		emoji = DialogueConfig.Personalities[c.personality].emoji,
		personality = c.personality,
		lines = lines,
		vip = c.vip,
	}) end
	-- greeting varies: wave, a nod, or pointing at the menu board
	local greet = rng:NextNumber()
	if greet < 0.35 then
		playOnce(c, "wave")
	elseif greet < 0.7 then
		jointKick(motor(c.model, "Head", "Neck"), CFrame.Angles(math.rad(-14), 0, 0), 0.15, 0.2, 0.25)
	else
		playOnce(c, "point")
	end
	task.spawn(function()
		for _, l in ipairs(lines) do
			sayText(c, l, "order")
			task.wait(1.4)
		end
		if not c.alive or c.state ~= "Ordering" then
			return
		end
		OrderService.CreateTicket(c, order, (not staff) and player or nil) -- staff orders are open to everyone
		Net.Sound(player, "register")
		setState(c, "WaitingForFood")
		c.patience = math.min(c.maxPatience, c.patience + c.maxPatience * 0.15)
		c.talking = false
		c.orderArrived = false
		task.wait(0.8)
		if not c.alive then
			return
		end
		say(c, "ack", "ack")
		if assignPickup(c) then
			orderingCustomer = nil
			relayout()
		end
		-- otherwise the customer waits at the register until a pickup spot frees up
	end)
end

function CustomerService.RepeatOrder(player: Player, id: any)
	local c = customers[id]
	if not c or not c.alive or not c.lastSpeech then
		return { ok = false }
	end
	c.patience = math.max(0, c.patience - c.maxPatience * 0.05)
	sayText(c, c.lastSpeech, "order")
	Net.Fire("Dialogue", player, {
		id = c.id,
		name = c.name,
		emoji = DialogueConfig.Personalities[c.personality].emoji,
		personality = c.personality,
		lines = { c.lastSpeech },
		vip = c.vip,
	})
	return { ok = true }
end

function CustomerService.Serve(player: Player, c)
	if not c or not c.alive or c.state ~= "WaitingForFood" then
		return
	end
	if not playerNear(player, c) then
		return
	end
	if c.serving then
		return
	end
	c.serving = true
	local tray = FoodPreparationService.Tray(player)
	local firstMeal
	for _, item in ipairs(tray) do
		if item.kind == "meal" then
			firstMeal = item.meal
			break
		end
	end
	local status = OrderService.Serve(player, c)
	if status == "refused" then
		say(c, "refuse", "refuse")
		playOnce(c, "point")
		c.patience = math.max(0, c.patience - c.maxPatience * 0.15)
		Net.Notify(player, "n_refused", { name = c.name }, "bad")
		Net.Sound(player, "fail")
	elseif status == "partial" then
		say(c, "partial", "partial")
		c.patience = math.min(c.maxPatience, c.patience + c.maxPatience * 0.1)
		c.mealForEating = c.mealForEating or firstMeal
	elseif status == "complete" then
		c.mealForEating = c.mealForEating or firstMeal
		setState(c, "ReceivingFood")
		local stars = OrderService.Complete(player, c)
		c.lastStars = stars
		setMood(c, stars >= 4 and "happy" or stars >= 3 and "neutral" or "annoyed")
		if stars >= 4 then
			say(c, "react_great", "happy")
			playOnce(c, "cheer")
		elseif stars >= 3 then
			say(c, "react_ok", "ok")
		else
			say(c, "react_bad", "bad")
		end
		task.spawn(function()
			task.wait(1.6)
			if not c.alive then
				return
			end
			if stars >= 4 and rng:NextNumber() < 0.5 then
				say(c, "tip", "tip")
				task.wait(1.2)
			end
			if not c.takeaway and c.alive then
				startEating(c)
			else
				if c.alive then
					say(c, "goodbye", "goodbye")
					leave(c)
				end
			end
		end)
	end
	c.serving = false
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------
local function pickPersonality(): string
	local total = 0
	for _, p in pairs(DialogueConfig.Personalities) do
		total += p.weight
	end
	local roll = rng:NextNumber() * total
	for name, p in pairs(DialogueConfig.Personalities) do
		roll -= p.weight
		if roll <= 0 then
			return name
		end
	end
	return "friendly"
end

function CustomerService.QueueCapacity(): number
	return RestaurantService.UpgradeValue("queue")
end

function CustomerService.ActiveCount(): number
	local n = 0
	for _ in pairs(customers) do
		n += 1
	end
	return n
end

function CustomerService.WaitingCount(): number
	local n = 0
	for _, c in pairs(customers) do
		if WAITING_STATES[c.state] or c.state == "ReceivingFood" then
			n += 1
		end
	end
	return n
end

function CustomerService.CanSpawn(): boolean
	return #queue < CustomerService.QueueCapacity()
		and CustomerService.WaitingCount() < Config.Customers.MaxWaiting
		and CustomerService.ActiveCount() < (CustomerService.MaxActiveHook and CustomerService.MaxActiveHook() or 10)
end

function CustomerService.Spawn(opts)
	opts = opts or {}
	if not CustomerService.CanSpawn() then
		return nil
	end
	local vip = opts.vip or false
	local rig = newRig()
	if not rig then
		return nil
	end
	nextId += 1
	local personality = opts.personality or pickPersonality()
	local pdef = DialogueConfig.Personalities[personality]
	-- every guest gets a look seed so a future regular looks the same on every visit
	local lookSeed = opts.lookSeed or rng:NextInteger(1, 2 ^ 30)
	local look = randomLook(vip or opts.critic == true, Random.new(lookSeed))
	dress(rig, look)
	local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	hum.WalkSpeed = Config.Customers.WalkSpeed * (personality == "impatient" and 1.2 or 1) * rng:NextNumber(0.9, 1.1)
	local name = opts.name or DialogueConfig.FirstNames[rng:NextInteger(1, #DialogueConfig.FirstNames)]
	local decorMul = RestaurantService.UpgradeValue("decor")
	local maxPatience = Config.Customers.BasePatience * pdef.patience * decorMul * (opts.groupSize and opts.groupSize > 1 and 1.3 or 1)
	local eat = rng:NextNumber() < Config.Customers.EatChance
	local c = {
		id = nextId,
		model = rig,
		humanoid = hum,
		root = root,
		name = name,
		personality = personality,
		vip = vip,
		groupSize = opts.groupSize or 1,
		tutorial = opts.tutorial or false,
		takeaway = opts.tutorial and true or not eat,
		state = "Entering",
		patience = maxPatience,
		maxPatience = maxPatience,
		remarks = 0,
		alive = true,
		moveToken = 0,
		lastFace = 0,
		lastWaitRemark = os.clock() + rng:NextNumber(10, 20),
		critic = opts.critic,
		favorite = opts.favorite,
		regularVisits = opts.regularVisits,
		lookSeed = lookSeed,
	}
	customers[c.id] = c
	rig.Name = "Customer_" .. c.id
	rig:SetAttribute("CustomerId", c.id)
	rig:SetAttribute("CustomerName", name)
	rig:SetAttribute("Personality", personality)
	rig:SetAttribute("Emoji", pdef.emoji)
	rig:SetAttribute("VIP", vip)
	rig:SetAttribute("Regular", opts.regularVisits ~= nil)
	rig:SetAttribute("Critic", opts.critic == true)
	rig:SetAttribute("Patience", 1)
	rig:SetAttribute("State", "Entering")
	local side = rng:NextNumber() < 0.5 and "SpawnL" or "SpawnR"
	rig:PivotTo(CFrame.new(nav(side)))
	rig.Parent = customerFolder
	CollectionService:AddTag(rig, "Customer")
	setupAnims(c)
	if personality == "aggressive" and not c.tutorial then
		task.delay(rng:NextNumber(2, 5), function()
			if c.alive and WAITING_STATES[c.state] then
				setAggressive(c)
			end
		end)
	end
	table.insert(queue, c)
	goToQueueSlot(c, #queue)
	if vip then
		Net.NotifyAll("n_vip", nil, "vip")
	end
	return c
end

local function spawnPedestrian()
	if pedestrians >= Config.Customers.MaxPedestrians then
		return
	end
	local rig = newRig()
	if not rig then
		return
	end
	pedestrians += 1
	dress(rig, randomLook(false))
	local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.WalkSpeed = rng:NextNumber(7, 11)
	local near = rng:NextNumber() < 0.5
	local a, b = near and "PedL2" or "PedL", near and "PedR2" or "PedR"
	if rng:NextNumber() < 0.5 then
		a, b = b, a
	end
	local p = {
		model = rig,
		humanoid = hum,
		root = rig:FindFirstChild("HumanoidRootPart"),
		alive = true,
		moveToken = 0,
		tracks = {},
		runConn = nil :: RBXScriptConnection?,
	}
	rig.Name = "Pedestrian"
	rig:PivotTo(CFrame.new(nav(a)))
	rig.Parent = pedFolder
	CollectionService:AddTag(rig, "Pedestrian")
	setupAnims(p)
	task.spawn(function()
		walk(p, { nav(b) })
		p.alive = false
		if p.runConn then
			p.runConn:Disconnect()
		end
		pedestrians -= 1
		releaseRig(rig)
	end)
end

---------------------------------------------------------------------------
-- Tick: patience, remarks, facing, waiting at register for pickup slots
---------------------------------------------------------------------------
local function tick(dt: number)
	for _, c in pairs(customers) do
		if c.alive and WAITING_STATES[c.state] then
			local drain = 0
			if c.state == "Entering" or c.state == "Queuing" then
				drain = Config.Customers.QueueDrain
			elseif c.state == "Ordering" then
				drain = c.talking and 0 or Config.Customers.OrderingDrain
			elseif c.state == "WaitingForFood" then
				drain = Config.Customers.WaitingDrain * (c.groupSize > 1 and 0.8 or 1)
			end
			if c.tutorial or RestaurantService.TutorialActive then
				drain = 0
			end
			c.patience = math.max(0, c.patience - drain * dt * (100 / Config.Customers.BasePatience))
			local frac = c.patience / c.maxPatience
			c.model:SetAttribute("Patience", math.floor(frac * 100) / 100)
			if c.remarks == 0 and frac < Config.Customers.ImpatientRemarkAt then
				c.remarks = 1
				say(c, "impatient", "impatient")
				playOnce(c, "point")
			elseif c.remarks == 1 and frac < 0.12 then
				c.remarks = 2
				say(c, "impatient", "impatient")
				Net.Sound(nil, "complain", c.root.Position)
			end
			if not c.aggressive and not c.tutorial and frac < Config.Aggro.TurnAt then
				setAggressive(c)
			end
			if c.aggressive and not c.slapped and c.patience > 0 and os.clock() >= (c.nextRant or 0) then
				rant(c)
			end
			if not c.aggressive and not c.talking and not c.sitting and os.clock() > (c.nextGesture or 0) and c.humanoid.MoveDirection.Magnitude < 0.1 then
				c.nextGesture = os.clock() + rng:NextNumber(5, 10)
				if c.nextGestureArmed then
					idleGesture(c)
				end
				c.nextGestureArmed = true
			end
			if c.patience <= 0 then
				cancel(c)
			elseif c.state == "WaitingForFood" and os.clock() > c.lastWaitRemark then
				c.lastWaitRemark = os.clock() + rng:NextNumber(25, 45)
				if frac > 0.5 and rng:NextNumber() < 0.5 then
					say(c, "waiting", "waiting")
				end
			end
			-- face the nearest worker while ordering or waiting
			if (c.state == "Ordering" and c.orderArrived) or (c.state == "WaitingForFood" and c.pickup and not c.root.Anchored) then
				if os.clock() - c.lastFace > 1 and c.humanoid.MoveDirection.Magnitude < 0.1 then
					c.lastFace = os.clock()
					local target = nearestPlayer(c.root.Position, 16)
					if target and target.Z < c.root.Position.Z - 2 then
						face(c, target)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function CustomerService.ClearAll()
	for _, c in pairs(customers) do
		despawn(c)
	end
	queue = {}
	orderingCustomer = nil
	pickupOwner = {}
	seatOwner = {}
end

function CustomerService.ForceLeaveAll()
	for _, c in pairs(customers) do
		if WAITING_STATES[c.state] then
			leave(c)
		end
	end
end

function CustomerService.Get(id: number)
	return customers[id]
end

function CustomerService.Debug()
	local out = {}
	for _, c in pairs(customers) do
		table.insert(out, string.format("#%d %s %s p=%.0f%% q=%s pick=%s tp=%d", c.id, c.name, c.state, c.patience / c.maxPatience * 100, tostring(c.queueIndex), tostring(c.pickup), c.teleports or 0))
	end
	return table.concat(out, "\n")
end

-- used by the employee AI (Server/EmployeeService)
CustomerService.NewRig = newRig
CustomerService.Dress = dress
CustomerService.AnimIds = animIds
function CustomerService.OrderingCustomer()
	local c = orderingCustomer
	if c and c.alive and c.state == "Ordering" and c.orderArrived and not c.talking then
		return c
	end
	return nil
end
function CustomerService.All()
	return customers
end
CustomerService.LeaveHook = nil :: ((any, boolean?, BasePart?) -> ())?
CustomerService.MaxActiveHook = nil :: (() -> number)?
CustomerService.SlapHook = nil :: ((any) -> ())?

function CustomerService.Init()
	setupCollisionGroups()
	customerFolder = workspace:FindFirstChild("Customers") or Instance.new("Folder")
	customerFolder.Name = "Customers"
	customerFolder.Parent = workspace
	pedFolder = workspace:FindFirstChild("Pedestrians") or Instance.new("Folder")
	pedFolder.Name = "Pedestrians"
	pedFolder.Parent = workspace
	poolFolder = ServerStorage:FindFirstChild("NPCPool") or Instance.new("Folder")
	poolFolder.Name = "NPCPool"
	poolFolder.Parent = ServerStorage

	Net.On("CustomerAction", function(player, model, action)
		if typeof(model) ~= "Instance" or not model:IsDescendantOf(customerFolder) then
			return
		end
		local id = model:GetAttribute("CustomerId")
		local c = id and customers[id]
		if not c or c.model ~= model then
			return
		end
		if action == "take" then
			CustomerService.TakeOrder(player, c)
		elseif action == "serve" then
			CustomerService.Serve(player, c)
		elseif action == "slap" then
			CustomerService.Slap(player, c)
		end
	end)
	Net.OnRequest("RepeatOrder", CustomerService.RepeatOrder)

	-- the register works as an alternative "take order" point
	FoodPreparationService.ExternalActions.register = function(player)
		if orderingCustomer then
			CustomerService.TakeOrder(player, orderingCustomer)
		end
	end
	-- the order laptop: "Bestellung aufnehmen" in the POS app
	FoodPreparationService.ExternalActions.laptop = function(player, _part, action)
		if action == "take_order" and orderingCustomer then
			CustomerService.TakeOrder(player, orderingCustomer, true)
		end
	end

	task.spawn(function()
		while true do
			local dt = task.wait(0.25)
			local ok, err = pcall(tick, dt)
			if not ok then
				warn("[CustomerService] tick error", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(5, 12))
			pcall(spawnPedestrian)
		end
	end)
	-- unused-variable guard for analyzers
	local _ = DataService
end

return CustomerService
