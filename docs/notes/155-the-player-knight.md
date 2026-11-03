## 155. The player is the molten rust knight (2026-11-03)

The user's armoured knight (front and back concept views,
`models/source/knight/knight_front.png`, `knight_back.png`) is now the player's
body.

### Where it came from

- Generated on Higgsfield: **Meshy multi-image to 3D**, textured and auto-rigged,
  35 credits. The Higgsfield connector on this account is read-only (history,
  catalog, balance: no generate tool), and higgsfield.ai has no 3D page, so it
  was run through the site's **Supercomputer** agent in the built-in browser
  (the user signed in and accepted the media upload agreement themselves).
  The agent first proposed single-image with rigging off; asking again in the
  chat fixed it. It then offered a second "corrected" job for another 35 --
  stopped; the first was already done (`show_generations` lists it).
- Getting local files into that page: the pane has no file-upload tool, the
  native picker never appears, synthetic Ctrl+V does not paste the system
  clipboard, `navigator.clipboard.read` needs focus the hidden pane lacks, and
  the page's CSP blocks `fetch`/`<img>` from localhost. What worked: the images
  pushed to the (public) repo and fetched from `cdn.jsdelivr.net/gh/...@<sha>/`
  (jsDelivr is in its `connect-src`), then a synthetic `paste` event with a
  `DataTransfer` of `File`s on the prompt's contenteditable.
- `tools/tripo.ps1` (the direct Tripo route) gained `-BackImage`
  (multiview_to_model, front + back). Untested end to end: the project's Tripo
  key had 0 credits.
- Raw: `models/source/knight/knight_meshy.glb`, 31k triangles, 1.70 m, T-pose,
  24 bones, facing glTF +Z, plus a stray 2 m icosphere (Meshy ships one; the
  surgeon had it too) and a one-frame `clip0`.

### The build (`tools/build_player_knight.py` -> `models/player_knight.glb`)

Drops the icosphere and the clip; cuts an **emission map out of the albedo**
where it is hot (max channel > 0.55 ramping to 0.8, saturation > 0.45, r >= g >
1.2 b; one texel of spread): 5.8% of texels, the molten cracks; metallic 0.55,
roughness 0.62 (Meshy: 0 / 0.8). 2048 albedo, JPEG.

### The body (`scripts/coop_avatar.gd`, the old co-op stand-in's file)

- **Alone: shadow only** (`SHADOWS_ONLY`, layer `SOLO_LAYER` = 1 << 13, which is
  split_screen `AVATAR[0]` and unused outside co-op). The knight casts the
  player's shadow for the moon and every lit wall torch, is never drawn, so it
  cannot clip the camera. Made in player.gd `_ready` (`_make_body`).
- **Co-op: the visible body** the other half sees, replacing the hooded
  primitive figure; player.gd `set_view_layers` calls `set_mode(AVATAR[i],
  true)` on the existing body. Sword / spear / torch props and the name label
  as before; it casts a shadow while the knob is on.
- Scale 1.05: visor at the 1.6 m eye, crest 1.79 m inside the 1.8 m capsule.
  Turned 180 degrees (glTF +Z forward). `GLOW` 2.2 on the emission.
- **Posed procedurally, nothing baked.** Limb segments are aimed at directions
  in knight space (+Z forward, +X its left) by the shortest turn from their rest
  direction, under the turn their parents already have (`_aim`); trunk and head
  get rotations (`_turn`). `_set_bone` turns a rest-relative skeleton-space
  rotation into the local pose: `local = rest_local * (rest_global^-1 * e *
  rest_global)`, so the rig's own bone axes never matter and any humanoid with
  Meshy's bone names drops in. Stride (thigh 0.42 rad, knee 0.7), arm swing,
  hips yaw, spine and head follow `_look_pitch`; sword arm: wind-up -> cut over
  0.35 s of `_pose_time`, guard across the body, spear level; dead lies down and
  drops what it holds; hidden is gone.
- Bones (parent chains): Hips -> LeftUpLeg/RightUpLeg -> Leg -> Foot -> ToeBase;
  Hips -> Spine02 -> Spine01 -> Spine -> Left/RightShoulder -> Arm -> ForeArm ->
  Hand, and Spine -> neck -> Head.
- Measured on the poses (harness, windowed): right hand at +X (the player's
  right), the idle blade along -Z (forward), wind-up hand at 2.0 m, walking foot
  lifting 0.3 m.

### The knob

`Graphics.body_shadow` ("Your shadow" in the settings): on in every preset but
Potato (no shadows there anyway). Off: the lone player has no body at all (not
processed); a co-op body is still drawn, unshadowed.

### Measured (RTX 3060, 3440x1440, High, `--bench --set=body_shadow=...`)

```
                   off avg / p99      on avg / p99
spawn corridor     15.03 / 17.98      15.33 / 17.33
boss room centre   12.73 / 14.70      12.72 / 14.33
boss room edge     11.58 / 15.34      11.37 / 12.50
outer maze         11.72 / 12.98      12.15 / 14.50
chest room         18.42 / 20.25      18.46 / 20.18
surgery            17.97 / 20.83      18.03 / 22.01
OVERALL            71.1 fps           70.6 fps
```

About 0.3-0.4 ms where several torches see the player (spawn corridor, outer
maze; +0.1-0.4M primitives a station: the knight in each shadow pass), noise
elsewhere. Video memory the same both ways (the knight is loaded either way).

### Traps

- `tools/benchmark.gd --shot` gained a `shadow` view (back to a torch, looking
  down), but its torch is often not yet among the lit ones when the shot is
  taken, so it can come out black; the harness with its own shadowed omni was
  the real check.
- The first `for side in [1.0, -1.0]` would not infer `a`'s type: give the loop
  variable a type.
