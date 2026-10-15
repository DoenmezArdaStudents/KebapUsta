--[[
	studio_preview.luau – random customers from the npc_builder.py mesh set in Studio, no upload.

	1. Mesh templates: reads ServerStorage.NpcPreviewData (Manifest + Data, synced by Rojo from
	   tools/npc/out/studio/, written by `npc_builder.py --studio`) and builds every object as a
	   MeshPart via EditableMesh in ServerStorage.CustomerPartsPreview, with the attributes
	   Item / Part / Offset that Server/CustomerAppearance expects (like the baked CustomerParts).
	2. Catalog items: loads every asset of Shared/CustomerLooks into ServerStorage.CustomerAccessories
	   (InsertService, free Roblox items) – the folder that is exported to assets/ for the game.
	3. Lineup: rolls looks for SEEDS with Shared/CustomerLooks and dresses standard R15 rigs with
	   Server/CustomerAppearance in workspace.CustomerLookPreview, in front of the restaurant.
	   Old previews (NpcPreview, CustomerPreviewTest, …) are removed.

	Edit mode only (MCP execute_luau or the command bar): EditableMesh geometry is not saved and is
	lost when a playtest starts.
]]

local SEEDS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }

local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- fresh copies: require caches modules for the whole plugin session
local CustomerLooks = require(ReplicatedStorage.Shared.CustomerLooks:Clone())
local CustomerAppearance = require(ServerScriptService.Services.CustomerAppearance:Clone())

for _, path in {
	{ workspace, "CustomerPreviewTest" },
	{ workspace, "MoodTest" },
	{ workspace, "NpcPreview" },
	{ workspace, "AccessoryFitTest" },
	{ workspace, "CustomerLookPreview" },
	{ ServerStorage, "CustomerPreviewParts" },
	{ ServerStorage, "CustomerPreviewData" },
} do
	local inst = path[1]:FindFirstChild(path[2])
	if inst then
		inst:Destroy()
	end
end

-- 1. mesh templates ---------------------------------------------------------------------------
local data = ServerStorage:WaitForChild("NpcPreviewData", 10)
assert(data, "ServerStorage.NpcPreviewData missing – sync tools/npc/out/studio with Rojo")
local manifest = require(data:WaitForChild("Manifest"):Clone())
local chunks = {}
for i = 1, manifest.chunks do
	table.insert(chunks, data.Data:WaitForChild(string.format("Data_%03d", i)).Value)
end
local buf = EncodingService:Base64Decode(buffer.fromstring(table.concat(chunks)))
buf = EncodingService:DecompressBuffer(buf, Enum.CompressionAlgorithm.Zstd)
assert(buffer.len(buf) == manifest.bytes, "data length does not match the manifest")

local old = ServerStorage:FindFirstChild("CustomerPartsPreview")
if old then
	old:Destroy()
end
local parts = Instance.new("Folder")
parts.Name = "CustomerPartsPreview"
local offset = 0
for _, info in manifest.parts do
	local nv, nt = buffer.readu16(buf, offset), buffer.readu16(buf, offset + 2)
	offset += 4
	local em = AssetService:CreateEditableMesh()
	local vids, nids = table.create(nv), table.create(nv)
	for i = 1, nv do
		local p = Vector3.new(buffer.readi16(buf, offset), buffer.readi16(buf, offset + 2), buffer.readi16(buf, offset + 4)) / 2048
		local n = Vector3.new(buffer.readi8(buf, offset + 6), buffer.readi8(buf, offset + 7), buffer.readi8(buf, offset + 8)) / 127
		offset += 9
		vids[i] = em:AddVertex(p)
		nids[i] = em:AddNormal(n.Magnitude > 0 and n.Unit or Vector3.yAxis)
	end
	for _ = 1, nt do
		local a, b, c = buffer.readu16(buf, offset) + 1, buffer.readu16(buf, offset + 2) + 1, buffer.readu16(buf, offset + 4) + 1
		offset += 6
		local f = em:AddTriangle(vids[a], vids[b], vids[c])
		em:SetFaceNormals(f, { nids[a], nids[b], nids[c] })
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	mp.Name = info.name
	mp.Color = Color3.fromHex(info.color)
	mp.Material = Enum.Material.SmoothPlastic
	mp:SetAttribute("Item", info.item)
	mp:SetAttribute("Part", info.part)
	mp:SetAttribute("Offset", Vector3.new(info.offset[1], info.offset[2], info.offset[3]))
	mp.Parent = parts
end
assert(offset == buffer.len(buf), "data length does not match the parts")
parts.Parent = ServerStorage

-- 2. catalog items ----------------------------------------------------------------------------
local accessories = ServerStorage:FindFirstChild("CustomerAccessories")
if not accessories then
	accessories = Instance.new("Folder")
	accessories.Name = "CustomerAccessories"
	accessories.Parent = ServerStorage
end
local loadErrors = {}
for _, id in CustomerLooks.CatalogAssets() do
	if not accessories:FindFirstChild(tostring(id)) then
		local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
		local acc = ok and model:FindFirstChildWhichIsA("Accessory", true)
		if acc then
			acc:SetAttribute("AssetName", acc.Name)
			acc:SetAttribute("AssetId", id)
			acc.Name = tostring(id)
			acc.Parent = accessories
		else
			table.insert(loadErrors, tostring(id))
		end
	end
end

-- 3. lineup -----------------------------------------------------------------------------------
local origin = CFrame.new(0, 3, 0)
local restaurant = workspace:FindFirstChild("Restaurant")
if restaurant and restaurant:IsA("Model") then
	local cf, size = restaurant:GetBoundingBox()
	origin = CFrame.new(cf.X, cf.Y - size.Y / 2 + 3, cf.Z - size.Z / 2 - 12)
end
local lineup = Instance.new("Folder")
lineup.Name = "CustomerLookPreview"
lineup.Parent = workspace
local summary = {}
for i, seed in SEEDS do
	local look = CustomerLooks.Roll(Random.new(seed))
	local rig = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	rig.Name = string.format("Look_%d_%s", seed, look.sex)
	rig.HumanoidRootPart.Anchored = true
	rig:PivotTo(origin * CFrame.new((i - (#SEEDS + 1) / 2) * 4.5, 0, 0))
	rig.Parent = lineup
	CustomerAppearance.Dress(rig, look, parts, accessories)
	-- stand on the floor
	local lowest = math.huge
	for _, p in rig:GetChildren() do
		if p:IsA("MeshPart") and p:GetAttribute("LookPart") then
			lowest = math.min(lowest, p.Position.Y - p.Size.Y / 2)
		end
	end
	rig:PivotTo(rig:GetPivot() + Vector3.new(0, origin.Y - 3 - lowest, 0))
	local ids = {}
	for _, piece in look.pieces do
		if piece.id ~= "body" and not piece.id:match("^face_") then
			table.insert(ids, piece.id)
		end
	end
	table.insert(summary, string.format("%d %s: %s", seed, look.sex, table.concat(ids, ", ")))
	task.wait()
end
if #loadErrors > 0 then
	table.insert(summary, "LOAD FAILED: " .. table.concat(loadErrors, ", "))
end
return table.concat(summary, "\n")
