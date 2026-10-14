-- Visible employees that really work: every hired role (Shared/Business.Roles) is an NPC that walks
-- (pathfinding, never teleports) to its station and does the job with the same server functions a
-- player uses. Skill, speed and reliability come from the contract in BusinessService.
--   cashier  – takes orders at the register (CustomerService.TakeOrder)
--   cutter   – manages the spit heat and pre-carves portions into a warming pan players grab from
--   preparer – chops fresh vegetables when the bins wilt (BusinessService.Refresh)
--   cleaner  – walks to every dirt spot and wipes it away (BusinessService.Clean)
--   manager  – reorders low stock at the supplier terminal and speeds the whole team up

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Business = require(Shared.Business)
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local Progression = require(Shared.Progression)
local Net = require(script.Parent.Net)
local RestaurantService = require(script.Parent.RestaurantService)
local FoodPreparationService = require(script.Parent.FoodPreparationService)
local CustomerService = require(script.Parent.CustomerService)
local MeatCuttingService = require(script.Parent.MeatCuttingService)
local BusinessService = require(script.Parent.BusinessService)
local ColdRoomService = require(script.Parent.ColdRoomService)

local EmployeeService = {}
local rng = Random.new()

type Worker = {
	role: string,
	model: Model,
	hum: Humanoid,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	status: string,
	statusLabel: TextLabel,
	alive: boolean,
	working: string?,
	motors: { [string]: Motor6D },
	base: { [string]: CFrame },
}

local workers: { [string]: Worker } = {}
local folder: Folder
local LOCKER = Vector3.new(21, 3.3, -14)
local ROLE_COLORS = {
	cashier = Color3.fromRGB(200, 40, 40),
	cleaner = Color3.fromRGB(60, 110, 190),
	cutter = Color3.fromRGB(245, 245, 240),
	preparer = Color3.fromRGB(245, 245, 240),
	manager = Color3.fromRGB(30, 30, 34),
}

---------------------------------------------------------------------------
-- warming pans (filled by the carver, emptied by players)
---------------------------------------------------------------------------
local PAN_POS = { chicken = Vector3.new(-21.4, 3.72, -17.5), veal = Vector3.new(-15.9, 3.72, -17.5) }
local PAN_CAP = 3
local pans: { [string]: { part: BasePart, items: { { q: number, t: number } } } } = {}

local function contract(role: string)
	return BusinessService.Staff()[role]
end

local function updatePan(meat: string)
	local pan = pans[meat]
	if not pan then
		return
	end
	local hired = contract("cutter") ~= nil
	local n = #pan.items
	for _, c in ipairs(pan.part:GetChildren()) do
		if c:IsA("BasePart") then
			c:Destroy()
		end
	end
	pan.part.Transparency = hired and 0 or 1
	pan.part:SetAttribute("PromptOn", hired and n > 0)
	pan.part:SetAttribute("PromptObj", string.format("%s %d/%d", IngredientData.Meat[meat].icon, n, PAN_CAP))
	for i = 1, n do
		local p = Instance.new("Part")
		p.Name = "Portion"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Size = Vector3.new(0.9, 0.18, 0.5)
		p.CFrame = pan.part.CFrame * CFrame.new(0, 0.12 + (i - 1) * 0.1, (i - 2) * 0.35) * CFrame.Angles(0, (i - 2) * 0.4, 0)
		p.Color = IngredientData.Meat[meat].cooked
		p.Material = Enum.Material.Sand
		p.Parent = pan.part
	end
end

local function buildPans()
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return
	end
	local f = r:FindFirstChild("WarmPans") or Instance.new("Folder")
	f.Name = "WarmPans"
	f.Parent = r
	for meat, pos in pairs(PAN_POS) do
		if not pans[meat] then
			local p = Instance.new("Part")
			p.Name = "WarmPan_" .. meat
			p.Anchored = true
			p.Size = Vector3.new(1.3, 0.25, 1.5)
			p.CFrame = CFrame.new(pos)
			p.Color = Color3.fromRGB(190, 194, 198)
			p.Material = Enum.Material.Metal
			p.Reflectance = 0.15
			p:SetAttribute("Station", "precut")
			p:SetAttribute("Item", meat)
			p:SetAttribute("PromptDe", "Vorgeschnittenes Fleisch nehmen")
			p:SetAttribute("PromptEn", "Take pre-carved meat")
			p.Parent = f
			CollectionService:AddTag(p, "Station")
			pans[meat] = { part = p, items = {} }
			updatePan(meat)
		end
	end
