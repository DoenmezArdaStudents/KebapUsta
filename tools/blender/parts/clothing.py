"""
parts/clothing.py – 3D-Kleidung pro Körpersegment, für Mann (m) und Frau (w).

Jedes Kleidungsstück besteht aus mehreren Teilen (Rumpf, Ärmel, Hosenbeine, Schuhe, Knöpfe …),
jedes an sein R15-Segment geschweißt (`anchor`), damit es beim Laufen mitgeht. Die Formen kommen aus
parts/body.py; Details sind echte Geometrie (Bündchen, Kragen, Taschen, Nähte, Knopfleisten).
Farben setzt das Spiel (colorSlot): top = Oberteil, outer = Jacke/Strickjacke, bottom = Hose/Rock,
shoes = Schuhe, accent = Krawatte/Streifen; feste Farben für Knöpfe, Sohlen, Kordeln.
"""

import math

import customer_creator as cc
from customer_creator import BACK, FRONT, smoothstep
from parts import body as B

TAU = 2 * math.pi
UPPER_ARMS = ("RightUpperArm", "LeftUpperArm")
LOWER_ARMS = ("RightLowerArm", "LeftLowerArm")
UPPER_LEGS = ("RightUpperLeg", "LeftUpperLeg")
LOWER_LEGS = ("RightLowerLeg", "LeftLowerLeg")
FEET = ("RightFoot", "LeftFoot")

_ext = {}


def torso(body):
	"""Rumpf bis über die Hüfte (Oberteile reichen über den Hosenbund)."""
	if body not in _ext:
		ut = [r for r in B.SHAPES[body]["UpperTorso"] if r["h"] > -0.5]
		lt = [dict(r, a=r["a"] + 0.01, b=r["b"] + 0.01) for r in B.SHAPES[body]["LowerTorso"] if -1.1 <= r["h"] <= -0.6]
		_ext[body] = cc.Profile(lt + ut)
	return _ext[body]


def neck_h(body):
	return 1.07 if body == "m" else 1.06


def hem_band(h, h_end, width, up=True):
	"""1 im Bündchen-Bereich (Breite width ab h_end), sonst 0 – weich auslaufend."""
	if up:
		return 1 - smoothstep(h_end + width * 0.8, h_end + width, h)
	return smoothstep(h_end - width, h_end - width * 0.8, h)


def flare(h):
	"""Oberteile weiten sich unten, damit sie über den Hosenbund fallen."""
	return 0.11 * (1 - smoothstep(-0.95, -0.30, h))


def rib(u, count, depth=0.006):
	return depth * (0.5 + 0.5 * math.cos(count * u))


def piece(ob, seg, suffix=None, color=None):
	return cc.tag(ob, suffix=suffix or seg, anchor=seg, color=color)


def sleeves(body, lower, gap, thick, cuff=None, short_h=None, nu=20):
	"""
	Ärmel. short_h: Saumhöhe kurzer Ärmel (sonst lang bis zum Ellbogen). lower = (h0, h1) für den
	Unterarm-Ärmel. cuff = (Breite, Zusatzdicke, Rippen) für Bündchen/Manschette.
	Am Ellbogen schiebt sich der untere Ärmel unter den oberen – keine Stufe.
	"""
	objs = []
	for seg in UPPER_ARMS:
		prof = B.profile(body, seg)
		h0 = short_h if short_h is not None else -0.12

		top = prof.h1

		def g_up(h, u, top=top):
			cap = 1 - 0.55 * smoothstep(top - 0.30, top, h)  # Schulterkappe anliegend statt ballig
			elbow = 0 if short_h is not None else 0.02 * (1 - smoothstep(-0.12, 0.02, h))
			return gap * cap - elbow

		def t_up(h, u, top=top):
			return thick * (1 - 0.3 * smoothstep(top - 0.25, top, h))

		parts = [cc.capped_shell("tmp", prof, h0, prof.h1, g_up, t_up, nu=nu)]
		if short_h is not None:
			parts.append(cc.ring_line("tmp", prof, h0 + 0.035, gap + thick - 0.008, 0.03, n=24))
		objs.append(piece(cc.join("tmp", parts), seg))
	if lower:
		for seg in LOWER_ARMS:
			prof = B.profile(body, seg)

			def t_lo(h, u):
				if not cuff:
					return thick
				w, extra, ribs = cuff
				return thick + hem_band(h, lower[0], w) * (extra + (rib(u, ribs) if ribs else 0))

			def g_lo(h, u):
				tuck = 0.03 * smoothstep(lower[1] - 0.15, lower[1], h)
				narrow = 0.01 * hem_band(h, lower[0], cuff[0]) if cuff and cuff[2] else 0
				return gap - tuck - narrow

			objs.append(piece(cc.garment("tmp", prof, lower[0], lower[1], g_lo, t_lo, nu=nu), seg))
	return objs


