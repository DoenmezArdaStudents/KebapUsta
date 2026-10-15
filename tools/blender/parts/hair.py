"""
parts/hair.py – Frisuren, Bärte und Kopfbedeckungen für den Roblox Dynamic Head.

Alles sitzt auf der Kopfform aus customer_creator (Superellipsoid wie der Dynamic Head). Vorne
bleibt die Stirn unter HAIRLINE_MIN frei (Augen auf +0.27), Bärte bleiben unter dem Mund – die Mimik
(FaceControls) bleibt so immer sichtbar. build.py prüft das bei jedem Build.
"""

import math
import random

import customer_creator as cc
from customer_creator import HEAD_C, HEAD_HH, HEAD_RX, HEAD_RY, frontness, smoothstep
from mathutils import Vector

TAU = 2 * math.pi
HF = -math.pi / 2  # u-Winkel des Kopfes, der nach vorne zeigt


def du_front(u):
	"""Winkelabstand von vorne (0 … π)."""
	d = (u - HF) % TAU
	return min(d, TAU - d)


def side_of(u):
	"""+1 = rechte Kopfseite (Roblox +X), −1 = linke."""
	return 1 if math.cos(u) < 0 else -1  # Blender-X ist gespiegelt


def cut3(front, side, back, front_w=0.55):
	"""Unterkante: vorne front (Stirn), seitlich side, hinten back – weich verbunden."""

	def cut(u):
		f = frontness(u)
		if f >= 0:
			k = smoothstep(0.0, 1.0, f) ** front_w
			return side + (front - side) * k
		return side + (back - side) * smoothstep(0.0, 1.0, -f)

	return cut


def bumps(seed, count, amp, radius, t_min=0.0):
	"""Zufällige runde Beulen (Locken, Strähnen-Büschel) als bulge(u, t)."""
	rng = random.Random(seed)
	pts = [(rng.uniform(0, TAU), rng.uniform(t_min, 1.0), amp * rng.uniform(0.6, 1.0)) for _ in range(count)]

	def bulge(u, t):
		total = 0.0
		for pu, pt, a in pts:
			d = (u - pu + math.pi) % TAU - math.pi
			w = math.cos(math.pi / 2 * t) + 0.25  # oben liegen die u-Linien enger beisammen
			total += a * math.exp(-((d * w) ** 2 + (t - pt) ** 2) / radius**2)
		return min(total, amp * 1.3)

	return bulge


def strands(count, depth, t0=0.0):
	"""Feine Strähnen-Rillen längs (zum Scheitel hin auslaufend)."""

	def f(u, t):
		return depth * (0.5 + 0.5 * math.cos(count * u)) * (1 - t) * (t >= t0)

	return f


def fringe(cut, count, depth, sharp=True, width=0.5):
	"""Pony aus Strähnenspitzen; bleibt über HAIRLINE_MIN."""

	def fn(u):
		f = frontness(u)
		w = smoothstep(width, 1.0, f)
		x = u * count / TAU * 2
		wave = abs((x % 1.0) * 2 - 1) if sharp else abs(math.sin(math.pi * x))
		return max(cc.HAIRLINE_MIN + 0.005, cut(u) - depth * w * (1 - wave))

	return fn


def hair_curtain(name, u0, u1, z_top, z_bottom, thick, rx=0.66, ry=0.68, nu=26, nv=10, flare=0.08, ribs=14):
	"""
	Lange Haare, die vom Kopf herabfallen. z_bottom(u) = Unterkante (relativ zur Kopfmitte).
	Oben folgt die Fläche dem Kopf, darunter fällt sie senkrecht mit leichter Ausstellung.
	"""

	def fn(su, sv, off):
		u = cc.lerp(u0, u1, su)
		z = cc.lerp(z_top, z_bottom(u), sv)
		if z > -0.25:
			p = cc.head_offset(u, cc.phi_at(min(z, HEAD_HH * 0.98)), 0.03 + off)
		else:
			k = (-0.25 - z) / 0.9
			r = 1 + flare * min(k, 1.0)
			base = cc.head_offset(u, cc.phi_at(-0.25), 0.03 + off)
			d = Vector((base.x - HEAD_C.x, base.y - HEAD_C.y, 0)) * r
			p = Vector((HEAD_C.x + d.x, HEAD_C.y + d.y, HEAD_C.z + z))
		return cc.to_rbx(p)

	def outer(su, sv):
		u = cc.lerp(u0, u1, su)
		return thick * (0.75 + 0.25 * math.cos(ribs * u)) * (1 - 0.5 * sv**3) + 0.01

	return cc.slab(name, fn, nu, nv, lambda su, sv: 0.0, outer, sharp_angle=70)


