-- Meat carving at the rotating spit (client side).
--
--  * Cutting mode (local player): the cook steps up to the spit, the camera moves over the right
--    shoulder, movement is frozen and every prompt is hidden. [Click] / [Space] / [R2] / the touch
--    button makes one knife stroke; the electric cutter runs while the button is held. [E] /
--    [Backspace] / [B] / "Fertig" ends cutting. A rhythm bar shows the knife's ideal stroke timing.
--  * Body animation (every client, every cook): the R15 joints (waist, neck, both shoulders, elbows,
--    right wrist) are posed procedurally through the joints' Transform (Motor6D or AnimationConstraint)
--    after the Animator has run, so the
--    cut looks the same from every point of view: raise the knife, controlled downward slice along
--    the meat surface, back to the ready position. Each knife has its own rhythm and amplitude.
--  * Slices (every client): each stroke the server accepted (CutFX) shaves a slice off the meat at
--    the blade's height; it peels away, falls into the drip tray and fades, with grease sparks.
-- The client only sends stroke intents; the server times them and decides the meat (MeatCuttingService).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Progression = require(Shared.Progression)
local IngredientData = require(Shared.IngredientData)
local State = require(script.Parent.State)
local Sound = require(script.Parent.Sound)
local Kit = require(script.Parent.UIKit)

local MeatCutting = {}
MeatCutting.OnChanged = function(_active: boolean) end

local player = Players.LocalPlayer
local new, corner, label, tween = Kit.new, Kit.corner, Kit.label, Kit.tween
local T, F = Kit.T, Kit.F

local function tr(de: string, en: string): string
	return State.lang == "de" and de or en
end

---------------------------------------------------------------------------
-- R15 pose animation (all cooks)
---------------------------------------------------------------------------
-- joint -> { rx, ry, rz } (radians) in Motor6D.Transform space
type Pose = { [string]: { number } }
local JOINTS = {
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
}

-- Pose angles (rx = raise forward, rz = sideways). The wrist compensates the arm so the blade's
-- flat stays against the meat with the edge pointing down: rs + re + rw ≈ 90°.
-- ready: knife held against the upper half of the meat, left hand steadying at the tray, eyes up
local READY: Pose = {
	Waist = { -0.12, 0.05, 0 },
	Neck = { 0.15, -0.08, 0 },
	RightShoulder = { 2.5, 0, -0.08 },
	RightElbow = { 0.1, 0, 0 },
	RightWrist = { -0.93, 0, 0 },
	LeftShoulder = { 0.6, 0, 0.25 },
	LeftElbow = { 0.9, 0, 0 },
}
-- top of the stroke: knife lifted to the upper edge of the meat
local TOP: Pose = {
	Waist = { -0.03, 0.06, 0 },
	Neck = { 0.25, -0.08, 0 },
	RightShoulder = { 2.75, 0, -0.06 },
	RightElbow = { 0.2, 0, 0 },
	RightWrist = { -1.3, 0, 0 },
	LeftShoulder = { 0.6, 0, 0.25 },
	LeftElbow = { 0.9, 0, 0 },
}
-- end of the slice: arm pulled down through the meat surface, shoulders lean in, wrist follows
local CUT: Pose = {
	Waist = { -0.3, 0.03, 0 },
	Neck = { -0.02, -0.08, 0 },
	RightShoulder = { 2.15, 0, -0.1 },
	RightElbow = { 0.05, 0, 0 },
	RightWrist = { -0.5, 0, 0 },
	LeftShoulder = { 0.55, 0, 0.28 },
	LeftElbow = { 0.95, 0, 0 },
}

-- per knife: stroke duration factor and amplitude (old knife: big heavy strokes, pro: long sweep)
local STYLE = {
	old = { dur = 0.62, amp = 1.0 },
	standard = { dur = 0.52, amp = 0.95 },
	pro = { dur = 0.5, amp = 1.08 },
	premium = { dur = 0.44, amp = 0.9 },
	electric = { dur = 0.24, amp = 0.35 },
}