# ---------------------------------------------------------------------------
# Oberteile
# ---------------------------------------------------------------------------
@cc.part("tshirt", "top", "top", variants="AB", per_body=True, max_tris=3200)
def tshirt(variant, body):
	"""T-Shirt mit Rundhals (Frau: U-Ausschnitt), Saum, kurzen Ärmeln. B: Ringer-Shirt mit Kontrastbündchen."""
	prof = torso(body)
	nh = neck_h(body)
	scoop = 0.0 if body == "m" else 0.12

	def top_h(u):
		return nh - scoop * max(0.0, -math.sin(u)) ** 2

	def thick(h, u):
		return 0.035 + 0.012 * hem_band(h, -0.84, 0.07)

	def gap(h, u):
		return 0.025 + flare(h)

	objs = [piece(cc.garment("tmp", prof, -0.84, top_h, gap, thick, nu=32), "UpperTorso")]
	collar = cc.sweep(
		"tmp", [cc.rbx(*prof.point(top_h(u) - 0.012, u, 0.045)) for u in [TAU * i / 40 for i in range(40)]], 0.032, segments=6, closed=True
	)
	short_h = 0.42 if body == "m" else 0.55
	arms = sleeves(body, None, 0.025, 0.035, short_h=short_h)
	if variant == "A":
		objs[0] = piece(cc.join("tmp", [objs[0], collar]), "UpperTorso")
		return objs + arms
	# Ringer: Kragen und Ärmelbündchen in Akzentfarbe
	cuffs = []
	for seg in UPPER_ARMS:
		p = B.profile(body, seg)
		cuffs.append(piece(cc.ring_line("tmp", p, short_h + 0.02, 0.07, 0.035, n=24), seg, seg + "Cuff", "accent"))
	return objs + arms + [piece(collar, "UpperTorso", "Collar", "accent")] + cuffs


@cc.part("hoodie", "top", "top", variants="AB", per_body=True, max_tris=4400)
def hoodie(variant, body):
	"""Kapuzenpulli: Bauchtasche, Kapuze auf dem Rücken, Kordeln, Rippbündchen. B: mit Reißverschluss."""
	prof = torso(body)
	nh = neck_h(body)

	def thick(h, u):
		band = hem_band(h, -0.86, 0.14)
		return 0.05 + band * (0.02 + rib(u, 48))

	def gap(h, u):
		return 0.04 + flare(h) - 0.02 * hem_band(h, -0.86, 0.14)

	outer = lambda h, u: gap(h, u) + thick(h, u)  # noqa: E731
	main = cc.garment("tmp", prof, -0.86, nh, gap, thick, nu=36)
	w0, w1 = 0.95 if body == "m" else 0.85, 0.62 if body == "m" else 0.55
	pocket = cc.patch(
		"tmp", prof, -0.66, -0.20, 0, 0, outer, 0.03, nu=10, nv=6,
		urange=lambda h: (FRONT - cc.lerp(w0, w1, (h + 0.66) / 0.46), FRONT + cc.lerp(w0, w1, (h + 0.66) / 0.46)),
	)
	hood = cc.patch(
		"tmp", prof, 0.40, nh + 0.01, BACK - 1.25, BACK + 1.25, lambda h, u: 0.09,
		lambda h, u: 0.05 + 0.13 * math.sin(math.pi * min(1, max(0, (u - BACK + 1.25) / 2.5))) * math.sin(math.pi * min(1, (h - 0.40) / 0.75)) ** 0.6,
		nu=14, nv=8,
	)
	rim = cc.sweep("tmp", [cc.rbx(*prof.point(nh - 0.01, u, 0.10)) for u in [TAU * i / 36 for i in range(36)]], 0.085, segments=8, closed=True)
	objs = [piece(cc.join("tmp", [main, pocket, hood, rim]), "UpperTorso")]
	strings = []
	for side in (-1, 1):
		u = FRONT + side * 0.20
		top, bot = nh - 0.04, nh - 0.42
		strings.append(cc.line("tmp", prof, [(top, u), ((top + bot) / 2, u + side * 0.02), (bot, u + side * 0.03)], 0.12, 0.022))
		p = cc.rbx(*prof.point(bot, u + side * 0.03, 0.12))
		strings.append(cc.cylinder("tmp", p, p - cc.Vector((0, 0, 0.09)), 0.03, segments=8, bevel=0.008))
	objs.append(piece(cc.join("tmp", strings), "UpperTorso", "Cords", "fixed:#f2f2f2"))
	if variant == "B":
		zip_line = cc.line("tmp", prof, [(h, FRONT) for h in (nh - 0.02, 0.4, -0.2, -0.84)], 0.105, 0.018)
		objs.append(piece(zip_line, "UpperTorso", "Zip", "fixed:#c8c8cc"))
	objs += sleeves(body, (-0.76, 0.17), 0.035, 0.045, cuff=(0.12, 0.02, 24))
	return objs