def lock(name, pts, r0, r1, segments=8):
	"""Einzelne Strähne (verjüngt), pts in Blender-Koordinaten."""
	n = len(pts)
	tube = cc.sweep(name, pts, lambda i: cc.lerp(r0, r1, i / (n - 1)), segments=segments)
	tip = cc.sphere(name + "_tip", pts[-1], r1 * 1.05, segments=8, rings=5)
	return cc.join(name, [tube, tip])


def side_point(x_sign, z, y_off=0.0, out=0.06):
	"""Punkt seitlich am Kopf (Blender), x_sign Roblox-Seite."""
	return Vector((-x_sign * (HEAD_RX + out), HEAD_C.y + y_off, HEAD_C.z + z))


# ---------------------------------------------------------------------------
# Kurze Frisuren
# ---------------------------------------------------------------------------
@cc.part("hair_crop", "hair", "hair", variants="AB", attach="HairAttachment", max_tris=2400)
def hair_crop(variant, body):
	"""Moderner Kurzhaarschnitt: kurze Seiten (Fade), strukturiertes Deckhaar. B: hochgestylte Tolle."""
	cut = fringe(cut3(0.47, 0.10, -0.26), 14, 0.05)
	tex = bumps(11 if variant == "A" else 12, 26, 0.035, 0.12, t_min=0.35)

	def thick(u, t):
		top = smoothstep(0.15, 0.6, t)
		quiff = 0.10 * smoothstep(0.3, 1.0, frontness(u)) * math.sin(math.pi * min(1, t * 1.2)) if variant == "B" else 0
		return 0.03 + 0.11 * top + quiff

	return cc.head_shell("tmp", cut, thick, nu=56, nv=12, bulge=lambda u, t: tex(u, t) * smoothstep(0.25, 0.6, t))


@cc.part("hair_sidepart", "hair", "hair", attach="HairAttachment", max_tris=2400)
def hair_sidepart(variant, body):
	"""Klassischer Seitenscheitel: Scheitel links, Volumen nach rechts gekämmt."""
	cut = cut3(0.48, 0.08, -0.28)
	part_u = HF + 0.62  # Scheitel auf der linken Kopfseite

	def thick(u, t):
		d = (u - part_u + math.pi) % TAU - math.pi
		groove = 0.05 * math.exp(-(d * 6) ** 2) * smoothstep(0.3, 0.7, t)
		swept = 0.05 * smoothstep(0.0, 1.0, -d) * smoothstep(0.2, 0.8, t) * smoothstep(-0.2, 0.8, frontness(u))
		return 0.04 + 0.08 * smoothstep(0.1, 0.6, t) + swept - groove

	return cc.head_shell("tmp", cut, thick, nu=56, nv=12, bulge=strands(28, 0.012))


@cc.part("hair_curly_top", "hair", "hair", attach="HairAttachment", max_tris=2600)
def hair_curly_top(variant, body):
	"""Locken oben, kurze Seiten."""
	cut = cut3(0.46, 0.08, -0.24)
	curls = bumps(21, 46, 0.07, 0.10, t_min=0.3)

	def thick(u, t):
		return 0.03 + 0.12 * smoothstep(0.2, 0.55, t)

	return cc.head_shell("tmp", cut, thick, nu=60, nv=13, bulge=lambda u, t: curls(u, t) * smoothstep(0.25, 0.5, t))


@cc.part("hair_buzz", "hair", "hair", attach="HairAttachment", under_hat=True, max_tris=1200)
def hair_buzz(variant, body):
	"""Buzzcut – passt auch unter Kappe und Mütze."""
	return cc.head_shell("tmp", cut3(0.47, 0.06, -0.24), lambda u, t: 0.028, gap=0.01, nu=36, nv=8)


@cc.part("hair_receding", "hair", "hair", attach="HairAttachment", under_hat=True, max_tris=1600)
def hair_receding(variant, body):
	"""Haarkranz (Glatze oben) – für ältere Herren."""

	def thick(su, sv):
		edge = math.sin(math.pi * su) ** 0.4
		return (0.07 * (1 - sv**2) + 0.01) * edge

	return cc.head_patch("tmp", HF + 1.0, HF + TAU - 1.0, lambda u: -0.14, lambda u: 0.30 - 0.06 * (frontness(u) + 1), thick, nu=32, nv=6)


