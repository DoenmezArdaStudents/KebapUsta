"""
parts/body.py – Körper Mann (m) und Frau (w).

Leicht menschliche Formen (Schultern, Brust, Taille, Hüfte, Waden, Hände mit Daumen) mit
Roblox-Proportionen. Jedes Segment gehört zu einem R15-Körperteil (`anchor`) und wird im Spiel an
dessen Stelle angezeigt; die Gelenke (customer_creator.JOINT) bleiben die des Standard-Rigs, damit
die Roblox-Animationen passen. Den Kopf liefert Roblox (Dynamic Head mit Mimik).

`profile(body, segment)` gibt die Querschnitte zurück – die Kleidung baut darauf auf.
"""

import customer_creator as cc


def R(h, a, b, **kw):
	return {"h": h, "a": a, "b": b, **kw}


# Rechte Körperseite (+X); links wird gespiegelt
SHAPES = {
	"m": {
		"UpperTorso": [
			R(-0.82, 0.66, 0.40),
			R(-0.62, 0.70, 0.42),
			R(-0.35, 0.74, 0.44),
			R(0.00, 0.80, 0.46),
			R(0.30, 0.88, 0.48, front=0.03),
			R(0.55, 0.93, 0.49, front=0.04, back=0.02),
			R(0.75, 0.95, 0.47, front=0.02, back=0.03),
			R(0.88, 0.91, 0.43),
			R(0.97, 0.80, 0.38),
			R(1.03, 0.60, 0.32),
			R(1.07, 0.38, 0.27),
			R(1.10, 0.26, 0.23),
			R(1.30, 0.25, 0.22),
		],
		"LowerTorso": [
			R(-0.52, 0.76, 0.45),
			R(-0.70, 0.80, 0.46),
			R(-0.90, 0.84, 0.46, back=0.02),
			R(-1.05, 0.81, 0.44),
			R(-1.15, 0.62, 0.37),
			R(-1.22, 0.34, 0.26),
		],
		"RightUpperLeg": [
			R(-0.78, 0.42, 0.44, cx=0.48),
			R(-1.00, 0.43, 0.45, cx=0.48),
			R(-1.35, 0.40, 0.42, cx=0.48),
			R(-1.70, 0.34, 0.37, cx=0.48),
			R(-1.92, 0.31, 0.34, cx=0.48),
		],
		"RightLowerLeg": [
			R(-1.72, 0.26, 0.29, cx=0.48),
			R(-1.85, 0.30, 0.33, cx=0.48),
			R(-2.00, 0.32, 0.35, cx=0.48, back=0.02),
			R(-2.20, 0.31, 0.35, cx=0.48, back=0.04),
			R(-2.50, 0.26, 0.29, cx=0.48),
			R(-2.75, 0.22, 0.25, cx=0.48),
			R(-2.86, 0.21, 0.24, cx=0.48),
		],
		"RightUpperArm": [
			R(1.04, 0.06, 0.06, cx=1.30),
			R(1.01, 0.18, 0.18, cx=1.30),
			R(0.94, 0.29, 0.30, cx=1.31),
			R(0.82, 0.34, 0.35, cx=1.31),
			R(0.50, 0.33, 0.34, cx=1.32),
			R(0.20, 0.31, 0.33, cx=1.33),
			R(0.00, 0.27, 0.29, cx=1.33),
			R(-0.10, 0.25, 0.26, cx=1.33),
		],
		"RightLowerArm": [
			R(0.18, 0.24, 0.25, cx=1.34),
			R(0.05, 0.29, 0.29, cx=1.34),
			R(-0.10, 0.30, 0.31, cx=1.34),
			R(-0.30, 0.29, 0.29, cx=1.34),
			R(-0.55, 0.24, 0.25, cx=1.34),
			R(-0.77, 0.20, 0.21, cx=1.34),
		],
		"RightHand": [
			R(-0.64, 0.16, 0.20, cx=1.35, cz=-0.01),
			R(-0.76, 0.19, 0.27, cx=1.35, cz=-0.02),
			R(-0.92, 0.18, 0.29, cx=1.35, cz=-0.03),
			R(-1.05, 0.15, 0.27, cx=1.35, cz=-0.03),
			R(-1.13, 0.10, 0.19, cx=1.35, cz=-0.03),
			R(-1.16, 0.05, 0.10, cx=1.35, cz=-0.03),
		],
		"RightFoot": [
			R(0.27, 0.15, 0.09, cx=0.48, cy=-2.91),
			R(0.16, 0.21, 0.12, cx=0.48, cy=-2.88),
			R(-0.10, 0.23, 0.12, cx=0.48, cy=-2.89),
			R(-0.35, 0.24, 0.09, cx=0.48, cy=-2.92),
			R(-0.52, 0.19, 0.07, cx=0.48, cy=-2.94),
			R(-0.58, 0.09, 0.04, cx=0.48, cy=-2.95),
		],
	},
	"w": {
		"UpperTorso": [
			R(-0.82, 0.60, 0.38),
			R(-0.62, 0.63, 0.40),
			R(-0.35, 0.66, 0.41),
			R(0.05, 0.72, 0.43, front=0.03),
			R(0.38, 0.78, 0.44, front=0.09),
			R(0.58, 0.82, 0.44, front=0.06),
			R(0.76, 0.85, 0.42, front=0.01),
			R(0.88, 0.82, 0.39),
			R(0.96, 0.72, 0.34),
			R(1.02, 0.52, 0.29),
			R(1.07, 0.32, 0.24),
			R(1.10, 0.23, 0.21),
			R(1.30, 0.22, 0.20),
		],
		"LowerTorso": [
			R(-0.52, 0.70, 0.43),
			R(-0.72, 0.82, 0.46, back=0.03),
			R(-0.92, 0.92, 0.48, back=0.05),
			R(-1.07, 0.86, 0.45),
			R(-1.17, 0.62, 0.36),
			R(-1.23, 0.32, 0.24),
		],
		"RightUpperLeg": [
			R(-0.80, 0.44, 0.45, cx=0.47),
			R(-1.05, 0.44, 0.45, cx=0.47),
			R(-1.40, 0.38, 0.40, cx=0.47),
			R(-1.72, 0.32, 0.35, cx=0.47),
			R(-1.92, 0.29, 0.32, cx=0.47),
		],
		"RightLowerLeg": [
			R(-1.72, 0.24, 0.27, cx=0.47),
			R(-1.85, 0.28, 0.31, cx=0.47),
			R(-2.00, 0.30, 0.33, cx=0.47, back=0.02),
			R(-2.20, 0.29, 0.33, cx=0.47, back=0.04),
			R(-2.50, 0.24, 0.27, cx=0.47),
			R(-2.75, 0.20, 0.23, cx=0.47),
			R(-2.86, 0.19, 0.22, cx=0.47),
		],
		"RightUpperArm": [
			R(1.00, 0.05, 0.05, cx=1.22),
			R(0.97, 0.15, 0.16, cx=1.22),
			R(0.90, 0.25, 0.26, cx=1.23),
			R(0.78, 0.30, 0.31, cx=1.23),
			R(0.50, 0.29, 0.30, cx=1.24),
			R(0.20, 0.26, 0.28, cx=1.25),
			R(0.00, 0.24, 0.26, cx=1.25),
			R(-0.10, 0.22, 0.23, cx=1.25),
		],
		"RightLowerArm": [
			R(0.18, 0.21, 0.22, cx=1.26),
			R(0.05, 0.25, 0.26, cx=1.26),
			R(-0.10, 0.26, 0.27, cx=1.26),
			R(-0.30, 0.25, 0.26, cx=1.26),
			R(-0.55, 0.21, 0.22, cx=1.26),
			R(-0.77, 0.18, 0.19, cx=1.26),
		],
		"RightHand": [
			R(-0.64, 0.14, 0.18, cx=1.27, cz=-0.01),
			R(-0.76, 0.17, 0.24, cx=1.27, cz=-0.02),
			R(-0.91, 0.16, 0.26, cx=1.27, cz=-0.03),
			R(-1.03, 0.13, 0.24, cx=1.27, cz=-0.03),
			R(-1.11, 0.09, 0.17, cx=1.27, cz=-0.03),
			R(-1.14, 0.04, 0.09, cx=1.27, cz=-0.03),
		],
		"RightFoot": [
			R(0.25, 0.13, 0.08, cx=0.47, cy=-2.92),
			R(0.15, 0.19, 0.11, cx=0.47, cy=-2.89),
			R(-0.10, 0.21, 0.11, cx=0.47, cy=-2.90),
			R(-0.33, 0.22, 0.08, cx=0.47, cy=-2.93),
			R(-0.48, 0.17, 0.06, cx=0.47, cy=-2.945),
			R(-0.54, 0.08, 0.035, cx=0.47, cy=-2.955),
		],
	},
}

