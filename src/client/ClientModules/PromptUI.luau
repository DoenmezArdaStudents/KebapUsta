-- Custom look for all ProximityPrompts. The UI never captures the mouse (no clickable button on
-- PC), so the first-person camera keeps turning while a prompt is on screen. On touch devices the
-- key badge becomes a tap button that drives the prompt (incl. hold prompts).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PromptUI = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(244, 192, 72)
local BG = Color3.fromRGB(26, 22, 20)

local PAD_NAMES = {
	ButtonX = "X", ButtonY = "Y", ButtonA = "A", ButtonB = "B", ButtonL1 = "LB", ButtonR1 = "RB",
}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return PAD_NAMES[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "👆"
	end
	local name = prompt.KeyboardKeyCode.Name
	return #name <= 2 and name or string.sub(name, 1, 3)
end

local function create(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local adornee = prompt.Parent
	if not adornee or not (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model")) then
		return
	end
	local touch = inputType == Enum.ProximityPromptInputType.Touch

	local gui = Instance.new("BillboardGui")
	gui.Name = "KebapPrompt"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(250, 58)
	gui.Adornee = adornee
	gui.ResetOnSpawn = false
	gui.Active = touch
	gui.ClipsDescendants = false
	-- stack multiple prompts on one object (board: close/pack + plate; customer above head)
	local oy = prompt.UIOffset.Y
	gui.SizeOffset = Vector2.new(0, oy > 0 and -1.15 or (oy < 0 and 0.6 or 0))

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = holder

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.new(1, 0, 1, 0)
	pill.BackgroundColor3 = BG
	pill.BackgroundTransparency = 0.12
	pill.BorderSizePixel = 0
	pill.Active = false
	pill.Parent = holder
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 14)
	pc.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Transparency = 0.45
	stroke.Thickness = 1.5
	stroke.Parent = pill

	-- key badge (a real button only on touch devices)
	local badge: GuiObject
	if touch then
		local b = Instance.new("TextButton")
		b.AutoButtonColor = true
		badge = b
	else
		local l = Instance.new("TextLabel")
		l.Active = false
		badge = l
	end
	badge.Name = "Key"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 9, 0.5, 0)
	badge.Size = UDim2.fromOffset(40, 40)
	badge.BackgroundColor3 = GOLD
	badge.BorderSizePixel = 0
	local bt = badge :: any
	bt.Text = keyText(prompt, inputType)
	bt.TextColor3 = Color3.fromRGB(30, 22, 12)
	bt.Font = Enum.Font.GothamBlack
	bt.TextSize = 20
	badge.Parent = pill
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 10)
	bc.Parent = badge

	-- hold progress ring substitute: a bar along the bottom of the pill
	local barBg = Instance.new("Frame")
	barBg.Name = "HoldBar"
	barBg.AnchorPoint = Vector2.new(0, 1)
	barBg.Position = UDim2.new(0, 58, 1, -7)
	barBg.Size = UDim2.new(1, -70, 0, 4)
	barBg.BackgroundColor3 = Color3.fromRGB(70, 60, 50)
	barBg.BorderSizePixel = 0
	barBg.Visible = prompt.HoldDuration > 0
	barBg.Parent = pill
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	for _, f in ipairs({ barBg, fill }) do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end

	local action = Instance.new("TextLabel")
	action.Name = "Action"
	action.BackgroundTransparency = 1
	action.Position = UDim2.new(0, 58, 0, 7)
	action.Size = UDim2.new(1, -66, 0, 24)
	action.Font = Enum.Font.GothamBold
	action.TextSize = 19
	action.TextColor3 = Color3.fromRGB(252, 246, 236)
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextTruncate = Enum.TextTruncate.AtEnd
	action.Parent = pill
	local object = action:Clone()
	object.Name = "Object"
	object.Position = UDim2.new(0, 58, 0, 30)
	object.Size = UDim2.new(1, -66, 0, 18)
	object.Font = Enum.Font.GothamMedium
	object.TextSize = 14
	object.TextColor3 = Color3.fromRGB(205, 192, 178)
	object.Parent = pill

	local function refresh()
		action.Text = prompt.ActionText
		object.Text = prompt.ObjectText
		object.Visible = prompt.ObjectText ~= ""
		action.Position = prompt.ObjectText ~= "" and UDim2.new(0, 58, 0, 7) or UDim2.new(0, 58, 0, 16)
		barBg.Visible = prompt.HoldDuration > 0
		-- size to text
		local w = math.max(action.TextBounds.X, object.TextBounds.X)
		gui.Size = UDim2.fromOffset(math.clamp(w + 80, 150, 330), 58)
	end
	refresh()

	local conns = {}
	for _, prop in ipairs({ "ActionText", "ObjectText", "HoldDuration" }) do
		table.insert(conns, prompt:GetPropertyChangedSignal(prop):Connect(refresh))
	end
	local holdTween: Tween?
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		fill.Size = UDim2.fromScale(0, 1)
		holdTween = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		;(holdTween :: Tween):Play()
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		if holdTween then
			holdTween:Cancel()
		end
		fill.Size = UDim2.fromScale(0, 1)
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
		task.delay(0.08, function()
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
	end))
	if touch then
		local b = badge :: TextButton
		table.insert(conns, b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end))
		table.insert(conns, b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end))
	end

	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local hiddenConn
	hiddenConn = prompt.PromptHidden:Connect(function()
		hiddenConn:Disconnect()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		gui:Destroy()
	end)
end

function PromptUI.Init()
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			create(prompt, inputType)
		end
	end)
	local _ = UserInputService
end

return PromptUI