# ---------------------------------------------------------------------------
# Lange Frisuren
# ---------------------------------------------------------------------------
def center_part_cap(cut, top=0.10, nu=56, nv=12):
	"""Kopfhaube mit Mittelscheitel."""

	def thick(u, t):
		d = min(du_front(u), math.pi - du_front(u))  # Abstand zur Vorne-hinten-Linie
		groove = 0.03 * math.exp(-(d * 5) ** 2) * smoothstep(0.55, 0.9, t)
		return 0.05 + top * smoothstep(0.1, 0.7, t) - groove

	return cc.head_shell("tmp", cut, thick, nu=nu, nv=nv, bulge=strands(36, 0.015))


def face_cut(front, side, back, open_w=0.58, edge_w=0.22):
	"""Unterkante mit Gesichtsöffnung: vorne front (Pony), außerhalb des Gesichts tief (side/back)."""

	def cut(u):
		d = du_front(u)
		if d < open_w:
			return front
		k = smoothstep(open_w, open_w + edge_w, d)
		low = side + (back - side) * smoothstep(math.pi / 2, math.pi, d)
		return cc.lerp(front, low, k)

	return cut


def framing_shell(cut, volume=0.10, top=0.08, part_line=True, nu=64, nv=14, curls=None):
	"""Haube bis unter die Ohrenhöhe, unten voluminös und gerade fallend (Bob, lange Haare)."""

	def thick(u, t):
		d = min(du_front(u), math.pi - du_front(u))
		groove = 0.03 * math.exp(-(d * 5) ** 2) * smoothstep(0.55, 0.9, t) if part_line else 0
		return 0.05 + top * smoothstep(0.1, 0.7, t) - groove

	def bulge(u, t):
		face = 1 - smoothstep(0.45, 0.75, du_front(u))  # über der Stirn kein Bausch
		b = volume * (1 - t) ** 2 * (1 - face) + 0.015 * (0.5 + 0.5 * math.cos(36 * u)) * (1 - t)
		return b + (curls(u, t) if curls else 0)

	return cc.head_shell("tmp", cut, thick, nu=nu, nv=nv, bulge=bulge)


@cc.part("hair_long", "hair", "hair", variants="AB", attach="HairAttachment", max_tris=3600)
def hair_long(variant, body):
	"""Lange Haare mit Mittelscheitel: rahmen das Gesicht, fallen hinten über den Rücken. B: gewellt."""
	cap = framing_shell(face_cut(0.47, -0.48, -0.52), volume=0.12)
	wavy = variant == "B"
	u0, u1 = HF + math.pi - 1.3, HF + math.pi + 1.3  # Rückseite

	def fn(su, sv, off):
		u = cc.lerp(u0, u1, su)
		back = smoothstep(0.0, 1.0, -frontness(u))
		z_bot = cc.lerp(-0.72, -1.38, back) - (0.05 * abs(math.sin(6 * u)) if wavy else 0.04 * abs(math.sin(9 * u)))
		z = cc.lerp(-0.30, z_bot, sv)
		top = cc.head_offset(u, cc.phi_at(-0.30), 0.10 + off)
		k = smoothstep(0.0, 1.0, sv)
		x = (top.x - HEAD_C.x) * (1 + 0.15 * k)
		y = max(top.y - HEAD_C.y, cc.lerp(top.y - HEAD_C.y, 0.66, k)) + off * k
		wave = 0.03 * math.sin(10 * sv + 3 * u) if wavy else 0
		return cc.to_rbx(Vector((HEAD_C.x + x + wave, HEAD_C.y + y, HEAD_C.z + z)))

	def outer(su, sv):
		u = cc.lerp(u0, u1, su)
		return 0.09 * (0.75 + 0.25 * math.cos((10 if wavy else 16) * u)) * (1 - 0.5 * sv**3) + 0.01

	curtain = cc.slab("tmp", fn, 28, 10, lambda su, sv: 0.0, outer, sharp_angle=70)
	return cc.join("tmp", [cap, curtain])


@cc.part("hair_bob", "hair", "hair", attach="HairAttachment", max_tris=2800)
def hair_bob(variant, body):
	"""Kinnlanger Bob mit geradem, dichtem Pony."""
	return framing_shell(face_cut(0.43, -0.46, -0.48, open_w=0.56, edge_w=0.18), volume=0.11, top=0.07, part_line=False)


