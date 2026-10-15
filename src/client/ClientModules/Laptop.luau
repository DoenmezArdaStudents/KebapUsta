-- The order laptop: a realistic little operating system ("KebabOS") that opens when you use the
-- laptop at the counter. Lid-opening animation, boot + lock screen, desktop with icons, taskbar with
-- start menu (search), Wi-Fi / volume / battery / clock tray, quick settings (brightness, dark mode,
-- do-not-disturb), notification centre with calendar, movable / minimisable / maximisable windows,
-- and apps: Kassa (orders), Lieferant (stock), Shop-Ausbau (upgrades), Statistik, Einstellungen,
-- Rechner and Notizen. The physical laptop's screen in the world shows a live mini dashboard.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local Progression = require(Shared.Progression)
local Business = require(Shared.Business)
local Localization = require(Shared.Localization)
local State = require(script.Parent.State)
local Sound = require(script.Parent.Sound)
local Kit = require(script.Parent.UIKit)
local OrderText = require(script.Parent.OrderText)

local Laptop = {}
Laptop.OnOpenChanged = function(_open: boolean) end

local player = Players.LocalPlayer
local new, corner, round, stroke, pad, list, label, tween = Kit.new, Kit.corner, Kit.round, Kit.stroke, Kit.pad, Kit.list, Kit.label, Kit.tween
local F = Kit.F

local W, H = 1280, 790 -- screen resolution (design units)
local TASKBAR = 52

local ACCENT = Color3.fromRGB(232, 72, 48)
local BLUE = Color3.fromRGB(0, 120, 215)
local THEMES = {
	light = {
		win = Color3.fromRGB(243, 244, 247),
		card = Color3.fromRGB(255, 255, 255),
		line = Color3.fromRGB(222, 225, 232),
		text = Color3.fromRGB(26, 28, 34),
		dim = Color3.fromRGB(108, 114, 126),
		title = Color3.fromRGB(232, 234, 240),
		bar = Color3.fromRGB(238, 240, 245),
		hover = Color3.fromRGB(225, 228, 236),
		input = Color3.fromRGB(250, 250, 252),
	},
	dark = {
		win = Color3.fromRGB(32, 33, 38),
		card = Color3.fromRGB(44, 46, 53),
		line = Color3.fromRGB(62, 64, 74),
		text = Color3.fromRGB(240, 241, 245),
		dim = Color3.fromRGB(160, 164, 178),
		title = Color3.fromRGB(24, 25, 29),
		bar = Color3.fromRGB(26, 27, 32),
		hover = Color3.fromRGB(58, 60, 70),
		input = Color3.fromRGB(36, 38, 44),
	},
}
local WALLPAPERS = {
	{ Color3.fromRGB(255, 120, 72), Color3.fromRGB(150, 40, 110), Color3.fromRGB(40, 30, 90) }, -- Abendrot
	{ Color3.fromRGB(40, 170, 220), Color3.fromRGB(30, 80, 190), Color3.fromRGB(16, 22, 70) }, -- Donau
	{ Color3.fromRGB(80, 200, 140), Color3.fromRGB(20, 110, 110), Color3.fromRGB(10, 40, 50) }, -- Prater
	{ Color3.fromRGB(70, 70, 80), Color3.fromRGB(30, 30, 38), Color3.fromRGB(10, 10, 14) }, -- Graphit
}

-- OS state (session only)
local OS = {
	open = false,
	animating = false,
	booted = false,
	locked = true,
	wifi = true,
	dark = false,
	dnd = false,
	brightness = 1,
	wallpaper = 1,
	battery = 87,
	notes = "",
	notifications = {} :: { any },
	unread = 0,
	chat = {} :: { any },
	posTicket = nil :: number?,
	upTab = "unlocks",
	bizTab = "stages",
	confirmFire = nil :: string?,
}

local function C()
	return OS.dark and THEMES.dark or THEMES.light
end

local function tr(de: string, en: string): string
	return State.lang == "de" and de or en
end

local function money(n: number?): string
	return Localization.Money(n or 0)
end

local function clockText(): string
	local h = (State.shop and State.shop.clock) or 10
	local hh = math.floor(h)
	local mm = math.floor((h - hh) * 60)
	return string.format("%02d:%02d", hh % 24, mm)
end

local WEEKDAYS = {
	de = { "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" },
	en = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" },
}
local MONTHS = {
	de = { "Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" },
	en = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" },
}

local function dateText(): string
	local t = os.date("*t") :: any
	local lang = State.lang == "de" and "de" or "en"
	return string.format("%s, %d. %s", WEEKDAYS[lang][t.wday], t.day, MONTHS[lang][t.month])
end

-- references
local gui: ScreenGui
local backdrop: any
local holder: Frame
local holderScale: UIScale
local lid: Frame
local screen: Frame
local powerOverlay: Frame
local brightOverlay: Frame
local desktop: Frame
local winLayer: Frame
local taskbar: Frame
local popLayer: Frame
local toastLayer: Frame
local lockScreen: any
local blur: BlurEffect?
local refs: { [string]: any } = {}
local themed: { { obj: Instance, prop: string, key: string } } = {}
local wallpaperFrames: { Frame } = {}

local function theme(obj: Instance, prop: string, key: string)
	if #themed > 400 then
		local keep = {}
		for _, t in ipairs(themed) do
			if t.obj.Parent then
				table.insert(keep, t)
			end
		end
		themed = keep
	end
	table.insert(themed, { obj = obj, prop = prop, key = key })
	;(obj :: any)[prop] = (C() :: any)[key]
	return obj
end

---------------------------------------------------------------------------
-- small components
---------------------------------------------------------------------------
local function mouse(): Vector2
	return UserInputService:GetMouseLocation()
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function textBtn(props: { [string]: any }, onClick: () -> ()): TextButton
	props.BackgroundColor3 = props.BackgroundColor3 or C().card
	props.TextColor3 = props.TextColor3 or C().text
	props.Font = props.Font or F.bold
	props.TextSize = props.TextSize or 15
	return Kit.button(props, onClick)
end

-- slider 0..1. onChange(value, final)
local function slider(parent: Instance, props: { [string]: any }, value: number, color: Color3, onChange: (number, boolean) -> ())
	props.BackgroundTransparency = 1
	props.Parent = parent
	local hit = new("TextButton", props)
	hit.Text = ""
	hit.AutoButtonColor = false
	local track = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C().line, BorderSizePixel = 0, Parent = hit }, { round() })
	local fill = new("Frame", { Size = UDim2.fromScale(value, 1), BackgroundColor3 = color, BorderSizePixel = 0, Parent = track }, { round() })
	local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(value, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track }, { round(), stroke(Color3.new(0, 0, 0), 0.8, 1) })
	local dragging = false
	local v = value
	local function setFrom(x: number, final: boolean)
		local a = track.AbsolutePosition.X
		local w = math.max(track.AbsoluteSize.X, 1)
		v = math.clamp((x - a) / w, 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
		onChange(v, final)
	end
	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			tween(knob, 0.12, { Size = UDim2.fromOffset(22, 22) })
			setFrom(mouse().X, false)
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFrom(mouse().X, false)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if dragging and isPress(input) then
			dragging = false
			tween(knob, 0.15, { Size = UDim2.fromOffset(18, 18) })
			onChange(v, true)
		end
	end)
	hit.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
	return hit
end

local function switch(parent: Instance, props: { [string]: any }, on: boolean, onToggle: (boolean) -> ())
	props.Size = props.Size or UDim2.fromOffset(46, 24)
	props.BackgroundColor3 = on and BLUE or C().line
	props.Text = ""
	props.AutoButtonColor = false
	props.Parent = parent
	local b = new("TextButton", props, { round() })
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = b }, { round() })
	local state = on
	b.Activated:Connect(function()
		state = not state
		Sound.Play("click")
		tween(knob, 0.2, { Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
		tween(b, 0.2, { BackgroundColor3 = state and BLUE or C().line })
		onToggle(state)
	end)
	return b
end

local function wallpaper(parent: Instance, z: number?): Frame
	local cols = WALLPAPERS[OS.wallpaper]
	local f = new("Frame", { Name = "Wallpaper", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z or 0, Parent = parent })
	new("UIGradient", { Name = "G", Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, cols[1]), ColorSequenceKeypoint.new(0.55, cols[2]), ColorSequenceKeypoint.new(1, cols[3]) }), Rotation = 35, Parent = f })
	-- soft drifting light blobs
	for i = 1, 3 do
		local blob = new("Frame", {
			Name = "Blob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.2 + i * 0.22, 0.3 + (i % 2) * 0.35),
			Size = UDim2.fromOffset(420 + i * 60, 420 + i * 60),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Parent = f,
		}, { round() })
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }), Parent = blob })
		blob:SetAttribute("Seed", i)
	end
	table.insert(wallpaperFrames, f)
	return f
end

local function applyWallpaper()
	local cols = WALLPAPERS[OS.wallpaper]
	for _, f in ipairs(wallpaperFrames) do
		if f.Parent then
			local g = f:FindFirstChild("G") :: UIGradient
			g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, cols[1]), ColorSequenceKeypoint.new(0.55, cols[2]), ColorSequenceKeypoint.new(1, cols[3]) })
		end
	end
end

---------------------------------------------------------------------------
-- notifications (toasts inside the laptop + notification centre)
---------------------------------------------------------------------------
local renderNotifCenter: () -> ()
local updateTray: () -> ()

function Laptop.Notify(title: string, text: string?, icon: string?, onClick: (() -> ())?)
	table.insert(OS.notifications, 1, { title = title, text = text or "", icon = icon or "🔔", time = clockText(), onClick = onClick })
	while #OS.notifications > 30 do
		table.remove(OS.notifications)
	end
	if not OS.open or OS.locked then
		OS.unread += 1
	end
	if updateTray then
		updateTray()
	end
	if renderNotifCenter and refs.notifOpen then
		renderNotifCenter()
	end
	if not OS.open or OS.dnd or not toastLayer then
		return
	end
	local card = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = toastLayer,
	})
	local inner = new("Frame", { Position = UDim2.fromOffset(380, 0), Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = card }, { corner(12), stroke(Color3.new(0, 0, 0), 0.85) })
	theme(inner, "BackgroundColor3", "card")
	label({ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 40, 1, 0), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Text = icon or "🔔", Parent = inner })
	label({ Position = UDim2.fromOffset(62, 12), Size = UDim2.new(1, -74, 0, 22), Font = F.bold, TextSize = 16, TextColor3 = C().text, TextTruncate = Enum.TextTruncate.AtEnd, Text = title, Parent = inner })
	label({ Position = UDim2.fromOffset(62, 36), Size = UDim2.new(1, -74, 0, 30), TextSize = 14, TextColor3 = C().dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = text or "", Parent = inner })
	tween(inner, 0.45, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	Sound.Play("toast")
	local gone = false
	local function dismiss()
		if gone then
			return
		end
		gone = true
		tween(inner, 0.35, { Position = UDim2.fromOffset(380, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.36, function()
			card:Destroy()
		end)
	end
	card.Activated:Connect(function()
		if onClick then
			onClick()
		end
		dismiss()
	end)
	task.delay(4.5, dismiss)
end

---------------------------------------------------------------------------
-- window manager
---------------------------------------------------------------------------
type App = { title: { de: string, en: string }, icon: string, size: Vector2, render: (Frame, any) -> (), live: { [string]: boolean }? }
local APPS: { [string]: App } = {}
local APP_ORDER = { "pos", "supplier", "upgrades", "business", "reviews", "stats", "settings", "calc", "notes" }

type Win = { id: string, frame: CanvasGroup, body: Frame, titleLabel: TextLabel, maximized: boolean, minimized: boolean, restore: { pos: UDim2, size: UDim2 }?, state: { [string]: any } }
local windows: { [string]: Win } = {}
local focused: string? = nil
local zTop = 10
local openCount = 0
local updateTaskbar: () -> ()

local function renderWin(win: Win)
	local app = APPS[win.id]
	win.titleLabel.Text = app.title[State.lang] or app.title.en
	local scrolls = {}
	for _, d in ipairs(win.body:GetDescendants()) do
		if d:IsA("ScrollingFrame") then
			scrolls[d.Name] = d.CanvasPosition
		end
	end
	Kit.clear(win.body)
	app.render(win.body, win)
	-- keep scroll positions across live re-renders
	for _, d in ipairs(win.body:GetDescendants()) do
		if d:IsA("ScrollingFrame") and scrolls[d.Name] then
			d.CanvasPosition = scrolls[d.Name]
		end
	end
end

local function focusWin(id: string?)
	focused = id
	if id and windows[id] then
		zTop += 1
		windows[id].frame.ZIndex = zTop
	end
	for wid, w in pairs(windows) do
		local bar = w.frame:FindFirstChild("TitleBar") :: Frame
		if bar then
			tween(bar, 0.15, { BackgroundColor3 = wid == id and C().title or C().win })
		end
	end
	if updateTaskbar then
		updateTaskbar()
	end
end

local function taskButtonPos(id: string): UDim2
	local b = refs.taskButtons and refs.taskButtons[id]
	if b then
		local screenPos = screen.AbsolutePosition
		local s = holderScale.Scale
		local p = (b.AbsolutePosition + b.AbsoluteSize / 2 - screenPos) / s
		return UDim2.fromOffset(p.X, p.Y)
	end
	return UDim2.fromOffset(W / 2, H)
end

local function closeWin(id: string)
	local w = windows[id]
	if not w then
		return
	end
	windows[id] = nil
	local sc = w.frame:FindFirstChildOfClass("UIScale") :: UIScale
	tween(sc, 0.18, { Scale = 0.94 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(w.frame, 0.18, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.2, function()
		w.frame:Destroy()
	end)
	if focused == id then
		local best, bz = nil, -1
		for wid, ow in pairs(windows) do
			if not ow.minimized and ow.frame.ZIndex > bz then
				best, bz = wid, ow.frame.ZIndex
			end
		end
		focusWin(best)
	else
		updateTaskbar()
	end
end

local function minimizeWin(id: string)
	local w = windows[id]
	if not w or w.minimized then
		return
	end
	w.minimized = true
	local keep = { pos = w.frame.Position, size = w.frame.Size }
	w.state._minPos = keep
	local sc = w.frame:FindFirstChildOfClass("UIScale") :: UIScale
	local target = taskButtonPos(id)
	tween(w.frame, 0.32, { Position = target - UDim2.fromOffset(w.frame.AbsoluteSize.X / holderScale.Scale / 2, w.frame.AbsoluteSize.Y / holderScale.Scale / 2), GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tween(sc, 0.32, { Scale = 0.15 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	task.delay(0.33, function()
		if w.minimized then
			w.frame.Visible = false
		end
	end)
	if focused == id then
		focused = nil
	end
	updateTaskbar()
end

local function restoreWin(id: string)
	local w = windows[id]
	if not w then
		return
	end
	if w.minimized then
		w.minimized = false
		w.frame.Visible = true
		local keep = w.state._minPos
		local sc = w.frame:FindFirstChildOfClass("UIScale") :: UIScale
		tween(w.frame, 0.35, { Position = keep.pos, GroupTransparency = 0 }, Enum.EasingStyle.Quint)
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Quint)
	end
	focusWin(id)
end

local function toggleMaximize(id: string)
	local w = windows[id]
	if not w then
		return
	end
	if w.maximized then
		w.maximized = false
		local r = w.restore or { pos = UDim2.fromOffset(120, 60), size = UDim2.fromOffset(800, 520) }
		tween(w.frame, 0.3, { Position = r.pos, Size = r.size })
	else
		w.maximized = true
		w.restore = { pos = w.frame.Position, size = w.frame.Size }
		tween(w.frame, 0.3, { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -TASKBAR) })
	end
	local c = w.frame:FindFirstChildOfClass("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, w.maximized and 0 or 10)
	task.delay(0.32, function()
		if windows[id] == w then
			renderWin(w)
		end
	end)
end

local function openApp(id: string)
	local app = APPS[id]
	if not app then
		return
	end
	if windows[id] then
		restoreWin(id)
		return
	end
	openCount += 1
	local size = app.size
	local cascade = (openCount % 5) * 26
	local px = math.clamp((W - size.X) / 2 + cascade - 52, 8, W - size.X - 8)
	local py = math.clamp((H - TASKBAR - size.Y) / 2 + cascade - 40, 8, H - TASKBAR - size.Y - 8)
	local frame = new("CanvasGroup", {
		Name = "Win_" .. id,
		Position = UDim2.fromOffset(px, py),
		Size = UDim2.fromOffset(size.X, size.Y),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = winLayer,
	}, { corner(10), stroke(Color3.new(0, 0, 0), 0.78, 1) })
	theme(frame, "BackgroundColor3", "win")
	local sc = new("UIScale", { Scale = 0.92, Parent = frame })
	local bar = new("Frame", { Name = "TitleBar", Size = UDim2.new(1, 0, 0, 38), BorderSizePixel = 0, Active = true, Parent = frame })
	theme(bar, "BackgroundColor3", "title")
	label({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 26, 1, 0), TextSize = 18, Text = app.icon, TextXAlignment = Enum.TextXAlignment.Center, Parent = bar })
	local title = label({ Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -190, 1, 0), Font = F.medium, TextSize = 15, Text = "", Parent = bar })
	theme(title, "TextColor3", "text")
	local function chromeBtn(x: number, text: string, hoverColor: Color3, fn: () -> ())
		local b = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, x, 0, 0),
			Size = UDim2.fromOffset(46, 38),
			BackgroundTransparency = 1,
			BackgroundColor3 = hoverColor,
			Text = text,
			Font = F.medium,
			TextSize = 16,
			AutoButtonColor = false,
			Parent = bar,
		})
		theme(b, "TextColor3", "text")
		b.MouseEnter:Connect(function()
			tween(b, 0.12, { BackgroundTransparency = 0 })
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.15, { BackgroundTransparency = 1 })
		end)
		b.Activated:Connect(fn)
		return b
	end
	chromeBtn(0, "×", Color3.fromRGB(232, 17, 35), function()
		closeWin(id)
	end)
	chromeBtn(-46, "▢", C().hover, function()
		toggleMaximize(id)
	end)
	chromeBtn(-92, "—", C().hover, function()
		minimizeWin(id)
	end)
	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38), BackgroundTransparency = 1, ClipsDescendants = true, Parent = frame })
	-- resize grip
	local grip = new("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Text = "◢", TextSize = 12, TextTransparency = 0.6, Font = F.regular, ZIndex = 50, Parent = frame })
	theme(grip, "TextColor3", "dim")

	local win: Win = { id = id, frame = frame, body = body, titleLabel = title, maximized = false, minimized = false, restore = nil, state = {} }
	windows[id] = win
	renderWin(win)
	focusWin(id)
	tween(frame, 0.22, { GroupTransparency = 0 })
	tween(sc, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)

	-- focus on click, drag by title bar (double click = maximise), resize by grip
	frame.InputBegan:Connect(function(input)
		if isPress(input) and focused ~= id then
			focusWin(id)
		end
	end)
	local lastClick = 0
	local drag: { start: Vector2, pos: UDim2, mode: string, size: UDim2 }? = nil
	bar.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		if os.clock() - lastClick < 0.35 then
			toggleMaximize(id)
			lastClick = 0
			return
		end
		lastClick = os.clock()
		if win.maximized then
			return
		end
		drag = { start = mouse(), pos = frame.Position, mode = "move", size = frame.Size }
	end)
	grip.InputBegan:Connect(function(input)
		if isPress(input) and not win.maximized then
			drag = { start = mouse(), pos = frame.Position, mode = "resize", size = frame.Size }
		end
	end)
	local conns = {}
	frame.Destroying:Connect(function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end)
	conns[1] = UserInputService.InputChanged:Connect(function(input)
		if not drag or not frame.Parent then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local d = (mouse() - drag.start) / holderScale.Scale
		if drag.mode == "move" then
			local x = math.clamp(drag.pos.X.Offset + d.X, -frame.AbsoluteSize.X / holderScale.Scale + 120, W - 120)
			local y = math.clamp(drag.pos.Y.Offset + d.Y, 0, H - TASKBAR - 38)
			frame.Position = UDim2.fromOffset(x, y)
		else
			local w = math.max(app.size.X * 0.6, drag.size.X.Offset + d.X)
			local h = math.max(app.size.Y * 0.6, drag.size.Y.Offset + d.Y)
			frame.Size = UDim2.fromOffset(w, h)
		end
	end)
	conns[2] = UserInputService.InputEnded:Connect(function(input)
		if drag and isPress(input) then
			local wasResize = drag.mode == "resize"
			drag = nil
			if wasResize and windows[id] == win then
				renderWin(win)
			end
		end
	end)
