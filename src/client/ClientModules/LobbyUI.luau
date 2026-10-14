-- Lobby interface: cinematic camera over the kebab plaza, main menu (profile, Play Solo, create /
-- join a private lobby), lobby room with 4 player slots (avatar, name, level, ready, host crown,
-- friend invites), host-only Start button and a loading screen that also covers the teleport.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local SocialService = game:GetService("SocialService")

local State = require(script.Parent.State)
local Sound = require(script.Parent.Sound)
local Kit = require(script.Parent.UIKit)

local LobbyUI = {}

local player = Players.LocalPlayer
local new, corner, label, tween, pad, list = Kit.new, Kit.corner, Kit.label, Kit.tween, Kit.pad, Kit.list
local T, F = Kit.T, Kit.F
local GOLD = Color3.fromRGB(255, 196, 64)

local gui: ScreenGui
local refs: { [string]: any } = {}
local lobby: any = nil
local myReady = false

local MSG = {
	lobby_not_found = "Lobby nicht gefunden.",
	lobby_full = "Die Lobby ist voll (max. 4).",
	lobby_not_ready = "Noch nicht alle sind bereit.",
	lobby_no_slot = "Wähle zuerst einen Spielstand (oder erstelle einen neuen).",
	slot_delete_failed = "Löschen fehlgeschlagen – bitte später nochmal.",
}

local function toast(text: string)
	local t = refs.toast
	t.Text = text
	t.Visible = true
	t.TextTransparency = 0
	t.BackgroundTransparency = 0.15
	Kit.pop(t, 0.9, 0.25)
	task.delay(2.5, function()
		tween(t, 0.4, { TextTransparency = 1, BackgroundTransparency = 1 })
	end)
end

local function headshot(userId: number): string
	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	return ok and img or ""
end

local function bigButton(parent: Instance, order: number, text: string, color: Color3, onClick: () -> ()): TextButton
	return Kit.button({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = color, Font = F.black, TextSize = 20, Text = text, Radius = 12, Parent = parent }, onClick)
end

local function request(action: string, args: any?)
	local res = State.Request(action, args)
	if res and not res.ok and res.msg and MSG[res.msg] then
		toast(MSG[res.msg])
	end
	return res
end

---------------------------------------------------------------------------
-- loading screen (also handed to TeleportService so it stays up during the teleport)
---------------------------------------------------------------------------
local function buildLoading(): ScreenGui
	local lg = new("ScreenGui", { Name = "KebapLoading", IgnoreGuiInset = true, DisplayOrder = 100, ResetOnSpawn = false, Enabled = false })
	local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 12, 10), BorderSizePixel = 0, Parent = lg })
	Kit.gradient(Color3.fromRGB(70, 24, 16), Color3.fromRGB(14, 10, 10), 90).Parent = bg
	label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(160, 160), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 110, Text = "🥙", Name = "Icon", Parent = bg })
	label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromOffset(600, 50), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 44, TextColor3 = GOLD, Text = "KEBAP HAUS", Parent = bg })
	label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.65), Size = UDim2.fromOffset(600, 30), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 20, TextColor3 = T.dim, Text = "Restaurant wird vorbereitet …", Name = "Sub", Parent = bg })
	return lg
end

local loadingRun = 0
local function showLoading(on: boolean)
	local lg = refs.loading :: ScreenGui
	loadingRun += 1
	local run = loadingRun
	lg.Enabled = on
	if on then
		local icon = lg:FindFirstChild("Icon", true) :: TextLabel
		task.spawn(function()
			while run == loadingRun and lg.Enabled do
				tween(icon, 0.6, { Rotation = 12 }, Enum.EasingStyle.Sine)
				task.wait(0.6)
				tween(icon, 0.6, { Rotation = -12 }, Enum.EasingStyle.Sine)
				task.wait(0.6)
			end
		end)
		pcall(function()
			TeleportService:SetTeleportGui(lg:Clone())
		end)
	end