type Cook = {
	char: Model,
	joints: { [string]: any }, -- Motor6D | AnimationConstraint
	weight: number,
	strokeStart: number?,
	strokeDur: number,
	amp: number,
	sweep: number, -- electric: slow downward sweep while running
	lastStroke: number,
	motor: Sound?,
}
local cooks: { [Model]: Cook } = {}

local function lerpPose(a: Pose, b: Pose, f: number, out: Pose)
	for j, va in pairs(a) do
		local vb = b[j]
		out[j] = { va[1] + (vb[1] - va[1]) * f, va[2] + (vb[2] - va[2]) * f, va[3] + (vb[3] - va[3]) * f }
	end
end

local function smooth(f: number): number
	return f * f * (3 - 2 * f)
end

local tmpA: Pose, tmpB: Pose = {}, {}

-- pose of a cook at time `now` (stroke phase: raise → slice → recover)
local function strokePose(c: Cook, now: number): Pose
	if not c.strokeStart then
		return READY
	end
	local t = (now - c.strokeStart) / c.strokeDur
	if t >= 1 then
		c.strokeStart = nil
		return READY
	end
	local top, cut = TOP, CUT
	if c.amp ~= 1 then
		-- scale the stroke around the ready pose
		lerpPose(READY, TOP, c.amp, tmpA)
		lerpPose(READY, CUT, c.amp, tmpB)
		top, cut = tmpA, tmpB
	end
	local out: Pose = {}
	if t < 0.3 then
		lerpPose(READY, top, smooth(t / 0.3), out)
	elseif t < 0.62 then
		local f = (t - 0.3) / 0.32
		lerpPose(top, cut, f * f * (3 - 2 * f), out)
	else
		lerpPose(cut, READY, smooth((t - 0.62) / 0.38), out)
	end
	return out
end

local function addCook(char: Model)
	if cooks[char] then
		return
	end
	local joints = {}
	for joint, partName in pairs(JOINTS) do
		local p = char:FindFirstChild(partName)
		local m = p and p:FindFirstChild(joint)
		-- classic rigs use Motor6D, newer avatar rigs AnimationConstraint: both expose .Transform
		if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then
			joints[joint] = m
		end
	end
	cooks[char] = { char = char, joints = joints, weight = 0, strokeStart = nil, strokeDur = 0.5, amp = 1, sweep = 0, lastStroke = 0 }
end

-- start a stroke animation on a character (called for local input and for server-confirmed strokes)
local function animateStroke(char: Model, knife: string?)
	addCook(char)
	local c = cooks[char]
	local st = STYLE[knife or "standard"] or STYLE.standard
	c.strokeStart = os.clock()
	c.strokeDur = st.dur
	c.amp = st.amp * (0.94 + math.random() * 0.12)
	c.lastStroke = os.clock()
end

local function poseStep(dt: number)
	local now = os.clock()
	for char, c in pairs(cooks) do
		if not char.Parent then
			cooks[char] = nil
			continue
		end
		local active = char:GetAttribute("Cutting") ~= nil
		c.weight = math.clamp(c.weight + (active and dt * 5 or -dt * 4), 0, 1)
		if c.weight <= 0 and not active then
			if c.motor then
				c.motor:Destroy()
				c.motor = nil
			end
			cooks[char] = nil
			continue
		end
		local pose = strokePose(c, now)
		local knife = char:GetAttribute("CutKnife")
		if knife == "electric" then
			-- the motor cutter is guided slowly down the meat while it runs, with a fine vibration
			local running = now - c.lastStroke < 0.35
			c.sweep = running and (c.sweep + dt * 0.8) % 1 or math.max(0, c.sweep - dt)
			local sweepPose: Pose = {}
			lerpPose(TOP, CUT, smooth(c.sweep), sweepPose)
			local mixed: Pose = {}
			lerpPose(pose, sweepPose, running and 0.75 or 0, mixed)
			if running then
				local v = math.sin(now * 90) * 0.025
				mixed.RightWrist = { mixed.RightWrist[1] + v, mixed.RightWrist[2], mixed.RightWrist[3] + v }
			end
			pose = mixed
			-- motor sound follows the cook
			local disc = char:FindFirstChild("CutKnife") and (char :: any).CutKnife:FindFirstChild("Disc")
			if disc and not c.motor then
				local s = Sound.Attach("cutter_motor", disc)
				c.motor = s
			end
			if c.motor then
				c.motor.Volume = running and 0.35 or 0
			end
		end
		local w = c.weight
		for joint, m in pairs(c.joints) do
			local r = pose[joint]
			if r and m.Parent then
				local target = CFrame.Angles(r[1], r[2], r[3])
				m.Transform = w >= 1 and target or m.Transform:Lerp(target, w)
			end
		end
	end
