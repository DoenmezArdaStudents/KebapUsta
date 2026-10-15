-- Running the business: restaurant expansion stages (with a construction transition), staff
-- contracts (hire / train / fire / wages), price policy, cleanliness, ingredient freshness,
-- reviews, regulars, special customers and delivery orders. Everything is server-authoritative;
-- the employees' behaviour lives in Server/EmployeeService.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Business = require(Shared.Business)
local OrderLogic = require(Shared.OrderLogic)
local Config = require(Shared.Config)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RestaurantService = require(script.Parent.RestaurantService)
local FoodPreparationService = require(script.Parent.FoodPreparationService)
local OrderService = require(script.Parent.OrderService)
local CustomerService = require(script.Parent.CustomerService)
local GameLoopService = require(script.Parent.GameLoopService)
local ExpansionBuilder = require(script.Parent.ExpansionBuilder)

local BusinessService = {}
local rng = Random.new()

local staffChanged = Instance.new("BindableEvent")
BusinessService.StaffChanged = staffChanged.Event
BusinessService.StatusProvider = nil :: (() -> { [string]: string })?

local building: number? = nil -- stage under construction
local dirt: { BasePart } = {}
local fresh: { [string]: number } = {}
local deliveries: { [number]: any } = {}
local nextDeliveryId = 900000
local nextDelivery = 0
local criticDay = 0
local lastDirtyWarn = 0

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------
local function owner(): Player?
	return RestaurantService.GetOwner()
end

