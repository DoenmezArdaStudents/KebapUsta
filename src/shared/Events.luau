-- Random day events (issue #2), pure data. Server/EventService plans 0–2 of them per day and applies
-- their effects while they run; Client/EventUI shows the banner.
--   hours      window of shop hours the event may start in (it starts at a random time inside)
--   duration   length in shop hours
--   minDay     first day the event can happen
--   weight     relative chance when picking
--   demand     multiplier on customer arrivals (2 = twice as many)
--   group      chance a newcomer is a group, groupSize = { min, max }
--   personalities  weights that replace the normal personality mix for event customers
--   share      fraction of the newcomers that belong to the event (the rest are normal guests)
--   patience   multiplier on patience of event customers
--   takeaway   chance an event customer takes the food away (nil = normal)
--   menus      the event customers order one of these (if on the menu)
--   drinks     drink chance per person (nil = normal)
--   reward     tip bonus for event guests (0.5 = +50 % tip, Server/OrderService)

local Events = {}

export type EventDef = {
	id: string,
	icon: string,
	name: { de: string, en: string },
	desc: { de: string, en: string },
	hours: { number },
	duration: number,
	minDay: number,
	weight: number,
	demand: number,
	group: number?,
	groupSize: { number }?,
	personalities: { [string]: number }?,
	share: number?,
	patience: number?,
	takeaway: number?,
	menus: { string }?,
	drinks: number?,
	reward: number?,
}

Events.List = {
	{
		id = "school_lunch",
		icon = "🎒",
		name = { de = "Schüler haben Mittagspause!", en = "School lunch break!" },
		desc = { de = "Die Schule nebenan hat Pause – viele hungrige Schüler, schnell und günstig.", en = "The school next door is on break – lots of hungry students, quick and cheap." },
		hours = { 11.8, 12.6 },
		duration = 1.5,
		minDay = 2,
		weight = 4,
		demand = 2.2,
		group = 0.45,
		groupSize = { 2, 3 },
		personalities = { bro = 4, funny = 4, impatient = 3, friendly = 2 },
		share = 0.8,
		patience = 0.85,
		takeaway = 0.9,
		menus = { "duerum", "kebap", "box" },
		drinks = 0.6,
		reward = 0.5,
	},
	{
		id = "construction",
		icon = "👷",
		name = { de = "Bauarbeiter machen Pause", en = "Construction crew on break" },
		desc = { de = "Die Baustelle gegenüber hat Frühstückspause – große Portionen, wenig Zeit.", en = "The building site across the street is on break – big portions, little time." },
		hours = { 10.3, 10.8 },
		duration = 1.2,
		minDay = 3,
		weight = 2,
		demand = 1.7,
		group = 0.35,
		groupSize = { 2, 3 },
		personalities = { bro = 4, friendly = 3, impatient = 2 },
		share = 0.7,
		patience = 0.9,
		takeaway = 0.6,
		menus = { "kebap", "box" },
		drinks = 0.7,
		reward = 0.5,
	},
	{
		id = "football",
		icon = "⚽",
		name = { de = "Fußballspiel im Stadion", en = "Football match tonight" },
		desc = { de = "Die Fans kommen vor dem Anpfiff – Gruppen, Getränke, gute Stimmung.", en = "The fans arrive before kick-off – groups, drinks and a great mood." },
		hours = { 17.6, 18.3 },
		duration = 2,
		minDay = 4,
		weight = 2,
		demand = 1.8,
		group = 0.6,
		groupSize = { 2, 3 },
		personalities = { bro = 4, funny = 4, generous = 2, aggressive = 1 },
		share = 0.75,
		patience = 1.0,
		takeaway = 0.5,
		drinks = 1,
		reward = 1,
	},
	{
		id = "rain",
		icon = "🌧️",
		name = { de = "Regenschauer", en = "Rain shower" },
		desc = { de = "Weniger Laufkundschaft – wer kommt, bleibt gern drinnen und hat Zeit.", en = "Fewer passers-by – those who come like to stay inside and take their time." },
		hours = { 13.5, 18 },
		duration = 1.5,
		minDay = 2,
		weight = 2,
		demand = 0.55,
		share = 1,
		patience = 1.3,
		takeaway = 0.2,
	},
	{
		id = "heatwave",
		icon = "☀️",
		name = { de = "Hitzewelle", en = "Heatwave" },
		desc = { de = "Es ist heiß – fast jeder will ein kaltes Getränk dazu.", en = "It's hot – almost everyone wants a cold drink with it." },
		hours = { 13, 15 },
		duration = 2.5,
		minDay = 3,
		weight = 2,
		demand = 1.2,
		share = 1,
		patience = 0.9,
		drinks = 1,
	},
	{
		id = "office",
		icon = "💼",
		name = { de = "Büro bestellt für alle", en = "Office team lunch" },
		desc = { de = "Ein Büro aus der Nachbarschaft kommt im Team – großzügig, aber wählerisch.", en = "A team from a nearby office comes in together – generous but picky." },
		hours = { 14.5, 16 },
		duration = 1,
		minDay = 5,
		weight = 1,
		demand = 1.4,
		group = 0.8,
		groupSize = { 3, 3 },
		personalities = { generous = 4, picky = 3, friendly = 2 },
		share = 0.7,
		patience = 1.1,
		takeaway = 0.3,
		reward = 1.5,
	},
} :: { EventDef }

Events.ById = {} :: { [string]: EventDef }
for _, e in ipairs(Events.List) do
	Events.ById[e.id] = e
end

Events.MaxPerDay = 2
Events.ChancePerDay = 0.75 -- chance that a day has at least one event (from minDay on)

return Events
