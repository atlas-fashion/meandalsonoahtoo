"""Old dark wood planks for the corridor doors: albedo + normal map.

    blender -b --factory-startup -P tools/build_wood_texture.py -- OUT_DIR [SEED]

Writes OUT_DIR/wood_door_albedo.png and wood_door_normal.png, 1024 x 2048:
four different planks side by side (256 px each), each running the full
height of a door. `module_level.place_doors` gives every plank of a leaf one
of the four columns, so neighbouring planks never share a grain.

Tripo was the first choice for this, but a textured model costs 20 credits
on this account and the balance was 10. Everything here is numpy (Blender's
Python has it); plain Python on this machine may have no image library.

What makes it read as OLD wood rather than a brown gradient:
  - growth-ring grain, bent by low-frequency noise so no two lines are parallel
  - fine fibres running with the grain
  - knots, with the grain flowing round them and a dark core
  - weathering: grey, sun-bleached patches and water staining at the foot
  - a hairline crack or two, and dark gaps where the planks meet
"""
import bpy
import math
import random
import sys
import numpy as np

ARGV = sys.argv[sys.argv.index("--") + 1:]
OUT = ARGV[0]
SEED = int(ARGV[1]) if len(ARGV) > 1 else 5
W, H = 1024, 2048
PLANKS = 4
PW = W // PLANKS
rng = np.random.default_rng(SEED)


def vnoise(h, w, cy, cx):
    """Smooth value noise, h x w, with cy x cx cells."""
    grid = rng.random((cy + 2, cx + 2))
    ys = np.linspace(0, cy, h, endpoint=False)
    xs = np.linspace(0, cx, w, endpoint=False)
    y0 = ys.astype(int)
    x0 = xs.astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = grid[y0][:, x0]
    b = grid[y0][:, x0 + 1]
    c = grid[y0 + 1][:, x0]
    d = grid[y0 + 1][:, x0 + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(h, w, cy, cx, octaves=4):
    total = np.zeros((h, w))
    amp = 0.55
    for o in range(octaves):
        total += vnoise(h, w, cy * 2 ** o, cx * 2 ** o) * amp
        amp *= 0.5
    return total


albedo = np.zeros((H, W, 3))
height = np.zeros((H, W))
vv, uu = np.mgrid[0:H, 0:PW]
v = vv / float(H)
u = uu / float(PW)

for p in range(PLANKS):
    # Grain: a family of lines running down the plank, bent by slow noise.
    warp = fbm(H, PW, 6, 2) - 0.5
    g = u * rng.uniform(2.5, 4.0) + warp * 1.4 + v * rng.uniform(-0.4, 0.4)
    # Knots: the grain flows round them.
    knots = []
    for _k in range(rng.integers(1, 3)):
        ku, kv = rng.uniform(0.25, 0.75), rng.uniform(0.1, 0.9)
        kr = rng.uniform(0.05, 0.1)
        d2 = ((u - ku) * 1.0) ** 2 + ((v - kv) * PW / H * 4.0) ** 2
        g += np.exp(-d2 / (kr * kr)) * rng.uniform(0.8, 1.4) * np.sign(u - ku + 1e-6)
        knots.append((ku, kv, kr, d2))
    rings = 0.5 + 0.5 * np.sin(g * math.tau * 3.0)
    rings = rings ** 1.8
    fibres = vnoise(H, PW, 40, 70)
    fibres = (fibres - 0.5) * 0.5

    base = np.array([0.105, 0.068, 0.042]) * rng.uniform(0.85, 1.12)
    late = np.array([0.055, 0.035, 0.022])
    col = base[None, None, :] * (1.0 - rings[..., None]) + late[None, None, :] * rings[..., None]
    col *= (1.0 + fibres[..., None] * 0.6)
    # Weathering: grey, bleached patches.
    bleach = np.clip((fbm(H, PW, 5, 2) - 0.52) * 3.0, 0.0, 1.0) * 0.5
    grey = col.mean(axis=2, keepdims=True) * 1.5 + 0.02
    col = col * (1.0 - bleach[..., None]) + grey * bleach[..., None]
    # Water staining up from the foot of the door.
    foot = np.clip(1.0 - (1.0 - v) / 0.22, 0.0, 1.0) ** 1.5
    col *= (1.0 - 0.45 * foot[..., None] * (0.6 + 0.4 * fbm(H, PW, 8, 3)[..., None]))
    # Knot cores.
    for ku, kv, kr, d2 in knots:
        core = np.exp(-d2 / (kr * kr * 0.12))
        col *= (1.0 - 0.7 * core[..., None])
    # A hairline crack or two, following the grain.
    crack = np.zeros((H, PW))
    for _c in range(rng.integers(0, 3)):
        cu = rng.uniform(0.2, 0.8) + (fbm(H, 1, 10, 1)[:, 0] - 0.5) * 0.08
        v0, v1 = sorted(rng.uniform(0.0, 1.0, 2))
        on = (v[:, 0] >= v0) & (v[:, 0] <= v1)
        dist = np.abs(u - cu[:, None])
        crack = np.maximum(crack, np.where(on[:, None], np.clip(1.0 - dist / 0.012, 0.0, 1.0), 0.0))
    col *= (1.0 - 0.8 * crack[..., None])
    # Dark gaps at the plank edges.
    edge = np.clip(1.0 - np.minimum(u, 1.0 - u) / 0.035, 0.0, 1.0)
    col *= (1.0 - 0.75 * edge[..., None])

    h = rings * 0.35 + fibres * 0.5 - crack * 0.8 - edge * 0.9 - bleach * 0.1
    albedo[:, p * PW:(p + 1) * PW] = col
    height[:, p * PW:(p + 1) * PW] = h

# Normal map from the height field (OpenGL convention, +Y up).
strength = 3.5
dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
n = np.dstack([-dx * strength, dy * strength, np.ones_like(height)])
n /= np.linalg.norm(n, axis=2, keepdims=True)
normal = n * 0.5 + 0.5


def save(name, rgb, srgb):
    img = bpy.data.images.new(name, W, H, alpha=False)
    if not srgb:
        img.colorspace_settings.name = "Non-Color"
    data = np.dstack([np.clip(rgb, 0, 1), np.ones((H, W))])
    img.pixels = np.flipud(data).ravel().tolist()
    img.filepath_raw = "%s/%s.png" % (OUT, name)
    img.file_format = "PNG"
    img.save()


# Albedo is authored in linear terms; stored as sRGB like any colour texture.
save("wood_door_albedo", np.clip(albedo, 0, 1) ** (1.0 / 2.2), True)
save("wood_door_normal", normal, False)
print("[wood] wrote %s/wood_door_albedo.png and wood_door_normal.png" % OUT)
