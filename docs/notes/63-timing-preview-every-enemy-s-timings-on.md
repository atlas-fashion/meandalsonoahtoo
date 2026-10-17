## 63. Timing preview: every enemy's timings on the animation timeline (2026-10-17)

The user: "I just want to be able to see all the timings in the animation
timeline for each enemy."

- **tools/timing_preview/** -- `decrepit.tscn`, `enforcer.tscn`, `skeleton.tscn`,
  `boss.tscn`, one @tool script (`timing_preview.gd`). Open a scene, select its
  **Timeline** AnimationPlayer, pick a clip in the Animation panel: the
  timings are named, coloured MARKERS on the timeline (purple parry, red the
  blow, gold worth knowing, grey the move ends); scrubbing poses the model in
  the viewport. Not used by the game.
- **Live, one source of truth**: the markers are built from the enemy's own
  script constants (a FRESH compile of the source on disk, so an edit made
  outside Godot shows too) and its scene's exported values (loaded past the
  cache), and rebuilt whenever one of those files is saved (polled every
  0.5 s). Change a timing, save, the marker moves. Values an enemy only sets
  in `_init` (the enforcer's windup) are read off the source with a regex.
- **Why markers are not authored on the clips**: they are imported from .glb
  and Godot rebuilds them on every reimport, so anything added in the editor is
  lost. Timeline plays a COPY of the model's clips (made on load; its library
  is removed before the preview scene is saved, NOTIFICATION_EDITOR_PRE_SAVE,
  and rebuilt after), rooted at the model so every track resolves (checked:
  decrepit 15/15, enforcer 21/21, skeleton 18/18).
- **Trap**: an Animation holds ONE marker per moment -- a second added at the
  same time replaced the first (the dash's slide note, the enforcer's HIT, the
  skeletons' "hits from here" vanished). Markers at one time are joined into
  one label, in the first one's colour.
- What each shows:
  - decrepit: per move parry cue (listen), HIT n / window closes, move ends;
    the dash: lunge held -> slide, cue 0.2 s before arrival (the slide's length
    varies, so its hit has no fixed frame).
  - enforcer: swipe HIT at f21 with the rate it plays at (stretched to its
    0.6 s windup) and the old parry rule; beam cannon up (f37), settled = fires
    (charge 0.65 s); recoil ping-pong x1.6 for 3.2 s, vent 1.6 s.
  - skeleton / boss (clips stretched to their durations, so each says its
    duration and rate): windup telegraph and attack start; each attack "HITS
    from here, whenever in reach" (no single frame: `_try_connect` any frame of
    the attack) with its duration, the old parry rule, attack over; recovered.
- Checked headless (each preview built, every marker listed against the
  scripts' values) and in the editor (`--editor`, the decrepit preview opened,
  no errors). The Animation panel itself was not seen -- no editor UI here.