end

-- electric cutter disc spins on every client
local spinWelds: { [Weld]: CFrame } = {}
local function spinStep(dt: number)
	for char in pairs(cooks) do
		local k = char:FindFirstChild("CutKnife")
		local disc = k and k:FindFirstChild("Disc")
		local w = disc and disc:FindFirstChildOfClass("Weld")
		if w then
			local base = spinWelds[w]
			if not base then
				base = w.C0
				spinWelds[w] = base
			end
			local c = cooks[char]
			local speed = (os.clock() - c.lastStroke < 0.35) and 40 or 4
			w:SetAttribute("A", ((w:GetAttribute("A") or 0) + dt * speed) % (math.pi * 2))
			w.C0 = base * CFrame.Angles(w:GetAttribute("A") :: number, 0, 0)
		end
	end
	for w in pairs(spinWelds) do
		if not w.Parent then
			spinWelds[w] = nil
		end
	end
end

---------------------------------------------------------------------------
-- slices falling into the tray (all clients)
---------------------------------------------------------------------------
local function spitModel(meat: string): Model?
	for _, m in ipairs(CollectionService:GetTagged("Spit")) do
		if m:IsA("Model") and m:GetAttribute("Meat") == meat and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

local function sliceFX(char: Model, meat: string)
	local spit = spitModel(meat)
	local meatModel = spit and spit:FindFirstChild("Meat")
	local tray = spit and spit:FindFirstChild("DripTray") :: BasePart?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not spit or not meatModel or not tray or not root then
		return
	end
	local cx, cz = meatModel:GetAttribute("SpinX"), meatModel:GetAttribute("SpinZ")
	if typeof(cx) ~= "number" or typeof(cz) ~= "number" then
		return
	end
	-- height of the blade (fallback: the middle of the meat)
	local layers = {}
	for _, l in ipairs(meatModel:GetChildren()) do
		if l:IsA("BasePart") then
			table.insert(layers, l)
		end
	end
	if #layers == 0 then
		return
	end
	table.sort(layers, function(a, b)
		return a.Position.Y > b.Position.Y
	end)
	local knife = char:FindFirstChild("CutKnife")
	local blade = knife and (knife:FindFirstChild("Blade") or knife:FindFirstChild("Disc")) :: BasePart?
	local topY, botY = layers[1].Position.Y, layers[#layers].Position.Y
	local y = blade and math.clamp(blade.Position.Y, botY, topY) or (topY + botY) / 2
	-- the layer at that height decides radius and colour
	local layer = layers[1]
	for _, l in ipairs(layers) do
		if math.abs(l.Position.Y - y) < math.abs(layer.Position.Y - y) then
			layer = l
		end
	end
	local dir = Vector3.new(root.Position.X - cx, 0, root.Position.Z - cz)
	dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, 1)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local radius = layer.Size.Y / 2
	local contact = Vector3.new(cx, y, cz) + dir * (radius + 0.02) + side * (math.random() - 0.5) * 0.5

	local slice = Instance.new("Part")
	slice.Name = "MeatSlice"
	slice.Anchored = true
	slice.CanCollide = false
	slice.CanQuery = false
	slice.CanTouch = false
	slice.CastShadow = false
	slice.Material = Enum.Material.Sand
	local col = layer.Color
	slice.Color = Color3.new(math.clamp(col.R * (0.9 + math.random() * 0.15), 0, 1), math.clamp(col.G * (0.88 + math.random() * 0.12), 0, 1), math.clamp(col.B * 0.9, 0, 1))
	slice.Size = Vector3.new(0.5 + math.random() * 0.2, 0.36 + math.random() * 0.12, 0.05)
	slice.CFrame = CFrame.lookAt(contact, contact + dir)
	slice.Parent = workspace
	-- browned edge stripe
	local edge = slice:Clone()
	edge.Name = "Crust"
	edge.Size = Vector3.new(slice.Size.X, 0.05, 0.055)
	edge.Color = slice.Color:Lerp(Color3.fromRGB(70, 40, 20), 0.45)
	edge.CFrame = slice.CFrame * CFrame.new(0, slice.Size.Y / 2, 0)
	edge.Parent = slice

	-- peel away from the meat, then drop into the tray, then fade
	local peel = slice.CFrame * CFrame.new(0, -0.08, -0.18) * CFrame.Angles(math.rad(-25), 0, 0)
	local landPos = tray.Position + Vector3.new((math.random() - 0.5) * 1.6, tray.Size.Y / 2 + 0.04 + math.random() * 0.06, tray.Size.Z * (0.05 + math.random() * 0.3))
	local land = CFrame.new(landPos) * CFrame.Angles(math.rad(90 + math.random(-15, 15)), math.rad(math.random(0, 360)), 0)
	local function follow(p: BasePart, target: CFrame, info: TweenInfo)
		TweenService:Create(p, info, { CFrame = target }):Play()
		TweenService:Create(edge, info, { CFrame = target * CFrame.new(0, slice.Size.Y / 2, 0) }):Play()
	end
	follow(slice, peel, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	task.delay(0.1, function()
		follow(slice, land, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	end)
	task.delay(1.6, function()
		TweenService:Create(slice, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		TweenService:Create(edge, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(slice, 2.4)

	-- grease sparks at the blade
	local a = Instance.new("Attachment")
	a.WorldPosition = contact
	a.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 150, 60))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	pe.LightEmission = 0.6
	pe.Lifetime = NumberRange.new(0.25, 0.45)
	pe.Speed = NumberRange.new(1.5, 3.5)
	pe.SpreadAngle = Vector2.new(50, 50)
	pe.Acceleration = Vector3.new(0, -12, 0)
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Rate = 0
	pe.Parent = a
	a.CFrame = CFrame.lookAt(contact, contact + dir)
	pe:Emit(7)
	Debris:AddItem(a, 1)
	Sound.Play("cut_slice", contact)
end

---------------------------------------------------------------------------
-- local cutting mode
---------------------------------------------------------------------------
type Session = { meat: string, knife: string, interval: number, window: number, slices: number, auto: boolean, part: BasePart }
local session: Session? = nil
local lastPress = 0
local holding = false
local gui: ScreenGui
local refs: { [string]: any } = {}
local savedCamType: Enum.CameraType? = nil
local savedCamMode: Enum.CameraMode? = nil
local HEAD_PARTS = { Head = true, ChefCap = true, CapBand = true, HairBack = true, Moustache = true }
local camShake = 0

function MeatCutting.IsActive(): boolean
	return session ~= nil
end

local RATING = {
	perfect = { de = "PERFEKT!", en = "PERFECT!", color = T.green },
	fast = { de = "ZU HASTIG", en = "TOO HASTY", color = T.red },
	slow = { de = "ZU LANGSAM", en = "TOO SLOW", color = T.orange },
	start = { de = "GUTER ANSATZ", en = "GOOD START", color = T.text },
	electric = { de = "SAUBER", en = "CLEAN", color = T.blue },
}

local function buildGui()
	gui = new("ScreenGui", { Name = "CutGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, Enabled = false, Parent = player:WaitForChild("PlayerGui") })
	-- top centre, under the clock: the lower half of the screen belongs to the arm, knife and meat
	local panel = Kit.glass({ Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(400, 150), GroupTransparency = 0 }, 16, "CanvasGroup")
	panel.Parent = gui
	refs.panel = panel
	refs.title = label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 20), Font = F.black, TextSize = 15, Text = "", Parent = panel })
	refs.portions = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 10), Size = UDim2.fromOffset(160, 20), TextXAlignment = Enum.TextXAlignment.Right, Font = F.bold, TextSize = 14, TextColor3 = T.gold, Text = "", Parent = panel })
	-- rhythm bar: dark = too early (no cut), red = hasty, green = ideal, beyond = slow
	local bar = new("Frame", { Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 16), BackgroundColor3 = Color3.fromRGB(40, 40, 46), BorderSizePixel = 0, ClipsDescendants = true, Parent = panel }, { corner(8) })
	refs.bar = bar
	refs.early = new("Frame", { Size = UDim2.fromScale(0.2, 1), BackgroundColor3 = Color3.fromRGB(20, 20, 24), BorderSizePixel = 0, Parent = bar })
	refs.hasty = new("Frame", { BackgroundColor3 = Color3.fromRGB(150, 50, 44), BorderSizePixel = 0, Parent = bar })
	refs.zone = new("Frame", { BackgroundColor3 = Color3.fromRGB(60, 190, 100), BorderSizePixel = 0, Parent = bar })
	refs.slow = new("Frame", { BackgroundColor3 = Color3.fromRGB(170, 120, 40), BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = bar })
	refs.marker = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 4, 1, 6), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = bar })
	refs.rating = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(300, 28), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 24, Text = "", Parent = panel })
	refs.ratingScale = new("UIScale", { Parent = refs.rating })
	refs.dots = new("Frame", { Position = UDim2.fromOffset(16, 96), Size = UDim2.new(1, -32, 0, 16), BackgroundTransparency = 1, Parent = panel })
	Kit.list(true, 6).Parent = refs.dots
	refs.hint = label({ Position = UDim2.fromOffset(16, 120), Size = UDim2.new(1, -32, 0, 18), TextSize = 12, TextColor3 = T.dim, Text = "", Parent = panel })
	-- touch controls
	if UserInputService.TouchEnabled then
		refs.cutBtn = Kit.button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -30, 1, -180), Size = UDim2.fromOffset(150, 150), Radius = 75, BackgroundColor3 = T.accent, TextSize = 22, Text = "🔪\n" .. "SCHNEIDEN", Quiet = true, Parent = gui })
		refs.doneBtn = Kit.button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -200, 1, -190), Size = UDim2.fromOffset(110, 48), BackgroundColor3 = Color3.fromRGB(60, 60, 70), TextSize = 16, Text = "✓ Fertig", Parent = gui }, function()
			MeatCutting.Stop()
		end)
		refs.cutBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				MeatCutting.Press(true)
			end
		end)
		refs.cutBtn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				MeatCutting.Press(false)
			end
		end)
	end
