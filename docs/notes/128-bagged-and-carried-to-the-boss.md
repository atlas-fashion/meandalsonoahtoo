## 128. Bagged and carried to the boss: after the surgeon, a sack over the head, carried to the throne hall, a scout hooks it off; the great door wants no shards (2026-10-29)

The ask (from Noah, through the project coordinator): replace walking to the
great door and setting the shards in it. After the surgeon dies, a bag goes
over the player's head and they are carried to the boss room. One of two
scouts pulls the bag off. Remove the crystal (shard) requirement from the
boss gate. Leave a clear place for a long cutscene, which will be asked for
separately, then start the boss fight. Co-op must keep working.

### The sequence (`scripts/boss_abduction.gd`)

Started by maze.gd `take_to_the_boss(delay)`:
- by surgery_control.gd at the end of `_take_his_claw` (note 111), once the
  claw is kept;
- by surgery.gd `_on_surgeon_defeated` when no claw scene is coming (he died
  without the claw: `_claw_waiting` and `_busy` both false);
- on loading a save with the claw kept and `taken_to_boss` false
  (`_resume_abduction`, after `restore_player`), 2.5 s in. This covers a save
  made part way through, and saves from before this note.

It waits until every live player is free (no scene, menu, wheel, hiding
place, climb or rat's eyes). The dead are left to rise at their anchor.

1. **The sack comes down.** Each player gets `begin_cutscene` and
   `hands_busy`, and a `CanvasLayer` "Sack" (layer 38: over the HUD, under
   the letterbox) under `Coop.ui_root(p)`, so it covers only their half in
   co-op. It holds a ColorRect 1.2x the view with `shaders/burlap_bag.gdshader`.
   The rect drops from above in 0.22 s. Then the letterbox, a 0.45 shake, the
   eye yanked back (`scene_lean`), and a four-beat struggle.
2. **Carried** for `CARRY_TIME` 6 s, slung over a shoulder: lean (0.22, 0.32,
   0.2), 24 degree roll, a stride bob every 0.36 s. The weave sways
   (`drift`), and every fourth step a torch passes outside (`glow` up to
   0.35-0.6 and back to 0.08). After 0.6 s, while nobody can see,
   `_set_the_hall` runs:
   - the great door is opened at once (`shard_door.open_now`);
   - each player is put on the hall floor `KNEEL_SHARE` 0.42 of the way from
     the arch to the boss's spot, facing him, `KNEEL_APART` 1.9 m apart in
     co-op;
   - a scripted scout stands `SCOUT_OFF` 2 m in front of each player, facing
     them. Solo, the second scout stands guard 1.6 m behind.
3. **Dropped to their knees**: `KNEEL_LEAN` (0, -0.62, -0.15), a 0.55
   shake, the view on the scout's head. The shader's `see` rises to 0.6, so
   the hall's torchlight shows blurred through the holes in the weave.
   `KNELT_TIME` 1.6 s.
4. **Hooked off.** Each scout plays the body move "unhood" (co-op: the
   second one `SECOND_DELAY` 0.4 s later):
   - The spear reaches out slow (P_HOOK). Through t 0.25 to `HOOK_AT` 0.95
     the scene walks the scout in or out (`scripted_walk` = 3.5 x the
     forward error, capped at 1.2 m/s) until the point is at the sack's
     crown (camera + 0.1 m up), and pitches the point at it
     (`scripted_pitch`).
   - At HOOK_AT the overlay is jerked up and aside (0.3 s), and a sack
     appears in the world on the barbs: a frozen RigidBody3D, a burlap
     capsule with a cord, the weave drawn into a 32 px texture.
   - The spear flicks up and back (P_FLICK). At `LET_GO` 1.32 the sack is
     thrown back over the scout's shoulder (`SACK_BACK` 2.4, `SACK_UP` 3.2
     m/s), lands and is freed after 25 s.
   - The move is done at `UNHOOD_END` 2.3.
5. **`_long_scene()` -- THE PLACEHOLDER for the long cutscene.** It emits
   `long_scene_reached`, prints `[abduction] long cutscene hook
   (placeholder)`, and waits `LONG_SCENE_STANDIN` 1.5 s. When it is called:
   - everyone is still in the scene, letterboxed, kneeling, unbagged;
   - each player looks up at their scout (`_entries[i]["scout"]`);
   - solo, `_guard` stands behind them;
   - the boss is held on his dais (`caged`).

   Replace the wait with the scene. Return when it is over.
