-- Realistic meat carving at the rotating spits.
--
-- The spit prompt opens a cutting session (Request "CutStart"). While cutting, every knife stroke the
-- player makes is sent as an intent (RemoteEvent "CutStroke"); the server times the strokes itself:
--   * strokes closer together than the knife allows are rejected (no meat for spam / exploits)
--   * a stroke inside the knife's rhythm window is "perfect", too early is "fast" (less precise),
--     too late is "slow" (fine, but wastes time)
--   * every accepted stroke shaves one slice into the drip tray; `knife.slices` slices make a portion
--   * a portion's quality = rhythm precision × how well the meat is cooked, stock is used per portion
-- The electric cutter strokes automatically while the button is held, much faster.
-- Everyone sees the knife (welded to the right hand), the arm animation (Client/CutAnim) and the
-- falling slices (CutFX event); only the server decides how much meat lands in the bread.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local OrderLogic = require(Shared.OrderLogic)
local Progression = require(Shared.Progression)
local Net = require(script.Parent.Net)
local RestaurantService = require(script.Parent.RestaurantService)
local FoodPreparationService = require(script.Parent.FoodPreparationService)

local MeatCuttingService = {}

type Session = {
	meat: string,
	knife: string,
	spit: Model,
	carve: BasePart,
	last: number?, -- time of the last accepted stroke
	slices: number,
	scores: { number },
	portions: number,
	rejected: number,
	started: number,
}

local sessions: { [Player]: Session } = {}

