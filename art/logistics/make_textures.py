"""Procedural textures for the logistics models (boxes, crates, van, shelf). Outputs ./tex/*.png"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

N = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tex")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def noise(scale, octaves=4, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((N, N)); amp = tot = 1.0; tot = 0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        g = Image.fromarray((r.random((s + 1, s + 1)) * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        acc += np.asarray(g, float) / 255 * amp; tot += amp; amp *= 0.5
    return acc / tot


def lerp(a, b, t):
    t = t[..., None]
    return np.array(a, float) * (1 - t) + np.array(b, float) * t


def save(name, rgb):
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name))


yy, xx = np.mgrid[0:N, 0:N] / (N - 1)

# cardboard: fibres + corrugation lines, a darker seam and brown tape band through the middle
cb = lerp((205, 165, 112), (176, 132, 82), noise(5, 4, 1))
cb *= (0.96 + 0.04 * np.sin(xx * 340))[..., None]
fib = rng.random((N, N)) > 0.992
cb[fib] *= 0.85
tape = np.abs(xx - 0.5) < 0.06
cb[tape] = lerp((170, 120, 70), (150, 104, 60), noise(20, 2, 2))[tape]
cb[np.abs(xx - 0.5) < 0.004] *= 0.7
img = Image.fromarray(cb.astype(np.uint8))
d = ImageDraw.Draw(img)
# printed "this side up" arrows and a recycling-style mark, no text
for cx in (90, 422):
    d.polygon([(cx, 300), (cx - 26, 340), (cx - 10, 340), (cx - 10, 380), (cx + 10, 380), (cx + 10, 340), (cx + 26, 340)], fill=(80, 56, 36))
d.ellipse((230, 380, 282, 432), outline=(80, 56, 36), width=6)
save("cardboard.png", np.asarray(img.filter(ImageFilter.GaussianBlur(0.6)), float))

# plastic crate green (slight speckle) + produce half (leafy greens & tomatoes) as an atlas
crate = lerp((52, 140, 66), (40, 118, 54), noise(12, 2, 3))
leaf = lerp((150, 210, 90), (70, 150, 50), noise(10, 4, 4))
tom = lerp((220, 50, 40), (170, 30, 24), noise(9, 3, 5))
atlas = crate.copy()
atlas[:, N // 2:] = leaf[:, N // 2:]
atlas[N // 2:, N // 2:] = tom[N // 2:, N // 2:]
save("veg_crate.png", atlas)

# drinks crate: red plastic | bottles (glass brown) | caps (silver) atlas
red = lerp((200, 40, 36), (160, 26, 24), noise(10, 2, 6))
glass = lerp((90, 52, 28), (60, 34, 18), noise(6, 2, 7))
glass *= (0.85 + 0.3 * np.exp(-((xx - 0.62) ** 2) / 0.002))[..., None]
cap = lerp((210, 210, 214), (160, 160, 168), noise(20, 2, 8))
dr = red.copy()
dr[:, N // 2:] = glass[:, N // 2:]
dr[N * 3 // 4:, N // 2:] = cap[N * 3 // 4:, N // 2:]
save("drink_crate.png", dr)

# styrofoam (bubbly white) | blue lid | red band atlas
foam = lerp((246, 247, 250), (222, 226, 232), noise(40, 2, 9))
bub = rng.random((N, N)) > 0.97
foam[bub] *= 0.95
lid = lerp((60, 120, 200), (44, 96, 170), noise(8, 2, 10))
band = np.full((N, N, 3), (205, 40, 40), float)
mt = foam.copy()
mt[:, N // 2:] = lid[:, N // 2:]
mt[N * 3 // 4:, :N // 2] = band[N * 3 // 4:, :N // 2]
save("meat_box.png", mt)

# van paint: white with slight grime at the bottom, red/orange stripe band, dark trim strip
van = lerp((246, 246, 244), (226, 226, 222), noise(6, 3, 11))
van = lerp(van, (160, 150, 140), np.clip((yy - 0.85) * 4, 0, 1) * noise(10, 2, 12))
stripe = (yy > 0.42) & (yy < 0.52)
van[stripe] = lerp((232, 76, 40), (214, 60, 30), xx)[stripe]
van[(yy > 0.53) & (yy < 0.55)] = (240, 170, 40)
save("van_paint.png", van)

# solid swatches for glass, tyres, trim, lights, shelf metal
def solid(name, c, n=0.06, seed=0):
    base = np.array(c, float)
    v = base * (1 - n / 2 + n * noise(16, 2, seed))[..., None]
    save(name, v)

solid("glass_dark.png", (34, 48, 60), 0.1, 13)
solid("tyre.png", (28, 28, 30), 0.15, 14)
solid("trim.png", (60, 62, 66), 0.1, 15)
lights = np.zeros((N, N, 3)); lights[:] = (250, 240, 200); lights[:, N // 2:] = (210, 30, 30)
save("lights.png", lights)
shelf = np.zeros((N, N, 3))
shelf[:, :N // 2] = lerp((236, 120, 30), (210, 100, 24), noise(10, 2, 16))[:, :N // 2]  # uprights orange
shelf[:, N // 2:] = lerp((176, 180, 186), (140, 144, 150), noise(14, 2, 17))[:, N // 2:]  # galvanised beams/decks
save("shelf.png", shelf)
print("ok", OUT)

# layered raw meat for the döner cone: horizontal slices (v = height), fat streaks, neutral tone
lay = lerp((236, 214, 196), (206, 170, 150), noise(5, 3, 21))
band = (np.sin(yy * np.pi * 2 * 14 + noise(4, 2, 22) * 3) * 0.5 + 0.5)
lay = lerp(lay, (180, 132, 112), np.clip(band - 0.55, 0, 1) * 1.6)
fat = np.clip((noise(16, 3, 23) - 0.62) * 4, 0, 1) * (band < 0.35)
lay = lerp(lay, (250, 244, 232), fat * 0.8)
tray = np.zeros((N, N, 3)); tray[:] = (190, 192, 198)
lay[int(N * 0.9):, :] = tray[int(N * 0.9):, :]  # bottom strip: steel for tray and rod
save("meat_layers.png", lay)
print("meat ok")
