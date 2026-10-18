extends Node

## SANDBOX MODE (autoload `Sandbox`, 2026-10-17): a test bed started from the
## title's Sandbox button. The real level is built (so every area is a teleport
## target) but left EMPTY, plus a flat, lit plane well outside it where the
## player starts (maze.gd `_build_sandbox_plane`). The whole map is charted.
## Nothing is ever saved: it runs slotless (`Saves.slot` -1), as `--skip-title`
## does. The sandbox menu (scripts/sandbox_menu.gd, the backtick key) spawns
## enemies, sets the switches below and the weapon levels, and teleports.
##
## The switches are read where they bite:
##   * `enemies_passive` -- enemy.gd treats the player as hidden (they lose
##     interest and wander off; a blow already swinging still lands), crier.gd
##     `_can_see`, stalker.gd `_warded`, mimic.gd holds still.
##   * `player_god` -- player.gd takes no damage from any source (blows, drains,
##     beams, the morgue's scripted death); guards and parries still register,
##     so enemies react to them as usual.

## In a sandbox session.
var active := false
## Enemies never take an interest in the player.
var enemies_passive := false
## The player takes no damage.
var player_god := false
## Attack hitboxes (shield_hitbox.gd) are drawn while their hit window is open
## -- in the sandbox only (2026-10-18, the user); on by default there, the
## sandbox menu switches it.
var show_hitboxes := true


## Into a fresh sandbox (from the title).
func start() -> void:
	reset()
	active = true
	Saves.slot = -1
	Saves.pending = {}
	Saves.game_name = "Sandbox"
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(Saves.GAME_SCENE)


## Out of it: every switch off (a real game, the title).
func reset() -> void:
	active = false
	enemies_passive = false
	player_god = false