end

local function takePortion(player: Player, part: BasePart)
	local meat = part:GetAttribute("Item")
	local pan = meat and pans[meat]
	if not pan or #pan.items == 0 then
		return
	end
	-- into the meat pan in the cook's hands, like carving yourself (issue #3)
	if not FoodPreparationService.CutBowl(player, true) then
		return
	end
	local it = table.remove(pan.items, 1)
	-- meat waiting in the pan slowly dries out
	local age = os.clock() - it.t
	local q = it.q * math.clamp(1 - math.max(0, age - 60) / 300, 0.6, 1)
	FoodPreparationService.AddToBowl(player, meat, q)
	Net.Sound(player, "add")
	updatePan(meat)
end

---------------------------------------------------------------------------
-- NPC body, movement and work poses
---------------------------------------------------------------------------
local function setupGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Staff")
	end)
	for _, g in ipairs({ "Staff", "Players", "Customers", "NPCBlocker" }) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable("Staff", g, false)
		end)
	end
	-- the customer blockers in the kitchen opening are no wall for staff
	local r = workspace:FindFirstChild("Restaurant")
	if r then
		for _, p in ipairs(r:GetDescendants()) do
			if p:IsA("BasePart") and p:GetAttribute("NPCBlocker") and not p:FindFirstChildOfClass("PathfindingModifier") then
				local m = Instance.new("PathfindingModifier")
				m.Label = "NPCBlocker"
				m.PassThrough = true
				m.Parent = p
			end
		end
	end
end

local function setStatus(w: Worker, text: string)
	if w.status ~= text then
		w.status = text
		w.statusLabel.Text = text
		RestaurantService.PushShop()
	end
end

