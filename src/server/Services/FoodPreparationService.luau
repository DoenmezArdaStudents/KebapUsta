-- Interactive kebap preparation: bread, grill, rotating spits, vegetables, sauces, closing,
-- packing and the tray. Every ingredient is tracked exactly and shown visually.
--
-- Hands (issue #3): nothing teleports. Whatever changes place is carried, and a player has one pair
-- of hands for one thing: the bread (location "hand"), the meat pan (bowlAt "hand"), the bread top
-- (lid), the tray (trayAt "hand") or a box / meat cone (attribute Carry, Server/LogisticsService +
-- ColdRoomService). The order of work:
--   1. spit → carved portions go into the meat pan in your hands (Server/MeatCuttingService)
--   2. board → put the pan down; bread station → the bread is in your hand → put it on the board
--   3. board → the meat goes from the pan onto the bread; vegetables and cheese are added at their
--      stations to your bread (on the board or in your hand)
--   3b. sauces are bottles: take one from its dispenser (it is gone there – nobody else can use it
--      meanwhile), squeeze it onto the bread at the board and put it back. With the bread in your
--      hand you pump the sauce straight from the dispenser instead.
--   4. a classic bread is closed with its top half, fetched separately from the bread station
--   5. grill: pick the bread up, put it in, take it out into your hands again
--   6. packing puts the meal on your tray at the front of the board; pick the tray up to serve
-- Drinks go on the tray in your hands; only a carried tray can be served, only carried things trashed.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local OrderLogic = require(Shared.OrderLogic)
local Net = require(script.Parent.Net)
local EconomyService = require(script.Parent.EconomyService)
local RestaurantService = require(script.Parent.RestaurantService)

local FoodPreparationService = {}

type PrepState = {
	meal: any?,
	board: number?, -- the board the meal lies on (location "board")
	location: string?, -- "hand" | "board" | "grill"
	grillSlot: number?,
	grillStart: number?,
	tray: { any },
	trayAt: any, -- "hand" | board index | nil (no tray: nothing on it)
	bowl: { { meat: string, q: number } }?, -- carved portions in the meat pan
	bowlAt: any, -- "hand" | board index | nil
	lid: boolean?, -- the top half of a classic bread is in the hands
	sauce: string?, -- sauce bottle in the hand (taken from its dispenser)
	bowlModel: Model?,
	lidModel: Model?,
	sauceModel: Model?,
	lastCut: number,
	lastAction: number,
	model: Model?,
	trayModel: Model?,
}

local states: { [Player]: PrepState } = {}
local sauceHolder: { [string]: Player } = {} -- whose hand each dispenser's bottle is in
local grillOwner: { [number]: Player } = {}
local spits: { [string]: { heat: string, doneness: number, model: Instance? } } = {
	chicken = { heat = "low", doneness = 0.3 },
	veal = { heat = "low", doneness = 0.3 },
}
local mealFolder: Folder
local trayFolder: Folder

local function getState(player: Player): PrepState
	local s = states[player]
	if not s then
		s = { tray = {}, lastCut = 0, lastAction = 0 }
		states[player] = s
	end
	return s
end
FoodPreparationService.GetState = getState

local function restaurant()
	return workspace:FindFirstChild("Restaurant")
end

local function findStation(kind: string, attr: string?, value: any?): BasePart?
	for _, p in ipairs(CollectionService:GetTagged("Station")) do
		if p:GetAttribute("Station") == kind and (not attr or p:GetAttribute(attr) == value) then
			return p
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Hands & boards
---------------------------------------------------------------------------
local function mealInHand(s: PrepState): boolean
	return s.meal ~= nil and s.location == "hand"
end

local function mealOnBoard(s: PrepState, index: number): boolean
	return s.meal ~= nil and s.location == "board" and s.board == index
end

-- everything but the tray (drinks go on a carried tray)
local function handsBusyNoTray(player: Player, s: PrepState): boolean
	return mealInHand(s) or s.bowlAt == "hand" or s.lid == true or s.sauce ~= nil or player:GetAttribute("Carry") ~= nil
end

local function handsBusy(player: Player, s: PrepState): boolean
	return handsBusyNoTray(player, s) or s.trayAt == "hand"
end

function FoodPreparationService.HandsBusy(player: Player): boolean
	return handsBusy(player, getState(player))
end

function FoodPreparationService.TrayInHand(player: Player): boolean
	return getState(player).trayAt == "hand"
end

-- a board is in use while someone's meal, meat pan or tray stands on it
local function boardUser(index: number): Player?
	for p, s in pairs(states) do
		if mealOnBoard(s, index) or s.trayAt == index or s.bowlAt == index then
			return p
		end
	end
	return nil
end

-- the board a player's things stand on (they all share one)
local function myBoard(s: PrepState): number?
	if s.meal and s.location == "board" then
		return s.board
	end
	if type(s.bowlAt) == "number" then
		return s.bowlAt
	end
	if type(s.trayAt) == "number" then
		return s.trayAt
	end
	return nil
end

-- the board parts carry their user so the clients can grey out the prompts of a busy board
local function syncBoards()
	for _, b in ipairs(CollectionService:GetTagged("Station")) do
		local i = b:GetAttribute("Board")
		if b:GetAttribute("Station") == "board" and type(i) == "number" then
			local user = boardUser(i)
			local id = user and user.UserId or nil
			if b:GetAttribute("User") ~= id then
				b:SetAttribute("User", id)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------
local function bit(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function toastColor(base: Color3, heat: number): Color3
	if heat == 1 then
		return base:Lerp(Color3.fromRGB(170, 110, 50), 0.45)
	elseif heat == 2 then
		return base:Lerp(Color3.fromRGB(40, 25, 15), 0.75)
	end
	return base
end

-- deterministic scatter so a meal looks the same after each rebuild
local function scatter(seed: number, i: number, w: number, d: number)
	local r = Random.new(seed * 131 + i * 17)
	return (r:NextNumber() - 0.5) * w, (r:NextNumber() - 0.5) * d, r:NextNumber() * math.pi
end

local function meatColor(quality: number, meat: string): Color3
	local def = IngredientData.Meat[meat]
	if quality < 0.5 then
		return Color3.fromRGB(45, 28, 18)
	elseif quality < 0.8 then
		return def.cooked:Lerp(def.raw, 0.35)
	end
	return def.cooked
end

-- Builds a model of the meal at `origin` (top surface centre). scale < 1 for tray display.
local function buildMealParts(meal, origin: CFrame, scale: number?): Model
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Meal"
	local breadDef = IngredientData.Bread[meal.bread]
	local baseColor = toastColor(breadDef.color, meal.heat)
	local o = origin
	local function c(x, y, z)
		return o * CFrame.new(x * s, y * s, z * s)
	end
	-- plate below when served for eating in
	if meal.pack == "plate" then
		bit(m, Vector3.new(0.08, 2.8, 2.8) * s, c(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		o = o * CFrame.new(0, 0.08 * s, 0)
	end

	local fillW, fillD, fillY = 1.3, 0.7, 0.32
	if meal.bread == "classic" then
		local bottom = bit(m, Vector3.new(1.9, 0.3, 1.2) * s, c(0, 0.15, 0), baseColor, Enum.Material.Sand)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = bottom
	elseif meal.bread == "duerum" then
		if not meal.closed then
			bit(m, Vector3.new(0.06, 2.3, 2.3) * s, c(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), baseColor, Enum.Material.Sand, Enum.PartType.Cylinder)
			fillW, fillD, fillY = 1.2, 0.6, 0.12
		end
	elseif meal.bread == "box" then
		local white = Color3.fromRGB(245, 245, 240)
		bit(m, Vector3.new(1.9, 0.08, 1.4) * s, c(0, 0.04, 0), white)
		bit(m, Vector3.new(1.9, 0.6, 0.06) * s, c(0, 0.3, 0.7), white)
		bit(m, Vector3.new(1.9, 0.6, 0.06) * s, c(0, 0.3, -0.7), white)
		bit(m, Vector3.new(0.06, 0.6, 1.4) * s, c(0.95, 0.3, 0), white)
		bit(m, Vector3.new(0.06, 0.6, 1.4) * s, c(-0.95, 0.3, 0), white)
		fillW, fillD, fillY = 1.6, 1.1, 0.2
	end

	local showFilling = not (meal.bread == "duerum" and meal.closed)
	if showFilling then
		local idx = 0
		local function scatterBits(count, size, color, material, layerY)
			for _ = 1, count do
				idx += 1
				local x, z, rot = scatter(#meal.steps, idx, fillW, fillD)
				bit(m, size * s, c(x, layerY, z) * CFrame.Angles(0, rot, 0), color, material)
			end
		end
		local layer = fillY
		local meatIdx = 0
		for meat, n in pairs(meal.meat) do
			for _ = 1, n do
				meatIdx += 1
				local q = meal.meatQuality[meatIdx] or 1
				scatterBits(5, Vector3.new(0.4, 0.12, 0.18), meatColor(q, meat), Enum.Material.Sand, layer)
				layer += 0.03
			end
		end
		for _, v in ipairs(IngredientData.VegOrder) do
			local n = meal.veg[v] or 0
			if n > 0 then
				layer += 0.04
				scatterBits(4 * n, Vector3.new(0.25, 0.08, 0.2), IngredientData.Veg[v].color, Enum.Material.SmoothPlastic, layer)
			end
		end
		if meal.cheese > 0 then
			layer += 0.04
			scatterBits(5 * meal.cheese, Vector3.new(0.15, 0.1, 0.15), IngredientData.Extra.cheese.color, Enum.Material.SmoothPlastic, layer)
		end
		local sIdx = 0
		for _, sc in ipairs(IngredientData.SauceOrder) do
			local n = meal.sauces[sc] or 0
			for k = 1, n do
				sIdx += 1
				local z = ((sIdx % 4) - 1.5) * 0.18
				bit(m, Vector3.new(fillW * 0.9, 0.04, 0.09) * s, c(0, layer + 0.05 + k * 0.01, z) * CFrame.Angles(0, math.rad(8 * sIdx), 0), IngredientData.Sauce[sc].color, Enum.Material.SmoothPlastic)
			end
		end
	end

	if meal.closed then
		if meal.bread == "classic" then
			local top = bit(m, Vector3.new(1.9, 0.35, 1.2) * s, c(0, 0.62, -0.05) * CFrame.Angles(math.rad(-12), 0, 0), baseColor, Enum.Material.Sand)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = top
		elseif meal.bread == "duerum" then
			bit(m, Vector3.new(2.1, 0.75, 0.75) * s, c(0, 0.38, 0), baseColor, Enum.Material.Sand, Enum.PartType.Cylinder)
			-- visible filling at the ends
			local endColor = Color3.fromRGB(120, 190, 70)
			if (meal.meat.veal or 0) > 0 then
				endColor = IngredientData.Meat.veal.cooked
			elseif (meal.meat.chicken or 0) > 0 then
				endColor = IngredientData.Meat.chicken.cooked
			end
			bit(m, Vector3.new(0.05, 0.6, 0.6) * s, c(1.06, 0.38, 0), endColor, Enum.Material.Sand, Enum.PartType.Cylinder)
		elseif meal.bread == "box" then
			bit(m, Vector3.new(2, 0.08, 1.5) * s, c(0, 0.64, 0), Color3.fromRGB(245, 245, 240))
		end
	end

	if meal.pack == "takeaway" then
		if meal.bread == "duerum" then
			bit(m, Vector3.new(1.3, 0.8, 0.8) * s, c(-0.45, 0.38, 0), Color3.fromRGB(205, 210, 215), Enum.Material.Foil, Enum.PartType.Cylinder)
		elseif meal.bread == "classic" then
			bit(m, Vector3.new(2.05, 0.75, 0.5) * s, c(0, 0.38, 0.45), Color3.fromRGB(245, 240, 230), Enum.Material.Fabric)
			bit(m, Vector3.new(2.06, 0.1, 0.52) * s, c(0, 0.55, 0.45), Color3.fromRGB(176, 52, 38), Enum.Material.SmoothPlastic)
		else
			bit(m, Vector3.new(0.4, 0.05, 1.52) * s, c(0, 0.7, 0), Color3.fromRGB(176, 52, 38))
		end
	end
	m.Parent = mealFolder
	return m
end

-- Food meshes (art/food/build_food.py → ServerStorage.Models.Food). Each template is a MeshPart
-- with a SurfaceAppearance, so toasting, meat quality and freshness tint the real texture.
local ServerStorage = game:GetService("ServerStorage")
local VEG_MESH = { lettuce = "Lettuce", tomato = "Tomato", onion = "Onion", cabbage = "Cabbage", cucumber = "Cucumber" }
local WHITE = Color3.new(1, 1, 1)
local TOAST_TINT = { [0] = WHITE, [1] = Color3.fromRGB(222, 186, 150), [2] = Color3.fromRGB(86, 66, 54) }
local MEAT_TINT = { chicken = Color3.fromRGB(255, 236, 210), veal = Color3.fromRGB(160, 112, 92) }

local function foodTemplates(): Instance?
	local models = ServerStorage:FindFirstChild("Models")
	return models and models:FindFirstChild("Food")
end

local function piece(parent: Instance, name: string, cf: CFrame, s: number, tint: Color3?): BasePart?
	local lib = foodTemplates()
	local src = lib and lib:FindFirstChild(name) :: BasePart?
	if not src then
		return nil
	end
	local p = src:Clone()
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = src.Size * s
	p.CFrame = cf
	local sa = p:FindFirstChildOfClass("SurfaceAppearance")
	if sa and tint then
		sa.Color = tint
	end
	p.Parent = parent
	return p
end

local function buildMealMeshes(meal, origin: CFrame, scale: number?): Model
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Meal"
	local o = origin
	local function c(x, y, z)
		return o * CFrame.new(x * s, y * s, z * s)
	end
	local toast = TOAST_TINT[meal.heat] or WHITE
	if meal.pack == "plate" then
		bit(m, Vector3.new(0.08, 2.8, 2.8) * s, c(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		o = o * CFrame.new(0, 0.08 * s, 0)
	end

	local fillW, fillD, fillY = 1.2, 0.62, 0.14
	if meal.bread == "classic" then
		piece(m, "BreadBottom", c(0, 0.16, 0), s, toast)
	elseif meal.bread == "duerum" then
		if not meal.closed then
			piece(m, "DuerumFlat", c(0, 0.03, 0), s, toast)
			fillW, fillD, fillY = 1.2, 0.6, 0.06
		end
	elseif meal.bread == "box" then
		local white = Color3.fromRGB(245, 245, 240)
		bit(m, Vector3.new(1.9, 0.08, 1.4) * s, c(0, 0.04, 0), white)
		bit(m, Vector3.new(1.9, 0.6, 0.06) * s, c(0, 0.3, 0.7), white)
		bit(m, Vector3.new(1.9, 0.6, 0.06) * s, c(0, 0.3, -0.7), white)
		bit(m, Vector3.new(0.06, 0.6, 1.4) * s, c(0.95, 0.3, 0), white)
		bit(m, Vector3.new(0.06, 0.6, 1.4) * s, c(-0.95, 0.3, 0), white)
		fillW, fillD, fillY = 1.6, 1.1, 0.12
	end

	local fresh = math.clamp(meal.fresh or 1, 0, 1)
	local vegTint = WHITE:Lerp(Color3.fromRGB(196, 176, 110), 1 - fresh)
	local showFilling = not (meal.bread == "duerum" and meal.closed)
	if showFilling then
		local idx = 0
		local function spot(layerY: number, tilt: number)
			idx += 1
			local x, z, rot = scatter(#meal.steps, idx, fillW, fillD)
			local r = Random.new(idx * 97 + #meal.steps)
			return c(x, layerY, z) * CFrame.Angles(r:NextNumber(-tilt, tilt), rot * 2, r:NextNumber(-tilt, tilt))
		end
		local layer = fillY
		local meatIdx = 0
		for meat, n in pairs(meal.meat) do
			for _ = 1, n do
				meatIdx += 1
				local q = meal.meatQuality[meatIdx] or 1
				local tint = MEAT_TINT[meat] or WHITE
				if q < 0.5 then
					tint = Color3.fromRGB(70, 50, 40)
				elseif q < 0.8 then
					tint = tint:Lerp(Color3.fromRGB(255, 205, 190), 0.35)
				end
				for _ = 1, 4 do
					piece(m, "MeatShaving", spot(layer, 0.35), s, tint)
				end
				layer += 0.035
			end
		end
		for _, v in ipairs(IngredientData.VegOrder) do
			local n = meal.veg[v] or 0
			local mesh = VEG_MESH[v]
			if n > 0 and mesh then
				layer += 0.04
				for _ = 1, (v == "lettuce" and 3 or 4) * n do
					piece(m, mesh, spot(layer, v == "lettuce" and 0.5 or 0.3), s, vegTint)
				end
			end
		end
		if meal.cheese > 0 then
			layer += 0.035
			for _ = 1, 6 * meal.cheese do
				piece(m, "Cheese", spot(layer, 0.4), s, nil)
			end
		end
		local sIdx = 0
		for _, sc in ipairs(IngredientData.SauceOrder) do
			local n = meal.sauces[sc] or 0
			for k = 1, n do
				sIdx += 1
				local z = ((sIdx % 3) - 1) * 0.16
				piece(m, "Sauce", c(0, layer + 0.06 + k * 0.012, z) * CFrame.Angles(0, math.rad(6 * sIdx), 0), s * (fillW / 1.3), IngredientData.Sauce[sc].color)
			end
		end
	end

	if meal.closed then
		if meal.bread == "classic" then
			piece(m, "BreadTop", c(0, 0.7, 0.2) * CFrame.Angles(math.rad(24), 0, 0), s, toast)
		elseif meal.bread == "duerum" then
			piece(m, "DuerumRolled", c(0, 0.39, 0), s, toast)
			local endColor = Color3.fromRGB(120, 190, 70)
			if (meal.meat.veal or 0) > 0 then
				endColor = IngredientData.Meat.veal.cooked
			elseif (meal.meat.chicken or 0) > 0 then
				endColor = IngredientData.Meat.chicken.cooked
			end
			bit(m, Vector3.new(0.05, 0.42, 0.42) * s, c(1.0, 0.39, 0), endColor, Enum.Material.Sand, Enum.PartType.Cylinder)
		elseif meal.bread == "box" then
			bit(m, Vector3.new(2, 0.08, 1.5) * s, c(0, 0.64, 0), Color3.fromRGB(245, 245, 240))
		end
	end

	if meal.pack == "takeaway" then
		if meal.bread == "duerum" then
			bit(m, Vector3.new(1.3, 0.82, 0.82) * s, c(-0.45, 0.39, 0), Color3.fromRGB(205, 210, 215), Enum.Material.Foil, Enum.PartType.Cylinder)
		elseif meal.bread == "classic" then
			bit(m, Vector3.new(2.05, 0.75, 0.5) * s, c(0, 0.38, 0.45), Color3.fromRGB(245, 240, 230), Enum.Material.Fabric)
			bit(m, Vector3.new(2.06, 0.1, 0.52) * s, c(0, 0.55, 0.45), Color3.fromRGB(176, 52, 38), Enum.Material.SmoothPlastic)
		else
			bit(m, Vector3.new(0.4, 0.05, 1.52) * s, c(0, 0.7, 0), Color3.fromRGB(176, 52, 38))
		end
	end
	m.Parent = mealFolder
	return m
end

function FoodPreparationService.BuildMealModel(meal, origin: CFrame, scale: number?): Model
	if foodTemplates() and meal.bread ~= nil then
		return buildMealMeshes(meal, origin, scale)
	end
	return buildMealParts(meal, origin, scale)
end

local function boardCFrame(index: number): CFrame?
	local b = findStation("board", "Board", index)
	return b and (b.CFrame * CFrame.new(0, b.Size.Y / 2, 0))
end

local function grillCFrame(slot: number): CFrame?
	local g = findStation("grill", "Slot", slot)
	return g and (g.CFrame * CFrame.new(0, g.Size.Y / 2, 0))
end

local HOLD_MEAL = CFrame.new(0, 0.15, -1.35) -- held bread, in front of the root (visible in first person)
local HOLD_TRAY = CFrame.new(0, 0.2, -1.6)
local HOLD_BOWL = CFrame.new(0, 0.1, -1.3)
-- from the board's top centre: bread on the left, meat pan on the right, tray at the pass to the guests
local MEAL_ON_BOARD = CFrame.new(-0.45, 0, 0)
local BOWL_ON_BOARD = CFrame.new(1.02, 0, 0.1)
local TRAY_ON_BOARD = CFrame.new(0, -0.15, 1.68)

local function rootPart(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- carried models live outside the character (the first-person camera would hide them) and follow it
local function weldTo(m: Model, root: BasePart)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
end

-- held pose on the clients (Client/HandUI)
local function updateHold(player: Player, s: PrepState)
	local hold = mealInHand(s) or s.bowlAt == "hand" or s.lid == true
	if player:GetAttribute("Hold") ~= (hold or nil) then
		player:SetAttribute("Hold", hold or nil)
	end
end

local function refreshMealVisual(player: Player)
	local s = getState(player)
	updateHold(player, s)
	if s.model then
		s.model:Destroy()
		s.model = nil
	end
	if not s.meal then
		return
	end
	local cf, root
	if s.location == "grill" and s.grillSlot then
		cf = grillCFrame(s.grillSlot)
	elseif s.location == "board" and s.board then
		local b = boardCFrame(s.board)
		cf = b and b * MEAL_ON_BOARD
	elseif s.location == "hand" then
		root = rootPart(player)
		cf = root and root.CFrame * HOLD_MEAL
	end
	if cf then
		s.model = FoodPreparationService.BuildMealModel(s.meal, cf, root and 0.55 or nil)
		s.model.Name = "Meal_" .. player.UserId
		if root then
			weldTo(s.model, root)
		end
	end
end

-- the tray: carried in front of the character, or standing at the front of a board
local function refreshTrayVisual(player: Player)
	local s = getState(player)
	if #s.tray == 0 then
		s.trayAt = nil
	end
	player:SetAttribute("Tray", s.trayAt == "hand" or nil)
	if s.trayModel then
		s.trayModel:Destroy()
		s.trayModel = nil
	end
	local root, base
	if s.trayAt == "hand" then
		root = rootPart(player)
		base = root and root.CFrame * HOLD_TRAY
	elseif type(s.trayAt) == "number" then
		local b = boardCFrame(s.trayAt)
		base = b and b * TRAY_ON_BOARD
	end
	if not base then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Tray"
	local trayPart = bit(m, Vector3.new(2.3, 0.1, 1.3), base, Color3.fromRGB(176, 52, 38), Enum.Material.SmoothPlastic)
	for i, item in ipairs(s.tray) do
		local x = -0.8 + ((i - 1) % 3) * 0.8
		local z = (i > 3) and 0.35 or -0.1
		local cf = trayPart.CFrame * CFrame.new(x, 0.05, z)
		if item.kind == "drink" then
			bit(m, Vector3.new(0.7, 0.32, 0.32), cf * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.rad(90)), IngredientData.Drinks[item.id].color, Enum.Material.Glass, Enum.PartType.Cylinder)
		else
			local mm = FoodPreparationService.BuildMealModel(item.meal, cf, 0.35)
			for _, p in ipairs(mm:GetChildren()) do
				p.Parent = m
			end
			mm:Destroy()
		end
	end
	if root then
		weldTo(m, root)
	end
	m.Name = "Tray_" .. player.UserId
	m.Parent = trayFolder
	s.trayModel = m
end
FoodPreparationService.RefreshTray = refreshTrayVisual

local function meatTint(meat: string, q: number): Color3
	local tint = MEAT_TINT[meat] or WHITE
	if q < 0.5 then
		return Color3.fromRGB(70, 50, 40)
	elseif q < 0.8 then
		return tint:Lerp(Color3.fromRGB(255, 205, 190), 0.35)
	end
	return tint
end

-- stainless gastro pan with the carved meat piled inside
local function buildBowl(items: { any }, cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "MeatPan"
	local steel = Color3.fromRGB(205, 209, 214)
	local w, d, h, t = 0.86, 0.66, 0.3, 0.035
	local function steelBit(size: Vector3, at: CFrame)
		local p = bit(m, size, cf * at, steel, Enum.Material.Metal)
		p.Reflectance = 0.25
		return p
	end
	steelBit(Vector3.new(w - 0.06, t, d - 0.06), CFrame.new(0, t / 2, 0))
	for _, sx in ipairs({ -1, 1 }) do
		-- slightly flared walls and a rolled rim like a real GN pan
		steelBit(Vector3.new(t, h, d), CFrame.new(sx * (w / 2 - t / 2), h / 2, 0) * CFrame.Angles(0, 0, math.rad(-sx * 4)))
		steelBit(Vector3.new(w, h, t), CFrame.new(0, h / 2, sx * (d / 2 - t / 2)) * CFrame.Angles(math.rad(sx * 4), 0, 0))
		steelBit(Vector3.new(0.07, 0.03, d + 0.1), CFrame.new(sx * (w / 2 + 0.02), h, 0))
		steelBit(Vector3.new(w + 0.1, 0.03, 0.07), CFrame.new(0, h, sx * (d / 2 + 0.02)))
	end
	local idx = 0
	for k, it in ipairs(items) do
		local layer = t + 0.05 + math.min(k - 1, 6) * 0.03
		for _ = 1, 4 do
			idx += 1
			local x, z, rot = scatter(7, idx, w - 0.3, d - 0.3)
			local at = cf * CFrame.new(x, layer, z) * CFrame.Angles(0, rot * 2, (idx % 3 - 1) * 0.3)
			if not piece(m, "MeatShaving", at, 0.85, meatTint(it.meat, it.q)) then
				bit(m, Vector3.new(0.22, 0.08, 0.14), at, meatColor(it.q, it.meat), Enum.Material.Sand)
			end
		end
	end
	m.Parent = mealFolder
	return m
end

-- the meat pan: in the hands or standing on the right of a board
local function refreshBowlVisual(player: Player)
	local s = getState(player)
	if s.bowl == nil then
		s.bowlAt = nil
	end
	updateHold(player, s)
	if s.bowlModel then
		s.bowlModel:Destroy()
		s.bowlModel = nil
	end
	local root, cf
	if s.bowlAt == "hand" then
		root = rootPart(player)
		cf = root and root.CFrame * HOLD_BOWL
	elseif type(s.bowlAt) == "number" then
		local b = boardCFrame(s.bowlAt)
		cf = b and b * BOWL_ON_BOARD
	end
	if not cf or not s.bowl then
		return
	end
	local m = buildBowl(s.bowl, cf)
	m.Name = "MeatPan_" .. player.UserId
	if root then
		weldTo(m, root)
	end
	s.bowlModel = m
end

-- arm animation on every client (Client/HandUI): "sauce" = squeezing the held bottle over the bread,
-- "pump" = pressing the dispenser onto the bread held in the other hand
local function handAct(player: Player, kind: string)
	local t = workspace:GetServerTimeNow()
	player:SetAttribute("HandAct", kind)
	player:SetAttribute("HandT", t)
	task.delay(1.1, function()
		if player:GetAttribute("HandT") == t then
			player:SetAttribute("HandAct", nil)
		end
	end)
end

local HOLD_SAUCE = CFrame.new(0.85, 0.3, -1.25)
local SQUEEZE_SAUCE = CFrame.new(0.3, 0.75, -1.75) * CFrame.Angles(math.rad(180), 0, math.rad(12))

-- the sauce bottle in the right hand; upside down above the bread while squeezing
local function refreshSauceVisual(player: Player, squeezing: boolean?)
	local s = getState(player)
	player:SetAttribute("HoldSauce", s.sauce)
	if s.sauceModel then
		s.sauceModel:Destroy()
		s.sauceModel = nil
	end
	local root = s.sauce and rootPart(player)
	if not root or not s.sauce then
		return
	end
	local def = IngredientData.Sauce[s.sauce]
	local col = def and def.color or Color3.fromRGB(240, 240, 230)
	local m = Instance.new("Model")
	m.Name = "Sauce_" .. player.UserId
	local cf = root.CFrame * (squeezing and SQUEEZE_SAUCE or HOLD_SAUCE)
	local vertical = CFrame.Angles(0, 0, math.rad(90))
	bit(m, Vector3.new(0.85, 0.42, 0.42), cf * vertical, col, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	bit(m, Vector3.new(0.14, 0.44, 0.44), cf * CFrame.new(0, 0.48, 0) * vertical, Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	bit(m, Vector3.new(0.26, 0.1, 0.1), cf * CFrame.new(0, 0.66, 0) * vertical, Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	bit(m, Vector3.new(0.3, 0.12, 0.43), cf * CFrame.new(0, -0.05, -0.01), Color3.fromRGB(250, 250, 245), Enum.Material.Fabric)
	weldTo(m, root)
	m.Parent = mealFolder
	s.sauceModel = m
end

-- the dispenser shows its bottle only while nobody holds it
local function setDispenser(id: string, holder: Player?)
	sauceHolder[id] = holder
	local p = findStation("sauce", "Item", id)
	if not p then
		return
	end
	p:SetAttribute("HeldBy", holder and holder.UserId or nil)
	local unit = p.Parent
	local parts = (unit and unit:IsA("Model")) and unit:GetDescendants() or { p }
	for _, d in ipairs(parts) do
		if d:IsA("BasePart") then
			if holder then
				if d:GetAttribute("BaseT") == nil then
					d:SetAttribute("BaseT", d.Transparency)
				end
				d.Transparency = 1
			elseif d:GetAttribute("BaseT") ~= nil then
				d.Transparency = d:GetAttribute("BaseT")
				d:SetAttribute("BaseT", nil)
			end
		end
	end
end

-- put a held bottle back into its dispenser (also when the player dies or leaves)
local function returnSauce(player: Player)
	local s = states[player]
	if not s or not s.sauce then
		return
	end
	if sauceHolder[s.sauce] == player then
		setDispenser(s.sauce, nil)
	end
	s.sauce = nil
	refreshSauceVisual(player)
end

-- the top half of a classic bread, carried to the board to close it
local function refreshLidVisual(player: Player)
	local s = getState(player)
	updateHold(player, s)
	if s.lidModel then
		s.lidModel:Destroy()
		s.lidModel = nil
	end
	local root = s.lid and rootPart(player)
	if not root then
		return
	end
	local m = Instance.new("Model")
	m.Name = "BreadTop_" .. player.UserId
	local cf = root.CFrame * HOLD_MEAL * CFrame.new(0, 0.2, 0)
	if not piece(m, "BreadTop", cf, 0.55, nil) then
		local p = bit(m, Vector3.new(1.05, 0.2, 0.66), cf, IngredientData.Bread.classic.color, Enum.Material.Sand)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	weldTo(m, root)
	m.Parent = mealFolder
	s.lidModel = m
end

---------------------------------------------------------------------------
-- State publishing
---------------------------------------------------------------------------
local function push(player: Player)
	syncBoards()
	EconomyService.Push(player)
end

local function trayCapacity(): number
	return RestaurantService.UpgradeValue("tray")
end

function FoodPreparationService.TrayCapacity()
	return trayCapacity()
end

-- the meal leaves its place (packed, thrown away, player left)
local function releasePlace(player: Player)
	local s = getState(player)
	if s.grillSlot and grillOwner[s.grillSlot] == player then
		grillOwner[s.grillSlot] = nil
	end
	s.grillSlot = nil
	s.grillStart = nil
	s.board = nil
	s.location = nil
end

function FoodPreparationService.ClearMeal(player: Player)
	local s = getState(player)
	s.meal = nil
	releasePlace(player)
	if s.lid then
		s.lid = nil
		refreshLidVisual(player)
	end
	refreshMealVisual(player)
	push(player)
end

-- remove tray items (used by OrderService after serving)
function FoodPreparationService.RemoveTrayItems(player: Player, indices: { number })
	local s = getState(player)
	table.sort(indices, function(a, b)
		return a > b
	end)
	for _, i in ipairs(indices) do
		table.remove(s.tray, i)
	end
	refreshTrayVisual(player)
	push(player)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function notify(player, key, params, kind)
	Net.Notify(player, key, params, kind or "warn")
end

local function requireOpenMeal(player: Player): any?
	local s = getState(player)
	if not s.meal then
		notify(player, "n_need_meal")
		return nil
	end
	if s.location == "grill" then
		notify(player, "n_in_grill")
		return nil
	end
	if s.meal.closed then
		notify(player, "n_closed_meal")
		return nil
	end
	return s.meal
end

local function useStock(player: Player, stockId: string): boolean
	if RestaurantService.UseStock(stockId, 1) then
		return true
	end
	notify(player, "n_out_of_stock", { item = IngredientData.Stock[stockId].name })
	return false
end

local Actions = {}

function Actions.bread(player: Player, part: BasePart)
	local s = getState(player)
	local breadId = part:GetAttribute("Item")
	if not IngredientData.Bread[breadId] then
		return
	end
	if s.meal then
		-- the top half of a classic bread is fetched on its own, once everything is on the bottom half
		if breadId == "classic" and s.meal.bread == "classic" and not s.meal.closed and not s.lid then
			if handsBusy(player, s) then
				notify(player, "n_hands_full")
				return
			end
			s.lid = true
			Net.Sound(player, "add")
			refreshLidVisual(player)
			push(player)
			return
		end
		notify(player, s.lid and "n_hands_full" or "n_have_meal")
		return
	end
	if handsBusy(player, s) then
		notify(player, "n_hands_full")
		return
	end
	if not useStock(player, IngredientData.Bread[breadId].stock) then
		return
	end
	s.location = "hand"
	s.meal = OrderLogic.NewMeal(breadId)
	Net.Sound(player, "add")
	refreshMealVisual(player)
	push(player)
end

function Actions.grill(player: Player, part: BasePart)
	local s = getState(player)
	local slot = part:GetAttribute("Slot")
	if s.location == "grill" then
		-- take the bread out
		if s.grillSlot ~= slot then
			notify(player, "n_toast_busy")
			return
		end
		if handsBusy(player, s) then
			notify(player, "n_hands_full")
			return
		end
		local secs = (os.clock() - (s.grillStart or os.clock())) * RestaurantService.UpgradeValue("toaster")
		if secs >= Config.Prep.ToastBurnt then
			s.meal.heat = 2
			notify(player, "n_toast_burnt", nil, "bad")
		elseif secs >= Config.Prep.ToastPerfectMin then
			s.meal.heat = 1
			Net.Notify(player, "n_toast_perfect", nil, "success")
		end
		grillOwner[slot] = nil
		s.grillSlot = nil
		s.grillStart = nil
		s.location = "hand"
		table.insert(s.meal.steps, "heat:" .. s.meal.heat)
		Net.Sound(player, "toast")
		refreshMealVisual(player)
		push(player)
		return
	end
	if not s.meal then
		notify(player, "n_need_meal")
		return
	end
	if s.location ~= "hand" then
		notify(player, "n_meal_not_in_hand")
		return
	end
	if s.meal.closed then
		notify(player, "n_closed_meal")
		return
	end
	if s.meal.bread == "box" then
		notify(player, "n_box_no_heat")
		return
	end
	if grillOwner[slot] and grillOwner[slot] ~= player then
		notify(player, "n_toast_busy")
		return
	end
	grillOwner[slot] = player
	s.grillSlot = slot
	s.grillStart = os.clock()
	s.location = "grill"
	Net.Sound(player, "toast")
	refreshMealVisual(player)
	push(player)
end

local function cutQuality(d: number): number
	if d > Config.Prep.BurntDoneness then
		return 0.4
	elseif d > 1.6 then
		return 0.75
	elseif d >= 0.7 then
		return 1
	end
	return 0.8
end

-- Carving meat is a skill mechanic of its own (Server/MeatCuttingService): the spit prompt only opens
-- the cutting mode on the client and portions are awarded per validated knife stroke there.

-- used by MeatCuttingService
FoodPreparationService.Spits = spits
FoodPreparationService.CutQuality = cutQuality
function FoodPreparationService.OpenMeal(player: Player): any?
	local s = getState(player)
	if not s.meal or s.meal.closed or s.location == "grill" then
		return nil
	end
	return s.meal
end

-- The meat pan carved portions go into: the one in the hands, or a new one (free hands needed).
-- create = false only checks (and notifies why not).
function FoodPreparationService.CutBowl(player: Player, create: boolean): { any }?
	local s = getState(player)
	if s.bowlAt == "hand" and s.bowl then
		if #s.bowl >= Config.Prep.BowlPortions then
			notify(player, "n_bowl_full")
			return nil
		end
		return s.bowl
	end
	if type(s.bowlAt) == "number" then
		notify(player, "n_bowl_on_board")
		return nil
	end
	if handsBusy(player, s) then
		notify(player, "n_hands_full")
		return nil
	end
	if not create then
		return {}
	end
	s.bowl = {}
	s.bowlAt = "hand"
	refreshBowlVisual(player)
	push(player)
	return s.bowl
end

function FoodPreparationService.HeldBowl(player: Player): { any }?
	local s = getState(player)
	return s.bowlAt == "hand" and s.bowl or nil
end

function FoodPreparationService.AddToBowl(player: Player, meat: string, q: number)
	local s = getState(player)
	if s.bowlAt ~= "hand" or not s.bowl then
		return
	end
	table.insert(s.bowl, { meat = meat, q = q })
	refreshBowlVisual(player)
	push(player)
end

-- an empty pan is put back when carving ends without a portion
function FoodPreparationService.DropEmptyBowl(player: Player)
	local s = getState(player)
	if s.bowlAt == "hand" and s.bowl and #s.bowl == 0 then
		s.bowl = nil
		refreshBowlVisual(player)
		push(player)
	end
end
function FoodPreparationService.RequireOpenMeal(player: Player): any?
	return requireOpenMeal(player)
end
function FoodPreparationService.RefreshMeal(player: Player)
	refreshMealVisual(player)
	push(player)
end

function Actions.spit_heat(player: Player, part: BasePart)
	local meat = part:GetAttribute("Item")
	local spit = spits[meat]
	if not spit then
		return
	end
	spit.heat = spit.heat == "low" and "high" or "low"
	FoodPreparationService.UpdateSpitVisual(meat)
	Net.Sound(nil, "click", part.Position)
	FoodPreparationService.PushSpits()
end

local function addIngredient(player: Player, category: string, id: string, stockId: string): boolean
	local meal = requireOpenMeal(player)
	if not meal then
		return false
	end
	local current = (category == "cheese") and meal.cheese or (meal[category][id] or 0)
	if current >= Config.Prep.MaxIngredientPortions then
		notify(player, "n_too_much")
		return false
	end
	if not useStock(player, stockId) then
		return false
	end
	if category == "cheese" then
		meal.cheese += 1
	else
		meal[category][id] = current + 1
	end
	if category == "veg" and FoodPreparationService.FreshHook then
		meal.fresh = math.min(meal.fresh or 1, FoodPreparationService.FreshHook(id))
	end
	table.insert(meal.steps, category .. ":" .. id)
	Net.Sound(player, category == "sauces" and "sauce" or "add")
	refreshMealVisual(player)
	push(player)
	return true
end

function Actions.veg(player: Player, part: BasePart)
	local id = part:GetAttribute("Item")
	local def = IngredientData.Veg[id]
	if def then
		addIngredient(player, "veg", id, def.stock)
	end
end

function Actions.cheese(player: Player, _part: BasePart)
	addIngredient(player, "cheese", "cheese", "cheese")
end

-- The dispenser: take its bottle / put it back; with the bread in your hand, pump sauce onto it.
function Actions.sauce(player: Player, part: BasePart)
	local s = getState(player)
	local id = part:GetAttribute("Item")
	local def = IngredientData.Sauce[id]
	if not def then
		return
	end
	if s.sauce == id then
		returnSauce(player)
		Net.Sound(player, "click")
		push(player)
		return
	end
	local holder = sauceHolder[id]
	if holder and holder ~= player then
		notify(player, "n_sauce_taken", { name = holder.DisplayName })
		return
	end
	if mealInHand(s) then
		if addIngredient(player, "sauces", id, def.stock) then
			handAct(player, "pump")
		end
		return
	end
	if handsBusy(player, s) then
		notify(player, "n_hands_full")
		return
	end
	s.sauce = id
	setDispenser(id, player)
	refreshSauceVisual(player)
	Net.Sound(player, "add")
	push(player)
end

-- The board: put down / pick up the bread, the meat pan and the tray; the meat goes from the pan onto
-- the bread here, the bread is closed and packed here. One player per board while their things are on it.
function Actions.board(player: Player, part: BasePart, action: any)
	local s = getState(player)
	local i = part:GetAttribute("Board")
	if type(i) ~= "number" then
		return
	end
	local user = boardUser(i)
	if user and user ~= player then
		notify(player, "n_board_used", { name = user.DisplayName })
		return
	end
	-- all of a player's things stand at one board
	local function sameBoard(): boolean
		local b = myBoard(s)
		if b and b ~= i then
			notify(player, "n_other_board")
			return false
		end
		return true
	end
	if action == "place" then
		if not mealInHand(s) then
			notify(player, s.meal and "n_meal_not_in_hand" or "n_need_meal")
			return
		end
		if not sameBoard() then
			return
		end
		s.location = "board"
		s.board = i
		Net.Sound(player, "add")
	elseif action == "pickup" then
		if not mealOnBoard(s, i) then
			return
		end
		if handsBusy(player, s) then
			notify(player, "n_hands_full")
			return
		end
		s.location = "hand"
		s.board = nil
		Net.Sound(player, "add")
	elseif action == "bowl_down" then
		if s.bowlAt ~= "hand" or not sameBoard() then
			return
		end
		s.bowlAt = i
		Net.Sound(player, "add")
		refreshBowlVisual(player)
	elseif action == "bowl_up" then
		if s.bowlAt ~= i then
			return
		end
		if handsBusy(player, s) then
			notify(player, "n_hands_full")
			return
		end
		s.bowlAt = "hand"
		Net.Sound(player, "add")
		refreshBowlVisual(player)
	elseif action == "meat_on" then
		-- from the pan (in the hands or on this board) onto the bread on the board
		if not mealOnBoard(s, i) or s.meal.closed then
			return
		end
		if not s.bowl or #s.bowl == 0 or (s.bowlAt ~= "hand" and s.bowlAt ~= i) then
			notify(player, "n_no_meat_bowl")
			return
		end
		local room = Config.Prep.MaxMeatPortions - OrderLogic.MeatTotal(s.meal)
		if room <= 0 then
			notify(player, "n_too_much")
			return
		end
		for _ = 1, room do
			local it = table.remove(s.bowl, 1)
			if not it then
				break
			end
			s.meal.meat[it.meat] = (s.meal.meat[it.meat] or 0) + 1
			table.insert(s.meal.meatQuality, it.q)
			table.insert(s.meal.steps, "meat:" .. it.meat)
		end
		if #s.bowl == 0 then
			s.bowl = nil -- the empty pan goes to the dishes
		end
		Net.Sound(player, "add")
		refreshBowlVisual(player)
	elseif action == "sauce_on" then
		-- squeeze the bottle in your hand onto the bread on the board
		if not s.sauce or not mealOnBoard(s, i) or s.meal.closed then
			return
		end
		local id = s.sauce
		if addIngredient(player, "sauces", id, IngredientData.Sauce[id].stock) then
			handAct(player, "sauce")
			refreshSauceVisual(player, true)
			task.delay(1.1, function()
				if states[player] == s and s.sauce == id then
					refreshSauceVisual(player)
				end
			end)
		end
		return
	elseif action == "close" then
		if not mealOnBoard(s, i) or s.meal.closed then
			return
		end
		-- a classic bread needs its top half (bread station)
		if s.meal.bread == "classic" then
			if not s.lid then
				notify(player, "n_need_lid")
				return
			end
			s.lid = nil
			refreshLidVisual(player)
		end
		s.meal.closed = true
		table.insert(s.meal.steps, "close")
		Net.Sound(player, "wrap")
	elseif action == "pack_takeaway" or action == "pack_plate" then
		if not mealOnBoard(s, i) then
			return
		end
		if not s.meal.closed then
			notify(player, "n_not_closed")
			return
		end
		if not sameBoard() then
			return
		end
		if #s.tray >= trayCapacity() then
			notify(player, "n_tray_full")
			return
		end
		s.meal.pack = action == "pack_takeaway" and "takeaway" or "plate"
		table.insert(s.tray, { kind = "meal", meal = s.meal })
		s.meal = nil
		releasePlace(player)
		-- a new tray is set out at the front of this board
		s.trayAt = s.trayAt or i
		Net.Sound(player, "wrap")
		Net.Notify(player, "n_meal_to_tray", nil, "success")
		refreshTrayVisual(player)
	elseif action == "tray_down" then
		if s.trayAt ~= "hand" or not sameBoard() then
			return
		end
		s.trayAt = i
		Net.Sound(player, "add")
		refreshTrayVisual(player)
	elseif action == "tray_up" then
		if s.trayAt ~= i then
			return
		end
		if handsBusy(player, s) then
			notify(player, "n_hands_full")
			return
		end
		s.trayAt = "hand"
		Net.Sound(player, "add")
		refreshTrayVisual(player)
	else
		return
	end
	refreshMealVisual(player)
	push(player)
end

function Actions.drink(player: Player, part: BasePart)
	local s = getState(player)
	local id = part:GetAttribute("Item")
	local def = IngredientData.Drinks[id]
	if not def then
		return
	end
	-- the drink goes on the tray in your hands (a new one if you have none)
	if handsBusyNoTray(player, s) then
		notify(player, "n_hands_full")
		return
	end
	if type(s.trayAt) == "number" then
		notify(player, "n_tray_not_in_hand")
		return
	end
	if #s.tray >= trayCapacity() then
		notify(player, "n_tray_full")
		return
	end
	if not useStock(player, def.stock) then
		return
	end
	table.insert(s.tray, { kind = "drink", id = id })
	s.trayAt = "hand"
	Net.Notify(player, "n_drink_taken", { item = def.name }, "info")
	Net.Sound(player, "add")
	refreshTrayVisual(player)
	push(player)
end

function Actions.trash(player: Player, _part: BasePart)
	local s = getState(player)
	-- only what you carry to the bin
	if mealInHand(s) then
		FoodPreparationService.ClearMeal(player)
		Net.Notify(player, "n_discarded", nil, "info")
	elseif s.bowlAt == "hand" then
		s.bowl = nil
		refreshBowlVisual(player)
		Net.Notify(player, "n_discarded", nil, "info")
	elseif s.lid then
		s.lid = nil
		refreshLidVisual(player)
	elseif s.sauce then
		notify(player, "n_sauce_back")
		return
	elseif s.trayAt == "hand" and #s.tray > 0 then
		table.remove(s.tray, #s.tray)
		refreshTrayVisual(player)
		Net.Notify(player, "n_discarded", nil, "info")
	elseif s.meal or s.bowl or #s.tray > 0 then
		notify(player, "n_trash_hold")
		return
	else
		return
	end
	Net.Sound(player, "wrap")
	push(player)
end

-- handled by other services (set from Main)
FoodPreparationService.ExternalActions = {} :: { [string]: (Player, BasePart, any) -> () }
FoodPreparationService.FreshHook = nil :: ((string) -> number)?

local function onInteract(player: Player, part: any, action: any)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	if not CollectionService:HasTag(part, "Station") then
		return
	end
	local r = restaurant()
	if not r or not part:IsDescendantOf(r) then
		return
	end
	local kind = part:GetAttribute("Station")
	-- distance validation: prompt distance plus generous slack for latency and part size
	local maxDist = Config.Prep.PromptDistance + 7 + part.Size.Magnitude / 2
	if not Net.Near(player, part.Position, maxDist) then
		return
	end
	local s = getState(player)
	if os.clock() - s.lastAction < Config.Prep.ActionCooldown then
		return
	end
	s.lastAction = os.clock()
	if FoodPreparationService.InteractHook and FoodPreparationService.InteractHook(player, part, kind) then
		return
	end
	local fn = Actions[kind] or FoodPreparationService.ExternalActions[kind]
	if fn then
		local before = FoodPreparationService.BeforeAction and FoodPreparationService.BeforeAction(player, kind)
		fn(player, part, action)
		if before and FoodPreparationService.AfterAction then
			FoodPreparationService.AfterAction(player, part, kind, before)
		end
	end
end

---------------------------------------------------------------------------
-- Spits & grill simulation
---------------------------------------------------------------------------
local RAW = { chicken = Color3.fromRGB(236, 196, 160), veal = Color3.fromRGB(196, 110, 100) }
local COOKED = { chicken = Color3.fromRGB(205, 140, 70), veal = Color3.fromRGB(130, 72, 40) }
local BURNT = Color3.fromRGB(50, 30, 18)
-- the textured meat mesh (WorldBuilder.ApplySpitModel) is already roasted brown: doneness tints it
local RAW_TINT = Color3.fromRGB(255, 196, 186)
local BURNT_TINT = Color3.fromRGB(78, 62, 54)

function FoodPreparationService.UpdateSpitVisual(meat: string)
	local spit = spits[meat]
	local r = restaurant()
	local kitchen = r and r:FindFirstChild("Kitchen")
	local model = kitchen and kitchen:FindFirstChild("Spit_" .. meat)
	if not model then
		return
	end
	local d = spit.doneness
	local color
	if d <= 1 then
		color = RAW[meat]:Lerp(COOKED[meat], math.clamp(d, 0, 1))
	else
		color = COOKED[meat]:Lerp(BURNT, math.clamp((d - 1) / (Config.Prep.HighHeatCap - 1), 0, 1))
	end
	local stockFrac = math.clamp(RestaurantService.GetStock(IngredientData.Meat[meat].stock) / Config.Stock.MeatCapacity, 0, 1)
	local scale = 0.45 + 0.55 * stockFrac
	local meatModel = model:FindFirstChild("Meat")
	if meatModel then
		local tint = d <= 1 and RAW_TINT:Lerp(Color3.new(1, 1, 1), math.clamp(d, 0, 1))
			or Color3.new(1, 1, 1):Lerp(BURNT_TINT, math.clamp((d - 1) / (Config.Prep.HighHeatCap - 1), 0, 1))
		for _, layer in ipairs(meatModel:GetChildren()) do
			local baseSize = layer:GetAttribute("BaseSize")
			if layer:IsA("BasePart") and typeof(baseSize) == "Vector3" then
				local sa = layer:FindFirstChildOfClass("SurfaceAppearance")
				if sa then
					local c0 = sa.Color
					if math.abs(c0.R - tint.R) + math.abs(c0.G - tint.G) + math.abs(c0.B - tint.B) > 0.02 then
						sa.Color = tint
					end
				end
				local size = Vector3.new(math.max(0.5, baseSize.X * scale), baseSize.Y, math.max(0.5, baseSize.Z * scale))
				if (layer.Size - size).Magnitude > 0.02 then
					layer.Size = size
				end
			elseif layer:IsA("BasePart") then
				-- only write when it visibly changed (every write is replicated to all clients)
				local c0 = layer.Color
				if math.abs(c0.R - color.R) + math.abs(c0.G - color.G) + math.abs(c0.B - color.B) > 0.02 then
					layer.Color = color
				end
				local base = layer:GetAttribute("BaseDiameter") or 2
				local dia = math.max(0.35, base * scale)
				if math.abs(layer.Size.Y - dia) > 0.02 then
					layer.Size = Vector3.new(layer.Size.X, dia, dia)
				end
			end
		end
	end
	local burner = model:FindFirstChild("Burner") :: BasePart?
	if burner then
		burner.Color = spit.heat == "high" and Color3.fromRGB(255, 80, 20) or Color3.fromRGB(255, 150, 60)
		local glow = burner:FindFirstChild("Glow") :: PointLight?
		if glow then
			glow.Brightness = spit.heat == "high" and 3 or 1.2
		end
	end
	local knob = model:FindFirstChild("HeatKnob") :: BasePart?
	if knob then
		knob.Color = spit.heat == "high" and Color3.fromRGB(255, 60, 30) or Color3.fromRGB(60, 140, 220)
	end
	local rounded = math.floor(d * 20 + 0.5) / 20
	if model:GetAttribute("Doneness") ~= rounded then
		model:SetAttribute("Doneness", rounded)
	end
	if model:GetAttribute("Heat") ~= spit.heat then
		model:SetAttribute("Heat", spit.heat)
	end
end

function FoodPreparationService.PushSpits()
	for meat in pairs(spits) do
		FoodPreparationService.UpdateSpitVisual(meat)
	end
end

local function updateGrillLamps()
	local r = restaurant()
	local kitchen = r and r:FindFirstChild("Kitchen")
	if not kitchen then
		return
	end
	local rate = RestaurantService.UpgradeValue("toaster")
	for slot = 1, 2 do
		local lamp = kitchen:FindFirstChild("GrillLamp" .. slot, true) :: BasePart?
		local lid = kitchen:FindFirstChild("GrillLid" .. slot, true) :: BasePart?
		local p = grillOwner[slot]
		local s = p and states[p]
		local color = Color3.fromRGB(40, 40, 40)
		if s and s.grillStart then
			local secs = (os.clock() - s.grillStart) * rate
			if secs >= Config.Prep.ToastBurnt then
				color = Color3.fromRGB(255, 30, 30)
			elseif secs >= Config.Prep.ToastPerfectMax then
				color = Color3.fromRGB(255, 160, 20)
			elseif secs >= Config.Prep.ToastPerfectMin then
				color = Color3.fromRGB(40, 255, 80)
			else
				color = Color3.fromRGB(255, 220, 60)
			end
		end
		if lamp then
			lamp.Color = color
		end
		if lid then
			lid:SetAttribute("Closed", s ~= nil and s.grillStart ~= nil)
		end
	end
end

local function simulate(dt: number)
	local burner = RestaurantService.UpgradeValue("spit_burner")
	for meat, spit in pairs(spits) do
		local rate, cap
		if spit.heat == "high" then
			rate, cap = Config.Prep.HighHeatRate * burner, Config.Prep.HighHeatCap
		else
			rate, cap = Config.Prep.LowHeatRate * burner, Config.Prep.LowHeatCap
		end
		if spit.doneness < cap then
			spit.doneness = math.min(cap, spit.doneness + rate * dt)
		elseif spit.heat == "low" and spit.doneness > cap then
			-- crust slowly settles when heat is reduced
			spit.doneness = math.max(cap, spit.doneness - 0.02 * dt)
		end
		FoodPreparationService.UpdateSpitVisual(meat)
	end
	updateGrillLamps()
end

---------------------------------------------------------------------------
-- Public helpers
---------------------------------------------------------------------------
function FoodPreparationService.Tray(player: Player)
	return getState(player).tray
end

function FoodPreparationService.Init()
	mealFolder = workspace:FindFirstChild("Meals") or Instance.new("Folder")
	mealFolder.Name = "Meals"
	mealFolder.Parent = workspace
	trayFolder = workspace:FindFirstChild("Trays") or Instance.new("Folder")
	trayFolder.Name = "Trays"
	trayFolder.Parent = workspace

	Net.On("Interact", onInteract)

	EconomyService.AddStateProvider(function(player, st)
		local s = getState(player)
		st.meal = s.meal
		st.board = s.board
		st.location = s.location
		st.grillSlot = s.grillSlot
		-- client only needs elapsed toast seconds (server time base differs)
		st.grillElapsed = s.grillStart and (os.clock() - s.grillStart) * RestaurantService.UpgradeValue("toaster") or nil
		st.tray = s.tray
		st.trayAt = s.trayAt
		st.bowl = s.bowl
		st.bowlAt = s.bowlAt
		st.lid = s.lid
		st.sauce = s.sauce
		st.trayCap = trayCapacity()
	end)

	Players.PlayerRemoving:Connect(function(p)
		local s = states[p]
		if s then
			returnSauce(p)
			releasePlace(p)
			if s.model then
				s.model:Destroy()
			end
			if s.trayModel then
				s.trayModel:Destroy()
			end
			if s.bowlModel then
				s.bowlModel:Destroy()
			end
			if s.lidModel then
				s.lidModel:Destroy()
			end
		end
		states[p] = nil
		syncBoards()
	end)
	-- carried things are welded to the character: rebuild them on the new one
	local function onPlayer(p: Player)
		p.CharacterRemoving:Connect(function()
			local s = states[p]
			if s and s.model and s.location == "hand" then
				s.model:Destroy()
				s.model = nil
			end
			if s and s.trayModel and s.trayAt == "hand" then
				s.trayModel:Destroy()
				s.trayModel = nil
			end
			if s and s.bowlModel and s.bowlAt == "hand" then
				s.bowlModel:Destroy()
				s.bowlModel = nil
			end
			if s and s.lidModel then
				s.lidModel:Destroy()
				s.lidModel = nil
			end
			-- a bottle goes back into its dispenser
			returnSauce(p)
			push(p)
		end)
		p.CharacterAdded:Connect(function()
			task.wait(0.5)
			refreshTrayVisual(p)
			refreshMealVisual(p)
			refreshBowlVisual(p)
			refreshLidVisual(p)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end

	task.spawn(function()
		while true do
			local dt = task.wait(0.5)
			simulate(dt)
		end
	end)
	FoodPreparationService.PushSpits()
end

return FoodPreparationService
