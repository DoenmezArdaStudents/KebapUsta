--!nonstrict
-- Central tuning values for Realistic Kebap Simulator.
-- Everything gameplay-relevant lives here so balancing never requires touching service code.

local Config = {}

Config.DataVersion = 2
Config.DataStoreName = "RealisticKebapSim_Player_v1"
Config.AutosaveInterval = 150
Config.CurrencySymbol = "€"
Config.StartingCash = 30

Config.Day = {
	LengthSeconds = 480, -- one in-game day (10:00 - 22:00) in real seconds
	StartHour = 10,
	EndHour = 22,
	ClosingGrace = 40, -- seconds the shop waits for remaining customers after closing
	SummarySeconds = 12,
}

-- Day periods change the customer spawn interval (multiplier < 1 = busier)
Config.Periods = {
	{ from = 10, to = 11.5, key = "period_morning", spawn = 1.2 },
	{ from = 11.5, to = 14, key = "period_lunch", spawn = 0.8, rush = true },
	{ from = 14, to = 17.5, key = "period_quiet", spawn = 1.4 },
	{ from = 17.5, to = 20, key = "period_evening", spawn = 0.85, rush = true },
	{ from = 20, to = 22.01, key = "period_late", spawn = 1.1 },
}

Config.Customers = {
	BaseSpawnInterval = 32,
	MinSpawnInterval = 16,
	MaxWaiting = 4, -- no new customers while this many are already queuing/ordering/waiting
	BaseQueueCapacity = 3,
	MaxPickupSpots = 4,
	WalkSpeed = 10,
	BasePatience = 100,
	QueueDrain = 0.4,
	OrderingDrain = 1.0,
	WaitingDrain = 0.75,
	ImpatientRemarkAt = 0.3,
	EatChance = 0.45,
	EatTimeMin = 12,
	EatTimeMax = 22,
	FirstSpawnDelay = 3,
	MaxPedestrians = 4,
	InteractDistance = 11,
	VIPChance = 0.05,
	GroupChance = 0.05,
	GroupChanceRush = 0.09,
	MoveTimeout = 12,
}

-- Aggressive customers: some arrive in a bad mood, others snap when their patience runs low.
-- They rant at the staff and can be slapped ("Backpfeife"), after which they leave.
Config.Aggro = {
	TurnAt = 0.22, -- patience fraction at which any waiting customer turns aggressive
	RantMin = 6, -- seconds between angry outbursts
	RantMax = 10,
	SlapDistance = 9, -- studs (customers stand across the counter)
	SlapCooldown = 1.2,
}

Config.Prep = {
	BaseCutHold = 0.9,
	CutCost = 0.25,
	MinCutDoneness = 0.45,
	LowHeatRate = 0.05,
	LowHeatCap = 1.3,
	HighHeatRate = 0.11,
	HighHeatCap = 2.6,
	BurntDoneness = 1.9,
	ToastPerfectMin = 3,
	ToastPerfectMax = 8,
	ToastBurnt = 11,
	BaseMeatPortions = 2,
	MaxMeatPortions = 5,
	MaxIngredientPortions = 3,
	ActionCooldown = 0.12,
	PromptDistance = 6,
}

Config.Stock = {
	BaseCapacity = 30,
	MeatCapacity = 40,
}

Config.Economy = {
	RefuseAccuracy = 0.35,
	ExtraMeatPrice = 1.5,
	CheesePrice = 0.8,
	ExtraSaucePrice = 0.3,
	XPBase = 8,
	XPPerStar = 4,
	XPPerfectBonus = 10,
	BaseRent = 8,
	RentPerLevel = 2,
	ReputationStart = 3.0,
	ReputationWeight = 0.08,
}

-- XP needed to go from `level` to `level + 1` (about 4 orders at level 1, ~30 at level 10)
function Config.XPForLevel(level: number): number
	return math.floor(60 + 40 * math.max(level - 1, 0) ^ 1.35)
