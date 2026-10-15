--[[
	bake_parts.luau – turns the imported npc_builder.py FBX into ServerStorage.CustomerParts.

	After `npc_builder.py --fbx --studio` and a Studio 3D Importer import of out/<npc>.fbx as
	workspace.CustomerPartsImport (Rig Type: No Rig, Merge Meshes off), with the manifest synced to
	ServerStorage.NpcPreviewData.Manifest (temporary Rojo node, see README):
	  * every MeshPart gets the attributes Item / Part / Offset from the manifest (what
	    Server/CustomerAppearance needs) and is shrunk by the import scale (the importer reads the
	    FBX centimetres as studs → 100× too large; MeshPart.Size scales the mesh losslessly)
	  * physics off, SmoothPlastic, npc01 colours as defaults
	  * the parts are merged into ServerStorage.CustomerParts (same name = replaced), so an FBX with
	    only the new items (`--fbx-items`) is enough; the import model is removed
	  * afterwards every part of the manifest must be in the folder
	Then export ServerStorage.CustomerParts to assets/ServerStorage/CustomerParts.rbxm (CLAUDE.md).
]]

local ServerStorage = game:GetService("ServerStorage")

local imp = workspace:FindFirstChild("CustomerPartsImport")
assert(imp, "workspace.CustomerPartsImport missing – import out/<npc>.fbx with that name")
local manifest = require(ServerStorage.NpcPreviewData.Manifest:Clone())
local byName = {}
for _, info in manifest.parts do
	byName[info.name] = info
end

local imported, problems = {}, {}
for _, p in imp:GetDescendants() do
	if p:IsA("MeshPart") then
		if byName[p.Name] then
			table.insert(imported, p)
		else
			table.insert(problems, "not in manifest: " .. p.Name)
		end
	end
end
assert(#imported > 0, "no MeshParts of the manifest in the import")

-- import scale from the largest imported part (manifest `size` = size in studs)
table.sort(imported, function(a, b)
	return a.Size.Magnitude > b.Size.Magnitude
end)
local ref = byName[imported[1].Name].size
local scale = imported[1].Size.Magnitude / Vector3.new(ref[1], ref[2], ref[3]).Magnitude
assert(math.round(scale) >= 1 and math.abs(scale / math.round(scale) - 1) < 0.01, "unexpected import scale " .. scale)
scale = math.round(scale)

local folder = ServerStorage:FindFirstChild("CustomerParts")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "CustomerParts"
	folder.Parent = ServerStorage
end
for _, p in imported do
	local info = byName[p.Name]
	p.Size /= scale
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromHex(info.color)
	pcall(function()
		p.CollisionFidelity = Enum.CollisionFidelity.Box
	end)
	p.CFrame = CFrame.new(info.offset[1], info.offset[2], info.offset[3])
	p:SetAttribute("Item", info.item)
	p:SetAttribute("Part", info.part)
	p:SetAttribute("Offset", Vector3.new(info.offset[1], info.offset[2], info.offset[3]))
	local old = folder:FindFirstChild(p.Name)
	if old then
		old:Destroy()
	end
	p.Parent = folder
end
for name in byName do
	if not folder:FindFirstChild(name) then
		table.insert(problems, "missing in CustomerParts: " .. name)
	end
end
assert(#problems == 0, table.concat(problems, "\n"))

imp:Destroy()
return string.format("CustomerParts: %d new/replaced, %d MeshParts (import scale %d)", #imported, #folder:GetChildren(), scale)
