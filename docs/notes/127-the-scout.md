## 127. The scout: a spearman robot that roams the corridors hunting the player, built and animated procedurally (2026-10-28)

The user, with a picture (a hunched robot soldier in rusted riveted brass
and iron plate, a ragged hooded mantle, a long barbed spear held low):
- "Make this guy a new enemy, but make his eyes blue, like the enforcer. He
  should also roam the halls, looking for the player. He should be easier to
  kill than the enforcers. They should be called scouts. Scouts should have a
  spear dash, a tri stab attack, and a swipe that knocks the player down."
- "Make all animations very realistic."

There was no model or rig for it, so both are built in code. The animation
is procedural (IK, springs, a stepping gait), because that is what can keep
the feet planted and the hands on the spear at any speed or turn.

### The body (`scripts/scout_body.gd`)

**The mesh.** Built from primitives by `_Builder` into ONE skinned
ArrayMesh, shared by every scout (static `_mesh`, `_skin`). It has three
surfaces: plate, cloth and glow. The spear is a second, unskinned mesh.
- The head: a domed helmet-head with a brow band, a crown ridge and rows of
  rivets. Two big goggles: brass housings, iron bezels, dark glass, and a
  cyan ring and pupil in the enforcer's crystal colour (0.0, 0.91, 1.0),
  emissive. Brass ear gears with teeth, two antennae, a slot mouth with
  teeth, a jaw plate.
  - It is built 1.16x (`HEAD_SCALE`) about the top of the neck, as in the
    picture.
- The body: a barrel chest under a brass breastplate, a gorget, a back plate
  and power box, abdominal lames, a belt with pouches. Tassets hang half on
  the hips, half on the thigh beneath.
- The limbs: rounded pauldrons (half chest, half upper arm) with lames, gear
  joints at the elbows and knees, vambraces, greaves, sabatons, gauntlets
  closed on the shaft.
- The mantle: hangs from the shoulders, ragged at the hem. The hood is fallen
  back behind the neck.
- The spear: 2.4 m. The shaft is ringed every 0.14 m. The head is a long
  flat leaf, with side prongs flaring forward, barbs hooked back and small
  teeth.

**The textures** are drawn in code too (`_plate_textures`, 128 px):
- rivets on a 32 px grid with plate seams between the rows, plus pitting;
- the same as a height map, turned into a normal map;
- a weave for the cloth.

Rust is vertex colour from a 3D noise over where each vertex sits, with
grime lower down.

**The rig.** 31 bones: 17 for the body, and 7 two-bone strands for the
mantle.
- Every rest orientation is the identity.
- The head bone is named "Head", not "head", because skeleton_eyes.gd puts
  yellow eyes on any rig with a "head" bone.

**The animation** is posed every frame in `_process`. Nothing is baked.
- **Feet** are planted in the world and step (`_gait`):
  - A foot lifts when it has fallen a stride behind where it should be
    (more than speed x stance time), or has turned more than 0.6 rad.
    It only lifts if the other foot is down; when running, the other foot
    only has to be past the middle of its swing.
  - The foot swings on an arc to where it will be needed when it lands. The
    landing point is re-aimed through the swing as the speed changes.
  - Starting, stopping, turning on the spot, sidestepping, circling and
    running all come from that one rule.
  - The heel rolls up about the toe as a foot trails behind.
- **Legs** use two-bone IK. The pelvis drops when a planted foot would be out
  of reach. It moves down fast and up gently, never faster than
  `HIPS_SPEED` 1.8 m/s.
- **Pelvis and lean**: the pelvis bobs, sways over the standing foot, drops
  on the swinging side and turns with the stride, and the chest
  counter-turns. The body leans into speed and acceleration and banks into
  turns.
- **The spear leads the arms**:
  - A pose gives the rear grip in the chest's frame. The spear's direction
    turns with the chest but is NOT pitched by the hunch.
  - The rear hand holds the grip.
  - The front hand slides along the shaft to the point its arm can reach.
    In a thrust the shaft runs through it. A spring follows that point,
    capped at `SLIDE_SPEED` 3 m/s.
- **Every pose value follows a damped spring.** Moves use stiffer springs
  with a little overshoot. Locomotion uses softer ones.
- **Hits** kick reaction springs (`hit`) that wobble back to rest. A parry or
  a stagger plays `reel`: the spear is knocked up and the body thrown back.
- **The head** moves in saccades: quick turns, then holds. It fixes on the
  player when hunting, and looks about widely when searching or stopped.
- **Idle**: it breathes, and now and then shifts its weight or regrips.
- **The mantle**: verlet strands hung from the shoulders, drawn back to their
  drape, and kept outside an ellipse round the torso.
  - It is simulated only within the full-rate animation distance.
  - Hanging still, its bones are not re-posed.
- **Poses and moves** are tables at the top of the file (`P_*`, `MOVES`):
  - each move is keys of [time, pose, ease];
  - the swipe's sweep is mostly the body turning, about 160 degrees across
    pelvis and chest, so it reads as a swing, not a whirl.
- **How often it poses** follows the existing rig bands (`Graphics.anim_*`),
  as enemy.gd does. It poses every frame in a move or while dying.
- **Death** (`die`):
  - The knees buckle and the spear is let go: it becomes a RigidBody3D that
    clatters down and is freed after 6 s.
  - The body pitches over on its face about its knees (`_topple`), with the
    feet kept on the floor and the arms hanging limp.
  - The eyes flicker out.

### The scout (`scripts/scout.gd`, extends enemy.gd)