end

local function rerender(what: string)
	for _, w in pairs(windows) do
		local app = APPS[w.id]
		if app.live and app.live[what] and not w.minimized then
			renderWin(w)
		end
	end
end

---------------------------------------------------------------------------
-- app helpers
---------------------------------------------------------------------------
local function scroll(parent: Instance, props: { [string]: any }): ScrollingFrame
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.ScrollBarThickness = props.ScrollBarThickness or 6
	props.ScrollBarImageColor3 = C().dim
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.CanvasSize = UDim2.new()
	props.Parent = parent
	return new("ScrollingFrame", props)
end

local function card(parent: Instance, props: { [string]: any }): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or C().card
	props.BorderSizePixel = 0
	props.Parent = parent
	return new("Frame", props, { corner(props.Radius or 10), stroke(C().line, 0, 1) })
end

local function txt(parent: Instance, props: { [string]: any }): TextLabel
	props.TextColor3 = props.TextColor3 or C().text
	props.Parent = parent
	return label(props)
end

local function banner(parent: Instance, c1: Color3, c2: Color3, title: string, sub: string?, height: number?): Frame
	local b = new("Frame", { Size = UDim2.new(1, 0, 0, height or 64), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = parent })
	Kit.gradient(c1, c2, 0).Parent = b
	label({ Position = UDim2.fromOffset(20, sub and 10 or 0), Size = UDim2.new(1, -40, 0, sub and 28 or (height or 64)), Font = F.black, TextSize = 22, Text = title, Parent = b })
	if sub then
		label({ Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -40, 0, 20), TextSize = 14, TextTransparency = 0.12, Text = sub, Parent = b })
	end
	return b
end

local function laptopPart(): BasePart?
	for _, p in ipairs(CollectionService:GetTagged("Station")) do
		if p:GetAttribute("Station") == "laptop" and p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			return p
		end
	end
	return nil
end

local function nearLaptop(): boolean
	local part = laptopPart()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return part ~= nil and root ~= nil and (root.Position - part.Position).Magnitude < 12
end

local function orderingCustomer(): Model?
	for _, c in ipairs(CollectionService:GetTagged("Customer")) do
		if c:IsA("Model") and c:GetAttribute("State") == "Ordering" then
			return c
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- App: Kassa (POS)
---------------------------------------------------------------------------
local patienceFills: { { fill: Frame, ticket: any } } = {}

local function findTicket(id: number?)
	for _, t in ipairs(State.tickets) do
		if t.id == id then
			return t
		end
	end
	return nil
end

APPS.pos = {
	title = { de = "Kassa · Bestellungen", en = "Register · Orders" },
	icon = "🧾",
	size = Vector2.new(940, 600),
	live = { tickets = true, selection = true, shop = true, chat = true, customers = true },
	render = function(body, _win)
		patienceFills = {}
		local shop = State.shop
		local headerSub = string.format("%s %s  ·  %s %s  ·  %d %s", tr("Tag", "Day"), shop and shop.day or 1, tr("Umsatz heute", "Revenue today"), money(shop and shop.dayStats and shop.dayStats.revenue), #State.tickets, tr("offen", "open"))
		banner(body, ACCENT, Color3.fromRGB(255, 150, 60), "🥙  KEBAP HAUS  ·  " .. tr("Kassa", "Register"), headerSub)
		local y = 64
		-- customer at the register?
		local oc = orderingCustomer()
		if oc then
			local alert = new("Frame", { Position = UDim2.fromOffset(14, y + 12), Size = UDim2.new(1, -28, 0, 54), BackgroundColor3 = Color3.fromRGB(255, 244, 214), BorderSizePixel = 0, Parent = body }, { corner(10) })
			local st = stroke(Color3.fromRGB(245, 166, 35), 0, 2)
			st.Parent = alert
			Kit.pulse(st, "Transparency", 0, 0.7, 0.7)
			label({ Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -260, 1, 0), Font = F.bold, TextSize = 17, TextColor3 = Color3.fromRGB(120, 70, 0), Text = "🔔  " .. tr("Ein Kunde wartet an der Kassa", "A customer is waiting at the register"), Parent = alert })
			local near = nearLaptop()
			textBtn({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(230, 38), BackgroundColor3 = near and Color3.fromRGB(245, 140, 20) or Color3.fromRGB(200, 190, 170), TextColor3 = Color3.new(1, 1, 1), Text = near and tr("Bestellung aufnehmen", "Take order") or tr("Geh zum Laptop", "Go to the laptop"), Parent = alert }, function()
				local part = laptopPart()
				if part and nearLaptop() then
					State.Remote("Interact"):FireServer(part, "take_order")
				end
			end)
			y += 66
		end
		-- left: open orders
		local left = new("Frame", { Position = UDim2.fromOffset(14, y + 12), Size = UDim2.new(0, 330, 1, -(y + 26)), BackgroundTransparency = 1, Parent = body })
		txt(left, { Size = UDim2.new(1, 0, 0, 22), Font = F.bold, TextSize = 15, TextColor3 = C().dim, Text = string.upper(tr("Offene Bestellungen", "Open orders")) })
		local listFrame = scroll(left, { Name = "OrderList", Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -190) })
		list(false, 8).Parent = listFrame
		pad(2, 2, 8, 2).Parent = listFrame
		if not findTicket(OS.posTicket) then
			OS.posTicket = State.tickets[1] and State.tickets[1].id or nil
		end
		local selItem, selTicket = State.SelectedItem()
		if #State.tickets == 0 then
			txt(listFrame, { Size = UDim2.new(1, 0, 0, 120), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, TextColor3 = C().dim, TextWrapped = true, Text = "☕\n" .. tr("Keine offenen Bestellungen.\nWarte auf Kunden …", "No open orders.\nWaiting for customers …") })
		end
		for i, t in ipairs(State.tickets) do
			local sel = t.id == OS.posTicket
			local b = new("TextButton", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = sel and Color3.fromRGB(255, 236, 228) or C().card, AutoButtonColor = false, Text = "", BorderSizePixel = 0, Parent = listFrame }, { corner(10) })
			if OS.dark and sel then
				b.BackgroundColor3 = Color3.fromRGB(80, 44, 40)
			end
			stroke(sel and ACCENT or C().line, 0, sel and 2 or 1).Parent = b
			local delivered, total = 0, #t.items
			for _, it in ipairs(t.items) do
				if it.delivered then
					delivered += 1
				end
			end
			txt(b, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -110, 0, 22), Font = F.bold, TextSize = 16, Text = string.format("%s%s %s", t.vip and "⭐ " or "", t.emoji, t.name) .. (t.takerId and (t.takerId == game:GetService("Players").LocalPlayer.UserId and "  · 👤 Du" or ("  · 🔒 " .. (t.takerName or "?"))) or ""), TextTruncate = Enum.TextTruncate.AtEnd })
			txt(b, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(100, 22), Font = F.bold, TextSize = 16, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Right, Text = money(t.total * ((shop and shop.premium) or 1)) })
			txt(b, { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 18), TextSize = 13, TextColor3 = C().dim, Text = string.format("#%d · %d/%d %s%s", t.id, delivered, total, tr("serviert", "served"), #t.drinks > 0 and (" · " .. #t.drinks .. " 🥤") or "") })
			local _, fill = Kit.bar({ Position = UDim2.new(0, 12, 0, 56), Size = UDim2.new(1, -24, 0, 6), Parent = b }, Kit.T.green, C().line)
			local p = OrderText.Patience(t)
			fill.Size = UDim2.fromScale(p, 1)
			table.insert(patienceFills, { fill = fill, ticket = t })
			b.Activated:Connect(function()
				OS.posTicket = t.id
				Sound.Play("click")
				rerender("tickets")
			end)
		end
		-- conversation log
		local chatCard = card(left, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 150) })
		txt(chatCard, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20), Font = F.bold, TextSize = 13, TextColor3 = C().dim, Text = "💬 " .. string.upper(tr("Gespräch", "Conversation")) })
		local chat = scroll(chatCard, { Name = "Chat", Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 1, -34), ScrollBarThickness = 4 })
		list(false, 4).Parent = chat
		if #OS.chat == 0 then
			txt(chat, { Size = UDim2.new(1, 0, 0, 40), TextSize = 13, TextColor3 = C().dim, TextWrapped = true, Text = tr("Hier erscheint, was der Kunde bestellt.", "What the customer orders appears here.") })
		end
		for i, m in ipairs(OS.chat) do
			txt(chat, { LayoutOrder = i, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 14, Text = string.format("<b>%s %s:</b> %s", m.emoji, m.name, m.text) })
		end
		task.defer(function()
			chat.CanvasPosition = Vector2.new(0, 1e5)
		end)
		-- right: details of the selected order
		local right = card(body, { Position = UDim2.new(0, 356, 0, y + 12), Size = UDim2.new(1, -370, 1, -(y + 26)) })
		local t = findTicket(OS.posTicket)
		if not t then
			txt(right, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, TextColor3 = C().dim, Text = tr("Wähle links eine Bestellung aus.", "Select an order on the left.") })
			return
		end
		txt(right, { Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -170, 0, 30), Font = F.black, TextSize = 22, Text = string.format("%s%s %s", t.vip and "⭐ " or "", t.emoji, t.name) .. (t.takerId and (t.takerId == game:GetService("Players").LocalPlayer.UserId and "  · 👤 Du" or ("  · 🔒 " .. (t.takerName or "?"))) or ""), TextTruncate = Enum.TextTruncate.AtEnd })
		txt(right, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 12), Size = UDim2.fromOffset(150, 30), Font = F.black, TextSize = 22, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Right, Text = money(t.total * ((shop and shop.premium) or 1)) })
		txt(right, { Position = UDim2.fromOffset(18, 42), Size = UDim2.new(1, -36, 0, 18), TextSize = 13, TextColor3 = C().dim, Text = tr("Kunde wartet vorne an der Theke bei den Brettern (Abholung).", "Customer waits at the counter in front of the prep boards (pickup).") })
		local _, pfill = Kit.bar({ Position = UDim2.new(0, 18, 0, 66), Size = UDim2.new(1, -36, 0, 8), Parent = right }, Kit.T.green, C().line)
		pfill.Size = UDim2.fromScale(OrderText.Patience(t), 1)
		table.insert(patienceFills, { fill = pfill, ticket = t })
		local items = scroll(right, { Name = "Items", Position = UDim2.fromOffset(14, 84), Size = UDim2.new(1, -28, 1, -96) })
		list(false, 10).Parent = items
		pad(4, 2, 10, 4).Parent = items
		for i, item in ipairs(t.items) do
			local isSel = selTicket == t and selItem == item
			local ic = card(items, { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = isSel and (OS.dark and Color3.fromRGB(70, 56, 30) or Color3.fromRGB(255, 246, 222)) or C().win })
			pad(14, 12, 14, 12).Parent = ic
			list(false, 3).Parent = ic
			for li, line in ipairs(OrderText.Lines(item, OS.dark and "#ff8a76" or "#d0402c")) do
				txt(ic, {
					LayoutOrder = li,
					Size = UDim2.new(1, -150, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextWrapped = true,
					TextSize = li == 1 and 17 or 15,
					TextColor3 = item.delivered and C().dim or C().text,
					Text = (li == 1 and item.delivered) and ("✅ <s>" .. line .. "</s>") or line,
				})
			end
			local btnText = item.delivered and ("✅ " .. tr("Serviert", "Served")) or (isSel and ("✓ " .. tr("In Arbeit", "Preparing")) or (tr("Zubereiten", "Prepare") .. " ▶"))
			local b = textBtn({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(136, 34),
				BackgroundColor3 = item.delivered and C().line or (isSel and Color3.fromRGB(46, 160, 90) or ACCENT),
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 14,
				Text = btnText,
				Parent = ic,
			}, function()
				if not item.delivered then
					State.selected = { ticket = t.id, item = i }
					State.Fire("selection")
				end
			end)
			-- the button must not take part in the list layout
			local holderFrame = new("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Parent = ic })
			b.Parent = holderFrame
		end
		local d = OrderText.Drinks(t)
		if d then
			local dc = card(items, { LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C().win })
			txt(dc, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 15, Text = "🥤 " .. d })
		end
	end,
}

