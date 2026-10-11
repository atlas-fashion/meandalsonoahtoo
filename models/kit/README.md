# Modular jail kit

Six pieces, generated with Tripo and processed by `tools/prep_kit_asset.py`.
The `*_ready.glb` files are **build artifacts** — never hand-edit them. The raw
`*.glb` next to each one is the Tripo download and is what a rebuild starts from.

## Rebuild

```
blender --background --factory-startup --python tools/prep_kit_asset.py -- \
    models/kit/NAME.glb models/kit/NAME_ready.glb SX SY SZ ORIGIN 512 TRIS
```

| Piece | Size (W × D × H) | Origin | Triangles | Notes |
| --- | --- | --- | --- | --- |
| `wall_panel` | 2.000 × 0.857 × 2.237 | bottom | 1199 | Default course. Detailed on both faces. |
| `wall_cracked` | 2.000 × 0.857 × 2.237 | bottom | 1199 | Variant, interchangeable with `wall_panel`. |
| `wall_window` | 2.000 × 0.857 × 2.237 | bottom | 2000 | Barred grate, recessed. **Detail is on one face only.** |
| `ceiling_slab` | 3.000 × 2.997 × 0.969 | top | 600 | Origin at the top face, so it hangs from the ceiling plane. |
| `cell_door` | 2.200 × 0.200 × 3.000 | bottom | 1200 | Rusted iron bars. |
| `cell_frame` | 3.247 × 1.660 × 3.300 | bottom | 1200 | Stone jambs + lintel; the door sits inside it. |

Walls are 2.237 m per course and stack; `kit_placer.gd` emits `wall_rows` rows.

## Which way round a piece faces

Blender +Y becomes glTF/Godot −Z, and `kit_placer.gd` points each panel's local
−Z at the walkable side. So **the detail face must be on Blender +Y**.

This is not cosmetic. `wall_window`'s grate is on one face only; with the piece
turned round, the grate faces solid rock and the corridor shows a blank wall.
`prep_kit_asset.py` orients by matching bounding-box *extents* by rank, which
cannot tell front from back — it only guarantees the piece is not stretched.
After regenerating any one-sided piece, render all four sides
(`tools/` has no permanent harness for this; write a throwaway one) and confirm
the detail is on +Y before shipping it.

## Traps this kit already hit

* **Decimation tears a generated mesh apart.** Tripo's surface has coincident
  but unwelded vertices, so most edges have no second face and collapse cannot
  merge across them. At a 300-triangle budget the wall panel came out as a cloud
  of loose shards — with the correct size, the correct triangle count and no
  warning. `prep_kit_asset.py` now welds before decimating. Below roughly 900
  triangles the stone courses dissolve into faceted lumps whatever you do.
* **Small details die first.** `wall_window`'s grate is gone at 900 triangles
  and present at 2000. Budget per piece, not per kit.
* **The exporter drops degenerate triangles, so Blender's bounding box is not
  the shipped one.** Collapse can place a merged vertex outside the original
  hull; the box grew 0.494 → 0.566 across decimation, the scale factor was
  computed from the inflated box, and the panel shipped 11% short. The prep
  script now cleans up before measuring and re-imports the written file to check
  its size against the target, failing loudly if it is off by more than 2 mm.
* **Match proportions, do not force them.** Scaling a generated piece onto a
  contract it does not fit stretched the cell door 73.8× on one axis. Measure
  the raw asset first and adapt the module size to it; the kit tiles because the
  pieces agree with each other, not because they match a number chosen up front.
* **Numbers passed on every one of the above.** Render the piece and look at it.
