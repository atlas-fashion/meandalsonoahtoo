"""A tileable brick texture for the sewer pipes, in the dungeon's colours.

    blender -b --factory-startup -P tools/build_sewer_brick.py

Writes textures/sewer_brick_albedo.png and textures/sewer_brick_normal.png
(1024 px, tiling both ways). The corridor brick is Tripo's, baked per piece on
its own UVs, so it cannot tile round a pipe; this matches it instead: dark
charcoal bricks, each a little different, pitted, in thick crumbling brown
mortar (the user's wall photo, models/source/brick_kit_refs/wall.webp). No
damp band: the texture tiles, and it would repeat as stripes.
Running bond, 8 courses x 4 bricks. Deterministic (seed 11).
"""
import os
import bpy
import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "textures")
N = 1024
ROWS = 8
COLS = 4
MORTAR = 0.12       # of a brick's height
rng = np.random.default_rng(11)


def noise(n, scale, octaves=4):
    """Tileable value noise: summed octaves of a random lattice, wrapped."""
    out = np.zeros((n, n))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        g = scale * (2 ** o)
        lat = rng.random((g, g))
        x = np.arange(n) * g / n
        i0 = np.floor(x).astype(int) % g
        i1 = (i0 + 1) % g
        f = x - np.floor(x)
        f = f * f * (3 - 2 * f)
        a = lat[i0][:, i0] * (1 - f)[None, :] + lat[i0][:, i1] * f[None, :]
        b = lat[i1][:, i0] * (1 - f)[None, :] + lat[i1][:, i1] * f[None, :]
        out += amp * (a * (1 - f)[:, None] + b * f[:, None])
        total += amp
        amp *= 0.5
    return out / total


def main():
    v = (np.arange(N) + 0.5) / N
    u = (np.arange(N) + 0.5) / N
    U, V = np.meshgrid(u, v)
    row = np.floor(V * ROWS).astype(int)
    shift = (row % 2) * 0.5 / COLS
    uu = (U + shift) % 1.0
    col = np.floor(uu * COLS).astype(int)
    fu = uu * COLS - col
    fv = V * ROWS - row
    # Distance into the brick from its nearest edge, in brick heights.
    edge = np.minimum(np.minimum(fu, 1 - fu) * (ROWS / COLS), np.minimum(fv, 1 - fv))
    rough = noise(N, 8) - 0.5
    mortar = np.clip((MORTAR + rough * 0.12 - edge) / 0.025, 0, 1)
    # Per brick: shade and a lean toward brown.
    ids = row * COLS + col
    shade = rng.uniform(0.09, 0.2, ROWS * COLS)[ids]
    warm = rng.uniform(0.0, 0.35, ROWS * COLS)[ids]
    pits = noise(N, 32, 3)
    blotch = noise(N, 6, 3)
    speck = noise(N, 96, 2)
    base = shade * (0.7 + 0.6 * blotch) * (0.6 + 0.8 * pits) * (0.8 + 0.4 * speck)
    brick = np.stack([base * (1 + 0.45 * warm), base * (1 + 0.18 * warm), base * (0.95 - 0.1 * warm)], -1)
    grit = noise(N, 48, 2)
    mortar_col = np.stack([0.16 + 0.14 * grit, 0.10 + 0.09 * grit, 0.06 + 0.05 * grit], -1)
    col_rgb = brick * (1 - mortar[..., None]) + mortar_col * mortar[..., None]
    # Height: brick faces up, bevelled edges, pitted; mortar sunk.
    height = np.clip(edge / 0.08, 0, 1) * (0.85 + 0.15 * pits) * (1 - mortar) + 0.1 * rough
    gy, gx = np.gradient(height)
    strength = 6.0
    nx, ny = -gx * strength, gy * strength
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    os.makedirs(OUT, exist_ok=True)
    for name, data in (("sewer_brick_albedo", col_rgb), ("sewer_brick_normal", normal)):
        img = bpy.data.images.new(name, N, N, alpha=False)
        if name.endswith("normal"):
            img.colorspace_settings.name = "Non-Color"
        px = np.ones((N, N, 4))
        # Blender images are stored bottom row first.
        px[..., :3] = np.clip(data[::-1], 0, 1)
        img.pixels = px.ravel()
        img.filepath_raw = os.path.join(OUT, name + ".png")
        img.file_format = "PNG"
        img.save()
        print("[sewer brick] wrote", img.filepath_raw, "mean", np.round(data.reshape(-1, 3).mean(0), 3))


main()