---------------------------------------------------------------------------
-- App: Lieferant (stock)
---------------------------------------------------------------------------
APPS.supplier = {
	title = { de = "Lieferant · Großmarkt", en = "Supplier · Wholesale" },
	icon = "🚚",
	size = Vector2.new(800, 560),
	live = { shop = true },
	render = function(body, _win)
		local shop = State.shop
		if not OS.wifi then
			txt(body, { Position = UDim2.fromScale(0, 0.28), Size = UDim2.new(1, 0, 0, 60), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 52, Text = "📡" })
			txt(body, { Position = UDim2.new(0, 0, 0.28, 66), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 24, Text = tr("Keine Internetverbindung", "No internet connection") })
			txt(body, { Position = UDim2.new(0, 0, 0.28, 104), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, TextColor3 = C().dim, Text = tr("Der Großmarkt ist nur online erreichbar. Schalte das WLAN ein.", "The wholesaler is only reachable online. Turn on Wi-Fi.") })
			textBtn({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.28, 140), Size = UDim2.fromOffset(200, 40), BackgroundColor3 = BLUE, TextColor3 = Color3.new(1, 1, 1), Text = tr("WLAN einschalten", "Turn on Wi-Fi"), Parent = body }, function()
				OS.wifi = true
				updateTray()
				rerender("shop")
			end)
			return
		end
		if not shop then
			return
		end
		local delayS = Config.UpgradeValue(shop.upgrades, "delivery")
		banner(body, Color3.fromRGB(0, 110, 200), Color3.fromRGB(0, 170, 190), "🚚  " .. tr("Wiener Großmarkt", "Vienna Wholesale"), tr(string.format("Lieferung in %ds direkt in den Lagerraum · bezahlt wird vom eigenen Konto", delayS), string.format("Delivered in %ds straight to the storage room · paid from your own cash", delayS)))
		local header = new("Frame", { Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 0, 22), BackgroundTransparency = 1, Parent = body })
		for _, h in ipairs({ { 0, tr("Produkt", "Product") }, { 0.32, tr("Bestand", "Stock") }, { 0.62, tr("Unterwegs", "In transit") } }) do
			txt(header, { Position = UDim2.fromScale(h[1], 0), Size = UDim2.new(0.3, 0, 1, 0), Font = F.bold, TextSize = 13, TextColor3 = C().dim, Text = string.upper(h[2]) })
		end
		local rows = scroll(body, { Name = "Rows", Position = UDim2.fromOffset(16, 100), Size = UDim2.new(1, -32, 1, -164) })
		list(false, 6).Parent = rows
		local totalCost, toBuy = 0, {}
		local shown = 0
		for i, id in ipairs(IngredientData.StockOrder) do
			if not Progression.StockUnlocked(shop.unlocks, id) then
				continue
			end
			shown += 1
			local def = IngredientData.Stock[id]
			local n, cap, transit = shop.stock[id] or 0, shop.caps[id] or 1, shop.transit[id] or 0
			local row = card(rows, { LayoutOrder = i, Size = UDim2.new(1, -8, 0, 46) })
			txt(row, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.3, -14, 1, 0), Font = F.bold, TextSize = 15, Text = def.name[State.lang], TextTruncate = Enum.TextTruncate.AtEnd })
			local ratio = n / cap
			local _, fill = Kit.bar({ Position = UDim2.new(0.32, 0, 0.5, -4), Size = UDim2.new(0.18, 0, 0, 8), Parent = row }, ratio < 0.2 and Kit.T.red or (ratio < 0.5 and Kit.T.orange or Kit.T.green), C().line)
			fill.Size = UDim2.fromScale(0, 1)
			tween(fill, 0.6, { Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1) }, Enum.EasingStyle.Quint, nil, i * 0.03)
			txt(row, { Position = UDim2.new(0.51, 6, 0, 0), Size = UDim2.new(0.1, 0, 1, 0), TextSize = 14, Text = string.format("%d/%d", n, cap) })
			txt(row, { Position = UDim2.new(0.62, 0, 0, 0), Size = UDim2.new(0.14, 0, 1, 0), TextSize = 14, TextColor3 = BLUE, Text = transit > 0 and ("🚚 +" .. transit) or "–" })
			local amount = math.min(def.pack, cap - n - transit)
			local cost = def.cost * math.max(amount, 0)
			if amount > 0 and ratio < 0.6 then
				totalCost += cost
				table.insert(toBuy, id)
			end
			textBtn({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(150, 32),
				TextSize = 14,
				BackgroundColor3 = amount > 0 and BLUE or C().line,
				TextColor3 = amount > 0 and Color3.new(1, 1, 1) or C().dim,
				Text = amount > 0 and string.format("+%d · %s", amount, money(cost)) or ("✓ " .. tr("Voll", "Full")),
				Parent = row,
			}, function()
				if amount > 0 then
					State.Request("Restock", id)
				end
			end)
		end
		local lockedCount = #IngredientData.StockOrder - shown
		if lockedCount > 0 then
			local hint = card(rows, { LayoutOrder = 999, Size = UDim2.new(1, -8, 0, 40), BackgroundColor3 = C().win })
			txt(hint, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 13, TextColor3 = C().dim, Text = "🔒 " .. string.format(tr("%d weitere Produkte – zuerst im Shop-Ausbau freischalten.", "%d more products – unlock them in Shop Upgrades first."), lockedCount) })
		end
		local footer = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -12), Size = UDim2.new(1, -32, 0, 44), BackgroundTransparency = 1, Parent = body })
		txt(footer, { Size = UDim2.new(0.6, 0, 1, 0), TextSize = 14, TextColor3 = C().dim, Text = string.format("%s: <b>%s</b>", tr("Dein Guthaben", "Your balance"), money(State.player and State.player.cash)) })
		textBtn({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(300, 44), BackgroundColor3 = #toBuy > 0 and Color3.fromRGB(46, 160, 90) or C().line, TextColor3 = #toBuy > 0 and Color3.new(1, 1, 1) or C().dim, Text = #toBuy > 0 and string.format("📦 %s (%s)", tr("Knappe Ware auffüllen", "Restock low items"), money(totalCost)) or ("✓ " .. tr("Alles gut gefüllt", "Everything well stocked")), Parent = footer }, function()
			task.spawn(function()
				for _, id in ipairs(toBuy) do
					State.Request("Restock", id)
					task.wait(0.3)
				end
			end)
		end)
	end,
}

---------------------------------------------------------------------------
-- App: Shop-Ausbau (upgrades)
---------------------------------------------------------------------------
APPS.upgrades = {
	title = { de = "Shop-Ausbau", en = "Shop Upgrades" },
	icon = "🛠️",
	size = Vector2.new(900, 600),
	live = { shop = true, player = true },
	render = function(body, _win)
		local ps, shop = State.player, State.shop
		if not ps or not shop then
			return
		end
		local unlocks = shop.unlocks or {}
		banner(body, Color3.fromRGB(120, 60, 200), Color3.fromRGB(220, 80, 160), "🛠️  " .. tr("Ausbau & Freischaltungen", "Unlocks & Upgrades"), string.format("%s: %s  ·  %s %d%s", tr("Guthaben", "Balance"), money(ps.cash), tr("Level", "Level"), ps.level, ps.isOwner and "" or ("  ·  " .. tr("nur der Chef kann kaufen", "only the owner can buy"))))
		-- tabs
		local tabs = new("Frame", { Position = UDim2.fromOffset(14, 74), Size = UDim2.new(1, -28, 0, 36), BackgroundTransparency = 1, Parent = body })
		list(true, 8).Parent = tabs
		local TABS = {
			{ "unlocks", "🧺 " .. tr("Zutaten & Geräte", "Ingredients & equipment") },
			{ "knives", "🔪 " .. tr("Messer", "Knives") },
			{ "upgrades", "⚙️ " .. tr("Verbesserungen", "Improvements") },
		}
		for i, t in ipairs(TABS) do
			local on = OS.upTab == t[1]
			textBtn({ LayoutOrder = i, Size = UDim2.fromOffset(i == 1 and 230 or 150, 34), TextSize = 14, BackgroundColor3 = on and Color3.fromRGB(130, 70, 220) or C().card, TextColor3 = on and Color3.new(1, 1, 1) or C().text, Text = t[2], Parent = tabs }, function()
				OS.upTab = t[1]
				rerender("shop")
			end)
		end
		local grid = scroll(body, { Name = "Grid", Position = UDim2.fromOffset(14, 118), Size = UDim2.new(1, -28, 1, -130) })
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -10, 0, 136), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		pad(2, 2, 10, 2).Parent = grid

		if OS.upTab ~= "upgrades" then
			local wantKnife = OS.upTab == "knives"
			local order = 0
			if wantKnife then
				-- the starting knife, always owned
				order += 1
				local k = Progression.Knives.old
				local c = card(grid, { LayoutOrder = 0, BackgroundColor3 = shop.knife == "old" and (OS.dark and Color3.fromRGB(40, 70, 50) or Color3.fromRGB(230, 248, 234)) or C().card })
				pad(14, 12).Parent = c
				txt(c, { Size = UDim2.new(1, 0, 0, 22), Font = F.bold, TextSize = 17, Text = "🔪  " .. k.name[State.lang] })
				txt(c, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 52), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, TextYAlignment = Enum.TextYAlignment.Top, Text = tr("Stumpf und klein – dein Startmesser.", "Blunt and short – your starting knife.") })
				txt(c, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(0.6, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.green, Text = shop.knife == "old" and ("✓ " .. tr("In Benutzung", "In use")) or ("✓ " .. tr("Besitzt du", "Owned")) })
			end
			for _, u in ipairs(Progression.Unlocks) do
				if not u.base and ((u.cat == "knife") == wantKnife) then
					order += 1
					local st = Progression.State(unlocks, u.id)
					local ok, why = Progression.CanBuy(unlocks, u.id, ps.level, ps.cash)
					local inUse = u.gives.knife and shop.knife == u.gives.knife
					local c = card(grid, { LayoutOrder = order + (st == "owned" and 100 or 0), BackgroundColor3 = (st == "owned" and inUse) and (OS.dark and Color3.fromRGB(40, 70, 50) or Color3.fromRGB(230, 248, 234)) or C().card })
					pad(14, 12).Parent = c
					txt(c, { Size = UDim2.new(1, -70, 0, 22), Font = F.bold, TextSize = 17, Text = u.icon .. "  " .. u.name[State.lang], TextTruncate = Enum.TextTruncate.AtEnd })
					txt(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(70, 22), TextXAlignment = Enum.TextXAlignment.Right, Font = F.bold, TextSize = 13, TextColor3 = ps.level >= u.level and Kit.T.green or C().dim, Text = "Lvl " .. u.level })
					local desc = u.desc[State.lang]
					if u.requires and why == "requires" then
						local need = {}
						for _, r in ipairs(u.requires) do
							if not Progression.Owned(unlocks, r) then
								table.insert(need, Progression.ById[r].name[State.lang])
							end
						end
						desc ..= "\n<font color='#d0402c'>" .. tr("Benötigt: ", "Requires: ") .. table.concat(need, ", ") .. "</font>"
					elseif u.install then
						desc ..= "\n<font color='#8a8f9a'>📦 " .. tr("Wird geliefert & in der Küche eingebaut", "Delivered & installed in the kitchen") .. "</font>"
					end
					txt(c, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 56), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, TextYAlignment = Enum.TextYAlignment.Top, Text = desc })
					if st == "owned" then
						txt(c, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(0.6, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.green, Text = inUse and ("✓ " .. tr("In Benutzung", "In use")) or ("✓ " .. tr("Installiert", "Installed")) })
					elseif st == "delivered" then
						txt(c, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.orange, Text = "📦 " .. tr("Kiste in der Küche auspacken!", "Unpack the crate in the kitchen!") })
					else
						local text
						if not ps.isOwner then
							text = "👑 " .. tr("Nur Chef", "Owner only")
						elseif why == "level" then
							text = "🔒 Level " .. u.level
						elseif why == "requires" then
							text = "🔒 " .. tr("Erst Voraussetzung", "Requirement first")
						else
							text = tr("Kaufen", "Buy") .. " · " .. money(u.price)
						end
						local can = ps.isOwner and ok
						local priceTag = txt(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.4, 0, 0, 30), Font = F.bold, TextSize = 15, TextColor3 = ps.cash >= u.price and Color3.fromRGB(150, 90, 230) or C().dim, Text = money(u.price) })
						local _ = priceTag
						textBtn({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(0.58, 0, 0, 32), TextSize = 14, BackgroundColor3 = can and Color3.fromRGB(130, 70, 220) or C().line, TextColor3 = can and Color3.new(1, 1, 1) or C().dim, Text = text, Parent = c }, function()
							if not can then
								Sound.Play("fail")
								return
							end
							local res = State.Request("BuyUnlock", u.id)
							if res and res.ok then
								Sound.Play("levelup")
								Laptop.Notify(u.icon .. " " .. u.name[State.lang], res.state == "delivered" and tr("Bestellt – wird gleich geliefert.", "Ordered – arriving shortly.") or tr("Freigeschaltet!", "Unlocked!"), u.icon)
							end
						end)
					end
				end
			end
			return
		end

		local upgrades = shop.upgrades or {}
		for i, id in ipairs(Config.UpgradeOrder) do
			local def = Config.Upgrades[id]
			local tier = upgrades[id] or 0
			local maxTier = #def.prices
			local c = card(grid, { LayoutOrder = i })
			pad(14, 12).Parent = c
			txt(c, { Size = UDim2.new(1, 0, 0, 22), Font = F.bold, TextSize = 17, Text = def.icon .. "  " .. def.name[State.lang], TextTruncate = Enum.TextTruncate.AtEnd })
			txt(c, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 36), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, TextYAlignment = Enum.TextYAlignment.Top, Text = def.desc[State.lang] })
			local dots = {}
			for k = 1, maxTier do
				table.insert(dots, k <= tier and "●" or "○")
			end
			txt(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.45, 0, 0, 30), Font = F.bold, TextSize = 15, TextColor3 = Color3.fromRGB(150, 90, 230), Text = table.concat(dots, " ") })
			local needs = def.needs and not Progression.Owned(unlocks, def.needs)
			if tier >= maxTier then
				txt(c, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(0.5, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.green, Text = "✓ MAX" })
			else
				local price = def.prices[tier + 1]
				local req = def.req[tier + 1]
				local locked = ps.level < req
				local can = ps.isOwner and not locked and not needs and ps.cash >= price
				local text = locked and ("🔒 Level " .. req) or (tr("Kaufen", "Buy") .. " · " .. money(price))
				if needs then
					text = "🔒 " .. Progression.ById[def.needs].name[State.lang]
				end
				if not ps.isOwner then
					text = "👑 " .. tr("Nur Chef", "Owner only")
				end
				textBtn({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(0.55, 0, 0, 32), TextSize = 14, BackgroundColor3 = can and Color3.fromRGB(130, 70, 220) or C().line, TextColor3 = can and Color3.new(1, 1, 1) or C().dim, Text = text, Parent = c }, function()
					local res = State.Request("BuyUpgrade", id)
					if res and res.ok then
						Sound.Play("levelup")
						Laptop.Notify("🛠️ " .. def.name[State.lang], tr("Upgrade installiert.", "Upgrade installed."), def.icon)
					end
				end)
			end
		end
	end,
}

---------------------------------------------------------------------------
-- App: Betrieb (expansion stages, staff, prices)
---------------------------------------------------------------------------
local BIZ_PURPLE = Color3.fromRGB(230, 120, 30)

local function actionBtn(parent: Instance, props: { [string]: any }, can: boolean, text: string, onClick: () -> ())
	props.TextSize = props.TextSize or 14
	props.BackgroundColor3 = can and BIZ_PURPLE or C().line
	props.TextColor3 = can and Color3.new(1, 1, 1) or C().dim
	props.Text = text
	props.Parent = parent
	return textBtn(props, function()
		if not can then
			Sound.Play("fail")
			return
		end
		onClick()
	end)
end

local function stars(n: number): string
	return string.rep("★", n) .. string.rep("☆", Business.MaxSkill - n)
end