- **Stats**: "SCOUT", 110 health (an enforcer has 240), hunts at 4.6 m/s.
  - Vision: a 140 degree cone through no stone. It also hears anyone within
    `HEAR_RANGE` 4 m, whichever way it faces.
  - Not in the "skeletons" group, so shields do not guard it and crossbows do
    not hide behind it.
  - Drops coins, health potions or a gold crystal.
- **Roaming**: always alone on a patrol (patrol.gd: its own area, stops to do
  something, never through a shut door). It walks it at about 1.6 m/s.
  `_face` turns at `TURN_RATE` 7.5 rad/s; it never snaps round.
- **Hunting**:
  - First sight plays SPOT: it straightens and snatches the spear up, for
    0.6 s.
  - Then it comes on along the navmesh, slowing in the last few metres.
  - Close in and waiting for its next attack, it circles at 1.9 m, keeping
    its distance and changing direction now and then.
  - Making no headway for 2.5 s while more than 2.5 m off (a shut door,
    bars), it gives up: blind to them for 5 s, and it searches where it
    stands.
- **The moves.** Each blow lands only where the spear really passes through
  the player's capsule, through no stone. Each has a parry cue.
  - TRI-STAB, inside `CLOSE_GAP` 1.9 m: three thrusts at 8 / 8 / 12; the
    last is a lunge with a 0.55 m step in. Cues at 0.18 / 0.56 / 0.92 s.
  - SWIPE, also close in, 40% when ready, 3.2 s cooldown: wound back over
    its right side, then swept low at the legs. 12 damage, and unguarded it
    knocks them down (`knock_down`, 7.0). Cue at 0.44 s.
  - SPEAR DASH, from 5-9.5 m with a clear floor, 60% a roll every 0.4 s,
    4.5 s cooldown:
    - a 0.5 s crouch with the spear couched;
    - a burst of up to 7.5 m in 0.7 s, re-aimed as they move, fastest at
      once (about 16 m/s), stopping 1.25 m off with the point on them;
    - 16 damage and a shove.
  - A blocked blow shoves. A parry staggers it: the player's own knockback,
    shown as `reel`.
- **Searching** (`_begin_search`, `_search_step`):
  - Having lost them, it walks to where they were last seen and looks about
    for 1.6-3 s.
  - Then it walks two more legs of 5-9 m the way they were heading, never
    through a shut door, looking about after each.
  - Then it goes back to its patrol.
- **Dead**: it lies where it fell. enemy.gd would keep moving a dying body
  under gravity, and with its shape switched off that dropped the first
  version through the floor.

### Where they are

- **maze.gd**: `scout_share` 0.08 of corridor encounters are a lone scout on
  patrol (`_spawn_scout`), present from the start. Scouts are not held in
  containment.
  - They have their own `_scout_rng`, so every other spawn stays where it
    was.
  - The trickle (note 123) rolls them like any other encounter.
  - `[scouts] N of M corridor enemies` is printed at the population.
  - Seed of the run: 21 of 87.
- **The sandbox**: a "Scout" entry.

### Measured

**Throwaway windowed sandbox harness** (deleted). Final run, 18/18:
- 9 s of roaming: 16-20 footfalls, 7-9 m covered.
- The worst toe slide of a planted foot is 0.021 m, on the first step from
  standing, while the pelvis sinks into it.
- The rear hand is on the shaft (0.000 m) and the front hand within 0.03 m.
- Tri-stabs and swipes landed, and the swipe knocked the player down.
- No hand or head moved more than 0.24 m in one frame (in the body's own
  frame) through the fighting.
- The dash came from 8.5 m and its point passed within 0.03 m of the
  player's axis, for 16 damage.
- Parries threw it reeling.
- It searched where it lost them.
- It fell, the spear dropped, and the body went.

The harness failed honestly along the way:
- With the aim in the chest's frame, the hunch pointed every thrust at the
  floor: the dash missed and the stabs mostly missed.
- Lunges crouched to a kneel.
- The pelvis dropping in one frame showed as a 0.3-0.4 m pop.
- The front hand jumped between the two places on the shaft at arm's
  length.
- The swipe's spear turned about 6 rad in 0.24 s.

**Measuring traps:**
- `get_bone_global_pose` read at the start of a frame is the previous
  frame's pose. With the body turning fast it showed a 0.4 m "foot slide"
  that was not there. Measure from the pose as written.
- A screenshot save makes the next frame long: skip those frames.
- `.Replace()` in a harness edit replaced every copy of a loop header, and
  the dash test ran zero frames.

**Posing cost**: about 160 us a scout a frame at full rate (twelve walking,
60 fps).

**Real level** (throwaway; every scout woken, the player passive, 45 s):
- 21 scouts, standing 14.9% of half-seconds;
- none never moved;
- 2 stood over 8 s at once (a stop, then a failed plan behind shut doors,
  note 125).

**Bench** (RTX 3060, 3440x1440, `--bench`, editor open):

```
                 overall fps   worst p99 (ms)        video mem
no scouts            101.3     15.15 (chest room)    617.5 MB
28 scouts (0.12)      97.5     16.67 (chest room)    628.6 MB
21 scouts (0.08)      96.9     18.06 (surgery)       626.1 MB
```

The two runs with scouts are within each other's noise. The share was cut
to 0.08 because 28 felt like too many, not for speed.

A clean `--quit-after 1500` windowed run had no errors or warnings.

### Traps
- **PowerShell**: `R` is PowerShell's alias for Invoke-History, so a
  helper named `R` silently did nothing.
- **`SurfaceTool.set_skin_weight_count`** must come BEFORE `begin()`.
- **A harness cannot preload a script that names an autoload**:
  scout_body.gd reads `Graphics`. Use `load()` at run time.

### Not done
- Sounds for its steps and moves.
- An LOD mesh: each scout is one full-detail skinned mesh.
