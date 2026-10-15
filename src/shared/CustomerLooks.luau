-- Customer looks (pure data + roll): which pieces a customer wears and in which colours.
-- Rolled from the customer's lookSeed, so a regular looks the same on every visit.
-- Server/CustomerAppearance puts a look onto an R15 rig.
--
-- Every customer shares one body (tools/npc: classic R15 blocks + face). Variety comes from:
--   mesh    – our Blender mesh set (ServerStorage.CustomerParts, objects <Item>_<R15 part>);
--             `items` maps each mesh item to a colour role of the piece
--   catalog – free avatar items made by Roblox (ServerStorage.CustomerAccessories, named by
--             asset id); textures are removed and the item is coloured flat, so it matches the
--             palette and the untextured block look
-- Colours: red, grey, brown and the shades in between (+ dark denim for jeans).
-- Rules: one top, an optional outer layer, bottoms, shoes, hair; under a hat the customer gets a
-- buzz cut (women also a low ponytail) so no hair pokes through the hat.

local CustomerLooks = {}

CustomerLooks.VERSION = 2

CustomerLooks.PALETTE = {
	red = { "#8C2B2B", "#B5382F", "#6E2424", "#A0463A", "#7A3B32" },
	brown = { "#5A3E2B", "#7B5A3F", "#3E2A1E", "#9A7656", "#6B4A35" },
	sand = { "#C2A07A", "#D8C3A5" },
	offwhite = { "#EDE9E0" },
	grey = { "#2E2E30", "#4A4B4E", "#6B6D70", "#8E9094", "#B8BABD" },
	greyDark = { "#2E2E30", "#4A4B4E", "#6B6D70" }, -- light grey trousers read as white
	dark = { "#151516", "#232325", "#2E2E30" },
	between = { "#7A4B3A", "#8A6A5A", "#6E5A55", "#5C3A33" }, -- rust, taupe, greige, maroon-brown
	denim = { "#2F3B52", "#263044", "#3A465C" },
	shoe = { "#B8BABD", "#EDE9E0", "#2E2E30", "#5A3E2B", "#151516" },
	sole = { "#EDE9E0", "#D8C3A5", "#2E2E30" },
}

CustomerLooks.SKIN = { "#F2D3B8", "#E8BE9C", "#D9A57E", "#C08A62", "#9C6B48", "#7A4E33", "#5C3A26" }
CustomerLooks.HAIR = { "#151516", "#2B1E16", "#3B2A20", "#5A3E2B", "#7B5A3F", "#8C4A2F", "#9A9A9A", "#C8C8C8" }
CustomerLooks.HAIR_WEIGHTS = { 4, 4, 5, 4, 3, 2, 1, 1 } -- grey and white less often
CustomerLooks.MOUTH = { m = "#5A2A24", w = "#8A3A3A" }
CustomerLooks.EYES = "#231B17"
CustomerLooks.SHINE = "#FFFFFF"

-- default colour groups per slot (an item can override them with `colors`); a group listed
-- several times is picked more often
local SLOT_COLORS = {
	top = { "grey", "grey", "grey", "between", "between", "red", "red", "sand", "brown", "offwhite" },
	outer = { "brown", "brown", "dark", "grey", "between", "between" },
	bottom = { "denim", "dark", "greyDark", "brown", "sand" },
	hat = { "red", "brown", "grey", "dark", "between" },
	face = { "dark" },
}

