-- Facial moods of NPCs as Dynamic Head FaceControls values (pure data).
-- FaceControls do not replicate: the server only sets the model attribute "Mood",
-- Client/CustomerFaces applies these values on every client.

local MoodFaces = {}

MoodFaces.MOODS = {
	happy = {
		LeftLipCornerPuller = 0.9,
		RightLipCornerPuller = 0.9,
		LeftCheekRaiser = 0.5,
		RightCheekRaiser = 0.5,
		LeftInnerBrowRaiser = 0.4,
		RightInnerBrowRaiser = 0.4,
	},
	neutral = {},
	annoyed = { LeftBrowLowerer = 0.6, RightBrowLowerer = 0.6, Corrugator = 0.5, LeftLipCornerDown = 0.6, RightLipCornerDown = 0.6 },
	angry = {
		LeftBrowLowerer = 1,
		RightBrowLowerer = 1,
		Corrugator = 1,
		LeftLipCornerDown = 0.8,
		RightLipCornerDown = 0.8,
		LeftNoseWrinkler = 0.5,
		RightNoseWrinkler = 0.5,
		LeftUpperLipRaiser = 0.4,
		RightUpperLipRaiser = 0.4,
	},
}

-- every FaceControls property any mood touches; a mood resets the others to 0
local keys = {}
for _, m in pairs(MoodFaces.MOODS) do
	for k in pairs(m) do
		keys[k] = true
	end
end

-- full target values for a mood (unknown moods count as neutral)
function MoodFaces.Goal(mood: string?): { [string]: number }
	local target = MoodFaces.MOODS[mood or "neutral"] or MoodFaces.MOODS.neutral
	local goal = {}
	for k in pairs(keys) do
		goal[k] = target[k] or 0
	end
	return goal
end

return MoodFaces
