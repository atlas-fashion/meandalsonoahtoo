extends Node

## Saving and loading (2026-10-09), autoload "Saves".
##
## Four slots, chosen on the title screen. A slot holds everything a death
## does not reset: the level's seed (the whole layout comes from it), the
## player (where they stand, health, the pack, the slot in hand), the anchor
## they rise at, the map, kicked-in doors, looted cages, emptied coffins, the
## puzzle rooms, the shard door and whether the boss is dead. Enemies are not
## saved: as after a death, the world is repopulated when it loads.
##
## Three ways a game is saved (2026-10-09, at the user's request; the third
## added 2026-10-10): by itself every `autosave_every` seconds of play, by
## itself on a death (player.gd `_die` -> `request("death")`, written once the
## player is up again), and by the player (the pause menu's Save game, or
## "Save and exit"). Leaving does NOT save by itself:
## the pause menu asks. The one other write is creating a new game, so its
## named slot exists to be loaded. A save waits until it is safe (`_safe`):
## never mid-scene, dead, hidden in a coffin or getting up -- a shard in flight
## to the door belongs to neither the pack nor the door.
##
## A slot shows its game's name (given when it was made), the zone the player
## is in, and when it was saved -- deliberately not how far they have got.
##
## Gathering and restoring are done by the level (maze.gd `save_state` /
## `restore_world` / `restore_player`); this keeps the slots, the clock and the
## scene changes. Nothing is ever written while `slot` is -1, which is how the
## game runs from a harness, the benchmark or `--skip-title`.

signal saved(slot: int, reason: String)

const SLOTS := 4
const VERSION := 1
const TITLE_SCENE := "res://scenes/title.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

## Where the slots live. A harness points this somewhere else, so it never
## touches the player's saves.
var save_dir := "user://saves"
@export var autosave_every := 60.0

## The slot being played, or -1 (nothing is saved).
var slot := -1
## What the game being started should load: a slot's data, or {} for new.
var pending := {}
## Seconds of play in this slot, carried in the save.
var play_time := 0.0
## The name the player gave this game.
var game_name := ""
## Seconds since the game was last saved (shown when leaving without saving).
var since_saved := 0.0
const NAME_MAX := 24

var _since := 0.0
var _requested := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func path(i: int) -> String:
	return "%s/slot_%d.save" % [save_dir, i + 1]


func exists(i: int) -> bool:
	return FileAccess.file_exists(path(i))


func read(i: int) -> Dictionary:
	if not exists(i):
		return {}
	var f := FileAccess.open(path(i), FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	return data if data is Dictionary else {}


## The slot's description for the title screen, or {} if it is empty.
func summary(i: int) -> Dictionary:
	var data := read(i)
	return data.get("meta", {}) if not data.is_empty() else {}


func erase(i: int) -> void:
	if exists(i):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(i)))


## Starts the game in slot `i`: carries on from its save, or -- if it is empty
## -- starts a new game there called `new_name`.
func start(i: int, new_name := "") -> void:
	# A real game: no sandbox switches carried in.
	Sandbox.reset()
	slot = i
	pending = read(i)
	var meta: Dictionary = pending.get("meta", {})
	play_time = float(meta.get("play_time", 0.0))
	game_name = String(meta.get("name", "")) if not pending.is_empty() else clean_name(new_name, i)
	_since = 0.0
	since_saved = 0.0
	_requested = ""
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(GAME_SCENE)


## A name as typed, trimmed and cut to length; empty becomes "Game N".
static func clean_name(typed: String, i: int) -> String:
	var n := typed.strip_edges().left(NAME_MAX)
	return n if n != "" else "Game %d" % (i + 1)


## Back to the title. Does not save: the pause menu asks first.
func exit_to_title() -> void:
	Sandbox.reset()
	# Co-op ends at the title (coop.gd); it is chosen again from there.
	Coop.stop()
	slot = -1
	pending = {}
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


## Something worth saving for happened: saved as soon as it is safe.
func request(reason: String) -> void:
	if slot >= 0:
		_requested = reason


func _process(delta: float) -> void:
	var maze := _maze()
	if slot < 0 or maze == null or not maze.get("is_built"):
		return
	if not get_tree().paused:
		play_time += delta
		_since += delta
		since_saved += delta
	if _since >= autosave_every and _requested == "":
		_requested = "autosave"
	if _requested != "" and not get_tree().paused and _safe():
		save_now(_requested)


## Writes the slot now. Returns "" on success, else why not.
func save_now(reason: String) -> String:
	if slot < 0:
		return "Nothing to save to."
	var maze := _maze()
	if maze == null or not maze.get("is_built"):
		return "The level is not ready."
	if not _safe():
		return "You cannot save right now."
	var data: Dictionary = maze.call("save_state")
	data["meta"] = _meta(data)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	# Written to a side file and swapped in, so a crash mid-write leaves the old
	# save whole.
	var tmp := path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Could not write the save."
	f.store_var(data)
	f.close()
	var final := ProjectSettings.globalize_path(path(slot))
	if FileAccess.file_exists(path(slot)):
		DirAccess.remove_absolute(final)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), final)
	_since = 0.0
	since_saved = 0.0
	_requested = ""
	if reason == "autosave" or reason == "death":
		for hud in Coop.huds():
			if hud.has_method("_show_toast"):
				hud.call("_show_toast", "Autosaved", 1.0)
	saved.emit(slot, reason)
	print("[save] slot %d (%s), %.0f s played" % [slot + 1, reason, play_time])
	return ""


## What the slot card shows: the game's name, the zone, when. Not progress.
func _meta(data: Dictionary) -> Dictionary:
	return {
		"version": VERSION,
		"name": game_name if game_name != "" else "Game %d" % (slot + 1),
		"zone": data.get("zone", 1),
		"zone_name": data.get("zone_name", "Zone 1"),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"play_time": play_time,
	}


func _maze() -> Node:
	return get_tree().get_first_node_in_group("maze")


## Never mid-scene, dead, hidden or getting up.
func _safe() -> bool:
	# Co-op: safe only if it is for both players.
	var all := Coop.all()
	if all.is_empty():
		return false
	for p in all:
		if not _safe_for(p):
			return false
	return true


func _safe_for(player: Node) -> bool:
	if player.get("_dead") == true or player.get("in_cutscene") == true:
		return false
	if player.has_method("is_hidden") and player.call("is_hidden"):
		return false
	if player.has_method("is_waking") and player.call("is_waking"):
		return false
	return true


## "1:05:32" or "12:03".
static func clock(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