end

-- Upgrades. `values[tier + 1]` is the effect at the current tier (tier 0 = not purchased).
-- prices[i] / req[i] = cost and required player level for tier i.
Config.Upgrades = {
	sharp_knife = {
		icon = "🔪",
		name = { de = "Scharfes Dönermesser", en = "Sharp Kebab Knife" },
		desc = { de = "Fleisch schneller vom Spieß schneiden.", en = "Carve meat off the spit faster." },
		prices = { 120, 350, 800 },
		req = { 1, 3, 5 },
		values = { 0.9, 0.65, 0.45, 0.3 },
	},
	spit_burner = {
		icon = "🔥",
		name = { de = "Stärkerer Spieß-Brenner", en = "Stronger Spit Burner" },
		desc = { de = "Das Fleisch gart schneller nach.", en = "Meat cooks back faster." },
		prices = { 200, 600 },
		req = { 2, 4 },
		values = { 1, 1.35, 1.7 },
	},
	toaster = {
		needs = "grill",
		icon = "🍞",
		name = { de = "Profi-Kontaktgrill", en = "Pro Contact Grill" },
		desc = { de = "Brot wird schneller getoastet.", en = "Bread toasts faster." },
		prices = { 150, 450 },
		req = { 1, 3 },
		values = { 1, 1.4, 1.8 },
	},
	storage = {
		icon = "🧊",
		name = { de = "Größeres Kühllager", en = "Bigger Cold Storage" },
		desc = { de = "Mehr Zutaten auf Lager.", en = "Store more ingredients." },
		prices = { 180, 500 },
		req = { 2, 4 },
		values = { 1, 1.5, 2 },
	},
	queue = {
		icon = "🧍",
		name = { de = "Mehr Platz an der Theke", en = "Bigger Counter Area" },
		desc = { de = "Mehr Kunden können anstehen.", en = "More customers can queue." },
		prices = { 250, 700 },
		req = { 2, 5 },
		values = { 3, 4, 5 },
	},
	decor = {
		icon = "🪴",
		name = { de = "Gemütliche Einrichtung", en = "Cosy Interior" },
		desc = { de = "Pflanzen, Bilder & Neonschild. Kunden sind geduldiger.", en = "Plants, art & neon sign. Customers are more patient." },
		prices = { 300, 900 },
		req = { 3, 6 },
		values = { 1, 1.12, 1.25 },
	},
	tables = {
		icon = "🪑",
		name = { de = "Zusätzliche Tische", en = "Extra Tables" },
		desc = { de = "Mehr Sitzplätze – mehr Gäste bleiben zum Essen.", en = "More seats – more guests stay to eat." },
		prices = { 350, 800 },
		req = { 3, 6 },
		values = { 0, 1, 2 },
	},
	menu_veggie = {
		icon = "🥗",
		name = { de = "Menü: Veggie-Kebap", en = "Menu: Veggie Kebab" },
		desc = { de = "Neues Gericht für Vegetarier.", en = "New dish for vegetarians." },
		prices = { 300 },
		req = { 2 },
		values = { false, true },
	},
	menu_box = {
		icon = "📦",
		name = { de = "Menü: Kebap-Box", en = "Menu: Kebab Box" },
		desc = { de = "Fleisch, Salat & Sauce in der Box.", en = "Meat, salad & sauce in a box." },
		prices = { 400 },
		req = { 3 },
		values = { false, true },
	},
	delivery = {
		icon = "🚚",
		name = { de = "Express-Lieferant", en = "Express Supplier" },
		desc = { de = "Nachbestellungen kommen schneller an.", en = "Restocks arrive faster." },
		prices = { 150, 400 },
		req = { 1, 3 },
		values = { 25, 12, 4 },
	},
	tray = {
		icon = "🍽️",
		name = { de = "Großes Tablett", en = "Large Tray" },
		desc = { de = "Mehr Gerichte gleichzeitig tragen.", en = "Carry more items at once." },
		prices = { 200, 600 },
		req = { 2, 5 },
		values = { 2, 3, 4 },
	},
	premium = {
		icon = "⭐",
		name = { de = "Premium-Zutaten", en = "Premium Ingredients" },
		desc = { de = "Höhere Preise und mehr Trinkgeld.", en = "Higher prices and bigger tips." },
		prices = { 900 },
		req = { 6 },
		values = { 1, 1.15 },
	},
	lounge = {
		icon = "🛋️",
		name = { de = "Renovierung: Lounge", en = "Renovation: Lounge" },
		desc = { de = "Öffnet einen neuen Lounge-Bereich mit Sofas.", en = "Opens a new lounge area with sofas." },
		prices = { 2500 },
		req = { 8 },
		values = { 0, 1 },
	},
}

