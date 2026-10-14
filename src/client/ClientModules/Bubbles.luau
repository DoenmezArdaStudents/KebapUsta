-- Customer name tags, patience bars and speech bubbles (rendered locally in the player's language).

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local State = require(script.Parent.State)

local Bubbles = {}

local tags: { [Model]: { gui: BillboardGui, bar: Frame, fill: Frame, bubble: TextLabel, title: TextLabel, conns: { RBXScriptConnection }, hideAt: number } } = {}

local STATE_ICON = {
	Entering = "",
	Queuing = "⏳",
	Ordering = "💬",
	WaitingForFood = "🍽️",
	ReceivingFood = "😋",
	Eating = "🍴",
	Leaving = "👋",
	Cancelled = "😡",
}

local function patienceColor(f: number): Color3
	if f > 0.6 then
		return Color3.fromRGB(90, 210, 110)
	elseif f > 0.3 then
		return Color3.fromRGB(245, 190, 60)
	end
	return Color3.fromRGB(235, 70, 60)
end

local function create(model: Model)
	local head = model:WaitForChild("Head", 5) :: BasePart?
	if not head or tags[model] then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "KebapTag"
	gui.Adornee = head
	gui.Size = UDim2.new(0, 230, 0, 120)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local bubble = Instance.new("TextLabel")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.new(0.5, 0, 0.62, 0)
	bubble.Size = UDim2.new(1, 0, 0.62, 0)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 252, 245)
	bubble.TextColor3 = Color3.fromRGB(30, 26, 24)
	bubble.Font = Enum.Font.GothamMedium
	bubble.TextScaled = true
	bubble.TextWrapped = true
	bubble.Text = ""
	bubble.Visible = false
	bubble.Parent = gui
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 12)
	bc.Parent = bubble
	local bp = Instance.new("UIPadding")
	bp.PaddingLeft = UDim.new(0, 8)
	bp.PaddingRight = UDim.new(0, 8)
	bp.PaddingTop = UDim.new(0, 4)
	bp.PaddingBottom = UDim.new(0, 4)
	bp.Parent = bubble
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = bubble

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 0, 0.66, 0)
	title.Size = UDim2.new(1, 0, 0.2, 0)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.4
	title.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Patience"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0.88, 0)
	bar.Size = UDim2.new(0.5, 0, 0.08, 0)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local bcor = Instance.new("UICorner")
	bcor.CornerRadius = UDim.new(1, 0)
	bcor.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = patienceColor(1)
	fill.Parent = bar
	local fcor = bcor:Clone()
	fcor.Parent = fill

	gui.Parent = head
	local entry = { gui = gui, bar = bar, fill = fill, bubble = bubble, title = title, conns = {}, hideAt = 0 }
	tags[model] = entry

	local function refresh()
		local name = model:GetAttribute("CustomerName") or ""
		local emoji = model:GetAttribute("Emoji") or ""
		local st = model:GetAttribute("State") or ""
		local vip = model:GetAttribute("VIP") and "⭐ " or ""
		local aggressive = model:GetAttribute("Aggressive") == true
		title.Text = string.format("%s%s %s %s", vip, aggressive and "😡" or emoji, name, STATE_ICON[st] or "")
		title.TextColor3 = aggressive and Color3.fromRGB(255, 90, 80) or Color3.new(1, 1, 1)
		local p = model:GetAttribute("Patience") or 1
		local waiting = st == "Queuing" or st == "Ordering" or st == "WaitingForFood" or st == "Entering"
		bar.Visible = waiting
		fill.Size = UDim2.fromScale(math.clamp(p, 0, 1), 1)
		fill.BackgroundColor3 = patienceColor(p)
	end
	refresh()
	for _, attr in ipairs({ "Patience", "State", "CustomerName", "Aggressive" }) do
		table.insert(entry.conns, model:GetAttributeChangedSignal(attr):Connect(refresh))
	end
end

local function remove(model: Model)
	local e = tags[model]
	if e then
		for _, c in ipairs(e.conns) do
			c:Disconnect()
		end
		e.gui:Destroy()
		tags[model] = nil
	end
end

function Bubbles.Say(model: Instance, line, kind: string?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local e = tags[model]
	if not e then
		create(model)
		e = tags[model]
	end
	if not e or type(line) ~= "table" then
		return
	end
	local text = line[State.lang] or line.en or ""
	e.bubble.Text = text
	e.bubble.Visible = true
	e.bubble.Rotation = 0
	e.bubble.TextColor3 = Color3.fromRGB(30, 26, 24)
	if kind == "rant" then
		-- shouting: red bubble that shakes
		e.bubble.BackgroundColor3 = Color3.fromRGB(235, 60, 50)
		e.bubble.TextColor3 = Color3.new(1, 1, 1)
		task.spawn(function()
			for i = 1, 8 do
				e.bubble.Rotation = (i % 2 == 0 and 4 or -4) * (1 - i / 9)
				task.wait(0.04)
			end
			e.bubble.Rotation = 0
		end)
	elseif kind == "angry" or kind == "refuse" or kind == "impatient" or kind == "bad" then
		e.bubble.BackgroundColor3 = Color3.fromRGB(255, 225, 220)
	elseif kind == "happy" or kind == "tip" then
		e.bubble.BackgroundColor3 = Color3.fromRGB(225, 255, 228)
	else
		e.bubble.BackgroundColor3 = Color3.fromRGB(255, 252, 245)
	end
	e.bubble.Size = UDim2.new(1, 0, 0.0, 0)
	TweenService:Create(e.bubble, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.new(1, 0, 0.62, 0) }):Play()
	local duration = math.clamp(#text / 14, 3, 9)
	e.hideAt = os.clock() + duration
	task.delay(duration, function()
		if tags[model :: Model] == e and os.clock() >= e.hideAt - 0.05 then
			e.bubble.Visible = false
		end
	end)
end

function Bubbles.Init()
	for _, tag in ipairs({ "Customer" }) do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(m)
			task.spawn(create, m)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			task.spawn(create, m)
		end
	end
	State.Remote("Say").OnClientEvent:Connect(Bubbles.Say)
end

return Bubbles
