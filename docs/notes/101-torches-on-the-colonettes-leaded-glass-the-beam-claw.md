## 101. The surgery's torches on the colonettes, leaded glass in the booth, a second claw that beams (2026-10-23)

The user: "Fix all the floating torches in the room. The control room glass
looks bad. fix it. Make more than one claw. The other claw should be a beam of
blue like the enforcer that slows you down, giving the other claw time to catch
up to you. The player should still be able to dodge the claw, so the beam should
stop before the claw crashes down to get the player." Builds on notes 99-100.

### The torches (`scripts/surgery.gd` `_hang_wall_torches`, `_post_near`)

The 16 wall torches hung at every join between two `wallframe`s, on the frames'
front plane (`_inner - 0.05`). **The frame is open at the join**: measured off
the model (a depth profile of its faces at torch height), there is nothing
within x = +-2.40..2.50 of its 5 m width; its end colonettes stand at
+-2.07 (`FRAME_POST_X`), their faces 0.135 in front of its middle
(`FRAME_POST_FRONT`) -- 0.12 behind the plane the torches hung on. So every
torch stood in the air between two colonettes, half a metre out from the brick.
`_build_walls` now records each frame's two colonette faces (`_posts`, scaled
with the frame's width) and each torch goes on the face of the one nearest its
join (within 1 m; none at a way in, as before). Measured: a ray from each torch
back into the wall now meets the frame's collision at 0.115 (it was 0.05, in
front of the collision box but with no stone behind it); side-on renders show
each one against its colonette.

### The booth glass (`scripts/surgery_control.gd` `_glaze`, `_without_panes`)

Note 99's "Glass" (split off `boothwindow` by build_surgery_kit.py) turned out
to be the mullions, the lancet tracery and the top rail as well as the panes,
and the panes are Tripo's crumpled surface with the leading painted on in a
smeared atlas. Drawn see-through (alpha 0.28, roughness 0.2) it read as wet foil:
glints everywhere, nothing clear through it.

- The pane faces are flat-on (|n.z| > 0.8) within `PANE_DEPTH` 0.045 of the
  window's middle plane (measured: ~5 m^2 a side at |z| 0.02-0.03; the ironwork
  stands out to 0.12). `_without_panes` rebuilds the Glass mesh without them
  (cached per source mesh); the ironwork stays, opaque, in its own picture.
- Behind it one flat `QuadMesh` (`PANE_X` 2.57, `PANE_Y` 0.81..2.33, model
  frame) with **shaders/surgery_glass.gdshader**: a new Higgsfield picture,
  `textures/surgery_glass.png` (gpt_image_2_5 high, 1.5 credits; the source is
  `models/source/surgery_hf/ref_glass.png`) -- diamond quarries, dark cames. The
  cames (luminance under 0.28..0.5) are opaque dark lead, the quarries tinted
  and alpha `clear_alpha` 0.16. Mapped in metres off the pane (`tile` 1.1 a
  metre, `scale` the window's), so the end window's diamonds are the same size.
- The texture imported at compress/mode=0, mipmaps off: patched to 2 / on.
- Headless the dummy renderer keeps no mesh arrays: `_without_panes` returns
  the mesh whole then.

### The beam claw (`scripts/surgery_beam_claw.gd`, new)

A second claw on the same gantry: a **second girder** on the bridge
`BEAM_GIRDER_Z` 1.4 m along +Z (surgical_table.gd `_build_gantry`, the girder
section at 0.78 scale, 0.05 lower so the trolley hangs from it), its own
trolley (the kit's `ring` at 0.28) and telescoping arm (`segment`), the
kit's `claw` at 0.72 lit **blue** (its own duplicated materials -- `glow`
shares materials between copies, and the grabbing claw recolours its own every
frame). No new model. The two trolleys clear each other passing (0.85 + 0.48 <
1.4), so it is free along the bridge.

- It is driven by the table: `beamer`, made in `_ready`, `tick(delta)` each
  physics frame after the table's own, posed in its own `_process`. States
  follow the table's: DORMANT parked at `PARK_X` 3.5, drawn up; WAKING pays
  out; HUNT / REAR hunts; CARRY / STRAP stands off over the table; DYING falls
  (`_fall`, onto whatever `_under` finds -- floor or a bookcase's top -- with
  `_impact_fx` 0.6); a save with the machine off: `lie_dead`, settled on the
  first tick.
- **The head rides its arm**: carried with the bridge (`_last_bz`) and its
  trolley (`_drive_x`); its own drive (`HEAD_SPEED` 7.5, `HEAD_ACCEL` 24) only
  reaches it out. A free point following a goal lagged the bridge by up to a
  metre and ran into the other claw.
- **Where:** `_choose_spot` every 0.2 s, two rings (`SPOT_NEAR` 1.4,
  `SPOT_FAR` 2.4) round the target's chest, the wrist at `WRIST_Y` 5.6 (the
  fingertips clear the 3.9 m shelves), within `REACH_Z` 2.8 of its rail, the
  nearest with a **clear ray** from its muzzle to their chest. Kept as an
  offset from them (they and the bridge move). `_keep_off`, every tick against
  where the other claw is now: always `SIDE_MARGIN` 1.35 on its rail's side
  (+Z) of the other wrist -- so its arm, running out along Z from its rail,
  never crosses the other's -- and out of `KEEP_OFF` 1.4; at the far wall,
  stood aside along the bridge instead.
