-- Client entry: starts presentation modules and runs purely cosmetic animation (spits, fans).

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Modules = script.Parent:WaitForChild("ClientModules")
local State = require(Modules.State)
local Sound = require(Modules.Sound)
local UI = require(Modules.UI)
local Interaction = require(Modules.Interaction)
local Bubbles = require(Modules.Bubbles)
local Tutorial = require(Modules.Tutorial)
local FirstPerson = require(Modules.FirstPerson)
local PromptUI = require(Modules.PromptUI)
local Slap = require(Modules.Slap)
local MeatCutting = require(Modules.MeatCutting)

Sound.Init()

-- public servers start in the lobby; the game client starts once the server switches to "game"
local RS = game:GetService("ReplicatedStorage")
local t0 = os.clock()
while RS:GetAttribute("Mode") == nil and os.clock() - t0 < 15 do
	task.wait(0.1)
end
if RS:GetAttribute("Mode") == "lobby" then
	State.Init()
	local LobbyUI = require(Modules.LobbyUI)
	LobbyUI.Init()
	while RS:GetAttribute("Mode") ~= "game" do
		RS:GetAttributeChangedSignal("Mode"):Wait()
	end
	LobbyUI.Close()
	UI.Init()
	State.Request("Sync")
else
	UI.Init()
	State.Init()
end
Interaction.OpenPanel = UI.OpenPanel
require(Modules.AdminUI).Init()
require(Modules.LogisticsUI).Init()
require(Modules.HandUI).Init()
require(Modules.Doors).Init()
require(Modules.DeliveryVan).Init()
PromptUI.Init()
Interaction.Init()
Bubbles.Init()
Tutorial.Init()
FirstPerson.Init()
Slap.Init()
Interaction.OnSlap = Slap.Local
MeatCutting.Init()
Interaction.OnSpit = MeatCutting.Start
Interaction.IsCutting = MeatCutting.IsActive
MeatCutting.OnChanged = function(active)
	UI.SetCutting(active)
	Interaction.RefreshAll()
end
UI.OnPanelChanged = FirstPerson.SetMenuOpen

State.Remote("Sound").OnClientEvent:Connect(function(name, position)
	Sound.Play(name, position)
end)

-- new equipment installed: dust puff + sparkles where the crate was
State.Remote("Installed").OnClientEvent:Connect(function(_id, position)
	if typeof(position) ~= "Vector3" then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(2, 1, 2)
	p.CFrame = CFrame.new(position)
	p.Parent = workspace
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(210, 190, 160))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.6, 1.1)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Rate = 0
	dust.Parent = p
	local spark = Instance.new("ParticleEmitter")
	spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spark.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120))
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	spark.LightEmission = 1
	spark.Lifetime = NumberRange.new(0.8, 1.4)
	spark.Speed = NumberRange.new(3, 7)
	spark.SpreadAngle = Vector2.new(70, 70)
	spark.EmissionDirection = Enum.NormalId.Top
	spark.Acceleration = Vector3.new(0, -6, 0)
	spark.Rate = 0
	spark.Parent = p
	dust:Emit(18)
	task.delay(0.3, function()
		spark:Emit(30)
	end)
	game:GetService("Debris"):AddItem(p, 3)
end)

-- rotating döner spits & ceiling fans (local-only cosmetics, one shared loop)
type Spinner = { parts: { { part: BasePart, offset: CFrame } }, center: Vector3, speed: number, angle: number }
local spinners: { [Instance]: Spinner } = {}

local function addSpinner(model: Instance, speed: number)
	if spinners[model] then
		return
	end
	local center
	if model:IsA("Model") then
		local x, z = model:GetAttribute("SpinX"), model:GetAttribute("SpinZ")
		local pivot = model:GetPivot().Position
		center = Vector3.new(x or pivot.X, pivot.Y, z or pivot.Z)
	elseif model:IsA("BasePart") then
		center = model.Position
	else
		return
	end
	local parts = {}
	local base = CFrame.new(center)
	local list = model:IsA("BasePart") and { model, unpack(model:GetChildren()) } or model:GetChildren()
	for _, p in ipairs(list) do
		if p:IsA("BasePart") then
			table.insert(parts, { part = p, offset = base:ToObjectSpace(p.CFrame) })
		end
	end
	spinners[model] = { parts = parts, center = center, speed = speed, angle = 0 }
end

for _, m in ipairs(CollectionService:GetTagged("SpitRotor")) do
	addSpinner(m, 0.6)
end
for _, m in ipairs(CollectionService:GetTagged("Fan")) do
	addSpinner(m, 2.5)
end
CollectionService:GetInstanceAddedSignal("SpitRotor"):Connect(function(m)
	addSpinner(m, 0.6)
end)

-- throttled to ~30 updates/s and only near the camera: moving parts are not free to render
local accum = 0
RunService.RenderStepped:Connect(function(frameDt)
	accum += frameDt
	if accum < 1 / 30 then
		return
	end
	local dt = accum
	accum = 0
	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero
	for model, s in pairs(spinners) do
		if not model.Parent then
			spinners[model] = nil
			continue
		end
		if (s.center - camPos).Magnitude > 60 then
			continue
		end
		s.angle = (s.angle + dt * s.speed) % (math.pi * 2)
		local rot = CFrame.new(s.center) * CFrame.Angles(0, s.angle, 0)
		for _, e in ipairs(s.parts) do
			if e.part.Parent then
				-- keep server-driven size (spit shrinks as stock is used) while rotating
				e.part.CFrame = rot * e.offset
			end
		end
	end
end)