@cc.part("hair_ponytail", "hair", "hair", attach="HairAttachment", under_hat=True, max_tris=2400)
def hair_ponytail(variant, body):
	"""Zurückgekämmt mit Pferdeschwanz und Haargummi."""
	cap = cc.head_shell("tmp", cut3(0.47, 0.0, -0.42), lambda u, t: 0.04 + 0.03 * t, nu=48, nv=10, bulge=strands(40, 0.012))
	base = HEAD_C + Vector((0, HEAD_RY + 0.06, 0.12))
	pts = [base, base + Vector((0, 0.16, -0.12)), base + Vector((0, 0.20, -0.42)), base + Vector((0, 0.14, -0.78)), base + Vector((0, 0.08, -1.0))]
	tail = cc.sweep("tmp", pts, lambda i: (0.14, 0.19, 0.17, 0.11, 0.04)[i], segments=12)
	tie = cc.torus("tmp", base + Vector((0, 0.03, 0.0)), 0.12, 0.04, axis="Y", segments=14, ring_segments=6)
	tie.rotation_euler.x = math.radians(90)
	return [cc.join("tmp", [cap, tail]), cc.tag(tie, suffix="Tie", color="fixed:#1d1d22")]


@cc.part("hair_bun", "hair", "hair", attach="HairAttachment", max_tris=2400)
def hair_bun(variant, body):
	"""Hochgesteckter Dutt am Hinterkopf."""
	cap = cc.head_shell("tmp", cut3(0.47, 0.0, -0.42), lambda u, t: 0.04 + 0.03 * t, nu=48, nv=10, bulge=strands(40, 0.012))
	c = HEAD_C + Vector((0, 0.38, 0.55))
	bun = cc.sphere("tmp", c, 0.25, scale=(1.05, 0.95, 0.85), segments=18, rings=10)
	wrap = cc.torus("tmp", c + Vector((0, 0.0, 0.02)), 0.21, 0.06, axis="Z", segments=18, ring_segments=6)
	return cc.join("tmp", [cap, bun, wrap])


@cc.part("hair_curly_long", "hair", "hair", attach="HairAttachment", max_tris=3000)
def hair_curly_long(variant, body):
	"""Voluminöse Locken bis zum Kinn."""
	cut = cut3(0.46, -0.32, -0.55, front_w=0.35)
	curls = bumps(31, 70, 0.08, 0.09)

	def thick(u, t):
		return 0.10 + 0.08 * smoothstep(0.0, 0.6, t)

	def safe_cut(u):
		# seitlich am Gesicht nicht unter die Augen in den Gesichtsbereich
		return max(cut(u), 0.47 if du_front(u) < 0.62 else -1)

	return cc.head_shell("tmp", safe_cut, thick, nu=64, nv=13, bulge=curls)


@cc.part("hair_perm", "hair", "hair", attach="HairAttachment", max_tris=2600)
def hair_perm(variant, body):
	"""Kurze Dauerwelle – typisch für ältere Damen."""
	cut = cut3(0.47, 0.0, -0.26)
	curls = bumps(41, 50, 0.06, 0.10)
	return cc.head_shell("tmp", cut, lambda u, t: 0.07 + 0.07 * smoothstep(0.0, 0.6, t), nu=60, nv=12, bulge=curls)


# ---------------------------------------------------------------------------
# Bärte (bleiben unter dem Mund, damit die Mimik sichtbar ist)
# ---------------------------------------------------------------------------
def beard_top(u):
	d = du_front(u)
	low = cc.MOUTH_Y - cc.MOUTH_CLEAR - 0.04
	return cc.lerp(low, 0.02, smoothstep(0.45, 1.15, d))


@cc.part("beard_full", "beard", "hair", attach="FaceFrontAttachment", max_tris=1600)
def beard_full(variant, body):
	"""Vollbart mit schmalen Koteletten (Mund bleibt frei)."""

	def thick(su, sv):
		edge = math.sin(math.pi * su) ** 0.35
		chin = 0.5 + 0.5 * math.cos(math.pi * (su - 0.5) * 2) ** 2
		return (0.03 + 0.05 * chin) * (1 - sv**2) * edge + 0.004

	return cc.head_patch("tmp", HF - 1.38, HF + 1.38, lambda u: -0.585, beard_top, thick, nu=30, nv=8)


