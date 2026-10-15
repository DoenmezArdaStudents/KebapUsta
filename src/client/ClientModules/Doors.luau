-- Swing doors (tag "SwingDoor"): the server only flips the model's "Open" attribute and the
-- collision; every client animates the leaf locally around the "Hinge" CFrame, so the motion is
-- smooth and the same for everybody (late joiners snap to the current state).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Doors = {}

type Door = { model: Model, leaf: BasePart, closed: CFrame, hinge: CFrame, angle: number, target: number, max: number }
local doors: { [Model]: Door } = {}

local function add(m: Instance)
	if not m:IsA("Model") or doors[m] then
		return
	end
	local leaf = m:WaitForChild("Leaf", 10) :: BasePart?
	local hinge = m:GetAttribute("Hinge")
	if not leaf or typeof(hinge) ~= "CFrame" then
		return
	end
	local max = m:GetAttribute("OpenAngle") or 90
	local d: Door = { model = m, leaf = leaf, closed = leaf.CFrame, hinge = hinge, angle = 0, target = 0, max = max }
	local function sync()
		d.target = m:GetAttribute("Open") and d.max or 0
	end
	sync()
	d.angle = d.target -- late joiners: no swing, just the current state
	m:GetAttributeChangedSignal("Open"):Connect(sync)
	doors[m] = d
end

local function step(dt: number)
	for m, d in pairs(doors) do
		if not m.Parent then
			doors[m] = nil
			continue
		end
		local diff = d.target - d.angle
		if math.abs(diff) > 0.05 or d.leaf:GetAttribute("_set") == nil then
			-- ease-out: fast start, soft stop (like a door closer)
			d.angle += diff * math.min(1, dt * 7)
			d.leaf.CFrame = d.hinge * CFrame.Angles(0, math.rad(d.angle), 0) * d.hinge:Inverse() * d.closed
			d.leaf:SetAttribute("_set", true)
		end
	end
end

function Doors.Init()
	CollectionService:GetInstanceAddedSignal("SwingDoor"):Connect(function(m)
		task.spawn(add, m)
	end)
	for _, m in ipairs(CollectionService:GetTagged("SwingDoor")) do
		task.spawn(add, m)
	end
	RunService.RenderStepped:Connect(step)
end

return Doors
