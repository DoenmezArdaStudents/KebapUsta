-- Admin panel (only for players with the "Admin" attribute; the server re-checks every command).
-- Toggle: the ADMIN button top right or F6. Fly (F7) and noclip are local to the admin.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local State = require(script.Parent.State)
local FirstPerson = require(script.Parent.FirstPerson)

local AdminUI = {}
local lp = Players.LocalPlayer

local GOLD = Color3.fromRGB(240, 180, 60)
local BG = Color3.fromRGB(28, 24, 22)
local CARD = Color3.fromRGB(44, 38, 34)

local gui, panel, valueBox, targetBox, status
local flying, noclip = false, false
local flyConn, noclipConn, lv, ao

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = o
end

local function label(parent, text, size, color)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = size or 14
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Text = text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Size = UDim2.new(1, 0, 0, (size or 14) + 8)
	t.Parent = parent
	return t
end

local function setStatus(ok, msg)
	if status then
		status.Text = msg or ""
		status.TextColor3 = ok and Color3.fromRGB(140, 230, 140) or Color3.fromRGB(255, 130, 110)
	end
end

local function run(cmd, value)
	local res = State.Request("Admin", { cmd = cmd, value = value or valueBox.Text, target = targetBox.Text })
	setStatus(res and res.ok, res and res.msg or "Keine Antwort")
end

local function setFly(on)
	flying = on
	local char = lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local h = char and char:FindFirstChildOfClass("Humanoid")
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	if lv then
		lv.Attachment0:Destroy()
		lv:Destroy()
		ao:Destroy()
		lv, ao = nil, nil
	end
	if h then
		h.PlatformStand = false
	end
	if not (on and hrp and h) then
		flying = false
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = hrp
	lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hrp
	ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.Responsiveness = 40
	ao.Parent = hrp
	h.PlatformStand = true
	flyConn = RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		local dir = Vector3.zero
		if UIS:GetFocusedTextBox() == nil then
			local cf = cam.CFrame
			if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
			if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
		end
		local speed = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 120 or 50
		lv.VectorVelocity = dir.Magnitude > 0 and dir.Unit * speed or Vector3.zero
		local look = cam.CFrame.LookVector
		ao.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 1e-4))
	end)
end

local function setNoclip(on)
	noclip = on
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if on then
		noclipConn = RunService.Stepped:Connect(function()
			local char = lp.Character
			if char then
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") then
						p.CanCollide = false
					end
				end
			end
		end)
	end
end