@cc.part("beard_stubble", "beard", "mix:hair:skin:0.45", attach="FaceFrontAttachment", max_tris=1000)
def beard_stubble(variant, body):
	"""Drei-Tage-Bart: dünne Schicht in Bartform, Farbe zwischen Haar und Haut."""
	return cc.head_patch("tmp", HF - 1.32, HF + 1.32, lambda u: -0.585, beard_top, lambda su, sv: 0.010 * math.sin(math.pi * su) ** 0.2, gap=0.006, nu=26, nv=6)


# ---------------------------------------------------------------------------
# Kopfbedeckungen
# ---------------------------------------------------------------------------
@cc.part("cap", "hat", "accent", variants="AB", attach="HatAttachment", max_tris=2000)
def cap(variant, body):
	"""Baseballkappe: Krone mit Nähten, Knopf, gebogener Schirm. B: rückwärts getragen."""
	gap = 0.075
	rot = math.pi if variant == "B" else 0.0
	cut = cut3(0.46, 0.18, 0.08) if not rot else cut3(0.46, 0.22, 0.30)
	ru = cut  # Krone bleibt über der Stirn; nur Schirm und Nähte drehen sich
	crown = cc.head_shell("tmp", ru, lambda u, t: 0.045, gap=gap, nu=48, nv=10)
	parts = [crown]
	for k in range(6):
		u = HF + rot + k * TAU / 6
		pts = [cc.head_offset(u, cc.phi_at(ru(u)) + (math.pi / 2 - cc.phi_at(ru(u))) * t, gap + 0.05) for t in (0.0, 0.3, 0.6, 0.9)]
		parts.append(cc.sweep("tmp", pts, 0.012, segments=4))
	parts.append(cc.sphere("tmp", HEAD_C + Vector((0, 0, HEAD_HH + gap + 0.05)), 0.07, scale=(1, 1, 0.55), segments=10, rings=6))
	rows = []
	for i in range(19):
		u = HF + rot + (i / 18 - 0.5) * math.radians(150)
		p = cc.head_offset(u, cc.phi_at(ru(u)), gap + 0.03)
		d = Vector((p.x - HEAD_C.x, p.y - HEAD_C.y, 0)).normalized()
		length = 0.08 + 0.50 * max(0.0, frontness(u - rot)) ** 1.6
		row = []
		for j in range(5):
			s = j / 4
			q = p - d * 0.05 + d * length * s
			q.z += -0.04 * s * s * length
			row.append(cc.to_rbx(q))
		rows.append(row)
	parts.append(cc.slab("tmp", lambda su, sv, off: rows[round(su * 18)][round(sv * 4)] + Vector((0, -off, 0)), 18, 4, lambda su, sv: 0.0, lambda su, sv: 0.04))
	return cc.join("tmp", parts)


@cc.part("beanie", "hat", "accent", variants="AB", attach="HatAttachment", max_tris=2100)
def beanie(variant, body):
	"""Strickmütze mit Umschlag. B: mit Bommel."""
	cut = cut3(0.43, 0.02, -0.14)

	def thick(u, t):
		cuff = 1 - smoothstep(0.22, 0.30, t)
		knit = 0.006 * (0.5 + 0.5 * math.cos(28 * u))
		return 0.06 + cuff * (0.05 + 0.02 * (0.5 + 0.5 * math.cos(16 * u))) + knit + 0.06 * t**4

	shell = cc.head_shell("tmp", cut, thick, gap=0.05, nu=64, nv=11)
	if variant == "A":
		return shell
	pom = cc.sphere("tmp", HEAD_C + Vector((0, 0, HEAD_HH + 0.32)), 0.17, segments=14, rings=9)
	return cc.join("tmp", [shell, pom])


@cc.part("flat_cap", "hat", "accent", attach="HatAttachment", max_tris=1600)
def flat_cap(variant, body):
	"""Schiebermütze: flache Krone, nach vorne gezogen, kurzer Schirm."""
	gap = 0.04
	cut = cut3(0.46, 0.16, 0.06)

	def thick(u, t):
		f = max(0.0, frontness(u))
		return 0.05 + 0.10 * f * math.sin(math.pi * min(1, t * 1.1)) + 0.03 * (1 - t)

	crown = cc.head_shell("tmp", cut, thick, gap=gap, nu=48, nv=10)
	rows = []
	for i in range(15):
		u = HF + (i / 14 - 0.5) * math.radians(120)
		p = cc.head_offset(u, cc.phi_at(cut(u)), gap + 0.02)
		d = Vector((p.x - HEAD_C.x, p.y - HEAD_C.y, 0)).normalized()
		length = 0.05 + 0.25 * max(0.0, frontness(u)) ** 1.4
		rows.append([cc.to_rbx(p - d * 0.04 + d * length * j / 3 + Vector((0, 0, -0.03 * j / 3))) for j in range(4)])
	brim = cc.slab("tmp", lambda su, sv, off: rows[round(su * 14)][round(sv * 3)] + Vector((0, -off, 0)), 14, 3, lambda su, sv: 0.0, lambda su, sv: 0.035)
	return cc.join("tmp", [crown, brim])


