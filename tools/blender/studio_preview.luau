--[[
	studio_preview.luau – Studio-Test der Blender-Kunden ohne Mesh-Upload (Issue #1).

	Liest ServerStorage.CustomerPreviewData (kommt per `rojo serve tools/blender/studio_preview.project.json`
	aus tools/blender/out/studio/), baut jedes Teil per EditableMesh als MeshPart
	(ServerStorage.CustomerPreviewParts) und stellt die Beispiel-Kunden aus build.py als echte R15-Rigs
	in workspace.CustomerPreviewTest auf: Roblox-Körperteile unsichtbar (Gelenke/Animationen bleiben),
	Blender-Körper und -Kleidung an die Segmente geschweißt, Kopf = Dynamic Head mit Mimik.

	Nur für Studio (Edit-Modus, per MCP execute_luau oder Command Bar): EditableMesh-Inhalte werden
	nicht gespeichert und nicht zu Clients repliziert. Im Spiel kommen die Teile später als
	hochgeladene Meshes (siehe docs/customer-models.md, 4.2).
]]

local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local data = ServerStorage:WaitForChild("CustomerPreviewData", 10)
assert(data, "ServerStorage.CustomerPreviewData fehlt – rojo serve tools/blender/studio_preview.project.json verbinden")
local manifest = require(data:WaitForChild("Manifest"):Clone()) -- Klon: require cached sonst den alten Stand
local chunks = {}
for i = 1, manifest.chunks do
	table.insert(chunks, data.Data:WaitForChild(string.format("Data_%03d", i)).Value)
end
local buf = EncodingService:Base64Decode(buffer.fromstring(table.concat(chunks)))
if manifest.compressed then
	buf = EncodingService:DecompressBuffer(buf, Enum.CompressionAlgorithm.Zstd)
end

-- Teile bauen ------------------------------------------------------------------------------
local old = ServerStorage:FindFirstChild("CustomerPreviewParts")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "CustomerPreviewParts"

local offset = 0
for n, info in manifest.parts do
	local nv, nt = buffer.readu16(buf, offset), buffer.readu16(buf, offset + 2)
	offset += 4
	local em = AssetService:CreateEditableMesh()
	local vids, nids = table.create(nv), table.create(nv)
	for i = 1, nv do
		local p = Vector3.new(buffer.readi16(buf, offset), buffer.readi16(buf, offset + 2), buffer.readi16(buf, offset + 4)) / 2048
		local nrm = Vector3.new(buffer.readi8(buf, offset + 6), buffer.readi8(buf, offset + 7), buffer.readi8(buf, offset + 8)) / 127
		offset += 9
		vids[i] = em:AddVertex(p)
		nids[i] = em:AddNormal(nrm.Magnitude > 0 and nrm.Unit or Vector3.yAxis)
	end
	for _ = 1, nt do
		local a, b, c = buffer.readu16(buf, offset) + 1, buffer.readu16(buf, offset + 2) + 1, buffer.readu16(buf, offset + 4) + 1
		offset += 6
		local f = em:AddTriangle(vids[a], vids[b], vids[c])
		em:SetFaceNormals(f, { nids[a], nids[b], nids[c] })
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	mp.Name = info.name
	mp.Anchored = false
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.Massless = true
	mp.Material = Enum.Material.SmoothPlastic
	mp:SetAttribute("Anchor", info.anchor)
	mp:SetAttribute("Center", Vector3.new(info.center[1], info.center[2], info.center[3]))
	mp.Parent = folder
	if n % 25 == 0 then
		task.wait()
	end
end
assert(offset == buffer.len(buf), "Datenlänge passt nicht")
folder.Parent = ServerStorage

-- Kunden aufstellen ------------------------------------------------------------------------
for _, name in { "CustomerPreviewTest", "MoodTest" } do
	local f = workspace:FindFirstChild(name)
	if f then
		f:Destroy()
	end
end
local test = Instance.new("Folder")
test.Name = "CustomerPreviewTest"
local origin = CFrame.new(0, 3, 0)
local base = workspace:FindFirstChild("Restaurant")
if base and base:IsA("Model") then
	local cf, size = base:GetBoundingBox()
	origin = CFrame.new(cf.X - #manifest.looks * 2.2, cf.Y - size.Y / 2 + 3.006, cf.Z - size.Z / 2 - 12)
end

local MOODS = { "happy", "neutral", "happy", "annoyed", "happy", "neutral", "happy", "happy" }
local FACE = {
	happy = { LeftLipCornerPuller = 0.9, RightLipCornerPuller = 0.9, LeftCheekRaiser = 0.5, RightCheekRaiser = 0.5 },
	annoyed = { LeftBrowLowerer = 0.6, RightBrowLowerer = 0.6, Corrugator = 0.5, LeftLipCornerDown = 0.6, RightLipCornerDown = 0.6 },
	neutral = {},
}

for i, look in manifest.looks do
	local rig = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	rig.Name = string.format("Customer_%s_%s", look.archetype, look.body)
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end
	for _, p in rig:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			if p.Name == "Head" then
				p.Color = Color3.fromHex(look.skin)
			else
				p.Transparency = 1 -- Roblox-Segment bleibt für Gelenke, sichtbar ist das Blender-Mesh
			end
		end
	end
	local hrp = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	hrp.Anchored = true
	rig:PivotTo(origin * CFrame.new((i - 1) * 4.4, 0, 0))
	for _, piece in look.pieces do
		local src = folder:FindFirstChild(piece.name) :: MeshPart?
		if not src then
			warn("Teil fehlt:", piece.name)
			continue
		end
		local seg = rig:FindFirstChild(src:GetAttribute("Anchor")) :: BasePart
		local p = src:Clone()
		p.Color = Color3.fromHex(piece.color)
		p.Transparency = piece.transparency or 0
		p.CFrame = hrp.CFrame * CFrame.new(src:GetAttribute("Center"))
		local w = Instance.new("WeldConstraint")
		w.Part0 = seg
		w.Part1 = p
		w.Parent = p
		p.Parent = rig
	end
	local fc = rig.Head:FindFirstChildOfClass("FaceControls")
	if fc then
		for k, v in FACE[MOODS[i] or "neutral"] do
			fc[k] = v
		end
	end
	rig.Parent = test
	rig:ScaleTo(look.scale)
	task.wait()
end
test.Parent = workspace
return string.format("%d Teile, %d Kunden bei %s", #folder:GetChildren(), #manifest.looks, tostring(origin.Position))