APPS.business = {
	title = { de = "Betrieb", en = "Business" },
	icon = "🏢",
	size = Vector2.new(940, 620),
	live = { shop = true, player = true },
	render = function(body, _win)
		local ps, shop = State.player, State.shop
		local b = shop and shop.biz
		if not ps or not shop or not b then
			txt(body, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Text = tr("Lädt …", "Loading …") })
			return
		end
		local stageDef = Business.Stages[b.stage]
		banner(body, Color3.fromRGB(230, 110, 30), Color3.fromRGB(200, 50, 60), "🏢  " .. tr("Betrieb", "Business") .. " · " .. stageDef.icon .. " " .. stageDef.name[State.lang], string.format("%s: %s  ·  Level %d%s", tr("Guthaben", "Balance"), money(ps.cash), ps.level, ps.isOwner and "" or ("  ·  " .. tr("nur der Chef kann entscheiden", "only the owner decides"))))
		local tabs = new("Frame", { Position = UDim2.fromOffset(14, 74), Size = UDim2.new(1, -28, 0, 36), BackgroundTransparency = 1, Parent = body })
		list(true, 8).Parent = tabs
		OS.bizTab = OS.bizTab or "stages"
		for i, t in ipairs({ { "stages", "🏗️ " .. tr("Ausbau", "Expansion") }, { "staff", "👥 " .. tr("Personal", "Staff") }, { "prices", "🏷️ " .. tr("Preise", "Prices") }, { "theme", "🎨 " .. tr("Einrichtung", "Interior") }, { "branches", "🏪 " .. tr("Filialen", "Branches") } }) do
			local on = OS.bizTab == t[1]
			textBtn({ LayoutOrder = i, Size = UDim2.fromOffset(140, 34), TextSize = 14, BackgroundColor3 = on and BIZ_PURPLE or C().card, TextColor3 = on and Color3.new(1, 1, 1) or C().text, Text = t[2], Parent = tabs }, function()
				OS.bizTab = t[1]
				rerender("shop")
			end)
		end
		local sc = scroll(body, { Name = "Biz", Position = UDim2.fromOffset(14, 118), Size = UDim2.new(1, -28, 1, -130) })
		pad(2, 2, 10, 2).Parent = sc

		if OS.bizTab == "stages" then
			list(false, 10).Parent = sc
			for i, st in ipairs(Business.Stages) do
				local built = b.stage >= st.id
				local isNext = st.id == b.stage + 1
				local c = card(sc, { LayoutOrder = i, Size = UDim2.new(1, -8, 0, 92), BackgroundColor3 = built and (OS.dark and Color3.fromRGB(40, 70, 50) or Color3.fromRGB(230, 248, 234)) or C().card })
				txt(c, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(60, 60), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Text = st.icon })
				txt(c, { Position = UDim2.fromOffset(84, 8), Size = UDim2.new(1, -320, 0, 24), Font = F.bold, TextSize = 17, Text = string.format("%s %d · %s", tr("Stufe", "Stage"), st.id, st.name[State.lang]) })
				txt(c, { Position = UDim2.fromOffset(84, 32), Size = UDim2.new(1, -320, 0, 36), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, TextYAlignment = Enum.TextYAlignment.Top, Text = st.desc[State.lang] })
				txt(c, { Position = UDim2.fromOffset(84, 68), Size = UDim2.new(1, -320, 0, 18), TextSize = 12, TextColor3 = BIZ_PURPLE, Text = string.format("👥 ×%.2f %s  ·  %d %s", st.demand, tr("Kundschaft", "customers"), st.maxActive, tr("Gäste gleichzeitig", "guests at once")) })
				local right = UDim2.new(1, -14, 0.5, 0)
				if built then
					txt(c, { AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(200, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.green, Text = "✓ " .. tr("Gebaut", "Built") })
				elseif b.building == st.id then
					txt(c, { AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(200, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.orange, Text = "🚧 " .. tr("Wird gebaut …", "Building …") })
				elseif isNext then
					local locked = ps.level < st.level
					local can = ps.isOwner and not locked and ps.cash >= st.price and not b.building
					local text = locked and ("🔒 Level " .. st.level) or (tr("Bauen", "Build") .. " · " .. money(st.price))
					actionBtn(c, { AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(200, 38) }, can, ps.isOwner and text or ("👑 " .. tr("Nur Chef", "Owner only")), function()
						local res = State.Request("BizBuyStage")
						if res and res.ok then
							Sound.Play("levelup")
							Laptop.Notify("🚧 " .. st.name[State.lang], tr("Die Bauarbeiten laufen – schau sie dir an!", "Construction started – go and watch!"), st.icon)
						end
					end)
				else
					txt(c, { AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(200, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.bold, TextColor3 = C().dim, Text = string.format("🔒 Lvl %d · %s", st.level, money(st.price)) })
				end
			end
		elseif OS.bizTab == "staff" then
			new("UIGridLayout", { CellSize = UDim2.new(0.5, -10, 0, 214), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })
			local wages = 0
			for _, e in pairs(b.staff) do
				wages += e.salary
			end
			for i, role in ipairs(Business.RoleOrder) do
				local def = Business.Roles[role]
				local e = b.staff[role]
				local c = card(sc, { LayoutOrder = i })
				pad(14, 12).Parent = c
				txt(c, { Size = UDim2.new(1, -80, 0, 22), Font = F.bold, TextSize = 17, Text = def.icon .. "  " .. def.name[State.lang] })
				txt(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(80, 22), TextXAlignment = Enum.TextXAlignment.Right, Font = F.bold, TextSize = 13, TextColor3 = ps.level >= def.level and Kit.T.green or C().dim, Text = "Lvl " .. def.level })
				if e then
					txt(c, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 20), Font = F.bold, TextSize = 15, Text = string.format("%s  <font color='#e6a020'>%s</font>", e.name, stars(e.skill)) })
					txt(c, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = C().dim, Text = string.format("⚡ %s %d %%   ·   🎯 %s %d %%   ·   💶 %s/%s", tr("Tempo", "Speed"), math.floor(e.speed * 100), tr("Zuverlässig", "Reliable"), math.floor(e.rel * 100), money(e.salary), tr("Tag", "day")) })
					local stc = card(c, { Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = OS.dark and Color3.fromRGB(40, 44, 54) or Color3.fromRGB(244, 246, 250) })
					txt(stc, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 14, Text = "● " .. (e.status ~= nil and e.status ~= "" and e.status or tr("Kommt zur Arbeit …", "Coming to work …")), TextTruncate = Enum.TextTruncate.AtEnd })
					local maxed = e.skill >= Business.MaxSkill
					local cost = Business.TrainCost(e.skill)
					actionBtn(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.62, -6, 0, 34) }, ps.isOwner and not maxed and ps.cash >= cost, maxed and "✓ MAX" or ("📚 " .. tr("Training", "Training") .. " · " .. money(cost)), function()
						if State.Request("BizTrain", role) then
							Sound.Play("levelup")
						end
					end)
					local fireBtn = textBtn({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(0.38, -6, 0, 34), TextSize = 13, BackgroundColor3 = C().card, TextColor3 = Kit.T.red, Text = tr("Entlassen", "Dismiss"), Parent = c }, function()
						if not ps.isOwner then
							return
						end
						if OS.confirmFire ~= role then
							OS.confirmFire = role
							rerender("shop")
							return
						end
						OS.confirmFire = nil
						State.Request("BizFire", role)
					end)
					if OS.confirmFire == role then
						fireBtn.Text = tr("Sicher?", "Sure?")
						fireBtn.BackgroundColor3 = Kit.T.red
						fireBtn.TextColor3 = Color3.new(1, 1, 1)
					end
				else
					txt(c, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 34), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, TextYAlignment = Enum.TextYAlignment.Top, Text = def.desc[State.lang] })
					if ps.level < def.level then
						txt(c, { Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextColor3 = C().dim, Text = "🔒 Level " .. def.level })
					else
						txt(c, { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, Font = F.bold, TextColor3 = C().dim, Text = string.format("%s · %s %s", tr("Bewerbungen heute", "Applicants today"), tr("Einstellung", "Signing"), money(def.hire)) })
						for k, cand in ipairs(Business.Candidates(role, shop.day)) do
							local row = new("Frame", { Position = UDim2.fromOffset(0, 80 + (k - 1) * 38), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = c })
							txt(row, { Size = UDim2.new(1, -110, 1, 0), TextSize = 13, Text = string.format("<b>%s</b> <font color='#e6a020'>%s</font>  ⚡%d%% 🎯%d%%  💶%s", cand.name, string.rep("★", cand.skill), math.floor(cand.speed * 100), math.floor(cand.rel * 100), money(cand.salary)), TextTruncate = Enum.TextTruncate.AtEnd })
							actionBtn(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(104, 30), TextSize = 13 }, ps.isOwner and ps.cash >= def.hire, tr("Einstellen", "Hire"), function()
								local res = State.Request("BizHire", { role = role, idx = k })
								if res and res.ok then
									Sound.Play("levelup")
									Laptop.Notify(def.icon .. " " .. cand.name, tr("Fängt sofort an!", "Starts right away!"), def.icon)
								end
							end)
						end
					end
				end
			end
			local info = card(sc, { LayoutOrder = 99, BackgroundColor3 = OS.dark and Color3.fromRGB(50, 44, 30) or Color3.fromRGB(255, 246, 225) })
			pad(14, 12).Parent = info
			txt(info, { Size = UDim2.new(1, 0, 1, 0), TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = string.format("💶 <b>%s: %s / %s</b>\n%s", tr("Löhne", "Wages"), money(wages), tr("Tag", "day"), tr("Löhne werden beim Ladenschluss bezahlt. Training erhöht Können und Tempo – und den Lohn. Unzuverlässige Leute machen öfter Pause.", "Wages are paid at closing time. Training raises skill and speed – and the wage. Unreliable staff take more breaks.")) })
		elseif OS.bizTab == "theme" then
			new("UIGridLayout", { CellSize = UDim2.new(0.333, -9, 0, 130), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })
			for i, t in ipairs(Business.Themes) do
				local on = b.theme == t.id
				local owned = b.themes and b.themes[t.id]
				local locked = t.stage and b.stage < t.stage
				local c = card(sc, { LayoutOrder = i, BackgroundColor3 = on and (OS.dark and Color3.fromRGB(40, 70, 50) or Color3.fromRGB(230, 248, 234)) or C().card })
				pad(12, 10).Parent = c
				new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = t.color, BorderSizePixel = 0, Parent = c }, { round() })
				txt(c, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 22), Font = F.bold, TextSize = 15, Text = t.name[State.lang] })
				if on then
					txt(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextColor3 = Kit.T.green, Text = "✓ " .. tr("Aktiv", "Active") })
				else
					local text = locked and ("🔒 " .. Business.Stages[t.stage].name[State.lang]) or (owned and tr("Wählen", "Select") or (tr("Kaufen", "Buy") .. " · " .. money(t.price)))
					actionBtn(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 32) }, ps.isOwner and not locked and (owned or ps.cash >= t.price), ps.isOwner and text or ("👑 " .. tr("Nur Chef", "Owner only")), function()
						State.Request("BizTheme", t.id)
					end)
				end
			end
		elseif OS.bizTab == "branches" then
			list(false, 10).Parent = sc
			local rep = shop.reputation or 3
			for i, br in ipairs(Business.Branches) do
				local lvl = b.branches and b.branches[br.id]
				local c = card(sc, { LayoutOrder = i, Size = UDim2.new(1, -8, 0, 92), BackgroundColor3 = lvl and (OS.dark and Color3.fromRGB(40, 70, 50) or Color3.fromRGB(230, 248, 234)) or C().card })
				txt(c, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(60, 60), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Text = br.icon })
				txt(c, { Position = UDim2.fromOffset(84, 8), Size = UDim2.new(1, -320, 0, 24), Font = F.bold, TextSize = 17, Text = br.name[State.lang] .. (lvl and string.format("  ·  %s %d/%d", tr("Stufe", "Level"), lvl, Business.BranchMaxLevel) or "") })
				local now = Business.BranchIncome(br.income, lvl or 1, rep)
				txt(c, { Position = UDim2.fromOffset(84, 34), Size = UDim2.new(1, -320, 0, 50), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, TextYAlignment = Enum.TextYAlignment.Top, Text = string.format(tr("Eigenes Team vor Ort. Zahlt bei Ladenschluss ca. %s pro Tag aus – mehr mit besserem Ruf (★ %.1f) und Ausbau.", "Own crew on site. Pays about %s per day at closing time – more with a better reputation (★ %.1f) and upgrades."), money(now), rep) })
				local right = UDim2.new(1, -14, 0.5, 0)
				if lvl and lvl >= Business.BranchMaxLevel then
					txt(c, { AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(200, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.green, Text = "✓ MAX" })
				else
					local cost = lvl and Business.BranchUpgradeCost(br.price, lvl) or br.price
					local locked = not lvl and ps.level < br.level
					local text = locked and ("🔒 Level " .. br.level) or ((lvl and tr("Ausbauen", "Upgrade") or tr("Eröffnen", "Open")) .. " · " .. money(cost))
					actionBtn(c, { AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(200, 38) }, ps.isOwner and not locked and ps.cash >= cost, ps.isOwner and text or ("👑 " .. tr("Nur Chef", "Owner only")), function()
						State.Request("BizBranch", br.id)
					end)
				end
			end
		else
			list(false, 10).Parent = sc
			for i, id in ipairs(Business.PriceOrder) do
				local def = Business.Prices[id]
				local on = b.price == id
				local locked = def.stage and b.stage < def.stage
				local c = card(sc, { LayoutOrder = i, Size = UDim2.new(1, -8, 0, 84), BackgroundColor3 = on and (OS.dark and Color3.fromRGB(60, 48, 30) or Color3.fromRGB(255, 240, 220)) or C().card })
				txt(c, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(50, 60), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Text = def.icon })
				txt(c, { Position = UDim2.fromOffset(74, 10), Size = UDim2.new(1, -300, 0, 24), Font = F.bold, TextSize = 17, Text = def.name[State.lang] })
				txt(c, { Position = UDim2.fromOffset(74, 38), Size = UDim2.new(1, -300, 0, 36), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, Text = string.format("%s ×%.2f  ·  %s ×%.2f  ·  %s %s%d %%", tr("Preise", "Prices"), def.mul, tr("Kundschaft", "Customers"), def.demand, tr("Zufriedenheit", "Satisfaction"), def.mood >= 0 and "+" or "", math.floor(def.mood * 100)) })
				if on then
					txt(c, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(180, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = F.black, TextColor3 = Kit.T.green, Text = "✓ " .. tr("Aktiv", "Active") })
				else
					local text = locked and ("🔒 " .. Business.Stages[def.stage].name[State.lang]) or tr("Wählen", "Select")
					actionBtn(c, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(180, 36) }, ps.isOwner and not locked, ps.isOwner and text or ("👑 " .. tr("Nur Chef", "Owner only")), function()
						State.Request("BizPrice", id)
					end)
				end
			end
			txt(sc, { LayoutOrder = 10, Size = UDim2.new(1, -8, 0, 60), TextSize = 13, TextWrapped = true, TextColor3 = C().dim, Text = tr("Günstige Preise locken mehr Gäste an, bringen aber weniger pro Gericht. Premium-Preise bringen mehr Geld – die Gäste erwarten dafür aber auch mehr.", "Cheap prices attract more guests but earn less per dish. Premium prices earn more – but guests expect more, too.") })
		end
	end,
}

---------------------------------------------------------------------------
-- App: Bewertungen (reviews, cleanliness, freshness, regulars)
---------------------------------------------------------------------------
APPS.reviews = {
	title = { de = "Bewertungen", en = "Reviews" },
	icon = "⭐",
	size = Vector2.new(900, 600),
	live = { shop = true },
	render = function(body, _win)
		local shop = State.shop
		local b = shop and shop.biz
		if not shop or not b then
			return
		end
		local rating = b.ratingCount > 0 and string.format("%.1f ★ (%d %s)", b.rating, b.ratingCount, tr("Bewertungen", "reviews")) or tr("Noch keine Bewertungen", "No reviews yet")
		banner(body, Color3.fromRGB(240, 170, 30), Color3.fromRGB(230, 110, 40), "⭐  " .. tr("Bewertungen & Ruf", "Reviews & reputation"), string.format("%s  ·  %s %.1f/5", rating, tr("Ruf", "Reputation"), shop.reputation or 0))
		-- left: cleanliness, freshness, regulars
		local left = scroll(body, { Position = UDim2.fromOffset(14, 76), Size = UDim2.new(0.42, -14, 1, -88) })
		list(false, 10).Parent = left
		pad(2, 2, 8, 2).Parent = left
		local cl = card(left, { LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 84) })
		pad(14, 10).Parent = cl
		local cleanCol = b.clean > 0.75 and Kit.T.green or (b.clean > 0.5 and Kit.T.orange or Kit.T.red)
		txt(cl, { Size = UDim2.new(1, 0, 0, 22), Font = F.bold, TextSize = 16, Text = string.format("🧽 %s: %d %%", tr("Sauberkeit", "Cleanliness"), math.floor(b.clean * 100 + 0.5)) })
		local _, fill = Kit.bar({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 10), Parent = cl }, cleanCol, C().line)
		fill.Size = UDim2.fromScale(b.clean, 1)
		txt(cl, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = C().dim, Text = b.dirt > 0 and string.format(tr("%d Schmutzstellen – mit [E] putzen", "%d dirty spots – clean with [E]"), b.dirt) or tr("Alles blitzblank!", "Spotless!") })
		local fr = card(left, { LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
		pad(14, 10).Parent = fr
		list(false, 6).Parent = fr
		txt(fr, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), Font = F.bold, TextSize = 16, Text = "🥬 " .. tr("Frische der Zutaten", "Ingredient freshness") })
		local ids = {}
		for id in pairs(b.fresh) do
			table.insert(ids, id)
		end
		table.sort(ids)
		for i, id in ipairs(ids) do
			local f = b.fresh[id]
			local row = new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = fr })
			local v = IngredientData.Veg[id]
			txt(row, { Size = UDim2.new(0.4, 0, 1, 0), TextSize = 13, Text = (v and v.icon or "") .. " " .. (v and v.name[State.lang] or id) })
			local _, ff = Kit.bar({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.4, 0, 0.5, 0), Size = UDim2.new(0.45, 0, 0, 8), Parent = row }, f > 0.7 and Kit.T.green or (f > 0.45 and Kit.T.orange or Kit.T.red), C().line)
			ff.Size = UDim2.fromScale(f, 1)
			txt(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.15, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12, Text = math.floor(f * 100) .. "%" })
		end
		txt(fr, { LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 30), TextSize = 12, TextWrapped = true, TextColor3 = C().dim, Text = tr("Welkes Gemüse senkt die Qualität. [R] an der Gemüsewanne: frisch schneiden.", "Wilted veg lowers quality. [R] at the veg bin: chop fresh.") })
		local rg = card(left, { LayoutOrder = 3, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
		pad(14, 10).Parent = rg
		list(false, 4).Parent = rg
		txt(rg, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), Font = F.bold, TextSize = 16, Text = string.format("💛 %s (%d)", tr("Stammkunden", "Regulars"), #b.regulars) })
		if #b.regulars == 0 then
			txt(rg, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 34), TextSize = 12, TextWrapped = true, TextColor3 = C().dim, Text = tr("Begeisterte Gäste (4–5 ★) kommen manchmal als Stammkunden wieder – und geben mehr Trinkgeld.", "Delighted guests (4–5 ★) sometimes come back as regulars – and tip more.") })
		end
		for i, r in ipairs(b.regulars) do
			txt(rg, { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 18), TextSize = 13, Text = string.format("%s · %d %s · %s", r.name, r.visits, tr("Besuche", "visits"), r.menu or "?") })
		end
		-- right: review feed
		local right = scroll(body, { Position = UDim2.new(0.42, 6, 0, 76), Size = UDim2.new(0.58, -20, 1, -88) })
		list(false, 8).Parent = right
		pad(2, 2, 8, 2).Parent = right
		if #b.reviews == 0 then
			txt(right, { Size = UDim2.new(1, -8, 0, 40), TextSize = 14, TextColor3 = C().dim, Text = tr("Bediene Kunden, um Bewertungen zu bekommen.", "Serve customers to get reviews.") })
		end
		for i, r in ipairs(b.reviews) do
			local c = card(right, { LayoutOrder = i, Size = UDim2.new(1, -8, 0, 70) })
			txt(c, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -140, 0, 20), Font = F.bold, TextSize = 14, Text = r.n, TextTruncate = Enum.TextTruncate.AtEnd })
			txt(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(130, 20), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14, TextColor3 = Color3.fromRGB(230, 160, 20), Text = string.rep("★", r.s) .. string.rep("☆", 5 - r.s) })
			txt(c, { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 36), TextSize = 13, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C().dim, Text = string.format("„%s“  <font color='#9aa0aa'>· %s %d</font>", r.t, tr("Tag", "Day"), r.d or 0) })
		end
	end,
}

