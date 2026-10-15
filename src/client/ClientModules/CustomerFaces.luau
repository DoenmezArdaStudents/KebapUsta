-- Customer facial expressions: the server sets the model attribute "Mood" (happy / neutral /
-- annoyed / angry); FaceControls do not replicate, so every client tweens the Dynamic Head locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MoodFaces = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MoodFaces"))

local CustomerFaces = {}

local TWEEN = TweenInfo.new(0.35)

local function apply(model: Instance)
	local head = model:FindFirstChild("Head")
	local fc = head and head:FindFirstChildOfClass("FaceControls")
	if fc then
		TweenService:Create(fc, TWEEN, MoodFaces.Goal(model:GetAttribute("Mood"))):Play()
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("Mood"):Connect(function()
		apply(model)
	end)
	task.spawn(function()
		if model:WaitForChild("Head", 10) then
			apply(model)
		end
	end)
end

function CustomerFaces.Init()
	task.spawn(function()
		local folder = workspace:WaitForChild("Customers")
		folder.ChildAdded:Connect(watch)
		for _, m in ipairs(folder:GetChildren()) do
			watch(m)
		end
	end)
end

return CustomerFaces
