-- Renders delivery vans (tag "DeliveryVan") from the server's timeline: every frame each visual part
-- is placed at VanRoute.Pose(phase, elapsed) * its van-space "Local" CFrame. Wheels spin with the
-- speed, the rear doors swing open/closed from the DoorsOpen attribute, and the engine / reverse
-- beeper play locally from the van. Nothing here changes game state.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local VanRoute = require(Shared.VanRoute)
local Config = require(Shared.Config)

local DeliveryVan = {}

type Van = { model: Model, parts: { BasePart }, spin: number, door: number, engine: Sound?, beep: Sound?, anchor: BasePart? }
local vans: { [Model]: Van } = {}

local function sound(name: string, parent: Instance): Sound?
	local def = Config.Sounds[name]
	if not def then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = def.volume or 0.5
	s.Looped = true
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 90
	s.Parent = parent
	return s
end

local function add(m: Instance)
	if not m:IsA("Model") or vans[m] then
		return
	end
	local v: Van = { model = m, parts = {}, spin = 0, door = 0 }
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and typeof(p:GetAttribute("Local")) == "CFrame" then
			table.insert(v.parts, p)
			if not v.anchor and (p.Name == "Body" or p.Name == "Cargo") then
				v.anchor = p
			end
		end
	end
	if v.anchor then
		v.engine = sound("van_engine", v.anchor)
		v.beep = sound("van_beep", v.anchor)
		if v.engine then
			v.engine:Play()
		end
	end
	vans[m] = v
end

local function step(dt: number)
	local t = workspace:GetServerTimeNow()
	for m, v in pairs(vans) do
		if not m.Parent then
			vans[m] = nil
			continue
		end
		local phase = m:GetAttribute("Phase") or "arrive"
		local base, speed = VanRoute.Pose(phase, t - (m:GetAttribute("T0") or t))
		v.spin += speed * dt / 1.05 -- wheel radius ≈ 1.05 studs
		local target = m:GetAttribute("DoorsOpen") and 1 or 0
		v.door += (target - v.door) * math.min(1, dt * 3)
		for _, p in ipairs(v.parts) do
			local loc: CFrame = p:GetAttribute("Local")
			local role = p:GetAttribute("Role")
			if role == "wheel" then
				loc = loc * CFrame.Angles(-v.spin, 0, 0) -- rolling forward (-Z) turns the wheel about X
			elseif role == "door" then
				local hinge: CFrame = p:GetAttribute("Hinge")
				local swing: number = p:GetAttribute("Swing") or 0
				loc = hinge * CFrame.Angles(0, math.rad(swing * v.door), 0) * hinge:Inverse() * loc
			end
			p.CFrame = base * loc
		end
		-- engine: louder and higher while driving; reverse beeper only while backing in
		if v.engine then
			local s = math.abs(speed)
			v.engine.PlaybackSpeed = 0.85 + math.min(s, 26) / 26 * 0.5
			v.engine.Volume = ((Config.Sounds.van_engine or {}).volume or 0.5) * (phase == "parked" and 0.55 or 1)
		end
		if v.beep then
			local want = phase == "reverse" and math.abs(speed) > 0.2
			if want and not v.beep.IsPlaying then
				v.beep:Play()
			elseif not want and v.beep.IsPlaying then
				v.beep:Stop()
			end
		end
	end
end

function DeliveryVan.Init()
	CollectionService:GetInstanceAddedSignal("DeliveryVan"):Connect(function(m)
		task.defer(add, m)
	end)
	for _, m in ipairs(CollectionService:GetTagged("DeliveryVan")) do
		add(m)
	end
	RunService.RenderStepped:Connect(step)
end

return DeliveryVan
