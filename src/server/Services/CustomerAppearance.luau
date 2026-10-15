-- Puts a Shared/CustomerLooks look onto an R15 rig (customers, pedestrians).
--
-- The Roblox body parts stay (joints, animations, attachments and the wrap cage that layered
-- clothing fits to) but are invisible; what you see is
--   * our meshes (ServerStorage.CustomerParts, built by tools/npc): one MeshPart per item and body
--     part, attributes Item / Part / Offset (centre relative to the centre of its R15 part), welded
--     to that part and coloured per look
--   * free Roblox catalog items (ServerStorage.CustomerAccessories, named by asset id): cloned,
--     texture removed, coloured flat, worn via Humanoid:AddAccessory
-- Skin segments that the clothes cover completely (CustomerLooks `covers`) are left out.
-- Everything it adds is tagged with the attribute LookPart (meshes) or is an Accessory, so Dress /
-- Strip can remove it again when a pooled rig is reused.

local ServerStorage = game:GetService("ServerStorage")

local CustomerLooks = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CustomerLooks"))

local CustomerAppearance = {}

local indexCache: { [Instance]: { [string]: { MeshPart } } } = {}

-- layered clothing order per look slot (the catalog items bring their own orders, which can put a
-- top over a jacket): bottoms < tops < outer layer
local WRAP_ORDER = { bottom = 4, top = 7, outer = 12 }

local function index(parts: Folder): { [string]: { MeshPart } }
	local idx = indexCache[parts]
	if idx then
		return idx
	end
	idx = {}
	for _, p in parts:GetChildren() do
		local item = p:GetAttribute("Item")
		if p:IsA("MeshPart") and item then
			idx[item] = idx[item] or {}
			table.insert(idx[item], p)
		end
	end
	indexCache[parts] = idx
	return idx
end

local function tint(acc: Accessory, color: Color3)
	for _, d in acc:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			d:Destroy()
		elseif d:IsA("MeshPart") then
			d.TextureID = ""
		end
	end
	for _, d in acc:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = color
			d.Material = Enum.Material.SmoothPlastic
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
end

-- remove everything a previous Dress added and show the Roblox body again
function CustomerAppearance.Strip(rig: Model)
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:RemoveAccessories()
	end
	for _, p in rig:GetChildren() do
		if p:GetAttribute("LookPart") or p:GetAttribute("Accessory") then -- Accessory: old look parts, phone
			p:Destroy()
		elseif p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Transparency = 0
		end
	end
end

function CustomerAppearance.Available(parts: Folder?, accessories: Folder?): boolean
	return (parts or ServerStorage:FindFirstChild("CustomerParts")) ~= nil
		and (accessories or ServerStorage:FindFirstChild("CustomerAccessories")) ~= nil
end

-- Dress `rig` in `look` (from CustomerLooks.Roll). Returns false if the parts are missing.
function CustomerAppearance.Dress(rig: Model, look, parts: Folder?, accessories: Folder?): boolean
	parts = parts or ServerStorage:FindFirstChild("CustomerParts") :: Folder?
	accessories = accessories or ServerStorage:FindFirstChild("CustomerAccessories") :: Folder?
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if not parts or not accessories or not hum then
		return false
	end
	CustomerAppearance.Strip(rig)
	-- the meshes are made for the unscaled body (the old look scaled pooled rigs)
	for _, name in { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale" } do
		local v = hum:FindFirstChild(name)
		if v and v:IsA("NumberValue") and v.Value ~= 1 then
			v.Value = 1
		end
	end
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end
	for _, p in rig:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Transparency = 1
			for _, d in p:GetChildren() do
				if d:IsA("Decal") then
					d:Destroy() -- the classic face decal; our face is geometry
				end
			end
		end
	end

	local idx = index(parts)
	local covered = CustomerLooks.CoveredParts(look) -- no skin under clothes (pokes through when joints bend)
	for _, piece in look.pieces do
		local def = CustomerLooks.ITEMS[piece.id]
		if not def then
			warn("[CustomerAppearance] unknown look piece", piece.id)
			continue
		end
		local colors = piece.colors or {}
		if def.source == "mesh" then
			for item, role in def.items do
				local hex = colors[role] or colors.main
				for _, template in idx[item] or {} do
					local partName = template:GetAttribute("Part")
					local seg = rig:FindFirstChild(partName) :: BasePart?
					if not seg or (item == "Body" and covered[partName]) then
						continue
					end
					local p = template:Clone()
					if hex then
						p.Color = Color3.fromHex(hex)
					end
					p.Anchored = false
					p.CanCollide = false
					p.CanQuery = false
					p.CanTouch = false
					p.Massless = true
					p.CFrame = seg.CFrame * CFrame.new(template:GetAttribute("Offset") :: Vector3)
					p:SetAttribute("LookPart", true)
					local w = Instance.new("WeldConstraint")
					w.Part0 = seg
					w.Part1 = p
					w.Parent = p
					p.Parent = rig
				end
			end
		else
			local template = accessories:FindFirstChild(tostring(def.asset))
			if template and template:IsA("Accessory") then
				local acc = template:Clone()
				tint(acc, Color3.fromHex(colors.main or colors.hair or "#6B6D70"))
				local wrap = acc:FindFirstChildWhichIsA("WrapLayer", true)
				if wrap and WRAP_ORDER[def.slot] then
					wrap.Order = WRAP_ORDER[def.slot]
				end
				hum:AddAccessory(acc)
			else
				warn("[CustomerAppearance] catalog item missing", piece.id, def.asset)
			end
		end
	end
	return true
end

return CustomerAppearance