@cc.part("shirt", "top", "top", variants="AB", per_body=True, max_tris=3800)
def shirt(variant, body):
	"""Hemd/Bluse: Kragen, Knopfleiste, Brusttasche, Manschetten. A: langarm, in die Hose gesteckt; B: kurzarm."""
	prof = torso(body)
	nh = neck_h(body)
	tucked = variant == "A"
	h0 = -0.78 if tucked else -0.84

	def tuck(h):
		return 1 - smoothstep(-0.78, -0.50, h) if tucked else 0.0  # verschwindet im Hosenbund

	def gap(h, u):
		return 0.02 - 0.015 * tuck(h) + (0 if tucked else flare(h))

	def thick(h, u):
		return 0.03 - 0.012 * tuck(h) + (0 if tucked else 0.01 * hem_band(h, h0, 0.06))

	outer = lambda h, u: gap(h, u) + thick(h, u)  # noqa: E731
	parts = [cc.garment("tmp", prof, h0, nh, gap, thick, nu=34)]
	# Kragensteg rund um den Hals + zwei Kragenspitzen
	parts.append(cc.patch("tmp", prof, nh - 0.03, nh + 0.08, FRONT + 0.14, FRONT + TAU - 0.14, 0.035, 0.035, nu=24, nv=3))
	for side in (-1, 1):
		lo, hi = nh - 0.24, nh + 0.02

		def ur(h, side=side, lo=lo, hi=hi):
			k = (h - lo) / (hi - lo)
			a, b = 0.08, cc.lerp(0.30, 0.78, k)
			return (FRONT + a, FRONT + b) if side > 0 else (FRONT - b, FRONT - a)

		parts.append(cc.patch("tmp", prof, lo, hi, 0, 0, lambda h, u: outer(h, u) + 0.004, 0.028, nu=6, nv=5, urange=ur))
	parts.append(cc.patch("tmp", prof, h0 + 0.02, nh - 0.12, FRONT - 0.07, FRONT + 0.07, outer, 0.014, nu=2, nv=12))
	if body == "m":
		parts.append(cc.patch("tmp", prof, 0.28, 0.62, FRONT - 0.64, FRONT - 0.26, outer, 0.016, nu=4, nv=4))
	objs = [piece(cc.join("tmp", parts), "UpperTorso")]
	buttons = [cc.button("tmp", prof, h, FRONT, outer(h, FRONT) + 0.014, 0.032, 0.018) for h in (0.82, 0.55, 0.28, 0.01, -0.26, -0.53)]
	objs.append(piece(cc.join("tmp", buttons), "UpperTorso", "Buttons", "fixed:#f4f4f2"))
	if variant == "A":
		objs += sleeves(body, (-0.70, 0.17), 0.02, 0.03, cuff=(0.14, 0.015, 0))
	else:
		objs += sleeves(body, None, 0.02, 0.03, short_h=0.40 if body == "m" else 0.52)
	return objs


