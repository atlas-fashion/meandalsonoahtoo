## 130. The small health potion: half the heal in half the time, dropped by the sewer lizards (2026-10-29)

The user: "The lizards in the sewers need to drop a new kind of heal that is
half of the current one. It should heal half as much and take half as much
time."

### What it is
- **`resources/small_health_potion.tres`**, a ConsumableType:
  - "Small Health Potion", inventory id `small_health_potion`;
  - `heal_amount` 20 (the health potion's 40);
  - a paler green, Color(0.55, 0.95, 0.4).
- **`consumable_type.gd`** has a new `drink_scale`: the share of the player's
  `drink_time` a drink takes. It is 1.0 for the health potion and 0.5 for the
  small one, so the small one takes 1.5 s against 3 s.
- **`inventory.gd` ITEMS** has its entry: kind "Consumable", stack 20,
  single. It rides the quick wheel like the health potion.

### Where it is wired in
- **player.gd**:
  - `consumables` lists it; `starting_counts` is [3, 0], so a new game
    starts with none.
  - `use_consumable` sets `_drink_total` = `drink_time * drink_scale`.
    `_update_drink` spreads the heal evenly over that, and
    `drink_remaining` (the HUD's countdown) runs over it.
  - The held flask is marked `small` while it is the one in hand or being
    drunk.
- **held_potion.gd**: the same flask drawn at `SMALL_SCALE` 0.72.
- **item_drop.gd**: on the floor, the same model at 0.155 (the health
  potion's is 0.22), lying on its side.
- **item_icon.gd**: the same flask, 0.7 the size, standing on the same line.
- **inventory_screen.gd**: the Potions line reads "3 + 2 small" when there
  are small ones.
- **sandbox_menu.gd**: "5 small health potions".
- **sewer_lizard.gd** `drop_odds`: `small_health_potion` 0.3 in place of
  `health_potion` 0.08 (`bone_fragment` 0.3 as before; 0-1 rolls).

### Measured
Throwaway windowed sandbox harness (deleted), 8/8:
- it is a consumable;
- from 40/100 health, the health potion gave 40.0 in 2.90 s and the small
  one 20.0 in 1.51 s (wall clock);
- 4000 rolls of a lizard's drops: 1142 small potions, 1246 bone fragments,
  1612 nothing, no full potions;
- a small potion lying on the floor was walked over and taken into the bag
  (1 -> 2).

**Re-broken** (`drink_scale` 1.0): "in half the time" failed, 3.01 s against
2.89 s.

A clean `--quit-after 1500` windowed run had no errors or warnings.

### Trap
Walking over a drop takes it only when one of that item is already carried
(`item_drop._auto_take`). With none in the bag it waits for E, and a test
that just walks the player onto it sees nothing taken.