-- knives and dishes are bought in the unlock catalog (Shared/Progression); these are optional
-- improvements the player can choose between
Config.UpgradeOrder = {
	"delivery", "toaster", "spit_burner", "storage", "tray",
	"queue", "decor", "tables", "premium", "lounge",
}

function Config.UpgradeValue(upgrades: { [string]: number }?, id: string): any
	local def = Config.Upgrades[id]
	local tier = (upgrades and upgrades[id]) or 0
	tier = math.clamp(tier, 0, #def.prices)
	return def.values[tier + 1]
end

-- Sounds. Only verified Creator Store assets (ProSoundEffects, licensed by Roblox) or
-- built-in rbxasset:// sounds are used. Replace ids here to customise. Empty id = silent.
Config.Sounds = {
	doorbell = { id = "rbxassetid://9125935023", volume = 0.35 },
	ambience = { id = "rbxassetid://9112875348", volume = 0.12, looped = true },
	cut = { id = "rbxasset://sounds/snap.mp3", volume = 0.35 },
	add = { id = "rbxasset://sounds/clickfast.wav", volume = 0.35 },
	sauce = { id = "rbxasset://sounds/clickfast.wav", volume = 0.3 },
	wrap = { id = "rbxasset://sounds/snap.mp3", volume = 0.3 },
	register = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45 },
	success = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5 },
	fail = { id = "rbxasset://sounds/button.wav", volume = 0.6 },
	complain = { id = "rbxasset://sounds/button.wav", volume = 0.5 },
	click = { id = "rbxasset://sounds/clickfast.wav", volume = 0.3 },
	levelup = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6 },
	toast = { id = "rbxasset://sounds/clickfast.wav", volume = 0.3 },
	-- Creator Store audio (loaded and verified in Studio): slap, pain, angry shouts
	slap = { id = "rbxassetid://511340819", volume = 1, pitchVar = 0.08 },
	slap_hit = { id = "rbxassetid://9114758494", volume = 0.5, pitchVar = 0.1 },
	ow = { id = "rbxassetid://107509588243169", volume = 0.8, pitchVar = 0.12 },
	angry1 = { id = "rbxassetid://9125652139", volume = 0.6, pitchVar = 0.15 },
	angry2 = { id = "rbxassetid://9125652956", volume = 0.6, pitchVar = 0.15 },
	angry3 = { id = "rbxassetid://9120416707", volume = 0.55, pitchVar = 0.15 },
	-- meat carving (ProSoundEffects, Creator Store): slice, knife drawn, electric cutter motor
	cut_slice = { id = "rbxassetid://9113833032", volume = 0.35, pitchVar = 0.18 },
	knife_draw = { id = "rbxassetid://9113450094", volume = 0.4 },
	cutter_motor = { id = "rbxassetid://9116980359", volume = 0.35 },
	-- back door (Creator Store, Dino_B9; loaded and verified in Studio)
	door_open = { id = "rbxassetid://7309105153", volume = 0.5, pitchVar = 0.05 },
	door_close = { id = "rbxassetid://7309106429", volume = 0.45, pitchVar = 0.05 },
	-- delivery van (Creator Store; loaded and verified in Studio): engine loop, reverse beeper loop,
	-- air brake, rear cargo doors
	van_engine = { id = "rbxassetid://132909779540049", volume = 0.35 },
	van_beep = { id = "rbxassetid://5471337533", volume = 0.35 },
	van_brake = { id = "rbxassetid://109083794861112", volume = 0.45 },
	van_door_open = { id = "rbxassetid://9112987710", volume = 0.5 },
	van_door_close = { id = "rbxassetid://106783007480793", volume = 0.5 },
}