@cc.part("tie", "accessory", "accent", per_body=True, bodies=("m",), max_tris=600)
def tie(variant, body):
	"""Krawatte über dem Hemd (Knoten + Blatt mit Spitze)."""
	prof = torso(body)
	nh = neck_h(body)
	off = 0.06
	knot = cc.patch("tmp", prof, nh - 0.13, nh + 0.02, FRONT - 0.13, FRONT + 0.13, off, 0.06, nu=4, nv=3)

	def ur(h):
		k = (h + 0.48) / (nh - 0.13 + 0.48)
		w = 0.20 * smoothstep(0.0, 0.12, k) * (1 - 0.35 * k)
		return FRONT - w - 0.005, FRONT + w + 0.005

	blade = cc.patch("tmp", prof, -0.48, nh - 0.11, 0, 0, lambda h, u: off + 0.012, 0.022, nu=4, nv=12, urange=ur)
	return piece(cc.join("tmp", [knot, blade]), "UpperTorso", "Tie")


def open_front(width, edge=None):
	"""u-Bereich einer vorne offenen Jacke: width(h) = halber Öffnungswinkel."""

	def ur(h):
		w = width(h)
		return FRONT + w, FRONT + TAU - w

	return ur


@cc.part("blazer", "outer", "outer", per_body=True, max_tris=4000)
def blazer(variant, body):
	"""Sakko/Blazer: offen, Revers, Kragen, Knopf, Pattentaschen, Ärmel über dem Hemd."""
	prof = torso(body)
	nh = neck_h(body)
	hem = -1.0 if body == "m" else -0.92
	btn = 0.22 if body == "m" else 0.30

	def width(h):
		if h >= btn:
			return cc.lerp(0.17, 0.92, smoothstep(btn, nh, h) ** 0.8)
		return 0.15 + (btn - h) * 0.32

	def gap(h, u):
		return 0.065 + flare(h) * 0.9

	thick = 0.045
	outer = lambda h, u: gap(h, u) + thick  # noqa: E731
	parts = [cc.garment("tmp", prof, hem, nh, gap, thick, nu=36, urange=open_front(width))]
	# Revers: auf die Vorderkanten geklappt
	for side in (-1, 1):

		def ur(h, side=side):
			k = (h - btn) / (nh - btn)
			lw = 0.03 + 0.30 * math.sin(math.pi * min(1, max(0, k))) ** 0.7
			w = width(h)
			return (FRONT + w, FRONT + w + lw) if side > 0 else (FRONT - w - lw, FRONT - w)

		parts.append(cc.patch("tmp", prof, btn, nh - 0.04, 0, 0, lambda h, u: outer(h, u) - 0.005, 0.03, nu=4, nv=8, urange=ur))
	parts.append(cc.patch("tmp", prof, nh - 0.08, nh + 0.08, FRONT + 0.95, FRONT + TAU - 0.95, 0.10, 0.045, nu=16, nv=3))
	for side in (-1, 1):
		u0, u1 = (FRONT + 0.55, FRONT + 1.10) if side > 0 else (FRONT - 1.10, FRONT - 0.55)
		parts.append(cc.patch("tmp", prof, -0.60, -0.50, u0, u1, outer, 0.02, nu=4, nv=2))
	parts.append(cc.patch("tmp", prof, 0.42, 0.47, FRONT - 0.78, FRONT - 0.42, outer, 0.015, nu=3, nv=1))
	objs = [piece(cc.join("tmp", parts), "UpperTorso")]
	b = cc.button("tmp", prof, btn - 0.03, FRONT + width(btn) - 0.02, outer(btn, FRONT) + 0.005, 0.04, 0.02)
	objs.append(piece(b, "UpperTorso", "Buttons", "fixed:#1c1c1e"))
	objs += sleeves(body, (-0.60, 0.17), 0.045, 0.035, nu=22)
	return objs


