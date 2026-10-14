-- Multiplayer lobby. Public servers of this place are lobbies; every game session runs in its own
-- reserved server of the same place (TeleportService). In a lobby players can play solo or create a
-- private lobby (1–4 players, 4-digit code / friend invites), mark themselves ready, and the host
-- starts the game: everybody is teleported together into a fresh reserved server where the host's
-- restaurant is loaded (the host owns it, friends work as staff). Progress is saved per player by
-- DataService; the shared restaurant lives in the host's save, so the same group continues it.
-- Studio cannot teleport: there "Start" switches this server into game mode in place.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)

local LobbyService = {}
LobbyService.StartInPlace = nil :: ((hostId: number) -> ())?

local MAX = 4
type Lobby = { code: string, host: Player, members: { Player }, ready: { [Player]: boolean }, starting: boolean }
local lobbies: { [string]: Lobby } = {}
local memberOf: { [Player]: Lobby } = {}

local LOBBY_ORIGIN = Vector3.new(0, 0, -420)

---------------------------------------------------------------------------
-- 3D lobby: a small night-time kebab plaza
---------------------------------------------------------------------------
local function p(parent, size, cf, color, mat, props)
	local x = Instance.new("Part")
	x.Anchored = true
	x.Size = size
	x.CFrame = cf
	x.Color = color
	x.Material = mat or Enum.Material.SmoothPlastic
	x.TopSurface = Enum.SurfaceType.Smooth
	x.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		(x :: any)[k] = v
	end
	x.Parent = parent
	return x
end

