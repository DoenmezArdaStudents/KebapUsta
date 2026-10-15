-- Server entry point: builds the world if needed, starts all services and loads players.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

if not workspace:FindFirstChild("Restaurant") then
	require(Services.WorldBuilder).Build()
end
-- every player spawns as the same Dönermann (same size, same outfit), in first person
if not game:GetService("StarterPlayer"):FindFirstChild("StarterCharacter") then
	require(Services.CharacterBuilder).Install()
	for _, p in ipairs(Players:GetPlayers()) do
		p:LoadCharacter()
	end
end

local Net = require(Services.Net)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local RestaurantService = require(Services.RestaurantService)
local UpgradeService = require(Services.UpgradeService)
local FoodPreparationService = require(Services.FoodPreparationService)
local OrderService = require(Services.OrderService)
local CustomerService = require(Services.CustomerService)
local GameLoopService = require(Services.GameLoopService)
local UnlockService = require(Services.UnlockService)
local GoalService = require(Services.GoalService)
local MeatCuttingService = require(Services.MeatCuttingService)
local BusinessService = require(Services.BusinessService)
local EmployeeService = require(Services.EmployeeService)
local ColdRoomService = require(Services.ColdRoomService)
local AdminService = require(Services.AdminService)
local LogisticsService = require(Services.LogisticsService)
local HandService = require(Services.HandService)
local BackDoorService = require(Services.BackDoorService)
local BackyardService = require(Services.BackyardService)
local EventService = require(Services.EventService)

local LobbyService = require(Services.LobbyService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

DataService.Init()

-- Public servers are lobbies; reserved servers (created by the lobby's teleport) run the game.
local isGameServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local started = false
local function startGame(hostId: number?)
	if started then
		return
	end
	started = true
	RestaurantService.PreferredOwnerId = hostId
	RestaurantService.Init()
	UpgradeService.Init()
	FoodPreparationService.Init()
	OrderService.Init()
	CustomerService.Init()
	GameLoopService.Init()
	UnlockService.Init()
	GoalService.Init()
	MeatCuttingService.Init()
	BusinessService.Init()
	EventService.Init()
	ColdRoomService.Init()
	EmployeeService.Init()
	LogisticsService.Init()
	HandService.Init()
	BackDoorService.Init()
	BackyardService.Init()
	AdminService.Init()
	ReplicatedStorage:SetAttribute("Mode", "game")
	RestaurantService.ChooseOwner()
	for _, p in ipairs(Players:GetPlayers()) do
		RestaurantService.PushShop(p)
		if workspace:FindFirstChild("Lobby") then
			p:LoadCharacter() -- Studio in-place start: respawn in the restaurant
		end
	end
end

if isGameServer then
	-- the host id comes with the first arriving player's teleport data
	local function readHost(p: Player)
		local host = LobbyService.HostFromJoinData(p)
		if host and not RestaurantService.PreferredOwnerId then
			RestaurantService.PreferredOwnerId = host
			RestaurantService.ChooseOwner()
		end
	end
	Players.PlayerAdded:Connect(readHost)
	for _, p in ipairs(Players:GetPlayers()) do
		readHost(p)
	end
	startGame(nil)
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		lobby:Destroy()
	end
else
	-- Studio cannot teleport: the lobby session starts right here on the host's slot
	LobbyService.StartInPlace = function(hostId: number, slot: number?)
		local host = Players:GetPlayerByUserId(hostId)
		if host then
			DataService.Load(host, slot)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= host then
				DataService.LoadGuest(p, host)
			end
		end
		startGame(hostId)
	end
	LobbyService.Init()
end

-- settings are the only free-form data the client may send; validate strictly
Net.OnRequest("SetSettings", function(player, args)
	local data = DataService.Get(player)
	if not data or type(args) ~= "table" then
		return { ok = false }
	end
	if args.lang == "de" or args.lang == "en" then
		data.settings.lang = args.lang
	end
	if type(args.ambience) == "number" and args.ambience == args.ambience then
		data.settings.ambience = math.clamp(args.ambience, 0, 1)
	end
	if type(args.sfx) == "number" and args.sfx == args.sfx then
		data.settings.sfx = math.clamp(args.sfx, 0, 1)
	end
	if type(args.hints) == "boolean" then
		data.settings.hints = args.hints
	end
	DataService.MarkDirty(player)
	EconomyService.Push(player)
	return { ok = true }
end)

Net.OnRequest("Sync", function(player)
	EconomyService.Push(player)
	RestaurantService.PushShop(player)
	OrderService.PushTickets()
	return { ok = true }
end)

-- co-op session end (host left / host never arrived): back to the lobby, progress is saved
local TeleportService = game:GetService("TeleportService")
local function sessionEnd(list: { Player }, msg: string)
	for _, p in ipairs(list) do
		Net.Notify(p, "🏠 " .. msg, nil, "warn")
	end
	task.wait(4)
	local alive = {}
	for _, p in ipairs(list) do
		if p.Parent then
			table.insert(alive, p)
		end
	end
	if #alive == 0 then
		return
	end
	local ok = not game:GetService("RunService"):IsStudio() and pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, alive)
	end)
	if not ok then
		for _, p in ipairs(alive) do
			p:Kick(msg)
		end
	end
end

