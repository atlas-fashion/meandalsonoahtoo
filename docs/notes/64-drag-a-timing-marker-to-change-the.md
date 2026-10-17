## 64. Drag a timing marker to change the timing; the enforcers only (2026-10-17)

Builds on note 63. The user: the skeletons and the boss are early prototypes due
a whole rework, so the system is built for "both the enforcers" -- the enforcer
and the decrepit enforcer. `tools/timing_preview/skeleton.tscn` and `boss.tscn`
are removed (git history has them).

- **Dragging a marker writes its constant** (tools/timing_preview/timing_preview.gd
  `check_drags`, polled every 0.25 s in the editor): each marker is BOUND to
  the constant it shows; one no longer where it was put has been dragged, its
  time snapped to the clip's frame (60 fps), turned into the value and written
  into the script in place of the old one (`write_const`: the `const NAME :=`
  line's value only, a trailing comment kept), then the markers rebuild from
  the script. If the script is open in Godot's script editor it offers to
  reload it.
  - decrepit: HIT -> `*_CONTACT` (the cue moves with it, its listen kept);
    parry cue -> `*_LISTEN` (= hit - cue: the window closes on the blow);
    move ends -> `*_END`; lunge -> slide -> `DASH_LUNGE`.
  - enforcer: swipe HIT -> `SWIPE_CONTACT`, written as frames (`22.0 / 60.0`,
    its style); settled: BEAM FIRES -> `BEAM_SET_EARLY` (= clip length -
    marker).
  - Gold info markers (cannon up, the recoil, the dash's parry note) are bound
    to nothing: dragging one changes nothing and is put back at the next
    rebuild.
- The script stays the one source of truth; the markers are only a view of it
  that can also edit it. Comments that quote a timing's old value in prose
  (e.g. "f33" beside SWIPE_CONTACT) are not rewritten.
- Measured (throwaway harness, deleted; drags simulated by moving the markers on
  Timeline's clips and calling `check_drags`, the scripts restored from git
  after): 12/12 -- decrepit HIT +3 f wrote SWIPE_CONTACT 0.533 -> 0.5833 with
  the listen kept and both markers rebuilt there; cue -4 f wrote SWIPE_LISTEN
  0.3166 (= hit - cue); move ends +6 f JUMP_END 1.25; lunge +2 f DASH_LUNGE
  0.2667; enforcer HIT +1 f wrote `22.0 / 60.0`; beam fires -3 f
  BEAM_SET_EARLY 0.04 -> 0.0833; an info marker moved nothing; both scripts
  compiled after every write. Dragging in the real Animation panel was not
  seen (no editor UI here).
