## 133. The intro stopped for good on the walk up the hill, and the gate was shut; the whole intro played on keys and mouse (2026-10-30)

The user: the new game's cutscene stops at a certain point in the forest part. Note 131
listed "the whole game in one sitting" as not tested and note 132 "the whole intro in
one sitting"; both harnesses skipped the story or jumped ahead, and neither ever walked
the path up in the player's own eyes.

### The cause (`intro.gd _walk_all`)

The walk up the hill has two legs. `_walk_all` counted the players down from a lambda
connected to `scene_walk_finished`: `left -= 1`. **A GDScript lambda captures a local by
value**, so it counted down its own copy and the `while left > 0` loop never ended. The
player reached the first bend, stood still with the view on the hill, and never got
control. It only happens with the story watched: a skip does not walk (`_arrive`
`skipped`), which is why every earlier run missed it. `left` is an array now, as `done`
already was in `_say`.

### Found playing on: the gate was shut (`intro_world.gd _build_ruins`)

`_brick("arch", ...)` used the default `solid`, one box round the whole mesh, opening and
all (6.6 x 5.6 x 1.5 m). The player stopped at z -25.15, 3.65 m from the gate mark, and
"Walk up to the gate" wants 3.6: the tutorial's second lesson could not be finished by
walking straight at the arch, whatever was tried. The arch now has its two legs only,
sized from `BrickLevel.ARCH_*` as brick_level.gd `_arch_collision` does; its opening
measures +/-1.63 m at walking height.

### Measured (throwaway windowed harness, deleted; real `title_screen._play`, `Saves.save_dir` elsewhere, real `InputEventKey` / mouse events)

- **Before, story watched:** the player at (27.1, -60.1) from 96 s to the end of the run
  at 150 s, `in_cutscene` true, `_scene_walk_target` null, no lessons.
- **After, story watched, one sitting from the title:** story over at 88 s, both legs of
  the walk done, lesson 1 at 105 s, all 24 lessons in order on keyboard and mouse, the
  altar at about 280 s, `[intro] done: into the cell`, `[save] slot 4 (new game)`.
  Afterward the maze visible, `intro_running` false, on the cell spot, 100 health, control
  back, the save on disk. No errors in the log.
- The two wheels were driven through their real keys and mouse travel this time, and the
  sentinel was blocked and parried with the right button.

### NOT tested

- Co-op, and the walk with two players (the count is written for it).
- A pad from the title.
- A person playing: steering in the run set the view directly (the steps, keys, clicks
  and wheel aiming were real events). The trunk, the stone and the altar were reached
  in straight lines.

### Seen, left alone

- The first lesson's card appears while the letterbox is still drawing out, so its top is
  cut off for about a second.
- If the player is already at the altar when the "altar" lesson opens, the handle's line
  and the kidnapping's first line share one subtitle layer. It reads badly, but nothing
  waits on it.

### Traps

- **A lambda captures locals by value.** Assigning to one inside changes only the
  lambda's copy, with no warning. Use an array or a dictionary, or a member.
- **`_solid_box` round a piece with a hole fills the hole.** `_brick`'s `solid` is for
  solid pieces.
- **A skip hides the scene after it.** Anything that runs only when the story is watched
  has to be tested with the story watched.