local function biz(): any?
	local o = owner()
	local d = o and DataService.Get(o)
	if not d then
		return nil
	end
	local b = d.biz
	if type(b) ~= "table" then
		b = {}
		d.biz = b
	end
	b.stage = math.clamp(math.floor(tonumber(b.stage) or 1), 1, #Business.Stages)
	if type(b.staff) ~= "table" then
		b.staff = {}
	end
	for role, e in pairs(b.staff) do
		if not Business.Roles[role] or type(e) ~= "table" then
			b.staff[role] = nil
		else
			e.skill = math.clamp(math.floor(tonumber(e.skill) or 1), 1, Business.MaxSkill)
			e.speed = math.clamp(tonumber(e.speed) or 1, 0.7, 1.3)
			e.rel = math.clamp(tonumber(e.rel) or 0.85, 0.5, 1)
			e.salary = math.clamp(tonumber(e.salary) or Business.Roles[role].salary, 0, 1000)
			e.name = type(e.name) == "string" and e.name or "Ali"
		end
	end
	if type(b.reviews) ~= "table" then
		b.reviews = {}
	end
	if type(b.regulars) ~= "table" then
		b.regulars = {}
	end
	if not Business.Prices[b.price] then
		b.price = "normal"
	end
	if type(b.theme) ~= "string" then
		b.theme = "classic"
	end
	if type(b.themes) ~= "table" then
		b.themes = { classic = true }
	end
	if type(b.branches) ~= "table" then
		b.branches = {}
	end
	for id, lvl in pairs(b.branches) do
		if type(lvl) ~= "number" then
			b.branches[id] = nil
		else
			b.branches[id] = math.clamp(math.floor(lvl), 1, Business.BranchMaxLevel)
		end
	end
	return b
end

local function dirty()
	local o = owner()
	if o then
		DataService.MarkDirty(o)
	end
end

function BusinessService.Stage(): number
	local b = biz()
	return b and b.stage or 1
end

function BusinessService.StageDef()
	return Business.Stages[BusinessService.Stage()]
end

function BusinessService.Staff(): { [string]: any }
	local b = biz()
	return b and b.staff or {}
end

BusinessService.WastePenaltyHook = nil :: (() -> number)? -- waste lying around, full bins (Server/WasteService)
BusinessService.CleanHook = nil :: ((BasePart) -> ())?

function BusinessService.Cleanliness(): number
	local waste = BusinessService.WastePenaltyHook and BusinessService.WastePenaltyHook() or 0
	return math.clamp(1 - #dirt * 0.075 - waste, 0, 1)
end

function BusinessService.Dirt(): { BasePart }
	return dirt
end

function BusinessService.Fresh(): { [string]: number }
	return fresh
end

local function priceDef()
	local b = biz()
	return Business.Prices[b and b.price or "normal"]
end

---------------------------------------------------------------------------
-- reviews
---------------------------------------------------------------------------
local GOOD = {
	wait = { "Super schnell bedient!", "Keine Wartezeit, top Service." },
	acc = { "Genau so, wie ich es bestellt habe.", "Bestellung war perfekt." },
	quality = { "Das Fleisch war ein Traum – saftig und knusprig.", "Bester Döner der Stadt!" },
	clean = { "Blitzsauberer Laden.", "Alles sauber und gepflegt." },
	price = { "Faire Preise für richtig gutes Essen.", "Preis-Leistung stimmt." },
}
local BAD = {
	wait = { "Viel zu lange gewartet.", "Die Wartezeit war eine Zumutung." },
	acc = { "Falsche Zutaten bekommen.", "Meine Bestellung war komplett falsch." },
	quality = { "Fleisch war verbrannt oder roh.", "Geschmacklich leider enttäuschend." },
	clean = { "Überall Dreck auf dem Boden und den Tischen.", "Der Laden war schmutzig – eklig." },
	price = { "Für den Preis hätte ich mehr erwartet.", "Ganz schön teuer hier." },
	fresh = { "Der Salat war welk und matschig.", "Gemüse war alles andere als frisch." },
}

local function pick(t: { string }): string
	return t[rng:NextInteger(1, #t)]
end

local function addReview(name: string, stars: number, text: string)
	local b = biz()
	if not b then
		return
	end
	table.insert(b.reviews, 1, { n = name, s = stars, t = text, d = RestaurantService.GetDay() })
	while #b.reviews > 20 do
		table.remove(b.reviews)
	end
	dirty()
	RestaurantService.PushShop()
end

local function reviewFor(c, stars: number, result, mealFresh: number)
	local clean = BusinessService.Cleanliness()
	local price = priceDef()
	local scores = {
		wait = result.patience or 1,
		acc = result.accuracy or 1,
		quality = result.quality or 1,
		clean = clean,
		price = 1 - (price.mul - 0.85) * 1.2,
		fresh = mealFresh,
	}
	local worst, worstV = "wait", 2
	local best, bestV = "quality", -1
	for k, v in pairs(scores) do
		if v < worstV then
			worst, worstV = k, v
		end
		if GOOD[k] and v > bestV then
			best, bestV = k, v
		end
	end
	local text
	if stars >= 4 then
		text = pick(GOOD[best])
		if worstV < 0.55 and BAD[worst] then
			text ..= " Nur: " .. pick(BAD[worst])
		end
	elseif stars <= 2 then
		text = pick(BAD[worst] or BAD.wait)
	else
		text = (GOOD[best] and pick(GOOD[best]) or "Ganz okay.") .. " Aber: " .. pick(BAD[worst] or BAD.wait)
	end
	addReview(c.name, stars, text)
end

function BusinessService.Rating(): (number, number)
	local b = biz()
	if not b or #b.reviews == 0 then
		return 0, 0
	end
	local sum = 0
	for _, r in ipairs(b.reviews) do
		sum += r.s
	end
	return sum / #b.reviews, #b.reviews
end

---------------------------------------------------------------------------
-- cleanliness
---------------------------------------------------------------------------
local function dirtFolder(): Instance?
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return nil
	end
	local f = r:FindFirstChild("Dirt")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Dirt"
		f.Parent = r
	end
	return f
end

local DIRT = {
	crumbs = { Color3.fromRGB(196, 150, 90), "🍞 Krümel", 1.6 },
	spill = { Color3.fromRGB(150, 40, 25), "🥫 Soßenfleck", 2.4 },
	trash = { Color3.fromRGB(235, 235, 230), "🧻 Müll", 1.2 },
	mud = { Color3.fromRGB(90, 70, 50), "👣 Schmutz", 2.8 },
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

function BusinessService.AddDirt(pos: Vector3, kind: string)
	local f = dirtFolder()
	if not f or #dirt >= 14 then
		return
	end
	local def = DIRT[kind] or DIRT.spill
	local exclude = { f }
	for _, n in ipairs({ "Customers", "Pedestrians", "Staff" }) do
		local x = workspace:FindFirstChild(n)
		if x then
			table.insert(exclude, x)
		end
	end
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 2.5, 0), Vector3.new(0, -8, 0), rayParams)
	if not hit then
		return
	end
	local d = def[3] * rng:NextNumber(0.8, 1.2)
	local p = Instance.new("Part")
	p.Name = "Dirt"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.04, d, d * rng:NextNumber(0.7, 1))
	p.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(90))
	p.Color = def[1]
	p.Material = kind == "trash" and Enum.Material.SmoothPlastic or Enum.Material.Sand
	p.Transparency = 0.15
	if kind == "trash" then
		p.Shape = Enum.PartType.Block
		p.Size = Vector3.new(0.5, 0.3, 0.6)
		p.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0.3, rng:NextNumber(0, 6.28), 0.2)
	end
	p:SetAttribute("Station", "dirt")
	p:SetAttribute("DirtKind", kind)
	p:SetAttribute("PromptDe", "Putzen")
	p:SetAttribute("PromptEn", "Clean")
	p:SetAttribute("PromptObj", def[2])
	p:SetAttribute("PromptHold", 0.9)
	p.Parent = f
	CollectionService:AddTag(p, "Station")
	table.insert(dirt, p)
	local clean = BusinessService.Cleanliness()
	if clean < 0.6 and os.clock() - lastDirtyWarn > 60 then
		lastDirtyWarn = os.clock()
		Net.NotifyAll("n_dirty", nil, "warn")
	end
	RestaurantService.PushShop()
end