# ---------------------------------------------------------------------------
# Brillen (Augen auf +0.27, Abstand ±0.12)
# ---------------------------------------------------------------------------
def frame_ring(cx, cz, w, h, n, tube, y):
	"""Brillenrahmen als (abgerundetes) Rechteck/Oval um (cx, cz) in der Gesichtsebene."""
	pts = []
	for i in range(28):
		a = TAU * i / 28
		x = cx + w * cc._spow(math.cos(a), 2 / n)
		z = cz + h * cc._spow(math.sin(a), 2 / n)
		pts.append(Vector((x, y(x, z - HEAD_C.z), z)))
	return cc.sweep("tmp", pts, tube, segments=6, closed=True)


@cc.part("glasses", "face", "fixed:#26262a", variants="AB", attach="FaceFrontAttachment", max_tris=1600)
def glasses(variant, body):
	"""Brille: A rund, B eckig (Business). Gläser als eigenes, durchsichtiges Teil."""
	ez = HEAD_C.z + cc.EYE_Y
	w, h, n = (0.125, 0.125, 2.0) if variant == "A" else (0.15, 0.10, 3.5)
	cxs = (-0.155, 0.155) if variant == "A" else (-0.17, 0.17)
	y = lambda x, z: cc.front_y(x, z) - 0.065  # noqa: E731
	parts, lenses = [], []
	for cx in cxs:
		parts.append(frame_ring(cx, ez, w, h, n, 0.02, y))
		disc = cc.cylinder("tmp", (cx, y(cx, cc.EYE_Y) - 0.004, ez), (cx, y(cx, cc.EYE_Y) + 0.006, ez), 1.0, segments=24)
		disc.scale = (w * 0.95, 1, h * 0.95)
		lenses.append(disc)
		sx = 1 if cx > 0 else -1
		x0 = cx + sx * w
		pts = [Vector((x0, y(x0, cc.EYE_Y), ez + 0.02)), Vector((sx * (HEAD_RX + 0.03), HEAD_C.y - 0.30, ez + 0.03)), Vector((sx * (HEAD_RX + 0.03), HEAD_C.y + 0.15, ez - 0.02))]
		parts.append(cc.sweep("tmp", pts, 0.018, segments=5))
	bx = abs(cxs[0]) - w
	bridge = [Vector((x, y(x, cc.EYE_Y) - 0.01, ez + 0.03 + 0.03 * (1 - (x / max(bx, 0.01)) ** 2))) for x in (-bx, -bx / 2, 0, bx / 2, bx)]
	parts.append(cc.sweep("tmp", bridge, 0.018, segments=5))
	lens = cc.join("tmp", lenses)
	return [cc.join("tmp", parts), cc.tag(lens, suffix="Lens", color="fixed:#cfe8ff", transparency=0.65)]


@cc.part("headphones", "extra", "fixed:#2a2a30", attach="HatAttachment", max_tris=1600)
def headphones(variant, body):
	"""Kopfhörer: Bügel über Haaren/Mütze, zwei Muscheln mit Polster."""
	cx = HEAD_RX + 0.15
	band = [HEAD_C + Vector((math.cos(a) * cx, 0.02, 0.10 + math.sin(a) * (HEAD_HH + 0.24))) for a in [math.pi * i / 18 for i in range(19)]]
	objs = [cc.sweep("tmp", band, (0.05, 0.11), segments=8)]
	for sx in (-1, 1):
		c = HEAD_C + Vector((sx * cx, 0.02, 0.0))
		objs.append(cc.cylinder("tmp", c - Vector((sx * 0.07, 0, 0)), c + Vector((sx * 0.07, 0, 0)), 0.22, segments=18, bevel=0.04))
		objs.append(cc.cylinder("tmp", c - Vector((sx * 0.12, 0, 0)), c - Vector((sx * 0.06, 0, 0)), 0.19, segments=18, bevel=0.025))
	return cc.join("tmp", objs)
