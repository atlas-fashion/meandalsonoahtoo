class_name Inventory
extends RefCounted

## What the player carries: the two wheels, then the bag (2026-10-10; the
## hotbar is gone). Every slot is either empty ({}) or {"id": StringName,
## "count": int}.
##
##   0 - 3    the WEAPON wheel (C / right stick click): up, right, down, left.
##            Weapons only. The one in hand is `player.selected_slot`.
##   4 - 7    the QUICK ITEM wheel (R, or the d-pad): up, right, down, left.
##            Consumables only.
##   8 - 37   the bag: anything.
##
## HOTBAR keeps its old name for "the slots before the bag" (both wheels).
##
## Pure data. The player owns one (`player.inventory`), the HUD draws the
## hotbar from it and the inventory screen lets the player rearrange it; all of
## them listen to `changed`. Item kinds live in ITEMS, so a new kind of thing
## to carry is one entry there (and, if it should look like something, a case
## in item_icon.gd).

signal changed

const WEAPONS := 4
const QUICK := 4
## The first quick-item slot.
const QUICK_FIRST := WEAPONS
const HOTBAR := WEAPONS + QUICK
## Five across, six down on the inventory screen.
const BAG := 30
const SIZE := HOTBAR + BAG
## The layout before the wheels (9 hotbar slots + the bag): what an old save
## holds, put back by `migrate`.
const OLD_SIZE := 39

## id -> name, how many fit in one slot, the colour it is drawn in, what sort of
## thing it is and a line or two about it (the inventory screen's description
## panel; it adds live numbers -- damage, healing -- underneath).
const ITEMS := {
	&"sword": {"name": "Sword", "stack": 1, "color": Color(0.78, 0.8, 0.84),
		"kind": "Weapon",
		"desc": "A long blade of old, dark iron. Heavy enough to break bone, quick enough to cut twice before a skeleton turns.",
		"quote": "It has opened every skull in these halls."},
	&"spear": {"name": "Ashwood Spear", "stack": 1, "color": Color(0.7, 0.55, 0.36),
		"kind": "Weapon",
		"desc": "Seven feet of ash with a leaf of iron at the end. Quick to jab, braced for a charge, and thrown, it bursts like a firepot and comes back to the hand that threw it.",
		"quote": "It always finds its way home."},
	&"health_potion": {"name": "Health Potion", "stack": 20, "color": Color(0.24, 0.92, 0.32),
		"kind": "Consumable",
		"desc": "A flask of something green and faintly glowing. Bitter, warm, and it closes wounds.",
		"quote": "Bitter as the grave, warm as a hearth."},
	&"coins": {"name": "Coins", "stack": 9999, "color": Color(1.0, 0.78, 0.25),
		"kind": "Treasure",
		"desc": "Old gold and loose jewels, pried from chests and the bone cages.",
		"quote": "The dead keep their wealth close, and poorly."},
	&"bone_fragment": {"name": "Bone Fragment", "stack": 99, "color": Color(0.86, 0.8, 0.66),
		"kind": "Material",
		"desc": "A splintered length of bone from a skeleton that will not be getting up again.",
		"quote": "Brittle, dry, and still faintly warm."},
	&"skeleton_skull": {"name": "Skeleton Skull", "stack": 20, "color": Color(0.92, 0.86, 0.72),
		"kind": "Trophy",
		"desc": "A whole skull, prised off a fallen skeleton before it could crumble. Few come away intact.",
		"quote": "It is still listening."},
	# What the dungeon's machines run on (2026-10-09): warden bots on gold
	# crystals (warden.gd drops them), the prison hubs' generators on red ones
	# (dungeon_room.gd, taken out to cut the power).
	&"gold_crystal": {"name": "Gold Crystal", "stack": 20, "color": Color(1.0, 0.74, 0.2),
		"kind": "Material",
		"desc": "A cloudy gold crystal prised out of a warden bot's chest. It still ticks faintly, like something counting.",
		"quote": "It wanted to keep walking."},
	&"red_crystal": {"name": "Red Crystal", "stack": 10, "color": Color(1.0, 0.16, 0.1),
		"kind": "Material",
		"desc": "A heavy red crystal pulled out of a prison generator. Every lock in the block let go when it came free.",
		"quote": "The cells were never shut by iron."},
	# The chest rooms' shards (dungeon_room.gd), one per room; the great door
	# before the throne hall (shard_door.gd) wants every one.
	&"shard_crimson": {"name": "Crimson Shard", "stack": 1, "color": Color(1.0, 0.2, 0.15),
		"kind": "Relic",
		"desc": "A splinter of red crystal, warm as a coal. It hums when it is carried toward the great door.",
		"quote": "One of five. The door remembers its shape."},
	&"shard_azure": {"name": "Azure Shard", "stack": 1, "color": Color(0.25, 0.55, 1.0),
		"kind": "Relic",
		"desc": "A splinter of blue crystal, cold to the touch. It hums when it is carried toward the great door.",
		"quote": "One of five. The door remembers its shape."},
	&"shard_verdant": {"name": "Verdant Shard", "stack": 1, "color": Color(0.3, 1.0, 0.45),
		"kind": "Relic",
		"desc": "A splinter of green crystal with something moving in it. It hums when it is carried toward the great door.",
		"quote": "One of five. The door remembers its shape."},
	&"shard_amber": {"name": "Amber Shard", "stack": 1, "color": Color(1.0, 0.68, 0.15),
		"kind": "Relic",
		"desc": "A splinter of golden crystal, heavy for its size. It hums when it is carried toward the great door.",
		"quote": "One of five. The door remembers its shape."},
	&"shard_violet": {"name": "Violet Shard", "stack": 1, "color": Color(0.74, 0.32, 1.0),
		"kind": "Relic",
		"desc": "A splinter of violet crystal that never quite stops glowing. It hums when it is carried toward the great door.",
		"quote": "One of five. The door remembers its shape."},
}

