## 187. A scoutpost's door stays open once wound; rising at its beacon shuts it again (2026-11-14)

The user: once the wheel is completed the door stays open; it closes again only
when the player respawns at that scoutpost's beacon, so they must reopen it.
And: verify the stairs in game by actually walking the player up them.

Supersedes the lock rules of notes 180-182 where they differ: note 180's "wound
up they stay up until everyone has left; then armed again", and note 182's
"cleared, it never shuts again" now has one exception (rising at its beacon).

### What changed (scoutpost.gd, maze.gd)
- **`wound`** (scoutpost.gd): set in `_unlock` when a hand was on the wheel as the
  gates reached the top -- not when a shut post with nobody alive inside opens
  itself (`EMPTY_OPEN`, note 180), so dying in a post and rising elsewhere does
  not count as winding it. A wound post is never armed again on walking in
  (`_armed = not (cleared or wound)`). Before, a post wound without being
  `cleared` (its guard list empty: the player was inside when the population
  was rolled, or no scouts were spawned) shut again on every visit.
- **`shut_in()`** (scoutpost.gd): clears `wound` and arms the post; the usual
  `_process` drop follows, the player being inside (0.35 s, then the 0.32 s
  crash, during the respawn's black). A post already locked stays locked.
  The wheel must be wound again; on a cleared post it turns at once (its scouts
  stay dead: `_spawn_scoutpost_scouts` gives a cleared post none, nor a post a
  player is standing in).
- **maze.gd `_shut_risen_in(player)`**, from `_on_player_respawned` after the
  player is placed (each co-op player too): every post the risen player is
  `_inside` gets `shut_in`. Rising inside a post can only be at its beacon (the
  beacon stands in the middle, the rise point 1.6 m in front of it).
- **Saved**: maze.gd `save_state` "scoutposts_wound" (indices, as
  "scoutposts_cleared"), `restore_world` sets `wound`. Loading a save is not a
  respawn: a wound post loaded into stays open.

### Measured
Throwaway windowed harness in the real level (default seed, `--no-enemies`, real
E and forward input; the post's scouts freed and its guard list emptied before
each wind, so `wound` alone was tested, not `cleared`), 0 failures:
- the first post open from outside; shut 1.2 s after walking in; held E winds it
  to 1.00 and sets `wound`;
- out and back in: stays open; walking about inside: stays open;
- **re-break**: `wound` set false by hand and walked in again: it shuts -- the
  test notices;
- died and risen at the start beacon: the post still open;
- its beacon claimed and made active, died: risen inside it (local
  (0, 0.17, 1.6)), `wound` false, shut 1.2 s later, stays shut with nobody
  winding; wound again (after the 0.38 s getting up) and open on coming back;
- `cleared` set, risen there again: shut, and the wheel winds at once;
- `save_state()` carries "scoutposts_wound": [0].
- **The stairs, all 8 posts**: holding forward from each stair's foot reaches
  the upper floor (2.12 m, then standing at 2.15) in 1.30 s, then walks
  8.5-8.8 m along it to its far end (the seventh post's upper floor is 5.2 m
  from the stair's head to its end, walked 3.9 m to within 0.6 m of it).
- Clean windowed `--quit-after 2400` run: no errors; the one warning is the
  carve's old "rooms only fit 4 cells apart".

### Traps
- `--no-enemies` does not stop the scoutposts' scouts: 3 were in the first post,
  and with them alive the wheel will not turn ("Kill the scouts first"), so the
  first harness run "failed" every wind. Free them, or they are guards.
- After a respawn the player gets up (`in_cutscene`, 0.4-0.9 s here): the wheel's
  prompt is hidden until then, and E held before it does nothing.