---------------------------------------------------------------------------
-- App: Statistik & Ziele
---------------------------------------------------------------------------
local GOAL_KEYS = { serve = "goal_serve", perfect = "goal_perfect", earn = "goal_earn", duerum = "goal_duerum", drinks = "goal_drinks", nowalk = "goal_nowalk" }

APPS.stats = {
	title = { de = "Statistik & Ziele", en = "Stats & Goals" },
	icon = "📊",
	size = Vector2.new(820, 580),
	live = { shop = true, player = true },
	render = function(body, _win)
		local shop, ps = State.shop, State.player
		if not shop or not ps then
			return
		end
		local s = shop.dayStats
		local sc = scroll(body, { Name = "Stats", Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 1, -24) })
		list(false, 12).Parent = sc
		pad(2, 2, 10, 10).Parent = sc
		local tiles = new("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1, Parent = sc })
		new("UIGridLayout", { CellSize = UDim2.new(0.25, -9, 1, 0), CellPadding = UDim2.fromOffset(12, 0), Parent = tiles })
		local tileData = {
			{ "💶", tr("Umsatz heute", "Revenue today"), money(s.revenue), Color3.fromRGB(46, 160, 90) },
			{ "🙂", tr("Bedient", "Served"), tostring(s.served), BLUE },
			{ "💯", tr("Perfekt", "Perfect"), tostring(s.perfect), Color3.fromRGB(150, 90, 230) },
			{ "😠", tr("Gegangen", "Walk-outs"), tostring(s.walkouts), Kit.T.red },
		}
		for _, d in ipairs(tileData) do
			local c = card(tiles, {})
			local strip = new("Frame", { Size = UDim2.new(0, 4, 1, -20), Position = UDim2.fromOffset(0, 10), BackgroundColor3 = d[4], BorderSizePixel = 0, Parent = c }, { round() })
			local _ = strip
			txt(c, { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -24, 0, 20), TextSize = 14, TextColor3 = C().dim, Text = d[1] .. "  " .. d[2] })
			txt(c, { Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -24, 0, 40), Font = F.black, TextSize = 30, Text = d[3] })
		end
		-- next goals (short / medium / long) from the server
		local ng = shop.nextGoals
		if ng then
			local box = new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = sc })
			list(false, 8).Parent = box
			txt(box, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 26), Font = F.black, TextSize = 19, Text = "🚀 " .. tr("Nächste Ziele", "Next goals") })
			for i, key in ipairs({ "short", "medium", "long" }) do
				local g = ng[key]
				if g then
					local tag = ({ tr("KURZ", "SHORT"), tr("MITTEL", "MEDIUM"), tr("LANG", "LONG") })[i]
					local col = ({ BLUE, Color3.fromRGB(150, 90, 230), Color3.fromRGB(230, 150, 20) })[i]
					local c = card(box, { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 74) })
					local chip = new("Frame", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(64, 20), BackgroundColor3 = col, BorderSizePixel = 0, Parent = c }, { round() })
					label({ Size = UDim2.fromScale(1, 1), Font = F.black, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = tag, Parent = chip })
					txt(c, { Position = UDim2.fromOffset(86, 8), Size = UDim2.new(1, -300, 0, 24), Font = F.bold, TextSize = 16, Text = g.icon .. "  " .. g.title[State.lang], TextTruncate = Enum.TextTruncate.AtEnd })
					txt(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(210, 24), Font = F.bold, TextSize = 13, TextColor3 = Color3.fromRGB(200, 140, 20), TextXAlignment = Enum.TextXAlignment.Right, Text = "🎁 " .. g.reward[State.lang], TextTruncate = Enum.TextTruncate.AtEnd })
					local sub = g.sub and g.sub[State.lang] or ""
					if g.money and (g.need or 0) > 0 then
						sub = string.format("%s %s", tr("Noch", "Still need"), money(g.need)) .. (sub ~= "" and ("  ·  " .. sub) or "")
					end
					txt(c, { Position = UDim2.fromOffset(86, 32), Size = UDim2.new(1, -100, 0, 18), TextSize = 13, TextColor3 = C().dim, Text = sub, TextTruncate = Enum.TextTruncate.AtEnd })
					local _, fill = Kit.bar({ Position = UDim2.new(0, 86, 0, 56), Size = UDim2.new(1, -200, 0, 8), Parent = c }, col, C().line)
					tween(fill, 0.7, { Size = UDim2.fromScale(math.clamp(g.progress or 0, 0, 1), 1) }, Enum.EasingStyle.Quint, nil, 0.05 * i)
					local prog = g.money and (money(g.cur) .. " / " .. money(g.max)) or string.format("%d / %d", math.floor(g.cur or 0), g.max or 1)
					txt(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 50), Size = UDim2.fromOffset(104, 20), TextSize = 12, TextColor3 = C().dim, TextXAlignment = Enum.TextXAlignment.Right, Text = prog })
				end
			end
		end
		txt(sc, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 26), Font = F.black, TextSize = 19, Text = "🎯 " .. tr("Tagesziele", "Daily goals") })
		for i, g in ipairs(shop.goals or {}) do
			local v = shop.dayStats[g.stat] or 0
			local target = g.kind == "earn" and money(g.target) or tostring(g.target)
			local progress = g.kind == "earn" and money(v) or tostring(math.floor(v))
			local c = card(sc, { LayoutOrder = 2 + i, Size = UDim2.new(1, 0, 0, 58) })
			txt(c, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -150, 0, 24), Font = F.bold, TextSize = 15, Text = (g.done and "✅ " or "") .. Localization.Get(GOAL_KEYS[g.kind], State.lang, { n = target }) })
			txt(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6), Size = UDim2.fromOffset(130, 24), Font = F.bold, TextSize = 15, TextColor3 = Color3.fromRGB(200, 140, 20), TextXAlignment = Enum.TextXAlignment.Right, Text = "+" .. money(g.reward) })
			local ratio = g.done and 1 or (g.atMost and 0.5 or math.clamp(v / math.max(g.target, 1), 0, 1))
			local _, fill = Kit.bar({ Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -120, 0, 8), Parent = c }, g.done and Kit.T.green or BLUE, C().line)
			tween(fill, 0.7, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quint, nil, 0.05 * i)
			txt(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 31), Size = UDim2.fromOffset(96, 20), TextSize = 13, TextColor3 = C().dim, TextXAlignment = Enum.TextXAlignment.Right, Text = g.atMost and "⏳" or (progress .. "/" .. target) })
		end
		local st = ps.stats
		txt(sc, { LayoutOrder = 20, Size = UDim2.new(1, 0, 0, 26), Font = F.black, TextSize = 19, Text = "📈 " .. tr("Gesamt", "All time") })
		txt(sc, { LayoutOrder = 21, Size = UDim2.new(1, 0, 0, 22), TextSize = 15, TextColor3 = C().dim, Text = string.format("%s: %d · %s: %d · %s: %s · %s: %d", tr("Bedient", "Served"), st.served, tr("Perfekt", "Perfect"), st.perfect, tr("Verdient", "Earned"), money(st.earned), tr("Tage", "Days"), st.days) })
		txt(sc, { LayoutOrder = 22, Size = UDim2.new(1, 0, 0, 26), Font = F.black, TextSize = 19, Text = "🏆 " .. tr("Erfolge", "Achievements") })
		local ach = new("Frame", { LayoutOrder = 23, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = sc })
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 50), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ach })
		for i, a in ipairs(Config.Achievements) do
			local done = ps.achievements[a.id]
			local c = card(ach, { LayoutOrder = i, BackgroundColor3 = done and (OS.dark and Color3.fromRGB(70, 60, 26) or Color3.fromRGB(255, 248, 220)) or C().card })
			txt(c, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 14, TextWrapped = true, Text = string.format("%s <b>%s</b>  <font color='#8a8f9a'>(%d/%d)</font>", done and "🏆" or "🔒", a.name[State.lang], math.min(math.floor(st[a.stat] or 0), a.goal), a.goal) })
		end
	end,
}

---------------------------------------------------------------------------
-- App: Einstellungen
---------------------------------------------------------------------------
local applyTheme: () -> ()
local applyBrightness: () -> ()

APPS.settings = {
	title = { de = "Einstellungen", en = "Settings" },
	icon = "⚙️",
	size = Vector2.new(720, 600),
	live = { player = true },
	render = function(body, _win)
		local ps = State.player
		if not ps then
			return
		end
		local s = ps.settings
		local sc = scroll(body, { Name = "Settings", Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 1, -28) })
		list(false, 8).Parent = sc
		pad(2, 2, 10, 10).Parent = sc
		local order = 0
		local function section(text: string)
			order += 1
			txt(sc, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 32), Font = F.black, TextSize = 18, Text = text, TextYAlignment = Enum.TextYAlignment.Bottom })
		end
		local function row(text: string, sub: string?): Frame
			order += 1
			local r = card(sc, { LayoutOrder = order, Size = UDim2.new(1, -6, 0, sub and 62 or 52) })
			txt(r, { Position = UDim2.fromOffset(16, sub and 9 or 0), Size = UDim2.new(0.5, 0, 0, sub and 24 or 52), Font = F.bold, TextSize = 15, Text = text })
			if sub then
				txt(r, { Position = UDim2.fromOffset(16, 32), Size = UDim2.new(0.55, 0, 0, 20), TextSize = 13, TextColor3 = C().dim, Text = sub })
			end
			return r
		end
		local function send(args)
			State.Request("SetSettings", args)
		end
		section(tr("Spiel", "Game"))
		local r1 = row("🌐 " .. tr("Sprache", "Language"))
		for i, l in ipairs({ { "de", "Deutsch" }, { "en", "English" } }) do
			textBtn({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16 - (2 - i) * 122, 0.5, 0), Size = UDim2.fromOffset(114, 34), BackgroundColor3 = s.lang == l[1] and BLUE or C().win, TextColor3 = s.lang == l[1] and Color3.new(1, 1, 1) or C().text, Text = l[2], Parent = r1 }, function()
				send({ lang = l[1] })
			end)
		end
		for _, key in ipairs({ "sfx", "ambience" }) do
			local r = row((key == "sfx" and "🔊 " or "🎵 ") .. (key == "sfx" and tr("Effekte", "Effects") or tr("Umgebung", "Ambience")))
			local pct = txt(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(50, 20), TextXAlignment = Enum.TextXAlignment.Right, Font = F.bold, Text = string.format("%d%%", math.floor((s[key] or 0.5) * 100 + 0.5)) })
			slider(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -76, 0.5, 0), Size = UDim2.fromOffset(240, 30) }, s[key] or 0.5, BLUE, function(v, final)
				pct.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
				if final then
					send({ [key] = v })
				end
			end)
		end
		local r4 = row("💡 " .. tr("Tipps anzeigen", "Show hints"))
		switch(r4, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0) }, s.hints, function(on)
			send({ hints = on })
		end)
		if ps.isOwner then
			local r5 = row("🎓 " .. tr("Tutorial", "Tutorial"), tr("Die Einführung noch einmal spielen", "Play the introduction again"))
			textBtn({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(160, 34), BackgroundColor3 = C().win, Text = tr("Wiederholen", "Replay"), Parent = r5 }, function()
				State.Request("ReplayTutorial")
			end)
		end
		section(tr("Laptop", "Laptop"))
		local rb = row("☀️ " .. tr("Helligkeit", "Brightness"))
		slider(rb, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(300, 30) }, OS.brightness, Color3.fromRGB(245, 166, 35), function(v)
			OS.brightness = math.max(0.15, v)
			applyBrightness()
		end)
		local rd = row("🌙 " .. tr("Dunkler Modus", "Dark mode"))
		switch(rd, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0) }, OS.dark, function(on)
			OS.dark = on
			task.delay(0.22, applyTheme)
		end)
		local rw = row("🖼️ " .. tr("Hintergrund", "Wallpaper"))
		for i, cols in ipairs(WALLPAPERS) do
			local sw = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16 - (#WALLPAPERS - i) * 62, 0.5, 0), Size = UDim2.fromOffset(54, 34), Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), Parent = rw }, { corner(8) })
			Kit.gradient(cols[1], cols[3], 35).Parent = sw
			if OS.wallpaper == i then
				stroke(BLUE, 0, 3).Parent = sw
			end
			Kit.hover(sw, 0.08)
			sw.Activated:Connect(function()
				OS.wallpaper = i
				applyWallpaper()
				rerender("player")
				for _, w in pairs(windows) do
					if w.id == "settings" then
						renderWin(w)
					end
				end
			end)
		end
		section(tr("Steuerung", "Controls"))
		order += 1
		local info = card(sc, { LayoutOrder = order, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
		pad(16, 12).Parent = info
		txt(info, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 14, TextColor3 = C().dim, Text = tr("[E] Aktion · [R] zweite Aktion · [F] Kunde bedienen · gedrückt halten = Fleisch schneiden · [Shift] schneller gehen · [Alt] halten / [C] = Maus · [U] [L] [G] [O] Laptop-Apps · [Rücktaste] Laptop zuklappen", "[E] action · [R] second action · [F] serve customer · hold = carve meat · [Shift] walk faster · hold [Alt] / [C] = mouse · [U] [L] [G] [O] laptop apps · [Backspace] close laptop") })
	end,
}

---------------------------------------------------------------------------
-- App: Rechner (calculator)
---------------------------------------------------------------------------
local calc = { display = "0", acc = nil :: number?, op = nil :: string?, fresh = true, expr = "" }

local function calcFormat(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "Error"
	end
	local s = string.format("%.10g", n)
	return (string.gsub(s, "%.", ","))
end

local function calcValue(): number
	return tonumber((string.gsub(calc.display, ",", "."))) or 0
end

local function calcApply(a: number, op: string, b: number): number
	if op == "+" then
		return a + b
	elseif op == "−" then
		return a - b
	elseif op == "×" then
		return a * b
	elseif op == "÷" then
		return b == 0 and 0 / 0 or a / b
	end
	return b
end

local function calcPress(k: string)
	if k == "C" then
		calc.display, calc.acc, calc.op, calc.fresh, calc.expr = "0", nil, nil, true, ""
	elseif k == "⌫" then
		calc.display = #calc.display > 1 and string.sub(calc.display, 1, -2) or "0"
	elseif k == "±" then
		calc.display = calcFormat(-calcValue())
	elseif k == "%" then
		calc.display = calcFormat(calcValue() / 100)
	elseif k == "," then
		if calc.fresh then
			calc.display, calc.fresh = "0,", false
		elseif not string.find(calc.display, ",") then
			calc.display ..= ","
		end
	elseif tonumber(k) then
		if calc.fresh or calc.display == "0" then
			calc.display, calc.fresh = k, false
		elseif #calc.display < 14 then
			calc.display ..= k
		end
	elseif k == "=" then
		if calc.op and calc.acc then
			calc.expr = calcFormat(calc.acc) .. " " .. calc.op .. " " .. calc.display .. " ="
			calc.display = calcFormat(calcApply(calc.acc, calc.op, calcValue()))
			calc.acc, calc.op, calc.fresh = nil, nil, true
		end
	else -- operator
		if calc.op and calc.acc and not calc.fresh then
			calc.acc = calcApply(calc.acc, calc.op, calcValue())
			calc.display = calcFormat(calc.acc :: number)
		else
			calc.acc = calcValue()
		end
		calc.op, calc.fresh = k, true
		calc.expr = calcFormat(calc.acc :: number) .. " " .. k
	end
end

APPS.calc = {
	title = { de = "Rechner", en = "Calculator" },
	icon = "🧮",
	size = Vector2.new(340, 500),
	render = function(body, win)
		local exprL = txt(body, { Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -36, 0, 22), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 15, TextColor3 = C().dim, Text = calc.expr })
		local disp = txt(body, { Position = UDim2.fromOffset(18, 36), Size = UDim2.new(1, -36, 0, 64), TextXAlignment = Enum.TextXAlignment.Right, Font = F.bold, TextSize = 48, TextScaled = false, Text = calc.display })
		local function refresh()
			exprL.Text = calc.expr
			disp.Text = calc.display
			disp.TextSize = #calc.display > 10 and 32 or 48
		end
		win.state.refresh = refresh
		local grid = new("Frame", { Position = UDim2.fromOffset(12, 112), Size = UDim2.new(1, -24, 1, -124), BackgroundTransparency = 1, Parent = body })
		new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0.2, -6), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		local keys = { "C", "⌫", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "±", "0", ",", "=" }
		for i, k in ipairs(keys) do
			local isOp = k == "÷" or k == "×" or k == "−" or k == "+"
			local isEq = k == "="
			textBtn({ LayoutOrder = i, Text = k, TextSize = 22, Font = tonumber(k) and F.medium or F.bold, BackgroundColor3 = isEq and BLUE or (isOp and C().title or C().card), TextColor3 = isEq and Color3.new(1, 1, 1) or C().text, Quiet = true, Parent = grid }, function()
				Sound.Play("add")
				calcPress(k)
				refresh()
			end)
		end
		refresh()
	end,
}