-- the host loads their selected slot; everybody else plays as a guest on the host's restaurant
local function loadForGame(player: Player, hostId: number?, slot: number?)
	if not hostId or player.UserId == hostId then
		DataService.Load(player, slot)
		return
	end
	local t0 = os.clock()
	local host = nil
	while player.Parent and os.clock() - t0 < 60 do
		host = Players:GetPlayerByUserId(hostId)
		if host and DataService.Get(host) and not DataService.IsGuest(host) then
			break
		end
		host = nil
		task.wait(0.5)
	end
	if host then
		DataService.LoadGuest(player, host)
		EconomyService.Push(player)
		Net.Notify(player, ("👥 Du arbeitest im Restaurant von %s"):format(host.DisplayName), nil, "info")
	elseif player.Parent then
		sessionEnd({ player }, "Der Host ist nicht im Spiel – zurück zur Lobby")
	end
end

local function onPlayer(player: Player)
	task.spawn(function()
		if isGameServer then
			local info = LobbyService.JoinInfo(player) or {}
			loadForGame(player, info.host or RestaurantService.PreferredOwnerId, info.slot)
		elseif ReplicatedStorage:GetAttribute("Mode") == "game" then
			loadForGame(player, RestaurantService.PreferredOwnerId, nil) -- late joiner in a Studio session
		else
			DataService.LoadMeta(player) -- lobby: only the slot cards
		end
	end)
end
-- host chat command "!gastkauf": allow / forbid guests to make big purchases this session
local function hostChat(p: Player)
	p.Chatted:Connect(function(msg)
		if msg:lower() == "!gastkauf" and (p.UserId == RestaurantService.PreferredOwnerId or RestaurantService.IsOwner(p)) then
			EconomyService.GuestsMaySpend = not EconomyService.GuestsMaySpend
			Net.NotifyAll(EconomyService.GuestsMaySpend and "👑 Der Host erlaubt Gästen jetzt alle Käufe" or "👑 Große Käufe macht wieder nur der Host", nil, "info")
		end
	end)
end
Players.PlayerAdded:Connect(hostChat)
for _, p in ipairs(Players:GetPlayers()) do
	hostChat(p)
end
Players.PlayerRemoving:Connect(function(player)
	if ReplicatedStorage:GetAttribute("Mode") ~= "game" or player.UserId ~= RestaurantService.PreferredOwnerId then
		return
	end
	local guests = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and DataService.IsGuest(p) then
			table.insert(guests, p)
		end
	end
	if #guests > 0 then
		task.spawn(sessionEnd, guests, "Der Host hat das Restaurant verlassen – alles ist gespeichert")
	end
end)
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end

-- Studio-only debug hook (used for automated playtests); never created in live servers
if game:GetService("RunService"):IsStudio() then
	local dbg = Instance.new("BindableFunction")
	dbg.Name = "KebapDebug"
	dbg.OnInvoke = function(cmd: string, arg: any)
		local p = Players:GetPlayers()[1]
		if cmd == "customers" then
			return CustomerService.Debug()
		elseif cmd == "log" then
			return table.concat(CustomerService.EventLog, "\n")
		elseif cmd == "state" then
			local data = p and DataService.Get(p)
			local prep = p and FoodPreparationService.GetState(p)
			return {
				owner = tostring(RestaurantService.GetOwner()),
				tutorialActive = RestaurantService.TutorialActive,
				tutorialDone = data and data.tutorialDone,
				cash = data and data.cash,
				xp = data and data.xp,
				level = data and data.level,
				rep = RestaurantService.GetReputation(),
				clock = RestaurantService.Clock,
				meal = prep and prep.meal,
				tray = prep and #prep.tray,
				dayStats = RestaurantService.DayStats,
				saving = p and DataService.IsSaving(p),
			}
		elseif cmd == "setData" and p then
			local data = DataService.Get(p)
			for k, v in pairs(arg) do
				data[k] = v
			end
			EconomyService.Push(p)
			RestaurantService.ApplyWorldUpgrades()
			UnlockService.ApplyWorld()
			RestaurantService.PushShop()
			return true
		elseif cmd == "setStock" and p then
			local data = DataService.Get(p)
			for k, v in pairs(arg) do
				data.stock[k] = v
			end
			RestaurantService.PushShop()
			return true
		elseif cmd == "spawn" then
			local c = CustomerService.Spawn(arg or {})
			return c and c.id
		elseif cmd == "aggro" then
			return CustomerService.DebugAggro(arg)
		elseif cmd == "clock" then
			RestaurantService.Clock = arg
			return true
		elseif cmd == "biz" then
			BusinessService.DebugRefresh()
			return RestaurantService.BuildShopState().biz
		elseif cmd == "construct" then
			BusinessService.DebugConstruct(arg)
			return true
		elseif cmd == "event" then
			return EventService.Start(arg)
		elseif cmd == "guest" then
			-- simulate a co-op guest: arg = player index to turn into a guest of player 1
			local g = Players:GetPlayers()[arg or 2]
			if g and g ~= p then
				DataService.LoadGuest(g, p)
				return true
			end
			return false
		elseif cmd == "data" and p then
			return DataService.Get(p)
		elseif cmd == "restock" and p then
			return RestaurantService.Restock(p, arg)
		elseif cmd == "dirt" then
			BusinessService.AddDirt(arg[1], arg[2])
			return #BusinessService.Dirt()
		end
		return nil
	end
	dbg.Parent = game:GetService("ServerStorage")
end
