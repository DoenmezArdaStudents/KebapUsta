-- Remote creation, rate limiting and safe handler wrapping.
-- The client never sends amounts, prices or results – only intents (which station, which customer).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = {}

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end

local EVENTS = {
	"Interact", -- C->S station interaction
	"CustomerAction", -- C->S take order / serve
	"PlayerState", -- S->C private player state
	"ShopState", -- S->C restaurant state (all)
	"Tickets", -- S->C open orders (all)
	"Notify", -- S->C toast message
	"Say", -- S->C customer speech bubble / dialogue
	"Feedback", -- S->C order result popup
	"Sound", -- S->C play a sound
	"DaySummary", -- S->C end of day report
	"Dialogue", -- S->C open dialogue box for the order taker
	"DayPhase", -- S->C "sleep" / "wake" transitions at the end of a day
	"Slap", -- S->C a player slapped an aggressive customer (effects on all clients)
	"Installed", -- S->C an unlock was installed (sparkle effect at the position)
	"CutStroke", -- C->S one knife stroke while cutting (timed and validated on the server)
	"CutFX", -- S->C an accepted stroke: slice + animation for everyone
	"CutResult", -- S->C a finished meat portion (quality) for the cook
	"CutEnd", -- S->C the cutting session ended
	"LobbyState", -- S->C the private lobby the player is in (nil = none)
	"LobbyLoading", -- S->C show / hide the loading screen around a teleport
}

local remotes: { [string]: RemoteEvent } = {}
for _, name in ipairs(EVENTS) do
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	remotes[name] = r
end
local requestFn = folder:FindFirstChild("Request")
if not requestFn then
	requestFn = Instance.new("RemoteFunction")
	requestFn.Name = "Request"
	requestFn.Parent = folder
end

-- token bucket per player per channel
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local LIMITS = {
	Interact = { rate = 10, burst = 16 },
	CustomerAction = { rate = 4, burst = 6 },
	Request = { rate = 4, burst = 8 },
	CutStroke = { rate = 8, burst = 10 },
}

function Net.Allow(player: Player, channel: string): boolean
	local lim = LIMITS[channel] or { rate = 5, burst = 10 }
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local b = pb[channel]
	local now = os.clock()
	if not b then
		b = { tokens = lim.burst, last = now }
		pb[channel] = b
	end
	b.tokens = math.min(lim.burst, b.tokens + (now - b.last) * lim.rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(p)
	buckets[p] = nil
end)

function Net.Fire(name: string, player: Player, ...)
	if player.Parent then
		remotes[name]:FireClient(player, ...)
	end
end

function Net.FireAll(name: string, ...)
	remotes[name]:FireAllClients(...)
end

-- handler(player, ...) wrapped in rate-limit + pcall so one bad request never breaks the loop
function Net.On(name: string, handler: (Player, ...any) -> ())
	remotes[name].OnServerEvent:Connect(function(player, ...)
		if not Net.Allow(player, name) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn("[Net] handler error in", name, err)
		end
	end)
end

local requestHandlers: { [string]: (Player, any) -> any } = {}
function Net.OnRequest(action: string, handler: (Player, any) -> any)
	requestHandlers[action] = handler
end

requestFn.OnServerInvoke = function(player, action, args)
	if type(action) ~= "string" then
		return { ok = false }
	end
	if not Net.Allow(player, "Request") then
		return { ok = false, msg = "n_rate_limited" }
	end
	local h = requestHandlers[action]
	if not h then
		return { ok = false }
	end
	local ok, res = pcall(h, player, args)
	if not ok then
		warn("[Net] request error", action, res)
		return { ok = false }
	end
	return res
end

function Net.Notify(player: Player, key: string, params: { [string]: any }?, kind: string?)
	Net.Fire("Notify", player, key, params, kind or "info")
end

function Net.NotifyAll(key: string, params: { [string]: any }?, kind: string?)
	Net.FireAll("Notify", key, params, kind or "info")
end

function Net.Sound(player: Player?, name: string, position: Vector3?)
	if player then
		Net.Fire("Sound", player, name, position)
	else
		Net.FireAll("Sound", name, position)
	end
end

-- distance check from a player's character to a world position
function Net.Near(player: Player, pos: Vector3, maxDist: number): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return (root.Position - pos).Magnitude <= maxDist
end

return Net