---------------------------------------------------------------------------
-- App: Notizen
---------------------------------------------------------------------------
APPS.notes = {
	title = { de = "Notizen", en = "Notes" },
	icon = "📝",
	size = Vector2.new(560, 460),
	render = function(body, _win)
		local tb = new("TextBox", {
			Position = UDim2.fromOffset(16, 14),
			Size = UDim2.new(1, -32, 1, -56),
			BackgroundColor3 = OS.dark and C().input or Color3.fromRGB(255, 252, 228),
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			MultiLine = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = F.regular,
			TextSize = 17,
			TextColor3 = C().text,
			PlaceholderText = tr("Notizen für die Schicht … z. B. „Kalb nachbestellen“", "Notes for the shift … e.g. 'restock veal'"),
			PlaceholderColor3 = C().dim,
			Text = OS.notes,
			Parent = body,
		}, { corner(8), pad(12) })
		local status = txt(body, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -10), Size = UDim2.new(1, -36, 0, 22), TextSize = 13, TextColor3 = C().dim, Text = "" })
		local function upd()
			local words = 0
			for _ in string.gmatch(tb.Text, "%S+") do
				words += 1
			end
			status.Text = string.format("%d %s · %d %s", words, tr("Wörter", "words"), utf8.len(tb.Text) or #tb.Text, tr("Zeichen", "characters"))
		end
		upd()
		tb:GetPropertyChangedSignal("Text"):Connect(function()
			OS.notes = tb.Text
			upd()
		end)
		tb.FocusLost:Connect(function()
			status.Text = "✓ " .. tr("Gespeichert", "Saved")
			status.TextTransparency = 0
			tween(status, 1.2, { TextTransparency = 0.5 }, Enum.EasingStyle.Quad, nil, 1)
		end)
	end,
}

---------------------------------------------------------------------------
-- Desktop, taskbar, start menu, quick settings, notification centre, lock screen
---------------------------------------------------------------------------
local closePopups: () -> ()
local lockNow: () -> ()

local function buildDesktop()
	desktop = new("Frame", { Name = "Desktop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = screen })
	wallpaper(desktop, 0)
	local icons = new("Frame", { Name = "Icons", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(0, 220, 1, -TASKBAR - 28), BackgroundTransparency = 1, ZIndex = 2, Parent = desktop })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(100, 96), CellPadding = UDim2.fromOffset(6, 6), FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, Parent = icons })
	refs.desktopIcons = {}
	for i, id in ipairs(APP_ORDER) do
		local app = APPS[id]
		local b = new("TextButton", { LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = icons }, { corner(8) })
		label({ Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 46), TextSize = 38, TextXAlignment = Enum.TextXAlignment.Center, Text = app.icon, Parent = b })
		local nameL = label({ Name = "Name", Position = UDim2.fromOffset(4, 56), Size = UDim2.new(1, -8, 0, 34), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextStrokeTransparency = 0.55, Text = "", Parent = b })
		refs.desktopIcons[id] = nameL
		local last = 0
		b.MouseEnter:Connect(function()
			tween(b, 0.12, { BackgroundTransparency = 0.82 })
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.15, { BackgroundTransparency = 1 })
		end)
		b.Activated:Connect(function()
			-- double click opens (touch: single tap)
			if os.clock() - last < 0.45 or UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
				Sound.Play("click")
				openApp(id)
				last = 0
			else
				last = os.clock()
				tween(b, 0.1, { BackgroundTransparency = 0.7 })
			end
		end)
	end
	winLayer = new("Frame", { Name = "Windows", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = screen })
	toastLayer = new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -TASKBAR - 14), Size = UDim2.fromOffset(360, 400), BackgroundTransparency = 1, ZIndex = 8, Parent = screen })
	local tl = list(false, 10, nil, Enum.VerticalAlignment.Bottom)
	tl.Parent = toastLayer
end

local function trayIconButton(parent: Instance, order: number, w: number): TextButton
	local b = new("TextButton", { LayoutOrder = order, Size = UDim2.fromOffset(w, 40), BackgroundColor3 = C().hover, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = parent }, { corner(6) })
	b.MouseEnter:Connect(function()
		tween(b, 0.12, { BackgroundTransparency = 0.3 })
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.15, { BackgroundTransparency = 1 })
	end)
	return b
end

local toggleStart: () -> ()
local toggleQuick: () -> ()
local toggleNotif: () -> ()

local function buildTaskbar()
	taskbar = new("Frame", { Name = "Taskbar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, TASKBAR), BorderSizePixel = 0, BackgroundTransparency = 0.08, ZIndex = 6, Parent = screen })
	theme(taskbar, "BackgroundColor3", "bar")
	local topLine = new("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Parent = taskbar })
	theme(topLine, "BackgroundColor3", "line")
	-- left widget: today's revenue
	local widget = trayIconButton(taskbar, 0, 170)
	widget.Position = UDim2.fromOffset(8, 6)
	refs.widget = label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, Font = F.medium, Text = "", Parent = widget })
	theme(refs.widget, "TextColor3", "text")
	widget.Activated:Connect(function()
		openApp("stats")
	end)
	-- centre: start + pinned apps
	local center = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = taskbar })
	list(true, 4, nil, Enum.VerticalAlignment.Center).Parent = center
	local start = trayIconButton(center, 0, 44)
	label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 24, TextColor3 = ACCENT, Text = "◆", Parent = start })
	start.Activated:Connect(function()
		toggleStart()
	end)
	refs.taskButtons = {}
	refs.taskIndicators = {}
	for i, id in ipairs(APP_ORDER) do
		local b = trayIconButton(center, i, 44)
		b.Name = "Task_" .. id
		label({ Size = UDim2.new(1, 0, 1, -4), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 22, Text = APPS[id].icon, Parent = b })
		local ind = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.fromOffset(0, 3), BackgroundColor3 = C().dim, BorderSizePixel = 0, Parent = b }, { round() })
		refs.taskButtons[id] = b
		refs.taskIndicators[id] = ind
		b.Activated:Connect(function()
			local w = windows[id]
			if w and focused == id and not w.minimized then
				minimizeWin(id)
			else
				openApp(id)
			end
		end)
	end
	-- right: tray
	local tray = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = taskbar })
	list(true, 2, nil, Enum.VerticalAlignment.Center).Parent = tray
	local sys = trayIconButton(tray, 1, 132)
	local sysRow = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = sys })
	list(true, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent = sysRow
	refs.wifiL = label({ LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Text = "📶", Parent = sysRow })
	refs.volL = label({ LayoutOrder = 2, Size = UDim2.fromOffset(22, 22), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Text = "🔊", Parent = sysRow })
	-- battery icon
	local bat = new("Frame", { LayoutOrder = 3, Size = UDim2.fromOffset(26, 13), BackgroundTransparency = 1, Parent = sysRow })
	local shell = new("Frame", { Size = UDim2.new(1, -3, 1, 0), BackgroundTransparency = 1, Parent = bat }, { corner(3) })
	local shellStroke = stroke(C().text, 0.1, 1.5)
	shellStroke.Parent = shell
	theme(shellStroke, "Color", "text")
	local nub = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(2, 5), BorderSizePixel = 0, Parent = bat })
	theme(nub, "BackgroundColor3", "text")
	refs.batFill = new("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(0.8, -4, 1, -4), BackgroundColor3 = Kit.T.green, BorderSizePixel = 0, Parent = shell }, { corner(1) })
	refs.batPct = label({ LayoutOrder = 4, Size = UDim2.fromOffset(34, 22), TextSize = 13, Font = F.medium, Text = "", Parent = sysRow })
	theme(refs.batPct, "TextColor3", "text")
	sys.Activated:Connect(function()
		toggleQuick()
	end)
	local clockB = trayIconButton(tray, 2, 92)
	refs.trayTime = label({ Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, Font = F.medium, Text = "", Parent = clockB })
	refs.trayDate = label({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, Text = "", Parent = clockB })
	theme(refs.trayTime, "TextColor3", "text")
	theme(refs.trayDate, "TextColor3", "text")
	clockB.Activated:Connect(function()
		toggleNotif()
	end)
	local bell = trayIconButton(tray, 3, 40)
	label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 17, Text = "🔔", Parent = bell })
	refs.badge = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = ACCENT, TextColor3 = Color3.new(1, 1, 1), Font = F.bold, TextSize = 11, Text = "", Visible = false, Parent = bell }, { round() })
	bell.Activated:Connect(function()
		toggleNotif()
	end)
end

updateTaskbar = function()
	if not refs.taskIndicators then
		return
	end
	for id, ind in pairs(refs.taskIndicators) do
		local w = windows[id]
		local width = (w and focused == id and not w.minimized) and 18 or (w and 6 or 0)
		tween(ind, 0.25, { Size = UDim2.fromOffset(width, 3), BackgroundColor3 = (focused == id) and ACCENT or C().dim })
	end
end

updateTray = function()
	if not refs.trayTime then
		return
	end
	refs.trayTime.Text = clockText()
	refs.trayDate.Text = string.format("%s %d", tr("Tag", "Day"), State.shop and State.shop.day or 1)
	refs.wifiL.Text = OS.wifi and "📶" or "✈️"
	local sfx = State.player and State.player.settings and State.player.settings.sfx or 0.5
	refs.volL.Text = sfx <= 0.01 and "🔇" or (sfx < 0.5 and "🔉" or "🔊")
	local b = math.floor(OS.battery + 0.5)
	refs.batPct.Text = b .. "%"
	refs.batFill.Size = UDim2.new(b / 100, -4, 1, -4)
	refs.batFill.BackgroundColor3 = b <= 20 and Kit.T.red or (b <= 40 and Kit.T.orange or Kit.T.green)
	refs.badge.Text = tostring(math.min(OS.unread, 99))
	refs.badge.Visible = OS.unread > 0
	local shop = State.shop
	refs.widget.Text = string.format("📈 %s %s", tr("Heute", "Today"), money(shop and shop.dayStats and shop.dayStats.revenue))
	if refs.lockTime then
		refs.lockTime.Text = clockText()
		refs.lockDate.Text = dateText()
	end
	if refs.qsBattery then
		refs.qsBattery.Text = string.format("🔋 %d %%  ·  %s", b, tr("Akkubetrieb", "On battery"))
	end
end

-- popups -------------------------------------------------------------------
local function popup(name: string, size: Vector2, anchor: Vector2, pos: UDim2): Frame
	local p = new("Frame", { Name = name, AnchorPoint = anchor, Position = pos, Size = UDim2.fromOffset(size.X, size.Y), BorderSizePixel = 0, Visible = false, ZIndex = 1, Parent = popLayer }, { corner(12), stroke(Color3.new(0, 0, 0), 0.82, 1) })
	theme(p, "BackgroundColor3", "win")
	p:SetAttribute("Home", pos)
	return p
end

local function showPopup(p: Frame, show: boolean, fromSide: string?)
	local home = p:GetAttribute("Home") :: UDim2
	local off = fromSide == "right" and UDim2.fromOffset(40, 0) or UDim2.fromOffset(0, 40)
	if show then
		p.Visible = true
		p.Position = home + off
		tween(p, 0.3, { Position = home })
	else
		local tw = tween(p, 0.18, { Position = home + off }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tw.Completed:Connect(function()
			if p.Position ~= home then
				p.Visible = false
			end
		end)
	end
end

local renderStart: (string) -> ()

local function buildStartMenu()
	local p = popup("Start", Vector2.new(600, 560), Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -TASKBAR - 10))
	refs.start = p
	local search = new("TextBox", { Position = UDim2.fromOffset(24, 22), Size = UDim2.new(1, -48, 0, 40), BorderSizePixel = 0, ClearTextOnFocus = false, Font = F.regular, TextSize = 16, Text = "", TextXAlignment = Enum.TextXAlignment.Left, Parent = p }, { corner(20), pad(18, 0) })
	theme(search, "BackgroundColor3", "input")
	theme(search, "TextColor3", "text")
	theme(search, "PlaceholderColor3", "dim")
	refs.search = search
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(24, 84), Size = UDim2.new(1, -48, 1, -170), BackgroundTransparency = 1, Parent = p })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(128, 104), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	refs.startGrid = grid
	local foot = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 68), BorderSizePixel = 0, Parent = p }, { corner(12) })
	theme(foot, "BackgroundColor3", "title")
	local avatar = new("ImageLabel", { Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Color3.fromRGB(200, 200, 205), Image = "", Parent = foot }, { round() })
	refs.startAvatar = avatar
	local nm = label({ Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -200, 1, 0), Font = F.bold, TextSize = 15, Text = player.DisplayName, Parent = foot })
	theme(nm, "TextColor3", "text")
	local power = trayIconButton(foot, 1, 44)
	power.AnchorPoint = Vector2.new(1, 0.5)
	power.Position = UDim2.new(1, -20, 0.5, 0)
	local pl = label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = F.bold, TextSize = 20, Text = "⏻", Parent = power })
	theme(pl, "TextColor3", "text")
	-- power menu
	local pm = new("Frame", { Name = "PowerMenu", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -72), Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = p }, { corner(10), stroke(Color3.new(0, 0, 0), 0.8), pad(6) })
	theme(pm, "BackgroundColor3", "card")
	list(false, 2).Parent = pm
	refs.powerMenu = pm
	local function pmItem(order: number, text: string, fn: () -> ())
		local b = new("TextButton", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C().hover, BackgroundTransparency = 1, AutoButtonColor = false, Font = F.medium, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Text = text, ZIndex = 5, Parent = pm }, { corner(6), pad(12, 0) })
		theme(b, "TextColor3", "text")
		b.MouseEnter:Connect(function()
			tween(b, 0.1, { BackgroundTransparency = 0 })
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.12, { BackgroundTransparency = 1 })
		end)
		b.Activated:Connect(function()
			Sound.Play("click")
			pm.Visible = false
			fn()
		end)
		return b
	end
	refs.pmLock = pmItem(1, "", function()
		closePopups()
		lockNow()
	end)
	refs.pmSleep = pmItem(2, "", function()
		closePopups()
		Laptop.Close()
	end)
	refs.pmClose = pmItem(3, "", function()
		closePopups()
		local res = State.Request("CloseShop")
		if res and res.ok then
			Laptop.Close()
		else
			Laptop.Notify("🔑 " .. tr("Noch nicht Feierabend", "Not closing time yet"), tr("Den Laden kannst du erst ab 22:00 Uhr absperren.", "You can only lock the shop after 22:00."), "🕙")
		end
	end)
	power.Activated:Connect(function()
		pm.Visible = not pm.Visible
		if pm.Visible then
			Kit.pop(pm, 0.9, 0.2)
		end
	end)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		renderStart(search.Text)
	end)
	search.FocusLost:Connect(function(enter)
		if enter then
			-- open the first match
			for _, c in ipairs(grid:GetChildren()) do
				if c:IsA("TextButton") then
					local id = c:GetAttribute("App")
					closePopups()
					openApp(id)
					break
				end
			end
		end
	end)
end

renderStart = function(query: string)
	local grid = refs.startGrid
	Kit.clear(grid, { "UIGridLayout" })
	local q = string.lower(query or "")
	local n = 0
	for i, id in ipairs(APP_ORDER) do
		local app = APPS[id]
		local name = app.title[State.lang]
		if q == "" or string.find(string.lower(name), q, 1, true) then
			n += 1
			local b = new("TextButton", { LayoutOrder = i, BackgroundColor3 = C().hover, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = grid }, { corner(8) })
			b:SetAttribute("App", id)
			label({ Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 44), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Text = app.icon, Parent = b })
			label({ Position = UDim2.fromOffset(6, 58), Size = UDim2.new(1, -12, 0, 38), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C().text, Text = name, Parent = b })
			b.MouseEnter:Connect(function()
				tween(b, 0.1, { BackgroundTransparency = 0 })
			end)
			b.MouseLeave:Connect(function()
				tween(b, 0.12, { BackgroundTransparency = 1 })
			end)
			b.Activated:Connect(function()
				Sound.Play("click")
				closePopups()
				openApp(id)
			end)
			Kit.pop(b, 0.85, 0.25, n * 0.02)
		end
	end
	if n == 0 then
		local l = label({ Size = UDim2.fromOffset(300, 40), TextColor3 = C().dim, Text = tr("Keine Ergebnisse", "No results"), Parent = grid })
		local _ = l
	end
end