Config.Achievements = {
	{ id = "first_order", stat = "served", goal = 1, reward = 20, name = { de = "Erster Kunde", en = "First Customer" } },
	{ id = "served_10", stat = "served", goal = 10, reward = 40, name = { de = "Die ersten 10 Kebaps", en = "First 10 Kebabs" } },
	{ id = "first_unlock", stat = "unlocks", goal = 1, reward = 25, name = { de = "Erste Anschaffung", en = "First Purchase" } },
	{ id = "served_100", stat = "served", goal = 100, reward = 300, name = { de = "100 Kunden bedient", en = "100 Customers Served" } },
	{ id = "veal_1", stat = "veal", goal = 1, reward = 80, name = { de = "Erster Kalb-Kebap", en = "First Veal Kebab" } },
	{ id = "unlocks_8", stat = "unlocks", goal = 8, reward = 400, name = { de = "Gut ausgestattet", en = "Well Equipped" } },
	{ id = "served_50", stat = "served", goal = 50, reward = 150, name = { de = "Stammlokal", en = "Local Favourite" } },
	{ id = "served_250", stat = "served", goal = 250, reward = 600, name = { de = "Kebap-Legende", en = "Kebab Legend" } },
	{ id = "perfect_10", stat = "perfect", goal = 10, reward = 100, name = { de = "Perfektionist", en = "Perfectionist" } },
	{ id = "earned_1000", stat = "earned", goal = 1000, reward = 150, name = { de = "Erste Tausend", en = "First Thousand" } },
	{ id = "days_5", stat = "days", goal = 5, reward = 200, name = { de = "Eine Arbeitswoche", en = "A Working Week" } },
	{ id = "satisfied_1000", stat = "satisfied", goal = 1000, reward = 2500, name = { de = "1.000 zufriedene Gäste", en = "1,000 Happy Guests" } },
	{ id = "unlocks_all", stat = "unlocks", goal = 18, reward = 3000, name = { de = "Voll ausgestattete Küche", en = "Fully Equipped Kitchen" } },
	{ id = "earned_100000", stat = "earned", goal = 100000, reward = 10000, name = { de = "€100.000 Umsatz", en = "€100,000 Revenue" } },
	{ id = "first_hire", stat = "hired", goal = 1, reward = 60, name = { de = "Erster Mitarbeiter", en = "First Employee" } },
	{ id = "full_team", stat = "hired", goal = 5, reward = 500, name = { de = "Volles Team", en = "Full Team" } },
	{ id = "first_stage", stat = "expansions", goal = 1, reward = 150, name = { de = "Erster Ausbau", en = "First Expansion" } },
	{ id = "palace", stat = "expansions", goal = 4, reward = 3000, name = { de = "Kebap-Palast", en = "Kebab Palace" } },
	{ id = "clean_50", stat = "cleaned", goal = 50, reward = 120, name = { de = "Putzteufel", en = "Clean Freak" } },
	{ id = "regulars_5", stat = "regulars", goal = 5, reward = 200, name = { de = "5 Stammkunden", en = "5 Regulars" } },
	{ id = "first_branch", stat = "branches", goal = 1, reward = 800, name = { de = "Erste Filiale", en = "First Branch" } },
	{ id = "deliveries_20", stat = "deliveries", goal = 20, reward = 300, name = { de = "Lieferprofi", en = "Delivery Pro" } },
}

return Config