6. **The scouts go.** The view turns to the boss and the players stand.
   The scouts walk toward the arch at `SCOUT_EXIT_SPEED` 2.2. Each one is
   freed once it is behind every player's view, or out through the arch.
   All are freed after `SCOUT_EXIT_MAX` 7 s.
7. **The fight.** The boss is let go (`caged = false`, `alert()`) and the
   scene ends. The boss engages with them inside his zone, and maze.gd
   `_update_seal` drops the portcullis as for any fight.
   `_on_taken_to_boss` sets `taken_to_boss` (saved).

**The boss through the scene**: enemy.gd `caged` (note 120) holds him:
blind, deaf, unhurt and not engaged, so the portcullis stays up while the
scouts are in the hall.

### Scripted scouts (`scout.gd`, `scout_body.gd`)
- scout.gd `scripted`: `_physics_process` hands every tick to
  `_scripted_step`. That means no AI, no patrol and no blows; `take_damage`
  returns.
  - It walks at `scripted_walk` and turns to `scripted_face` (or the way it
    walks) at TURN_RATE.
  - It feeds the body `scripted_look`, `scripted_move` /
    `scripted_move_t` and `scripted_pitch`, posed every frame
    (`lod_distance` 0).
- scout_body.gd: P_HOOK, P_FLICK and the MOVES entry "unhood". The aim pitch
  only applies in a move, as before.

### The great door (`shard_door.gd`)
- `need_shards` (false): the prompt reads "E   Open". Once the surgery is
  done (`maze.surgery_done`, unchanged), E plays the door's own opening
  scene with every socket filled. Before that it still refuses with the
  surgery toast. This is the way back in after a death in the boss fight:
  the abduction plays only once.
- `open_now()`: the restore path's instant opening, now shared with the
  abduction.
- The containment blocks still give their shards (relics with no use now).
  The surgery still stays bolted until every block is open (note 120), so
  progression is unchanged up to the surgeon.

### Measured (throwaway windowed harness, deleted)
The harness used seed 20260918. It set the table dead, ran the surgeon's
`leave()` (which arms him with the claw), killed him with `set_dead_now`,
and called `_on_surgeon_defeated`, so the real claw scene ran and handed
over.

Solo, 0 failures:
- The door refused before the surgery.
- Claw scene, claw kept, abduction started.
- 1 sack, 2 scouts, carried into the boss's zone, 0.000 m off the hall
  floor.
- The boss never engaged during the scene.
- The point was 0.21 m from the sack's crown at the hook.
- Long-scene hook reached.
- Sacks gone, scouts gone, scene ended, the boss caged off and engaged, the
  hall sealed (`_boss_committed`).
- Door open, `taken_to_boss` saved.
- The sack lay on the floor (0.14 m up) 6.9 m off.
- `take_to_the_boss` again: nothing. Resume with `taken` false: it starts.

Co-op (`Coop.start()` before main): the same, 2 sacks, the players knelt
1.90 m apart.

**Re-broken** (the claw scene's call commented out): 12 checks fail.
"Abduction started", "bagged", "two scouts", "carried", "point at the sack",
"long scene", "boss fighting", "hall sealed" and "taken saved" are among
them. The same run checked the door: E opened it with no shards once the
surgery was done.

Screenshots: the burlap view while carried (dark weave) and knelt (warm
light through it); the sack going up off the view; the scout before them
with the spear lowered after the flick; the fight (the boss's bar up, the
weapon back in hand).

A clean `--quit-after 1500 -- --skip-title` windowed run: no errors or
warnings. Not benchmarked: the scene is one-off, two scouts and one
full-screen shader for about 20 s.

### Traps
- **The sack flew 70 m out of the hall.** The first throw used the spear
  tip's own speed (displacement / delta), and one long frame made that
  about 25 m/s. The throw is now a fixed velocity back over the shoulder.
  The harness's first floor check (`y - floor < 0.4`) passed with the sack
  6.85 m BELOW the floor. Check `absf`, and a distance band.
- **A freed abduction node compares equal to null** (section 4), so
  "started" read false after it had run and freed itself. Keep a flag.
- **The burlap was black.** At a 0.035 base, the weave read as a black
  screen in the screenshots. It is now 0.14 plus 1.4 x the light outside.
- PowerShell `Set-Content -Encoding utf8` writes a BOM. Two scripts picked
  one up from harness edits; strip it before committing.

### Not done
- The long cutscene itself (`_long_scene`).
- Sounds: the sack, the carry, the flick.
- The scouts carrying the player is never seen: the bag covers it, and they
  are put in the hall while it does.
