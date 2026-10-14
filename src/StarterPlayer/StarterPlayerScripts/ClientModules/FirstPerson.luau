-- First-person camera with realistic movement: eased acceleration, sprint, subtle head bob and
-- sway, footstep-synced bob. No permanent crosshair. The mouse cursor is freed for the HUD by
-- holding [Alt], toggling [C], or automatically while a menu panel is open: MouseBehavior is
-- overridden after the camera update and mouse-look is sunk so the view stays still.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local FirstPerson = {}

local player = Players.LocalPlayer
local WALK = 10
local SPRINT = 15.5
local ACCEL = 9 -- studs/s² ease-in, starting from a slow first step
local START_SPEED = 4

local hint: TextLabel
local manualCursor = false -- [C] toggles
local altHeld = false -- hold [Alt]
local menuOpen = false -- a HUD panel is open
local sprinting = false
local cursorFree = false

-- Mouse movement is sunk while the cursor is free so the view stays still while you click the HUD.
local function sinkLook()
	return Enum.ContextActionResult.Sink
end

local function updateCursor()
	local free = manualCursor or altHeld or menuOpen
	if free ~= cursorFree then
		cursorFree = free
		if free then
			ContextActionService:BindActionAtPriority("KebapFreezeLook", sinkLook, false, 3000, Enum.UserInputType.MouseMovement)
		else
			ContextActionService:UnbindAction("KebapFreezeLook")
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	end
	if hint then
		hint.Text = free and "[C] Maus sperren · lock mouse" or "[Alt] halten / [C] = Maus · mouse"
		hint.TextTransparency = free and 0 or 0.35
	end
end

function FirstPerson.SetMenuOpen(open: boolean)
	menuOpen = open
	updateCursor()
end

function FirstPerson.IsCursorFree(): boolean
	return cursorFree
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FirstPersonGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1
	gui.Parent = player:WaitForChild("PlayerGui")
	hint = Instance.new("TextLabel")
	hint.Name = "CursorHint"
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -14, 1, -12)
	hint.Size = UDim2.fromOffset(300, 18)
	hint.BackgroundTransparency = 1
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextColor3 = Color3.fromRGB(240, 230, 220)
	hint.TextStrokeTransparency = 0.6
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 13
	hint.Visible = UserInputService.KeyboardEnabled
	hint.Parent = gui
	updateCursor()
end

function FirstPerson.Init()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	buildGui()

	ContextActionService:BindAction("KebapCursor", function(_, state)
		if state == Enum.UserInputState.Begin then
			manualCursor = not manualCursor
			updateCursor()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.C)
	ContextActionService:BindAction("KebapCursorHold", function(_, state)
		altHeld = state == Enum.UserInputState.Begin
		updateCursor()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt)
	-- releasing focus (alt-tab) must not leave the cursor stuck free
	UserInputService.WindowFocusReleased:Connect(function()
		altHeld = false
		updateCursor()
	end)
	-- after the camera module has locked the mouse, override it while the cursor is free
	RunService:BindToRenderStep("KebapCursorFree", Enum.RenderPriority.Camera.Value + 2, function()
		if cursorFree then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end)
	ContextActionService:BindAction("KebapSprint", function(_, state)
		sprinting = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	local bobTime = 0
	local speed = 0
	local bobOffset = Vector3.zero
	local roll = 0
	local lastLook: Vector3? = nil
	local sway = 0

	-- runs right after the default camera so our offsets sit on top of it
	RunService:BindToRenderStep("KebapFirstPerson", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local cam = workspace.CurrentCamera
		if not hum or not root or not cam then
			return
		end
		cam.FieldOfView = 72 + (sprinting and 4 or 0)

		-- eased acceleration: a step starts slow and builds up, stopping is quick
		local moving = hum.MoveDirection.Magnitude > 0.05
		local mul = (player:GetAttribute("CarrySpeed") or 1) * (player:GetAttribute("SpeedMul") or 1)
		local target = (sprinting and SPRINT or WALK) * mul
		if moving then
			speed = speed < START_SPEED and START_SPEED or math.min(target, speed + ACCEL * dt)
			if speed > target then
				speed = math.max(target, speed - ACCEL * 2 * dt)
			end
		else
			speed = 0
		end
		hum.WalkSpeed = moving and speed or WALK * mul

		-- head bob tied to actual ground speed
		local horiz = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local onGround = hum.FloorMaterial ~= Enum.Material.Air
		local amount = onGround and math.clamp(horiz / SPRINT, 0, 1) or 0
		bobTime += dt * (6 + horiz * 0.55)
		local targetBob = Vector3.new(math.sin(bobTime) * 0.07 * amount, math.abs(math.cos(bobTime)) * 0.11 * amount, 0)
		bobOffset = bobOffset:Lerp(targetBob, math.min(1, dt * 12))
		hum.CameraOffset = bobOffset

		-- gentle roll from strafing and turning
		local look = cam.CFrame.LookVector
		if lastLook then
			local turn = lastLook:Cross(look).Y
			sway = sway + (math.clamp(turn * 40, -1, 1) - sway) * math.min(1, dt * 6)
		end
		lastLook = look
		local strafe = root.CFrame.RightVector:Dot(root.AssemblyLinearVelocity) / SPRINT
		local targetRoll = math.rad(-strafe * 1.4 - sway * 1.2 + math.sin(bobTime * 0.5) * 0.35 * amount)
		roll = roll + (targetRoll - roll) * math.min(1, dt * 8)
		cam.CFrame = cam.CFrame * CFrame.Angles(0, 0, roll)

	end)

	-- keep CameraMode in case something resets it on respawn
	player.CharacterAdded:Connect(function()
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		speed = 0
	end)
end

return FirstPerson
