-- Delivery tracker (bottom left) and a carry hint while a box is in your hands.
local Players = game:GetService("Players")
local State = require(script.Parent.State)
local IngredientData = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IngredientData"))

local LogisticsUI = {}
local lp = Players.LocalPlayer

local function new(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	return o
end

function LogisticsUI.Init()
	local gui = new("ScreenGui", { Name = "LogisticsUI", ResetOnSpawn = false, DisplayOrder = 5, Parent = lp:WaitForChild("PlayerGui") })
	local box = new("Frame", { Size = UDim2.fromOffset(250, 40), Position = UDim2.new(0, 12, 1, -12), AnchorPoint = Vector2.new(0, 1), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(28, 24, 22), BackgroundTransparency = 0.15, Parent = gui })
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = box })
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = box })
	local text = new("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, RichText = true, Text = "", Parent = box })
	local hint = new("TextLabel", { Size = UDim2.fromOffset(520, 34), Position = UDim2.new(0.5, 0, 1, -110), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Color3.fromRGB(240, 180, 60), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(28, 24, 22), Visible = false, Parent = gui })
	new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = hint })

	local function name(id)
		local d = IngredientData.Stock[id]
		return d and d.name.de:gsub(" %(Portion%)", "") or id
	end
	local function update()
		local l = State.player and State.player.logi
		if not l then
			box.Visible = false
			return
		end
		local lines = { "<b>🚚 Lieferungen</b>" }
		local now = workspace:GetServerTimeNow()
		for i, o in ipairs(l.orders) do
			if i > 5 then
				table.insert(lines, ("  … +%d weitere"):format(#l.orders - 5))
				break
			end
			local s = math.max(0, math.floor((o.due or 0) - now))
			table.insert(lines, ("  %s ×%d – %s"):format(name(o.id), o.n, s > 0 and ("%d:%02d"):format(s // 60, s % 60) or "kommt gleich"))
		end
		if #l.orders == 0 then
			table.insert(lines, l.van and "  Lieferwagen lädt ab …" or "  <font color='#aaa'>keine offen</font>")
		end
		if l.out > 0 then
			table.insert(lines, ("<font color='#f0c040'>📦 %d Kiste(n) in der Lieferzone</font>"):format(l.out))
		end
		table.insert(lines, ("🏬 Lager: %d / %d Plätze"):format(l.shelf, l.slots))
		text.Text = table.concat(lines, "\n")
		box.Visible = true
	end
	local function updateHint()
		local c = lp:GetAttribute("Carry")
		hint.Visible = c ~= nil
		if c then
			local d = IngredientData.Stock[c]
			hint.Text = d and d.meat and ("📦 %s – ab in den Kühlraum"):format(name(c)) or ("📦 %s – ins Lagerregal oder zur passenden Station"):format(name(c))
		end
	end
	State.Changed:Connect(function(what)
		if what == "player" then
			update()
		end
	end)
	lp:GetAttributeChangedSignal("Carry"):Connect(function()
		updateHint()
		State.Fire("player")
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			update()
		end
	end)
	update()
	updateHint()
	-- two-handed carry pose for every player holding a box (joints' Transform, like the cutting pose)
	local POSE = { RightShoulder = { "RightUpperArm", 1.3, 0, -0.18 }, LeftShoulder = { "LeftUpperArm", 1.3, 0, 0.18 }, RightElbow = { "RightLowerArm", 0.55, 0, 0 }, LeftElbow = { "LeftLowerArm", 0.55, 0, 0 }, Waist = { "UpperTorso", -0.08, 0, 0 } }
	local weights: { [Model]: number } = {}
	game:GetService("RunService").PreSimulation:Connect(function(dt)
		for _, pl in ipairs(Players:GetPlayers()) do
			local char = pl.Character
			if not char then
				continue
			end
			local on = pl:GetAttribute("Carry") ~= nil
			local w = math.clamp((weights[char] or 0) + (on and dt * 6 or -dt * 6), 0, 1)
			weights[char] = w > 0 and w or nil
			if w <= 0 then
				continue
			end
			for joint, d in pairs(POSE) do
				local part = char:FindFirstChild(d[1])
				local m = part and part:FindFirstChild(joint)
				if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then
					local target = CFrame.Angles(d[2], d[3], d[4])
					;(m :: any).Transform = w >= 1 and target or (m :: any).Transform:Lerp(target, w)
				end
			end
		end
	end)
end

return LogisticsUI
