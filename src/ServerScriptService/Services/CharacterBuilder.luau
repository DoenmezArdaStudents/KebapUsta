-- Builds the uniform "Dönermann" StarterCharacter: every player spawns with exactly the same
-- body (same height & proportions) and the same outfit, regardless of their own avatar.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local CharacterBuilder = {}

local SKIN = Color3.fromRGB(222, 176, 138)
local SHIRT = Color3.fromRGB(246, 246, 244)
local PANTS = Color3.fromRGB(34, 34, 38)
local SHOES = Color3.fromRGB(22, 22, 24)
local APRON = Color3.fromRGB(176, 52, 38)
local HAIR = Color3.fromRGB(38, 28, 22)

local function weldPart(rig: Model, attachTo: string, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
	local base = rig:FindFirstChild(attachTo) :: BasePart?
	if not base then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = rig
	return p
end

function CharacterBuilder.Build(): Model
	local desc = Instance.new("HumanoidDescription")
	-- identical proportions for everybody
	desc.HeightScale = 1
	desc.WidthScale = 1
	desc.DepthScale = 1
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	desc.HeadColor = SKIN
	desc.LeftArmColor = SHIRT
	desc.RightArmColor = SHIRT
	desc.TorsoColor = SHIRT
	desc.LeftLegColor = PANTS
	desc.RightLegColor = PANTS
	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	rig.Name = "StarterCharacter"

	-- colours per part: skin hands, white sleeves, black trousers, dark shoes
	for _, p in ipairs(rig:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local n = p.Name
			if n == "Head" or string.find(n, "Hand") then
				p.Color = SKIN
			elseif string.find(n, "Foot") then
				p.Color = SHOES
			elseif string.find(n, "Leg") or n == "LowerTorso" then
				p.Color = PANTS
			else
				p.Color = SHIRT
			end
		end
	end
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end

	-- outfit: white chef cap, short hair, moustache, red apron with straps, name badge
	weldPart(rig, "Head", "ChefCap", Vector3.new(1.28, 0.55, 1.28), CFrame.new(0, 0.62, 0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	weldPart(rig, "Head", "CapBand", Vector3.new(1.3, 0.12, 1.3), CFrame.new(0, 0.38, 0), APRON, Enum.Material.Fabric)
	weldPart(rig, "Head", "HairBack", Vector3.new(1.18, 0.5, 0.25), CFrame.new(0, 0.12, 0.52), HAIR, Enum.Material.Fabric)
	weldPart(rig, "Head", "Moustache", Vector3.new(0.62, 0.12, 0.08), CFrame.new(0, -0.18, -0.6), HAIR, Enum.Material.Fabric)
	local apron = weldPart(rig, "LowerTorso", "Apron", Vector3.new(1.75, 1.9, 0.08), CFrame.new(0, -0.55, -0.55), APRON, Enum.Material.Fabric)
	weldPart(rig, "UpperTorso", "ApronBib", Vector3.new(1.2, 1.0, 0.08), CFrame.new(0, -0.15, -0.53), APRON, Enum.Material.Fabric)
	weldPart(rig, "UpperTorso", "StrapL", Vector3.new(0.14, 0.9, 0.06), CFrame.new(-0.5, 0.55, -0.53), APRON, Enum.Material.Fabric)
	weldPart(rig, "UpperTorso", "StrapR", Vector3.new(0.14, 0.9, 0.06), CFrame.new(0.5, 0.55, -0.53), APRON, Enum.Material.Fabric)
	weldPart(rig, "UpperTorso", "Badge", Vector3.new(0.4, 0.18, 0.05), CFrame.new(0.55, 0.3, -0.53), Color3.fromRGB(240, 200, 70), Enum.Material.Metal)
	if apron then
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 60
		sg.Parent = apron
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0.35, 0)
		t.Position = UDim2.new(0, 0, 0.08, 0)
		t.Text = "KEBAP\nHAUS"
		t.TextColor3 = Color3.fromRGB(255, 255, 255)
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.Parent = sg
	end

	local hum = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.WalkSpeed = 10
	hum.UseJumpPower = true
	hum.JumpPower = 32
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	return rig
end

-- Install/replace StarterPlayer.StarterCharacter and the first-person settings
function CharacterBuilder.Install()
	local old = StarterPlayer:FindFirstChild("StarterCharacter")
	if old then
		old:Destroy()
	end
	local rig = CharacterBuilder.Build()
	rig.Parent = StarterPlayer
	StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	StarterPlayer.LoadCharacterAppearance = false
	StarterPlayer.CharacterWalkSpeed = 10
	StarterPlayer.CharacterUseJumpPower = true
	StarterPlayer.CharacterJumpPower = 32
	return rig
end

return CharacterBuilder