local function makeWorker(role: string, e): Worker?
	local rig = CustomerService.NewRig()
	if not rig then
		return nil
	end
	local r = Random.new(e.seed or 1)
	local skins = { Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 192, 152), Color3.fromRGB(198, 140, 100), Color3.fromRGB(141, 95, 62) }
	local hairs = { Color3.fromRGB(30, 25, 20), Color3.fromRGB(90, 60, 30), Color3.fromRGB(200, 160, 90) }
	CustomerService.Dress(rig, {
		skin = skins[r:NextInteger(1, #skins)],
		shirt = ROLE_COLORS[role],
		pants = Color3.fromRGB(35, 35, 40),
		shoes = Color3.fromRGB(25, 25, 25),
		hair = hairs[r:NextInteger(1, #hairs)],
		longHair = r:NextNumber() < 0.4,
		hat = role == "cutter" or role == "preparer" or role == "cashier",
		hatColor = role == "cashier" and Color3.fromRGB(200, 40, 40) or Color3.fromRGB(250, 250, 250),
		glasses = role == "manager",
		vip = false,
	})
	rig.Name = "Staff_" .. role
	local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	hum.WalkSpeed = 12 * e.speed
	for _, p in ipairs(rig:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Staff"
		end
	end
	-- apron for the kitchen crew, clipboard for the manager
	local torso = rig:FindFirstChild("UpperTorso") :: BasePart?
	local lower = rig:FindFirstChild("LowerTorso") :: BasePart?
	local function attach(name: string, size: Vector3, to: BasePart?, offset: CFrame, color: Color3)
		if not to then
			return
		end
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.CollisionGroup = "Staff"
		p.CFrame = to.CFrame * offset
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = to
		wc.Part1 = p
		wc.Parent = p
		p:SetAttribute("Accessory", true)
		p.Parent = rig
	end
	if role ~= "manager" then
		local apron = role == "cleaner" and Color3.fromRGB(40, 70, 130) or Color3.fromRGB(150, 30, 30)
		attach("Apron", Vector3.new(1.7, 1.4, 0.1), torso, CFrame.new(0, -0.1, -0.52), apron)
		attach("ApronLow", Vector3.new(1.75, 1.3, 0.1), lower, CFrame.new(0, -0.6, -0.55), apron)
	end
	-- name tag + live status
	local head = rig:FindFirstChild("Head") :: BasePart
	local bb = Instance.new("BillboardGui")
	bb.Name = "StaffTag"
	bb.Size = UDim2.fromOffset(220, 50)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 45
	bb.AlwaysOnTop = false
	local def = Business.Roles[role]
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.4
	title.Text = string.format("%s %s · %s", def.icon, e.name, string.rep("★", e.skill))
	title.Parent = bb
	local status = Instance.new("TextLabel")
	status.Position = UDim2.fromScale(0, 0.55)
	status.Size = UDim2.new(1, 0, 0.45, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextScaled = true
	status.TextColor3 = Color3.fromRGB(255, 220, 140)
	status.TextStrokeTransparency = 0.5
	status.Text = ""
	status.Parent = bb
	bb.Parent = head
	-- animations (same ids the customers use)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local tracks = {}
	for name, id in pairs(CustomerService.AnimIds) do
		if name == "walk" or name == "idle" or name == "wave" or name == "point" then
			local a = Instance.new("Animation")
			a.AnimationId = id
			local ok, t = pcall(function()
				return animator:LoadAnimation(a)
			end)
			if ok and t then
				t.Looped = name == "walk" or name == "idle"
				t.Priority = name == "walk" and Enum.AnimationPriority.Movement or (name == "idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Action)
				tracks[name] = t
			end
		end
	end
	if tracks.idle then
		tracks.idle:Play()
	end
	hum.Running:Connect(function(speed)
		local walk = tracks.walk
		if not walk then
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
	local motors, base = {}, {}
	for _, m in ipairs(rig:GetDescendants()) do
		if m:IsA("Motor6D") then
			motors[m.Name] = m
			base[m.Name] = m:GetAttribute("BaseC0") or m.C0
			m:SetAttribute("BaseC0", base[m.Name])
		end
	end
	rig:SetAttribute("Staff", role)
	rig:PivotTo(CFrame.new(LOCKER + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))))
	rig.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return {
		role = role,
		model = rig,
		hum = hum,
		root = root,
		tracks = tracks,
		status = "",
		statusLabel = status,
		alive = true,
		working = nil,
		motors = motors,
		base = base,
	}
end

local agent = { AgentRadius = 1.1, AgentHeight = 5, AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 4 }

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function stepTo(w: Worker, pos: Vector3, reach: number): boolean
	local t0 = os.clock()
	local last = w.root.Position
	local stuck = 0
	w.hum:MoveTo(pos)
	while w.alive and flat(w.root.Position, pos) > reach do
		local dt = task.wait(0.1)
		if os.clock() - t0 > 6 then
			return false
		end
		if (w.root.Position - last).Magnitude < 0.03 then
			stuck += dt
			if stuck > 0.8 then
				return false
			end
		else
			stuck = 0
		end
		last = w.root.Position
		w.hum:MoveTo(pos)
	end
	return w.alive
end

-- walk there: pathfinding first, then straight steps; tries a few times but never teleports
local function walkTo(w: Worker, pos: Vector3, reach: number?): boolean
	reach = reach or 1.3
	for attempt = 1, 3 do
		if not w.alive then
			return false
		end
		if flat(w.root.Position, pos) <= (reach :: number) then
			return true
		end
		local path = PathfindingService:CreatePath(agent)
		local ok = pcall(function()
			path:ComputeAsync(w.root.Position, pos)
		end)
		local points = {}
		if ok and path.Status == Enum.PathStatus.Success then
			for _, wp in ipairs(path:GetWaypoints()) do
				table.insert(points, wp.Position)
			end
		else
			table.insert(points, pos)
		end
		local good = true
		for i, p in ipairs(points) do
			if not stepTo(w, p, i == #points and (reach :: number) or 1.6) then
				good = false
				break
			end
		end
		if good then
			return true
		end
		-- side-step and try again
		w.hum:MoveTo(w.root.Position + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)))
		task.wait(0.6 * attempt)
	end
	return false
end

-- Kitchen/storage and the guest area are only connected through the staff gap next to the counter
-- (x 9.3..12); the invisible customer blockers there stop the navmesh, so staff cross it on foot.
local GATE_KITCHEN = Vector3.new(10.6, 3.3, -10.2)
local GATE_DINING = Vector3.new(10.6, 3.3, -4.6)
local function inKitchen(p: Vector3): boolean
	return p.Z < -7.8
end

local function goTo(w: Worker, pos: Vector3, reach: number?): boolean
	local here = w.root.Position
	if inKitchen(here) ~= inKitchen(pos) then
		local from = inKitchen(here) and GATE_KITCHEN or GATE_DINING
		local to = inKitchen(here) and GATE_DINING or GATE_KITCHEN
		if not walkTo(w, from, 1.2) or not stepTo(w, to, 1.2) then
			return false
		end
	end
	return walkTo(w, pos, reach)
end

local function face(w: Worker, target: Vector3)
	local p = w.root.Position
	if flat(p, target) > 0.1 then
		w.root.CFrame = CFrame.lookAt(p, Vector3.new(target.X, p.Y, target.Z))
	end
end

-- procedural work motion on the arms (the rigs use Motor6D joints)
local POSES = {
	type = function(t)
		return { RightShoulder = CFrame.Angles(math.rad(70 + math.sin(t * 14) * 6), 0, 0), LeftShoulder = CFrame.Angles(math.rad(70 + math.cos(t * 13) * 6), 0, 0) }
	end,
	carve = function(t)
		local s = (math.sin(t * 6) + 1) / 2
		return { RightShoulder = CFrame.Angles(math.rad(60 + s * 70), 0, 0), RightElbow = CFrame.Angles(math.rad(10 + s * 30), 0, 0), LeftShoulder = CFrame.Angles(math.rad(40), 0, math.rad(-10)) }
	end,
	chop = function(t)
		local s = math.abs(math.sin(t * 9))
		return { RightShoulder = CFrame.Angles(math.rad(45 + s * 35), 0, 0), LeftShoulder = CFrame.Angles(math.rad(50), 0, math.rad(15)), Waist = CFrame.Angles(math.rad(-12), 0, 0) }
	end,
	wipe = function(t)
		return { RightShoulder = CFrame.Angles(math.rad(55), math.sin(t * 7) * 0.6, 0), Waist = CFrame.Angles(math.rad(-35), 0, 0), Neck = CFrame.Angles(math.rad(-15), 0, 0) }
	end,
	clipboard = function(t)
		return { LeftShoulder = CFrame.Angles(math.rad(70), 0, 0), RightShoulder = CFrame.Angles(math.rad(55 + math.sin(t * 5) * 8), 0, 0), Neck = CFrame.Angles(math.rad(-18), 0, 0) }
	end,
}

local function work(w: Worker, pose: string, seconds: number)
	w.working = pose
	local t0 = os.clock()
	local fn = POSES[pose]
	while w.alive and os.clock() - t0 < seconds do
		local t = os.clock() - t0
		local offs = fn(t)
		for name, m in pairs(w.motors) do
			local o = offs[name]
			m.C0 = o and (w.base[name] * o) or w.base[name]
		end
		task.wait(0.05)
	end
	for name, m in pairs(w.motors) do
		m.C0 = w.base[name]
	end
	w.working = nil
end

local function boost(): number
	local m = workers.manager
	return (m and m.alive and not string.find(m.status, "☕")) and 1.15 or 1
end

-- seconds a task takes for this worker
local function taskTime(w: Worker, base: number): number
	local e = contract(w.role)
	if not e then
		return base
	end
	return base / (e.speed * (0.7 + 0.1 * e.skill) * boost())
end

local function onShift(): boolean
	return RestaurantService.Open and RestaurantService.GetOwner() ~= nil
end

local function maybeBreak(w: Worker): boolean
	local e = contract(w.role)
	if not e or rng:NextNumber() > (1 - e.rel) * 0.12 then
		return false
	end
	setStatus(w, "☕ Kurze Pause")
	goTo(w, LOCKER, 2)
	task.wait(14)
	return true
end

---------------------------------------------------------------------------
-- jobs
---------------------------------------------------------------------------
local function spitReady(meat: string): boolean
	local r = workspace:FindFirstChild("Restaurant")
	for _, m in ipairs(CollectionService:GetTagged("Spit")) do
		if m:GetAttribute("Meat") == meat and r and m:IsDescendantOf(r) then
			return true
		end
	end
	return false
end

local JOBS = {}

function JOBS.cashier(w: Worker)
	local stand = Vector3.new(3.6, 3.3, -9.3)
	if not goTo(w, stand, 1) then
		return
	end
	face(w, Vector3.new(5, 3.3, 0))
	local c = CustomerService.OrderingCustomer()
	local owner = RestaurantService.GetOwner()
	if c and owner then
		setStatus(w, "🧾 Nimmt Bestellung auf")
		work(w, "type", taskTime(w, 2.2))
		if CustomerService.OrderingCustomer() == c then
			CustomerService.TakeOrder(owner, c, true, w.model)
			if w.tracks.wave then
				w.tracks.wave:Play(0.1)
			end
			task.wait(3)
		end
	else
		setStatus(w, "Wartet auf Kunden")
		task.wait(0.6)
	end
end

-- fetch a rested cone from the cold room and mount it on the spit
local function fetchCone(w: Worker, meat: string)
	setStatus(w, "❄️ Holt Fleisch aus dem Kühlraum")
	if not goTo(w, ColdRoomService.Entrance, 1.2) then
		return
	end
	ColdRoomService.SetDoor(true)
	task.wait(0.7)
	if not stepTo(w, ColdRoomService.Inside, 1.2) then
		return
	end
	work(w, "type", 1)
	local pack = ColdRoomService.StaffTake(meat)
	if not pack then
		stepTo(w, ColdRoomService.Entrance, 1.2)
		return
	end
	local carry = ColdRoomService.AttachCarry(w.model, meat)
	stepTo(w, ColdRoomService.Entrance, 1.2)
	ColdRoomService.SetDoor(false)
	setStatus(w, "🥙 Steckt einen neuen Spieß auf")
	local x = meat == "chicken" and -24.9 or -18.4
	local ok = goTo(w, Vector3.new(x - 0.55, 3.9, -14.9), 1.2)
	if ok then
		face(w, Vector3.new(x, 3.9, -17.9))
		work(w, "carve", 1.5)
	end
	if carry then
		carry:Destroy()
	end
	if ok then
		ColdRoomService.StaffLoad(meat, pack)
	else
		ColdRoomService.StaffAbort(meat, pack)
	end
end

function JOBS.cutter(w: Worker)
	-- a spit running low gets a fresh cone from the cold room first
	for meat in pairs(PAN_POS) do
		local stockId = IngredientData.Meat[meat].stock
		if RestaurantService.GetStock(stockId) <= RestaurantService.Capacity(stockId) * 0.35 and ColdRoomService.CanLoad(meat) then
			fetchCone(w, meat)
			return
		end
	end
	local best, bestNeed = nil, -1
	for meat in pairs(PAN_POS) do
		local st = FoodPreparationService.Spits[meat]
		local stockOk = RestaurantService.HasStock(IngredientData.Meat[meat].stock, 1)
		if st and spitReady(meat) and stockOk and Progression.StockUnlocked(RestaurantService.GetUnlocks(), IngredientData.Meat[meat].stock) then
			local need = PAN_CAP - #pans[meat].items + (st.heat == "high" and st.doneness > 1.4 and 2 or 0) + (st.heat == "low" and st.doneness < 0.9 and 2 or 0)
			if need > bestNeed then
				best, bestNeed = meat, need
			end
		end
	end
	if not best then
		setStatus(w, "Kein Fleisch auf Lager")
		task.wait(2)
		return
	end
	local meat = best :: string
	local spitX = meat == "chicken" and -24.9 or -18.4
	if not goTo(w, Vector3.new(spitX - 0.55, 3.9, -14.9), 1) then
		return
	end
	face(w, Vector3.new(spitX, 3.9, -17.9))
	local st = FoodPreparationService.Spits[meat]
	-- heat management: keep the meat in the perfect window
	local wanted = st.doneness < 0.9 and "high" or (st.doneness > 1.4 and "low" or st.heat)
	if wanted ~= st.heat then
		setStatus(w, "🔥 Regelt die Hitze")
		work(w, "type", 0.8)
		st.heat = wanted
		FoodPreparationService.UpdateSpitVisual(meat)
		FoodPreparationService.PushSpits()
		return
	end
	if MeatCuttingService.SpitBusy(meat) then
		setStatus(w, "Wartet – Spieß ist belegt")
		task.wait(1.5)
		return
	end
	if #pans[meat].items >= PAN_CAP then
		setStatus(w, "✓ Wanne ist voll")
		task.wait(1.5)
		return
	end
	if st.doneness < Config.Prep.MinCutDoneness then
		setStatus(w, "Wartet, bis das Fleisch gar ist")
		task.wait(1.5)
		return
	end
	setStatus(w, "🔪 Schneidet " .. IngredientData.Meat[meat].name.de)
	local dur = taskTime(w, 4)
	task.spawn(function()
		for _ = 1, math.floor(dur / 0.6) do
			Net.Sound(nil, "cut_slice", Vector3.new(spitX, 5, -16.6))
			task.wait(0.6)
		end
	end)
	work(w, "carve", dur)
	if not RestaurantService.UseStock(IngredientData.Meat[meat].stock, 1) then
		return
	end
	local e = contract("cutter")
	local q = math.clamp((0.68 + 0.06 * (e and e.skill or 1)) * FoodPreparationService.CutQuality(st.doneness), 0, 1)
	st.doneness = math.max(0, st.doneness - Config.Prep.CutCost)
	FoodPreparationService.UpdateSpitVisual(meat)
	FoodPreparationService.PushSpits()
	table.insert(pans[meat].items, { q = q, t = os.clock() })
	updatePan(meat)
end

function JOBS.preparer(w: Worker)
	local worst, worstF = nil, 0.75
	for id, f in pairs(BusinessService.Fresh()) do
		if f < worstF then
			worst, worstF = id, f
		end
	end
	if not worst then
		setStatus(w, "✓ Alles frisch")
		goTo(w, Vector3.new(-21, 3.3, -9.6), 2)
		face(w, Vector3.new(-21, 3.3, -6))
		task.wait(2)
		return
	end
	local bin
	for _, s in ipairs(CollectionService:GetTagged("Station")) do
		if s:GetAttribute("Station") == "veg" and s:GetAttribute("Item") == worst then
			bin = s
		end
	end
	if not bin then
		task.wait(2)
		return
	end
	local x = (bin :: BasePart).Position.X
	if not goTo(w, Vector3.new(x, 3.3, -9.0), 1) then
		return
	end
	face(w, Vector3.new(x, 3.3, -6))
	setStatus(w, "🥬 Schneidet " .. IngredientData.Veg[worst].name.de .. " frisch")
	task.spawn(function()
		for _ = 1, 4 do
			Net.Sound(nil, "cut", Vector3.new(x, 4, -6.5))
			task.wait(0.7)
		end
	end)
	work(w, "chop", taskTime(w, 3.2))
	BusinessService.Refresh(worst)
end

function JOBS.cleaner(w: Worker)
	local list = BusinessService.Dirt()
	local best, bestD = nil, math.huge
	for _, p in ipairs(list) do
		local d = flat(p.Position, w.root.Position)
		if d < bestD then
			best, bestD = p, d
		end
	end
	if not best then
		setStatus(w, "✓ Alles sauber")
		goTo(w, Vector3.new(8, 3.3, -11), 2)
		task.wait(2)
		return
	end
	local target = best :: BasePart
	setStatus(w, "🧽 Geht putzen")
	if not goTo(w, target.Position, 2.2) then
		return
	end
	if not target.Parent then
		return
	end
	face(w, target.Position)
	setStatus(w, "🧽 Putzt")
	work(w, "wipe", taskTime(w, 2.4))
	BusinessService.Clean(target)
end

function JOBS.manager(w: Worker)
	local owner = RestaurantService.GetOwner()
	if not owner then
		task.wait(2)
		return
	end
	goTo(w, Vector3.new(16, 3.3, -12.4), 1.2)
	face(w, Vector3.new(16, 3.3, -10.5))
	setStatus(w, "📋 Prüft das Lager")
	work(w, "clipboard", 3)
	local shop = RestaurantService.BuildShopState()
	for id, def in pairs(IngredientData.Stock) do
		if Progression.StockUnlocked(RestaurantService.GetUnlocks(), id) then
			local have = (shop.stock[id] or 0) + (shop.transit[id] or 0)
			if have < (shop.caps[id] or 0) * 0.3 then
				local res = RestaurantService.Restock(owner, id)
				if res and res.ok then
					setStatus(w, "📦 Bestellt " .. def.name.de .. " nach")
					task.wait(2)
				end
			end
		end
	end
	-- walk the floor and keep the team going
	setStatus(w, "👀 Behält das Team im Blick")
	goTo(w, Vector3.new(-6, 3.3, -10.5), 2)
	face(w, Vector3.new(-6, 3.3, -6))
	work(w, "clipboard", 4)
end

---------------------------------------------------------------------------
-- life cycle
---------------------------------------------------------------------------
local function run(w: Worker)
	while w.alive do
		local e = contract(w.role)
		if not e then
			break
		end
		if not onShift() then
			setStatus(w, RestaurantService.Phase == "open" and "Wartet auf Schichtbeginn" or "🏠 Feierabend")
			goTo(w, LOCKER, 2.5)
			task.wait(2)
		elseif e.training and os.clock() - e.training < 6 then
			setStatus(w, "📚 Training – jetzt " .. string.rep("★", e.skill))
			if w.tracks.wave then
				w.tracks.wave:Play(0.1)
			end
			task.wait(3)
		elseif not maybeBreak(w) then
			local ok, err = pcall(JOBS[w.role], w)
			if not ok then
				warn("[EmployeeService]", w.role, err)
				task.wait(2)
			end
		end
	end
end

local function despawn(w: Worker)
	w.alive = false -- stops the current job
	task.spawn(function()
		task.wait(0.3)
		w.alive = true -- walk out first (the job loop already ended: no contract)
		setStatus(w, "👋 Geht nach Hause")
		goTo(w, LOCKER, 2.5)
		w.alive = false
		w.model:Destroy()
	end)
end

local function refresh()
	local staff = BusinessService.Staff()
	for role, w in pairs(workers) do
		local e = staff[role]
		if not e then
			workers[role] = nil
			despawn(w)
		else
			local def = Business.Roles[role]
			local head = w.model:FindFirstChild("Head")
			local tag = head and head:FindFirstChild("StaffTag")
			local title = tag and tag:FindFirstChildOfClass("TextLabel")
			if title then
				title.Text = string.format("%s %s · %s", def.icon, e.name, string.rep("★", e.skill))
			end
			w.hum.WalkSpeed = 12 * e.speed
		end
	end
	for role, e in pairs(staff) do
		if not workers[role] then
			local w = makeWorker(role, e)
			if w then
				workers[role] = w
				task.spawn(run, w)
			end
		end
	end
	for meat in pairs(pans) do
		updatePan(meat)
	end
end

function EmployeeService.Init()
	folder = workspace:FindFirstChild("Staff") :: Folder or Instance.new("Folder")
	folder.Name = "Staff"
	folder.Parent = workspace
	setupGroups()
	buildPans()
	FoodPreparationService.ExternalActions.precut = takePortion
	BusinessService.StatusProvider = function()
		local s = {}
		for role, w in pairs(workers) do
			s[role] = w.status
		end
		return s
	end
	BusinessService.StaffChanged:Connect(refresh)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
	refresh()
end

return EmployeeService
