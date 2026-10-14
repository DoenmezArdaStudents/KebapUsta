-- Slap ("Backpfeife") presentation: first-person hand swing with camera punch for the slapper,
-- and for everyone an impact burst, a red hand print on the cheek and dizzy stars above the head.
-- The server validates the slap and animates the customer's reaction.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local State = require(script.Parent.State)
local Sound = require(script.Parent.Sound)

local Slap = {}

local player = Players.LocalPlayer
local SKIN = Color3.fromRGB(222, 176, 138)
local SLEEVE = Color3.fromRGB(245, 245, 245)

local lastLocal = 0
local shake = 0 -- current camera punch strength
local shakeSide = 1

---------------------------------------------------------------------------
-- first-person hand
---------------------------------------------------------------------------
local function handPart(parent: Instance, name: string, size: Vector3, color: Color3, cf: CFrame, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p:SetAttribute("Offset", cf)
	p.Parent = parent
	return p
end

-- hand model in its own space: fingers point along -Z, palm faces -X, sleeve runs back along +Z
local function buildHand(): Model
	local m = Instance.new("Model")
	m.Name = "SlapHand"
	handPart(m, "Palm", Vector3.new(0.14, 0.5, 0.55), SKIN, CFrame.new())
	for i = 0, 3 do
		local y = 0.18 - i * 0.12
		local len = ({ 0.36, 0.42, 0.4, 0.32 })[i + 1]
		handPart(m, "Finger" .. i, Vector3.new(0.11, 0.1, len), SKIN, CFrame.new(0, y, -0.275 - len / 2 + 0.02))
	end
	handPart(m, "Thumb", Vector3.new(0.11, 0.1, 0.3), SKIN, CFrame.new(-0.05, 0.3, -0.05) * CFrame.Angles(math.rad(-50), 0, 0))
	handPart(m, "Wrist", Vector3.new(0.3, 0.42, 0.3), SKIN, CFrame.new(0.02, -0.02, 0.38))
	handPart(m, "Sleeve", Vector3.new(1.6, 0.52, 0.52), SLEEVE, CFrame.new(0.02, -0.02, 1.25) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
	return m
end

-- keyframes in camera space (x right, y up, -z forward) and time
local KEYS = {
	{ t = 0.0, cf = CFrame.new(1.5, -1.5, -1.6) * CFrame.Angles(0, math.rad(10), math.rad(-10)) },
	{ t = 0.13, cf = CFrame.new(1.25, -0.25, -1.55) * CFrame.Angles(math.rad(10), math.rad(45), math.rad(-15)) }, -- wind-up
	{ t = 0.21, cf = CFrame.new(-0.05, -0.2, -2.05) * CFrame.Angles(0, math.rad(-15), math.rad(-5)) }, -- impact
	{ t = 0.33, cf = CFrame.new(-0.95, -0.5, -1.75) * CFrame.Angles(0, math.rad(-45), math.rad(-10)) }, -- follow-through
	{ t = 0.62, cf = CFrame.new(-1.5, -1.7, -1.4) * CFrame.Angles(0, math.rad(-50), math.rad(-20)) },
}

local function sample(t: number): CFrame
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if t <= b.t then
			local f = (t - a.t) / (b.t - a.t)
			f = f * f * (3 - 2 * f) -- smoothstep
			return a.cf:Lerp(b.cf, f)
		end
	end
	return KEYS[#KEYS].cf
end

local activeHand: Model? = nil

local function playHand()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if activeHand then
		RunService:UnbindFromRenderStep("KebapSlapHand")
		activeHand:Destroy()
	end
	local hand = buildHand()
	activeHand = hand
	hand.Parent = cam
	local parts = {}
	for _, p in ipairs(hand:GetChildren()) do
		if p:IsA("BasePart") then
			table.insert(parts, { part = p, offset = p:GetAttribute("Offset") :: CFrame })
		end
	end
	local start = os.clock()
	local hit = false
	RunService:BindToRenderStep("KebapSlapHand", Enum.RenderPriority.Camera.Value + 5, function()
		local t = os.clock() - start
		local camNow = workspace.CurrentCamera
		if t > KEYS[#KEYS].t or not camNow then
			RunService:UnbindFromRenderStep("KebapSlapHand")
			hand:Destroy()
			if activeHand == hand then
				activeHand = nil
			end
			return
		end
		local base = camNow.CFrame * sample(t)
		for _, e in ipairs(parts) do
			e.part.CFrame = base * e.offset
		end
		if not hit and t >= KEYS[3].t then
			hit = true
			shake = 1
			shakeSide = -1
			Sound.Play("slap")
			Sound.Play("slap_hit")
		end
	end)
end

---------------------------------------------------------------------------
-- impact effects on the customer (all clients)
---------------------------------------------------------------------------
local function effects(model: Model)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SlapFX"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(220, 220)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = 70
	gui.Parent = player:WaitForChild("PlayerGui")
	-- big impact burst
	local boom = Instance.new("TextLabel")
	boom.BackgroundTransparency = 1
	boom.AnchorPoint = Vector2.new(0.5, 0.5)
	boom.Position = UDim2.fromScale(0.5, 0.5)
	boom.Size = UDim2.fromOffset(40, 40)
	boom.Text = "💥"
	boom.TextScaled = true
	boom.Parent = gui
	TweenService:Create(boom, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(120, 120) }):Play()
	task.delay(0.25, function()
		TweenService:Create(boom, TweenInfo.new(0.3), { TextTransparency = 1, Size = UDim2.fromOffset(150, 150) }):Play()
	end)
	-- "KLATSCH!" comic text
	local word = Instance.new("TextLabel")
	word.BackgroundTransparency = 1
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.22)
	word.Size = UDim2.fromOffset(200, 44)
	word.Font = Enum.Font.FredokaOne
	word.TextScaled = true
	word.Text = State.lang == "de" and "KLATSCH!" or "SLAP!"
	word.TextColor3 = Color3.fromRGB(255, 220, 60)
	word.TextStrokeColor3 = Color3.fromRGB(120, 30, 0)
	word.TextStrokeTransparency = 0
	word.Rotation = -12
	word.Parent = gui
	local ws = Instance.new("UIScale")
	ws.Scale = 0.3
	ws.Parent = word
	TweenService:Create(ws, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(word, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.5), { Position = UDim2.fromScale(0.5, 0.05), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	-- sparks flying outwards
	for i = 1, 7 do
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromScale(0.5, 0.5)
		s.Size = UDim2.fromOffset(22, 22)
		s.Text = i % 2 == 0 and "✦" or "★"
		s.TextScaled = true
		s.TextColor3 = Color3.fromRGB(255, 230, 90)
		s.Parent = gui
		local a = (i / 7) * math.pi * 2
		TweenService:Create(s, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(a) * 90, 0.5, math.sin(a) * 90),
			TextTransparency = 1,
			Rotation = 180,
		}):Play()
	end
	-- red hand print on the cheek (on the head's left side, fades slowly)
	local handPrint = Instance.new("SurfaceGui")
	handPrint.Name = "HandPrint"
	handPrint.Face = Enum.NormalId.Left
	handPrint.Adornee = head
	handPrint.LightInfluence = 1
	handPrint.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	handPrint.PixelsPerStud = 100
	handPrint.Parent = player:WaitForChild("PlayerGui")
	local hp = Instance.new("TextLabel")
	hp.BackgroundTransparency = 1
	hp.AnchorPoint = Vector2.new(0.5, 0.5)
	hp.Position = UDim2.fromScale(0.45, 0.55)
	hp.Size = UDim2.fromScale(0.75, 0.75)
	hp.Text = "✋"
	hp.TextScaled = true
	hp.TextColor3 = Color3.fromRGB(230, 40, 40)
	hp.TextTransparency = 0.25
	hp.Parent = handPrint
	TweenService:Create(hp, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), { TextTransparency = 1 }):Play()
	-- dizzy stars circling above the head
	local dizzy = Instance.new("BillboardGui")
	dizzy.Adornee = head
	dizzy.Size = UDim2.fromOffset(120, 60)
	dizzy.StudsOffsetWorldSpace = Vector3.new(0, 1.3, 0)
	dizzy.LightInfluence = 0
	dizzy.MaxDistance = 70
	dizzy.Parent = player:WaitForChild("PlayerGui")
	local stars = {}
	for i = 1, 3 do
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Size = UDim2.fromOffset(20, 20)
		s.Text = "⭐"
		s.TextScaled = true
		s.Parent = dizzy
		stars[i] = s
	end
	local t0 = os.clock()
	local rs
	rs = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > 2.4 or not head.Parent then
			rs:Disconnect()
			dizzy:Destroy()
			return
		end
		for i, s in ipairs(stars) do
			local a = t * 5 + i * (math.pi * 2 / 3)
			s.Position = UDim2.new(0.5, math.cos(a) * 40, 0.5, math.sin(a) * 10)
			s.TextTransparency = t > 1.9 and (t - 1.9) * 2 or 0
		end
	end)
	task.delay(1.2, function()
		gui:Destroy()
	end)
	task.delay(5, function()
		handPrint:Destroy()
	end)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
-- called the moment the local player presses the prompt (instant feedback)
function Slap.Local(_model: Model)
	lastLocal = os.clock()
	playHand()
end

function Slap.Init()
	State.Remote("Slap").OnClientEvent:Connect(function(slapper: Player, model: Model)
		if typeof(model) ~= "Instance" or not model:IsA("Model") then
			return
		end
		local isMe = slapper == player and os.clock() - lastLocal < 1
		task.delay(isMe and 0.05 or 0.2, function()
			effects(model)
			if not isMe then
				local head = model:FindFirstChild("Head") :: BasePart?
				Sound.Play("slap", head and head.Position or nil)
			end
		end)
	end)
	-- camera punch after a slap
	RunService:BindToRenderStep("KebapSlapShake", Enum.RenderPriority.Camera.Value + 4, function(dt)
		if shake <= 0.001 then
			shake = 0
			return
		end
		local cam = workspace.CurrentCamera
		if cam then
			local s = shake
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(math.sin(os.clock() * 60) * 1.2 * s), math.rad(shakeSide * 2.2 * s), math.rad(shakeSide * 1.5 * s))
		end
		shake = math.max(0, shake - dt * 4)
	end)
end

return Slap
