"""The dungeon kit's three tiling materials (note 183), made from nothing in numpy.

    blender -b --python tools/dungeon_kit_textures.py

Writes models/dungeon/dk_{stone,wood,iron}_{albedo,normal,orm}.jpg. Run by
tools/build_dungeon_kit.py's README step; the kit's meshes carry no textures of
their own (scripts/brick_level.gd builds the three materials from these files).

Every map TILES: the noise is made in frequency space (random phases under a
power-law spectrum, inverse FFT), which wraps by construction, and the cell
noise (pits, cracks) measures its distances round the edges. Height comes
first; the normal map is its slope, the occlusion its hollows (height against
a blurred copy of itself), and colour and roughness are read off both.

  stone  2048 x 2048 for 2.0 x 2.0 m: rough-hewn dark stone -- broad dressing
         marks, pick pits, hairline cracks, damp patches that shine, pale
         lichen. NO joints: the kit's stones are separate geometry and each
         takes its own patch of this.
  wood   1024 x 2048 for 1.0 x 2.0 m, grain along v: old oak, checked and grey.
  iron   1024 x 1024 for 1.0 m: forged iron, pitted, rust in blotches (blue
         channel of the ORM is metal).
"""
import os
import sys

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "models", "dungeon")


def log(*a):
    print("[dk_tex]", *a, flush=True)


def fbm(shape, size_m, beta, seed, lo=0.0, hi=1e9, aniso=(1.0, 1.0)):
    """Tiling fractal noise, mean 0, std 1. `lo`/`hi` in cycles per metre;
    `aniso` scales the (v, u) frequencies -- (8, 1) stretches features along v."""
    h, w = shape
    rng = np.random.default_rng(seed)
    fv = np.fft.fftfreq(h)[:, None] * h / size_m[1]
    fu = np.fft.rfftfreq(w)[None, :] * w / size_m[0]
    f = np.sqrt((fv * aniso[0]) ** 2 + (fu * aniso[1]) ** 2)
    f[0, 0] = 1.0
    amp = f ** (-beta)
    amp[(f < lo) | (f > hi)] = 0.0
    amp[0, 0] = 0.0
    spec = amp * np.exp(1j * rng.uniform(0.0, 2.0 * np.pi, amp.shape))
    img = np.fft.irfft2(spec, s=(h, w))
    img -= img.mean()
    return (img / (img.std() + 1e-12)).astype(np.float32)


def blur(img, sigma_px):
    """Gaussian blur that wraps."""
    h, w = img.shape
    fv = np.fft.fftfreq(h)[:, None]
    fu = np.fft.rfftfreq(w)[None, :]
    k = np.exp(-2.0 * (np.pi * sigma_px) ** 2 * (fv * fv + fu * fu))
    return np.fft.irfft2(np.fft.rfft2(img) * k, s=(h, w)).astype(np.float32)


