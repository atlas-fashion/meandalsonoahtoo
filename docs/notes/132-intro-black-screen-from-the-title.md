## 132. The intro was a black screen from the title; leaving it mid-way leaves nothing on the title (2026-10-30)

The user: starting a new game showed only a black screen instead of the intro and
tutorial. Note 131 listed "a real new game from the title" as not tested; every run
there used `--intro` with slot -1, and this bug only exists with a slot.

### The cause

hud.gd `_ready`, when `Saves.slot >= 0`: `fade_black(1.0, 0.0)`, the sheet that holds
the title's black over the level's build, lifted by `wake_up` or by maze.gd for a loaded
game. The intro takes the place of that `wake_up`, so nothing lifted it, and the sheet
is on layer 90, over the intro's own black (45). The story, the lessons and the
kidnapping all ran underneath it. Hiding the HUD does not hide it: a CanvasLayer's
`visible` does not reach a child CanvasLayer.

### The fix (`intro.gd _run`)

The intro lifts every HUD's sheet itself, **after** its two frames' wait and
`_hide_dungeon`, not straight after `_make_black`. Lifted at once, the cell and the
minimap showed for about 2 s: a new ColorRect added at that point in the frame is not
drawn that frame, and that one frame then stays on screen through the stall that follows.

### Found while checking it

- **Quitting to the title mid-intro** (the pause menu is open throughout) left the bars,
  the black layer and a lesson card over the title, and the intro ran on. All of them
  live on the root, and a scene change takes the node out of the tree a frame before
  freeing it, so `get_tree()` went null, each `await` errored and returned, and the rest
  of the intro ran straight through, lessons included. Now `_frame()` parks the coroutine
  on a signal that never comes once out of the tree, and `_exit_tree` frees what is on
  the root (black, bars, subtitles, the sacks, the cinematic cameras, the lessons' cards).
  `intro_lessons.close()` can now be called twice, and frees the stone's subtitles.
- **"Below. With the others."** was on layer 41, under the black at 45, so it was never
  seen. It is on 46 now.
- `_end_subs` freed its layer from a lambda on the intro: a timer that outlives the intro
  never ran it, so the hidden layer stayed for good. It connects to `queue_free` now.

### Measured (throwaway windowed harness, deleted; a real `title_screen._play` with `Saves.save_dir` pointed elsewhere)

- **Before:** `hud_black` 1.00 and screen brightness 0.0000 for the whole story, with the
  intro's own black at 0.00.
- **After:** brightness 0.0000 for the first frames, then 0.0002 with the sheet off (no
  cell), the card on the black, and the scenes at 0.02 to 0.08.
- **Skip:** control after 9.6 s, `in_cutscene` false, HUD on, lesson 1 of 24 on screen.
- **Quit at 8 s:** nothing left on the root, the title clean, no errors, and a second new
  game from there played.
- **Quit in the first lesson:** no errors, only the hidden subtitle layer waiting on its
  12 s timer.
- **Ending:** jumped to the altar; into the cell, full health, up off the floor, `[save]
  slot 4 (new game)`, the last line readable on the black.

### NOT tested

- Quitting during the kidnapping, under the sack.
- Co-op from the title: the loop lifts every HUD, but it was not run.
- The whole intro in one sitting: the lessons were jumped over.

### Traps

- **A harness sampling every frame slows the game's clock.** Saving a 3440x1440 PNG
  takes about a second, and the frame's delta is capped near 8 physics ticks (0.13 s),
  so the 22 s ending took 160 s. It looks like a hang.
- **`--script` paths and game args with spaces** split at the space through
  `Start-Process`; quote them inside the argument.