function BusinessService.Clean(part: BasePart): boolean
	local i = table.find(dirt, part)
	if not i then
		return false
	end
	table.remove(dirt, i)
	if BusinessService.CleanHook then
		pcall(BusinessService.CleanHook, part)
	end
	Net.Sound(nil, "wrap", part.Position)
	part:Destroy()
	RestaurantService.PushShop()
	return true
end

local function clearDirt()
	for _, p in ipairs(dirt) do
		p:Destroy()
	end
	table.clear(dirt)
end

---------------------------------------------------------------------------
-- freshness of the vegetable bins
---------------------------------------------------------------------------
local freshPoints: { [string]: BasePart } = {}

local fillParts: { [string]: BasePart } = {}

local function updateFreshVisual(id: string)
	local f = fresh[id] or 1
	local p = freshPoints[id]
	if p then
		p:SetAttribute("PromptObj", string.format("🥬 %d %%", math.floor(f * 100 + 0.5)))
		p:SetAttribute("PromptOn", f < 0.85)
	end
	local fill = fillParts[id]
	if fill then
		local base = fill:GetAttribute("FreshColor")
		if typeof(base) ~= "Color3" then
			base = fill.Color
			fill:SetAttribute("FreshColor", base)
		end
		fill.Color = (base :: Color3):Lerp(Color3.fromRGB(110, 90, 50), (1 - f) * 0.85)
		-- the modelled vegetable pieces in the bin wilt too
		local tint = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(176, 150, 86), (1 - f) * 0.9)
		for _, c in ipairs(fill:GetChildren()) do
			local sa = c:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa.Color = tint
			end
		end
	end
end

local function setupFreshPoints()
	local r = workspace:FindFirstChild("Restaurant")
	if not r then
		return
	end
	local folder = r:FindFirstChild("FreshPoints") or Instance.new("Folder")
	folder.Name = "FreshPoints"
	folder.Parent = r
	for _, st in ipairs(CollectionService:GetTagged("Station")) do
		if st:GetAttribute("Station") == "veg" and st:IsDescendantOf(r) then
			local id = st:GetAttribute("Item")
			if id and not freshPoints[id] then
				fresh[id] = fresh[id] or 1
				local p = Instance.new("Part")
				p.Name = "Fresh_" .. id
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Transparency = 1
				p.Size = Vector3.new(1, 0.4, 1)
				p.CFrame = (st :: BasePart).CFrame * CFrame.new(0, 0.6, 0)
				p:SetAttribute("Station", "fresh")
				p:SetAttribute("Item", id)
				p:SetAttribute("PromptKey", "R")
				p:SetAttribute("PromptDe", "Frisch schneiden")
				p:SetAttribute("PromptEn", "Chop fresh")
				p:SetAttribute("PromptHold", 1.4)
				p.Parent = folder
				CollectionService:AddTag(p, "Station")
				freshPoints[id] = p
				-- the coloured filling sits right on top of the bin (it may live in another folder)
				for _, c in ipairs(r:GetDescendants()) do
					if c.Name == "Fill" and c:IsA("BasePart") and (c.Position - (st :: BasePart).Position).Magnitude < 1 then
						fillParts[id] = c
					end
				end
				updateFreshVisual(id)
			end
		end
	end
end

function BusinessService.Refresh(id: string)
	if fresh[id] then
		fresh[id] = 1
		updateFreshVisual(id)
		RestaurantService.PushShop()
	end
end

---------------------------------------------------------------------------
-- expansion stages
---------------------------------------------------------------------------
local function applyWorld()
	ExpansionBuilder.Clear()
	local stage = BusinessService.Stage()
	for s = 2, stage do
		ExpansionBuilder.Build(s)
	end
	RestaurantService.PushShop()
end

local function stripes(parent: Instance, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / 2))
	for i = 0, n - 1 do
		local p0 = a:Lerp(b, i / n)
		local p1 = a:Lerp(b, (i + 1) / n)
		local mid = (p0 + p1) / 2
		local p = Instance.new("Part")
		p.Name = "Fence"
		p.Anchored = true
		p.Size = Vector3.new((p1 - p0).Magnitude, 2.2, 0.15)
		p.CFrame = CFrame.lookAt(mid + Vector3.new(0, 1.4, 0), mid + Vector3.new(0, 1.4, 0) + (p1 - p0).Unit:Cross(Vector3.yAxis))
		p.Color = i % 2 == 0 and Color3.fromRGB(240, 120, 30) or Color3.fromRGB(245, 245, 240)
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.Parent = parent
	end
end

