-- Hand presentation: arm poses for items in the hand (Server/HandService), the carried tray and the
-- held bread, meat pan or bread top (Server/FoodPreparationService), applied to every player's joints;
-- plus a first-person view model of the flashed item for yourself.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HandUI = {}
local lp = Players.LocalPlayer

type Pose = { [string]: { any } }
local REACH: Pose = { RightShoulder = { "RightUpperArm", 1.1, 0, 0.15 }, RightElbow = { "RightLowerArm", 0.55, 0, 0 }, RightWrist = { "RightHand", -0.2, 0, 0 } }
local SQUEEZE: Pose = { RightShoulder = { "RightUpperArm", 1.35, 0, 0.12 }, RightElbow = { "RightLowerArm", 0.9, 0, 0 }, RightWrist = { "RightHand", 0.6, 0, 0 } }
local TRAY: Pose = {
	RightShoulder = { "RightUpperArm", 0.95, 0, -0.25 }, LeftShoulder = { "LeftUpperArm", 0.95, 0, 0.25 },
	RightElbow = { "RightLowerArm", 0.9, 0, 0 }, LeftElbow = { "LeftLowerArm", 0.9, 0, 0 },
}

local function apply(char: Model, pose: Pose, w: number, extra: number?)
	for joint, d in pairs(pose) do
		local part = char:FindFirstChild(d[1])
		local m = part and part:FindFirstChild(joint)
		if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then
			local target = CFrame.Angles(d[2] + (joint == "RightWrist" and extra or 0), d[3], d[4])
			;(m :: any).Transform = w >= 1 and target or (m :: any).Transform:Lerp(target, w)
		end
	end
end

local trayW: { [Model]: number } = {}

local function poseStep(dt: number)
	local now = workspace:GetServerTimeNow()
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		if not char or pl:GetAttribute("Carry") then
			continue
		end
		-- tray or bread held with both hands (the carving pose has its own left hand)
		local holding = (pl:GetAttribute("Tray") or pl:GetAttribute("Hold")) and not char:GetAttribute("Cutting")
		local tw = math.clamp((trayW[char] or 0) + (holding and dt * 6 or -dt * 6), 0, 1)
		trayW[char] = tw > 0 and tw or nil
		if tw > 0 then
			apply(char, TRAY, tw)
		end
		-- quick reach with the item in the right hand
		local act = pl:GetAttribute("HandAct")
		local t0 = pl:GetAttribute("HandT")
		if act and typeof(t0) == "number" then
			local t = now - t0
			if t >= 0 and t < 1.1 then
				local w = math.clamp(math.min(t / 0.15, (1.1 - t) / 0.25), 0, 1)
				local squeeze = act == "sauce"
				apply(char, squeeze and SQUEEZE or REACH, w, squeeze and math.sin(t * 18) * 0.12 or math.sin(t * 9) * 0.1)
			end
		end
	end
end

-- first person: show the item at the lower right of the screen with a simple fist
local view: Model? = nil
local viewT = 0
local function clearView()
	if view then
		view:Destroy()
		view = nil
	end
end

local function makeView()
	clearView()
	local src = workspace:FindFirstChild("HandItems") and workspace.HandItems:FindFirstChild("Hand_" .. lp.UserId)
	local hand = lp.Character and lp.Character:FindFirstChild("RightHand") :: BasePart?
	if not src or not hand then
		return
	end
	local m = src:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	-- fist + cuff so the item does not float in the air
	local fist = Instance.new("Part")
	fist.Name = "Fist"
	fist.Size = Vector3.new(0.42, 0.5, 0.42)
	fist.CFrame = hand.CFrame
	fist.Color = hand.Color
	fist.Anchored = true
	fist.CanCollide = false
	fist.CanQuery = false
	fist.Parent = m
	local cuff = fist:Clone()
	cuff.Name = "Cuff"
	cuff.Size = Vector3.new(0.5, 0.35, 0.5)
	cuff.CFrame = hand.CFrame * CFrame.new(0, 0.4, 0)
	cuff.Color = Color3.fromRGB(245, 245, 245)
	cuff.Parent = m
	m.PrimaryPart = fist
	m.Parent = workspace.CurrentCamera
	for _, d in ipairs(src:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		end
	end
	view = m
	viewT = os.clock()
end

local function viewStep()
	if not view then
		return
	end
	local t = os.clock() - viewT
	if t > 1.1 or not lp:GetAttribute("HandAct") then
		clearView()
		return
	end
	local cam = workspace.CurrentCamera
	local inK = math.clamp(math.min(t / 0.15, (1.1 - t) / 0.25), 0, 1)
	local bob = math.sin(t * 10) * 0.04
	-- palm faces the screen centre, item pointing forward
	local cf = cam.CFrame * CFrame.new(1.25, -1.75 + inK * 0.5 + bob, -3.2) * CFrame.Angles(math.rad(80), math.rad(-15), math.rad(10))
	view:PivotTo(cf)
end

function HandUI.Init()
	RunService.PreSimulation:Connect(poseStep)
	RunService.RenderStepped:Connect(viewStep)
	lp:GetAttributeChangedSignal("HandT"):Connect(function()
		task.wait() -- the item model replicates together with the attribute; give it a frame
		local hi = workspace:FindFirstChild("HandItems")
		if hi and not hi:FindFirstChild("Hand_" .. lp.UserId) then
			hi:WaitForChild("Hand_" .. lp.UserId, 0.5)
		end
		makeView()
	end)
end

return HandUI
