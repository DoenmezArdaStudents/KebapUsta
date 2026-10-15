-- Delivery van route through the back street into the backyard (pure data + math, no side effects).
-- Server (Server/DeliveryVanService) and every client (Client/DeliveryVan) compute the van's pose
-- from the same phase + elapsed time, so all players see the same smooth movement.
--
-- Phases:  arrive  – drive along the back street (eastbound lane) and brake past the gate
--          truck_arrive / truck_parked / truck_depart – the garbage truck stops on the street at the gate
--          reverse – back in through the gate into the delivery area (rear doors face the back door)
--          parked  – unloading (static)
--          depart  – drive out of the gate and away down the back street
-- Van space: front = -Z (Roblox LookVector), ground at Y = 0.

local VanRoute = {}

local LANE = -56.8 -- eastbound lane of the back street (driving on the right)
local GATE_X = 29
VanRoute.PARK_Z = -37.5 -- van centre when parked (rear face at about z -30.9)
VanRoute.TRUCK_X = 33 -- garbage truck centre when stopped (18 long: rear hopper at x ≈ 24, by the gate)

-- static phases: the end pose of a moving phase
local STATIC = { parked = "reverse", truck_parked = "truck_arrive" }

type Seg = { kind: "line" | "bez", p: { Vector3 } }
type Phase = { segs: { Seg }, reverse: boolean, speed: number, easeIn: boolean, easeOut: boolean, points: { Vector3 }?, dist: { number }?, length: number? }

local function v(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

local PHASES: { [string]: Phase } = {
	arrive = { segs = { { kind = "line", p = { v(-170, LANE), v(41, LANE) } } }, reverse = false, speed = 26, easeIn = false, easeOut = true },
	reverse = {
		segs = {
			{ kind = "bez", p = { v(41, LANE), v(32, LANE), v(GATE_X, -52), v(GATE_X, -46) } },
			{ kind = "line", p = { v(GATE_X, -46), v(GATE_X, VanRoute.PARK_Z) } },
		},
		reverse = true,
		speed = 5.5,
		easeIn = true,
		easeOut = true,
	},
	-- garbage truck (Server/GarbageTruckService): stops on the street with its rear hopper at the gate
	truck_arrive = { segs = { { kind = "line", p = { v(-170, LANE), v(VanRoute.TRUCK_X, LANE) } } }, reverse = false, speed = 20, easeIn = false, easeOut = true },
	truck_depart = { segs = { { kind = "line", p = { v(VanRoute.TRUCK_X, LANE), v(230, LANE) } } }, reverse = false, speed = 14, easeIn = true, easeOut = false },
	depart = {
		segs = {
			{ kind = "line", p = { v(GATE_X, VanRoute.PARK_Z), v(GATE_X, -48) } },
			{ kind = "bez", p = { v(GATE_X, -48), v(GATE_X, -54.5), v(34, LANE), v(42, LANE) } },
			{ kind = "line", p = { v(42, LANE), v(200, LANE) } },
		},
		reverse = false,
		speed = 16,
		easeIn = true,
		easeOut = false,
	},
}

local function bez(p: { Vector3 }, t: number): Vector3
	local u = 1 - t
	return p[1] * (u * u * u) + p[2] * (3 * u * u * t) + p[3] * (3 * u * t * t) + p[4] * (t * t * t)
end

-- sample every phase once into a polyline with cumulative distances
for _, ph in pairs(PHASES) do
	local pts = {}
	for _, s in ipairs(ph.segs) do
		local n = s.kind == "line" and math.max(2, math.ceil((s.p[2] - s.p[1]).Magnitude / 2)) or 40
		for i = (#pts == 0 and 0 or 1), n do
			local t = i / n
			table.insert(pts, s.kind == "line" and s.p[1]:Lerp(s.p[2], t) or bez(s.p, t))
		end
	end
	local dist = { 0 }
	for i = 2, #pts do
		dist[i] = dist[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	ph.points, ph.dist, ph.length = pts, dist, dist[#dist]
end

-- distance travelled as a fraction 0..1 of time, with acceleration / braking at the ends
local function ease(ph: Phase, a: number): number
	a = math.clamp(a, 0, 1)
	if ph.easeIn and ph.easeOut then
		return a * a * (3 - 2 * a)
	elseif ph.easeOut then
		return 1 - (1 - a) * (1 - a)
	elseif ph.easeIn then
		return a * a
	end
	return a
end

-- seconds a phase takes (eased phases need longer for the same average speed)
function VanRoute.Duration(phase: string): number
	local ph = PHASES[phase]
	if not ph then
		return 0
	end
	local factor = (ph.easeIn and ph.easeOut) and 1.5 or ((ph.easeIn or ph.easeOut) and 1.3 or 1)
	return (ph.length :: number) / ph.speed * factor
end

local function sample(ph: Phase, d: number): (Vector3, Vector3)
	local pts, dist = ph.points :: { Vector3 }, ph.dist :: { number }
	d = math.clamp(d, 0, ph.length :: number)
	local i = 2
	while i < #pts and dist[i] < d do
		i += 1
	end
	local a, b = pts[i - 1], pts[i]
	local seg = dist[i] - dist[i - 1]
	local f = seg > 0 and (d - dist[i - 1]) / seg or 0
	return a:Lerp(b, f), (b - a).Unit
end

-- the van's ground pose (CFrame, front = -Z) and speed sign for a phase at `t` seconds in
function VanRoute.Pose(phase: string, t: number): (CFrame, number)
	if STATIC[phase] or not PHASES[phase] then
		local ph = PHASES[STATIC[phase] or "reverse"]
		local pos, dir = sample(ph, ph.length :: number)
		return CFrame.lookAt(pos, pos + (ph.reverse and -dir or dir)), 0
	end
	local ph = PHASES[phase]
	local dur = VanRoute.Duration(phase)
	local a = dur > 0 and t / dur or 1
	local d = ease(ph, a) * (ph.length :: number)
	local pos, dir = sample(ph, d)
	local forward = ph.reverse and -dir or dir
	-- rough current speed for wheel spin / engine pitch (finite difference of the eased curve)
	local d2 = ease(ph, a + 0.01) * (ph.length :: number)
	local speed = a >= 1 and 0 or (d2 - d) / (dur * 0.01) * (ph.reverse and -1 or 1)
	return CFrame.lookAt(pos, pos + forward), speed
end

VanRoute.LANE = LANE
VanRoute.GATE_X = GATE_X
return VanRoute