local function construct(stage: number)
	building = stage
	RestaurantService.PushShop()
	local f = ExpansionBuilder.Folder()
	local site = ExpansionBuilder.Sites[stage]
	if not f or not site then
		building = nil
		return
	end
	local cs = Instance.new("Model")
	cs.Name = "ConstructionSite"
	local c, s = site.center, site.size
	local corners = {
		c + Vector3.new(-s.X / 2, 0, -s.Z / 2),
		c + Vector3.new(s.X / 2, 0, -s.Z / 2),
		c + Vector3.new(s.X / 2, 0, s.Z / 2),
		c + Vector3.new(-s.X / 2, 0, s.Z / 2),
	}
	for i = 1, 4 do
		stripes(cs, corners[i], corners[i % 4 + 1])
	end
	local dust = Instance.new("Part")
	dust.Name = "Dust"
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.Transparency = 1
	dust.Size = Vector3.new(s.X, 1, s.Z)
	dust.CFrame = CFrame.new(c + Vector3.new(0, 1, 0))
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 25
	pe.Lifetime = NumberRange.new(1.5, 3)
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 185, 160))
	pe.Parent = dust
	dust.Parent = cs
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 60)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(240, 170, 30)
	t.TextColor3 = Color3.fromRGB(30, 30, 30)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = t
	bb.Parent = dust
	cs.Parent = f
	local def = Business.Stages[stage]
	Net.NotifyAll("n_stage_building", { name = def.name }, "info")
	local BUILD = 12
	for i = BUILD, 1, -1 do
		t.Text = string.format("🚧 %s · %d s", def.name.de, i)
		Net.Sound(nil, i % 2 == 0 and "cut" or "click", c + Vector3.new(0, 2, 0))
		task.wait(1)
	end
	-- the new parts rise into place, bottom to top
	local m = ExpansionBuilder.Build(stage)
	if m then
		local seats = {}
		for _, sp in ipairs(m:GetDescendants()) do
			if CollectionService:HasTag(sp, "SeatPoint") then
				CollectionService:RemoveTag(sp, "SeatPoint")
				table.insert(seats, sp)
			end
		end
		local parts = {}
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				table.insert(parts, { p = p, cf = p.CFrame, tr = p.Transparency })
				p.Transparency = 1
				p.CFrame = p.CFrame + Vector3.new(0, 4, 0)
			end
		end
		table.sort(parts, function(a, b)
			return a.cf.Position.Y < b.cf.Position.Y
		end)
		local per = math.max(1, math.ceil(#parts / 40))
		for i, e in ipairs(parts) do
			TweenService:Create(e.p, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = e.cf, Transparency = e.tr }):Play()
			if i % per == 0 then
				task.wait(0.05)
			end
		end
		task.wait(0.6)
		for _, e in ipairs(parts) do
			e.p.CFrame = e.cf
			e.p.Transparency = e.tr
		end
		for _, sp in ipairs(seats) do
			CollectionService:AddTag(sp, "SeatPoint")
		end
	end
	cs:Destroy()
	building = nil
	Net.FireAll("Installed", "stage" .. stage, c + Vector3.new(0, 3, 0))
	Net.NotifyAll("n_stage_built", { name = def.name }, "success")
	Net.Sound(nil, "levelup")
	RestaurantService.PushShop()
end

local function buyStage(player: Player)
	if not RestaurantService.IsOwner(player) then
		Net.Notify(player, "n_owner_only", nil, "warn")
		return { ok = false }
	end
	local b = biz()
	local d = DataService.Get(player)
	if not b or not d or building then
		return { ok = false }
	end
	local nextDef = Business.Stages[b.stage + 1]
	if not nextDef then
		return { ok = false }
	end
	if d.level < nextDef.level then
		Net.Notify(player, "n_level_req", { level = nextDef.level }, "warn")
		return { ok = false }
	end
	if not EconomyService.Spend(player, nextDef.price) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return { ok = false }
	end
	b.stage = nextDef.id
	EconomyService.AddStat(player, "expansions", 1)
	DataService.MarkDirty(player)
	EconomyService.Push(player)
	task.spawn(construct, nextDef.id)
	return { ok = true }
end

---------------------------------------------------------------------------
-- staff contracts
---------------------------------------------------------------------------
local function ownerCheck(player: Player): boolean
	if not RestaurantService.IsOwner(player) then
		Net.Notify(player, "n_owner_only", nil, "warn")
		return false
	end
	return true
end

local function hire(player: Player, args: any)
	local role = type(args) == "table" and args.role
	local idx = type(args) == "table" and args.idx
	if type(role) ~= "string" or type(idx) ~= "number" or not ownerCheck(player) then
		return { ok = false }
	end
	local def = Business.Roles[role]
	local b = biz()
	local d = DataService.Get(player)
	if not def or not b or not d or b.staff[role] then
		return { ok = false }
	end
	if d.level < def.level then
		Net.Notify(player, "n_level_req", { level = def.level }, "warn")
		return { ok = false }
	end
	local cand = Business.Candidates(role, RestaurantService.GetDay())[math.floor(idx)]
	if not cand then
		return { ok = false }
	end
	if not EconomyService.Spend(player, def.hire) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return { ok = false }
	end
	b.staff[role] = { name = cand.name, skill = cand.skill, speed = cand.speed, rel = cand.rel, salary = cand.salary, seed = cand.seed, day = RestaurantService.GetDay() }
	RestaurantService.DayStats.expenses += def.hire
	EconomyService.AddStat(player, "hired", 1)
	DataService.MarkDirty(player)
	EconomyService.Push(player)
	Net.NotifyAll("n_hired", { name = cand.name, role = def.name }, "success")
	staffChanged:Fire()
	RestaurantService.PushShop()
	return { ok = true }
end

local function fire(player: Player, role: any)
	if type(role) ~= "string" or not ownerCheck(player) then
		return { ok = false }
	end
	local b = biz()
	local e = b and b.staff[role]
	if not e then
		return { ok = false }
	end
	b.staff[role] = nil
	DataService.MarkDirty(player)
	Net.NotifyAll("n_fired", { name = e.name }, "info")
	staffChanged:Fire()
	RestaurantService.PushShop()
	return { ok = true }
end

local function train(player: Player, role: any)
	if type(role) ~= "string" or not ownerCheck(player) then
		return { ok = false }
	end
	local b = biz()
	local e = b and b.staff[role]
	if not e or e.skill >= Business.MaxSkill then
		return { ok = false }
	end
	local cost = Business.TrainCost(e.skill)
	if not EconomyService.Spend(player, cost) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return { ok = false }
	end
	e.skill += 1
	e.salary = math.floor(e.salary * 1.12 + 0.5)
	e.training = os.clock()
	RestaurantService.DayStats.expenses += cost
	DataService.MarkDirty(player)
	EconomyService.Push(player)
	Net.NotifyAll("n_trained", { name = e.name, skill = e.skill }, "success")
	staffChanged:Fire()
	RestaurantService.PushShop()
	return { ok = true }
end

local function setPrice(player: Player, level: any)
	if type(level) ~= "string" or not ownerCheck(player) then
		return { ok = false }
	end
	local def = Business.Prices[level]
	local b = biz()
	if not def or not b then
		return { ok = false }
	end
	if def.stage and b.stage < def.stage then
		Net.Notify(player, "n_price_locked", { name = Business.Stages[def.stage].name }, "warn")
		return { ok = false }
	end
	b.price = level
	DataService.MarkDirty(player)
	Net.NotifyAll("n_price_set", { name = def.name }, "info")
	RestaurantService.PushShop()
	return { ok = true }
end

local function payWages(): number
	local o = owner()
	local b = biz()
	if not o or not b then
		return 0
	end
	local total = 0
	for _, e in pairs(b.staff) do
		total += e.salary
	end
	if total > 0 then
		EconomyService.AddCash(o, -total, false)
		Net.Notify(o, "n_wages", { amount = string.format("%.2f €", total) }, "info")
	end
	-- branches pay out at closing time (counted as today's revenue)
	local income = 0
	for _, br in ipairs(Business.Branches) do
		local lvl = b.branches[br.id]
		if lvl then
			income += Business.BranchIncome(br.income, lvl, RestaurantService.GetReputation())
		end
	end
	if income > 0 then
		EconomyService.AddCash(o, income, true)
		RestaurantService.DayStats.revenue += income
		Net.Notify(o, "n_branch_income", { amount = string.format("%.2f €", income) }, "success")
	end
	return total
end

---------------------------------------------------------------------------
-- shop theme & branches
---------------------------------------------------------------------------
local ACCENT = Business.Themes[1].color

local function applyTheme()
	local b = biz()
	local r = workspace:FindFirstChild("Restaurant")
	if not b or not r then
		return
	end
	local color = ACCENT
	for _, t in ipairs(Business.Themes) do
		if t.id == b.theme then
			color = t.color
		end
	end
	for _, name in ipairs({ "Shell", "Kitchen", "Dining" }) do
		local f = r:FindFirstChild(name)
		if f then
			for _, p in ipairs(f:GetDescendants()) do
				if p:IsA("BasePart") then
					if p:GetAttribute("ThemeAccent") == nil and p.Color == ACCENT then
						p:SetAttribute("ThemeAccent", true)
					end
					if p:GetAttribute("ThemeAccent") then
						p.Color = color
					end
				end
			end
		end
	end
end

local function setTheme(player: Player, id: any)
	if type(id) ~= "string" or not ownerCheck(player) then
		return { ok = false }
	end
	local b = biz()
	local def
	for _, t in ipairs(Business.Themes) do
		if t.id == id then
			def = t
		end
	end
	if not b or not def then
		return { ok = false }
	end
	if def.stage and b.stage < def.stage then
		Net.Notify(player, "n_price_locked", { name = Business.Stages[def.stage].name }, "warn")
		return { ok = false }
	end
	if not b.themes[id] then
		if not EconomyService.Spend(player, def.price) then
			Net.Notify(player, "n_not_enough_cash", nil, "warn")
			return { ok = false }
		end
		b.themes[id] = true
		RestaurantService.DayStats.expenses += def.price
		EconomyService.Push(player)
	end
	b.theme = id
	DataService.MarkDirty(player)
	applyTheme()
	Net.Sound(nil, "levelup")
	Net.NotifyAll("n_theme_set", { name = def.name }, "success")
	RestaurantService.PushShop()
	return { ok = true }
end

local function buyBranch(player: Player, id: any)
	if type(id) ~= "string" or not ownerCheck(player) then
		return { ok = false }
	end
	local b = biz()
	local d = DataService.Get(player)
	local def
	for _, br in ipairs(Business.Branches) do
		if br.id == id then
			def = br
		end
	end
	if not b or not d or not def then
		return { ok = false }
	end
	local lvl = b.branches[id]
	if lvl and lvl >= Business.BranchMaxLevel then
		return { ok = false }
	end
	if not lvl and d.level < def.level then
		Net.Notify(player, "n_level_req", { level = def.level }, "warn")
		return { ok = false }
	end
	local cost = lvl and Business.BranchUpgradeCost(def.price, lvl) or def.price
	if not EconomyService.Spend(player, cost) then
		Net.Notify(player, "n_not_enough_cash", nil, "warn")
		return { ok = false }
	end
	b.branches[id] = (lvl or 0) + 1
	if not lvl then
		EconomyService.AddStat(player, "branches", 1)
	end
	RestaurantService.DayStats.expenses += cost
	DataService.MarkDirty(player)
	EconomyService.Push(player)
	Net.NotifyAll(lvl and "n_branch_up" or "n_branch_new", { name = def.name, level = b.branches[id] }, "success")
	Net.Sound(nil, "levelup")
	RestaurantService.PushShop()
	return { ok = true }
end

---------------------------------------------------------------------------
-- regulars & special customers
---------------------------------------------------------------------------
local CRITICS = { "Frau Kessler", "Herr Brandt", "Frau Yıldız", "Herr Novak" }

local function specialSpawn()
	local b = biz()
	if not b then
		return nil
	end
	local stage = Business.Stages[b.stage]
	local day = RestaurantService.GetDay()
	-- a food critic visits at most once a day from day 3 on
	if day >= 3 and criticDay ~= day and rng:NextNumber() < 0.04 then
		criticDay = day
		local c = CustomerService.Spawn({ critic = true, personality = "picky", name = CRITICS[rng:NextInteger(1, #CRITICS)] })
		if c then
			Net.NotifyAll("n_critic", { name = c.name }, "vip")
		end
		return c
	end
	if stage.vip and rng:NextNumber() < Config.Customers.VIPChance * (stage.vip - 1) then
		return CustomerService.Spawn({ vip = true, personality = "picky" })
	end
	if #b.regulars > 0 and rng:NextNumber() < 0.2 then
		local inside = {}
		for _, c in pairs(CustomerService.All()) do
			inside[c.name] = true
		end
		local r = b.regulars[rng:NextInteger(1, #b.regulars)]
		if not inside[r.name] then
			local c = CustomerService.Spawn({
				name = r.name,
				lookSeed = r.seed,
				personality = r.personality,
				favorite = { menu = r.menu, meat = r.meat },
				regularVisits = r.visits,
			})
			if c then
				Net.NotifyAll("n_regular_back", { name = r.name, n = r.visits + 1 }, "info")
			end
			return c
		end
	end
	return nil
end

local function onCompleted(player: Player, c, stars: number, result, order)
	local b = biz()
	if not b then
		return
	end
	local mealFresh = 1
	-- reviews: critics always write one, other guests sometimes
	if c.critic then
		local d = DataService.Get(owner() :: Player)
		if d then
			local delta = stars >= 4 and 0.25 or (stars <= 2 and -0.25 or 0)
			d.reputation = math.clamp(d.reputation + delta, 1, 5)
		end
		addReview("🖋️ " .. c.name .. " (Stadtanzeiger)", stars, stars >= 4 and "Ein Imbiss, der Maßstäbe setzt. Unbedingt probieren!" or (stars <= 2 and "Enttäuschend. Diesen Laden kann ich nicht empfehlen." or "Solide, aber ohne Glanz."))
		Net.NotifyAll(stars >= 4 and "n_critic_good" or "n_critic_bad", { stars = string.rep("★", stars) }, stars >= 4 and "success" or "bad")
	elseif rng:NextNumber() < (stars <= 2 and 0.8 or 0.45) then
		reviewFor(c, stars, result, mealFresh)
	end
	-- regulars
	if c.regularVisits then
		for _, r in ipairs(b.regulars) do
			if r.name == c.name and r.seed == c.lookSeed then
				r.visits += 1
				if stars <= 2 then
					r.visits = math.max(0, r.visits - 2)
				end
				break
			end
		end
		dirty()
	elseif stars >= 4 and not c.delivery and not c.critic and c.lookSeed and #b.regulars < 12 and rng:NextNumber() < 0.3 then
		local it = order.items[1]
		table.insert(b.regulars, { name = c.name, seed = c.lookSeed, personality = c.personality, menu = it and it.menu, meat = it and it.meat, visits = 1 })
		dirty()
		EconomyService.AddStat(owner() :: Player, "regulars", 1)
		Net.NotifyAll("n_new_regular", { name = c.name }, "success")
	end
	RestaurantService.PushShop()
end

local function modifiers(c): (number, number, number)
	local price = priceDef()
	local clean = BusinessService.Cleanliness()
	local mood = price.mood + (clean - 0.85) * 0.3
	if c.critic then
		mood *= 1.5
	end
	local tipMul = c.regularVisits and (1 + 0.1 * math.min(c.regularVisits, 5)) or 1
	return mood, price.mul, tipMul
end

---------------------------------------------------------------------------
-- delivery orders (stage 3+)
---------------------------------------------------------------------------
local DELIVERY_NAMES = { "Familie Weber", "Büro Schmidt & Co.", "Studi-WG", "Frau Demir", "Herr Fischer", "Praxis Dr. Kaya", "Kita Sonnenschein" }

local function deliveryCount(): number
	local n = 0
	for _ in pairs(deliveries) do
		n += 1
	end
	return n
end

local function newDelivery()
	local o = owner()
	if not o then
		return
	end
	nextDeliveryId += 1
	local name = DELIVERY_NAMES[rng:NextInteger(1, #DELIVERY_NAMES)]
	local patience = 200
	local c = {
		id = nextDeliveryId,
		name = "🛵 " .. name,
		personality = "friendly",
		vip = false,
		groupSize = 1,
		patience = patience,
		maxPatience = patience,
		alive = true,
		delivery = true,
	}
	local order = OrderLogic.GenerateOrder(rng, { available = RestaurantService.Available(), count = rng:NextNumber() < 0.3 and 2 or 1, takeaway = true })
	for _, it in ipairs(order.items) do
		it.takeaway = true
	end
	OrderService.CreateTicket(c, order, o)
	deliveries[c.id] = c
	Net.NotifyAll("n_delivery_new", { name = name }, "info")
	Net.Sound(nil, "doorbell")
end

local function rideScooter()
	local f = ExpansionBuilder.Folder()
	local st = f and f:FindFirstChild("Stage3")
	local sc = st and st:FindFirstChild("Scooter") :: Model?
	if not sc or sc:GetAttribute("Away") then
		return
	end
	sc:SetAttribute("Away", true)
	local home = sc:GetPivot()
	for i = 1, 40 do
		sc:PivotTo(home * CFrame.new(-i * 0.35 * i / 8, 0, 0))
		task.wait(0.05)
	end
	for _, p in ipairs(sc:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 1
		end
	end
	task.wait(18)
	sc:PivotTo(home)
	for _, p in ipairs(sc:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 0
		end
	end
	sc:SetAttribute("Away", nil)
end

local function deliverAction(player: Player)
	local ids = {}
	for id in pairs(deliveries) do
		table.insert(ids, id)
	end
	table.sort(ids)
	if #ids == 0 then
		Net.Notify(player, "n_no_delivery", nil, "warn")
		return
	end
	for _, id in ipairs(ids) do
		local c = deliveries[id]
		local status = OrderService.Serve(player, c)
		if status == "complete" then
			deliveries[id] = nil
			OrderService.Complete(player, c)
			EconomyService.AddStat(player, "deliveries", 1)
			Net.Notify(player, "n_delivery_done", { name = c.name }, "success")
			task.spawn(rideScooter)
			return
		elseif status == "partial" then
			return
		end
	end
end

local function tickDeliveries(dt: number)
	for id, c in pairs(deliveries) do
		if not RestaurantService.TutorialActive then
			c.patience -= dt
		end
		if c.patience <= 0 or not RestaurantService.Open then
			deliveries[id] = nil
			OrderService.RemoveTicket(c)
			if c.patience <= 0 then
				RestaurantService.Rate(1, 1)
				RestaurantService.DayStats.walkouts += 1
				addReview(c.name, 1, "Lieferung kam nie an. Nie wieder!")
				Net.NotifyAll("n_delivery_lost", { name = c.name }, "bad")
			end
		end
	end
	local stage = BusinessService.StageDef()
	if stage.delivery and RestaurantService.Open and owner() and not RestaurantService.TutorialActive and deliveryCount() < 2 and os.clock() > nextDelivery then
		if nextDelivery > 0 then
			newDelivery()
		end
		nextDelivery = os.clock() + rng:NextNumber(70, 130) / stage.demand
	end
end

---------------------------------------------------------------------------
-- shop state for the laptop apps
---------------------------------------------------------------------------
local function provider()
	local b = biz()
	if not b then
		return nil
	end
	local status = BusinessService.StatusProvider and BusinessService.StatusProvider() or {}
	local staff = {}
	for role, e in pairs(b.staff) do
		staff[role] = { name = e.name, skill = e.skill, speed = e.speed, rel = e.rel, salary = e.salary, status = status[role] }
	end
	local reviews = {}
	for i = 1, math.min(12, #b.reviews) do
		reviews[i] = b.reviews[i]
	end
	local regulars = {}
	for _, r in ipairs(b.regulars) do
		table.insert(regulars, { name = r.name, visits = r.visits, menu = r.menu })
	end
	local avg, n = BusinessService.Rating()
	return {
		stage = b.stage,
		building = building,
		staff = staff,
		price = b.price,
		clean = BusinessService.Cleanliness(),
		dirt = #dirt,
		fresh = fresh,
		reviews = reviews,
		rating = avg,
		ratingCount = n,
		regulars = regulars,
		deliveries = deliveryCount(),
		theme = b.theme,
		themes = b.themes,
		branches = b.branches,
	}
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------
function BusinessService.Init()
	RestaurantService.BizProvider = provider
	OrderService.ModHook = modifiers
	OrderService.CompletedHook = onCompleted
	GameLoopService.DemandHook = function()
		local stage = BusinessService.StageDef()
		return stage.demand * priceDef().demand * (0.7 + 0.3 * BusinessService.Cleanliness())
	end
	GameLoopService.SpecialSpawnHook = specialSpawn
	GameLoopService.WageHook = payWages
	CustomerService.MaxActiveHook = function()
		return BusinessService.StageDef().maxActive
	end
	FoodPreparationService.FreshHook = function(id: string)
		return fresh[id] or 1
	end
	CustomerService.LeaveHook = function(c, angry, seat)
		if seat then
			if rng:NextNumber() < 0.65 then
				BusinessService.AddDirt((seat.CFrame * CFrame.new(0, 1.6, -1.6)).Position, rng:NextNumber() < 0.7 and "crumbs" or "trash")
			end
			if rng:NextNumber() < 0.2 then
				BusinessService.AddDirt((seat.CFrame * CFrame.new(1.5, -1, 0.3)).Position, "spill")
			end
		elseif angry then
			if rng:NextNumber() < 0.5 then
				BusinessService.AddDirt(c.root.Position + Vector3.new(rng:NextNumber(-1, 1), -1, rng:NextNumber(-1, 1)), "spill")
			end
			if rng:NextNumber() < 0.5 then
				addReview(c.name, 1, pick(BAD.wait) .. " Bin ohne Essen gegangen.")
			end
		end
	end

	FoodPreparationService.ExternalActions.dirt = function(player, part)
		if BusinessService.Clean(part) then
			EconomyService.AddXP(player, 2)
			EconomyService.AddStat(player, "cleaned", 1)
		end
	end
	FoodPreparationService.ExternalActions.fresh = function(player, part)
		local id = part:GetAttribute("Item")
		if id and (fresh[id] or 1) < 0.85 then
			BusinessService.Refresh(id)
			Net.Sound(player, "cut")
			EconomyService.AddXP(player, 1)
		end
	end
	FoodPreparationService.ExternalActions.delivery = function(player)
		deliverAction(player)
	end

	Net.OnRequest("BizBuyStage", buyStage)
	Net.OnRequest("BizHire", hire)
	Net.OnRequest("BizFire", fire)
	Net.OnRequest("BizTrain", train)
	Net.OnRequest("BizPrice", setPrice)
	Net.OnRequest("BizTheme", setTheme)
	Net.OnRequest("BizBranch", buyBranch)

	RestaurantService.OwnerChanged:Connect(function()
		applyWorld()
		applyTheme()
		staffChanged:Fire()
	end)
	applyWorld()
	applyTheme()
	setupFreshPoints()

	-- background: freshness decay, random dirt, delivery orders
	task.spawn(function()
		local acc, dirtAt = 0, os.clock() + 60
		while true do
			local dt = task.wait(1)
			tickDeliveries(dt)
			if RestaurantService.Open and owner() and not RestaurantService.TutorialActive then
				acc += dt
				if acc >= 5 then
					setupFreshPoints() -- bins of newly installed vegetables
					local rate = 0.55 / Config.Day.LengthSeconds
					for id in pairs(fresh) do
						local before = fresh[id]
						fresh[id] = math.max(0, before - rate * acc)
						if math.floor(before * 20) ~= math.floor(fresh[id] * 20) then
							updateFreshVisual(id)
						end
					end
					acc = 0
				end
				if os.clock() > dirtAt then
					dirtAt = os.clock() + rng:NextNumber(60, 100)
					if CustomerService.ActiveCount() > 0 then
						local r = workspace:FindFirstChild("Restaurant")
						local nav = r and r:FindFirstChild("Nav")
						local names = { "Queue1", "Queue2", "Queue3", "OrderSpot", "Pickup1", "Pickup2", "AisleMid", "DoorIn" }
						local p = nav and nav:FindFirstChild(names[rng:NextInteger(1, #names)]) :: BasePart?
						if p then
							BusinessService.AddDirt(p.Position + Vector3.new(rng:NextNumber(-1.5, 1.5), -2, rng:NextNumber(-1.5, 1.5)), rng:NextNumber() < 0.6 and "mud" or "trash")
						end
					end
				end
			end
		end
	end)
	local _ = clearDirt
end

-- Studio playtest helpers (Main's KebapDebug)
function BusinessService.DebugRefresh()
	applyWorld()
	staffChanged:Fire()
end
function BusinessService.DebugConstruct(stage: number)
	task.spawn(construct, stage)
end

return BusinessService