local function buildQuick()
	local p = popup("Quick", Vector2.new(380, 330), Vector2.new(1, 1), UDim2.new(1, -10, 1, -TASKBAR - 10))
	refs.quick = p
	local tiles = new("Frame", { Position = UDim2.fromOffset(18, 18), Size = UDim2.new(1, -36, 0, 84), BackgroundTransparency = 1, Parent = p })
	new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 1, 0), CellPadding = UDim2.fromOffset(12, 0), Parent = tiles })
	local function tile(icon: string, name: string, get: () -> boolean, set: (boolean) -> ())
		local b = new("TextButton", { AutoButtonColor = false, Text = "", BorderSizePixel = 0, Parent = tiles }, { corner(10) })
		label({ Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 30), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Text = icon, Parent = b })
		local n = label({ Position = UDim2.fromOffset(4, 46), Size = UDim2.new(1, -8, 0, 30), TextSize = 13, TextWrapped = true, Font = F.medium, TextXAlignment = Enum.TextXAlignment.Center, Text = name, Parent = b })
		local function paint()
			local on = get()
			tween(b, 0.18, { BackgroundColor3 = on and BLUE or C().card })
			n.TextColor3 = on and Color3.new(1, 1, 1) or C().text
		end
		paint()
		b.Activated:Connect(function()
			Sound.Play("click")
			set(not get())
			paint()
			updateTray()
		end)
		b:SetAttribute("Tile", true)
		table.insert(refs.qsTiles, paint)
		Kit.hover(b, 0.03)
	end
	refs.qsTiles = {}
	tile("📶", tr("WLAN", "Wi-Fi"), function()
		return OS.wifi
	end, function(v)
		OS.wifi = v
		rerender("shop")
	end)
	tile("🔕", tr("Nicht stören", "Do not disturb"), function()
		return OS.dnd
	end, function(v)
		OS.dnd = v
	end)
	tile("🌙", tr("Dunkel", "Dark"), function()
		return OS.dark
	end, function(v)
		OS.dark = v
		task.delay(0.05, applyTheme)
	end)
	local function sliderRow(y: number, icon: string, value: number, color: Color3, fn: (number, boolean) -> ())
		label({ Position = UDim2.fromOffset(18, y), Size = UDim2.fromOffset(30, 30), TextSize = 18, Text = icon, Parent = p })
		slider(p, { Position = UDim2.fromOffset(58, y), Size = UDim2.new(1, -84, 0, 30) }, value, color, fn)
	end
	sliderRow(124, "☀️", OS.brightness, Color3.fromRGB(245, 166, 35), function(v)
		OS.brightness = math.max(0.15, v)
		applyBrightness()
	end)
	local sfx = State.player and State.player.settings and State.player.settings.sfx or 0.5
	sliderRow(172, "🔊", sfx, BLUE, function(v, final)
		if final then
			State.Request("SetSettings", { sfx = v })
		end
	end)
	local line = new("Frame", { Position = UDim2.fromOffset(0, 226), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Parent = p })
	theme(line, "BackgroundColor3", "line")
	refs.qsBattery = label({ Position = UDim2.fromOffset(18, 236), Size = UDim2.new(1, -36, 0, 24), TextSize = 14, Text = "", Parent = p })
	theme(refs.qsBattery, "TextColor3", "text")
	local net = label({ Position = UDim2.fromOffset(18, 262), Size = UDim2.new(1, -36, 0, 24), TextSize = 14, Text = "", Parent = p })
	theme(net, "TextColor3", "dim")
	refs.qsNet = net
	local edit = textBtn({ Position = UDim2.fromOffset(18, 290), Size = UDim2.new(1, -36, 0, 30), TextSize = 13, Text = "⚙️ " .. tr("Alle Einstellungen", "All settings"), Parent = p }, function()
		closePopups()
		openApp("settings")
	end)
	theme(edit, "BackgroundColor3", "card")
	theme(edit, "TextColor3", "text")
end

renderNotifCenter = function()
	local p = refs.notif
	if not p then
		return
	end
	local listF = p:FindFirstChild("List") :: ScrollingFrame
	Kit.clear(listF, { "UIListLayout", "UIPadding" })
	if #OS.notifications == 0 then
		label({ Size = UDim2.new(1, 0, 0, 60), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C().dim, TextSize = 14, Text = tr("Keine neuen Benachrichtigungen", "No new notifications"), Parent = listF })
	end
	for i, n in ipairs(OS.notifications) do
		local c = new("TextButton", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C().card, AutoButtonColor = false, Text = "", BorderSizePixel = 0, Parent = listF }, { corner(10) })
		label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 34, 1, 0), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Text = n.icon, Parent = c })
		label({ Position = UDim2.fromOffset(52, 8), Size = UDim2.new(1, -110, 0, 20), Font = F.bold, TextSize = 14, TextColor3 = C().text, TextTruncate = Enum.TextTruncate.AtEnd, Text = n.title, Parent = c })
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(50, 20), TextSize = 12, TextColor3 = C().dim, TextXAlignment = Enum.TextXAlignment.Right, Text = n.time, Parent = c })
		label({ Position = UDim2.fromOffset(52, 30), Size = UDim2.new(1, -62, 0, 28), TextSize = 13, TextColor3 = C().dim, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top, Text = n.text, Parent = c })
		c.Activated:Connect(function()
			if n.onClick then
				closePopups()
				n.onClick()
			end
		end)
	end
	-- calendar of the real current month
	local cal = p:FindFirstChild("Calendar") :: Frame
	Kit.clear(cal)
	local t = os.date("*t") :: any
	local lang = State.lang == "de" and "de" or "en"
	label({ Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 24), Font = F.bold, TextSize = 15, TextColor3 = C().text, Text = string.format("%s %d", MONTHS[lang][t.month], t.year), Parent = cal })
	local grid = new("Frame", { Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 1, -42), BackgroundTransparency = 1, Parent = cal })
	new("UIGridLayout", { CellSize = UDim2.new(1 / 7, 0, 1 / 7, 0), CellPadding = UDim2.new(), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	local heads = lang == "de" and { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" } or { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }
	local order = 0
	for _, h in ipairs(heads) do
		order += 1
		label({ LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, Font = F.bold, TextColor3 = C().dim, Text = h, Parent = grid })
	end
	local first = os.date("*t", os.time({ year = t.year, month = t.month, day = 1, hour = 12 })) :: any
	local offset = (first.wday + 5) % 7 -- Monday first
	local days = (os.date("*t", os.time({ year = t.year, month = t.month + 1, day = 0, hour = 12 })) :: any).day
	for _ = 1, offset do
		order += 1
		new("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Parent = grid })
	end
	for d = 1, days do
		order += 1
		local today = d == t.day
		local cell = new("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Parent = grid })
		local l = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, Font = today and F.bold or F.regular, TextColor3 = today and Color3.new(1, 1, 1) or C().text, BackgroundColor3 = BLUE, BackgroundTransparency = today and 0 or 1, Text = tostring(d), Parent = cell })
		round().Parent = l
	end
end

local function buildNotif()
	local p = popup("Notif", Vector2.new(380, H - TASKBAR - 20), Vector2.new(1, 1), UDim2.new(1, -10, 1, -TASKBAR - 10))
	refs.notif = p
	local head = label({ Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -150, 0, 30), Font = F.bold, TextSize = 16, Text = "", Parent = p })
	theme(head, "TextColor3", "text")
	refs.notifHead = head
	local clearB = textBtn({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(120, 28), TextSize = 13, Text = "", Parent = p }, function()
		OS.notifications = {}
		renderNotifCenter()
	end)
	refs.notifClear = clearB
	theme(clearB, "BackgroundColor3", "card")
	theme(clearB, "TextColor3", "text")
	local listF = scroll(p, { Name = "List", Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 1, -350) })
	list(false, 8).Parent = listF
	pad(2, 2, 8, 2).Parent = listF
	local cal = new("Frame", { Name = "Calendar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 280), BorderSizePixel = 0, Parent = p }, { corner(10) })
	theme(cal, "BackgroundColor3", "card")
end

closePopups = function()
	for _, key in ipairs({ "start", "quick", "notif" }) do
		local p = refs[key]
		if p and p.Visible then
			showPopup(p, false, key == "notif" and "right" or nil)
		end
	end
	refs.notifOpen = false
	if refs.powerMenu then
		refs.powerMenu.Visible = false
	end
end

toggleStart = function()
	local p = refs.start
	local show = not p.Visible
	closePopups()
	if show then
		refs.search.Text = ""
		refs.search.PlaceholderText = tr("🔎  Apps durchsuchen", "🔎  Search apps")
		refs.pmLock.Text = "🔒  " .. tr("Sperren", "Lock")
		refs.pmSleep.Text = "💤  " .. tr("Zuklappen (Energie sparen)", "Close lid (sleep)")
		local after = State.shop and State.shop.phase == "after_hours"
		refs.pmClose.Text = (after and "🌙  " or "🕙  ") .. tr("Feierabend – Laden absperren", "Closing time – lock the shop")
		refs.pmClose.TextTransparency = after and 0 or 0.45
		renderStart("")
		showPopup(p, true)
	end
end

toggleQuick = function()
	local p = refs.quick
	local show = not p.Visible
	closePopups()
	if show then
		for _, paint in ipairs(refs.qsTiles) do
			paint()
		end
		refs.qsNet.Text = OS.wifi and ("📶 " .. tr("Verbunden · KebapHaus-WLAN", "Connected · KebapHaus-WiFi")) or ("✈️ " .. tr("Nicht verbunden", "Not connected"))
		updateTray()
		showPopup(p, true)
	end
end

toggleNotif = function()
	local p = refs.notif
	local show = not p.Visible
	closePopups()
	if show then
		OS.unread = 0
		refs.notifHead.Text = tr("Benachrichtigungen", "Notifications")
		refs.notifClear.Text = tr("Alle löschen", "Clear all")
		refs.notifOpen = true
		renderNotifCenter()
		updateTray()
		showPopup(p, true, "right")
	end
end

-- lock screen --------------------------------------------------------------
local unlocking = false

local function unlock()
	if not OS.locked or unlocking then
		return
	end
	unlocking = true
	local dots = refs.lockDots
	task.spawn(function()
		for i = 1, 6 do
			dots.Text = string.rep("●", i)
			Sound.Play("add")
			task.wait(0.06)
		end
		task.wait(0.15)
		OS.locked = false
		tween(lockScreen, 0.5, { Position = UDim2.fromScale(0, -1) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(0.5)
		lockScreen.Visible = false
		unlocking = false
		dots.Text = ""
		-- desktop icons pop in
		local i = 0
		for _, c in ipairs((desktop:FindFirstChild("Icons") :: Instance):GetChildren()) do
			if c:IsA("GuiButton") then
				i += 1
				Kit.pop(c, 0.6, 0.35, i * 0.04)
			end
		end
		if OS.unread > 0 then
			Laptop.Notify(tr("Willkommen zurück", "Welcome back"), string.format(tr("%d neue Benachrichtigung(en)", "%d new notification(s)"), OS.unread), "👋", function()
				toggleNotif()
			end)
		end
	end)
end

lockNow = function()
	OS.locked = true
	lockScreen.Visible = true
	lockScreen.Position = UDim2.fromScale(0, -1)
	tween(lockScreen, 0.45, { Position = UDim2.fromScale(0, 0) }, Enum.EasingStyle.Quint)
end

local function buildLockScreen()
	lockScreen = new("TextButton", { Name = "Lock", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 20, Parent = screen })
	local wp = wallpaper(lockScreen, 20)
	local dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 21, Parent = wp })
	local _ = dim
	refs.lockTime = label({ Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 130), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 128, Text = "10:00", ZIndex = 22, Parent = lockScreen })
	refs.lockDate = label({ Position = UDim2.fromOffset(0, 240), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, Font = F.medium, TextSize = 26, Text = "", ZIndex = 22, Parent = lockScreen })
	local avatar = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 400), Size = UDim2.fromOffset(110, 110), BackgroundColor3 = Color3.fromRGB(220, 220, 225), Image = "", ZIndex = 22, Parent = lockScreen }, { round(), stroke(Color3.new(1, 1, 1), 0.4, 3) })
	refs.lockAvatar = avatar
	label({ Position = UDim2.fromOffset(0, 520), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, Font = F.bold, TextSize = 24, Text = player.DisplayName, ZIndex = 22, Parent = lockScreen })
	local pw = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 566), Size = UDim2.fromOffset(300, 44), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 22, Parent = lockScreen }, { corner(8), stroke(Color3.new(1, 1, 1), 0.6, 1) })
	refs.lockDots = label({ Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -70, 1, 0), TextSize = 16, Text = "", ZIndex = 23, Parent = pw })
	local go = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = BLUE, Text = "→", TextColor3 = Color3.new(1, 1, 1), Font = F.bold, TextSize = 18, ZIndex = 23, Parent = pw }, { corner(6) })
	refs.lockHint = label({ Position = UDim2.fromOffset(0, 624), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, TextTransparency = 0.25, Text = "", ZIndex = 22, Parent = lockScreen })
	Kit.pulse(refs.lockHint, "TextTransparency", 0.15, 0.6, 1.2)
	go.Activated:Connect(unlock)
	lockScreen.Activated:Connect(unlock)
	-- avatar headshot (real Roblox thumbnail API)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and img then
			avatar.Image = img
			if refs.startAvatar then
				refs.startAvatar.Image = img
			end
		end
	end)
end

---------------------------------------------------------------------------
-- theme & brightness
---------------------------------------------------------------------------
applyTheme = function()
	for _, t in ipairs(themed) do
		if t.obj.Parent then
			(t.obj :: any)[t.prop] = (C() :: any)[t.key]
		end
	end
	for _, w in pairs(windows) do
		renderWin(w)
	end
	focusWin(focused)
end

applyBrightness = function()
	if brightOverlay then
		brightOverlay.BackgroundTransparency = math.clamp(OS.brightness, 0.15, 1) ^ 0.7
	end
	if refs.worldDim then
		refs.worldDim.BackgroundTransparency = math.clamp(OS.brightness, 0.15, 1) ^ 0.7
	end
end

---------------------------------------------------------------------------
-- physical frame (lid, bezel, base) and open / close animation
---------------------------------------------------------------------------
local LID_W, LID_H = 1320, 850

local function build()
	gui = new("ScreenGui", { Name = "LaptopGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	backdrop = new("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 6, 10), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = gui })
	holder = new("Frame", { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(1420, 900), BackgroundTransparency = 1, Active = true, Parent = gui })
	holderScale = new("UIScale", { Parent = holder })
	-- soft shadow under the laptop
	new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(1460, 28), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, BorderSizePixel = 0, Parent = holder }, { round() })
	-- base (front edge of the keyboard deck)
	local base = new("Frame", { Name = "Base", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(1420, 30), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = holder }, { corner(14) })
	Kit.gradient(Color3.fromRGB(214, 216, 220), Color3.fromRGB(142, 145, 150), 90).Parent = base
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(190, 10), BackgroundColor3 = Color3.fromRGB(120, 123, 128), BorderSizePixel = 0, ZIndex = 3, Parent = base }, { corner(5) })
	-- lid
	lid = new("Frame", { Name = "Lid", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(LID_W, LID_H), BackgroundColor3 = Color3.fromRGB(16, 16, 18), BorderSizePixel = 0, ClipsDescendants = true, Parent = holder }, { corner(26), stroke(Color3.fromRGB(150, 153, 158), 0, 3) })
	new("Frame", { Name = "Webcam", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.fromRGB(34, 40, 52), BorderSizePixel = 0, Parent = lid }, { round() })
	refs.camLed = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 14, 0, 16), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(60, 220, 100), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = lid }, { round() })
	screen = new("Frame", { Name = "Screen", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 32), Size = UDim2.fromOffset(W, H), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ClipsDescendants = true, Parent = lid }, { corner(6) })
	label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(200, 22), TextXAlignment = Enum.TextXAlignment.Center, Font = F.bold, TextSize = 13, TextColor3 = Color3.fromRGB(120, 122, 128), Text = "KebabBook Pro", Parent = lid })
	-- outside controls
	local closeBtn = Kit.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, -12), Size = UDim2.fromOffset(150, 36), BackgroundColor3 = Color3.fromRGB(30, 30, 36), TextColor3 = Color3.new(1, 1, 1), TextSize = 14, Text = "", Radius = 18, Parent = holder }, function()
		Laptop.Close()
	end)
	refs.closeBtn = closeBtn
	stroke(Color3.new(1, 1, 1), 0.8).Parent = closeBtn

	buildDesktop()
	buildTaskbar()
	popLayer = new("Frame", { Name = "Popups", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7, Parent = screen })
	buildStartMenu()
	buildQuick()
	buildNotif()
	buildLockScreen()
	brightOverlay = new("Frame", { Name = "Brightness", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = 40, Parent = screen })
	powerOverlay = new("Frame", { Name = "Power", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 50, Parent = screen })
	refs.bootLogo = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(400, 120), TextXAlignment = Enum.TextXAlignment.Center, Font = F.black, TextSize = 96, TextColor3 = ACCENT, Text = "◆", TextTransparency = 1, ZIndex = 51, Parent = powerOverlay })
	refs.bootText = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromOffset(400, 40), TextXAlignment = Enum.TextXAlignment.Center, Font = F.bold, TextSize = 24, Text = "KebabOS", TextTransparency = 1, ZIndex = 51, Parent = powerOverlay })
	refs.bootSpin = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.68), Size = UDim2.fromOffset(400, 40), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 30, Text = "", TextTransparency = 1, ZIndex = 51, Parent = powerOverlay })
end

local function fitScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return math.min(vp.X * 0.94 / 1420, vp.Y * 0.9 / 900)
end