## The shards, in the order the puzzle rooms are given them.
const SHARDS: Array[StringName] = [&"shard_crimson", &"shard_azure", &"shard_verdant",
	&"shard_amber", &"shard_violet"]


var slots: Array[Dictionary] = []
## Quick-wheel slots keep the item they were given (slot index -> id) after
## the last one is used: the slot shows it greyed out with a 0, and the next of
## that item picked up goes back there. Set whenever an item lands in a quick
## slot; cleared only by moving it out by hand, putting another item in, or
## `unassign` (2026-10-11).
var assigned := {}


func _init() -> void:
	clear()


func clear() -> void:
	slots.clear()
	for i in SIZE:
		slots.append({})
	assigned.clear()
	changed.emit()


## The item quick slot `i` belongs to, held or run out; &"" if none.
func assigned_at(i: int) -> StringName:
	return StringName(assigned.get(i, &""))


## Forgets what quick slot `i` belongs to (only when it is empty).
func unassign(i: int) -> void:
	if is_empty(i) and assigned.has(i):
		assigned.erase(i)
		changed.emit()


## May slot `i` take a new stack of `id`? Empty, of the right kind, and not a
## quick slot kept for something else.
func _free_for(i: int, id: StringName) -> bool:
	if not is_empty(i) or not slot_accepts(i, id):
		return false
	return not assigned.has(i) or StringName(assigned[i]) == id


## Every quick slot holding something now belongs to it. Run after any change.
func _mark() -> void:
	for i in range(QUICK_FIRST, HOTBAR):
		if not is_empty(i):
			assigned[i] = id_at(i)


func _changed() -> void:
	_mark()
	changed.emit()


static func item_name(id: StringName) -> String:
	return String(ITEMS.get(id, {}).get("name", String(id).capitalize()))


static func item_kind(id: StringName) -> String:
	return String(ITEMS.get(id, {}).get("kind", ""))


## Anything of kind "Weapon" can block (the haft's shield, `player._start_block`).
static func is_weapon(id: StringName) -> bool:
	return item_kind(id) == "Weapon"


static func is_consumable(id: StringName) -> bool:
	return item_kind(id) == "Consumable"


