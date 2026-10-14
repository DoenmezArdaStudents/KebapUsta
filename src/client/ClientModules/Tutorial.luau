-- Interactive first-time tutorial. Steps are derived from real game state, so they advance as the
-- player actually performs each action. The current target is highlighted in the world.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local OrderLogic = require(Shared.OrderLogic)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local Tutorial = {}

local TOTAL = 8
local highlight: Highlight
local finishedShownAt: number? = nil
local hadTicket = false

local function station(kind: string, item: string?): Instance?
	for _, p in ipairs(CollectionService:GetTagged("Station")) do
		if p:GetAttribute("Station") == kind and (item == nil or p:GetAttribute("Item") == item) then
			return p
		end
	end
	return nil
end

-- a prep board: the given one, otherwise one nobody else works at
local function board(index: any): Instance?
	local me = game:GetService("Players").LocalPlayer.UserId
	local fallback = nil
	for _, p in ipairs(CollectionService:GetTagged("Station")) do
		if p:GetAttribute("Station") == "board" then
			if p:GetAttribute("Board") == index then
				return p
			end
			local user = p:GetAttribute("User")
			if not fallback and (user == nil or user == me) then
				fallback = p
			end
		end
	end
	return fallback or station("board", nil)
end

local function customerInState(state: string): Instance?
	for _, c in ipairs(CollectionService:GetTagged("Customer")) do
		if c:GetAttribute("State") == state then
			return c
		end
	end
	return nil
end

local function setTarget(inst: Instance?)
	if inst and (inst:IsA("BasePart") or inst:IsA("Model")) then
		highlight.Adornee = inst
		highlight.Enabled = true
	else
		highlight.Adornee = nil
		highlight.Enabled = false
	end
end

local function compute(): (number?, string?, Instance?)
	local ps = State.player
	if not ps then
		return nil
	end
	if ps.tutorialDone then
		if finishedShownAt and os.clock() - finishedShownAt < 9 then
			return 8, "tut_8", station("stock_terminal")
		end
		return nil
	end
	local item = State.SelectedItem()
	local meal = ps.meal
	local trayHasMeal = false
	for _, t in ipairs(ps.tray or {}) do
		if t.kind == "meal" then
			trayHasMeal = true
		end
	end
	if trayHasMeal then
		-- the tray stands at the board until you pick it up
		if type(ps.trayAt) == "number" then
			return 7, "tut_7", board(ps.trayAt)
		end
		return 7, "tut_7", customerInState("WaitingForFood")
	end
	if not item then
		if hadTicket then
			return nil
		end
		return 1, "tut_1", customerInState("Ordering") or station("laptop")
	end
	hadTicket = true
	-- order of work (issue #3): meat into the pan → pan and bread onto the board → fill → close → serve
	local need = item.meatPortions or 0
	local inBowl = ps.bowl and #ps.bowl or 0
	local inMeal = meal and OrderLogic.MeatTotal(meal) or 0
	local myBoard = (meal and ps.location == "board" and ps.board) or (type(ps.bowlAt) == "number" and ps.bowlAt) or ps.trayAt
	if inMeal + inBowl < need then
		return 2, "tut_2", station("spit", item.meat == "veal" and "veal" or "chicken")
	end
	if not meal and ps.bowlAt == "hand" then
		return 3, "tut_3", board(myBoard)
	end
	if not meal then
		return 4, "tut_4", station("bread", item.bread)
	end
	if ps.location == "hand" then
		return 4, "tut_4", board(myBoard)
	end
	if inBowl > 0 and inMeal < need then
		return 5, "tut_5", board(myBoard)
	end
	local list = OrderLogic.Checklist(item, meal)
	-- a sauce bottle in the hand: squeeze it on at the board, then back into its dispenser
	if ps.sauce then
		for _, e in ipairs(list) do
			if e.key == "sauce:" .. ps.sauce and e.state ~= "ok" then
				return 5, "tut_5", board(myBoard)
			end
		end
		return 5, "tut_5", station("sauce", ps.sauce)
	end
	for _, e in ipairs(list) do
		if (string.sub(e.key, 1, 4) == "veg:" or string.sub(e.key, 1, 6) == "sauce:") and e.state ~= "ok" then
			local kind = string.sub(e.key, 1, 4) == "veg:" and "veg" or "sauce"
			return 5, "tut_5", station(kind, e.data.id)
		end
	end
	if not meal.closed and meal.bread == "classic" and not ps.lid then
		return 6, "tut_6", station("bread", "classic")
	end
	return 6, "tut_6", board(myBoard)
end

local function refresh()
	local hints = not State.player or State.player.settings == nil or State.player.settings.hints ~= false
	local step, key, target = compute()
	if not hints and step ~= 8 then
		step = nil
	end
	UI.SetTutorial(step, TOTAL, key)
	setTarget(step and target or nil)
end

function Tutorial.Init()
	highlight = Instance.new("Highlight")
	highlight.Name = "TutorialHighlight"
	highlight.FillColor = Color3.fromRGB(255, 210, 80)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.fromRGB(255, 240, 160)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = workspace
	local wasDone = nil
	State.Changed:Connect(function(what)
		if what == "player" and State.player then
			if wasDone == false and State.player.tutorialDone then
				finishedShownAt = os.clock()
			end
			if not State.player.tutorialDone then
				finishedShownAt = nil
				if wasDone == true then
					hadTicket = false -- tutorial replayed
				end
			end
			wasDone = State.player.tutorialDone
		end
		refresh()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
end

return Tutorial
