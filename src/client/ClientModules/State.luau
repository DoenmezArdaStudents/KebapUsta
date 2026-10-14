-- Client-side mirror of server state (display only – the server is authoritative).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local State = {
	player = nil :: any,
	shop = nil :: any,
	tickets = {} :: { any },
	selected = nil :: { ticket: number, item: number }?,
	lang = "de",
	grillReceivedAt = 0,
}

local changed = Instance.new("BindableEvent")
State.Changed = changed.Event -- (what: "player" | "shop" | "tickets" | "selection")

function State.Fire(what: string)
	changed:Fire(what)
end

function State.Request(action: string, args: any?)
	local ok, res = pcall(function()
		return (Remotes:WaitForChild("Request") :: RemoteFunction):InvokeServer(action, args)
	end)
	if ok then
		return res
	end
	return { ok = false }
end

function State.Remote(name: string): RemoteEvent
	return Remotes:WaitForChild(name) :: RemoteEvent
end

-- the order item the meal panel compares against
function State.SelectedItem()
	if State.selected then
		for _, t in ipairs(State.tickets) do
			if t.id == State.selected.ticket then
				local it = t.items[State.selected.item]
				if it and not it.delivered then
					return it, t
				end
			end
		end
	end
	-- fallback: oldest ticket's first undelivered item
	for _, t in ipairs(State.tickets) do
		for _, it in ipairs(t.items) do
			if not it.delivered then
				return it, t
			end
		end
	end
	return nil, nil
end

function State.Init()
	State.Remote("PlayerState").OnClientEvent:Connect(function(s)
		State.player = s
		State.lang = (s.settings and s.settings.lang) or "de"
		State.grillReceivedAt = os.clock()
		State.Fire("player")
	end)
	State.Remote("ShopState").OnClientEvent:Connect(function(s)
		State.shop = s
		State.Fire("shop")
	end)
	State.Remote("Tickets").OnClientEvent:Connect(function(list)
		State.tickets = list
		State.Fire("tickets")
	end)
	task.spawn(function()
		State.Request("Sync")
	end)
end

return State