-- freeze walking while the laptop is open (sinks the movement keys above the default controls)
local function sinkMove()
	return Enum.ContextActionResult.Sink
end

local function setControls(enabled: boolean)
	if enabled then
		ContextActionService:UnbindAction("KebapLaptopFreeze")
	else
		ContextActionService:BindActionAtPriority(
			"KebapLaptopFreeze",
			sinkMove,
			false,
			3000,
			Enum.KeyCode.W,
			Enum.KeyCode.A,
			Enum.KeyCode.S,
			Enum.KeyCode.D,
			Enum.KeyCode.Up,
			Enum.KeyCode.Down,
			Enum.KeyCode.Left,
			Enum.KeyCode.Right,
			Enum.KeyCode.Space,
			Enum.KeyCode.Thumbstick1,
			Enum.KeyCode.ButtonA
		)
	end
end

local function boot()
	OS.booted = true
	local spin = { "◜", "◝", "◞", "◟" }
	tween(refs.bootLogo, 0.4, { TextTransparency = 0 })
	tween(refs.bootText, 0.4, { TextTransparency = 0 }, nil, nil, 0.15)
	tween(refs.bootSpin, 0.4, { TextTransparency = 0 }, nil, nil, 0.3)
	for i = 1, 16 do
		refs.bootSpin.Text = spin[(i % 4) + 1]
		task.wait(0.08)
	end
	tween(refs.bootLogo, 0.25, { TextTransparency = 1 })
	tween(refs.bootText, 0.25, { TextTransparency = 1 })
	tween(refs.bootSpin, 0.25, { TextTransparency = 1 })
	task.wait(0.25)
end

function Laptop.IsOpen(): boolean
	return OS.open
end

-- the laptop stands in the office (Server/OfficeService): it only opens at the desk
Laptop.OnBlocked = function() end

function Laptop.Open(app: string?)
	if not OS.open and not nearLaptop() then
		Laptop.OnBlocked()
		return
	end
	if OS.open then
		if app then
			if OS.locked then
				unlock()
				task.delay(0.9, function()
					openApp(app)
				end)
			else
				openApp(app)
			end
		end
		return
	end
	if OS.animating then
		return
	end
	OS.open = true
	OS.animating = true
	gui.Enabled = true
	Laptop.OnOpenChanged(true)
	setControls(false)
	Sound.Play("click")
	-- refresh texts that depend on language
	refs.closeBtn.Text = "▼  " .. tr("Zuklappen", "Close")
	refs.lockHint.Text = tr("Klicken oder Enter zum Entsperren", "Click or press Enter to unlock")
	for id, l in pairs(refs.desktopIcons) do
		l.Text = APPS[id].title[State.lang]
	end
	updateTray()
	-- camera blur
	local cam = workspace.CurrentCamera
	if cam then
		blur = blur or new("BlurEffect", { Size = 0 })
		;(blur :: BlurEffect).Parent = cam
		tween(blur :: BlurEffect, 0.4, { Size = 14 })
	end
	local s = fitScale()
	holderScale.Scale = s * 0.88
	backdrop.BackgroundTransparency = 1
	tween(backdrop, 0.35, { BackgroundTransparency = 0.35 })
	tween(holderScale, 0.5, { Scale = s }, Enum.EasingStyle.Back)
	-- lid swings open
	lid.Size = UDim2.fromOffset(LID_W, 40)
	powerOverlay.BackgroundTransparency = 0
	tween(lid, 0.55, { Size = UDim2.fromOffset(LID_W, LID_H) }, Enum.EasingStyle.Quint)
	task.spawn(function()
		task.wait(0.5)
		refs.camLed.BackgroundTransparency = 0
		if not OS.booted then
			boot()
			lockScreen.Visible = true
			lockScreen.Position = UDim2.fromScale(0, 0)
		end
		tween(powerOverlay, 0.35, { BackgroundTransparency = 1 })
		task.wait(0.35)
		OS.animating = false
		if app then
			if OS.locked then
				unlock()
				task.wait(0.9)
			end
			openApp(app)
		end
	end)
end

function Laptop.Close()
	if not OS.open or OS.animating then
		return
	end
	OS.animating = true
	closePopups()
	Sound.Play("wrap")
	tween(powerOverlay, 0.18, { BackgroundTransparency = 0 })
	refs.camLed.BackgroundTransparency = 1
	task.delay(0.15, function()
		tween(lid, 0.38, { Size = UDim2.fromOffset(LID_W, 40) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(holderScale, 0.4, { Scale = fitScale() * 0.9 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(backdrop, 0.4, { BackgroundTransparency = 1 })
		if blur then
			tween(blur, 0.4, { Size = 0 })
		end
	end)
	task.delay(0.58, function()
		gui.Enabled = false
		OS.open = false
		OS.animating = false
		setControls(true)
		Laptop.OnOpenChanged(false)
	end)
end

-- which app belongs to the old panel names / hotkeys
local PANEL_APP = { upgrades = "upgrades", stock = "supplier", goals = "stats", settings = "settings", orders = "pos" }

function Laptop.Toggle(panel: string?)
	local app = panel and PANEL_APP[panel] or nil
	if OS.open then
		if not app or (focused == app and windows[app] and not windows[app].minimized) then
			Laptop.Close()
		else
			Laptop.Open(app)
		end
	else
		Laptop.Open(app or (panel == "laptop" and "pos" or nil))
	end
end

-- customer dialogue → POS conversation log
function Laptop.OnDialogue(data)
	for _, line in ipairs(data.lines or {}) do
		table.insert(OS.chat, { name = data.name or "?", emoji = data.emoji or "", text = line[State.lang] or line.en or "" })
	end
	while #OS.chat > 14 do
		table.remove(OS.chat, 1)
	end
	rerender("chat")
end

---------------------------------------------------------------------------
-- in-world laptop screen (live mini dashboard)
---------------------------------------------------------------------------
local world: { [string]: any } = {}

local function buildWorldScreen(part: BasePart)
	local sg = new("SurfaceGui", {
		Name = "LaptopWorldScreen",
		Adornee = part,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 420,
		LightInfluence = 0,
		Brightness = 1.4,
		MaxDistance = 60,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sg })
	wallpaper(root, 0)
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2, Parent = root })
	world.time = label({ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, 0, 1, 0), Font = F.bold, TextSize = 20, Text = "", ZIndex = 3, Parent = top })
	world.status = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 18, Text = "", ZIndex = 3, Parent = top })
	local panelF = new("Frame", { Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 1, -60), BackgroundColor3 = Color3.fromRGB(250, 250, 252), BackgroundTransparency = 0.04, BorderSizePixel = 0, ZIndex = 2, Parent = root }, { corner(12) })
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3, Parent = panelF }, { corner(12) })
	Kit.gradient(ACCENT, Color3.fromRGB(255, 150, 60), 0).Parent = head
	world.head = label({ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), Font = F.black, TextSize = 22, Text = "", ZIndex = 4, Parent = head })
	world.alert = label({ Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 34), Font = F.bold, TextSize = 20, TextColor3 = Color3.fromRGB(200, 110, 0), Text = "", ZIndex = 3, Parent = panelF })
	world.list = new("Frame", { Position = UDim2.fromOffset(12, 88), Size = UDim2.new(1, -24, 1, -96), BackgroundTransparency = 1, ZIndex = 3, Parent = panelF })
	list(false, 6).Parent = world.list
	world.dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10, Parent = root })
	refs.worldDim = world.dim
	world.fills = {}
end

local function updateWorldScreen()
	if not world.list then
		return
	end
	world.time.Text = clockText()
	local phase = State.shop and State.shop.phase
	world.status.Text = (phase == "after_hours" and ("🌙 " .. tr("Feierabend", "Closed")) or (State.shop and State.shop.open and ("🟢 " .. tr("Geöffnet", "Open")) or "⚪")) .. "   " .. (OS.wifi and "📶" or "✈️") .. "  " .. math.floor(OS.battery + 0.5) .. "%"
	world.head.Text = string.format("🧾 %s · %d %s", tr("Kassa", "Register"), #State.tickets, tr("offen", "open"))
	world.alert.Text = orderingCustomer() and ("🔔 " .. tr("Kunde an der Kassa – Bestellung aufnehmen!", "Customer at the register – take the order!")) or ""
	Kit.clear(world.list, { "UIListLayout" })
	world.fills = {}
	for i, t in ipairs(State.tickets) do
		if i > 4 then
			label({ LayoutOrder = i, Size = UDim2.new(1, 0, 0, 24), TextSize = 17, TextColor3 = Color3.fromRGB(110, 110, 120), Text = string.format("+ %d %s …", #State.tickets - 4, tr("weitere", "more")), ZIndex = 4, Parent = world.list })
			break
		end
		local row = new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Color3.fromRGB(240, 241, 245), BorderSizePixel = 0, ZIndex = 4, Parent = world.list }, { corner(8) })
		local first = t.items[1]
		label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -120, 0, 26), Font = F.bold, TextSize = 19, TextColor3 = Color3.fromRGB(30, 30, 36), TextTruncate = Enum.TextTruncate.AtEnd, Text = string.format("%s%s %s", t.vip and "⭐" or "", t.emoji, t.name) .. (t.takerId and (t.takerId == game:GetService("Players").LocalPlayer.UserId and "  · 👤 Du" or ("  · 🔒 " .. (t.takerName or "?"))) or ""), ZIndex = 5, Parent = row })
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(110, 26), Font = F.bold, TextSize = 19, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Right, Text = money(t.total * ((State.shop and State.shop.premium) or 1)), ZIndex = 5, Parent = row })
		label({ Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 18), TextSize = 15, TextColor3 = Color3.fromRGB(100, 104, 116), TextTruncate = Enum.TextTruncate.AtEnd, Text = first and (OrderText.Title(first) .. (#t.items > 1 and string.format(" +%d", #t.items - 1) or "")) or "", ZIndex = 5, Parent = row })
		local _, fill = Kit.bar({ Position = UDim2.new(0, 10, 1, -8), Size = UDim2.new(1, -20, 0, 4), ZIndex = 5, Parent = row }, Kit.T.green, Color3.fromRGB(220, 222, 230))
		fill.ZIndex = 6
		fill.Size = UDim2.fromScale(OrderText.Patience(t), 1)
		table.insert(world.fills, { fill = fill, ticket = t })
	end
	if #State.tickets == 0 then
		label({ Size = UDim2.new(1, 0, 0, 60), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 19, TextColor3 = Color3.fromRGB(120, 124, 136), Text = "☕ " .. tr("Keine offenen Bestellungen", "No open orders"), ZIndex = 4, Parent = world.list })
	end
end

local function patienceColor(p: number): Color3
	return p > 0.6 and Kit.T.green or (p > 0.3 and Kit.T.orange or Kit.T.red)
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------
function Laptop.Init()
	build()
	applyBrightness()
	-- walking away from the office desk closes the laptop
	task.spawn(function()
		while true do
			task.wait(0.5)
			if OS.open and not OS.animating and laptopPart() and not nearLaptop() then
				Laptop.Close()
			end
		end
	end)
	-- in-world screen
	task.spawn(function()
		local part
		repeat
			for _, p in ipairs(CollectionService:GetTagged("LaptopScreen")) do
				if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
					part = p
				end
			end
			if not part then
				task.wait(1)
			end
		until part
		buildWorldScreen(part)
		updateWorldScreen()
	end)

	-- live data
	local knownTickets: { [number]: boolean } = {}
	State.Changed:Connect(function(what)
		if what == "tickets" then
			for _, t in ipairs(State.tickets) do
				if not knownTickets[t.id] then
					knownTickets[t.id] = true
					local tid = t.id
					Laptop.Notify(string.format("🧾 %s", tr("Neue Bestellung", "New order")), string.format("%s %s · %s", t.emoji, t.name, money(t.total)), "🧾", function()
						OS.posTicket = tid
						openApp("pos")
					end)
				end
			end
			rerender("tickets")
			updateWorldScreen()
		elseif what == "selection" then
			rerender("selection")
		elseif what == "shop" then
			rerender("shop")
			updateTray()
			updateWorldScreen()
		elseif what == "player" then
			rerender("player")
			updateTray()
		end
	end)
	CollectionService:GetInstanceAddedSignal("Customer"):Connect(function(m)
		m:GetAttributeChangedSignal("State"):Connect(function()
			if m:GetAttribute("State") == "Ordering" then
				updateWorldScreen()
				if OS.open then
					rerender("customers")
				end
				Laptop.Notify("🔔 " .. tr("Kunde an der Kassa", "Customer at the register"), tr("Bestellung im Kassa-Programm aufnehmen.", "Take the order in the register app."), "🔔", function()
					openApp("pos")
				end)
			elseif OS.open then
				rerender("customers")
				updateWorldScreen()
			end
		end)
	end)

	-- Enter unlocks; keyboard input for the calculator
	UserInputService.InputBegan:Connect(function(input, processed)
		if not OS.open or processed then
			return
		end
		if OS.locked then
			if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter or input.KeyCode == Enum.KeyCode.Space then
				unlock()
			end
			return
		end
		if focused == "calc" and windows.calc then
			local map = {
				[Enum.KeyCode.Zero] = "0", [Enum.KeyCode.One] = "1", [Enum.KeyCode.Two] = "2", [Enum.KeyCode.Three] = "3", [Enum.KeyCode.Four] = "4",
				[Enum.KeyCode.Five] = "5", [Enum.KeyCode.Six] = "6", [Enum.KeyCode.Seven] = "7", [Enum.KeyCode.Eight] = "8", [Enum.KeyCode.Nine] = "9",
				[Enum.KeyCode.KeypadZero] = "0", [Enum.KeyCode.KeypadOne] = "1", [Enum.KeyCode.KeypadTwo] = "2", [Enum.KeyCode.KeypadThree] = "3", [Enum.KeyCode.KeypadFour] = "4",
				[Enum.KeyCode.KeypadFive] = "5", [Enum.KeyCode.KeypadSix] = "6", [Enum.KeyCode.KeypadSeven] = "7", [Enum.KeyCode.KeypadEight] = "8", [Enum.KeyCode.KeypadNine] = "9",
				[Enum.KeyCode.KeypadPlus] = "+", [Enum.KeyCode.KeypadMinus] = "−", [Enum.KeyCode.KeypadMultiply] = "×", [Enum.KeyCode.KeypadDivide] = "÷",
				[Enum.KeyCode.Return] = "=", [Enum.KeyCode.KeypadEnter] = "=", [Enum.KeyCode.Comma] = ",", [Enum.KeyCode.Period] = ",", [Enum.KeyCode.KeypadPeriod] = ",",
				[Enum.KeyCode.Delete] = "C", [Enum.KeyCode.Minus] = "−", [Enum.KeyCode.Slash] = "÷", [Enum.KeyCode.Asterisk] = "×", [Enum.KeyCode.Plus] = "+",
			}
			local k = map[input.KeyCode]
			if k then
				calcPress(k)
				local r = windows.calc.state.refresh
				if r then
					r()
				end
			end
		end
	end)

	-- animation & clocks
	local acc, batAcc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		if OS.open then
			-- drifting wallpaper blobs
			local t = os.clock()
			for _, f in ipairs(wallpaperFrames) do
				if f.Parent and f.Visible then
					local g = f:FindFirstChild("G") :: UIGradient
					g.Rotation = 35 + math.sin(t * 0.15) * 12
					for _, b in ipairs(f:GetChildren()) do
						if b.Name == "Blob" then
							local seed = b:GetAttribute("Seed") or 1
							b.Position = UDim2.fromScale(0.2 + seed * 0.22 + math.sin(t * 0.13 * seed + seed) * 0.06, 0.3 + (seed % 2) * 0.35 + math.cos(t * 0.11 * seed) * 0.06)
						end
					end
				end
			end
		end
		acc += dt
		batAcc += dt
		if acc >= 0.5 then
			acc = 0
			-- patience bars (laptop + world)
			for _, e in ipairs(patienceFills) do
				if e.fill.Parent then
					local p = OrderText.Patience(e.ticket)
					tween(e.fill, 0.45, { Size = UDim2.fromScale(p, 1), BackgroundColor3 = patienceColor(p) }, Enum.EasingStyle.Linear)
				end
			end
			for _, e in ipairs(world.fills or {}) do
				if e.fill.Parent then
					local p = OrderText.Patience(e.ticket)
					e.fill.Size = UDim2.fromScale(p, 1)
					e.fill.BackgroundColor3 = patienceColor(p)
				end
			end
			if world.time then
				world.time.Text = clockText()
			end
			if OS.open then
				updateTray()
			end
		end
		-- battery: drains while the laptop is in use, charges on the counter when closed
		if batAcc >= 6 then
			batAcc = 0
			local before = OS.battery
			OS.battery = math.clamp(OS.battery + (OS.open and -0.4 or 0.9), 1, 100)
			if OS.open and before > 15 and OS.battery <= 15 then
				Laptop.Notify("🪫 " .. tr("Akku schwach", "Battery low"), tr("Klapp den Laptop zu, dann lädt er an der Theke.", "Close the laptop to charge it at the counter."), "🪫")
			end
		end
	end)

	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if OS.open and not OS.animating then
				holderScale.Scale = fitScale()
			end
		end)
	end
	local _ = GuiService
end

return Laptop
