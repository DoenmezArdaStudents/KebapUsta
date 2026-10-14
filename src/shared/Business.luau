-- Business catalog shared by server and client: restaurant expansion stages, employee roles,
-- price levels and the candidate generator. Pure data + helpers, no side effects.

local Business = {}

export type Stage = {
	id: number,
	icon: string,
	name: { de: string, en: string },
	desc: { de: string, en: string },
	price: number,
	level: number,
	demand: number, -- customer arrival multiplier
	maxActive: number, -- customers in the shop at once
	delivery: boolean?,
	premium: boolean?,
	vip: number?,
}

Business.Stages = {
	{
		id = 1,
		icon = "🥙",
		name = { de = "Imbiss", en = "Snack bar" },
		desc = { de = "Dein kleiner Döner-Laden – hier fängt alles an.", en = "Your little kebab shop – where it all starts." },
		price = 0,
		level = 1,
		demand = 1,
		maxActive = 10,
	},
	{
		id = 2,
		icon = "☂️",
		name = { de = "Terrasse", en = "Terrace" },
		desc = { de = "3 Tische mit Sonnenschirmen vor dem Laden: 6 Sitzplätze mehr, +10 % Kundschaft.", en = "3 tables with parasols outside: 6 more seats, +10 % customers." },
		price = 1200,
		level = 6,
		demand = 1.1,
		maxActive = 11,
	},
	{
		id = 3,
		icon = "🛵",
		name = { de = "Lieferdienst", en = "Delivery service" },
		desc = { de = "Lieferroller & Abholregal: Telefon-Bestellungen kommen dazu, +10 % Kundschaft.", en = "Scooter & delivery shelf: phone orders come in, +10 % customers." },
		price = 3000,
		level = 9,
		demand = 1.2,
		maxActive = 12,
		delivery = true,
	},
	{
		id = 4,
		icon = "🏮",
		name = { de = "Neue Fassade", en = "New facade" },
		desc = { de = "Markise, Leuchtschrift & Lichterketten: +15 % Kundschaft, Premium-Preise möglich.", en = "Awning, neon lettering & fairy lights: +15 % customers, premium prices possible." },
		price = 6000,
		level = 12,
		demand = 1.35,
		maxActive = 13,
		delivery = true,
		premium = true,
	},
	{
		id = 5,
		icon = "👑",
		name = { de = "Kebap-Palast", en = "Kebab palace" },
		desc = { de = "Goldene Theke, Kronleuchter & VIP-Ecke: +20 % Kundschaft, doppelt so viele VIPs.", en = "Golden counter, chandeliers & VIP corner: +20 % customers, twice the VIPs." },
		price = 12000,
		level = 16,
		demand = 1.55,
		maxActive = 14,
		delivery = true,
		premium = true,
		vip = 2,
	},
} :: { Stage }

export type Role = {
	icon: string,
	name: { de: string, en: string },
	desc: { de: string, en: string },
	level: number,
	hire: number,
	salary: number,
}

Business.Roles = {
	cashier = {
		icon = "🧾",
		name = { de = "Kassierer/in", en = "Cashier" },
		desc = { de = "Steht an der Kasse und nimmt die Bestellungen der Kunden auf.", en = "Works the register and takes customers' orders." },
		level = 5,
		hire = 250,
		salary = 35,
	},
	cleaner = {
		icon = "🧽",
		name = { de = "Reinigungskraft", en = "Cleaner" },
		desc = { de = "Wischt verschüttete Sachen auf und räumt die Tische ab.", en = "Mops up spills and clears the tables." },
		level = 6,
		hire = 200,
		salary = 30,
	},
	cutter = {
		icon = "🔪",
		name = { de = "Dönerschneider/in", en = "Kebab carver" },
		desc = { de = "Regelt die Spieß-Hitze und schneidet Fleisch in die Warmhalte-Wanne vor.", en = "Manages the spit heat and pre-carves meat into the warming pan." },
		level = 8,
		hire = 400,
		salary = 50,
	},
	preparer = {
		icon = "🥬",
		name = { de = "Vorbereiter/in", en = "Prep cook" },
		desc = { de = "Schneidet Gemüse frisch nach – deine Zutaten bleiben knackig.", en = "Chops fresh vegetables – your ingredients stay crisp." },
		level = 10,
		hire = 350,
		salary = 45,
	},
	manager = {
		icon = "📋",
		name = { de = "Schichtleiter/in", en = "Shift manager" },
		desc = { de = "Bestellt knappe Zutaten automatisch nach und treibt das Team an (+15 % Tempo).", en = "Reorders low ingredients automatically and drives the team (+15 % speed)." },
		level = 13,
		hire = 800,
		salary = 80,
	},
} :: { [string]: Role }
Business.RoleOrder = { "cashier", "cleaner", "cutter", "preparer", "manager" }