end

---------------------------------------------------------------------------
-- lobby room
---------------------------------------------------------------------------
local function renderLobby()
	local room = refs.room :: Frame
	refs.menu.Visible = lobby == nil
	room.Visible = lobby ~= nil
	if not lobby then
		return
	end
	refs.roomTitle.Text = "Lobby  #" .. lobby.code
	local slots = refs.slots :: Frame
	Kit.clear(slots, { "UIGridLayout" })
	local amHost, allReady = false, true
	for i = 1, lobby.max do
		local m = lobby.members[i]
		local c = Kit.glass({ LayoutOrder = i, BackgroundTransparency = 0.3, Parent = slots }, 14)
		if m then
			if m.userId == player.UserId and m.host then
				amHost = true
			end
			if not m.host and not m.ready then
				allReady = false
			end
			local img = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(84, 84), BackgroundColor3 = Color3.fromRGB(50, 44, 42), Image = "", Parent = c }, { Kit.round() })
			task.spawn(function()
				img.Image = headshot(m.userId)
			end)
			Kit.stroke(m.ready and T.green or (m.host and GOLD or Color3.fromRGB(90, 90, 96)), 0, 3).Parent = img
			if m.host then
				label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 30, 0, 18), Size = UDim2.fromOffset(30, 30), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 24, Text = "👑", Parent = c })
			end
			label({ Position = UDim2.fromOffset(6, 104), Size = UDim2.new(1, -12, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Font = F.bold, TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd, Text = m.name, Parent = c })
			label({ Position = UDim2.fromOffset(6, 126), Size = UDim2.new(1, -12, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, TextColor3 = T.dim, Text = "Level " .. m.level, Parent = c })
			local badge = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(110, 26), BackgroundColor3 = m.host and GOLD or (m.ready and T.green or Color3.fromRGB(70, 70, 76)), Parent = c }, { Kit.round() })
			label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 13, TextColor3 = Color3.fromRGB(20, 18, 16), Text = m.host and "HOST" or (m.ready and "BEREIT ✓" or "WARTET …"), Parent = badge })
			if m.userId == player.UserId then
				myReady = m.ready
			end
		else
			local b = Kit.button({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = F.bold, TextSize = 16, TextColor3 = T.dim, Text = "＋\nFreund einladen", Parent = c }, function()
				pcall(function()
					-- the lobby code travels with the invite: the friend lands directly in this lobby
					local opts = Instance.new("ExperienceInviteOptions")
					opts.LaunchData = lobby and lobby.code or ""
					opts.PromptMessage = "Komm in mein Kebap Haus!"
					SocialService:PromptGameInvite(player, opts)
				end)
			end)
			local _ = b
		end
		Kit.pop(c, 0.92, 0.25, i * 0.04)
	end
	refs.start.Visible = amHost
	refs.ready.Visible = not amHost
	refs.ready.Text = myReady and "✓ Bereit" or "Bereit?"
	refs.ready.BackgroundColor3 = myReady and T.green or Color3.fromRGB(70, 70, 80)
	local canStart = amHost and allReady and not lobby.starting
	refs.start.BackgroundColor3 = canStart and T.accent or Color3.fromRGB(70, 70, 80)
	refs.start.Text = lobby.starting and "Startet …" or (allReady and "▶ Spiel starten" or "Warte auf alle …")
	refs.roomSub.Text = string.format("%d / %d Spieler  ·  🏪 %s", #lobby.members, lobby.max, lobby.slotName or "Host wählt Spielstand …")
end

---------------------------------------------------------------------------
-- save slots: three restaurant cards (create / select / delete with confirmation)
---------------------------------------------------------------------------
local slotData: any = nil
local deleteArm: { [number]: number } = {}

local function fmtTime(sec: number): string
	sec = math.floor(sec or 0)
	local h, m = sec // 3600, (sec % 3600) // 60
	return h > 0 and string.format("%dh %02dm", h, m) or string.format("%d min", m)
end

local function refreshProfile()
	local r = State.Request("LobbyProfile")
	if r and r.ok and refs.profile then
		refs.profile.Text = r.name and string.format("%s\nLevel %d  ·  €%.2f  ·  Tag %d", r.name, r.level, r.cash, r.day) or "Kein Spielstand gewählt"
	end
end

local renderSlots
local function applySlots(r: any)
	if r and r.ok then
		slotData = r
		renderSlots()
		refreshProfile()
	end
end

renderSlots = function()
	local box = refs.slotCards :: Frame
	if not box or not slotData then
		return
	end
	Kit.clear(box, { "UIGridLayout" })
	for i = 1, #slotData.slots do
		local s = slotData.slots[i]
		local sel = slotData.selected == i
		local c = Kit.glass({ LayoutOrder = i, BackgroundTransparency = sel and 0.05 or 0.3, Parent = box }, 12)
		Kit.stroke(sel and GOLD or Color3.fromRGB(80, 80, 88), 0, sel and 3 or 1).Parent = c
		if s.exists then
			local click = Kit.button({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = c }, function()
				applySlots(request("SlotSelect", i))
			end)
			local _ = click
			label({ Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -40, 0, 18), Font = F.bold, TextSize = 12, TextColor3 = sel and GOLD or T.dim, Text = "SPIELSTAND " .. i .. (sel and "  ✓" or ""), Parent = c })
			label({ Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 38), Font = F.black, TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = s.name or ("Kebap Haus " .. i), Parent = c })
			label({ Position = UDim2.fromOffset(10, 66), Size = UDim2.new(1, -20, 0, 18), Font = F.bold, TextSize = 14, TextColor3 = T.green, Text = string.format("€%.0f", s.cash or 0), Parent = c })
			label({ Position = UDim2.fromOffset(10, 84), Size = UDim2.new(1, -20, 0, 16), TextSize = 12, TextColor3 = T.text, Text = string.format("Level %d · Tag %d", s.level or 1, s.day or 1), Parent = c })
			label({ Position = UDim2.fromOffset(10, 102), Size = UDim2.new(1, -20, 0, 16), TextSize = 11, TextColor3 = T.dim, Text = "⏱ " .. fmtTime(s.playtime or 0) .. (s.last and ("  ·  " .. os.date("%d.%m.%y", s.last)) or ""), Parent = c })
			local armed = deleteArm[i] and os.clock() - deleteArm[i] < 12
			Kit.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(armed and 64 or 26, 24), BackgroundColor3 = armed and Color3.fromRGB(200, 50, 40) or Color3.fromRGB(60, 56, 60), Font = F.bold, TextSize = 12, Text = armed and "Löschen!" or "🗑", Radius = 6, Parent = c }, function()
				if armed then
					deleteArm[i] = nil
					local r = request("SlotDelete", { slot = i, confirm = true })
					if r and r.ok then
						toast("Spielstand " .. i .. " gelöscht.")
					end
					applySlots(r)
				else
					local r = request("SlotDelete", { slot = i })
					if r and r.confirm then
						deleteArm[i] = os.clock()
						toast("Nochmal tippen, um Spielstand " .. i .. " endgültig zu löschen.")
						renderSlots()
						task.delay(12, renderSlots)
					end
				end
			end)
		else
			Kit.button({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = F.bold, TextSize = 15, TextColor3 = T.dim, Text = "＋\nNeuer\nSpielstand", Parent = c }, function()
				applySlots(request("SlotCreate", i))
			end)
		end
	end
