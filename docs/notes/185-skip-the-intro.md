## 185. Skip the intro (2026-11-14)

Noah asked for a way to skip the whole intro outside the dungeon (note 131) and
start a new game straight in the cell. Holding jump only ever skipped the story;
the walk up the hill, the 24 lessons and the kidnapping at the altar could not
be left out. There are now two ways.

**1. A tick when naming a new game.** The title's NAME YOUR GAME page has a
CheckButton, "Skip the intro (wake in the cell)" (`title_screen.gd`
`_skip_intro`). `_play` passes it to `Saves.start(i, name, no_intro)` only for an
empty slot; it sets `Saves.skip_intro` (cleared again by `exit_to_title`), and
intro.gd `wanted()` returns false for it. The maze then takes its old new-game
branch (maze.gd, after `level_built`): `wake_up` on the cell floor, then
`Saves.request("new game")` -- exactly what a new game did before the intro.
The tick is remembered for the next new game in `user://title.cfg`
(`[new_game] skip_intro`), off by default. `-- --intro` still forces the intro.

**2. "Skip the intro" in the pause menu** while it runs (`pause_menu.gd`
`_skip_intro`, shown only when `_intro()` finds a skippable intro: the intro node
is in group `&"intro"`, `can_skip()` is true once its world is built and until
it is skipped). It closes the menu and calls intro.gd `skip_all()`, from
wherever the intro has got to -- story, walk, lessons or the altar:
- `_aborted` is set. `_frame` now waits on `_stopped` (a signal never emitted)
  when aborted or out of the tree, so every scene under way stops at its next
  frame and is dropped silently when the intro is freed. `_run` returns after
  each phase if aborted (the lessons' `finished` would otherwise run `_taken`).
  `_say` does nothing once aborted.
- It closes the lessons, the subtitles and the sacks, stills the shake, puts
  the black up, and runs the normal `_finish`: look restored, dungeon and
  minimap shown, cameras back, players home, full health, the new game's pack,
  `wake_up`, the game saved.
- `_finish` waits one real `process_frame` instead of `_frame` (which would now
  stall it), and guards a null `world`.

The story's prompt now reads "Hold SPACE to skip the story" (A on a pad), since
it never skipped the rest.

### Measured (throwaway windowed harness, deleted; real `title_screen._play`, `Saves.save_dir` elsewhere)

- **Tick on:** no intro node, `intro_running` false, the maze visible, the player
  on the cell spot (137.25, 0, -54) getting up (`in_cutscene` true at 1 s, false
  by 8 s), `[save] slot 4 (new game)`. The tick read back as on in the next run.
- **Skip from the pause menu, in the story (6 s), in the first lesson, and at
  the altar (lessons' `finished` emitted by hand, skipped 5 s into the kidnapping
  under the sack):** each time the button was visible, `[intro] skipped`, then
  `[intro] done: into the cell`; afterwards the intro gone, the maze visible, on
  the cell spot from 2390 m away, 100 health, control back by 8 s, the save on
  disk, and the Environment the same as a run with no intro (sky background, fog
  1.0, exposure 1.0). No errors in any log.
- One hidden layer is left on the root for up to 12 s after a skip in the story
  or the kidnapping: the subtitles waiting on `_end_subs`'s timer (as note 132
  already found for quitting).
- Clean `--quit-after` runs of the title and of `--skip-title`: no errors.

### NOT tested

- Co-op: `skip_all` and `_finish` loop over every player, but it was not run.
- A pad pressing the tick or the pause button (both are ordinary focusable
  controls).