-- sex: "m" / "w" / nil (both). weight: relative chance within the slot.
-- covers: body segments the piece hides completely ("Arms"/"Legs"/"Feet" = both sides). Their skin
-- is not built at all, so rigid body corners never poke through the clothing when joints bend.
-- Only list a segment if it stays covered in every pose (crop top, short sleeves, skirt: no).
-- needsTop: an outer layer that only fits over these tops (our tight mesh jacket would let the
-- thicker layered catalog tops poke through).
CustomerLooks.ITEMS = {
	-- base (always)
	body = { slot = "base", source = "mesh", items = { Body = "skin" } },
	face_m = { slot = "base", source = "mesh", sex = "m", items = { Eyes = "eyes", EyeShine = "shine", Nose = "skin", Mouth = "mouth", Brows = "hair" } },
	face_w = {
		slot = "base",
		source = "mesh",
		sex = "w",
		items = { Eyes = "eyes", EyeShine = "shine", Nose = "skin", Mouth = "mouth", BrowsThin = "hair", Lashes = "eyes" },
	},

	-- tops
	hoodie = { slot = "top", source = "mesh", weight = 3, items = { Hoodie = "main", HoodieAccent = "accent" }, covers = { "UpperTorso", "LowerTorso", "UpperArms", "LowerArms" } },
	tee = { slot = "top", source = "catalog", asset = 9112474888, weight = 3, covers = { "UpperTorso" } }, -- Basic T-Shirt
	longsleeve = { slot = "top", source = "catalog", asset = 7178740556, weight = 1, covers = { "UpperTorso", "UpperArms", "LowerArms" } }, -- Baseball Long Sleeve
	sweater = { slot = "top", source = "catalog", asset = 9240758221, weight = 2, covers = { "UpperTorso", "UpperArms", "LowerArms" } }, -- Knit Sweater
	tietop = { slot = "top", source = "catalog", asset = 9240752338, weight = 2, sex = "w" }, -- Tie-Front Top

	-- outer layer (optional)
	jacket = { slot = "outer", source = "mesh", weight = 3, items = { Jacket = "main" }, needsTop = { hoodie = true }, covers = { "UpperArms" } },
	leather = { slot = "outer", source = "catalog", asset = 6984767443, weight = 2, covers = { "UpperArms", "LowerArms" } }, -- Leather Jacket
	leather_collar = { slot = "outer", source = "catalog", asset = 7192547628, weight = 1, covers = { "UpperArms", "LowerArms" } }, -- Collared Leather Jacket
	denim_jacket = { slot = "outer", source = "catalog", asset = 8516609675, weight = 1, covers = { "UpperArms", "LowerArms" } }, -- Denim Jacket
	parka = { slot = "outer", source = "catalog", asset = 8648397446, weight = 1, covers = { "UpperArms", "LowerArms" } }, -- Parka
	coat = { slot = "outer", source = "catalog", asset = 8516638468, weight = 1, covers = { "UpperArms", "LowerArms" } }, -- Business Coat
	trench = { slot = "outer", source = "catalog", asset = 8648380153, weight = 1, colors = { "sand", "brown", "grey" }, covers = { "UpperArms", "LowerArms" } }, -- Trench Coat
	zip_hoodie = { slot = "outer", source = "catalog", asset = 7192553841, weight = 1, colors = { "grey", "dark", "red" }, covers = { "UpperArms", "LowerArms" } }, -- Zip Hoodie

	-- bottoms
	jeans = { slot = "bottom", source = "mesh", weight = 4, items = { Pants = "main" }, colors = { "denim", "dark", "greyDark" }, covers = { "LowerTorso", "UpperLegs", "LowerLegs" } },
	cargo = { slot = "bottom", source = "catalog", asset = 6984740059, weight = 2, colors = { "brown", "greyDark", "sand", "dark" }, covers = { "LowerTorso", "UpperLegs", "LowerLegs" } }, -- Cargo Pants
	sweats = { slot = "bottom", source = "catalog", asset = 7192664790, weight = 1, colors = { "greyDark", "dark" }, covers = { "LowerTorso", "UpperLegs", "LowerLegs" } }, -- Casual Sweats
	shorts = { slot = "bottom", source = "catalog", asset = 9174391966, weight = 1, colors = { "sand", "brown", "greyDark" }, covers = { "LowerTorso", "UpperLegs" } }, -- Bermuda Shorts
	skirt = { slot = "bottom", source = "catalog", asset = 9240776381, weight = 3, sex = "w", colors = { "red", "brown", "dark", "sand", "between" }, covers = { "LowerTorso" } }, -- Long Ruffle Skirt

	-- shoes
	sneakers = { slot = "shoes", source = "mesh", items = { Shoe = "main", ShoeSole = "sole", ShoeAccent = "accent" }, covers = { "Feet" } },

	-- hair (catalog hair is free Roblox hair; the colour comes from the look)
	crop = { slot = "hair", source = "mesh", sex = "m", weight = 4, items = { Hair = "hair" } },
	short_sleek = { slot = "hair", source = "catalog", asset = 6993758617, sex = "m", weight = 2 },
	side_part = { slot = "hair", source = "catalog", asset = 7193419595, sex = "m", weight = 2 },
	curly_fade = { slot = "hair", source = "catalog", asset = 9244010432, sex = "m", weight = 2 },
	short_fringe = { slot = "hair", source = "catalog", asset = 9243976603, sex = "m", weight = 2 },
	surfer = { slot = "hair", source = "catalog", asset = 9244033194, weight = 1 },
	curly_afro = { slot = "hair", source = "catalog", asset = 7193451306, weight = 1 },
	ponytail = { slot = "hair", source = "catalog", asset = 9244097555, sex = "w", weight = 3 },
	wavy_middle = { slot = "hair", source = "catalog", asset = 7193448258, sex = "w", weight = 3 },
	medium_middle = { slot = "hair", source = "catalog", asset = 7193437847, sex = "w", weight = 2 },
	straight_bangs = { slot = "hair", source = "catalog", asset = 7193449810, sex = "w", weight = 2 },
	top_knot = { slot = "hair", source = "catalog", asset = 9244060144, sex = "w", weight = 1 },
	-- under hats
	buzz = { slot = "hatHair", source = "mesh", items = { Buzz = "hair" } },
	tail = { slot = "hatHair", source = "mesh", sex = "w", items = { Tail = "hair" } },

	-- hats (optional) – always with buzz (+ tail) instead of the normal hair
	cap = { slot = "hat", source = "catalog", asset = 607702162, weight = 3 }, -- Roblox Baseball Cap
	fedora = { slot = "hat", source = "catalog", asset = 3033910400, weight = 1 }, -- International Fedora

	-- face accessories (optional)
	aviators = { slot = "face", source = "catalog", asset = 376526673, weight = 1 }, -- Stylish Aviators
	shades = { slot = "face", source = "catalog", asset = 376527500, weight = 1 }, -- Orange Shades
}