end

---------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------
local function build()
	gui = new("ScreenGui", { Name = "KebapLobby", IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	new("UIScale", { Name = "Scale", Parent = gui })
	-- vignette
	local vig = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, Parent = gui })
	new("UIGradient", { Rotation = 0, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.45, 0.85), NumberSequenceKeypoint.new(1, 1) }), Parent = vig })

	-- left: logo + menu / room
	local side = new("Frame", { Name = "Side", Position = UDim2.new(0, -460, 0, 0), Size = UDim2.new(0, 440, 1, 0), BackgroundTransparency = 1, Parent = gui })
	pad(36, 40, 0, 30).Parent = side
	label({ Size = UDim2.new(1, 0, 0, 70), Font = F.black, TextSize = 62, TextColor3 = GOLD, Text = "KEBAP HAUS", TextStrokeTransparency = 0.6, Parent = side })
	label({ Position = UDim2.fromOffset(4, 66), Size = UDim2.new(1, 0, 0, 26), Font = F.bold, TextSize = 22, TextColor3 = T.text, Text = "🥙  Realistic Kebap Simulator", Parent = side })

	-- profile card
	local prof = Kit.glass({ Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, -20, 0, 92), Parent = side }, 14)
	local av = new("ImageLabel", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(68, 68), BackgroundColor3 = Color3.fromRGB(50, 44, 42), Parent = prof }, { Kit.round() })
	task.spawn(function()
		av.Image = headshot(player.UserId)
	end)
	label({ Position = UDim2.fromOffset(94, 14), Size = UDim2.new(1, -104, 0, 26), Font = F.black, TextSize = 22, Text = player.DisplayName, TextTruncate = Enum.TextTruncate.AtEnd, Parent = prof })
	refs.profile = label({ Position = UDim2.fromOffset(94, 46), Size = UDim2.new(1, -104, 0, 34), TextSize = 15, TextColor3 = T.dim, TextWrapped = true, Text = "Lade Spielstand …", Parent = prof })

	-- main menu
	local slotBox = new("Frame", { Name = "SlotCards", Position = UDim2.fromOffset(0, 216), Size = UDim2.new(1, -20, 0, 128), BackgroundTransparency = 1, Parent = side })
	new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 1, 0), CellPadding = UDim2.fromOffset(9, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = slotBox })
	refs.slotCards = slotBox
	local menu = new("Frame", { Name = "Menu", Position = UDim2.fromOffset(0, 360), Size = UDim2.new(1, -20, 0, 300), BackgroundTransparency = 1, Parent = side })
	list(false, 12).Parent = menu
	refs.menu = menu
	bigButton(menu, 1, "▶  Solo spielen", T.accent, function()
		request("PlaySolo")
	end)
	bigButton(menu, 2, "👥  Private Lobby erstellen", Color3.fromRGB(70, 110, 200), function()
		request("LobbyCreate")
	end)
	local joinRow = new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = menu })
	local box = new("TextBox", { Size = UDim2.new(1, -150, 1, 0), BackgroundColor3 = Color3.fromRGB(30, 28, 30), BackgroundTransparency = 0.15, Font = F.bold, TextSize = 22, TextColor3 = T.text, PlaceholderText = "Lobby-Code", PlaceholderColor3 = T.dim, Text = "", ClearTextOnFocus = false, Parent = joinRow }, { corner(12) })
	Kit.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 140, 1, 0), BackgroundColor3 = Color3.fromRGB(60, 60, 70), Font = F.black, TextSize = 18, Text = "Beitreten", Radius = 12, Parent = joinRow }, function()
		request("LobbyJoin", (box.Text:gsub("%D", "")))
	end)
	label({ LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 40), TextSize = 14, TextColor3 = T.dim, TextWrapped = true, Text = "Bis zu 4 Spieler führen gemeinsam das Restaurant des Hosts. Dein Fortschritt wird automatisch gespeichert.", Parent = menu })

	-- lobby room
	local room = new("Frame", { Name = "Room", Position = UDim2.fromOffset(0, 360), Size = UDim2.new(0, 560, 0, 420), BackgroundTransparency = 1, Visible = false, Parent = side })
	refs.room = room
	refs.roomTitle = label({ Size = UDim2.new(1, 0, 0, 36), Font = F.black, TextSize = 30, Text = "", Parent = room })
	refs.roomSub = label({ Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = T.dim, Text = "", Parent = room })
	local slots = new("Frame", { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 200), BackgroundTransparency = 1, Parent = room })
	new("UIGridLayout", { CellSize = UDim2.new(0.25, -9, 1, 0), CellPadding = UDim2.fromOffset(12, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = slots })
	refs.slots = slots
	local row = new("Frame", { Position = UDim2.fromOffset(0, 284), Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = room })
	refs.start = Kit.button({ Size = UDim2.new(0.62, -6, 1, 0), BackgroundColor3 = T.accent, Font = F.black, TextSize = 20, Text = "▶ Spiel starten", Radius = 12, Parent = row }, function()
		request("LobbyStart")
	end)
	refs.ready = Kit.button({ Size = UDim2.new(0.62, -6, 1, 0), BackgroundColor3 = Color3.fromRGB(70, 70, 80), Font = F.black, TextSize = 20, Text = "Bereit?", Radius = 12, Parent = row }, function()
		request("LobbyReady", not myReady)
	end)
	Kit.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, -6, 1, 0), BackgroundColor3 = Color3.fromRGB(60, 60, 70), Font = F.bold, TextSize = 18, Text = "Verlassen", Radius = 12, Parent = row }, function()
		request("LobbyLeave")
	end)

	refs.toast = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(420, 44), TextXAlignment = Enum.TextXAlignment.Center, BackgroundColor3 = Color3.fromRGB(30, 26, 26), BackgroundTransparency = 1, Font = F.bold, TextSize = 18, Text = "", Visible = false, Parent = gui })
	corner(12).Parent = refs.toast
	refs.side = side
	refs.loading = buildLoading()
	refs.loading.Parent = player.PlayerGui