@cc.part("cardigan", "outer", "outer", per_body=True, max_tris=4000)
def cardigan(variant, body):
	"""Strickjacke: V-Ausschnitt, Knopfleiste, Rippbündchen, aufgesetzte Taschen."""
	prof = torso(body)
	nh = neck_h(body)
	v = -0.05

	def width(h):
		return 0.07 if h < v else cc.lerp(0.07, 0.85, smoothstep(v, nh, h) ** 0.9)

	def gap(h, u):
		return 0.06 + flare(h)

	def thick(h, u):
		band = hem_band(h, -0.86, 0.13)
		return 0.045 + band * (0.015 + rib(u, 60)) + 0.003 * math.cos(70 * u)

	outer = lambda h, u: gap(h, u) + thick(h, u)  # noqa: E731
	parts = [cc.garment("tmp", prof, -0.86, nh, gap, thick, nu=40, urange=open_front(width))]
	for side in (-1, 1):

		def ur(h, side=side):
			w = width(h)
			return (FRONT + w, FRONT + w + 0.11) if side > 0 else (FRONT - w - 0.11, FRONT - w)

		parts.append(cc.patch("tmp", prof, -0.86, nh - 0.02, 0, 0, lambda h, u: outer(h, u) - 0.01, 0.025, nu=2, nv=14, urange=ur))
		u0, u1 = (FRONT + 0.45, FRONT + 0.95) if side > 0 else (FRONT - 0.95, FRONT - 0.45)
		parts.append(cc.patch("tmp", prof, -0.66, -0.30, u0, u1, outer, 0.022, nu=4, nv=4))
	objs = [piece(cc.join("tmp", parts), "UpperTorso")]
	buttons = [cc.button("tmp", prof, h, FRONT + 0.12, outer(h, FRONT) + 0.025, 0.035, 0.02) for h in (-0.12, -0.36, -0.60)]
	objs.append(piece(cc.join("tmp", buttons), "UpperTorso", "Buttons", "fixed:#3a2a20"))
	objs += sleeves(body, (-0.74, 0.17), 0.05, 0.04, cuff=(0.14, 0.015, 30))
	return objs


# ---------------------------------------------------------------------------
# Hosen & Röcke
# ---------------------------------------------------------------------------
def pants_legs(body, gap_up, gap_lo, thick, hem=None, crease=False, seam=True, nu=22):
	"""Hosenbeine; hem = (Breite, Zusatzdicke, Rippen, enger) für Umschlag/Bündchen."""
	objs = []
	for seg in UPPER_LEGS:
		prof = B.profile(body, seg)
		def g_up(h, u):
			return gap_up - 0.015 * (1 - smoothstep(-1.92, -1.78, h))

		parts = [cc.garment("tmp", prof, -1.92, -0.80, g_up, thick, nu=nu)]
		o = gap_up + thick
		if seam:
			parts.append(cc.line("tmp", prof, [(h, prof.outer_u) for h in (-0.80, -1.30, -1.88)], o, 0.012, segments=5))
		if crease:
			parts.append(cc.line("tmp", prof, [(h, FRONT) for h in (-0.95, -1.40, -1.88)], o - 0.004, 0.012, segments=5))
		objs.append(piece(cc.join("tmp", parts), seg))
	for seg in LOWER_LEGS:
		prof = B.profile(body, seg)

		def g(h, u):
			wide = gap_lo(h) if callable(gap_lo) else gap_lo
			if hem and hem[3]:
				wide -= hem[3] * hem_band(h, -2.86, hem[0])
			return cc.lerp(wide, 0.02, smoothstep(-1.90, -1.76, h))  # oben unter das Oberschenkelteil

		def t(h, u):
			if not hem:
				return thick
			w, extra, ribs, _ = hem
			return thick + hem_band(h, -2.86, w) * (extra + (rib(u, ribs) if ribs else 0))

		parts = [cc.garment("tmp", prof, -2.86, -1.72, g, t, nu=nu)]
		o = lambda h: g(h, 0) + thick  # noqa: E731
		if seam:
			parts.append(cc.line("tmp", prof, [(h, prof.outer_u) for h in (-1.90, -2.30, -2.80)], o(-2.3), 0.012, segments=5))
		if crease:
			parts.append(cc.line("tmp", prof, [(h, FRONT) for h in (-1.90, -2.30, -2.80)], o(-2.3) - 0.004, 0.012, segments=5))
		objs.append(piece(cc.join("tmp", parts), seg))
	return objs