## Whether slot `i` may hold `id`: weapons on the weapon wheel, consumables on
## the quick wheel, anything in the bag. Nothing (&"") fits anywhere.
static func slot_accepts(i: int, id: StringName) -> bool:
	if id == &"":
		return true
	if i < WEAPONS:
		return is_weapon(id)
	if i < HOTBAR:
		return is_consumable(id)
	return true


## Where a new stack of `id` may go, in the order to try: its wheel, then the bag.
static func _home_order(id: StringName) -> Array:
	if is_weapon(id):
		return range(WEAPONS) + range(HOTBAR, SIZE)
	if is_consumable(id):
		return range(QUICK_FIRST, HOTBAR) + range(HOTBAR, SIZE)
	return range(HOTBAR, SIZE)


## An old save's slots (any layout) put back into this one: everything re-added,
## so weapons land on the weapon wheel, potions on the quick wheel, the rest in
## the bag.
func migrate(old: Array) -> void:
	assigned.clear()
	slots.clear()
	for i in SIZE:
		slots.append({})
	for s in old:
		if s is Dictionary and not (s as Dictionary).is_empty():
			add(StringName(s["id"]), int(s["count"]))
	_changed()


## A saved game's slots and quick-slot assignments, put back as they were.
func restore(saved_slots: Array, saved_assigned: Dictionary) -> void:
	slots.assign(saved_slots)
	assigned = saved_assigned.duplicate()
	_changed()


static func item_description(id: StringName) -> String:
	return String(ITEMS.get(id, {}).get("desc", ""))


static func item_quote(id: StringName) -> String:
	return String(ITEMS.get(id, {}).get("quote", ""))


static func stack_size(id: StringName) -> int:
	return int(ITEMS.get(id, {}).get("stack", 1))


static func item_color(id: StringName) -> Color:
	return ITEMS.get(id, {}).get("color", Color.WHITE)


func is_empty(i: int) -> bool:
	return i < 0 or i >= SIZE or slots[i].is_empty()


func id_at(i: int) -> StringName:
	return &"" if is_empty(i) else StringName(slots[i]["id"])


func count_at(i: int) -> int:
	return 0 if is_empty(i) else int(slots[i]["count"])


func count(id: StringName) -> int:
	var total := 0
	for s in slots:
		if not s.is_empty() and s["id"] == id:
			total += int(s["count"])
	return total


## The first slot holding `id`, hotbar first; -1 if there is none.
func find(id: StringName) -> int:
	for i in SIZE:
		if id_at(i) == id:
			return i
	return -1


## How many more of `id` would fit: the room left on its stacks plus every
## empty slot's worth.
func room_for(id: StringName) -> int:
	var cap := stack_size(id)
	var room := 0
	for i in SIZE:
		if _free_for(i, id):
			room += cap
		elif id_at(i) == id:
			room += maxi(cap - count_at(i), 0)
	return room


