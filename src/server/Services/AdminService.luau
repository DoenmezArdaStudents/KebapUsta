-- Admin rank: the place creator (plus ADMIN_IDS, plus everyone in Studio) gets the "Admin"
-- attribute, the admin panel (Client/AdminUI) and ;chat commands. Every command is checked here.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Services = script.Parent

local Net = require(Services.Net)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local RestaurantService = require(Services.RestaurantService)
local UnlockService = require(Services.UnlockService)
local CustomerService = require(Services.CustomerService)
local BusinessService = require(Services.BusinessService)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local IngredientData = require(Shared.IngredientData)

local AdminService = {}

-- extra admins by UserId (the game's creator is always admin)
local ADMIN_IDS: { [number]: boolean } = {}

local function isAdmin(p: Player): boolean
	if RunService:IsStudio() or ADMIN_IDS[p.UserId] then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return p.UserId == game.CreatorId
	end
	local ok, rank = pcall(p.GetRankInGroup, p, game.CreatorId)
	return ok and rank == 255
end
AdminService.IsAdmin = isAdmin

local function findPlayer(name: any, default: Player): Player?
	if type(name) ~= "string" or name == "" or name == "me" then
		return default
	end
	name = name:lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower():sub(1, #name) == name or p.DisplayName:lower():sub(1, #name) == name then
			return p
		end
	end
	return nil
end

local function hum(p: Player): Humanoid?
	return p.Character and p.Character:FindFirstChildOfClass("Humanoid")
end
local function root(p: Player): BasePart?
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function refreshWorld(p: Player)
	EconomyService.Push(p)
	RestaurantService.ApplyWorldUpgrades()
	UnlockService.ApplyWorld()
	RestaurantService.PushShop()
	DataService.MarkDirty(p)
end

local function fillStock(p: Player)
	local data = DataService.Get(p)
	if not data then
		return
	end
	data.stocked = data.stocked or {}
	for id in pairs(IngredientData.Stock) do
		if Progression.StockUnlocked(data.unlocks, id) then
			data.stock[id] = RestaurantService.Capacity(id)
			data.stocked[id] = true
		end
	end
	RestaurantService.PushShop()
	DataService.MarkDirty(p)
end

-- cmd -> function(admin, value, target) -> message
local C = {}
C.money = function(p, v, t)
	EconomyService.AddCash(t, tonumber(v) or 1000, false)
	return ("+€%d für %s"):format(tonumber(v) or 1000, t.Name)
end
C.setmoney = function(p, v, t)
	local d = DataService.Get(t)
	d.cash = math.max(0, tonumber(v) or 0)
	refreshWorld(t)
	return ("Geld von %s = €%d"):format(t.Name, d.cash)
end
C.xp = function(p, v, t)
	EconomyService.AddXP(t, tonumber(v) or 500)
	return "+XP"
end
C.level = function(p, v, t)
	local d = DataService.Get(t)
	d.level = math.clamp(math.floor(tonumber(v) or d.level + 1), 1, 100)
	d.xp = 0
	refreshWorld(t)
	return ("Level von %s = %d"):format(t.Name, d.level)
end
C.rep = function(p, v, t)
	local d = DataService.Get(t)
	d.reputation = math.clamp(tonumber(v) or 100, 0, 100)
	refreshWorld(t)
	return ("Ruf = %d"):format(d.reputation)
end
C.unlockall = function(p, v, t)
	local d = DataService.Get(t)
	for _, u in ipairs(Progression.Unlocks) do
		d.unlocks[u.id] = "owned"
	end
	d.level = math.max(d.level, 20)
	refreshWorld(t)
	fillStock(t)
	return "Alles freigeschaltet"
end
C.fillstock = function(p, v, t)
	fillStock(t)
	return "Lager voll"
end
C.time = function(p, v)
	local h = math.clamp(tonumber(v) or 12, Config.Day.StartHour, Config.Day.EndHour - 0.05)
	RestaurantService.Clock = h
	return ("Uhrzeit = %.1f Uhr"):format(h)
end
C.skipday = function()
	RestaurantService.Clock = Config.Day.EndHour - 0.01
	return "Tag wird beendet"
end
C.spawn = function(p, v)
	local n = math.clamp(math.floor(tonumber(v) or 1), 1, 10)
	for i = 1, n do
		task.delay((i - 1) * 0.6, CustomerService.Spawn, {})
	end
	return ("%d Kunde(n)"):format(n)
end
C.vip = function()
	CustomerService.Spawn({ vip = true })
	return "VIP-Kunde"
end
C.critic = function()
	CustomerService.Spawn({ critic = true })
	return "Kritiker"
end
C.angry = function()
	CustomerService.DebugAggro(nil)
	return "Kunde wütend"
end
C.clearcustomers = function()
	CustomerService.ForceLeaveAll()
	return "Kunden gehen"
end
C.clean = function()
	local n = 0
	for _, d in ipairs(table.clone(BusinessService.Dirt())) do
		if BusinessService.Clean(d) then
			n += 1
		end
	end
	return ("%d Flecken entfernt"):format(n)
end
C.stage = function(p, v)
	BusinessService.DebugConstruct(math.clamp(math.floor(tonumber(v) or 2), 1, 5))
	return "Ausbaustufe gesetzt"
end
C.speed = function(p, v, t)
	local h = hum(t)
	if h then
		h.WalkSpeed = math.clamp(tonumber(v) or 16, 0, 200)
		t:SetAttribute("SpeedMul", h.WalkSpeed / 10)
	end
	return "Speed = " .. tostring(h and h.WalkSpeed)
end
C.jump = function(p, v, t)
	local h = hum(t)
	if h then
		h.UseJumpPower = true
		h.JumpPower = math.clamp(tonumber(v) or 50, 0, 300)
	end
	return "Sprungkraft gesetzt"
end
C.heal = function(p, v, t)
	local h = hum(t)
	if h then
		h.Health = h.MaxHealth
	end
	return "Geheilt"
end
C.tp = function(p, v, t)
	local a, b = root(p), root(t)
	if a and b and t ~= p then
		p.Character:PivotTo(b.CFrame * CFrame.new(0, 0, 3))
	end
	return "Teleportiert zu " .. t.Name
end
C.bring = function(p, v, t)
	local a, b = root(p), root(t)
	if a and b and t ~= p then
		t.Character:PivotTo(a.CFrame * CFrame.new(0, 0, -3))
	end
	return t.Name .. " geholt"
end
C.kick = function(p, v, t)
	if t == p then
		return "Du kannst dich nicht selbst kicken"
	end
	t:Kick(type(v) == "string" and v ~= "" and v or "Vom Admin gekickt")
	return t.Name .. " gekickt"
end
C.announce = function(p, v)
	if type(v) ~= "string" or v == "" then
		return "Text fehlt"
	end
	Net.NotifyAll("📢 " .. v:sub(1, 120), nil, "levelup")
	return "Gesendet"
end
C.save = function(p, v, t)
	DataService.Save(t)
	return "Gespeichert"
end

local PLAYER_CMDS = { money = true, setmoney = true, xp = true, level = true, rep = true, unlockall = true, fillstock = true, speed = true, jump = true, heal = true, tp = true, bring = true, kick = true, save = true }

function AdminService.Run(p: Player, cmd: any, value: any, target: any): (boolean, string)
	if not isAdmin(p) then
		return false, "Kein Admin"
	end
	local fn = type(cmd) == "string" and C[cmd:lower()]
	if not fn then
		return false, "Unbekannter Befehl: " .. tostring(cmd)
	end
	local t = p
	if PLAYER_CMDS[cmd:lower()] then
		t = findPlayer(target, p)
		if not t or not DataService.Get(t) then
			return false, "Spieler nicht gefunden"
		end
	end
	local ok, msg = pcall(fn, p, value, t)
	if not ok then
		warn("[Admin]", cmd, msg)
		return false, "Fehler: " .. tostring(msg)
	end
	return true, msg or "OK"
end

-- chat: ;money 5000 [spieler]   ;speed 40   ;announce Hallo zusammen
local function onChat(p: Player, text: string)
	if text:sub(1, 1) ~= ";" or not isAdmin(p) then
		return
	end
	local parts = text:sub(2):split(" ")
	local cmd = table.remove(parts, 1) or ""
	local value, target
	if cmd == "announce" or cmd == "kick" then
		if cmd == "kick" then
			target = table.remove(parts, 1)
		end
		value = table.concat(parts, " ")
	elseif C[cmd] and tonumber(parts[1]) == nil and #parts == 1 and PLAYER_CMDS[cmd] then
		target = parts[1]
	else
		value, target = parts[1], parts[2]
	end
	local ok, msg = AdminService.Run(p, cmd, value, target)
	Net.Notify(p, (ok and "✅ " or "⚠️ ") .. msg, nil, ok and "info" or "warn")
end

local function setup(p: Player)
	if isAdmin(p) then
		p:SetAttribute("Admin", true)
	end
	p.Chatted:Connect(function(msg)
		onChat(p, msg)
	end)
end

function AdminService.Init()
	Players.PlayerAdded:Connect(setup)
	for _, p in ipairs(Players:GetPlayers()) do
		setup(p)
	end
	Net.OnRequest("Admin", function(p, args)
		if type(args) ~= "table" then
			return { ok = false }
		end
		local ok, msg = AdminService.Run(p, args.cmd, args.value, args.target)
		return { ok = ok, msg = msg }
	end)
end

return AdminService
