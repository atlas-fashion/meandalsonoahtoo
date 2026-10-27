## 113. Ghost mode only on a fresh press of its key (2026-10-27)

The user: ghost mode sometimes turns on without them pressing its key.

### What set it off

Ghost mode ("dodge": Shift, L3 on a pad) was LEVEL-triggered: `player._update_ghost`
started one on any frame the key read as down and nothing forbade it. So it
went off by itself whenever Shift was already down for some other reason at the
moment play resumed, and once by a bug in how the key was read:

- **Held through anything that stops play** -- Shift-click in the inventory
  (item_slot.gd moves a stack) and the inventory closed with Shift still down;
  a menu, the pause menu, a scene (`in_cutscene`), a hiding place, a ladder, a
  vat, getting up after death (`_respawn` cleared `_ghost_locked`). The moment
  any of them ended, the ghost started with no press.
- **System chords** -- Win+Shift+S (the snipping tool), the Copilot key
  (Win+Shift+F23), Ctrl+Shift+Esc: Shift reached the game first.
- **The latched action came back** -- note 9 made `_action_held` ask the
  keyboard itself because the stored action state latched on, but "dodge" has a
  pad binding, and for that entry the function fell back to
  `Input.is_action_pressed("dodge")`, which answers for the WHOLE action,
  keyboard state included. So any latch of the action switched the ghost on
  with no key down at all.

Checked on this PC: no controller is connected (Godot reports 0 pads), so L3
was not the cause here; Razer Synapse and the Wacom driver are running, either
of which can send Shift from a remapped button.

### The fix (scripts/player.gd)

- `_update_ghost`: `_ghost_locked` (already "let go before it starts again"
  after running the bar dry) is now also set while the key is down and
  `ui_open`, `_dead`, `_ghost_resumed` (below) or `_system_chord()` (Ctrl, Alt
  or Win down; the keyboard player only). It clears whenever the key is up. So
  a ghost starts only on a press made in play.
- `_physics_process` stamps `_ghost_frame` on every frame in play (not hidden,
  climbing, restrained, on a vat or in a scene); a gap of more than one physics
  frame -- those states, or the tree paused, which skips the call altogether --
  sets `_ghost_resumed` for the next frame. The combat early returns (slam,
  spear dash, the axe planted) come after the stamp, so a key pressed during
  one of those still starts the ghost when it ends, as before.
- `_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` locks it.
- `_respawn` sets `_ghost_locked = true` (was false).
- `_ghost_locked` starts true; the first frame with the key up clears it.
- `_action_held` asks pad bindings of the pad itself, `_pad_held(e, deadzone)`:
  `Input.is_joy_button_pressed` / `get_joy_axis` over all 16 pad slots
  (`PAD_SLOTS`) for a device -1 binding -- slots, not
  `get_connected_joypads()`, so made-up pad events in a harness count. Block
  (`_check_block`) goes through the same path.

### Measured

Throwaway harness in the sandbox, real `InputEventKey` / `InputEventJoypadButton`
events through `Input.parse_input_event`, 18 checks: press starts / release
ends; Shift held through a menu, a scene, a pause, a respawn, Win+Shift,
Ctrl+Shift, Ctrl let go with Shift still down, a focus loss, the action pressed
with no key -- no ghost; a fresh press after each -- ghost; L3 starts and ends
it. **18/18 with the fix; the old player.gd fails 9 of them** (every one of the
"no ghost" cases). Clean `--quit-after` windowed run: no errors.

### Traps

- A respawn plays the getting-up scene, so ghost checks right after one pass
  vacuously (the harness first did: it waited for `in_cutscene` to clear).
- `Input.is_action_pressed` on an action with mixed bindings reports the
  keyboard too. Ask each device of its own state.
