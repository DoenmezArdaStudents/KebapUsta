-- Visible items in the player's hand: every successful kitchen action briefly puts the real item
-- (bread, a lettuce leaf, a sauce bottle, a drink …) into the right hand, welded to RightHand so
-- everyone sees it. The player attributes HandAct/HandT drive the arm pose and the first-person
-- view model on the clients (Client/HandUI). The carried tray ("Tray") and the held bread ("HoldMeal",
-- Server/FoodPreparationService) flag a held pose; the bread itself is a carried model, no flash.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Services = script.Parent
local FoodPreparationService = require(Services.FoodPreparationService)
local IngredientData = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IngredientData"))

local HandService = {}
local folder: Folder
local current: { [Player]: Model } = {}

local VEG_MESH = { lettuce = "Lettuce", tomato = "Tomato", onion = "Onion", cabbage = "Cabbage", cucumber = "Cucumber" }

local function part(m: Model, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	return p
end

local function food(m: Model, name: string, cf: CFrame, s: number, tint: Color3?)
	local lib = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("Food")
	local src = lib and lib:FindFirstChild(name) :: BasePart?
	if not src then
		return nil
	end
	local p = src:Clone()
	p.Size = src.Size * s
	p.CFrame = cf
	local sa = p:FindFirstChildOfClass("SurfaceAppearance")
	if sa and tint then
		sa.Color = tint
	end
	p.Parent = m
	return p
end

-- builds the item around the grip point (hand space: -Y down from the palm, -Z forward)
local function build(kind: string, item: any, grip: CFrame): Model?
	local m = Instance.new("Model")
	if kind == "sauce" then
		local def = IngredientData.Sauce[item]
		local col = def and def.color or Color3.fromRGB(240, 240, 230)
		-- squeeze bottle held upside down, nozzle pointing at the kebab
		local body = grip * CFrame.Angles(math.rad(180), 0, 0)
		part(m, Vector3.new(0.85, 0.42, 0.42), body * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), col, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.14, 0.44, 0.44), body * CFrame.new(0, 0.58, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.26, 0.1, 0.1), body * CFrame.new(0, 0.76, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.3, 0.12, 0.43), body * CFrame.new(0, 0.05, -0.01), Color3.fromRGB(250, 250, 245), Enum.Material.Fabric) -- label band
	elseif kind == "veg" then
		local mesh = VEG_MESH[item]
		local ok = mesh and food(m, mesh, grip * CFrame.new(0, -0.1, -0.15) * CFrame.Angles(math.rad(70), 0, 0), 1.3)
		if not ok then
			local def = IngredientData.Veg[item]
			part(m, Vector3.new(0.5, 0.12, 0.4), grip * CFrame.new(0, -0.1, -0.15), def and def.color or Color3.fromRGB(120, 190, 70), Enum.Material.Grass)
		end
	elseif kind == "cheese" then
		for i = 1, 5 do
			if not food(m, "Cheese", grip * CFrame.new((i - 3) * 0.06, -0.12, -0.15) * CFrame.Angles(math.rad(i * 37), math.rad(i * 61), 0), 1.4) then
				part(m, Vector3.new(0.3, 0.06, 0.06), grip * CFrame.new((i - 3) * 0.06, -0.12, -0.15), Color3.fromRGB(250, 220, 110))
			end
		end
	elseif kind == "bread" then
		local cf = grip * CFrame.new(0, -0.2, -0.35) * CFrame.Angles(math.rad(80), 0, 0)
		if item == "classic" then
			if not food(m, "BreadBottom", cf, 0.75) then
				part(m, Vector3.new(1.2, 0.3, 0.8), cf, Color3.fromRGB(214, 160, 90), Enum.Material.Sand)
			end
		elseif item == "duerum" then
			if not food(m, "DuerumFlat", cf, 0.45) then
				part(m, Vector3.new(1.1, 0.05, 1.1), cf, Color3.fromRGB(232, 205, 150), Enum.Material.Sand, Enum.PartType.Cylinder)
			end
		else
			part(m, Vector3.new(0.95, 0.35, 0.7), cf, Color3.fromRGB(245, 245, 240))
		end
	elseif kind == "drink" then
		local def = IngredientData.Drinks[item]
		local col = def and def.color or Color3.fromRGB(200, 40, 40)
		local cf = grip * CFrame.new(0, -0.1, -0.12) * CFrame.Angles(math.rad(90), 0, 0)
		part(m, Vector3.new(0.75, 0.36, 0.36), cf * CFrame.Angles(0, 0, math.rad(90)), col, Enum.Material.Metal, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.06, 0.32, 0.32), cf * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif kind == "grill" then
		-- spatula
		part(m, Vector3.new(0.12, 0.12, 0.8), grip * CFrame.new(0, -0.05, -0.1), Color3.fromRGB(30, 30, 30))
		part(m, Vector3.new(0.5, 0.03, 0.55), grip * CFrame.new(0, -0.05, -0.75), Color3.fromRGB(200, 202, 206), Enum.Material.Metal)
	elseif kind == "board" then
		-- wrapping paper / foil being folded around the kebab
		part(m, Vector3.new(0.9, 0.02, 0.7), grip * CFrame.new(0, -0.15, -0.3) * CFrame.Angles(math.rad(60), 0, 0), Color3.fromRGB(206, 210, 216), Enum.Material.Foil)
	else
		m:Destroy()
		return nil
	end
	return m
end

function HandService.Flash(player: Player, kind: string, item: any, secs: number?)
	local char = player.Character
	local hand = char and char:FindFirstChild("RightHand") :: BasePart?
	if not hand or player:GetAttribute("Carry") then
		return
	end
	local old = current[player]
	if old then
		old:Destroy()
	end
	local m = build(kind, item, hand.CFrame * CFrame.new(0, -0.25, 0))
	if not m then
		return
	end
	m.Name = "Hand_" .. player.UserId
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = hand
			w.Part1 = p
			w.Parent = p
		end
	end
	m.Parent = folder -- outside the character: the first-person camera would hide it otherwise
	current[player] = m
	player:SetAttribute("HandAct", kind)
	player:SetAttribute("HandT", workspace:GetServerTimeNow())
	local t = secs or 1.1
	task.delay(t, function()
		if current[player] == m then
			current[player] = nil
			player:SetAttribute("HandAct", nil)
		end
		m:Destroy()
	end)
end

-- snapshot of what an action can change: meal contents, tray, grill (not where the meal lies: putting
-- it down or picking it up is no kitchen action)
local function signature(player: Player): string
	local s = FoodPreparationService.GetState(player)
	local ok, json = pcall(HttpService.JSONEncode, HttpService, { s.meal, #s.tray, s.grillStart ~= nil })
	return ok and json or tostring(os.clock())
end

local SHOWS = { sauce = true, veg = true, cheese = true, drink = true, grill = true, board = true }

function HandService.Init()
	folder = Instance.new("Folder")
	folder.Name = "HandItems"
	folder.Parent = workspace
	-- wrap every kitchen action: if it changed something, show the item in the hand
	FoodPreparationService.BeforeAction = function(player: Player, kind: string)
		return SHOWS[kind] and signature(player) or nil
	end
	FoodPreparationService.AfterAction = function(player: Player, part: BasePart, kind: string, before: string?)
		if before and signature(player) ~= before then
			HandService.Flash(player, kind, part:GetAttribute("Item"))
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		if current[p] then
			current[p]:Destroy()
			current[p] = nil
		end
	end)
end

return HandService