## Puts `amount` of `id` away: topping up stacks already carried first, then
## the first empty slot that takes it -- its wheel before the bag, so a new
## weapon or potion is ready to hand. Returns how many actually fitted.
func add(id: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var cap := stack_size(id)
	var left := amount
	for i in SIZE:
		if left <= 0:
			break
		if id_at(i) == id and count_at(i) < cap:
			var room := cap - count_at(i)
			var put := mini(room, left)
			slots[i]["count"] = count_at(i) + put
			left -= put
	# Its own quick slot first (kept for it while empty), then the rest.
	var order := _home_order(id)
	for i in range(HOTBAR - 1, QUICK_FIRST - 1, -1):
		if assigned_at(i) == id:
			order.erase(i)
			order.push_front(i)
	for i in order:
		if left <= 0:
			break
		if _free_for(i, id):
			var put := mini(cap, left)
			slots[i] = {"id": id, "count": put}
			left -= put
	if left != amount:
		_changed()
	return amount - left


## Takes up to `amount` out of slot `i`. Returns how many came out.
func take(i: int, amount := 1) -> int:
	if is_empty(i) or amount <= 0:
		return 0
	var got := mini(amount, count_at(i))
	slots[i]["count"] = count_at(i) - got
	if count_at(i) <= 0:
		slots[i] = {}
	changed.emit()
	return got


## Takes up to `amount` of `id` from wherever it is carried, bag first so the
## hotbar stack is the one that lasts. Returns how many came out.
func remove(id: StringName, amount: int) -> int:
	var left := amount
	for i in range(SIZE - 1, -1, -1):
		if left <= 0:
			break
		if id_at(i) == id:
			var got := mini(left, count_at(i))
			slots[i]["count"] = count_at(i) - got
			if count_at(i) <= 0:
				slots[i] = {}
			left -= got
	if left != amount:
		changed.emit()
	return amount - left


## Moves what is in `from` onto `to`: merged into it when they are the same
## kind and there is room, otherwise the two slots swap.
func move(from: int, to: int) -> void:
	if from == to or is_empty(from) or to < 0 or to >= SIZE:
		return
	# Each wheel takes only its own kind -- both ways, if this is a swap.
	if not slot_accepts(to, id_at(from)) or not slot_accepts(from, id_at(to)):
		return
	if id_at(from) == id_at(to):
		var cap := stack_size(id_at(to))
		var room := cap - count_at(to)
		if room > 0:
			var put := mini(room, count_at(from))
			slots[to]["count"] = count_at(to) + put
			slots[from]["count"] = count_at(from) - put
			if count_at(from) <= 0:
				slots[from] = {}
				assigned.erase(from)
			_changed()
			return
	var held := slots[from]
	slots[from] = slots[to]
	slots[to] = held
	# Taken out of a quick slot by hand into an empty one: that slot is free.
	if slots[from].is_empty():
		assigned.erase(from)
	_changed()


## Moves half of a stack (rounded up) into an empty slot, or merges it into a
## stack of the same kind. Does nothing if `to` holds something else.
func split(from: int, to: int) -> void:
	if from == to or count_at(from) < 2 or to < 0 or to >= SIZE:
		return
	if not is_empty(to) and id_at(to) != id_at(from):
		return
	if not slot_accepts(to, id_at(from)):
		return
	var id := id_at(from)
	var half := int(ceil(count_at(from) / 2.0))
	if is_empty(to):
		slots[to] = {"id": id, "count": 0}
	var put := mini(half, stack_size(id) - count_at(to))
	if put <= 0:
		if count_at(to) == 0:
			slots[to] = {}
		return
	slots[to]["count"] = count_at(to) + put
	slots[from]["count"] = count_at(from) - put
	_changed()


## Shift-click: sends a stack from a wheel into the bag, or from the bag onto its
## wheel (weapons to the weapon wheel, consumables to the quick wheel; anything
## else stays put), merging into matching stacks first.
func quick_move(i: int) -> void:
	if is_empty(i):
		return
	var id := id_at(i)
	var lo := HOTBAR
	var hi := SIZE
	if i >= HOTBAR:
		if is_weapon(id):
			lo = 0
			hi = WEAPONS
		elif is_consumable(id):
			lo = QUICK_FIRST
			hi = HOTBAR
		else:
			return
	var cap := stack_size(id)
	for j in range(lo, hi):
		if count_at(i) <= 0:
			break
		if id_at(j) == id and count_at(j) < cap:
			var put := mini(cap - count_at(j), count_at(i))
			slots[j]["count"] = count_at(j) + put
			slots[i]["count"] = count_at(i) - put
	if count_at(i) > 0:
		var targets := range(lo, hi)
		# Onto the quick wheel: the slot kept for it first.
		for j in range(hi - 1, lo - 1, -1):
			if assigned_at(j) == id:
				targets.erase(j)
				targets.push_front(j)
		for j in targets:
			if _free_for(j, id):
				slots[j] = slots[i]
				slots[i] = {}
				break
	if count_at(i) <= 0:
		slots[i] = {}
		# Sent off the quick wheel by hand: the slot is free again.
		if i >= QUICK_FIRST and i < HOTBAR:
			assigned.erase(i)
	_changed()
