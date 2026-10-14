"""Procedural PBR-ish albedo textures for the food models (numpy + PIL, no external assets).

Every texture is 512x512 and tileable enough for the small food pieces. Run:
    python3 make_textures.py
Outputs land in ./tex/.
"""
import os
import numpy as np
from PIL import Image, ImageFilter

N = 512
OUT = os.path.join(os.path.dirname(__file__), "tex")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(42)


def noise(scale, octaves=4, seed=0):
    """Fractal value noise in [0,1]."""
    r = np.random.default_rng(seed)
    acc = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        g = r.random((s + 1, s + 1))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        acc += np.asarray(img, dtype=float) / 255 * amp
        tot += amp
        amp *= 0.5
    return acc / tot


def save(name, rgb):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    Image.fromarray(rgb).save(os.path.join(OUT, name))


def lerp(a, b, t):
    t = t[..., None]
    return np.array(a, float) * (1 - t) + np.array(b, float) * t


yy, xx = np.mgrid[0:N, 0:N] / (N - 1)

# ---------------------------------------------------------------- bread atlas
# left half: golden crust · right-bottom: soft crumb · right-top: sesame
crust_n = noise(6, 5, 1)
spots = noise(14, 3, 2)
crust = lerp((214, 152, 78), (150, 88, 38), np.clip(crust_n * 1.3 - 0.25, 0, 1))
crust = lerp(crust / 255 * 255, (110, 60, 24), np.clip((spots - 0.62) * 4, 0, 1))
# fine flour dust speckles
dust = rng.random((N, N)) > 0.985
crust[dust] = crust[dust] * 0.4 + np.array([235, 220, 190]) * 0.6
crumb_n = noise(20, 3, 3)
crumb = lerp((242, 226, 190), (220, 196, 150), crumb_n)
pores = rng.random((N, N)) > 0.93
crumb[pores] *= 0.86
crumb = np.asarray(Image.fromarray(crumb.astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), float)
seed = lerp((246, 232, 196), (214, 188, 136), noise(8, 2, 4))
bread = np.zeros((N, N, 3))
half = N // 2
bread[:, :half] = crust[:, :half]
bread[half:, half:] = crumb[half:, half:]
bread[:half, half:] = seed[:half, half:]
save("bread_atlas.png", bread)

# ---------------------------------------------------------------- dürüm flatbread
base = lerp((236, 214, 168), (222, 192, 138), noise(5, 4, 5))
img = Image.fromarray(base.astype(np.uint8))
spot_layer = np.zeros((N, N))
for _ in range(90):
    cx, cy = rng.random(2) * N
    rad = rng.uniform(5, 22)
    d = np.sqrt((xx * N - cx) ** 2 + (yy * N - cy) ** 2)
    spot_layer = np.maximum(spot_layer, np.clip(1 - d / rad, 0, 1) * rng.uniform(0.4, 1.0))
spot_layer = np.asarray(Image.fromarray((spot_layer * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.5)), float) / 255
duerum = lerp(base, (128, 74, 30), spot_layer * 0.85)
save("duerum.png", duerum)

# ---------------------------------------------------------------- lettuce leaf (u across, v along)
vein = np.exp(-((xx - 0.5) ** 2) / 0.0012)
side = np.zeros_like(xx)
for k in range(1, 9):
    yk = k / 9
    # side veins branching from the mid rib, slanted toward the tip
    d = np.abs((yy - yk) - np.abs(xx - 0.5) * 0.7)
    side = np.maximum(side, np.exp(-(d ** 2) / 0.00025) * (np.abs(xx - 0.5) < 0.48))
edge = np.clip(np.abs(xx - 0.5) * 2.2, 0, 1)
leaf = lerp((172, 222, 98), (70, 150, 52), edge * 0.9 + noise(10, 3, 6) * 0.25)
leaf = lerp(leaf, (226, 244, 186), np.clip(vein * 0.9 + side * 0.45, 0, 1))
save("lettuce.png", leaf)