local function label(part: BasePart, face: Enum.NormalId, text: string, color: Color3, stroke: Color3?, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.LightInfluence = 0
	sg.Brightness = 2
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeColor3 = stroke or Color3.new(0, 0, 0)
	t.TextStrokeTransparency = stroke and 0 or 1
	t.Parent = sg
	return t
end

local function lamp(parent: Instance, pos: CFrame, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	local holder = p(parent, Vector3.new(0.2, 0.2, 0.2), pos, color, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	l.Parent = holder
	return holder
end

-- a town house with lit / dark windows and a shop front on the ground floor
local function townHouse(parent: Instance, cf: CFrame, w: number, h: number, d: number, color: Color3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "House"
	m.Parent = parent
	p(m, Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color, Enum.Material.Plaster)
	p(m, Vector3.new(w + 0.6, 0.8, d + 0.6), cf * CFrame.new(0, h + 0.4, 0), Color3.fromRGB(235, 230, 220), Enum.Material.Plaster)
	-- shop front
	local shop = ({ Color3.fromRGB(40, 60, 70), Color3.fromRGB(70, 40, 40), Color3.fromRGB(40, 50, 40) })[rng:NextInteger(1, 3)]
	p(m, Vector3.new(w - 2, 5, 0.3), cf * CFrame.new(0, 3, -d / 2 - 0.1), shop, Enum.Material.Glass, { Reflectance = 0.2 })
	if rng:NextNumber() < 0.6 then
		local lit = p(m, Vector3.new(w - 2.6, 4.4, 0.2), cf * CFrame.new(0, 3, -d / 2 - 0.2), Color3.fromRGB(255, 196, 120), Enum.Material.Neon, { Transparency = 0.45, CanCollide = false })
		local _ = lit
	end
	local awn = ({ Color3.fromRGB(40, 110, 70), Color3.fromRGB(30, 70, 140), Color3.fromRGB(150, 40, 40), Color3.fromRGB(200, 150, 40) })[rng:NextInteger(1, 4)]
	p(m, Vector3.new(w - 1, 0.2, 2.6), cf * CFrame.new(0, 6.2, -d / 2 - 1.2) * CFrame.Angles(math.rad(-18), 0, 0), awn, Enum.Material.Fabric, { CanCollide = false })
	-- upper windows
	local cols = math.max(1, math.floor((w - 2) / 4))
	for floor = 0, math.floor((h - 10) / 5) do
		for c = 0, cols - 1 do
			local x = -w / 2 + 2 + (c + 0.5) * ((w - 4) / cols)
			local y = 9.5 + floor * 5
			if y + 2 < h then
				local lit = rng:NextNumber() < 0.45
				p(m, Vector3.new(2, 2.8, 0.2), cf * CFrame.new(x, y, -d / 2 - 0.05), lit and Color3.fromRGB(255, 205, 130) or Color3.fromRGB(45, 60, 80), lit and Enum.Material.Neon or Enum.Material.Glass, { Transparency = lit and 0.25 or 0, CanCollide = false })
				p(m, Vector3.new(2.6, 0.25, 0.6), cf * CFrame.new(x, y - 1.55, -d / 2 - 0.25), Color3.fromRGB(240, 236, 228), Enum.Material.Plaster, { CanCollide = false })
			end
		end
	end
	return m
end

function LobbyService.BuildWorld()
	if workspace:FindFirstChild("Lobby") then
		return workspace.Lobby
	end
	local rng = Random.new(7)
	local m = Instance.new("Model")
	m.Name = "Lobby"
	local o = CFrame.new(LOBBY_ORIGIN)
	local WARM = Color3.fromRGB(255, 196, 120)

	-- ground: cobblestone square with pavements along the houses
	p(m, Vector3.new(140, 1, 130), o * CFrame.new(0, -0.5, 0), Color3.fromRGB(96, 88, 82), Enum.Material.Cobblestone)
	for _, s in ipairs({ { 0, -21, 76, 4 }, { -33, 6, 6, 58 }, { 33, 6, 6, 58 }, { 0, 34, 76, 4 } }) do
		p(m, Vector3.new(s[3], 0.3, s[4]), o * CFrame.new(s[1], 0.15, s[2]), Color3.fromRGB(170, 164, 156), Enum.Material.Concrete)
	end

	-- the Kebap Haus: lit shop front, striped awning, neon sign
	local shopM = Instance.new("Model")
	shopM.Name = "KebapHaus"
	shopM.Parent = m
	local f = o * CFrame.new(0, 0, -30) -- building centre, facade at z = -23
	p(shopM, Vector3.new(36, 24, 14), f * CFrame.new(0, 12, 0), Color3.fromRGB(240, 226, 200), Enum.Material.Plaster)
	p(shopM, Vector3.new(36.4, 9, 0.4), f * CFrame.new(0, 4.5, 7.05), Color3.fromRGB(150, 50, 36), Enum.Material.Brick)
	p(shopM, Vector3.new(37, 1, 15), f * CFrame.new(0, 24.5, 0), Color3.fromRGB(120, 40, 30), Enum.Material.Slate)
	for _, x in ipairs({ -10, 10 }) do
		p(shopM, Vector3.new(11, 5.4, 0.3), f * CFrame.new(x, 4, 7.3), Color3.fromRGB(30, 26, 24), Enum.Material.Metal)
		p(shopM, Vector3.new(10.2, 4.6, 0.2), f * CFrame.new(x, 4, 7.45), WARM, Enum.Material.Neon, { Transparency = 0.2 })
		lamp(shopM, f * CFrame.new(x, 4, 9), WARM, 18, 1.6)
	end
	-- door with an "OFFEN" sign
	p(shopM, Vector3.new(4.6, 7.4, 0.3), f * CFrame.new(0, 3.7, 7.3), Color3.fromRGB(30, 26, 24), Enum.Material.Metal)
	p(shopM, Vector3.new(3.8, 6.6, 0.2), f * CFrame.new(0, 3.5, 7.45), Color3.fromRGB(255, 220, 160), Enum.Material.Glass, { Transparency = 0.1 })
	local open = p(shopM, Vector3.new(2.6, 0.9, 0.15), f * CFrame.new(0, 5.6, 7.6), Color3.fromRGB(60, 255, 110), Enum.Material.Neon)
	label(open, Enum.NormalId.Back, "OFFEN", Color3.fromRGB(20, 60, 25))
	-- glass showcase with a turning spit next to the door
	local caseCF = f * CFrame.new(-4.6, 0, 8.4)
	p(shopM, Vector3.new(3, 3, 2.2), caseCF * CFrame.new(0, 1.5, 0), Color3.fromRGB(60, 62, 66), Enum.Material.Metal)
	p(shopM, Vector3.new(3, 4.4, 2.2), caseCF * CFrame.new(0, 5.2, 0), Color3.fromRGB(200, 230, 240), Enum.Material.Glass, { Transparency = 0.75, CanCollide = false })
	p(shopM, Vector3.new(3, 0.2, 2.2), caseCF * CFrame.new(0, 7.5, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	p(shopM, Vector3.new(0.4, 3.6, 1.8), caseCF * CFrame.new(-1.2, 5.2, 0), Color3.fromRGB(255, 90, 40), Enum.Material.Neon, { CanCollide = false })
	local rotor = Instance.new("Model")
	rotor.Name = "ShowSpit"
	rotor.Parent = shopM
	for i = 1, 7 do
		local d = 1.5 - i * 0.12
		p(rotor, Vector3.new(0.48, d, d), caseCF * CFrame.new(0.2, 6.9 - i * 0.48, 0) * CFrame.Angles(0, math.rad(i * 40), math.rad(90)), Color3.fromRGB(205 - i * 4, 135 - i * 3, 66), Enum.Material.Sand, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	game:GetService("CollectionService"):AddTag(rotor, "SpitRotor")
	-- striped awning
	for i = 0, 17 do
		local x = -17 + i * 2 + 1
		if math.abs(x) > 3 then
			p(shopM, Vector3.new(2, 0.2, 4.4), f * CFrame.new(x, 9.2, 9.1) * CFrame.Angles(math.rad(-20), 0, 0), i % 2 == 0 and Color3.fromRGB(200, 40, 34) or Color3.fromRGB(245, 242, 235), Enum.Material.Fabric, { CanCollide = false })
		end
	end
	-- big neon sign with an orange outline
	local sign = p(shopM, Vector3.new(26, 4.6, 0.5), f * CFrame.new(0, 13.2, 7.3), Color3.fromRGB(26, 20, 18), Enum.Material.SmoothPlastic)
	label(sign, Enum.NormalId.Back, "🥙 KEBAP HAUS", Color3.fromRGB(255, 200, 70), Color3.fromRGB(200, 40, 30))
	for _, e in ipairs({ { 0, 2.45, 26.4, 0.25 }, { 0, -2.45, 26.4, 0.25 }, { -13.1, 0, 0.25, 5 }, { 13.1, 0, 0.25, 5 } }) do
		p(shopM, Vector3.new(e[3], e[4], 0.25), f * CFrame.new(e[1], 13.2 + e[2], 7.6), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, { CanCollide = false })
	end
	lamp(shopM, f * CFrame.new(0, 13, 11), Color3.fromRGB(255, 150, 70), 26, 1.4)
	-- upper floor windows with flower boxes
	for row = 0, 1 do
		for c = 0, 4 do
			local x = -14 + c * 7
			local y = 17 + row * 4.2
			if row == 0 or c % 2 == 0 then
				local lit = (c + row) % 2 == 0
				p(shopM, Vector3.new(3, 3, 0.2), f * CFrame.new(x, y, 7.05), lit and WARM or Color3.fromRGB(50, 64, 84), lit and Enum.Material.Neon or Enum.Material.Glass, { Transparency = lit and 0.3 or 0, CanCollide = false })
				p(shopM, Vector3.new(3.4, 0.6, 0.8), f * CFrame.new(x, y - 1.8, 7.4), Color3.fromRGB(90, 60, 40), Enum.Material.Wood, { CanCollide = false })
				for k = -1, 1 do
					p(shopM, Vector3.new(0.6, 0.6, 0.6), f * CFrame.new(x + k * 1, y - 1.3, 7.4), ({ Color3.fromRGB(230, 60, 70), Color3.fromRGB(250, 200, 60), Color3.fromRGB(240, 120, 200) })[k + 2], Enum.Material.Plastic, { Shape = Enum.PartType.Ball, CanCollide = false })
				end
			end
		end
	end

	-- neighbouring houses close the square on all sides
	local palette = { Color3.fromRGB(214, 186, 150), Color3.fromRGB(190, 206, 214), Color3.fromRGB(222, 206, 170), Color3.fromRGB(200, 170, 170), Color3.fromRGB(180, 196, 170) }
	local idx = 0
	local function row(x0: number, z: number, dir: number, along: string, from: number, to: number)
		local pos = from
		while pos < to do
			idx += 1
			local w = rng:NextInteger(10, 15)
			w = math.min(w, to - pos)
			local h = rng:NextInteger(18, 30)
			local cf
			if along == "x" then
				cf = o * CFrame.new(pos + w / 2, 0, z) * CFrame.Angles(0, dir, 0)
			else
				cf = o * CFrame.new(x0, 0, pos + w / 2) * CFrame.Angles(0, dir, 0)
			end
			townHouse(m, cf, w, h, 12, palette[idx % #palette + 1], rng)
			pos += w
		end
	end
	row(0, -30, 0, "x", -66, -18)
	row(0, -30, 0, "x", 18, 66)
	row(-42, 0, math.rad(-90), "z", -24, 38)
	row(42, 0, math.rad(90), "z", -24, 38)
	row(0, 44, math.rad(180), "x", -66, 66)

	-- the Döner fountain in the middle of the square
	local fc = o * CFrame.new(-17, 0, 3)
	p(m, Vector3.new(1.4, 17, 17), fc * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(190, 180, 166), Enum.Material.Limestone, { Shape = Enum.PartType.Cylinder })
	p(m, Vector3.new(0.3, 15.4, 15.4), fc * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 150, 200), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.25, CanCollide = false })
	p(m, Vector3.new(4, 3.2, 4), fc * CFrame.new(0, 2.2, 0), Color3.fromRGB(190, 180, 166), Enum.Material.Limestone)
	p(m, Vector3.new(4.6, 0.4, 4.6), fc * CFrame.new(0, 3.9, 0), Color3.fromRGB(230, 180, 60), Enum.Material.Metal)
	p(m, Vector3.new(0.5, 12, 0.5), fc * CFrame.new(0, 10, 0), Color3.fromRGB(210, 210, 215), Enum.Material.Metal)
	local doner = Instance.new("Model")
	doner.Name = "Doner"
	doner.Parent = m
	for i = 1, 12 do
		local d = 5.6 - i * 0.3
		p(doner, Vector3.new(0.75, d, d), fc * CFrame.new(0, 14.4 - i * 0.72, 0) * CFrame.Angles(0, math.rad(i * 29), math.rad(90)), Color3.fromRGB(206 - i * 3, 132 - i * 2, 64), Enum.Material.Sand, { Shape = Enum.PartType.Cylinder })
	end
	p(doner, Vector3.new(0.5, 4.2, 4.2), fc * CFrame.new(0, 14.9, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(230, 180, 60), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	game:GetService("CollectionService"):AddTag(doner, "SpitRotor")
	lamp(m, fc * CFrame.new(0, 6, 0), Color3.fromRGB(255, 160, 80), 24, 1.6)
	-- water jets
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local jet = p(m, Vector3.new(0.4, 0.4, 0.4), fc * CFrame.new(math.cos(a) * 5.5, 1.3, math.sin(a) * 5.5), Color3.fromRGB(200, 230, 255), Enum.Material.Neon, { Transparency = 1, CanCollide = false })
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 18
		pe.Lifetime = NumberRange.new(0.8, 1.1)
		pe.Speed = NumberRange.new(9, 11)
		pe.SpreadAngle = Vector2.new(4, 4)
		pe.Acceleration = Vector3.new(0, -20, 0)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Size = NumberSequence.new(0.35, 0.15)
		pe.Transparency = NumberSequence.new(0.3, 1)
		pe.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
		pe.LightEmission = 0.4
		pe.Parent = jet
	end

	-- benches around the fountain
	for i = 0, 3 do
		local c = fc * CFrame.Angles(0, math.rad(45 + i * 90), 0) * CFrame.new(0, 0, 10.5)
		p(m, Vector3.new(5, 0.35, 1.6), c * CFrame.new(0, 1.5, 0), Color3.fromRGB(120, 80, 50), Enum.Material.WoodPlanks)
		p(m, Vector3.new(5, 1.4, 0.3), c * CFrame.new(0, 2.3, 0.75), Color3.fromRGB(120, 80, 50), Enum.Material.WoodPlanks)
		for _, sx in ipairs({ -2, 2 }) do
			p(m, Vector3.new(0.3, 1.4, 1.4), c * CFrame.new(sx, 0.7, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		end
	end

	-- terrace tables with parasols in front of the shop
	for _, x in ipairs({ -13, 13 }) do
		local c = o * CFrame.new(x, 0, -15)
		p(m, Vector3.new(2.8, 0.2, 2.8), c * CFrame.new(0, 3, 0), Color3.fromRGB(235, 232, 225), Enum.Material.Marble)
		p(m, Vector3.new(0.3, 3, 0.3), c * CFrame.new(0, 1.5, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		p(m, Vector3.new(0.15, 6, 0.15), c * CFrame.new(0, 6, 0), Color3.fromRGB(220, 220, 220), Enum.Material.Metal, { CanCollide = false })
		p(m, Vector3.new(0.3, 7, 7), c * CFrame.new(0, 8.8, 0) * CFrame.Angles(0, 0, math.rad(90)), x < 0 and Color3.fromRGB(200, 40, 34) or Color3.fromRGB(245, 242, 235), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		for _, sx in ipairs({ -2, 2 }) do
			p(m, Vector3.new(1.5, 0.2, 1.5), c * CFrame.new(sx, 1.8, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
			p(m, Vector3.new(0.15, 1.7, 1.5), c * CFrame.new(sx + (sx < 0 and -0.7 or 0.7), 2.7, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
		end
	end

	-- street lamps
	for _, s in ipairs({ { -24, -17 }, { 24, -17 }, { -24, 22 }, { 24, 22 } }) do
		local c = o * CFrame.new(s[1], 0, s[2])
		p(m, Vector3.new(0.5, 11, 0.5), c * CFrame.new(0, 5.5, 0), Color3.fromRGB(28, 30, 32), Enum.Material.Metal)
		p(m, Vector3.new(1.4, 1.6, 1.4), c * CFrame.new(0, 11.6, 0), Color3.fromRGB(255, 214, 150), Enum.Material.Neon, { Transparency = 0.1 })
		p(m, Vector3.new(1.8, 0.3, 1.8), c * CFrame.new(0, 12.5, 0), Color3.fromRGB(28, 30, 32), Enum.Material.Metal)
		lamp(m, c * CFrame.new(0, 11, 0), Color3.fromRGB(255, 200, 140), 28, 1.3)
	end

	-- trees in planters
	for _, s in ipairs({ { -29, -14 }, { 28, -6 }, { -29, 20 }, { 28, 12 } }) do
		local c = o * CFrame.new(s[1], 0, s[2])
		p(m, Vector3.new(3, 1.2, 3), c * CFrame.new(0, 0.6, 0), Color3.fromRGB(120, 116, 110), Enum.Material.Concrete)
		p(m, Vector3.new(0.8, 6, 0.8), c * CFrame.new(0, 3.5, 0), Color3.fromRGB(92, 64, 44), Enum.Material.Wood)
		p(m, Vector3.new(6, 5, 6), c * CFrame.new(0, 7.5, 0), Color3.fromRGB(70, 126, 64), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		p(m, Vector3.new(4, 3.6, 4), c * CFrame.new(0.8, 9.6, 0.4), Color3.fromRGB(86, 140, 74), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	end

	-- delivery scooter and crates beside the shop
	local sc = o * CFrame.new(21, 0, -18) * CFrame.Angles(0, math.rad(-70), 0)
	p(m, Vector3.new(4, 1.2, 1.4), sc * CFrame.new(0, 1.6, 0), Color3.fromRGB(210, 40, 40), Enum.Material.SmoothPlastic)
	p(m, Vector3.new(1.8, 0.4, 1.2), sc * CFrame.new(-0.6, 2.4, 0), Color3.fromRGB(28, 28, 30), Enum.Material.Fabric)
	p(m, Vector3.new(1.8, 1.6, 1.8), sc * CFrame.new(-1.5, 3.4, 0), Color3.fromRGB(240, 240, 235), Enum.Material.SmoothPlastic)
	for _, x in ipairs({ -1.6, 1.8 }) do
		p(m, Vector3.new(0.5, 1.6, 1.6), sc * CFrame.new(x, 0.8, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(28, 28, 30), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
	end
	p(m, Vector3.new(0.3, 2.2, 0.3), sc * CFrame.new(1.8, 2.6, 0) * CFrame.Angles(0, 0, math.rad(-15)), Color3.fromRGB(210, 40, 40), Enum.Material.SmoothPlastic)
	for i = 0, 2 do
		p(m, Vector3.new(2, 1.6, 2), o * CFrame.new(-21 + (i % 2) * 0.4, 0.8 + math.floor(i / 2) * 1.6, -19.5 + (i % 2) * 2.1) * CFrame.Angles(0, math.rad(i * 12), 0), Color3.fromRGB(190, 150, 100), Enum.Material.WoodPlanks)
	end

	-- fairy lights across the square
	local colors = { Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 120, 90), Color3.fromRGB(140, 200, 255), Color3.fromRGB(150, 255, 150) }
	for k, z in ipairs({ -14, -2 }) do
		local a, b = o * CFrame.new(-36, 15, z), o * CFrame.new(36, 15, z + 4)
		local n = 24
		for i = 0, n do
			local t = i / n
			local pos = a.Position:Lerp(b.Position, t) - Vector3.new(0, math.sin(t * math.pi) * 2.2, 0)
			local bulb = p(m, Vector3.new(0.45, 0.45, 0.45), CFrame.new(pos), colors[(i + k) % #colors + 1], Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false })
			if i % 6 == 3 then
				local l = Instance.new("PointLight")
				l.Color = bulb.Color
				l.Range = 12
				l.Brightness = 0.8
				l.Parent = bulb
			end
		end
	end

	-- invisible fence so nobody leaves the square
	for _, w in ipairs({ { 0, -22.5, 80, 1 }, { 0, 37, 80, 1 }, { -36.5, 7, 1, 62 }, { 36.5, 7, 1, 62 } }) do
		p(m, Vector3.new(w[3], 14, w[4]), o * CFrame.new(w[1], 7, w[2]), Color3.new(), nil, { Transparency = 1 })
	end
	local spawnPart = p(m, Vector3.new(4, 0.2, 4), o * CFrame.new(7, 0.1, 12), Color3.fromRGB(255, 196, 64), Enum.Material.Neon, { CanCollide = false, Transparency = 1, Name = "LobbySpawn" })
	spawnPart.Name = "LobbySpawn"
	m:SetAttribute("CamLook", LOBBY_ORIGIN + Vector3.new(-5, 8, -20))
	m.Parent = workspace
	return m
end

---------------------------------------------------------------------------
-- lobbies
---------------------------------------------------------------------------
local function newCode(): string
	for _ = 1, 50 do
		local c = tostring(math.random(1000, 9999))
		if not lobbies[c] then
			return c
		end
	end
	return tostring(os.time() % 10000)
end

-- save slots: which of their 3 restaurants each player has picked in the lobby
local selected: { [Player]: number } = {}

local function slotInfo(pl: Player, slot: number?)
	local meta = DataService.GetMeta(pl)
	return meta and slot and meta.slots[slot] or nil
end

local function snapshot(l: Lobby)
	local list = {}
	for _, pl in ipairs(l.members) do
		local s = slotInfo(pl, selected[pl])
		table.insert(list, { userId = pl.UserId, name = pl.DisplayName, ready = l.ready[pl] == true, host = pl == l.host, level = s and s.level or 1 })
	end
	local hs = slotInfo(l.host, selected[l.host])
	return { code = l.code, members = list, starting = l.starting, max = MAX, slotName = hs and hs.name or nil, slotLevel = hs and hs.level or nil }
end

local function push(l: Lobby?)
	if not l then
		return
	end
	local s = snapshot(l)
	for _, pl in ipairs(l.members) do
		Net.Fire("LobbyState", pl, s)
	end
end

local function leave(pl: Player)
	local l = memberOf[pl]
	if not l then
		return
	end
	memberOf[pl] = nil
	local i = table.find(l.members, pl)
	if i then
		table.remove(l.members, i)
	end
	l.ready[pl] = nil
	if pl.Parent then
		Net.Fire("LobbyState", pl, nil)
	end
	if #l.members == 0 then
		lobbies[l.code] = nil
		return
	end
	if l.host == pl then
		l.host = l.members[1] -- host left: the next member takes over
	end
	push(l)
end

local function create(pl: Player)
	leave(pl)
	local l: Lobby = { code = newCode(), host = pl, members = { pl }, ready = {}, starting = false }
	lobbies[l.code] = l
	memberOf[pl] = l
	push(l)
	return { ok = true, code = l.code }
end

local function join(pl: Player, code: any)
	if type(code) ~= "string" then
		return { ok = false, msg = "lobby_not_found" }
	end
	local l = lobbies[code]
	if not l or l.starting then
		return { ok = false, msg = "lobby_not_found" }
	end
	if #l.members >= MAX and memberOf[pl] ~= l then
		return { ok = false, msg = "lobby_full" }
	end
	if memberOf[pl] ~= l then
		leave(pl)
		table.insert(l.members, pl)
		memberOf[pl] = l
	end
	push(l)
	return { ok = true }
end

-- teleport a group into a fresh reserved server; retries, then reports failure
local function teleport(players: { Player }, hostId: number, l: Lobby?, slot: number?)
	if RunService:IsStudio() then
		-- Studio can't teleport: run the session right here
		for _, pl in ipairs(players) do
			Net.Fire("LobbyLoading", pl, true)
		end
		task.wait(1.2)
		if LobbyService.StartInPlace then
			LobbyService.StartInPlace(hostId, slot)
		end
		return true
	end
	for _, pl in ipairs(players) do
		Net.Fire("LobbyLoading", pl, true)
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			local options = Instance.new("TeleportOptions")
			options.ShouldReserveServer = true
			options:SetTeleportData({ host = hostId, slot = slot or 1, v = 2 })
			TeleportService:TeleportAsync(game.PlaceId, players, options)
		end)
		if ok then
			return true
		end
		warn("[Lobby] teleport failed (attempt " .. attempt .. "): " .. tostring(err))
		task.wait(1.5 * attempt)
	end
	for _, pl in ipairs(players) do
		if pl.Parent then
			Net.Fire("LobbyLoading", pl, false)
			Net.Notify(pl, "lobby_tp_failed", nil, "warn")
		end
	end
	if l then
		l.starting = false
		push(l)
	end
	return false
end

local function start(pl: Player)
	local l = memberOf[pl]
	if not l or l.host ~= pl or l.starting then
		return { ok = false }
	end
	for _, m in ipairs(l.members) do
		if m ~= l.host and not l.ready[m] then
			return { ok = false, msg = "lobby_not_ready" }
		end
	end
	local slot = selected[pl]
	if not slotInfo(pl, slot) then
		return { ok = false, msg = "lobby_no_slot" }
	end
	l.starting = true
	push(l)
	task.spawn(teleport, table.clone(l.members), l.host.UserId, l, slot)
	return { ok = true }
end

function LobbyService.Init()
	LobbyService.BuildWorld()
	-- warm evening light for the square (the game sets its own lighting when it starts)
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 17.7
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 120, 120)
	Lighting.Ambient = Color3.fromRGB(90, 78, 78)
	ReplicatedStorage:SetAttribute("Mode", "lobby")
	local spawn = workspace.Lobby:FindFirstChild("LobbySpawn") :: BasePart
	local function place(char: Model)
		task.defer(function()
			local hrp = char:WaitForChild("HumanoidRootPart", 5)
			if hrp and ReplicatedStorage:GetAttribute("Mode") == "lobby" then
				char:PivotTo(CFrame.new(spawn.Position + Vector3.new(math.random(-3, 3), 3.2, math.random(-3, 3))) * CFrame.Angles(0, math.rad(180), 0))
			end
		end)
	end
	local function onPlayer(pl: Player)
		pl.CharacterAdded:Connect(place)
		if pl.Character then
			place(pl.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, pl in ipairs(Players:GetPlayers()) do
		onPlayer(pl)
	end
	Players.PlayerRemoving:Connect(leave)

	Net.OnRequest("LobbyCreate", create)
	Net.OnRequest("LobbyJoin", join)
	Net.OnRequest("LobbyLeave", function(pl)
		leave(pl)
		return { ok = true }
	end)
	Net.OnRequest("LobbyReady", function(pl, ready)
		local l = memberOf[pl]
		if l and not l.starting then
			l.ready[pl] = ready == true
			push(l)
		end
		return { ok = true }
	end)
	Net.OnRequest("LobbyStart", start)
	Net.OnRequest("PlaySolo", function(pl)
		if memberOf[pl] and memberOf[pl].starting then
			return { ok = false }
		end
		local slot = selected[pl]
		if not slotInfo(pl, slot) then
			return { ok = false, msg = "lobby_no_slot" }
		end
		leave(pl)
		task.spawn(teleport, { pl }, pl.UserId, nil, slot)
		return { ok = true }
	end)
	-- save slot cards: list / create / select / delete (delete needs a confirm token from a first call)
	local pendingDelete: { [Player]: { slot: number, t: number } } = {}
	local function slotState(pl: Player)
		local meta = DataService.GetMeta(pl)
		local t0 = os.clock()
		while not meta and os.clock() - t0 < 10 and pl.Parent do
			task.wait(0.25)
			meta = DataService.GetMeta(pl)
		end
		if not meta then
			return { ok = false }
		end
		local cards = {}
		for i = 1, DataService.SLOTS do
			cards[i] = meta.slots[i] or { exists = false }
		end
		if not selected[pl] then
			local last = meta.lastSlot
			if last and cards[last] and cards[last].exists then
				selected[pl] = last
			else
				for i = 1, DataService.SLOTS do
					if cards[i].exists then
						selected[pl] = i
						break
					end
				end
			end
		end
		return { ok = true, slots = cards, selected = selected[pl] }
	end
	local function inStartingLobby(pl: Player): boolean
		return memberOf[pl] ~= nil and memberOf[pl].starting
	end
	Net.OnRequest("SlotList", slotState)
	Net.OnRequest("SlotSelect", function(pl, n)
		n = tonumber(n)
		if not n or inStartingLobby(pl) or not slotInfo(pl, n) then
			return { ok = false }
		end
		selected[pl] = n
		push(memberOf[pl])
		return slotState(pl)
	end)
	Net.OnRequest("SlotCreate", function(pl, n)
		n = tonumber(n)
		if not n or inStartingLobby(pl) or not DataService.CreateSlot(pl, n) then
			return { ok = false }
		end
		selected[pl] = n
		push(memberOf[pl])
		return slotState(pl)
	end)
	Net.OnRequest("SlotDelete", function(pl, args)
		local n = type(args) == "table" and tonumber(args.slot)
		if not n or inStartingLobby(pl) or not slotInfo(pl, n) then
			return { ok = false }
		end
		local p = pendingDelete[pl]
		if not (type(args) == "table" and args.confirm == true and p and p.slot == n and os.clock() - p.t < 15) then
			pendingDelete[pl] = { slot = n, t = os.clock() }
			return { ok = true, confirm = true }
		end
		pendingDelete[pl] = nil
		if not DataService.DeleteSlot(pl, n) then
			return { ok = false, msg = "slot_delete_failed" }
		end
		if selected[pl] == n then
			selected[pl] = nil
		end
		push(memberOf[pl])
		return slotState(pl)
	end)
	-- friends invited from a lobby join it automatically (the code travels as launch data)
	local function autoJoin(pl: Player)
		local ok, jd = pcall(function()
			return pl:GetJoinData()
		end)
		local code = ok and jd and jd.LaunchData
		if type(code) == "string" and lobbies[code] then
			task.delay(1, join, pl, code)
		end
	end
	Players.PlayerAdded:Connect(autoJoin)
	Players.PlayerRemoving:Connect(function(pl)
		selected[pl] = nil
		pendingDelete[pl] = nil
	end)
	Net.OnRequest("LobbyProfile", function(pl)
		local s = slotInfo(pl, selected[pl])
		if not DataService.GetMeta(pl) then
			return { ok = false }
		end
		return { ok = true, level = s and s.level or 1, cash = s and s.cash or 0, day = s and s.day or 1, served = 0, name = s and s.name }
	end)
	-- teleports that fail after leaving the server's hands (e.g. the place is full)
	TeleportService.TeleportInitFailed:Connect(function(pl, result, msg)
		warn("[Lobby] TeleportInitFailed", pl.Name, result, msg)
		Net.Fire("LobbyLoading", pl, false)
		Net.Notify(pl, "lobby_tp_failed", nil, "warn")
		local l = memberOf[pl]
		if l then
			l.starting = false
			push(l)
		end
	end)
end

function LobbyService.JoinInfo(pl: Player): { host: number?, slot: number? }?
	local ok, jd = pcall(function()
		return pl:GetJoinData()
	end)
	local td = ok and jd and jd.TeleportData
	if type(td) == "table" then
		return { host = tonumber(td.host), slot = tonumber(td.slot) }
	end
	return nil
end

-- game servers: the teleport data names the host whose restaurant is loaded
function LobbyService.HostFromJoinData(pl: Player): number?
	local ok, jd = pcall(function()
		return pl:GetJoinData()
	end)
	local td = ok and jd and jd.TeleportData
	if type(td) == "table" and type(td.host) == "number" then
		return td.host
	end
	return nil
end

return LobbyService
