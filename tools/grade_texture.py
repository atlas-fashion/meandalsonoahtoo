"""Grade a tileable texture to match the treated Tripo stone.

    blender -b -P tools/grade_texture.py -- in.png out.png [DESAT] [LIFT] [CONTRAST]

The surfaces `build_modules.py` invents -- the reveals of a bored archway, the
lid, the floor slab -- are textured in world space with the project's tileable
stone (see `module_level.gd`). That texture was painted for the pre-Tripo game
and is small orange brick with green moss, and next to the Tripo stone, which
`build_modules.py` pulls toward dark grey, it read as a different building.

This applies the same three operations `grey_albedo()` applies to the Tripo
atlases -- partial desaturation, contrast about the midpoint, then placement --
so both end up in the same family. The defaults are those same values.
"""
import sys
import bpy
import numpy as np

ARGV = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = ARGV[0], ARGV[1]
DESAT = float(ARGV[2]) if len(ARGV) > 2 else 0.82
LIFT = float(ARGV[3]) if len(ARGV) > 3 else 0.80
CONTRAST = float(ARGV[4]) if len(ARGV) > 4 else 1.30

img = bpy.data.images.load(SRC)
px = np.empty(img.size[0] * img.size[1] * img.channels, dtype=np.float32)
img.pixels.foreach_get(px)
px = px.reshape(-1, img.channels)
rgb = px[:, :3]
luma = (rgb * np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)).sum(axis=1)
out = rgb * (1.0 - DESAT) + luma[:, None] * DESAT
out = (out - 0.5) * CONTRAST + 0.5
px[:, :3] = np.clip(out * LIFT, 0.0, 1.0)
img.pixels.foreach_set(px.reshape(-1))
img.filepath_raw = DST
img.file_format = "PNG"
img.save()
before = rgb.mean(axis=0)
after = px[:, :3].mean(axis=0)
print("graded %s -> %s  mean rgb %.2f %.2f %.2f -> %.2f %.2f %.2f"
      % (SRC, DST, before[0], before[1], before[2], after[0], after[1], after[2]))