end

-- slow cinematic drift over the square, looking at the shop front (the menu sits on the left)
local function camera()
	local lobbyModel = workspace:WaitForChild("Lobby", 10)
	local cam = workspace.CurrentCamera
	if not lobbyModel or not cam then
		return
	end
	local origin = Vector3.new(0, 0, -420)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 62
	RunService:BindToRenderStep("KebapLobbyCam", Enum.RenderPriority.Camera.Value + 30, function()
		cam.CameraType = Enum.CameraType.Scriptable
		local t = os.clock() * 0.11
		local eye = origin + Vector3.new(4 + math.sin(t) * 8, 9 + math.sin(t * 0.7) * 1.2, 28 + math.cos(t * 0.8) * 3)
		local look = origin + Vector3.new(-6 + math.sin(t) * 3, 8, -20)
		cam.CFrame = CFrame.lookAt(eye, look)
	end)
end

function LobbyUI.Init()
	player.CameraMode = Enum.CameraMode.Classic
	build()
	camera()
	tween(refs.side, 0.8, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	State.Remote("LobbyState").OnClientEvent:Connect(function(s)
		lobby = s
		Sound.Play("click")
		renderLobby()
	end)
	State.Remote("LobbyLoading").OnClientEvent:Connect(showLoading)
	State.Remote("Notify").OnClientEvent:Connect(function(key)
		if key == "lobby_tp_failed" then
			toast("Teleport fehlgeschlagen – bitte nochmal versuchen.")
		end
	end)
	task.spawn(function()
		for _ = 1, 20 do
			local r = State.Request("SlotList")
			if r and r.ok then
				applySlots(r)
				return
			end
			task.wait(1)
		end
	end)
end

-- the game started (Studio in-place session): fade the lobby away
function LobbyUI.Close()
	RunService:UnbindFromRenderStep("KebapLobbyCam")
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	workspace.CurrentCamera.FieldOfView = 70
	if gui then
		gui:Destroy()
	end
	task.delay(1.5, function()
		if refs.loading then
			refs.loading.Enabled = false
		end
	end)
end

return LobbyUI