end

local function setDots(n: number, total: number)
	Kit.clear(refs.dots, { "UIListLayout" })
	label({ LayoutOrder = 0, Size = UDim2.fromOffset(70, 16), TextSize = 12, TextColor3 = T.dim, Text = tr("Scheiben", "Slices"), Parent = refs.dots })
	for i = 1, total do
		local on = i <= n
		local d = new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(14, 14), BackgroundColor3 = on and Color3.fromRGB(205, 140, 70) or Color3.fromRGB(60, 60, 66), BorderSizePixel = 0, Parent = refs.dots }, { Kit.round() })
		if on and i == n then
			Kit.pop(d, 1.6, 0.25)
		end
	end
end

local function neededPortions(): number?
	local item = State.SelectedItem()
	return item and item.meatPortions or nil
end

local function meatInMeal(): number
	local m = State.player and State.player.meal
	local n = 0
	if m then
		for _, v in pairs(m.meat) do
			n += v
		end
	end
	return n
end

local function updatePortions()
	local need = neededPortions()
	local have = meatInMeal()
	refs.portions.Text = need and string.format("🥩 %d / %d %s", have, need, tr("Portionen", "portions")) or string.format("🥩 %d %s", have, tr("Portionen", "portions"))
	refs.portions.TextColor3 = (need and have >= need) and T.green or T.gold
