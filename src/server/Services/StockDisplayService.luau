-- Shows the real ingredient stock in the world, so staff can see at a glance what is running low
-- instead of checking the laptop. Updated after every shop state push (RestaurantService.ShopPushed).
-- Each display is built lazily from the station's own visuals in the Restaurant asset (they serve as
-- templates and are replaced by parts in a "StockDisplay" folder):
--   bread crates   one bread / flatbread / box per unit
-- Displays never show more than Config.Stock.BaseCapacity; beyond that (storage upgrade) they stay full.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local RestaurantService = require(script.Parent.RestaurantService)

local StockDisplayService = {}

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
	local n = math.clamp(math.floor(RestaurantService.GetStock(CRATE_STOCK[c.kind])), 0, Config.Stock.BaseCapacity)
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
-- Update
---------------------------------------------------------------------------
type Kind = { setup: (BasePart) -> any, update: (any) -> () }
local KINDS: { [string]: Kind } = {
	bread = { setup = setupCrate, update = updateCrate },
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
