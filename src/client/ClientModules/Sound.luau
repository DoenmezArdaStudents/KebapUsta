-- Sound playback with volume settings. Missing/blocked assets fail silently.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Sound = {}

local sfxGroup: SoundGroup
local ambGroup: SoundGroup
local templates: { [string]: Sound } = {}
local ambience: Sound?

function Sound.SetVolumes(sfx: number, amb: number)
	if sfxGroup then
		sfxGroup.Volume = sfx
	end
	if ambGroup then
		ambGroup.Volume = amb
	end
end

function Sound.Play(name: string, position: Vector3?)
	local t = templates[name]
	if not t then
		return
	end
	local s = t:Clone()
	local var = t:GetAttribute("PitchVar")
	if typeof(var) == "number" then
		s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * var
	end
	if position then
		local a = Instance.new("Attachment")
		a.WorldPosition = position
		a.Parent = workspace.Terrain
		s.RollOffMaxDistance = 60
		s.RollOffMinDistance = 8
		s.Parent = a
		s:Play()
		Debris:AddItem(a, 6)
	else
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 6)
	end
end

-- looped sound attached to a part (e.g. the electric cutter's motor); caller owns it
function Sound.Attach(name: string, parent: Instance): Sound?
	local t = templates[name]
	if not t then
		return nil
	end
	local s = t:Clone()
	s.Looped = true
	s.SoundGroup = sfxGroup
	s.RollOffMaxDistance = 50
	s.RollOffMinDistance = 6
	s.Parent = parent
	s:Play()
	return s
end

function Sound.Init()
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "KebapSFX"
	sfxGroup.Volume = 0.7
	sfxGroup.Parent = SoundService
	ambGroup = Instance.new("SoundGroup")
	ambGroup.Name = "KebapAmbience"
	ambGroup.Volume = 0.5
	ambGroup.Parent = SoundService
	for name, def in pairs(Config.Sounds) do
		if def.id and def.id ~= "" then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = def.id
			s.Volume = def.volume or 0.5
			s.SoundGroup = def.looped and ambGroup or sfxGroup
			s.Looped = def.looped == true
			if def.pitchVar then
				s:SetAttribute("PitchVar", def.pitchVar)
			end
			templates[name] = s
		end
	end
	local amb = templates.ambience
	if amb then
		ambience = amb:Clone()
		local a = ambience :: Sound
		a.Parent = SoundService
		pcall(function()
			a:Play()
		end)
	end
end

return Sound