Business.MaxSkill = 5
function Business.TrainCost(skill: number): number
	return 120 * skill
end

-- price policy: pay multiplier, demand multiplier, mood offset
Business.Prices = {
	cheap = { icon = "🏷️", name = { de = "Günstig", en = "Cheap" }, mul = 0.85, demand = 1.15, mood = 0.05 },
	normal = { icon = "⚖️", name = { de = "Normal", en = "Normal" }, mul = 1, demand = 1, mood = 0 },
	premium = { icon = "💎", name = { de = "Premium", en = "Premium" }, mul = 1.25, demand = 0.88, mood = -0.06, stage = 4 },
}
Business.PriceOrder = { "cheap", "normal", "premium" }

-- shop colour themes (walls, counter front and accents); classic is the original look
Business.Themes = {
	{ id = "classic", icon = "🟥", name = { de = "Klassisch Rot", en = "Classic red" }, color = Color3.fromRGB(176, 52, 38), price = 0 },
	{ id = "ocean", icon = "🟦", name = { de = "Ozeanblau", en = "Ocean blue" }, color = Color3.fromRGB(36, 104, 168), price = 150 },
	{ id = "forest", icon = "🟩", name = { de = "Olivgrün", en = "Olive green" }, color = Color3.fromRGB(78, 118, 62), price = 150 },
	{ id = "royal", icon = "🟪", name = { de = "Königslila", en = "Royal purple" }, color = Color3.fromRGB(106, 58, 150), price = 150 },
	{ id = "sunset", icon = "🟧", name = { de = "Sonnenuntergang", en = "Sunset" }, color = Color3.fromRGB(214, 112, 36), price = 150 },
	{ id = "noir", icon = "⬛", name = { de = "Schwarz & Gold", en = "Black & gold" }, color = Color3.fromRGB(34, 32, 36), price = 400, stage = 5 },
}

-- extra locations: branches run by their own crew and pay out at closing time
Business.Branches = {
	{ id = "bahnhof", icon = "🚉", name = { de = "Imbiss am Bahnhof", en = "Station snack bar" }, price = 8000, level = 12, income = 160 },
	{ id = "strand", icon = "🏖️", name = { de = "Strandbude", en = "Beach shack" }, price = 15000, level = 15, income = 300 },
	{ id = "city", icon = "🏙️", name = { de = "Innenstadt-Filiale", en = "City centre branch" }, price = 30000, level = 20, income = 620 },
}
Business.BranchMaxLevel = 3
function Business.BranchUpgradeCost(price: number, level: number): number
	return math.floor(price * 0.4 * level)
end
-- daily payout: grows with the branch level and the reputation of the brand (your main shop)
function Business.BranchIncome(base: number, level: number, reputation: number): number
	return math.floor(base * (1 + 0.4 * (level - 1)) * (0.5 + reputation / 5) * 100 + 0.5) / 100
end

local FIRST = { "Ali", "Mehmet", "Ayşe", "Elif", "Can", "Lena", "Jonas", "Murat", "Selin", "Tim", "Emre", "Sophie", "Deniz", "Yusuf", "Mia", "Kerem" }

export type Candidate = { role: string, name: string, skill: number, speed: number, rel: number, salary: number, seed: number }

-- a stable set of applicants per role and day (same list on server and client)
function Business.Candidates(role: string, day: number): { Candidate }
	local def = Business.Roles[role]
	local seed = day * 977 + #role * 131 + string.byte(role, 1) * 7
	local rng = Random.new(seed)
	local list = {}
	for i = 1, 3 do
		local skill = rng:NextInteger(1, 3)
		local speed = math.floor(rng:NextNumber(0.85, 1.2) * 100 + 0.5) / 100
		local rel = math.floor(rng:NextNumber(0.75, 0.98) * 100 + 0.5) / 100
		local salary = math.floor(def.salary * (0.75 + skill * 0.15 + (speed - 1) * 0.8 + (rel - 0.85) * 0.8) + 0.5)
		table.insert(list, { role = role, name = FIRST[rng:NextInteger(1, #FIRST)], skill = skill, speed = speed, rel = rel, salary = salary, seed = seed + i })
	end
	return list
end

return Business