def waist(body, gap, thick, band=0.14, loops=True, elastic=False):
	"""Hüftteil der Hose mit Bund (und Gürtelschlaufen)."""
	prof = B.profile(body, "LowerTorso")

	def t(h, u):
		b = hem_band(h, -0.60, band, up=False)
		return thick + b * (0.015 + (rib(u, 60, 0.008) if elastic else 0))

	parts = [cc.garment("tmp", prof, -1.18, -0.60, gap, t, nu=40)]
	o = gap + thick + 0.015
	if loops:
		for u in (FRONT - 0.75, FRONT + 0.75, BACK - 0.65, BACK + 0.65, BACK):
			parts.append(cc.patch("tmp", prof, -0.75, -0.59, u - 0.035, u + 0.035, o - 0.004, 0.016, nu=1, nv=2))
	return prof, parts, o


@cc.part("jeans", "bottom", "bottom", variants="AB", per_body=True, max_tris=2400)
def jeans(variant, body):
	"""Jeans: Bund mit Schlaufen, Knopf, Hosenschlitz, Taschen, Ziernähte, Seitennähte. B: Umschlag unten."""
	gap, thick = 0.03, 0.035
	prof, parts, o = waist(body, gap, thick)
	for side in (-1, 1):  # Gesäßtaschen
		u0, u1 = (BACK + 0.20, BACK + 0.72) if side > 0 else (BACK - 0.72, BACK - 0.20)
		parts.append(cc.patch("tmp", prof, -1.00, -0.72, 0, 0, gap + thick, 0.02, nu=4, nv=3,
			urange=lambda h, u0=u0, u1=u1: (u0 + 0.06 * (1 - (h + 1.0) / 0.28), u1 - 0.06 * (1 - (h + 1.0) / 0.28))))
	objs = [piece(cc.join("tmp", parts), "LowerTorso")]
	stitch = [cc.line("tmp", prof, [(-0.74, FRONT + 0.06), (-0.86, FRONT + 0.06), (-0.95, FRONT - 0.02)], gap + thick + 0.002, 0.011, segments=5)]
	for side in (-1, 1):
		u = FRONT + side * 0.55
		stitch.append(cc.line("tmp", prof, [(-0.72, u), (-0.79, u + side * 0.22), (-0.84, u + side * 0.45)], gap + thick + 0.002, 0.011, segments=5))
	stitch.append(cc.button("tmp", prof, -0.66, FRONT, o + 0.002, 0.035, 0.02))
	for side in (-1, 1):  # Gesäßtaschen: Kontur + Ziernaht
		u0, u1 = (BACK + 0.20, BACK + 0.72) if side > 0 else (BACK - 0.72, BACK - 0.20)
		m = (u0 + u1) / 2
		o2 = gap + thick + 0.021
		outline = [(-0.72, u0), (-0.95, u0 + 0.05), (-1.00, m), (-0.95, u1 - 0.05), (-0.72, u1)]
		stitch.append(cc.line("tmp", prof, outline, o2, 0.01, segments=4))
		stitch.append(cc.line("tmp", prof, [(-0.80, u0 + 0.08), (-0.88, m), (-0.80, u1 - 0.08)], o2, 0.01, segments=4))
	objs.append(piece(cc.join("tmp", stitch), "LowerTorso", "Stitch", "fixed:#c9954c"))

	def gap_lo(h):
		return 0.045 + 0.03 * (1 - smoothstep(-2.85, -2.2, h))

	hem = (0.14, 0.04, 0, 0) if variant == "B" else (0.05, 0.008, 0, 0)
	objs += pants_legs(body, 0.045, gap_lo, thick, hem=hem)
	return objs


@cc.part("trousers", "bottom", "bottom", per_body=True, max_tris=2400)
def trousers(variant, body):
	"""Stoff-/Anzughose: Bügelfalte, schräge Eingrifftaschen, Paspeltaschen hinten."""
	gap, thick = 0.03, 0.03
	prof, parts, o = waist(body, gap, thick, band=0.12)
	for side in (-1, 1):
		u = FRONT + side * 0.60
		parts.append(cc.line("tmp", prof, [(-0.70, u), (-0.88, u + side * 0.30)], gap + thick, 0.012, segments=5))
		u0, u1 = (BACK + 0.25, BACK + 0.65) if side > 0 else (BACK - 0.65, BACK - 0.25)
		parts.append(cc.patch("tmp", prof, -0.76, -0.72, u0, u1, gap + thick, 0.012, nu=3, nv=1))
	objs = [piece(cc.join("tmp", parts), "LowerTorso")]
	objs += pants_legs(body, 0.05, lambda h: 0.05 + 0.015 * (1 - smoothstep(-2.85, -2.2, h)), thick, crease=True, seam=False)
	return objs