local SECTIONS = {
	{ "💰 Spieler", {
		{ "Geld +", "money" }, { "Geld setzen", "setmoney" }, { "XP +", "xp" }, { "Level setzen", "level" },
		{ "Ruf setzen", "rep" }, { "Alles freischalten", "unlockall" }, { "Lager füllen", "fillstock" }, { "Speichern", "save" },
	} },
	{ "🕒 Spiel", {
		{ "Uhrzeit setzen", "time" }, { "Tag beenden", "skipday" }, { "Ausbaustufe", "stage" }, { "Alles putzen", "clean" },
		{ "Event starten (Wert = id / leer = zufällig)", "event" },
	} },
	{ "🧍 Kunden", {
		{ "Kunden spawnen", "spawn" }, { "VIP", "vip" }, { "Kritiker", "critic" }, { "Wütender Kunde", "angry" }, { "Alle weg", "clearcustomers" },
	} },
	{ "🏃 Bewegung", {
		{ "Speed", "speed" }, { "Sprungkraft", "jump" }, { "Heilen", "heal" }, { "Fliegen (F7)", "@fly" }, { "Noclip", "@noclip" },
		{ "TP zu Spieler", "tp" }, { "Spieler holen", "bring" },
	} },
	{ "🛡️ Server", {
		{ "Ansage (Wert = Text)", "announce" }, { "Kicken", "kick" },
	} },
}

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AdminUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = lp:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.fromOffset(84, 30)
	toggle.Position = UDim2.new(1, -96, 0, 64)
	toggle.BackgroundColor3 = GOLD
	toggle.Font = Enum.Font.GothamBlack
	toggle.TextSize = 14
	toggle.TextColor3 = BG
	toggle.Text = "🛡️ ADMIN"
	toggle.Parent = gui
	corner(toggle)

	panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(380, 520)
	panel.Position = UDim2.new(1, -396, 0, 102)
	panel.BackgroundColor3 = BG
	panel.Visible = false
	panel.Active = true
	panel.Draggable = true
	panel.Parent = gui
	corner(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = panel

	local head = label(panel, "  🛡️ Admin-Modus", 18, GOLD)
	head.Size = UDim2.new(1, 0, 0, 36)

	local function input(x, placeholder)
		local b = Instance.new("TextBox")
		b.Size = UDim2.new(0.5, -15, 0, 30)
		b.Position = UDim2.new(x, x == 0 and 10 or 5, 0, 38)
		b.BackgroundColor3 = CARD
		b.TextColor3 = Color3.new(1, 1, 1)
		b.PlaceholderText = placeholder
		b.PlaceholderColor3 = Color3.fromRGB(150, 140, 130)
		b.Font = Enum.Font.Gotham
		b.TextSize = 14
		b.Text = ""
		b.ClearTextOnFocus = false
		b.Parent = panel
		corner(b, 6)
		return b
	end
	valueBox = input(0, "Wert (z.B. 5000)")
	targetBox = input(0.5, "Spieler (leer = du)")

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -110)
	scroll.Position = UDim2.fromOffset(10, 76)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll

	for i, sec in ipairs(SECTIONS) do
		local t = label(scroll, sec[1], 15, GOLD)
		t.LayoutOrder = i * 2 - 1
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.Size = UDim2.new(1, -6, 0, 0)
		grid.LayoutOrder = i * 2
		grid.Parent = scroll
		local g = Instance.new("UIGridLayout")
		g.CellSize = UDim2.new(0.5, -4, 0, 32)
		g.CellPadding = UDim2.fromOffset(6, 6)
		g.SortOrder = Enum.SortOrder.LayoutOrder
		g.Parent = grid
		for j, b in ipairs(sec[2]) do
			local btn = Instance.new("TextButton")
			btn.LayoutOrder = j
			btn.BackgroundColor3 = CARD
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Font = Enum.Font.GothamMedium
			btn.TextSize = 13
			btn.Text = b[1]
			btn.Parent = grid
			corner(btn, 6)
			btn.MouseButton1Click:Connect(function()
				if b[2] == "@fly" then
					setFly(not flying)
					setStatus(true, flying and "Fliegen an (WASD, Leertaste/Strg, Shift = schnell)" or "Fliegen aus")
				elseif b[2] == "@noclip" then
					setNoclip(not noclip)
					setStatus(true, noclip and "Noclip an" or "Noclip aus")
				else
					run(b[2])
				end
			end)
		end
	end

	status = label(panel, "Chat: ;money 5000  ;speed 40  ;tp Name", 12, Color3.fromRGB(190, 180, 170))
	status.Size = UDim2.new(1, -20, 0, 28)
	status.Position = UDim2.new(0, 10, 1, -32)
	status.TextWrapped = true

	local function show(v)
		panel.Visible = v
		FirstPerson.SetMenuOpen(v)
	end
	toggle.MouseButton1Click:Connect(function()
		show(not panel.Visible)
	end)
	UIS.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F6 then
			show(not panel.Visible)
		elseif input.KeyCode == Enum.KeyCode.F7 then
			setFly(not flying)
		end
	end)
	lp.CharacterAdded:Connect(function()
		flying = false
		setNoclip(false)
	end)
end

function AdminUI.Init()
	if lp:GetAttribute("Admin") then
		build()
		return
	end
	local conn
	conn = lp:GetAttributeChangedSignal("Admin"):Connect(function()
		if lp:GetAttribute("Admin") and not gui then
			conn:Disconnect()
			build()
		end
	end)
end

return AdminUI
