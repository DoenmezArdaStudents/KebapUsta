-- Random day events (issue #2): "Schüler haben Mittagspause", football fans, rain, heatwave …
-- The catalog lives in Shared/Events. At the start of every shop day 0–2 events are planned at
-- random times inside their windows (never overlapping). While one runs:
--   * customer demand is multiplied (GameLoopService.EventDemandHook)
--   * a share of the newcomers are event guests with their own personalities, group sizes,
--     patience, takeaway chance, menu and drink preferences and a tip bonus
--     (GameLoopService.EventSpawnHook → CustomerService.Spawn options)
-- ReplicatedStorage attributes EventId / EventUntil (shop hour) drive the client banner
-- (Client/EventUI); start and end are announced to everyone.
-- Admins / the Studio debug hook can start one right away: EventService.Start(id).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Events = require(Shared.Events)
local Net = require(script.Parent.Net)
local RestaurantService = require(script.Parent.RestaurantService)
local GameLoopService = require(script.Parent.GameLoopService)

local EventService = {}

type Planned = { id: string, at: number }
local rng = Random.new()
local plannedDay: number? = nil
local plan: { Planned } = {}
local active: Events.EventDef? = nil
local activeUntil = 0

local function publish()
	ReplicatedStorage:SetAttribute("EventId", active and active.id or nil)
	ReplicatedStorage:SetAttribute("EventUntil", active and activeUntil or nil)
end

local function stop()
	if not active then
		return
	end
	local e = active
	active = nil
	publish()
	Net.NotifyAll("n_event_end", { icon = e.icon, name = e.name }, "info")
end

function EventService.Start(id: string, clock: number?): boolean
	local e = Events.ById[id]
	if not e then
		return false
	end
	if active then
		stop()
	end
	local now = clock or RestaurantService.Clock or Config.Day.StartHour
	active = e
	activeUntil = math.min(Config.Day.EndHour, now + e.duration)
	publish()
	Net.NotifyAll("n_event_start", { icon = e.icon, name = e.name, desc = e.desc }, "event")
	return true
end

function EventService.Active(): Events.EventDef?
	return active
end

local function planDay(day: number)
	plannedDay = day
	table.clear(plan)
	if rng:NextNumber() > Events.ChancePerDay then
		return
	end
	local pool = {}
	for _, e in ipairs(Events.List) do
		if day >= e.minDay then
			table.insert(pool, e)
		end
	end
	local count = rng:NextNumber() < 0.35 and 2 or 1
	for _ = 1, math.min(count, Events.MaxPerDay) do
		local total = 0
		for _, e in ipairs(pool) do
			total += e.weight
		end
		if total <= 0 then
			break
		end
		local roll = rng:NextNumber() * total
		local pick: Events.EventDef? = nil
		for i, e in ipairs(pool) do
			roll -= e.weight
			if roll <= 0 then
				pick = e
				table.remove(pool, i)
				break
			end
		end
		if pick then
			local at = rng:NextNumber(pick.hours[1], pick.hours[2])
			-- no overlap with an already planned event
			local clash = false
			for _, p in ipairs(plan) do
				local o = Events.ById[p.id]
				if at < p.at + o.duration and p.at < at + pick.duration then
					clash = true
				end
			end
			if not clash then
				table.insert(plan, { id = pick.id, at = at })
			end
		end
	end
end

local function tick(clock: number)
	local day = RestaurantService.GetDay()
	if plannedDay ~= day then
		stop()
		planDay(day)
	end
	if active and clock >= activeUntil then
		stop()
	end
	if not active then
		for i, p in ipairs(plan) do
			if clock >= p.at then
				table.remove(plan, i)
				if clock < p.at + Events.ById[p.id].duration then
					EventService.Start(p.id, clock)
				end
				break
			end
		end
	end
end

local function pickWeighted(weights: { [string]: number }): string?
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	local roll = rng:NextNumber() * total
	for k, w in pairs(weights) do
		roll -= w
		if roll <= 0 then
			return k
		end
	end
	return nil
end

-- spawn options for the next newcomer, or nil for a normal guest
local function eventGuest(): any?
	local e = active
	if not e or rng:NextNumber() > (e.share or 1) then
		return nil
	end
	local opts: any = {
		event = e.id,
		patienceMul = e.patience,
		eventTip = e.reward,
		eventOrder = (e.menus or e.drinks) and { menus = e.menus, drinks = e.drinks } or nil,
	}
	if e.takeaway then
		opts.takeaway = rng:NextNumber() < e.takeaway
	end
	if e.personalities then
		opts.personality = pickWeighted(e.personalities)
	end
	if e.group and rng:NextNumber() < e.group then
		local gs = e.groupSize or { 2, 3 }
		opts.groupSize = rng:NextInteger(gs[1], gs[2])
	end
	return opts
end

function EventService.Init()
	GameLoopService.EventTickHook = tick
	GameLoopService.EventDemandHook = function()
		return active and active.demand or 1
	end
	GameLoopService.EventSpawnHook = eventGuest
	publish()
end

return EventService