@cc.part("joggers", "bottom", "bottom", variants="AB", per_body=True, max_tris=2400)
def joggers(variant, body):
	"""Jogginghose: Gummibund mit Kordel, weite Beine, Rippbündchen am Knöchel. B: Seitenstreifen."""
	gap, thick = 0.04, 0.035
	prof, parts, o = waist(body, gap, thick, band=0.16, loops=False, elastic=True)
	objs = [piece(cc.join("tmp", parts), "LowerTorso")]
	cord = []
	for side in (-1, 1):
		u = FRONT + side * 0.10
		cord.append(cc.line("tmp", prof, [(-0.64, u), (-0.76, u + side * 0.03), (-0.88, u + side * 0.05)], o, 0.02))
	objs.append(piece(cc.join("tmp", cord), "LowerTorso", "Cords", "fixed:#f2f2f2"))
	objs += pants_legs(body, 0.06, lambda h: 0.06 - 0.015 * (1 - smoothstep(-2.85, -2.3, h)), thick, hem=(0.18, 0.02, 30, 0.035), seam=False)
	if variant == "B":
		for seg in UPPER_LEGS + LOWER_LEGS:
			p = B.profile(body, seg)
			hs = (-0.78, -1.3, -1.9) if "Upper" in seg else (-1.75, -2.3, -2.66)
			for k in (-0.07, 0.07):
				objs.append(piece(cc.line("tmp", p, [(h, p.outer_u + k) for h in hs], 0.105, 0.02, segments=5), seg, seg + "Stripe" + ("A" if k < 0 else "B"), "accent"))
	return objs


@cc.part("skirt", "bottom", "bottom", variants="AB", per_body=True, bodies=("w",), max_tris=2400)
def skirt(variant, body):
	"""Knielanger Rock (A-Linie). B: plissiert."""
	lt = B.SHAPES[body]["LowerTorso"]
	rings = [dict(r) for r in lt if r["h"] >= -1.0] + [
		{"h": -1.30, "a": 1.00, "b": 0.62},
		{"h": -1.72, "a": 1.10, "b": 0.72},
	]
	prof = cc.Profile(rings)
	pleat = variant == "B"

	def gap(h, u):
		k = 1 - smoothstep(-1.72, -0.9, h)
		return 0.03 + (0.035 * abs(math.sin(9 * u)) * k if pleat else 0)

	def thick(h, u):
		return 0.035 + 0.012 * hem_band(h, -1.72, 0.06) + 0.02 * hem_band(h, -0.52, 0.12, up=False)

	main = cc.garment("tmp", prof, -1.72, -0.52, gap, thick, nu=54 if pleat else 36, nv=10)
	return [piece(main, "LowerTorso", "Skirt")]


@cc.part("belt", "accessory", "fixed:#3b2618", per_body=True, max_tris=800)
def belt(variant, body):
	"""Ledergürtel mit Metallschnalle (über dem Hosenbund)."""
	prof = B.profile(body, "LowerTorso")
	strap = cc.garment("tmp", prof, -0.71, -0.615, 0.095, 0.02, nu=40, nv=2)
	p = cc.on_surface(prof, -0.66, FRONT, 0.12)
	buckle = cc.rounded_box("tmp", (0.20, 0.03, 0.12), p, radius=0.02, segments=2)
	return [piece(strap, "LowerTorso", "Strap"), piece(buckle, "LowerTorso", "Buckle", "fixed:#c9c9cf")]