CustomerLooks.CHANCE = {
	w = 0.5, -- share of women
	outer = 0.5,
	hat = 0.2,
	face = 0.08,
}

-- R15 parts behind the `covers` names
CustomerLooks.COVER_PARTS = {
	UpperTorso = { "UpperTorso" },
	LowerTorso = { "LowerTorso" },
	UpperArms = { "LeftUpperArm", "RightUpperArm" },
	LowerArms = { "LeftLowerArm", "RightLowerArm" },
	UpperLegs = { "LeftUpperLeg", "RightUpperLeg" },
	LowerLegs = { "LeftLowerLeg", "RightLowerLeg" },
	Feet = { "LeftFoot", "RightFoot" },
}

-- R15 parts whose skin a look does not need (fully covered by its clothes)
function CustomerLooks.CoveredParts(look): { [string]: boolean }
	local covered = {}
	for _, piece in look.pieces do
		local def = CustomerLooks.ITEMS[piece.id]
		for _, name in (def and def.covers) or {} do
			for _, part in CustomerLooks.COVER_PARTS[name] do
				covered[part] = true
			end
		end
	end
	return covered
end

-- every catalog asset id the looks can use (for baking ServerStorage.CustomerAccessories)
function CustomerLooks.CatalogAssets(): { number }
	local ids = {}
	for _, def in CustomerLooks.ITEMS do
		if def.source == "catalog" then
			table.insert(ids, def.asset)
		end
	end
	table.sort(ids)
	return ids
end

---------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------
local function pickWeighted(rng: Random, list: { any }, weightOf: (any) -> number)
	local total = 0
	for _, v in list do
		total += weightOf(v)
	end
	local roll = rng:NextNumber() * total
	for _, v in list do
		roll -= weightOf(v)
		if roll <= 0 then
			return v
		end
	end
	return list[#list]
end

-- items of a slot for this sex, sorted by id so the roll never depends on table order
local function itemsFor(slot: string, sex: string, top: string?): { string }
	local ids = {}
	for id, def in CustomerLooks.ITEMS do
		if def.slot == slot and (def.sex == nil or def.sex == sex) and (def.needsTop == nil or def.needsTop[top]) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function pickItem(rng: Random, slot: string, sex: string, top: string?): string
	return pickWeighted(rng, itemsFor(slot, sex, top), function(id)
		return CustomerLooks.ITEMS[id].weight or 1
	end)
end

-- small brightness jitter so two customers in "the same" colour are not identical
local function jitter(rng: Random, hex: string, amount: number): string
	local c = Color3.fromHex(hex)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 + rng:NextNumber(-amount, amount)), 0, 1)):ToHex()
