-- Banner for the running day event (issue #2): a gold chip under the clock, e.g.
-- "🎒 Schüler haben Mittagspause! · bis 13:30". Driven by the ReplicatedStorage attributes
-- EventId / EventUntil (Server/EventService); start/end toasts come from the server notify.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Events)
local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local EventUI = {}

local player = Players.LocalPlayer
local chip: Frame
local text: TextLabel

local function hhmm(h: number): string
	local hh = math.floor(h)
	local mm = math.floor((h - hh) * 60 + 0.5)
	if mm >= 60 then
		hh, mm = hh + 1, 0
	end
	return string.format("%02d:%02d", hh, mm)
end

local function refresh()
	local id = ReplicatedStorage:GetAttribute("EventId")
	local e = type(id) == "string" and Events.ById[id] or nil
	local cutting = player.Character and player.Character:GetAttribute("Cutting") ~= nil
	if not e or ReplicatedStorage:GetAttribute("Mode") ~= "game" then
		chip.Visible = false
		return
	end
	local lang = State.lang == "en" and "en" or "de"
	local untilH = ReplicatedStorage:GetAttribute("EventUntil")
	local tail = typeof(untilH) == "number" and ((lang == "de" and " · bis " or " · until ") .. hhmm(untilH)) or ""
	local wasVisible = chip.Visible
	text.Text = string.format("%s  <b>%s</b>%s", e.icon, e.name[lang], tail)
	chip.Visible = not cutting -- the cutting panel sits in the same spot
	if chip.Visible and not wasVisible then
		Kit.pop(chip, 0.8, 0.35)
	end
end

function EventUI.Init()
	local gui = Kit.new("ScreenGui", { Name = "EventUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, Parent = player:WaitForChild("PlayerGui") })
	chip = Kit.glass({
		Name = "EventChip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(60, 44, 10),
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	}, 17)
	Kit.pad(14, 0, 14, 0).Parent = chip
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Kit.T.gold
		stroke.Transparency = 0.3
	end
	text = Kit.label({ Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Font = Kit.F.medium, TextSize = 15, TextColor3 = Kit.T.gold, Text = "", Parent = chip })
	ReplicatedStorage:GetAttributeChangedSignal("EventId"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("EventUntil"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("Mode"):Connect(refresh)
	State.Changed:Connect(function(what)
		if what == "settings" or what == "player" then
			refresh()
		end
	end)
	local function watch(char: Model)
		char:GetAttributeChangedSignal("Cutting"):Connect(refresh)
	end
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
	refresh()
end

return EventUI
