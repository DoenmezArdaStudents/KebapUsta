-- Cleanliness indicator (issue #13): a small HUD card at the top right with the restaurant's
-- cleanliness, how much waste is lying around and the fill level of the three backyard
-- containers (Server/WasteService state: player.waste, player.clean).

local Players = game:GetService("Players")
local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local WasteUI = {}

local player = Players.LocalPlayer
local card: Frame
local title: TextLabel
local bar: Frame
local info: TextLabel

local function tr(de: string, en: string): string
	return State.lang == "en" and en or de
end

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function refresh()
	local p = State.player
	local w = p and p.waste
	if not w or type(p.clean) ~= "number" or game:GetService("ReplicatedStorage"):GetAttribute("Mode") ~= "game" then
		card.Visible = false
		return
	end
	card.Visible = true
	local clean = math.clamp(p.clean, 0, 1)
	local col = clean > 0.75 and Kit.T.green or (clean > 0.5 and Kit.T.orange or Kit.T.red)
	title.Text = string.format("🧽 %s <font color='%s'><b>%d %%</b></font>", tr("Sauberkeit", "Cleanliness"), hex(col), math.floor(clean * 100 + 0.5))
	bar.Size = UDim2.fromScale(clean, 1)
	bar.BackgroundColor3 = col
	local parts = {}
	local lying = (w.inside or 0) + (w.outside or 0)
	if lying > 0 then
		table.insert(parts, string.format("<font color='%s'>🗑️ %d %s</font>", hex(Kit.T.orange), lying, tr("Müll liegt herum", "waste lying around")))
	end
	local names = { general = tr("Rest", "Gen"), plastic = tr("Plastik", "Plastic"), organic = tr("Bio", "Org") }
	local bins = {}
	for _, id in ipairs({ "general", "plastic", "organic" }) do
		local b = w.bins and w.bins[id]
		if b then
			local full = b.fill >= b.cap
			table.insert(bins, string.format(full and "<font color='%s'><b>%s %d/%d</b></font>" or "%s%s %d/%d", full and hex(Kit.T.red) or "", names[id], b.fill, b.cap))
		end
	end
	table.insert(parts, "♻️ " .. table.concat(bins, "  "))
	if w.truck then
		table.insert(parts, "🚛 " .. tr("Müllabfuhr kommt", "Waste pickup on its way"))
	end
	info.Text = table.concat(parts, "\n")
end

function WasteUI.Init()
	local gui = Kit.new("ScreenGui", { Name = "WasteUI", ResetOnSpawn = false, DisplayOrder = 4, Parent = player:WaitForChild("PlayerGui") })
	card = Kit.glass({ Name = "Clean", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 160), Size = UDim2.fromOffset(230, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Parent = gui }, 12)
	Kit.pad(12, 8, 12, 8).Parent = card
	Kit.list(false, 5).Parent = card
	title = Kit.label({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), Font = Kit.F.medium, TextSize = 14, Text = "", Parent = card })
	local bg
	bg, bar = Kit.bar({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 6), Parent = card }, Kit.T.green)
	info = Kit.label({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = Kit.T.dim, Text = "", Parent = card })
	local _ = bg
	State.Changed:Connect(function(what)
		if what == "player" then
			refresh()
		end
	end)
	game:GetService("ReplicatedStorage"):GetAttributeChangedSignal("Mode"):Connect(refresh)
	refresh()
end

return WasteUI