# ---------------------------------------------------------------- tomato slice (top view, centred)
cx = xx - 0.5
cy = yy - 0.5
r = np.sqrt(cx ** 2 + cy ** 2) * 2
ang = np.arctan2(cy, cx)
skin = (r > 0.9)
wall = (r > 0.72) & ~skin
warp = (noise(6, 3, 21) - 0.5) * 1.6
chamber_shape = (np.cos(ang * 4 + warp) * 0.5 + 0.5) * (0.8 + 0.4 * noise(9, 2, 22))
chambers = (r < 0.7 + warp * 0.05) & (r > 0.2 + warp * 0.04) & (chamber_shape > 0.36)
tomato = np.zeros((N, N, 3))
tomato[:] = (226, 56, 40)
tomato[wall] = (214, 44, 32)
tomato[skin] = (178, 24, 18)
tomato[chambers] = (244, 120, 82)
seeds = chambers & (rng.random((N, N)) > 0.992)
seedmask = np.asarray(Image.fromarray((seeds * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)), float) / 255
tomato = lerp(tomato, (238, 214, 140), seedmask * 0.9)
core = r < 0.18
tomato[core] = tomato[core] * 0.6 + np.array([250, 170, 130]) * 0.4
tomato = np.asarray(Image.fromarray(tomato.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), float)
tomato *= (0.92 + noise(18, 2, 7)[..., None] * 0.12)
save("tomato.png", tomato)

# ---------------------------------------------------------------- onion ring (u around, v across ring width)
onion = lerp((236, 226, 236), (186, 120, 176), np.clip((yy - 0.55) * 2.6, 0, 1))
onion *= (0.94 + noise(30, 2, 8)[..., None] * 0.08)
save("onion.png", onion)

# ---------------------------------------------------------------- red cabbage shred
cab = lerp((128, 40, 118), (88, 22, 82), noise(8, 3, 9))
cab_vein = np.exp(-((xx - 0.5) ** 2) / 0.004)
cab = lerp(cab, (232, 214, 236), cab_vein * 0.85)
save("cabbage.png", cab)

# ---------------------------------------------------------------- cucumber slice (top view)
cuc = np.zeros((N, N, 3))
cuc[:] = (206, 230, 168)
rind = r > 0.9
inner = r > 0.82
cuc[inner] = (150, 196, 110)
cuc[rind] = (52, 110, 44)
seedring = (r < 0.5) & (r > 0.2)
s3 = (np.cos(ang * 3) * 0.5 + 0.5) > 0.4
cuc[seedring & s3] = (226, 238, 196)
sd = seedring & s3 & (rng.random((N, N)) > 0.994)
sdm = np.asarray(Image.fromarray((sd * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)), float) / 255
cuc = lerp(cuc, (244, 246, 220), sdm)
cuc = np.asarray(Image.fromarray(cuc.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), float)
save("cucumber.png", cuc)

# ---------------------------------------------------------------- shaved meat (neutral golden, tinted per meat in-game)
m_n = noise(12, 4, 10)
fibers = (np.sin(yy * 220 + noise(4, 2, 11) * 9) * 0.5 + 0.5)
meat = lerp((226, 160, 86), (168, 96, 42), np.clip(m_n * 0.8 + fibers * 0.3, 0, 1))
char = np.clip((noise(10, 3, 12) - 0.6) * 3.5, 0, 1)
meat = lerp(meat, (70, 36, 16), char * 0.8)
edge_c = np.clip(np.abs(xx - 0.5) * 2 - 0.75, 0, 1) * 4
meat = lerp(meat, (96, 50, 20), np.clip(edge_c, 0, 1) * 0.7)
save("meat.png", meat)

# ---------------------------------------------------------------- sauce (near white, gets tinted per sauce)
sauce = lerp((252, 252, 248), (226, 226, 220), noise(6, 3, 13))
gloss = np.clip(1 - np.abs(xx - 0.38) * 12, 0, 1) * 0.5
sauce = lerp(sauce, (255, 255, 255), gloss)
save("sauce.png", sauce)

# ---------------------------------------------------------------- grated cheese
ch = lerp((250, 236, 170), (232, 204, 120), noise(16, 3, 14))
save("cheese.png", ch)
print("textures written to", OUT)
