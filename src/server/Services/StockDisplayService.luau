-- Shows the real ingredient stock in the world, so staff can see at a glance what is running low
-- instead of checking the laptop. Updated after every shop state push (RestaurantService.ShopPushed).
-- Each display is built lazily from the station's own visuals in the Restaurant asset (they serve as
-- templates and are replaced by parts in a "StockDisplay" folder):
--   bread crates   one bread / flatbread / box per unit
--   salad bar      the veg / cheese level in each pan sinks with every portion used
--   sauces         a sight window on each bottle shows the sauce level
--   drinks fridge  one bottle per unit, the front row empties first
-- Displays never show more than Config.Stock.BaseCapacity; beyond that (storage upgrade) they stay full.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local IngredientData = require(Shared.IngredientData)
local RestaurantService = require(script.Parent.RestaurantService)

local StockDisplayService = {}

-- units the display shows: whole units, capped at what a full display holds
local function stockOf(stockId: string): number
	return math.clamp(math.floor(RestaurantService.GetStock(stockId)), 0, Config.Stock.BaseCapacity)
end

-- display parts are pure visuals: they must not block players or the stations' prompts
local function decor(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
end

---------------------------------------------------------------------------
-- Bread crates: the display shows the real stock – one bread / flatbread / box per unit, up to
-- Config.Stock.BaseCapacity (beyond that, e.g. with the storage upgrade, the crate stays full).
-- The crate model's own display pieces (Restaurant asset) serve as templates and are replaced.
---------------------------------------------------------------------------
local CRATE_STOCK = { classic = "bread_classic", duerum = "bread_duerum", box = "box" }
local CRATE_PIECES = { classic = { "DisplayBreadBottom", "DisplayBreadTop" }, duerum = { "DisplayDuerumFlat" }, box = { "Box", "BoxSeam" } }
local CRATE_FLOOR = 0.115 -- crate floor + cloth, above the bottom of the bin hitbox
local BREAD_SCALE = 0.65 -- display breads are smaller so 2 x 4 fit per layer
local BREAD_LAYER = 8

type CratePiece = { part: BasePart, rot: CFrame, x: number, z: number, h: number }
type Crate = { bin: BasePart, kind: string, pieces: { CratePiece }, folder: Folder, shown: number? }

-- templates relative to the bin: rotation, horizontal offset and height above the crate floor
local function setupCrate(bin: BasePart): Crate | false
	local unit = bin.Parent
	local kind = bin:GetAttribute("Item")
	local names = CRATE_PIECES[kind]
	if not unit or not names then
		return false
	end
	local floorY = -bin.Size.Y / 2 + CRATE_FLOOR
	local pieces: { CratePiece } = {}
	local anchor: BasePart? = nil
	for _, name in ipairs(names) do
		-- the first piece is the lowest one; the others belong to the same item (closest to it)
		local best: BasePart? = nil
		for _, c in ipairs(unit:GetChildren()) do
			if c.Name == name and c:IsA("BasePart") then
				local better = if anchor
					then not best or (c.Position - anchor.Position).Magnitude < (best.Position - anchor.Position).Magnitude
					else not best or c.Position.Y < best.Position.Y
				if better then
					best = c
				end
			end
		end
		if not best then
			return false -- not the expected crate model: leave it untouched
		end
		anchor = anchor or best
		local rel = bin.CFrame:ToObjectSpace(best.CFrame)
		local tpl = best:Clone()
		tpl.Anchored = true
		tpl.CanCollide = false
		tpl.CanTouch = false
		tpl.CanQuery = false -- a full heap must not block the bin's prompt (line of sight)
		table.insert(pieces, { part = tpl, rot = rel - rel.Position, x = rel.X, z = rel.Z, h = rel.Y - floorY })
	end
	for _, c in ipairs(unit:GetChildren()) do
		if table.find(names, c.Name) or c.Name == "BoxBand" then
			c:Destroy()
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "StockDisplay"
	folder.Parent = unit
	return { bin = bin, kind = kind, pieces = pieces, folder = folder }
end

-- the parts for the i-th unit in the crate (deterministic, so items never jump when stock changes)
local function crateItem(c: Crate, i: number): { BasePart }
	local rng = Random.new(i)
	local floorY = -c.bin.Size.Y / 2 + CRATE_FLOOR
	local parts = {}
	for _, p in ipairs(c.pieces) do
		local part = p.part:Clone()
		local cf
		if c.kind == "classic" then
			-- 2 columns x 4 rows per layer, slightly loose like real bread
			local layer, k = (i - 1) // BREAD_LAYER, (i - 1) % BREAD_LAYER
			local x = ((k % 2) - 0.5) * 0.76 + rng:NextNumber(-0.03, 0.03)
			local z = ((k // 2) - 1.5) * 0.5 + rng:NextNumber(-0.02, 0.02)
			local y = floorY + layer * 0.25 + p.h * BREAD_SCALE
			part.Size = p.part.Size * BREAD_SCALE
			cf = CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0)
		elseif c.kind == "duerum" then
			-- a stack of flatbreads, each a little off-centre and turned
			cf = CFrame.new(p.x + rng:NextNumber(-0.05, 0.05), floorY + (i - 1) * 0.042 + p.h, p.z + rng:NextNumber(-0.05, 0.05))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		else
			-- boxes nest inside each other: every box sits a little higher and narrower than the one
			-- below, so the stack shows one rim per box
			local grow = (Config.Stock.BaseCapacity - i) * 0.006
			part.Size = p.part.Size + Vector3.new(grow, 0, grow)
			cf = CFrame.new(p.x, floorY + (i - 1) * 0.035 + p.h, p.z)
		end
		part.CFrame = c.bin.CFrame * cf * p.rot
		part.Name = p.part.Name
		table.insert(parts, part)
	end
	return parts
end

local function updateCrate(c: Crate)
	local n = stockOf(CRATE_STOCK[c.kind])
	local old = c.shown or 0
	if old == n then
		return
	end
	c.shown = n
	for _, item in ipairs(c.folder:GetChildren()) do
		-- only the top box carries the lid seam: the old and the new top box are rebuilt
		local idx = tonumber(item.Name) or math.huge
		if idx > n or (c.kind == "box" and (idx == old or idx == n)) then
			item:Destroy()
		end
	end
	for i = 1, n do
		if not c.folder:FindFirstChild(tostring(i)) then
			local item = Instance.new("Model")
			item.Name = tostring(i)
			for _, part in ipairs(crateItem(c, i)) do
				if c.kind == "box" and part.Name == "BoxSeam" and i < n then
					part:Destroy()
				else
					part.Parent = item
				end
			end
			item.Parent = c.folder
		end
	end
end

---------------------------------------------------------------------------
-- Salad bar pans: the tray gets a rim, so it reads as a pan. The bed of veg sinks from the rim down
-- to the tray with every portion used; below SPARSE_BELOW portions the pieces on top thin out, and
-- an empty pan shows only the bare tray. The tray's own Fill + VegPiece parts are the templates.
---------------------------------------------------------------------------
local PAN_RIM = 0.35 -- rim height above the tray
local PAN_WALL = 0.06
local BED_MIN = 0.02 -- bed thickness with a single portion left
local SPARSE_BELOW = 10

type PanPiece = { part: BasePart, rot: CFrame, x: number, z: number, h: number }
type Pan = { tray: BasePart, stock: string, bed: BasePart, pieces: { PanPiece }, folder: Folder, x: number, z: number, shown: number? }

local function setupPan(tray: BasePart): Pan | false
	local def = IngredientData.Find(tray:GetAttribute("Item"))
	local fill = tray:FindFirstChild("Fill")
	if not def or not fill or not fill:IsA("BasePart") then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "StockDisplay"
	folder.Parent = tray
	local rel = tray.CFrame:ToObjectSpace(fill.CFrame)
	local top = tray.Size.Y / 2
	local inner = fill.Size
	local walls = {
		{ Vector3.new(inner.X + PAN_WALL * 2, PAN_RIM, PAN_WALL), 0, (inner.Z + PAN_WALL) / 2 },
		{ Vector3.new(inner.X + PAN_WALL * 2, PAN_RIM, PAN_WALL), 0, -(inner.Z + PAN_WALL) / 2 },
		{ Vector3.new(PAN_WALL, PAN_RIM, inner.Z), (inner.X + PAN_WALL) / 2, 0 },
		{ Vector3.new(PAN_WALL, PAN_RIM, inner.Z), -(inner.X + PAN_WALL) / 2, 0 },
	}
	for _, w in ipairs(walls) do
		local wall = Instance.new("Part")
		wall.Name = "PanRim"
		wall.Size = w[1]
		wall.CFrame = tray.CFrame * CFrame.new(rel.X + w[2], top + PAN_RIM / 2, rel.Z + w[3])
		wall.Color = tray.Color
		wall.Material = tray.Material
		decor(wall)
		wall.Parent = folder
	end
	local pieces: { PanPiece } = {}
	for _, c in ipairs(fill:GetChildren()) do
		if c:IsA("BasePart") then
			local p = fill.CFrame:ToObjectSpace(c.CFrame)
			local part = c:Clone()
			decor(part)
			table.insert(pieces, { part = part, rot = p - p.Position, x = rel.X + p.X, z = rel.Z + p.Z, h = p.Y - fill.Size.Y / 2 })
		end
	end
	local bed = fill:Clone()
	bed:ClearAllChildren()
	decor(bed)
	fill:Destroy()
	return { tray = tray, stock = def.stock, bed = bed, pieces = pieces, folder = folder, x = rel.X, z = rel.Z }
end

local function updatePan(pan: Pan)
	local n = stockOf(pan.stock)
	if pan.shown == n then
		return
	end
	pan.shown = n
	local h = BED_MIN + (PAN_RIM - 0.04 - BED_MIN) * (n - 1) / (Config.Stock.BaseCapacity - 1)
	local top = pan.tray.Size.Y / 2
	pan.bed.Size = Vector3.new(pan.bed.Size.X, h, pan.bed.Size.Z)
	pan.bed.CFrame = pan.tray.CFrame * CFrame.new(pan.x, top + h / 2, pan.z)
	pan.bed.Parent = if n > 0 then pan.folder else nil
	local visible = math.ceil(#pan.pieces * math.min(n / SPARSE_BELOW, 1))
	for i, p in ipairs(pan.pieces) do
		p.part.CFrame = pan.tray.CFrame * CFrame.new(p.x, top + h + p.h, p.z) * p.rot
		p.part.Parent = if i <= visible then pan.folder else nil
	end
end

---------------------------------------------------------------------------
-- Sauce bottles: a dark sight window on the staff side of each bottle with a bar of sauce that
-- drops with every portion used.
---------------------------------------------------------------------------
local STAFF_SIDE = Vector3.new(0, 0, -1) -- kitchen side of the front counter (WorldBuilder layout)
local WINDOW_WIDTH = 0.24
local WINDOW_HEIGHT = 0.7 -- share of the bottle height
local WINDOW_COLOR = Color3.fromRGB(35, 35, 40)

type Sauce = { bottle: BasePart, stock: string, window: BasePart, bar: BasePart, folder: Folder, shown: number? }

local function setupSauce(bottle: BasePart): Sauce | false
	local def = IngredientData.Find(bottle:GetAttribute("Item"))
	-- the bottle is an upright cylinder: its axis (the part's X axis) points up
	if not def or math.abs(bottle.CFrame.RightVector.Y) < 0.9 then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "StockDisplay"
	folder.Parent = bottle
	local radius = math.min(bottle.Size.Y, bottle.Size.Z) / 2
	local center = bottle.Position + STAFF_SIDE * (radius + 0.01)
	local window = Instance.new("Part")
	window.Name = "SightWindow"
	window.Size = Vector3.new(WINDOW_WIDTH, bottle.Size.X * WINDOW_HEIGHT, 0.02)
	window.CFrame = CFrame.lookAt(center, center + STAFF_SIDE)
	window.Color = WINDOW_COLOR
	window.Material = Enum.Material.SmoothPlastic
	decor(window)
	window.Parent = folder
	local bar = Instance.new("Part")
	bar.Name = "SauceLevel"
	bar.Color = bottle.Color
	bar.Material = Enum.Material.SmoothPlastic
	decor(bar)
	return { bottle = bottle, stock = def.stock, window = window, bar = bar, folder = folder }
end

local function updateSauce(s: Sauce)
	local n = stockOf(s.stock)
	if s.shown == n then
		return
	end
	s.shown = n
	local full = s.window.Size.Y - 0.08
	local h = full * n / Config.Stock.BaseCapacity
	s.bar.Size = Vector3.new(WINDOW_WIDTH - 0.08, h, 0.02)
	s.bar.CFrame = s.window.CFrame * CFrame.new(0, -full / 2 + h / 2, -0.012)
	s.bar.Parent = if n > 0 then s.folder else nil
end

---------------------------------------------------------------------------
-- Drinks fridge: one bottle per unit on the drink's shelf, in rows from the back to the glass door,
-- so the front row empties first. The shelf's own Bottle parts are the templates.
---------------------------------------------------------------------------
local FRIDGE_COLS = 6
local FRIDGE_ROWS = 5
local FRIDGE_MARGIN = 0.25 -- distance of the outer bottles from the shelf edges

type Shelf = { shelf: BasePart, stock: string, bottle: BasePart, rot: CFrame, y: number, front: number, folder: Folder, shown: number? }

local function setupShelf(shelf: BasePart): Shelf | false
	local def = IngredientData.Find(shelf:GetAttribute("Item"))
	local unit = shelf.Parent
	if not def or not unit then
		return false
	end
	-- the shelf's bottles are the ones within its height
	local bottles = {}
	for _, c in ipairs(unit:GetChildren()) do
		if c.Name == "Bottle" and c:IsA("BasePart") and math.abs(shelf.CFrame:PointToObjectSpace(c.Position).Y) < shelf.Size.Y / 2 then
			table.insert(bottles, c)
		end
	end
	if #bottles == 0 then
		return false
	end
	local rel = shelf.CFrame:ToObjectSpace(bottles[1].CFrame)
	local tpl = bottles[1]:Clone()
	decor(tpl)
	for _, b in ipairs(bottles) do
		b:Destroy()
	end
	local glass = unit:FindFirstChild("FridgeGlass")
	local front = if glass and glass:IsA("BasePart") and shelf.CFrame:PointToObjectSpace(glass.Position).Z < 0 then -1 else 1
	local folder = Instance.new("Folder")
	folder.Name = "StockDisplay"
	folder.Parent = unit
	return { shelf = shelf, stock = def.stock, bottle = tpl, rot = rel - rel.Position, y = rel.Y, front = front, folder = folder }
end

local function updateShelf(s: Shelf)
	local n = math.min(stockOf(s.stock), FRIDGE_COLS * FRIDGE_ROWS)
	if s.shown == n then
		return
	end
	s.shown = n
	for _, b in ipairs(s.folder:GetChildren()) do
		if (tonumber(b.Name) or math.huge) > n then
			b:Destroy()
		end
	end
	local halfX = s.shelf.Size.X / 2 - FRIDGE_MARGIN
	local halfZ = s.shelf.Size.Z / 2 - FRIDGE_MARGIN
	for i = 1, n do
		if not s.folder:FindFirstChild(tostring(i)) then
			local row, col = (i - 1) // FRIDGE_COLS, (i - 1) % FRIDGE_COLS
			local x = -halfX + col * halfX * 2 / (FRIDGE_COLS - 1)
			local z = s.front * (-halfZ + row * halfZ * 2 / (FRIDGE_ROWS - 1))
			local b = s.bottle:Clone()
			b.Name = tostring(i)
			b.CFrame = s.shelf.CFrame * CFrame.new(x, s.y, z) * s.rot
			b.Parent = s.folder
		end
	end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
type Kind = { setup: (BasePart) -> any, update: (any) -> () }
local KINDS: { [string]: Kind } = {
	bread = { setup = setupCrate, update = updateCrate },
	veg = { setup = setupPan, update = updatePan },
	cheese = { setup = setupPan, update = updatePan },
	sauce = { setup = setupSauce, update = updateSauce },
	drink = { setup = setupShelf, update = updateShelf },
}
local displays: { [BasePart]: any } = {} -- station -> display state, false if it can't show stock

function StockDisplayService.Update()
	for _, station in ipairs(CollectionService:GetTagged("Station")) do
		local kind = KINDS[station:GetAttribute("Station")]
		if kind and station:IsA("BasePart") then
			if displays[station] == nil then
				displays[station] = kind.setup(station)
			end
			if displays[station] then
				kind.update(displays[station])
			end
		end
	end
end

function StockDisplayService.Init()
	RestaurantService.ShopPushed:Connect(StockDisplayService.Update)
	StockDisplayService.Update()
end

return StockDisplayService