end

local function pickColor(rng: Random, groups: { string }, avoid: { [string]: boolean }?): string
	local hex
	for _ = 1, 6 do
		local group = CustomerLooks.PALETTE[groups[rng:NextInteger(1, #groups)]]
		hex = group[rng:NextInteger(1, #group)]
		if not (avoid and avoid[hex]) then
			break
		end
	end
	return hex
end

-- Roll a complete look. Only `rng` is used, so the same seed always gives the same look.
-- opts.vip: VIPs and critics are recognisable – dark coat over a sweater and a fedora.
-- opts.sex: force "m" / "w" (e.g. to match a known name); the rest of the roll stays the same.
function CustomerLooks.Roll(rng: Random, opts: { vip: boolean?, sex: string? }?)
	local vip = opts ~= nil and opts.vip == true
	local sexRoll = rng:NextNumber()
	local sex = (opts and (opts.sex == "m" or opts.sex == "w") and opts.sex)
		or (sexRoll < CustomerLooks.CHANCE.w and "w" or "m")
	local skin = CustomerLooks.SKIN[rng:NextInteger(1, #CustomerLooks.SKIN)]
	local hairIndex = pickWeighted(rng, { 1, 2, 3, 4, 5, 6, 7, 8 }, function(i)
		return CustomerLooks.HAIR_WEIGHTS[i]
	end)
	local hair = jitter(rng, CustomerLooks.HAIR[hairIndex], 0.06)
	local roles = {
		skin = skin,
		hair = hair,
		eyes = CustomerLooks.EYES,
		shine = CustomerLooks.SHINE,
		mouth = CustomerLooks.MOUTH[sex],
	}
	local used: { [string]: boolean } = {}
	local pieces = {}
	local function add(id: string, colors)
		table.insert(pieces, { id = id, colors = colors })
	end
	local function clothColors(id: string)
		local def = CustomerLooks.ITEMS[id]
		local main = pickColor(rng, def.colors or SLOT_COLORS[def.slot], used)
		used[main] = true
		return { main = jitter(rng, main, 0.05), accent = pickColor(rng, { "red", "grey" }, used) }
	end

	add("body", { skin = skin })
	add(sex == "w" and "face_w" or "face_m", roles)

	local top = vip and "sweater" or pickItem(rng, "top", sex)
	add(top, clothColors(top))
	if vip then
		add("coat", { main = pickColor(rng, { "dark" }) })
	elseif rng:NextNumber() < CustomerLooks.CHANCE.outer then
		local id = pickItem(rng, "outer", sex, top)
		add(id, clothColors(id))
	end
	local bottom = pickItem(rng, "bottom", sex)
	add(bottom, clothColors(bottom))
	add("sneakers", {
		main = pickColor(rng, { "shoe" }),
		sole = pickColor(rng, { "sole" }),
		accent = pickColor(rng, { "red", "grey" }),
	})

	if vip or rng:NextNumber() < CustomerLooks.CHANCE.hat then
		local hat = vip and "fedora" or pickItem(rng, "hat", sex)
		add("buzz", { hair = hair })
		if sex == "w" then
			add("tail", { hair = hair })
		end
		add(hat, { main = jitter(rng, pickColor(rng, SLOT_COLORS.hat, used), 0.05) })
	else
		add(pickItem(rng, "hair", sex), { hair = hair, main = hair })
	end
	if rng:NextNumber() < CustomerLooks.CHANCE.face then
		add(pickItem(rng, "face", sex), { main = pickColor(rng, SLOT_COLORS.face) })
	end

	return { version = CustomerLooks.VERSION, sex = sex, skin = skin, hair = hair, pieces = pieces }
end

return CustomerLooks
