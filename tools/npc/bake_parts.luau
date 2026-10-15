--[[
	bake_parts.luau – turns the imported npc_builder.py FBX into ServerStorage.CustomerParts.

	After `npc_builder.py --fbx --studio` and a Studio 3D Importer import of out/<npc>.fbx as
	workspace.CustomerPartsImport (Rig Type: No Rig, Merge Meshes off), with the manifest synced to
	ServerStorage.NpcPreviewData.Manifest (temporary Rojo node, see README):
	  * every MeshPart gets the attributes Item / Part / Offset from the manifest (what
	    Server/CustomerAppearance needs) and is shrunk by the import scale (the importer reads the
	    FBX centimetres as studs → 100× too large; MeshPart.Size scales the mesh losslessly)
	  * physics off, SmoothPlastic, npc01 colours as defaults
	  * the folder replaces ServerStorage.CustomerParts, the import model is removed
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

-- import scale from the head (1.18 studs high in the builder)
local head = imp:FindFirstChild("Body_Head", true) :: MeshPart
assert(head, "Body_Head missing in the import")
local scale = head.Size.Y / 1.2216796875
assert(math.round(scale) >= 1 and math.abs(scale / math.round(scale) - 1) < 0.01, "unexpected import scale " .. scale)
scale = math.round(scale)

local folder = Instance.new("Folder")
folder.Name = "CustomerParts"
local seen, problems = {}, {}
for _, p in imp:GetDescendants() do
	if not p:IsA("MeshPart") then
		continue
	end
	local info = byName[p.Name]
	if not info then
		table.insert(problems, "not in manifest: " .. p.Name)
		continue
	end
	seen[p.Name] = true
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
	p.Parent = folder
end
for name in byName do
	if not seen[name] then
		table.insert(problems, "missing in import: " .. name)
	end
end
assert(#problems == 0, table.concat(problems, "\n"))

local old = ServerStorage:FindFirstChild("CustomerParts")
if old then
	old:Destroy()
end
folder.Parent = ServerStorage
imp:Destroy()
return string.format("CustomerParts: %d MeshParts (import scale %d)", #folder:GetChildren(), scale)