end

local function layoutBar(s: Session)
	-- time axis 0 … 2× ideal interval
	local span = s.interval * 2
	local function x(t: number): number
		return math.clamp(t / span, 0, 1)
	end
	local minGap = s.interval * 0.45
	refs.early.Size = UDim2.fromScale(x(minGap), 1)
	refs.hasty.Position = UDim2.fromScale(x(minGap), 0)
	refs.hasty.Size = UDim2.fromScale(x(s.interval - s.window) - x(minGap), 1)
	refs.zone.Position = UDim2.fromScale(x(s.interval - s.window), 0)
	refs.zone.Size = UDim2.fromScale(x(s.interval + s.window) - x(s.interval - s.window), 1)
	refs.slow.Position = UDim2.fromScale(x(s.interval + s.window), 0)
	refs.slow.Size = UDim2.fromScale(1 - x(s.interval + s.window), 1)
end

local function showRating(key: string)
	local r = RATING[key] or RATING.start
	refs.rating.Text = r[State.lang] or r.en
	refs.rating.TextColor3 = r.color
	refs.ratingScale.Scale = 1.35
	tween(refs.ratingScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- one knife stroke from local input
local function doStroke()
	local s = session
	local char = player.Character
	if not s or not char then
		return
	end
	local now = os.clock()
	-- the client never fires faster than the knife can cut (the server enforces it anyway)
	local minGap = s.auto and s.interval * 0.75 or s.interval * 0.47
	if now - lastPress < minGap then
		return
	end
	lastPress = now
	animateStroke(char, s.knife)
	camShake = 0.6
	State.Remote("CutStroke"):FireServer()
end

function MeatCutting.Press(down: boolean)
	local s = session
	if not s then
		return
	end
	if s.auto then
		holding = down
		if down then
			task.spawn(function()
				while holding and session == s do
					doStroke()
					task.wait(s.interval * 0.8)
				end
			end)
		end
	elseif down then
		doStroke()
	end
end

local function sink()
	return Enum.ContextActionResult.Sink
end

local function unbind()
	for _, n in ipairs({ "KebapCutStroke", "KebapCutExit", "KebapCutFreeze" }) do
		ContextActionService:UnbindAction(n)
	end
	RunService:UnbindFromRenderStep("KebapCutCamera")
end

local function cleanup()
	if not session then
		return
	end
	session = nil
	holding = false
	unbind()
	ProximityPromptService.Enabled = true
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = savedCamType or Enum.CameraType.Custom
	end
	player.CameraMode = savedCamMode or Enum.CameraMode.LockFirstPerson
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = true
	end
	local char = player.Character
	if char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = 0
			end
		end
	end
	local panel = refs.panel
	local tw = tween(panel, 0.25, { GroupTransparency = 1 })
	tw.Completed:Connect(function()
		if not session then
			gui.Enabled = false
		end
	end)
	MeatCutting.OnChanged(false)
end

function MeatCutting.Stop()
	if not session then
		return
	end
	cleanup()
	task.spawn(function()
		State.Request("CutStop")
	end)
end

function MeatCutting.Start(part: BasePart)
	if session then
		return
	end
	local meat = part:GetAttribute("Item")
	if type(meat) ~= "string" then
		return
	end
	local res = State.Request("CutStart", meat)
	if not res or not res.ok then
		Sound.Play("fail")
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local spit = spitModel(meat)
	local meatModel = spit and spit:FindFirstChild("Meat")
	if not root or not meatModel then
		State.Request("CutStop")
		return
	end
	local s: Session = { meat = meat, knife = res.knife, interval = res.interval, window = res.window, slices = res.slices, auto = res.auto, part = part }
	session = s
	lastPress = 0
	-- step up to the spit: square to the meat, right hand in line with it
	local cx, cz = meatModel:GetAttribute("SpinX") :: number, meatModel:GetAttribute("SpinZ") :: number
	local away = Vector3.new(root.Position.X - cx, 0, root.Position.Z - cz)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
	local right = Vector3.new(away.Z, 0, -away.X) -- character's right when facing the meat
	local stand = Vector3.new(cx, root.Position.Y, cz) + away * 2.85 - right * 0.55
	-- keep the hip height above whatever floor is there (the cook's deck in front of the spits)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char :: Model }
	local below = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), rp)
	local target = workspace:Raycast(stand + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), rp)
	if below and target then
		stand = Vector3.new(stand.X, target.Position.Y + (root.Position.Y - below.Position.Y), stand.Z)
	end
	local standCF = CFrame.lookAt(stand, stand - away)
	root.CFrame = standCF
	root.AssemblyLinearVelocity = Vector3.zero
	-- third-person rules while cutting: the first-person camera would turn the body with the view
	savedCamMode = player.CameraMode
	player.CameraMode = Enum.CameraMode.Classic
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		-- first person turns the body with the camera (camera-relative rotation): stop that
		hum.AutoRotate = false
	end

	-- freeze walking/jumping, map the cut / exit inputs
	ContextActionService:BindActionAtPriority("KebapCutFreeze", sink, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("KebapCutStroke", function(_, state)
		if state == Enum.UserInputState.Begin then
			MeatCutting.Press(true)
		elseif state == Enum.UserInputState.End then
			MeatCutting.Press(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, 3001, Enum.UserInputType.MouseButton1, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("KebapCutExit", function(_, state)
		if state == Enum.UserInputState.Begin then
			MeatCutting.Stop()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3001, Enum.KeyCode.E, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
	ProximityPromptService.Enabled = false

	-- over-the-shoulder view on the meat
	local cam = workspace.CurrentCamera
	savedCamType = cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable
	local focus = Vector3.new(cx, 0, cz)
	local camCF = cam.CFrame
	RunService:BindToRenderStep("KebapCutCamera", Enum.RenderPriority.Camera.Value + 10, function(dt)
		local c = player.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not r or not session then
			return
		end
		local layers = meatModel:GetChildren()
		local fy = r.Position.Y + 3
		if #layers > 0 then
			local sum, n = 0, 0
			for _, l in ipairs(layers) do
				if l:IsA("BasePart") then
					sum += l.Position.Y
					n += 1
				end
			end
			fy = n > 0 and sum / n or fy
		end
		-- keep the cook squared up to the spit (nothing may turn the body while cutting)
		if (r.Position - standCF.Position).Magnitude < 3 then
			r.CFrame = CFrame.new(r.Position) * standCF.Rotation
		end
		-- high over-the-shoulder view: the meat face, the blade on it and the cook's arm in one shot
		local look = Vector3.new(focus.X, r.Position.Y + 1.3, focus.Z) + away * 0.6
		local eye = r.Position + Vector3.new(0, 4.3, 0) - right * 1.6 + away * 2.4
		local target = CFrame.lookAt(eye, look)
		camCF = camCF:Lerp(target, math.min(1, dt * 8))
		local shake = camShake > 0 and CFrame.Angles(math.rad(math.sin(os.clock() * 50) * 0.35 * camShake), 0, math.rad(math.sin(os.clock() * 37) * 0.25 * camShake)) or CFrame.new()
		camShake = math.max(0, camShake - dt * 4)
		workspace.CurrentCamera.CFrame = camCF * shake
		-- show the own body (first-person normally hides it); the head and cap stay see-through so
		-- they never hide the knife
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then
				local want = HEAD_PARTS[p.Name] and 0.65 or 0
				if p.LocalTransparencyModifier ~= want then
					p.LocalTransparencyModifier = want
				end
			end
		end
	end)

	-- UI
	local k = Progression.Knives[s.knife]
	refs.title.Text = string.format("🔪 %s · %s", k.name[State.lang], IngredientData.Meat[meat].name[State.lang])
	refs.bar.Visible = not s.auto
	refs.rating.Text = s.auto and tr("Gedrückt halten", "Hold") or tr("Im Takt schneiden", "Cut in rhythm")
	refs.rating.TextColor3 = T.text
	layoutBar(s)
	setDots(0, s.slices)
	updatePortions()
	local keys = UserInputService.TouchEnabled and "" or (s.auto and tr("[Maus/Leertaste] halten", "Hold [Mouse/Space]") or tr("[Klick/Leertaste] schneiden", "[Click/Space] cut"))
	refs.hint.Text = keys .. (keys ~= "" and "  ·  " or "") .. tr("[E] fertig", "[E] done") .. "  ·  " .. tr("grüner Bereich = beste Qualität", "green zone = best quality")
	if s.auto then
		refs.hint.Text = keys .. "  ·  " .. tr("[E] fertig", "[E] done")
	end
	gui.Enabled = true
	refs.panel.GroupTransparency = 1
	tween(refs.panel, 0.3, { GroupTransparency = 0 })
	Kit.pop(refs.panel, 0.9, 0.3)
	MeatCutting.OnChanged(true)
end

function MeatCutting.Init()
	buildGui()
	RunService.PreSimulation:Connect(poseStep)
	RunService.RenderStepped:Connect(function(dt)
		spinStep(dt)
		-- rhythm marker
		local s = session
		if s and not s.auto and gui.Enabled then
			-- measured from the last own stroke (the server times the gaps between strokes the same way)
			local since = lastPress > 0 and (os.clock() - lastPress) or s.interval * 2
			refs.marker.Position = UDim2.fromScale(math.clamp(since / (s.interval * 2), 0, 1), 0.5)
			local inZone = math.abs(since - s.interval) <= s.window
			refs.marker.BackgroundColor3 = inZone and Color3.fromRGB(180, 255, 190) or Color3.new(1, 1, 1)
		end
	end)
	-- characters that are cutting (incl. other players)
	local function watch(char: Model)
		char:GetAttributeChangedSignal("Cutting"):Connect(function()
			if char:GetAttribute("Cutting") then
				addCook(char)
			end
		end)
		if char:GetAttribute("Cutting") then
			addCook(char)
		end
	end
	local function onPlayer(p: Player)
		if p.Character then
			watch(p.Character)
		end
		p.CharacterAdded:Connect(watch)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)

	State.Remote("CutFX").OnClientEvent:Connect(function(cook: Player, meat: string, rating: string, slices: number, perPortion: number)
		local char = cook and cook.Character
		if not char then
			return
		end
		local knife = char:GetAttribute("CutKnife")
		if cook == player then
			-- own stroke confirmed: rating and slices
			if session then
				showRating(rating)
				setDots(slices, perPortion)
			end
			sliceFX(char, meat)
		else
			animateStroke(char, knife)
			local dur = (STYLE[knife or "standard"] or STYLE.standard).dur
			task.delay(dur * 0.5, function()
				sliceFX(char, meat)
			end)
		end
	end)
	State.Remote("CutResult").OnClientEvent:Connect(function(r)
		if not session then
			return
		end
		local pct = math.floor((r.quality or 0) * 100 + 0.5)
		refs.rating.Text = string.format("✅ %s · %d%%", tr("Portion fertig", "Portion done"), pct)
		refs.rating.TextColor3 = pct >= 90 and T.green or (pct >= 70 and T.gold or T.orange)
		refs.ratingScale.Scale = 1.3
		tween(refs.ratingScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		setDots(0, session.slices)
		task.defer(updatePortions)
	end)
	State.Remote("CutEnd").OnClientEvent:Connect(function()
		cleanup()
	end)
	State.Changed:Connect(function(what)
		if what == "player" and session then
			local m = State.player and State.player.meal
			if not m or m.closed or State.player.location == "grill" then
				MeatCutting.Stop()
			else
				updatePortions()
			end
		elseif what == "selection" and session then
			updatePortions()
		end
	end)
	player.CharacterRemoving:Connect(function()
		cleanup()
	end)
end

return MeatCutting