- **The beam** (the enforcer's: additive core and glow tubes, `CRYSTAL` /
  `HOT`, a flare where it lands, a light under `Graphics.effects`; drawn
  `SHORT_OF_PLAYER` 0.5 short of them): it may start `BEAM_LEAD` 2.0 s before
  the other claw may slam (its `_next_rear`), with a clear line, within
  `BEAM_RANGE` 14; charges `CHARGE_TIME` 0.7 (the fingers whiten); fires up to
  `BEAM_TIME` 3.2 s, `player.beam_hit(BEAM_DPS 3, ...)` -- slowed to
  `beam_slow` 0.45 (the HUD's beam edge shows it); blocked by a shelf it burns
  there and gives up after `LOST_LINE` 0.5 s; rests `BEAM_REST` 2.2 s.
- **Dodgeable** -- surgical_table.gd `_hunt`: over them and ready, the slam
  first cuts the beam (`beamer.cut()`) and begins only `BEAM_CLEAR` 0.2 s
  after the beam was last on (`last_fired`). The slow lingers player.gd
  BEAM_LINGER 0.35 s and WIND is 0.35 s, so they are at full speed from 0.2 s
  before TRACK begins -- through TRACK, LOCK and DROP. Without BEAM_CLEAR the
  two 0.35 s were a race: one slam in eleven began TRACK with the player still
  slowed.
- The bridge stops `bound + 0.25 - BEAM_GIRDER_Z` short of the +Z end
  (`_drive` `hi_z`), 0.55 m less than before, so the second girder stays off
  that wall's frames.

### Measured (windowed harnesses, the real level)

A player walking round the table (and, a second run, round the maze ring at
7.4 m, through the shelves), moved at their speed times `_beam_speed_scale()`,
dodging straight away at 4.25 m/s x that scale from the moment the claw locks:
over 60 s, 7 slams each run -- beam on at a slam's start 0, slowed at TRACK's
start 0, **grabbed 0**; the beam on 332-416 frames, the player slowed 362-508
(it fires in the maze too: the spot search finds lines down the aisles). The
claws' wrists never nearer than 0.97 m (in the maze run 1.02; before
`_keep_off` and the carried head: 0.24); the beam head never under 5.57 m.
Switched off: both claws down (state 9), the beam claw on the floor; restored
dead from a save: lying, `_fell`. The check can fail: before BEAM_CLEAR existed
its "slowed at TRACK" count was 1 (of 11 slams), not 0. Clean runs
(`--quit-after 1500 -- --skip-title`, twice): no errors or warnings.

Benchmark, RTX 3060, 3440x1440, editor closed: surgery 40.7 / 36.3 fps, p99
36.43 / 45.83 ms (two runs) against 36.8 fps, p99 39.17 before -- inside the
noise: every station moved as much between runs (boss room centre 112.7, 45.9,
31.7 fps). The machine sleeps at the benchmark's camera, so the beam is not
drawn there; it adds one light and two tubes when it fires. Video memory
1337-1342 MB (1336.5 before; the glass texture).

### Traps

- An open model frame has nothing at its ends: hang things on what is there
  (measure the faces), not on the bounding box's plane.
- A Tripo window's "glass" is a surface like any other: crumpled, and with the
  ironwork in it. Split it again by depth, not by rectangle.
- A follower driven as a free point lags a moving base; carry it with its base
  and drive only the offset.
- Two 0.35 s constants (the slow's linger, the slam's wind) are a race, not a
  guarantee: give it a margin of its own.