def worley(shape, cells, seed, warp=None):
    """Tiling cell noise: (F1, F2, cell id) with distances in cell widths.
    `warp` (dv, du in 0..1 units) bends the sample points."""
    h, w = shape
    rng = np.random.default_rng(seed)
    gy, gx = cells
    pts = rng.uniform(0.0, 1.0, (gy, gx, 2)).astype(np.float32)
    v = (np.arange(h, dtype=np.float32)[:, None] + 0.5) / h * np.ones((1, w), np.float32)
    u = (np.arange(w, dtype=np.float32)[None, :] + 0.5) / w * np.ones((h, 1), np.float32)
    if warp is not None:
        v = (v + warp[0]) % 1.0
        u = (u + warp[1]) % 1.0
    cv = v * gy
    cu = u * gx
    iv = np.floor(cv).astype(np.int32)
    iu = np.floor(cu).astype(np.int32)
    f1 = np.full(shape, 9.0, np.float32)
    f2 = np.full(shape, 9.0, np.float32)
    ident = np.zeros(shape, np.int32)
    for dv in (-1, 0, 1):
        for du in (-1, 0, 1):
            jv = iv + dv
            ju = iu + du
            p = pts[jv % gy, ju % gx]
            d = np.sqrt((jv + p[..., 0] - cv) ** 2 + (ju + p[..., 1] - cu) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ident = np.where(closer, (jv % gy) * gx + (ju % gx), ident)
            f1 = np.where(closer, d, f1)
    return f1, f2, ident


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def colour(c):
    return np.array(c, np.float32)[None, None, :]


def normal_from(height, px_m, strength):
    """Tangent-space normal (OpenGL, +Y up) from a height map in metres. Row 0
    is the BOTTOM of the image, as Blender stores pixels."""
    dv = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / (2.0 * px_m[1])
    du = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / (2.0 * px_m[0])
    n = np.stack([-du * strength, -dv * strength, np.ones_like(height)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def cavity_of(height, radius_px, scale):
    """0 on the flat and proud, towards 1 in the hollows."""
    return np.clip((blur(height, radius_px) - height) / scale, 0.0, 1.0)


def to_srgb(lin):
    lin = np.clip(lin, 0.0, 1.0)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1.0 / 2.4) - 0.055)


def save(name, rgb, srgb):
    h, w = rgb.shape[:2]
    px = np.ones((h, w, 4), np.float32)
    px[..., :3] = to_srgb(rgb) if srgb else np.clip(rgb, 0.0, 1.0)
    im = bpy.data.images.new(name, w, h, alpha=False)
    im.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    im.pixels.foreach_set(px.ravel())
    path = os.path.join(OUT, name + ".jpg")
    # The bytes are already sRGB: saved as they are (save_render would push
    # them through the view transform).
    im.filepath_raw = path
    im.file_format = "JPEG"
    im.save()
    log("wrote %s  %dx%d  mean %.3f" % (os.path.basename(path), w, h, float(rgb.mean())))
    bpy.data.images.remove(im)


def save_data(name, rgb):
    """Non-colour maps, bytes as they are."""
    h, w = rgb.shape[:2]
    px = np.ones((h, w, 4), np.float32)
    px[..., :3] = np.clip(rgb, 0.0, 1.0)
    im = bpy.data.images.new(name, w, h, alpha=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(px.ravel())
    path = os.path.join(OUT, name + ".jpg")
    im.filepath_raw = path
    im.file_format = "JPEG"
    im.save()
    log("wrote %s  %dx%d  mean %.3f" % (os.path.basename(path), w, h, float(rgb[..., :3].mean())))
    bpy.data.images.remove(im)


# --- stone -------------------------------------------------------------------------

def stone():
    n = 2048
    shape = (n, n)
    size = (2.0, 2.0)
    px = (size[0] / n, size[1] / n)
    # Broad lumps left by the mason's axe, then smaller ones.
    big = fbm(shape, size, 2.3, 11, lo=0.4, hi=5.0)
    mid = fbm(shape, size, 1.7, 12, lo=4.0, hi=40.0)
    fine = fbm(shape, size, 1.0, 13, lo=40.0, hi=400.0)
    # Dressing marks: short parallel strokes, in patches, two directions.
    tool_a = fbm(shape, size, 0.6, 14, lo=18.0, hi=140.0, aniso=(1.0, 0.12))
    tool_b = fbm(shape, size, 0.6, 15, lo=18.0, hi=140.0, aniso=(0.12, 1.0))
    where = fbm(shape, size, 2.0, 16, lo=0.5, hi=3.0)
    tool = np.where(where > 0.0, tool_a, tool_b) * smooth(np.abs(where), 0.15, 0.7)
    warp = (fbm(shape, size, 2.2, 19, lo=0.5, hi=6.0) * 0.012, fbm(shape, size, 2.2, 20, lo=0.5, hi=6.0) * 0.012)
    # Pick pits, of two sizes, ragged (the sample points bent by fine noise).
    jit = (fbm(shape, size, 1.0, 26, lo=20.0, hi=120.0) * 0.0025, fbm(shape, size, 1.0, 27, lo=20.0, hi=120.0) * 0.0025)
    pits = np.zeros(shape, np.float32)
    for cells, share, seed in ((52, 0.30, 17), (23, 0.22, 18)):
        f1, _, ident = worley(shape, (cells, cells), seed, jit)
        rng = np.random.default_rng(seed + 100)
        on = (rng.uniform(0, 1, cells * cells) < share)[ident]
        rad = rng.uniform(0.12, 0.42, cells * cells).astype(np.float32)[ident]
        pits = np.maximum(pits, smooth(f1, rad, rad * 0.25) * on * (0.5 + rad * 1.4))
    # Hewn facets: each cell a tilted plane, as a point or an axe leaves it.
    fa, _, fid = worley(shape, (13, 13), 28, (warp[0] * 1.6, warp[1] * 1.6))
    frng = np.random.default_rng(29)
    tilt = frng.normal(0.0, 1.0, (169, 2)).astype(np.float32)
    vv = (np.arange(n, dtype=np.float32)[:, None] + 0.5) / n * 13.0
    uu = (np.arange(n, dtype=np.float32)[None, :] + 0.5) / n * 13.0
    facet = (np.sin(vv * 2.0 * np.pi / 13.0 * 3.0 + tilt[fid, 0] * 6.0) * tilt[fid, 0]
             + np.cos(uu * 2.0 * np.pi / 13.0 * 3.0 + tilt[fid, 1] * 6.0) * tilt[fid, 1])
    facet = blur((facet + frng.normal(0.0, 0.6, 169).astype(np.float32)[fid]).astype(np.float32), 3.0)
    # Larger spalls: shallow flakes gone from the face.
    s1, s2, sid = worley(shape, (9, 9), 21, warp)
    spall_on = (np.random.default_rng(22).uniform(0, 1, 81) < 0.25)[sid]
    spall = smooth(s1, 0.45, 0.22) * spall_on
    # Hairline cracks: where a broad noise crosses zero, in the few places a
    # mask lets them -- long wandering lines, not a net.
    line = fbm(shape, size, 2.4, 23, lo=0.4, hi=6.0) + fbm(shape, size, 1.2, 25, lo=6.0, hi=60.0) * 0.06
    crack_mask = smooth(fbm(shape, size, 2.0, 24, lo=0.5, hi=2.0), 0.5, 1.2)
    crack = smooth(np.abs(line), 0.022, 0.0) * crack_mask
    height = (big * 0.0055 + mid * 0.0034 + fine * 0.00050 + tool * 0.0014 + facet * 0.0022
              - pits * 0.0042 - spall * 0.0050 - crack * 0.0060)
    height = height.astype(np.float32)
    normal = normal_from(height, px, 1.0)
    cav = cavity_of(height, 5.0, 0.0035)
    cav_wide = cavity_of(height, 28.0, 0.008)

    # Colour: a dark blue-grey stone, warmer where it has weathered, with the
    # hollows dark and dusty and the proud parts scuffed pale.
    tone = fbm(shape, size, 2.0, 30, lo=0.4, hi=3.0)
    tone2 = fbm(shape, size, 1.5, 31, lo=3.0, hi=30.0)
    # Bedding: faint bands along u, as sedimentary stone shows on a cut face.
    bed = fbm(shape, size, 1.4, 37, lo=2.0, hi=60.0, aniso=(1.0, 0.06))
    col = lerp(colour((0.092, 0.095, 0.106)), colour((0.215, 0.206, 0.196)),
               smooth(tone * 0.45 + tone2 * 0.35 + bed * 0.3 + facet * 0.25, -1.2, 1.2)[..., None])
    warm = smooth(fbm(shape, size, 2.1, 32, lo=0.4, hi=4.0), 0.3, 1.5)[..., None]
    col = lerp(col, col * colour((1.22, 1.02, 0.80)), warm * 0.6)
    proud = smooth(height - blur(height, 14.0), 0.0006, 0.0035)[..., None]
    col = col * (1.0 + 0.30 * proud)
    col = col * (1.0 - 0.55 * cav[..., None]) * (1.0 - 0.35 * cav_wide[..., None])
    speck = fbm(shape, size, 0.3, 33, lo=150.0, hi=900.0)[..., None]
    col = col * (1.0 + 0.07 * speck)
    col = lerp(col, colour((0.030, 0.028, 0.027)), (crack * 0.85)[..., None])
    # Lichen: pale grey-green crusts, sparse.
    lich = smooth(fbm(shape, size, 1.9, 34, lo=1.0, hi=12.0), 1.25, 1.9) * smooth(fbm(shape, size, 0.8, 35, lo=30.0, hi=200.0), -0.3, 0.6)
    col = lerp(col, colour((0.23, 0.25, 0.20)), (lich * 0.55)[..., None])
    # Damp: darker and glossy, in the low parts of broad patches.
    damp = smooth(fbm(shape, size, 2.2, 36, lo=0.4, hi=3.5) + cav_wide * 1.2, 0.5, 1.4)
    col = col * (1.0 - 0.32 * damp[..., None])
    rough = 0.90 - 0.10 * proud[..., 0] + 0.06 * cav - 0.42 * damp + 0.03 * speck[..., 0]
    rough = np.clip(rough, 0.3, 1.0)
    ao = 1.0 - 0.55 * cav - 0.3 * cav_wide
    orm = np.stack([np.clip(ao, 0.0, 1.0), rough, np.zeros_like(rough)], -1)
    save("dk_stone_albedo", col, True)
    save_data("dk_stone_normal", normal)
    save_data("dk_stone_orm", orm)


# --- wood --------------------------------------------------------------------------

def wood():
    shape = (2048, 1024)
    size = (1.0, 2.0)
    px = (size[0] / shape[1], size[1] / shape[0])
    # Grain: long along v.
    grain = fbm(shape, size, 1.1, 41, lo=6.0, hi=500.0, aniso=(14.0, 1.0))
    wave = fbm(shape, size, 2.0, 42, lo=0.5, hi=3.0, aniso=(3.0, 1.0))
    u = (np.arange(shape[1], dtype=np.float32)[None, :] + 0.5) / shape[1]
    # Growth rings cut lengthways: bands across u, wandering. 9 whole bands so it tiles.
    rings = np.sin((u * 9.0 + wave * 0.35) * 2.0 * np.pi)
    late = smooth(rings, 0.2, 0.95)
    fine = fbm(shape, size, 0.8, 43, lo=80.0, hi=600.0, aniso=(6.0, 1.0))
    # Checks: long dark splits where the grain noise runs deep.
    deep = fbm(shape, size, 1.3, 44, lo=3.0, hi=60.0, aniso=(22.0, 1.0))
    check = smooth(deep, 1.35, 2.1)
    # Wear across the grain: gouges and adze marks.
    adze = fbm(shape, size, 1.6, 45, lo=1.0, hi=10.0, aniso=(1.0, 0.35))
    height = (grain * 0.0011 + late * 0.0006 + fine * 0.0002 - check * 0.0045 + adze * 0.0016).astype(np.float32)
    normal = normal_from(height, px, 1.0)
    cav = cavity_of(height, 4.0, 0.0025)
    tone = fbm(shape, size, 2.0, 46, lo=0.4, hi=3.0, aniso=(4.0, 1.0))
    col = lerp(colour((0.040, 0.029, 0.021)), colour((0.098, 0.074, 0.052)), smooth(tone * 0.5 + grain * 0.5, -1.3, 1.3)[..., None])
    col = col * (1.0 - 0.28 * late[..., None])
    # Weathered grey on what stands proud.
    proud = smooth(height - blur(height, 10.0), 0.0003, 0.002)[..., None]
    col = lerp(col, colour((0.120, 0.114, 0.104)), proud * 0.6)
    col = col * (1.0 - 0.6 * cav[..., None])
    col = lerp(col, colour((0.014, 0.011, 0.009)), (check * 0.9)[..., None])
    stain = smooth(fbm(shape, size, 2.2, 47, lo=0.4, hi=2.5), 0.5, 1.6)[..., None]
    col = col * (1.0 - 0.35 * stain)
    rough = np.clip(0.80 - 0.12 * proud[..., 0] + 0.1 * cav - 0.18 * stain[..., 0], 0.4, 1.0)
    ao = np.clip(1.0 - 0.6 * cav - 0.5 * check, 0.0, 1.0)
    save("dk_wood_albedo", col, True)
    save_data("dk_wood_normal", normal)
    save_data("dk_wood_orm", np.stack([ao, rough, np.zeros_like(rough)], -1))


# --- iron --------------------------------------------------------------------------

def iron():
    n = 1024
    shape = (n, n)
    size = (1.0, 1.0)
    px = (size[0] / n, size[1] / n)
    big = fbm(shape, size, 2.0, 51, lo=1.0, hi=10.0)
    mid = fbm(shape, size, 1.4, 52, lo=10.0, hi=90.0)
    fine = fbm(shape, size, 0.7, 53, lo=90.0, hi=500.0)
    f1, _, ident = worley(shape, (60, 60), 54)
    on = (np.random.default_rng(55).uniform(0, 1, 3600) < 0.4)[ident]
    pits = smooth(f1, 0.4, 0.05) * on
    # Rust: scabbed blotches, thick in broad patches, standing a little proud.
    rust = smooth(big * 0.7 + mid * 0.45, 0.0, 1.3)
    scab = rust * smooth(mid, -0.5, 1.0)
    # Hammer facets on the bare metal.
    h1, _, _ = worley(shape, (14, 14), 56)
    facet = smooth(h1, 0.0, 0.7)
    height = (facet * 0.0010 * (1.0 - rust) + scab * 0.0016 + fine * 0.00025 - pits * 0.0022).astype(np.float32)
    normal = normal_from(height, px, 1.0)
    cav = cavity_of(height, 4.0, 0.002)
    bare = lerp(colour((0.030, 0.030, 0.032)), colour((0.085, 0.082, 0.080)), smooth(fine + mid * 0.5, -1.0, 1.5)[..., None])
    rcol = lerp(colour((0.038, 0.019, 0.011)), colour((0.090, 0.043, 0.019)), smooth(mid + fine * 0.6, -1.0, 1.2)[..., None])
    rcol = lerp(rcol, colour((0.020, 0.013, 0.010)), smooth(big, 0.4, 1.6)[..., None] * 0.6)
    col = lerp(bare, rcol, rust[..., None])
    col = col * (1.0 - 0.6 * cav[..., None])
    rough = np.clip(lerp(0.42 + 0.08 * fine, 0.88 + 0.05 * fine, rust), 0.25, 1.0)
    metal = np.clip(lerp(0.92, 0.10, smooth(rust, 0.15, 0.75)), 0.0, 1.0)
    ao = np.clip(1.0 - 0.6 * cav, 0.0, 1.0)
    save("dk_iron_albedo", col, True)
    save_data("dk_iron_normal", normal)
    save_data("dk_iron_orm", np.stack([ao, rough, metal], -1))


def main():
    os.makedirs(OUT, exist_ok=True)
    only = [a for a in sys.argv if a in ("stone", "wood", "iron")]
    for name, fn in (("stone", stone), ("wood", wood), ("iron", iron)):
        if not only or name in only:
            fn()


if __name__ == "__main__":
    main()
