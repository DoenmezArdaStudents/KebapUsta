"""Textures for the finished (closed) kebab models – issue #4. Run after make_textures.py:
    python3 make_textures.py && python3 make_finished_textures.py
Outputs in ./tex/:
  filling.png  atlas: u 0..0.5 v 0..0.5 mixed filling (meat, salad, sauce) | u 0.5..1 v 0..0.5 lettuce
               u 0..0.5 v 0.5..1 tomato | u 0.5..1 v 0.5..1 meat   (v measured from the bottom, Blender UVs)
  paper.png    kebab wrapping paper: cream paper with a red band and the shop name near the top edge (v 0.8..0.95)
  foil.png     crinkled aluminium foil
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "tex")
N = 512
rng = np.random.default_rng(11)


def load(name, size):
    return Image.open(os.path.join(TEX, name)).convert("RGB").resize((size, size), Image.LANCZOS)


def noise(n, scale, octaves=4, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n))
    amp = tot = 0.0
    amp = 1.0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        g = r.random((s + 1, s + 1))
        acc += np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC), float) / 255 * amp
        tot += amp
        amp *= 0.5
    return acc / tot


# --------------------------------------------------------------------------- filling atlas
H = N // 2
atlas = Image.new("RGB", (N, N))
lettuce, tomato, meat, onion, cabbage, sauce = (load(n, H) for n in ("lettuce.png", "tomato.png", "meat.png", "onion.png", "cabbage.png", "sauce.png"))
# image rows go top-down, Blender v goes bottom-up: v 0..0.5 = lower image half
atlas.paste(lettuce, (H, H))
atlas.paste(tomato, (0, 0))
atlas.paste(meat, (H, 0))

# mixed filling: meat base with salad / tomato / onion / red cabbage chips and a garlic sauce drizzle
mix = load("meat.png", H)
d = ImageDraw.Draw(mix)
src = {"lettuce": lettuce, "tomato": tomato, "onion": onion, "cabbage": cabbage}
for kind, count, size in (("lettuce", 26, (34, 60)), ("tomato", 14, (24, 40)), ("onion", 16, (14, 26)), ("cabbage", 18, (10, 22))):
    for _ in range(count):
        w = int(rng.integers(*size))
        h = int(w * rng.uniform(0.5, 0.9))
        x, y = int(rng.integers(0, H - w)), int(rng.integers(0, H - h))
        sx, sy = int(rng.integers(0, H - w)), int(rng.integers(0, H - h))
        chip = src[kind].crop((sx, sy, sx + w, sy + h))
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, w - 1, h - 1), fill=255)
        mask = mask.rotate(float(rng.uniform(0, 180))).filter(ImageFilter.GaussianBlur(1.2))
        mix.paste(chip, (x, y), mask)
# sauce drizzle (white garlic sauce + a little red chili)
for col, n in (((246, 242, 228), 3), ((196, 48, 32), 1)):
    for _ in range(n):
        y0 = rng.uniform(30, H - 30)
        ph = rng.uniform(0, 6)
        pts = [(x, y0 + 16 * np.sin(x / 34 + ph)) for x in range(-10, H + 10, 3)]
        d.line(pts, fill=col, width=int(rng.integers(5, 9)), joint="curve")
mix = mix.filter(ImageFilter.SMOOTH)
atlas.paste(mix, (0, H))
atlas.save(os.path.join(TEX, "filling.png"))

# --------------------------------------------------------------------------- wrapping paper
fib = noise(N, 24, 4, 3)
paper = np.zeros((N, N, 3))
base = np.array([244, 238, 224], float)
paper[:] = base
paper *= (0.94 + 0.08 * fib)[..., None]
# soft crease lines
for _ in range(10):
    x = int(rng.integers(0, N))
    paper[:, max(0, x - 1):x + 2] *= 0.95
img = Image.fromarray(np.clip(paper, 0, 255).astype(np.uint8))
d = ImageDraw.Draw(img)
# red band near the top edge (v 0.80..0.93 → image rows 0.07..0.20)
d.rectangle((0, int(N * 0.07), N, int(N * 0.20)), fill=(184, 44, 34))
d.rectangle((0, int(N * 0.215), N, int(N * 0.235)), fill=(184, 44, 34))
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", 40)
except OSError:
    font = ImageFont.load_default()
for x0 in (0, N // 2):
    d.text((x0 + N // 4, int(N * 0.135)), "KEBAP USTA", fill=(250, 240, 220), font=font, anchor="mm")
# small repeating pattern on the lower part
for y in range(int(N * 0.32), N, 64):
    for x in range((y // 64 % 2) * 32, N, 64):
        d.ellipse((x + 26, y + 26, x + 34, y + 34), fill=(214, 120, 96))
img.save(os.path.join(TEX, "paper.png"))

# --------------------------------------------------------------------------- foil
f1 = noise(N, 10, 5, 7)
f2 = noise(N, 40, 3, 8)
v = 150 + 70 * f1 + 35 * (f2 - 0.5)
gx = np.abs(np.gradient(f1 * 40, axis=1)) + np.abs(np.gradient(f1 * 40, axis=0))
v += 40 * np.clip(gx, 0, 1.5)
foil = np.stack([v, v * 1.01, v * 1.04], -1)
Image.fromarray(np.clip(foil, 0, 255).astype(np.uint8)).save(os.path.join(TEX, "foil.png"))
print("textures ok")