local function spitModel(meat: string): Model?
	local r = workspace:FindFirstChild("Restaurant")
	for _, m in ipairs(CollectionService:GetTagged("Spit")) do
		if m:IsA("Model") and m:GetAttribute("Meat") == meat and r and m:IsDescendantOf(r) then
			return m
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- knife models (welded to the character's right hand, visible to everyone)
-- hand space: fingers along -Y; with the arm raised forward +Z points down and -Y towards the meat.
-- The blade runs along -X (across the meat), edge facing down (+Z), flat side towards the meat.
---------------------------------------------------------------------------
local function knifePart(model: Model, hand: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CFrame = hand.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = hand
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = model
	return p
end

local function attachKnife(char: Model, knifeId: string)
	local hand = char:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return
	end
	local old = char:FindFirstChild("CutKnife")
	if old then
		old:Destroy()
	end
	local k = Progression.Knives[knifeId] or Progression.Knives.old
	local m = Instance.new("Model")
	m.Name = "CutKnife"
	m:SetAttribute("Knife", knifeId)
	local grip = CFrame.new(0, -0.18, 0)
	if knifeId == "electric" then
		-- motor housing in the fist, round blade on the left, half guard over the blade
		knifePart(m, hand, "Housing", Vector3.new(0.9, 0.34, 0.34), grip * CFrame.new(-0.05, 0, 0), k.handle, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		knifePart(m, hand, "Trigger", Vector3.new(0.18, 0.08, 0.1), grip * CFrame.new(0.05, 0.02, 0.19), Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic)
		knifePart(m, hand, "Cable", Vector3.new(0.5, 0.08, 0.08), grip * CFrame.new(0.65, 0, 0), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		knifePart(m, hand, "Arm", Vector3.new(0.5, 0.12, 0.16), grip * CFrame.new(-0.7, 0, 0.05), Color3.fromRGB(190, 192, 196), Enum.Material.Metal)
		local disc = knifePart(m, hand, "Disc", Vector3.new(0.035, 0.95, 0.95), grip * CFrame.new(-1.05, -0.12, 0.1) * CFrame.Angles(0, 0, math.rad(90)), k.color, Enum.Material.Metal, Enum.PartType.Cylinder)
		disc.Reflectance = 0.25
		disc:SetAttribute("Spin", true)
		knifePart(m, hand, "Guard", Vector3.new(0.6, 0.06, 0.32), grip * CFrame.new(-1.05, -0.06, -0.3), Color3.fromRGB(200, 40, 30), Enum.Material.SmoothPlastic)
	else
		local blade = k.blade
		knifePart(m, hand, "Handle", Vector3.new(0.62, 0.17, 0.24), grip * CFrame.new(0.05, 0, 0), k.handle, knifeId == "old" and Enum.Material.Wood or Enum.Material.SmoothPlastic)
		for i, x in ipairs({ -0.12, 0.2 }) do
			knifePart(m, hand, "Rivet" .. i, Vector3.new(0.05, 0.18, 0.05), grip * CFrame.new(x, 0, 0), Color3.fromRGB(200, 200, 200), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		knifePart(m, hand, "Bolster", Vector3.new(0.07, 0.2, 0.3), grip * CFrame.new(-0.28, 0, 0.02), Color3.fromRGB(170, 172, 176), Enum.Material.Metal)
		-- blade scaled to the chunky avatar hands so it reads clearly from a distance
		blade *= 1.35
		local height = knifeId == "pro" and 0.38 or 0.33
		local b = knifePart(m, hand, "Blade", Vector3.new(blade, 0.04, height), grip * CFrame.new(-0.32 - blade / 2, 0, 0.05), k.color, Enum.Material.Metal)
		b.Reflectance = knifeId == "old" and 0.05 or 0.3
		-- pointed tip
		local tip = Instance.new("WedgePart")
		tip.Name = "Tip"
		tip.Size = Vector3.new(0.04, height, 0.26)
		tip.Color = k.color
		tip.Material = Enum.Material.Metal
		tip.Reflectance = b.Reflectance
		tip.CanCollide = false
		tip.CanQuery = false
		tip.CanTouch = false
		tip.Massless = true
		tip.CastShadow = false
		local tipOffset = grip * CFrame.new(-0.32 - blade - 0.13, 0, 0.05) * CFrame.Angles(0, math.rad(-90), math.rad(-90))
		tip.CFrame = hand.CFrame * tipOffset
		local w = Instance.new("Weld")
		w.Part0 = hand
		w.Part1 = tip
		w.C0 = tipOffset
		w.Parent = tip
		tip.Parent = m
		if knifeId == "premium" then
			-- damascus pattern: thin darker bands along the blade
			for i = 1, 4 do
				knifePart(m, hand, "Band" .. i, Vector3.new(blade * 0.9, 0.042, 0.025), grip * CFrame.new(-0.32 - blade / 2, 0, -0.08 + i * 0.055), Color3.fromRGB(80, 84, 92), Enum.Material.Metal)
			end
		end
	end
	m.Parent = char
end

local function removeKnife(char: Model?)
	local k = char and char:FindFirstChild("CutKnife")
	if k then
		k:Destroy()
	end
end

---------------------------------------------------------------------------
-- drip tray pile: the shaved slices collect in the tray until a portion is complete
---------------------------------------------------------------------------
local function setPile(spit: Model, amount: number, perPortion: number)
	local tray = spit:FindFirstChild("DripTray") :: BasePart?
	if not tray then
		return
	end
	local pile = spit:FindFirstChild("TrayPile") :: BasePart?
	if amount <= 0 then
		if pile then
			pile:Destroy()
		end
		return
	end
	if not pile then
		local p = Instance.new("Part")
		p.Name = "TrayPile"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.Sand
		p.Parent = spit
		pile = p
	end
	local pl = pile :: BasePart
	local meat = spit:GetAttribute("Meat")
	local def = IngredientData.Meat[meat]
	pl.Color = def and def.cooked or Color3.fromRGB(200, 140, 70)
	local f = math.clamp(amount / math.max(1, perPortion), 0.15, 1)
	local h = 0.08 + 0.22 * f
	pl.Size = Vector3.new(1.0 + 0.9 * f, h, 0.8 + 0.6 * f)
	-- on the front half of the tray, towards the cook
	pl.CFrame = CFrame.new(tray.Position + Vector3.new(0, tray.Size.Y / 2 + h / 2, tray.Size.Z * 0.22))
end

---------------------------------------------------------------------------
-- sessions
---------------------------------------------------------------------------
local function stop(player: Player, reason: string?)
	local s = sessions[player]
	if not s then
		return
	end
	sessions[player] = nil
	local char = player.Character
	removeKnife(char)
	if char then
		char:SetAttribute("Cutting", nil)
	end
	setPile(s.spit, 0, 1)
	if reason then
		Net.Notify(player, reason, nil, "warn")
	end
	Net.Fire("CutEnd", player, reason)
end
MeatCuttingService.Stop = stop

-- someone is carving at this spit right now (the carver employee waits for them)
function MeatCuttingService.SpitBusy(meat: string): boolean
	for _, s in pairs(sessions) do
		if s.meat == meat then
			return true
		end
	end
	return false
end

function MeatCuttingService.IsCutting(player: Player): boolean
	return sessions[player] ~= nil
end

local function start(player: Player, meat: any)
	if type(meat) ~= "string" or not IngredientData.Meat[meat] then
		return { ok = false }
	end
	local spit = spitModel(meat)
	local carve = spit and spit:FindFirstChild("CarvePoint") :: BasePart?
	local spitState = FoodPreparationService.Spits[meat]
	if not spit or not carve or not spitState then
		return { ok = false }
	end
	if not Net.Near(player, carve.Position, Config.Prep.PromptDistance + 7) then
		return { ok = false }
	end
	if not FoodPreparationService.RequireOpenMeal(player) then
		return { ok = false }
	end
	if spitState.doneness < Config.Prep.MinCutDoneness then
		Net.Notify(player, "n_undercooked", nil, "bad")
		return { ok = false, msg = "n_undercooked" }
	end
	if not RestaurantService.HasStock(IngredientData.Meat[meat].stock, 1) then
		Net.Notify(player, "n_spit_empty", nil, "warn")
		return { ok = false, msg = "n_spit_empty" }
	end
	-- one cook per spit at a time
	for p, s in pairs(sessions) do
		if p ~= player and s.meat == meat then
			Net.Notify(player, "n_spit_busy", { name = p.DisplayName }, "warn")
			return { ok = false, msg = "n_spit_busy" }
		end
	end
	if sessions[player] then
		stop(player)
	end
	local knife = RestaurantService.KnifeId()
	sessions[player] = {
		meat = meat,
		knife = knife,
		spit = spit,
		carve = carve,
		last = nil,
		slices = 0,
		scores = {},
		portions = 0,
		rejected = 0,
		started = os.clock(),
	}
	local char = player.Character
	if char then
		attachKnife(char, knife)
		char:SetAttribute("Cutting", meat)
		char:SetAttribute("CutKnife", knife)
	end
	Net.Sound(nil, "knife_draw", carve.Position)
	local k = Progression.Knives[knife]
	return { ok = true, knife = knife, interval = k.interval, window = k.window, slices = k.slices, auto = k.auto == true }
end

local function stroke(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	local now = os.clock()
	local k = Progression.Knives[s.knife]
	-- strokes faster than the knife physically allows earn nothing
	local minGap = k.auto and k.interval * 0.7 or k.interval * 0.45
	if s.last and now - s.last < minGap then
		s.rejected += 1
		return
	end
	if not s.spit.Parent or not Net.Near(player, s.carve.Position, Config.Prep.PromptDistance + 8) then
		stop(player)
		return
	end
	local meal = FoodPreparationService.OpenMeal(player)
	if not meal then
		stop(player)
		return
	end
	local spitState = FoodPreparationService.Spits[s.meat]
	if spitState.doneness < Config.Prep.MinCutDoneness then
		stop(player, "n_undercooked")
		return
	end
	if OrderLogic.MeatTotal(meal) >= Config.Prep.MaxMeatPortions then
		stop(player, "n_too_much")
		return
	end
	-- rhythm rating
	local rating, score
	if k.auto then
		rating, score = "electric", 0.94
	elseif not s.last or now - s.last > k.interval * 3 then
		rating, score = "start", 0.9 -- first stroke (or after a pause)
	else
		local dt = now - s.last
		if math.abs(dt - k.interval) <= k.window then
			rating, score = "perfect", 1
		elseif dt < k.interval then
			-- hasty: the closer to the minimum gap, the more ragged the slice
			local f = math.clamp((dt - minGap) / math.max(0.01, k.interval - k.window - minGap), 0, 1)
			rating, score = "fast", 0.5 + 0.3 * f
		else
			rating, score = "slow", 0.88
		end
	end
	s.last = now
	s.slices += 1
	table.insert(s.scores, score)
	Net.FireAll("CutFX", player, s.meat, rating, s.slices, k.slices)
	setPile(s.spit, s.slices, k.slices)

	if s.slices >= k.slices then
		-- a full portion: take it from the stock and put it into the bread
		if not RestaurantService.UseStock(IngredientData.Meat[s.meat].stock, 1) then
			stop(player, "n_spit_empty")
			return
		end
		local sum = 0
		for _, v in ipairs(s.scores) do
			sum += v
		end
		local precision = sum / #s.scores
		local cooked = FoodPreparationService.CutQuality(spitState.doneness)
		local q = math.clamp(precision * cooked, 0, 1)
		meal.meat[s.meat] = (meal.meat[s.meat] or 0) + 1
		table.insert(meal.meatQuality, q)
		table.insert(meal.steps, "meat:" .. s.meat)
		spitState.doneness = math.max(0, spitState.doneness - Config.Prep.CutCost)
		FoodPreparationService.UpdateSpitVisual(s.meat)
		s.slices = 0
		s.scores = {}
		s.portions += 1
		setPile(s.spit, 0, 1)
		if cooked < 0.5 then
			Net.Notify(player, "n_burnt_meat", nil, "bad")
		end
		Net.Fire("CutResult", player, { quality = q, precision = precision, cooked = cooked, portions = OrderLogic.MeatTotal(meal) })
		Net.Sound(player, "add")
		RestaurantService.Record("portions", 1)
		FoodPreparationService.RefreshMeal(player)
		if OrderLogic.MeatTotal(meal) >= Config.Prep.MaxMeatPortions then
			stop(player)
		end
	end
end

function MeatCuttingService.Init()
	Net.OnRequest("CutStart", start)
	Net.OnRequest("CutStop", function(player)
		stop(player)
		return { ok = true }
	end)
	Net.On("CutStroke", stroke)
	Players.PlayerRemoving:Connect(function(p)
		local s = sessions[p]
		if s then
			setPile(s.spit, 0, 1)
		end
		sessions[p] = nil
	end)
	-- safety: end idle / invalid sessions (died, walked off, meal gone)
	task.spawn(function()
		while true do
			task.wait(1)
			for p, s in pairs(sessions) do
				local char = p.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local idle = os.clock() - (s.last or s.started)
				if not hum or hum.Health <= 0 or idle > 45 or not FoodPreparationService.OpenMeal(p) or not Net.Near(p, s.carve.Position, Config.Prep.PromptDistance + 9) then
					stop(p)
				end
			end
		end
	end)
end

return MeatCuttingService