# ---------------------------------------------------------------------------
# Schuhe
# ---------------------------------------------------------------------------
def shoe_profile(body, seg, style):
	"""Schuh-Querschnitte entlang der Fußachse (z, vorne negativ)."""
	foot = B.profile(body, seg)
	cx = foot.at(0)["cx"]
	k = 1.0 if body == "m" else 0.9
	if style == "sneaker":
		spec = [(0.33, 0.20, 0.14, -2.85), (0.22, 0.25, 0.19, -2.82), (0.00, 0.28, 0.19, -2.83), (-0.25, 0.29, 0.15, -2.86),
			(-0.45, 0.26, 0.11, -2.89), (-0.60, 0.19, 0.08, -2.91), (-0.67, 0.08, 0.05, -2.92)]
	else:  # Lederschuh
		spec = [(0.31, 0.18, 0.12, -2.87), (0.20, 0.23, 0.16, -2.85), (0.00, 0.25, 0.15, -2.87), (-0.25, 0.25, 0.12, -2.90),
			(-0.47, 0.20, 0.08, -2.925), (-0.63, 0.12, 0.05, -2.94), (-0.69, 0.05, 0.03, -2.95)]
	return [{"h": z * k, "a": a * k, "b": b, "cx": cx, "cy": cy} for z, a, b, cy in spec]


@cc.part("sneakers", "shoes", "shoes", variants="AB", per_body=True, max_tris=1600)
def sneakers(variant, body):
	"""Sneaker: Obermaterial, Sohle mit Kante, Schnürsenkel, Fersenlasche. B: Akzent-Ferse."""
	objs = []
	for seg in FEET:
		rings = shoe_profile(body, seg, "sneaker")
		if seg.startswith("Left"):
			rings = [dict(r, cx=-abs(r["cx"])) for r in rings]
		up = cc.Profile(rings, axis="z")
		upper = cc.solid("tmp", up, nu=24, sharp_angle=None)
		sole_rings = [dict(r, a=r["a"] + 0.025, b=0.05, cy=-2.958) for r in rings]
		sole_rings[0]["h"] += 0.02
		sole_rings[-1]["h"] -= 0.025
		sole = cc.solid("tmp", cc.Profile(sole_rings, axis="z"), nu=24, sharp_angle=45)
		laces = []
		for z in (-0.06, -0.16, -0.26, -0.36):
			zz = z * (1.0 if body == "m" else 0.9)
			a = up.point(zz, FRONT - 0.55, 0.005)
			b = up.point(zz, FRONT + 0.55, 0.005)
			mid = up.point(zz, FRONT, 0.02)
			laces.append(cc.sweep("tmp", [cc.rbx(*a), cc.rbx(*mid), cc.rbx(*b)], 0.022, segments=5))
		objs.append(piece(upper, seg, seg))
		objs.append(piece(cc.join("tmp", [sole] + laces), seg, seg + "Sole", "fixed:#f4f4f2"))
		if variant == "B":
			heel = cc.patch("tmp", up, 0.10, 0.34, BACK - 1.6, BACK + 1.6, 0.0, 0.025, nu=10, nv=4)
			objs.append(piece(heel, seg, seg + "Heel", "accent"))
	return objs


@cc.part("dress_shoes", "shoes", "shoes", per_body=True, max_tris=1200)
def dress_shoes(variant, body):
	"""Lederschuhe: schlankes Obermaterial, dünne Sohle mit Absatz, Ziernaht."""
	objs = []
	for seg in FEET:
		rings = shoe_profile(body, seg, "dress")
		if seg.startswith("Left"):
			rings = [dict(r, cx=-abs(r["cx"])) for r in rings]
		up = cc.Profile(rings, axis="z")
		upper = cc.join("tmp", [cc.solid("tmp", up, nu=24), cc.line("tmp", up, [(z, FRONT + s) for z, s in ((-0.40, -0.9), (-0.47, 0), (-0.40, 0.9))], 0.004, 0.012, segments=5)])
		sole_rings = [dict(r, a=r["a"] + 0.015, b=0.025, cy=-2.985) for r in rings]
		sole = cc.solid("tmp", cc.Profile(sole_rings, axis="z"), nu=20, sharp_angle=40)
		cx = rings[0]["cx"]
		heel = cc.rounded_box("tmp", (0.36, 0.20, 0.07), cc.rbx(cx, -2.97, 0.22), radius=0.02, segments=2)
		objs.append(piece(upper, seg, seg))
		objs.append(piece(cc.join("tmp", [sole, heel]), seg, seg + "Sole", "fixed:#2b1d14"))
	return objs
