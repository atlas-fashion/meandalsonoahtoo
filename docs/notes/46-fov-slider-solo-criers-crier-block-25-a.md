## 46. FOV slider, solo criers, crier block 25%, a white-purple moon, less red (2026-10-15)

- **Field of view** (`Graphics.field_of_view`, 55-100 deg vertical, default 75;
  `set_field_of_view` saves it under [controls] like the sensitivity and it is
  in no preset). `player._update_dash_view` takes it as `_base_fov` every frame,
  so the dash / swing / jump kicks ride on top of it. Slider "Field of view"
  under "Mouse sensitivity" in `settings_panel.gd` (title and pause menu).
- **Criers fly solo**: `flyer_pack_max` 1 (was 2). Measured: 36 criers, the
  nearest two 13 m apart.
- **Blocking a crier lets 25% through** (`crier.block_damage_share` 0.25):
  `player.take_damage` uses an attacker's `block_damage_share` when it has one,
  else `block_damage_taken` (10%). Parried 0, unguarded full. Measured with the
  real right mouse button: 50.00 / 12.50 / 0.00.
- **The moon is soft white with a purple hue**: `MOON_COLOUR` (0.86, 0.8, 1.0)
  at `moon_energy` 1.1 (white carries ~2.5x the red's luminance; 2.4 would have
  blown the courts out); sky `moon_color` (0.82, 0.74, 1.0), `moon_intensity`
  3.0, `moon_glow` 0.9, the cloud glow and horizon leaned violet.
- **Less red in the lighting**: torches orange (1.0, 0.5, 0.2) -> amber
  (1.0, 0.64, 0.38) in `TORCH_COLOUR` and torch.tscn, flicker HOT / EMBER
  likewise, `module_torch_energy` 1.3 -> 1.1 to keep the brightness; the
  prison's dome embers, the generator light and the cage niches'
  `WINDOW_COLOUR` pulled from red toward warm. Measured (HUD hidden, mean
  frame colour, 6 corridor views beside torches + the prisons + the courts):
  red/green 2.91 -> 1.62 overall; corridors ~2.4 -> ~2.0, prisons 2.7 -> 1.65,
  courts 3.4 -> 1.35. The torch FLAMES are unchanged.
- Harness trap (again): an entry script that NAMES a class whose script uses an
  autoload (`SettingsPanel.new()` -> `Graphics`) fails to compile and leaves
  the window open forever -- `load()` it at runtime. And the FOV setter saves:
  back up and restore `user://graphics.cfg` around any test of it.
- Bench (RTX 3060, 3440x1440, editor closed): 74.4 fps, worst p99 26.51 ms,
  1105 MB (74.6 / 27.31 / 1102 before).