SEGMENTS = [
	"UpperTorso",
	"LowerTorso",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
]

_cache = {}


def profile(body, segment):
	"""Querschnitte eines Körpersegments (Left* = gespiegeltes Right*)."""
	key = (body, segment)
	if key not in _cache:
		if segment.startswith("Left"):
			_cache[key] = profile(body, "Right" + segment[4:]).mirrored()
		else:
			axis = "z" if segment.endswith("Foot") else "y"
			_cache[key] = cc.Profile(SHAPES[body][segment], axis=axis)
	return _cache[key]


def side_x(prof):
	"""+1 für rechte, −1 für linke Gliedmaßen (Richtung nach außen in Roblox-X)."""
	return -1 if prof.is_mirrored else 1


def thumb(body, segment):
	"""Daumen an der Vorder-Innenseite der Hand."""
	prof = profile(body, segment)
	sx = side_x(prof)
	cx = prof.at(-0.8)["cx"]
	k = 1.0 if body == "m" else 0.9
	pts = [(cx - sx * 0.09 * k, -0.74, -0.14 * k), (cx - sx * 0.12 * k, -0.84, -0.27 * k), (cx - sx * 0.10 * k, -0.95, -0.32 * k)]
	tube = cc.sweep("tmp_thumb", [cc.rbx(*p) for p in pts], lambda i: (0.075, 0.07, 0.06)[i] * k, segments=10)
	tip = cc.sphere("tmp_tip", cc.rbx(*pts[-1]), 0.06 * k, segments=10, rings=6)
	return cc.join("tmp_thumb", [tube, tip])


@cc.part("body", "body", "skin", per_body=True, max_tris=3000)
def body_part(variant, body):
	objs = []
	for seg in SEGMENTS:
		prof = profile(body, seg)
		if seg.endswith("Hand"):
			ob = cc.join("tmp", [cc.solid("tmp_palm", prof, nu=20), thumb(body, seg)])
		elif seg == "UpperTorso":
			ob = cc.solid("tmp", prof, nu=36)
		else:
			ob = cc.solid("tmp", prof, nu=24)
		objs.append(cc.tag(ob, suffix=seg, anchor=seg))
	return objs
