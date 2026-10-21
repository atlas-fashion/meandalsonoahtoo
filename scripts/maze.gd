extends Node3D

## Builds the whole level: a maze carved by recursive backtracking around a
## walled boss chamber at the centre, a baked navmesh so enemies can route
## through it, and the enemy/boss population. Also rebuilds the population when
## the player dies.
##
## The grid is (2 * cells + 1) tiles square. Odd tile coordinates are corridor
## cells, even ones are the walls between them, so a whole tile is either open
## floor or solid wall -- no thin-wall bookkeeping.

signal level_built

const OPEN := 0
const WALL := 1

const DIRECTIONS := {
	"north": Vector2i(0, -1),
	"south": Vector2i(0, 1),
	"east": Vector2i(1, 0),
	"west": Vector2i(-1, 0),
}

@export_group("Maze")
@export var cells := 16
@export var tile_size := 4.0
@export var wall_height := 9.0
## 0 uses a time-based seed, so every run differs. Any other value is stable.
@export var maze_seed := 20260918

@export_group("Organic level")
## Replaces the square-tile maze with the organic one: winding curved corridors,
## chambers and a circular arena, built from the modular stone kit in
## `models/kit/`. The old tile maze is kept behind this flag rather than deleted
## -- it is the fallback if the kit turns out to be too expensive on the P620,
## and the project is not under version control.
##
## The tile grid does NOT go away when this is on. It is rasterised from the
## organic region and survives as a coarse occupancy map, because enemy
## spawning, wander areas, sightlines, room tests and the treasure/boss logic
## are all written against `grid`, `is_open()` and `tile_to_world()`. Rebuilding
## all of that against a different representation would have meant rewriting
## most of this file to change what the walls look like.
@export var organic := true
## Half-size of the organic map in metres. With `cells` and `tile_size` chosen so
## that `tiles * tile_size` covers `2 * organic_extent`, the grid lines up with
## the region and nothing needs re-centring.
## Half-size of the organic map in metres.
##
## This is what makes the maze bigger, and it has to be raised HERE rather than
## inside the generator: `_trace_contour()` below and `preview_maze_graph.gd`
## both size their raster window from this number, so a generator that quietly
## scattered nodes past it would have its far edge clipped off and read as a
## disconnected island.
@export var organic_extent := 92.0
## Corridors that go somewhere and stop. They are most of what makes a maze
## feel like a maze rather than a network.
@export var organic_dead_ends := 16
## Long corridors joining chest rooms on opposite sides of the map, so crossing
## one puts the player out somewhere they did not expect.
##
## Cut from 3 to 1. These are deliberate shortcuts, and every one of them pulls
## two chest rooms closer together in walking terms -- the opposite of wanting
## a long haul between them. One keeps the "come out somewhere unexpected"
## moment without turning the map into a hub.
@export var organic_long_links := 1
## How many chest rooms exist.
##
## Down from 10. This is the lever that actually lengthens the walk between
## them: measured over the corridor graph, the distance from a chest room to
## the NEAREST other one went from min 29 m / mean 74 m at ten rooms to
## min 75 m / mean 110 m at six. The worst case -- the one the player feels as
## "another one already?" -- more than doubled.
@export var organic_chest_rooms := 6
## The frozen, lightmapped level, built by `tools/freeze_level.gd`.
##
## When this is set the walls, floor, ceiling and torches come from it instead
## of being generated, and `maze_seed` MUST match the seed it was frozen at or
## the baked geometry will not line up with the grid, spawns and navigation
## that are still generated here.
##
## This is the trade baked lighting costs. A lightmap is precomputed for fixed
## geometry, and `LightmapGI` cannot light a `MultiMeshInstance3D` -- so the
## level has to be one specific maze, flattened into unique static meshes.
## Measured: 2.2 M triangles, 497 MB of video memory against 251 MB for the
## whole instanced game. What it buys back is 209 omni lights that stop being
## evaluated every frame.
@export var organic_baked_scene: PackedScene
## Bake the torchlight into each panel's MultiMesh instance colour, and stop
## the torch lights from shading static geometry.
##
## This is the affordable stand-in for a lightmap: `LightmapGI` cannot light a
## MultiMesh, and freezing the level to bake one measured 497 MB of video
## memory against 251 MB for the whole game. See `organic_lighting.gd`.
## How many unlockable bands the maze is divided into.
##
## 1 means the whole maze is open, which is today's behaviour and the default.
## The plan this exists for is boss-gated expansion: ship "phase 1", and have
## killing the boss open the next band with new enemies in it. Raising this
## and setting `organic_active_phase` below already builds only the open
## region -- walls close around it, collision follows, the grid and navmesh
## rasterise to it -- because everything reads the graph through a restricted
## view. What is NOT built is the unlock itself: no trigger, no transition, no
## new enemy set. See `scripts/maze_phases.gd`.
@export_range(1, 6) var organic_phase_count := 1
## Highest phase currently open, 0-based.
@export_range(0, 5) var organic_active_phase := 0
## Length of one vaulted ceiling bay along the corridor, in metres.
@export var organic_vault_bay := 3.0
## Scale applied across the vault so its arch spans the corridor. 1.0 means the
## authored width; the corridor is `organic_corridor_radius * 2` across.
@export var organic_vault_width := 1.0
## Metres between engaged pillars along the corridor walls.
@export var organic_pillar_spacing := 7.0
## Colour, strength and reach of the light baked behind each barred window.
@export var organic_window_colour := Color(1.0, 0.24, 0.12)
@export_range(0.0, 6.0, 0.1) var organic_window_energy := 2.2
@export var organic_window_range := 9.0
@export var organic_bake_light := true
## Multiplier on the baked result, for taste.
@export_range(0.2, 3.0, 0.05) var organic_bake_exposure := 1.45
## Floor the baked light never goes below. Without it a corridor out of torch
## range bakes to pure black, which reads as a hole rather than as darkness.
@export var organic_ambient_floor := Color(0.22, 0.21, 0.24)
## Half-width of a corridor. Tighter than it was: the user asked for corridors
## that feel claustrophobic, and at 2.9 they were 5.8 m across, which reads as a
## hall rather than a passage.
@export var organic_corridor_radius := 2.2
## The organic grid is sampled finer than the tile maze's 4 m.
##
## `grid` is what every spawn, wander area and room test still reads, and a tile
## only counts as open where the region has real clearance. At 4 m tiles a 4.4 m
## corridor can contain no qualifying tile centre at all, which fragments the
## grid, strands the spawner and breaks the walk `_nearest_room_to_start()` does
## to pick the mimic's room.
@export var organic_tile_size := 1.5
@export var organic_boss_radius := 30.0
## The user asked for exactly two ways into the arena, so it takes finding.
@export var organic_boss_doors := 2
## Courses of stone. Each is one authored panel height (2.237 m), never scaled.
## Three puts the corridor ceiling at 6.71 m: tall and narrow, which is the
## proportion the user asked for.
@export var organic_wall_rows := 3
## Raster resolution used to trace the wall contour. Higher is smoother and
## slower; 480 over a 172 m map is ~0.36 m per cell, well under the panel width.
@export var organic_contour_res := 480
## Extra metres of raster window beyond `organic_extent`, for both the wall
## contour and the tile grid.
##
## The generator does not stay inside the extent it is handed. Corridors are
## `corridor_radius` wide either side of a node, chambers bulge further, and a
## dead-end spur reaches up to 22 m from its parent -- so geometry lands past
## the boundary routinely. Rasterising exactly to `organic_extent` clipped it:
## the contour could not close out there, collision was thrown across the
## corridor, and 43 points along the centrelines ended up sealed inside a wall
## at x = -91. In play that is a passage that dead-ends into a blank wall.
##
## Widening the window costs a little contour resolution and nothing else.
@export var organic_contour_margin := 16.0
## Distance at which kit chunks stop drawing, in metres, before `Graphics`
## scales it by the View distance slider.
##
## `CLAUDE.md` records that cutting view range bought nothing (+0.11 ms) on the
## old level -- but that level was fill-bound, and the kit measures as
## geometry-bound (halving render scale saves only 2.04 ms of 15.22, while the
## content accounts for 13.4 ms across 182,800 primitives). Different bottleneck,
## so the lever is worth re-testing rather than assuming it is still dead.
##
## 70 m keeps the far side of the 60 m arena visible, so nothing pops in a place
## the player can actually see across.
@export var organic_view_range := 70.0
## Multiplier on the kit's albedo, pulling the pale generated limestone down to
## the exposure the level was authored for.
##
## Tuned against the old level's own screenshot rather than by eye: untinted the
## organic level measured mean luminance 0.336 to the tile level's 0.134, with
## shadows at 0.160 against 0.0125. At 0.38 it overshot the other way and
## crushed the blacks to zero.
@export_range(0.1, 1.0, 0.01) var organic_stone_tint := 0.55
## Scale on each torch's authored energy.
##
## The kit reflects far more light than the brick it replaced, so at the
## authored energy the torches blew out the stone around them: lit pixels
## measured p90 0.41 against the old level's 0.26 while the midtones already
## matched. Turning the lights down is the fix rather than darkening the stone
## further, because darkening enough to tame the highlights crushed the shadows
## to pure black.
@export_range(0.2, 2.0, 0.05) var organic_torch_energy := 0.6
## Scale on the archway standing in each chest-room entrance.
##
## The authored piece is 3.247 m across with an opening of roughly 2.1 m. At
## 2.0 the opening is about 4.2 m, a touch under the corridor's width, so the
## jambs bury themselves in the rock either side instead of standing out in the
## passage where the player would clip through them.
@export_range(0.5, 4.0, 0.05) var organic_archway_scale := 2.0

@export_group("Boss room")
## Side length in tiles of the chamber carved at the centre. It is enclosed by
## its own wall ring, so it is a real room rather than an open patch of maze.
@export var boss_room_tiles := 9
## How many of north/south/east/west are opened as doorways.
@export_range(1, 4) var boss_room_entrances := 2
@export var boss_scene: PackedScene = preload("res://scenes/boss.tscn")

@export_group("Treasure rooms")
## Open rooms carved at random odd positions, each with a chest at its centre.
@export var treasure_rooms := 5
## Must be odd, so the room always swallows at least one corridor cell and can
## never be sealed off from the maze.
@export var treasure_room_tiles := 5
@export var chest_scene: PackedScene = preload("res://scenes/chest.tscn")
## Exactly one of the chests is this instead, chosen at random and identical
## from the outside.
@export var mimic_scene: PackedScene = preload("res://scenes/mimic.tscn")
@export var spawn_mimic := true
@export var gate_scene: PackedScene = preload("res://scenes/gate.tscn")

@export_group("Jail cells")
## Barred cells sunk into the two chamber walls that have no doorway, each
## holding one skeleton until the Warden lets it out.
@export var cells_per_wall := 15
@export var cell_depth := 2.0
@export var cell_height := 3.0
## Thickness of the walls between neighbouring cells.
@export var cell_divider := 0.26
@export var cell_door_scene: PackedScene = preload("res://scenes/cell_door.tscn")
## How many doors the Warden throws open each time he calls for help.
@export var cells_per_summon := 10

@export_group("Pillars")
## Square columns standing in the open rooms, so the arenas are not bare boxes.
## They share the wall material, vines included.
@export var pillar_size := 1.3
## Distance from the room centre, in tiles.
@export var boss_pillar_offset := 2.0
## Torches are mounted on pillars at least this tall. Short stepping stones are
## left bare -- a torch on a knee-high block reads as clutter.
@export var torch_min_pillar_height := 2.5

@export_group("Chest pedestals")
## Every treasure room gets its own climb: the number of steps, how high each
## one rises, how they are arranged and how tall the pedestal ends up are all
## rolled per room. The pedestal is always exactly one rise above the top step,
## so whatever gets rolled is climbable.
@export var chest_pedestal_size := 2.2
## The player's jump clears about 1.27 m, so rises stay under this.
@export var step_rise_min := 0.7
@export var step_rise_max := 1.05
@export var step_count_min := 2
@export var step_count_max := 4
@export var step_size := 1.8

@export_group("Ceiling")
## The corridors are roofed; the boss chamber and treasure rooms are left open
## to the sky, which is what marks them out as you come in.
@export var ceiling_thickness := 0.6
@export var chandelier_scene: PackedScene = preload("res://scenes/chandelier.tscn")
## One chandelier per this many roofed tiles.
@export var chandelier_spacing := 9
## How far below the ceiling they hang.
@export var chandelier_drop := 2.6

@export_group("Arches")
## Big stone frames marking the way into the open rooms.
@export var arch_height := 6.5
@export var arch_post_width := 0.7
@export var arch_lintel_height := 0.9
## A grille of iron bars filling the head of each arch, above the lintel.
@export var arch_bar_count := 7
@export var arch_bar_width := 0.14
@export var arch_bar_height := 1.9

@export_group("Rendering")
## Walls and ceiling are split into square chunks of this many tiles. A single
## MultiMesh spanning the whole map can never be culled -- it is one instance,
## so it is all drawn or none of it is. Chunking lets the frustum and the
## occluders throw away the parts you cannot see.
@export var chunk_tiles := 6

@export_subgroup("Ground")
## The floor is a grid of separately cullable chunks rather than one slab, so
## the parts behind you are not submitted at all.
@export var floor_chunks := 6
## Quads along each chunk edge. Higher is smoother relief and more triangles.
@export var floor_quads := 14
## How far the ground rises and falls, in metres, as mud and dirt collect
## unevenly. Deliberately small: collision stays a flat box underneath, so
## anything deep enough to really see would be deep enough to walk through.
@export var floor_relief := 0.12
## Metres of world per repeat of the ground texture.
@export var floor_texture_metres := 6.0

@export_subgroup("Ambience")
## Skulls strewn about the floor.
@export var skull_count := 90
## Loose bones, which outnumber the skulls as they would in life.
@export var bone_count := 190
## Sections of iron bar left propped against corridor walls. One in this many
## eligible wall faces gets a small pile.
@export var lean_spacing := 17
## How far these props are drawn. They are ankle height and unlit at range, so
## there is nothing to see long before the walls stop being drawn.
@export var prop_draw_distance := 26.0

@export_group("Torches")
@export var torch_scene: PackedScene = preload("res://scenes/torch.tscn")
## One torch per this many eligible wall faces. Higher means sparser and, since
## each torch is a live light, cheaper.
@export var torch_spacing := 13
@export var torch_height := 2.5

@export_group("Enemies")
@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
## The flying criers (bombers before 2026-10-14). Kept a minority of the population so they read as a
## hazard rather than the main body of it.
@export var flyer_scene: PackedScene = preload("res://scenes/crier.tscn")
@export_range(0.0, 1.0) var flyer_share := 0.45
@export var enemy_count := 72
## In the module level the count follows the corridor length instead: this
## many per corridor cell (72 over the old ~283 cells was 0.25), so growing the
## maze does not thin out the danger. 0 falls back to `enemy_count`.
@export var enemies_per_corridor_cell := 0.25
## Overrides the scene's aggro so the whole map does not converge on the player
## at once. Corridor-length sight lines are roughly this long.
@export var enemy_aggro_range := 18.0
## Tiles around the player's start kept clear of enemies.
@export var safe_tiles_from_start := 5
## Minimum tiles between any two spawned enemies, so the maze reads as a series
## of separate encounters with room to breathe rather than one milling crowd.
@export var min_enemy_spacing := 3
## Enemies posted inside each treasure room as a group, on top of the scattered
## population. A room worth looting should be a room worth fighting for.
@export var chest_room_pack := 4
## How far an idle enemy may wander from where it spawned, in tiles. Candidate
## spots are also filtered to its own kind of place, so a corridor guard never
## strolls into a treasure room and a room guard never strolls out.
@export var wander_tiles := 3
## Share of red enemies that amble about. The rest hold their ground, so a
## corridor reads as a mix of sentries and strays rather than a parade.
## Only some of them pace. A corridor where everything is moving reads as a
## patrol route; one where half hold still reads as a place with guards in it.
## (2026-10-10: skeleton packs are now always on patrol, `patrols`; this is
## left deciding only for what is not.)
@export_range(0.0, 1.0) var wander_share := 0.5
## How far a sentry stands off a wall it would otherwise be pressed against.
@export var sentry_wall_clearance := 0.45
## How many tiles ahead a sentry looks when choosing which way to face. It
## takes the longest open run, so it ends up watching down a corridor.
@export var sentry_sightline := 5
## Reds arrive in groups of this many.
## Of the skeleton packs of two or more, how many bring an archer (archer.gd).
@export_range(0.0, 1.0) var archer_share := 0.85
## Of those packs of four or more that brought one, how many bring a second.
@export_range(0.0, 1.0) var second_archer_share := 0.45
const ARCHER_SCRIPT := preload("res://scripts/archer.gd")
## The skeleton types (prosthetic.gd, note 93; the "archer" above is the
## crossbow hand). Of the packs that have someone to guard -- three or more, or
## two with a crossbowman -- how many are led by a SHIELD skeleton; and of the
## rest of every pack (and the jail cells' stock), how many carry the HAMMER
## rather than the SWORD hand. Drill hands are the mine's (dungeon_room.gd).
@export_range(0.0, 1.0) var shield_share := 0.6
@export_range(0.0, 1.0) var hammer_share := 0.35
const PROSTHETIC := preload("res://scripts/prosthetic.gd")
## Its own stream, so the types' rolls leave every other spawn where it was.
var _hand_rng := RandomNumberGenerator.new()


## A sword or a hammer hand, by `hammer_share`.
func _melee_hand() -> StringName:
	return &"hammer" if _hand_rng.randf() < hammer_share else &"blade"


## Skeleton packs in the corridors are always on the move (patrol.gd): the
## column walks routes between corridor points, the enforcer at its back.
@export var patrols := true
const PATROL := preload("res://scripts/patrol.gd")
var _patrol_points: Array[Vector3] = []
@export var red_pack_min := 1
@export var red_pack_max := 5
## Criers fly solo (2026-10-14; they came in ones and twos).
@export var flyer_pack_min := 1
@export var flyer_pack_max := 1

@onready var nav_region: NavigationRegion3D = $NavRegion
@onready var floor_mesh: MeshInstance3D = $NavRegion/Floor/MeshInstance3D
@onready var floor_shape: CollisionShape3D = $NavRegion/Floor/CollisionShape3D
@onready var floor_body: StaticBody3D = $NavRegion/Floor
@onready var room_floor: MeshInstance3D = $NavRegion/BossRoomFloor
@onready var walls_body: StaticBody3D = $NavRegion/Walls
@onready var wall_visuals: MultiMeshInstance3D = $NavRegion/WallVisuals
@onready var pillars_body: StaticBody3D = $NavRegion/Pillars
@onready var pillar_visuals: MultiMeshInstance3D = $NavRegion/PillarVisuals
@onready var ceiling_visuals: MultiMeshInstance3D = $CeilingVisuals
@onready var arch_visuals: MultiMeshInstance3D = $ArchVisuals
@onready var bar_visuals: MultiMeshInstance3D = $ArchBarVisuals
@onready var wall_chunks: Node3D = $WallChunks
@onready var ceiling_chunks: Node3D = $CeilingChunks
@onready var occluder: OccluderInstance3D = $Occluder
@onready var gates_holder: Node3D = $Gates
@onready var arch_chunks: Node3D = $ArchChunks
@onready var bar_chunks: Node3D = $BarChunks
@onready var pillar_chunks: Node3D = $PillarChunks
@onready var floor_chunk_holder: Node3D = $FloorChunks
@onready var debris_chunks: Node3D = $DebrisChunks
@onready var lean_chunks: Node3D = $LeanChunks
@onready var cell_chunks: Node3D = $CellChunks
@onready var cells_holder: Node3D = $Cells

var tiles := 0
var grid: Array[PackedByteArray] = []
var entrances: Array[Vector2i] = []
## Centres of the carved treasure rooms, one chest each.
var treasure_centres: Array[Vector2i] = []
## Where each chest actually sits: the top of its pedestal.
var chest_perches: Array[Vector3] = []
## What was rolled for each room's climb, for inspection.
var chest_layouts: Array[Dictionary] = []
## Which chest is the mimic, or -1.
var mimic_index := -1
## Doorways per room: index 0 is the boss chamber, then one entry per chest room.
var room_openings: Array[Array] = []
## The gate nodes filling those doorways, same indexing.
var _gates: Array[Array] = []
## Whether each fight has started. Once it has, the room stays shut regardless
## of where the player wanders, until the champion is dead.
var _boss_committed := false
var _mimic_committed := false
var _boss: Node = null
var _mimic: Node = null
## Every column in the level, as {base, size}. Torches hang off the tall ones.
var _pillars: Array[Dictionary] = []
## Corridor tiles that got a ceiling; chandeliers hang from these.
var _roofed: Array[Vector2i] = []
## The noise the floor's relief was built from. Kept so anything resting on the
## ground can sit at exactly the height the ground actually has there.
## The jail cells lining the chamber: their doors, the spot inside each one,
## and whoever is locked in it. Same index throughout.
var cell_doors: Array[Node] = []
var cell_spots: Array[Vector3] = []
## Yaw that looks out of each cell rather than at the back of it.
var cell_facing: Array[float] = []
var cell_occupants: Array[Node] = []
var _relief: FastNoiseLite = null

## The organic generator and the wall contour traced from it. Null when
## `organic` is off. `_loops` are polylines in RASTER GRID units; world XZ is
## `_contour_origin + point * _contour_cell`.
var _graph = null
var _loops: Array = []
var _contour_cell := 0.0
var _contour_origin := Vector2.ZERO
## Top of the stonework, where the ceiling sits.
var _wall_top := 0.0
## The runtime-created torch holder, kept so the light bake can read it back.
var torches_node: Node3D = null
## Phase index per node, and the unrestricted graph, when phases are in use.
var _phases := {}
var _full_graph = null

## --- Module level -----------------------------------------------------------
##
## The level built from the solid tunnel sections in `models/kit`. Takes
## precedence over `organic`, which takes precedence over the tile maze, so
## both older levels survive as fallbacks.
##
## See `CLAUDE.md` section 6. The short version: a cell is ONE piece of tunnel
## carrying its own floor, walls and vault, so there are no panel joins to gap,
## step or leak.
@export_group("Module level")
@export var modules := true
## Grid size in CELLS. Keep it odd: the tile grid has to stay in phase with the
## cell grid or the one-tile doorways land on stone and the maze falls into
## islands. `_build_module_level` checks this rather than trusting it.
## Sample the layout from the organic generator instead of carving a plain
## grid maze. The map keeps that generator's footprint, chambers, dead ends
## and long cross-map links; only the corridors change, from bowed curves to
## right angles, because a solid tunnel section cannot bend.
@export var module_organic_shape := true
## Radius the organic generator scatters within, in metres. `module_grid` has
## to be big enough to hold it: grid * cell >= 2 * extent, with margin.
## 92 m on a 33-cell grid until 2026-10-09; widened so rooms can sit far apart
## with a lot of maze between them (about three times the corridor).
@export var module_extent := 150.0
@export var module_grid := Vector2i(53, 53)
## Dead-end spurs in the module level's generator (16 on the old, smaller map;
## scaled with the area so the bigger maze is as branchy).
@export var module_dead_ends := 44
## Cells of maze kept at least between any two rooms' blocks. Rooms are spread
## as far apart as the map allows on top of this (`module_maze._choose_rooms`).
@export var module_room_gap := 7
## Most doorways a chest room keeps. Corridors that ran through a room are
## walled off and dug round it instead, so rooms are found, not walked through.
@export var module_room_entrances := 2
@export var module_cell := 6.0
## Must divide `module_cell` a whole, odd number of times. 6.0 / 1.2 = 5.
@export var module_tile := 1.2
@export var module_view_range := 70.0
@export var module_stone_tint := 1.0
## Build the corridors from the brick kit (scripts/brick_level.gd, generated
## from the user's reference photos) instead of the Tripo tunnel modules.
@export var brick_kit := true
## Half-width in cells of the boss room. 3 gives a 7x7 block: a roofed arcade
## round a 30 m courtyard open to the sky. It was a single scaled-up module at
## 18 m before, which is the "boss room is tiny" that got reported.
@export var module_boss_half := 3
## Half-width in cells of each chest room. 2 gives a 5x5 block: an arcade
## round an 18 m open courtyard, with the chest on its pedestal in the middle.
@export var module_chest_half := 2
## How many chest rooms to try for. Fewer are placed if the map cannot fit
## them a corridor apart from one another.
@export var module_chest_rooms := 5
## Scales how many wall torches are hung. Omni light count is a per-pixel cost
## on this hardware, which is why it is a knob and not a constant.
## 1.1 since 2026-10-10, second pass ("way too dark... more torches, but way
## less bright"): many dim torches rather than a few bright ones.
## Torches cast shadows since 2026-10-12 (CLAUDE.md section 33). 1.5 was tried
## then -- every stretch got a torch in sight -- and measured 59 fps against 73
## and 1.5-3x the old brightness; 1.1 kept.
@export_range(0.0, 2.0) var module_torch_density := 1.1
## 2.3 under the old pale torch colour; raised with the move to fire orange so the
## corridors keep their brightness (orange carries ~18% less luminance).
## 1.3 since 2026-10-10 (many dim torches with wide soft reach; was 2.8);
## 1.4 with shadows; 1.3 since 2026-10-12 with the physical falloff ("darker,
## realistic and immersive"): about half the old brightness beside a torch.
## 1.1 since 2026-10-14: the light went from orange to amber (less red), which
## carries ~20% more luminance at the same energy.
@export var module_torch_energy := 1.1
## The base light: where no torch reaches, the player can BARELY see. ACES
## crushes low ambient to black -- 0.3 (and 0.12 before it) measured 0.0005
## with every torch off, i.e. there was no base light at all. 1.1 reads about
## 0.008-0.012: floor slabs and brick courses just visible, black a few metres
## off. 1.6 was plainly lit, 0.8 near black.
@export_range(0.0, 3.0) var module_ambient := 1.1
## Barred windows with red light coming through. Each one is a light, so this
## is on the same per-pixel budget as the torches.
@export_range(0.0, 2.0) var module_window_density := 1.0
@export var module_zone_gates := 2

var _module_level = null
var _module_fade: CanvasLayer = null
## The doorways to other zones. Kept OUT of `_spawned` on purpose: `_populate`
## frees everything in `_spawned` every time the world resets -- including the
## first time, straight after the level is built -- and filed there the doors
## were destroyed before the player could ever reach them.
var _zone_gates: Array[Node] = []

var _rng := RandomNumberGenerator.new()
var _active_seed := 0
## Everything this script spawned, so a reset can clear it again.
var _spawned: Array[Node] = []
var _start_tile := Vector2i(1, 1)
## Interior of the chamber, and interior plus its wall ring.
var _room_min := Vector2i.ZERO
var _room_max := Vector2i.ZERO
var _reserved_min := Vector2i.ZERO
var _reserved_max := Vector2i.ZERO


func _ready() -> void:
	add_to_group(&"maze")
	# `-- --no-enemies`: an empty level, for benching the stone alone.
	if "--no-enemies" in OS.get_cmdline_user_args():
		enemies_per_corridor_cell = 0.0
		enemy_count = 0
		convoy_count = 0
		stalker_enabled = false
	_active_seed = maze_seed if maze_seed != 0 else int(Time.get_ticks_usec())
	# A loaded game rebuilds its own level: everything comes from the seed.
	var save: Dictionary = Saves.pending
	if save.has("seed"):
		_active_seed = int(save["seed"])
	_rng.seed = _active_seed

	if modules:
		_rescale_tile_counts(module_tile)
		tile_size = module_tile
		tiles = module_grid.x * int(round(module_cell / module_tile))
		_build_module_level()
	elif organic:
		# Several gameplay values below are counted in TILES, and were tuned
		# against the old 4 m grid. The organic grid is much finer -- it has to
		# be, or a 4.4 m corridor falls between samples -- so at face value
		# `safe_tiles_from_start = 5` would shrink from 20 m of breathing room
		# at spawn to 7.5 m, and enemies would appear on top of the player.
		# Rescaled here so they keep the distance they were chosen for.
		_rescale_tile_counts(organic_tile_size)
		tile_size = organic_tile_size
		# The grid has to span the organic map, so its size comes from the extent
		# rather than from `cells`. Forced odd so there is still a centre tile
		# for `boss_tile()` to mean something.
		tiles = int(ceil((organic_extent + organic_contour_margin) * 2.0 / tile_size))
		if tiles % 2 == 0:
			tiles += 1
		_build_organic_level()
	else:
		tiles = 2 * cells + 1
		_compute_room_bounds()
		_carve_maze()
		_build_boss_room()
		_carve_treasure_rooms()
		_build_floor()
		_build_walls()
		_build_pillars()
		_build_ceiling()
		_build_arches()
		_build_torches()
		_build_debris()
		_build_leaning_bars()
		_build_jail_cells()

	# The sandbox (sandbox.gd): its test plane, before the player is placed on it.
	if Sandbox.active:
		_build_sandbox()
	_build_gates()
	_place_player()
	_connect_player()
	if modules and _module_level != null:
		_attach_explore_map()

	# Baking is asynchronous; agents spawned before it finishes would have no
	# map to path on.
	nav_region.bake_navigation_mesh()
	await nav_region.bake_finished
	# Almost the whole level is built here rather than authored in the scene, so
	# the quality settings have to be re-applied once it exists.
	Graphics.apply_all.call_deferred()
	# The level can be torn down while the bake is in flight (scene change,
	# restart); resuming on a freed node would crash.
	if not is_inside_tree():
		return

	_seal_cells()
	if save.has("seed"):
		restore_world(save)
	_populate()
	if save.has("seed"):
		restore_player(save)
	is_built = true
	level_built.emit()
	if Sandbox.active:
		_open_sandbox_menu()
	if Saves.slot >= 0 and not save.has("seed"):
		# A new game: the player wakes on the cell floor and gets up, as after a
		# death. Only from the title (a slot) -- the benchmark and harnesses
		# start standing.
		for player in Coop.all():
			if player.has_method("wake_up"):
				player.call("wake_up")
		# Creating the game writes its slot (once up: a save waits out the
		# getting up), so it is there to load. The only automatic save after
		# this is the one every minute.
		Saves.request("new game")
	elif Saves.slot >= 0:
		# A loaded game: out of the loading screen's black.
		for hud in Coop.huds():
			if hud.has_method("fade_black_when_steady"):
				hud.call("fade_black_when_steady", 0.0, 1.0)


## Centre of a tile in world space, with the whole maze centred on the origin.
## Keeps the tile-denominated gameplay distances meaning what they meant.
##
## Several values below are counted in TILES and were tuned against the old
## 4 m grid. Both newer levels use a much finer grid -- they have to, or a
## corridor falls between samples -- so at face value `safe_tiles_from_start`
## would shrink from 20 m of breathing room at spawn to a few metres, and
## enemies would appear on top of the player.
func _rescale_tile_counts(new_tile_size: float) -> void:
	var ratio: float = 4.0 / maxf(new_tile_size, 0.1)
	safe_tiles_from_start = int(round(float(safe_tiles_from_start) * ratio))
	min_enemy_spacing = int(round(float(min_enemy_spacing) * ratio))
	wander_tiles = int(round(float(wander_tiles) * ratio))
	sentry_sightline = int(round(float(sentry_sightline) * ratio))


func tile_to_world(tile: Vector2i) -> Vector3:
	var offset := (float(tiles) - 1.0) * 0.5
	return Vector3((float(tile.x) - offset) * tile_size, 0.0, (float(tile.y) - offset) * tile_size)


func world_to_tile(point: Vector3) -> Vector2i:
	var offset := (float(tiles) - 1.0) * 0.5
	return Vector2i(
		int(round(point.x / tile_size + offset)),
		int(round(point.z / tile_size + offset)),
	)


func is_open(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= tiles or tile.y >= tiles:
		return false
	return grid[tile.y][tile.x] == OPEN


func boss_tile() -> Vector2i:
	# The module level's boss room is snapped to the cell grid, so it can sit
	# up to half a cell from the generator's arena centre. Ask the room.
	if modules and _module_level != null:
		var boss: Dictionary = _module_level.boss_room()
		if not boss.is_empty():
			return world_to_tile(_module_level.room_world(boss))
	# The organic arena is wherever the generator put it, which is not
	# necessarily the middle of the grid. Returning the grid centre would put
	# the boss, its aggro box and its four columns in a corridor somewhere.
	if organic and _graph != null:
		return world_to_tile(Vector3(_graph.boss_centre.x, 0.0, _graph.boss_centre.y))
	return Vector2i(tiles / 2, tiles / 2)


func is_in_boss_room(tile: Vector2i) -> bool:
	# The organic arena is a disc, and the rectangle `_room_min/_room_max` is
	# only its bounding box. Testing the box would call the four corners of that
	# box "inside the boss room" when they are solid rock outside the arena,
	# which would keep enemies from spawning in corridors that are nowhere near
	# it and would seal the wrong tiles.
	if organic and _graph != null:
		var p := tile_to_world(tile)
		return Vector2(p.x, p.z).distance_to(_graph.boss_centre) <= _graph.boss_radius
	return (
		tile.x >= _room_min.x and tile.x <= _room_max.x
		and tile.y >= _room_min.y and tile.y <= _room_max.y
	)


## Builds the organic level: generate the graph, trace its wall contour, hand
## both to the geometry and dressing builders, and then project the whole thing
## back down onto the tile grid the rest of this file is written against.
##
## The projection is the load-bearing part. `_rasterise_grid()` is what lets
## enemy spawning, wander areas, sightlines, `is_open()`, the treasure/boss room
## tests and `_nearest_room_to_start()` keep working untouched against a level
## that is no longer made of tiles at all.
func _build_module_level() -> void:
	var builder = load("res://scripts/module_level.gd")
	if builder == null:
		push_error("module level scripts are missing; falling back to the organic maze")
		modules = false
		_rescale_tile_counts(organic_tile_size)
		tile_size = organic_tile_size
		tiles = int(ceil((organic_extent + organic_contour_margin) * 2.0 / tile_size))
		if tiles % 2 == 0:
			tiles += 1
		_build_organic_level()
		return

	# The two grids have to stay in phase. A cell must be a whole odd number
	# of tiles across AND the counts must both be odd, or cell centres fall
	# between tile centres, the one-tile doorways land on stone, and the maze
	# rasterises into disconnected islands. Checked rather than trusted,
	# because it depends on three separate exports agreeing.
	var per_cell := int(round(module_cell / module_tile))
	if absf(float(per_cell) * module_tile - module_cell) > 0.001 or per_cell % 2 == 0:
		push_error(("module_cell %.2f is not an odd whole number of %.2f tiles; "
			+ "the tile grid will fall out of phase with the cells")
			% [module_cell, module_tile])
	if module_grid.x % 2 == 0 or module_grid.y % 2 == 0:
		push_error("module_grid %s should be odd on both axes" % module_grid)

	# Geometry and collision go under NavRegion: the navmesh bake walks that
	# subtree, and a level hung anywhere else bakes empty and leaves every
	# enemy unable to move.
	var holder := Node3D.new()
	holder.name = "ModuleLevel"
	nav_region.add_child(holder)

	# The layout comes from the organic generator -- the same one that drew
	# the sprawling map with the round arena, chambers and long cross-map
	# links -- sampled onto the cell grid. Its bowed corridors cannot be built
	# from rigid square sections, so what survives is the footprint and the
	# topology, on right angles.
	var graph = null
	if module_organic_shape:
		var graph_script = load("res://scripts/maze_graph.gd")
		if graph_script == null:
			push_warning("maze_graph.gd is missing; falling back to a plain grid maze")
		else:
			graph = graph_script.new()
			graph.boss_radius = module_cell * (float(module_boss_half) + 0.5)
			graph.corridor_radius = organic_corridor_radius
			graph.cell_radius = 2.3
			graph.boss_doors = organic_boss_doors
			graph.dead_end_spurs = module_dead_ends
			graph.long_link_count = organic_long_links
			graph.generate(_active_seed, module_extent, 13.0,
				organic_chest_rooms, 7.0, 10.0)
			graph.build_cells(graph.safe_cell_count(1.8))
			graph._build_index()
			# Deliberately NOT stored in `_graph`. Four functions in this file
			# switch to the organic level's rules whenever `_graph` is set --
			# `boss_tile`, `is_in_boss_room`, `is_in_treasure_room` and
			# `_build_gates` -- and those rules describe the organic map's
			# round chambers, not these rooms. Storing it here sent every one
			# of them to the wrong place: the chest test was measuring discs
			# that no longer existed and the gates were placed for a boss room
			# of a different shape. The module level answers all four with the
			# square-room rules instead, fed from the rooms it actually built.

	# `-- --modules` builds the old Tripo tunnel modules instead, for A/B benches.
	builder.brick = brick_kit and not ("--modules" in OS.get_cmdline_user_args())
	_module_level = builder.build(
		holder, _active_seed, module_grid, module_cell, module_cell * 0.85,
		module_view_range, module_stone_tint, graph, {
			"exits": module_zone_gates,
			"boss_half": module_boss_half,
			"chest_half": module_chest_half,
			# One more than the chest rooms: the one furthest from the start
			# becomes the morgue (`_pick_morgue`).
			"chest_rooms": module_chest_rooms + (1 if morgue_enabled else 0)
				+ (1 if surgery_enabled else 0),
			"room_gap": module_room_gap,
			"room_entrances": module_room_entrances,
			"morgue": morgue_enabled,
			"surgery": surgery_enabled,
			"manholes": manhole_count,
		})
	_pick_morgue()
	_pick_surgery()

	# The authored floor plane and its collider are sized for the old level and
	# would sit under solid rock anyway. Hidden and disabled, NOT freed:
	# `floor_mesh` and `floor_shape` are `@onready` references that
	# `Graphics.apply_all()` walks, and a freed node compares equal to null so
	# the usual guard would not catch it.
	floor_mesh.visible = false
	room_floor.visible = false
	floor_shape.disabled = true

	# Torch COUNT is the main per-pixel lever on this hardware -- 347 torches
	# down to 133 was worth 3.7 ms on the previous level -- so it has to sit
	# under a quality knob. It rides on the existing `light_detail`, which
	# already scales the dressing lights' reach, rather than adding a sixth
	# thing to keep in step across five presets. `Graphics.apply_all()` cannot
	# retro-fit a torch that was never spawned, so this is read at build time.
	var detail := 1.0
	if Engine.has_singleton("Graphics") or Graphics != null:
		detail = Graphics.light_detail
	# Doors first: every door is flanked by a pair of torches, which
	# place_torches hangs from the list place_doors leaves in _module_level.
	var doors: Node3D = builder.place_doors(holder, _module_level)
	# The dead end the player wakes in is a jail cell, its door the one above.
	load("res://scripts/jail_cell.gd").build(holder, _module_level, module_torch_energy)
	var torches: Node3D = builder.place_torches(holder, _module_level,
		module_torch_density * detail, module_torch_energy)
	var windows: Node3D = builder.place_windows(
		holder, _module_level, module_window_density * detail)
	_room_sky_lights = builder.place_room_lights(holder, _module_level)
	var skylights: Node3D = builder.place_skylights(holder, _module_level, detail)
	print("[modules] %d wooden doors, %d torches beside them"
		% [int(doors.get_meta("door_count", 0)), int(torches.get_meta("door_torch_count", 0))])
	print("[modules] %d torches, %d bone cages, %d skylights (%d lit) (light_detail %.2f)"
		% [int(torches.get_meta("torch_count", 0)),
			int(windows.get_meta("window_count", 0)),
			int(skylights.get_meta("skylight_count", 0)),
			int(skylights.get_meta("skylight_lit", 0)), detail])
	_apply_module_environment(builder)
	_rasterise_module_grid(builder)
	_module_rooms()
	# The boss room: the stair from its one doorway and the hall above the
	# corridor roofs. Built here, under NavRegion, so the navmesh bakes it.
	_boss_hall = load("res://scripts/boss_hall.gd").build(holder, _module_level,
		module_stone_tint, detail, module_torch_energy)
	_close_boss_block_grid()
	_build_zone_gates()
	_place_anchors(holder)
	_place_hiding_spots(holder)
	_place_clutter(holder)
	_place_damp(holder)
	if not _morgue_room.is_empty():
		_morgue = load("res://scripts/morgue.gd").build(holder, _module_level, _morgue_room)
	if not _surgery_room.is_empty():
		_surgery = load("res://scripts/surgery.gd").build_room(holder, _module_level, _surgery_room)
	_build_puzzle_rooms(holder)
	_build_shard_door(holder)
	_build_sewer()


## --- The morgue (2026-10-08) -------------------------------------------------------
##
## One room built like the chest rooms -- a cloister round an open court -- but
## dressed as a morgue (scripts/morgue.gd): standing coffins, broken skeletons on
## the floor and slabs, and the Remnant's own royal sarcophagus. Opening that is
## a scene the player does not survive. The room is the chest room furthest from
## the start (the carve is asked for one extra), so it is found late. No chest,
## no guards, no ordinary enemies spawn in it. (The Remnant used to be drawn to
## wander near it; at the user's request it now wanders at random.)

@export var morgue_enabled := true


## --- The sewer (2026-10-15) ---------------------------------------------------------
##
## `manhole_count` manholes in corridor straights (module_level `_pick_manholes`),
## each with a cover to lift and a ladder down to the sewer (sewer.gd) -- big
## brick pipes on the same grid, 12 m under the corridors. Neither is under
## NavRegion: nothing walks down there. The sewer has its own map level
## (explore_map.gd `add_level`).

@export var manhole_count := 5
var _sewer: Node3D
var _manholes: Array[Node3D] = []


func _build_sewer() -> void:
	if _module_level == null or _module_level.manholes.is_empty():
		return
	var sewer_script = load("res://scripts/sewer.gd")
	_sewer = sewer_script.build(self, _module_level, _active_seed)
	if _sewer == null:
		return
	var manhole_script = load("res://scripts/manhole.gd")
	var i := 0
	for shaft in _sewer.get("shafts"):
		var cell: Vector2i = shaft["cell"]
		_manholes.append(manhole_script.build(self, shaft, _module_level.to_world(cell), i))
		i += 1
	_wall_off_sewer.call_deferred()


## No light up here reaches the sewer's visual layer: the floor between is not
## a shadow caster, so the corridors' torches and the moon would light the pipes
## through it. Run once the level's lights exist (the moon is the scene's).
func _wall_off_sewer() -> void:
	if _sewer == null:
		return
	var layer: int = _sewer.get("VISUAL_LAYER")
	for n in get_tree().root.find_children("*", "Light3D", true, false):
		var light := n as Light3D
		if _sewer.is_ancestor_of(light):
			continue
		light.light_cull_mask &= ~layer
		if light is DirectionalLight3D:
			light.shadow_caster_mask &= ~layer

var _morgue_room: Dictionary = {}
var _morgue: Node3D = null


func _pick_morgue() -> void:
	_morgue_room = {}
	if not morgue_enabled or _module_level == null:
		return
	# Chosen by the level builder (module_level `_make_morgue_hall`): its block
	# is built as an enclosed hall, so the choice has to come before the meshes.
	var best_d := -1.0
	for room in _module_level.rooms:
		if room["kind"] == "morgue":
			_morgue_room = room
			best_d = (_module_level.room_world(room) as Vector3).distance_to(_module_level.spawn)
	if not _morgue_room.is_empty():
		print("[morgue] in the room at %s, %.0f m from the start; %d chest rooms left"
			% [_morgue_room["centre"], best_d, _module_level.chest_rooms().size()])


## True for tiles in the morgue's whole block, arcade included.
func is_in_morgue(tile: Vector2i) -> bool:
	if _morgue_room.is_empty():
		return false
	var mid := world_to_tile(_module_level.room_world(_morgue_room))
	var half := int(floor((float(_morgue_room["half"]) + 0.5) * module_cell / tile_size))
	return absi(tile.x - mid.x) <= half and absi(tile.y - mid.y) <= half


func morgue_centre() -> Variant:
	return null if _morgue_room.is_empty() else _module_level.room_world(_morgue_room)


## --- The surgery (2026-10-21) --------------------------------------------------------
##
## One more enclosed hall (module_level `_make_surgery_hall`), where the dead
## prisoners were to be made bionic: scripts/surgery.gd dresses it and wakes the
## surgical table in it (scripts/surgical_table.gd) -- a machine that cannot be
## killed, only depowered. No ordinary enemies spawn in it. Depowered, it stays
## so (`save_state` "surgery"); a reset with it still running puts it back to
## sleep on its pedestal.

@export var surgery_enabled := true
var _surgery_room: Dictionary = {}
var _surgery: Node3D = null


func _pick_surgery() -> void:
	_surgery_room = {}
	if not surgery_enabled or _module_level == null:
		return
	for room in _module_level.rooms:
		if room["kind"] == "surgery":
			_surgery_room = room
	if not _surgery_room.is_empty():
		print("[surgery] in the room at %s, %.0f m from the start"
			% [_surgery_room["centre"],
				(_module_level.room_world(_surgery_room) as Vector3).distance_to(_module_level.spawn)])


## True for tiles in the surgery's whole block.
func is_in_surgery(tile: Vector2i) -> bool:
	if _surgery_room.is_empty():
		return false
	var mid := world_to_tile(_module_level.room_world(_surgery_room))
	var half := int(floor((float(_surgery_room["half"]) + 0.5) * module_cell / tile_size))
	return absi(tile.x - mid.x) <= half and absi(tile.y - mid.y) <= half


func surgery_centre() -> Variant:
	return null if _surgery_room.is_empty() else _module_level.room_world(_surgery_room)


func surgery() -> Node3D:
	return _surgery


## --- Puzzle rooms and the shard door (2026-10-08) -----------------------------------
##
## Every chest room is a puzzle room (scripts/puzzle_room.gd): entering seals it
## (its gates, `_gates[r + 1]`, driven from `_process`) until the puzzle is
## solved, and solving it raises the room's chest -- with the room's shard in
## it -- on a plinth out of the floor. The one furthest from the start, by
## walking, holds the mimic instead (`mimic_index`), and the mimic carries the
## shard. No pedestals, no guards and no chests from `_spawn_chests` in this
## mode. The boss hall's arch is shut by the great door (scripts/shard_door.gd),
## which opens once every shard is set in it.

@export var puzzle_rooms := true
## How many of the chest rooms are prison blocks (dungeon_room.gd).
@export var prison_rooms := 2
## And how many are crystal mines (2026-10-10), never the mimic's room either.
@export var mine_rooms := 1

## One per chest room, in `chest_rooms()` order, so puzzle i seals gates i + 1.
var _puzzles: Array[Node3D] = []
var _shard_door: Node3D = null


func _puzzle_mode() -> bool:
	return modules and puzzle_rooms and _module_level != null


func _build_puzzle_rooms(holder: Node3D) -> void:
	_puzzles.clear()
	if not _puzzle_mode():
		return
	var rooms: Array[Dictionary] = _module_level.chest_rooms()
	if rooms.is_empty():
		return
	mimic_index = _far_room_from_start() if spawn_mimic else -1
	# The chest rooms (dungeon_room.gd, 2026-10-09; the puzzles are no longer
	# built): `prison_rooms` of them are prison blocks, never the mimic's room,
	# chosen by the seed; the rest are plain rooms until they are designed.
	var script = load("res://scripts/dungeon_room.gd")
	var pick := RandomNumberGenerator.new()
	pick.seed = _active_seed ^ 0x5eed
	var open: Array[int] = []
	for i in rooms.size():
		if i != mimic_index:
			open.append(i)
	var prisons := {}
	while prisons.size() < prison_rooms and not open.is_empty():
		prisons[open.pop_at(pick.randi_range(0, open.size() - 1))] = true
	# Then `mine_rooms` crystal mines, from what is left.
	var mines := {}
	while mines.size() < mine_rooms and not open.is_empty():
		mines[open.pop_at(pick.randi_range(0, open.size() - 1))] = true
	for i in rooms.size():
		var kind: StringName = &"prison" if prisons.has(i) else (&"mine" if mines.has(i) else &"vacant")
		var shard: StringName = Inventory.SHARDS[i % Inventory.SHARDS.size()]
		_puzzles.append(script.build(holder, _module_level, rooms[i], kind, shard,
			i == mimic_index, self, module_stone_tint))


## The mimic's room: far from the start both ways -- to walk to, and as the crow
## flies. (It used to be the first room met; at the user's request it is far
## away.) Walking alone is not enough: the first pick was the longest walk at
## 367 tiles but only 36 m from the start in a straight line, right beside it
## on the map. Each distance is scaled by the largest, and the best sum wins.
func _far_room_from_start() -> int:
	var rooms: Array[Dictionary] = _module_level.chest_rooms()
	var start := world_to_tile(_module_level.spawn)
	var steps := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		for step in DIRECTIONS.values():
			var next: Vector2i = tile + step
			if steps.has(next) or not is_open(next):
				continue
			steps[next] = int(steps[tile]) + 1
			queue.append(next)
	var walks: Array[float] = []
	var flies: Array[float] = []
	var most_walk := 1.0
	var most_fly := 1.0
	for i in rooms.size():
		var centre := world_to_tile(_module_level.room_world(rooms[i]))
		var fly := Vector2(centre - start).length()
		var walk := float(steps.get(centre, -1))
		if walk < 0.0:
			# Not reached by the walk (it should be): straight-line tiles instead.
			walk = fly
		walks.append(walk)
		flies.append(fly)
		most_walk = maxf(most_walk, walk)
		most_fly = maxf(most_fly, fly)
	var best := -1
	var best_score := -1.0
	for i in rooms.size():
		var score := walks[i] / most_walk + flies[i] / most_fly
		if score > best_score:
			best_score = score
			best = i
	print("[puzzle] the mimic's room is %d of %d: %.0f m to walk, %.0f m away"
		% [best, rooms.size(), walks[best] * tile_size, flies[best] * tile_size])
	return best


func _build_shard_door(holder: Node3D) -> void:
	_shard_door = null
	if not _puzzle_mode() or _boss_hall.is_empty() or _puzzles.is_empty():
		return
	var shards: Array[StringName] = []
	for p in _puzzles:
		shards.append(p.get("shard"))
	_shard_door = load("res://scripts/shard_door.gd").build(holder, _boss_hall["gate"],
		_boss_hall["gate_size"], float(_module_level.boss_hall["wall"]), shards)


## The mimic a puzzle room raised (or raised again after a death), so the room
## seals round its fight as it always did.
func register_mimic(m: Node) -> void:
	_mimic = m
	_mimic_committed = false


func puzzle_rooms_list() -> Array[Node3D]:
	return _puzzles


## --- Saving and loading (2026-10-09; save_system.gd, autoload "Saves") ---------------
##
## The level is rebuilt from its seed, so a save only has to say what has been
## DONE to it. Doors, cages and coffins are found by their order in the tree,
## which the seed fixes; node names cannot be used (the unnamed ones get
## counters that differ from run to run).

## Set once the level is built and populated; Saves will not save before.
var is_built := false
## The boss has been killed: he is not spawned again.
var boss_defeated := false

## --- Zones (2026-10-09) ---------------------------------------------------------
##
## The game will be a run of zones, each with its own boss; killing a zone's
## boss opens the ones after it. Only zone 1 exists so far (this level), so all
## this does yet is name the zone the player is in -- the save slots show it --
## and remember which zones' bosses are dead (`zones_cleared`), which is what
## will open the next. ZONE_NAMES are placeholders.
const ZONE_NAMES := {1: "Zone 1"}
## The zone this level is.
var zone := 1
var zones_cleared: Array[int] = []


func zone_name() -> String:
	return String(ZONE_NAMES.get(zone, "Zone %d" % zone))


## The zones the player may go to: the first, and each one after a cleared one.
## Nothing reads it yet -- the zones after 1 are not built.
func zones_open() -> Array[int]:
	var out: Array[int] = [1]
	for z in zones_cleared:
		if not out.has(z + 1):
			out.append(z + 1)
	return out


func _on_boss_died() -> void:
	boss_defeated = true
	if not zones_cleared.has(zone):
		zones_cleared.append(zone)


func _nodes_with(script_path: String) -> Array[Node]:
	var script := load(script_path)
	var out: Array[Node] = []
	for n in find_children("*", "", true, false):
		if n.get_script() == script:
			out.append(n)
	return out


func _indices(nodes: Array[Node], test: Callable) -> Array[int]:
	var out: Array[int] = []
	for i in nodes.size():
		if test.call(nodes[i]):
			out.append(i)
	return out


func save_state() -> Dictionary:
	var data := {"version": 1, "seed": _active_seed, "boss_defeated": boss_defeated,
		"zone": zone, "zone_name": zone_name(), "zones_cleared": zones_cleared.duplicate()}
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("save_state"):
		data["player"] = player.call("save_state")
	# Co-op: player 2 too, and the save marked as a co-op game's.
	var second := Coop.player(1) if Coop.active else null
	if second != null:
		data["player2"] = second.call("save_state")
		data["coop"] = true
	data["anchor"] = _anchors.find(active_anchor()) if active_anchor() != null else -1
	var map = _explore_map_node()
	if map != null:
		data["map"] = map.snapshot()
		# The player's own marks; a death does not forget them.
		data["pins"] = map.pins_state()
		# The sewer's charting (its own level of the map).
		data["map_levels"] = map.levels_state()
	data["map_checkpoint"] = _map_snapshot.duplicate()
	data["doors"] = _indices(_nodes_with("res://scripts/wood_door.gd"),
		func(n: Node) -> bool: return n.get("opened") == true)
	data["cages"] = _indices(_nodes_with("res://scripts/bone_cage.gd"),
		func(n: Node) -> bool: return n.get("looted") == true)
	# Hiding carts opened and searched (2026-10-12). A new key: the old
	# "coffins" listed every cart, and would read as all of them searched.
	data["carts"] = _indices(_nodes_with("res://scripts/hiding_spot.gd"),
		func(n: Node) -> bool: return n.get("searched") == true)
	var puzzles: Array = []
	for p in _puzzles:
		puzzles.append(p.call("save_state"))
	data["puzzles"] = puzzles
	if _shard_door != null:
		data["door"] = _shard_door.call("save_state")
	var open_holes: Array = []
	for i in _manholes.size():
		if _manholes[i].call("is_open"):
			open_holes.append(i)
	data["manholes"] = open_holes
	if _surgery != null:
		data["surgery"] = _surgery.call("save_state")
	return data


## What a save changed in the level itself; before `_populate`, so the boss is
## never spawned if he is dead and a kicked-in door never arms its blocker.
func restore_world(data: Dictionary) -> void:
	boss_defeated = bool(data.get("boss_defeated", false))
	zones_cleared.assign(data.get("zones_cleared", []))
	var doors := _nodes_with("res://scripts/wood_door.gd")
	for i in data.get("doors", []):
		if int(i) < doors.size():
			doors[int(i)].call("restore_opened")
	var cages := _nodes_with("res://scripts/bone_cage.gd")
	for i in data.get("cages", []):
		if int(i) < cages.size():
			cages[int(i)].call("restore_looted")
	var carts := _nodes_with("res://scripts/hiding_spot.gd")
	for i in data.get("carts", []):
		if int(i) < carts.size():
			carts[int(i)].call("restore_searched")
	for i in data.get("manholes", []):
		if int(i) < _manholes.size():
			_manholes[int(i)].call("set_open_now")
	if _surgery != null and data.has("surgery"):
		_surgery.call("restore_state", data["surgery"])
	var a := int(data.get("anchor", -1))
	if a >= 0 and a < _anchors.size():
		for other in _anchors:
			other.set_active(false)
		_anchors[a].set_active(true)
		_active_anchor = _anchors[a]
	var map = _explore_map_node()
	if map != null and data.has("map"):
		map.restore(data["map"])
	if map != null and data.has("pins"):
		map.restore_pins(data["pins"])
	if map != null and data.has("map_levels"):
		map.restore_levels(data["map_levels"])
	_map_snapshot = data.get("map_checkpoint", _map_snapshot)


## The player and everything that must come after the world is repopulated:
## `_populate` forgets the mimic, which a solved room puts back.
func restore_player(data: Dictionary) -> void:
	var puzzles: Array = data.get("puzzles", [])
	for i in mini(puzzles.size(), _puzzles.size()):
		_puzzles[i].call("restore_state", puzzles[i])
	if _shard_door != null and data.has("door"):
		_shard_door.call("restore_state", data["door"])
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var anchor := active_anchor()
	if anchor != null and player.has_method("set_spawn_point"):
		player.set_spawn_point(anchor.spawn_point())
	if data.has("player") and player.has_method("restore_state"):
		player.call("restore_state", data["player"])
	# Co-op: player 2 as saved -- beside player 1, wherever that put them.
	var second := Coop.player(1) if Coop.active else null
	if second != null:
		if anchor != null:
			second.set_spawn_point(anchor.spawn_point())
		if data.has("player2"):
			second.call("restore_state", data["player2"])
		(second as Node3D).global_position = _partner_spot((player as Node3D).global_position,
			(player as Node3D).rotation.y)
	print("[save] loaded: anchor %d, %d doors, %d cages, %d coffins, boss %s"
		% [int(data.get("anchor", -1)), (data.get("doors", []) as Array).size(),
			(data.get("cages", []) as Array).size(), (data.get("coffins", []) as Array).size(),
			"dead" if boss_defeated else "alive"])


func shard_door() -> Node3D:
	return _shard_door


## --- Respawn anchors ------------------------------------------------------------
##
## Obelisks in dead ends (scripts/respawn_anchor.gd). Attuning one (E, crosshair
## on it) makes it THE place the player rises after death until another is
## attuned; before any is, that is the start. Dead ends because they are alcoves
## off the corridors: an anchor there never blocks a way through. One always
## goes in the dead end nearest the boss's doorway, as a checkpoint before the
## fight; the rest are spread over the map, as far from each other and from
## the start as the dead ends allow.
##
## Dying costs the map: everything charted since the anchor the player rises at
## was attuned (or since the level began) is forgotten -- `_map_snapshot`,
## taken on attuning and restored on respawn.

@export var anchor_count := 5
## How far back from a dead end's centre the obelisk stands, away from its
## mouth. The plugged dead end's back wall is 2.79 m from the centre and the
## plinth is 1.3 m square, so this leaves ~0.9 m of stone clear behind it.
const ANCHOR_BACK := 1.2
## The anchors as the user placed them on the map of the fixed seed
## (2026-10-10), world x, z; each takes the nearest free dead end. Another seed
## falls back to the spread-out placement.
const ANCHOR_MARKS_SEED := 20260918
@export var anchor_marks := PackedVector2Array([
	Vector2(31.5, -107.5),   # north, between the north prison block and the morgue
	Vector2(139.0, -54.0),   # east (kept)
	Vector2(-106.3, 37.0),   # west
	Vector2(43.0, 90.5),     # south, below the south-east prison block
	Vector2(-42.0, 137.0),   # south-west (kept)
])

var _anchors: Array[Node3D] = []
var _active_anchor: Node3D = null
var _map_snapshot := {}


func _place_anchors(holder: Node3D) -> void:
	_anchors.clear()
	_active_anchor = null
	if anchor_count <= 0 or _module_level == null:
		return
	var depth: Dictionary = _module_level.get_meta("spawn_depth", {})
	var door_cells := {}
	for door in _module_level.doors:
		door_cells[door["cell"]] = true
		door_cells[door["other"]] = true
	var spawn_cell: Vector2i = _module_level.spawn_door.get("cell", Vector2i(-999, -999))
	# Every dead end that is a plain alcove off a corridor.
	# Neither script has a class_name; this file loads them where it needs them.
	var level_script = load("res://scripts/module_level.gd")
	var cells_script = level_script.ModuleMaze
	var spots: Array[Dictionary] = []
	for key: Vector2i in depth:
		var cell = _module_level.cells[key]
		if cell.kind != "dead" or cell.room >= 0 or cell.court or key == spawn_cell \
				or door_cells.has(key):
			continue
		if level_script.under_boss_hall(_module_level, _module_level.to_world(key)):
			continue
		var exit_side := -1
		for side: int in cells_script.ORDER:
			if cell.open & side:
				exit_side = side if exit_side < 0 else -2
		if exit_side < 0:
			continue
		var step: Vector2i = cells_script.DIRS[exit_side]
		spots.append({"cell": key, "out": Vector3(float(step.x), 0.0, float(step.y)),
			"depth": int(depth[key])})
	if spots.is_empty():
		print("[anchors] no dead ends to put an anchor in")
		return

	var chosen: Array[Dictionary] = []
	var nearest := spots[0]
	for s in spots:
		if int(s["depth"]) < int(nearest["depth"]):
			nearest = s
	# Placed by hand for the fixed seed: each mark (world x, z) takes the
	# nearest free dead end -- anchors stand in alcoves so they never block
	# a corridor.
	if _active_seed == ANCHOR_MARKS_SEED and not anchor_marks.is_empty():
		for mark in anchor_marks:
			var best_mark: Dictionary = {}
			var best_d := INF
			for s in spots:
				if chosen.has(s):
					continue
				var at: Vector3 = _module_level.to_world(s["cell"])
				var d := Vector2(at.x - mark.x, at.z - mark.y).length()
				if d < best_d:
					best_d = d
					best_mark = s
			if not best_mark.is_empty():
				chosen.append(best_mark)
				print("[anchors] mark (%.0f, %.0f) -> dead end %s, %.1f m away"
					% [mark.x, mark.y, best_mark["cell"], best_d])
		_build_anchors(holder, chosen, nearest)
		return

	# The one before the boss: the nearest by walking distance.
	chosen.append(nearest)
	# Then the rest, each as far as possible from everything already placed and
	# from the start.
	var placed: Array[Vector3] = [_module_level.spawn, _module_level.to_world(nearest["cell"])]
	while chosen.size() < anchor_count and chosen.size() < spots.size():
		var best: Dictionary = {}
		var best_gap := -1.0
		for s in spots:
			if chosen.has(s):
				continue
			var at: Vector3 = _module_level.to_world(s["cell"])
			var gap := INF
			for p in placed:
				gap = minf(gap, Vector2(at.x - p.x, at.z - p.z).length())
			if gap > best_gap:
				best_gap = gap
				best = s
		if best.is_empty():
			break
		chosen.append(best)
		placed.append(_module_level.to_world(best["cell"]))
	_build_anchors(holder, chosen, nearest)


func _build_anchors(holder: Node3D, chosen: Array[Dictionary], nearest: Dictionary) -> void:
	var level_script = load("res://scripts/module_level.gd")
	var parent := Node3D.new()
	parent.name = "RespawnAnchors"
	holder.add_child(parent)
	var script: GDScript = load("res://scripts/respawn_anchor.gd")
	for s in chosen:
		var out: Vector3 = s["out"]
		var anchor := Node3D.new()
		anchor.set_script(script)
		anchor.name = "Anchor%d" % _anchors.size()
		parent.add_child(anchor)
		# +Z out of the dead end, towards the corridor.
		anchor.global_basis = Basis.looking_at(-out, Vector3.UP)
		# The brick dead end's back wall is 1.9 m out, not 2.79.
		var back := 1.1 if level_script.brick else ANCHOR_BACK
		anchor.global_position = _module_level.to_world(s["cell"]) - out * back
		anchor.connect(&"attuned", _on_anchor_attuned)
		_anchors.append(anchor)
		# Nothing spawns inside the plinth.
		var foot := world_to_tile(anchor.global_position)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var t := foot + Vector2i(dx, dz)
				if t.x >= 0 and t.y >= 0 and t.x < tiles and t.y < tiles \
						and tile_to_world(t).distance_to(anchor.global_position) < 1.3:
					grid[t.y][t.x] = WALL
	print("[anchors] %d respawn anchors, nearest the boss at walking depth %d"
		% [_anchors.size(), int(nearest["depth"])])


## --- The Remnant and its hiding places (2026-10-08) --------------------------------
##
## One huge ghost (scripts/stalker.gd) wanders the corridors; once it sees the
## player it hunts them until they shut themselves in a hiding place
## (scripts/hiding_spot.gd). Hiding places are lidded hauling carts (2026-10-10;
## they were sarcophagi with a skeleton inside) left against the side walls of
## corridor straights, spread over the map as evenly as the straights allow.
## Built before the navmesh bake, like the anchors.

@export var hiding_spot_count := 18
## As with the enemies, the count follows the corridor in the module level:
## 18 over the old ~283 corridor cells (2026-10-09, after the maze tripled).
## 0 falls back to `hiding_spot_count`.
@export var hiding_spots_per_corridor_cell := 0.064
## Centre of a hiding cart from its straight's centre line: the side wall is
## 1.90 m out at the middle of a straight, the cart 1.0 m deep (its rails and
## lid 5 cm more each side), and Tripo stone stands up to ~10 cm proud of the
## wall, so 1.22 leaves its back just clear.
const HIDE_FROM_CENTRE := 1.22
const HIDE_FROM_CENTRE_BRICK := 1.05
@export var stalker_enabled := true
## The Remnant starts at a random spot among the furthest `stalker_far_share`
## of the corridor from the player, and never nearer than
## `stalker_min_distance`, each time the world resets. From there it wanders at
## random over the whole map (stalker.gd `_pick_wander`).
@export var stalker_min_distance := 100.0
@export_range(0.01, 1.0) var stalker_far_share := 0.1

var _hiding_spots: Array[Node3D] = []


func _place_hiding_spots(holder: Node3D) -> void:
	_hiding_spots.clear()
	if hiding_spot_count <= 0 or _module_level == null:
		return
	var level_script = load("res://scripts/module_level.gd")
	var cells_script = level_script.ModuleMaze
	var door_cells := {}
	for door in _module_level.doors:
		door_cells[door["cell"]] = true
		door_cells[door["other"]] = true
	var spawn_cell: Vector2i = _module_level.spawn_door.get("cell", Vector2i(-999, -999))
	# Every free side wall of every plain corridor straight.
	var spots: Array[Dictionary] = []
	for key: Vector2i in _module_level.cells:
		var cell = _module_level.cells[key]
		if cell.kind != "straight" or cell.room >= 0 or cell.court or door_cells.has(key) \
				or _module_level.niches.has(key) or _module_level.manholes.has(key):
			continue
		if absi(key.x - spawn_cell.x) + absi(key.y - spawn_cell.y) <= 1:
			continue
		if level_script.under_boss_hall(_module_level, _module_level.to_world(key), 3.0):
			continue
		for side: int in cells_script.ORDER:
			if cell.open & side:
				continue
			# Not over the wall's torch.
			if _module_level.torch_cells.has(key) and int(_module_level.torch_cells[key]) == side:
				continue
			# Nor against a brick wall's iron cage, which stands half a metre out.
			var cages: Dictionary = _module_level.get_meta("cage_walls", {})
			if cages.has(key) and side in cages[key]:
				continue
			var step: Vector2i = cells_script.DIRS[side]
			spots.append({"cell": key, "dir": Vector3(float(step.x), 0.0, float(step.y))})
	if spots.is_empty():
		print("[hiding] no corridor straights to hide in")
		return

	var want := hiding_spot_count
	if hiding_spots_per_corridor_cell > 0.0:
		want = roundi(float(_corridor_cell_count()) * hiding_spots_per_corridor_cell)

	# Spread out: each next one as far as possible from those already placed.
	# Each spot keeps its distance to the nearest one chosen, updated as each is
	# added, so this is spots x count rather than spots x count^2.
	var rng := RandomNumberGenerator.new()
	rng.seed = _active_seed ^ 0x5ade
	var first := rng.randi_range(0, spots.size() - 1)
	var chosen: Array[Dictionary] = [spots[first]]
	var where: Array[Vector3] = []
	var gaps := PackedFloat32Array()
	for s in spots:
		where.append(_module_level.to_world(s["cell"]))
		gaps.append(INF)
	var last := first
	while chosen.size() < want and chosen.size() < spots.size():
		gaps[last] = -1.0
		var best := -1
		var best_gap := -1.0
		for i in spots.size():
			if gaps[i] < 0.0:
				continue
			gaps[i] = minf(gaps[i], where[i].distance_to(where[last]))
			if gaps[i] > best_gap:
				best_gap = gaps[i]
				best = i
		# 0.5: never two in one cell (they would face each other across it).
		if best < 0 or best_gap < 0.5:
			break
		chosen.append(spots[best])
		last = best

	var parent := Node3D.new()
	parent.name = "HidingSpots"
	holder.add_child(parent)
	var script: GDScript = load("res://scripts/hiding_spot.gd")
	for s in chosen:
		var dir: Vector3 = s["dir"]
		var spot := Node3D.new()
		spot.set_script(script)
		spot.name = "Hide%d" % _hiding_spots.size()
		spot.set("maze", self)
		spot.set("skeleton_scene", enemy_scene)
		parent.add_child(spot)
		# Back to the wall, doors (+Z) to the corridor.
		spot.global_basis = Basis.looking_at(dir, Vector3.UP)
		# The Tripo cart's wheels reach 0.82 m from its middle: it stands further in.
		var from_centre := HIDE_FROM_CENTRE_BRICK if load("res://scripts/module_level.gd").brick else HIDE_FROM_CENTRE
		spot.global_position = _module_level.to_world(s["cell"]) + dir * from_centre
		_hiding_spots.append(spot)
		# Nothing spawns inside it: its footprint, long along the wall (the cart
		# runs ~1.65 m either way from its middle) and shallow across.
		var foot := world_to_tile(spot.global_position)
		var along := spot.global_basis.x
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var t := foot + Vector2i(dx, dz)
				if t.x < 0 or t.y < 0 or t.x >= tiles or t.y >= tiles:
					continue
				var off := tile_to_world(t) - spot.global_position
				off.y = 0.0
				if absf(off.dot(along)) < 1.8 and absf(off.dot(dir)) < 0.8:
					grid[t.y][t.x] = WALL
	print("[hiding] %d hiding places (of %d free corridor walls)" % [_hiding_spots.size(), spots.size()])


## Broken wood in the corridors (brick kit only; brick_level.place_clutter):
## kept out of door cells, the spawn and its neighbour, and any straight with a
## hiding cart. What it stands on is marked WALL in the grid, so nothing spawns
## inside it.
func _place_clutter(holder: Node3D) -> void:
	var level_script = load("res://scripts/module_level.gd")
	if _module_level == null or not level_script.brick:
		return
	var blocked := {}
	for door in _module_level.doors:
		blocked[door["cell"]] = true
		blocked[door["other"]] = true
	var spawn_cell: Vector2i = _module_level.spawn_door.get("cell", Vector2i(-999, -999))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			blocked[spawn_cell + Vector2i(dx, dz)] = true
	for spot in _hiding_spots:
		var p: Vector3 = (spot as Node3D).global_position
		blocked[Vector2i(roundi((p.x - _module_level.origin.x) / _module_level.cell_size),
			roundi((p.z - _module_level.origin.z) / _module_level.cell_size))] = true
	for key in _module_level.manholes:
		blocked[key] = true
	var solid: Array = level_script.BrickLevel.place_clutter(holder, _module_level, blocked, module_view_range)
	for s in solid:
		var at: Vector3 = s["at"]
		var half: Vector2 = s["half"]
		var foot := world_to_tile(at)
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var t := foot + Vector2i(dx, dz)
				if t.x < 0 or t.y < 0 or t.x >= tiles or t.y >= tiles:
					continue
				var off := tile_to_world(t) - at
				if absf(off.x) < maxf(half.x, half.y) and absf(off.z) < maxf(half.x, half.y):
					grid[t.y][t.x] = WALL
	print("[clutter] %d solid pieces of broken wood" % solid.size())


## Wet patches and drips (scripts/damp.gd). No drip in a door's cells (it would
## fall through a leaf) or a hiding cart's (into the cart).
func _place_damp(holder: Node3D) -> void:
	var level_script = load("res://scripts/module_level.gd")
	if _module_level == null or not level_script.brick:
		return
	var blocked := {}
	for door in _module_level.doors:
		blocked[door["cell"]] = true
		blocked[door["other"]] = true
	for spot in _hiding_spots:
		var p: Vector3 = (spot as Node3D).global_position
		blocked[Vector2i(roundi((p.x - _module_level.origin.x) / _module_level.cell_size),
			roundi((p.z - _module_level.origin.z) / _module_level.cell_size))] = true
	for key in _module_level.manholes:
		blocked[key] = true
	var damp: Node3D = load("res://scripts/damp.gd").new()
	holder.add_child(damp)
	damp.build(_module_level, blocked)


## An enemy something else raised (a sarcophagus's skeleton): parented, set up
## and tracked like the population, so a reset clears it with the rest.
func adopt_enemy(enemy: Node3D) -> void:
	add_child(enemy)
	if enemy.get("aggro_range") != null:
		enemy.set("aggro_range", enemy_aggro_range)
	_spawned.append(enemy)


## The Remnant, somewhere well away from the player. In `_spawned`, so a death
## puts it back at a fresh distance and calms it down.
func _spawn_stalker() -> void:
	if not stalker_enabled or not modules or _module_level == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var tiles_open := _spawn_candidates(true)
	if tiles_open.is_empty():
		return
	var spots: Array[Vector3] = []
	for t in tiles_open:
		spots.append(tile_to_world(t))
	var from: Vector3 = player.global_position if player != null else Vector3.ZERO
	# Very far away: a random spot among the furthest `stalker_far_share` of the
	# corridor (and never nearer than `stalker_min_distance`), so it starts --
	# and starts again after every death -- across the map from the player.
	var by_distance := spots.duplicate()
	by_distance.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return Vector2(a.x - from.x, a.z - from.z).length_squared() > Vector2(b.x - from.x, b.z - from.z).length_squared())
	var pool: Array[Vector3] = []
	var take := maxi(1, int(ceil(by_distance.size() * stalker_far_share)))
	for i in take:
		var p: Vector3 = by_distance[i]
		if Vector2(p.x - from.x, p.z - from.z).length() >= stalker_min_distance or pool.is_empty():
			pool.append(p)
	# Its own freshly randomised RNG: the maze's is seeded to repeat layouts, and
	# the global one is reseeded on every reset too -- with either, the Remnant
	# came back on the very same spot after every death.
	var roll := RandomNumberGenerator.new()
	roll.randomize()
	var start: Vector3 = pool[roll.randi_range(0, pool.size() - 1)]
	var shade := CharacterBody3D.new()
	shade.set_script(load("res://scripts/stalker.gd"))
	shade.name = "Remnant"
	shade.position = start + Vector3(0.0, 0.2, 0.0)
	shade.wander_spots = spots
	add_child(shade)
	_spawned.append(shade)
	print("[remnant] spawned %.0f m from the player" % Vector2(start.x - from.x, start.z - from.z).length())


func _on_anchor_attuned(anchor: Node3D) -> void:
	for other in _anchors:
		if is_instance_valid(other) and other != anchor:
			other.set_active(false)
	anchor.set_active(true)
	_active_anchor = anchor
	var map = _explore_map_node()
	if map != null:
		_map_snapshot = map.snapshot()
	# Co-op: the party rises there, both of them.
	for player in Coop.all():
		if player.has_method("set_spawn_point"):
			player.set_spawn_point(anchor.spawn_point())


## The anchor the player rises at, or null for the start.
func active_anchor() -> Node3D:
	return _active_anchor if is_instance_valid(_active_anchor) else null


## Hands the rooms the level built to the gameplay systems that expect them.
##
## Everything below was written for the tile maze's square rooms, and it all
## still works once it is told where the rooms are: `treasure_centres` drives
## the chests and the mimic, `_room_min/_room_max` is the boss test,
## `room_openings` places the gates that seal a room during a fight, and
## `_build_pillars` raises the boss columns and the chest pedestals -- the
## pre-Tripo pillars, in the same triplanar stone, which is what was asked for.
##
## Room 0 is the boss room and chest room r is r + 1 throughout this file
## (`seal_room`, `_process`, `_build_gates`), so the openings are filed in
## exactly that order, with an empty entry held for a missing boss room.
func _module_rooms() -> void:
	treasure_centres.clear()
	room_openings.clear()

	var boss: Dictionary = _module_level.boss_room()
	if boss.is_empty():
		room_openings.append([])
	else:
		var mid := world_to_tile(_module_level.room_world(boss))
		# Two different sizes, for two different jobs. The boss GUARDS the
		# courtyard, so its aggro box is the court. But `is_in_boss_room` is
		# also what keeps ordinary enemies from spawning in there, and sized
		# to the court it let them spawn in the arcade round it -- the whole
		# block, ring included, is the room.
		var court := int(floor(_module_level.court_half_span(boss) / tile_size))
		var block := int(floor((float(boss["half"]) + 0.5) * module_cell / tile_size))
		_room_min = mid - Vector2i(block, block)
		_room_max = mid + Vector2i(block, block)
		_reserved_min = _room_min
		_reserved_max = _room_max
		# Sizes the boss's guarded zone, which `_spawn_boss` reads in tiles.
		boss_room_tiles = court * 2 + 1
		# Columns halfway out from the centre: cover to fight around, well
		# clear of the doorways. Set in tiles, because that is what
		# `_build_pillars` multiplies.
		boss_pillar_offset = _module_level.court_half_span(boss) * 0.5 / tile_size
		room_openings.append(_room_openings_for(boss))

	var span := 0
	for room in _module_level.chest_rooms():
		treasure_centres.append(world_to_tile(_module_level.room_world(room)))
		room_openings.append(_room_openings_for(room))
		# The whole block, arcade included -- sized to the courtyard alone,
		# skeletons spawned in the arcade and were standing in the room.
		span = int(floor((float(room["half"]) + 0.5) * module_cell / tile_size)) * 2 + 1
	# `is_in_treasure_room` tests a square of this many tiles.
	if span > 0:
		treasure_room_tiles = span

	_build_pillars()
	_keep_sky_lights_off_rock()
	var doors := 0
	for list in room_openings:
		doors += list.size()
	print("[modules] rooms: boss %s, %d chest rooms, %d doorways, %d chest perches"
		% ["yes" if not boss.is_empty() else "NONE", treasure_centres.size(),
			doors, chest_perches.size()])


## The exploration map: a minimap top-right; the full map is the inventory's Map
## page (`toggle_map`, M -- inventory_screen.gd).
##
## It fills in as the player walks -- cells they have stood in or can see down
## an open corridor, never through a wall -- and persists across respawns,
## because it is built once with the level and never freed by `_populate`.
func _attach_explore_map() -> void:
	var script = load("res://scripts/explore_map.gd")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if script == null or player == null:
		push_warning("exploration map not attached (script or player missing)")
		return
	# Co-op: one for each player, each charting where its own player goes
	# (split_screen.gd shows each in its player's half). Player 1's is the one
	# saved and restored.
	for p in (Coop.all() if Coop.active else [player]):
		var map = script.new()
		map.name = "ExploreMap" if Coop.index_of(p) == 0 else "ExploreMap2"
		add_child(map)
		map.setup(_module_level, p)
		if _sewer != null:
			map.add_level(&"sewer", _sewer.get("map"))
		# The sandbox has the whole map charted (and a death keeps it so).
		if Sandbox.active:
			map.reveal_all()
		if Coop.index_of(p) == 0:
			_explore_map = map
	# What dying before any anchor is attuned leaves charted.
	_map_snapshot = _explore_map.snapshot()


## Player 1's explore map (a reference: in co-op it moves into their half of
## the screen, out from under the maze).
var _explore_map = null


func _explore_map_node():
	return _explore_map if _explore_map != null and is_instance_valid(_explore_map) else null


## What `boss_hall.gd` returned: the boss's spot, the throne's seat, the hall's
## zone and gate. {} on levels without one.
var _boss_hall := {}


func has_boss_hall() -> bool:
	return not _boss_hall.is_empty()


## The throne's seat, facing down the hall at the doorway (-Z), for whatever
## makes the boss sit on it. Transform3D() without a hall.
func boss_throne_seat() -> Transform3D:
	return _boss_hall.get("seat", Transform3D())


## The boss block's ground is not floor any more: under the hall it is a sealed
## hollow, and the only way through it is the stair. The tile grid says so,
## or spawners and wanderers would treat 42 m of hidden ground as open floor.
func _close_boss_block_grid() -> void:
	if _boss_hall.is_empty():
		return
	var plan: Dictionary = _module_level.boss_hall
	var door: Vector3 = plan["door"]
	var into: Vector3 = plan["into"]
	var across: Vector3 = plan["across"]
	var half: float = float(plan["stair_width"]) * 0.5 - tile_size * 0.5
	var top: float = plan["top"]
	for z in range(_room_min.y, _room_max.y + 1):
		for x in range(_room_min.x, _room_max.x + 1):
			if x < 0 or z < 0 or x >= tiles or z >= tiles:
				continue
			var d := tile_to_world(Vector2i(x, z)) - door
			var u := d.dot(across)
			var v := d.dot(into)
			grid[z][x] = OPEN if absf(u) <= half and v >= -tile_size and v <= top else WALL


func _room_openings_for(room: Dictionary) -> Array:
	var out := []
	for door in _module_level.room_doors(room):
		out.append({"tile": world_to_tile(door["world"]), "outward": door["outward"]})
	return out


## Paints the module layout into the tile grid the gameplay systems index.
func _rasterise_module_grid(builder) -> void:
	# `assign` rather than `=`: the builder hands back a plain Array and `grid`
	# is typed, so a direct assignment is refused at runtime and leaves the
	# grid empty -- which every spawner then reads as a level with no floor.
	grid.assign(builder.rasterise(_module_level, tiles, tile_size, OPEN, WALL))

	_start_tile = world_to_tile(_module_level.spawn)
	_start_tile.x = clampi(_start_tile.x, 0, tiles - 1)
	_start_tile.y = clampi(_start_tile.y, 0, tiles - 1)
	grid[_start_tile.y][_start_tile.x] = OPEN
	entrances = [_start_tile]

	# The grid is a proxy for the real geometry, and a proxy that has quietly
	# fragmented is worse than none: the spawner would pack every enemy into
	# whichever pocket it could reach. Measured on every build, because it
	# depends on the cell size, the tile size and the doorway width together.
	var open_total := 0
	for z in tiles:
		for x in tiles:
			if grid[z][x] == OPEN:
				open_total += 1
	var seen := {}
	var stack: Array[Vector2i] = [_start_tile]
	seen[_start_tile] = true
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var to: Vector2i = at + step
			if to.x < 0 or to.y < 0 or to.x >= tiles or to.y >= tiles:
				continue
			if seen.has(to) or grid[to.y][to.x] != OPEN:
				continue
			seen[to] = true
			stack.append(to)
	var reached := seen.size()
	print("[modules] %d cells, %d open tiles, %d reachable from spawn (%.1f%%)"
		% [_module_level.cells.size(), open_total, reached,
			100.0 * float(reached) / maxf(1.0, float(open_total))])
	var spawn_cell := Vector2i(
		int(round((_module_level.spawn.x - _module_level.origin.x) / module_cell)),
		int(round((_module_level.spawn.z - _module_level.origin.z) / module_cell)))
	var kind := "NONE"
	if _module_level.cells.has(spawn_cell):
		kind = _module_level.cells[spawn_cell].kind
	print("[modules] spawn %v -> tile %v, cell %v (%s), wall top %.1f m"
		% [_module_level.spawn, _start_tile, spawn_cell, kind, _module_level.height])
	if reached < open_total:
		push_warning(("module grid fragmented: %d of %d open tiles cannot be "
			+ "reached from spawn") % [open_total - reached, open_total])
		_report_islands(seen)


## Names the unreachable pockets, so a fragmented grid can be fixed rather
## than just noticed. A count alone says nothing about the cause; where they
## are and how big they are usually says it immediately.
func _report_islands(seen: Dictionary) -> void:
	var visited := {}
	var islands: Array[Dictionary] = []
	for z in tiles:
		for x in tiles:
			var at := Vector2i(x, z)
			if grid[z][x] != OPEN or seen.has(at) or visited.has(at):
				continue
			var members: Array[Vector2i] = []
			var stack: Array[Vector2i] = [at]
			visited[at] = true
			while not stack.is_empty():
				var cur: Vector2i = stack.pop_back()
				members.append(cur)
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var to: Vector2i = cur + step
					if to.x < 0 or to.y < 0 or to.x >= tiles or to.y >= tiles:
						continue
					if grid[to.y][to.x] != OPEN or visited.has(to) or seen.has(to):
						continue
					visited[to] = true
					stack.append(to)
			islands.append({"size": members.size(), "at": members[0]})
	islands.sort_custom(func(a, b): return a["size"] > b["size"])
	for i in mini(6, islands.size()):
		var where: Vector2i = islands[i]["at"]
		print("[modules]   island %d tiles near %v (cell %v)"
			% [islands[i]["size"], tile_to_world(where),
				Vector2i(int(round((tile_to_world(where).x - _module_level.origin.x)
						/ module_cell)),
					int(round((tile_to_world(where).z - _module_level.origin.z)
						/ module_cell)))])
	print("[modules]   %d islands total" % islands.size())
	for room in _module_level.rooms:
		print("[modules]   %s room at cell %v, %d entrances"
			% [room["kind"], room["centre"], (room["entrances"] as Array).size()])


func _apply_module_environment(builder) -> void:
	# The WorldEnvironment lives in main.tscn, not in this scene, and is found
	# by group -- the same way `player.gd` finds it.
	var we := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if we == null or we.environment == null:
		push_warning("no world_environment; the module level will use the authored sky")
		return
	var env := we.environment
	# Read the authored value once and keep it, so a preset round trip scales
	# from the original instead of compounding on itself.
	if not env.has_meta("authored_ambient"):
		env.set_meta("authored_ambient", env.ambient_light_energy)
	# `fog_enabled` is deliberately left as it is: fog is a quality knob that
	# `Graphics` owns, and `apply_all()` fires after `level_built` and would
	# overrule anything set here anyway.
	builder.configure_environment(env, module_ambient, env.fog_enabled)
	# The procedural red sky with drifting cloud replaces the authored
	# panorama. It only sets `sky` and `background_mode`, so it cannot undo
	# the ambient and grade set just above.
	var sky_setup = load("res://scripts/sky_setup.gd")
	if sky_setup != null:
		sky_setup.apply(env)
	_setup_moon()


## --- The red moon (2026-10-14) -------------------------------------------------
##
## The courts, the boss hall and the floors under the skylights are lit by a
## blood-red moon: the scene's "MoonLight" DirectionalLight3D, set up here,
## with real shadows, so it reaches only what is open to the sky and every
## pillar, arch, bar and body throws its shadow. It replaces the red omnis that
## used to fake a sky over each court and the spotlight under each skylight.
## The sky shader draws the moon's disc in the light's own direction
## (LIGHT0_DIRECTION), so what you see and what lights you agree.
##
## High in the sky: the skylights' shafts are 1.65 m deep through a 1.0 x 2.4 m
## opening, so the light only reaches the floor below them from a steep angle.
## Diagonal in azimuth so neither corridor direction loses its pool.
const MOON_ELEVATION := 72.0
const MOON_AZIMUTH := 45.0
const MOON_COLOUR := Color(0.86, 0.8, 1.0)
@export var moon_energy := 1.1
## Directional shadows only reach this far; past it the moon would light
## everything it faces, roofs or no roofs. Chunks are culled at
## `module_view_range` (70 m) plus a block's half diagonal, so the shadow must
## reach past that.
const MOON_SHADOW_DISTANCE := 95.0


func _setup_moon() -> void:
	var moon: DirectionalLight3D = null
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		moon = n as DirectionalLight3D
		break
	if moon == null:
		push_warning("maze: no DirectionalLight3D in the scene; no moon")
		return
	var el := deg_to_rad(MOON_ELEVATION)
	var az := deg_to_rad(MOON_AZIMUTH)
	var toward := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	# A directional light shines down its -Z.
	moon.global_basis = Basis.looking_at(-toward, Vector3.UP)
	moon.light_color = MOON_COLOUR
	moon.light_energy = moon_energy
	moon.light_specular = 0.2
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = MOON_SHADOW_DISTANCE
	moon.directional_shadow_blend_splits = true
	moon.directional_shadow_fade_start = 0.95
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.2
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	# Graphics._apply_light: off with shadows off (Potato), where it would light
	# every corridor through its roof.
	moon.set_meta("moon", true)
	# Graphics read this light's settings at startup (no shadow then): forget
	# them, so it records the moon as authored here.
	moon.remove_meta("gfx_light")
	var gfx := get_node_or_null("/root/Graphics")
	if gfx != null:
		gfx.call("_apply_to_node", moon)


## Puts the sealed doorways and the screen wipe in place.
func _build_zone_gates() -> void:
	var gate_script = load("res://scripts/zone_gate.gd")
	var fade_script = load("res://scripts/screen_fade.gd")
	if gate_script == null or fade_script == null:
		push_error("zone gate scripts are missing")
		return

	_module_fade = CanvasLayer.new()
	_module_fade.name = "ZoneFade"
	_module_fade.set_script(fade_script)
	add_child(_module_fade)

	var index := 0
	for gate in _module_level.gates:
		var area := Area3D.new()
		area.name = "ZoneGate%d" % index
		area.set_script(gate_script)
		area.position = gate["world"]
		add_child(area)
		area.setup(_module_fade, "zone_%d" % (index + 1),
			Vector3(module_cell * 0.5, module_cell * 0.6, module_cell * 0.5))
		# Locked until the boss is beaten. Nothing unlocks them yet -- that is
		# the user's own next step -- but the state and the signal are real,
		# so the hook is `gate.unlock()` and nothing else has to change.
		area.locked = true
		area.refused.connect(_on_zone_gate_refused)
		_zone_gates.append(area)
		index += 1


func _on_zone_gate_refused(gate: Node3D) -> void:
	# Deliberately quiet for now: there is no prompt UI yet, and a push_warning
	# every time the player brushes a locked door would bury real errors.
	if OS.is_debug_build():
		print("[modules] locked zone door: %s" % gate.zone_name)


## Unlocks the doorways to the other zones. Call this when the boss dies.
func unlock_zone_gates() -> void:
	for node in _zone_gates:
		if is_instance_valid(node) and node.has_method("unlock"):
			node.unlock()


func _build_organic_level() -> void:
	var graph_script = load("res://scripts/maze_graph.gd")
	var contour_script = load("res://scripts/wall_contour.gd")
	var builder = load("res://scripts/organic_maze.gd")
	var dressing = load("res://scripts/organic_dressing.gd")
	if graph_script == null or contour_script == null or builder == null:
		push_error("organic level is missing its scripts; falling back to the tile maze")
		organic = false
		tiles = 2 * cells + 1
		_compute_room_bounds()
		_carve_maze()
		_build_boss_room()
		_carve_treasure_rooms()
		_build_floor()
		_build_walls()
		_build_pillars()
		_build_ceiling()
		_build_arches()
		_build_torches()
		_build_debris()
		_build_leaning_bars()
		_build_jail_cells()
		return

	_graph = graph_script.new()
	_graph.boss_radius = organic_boss_radius
	_graph.corridor_radius = organic_corridor_radius
	_graph.cell_radius = 2.3
	_graph.boss_doors = organic_boss_doors
	_graph.dead_end_spurs = organic_dead_ends
	_graph.long_link_count = organic_long_links
	_graph.generate(_active_seed, organic_extent, 13.0, organic_chest_rooms, 7.0, 10.0)
	_graph.build_cells(_graph.safe_cell_count(1.8))
	_graph._build_index()

	# --- phases -------------------------------------------------------------
	# What ships is "phase 1" of a larger maze; killing the boss is meant to
	# open the next band later. Nothing unlocks yet -- `organic_phase_count`
	# defaults to 1, so every node is phase 0 and this is a no-op -- but the
	# seam is real: raise the count and lower `organic_active_phase` and the
	# level genuinely builds only the open region, because everything
	# downstream reads the graph through the restricted view.
	var phases_script = load("res://scripts/maze_phases.gd")
	if phases_script != null and organic_phase_count > 1:
		_phases = phases_script.assign(_graph, organic_phase_count)
		print("[organic] %s" % phases_script.summarise(_graph, _phases, organic_phase_count))
		_full_graph = _graph
		_graph = phases_script.view(_graph, _phases,
			clampi(organic_active_phase, 0, organic_phase_count - 1))
		print("[organic] phase %d of %d active: %d corridors of %d open"
			% [organic_active_phase, organic_phase_count,
				_graph.corridors.size(), _full_graph.corridors.size()])

	_trace_contour(contour_script)
	_rasterise_grid()
	_wall_top = float(organic_wall_rows) * 2.237

	# The authored 132 m floor plane and its box collider are both too small for
	# a 172 m map and would sit under solid rock anyway, so they are retired
	# rather than reused. They are hidden and disabled, NOT freed: `floor_mesh`
	# and `floor_shape` are `@onready` references and `Graphics.apply_all()`
	# walks them, and a freed node compares equal to null so the usual guard
	# would not catch it.
	floor_mesh.visible = false
	room_floor.visible = false
	floor_shape.disabled = true

	# Organic floor collision gets its own body so the builder's "clear my
	# targets first" contract cannot take the scene's authored children with it.
	# The kit's engaged piers get their OWN holder. `$PillarChunks` still
	# belongs to the pre-kit `_build_pillars()`, which builds the arena columns
	# and the chest-room pedestals and clears that node when it runs -- sharing
	# it freed the kit pillars out from under a deferred `Graphics` call and
	# threw 58 times a build.
	var kit_pillars := Node3D.new()
	kit_pillars.name = "KitPillars"
	add_child(kit_pillars)

	var organic_floor := StaticBody3D.new()
	organic_floor.name = "OrganicFloor"
	nav_region.add_child(organic_floor)

	if organic_baked_scene != null:
		# The frozen level carries its own walls, floor, ceiling, collision and
		# torches, already lightmapped. Parented under NavRegion so the navmesh
		# bake still sees its collision -- the bake walks that subtree, and a
		# level hung anywhere else would produce an empty navmesh and enemies
		# that cannot move.
		var baked := organic_baked_scene.instantiate()
		var frozen_seed: int = int(baked.get_meta("freeze_seed", -1))
		if frozen_seed != _active_seed:
			push_error(("baked level was frozen at seed %d but the maze is "
				+ "running seed %d -- the geometry will not match the grid, "
				+ "spawns or navigation. Re-run tools/freeze_level.gd or set "
				+ "maze_seed to %d.") % [frozen_seed, _active_seed, frozen_seed])
		nav_region.add_child(baked)
		_wall_top = float(organic_wall_rows) * 2.237
		print("[organic] baked level instanced (seed %d); generation skipped"
			% _active_seed)
		_organic_rooms()
		_build_pillars()
		_organic_archways()
		_organic_jail_cells()
		return

	var counts: Dictionary = builder.build(_graph, _loops, _contour_cell, _contour_origin, {
		"wall_chunks": wall_chunks,
		"wall_body": walls_body,
		"ceiling_chunks": ceiling_chunks,
		"floor_chunks": floor_chunk_holder,
		"floor_body": organic_floor,
		"pillar_chunks": kit_pillars,
		"occluder": occluder,
	}, {
		"wall_rows": organic_wall_rows,
		"vault_bay": organic_vault_bay,
		"vault_width": organic_vault_width,
		"pillar_spacing": organic_pillar_spacing,
		"slab": 3.0,
		"tint": organic_stone_tint,
	})
	print("[organic] %d wall panels, %d ceiling slabs, %d floor slabs, %d collision shapes, %d shell quads"
		% [counts.get("wall_panels", 0), counts.get("ceiling_slabs", 0),
			counts.get("floor_slabs", 0), counts.get("collision_shapes", 0), counts.get("shell_quads", 0)])

	# Authored BEFORE `Graphics.apply_all()` runs, because `_apply_visibility()`
	# stashes whatever it first sees as the authored value and scales from that
	# forever after. Set it later and the slider would compound on itself.
	for holder in [wall_chunks, ceiling_chunks, floor_chunk_holder]:
		_set_kit_view_range(holder, organic_view_range)

	var dressed := {}
	if dressing != null:
		# `_build_torches()` makes this holder at runtime rather than in the
		# scene, so the organic path has to make its own.
		var torches := Node3D.new()
		torches_node = torches
		torches.name = "Torches"
		add_child(torches)
		dressed = dressing.build(_graph, _loops, _contour_cell, _contour_origin, {
			"torches": torches,
			"debris_chunks": debris_chunks,
			"lean_chunks": lean_chunks,
		}, {
			"torch_spacing": 17.0,
			"torch_height": torch_height,
			"wall_top": _wall_top,
			"torch_scene": torch_scene,
			"torch_energy": organic_torch_energy,
			"seed": _active_seed,
			"skull_count": skull_count,
			"bone_count": bone_count,
		})
	else:
		push_warning("organic dressing module missing; the level will be unlit")

	print("[organic] %d torches, %d debris" % [dressed.get("torches", 0),
		dressed.get("debris", 0)])

	# --- bake the torchlight into the geometry ------------------------------
	# Run after the dressing, because it reads the torches that were actually
	# placed rather than recomputing where they should have gone.
	var lighting = load("res://scripts/organic_lighting.gd")
	if lighting != null and organic_bake_light:
		var lamps: Array = lighting.collect_torches(torches_node)
		# Red daylight spilling in through the barred windows. Baked as virtual
		# lights rather than placed as real ones: there are hundreds of window
		# panels, and hundreds of extra omni lights is exactly the per-pixel
		# cost the bake exists to avoid.
		for w in builder.last_windows:
			lamps.append({
				"pos": (w as Transform3D).origin - (w as Transform3D).basis.z * 0.4
					+ Vector3(0.0, 2.6, 0.0),
				"colour": organic_window_colour,
				"energy": organic_window_energy,
				"range": organic_window_range,
			})
		var lit: int = lighting.bake(
			[wall_chunks, ceiling_chunks, floor_chunk_holder], lamps,
			organic_ambient_floor, {"exposure": organic_bake_exposure})
		var freed: int = lighting.exclude_static_from(torches_node)
		print("[organic] baked %d instances from %d torches; %d lights now skip static geometry"
			% [lit, lamps.size(), freed])

	_organic_rooms()
	# The pre-kit pillar pass, reused rather than reimplemented: four
	# full-height columns in the arena and a stepped pedestal in each chest
	# room. It is also what fills `chest_perches`, which is what lets
	# `_spawn_chests()` put a chest -- and the mimic -- in every chamber.
	# `treasure_centres` and `boss_tile()` are both organic-aware by the time
	# this runs, so it needs no changes of its own.
	_build_pillars()
	_organic_archways()
	_organic_jail_cells()


## Rasterises the walkable region and traces its boundary into smoothed polylines.
func _trace_contour(contour_script) -> void:
	var res := maxi(organic_contour_res, 64)
	_contour_cell = ((organic_extent + organic_contour_margin) * 2.0) / float(res)
	_contour_origin = Vector2(-(organic_extent + organic_contour_margin) + _contour_cell * 0.5,
		-(organic_extent + organic_contour_margin) + _contour_cell * 0.5)

	var solid: Array = []
	for y in res:
		var row := []
		row.resize(res)
		for x in res:
			row[x] = _graph.inside(_contour_origin + Vector2(float(x), float(y)) * _contour_cell)
		solid.append(row)

	var open_at := func(x: int, z: int) -> bool:
		if x < 0 or z < 0 or x >= res or z >= res:
			return false
		return solid[z][x]

	_loops = []
	for loop in contour_script.trace(open_at, res):
		# Resample BEFORE smoothing. Chaikin cuts a corner in proportion to the
		# edge length, so on the raster's one-cell edges three passes ate 2 m out
		# of a 4 m corridor and pinched it shut.
		_loops.append(contour_script.smooth(contour_script.resample(loop, 1.2), 3))


## Is `p` open with at least `clear` metres of room around it?
##
## Probes `inside()` on a small diamond rather than calling `distance()`, which
## is the obvious way to ask and the wrong one here: `distance()` walks every
## corridor and every segment of each, while `inside()` goes through the graph's
## spatial index. At the grid sizes this now runs at, the difference is seconds
## per build against milliseconds.
func _has_clearance(p: Vector2, clear: float) -> bool:
	if not _graph.inside(p):
		return false
	for d: Vector2 in [Vector2(clear, 0.0), Vector2(-clear, 0.0),
			Vector2(0.0, clear), Vector2(0.0, -clear)]:
		if not _graph.inside(p + d):
			return false
	return true


## Projects the organic region onto the tile grid.
##
## A tile counts as open only if its CENTRE has real clearance, not merely if it
## is technically inside the region. Enemy spawning jitters a position by up to
## 1.3 m off the tile centre, so a tile that only clips the edge of a corridor
## would drop skeletons inside solid rock.
func _rasterise_grid() -> void:
	# Scaled to the corridor rather than fixed. A flat 1.6 m was fine in a 5.8 m
	# corridor and leaves nothing open in a 4.4 m one -- at 1.21 m clearance and
	# 2.5 m tiles the corridors vanished from the grid entirely and only 0.1% of
	# it was reachable from spawn.
	#
	# 0.45 keeps roughly a metre of margin either side of an enemy jittered the
	# full 1.3 m off a tile centre, which is what this clearance exists for.
	var clear: float = minf(1.6, organic_corridor_radius * 0.45)
	grid.clear()
	for z in tiles:
		var row := PackedByteArray()
		row.resize(tiles)
		for x in tiles:
			var p := tile_to_world(Vector2i(x, z))
			row[x] = OPEN if _has_clearance(Vector2(p.x, p.z), clear) else WALL
		grid.append(row)

	# The spawn tile is guaranteed open whatever the clearance test decided: the
	# player has to start somewhere, and the generator already promised this node
	# is a corridor junction.
	var spawn: Vector2 = _graph.nodes[_graph.spawn_node]
	_start_tile = world_to_tile(Vector3(spawn.x, 0.0, spawn.y))
	_start_tile.x = clampi(_start_tile.x, 0, tiles - 1)
	_start_tile.y = clampi(_start_tile.y, 0, tiles - 1)
	grid[_start_tile.y][_start_tile.x] = OPEN
	entrances = [_start_tile]

	# The grid is a proxy for the real geometry, and a proxy that has quietly
	# fragmented is worse than no proxy at all: the spawner would pack every
	# enemy into whichever pocket it could reach, and `_nearest_room_to_start()`
	# would choose the mimic's room by failing to walk to the others. Measured
	# on every build rather than assumed, because it depends on the corridor
	# radius and the tile size together and both are tunable.
	var open_total := 0
	for z in tiles:
		for x in tiles:
			if grid[z][x] == OPEN:
				open_total += 1
	var seen := {}
	var stack: Array[Vector2i] = [_start_tile]
	seen[_start_tile] = true
	var reached := 0
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		reached += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if nb.x < 0 or nb.y < 0 or nb.x >= tiles or nb.y >= tiles:
				continue
			if seen.has(nb) or grid[nb.y][nb.x] != OPEN:
				continue
			seen[nb] = true
			stack.append(nb)
	var pct: float = 100.0 * float(reached) / maxf(float(open_total), 1.0)
	print("[organic] grid %d tiles at %.1f m, %d open, %.1f%% reachable from spawn"
		% [tiles, tile_size, open_total, pct])
	if pct < 90.0:
		push_warning("organic grid is fragmented (%.1f%% reachable): enemy spawning and the mimic's room will be wrong" % pct)


## Fills in the room bookkeeping the population code reads: the arena's bounding
## box, the chambers standing in for treasure rooms, and the chest perches.
func _organic_rooms() -> void:
	var centre := world_to_tile(Vector3(_graph.boss_centre.x, 0.0, _graph.boss_centre.y))
	var half := int(ceil(_graph.boss_radius / tile_size))
	_room_min = centre - Vector2i(half, half)
	_room_max = centre + Vector2i(half, half)
	# The ring of rock the arena is cut out of; nothing spawns in it.
	_reserved_min = _room_min - Vector2i.ONE
	_reserved_max = _room_max + Vector2i.ONE

	treasure_centres.clear()
	room_openings.clear()
	# Index 0 belongs to the boss chamber; the chest rooms follow. Openings are
	# left empty because the organic arena has no tile-aligned doorways to hang a
	# portcullis in -- `seal_room()` then does nothing, rather than crashing on a
	# missing index.
	room_openings.append([])
	for i in _graph.chamber_at.keys():
		var c: Vector2 = _graph.nodes[i]
		treasure_centres.append(world_to_tile(Vector3(c.x, 0.0, c.y)))
		room_openings.append([])


## A stone archway where each corridor breaks into a chest room.
##
## The kit's `cell_frame` piece doubles as the doorway: it is a pair of jambs
## under a lintel, which is exactly what a room entrance wants. It is scaled up
## so its opening spans the corridor and its jambs land INSIDE the rock either
## side, which is what lets it be purely decorative -- a smaller arch standing
## proud in the passage would need collision of its own or the player would walk
## through the stonework.
##
## The rim crossing is found by walking the corridor's own polyline out from the
## chamber until it leaves the disc, not by stepping `radius` along the straight
## line to the neighbouring node: these corridors are bowed, so the straight line
## leaves the room somewhere the corridor does not.
func _organic_archways() -> void:
	var frame_mesh := _kit_mesh("res://models/kit/cell_frame_ready.glb")
	if frame_mesh == null or organic_archway_scale <= 0.0:
		return
	var holder := Node3D.new()
	holder.name = "Archways"
	add_child(holder)

	var s := organic_archway_scale
	var placed := 0
	for i in _graph.chamber_at.keys():
		var centre: Vector2 = _graph.nodes[i]
		var radius: float = float(_graph.chamber_at[i])
		for line in _graph.corridors:
			var n: int = line.size()
			if n < 2:
				continue
			var head: float = Vector2(line[0]).distance_to(centre)
			var tail: float = Vector2(line[n - 1]).distance_to(centre)
			# Only corridors with an end actually in this room.
			if minf(head, tail) > radius * 0.7:
				continue
			var forward := head <= tail

			var prev := Vector2(line[0]) if forward else Vector2(line[n - 1])
			var at := prev
			var tangent := Vector2.ZERO
			var found := false
			for k in n:
				var idx := k if forward else n - 1 - k
				var p := Vector2(line[idx])
				if p.distance_to(centre) >= radius:
					at = p
					tangent = p - prev
					found = true
					break
				prev = p
			if not found:
				continue
			if tangent.length_squared() < 0.000001:
				tangent = at - centre
			if tangent.length_squared() < 0.000001:
				continue
			tangent = tangent.normalized()

			var z_axis := Vector3(-tangent.x, 0.0, -tangent.y)
			var y_axis := Vector3.UP
			var x_axis := y_axis.cross(z_axis).normalized()
			var mi := MeshInstance3D.new()
			mi.mesh = frame_mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
			mi.transform = Transform3D(
				Basis(x_axis * s, y_axis * s, z_axis * s),
				Vector3(at.x, 0.0, at.y))
			placed += 1
	print("[organic] %d chest-room archways" % placed)


## One barred door per alcove, standing at the arena rim and facing in.
##
## These are real nodes rather than MultiMesh instances because they have to
## open: `release_cells()` lifts them like portcullises when the Warden calls its
## reinforcements. There are only 26, so the draw-call cost is irrelevant next to
## being able to animate them.
func _organic_jail_cells() -> void:
	for child in cells_holder.get_children():
		child.free()
	cell_doors.clear()
	cell_spots.clear()
	cell_facing.clear()
	cell_occupants.clear()

	var placer = load("res://scripts/kit_placer.gd")
	var door_mesh := _kit_mesh("res://models/kit/cell_door_ready.glb")
	var frame_mesh := _kit_mesh("res://models/kit/cell_frame_ready.glb")
	if placer == null or cell_door_scene == null:
		return

	var xforms: Array = placer.cell_door_transforms(_graph, cell_height)
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		var door := cell_door_scene.instantiate()
		# The placer already built a basis whose -Z looks into the arena. Using
		# it directly beats re-deriving a yaw from it: `atan2()` on the basis
		# vectors is easy to get 180 degrees wrong, and a door hung backwards
		# puts its hinges and bars on the wrong side of the archway.
		door.transform = t

		# Swap the scene's authored box bars for the kit's ironwork, keeping the
		# node that the open() tween drives.
		#
		# Done BEFORE the door enters the tree, and that ordering is the whole
		# point: `Graphics` reacts to `node_added` with a deferred
		# `_apply_to_node(node: Node)`, so adding first and freeing second
		# queues a call against an object that no longer exists. A freed object
		# cannot bind to a typed parameter at all -- the call fails on the way
		# in, where no `is_instance_valid()` guard can catch it -- and it threw
		# once per bar, every build.
		if door_mesh != null:
			var bars: Node3D = door.get_node_or_null(^"Bars")
			if bars != null:
				for b in bars.get_children():
					b.free()
				var mi := MeshInstance3D.new()
				mi.mesh = door_mesh
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bars.add_child(mi)
		cells_holder.add_child(door)

		# The stone archway is static, so it hangs off the door node's parent
		# rather than off `Bars` -- putting it under the bars would lift the
		# doorway out of the wall along with them.
		if frame_mesh != null:
			var fi := MeshInstance3D.new()
			fi.mesh = frame_mesh
			fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cells_holder.add_child(fi)
			# Same basis as the door, pushed back along its own -Z so the bars
			# sit inside the archway rather than z-fighting with its face.
			fi.transform = Transform3D(t.basis, t.origin - t.basis.z * 0.35)

		cell_doors.append(door)
		var alcove: Vector2 = _graph.cells[i] if i < _graph.cells.size() else Vector2.ZERO
		cell_spots.append(Vector3(alcove.x, 0.3, alcove.y))
		# Typed explicitly: `_graph` is untyped (the script is `load()`ed, not
		# preloaded), so `:=` cannot infer anything from its members.
		var out: Vector2 = _graph.boss_centre - alcove
		cell_facing.append(atan2(out.x, out.y) if out.length_squared() > 0.0001 else 0.0)
		cell_occupants.append(null)


## Hangs a portcullis in each of the arena's two mouths.
##
## Kept separate from `_build_gates()` because that one positions a gate on a
## tile centre and yaws it to a cardinal `Vector2i` outward direction. The
## organic doors sit at arbitrary angles around the rim, and snapping their
## rotation to the nearest cardinal would leave the bars crossing the doorway
## diagonally with a gap at each side -- the boss would simply walk out.
##
## Only the boss chamber gets gates. The chest chambers are open bulges in the
## corridor network with no doorway to fill, so their `_gates` entries stay
## empty and `seal_room()` becomes a no-op for them.
func _organic_gates() -> void:
	var made: Array[Node] = []
	for dir in _graph.boss_door_dirs:
		var d: Vector2 = dir
		if d.length_squared() < 0.000001:
			continue
		d = d.normalized()
		var mouth: Vector2 = _graph.boss_centre + d * _graph.boss_radius
		var gate := gate_scene.instantiate()
		gate.position = Vector3(mouth.x, 0.0, mouth.y)
		# Face back along the door's own direction, so the bars span the opening
		# square-on rather than at whatever angle the nearest axis happens to be.
		gate.rotation.y = atan2(d.x, d.y)
		gates_holder.add_child(gate)
		made.append(gate)
	_gates.append(made)
	# The chest chambers still need their slots so `seal_room(mimic_index + 1)`
	# indexes something rather than falling off the end.
	for i in treasure_centres.size():
		_gates.append([] as Array[Node])


## Gives every chunk under `holder` a draw distance, so `Graphics`' View
## distance slider has something to scale. A chunk with `visibility_range_end`
## left at 0 is exempt from the setting entirely.
func _set_kit_view_range(holder: Node3D, metres: float) -> void:
	if holder == null or metres <= 0.0:
		return
	# Recursive, because the builder groups its chunks under a per-kind holder
	# ("Wall_panel", "Ceiling", "Floor") -- the MultiMeshInstance3Ds are
	# grandchildren, not children. Walking one level deep set the range on
	# nothing at all and the setting silently did nothing.
	var stack: Array = [holder]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is GeometryInstance3D:
				var g := child as GeometryInstance3D
				g.visibility_range_end = metres
				g.visibility_range_end_margin = metres * 0.15
				g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			stack.append(child)


## Pulls the one mesh out of a kit .glb, which Godot imports as a PackedScene.
func _kit_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("kit piece missing: %s" % path)
		return null
	var packed = load(path)
	if packed == null:
		return null
	var inst = packed.instantiate()
	var found: Mesh = null
	var stack: Array = [inst]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and found == null:
			found = (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	inst.queue_free()
	return found


func _compute_room_bounds() -> void:
	var centre := boss_tile()
	var half := boss_room_tiles / 2
	_room_min = centre - Vector2i(half, half)
	_room_max = centre + Vector2i(half, half)
	# One tile of wall all the way around the interior.
	_reserved_min = _room_min - Vector2i.ONE
	_reserved_max = _room_max + Vector2i.ONE


func _is_reserved(tile: Vector2i) -> bool:
	return (
		tile.x >= _reserved_min.x and tile.x <= _reserved_max.x
		and tile.y >= _reserved_min.y and tile.y <= _reserved_max.y
	)


## Iterative backtracker over the odd-coordinate cells, routed around the
## reserved chamber so the maze grows as a ring surrounding it.
func _carve_maze() -> void:
	grid.clear()
	for z in tiles:
		var row := PackedByteArray()
		row.resize(tiles)
		row.fill(WALL)
		grid.append(row)

	var stack: Array[Vector2i] = [_start_tile]
	grid[_start_tile.y][_start_tile.x] = OPEN
	var steps := [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]

	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var options: Array[Vector2i] = []
		for step in steps:
			var next: Vector2i = current + step
			if next.x <= 0 or next.y <= 0 or next.x >= tiles - 1 or next.y >= tiles - 1:
				continue
			if grid[next.y][next.x] != WALL:
				continue
			# Neither the destination nor the wall knocked out to reach it may
			# intrude on the chamber.
			if _is_reserved(next) or _is_reserved(current + step / 2):
				continue
			options.append(next)

		if options.is_empty():
			stack.pop_back()
			continue

		var chosen: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
		var between: Vector2i = current + (chosen - current) / 2
		grid[between.y][between.x] = OPEN
		grid[chosen.y][chosen.x] = OPEN
		stack.append(chosen)


func _build_boss_room() -> void:
	# Solid ring first, then hollow out the interior.
	for z in range(_reserved_min.y, _reserved_max.y + 1):
		for x in range(_reserved_min.x, _reserved_max.x + 1):
			if x < 0 or z < 0 or x >= tiles or z >= tiles:
				continue
			grid[z][x] = WALL
	for z in range(_room_min.y, _room_max.y + 1):
		for x in range(_room_min.x, _room_max.x + 1):
			grid[z][x] = OPEN

	entrances.clear()
	var names := DIRECTIONS.keys()
	for i in boss_room_entrances:
		var gate := _open_gate(DIRECTIONS[names[i]])
		if gate != Vector2i(-1, -1):
			entrances.append(gate)


## Opens a doorway through the ring and tunnels outward until it meets the maze,
## which guarantees the chamber is reachable whatever the corridor parity is.
func _open_gate(direction: Vector2i) -> Vector2i:
	var centre := boss_tile()
	var half := boss_room_tiles / 2
	var tile: Vector2i = centre + direction * (half + 1)
	var doorway := tile
	var guard := 0

	while guard < tiles:
		guard += 1
		if tile.x <= 0 or tile.y <= 0 or tile.x >= tiles - 1 or tile.y >= tiles - 1:
			return doorway
		grid[tile.y][tile.x] = OPEN
		if is_open(tile + direction):
			return doorway
		tile += direction
	return doorway


## Rooms are only ever carved open, never walled, so they cannot break
## connectivity: an odd-sized room on an odd centre always contains corridor
## cells that were already reachable.
func _carve_treasure_rooms() -> void:
	treasure_centres.clear()
	var half := treasure_room_tiles / 2
	var attempts := 0
	var limit := treasure_rooms * 40

	while treasure_centres.size() < treasure_rooms and attempts < limit:
		attempts += 1
		# Odd coordinates only, and far enough inside that the room fits.
		var cx := _rng.randi_range(1, cells - 1) * 2 + 1
		var cz := _rng.randi_range(1, cells - 1) * 2 + 1
		var centre := Vector2i(cx, cz)

		if centre.x - half < 1 or centre.y - half < 1:
			continue
		if centre.x + half > tiles - 2 or centre.y + half > tiles - 2:
			continue
		# Clear of the boss chamber and its ring.
		if _rect_hits_reserved(centre, half):
			continue
		# And clear of the player's start and of each other.
		if Vector2(centre - _start_tile).length() <= float(safe_tiles_from_start):
			continue
		var too_close := false
		for other in treasure_centres:
			if absi(other.x - centre.x) <= treasure_room_tiles and absi(other.y - centre.y) <= treasure_room_tiles:
				too_close = true
				break
		if too_close:
			continue

		for z in range(centre.y - half, centre.y + half + 1):
			for x in range(centre.x - half, centre.x + half + 1):
				grid[z][x] = OPEN
		treasure_centres.append(centre)


func _rect_hits_reserved(centre: Vector2i, half: int) -> bool:
	return (
		centre.x + half >= _reserved_min.x and centre.x - half <= _reserved_max.x
		and centre.y + half >= _reserved_min.y and centre.y - half <= _reserved_max.y
	)


func _build_floor() -> void:
	var span := float(tiles) * tile_size
	(floor_mesh.mesh as PlaneMesh).size = Vector2(span, span)
	# Collision is one flat slab regardless of the relief above it, which keeps
	# the navmesh bake and the player's footing perfectly predictable.
	(floor_shape.shape as BoxShape3D).size = Vector3(span, 0.4, span)
	floor_shape.position = Vector3(0, -0.2, 0)

	# The authored plane survives only as the material template. The ground you
	# actually see is the chunk grid below, which can be culled a piece at a
	# time where one 132 m slab never could.
	var material := floor_mesh.get_active_material(0)
	floor_mesh.visible = false

	for child in floor_chunk_holder.get_children():
		child.free()

	var relief := FastNoiseLite.new()
	relief.seed = _active_seed
	relief.frequency = 0.035
	relief.fractal_octaves = 3
	_relief = relief

	var half := span * 0.5
	var step := span / float(floor_chunks * floor_quads)
	for cz in floor_chunks:
		for cx in floor_chunks:
			var chunk := MeshInstance3D.new()
			chunk.mesh = _floor_chunk_mesh(cx, cz, half, step, relief)
			chunk.material_override = material
			# The ground is the bottom of the world. Nothing is under it for it
			# to shadow, so keep it out of the hand torch's cube map entirely.
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			floor_chunk_holder.add_child(chunk)

	# A distinct floor for the chamber, lifted a hair to avoid z-fighting.
	var room_span := float(boss_room_tiles) * tile_size
	(room_floor.mesh as PlaneMesh).size = Vector2(room_span, room_span)
	room_floor.position = tile_to_world(boss_tile()) + Vector3(0, 0.02, 0)


## One square of ground. Vertex positions come from a grid index global to the
## whole floor rather than one local to the chunk, so the two chunks meeting at
## a seam compute bit-identical coordinates and there is no hairline crack
## between them.
func _floor_chunk_mesh(
	cx: int, cz: int, half: float, step: float, relief: FastNoiseLite
) -> ArrayMesh:
	var side := floor_quads + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(side * side)
	norms.resize(side * side)
	uvs.resize(side * side)

	# Chunks are positioned at the origin and hold world-space vertices, so the
	# texture and the relief are continuous across the whole floor.
	for j in side:
		for i in side:
			var x := -half + float(cx * floor_quads + i) * step
			var z := -half + float(cz * floor_quads + j) * step
			var at := j * side + i
			verts[at] = Vector3(x, _ground_height(x, z, relief), z)
			norms[at] = _ground_normal(x, z, step, relief)
			uvs[at] = Vector2(x, z) / floor_texture_metres

	for j in floor_quads:
		for i in floor_quads:
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var d := c + 1
			# Wound so the faces point up; see _ground_normal for the axes.
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Height of the ground at a world point. Biased entirely downward: the flat
## collision slab sits at y = 0, so the surface may sink below it as much as it
## likes but must never rise above it, or the player would walk with their feet
## buried in a mound of visible mud.
func _ground_height(x: float, z: float, relief: FastNoiseLite) -> float:
	var broad := relief.get_noise_2d(x, z) * 0.65
	var fine := relief.get_noise_2d(x * 3.1 + 100.0, z * 3.1 - 100.0) * 0.35
	return ((broad + fine) * 0.5 - 0.5) * floor_relief


## Derived from the height field by central difference rather than from the
## triangles, so neighbouring chunks agree exactly along their shared edge and
## the lighting does not crease there.
func _ground_normal(x: float, z: float, step: float, relief: FastNoiseLite) -> Vector3:
	var e := step * 0.5
	var dx := _ground_height(x + e, z, relief) - _ground_height(x - e, z, relief)
	var dz := _ground_height(x, z + e, relief) - _ground_height(x, z - e, relief)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Wall tiles are merged into horizontal runs: far fewer collision shapes, and
## fewer internal edges for the player to snag on while sliding along a wall.
func _build_walls() -> void:
	for child in walls_body.get_children():
		child.free()

	var runs: Array[Vector3] = []  # x centre, z centre, length in tiles
	for z in tiles:
		var x := 0
		while x < tiles:
			if grid[z][x] != WALL:
				x += 1
				continue
			var run_start := x
			while x < tiles and grid[z][x] == WALL:
				x += 1
			var length := x - run_start
			var first := tile_to_world(Vector2i(run_start, z))
			var last := tile_to_world(Vector2i(x - 1, z))
			runs.append(Vector3((first.x + last.x) * 0.5, last.z, float(length)))

	var boxes: Array[Dictionary] = []
	for run in runs:
		var width := run.z * tile_size
		var size := Vector3(width, wall_height, tile_size)
		var centre := Vector3(run.x, wall_height * 0.5, run.y)
		boxes.append({"centre": centre, "size": size})

		var box := BoxShape3D.new()
		box.size = size
		var collider := CollisionShape3D.new()
		collider.shape = box
		collider.position = centre
		walls_body.add_child(collider)

	_spawn_chunks(wall_chunks, wall_visuals, boxes)
	# The walls are what actually hides the rest of the maze, so they are also
	# what the occlusion culler tests against.
	_build_occluders(boxes)


## Columns in the boss chamber and every treasure room. Built before the navmesh
## bake and parented under the region, so enemies path around them rather than
## grinding into them.
func _build_pillars() -> void:
	for child in pillars_body.get_children():
		child.free()
	_pillars.clear()

	# Boss chamber: four full-height columns -- not with the boss hall, whose
	# block is a stairwell and a sealed hollow; the hall has its own columns.
	var boss_centre := tile_to_world(boss_tile())
	var boss_offset := boss_pillar_offset * tile_size
	var hall: bool = modules and _module_level != null and not _module_level.boss_hall.is_empty()
	for sx in ([] if hall else [-1.0, 1.0]):
		for sz in [-1.0, 1.0]:
			_pillars.append({
				"base": boss_centre + Vector3(sx * boss_offset, 0.0, sz * boss_offset),
				"size": Vector3(pillar_size, wall_height, pillar_size),
				"column": true,
			})

	# Treasure rooms: a pedestal for the chest, with a staircase of blocks
	# leading up to it. The approach direction is rotated per room so they do
	# not all look identical.
	chest_perches.clear()
	chest_layouts.clear()
	var styles := ["line", "spiral", "scattered"]
	for index in treasure_centres.size():
		var room := tile_to_world(treasure_centres[index])
		# Puzzle rooms raise their own plinth once solved (puzzle_room.gd).
		if _puzzle_mode():
			break
		var rise := _rng.randf_range(step_rise_min, step_rise_max)
		var steps := _rng.randi_range(step_count_min, step_count_max)
		# One rise above the top step, so the last hop is the same as the rest.
		var pedestal := rise * float(steps + 1)
		var style: String = styles[_rng.randi_range(0, styles.size() - 1)]
		var facing := _rng.randf() * TAU
		var spacing := _rng.randf_range(1.0, 1.25)

		chest_layouts.append({
			"style": style, "steps": steps,
			"rise": snappedf(rise, 0.01), "pedestal": snappedf(pedestal, 0.01),
		})

		_pillars.append({
			"base": room,
			"size": Vector3(chest_pedestal_size, pedestal, chest_pedestal_size),
			"pedestal": true,
		})
		chest_perches.append(room + Vector3(0, pedestal, 0))

		for step in steps:
			# The staircase has to climb *toward* the pedestal: the tallest step
			# is the one nearest it, so the last hop is one rise like the rest.
			var level := step + 1
			var height := rise * float(level)
			var out := float(steps - level + 1)
			var distance := chest_pedestal_size * 0.5 + 0.7 + out * spacing
			var angle := facing
			# Kept modest: a big swing between consecutive steps turns a short
			# hop up into a long hop sideways.
			match style:
				"spiral":
					# Winds around the pedestal on the way up.
					angle += float(out) * 0.75
				"scattered":
					angle += _rng.randf_range(-0.35, 0.35)
			_pillars.append({
				"base": room + Vector3(cos(angle), 0.0, sin(angle)) * distance,
				"size": Vector3(step_size, height, step_size),
			})

	var rock := _rock_mesh(ROCK_PILLAR) if modules else null
	var column := _rock_mesh(ROCK_COLUMN) if rock != null else null
	var pillar_boxes: Array[Dictionary] = []
	for i in _pillars.size():
		var size: Vector3 = _pillars[i]["size"]
		var centre: Vector3 = _pillars[i]["base"] + Vector3(0, size.y * 0.5, 0)
		pillar_boxes.append({"centre": centre, "size": size})

		var collider := CollisionShape3D.new()
		if rock != null:
			# The rock is round in plan. A box of the same size would stick
			# its corners out of the stone, and on a step that is a ledge of
			# thin air to stand on.
			var cylinder := CylinderShape3D.new()
			cylinder.radius = size.x * 0.5
			cylinder.height = size.y
			collider.shape = cylinder
		else:
			var box := BoxShape3D.new()
			box.size = size
			collider.shape = box
		collider.position = centre
		pillars_body.add_child(collider)

	if rock != null:
		_spawn_rock_chunks(rock, column)
	else:
		_spawn_chunks(pillar_chunks, pillar_visuals, pillar_boxes)


## Rock from `tools/build_rock_pillar.py`, origin at the centre of a flat
## base. The pillar is 1 m on every axis and is scaled to each pedestal and
## step. The column is baked at its real 1.3 x 9 m, because the texture follows
## the mesh's own UVs, and stretching the unit rock 9x drew its cracks out into
## wood grain. World triplanar is no answer either: the baked texture does not
## tile, so its UV islands showed up as horizontal bands, which on a column
## look like stacked drums of masonry.
const ROCK_PILLAR := "res://models/kit/rock_pillar.glb"
const ROCK_COLUMN := "res://models/kit/rock_column.glb"
const ROCK_COLUMN_SIZE := Vector3(1.3, 9.0, 1.3)
## A render layer for the rock alone, so the courtyard sky lights can leave it
## out. Those hang right over the columns and the pedestal: in the boss room
## the light sits INSIDE the top of each 9 m column, and a chest room's single
## light is 6 m over its pedestal. At energy 22 that blew the dark rock out to
## pale concrete and pink blotches whatever its albedo was. Torches, the hand
## torch and ambient still reach it.
const ROCK_VISUAL_LAYER := 1 << 11

var _rock_meshes := {}
var _room_sky_lights: Node3D = null


func _keep_sky_lights_off_rock() -> void:
	# No sky omnis since the moon (2026-10-14): the rock is moonlit like the
	# rest of the court, and needs no fill of its own.
	if _room_sky_lights == null or _room_sky_lights.get_child_count() == 0:
		return
	for light in _room_sky_lights.find_children("*", "Light3D", true, false):
		(light as Light3D).light_cull_mask &= ~ROCK_VISUAL_LAYER
	# With the sky lights off it, the rock only had the cool ambient, and
	# columns across the court read as flat blue-black cut-outs. One sky-
	# coloured fill per room reaches the rock and nothing else, from a spot
	# clear of it: the middle of the boss court (its columns stand on the
	# diagonals), and off-centre in a chest court, where the pedestal is.
	for room in _module_level.rooms:
		var mid: Vector3 = _module_level.room_world(room)
		var half: float = _module_level.court_half_span(room)
		var fill := OmniLight3D.new()
		fill.name = "RockFill"
		# SKY_LIGHT_COLOUR in module_level.gd, so the rock is lit by the same sky.
		fill.light_color = Color(1.0, 0.44, 0.32)
		# The pedestal is nearer its fill than the boss columns are to theirs.
		fill.light_energy = ROCK_FILL_ENERGY * (1.0 if room["kind"] == "boss" else 0.4)
		fill.omni_range = half * 2.2
		fill.omni_attenuation = 0.75
		fill.light_specular = 0.0
		fill.shadow_enabled = false
		fill.light_cull_mask = ROCK_VISUAL_LAYER
		fill.distance_fade_enabled = true
		fill.distance_fade_begin = 55.0
		fill.distance_fade_length = 15.0
		var off := Vector3.ZERO if room["kind"] == "boss" else Vector3(-0.6, 0, -0.6) * half
		fill.position = mid + off + Vector3(0, 7.0, 0)
		_room_sky_lights.add_child(fill)


## Well under the sky lights' 22: the fill is nearer the rock than they are to
## the walls, and the columns should stay darker than the court around them.
const ROCK_FILL_ENERGY := 9.0


## Null if the asset is missing, in which case the pillars fall back to the
## old stone boxes.
func _rock_mesh(path: String) -> Mesh:
	if _rock_meshes.has(path):
		return _rock_meshes[path]
	var mesh: Mesh = null
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			mesh = (node as MeshInstance3D).mesh
			break
		scene.free()
	if mesh == null:
		push_warning("%s missing; falling back" % path)
	_rock_meshes[path] = mesh
	return mesh


## Rock columns, one MultiMesh per chunk and mesh. Base-origin instances, so
## the position is the pillar's base, with a yaw derived from the position so
## neighbouring columns do not show the same face. Columns are scaled relative
## to their native size, which is 1:1 at the default `pillar_size` and
## `wall_height`.
func _spawn_rock_chunks(rock: Mesh, column: Mesh) -> void:
	for child in pillar_chunks.get_children():
		child.free()
	var span := float(chunk_tiles) * tile_size
	var groups := {}
	for pillar in _pillars:
		var tall: bool = pillar.get("column", false) and column != null
		var base: Vector3 = pillar["base"]
		var key := Vector3i(int(floor(base.x / span)), int(floor(base.z / span)), 1 if tall else 0)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(pillar)
	for key in groups:
		var tall: bool = key.z == 1
		var list: Array = groups[key]
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = column if tall else rock
		mesh.instance_count = list.size()
		for i in list.size():
			var base: Vector3 = list[i]["base"]
			var size: Vector3 = list[i]["size"]
			var scale := size / ROCK_COLUMN_SIZE if tall else size
			var yaw := fposmod(base.x * 12.9898 + base.z * 78.233, TAU)
			var basis := Basis.from_scale(scale).rotated(Vector3.UP, yaw)
			mesh.set_instance_transform(i, Transform3D(basis, base))
		var chunk := MultiMeshInstance3D.new()
		chunk.name = "RockColumns" if tall else "RockPillars"
		chunk.multimesh = mesh
		chunk.material_override = _darker_rock(mesh.mesh)
		# Its OWN layer only: a light reaches an instance when the two masks
		# share any bit, so keeping layer 1 as well would defeat the point.
		chunk.layers = ROCK_VISUAL_LAYER
		pillar_chunks.add_child(chunk)
	pillar_visuals.multimesh.instance_count = 0


## Darkens the pillar rock without touching its texture: the baked albedo and
## normal (the stone detail) stay, only the albedo multiplier drops.
const ROCK_DARKEN := Color(0.68, 0.68, 0.7)
var _dark_rock := {}


func _darker_rock(mesh: Mesh) -> Material:
	if _dark_rock.has(mesh):
		return _dark_rock[mesh]
	var source := mesh.surface_get_material(0) as StandardMaterial3D
	if source == null:
		return null
	var m := source.duplicate() as StandardMaterial3D
	m.albedo_color = source.albedo_color * ROCK_DARKEN
	_dark_rock[mesh] = m
	return m




## Splits a pile of boxes into per-region MultiMesh instances, each of which the
## renderer can cull on its own. `template` supplies the mesh and material and
## is then emptied.
## `casts_shadow` is worth turning off for anything the single shadow-casting
## light in the game (the hand torch) does not need to be blocked by. An omni
## shadow is a cube map: every caster within range is re-rendered six times a
## frame, so geometry that only ever casts onto itself is pure waste there.
func _spawn_chunks(
	holder: Node3D, template: MultiMeshInstance3D, boxes: Array[Dictionary],
	casts_shadow := true
) -> int:
	for child in holder.get_children():
		child.free()

	var span := float(chunk_tiles) * tile_size
	var groups := {}
	for box in boxes:
		var centre: Vector3 = box["centre"]
		var key := Vector2i(int(floor(centre.x / span)), int(floor(centre.z / span)))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(box)

	for key in groups:
		var list: Array = groups[key]
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = template.multimesh.mesh
		mesh.instance_count = list.size()
		for i in list.size():
			mesh.set_instance_transform(i, Transform3D(
				Basis().scaled(list[i]["size"]), list[i]["centre"]))

		var chunk := MultiMeshInstance3D.new()
		chunk.multimesh = mesh
		chunk.material_override = template.material_override
		if not casts_shadow:
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(chunk)

	template.multimesh.instance_count = 0
	return groups.size()


## One occluder mesh covering every wall, so the culler can drop whatever is
## behind them without testing geometry per object.
func _build_occluders(boxes: Array[Dictionary]) -> void:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for box in boxes:
		_append_box(verts, indices, box["centre"], box["size"])
	var shape := ArrayOccluder3D.new()
	shape.set_arrays(verts, indices)
	occluder.occluder = shape


const _BOX_FACES := [
	[0, 1, 2], [0, 2, 3], [5, 4, 7], [5, 7, 6],
	[4, 0, 3], [4, 3, 7], [1, 5, 6], [1, 6, 2],
	[3, 2, 6], [3, 6, 7], [4, 5, 1], [4, 1, 0],
]


func _append_box(
	verts: PackedVector3Array, indices: PackedInt32Array,
	centre: Vector3, size: Vector3
) -> void:
	var h := size * 0.5
	var base := verts.size()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				verts.append(centre + Vector3(h.x * sx, h.y * sy, h.z * sz))
	# The eight corners above are ordered z-fastest; map them onto box faces.
	var order := [0, 1, 3, 2, 4, 5, 7, 6]
	for face in _BOX_FACES:
		for corner in face:
			indices.append(base + order[corner])


## A gate in every doorway of every room, sunk out of sight until whatever
## lives in that room wakes up. Built with their collision disabled so the
## navmesh bake routes through the openings as normal.
func _build_gates() -> void:
	for child in gates_holder.get_children():
		child.free()
	_gates.clear()
	# A rebuilt level is a fresh set of unfought rooms.
	_boss_committed = false
	_mimic_committed = false

	if gate_scene == null:
		return
	if organic and _graph != null:
		_organic_gates()
		return
	for room in room_openings.size():
		var made: Array[Node] = []
		# The boss room is sealed at its courtyard instead; see _boss_court_gates.
		var court_sealed := room == 0 and modules and _module_level != null
		for opening in ([] if court_sealed else room_openings[room]):
			var outward: Vector2i = opening["outward"]
			var gate := gate_scene.instantiate()
			gate.position = tile_to_world(opening["tile"])
			# Face across the opening so the bars span it.
			gate.rotation.y = atan2(float(outward.x), float(outward.y))
			gates_holder.add_child(gate)
			made.append(gate)
		_gates.append(made)
	if modules and _module_level != null:
		if _boss_hall.is_empty():
			_boss_court_gates()
		else:
			_boss_hall_gate()


## The boss hall is sealed at the top of its stair: one portcullis in the arch
## the stair comes up through (`boss_hall.gd` leaves its place), in `_gates[0]`
## so `seal_room(0, ...)` and the committed-until-dead logic drive it. The wall
## that keeps the boss in the hall is built with the hall.
func _boss_hall_gate() -> void:
	if _gates.is_empty():
		return
	var gate: Node3D = load("res://scripts/portcullis.gd").new()
	gate.name = "HallPortcullis"
	var size: Vector2 = _boss_hall["gate_size"]
	gate.width = size.x
	gate.height = size.y
	gate.bar_count = 15
	gate.transform = _boss_hall["gate"]
	gates_holder.add_child(gate)
	_gates[0] = [gate]
	print("[modules] boss hall: %.0f x %.0f m at %.1f m up, one doorway"
		% [float(_module_level.boss_hall["width"]), float(_module_level.boss_hall["depth"]),
			float(_module_level.boss_hall["floor_y"])])


## Collision layer 11: the boss alone collides with it (`_spawn_boss` adds it to
## the boss's mask), so it keeps him in his courtyard without blocking the
## player, other enemies, sight or the navmesh bake (mask 513).
const BOSS_WALL_LAYER := 1 << 10
## The courtyard-facing arches of the boss room's arcade, measured against the
## player's exact wall collision on 2026-09-29: jambs at +/-1.80 m, crown at
## 3.82 m, and the arch's own passage running 2.3-2.8 m in from the arcade
## cell's centre. Re-measure if the modules are rebuilt.
const COURT_ARCH_WIDTH := 3.6
const COURT_ARCH_HEIGHT := 3.82
const COURT_ARCH_DEPTH := 2.55
const _OPPOSITE := {1: 4, 4: 1, 2: 8, 8: 2}
const _SIDE_STEP := {1: Vector2i(0, -1), 2: Vector2i(1, 0), 4: Vector2i(0, 1), 8: Vector2i(-1, 0)}


## The boss room is sealed at the COURTYARD, not at its outer doors.
##
## The boss is walled into the court (he cannot follow into the arcade), so
## gates at the outer doors would have left the whole arcade as a safe place to
## stand. Instead a portcullis drops in every arch between the arcade and the
## court when the fight starts, and the player is shut in with him. These
## replace the room's outer-door gates in `_gates[0]`, so `seal_room(0, ...)`
## and the committed-until-dead logic in `_process` drive them unchanged.
func _boss_court_gates() -> void:
	var boss: Dictionary = _module_level.boss_room()
	if boss.is_empty() or _gates.is_empty():
		return
	var script = load("res://scripts/portcullis.gd")
	var centre: Vector2i = boss["centre"]
	var half: int = boss["half"]
	var made: Array[Node] = []
	for side in _SIDE_STEP:
		var out: Vector2i = _SIDE_STEP[side]
		var along := Vector2i(-out.y, out.x)
		var inward := Vector3(-float(out.x), 0.0, -float(out.y))
		# The ring's corner cells have no arch onto the court, so the run stops
		# one short of them.
		for e in range(-(half - 1), half):
			var pos: Vector2i = centre + out * half + along * e
			var cell = _module_level.cells.get(pos)
			if cell == null or not (cell.open & int(_OPPOSITE[side])):
				continue
			var gate: Node3D = script.new()
			gate.name = "Portcullis"
			gate.width = COURT_ARCH_WIDTH
			gate.height = COURT_ARCH_HEIGHT
			gate.position = _module_level.to_world(pos) + inward * COURT_ARCH_DEPTH
			# Local Z through the arch, so the bars span it along local X.
			gate.rotation.y = atan2(inward.x, inward.z)
			gates_holder.add_child(gate)
			made.append(gate)
	_gates[0] = made

	# The boss's wall, just inside the arches all round the court. His capsule
	# is 1.2 m in radius, so his centre stops 1.2 m short of it.
	var wall := StaticBody3D.new()
	wall.name = "BossCourtWall"
	wall.collision_layer = BOSS_WALL_LAYER
	wall.collision_mask = 0
	gates_holder.add_child(wall)
	var mid: Vector3 = _module_level.room_world(boss)
	var court: float = _module_level.court_half_span(boss)
	const THICK := 0.5
	const TALL := 12.0
	for side in _SIDE_STEP:
		var out: Vector2i = _SIDE_STEP[side]
		var normal := Vector3(float(out.x), 0.0, float(out.y))
		var box := BoxShape3D.new()
		var length := court * 2.0 + THICK * 2.0
		box.size = Vector3(THICK if out.x != 0 else length, TALL, length if out.x != 0 else THICK)
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = mid + normal * (court + THICK * 0.5) + Vector3(0.0, TALL * 0.5, 0.0)
		wall.add_child(shape)
	print("[modules] boss court: %d portcullises, boss wall at %.1f m" % [made.size(), court])


## Seals or clears every gate belonging to one room.
func seal_room(room: int, shut: bool) -> void:
	if room < 0 or room >= _gates.size():
		return
	for gate in _gates[room]:
		if is_instance_valid(gate):
			gate.set_sealed(shut)


func _process(_delta: float) -> void:
	_tick_decrepit()
	# Index 0 is the boss chamber, and treasure room r is at r + 1.
	#
	# Committed, not simply mirrored from `engaged`: sealing straight off the
	# live flag meant a step back through the doorway dropped the gates again,
	# so the fight could be kited out into the corridors. Once it has started
	# the room is shut, and only the champion dying opens it.
	# Dead champions are turned into real nulls here, before the call rather
	# than inside it, for two reasons that both bite:
	#
	#   * A freed object cannot be passed to a typed parameter at all. GDScript
	#     checks the argument's class on the way in, so an is_instance_valid()
	#     guard in the callee never gets the chance to run.
	#   * A freed object also compares equal to null, so `x != null` is false
	#     for one and cannot be used to detect it. is_instance_valid() is the
	#     only test that actually answers the question.
	#
	# Get either wrong and killing a champion throws here every frame from then
	# on, which leaves its room sealed for good with the player inside.
	if not is_instance_valid(_boss):
		_boss = null
	if not is_instance_valid(_mimic):
		_mimic = null

	_boss_committed = _update_seal(_boss, 0, _boss_committed)
	if _puzzles.is_empty():
		_mimic_committed = _update_seal(_mimic, mimic_index + 1, _mimic_committed)
		return
	# Puzzle rooms: a room is shut while its puzzle holds the player in, and the
	# mimic's room again for the whole of its fight once it has sprung.
	if _mimic == null:
		_mimic_committed = false
	elif _mimic.engaged:
		_mimic_committed = true
	for i in _puzzles.size():
		var shut: bool = bool(_puzzles[i].get("sealed")) or (i == mimic_index and _mimic_committed)
		seal_room(i + 1, shut)


## Returns the room's new committed state. `champion` is null once it is dead.
func _update_seal(champion: Node, room: int, committed: bool) -> bool:
	if is_instance_valid(champion):
		if champion.engaged:
			committed = true
		seal_room(room, committed)
		return committed
	if committed:
		# Killed: let everyone back out.
		seal_room(room, false)
	return false


## True for tiles inside any treasure room's footprint.
func is_in_treasure_room(tile: Vector2i) -> bool:
	# Organic "treasure rooms" are the generator's chambers, which are discs of
	# differing radius rather than one fixed square, so each is tested against
	# its own radius.
	if organic and _graph != null:
		var p := tile_to_world(tile)
		var xz := Vector2(p.x, p.z)
		for i in _graph.chamber_at.keys():
			if xz.distance_to(_graph.nodes[i]) <= float(_graph.chamber_at[i]):
				return true
		return false
	var half := treasure_room_tiles / 2
	for centre in treasure_centres:
		if absi(tile.x - centre.x) <= half and absi(tile.y - centre.y) <= half:
			return true
	return false


## Roofs the corridors only. Visual geometry with no collider, so it neither
## blocks the player nor confuses the navmesh bake.
func _build_ceiling() -> void:
	_roofed.clear()
	var runs: Array[Vector3] = []
	for z in tiles:
		var x := 0
		while x < tiles:
			if not _is_roofed(Vector2i(x, z)):
				x += 1
				continue
			var run_start := x
			while x < tiles and _is_roofed(Vector2i(x, z)):
				_roofed.append(Vector2i(x, z))
				x += 1
			var length := x - run_start
			var first := tile_to_world(Vector2i(run_start, z))
			var last := tile_to_world(Vector2i(x - 1, z))
			runs.append(Vector3((first.x + last.x) * 0.5, last.z, float(length)))

	var boxes: Array[Dictionary] = []
	for run in runs:
		boxes.append({
			"centre": Vector3(run.x, wall_height + ceiling_thickness * 0.5, run.y),
			"size": Vector3(run.z * tile_size, ceiling_thickness, tile_size),
		})
	# Nothing lives above the ceiling but sky, so it never needs to block light.
	_spawn_chunks(ceiling_chunks, ceiling_visuals, boxes, false)


func _is_roofed(tile: Vector2i) -> bool:
	return is_open(tile) and not is_in_boss_room(tile) and not is_in_treasure_room(tile)


## Frames the ways into the open rooms: two posts and a lintel, tall enough to
## read as a gate rather than a doorway. Visual only, so the opening stays as
## wide as it was for movement and pathing.
func _build_arches() -> void:
	var frames: Array[Dictionary] = []
	var rooms: Array[Dictionary] = [{
		"min": _room_min, "max": _room_max,
	}]
	var half := treasure_room_tiles / 2
	for centre in treasure_centres:
		rooms.append({
			"min": centre - Vector2i(half, half),
			"max": centre + Vector2i(half, half),
		})

	var bars: Array[Dictionary] = []
	# Index 0 is the boss chamber; 1..n line up with treasure_centres.
	room_openings.clear()
	for room in rooms:
		var lo: Vector2i = room["min"]
		var hi: Vector2i = room["max"]
		var mine: Array[Dictionary] = []
		for z in range(lo.y, hi.y + 1):
			_collect_arch(frames, bars, mine, Vector2i(lo.x - 1, z), Vector2i(-1, 0))
			_collect_arch(frames, bars, mine, Vector2i(hi.x + 1, z), Vector2i(1, 0))
		for x in range(lo.x, hi.x + 1):
			_collect_arch(frames, bars, mine, Vector2i(x, lo.y - 1), Vector2i(0, -1))
			_collect_arch(frames, bars, mine, Vector2i(x, hi.y + 1), Vector2i(0, 1))
		room_openings.append(mine)

	_spawn_chunks(arch_chunks, arch_visuals, frames)
	# Solid, not just painted on. The posts are stone a foot thick standing in
	# a doorway -- walking through them made every arch read as a hologram.
	# Built here, before the navmesh bake, so enemies route around them too.
	for frame in frames:
		var box := BoxShape3D.new()
		box.size = frame["size"]
		var collider := CollisionShape3D.new()
		collider.shape = box
		collider.position = frame["centre"]
		walls_body.add_child(collider)
	# Thin grilles: their shadows are acne at this resolution, and there are
	# hundreds of the bars.
	_spawn_chunks(bar_chunks, bar_visuals, bars, false)


## An opening tile next to a room becomes one arch: a post either side of the
## gap plus a lintel across the top.
func _collect_arch(
	frames: Array[Dictionary], bars: Array[Dictionary], openings: Array[Dictionary],
	tile: Vector2i, outward: Vector2i
) -> void:
	if not is_open(tile):
		return
	var centre := tile_to_world(tile)
	openings.append({"tile": tile, "outward": outward})
	# The posts sit on the axis across the opening.
	var across := Vector3(float(outward.y), 0.0, float(outward.x))
	var depth := Vector3(absf(float(outward.x)), 0.0, absf(float(outward.y)))
	var post_size := (
		across.abs() * arch_post_width
		+ Vector3(0, arch_height, 0)
		+ depth * (tile_size * 0.45)
	)
	for side in [-1.0, 1.0]:
		frames.append({
			"centre": centre + across * side * (tile_size * 0.5 - arch_post_width * 0.5)
				+ Vector3(0, arch_height * 0.5, 0),
			"size": post_size,
		})
	frames.append({
		"centre": centre + Vector3(0, arch_height + arch_lintel_height * 0.5, 0),
		"size": across.abs() * tile_size + Vector3(0, arch_lintel_height, 0)
			+ depth * (tile_size * 0.45),
	})

	# Iron bars filling the head of the arch, above the lintel.
	if arch_bar_count <= 0:
		return
	var span := tile_size - arch_post_width * 2.0
	var bar_base := arch_height + arch_lintel_height
	for i in arch_bar_count:
		# Evenly spaced across the opening, inset from both posts.
		var t := (float(i) + 0.5) / float(arch_bar_count) - 0.5
		bars.append({
			"centre": centre + across * (t * span)
				+ Vector3(0, bar_base + arch_bar_height * 0.5, 0),
			"size": across.abs() * arch_bar_width
				+ Vector3(0, arch_bar_height, 0)
				+ depth * arch_bar_width,
		})
	# A horizontal rail capping the grille.
	bars.append({
		"centre": centre + Vector3(0, bar_base + arch_bar_height, 0),
		"size": across.abs() * span + Vector3(0, arch_bar_width, 0) + depth * arch_bar_width,
	})


## Mounts torches on wall faces that front a corridor. They are level dressing,
## built once with the geometry, so a death reset leaves them alone.
func _build_torches() -> void:
	if torch_scene == null or torch_spacing <= 0:
		return
	var holder := Node3D.new()
	holder.name = "Torches"
	add_child(holder)

	var faces: Array[Array] = []
	for z in tiles:
		for x in tiles:
			var tile := Vector2i(x, z)
			if is_open(tile):
				continue
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if is_open(tile + step):
					faces.append([tile, step])

	for i in faces.size():
		if i % torch_spacing != 0:
			continue
		var tile: Vector2i = faces[i][0]
		var step: Vector2i = faces[i][1]
		var outward := Vector3(float(step.x), 0.0, float(step.y))

		var torch := torch_scene.instantiate()
		# Sit just proud of the wall face, at head height.
		torch.position = (
			tile_to_world(tile)
			+ outward * (tile_size * 0.5 - 0.06)
			+ Vector3(0, torch_height, 0)
		)
		# The scene points its flame down -Z, so face it into the corridor.
		torch.rotation.y = atan2(-outward.x, -outward.z)
		holder.add_child(torch)

	# Chandeliers under the corridor ceiling.
	if chandelier_scene != null and chandelier_spacing > 0:
		for i in _roofed.size():
			if i % chandelier_spacing != 0:
				continue
			var light := chandelier_scene.instantiate()
			light.position = tile_to_world(_roofed[i]) + Vector3(
				0, wall_height - chandelier_drop, 0)
			holder.add_child(light)

	# One on each face of every pillar tall enough to carry them.
	var sides := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	for pillar in _pillars:
		var size: Vector3 = pillar["size"]
		if size.y < torch_min_pillar_height:
			continue
		var mount: float = minf(torch_height, size.y - 1.1)
		for outward in sides:
			var torch := torch_scene.instantiate()
			torch.position = (
				pillar["base"]
				+ outward * (size.x * 0.5 - 0.06)
				+ Vector3(0, mount, 0)
			)
			torch.rotation.y = atan2(-outward.x, -outward.z)
			holder.add_child(torch)


## Skulls and loose bones strewn over the floor. Chunked MultiMeshes with a
## draw distance, so a few hundred of them cost a handful of calls rather than
## a few hundred nodes.
func _build_debris() -> void:
	for child in debris_chunks.get_children():
		child.free()
	if skull_count <= 0 and bone_count <= 0:
		return

	var open: Array[Vector2i] = []
	for z in tiles:
		for x in tiles:
			var tile := Vector2i(x, z)
			# Not under the player's feet on spawn.
			if is_open(tile) and tile.distance_to(_start_tile) > 2.0:
				open.append(tile)
	if open.is_empty():
		return

	var skulls: Array[Transform3D] = []
	var bones: Array[Transform3D] = []
	for i in skull_count + bone_count:
		var tile: Vector2i = open[_rng.randi() % open.size()]
		var spot := tile_to_world(tile) + Vector3(
			_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
		spot.y = _ground_height(spot.x, spot.z, _relief)
		if i < skull_count:
			# Tipped onto a cheek as often as not, and part sunk into the mud.
			skulls.append(Transform3D(
				Basis.from_euler(Vector3(
					_rng.randf_range(-0.5, 0.5),
					_rng.randf() * TAU,
					_rng.randf_range(-0.6, 0.6),
				)),
				spot + Vector3(0, _rng.randf_range(0.03, 0.07), 0),
			))
		else:
			# Lying flat, so only the yaw varies much.
			bones.append(Transform3D(
				Basis.from_euler(Vector3(
					_rng.randf_range(-0.12, 0.12),
					_rng.randf() * TAU,
					_rng.randf_range(-0.15, 0.15),
				)).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.35)),
				spot + Vector3(0, _rng.randf_range(0.01, 0.035), 0),
			))

	_spawn_prop_chunks(debris_chunks, _skull_mesh(), null, skulls)
	_spawn_prop_chunks(debris_chunks, _bone_mesh(), null, bones)


## Short lengths of iron bar left propped against the corridor walls.
func _build_leaning_bars() -> void:
	for child in lean_chunks.get_children():
		child.free()
	if lean_spacing <= 0:
		return

	var faces: Array[Array] = []
	for z in tiles:
		for x in tiles:
			var tile := Vector2i(x, z)
			if is_open(tile):
				continue
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if is_open(tile + step):
					faces.append([tile, step])

	var bar := BoxMesh.new()
	bar.size = Vector3.ONE
	var placements: Array[Transform3D] = []
	for i in faces.size():
		if i % lean_spacing != 0:
			continue
		var tile: Vector2i = faces[i][0]
		var step: Vector2i = faces[i][1]
		var outward := Vector3(float(step.x), 0.0, float(step.y))
		# The axis running along the wall face.
		var across := Vector3(outward.z, 0.0, -outward.x)
		var wall_face := tile_to_world(tile) + outward * (tile_size * 0.5)

		for b in _rng.randi_range(2, 4):
			var length := _rng.randf_range(1.1, 2.0)
			var tilt := _rng.randf_range(0.18, 0.42)
			var slide := _rng.randf_range(-1.3, 1.3)
			# Rotating +Y toward -outward tips the top of the bar into the wall
			# and kicks its foot out into the corridor.
			var axis := Vector3.UP.cross(-outward).normalized()
			var lean := Basis(axis, tilt)
			# A little yaw as well, so they are not all perfectly square on.
			lean = Basis(Vector3.UP, _rng.randf_range(-0.25, 0.25)) * lean

			var foot := wall_face + across * slide + outward * (sin(tilt) * length)
			var centre := (
				wall_face + across * slide
				+ outward * (sin(tilt) * length * 0.5 + 0.05)
				+ Vector3(0, cos(tilt) * length * 0.5, 0)
			)
			centre.y += _ground_height(foot.x, foot.z, _relief)
			var thickness := _rng.randf_range(0.07, 0.12)
			placements.append(Transform3D(
				lean.scaled(Vector3(thickness, length, thickness)), centre))

	_spawn_prop_chunks(lean_chunks, bar, bar_visuals.material_override, placements)


## The Warden has finished raising his weapon: let a batch out.
func _on_boss_summoned(_index: int) -> void:
	release_cells(cells_per_summon)


## One skeleton to a cell, standing where it was left.
##
## They spawn shut in and stay that way: no wandering, no sight, and a leash
## that keeps them where they are even if the fight comes close. Nothing gets
## out until the Warden opens the door.
func _stock_jail_cells() -> void:
	cell_occupants.clear()
	if enemy_scene == null:
		return
	for index in cell_spots.size():
		var skeleton := PROSTHETIC.make(enemy_scene, _melee_hand()) as Node3D
		skeleton.position = cell_spots[index]
		skeleton.rotation.y = cell_facing[index]
		add_child(skeleton)
		# Blind and rooted until released. Without this they would notice the
		# fight through their own bars and spend it shoving at the door.
		skeleton.set("wanders", false)
		skeleton.set("aggro_range", 0.5)
		skeleton.set("dormant_range", 0.0)
		cell_occupants.append(skeleton)
		_spawned.append(skeleton)


## Cells sunk into the two chamber walls that have no doorway.
##
## Built before the navmesh bake, with the doors' collision still off, so the
## interiors end up on the mesh and whatever is locked in them can walk out
## once the bars lift. The occupants themselves arrive later, with the rest of
## the population.
func _build_jail_cells() -> void:
	for child in cell_chunks.get_children():
		child.free()
	for child in cells_holder.get_children():
		child.free()
	cell_doors.clear()
	cell_spots.clear()
	cell_facing.clear()
	if cells_per_wall <= 0 or cell_door_scene == null:
		return

	var boxes: Array[Dictionary] = []
	for outward in _blank_chamber_walls():
		_line_one_wall(outward, boxes)

	_spawn_chunks(cell_chunks, wall_visuals, boxes)
	for box in boxes:
		var shape := BoxShape3D.new()
		shape.size = box["size"]
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = box["centre"]
		walls_body.add_child(collider)


## The chamber's sides that no doorway passes through. Worked out from the
## entrances rather than assumed, so changing boss_room_entrances cannot
## quietly put a row of cells across a door.
func _blank_chamber_walls() -> Array[Vector3]:
	var centre := boss_tile()
	var used := {}
	for entrance in entrances:
		var offset: Vector2i = entrance - centre
		# Whichever axis it lies furthest along is the wall it pierces.
		if absi(offset.x) >= absi(offset.y):
			used[Vector2i(signi(offset.x), 0)] = true
		else:
			used[Vector2i(0, signi(offset.y))] = true

	var free: Array[Vector3] = []
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not used.has(step):
			free.append(Vector3(float(step.x), 0.0, float(step.y)))
	return free


## One row of cells along the inside face of a wall. `outward` points from the
## room's centre toward that wall.
func _line_one_wall(outward: Vector3, boxes: Array[Dictionary]) -> void:
	var room := tile_to_world(boss_tile())
	var half := float(boss_room_tiles) * tile_size * 0.5
	# The axis running along the wall face.
	var along := Vector3(outward.z, 0.0, -outward.x)
	var face := room + outward * half
	var span := half * 2.0
	var width := span / float(cells_per_wall)

	for i in cells_per_wall:
		var offset: float = -half + width * (float(i) + 0.5)
		var mouth := face + along * offset - outward * cell_depth
		var back := face + along * offset

		# Divider between this cell and the next, on one side only, so
		# neighbours share a wall rather than doubling up.
		if i < cells_per_wall - 1:
			boxes.append({
				"centre": face + along * (offset + width * 0.5)
					- outward * (cell_depth * 0.5)
					+ Vector3(0, cell_height * 0.5, 0),
				"size": along.abs() * cell_divider
					+ outward.abs() * cell_depth
					+ Vector3(0, cell_height, 0),
			})
		# Lintel over the mouth, which is also what the bars vanish into.
		boxes.append({
			"centre": mouth + Vector3(0, cell_height + 0.25, 0),
			"size": along.abs() * width + outward.abs() * cell_depth
				+ Vector3(0, 0.5, 0),
		})

		var door := cell_door_scene.instantiate() as Node3D
		door.position = mouth
		# Bars span the opening: turn them to lie along the wall.
		door.rotation.y = atan2(outward.x, outward.z)
		cells_holder.add_child(door)
		cell_doors.append(door)
		# Where its occupant stands: back of the cell, off the floor.
		cell_spots.append(back - outward * (cell_depth * 0.55) + Vector3(0, 0.3, 0))
		# Looking out through its own bars. Same figure as the door's, since
		# the enemy's forward is -Z and the cell opens along -outward.
		cell_facing.append(atan2(outward.x, outward.z))


## Makes every closed door solid. Called once the navmesh has been baked, for
## the same reason the room gates are.
func _seal_cells() -> void:
	for door in cell_doors:
		if is_instance_valid(door) and door.has_method("make_solid"):
			door.make_solid()


## Throws open the next batch of cells and turns loose whatever is inside.
func release_cells(count: int) -> int:
	# Picked at random from whatever is still shut, rather than working along
	# the row. Opening them in order makes the second and third calls
	# predictable -- you learn to stand at the far end. Scattered, the threat
	# can come from anywhere along either wall every time.
	var shut: Array[int] = []
	for index in cell_doors.size():
		var door: Node = cell_doors[index]
		if is_instance_valid(door) and not door.is_open:
			shut.append(index)

	var opened := 0
	while opened < count and not shut.is_empty():
		var pick: int = _rng.randi_range(0, shut.size() - 1)
		var index: int = shut[pick]
		shut.remove_at(pick)

		var door: Node = cell_doors[index]
		# Staggered, so a batch reads as ten doors rather than one mechanism
		# with ten parts.
		door.open_delay = float(opened) * 0.06
		door.open()
		opened += 1
		if index < cell_occupants.size():
			var skeleton: Node = cell_occupants[index]
			if is_instance_valid(skeleton):
				_turn_loose(skeleton)
	return opened


## Wakes a caged skeleton properly: out of its cell, off its leash, and with no
## patch of floor it is supposed to stay on.
func _turn_loose(skeleton: Node) -> void:
	skeleton.set("wanders", false)
	skeleton.set("wander_spots", [] as Array[Vector3])
	skeleton.set("aggro_range", 70.0)
	# It has been waiting in the dark for this; it does not need to be shown
	# where you are.
	skeleton.set("vision_cone_degrees", 0.0)
	skeleton.set("sight_needs_line_of_sight", false)
	skeleton.set("_dormant", false)
	skeleton.set("_seen_until", _now_seconds() + 9999.0)


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


## Chunked MultiMeshes for props placed at arbitrary angles, which the
## box-shaped _spawn_chunks cannot express. Each chunk carries a draw distance,
## so these never reach the renderer at all beyond prop_draw_distance.
func _spawn_prop_chunks(
	holder: Node3D, mesh: Mesh, material: Material, placements: Array[Transform3D]
) -> int:
	if placements.is_empty():
		return 0

	var span := float(chunk_tiles) * tile_size
	var groups := {}
	for placement in placements:
		var key := Vector2i(
			int(floor(placement.origin.x / span)), int(floor(placement.origin.z / span)))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(placement)

	for key in groups:
		var list: Array = groups[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = list.size()
		for i in list.size():
			multi.set_instance_transform(i, list[i])

		var chunk := MultiMeshInstance3D.new()
		chunk.multimesh = multi
		if material != null:
			chunk.material_override = material
		chunk.visibility_range_end = prop_draw_distance
		chunk.visibility_range_end_margin = 5.0
		chunk.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# Ankle-height clutter contributes nothing to a shadow map.
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(chunk)
	return groups.size()


## A cranium, a muzzle and two sunken sockets, built as one surface with the
## colours baked into the vertices so the whole thing is a single draw call per
## chunk rather than one per material.
func _skull_mesh() -> ArrayMesh:
	# Old and dirt-stained rather than bleached. Kept close to the tone of the
	# pebbles in the ground texture so they settle into the mud instead of
	# glowing out of it, and torchlight lifts them further than this anyway.
	var bone := Color(0.325490, 0.301961, 0.258824)
	var socket := Color(0.047059, 0.043137, 0.039216)

	# Barely tessellated on purpose. These are 20 cm across, ankle height, in a
	# maze lit by guttering torches -- there are hundreds of them and nobody
	# will ever see a silhouette edge.
	var cranium := SphereMesh.new()
	cranium.radius = 0.105
	cranium.height = 0.21
	cranium.radial_segments = 6
	cranium.rings = 3

	var muzzle := BoxMesh.new()
	muzzle.size = Vector3(0.115, 0.075, 0.10)

	var eye := BoxMesh.new()
	eye.size = Vector3(0.042, 0.042, 0.042)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_tinted(st, cranium,
		Transform3D(Basis().scaled(Vector3(1.0, 0.94, 1.12)), Vector3.ZERO), bone)
	_append_tinted(st, muzzle,
		Transform3D(Basis(), Vector3(0.0, -0.062, 0.088)), bone)
	# Straddling the surface, so each socket reads as a hole rather than a decal.
	for side in [-1.0, 1.0]:
		_append_tinted(st, eye,
			Transform3D(Basis(), Vector3(side * 0.045, 0.005, 0.088)), socket)
	st.set_material(_vertex_colour_material())
	return st.commit()


## A shaft with a knuckle at each end.
func _bone_mesh() -> ArrayMesh:
	# A shade below the skulls: loose bones have been lying in it longer.
	var bone := Color(0.305882, 0.282353, 0.239216)

	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.036, 0.036, 0.23)

	var knuckle := SphereMesh.new()
	knuckle.radius = 0.038
	knuckle.height = 0.076
	knuckle.radial_segments = 5
	knuckle.rings = 2

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_tinted(st, shaft, Transform3D(), bone)
	for end in [-0.118, 0.118]:
		_append_tinted(st, knuckle,
			Transform3D(Basis().scaled(Vector3(1.0, 0.85, 1.0)), Vector3(0, 0, end)), bone)
	st.set_material(_vertex_colour_material())
	return st.commit()


## Bone and socket colours are baked per vertex, so the material only has to
## agree to read them.
func _vertex_colour_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
	return material


## Copies a primitive into the surface under a transform, tagging every vertex
## with a colour. SurfaceTool.append_from would carry the source arrays across
## untouched, which leaves no way to give two primitives different colours
## within one surface.
func _append_tinted(
	st: SurfaceTool, mesh: Mesh, xform: Transform3D, colour: Color
) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Normals transform by the inverse transpose, which matters because the
	# cranium is squashed.
	var normal_basis := xform.basis.inverse().transposed()
	for i in indices:
		st.set_color(colour)
		st.set_normal((normal_basis * norms[i]).normalized())
		st.add_vertex(xform * verts[i])


## Every player to the start (or the attuned anchor, or the sandbox's plane);
## co-op, player 2 a step beside player 1 (`_partner_spot`).
func _place_player() -> void:
	for p in Coop.all():
		_place_one(p)
	if Coop.active:
		_settle_partner()


## Co-op: player 2 placed again beside player 1 once the physics has the
## level -- built this very frame, its floors are not in the space yet, and
## `_partner_spot` found none and put them on player 1's spot.
func _settle_partner() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var a := Coop.player(0) as Node3D
	var b := Coop.player(1) as Node3D
	if a == null or b == null or b.get("_dead") == true or b.get("in_cutscene") == true:
		return
	if Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length() > 0.3:
		return
	var at := _partner_spot(a.global_position, a.rotation.y)
	b.global_position = at
	b.call("set_spawn_point", at)


func _place_one(player: Node3D) -> void:
	if player == null:
		return
	var second := Coop.index_of(player) == 1
	# The sandbox starts -- and, after a death, rises -- on its test plane.
	if _sandbox_world != null:
		var at: Vector3 = _sandbox_world.call("spawn_point")
		if second:
			at = _partner_spot(at, 0.0)
		player.global_position = at
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.set("_look_pitch", 0.0)
		player.set_spawn_point(at)
		return
	var spawn := tile_to_world(_start_tile) + Vector3(0, 0.3, 0)
	var anchor := active_anchor()
	if anchor != null:
		# Risen at the attuned anchor, facing out of its dead end.
		spawn = anchor.spawn_point()
		if second:
			spawn = _partner_spot(spawn, anchor.spawn_yaw())
		player.global_position = spawn
		player.velocity = Vector3.ZERO
		player.rotation.y = anchor.spawn_yaw()
		player.set("_look_pitch", 0.0)
		player.set_spawn_point(spawn)
		return
	# Shut in behind the spawn's door: the exact spot, not snapped to the 1.2 m
	# tile grid, which could put the door out of reach of the first E.
	if _module_level != null and not _module_level.spawn_door.is_empty():
		spawn = _module_level.spawn + Vector3(0, 0.1, 0)
	var yaw: float = _module_level.spawn_yaw if _module_level != null and not _module_level.spawn_door.is_empty() \
		else player.rotation.y
	if second:
		spawn = _partner_spot(spawn, yaw)
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	# Facing the door that shuts the spawn's dead end -- on every respawn too.
	if _module_level != null and not _module_level.spawn_door.is_empty():
		player.rotation.y = _module_level.spawn_yaw
		player.set("_look_pitch", 0.0)
	# Otherwise respawning would send them back to wherever the scene put them.
	if player.has_method("set_spawn_point"):
		player.set_spawn_point(spawn)


## Co-op: where player 2 stands beside player 1's `spot` (facing `yaw`) -- a
## step to the right, else the left, behind, ahead, whichever has floor and
## no stone in the way; the spot itself if none does.
func _partner_spot(spot: Vector3, yaw: float) -> Vector3:
	var basis := Basis(Vector3.UP, yaw)
	var space := get_world_3d().direct_space_state
	var waist := spot + Vector3(0.0, 0.9, 0.0)
	var tries: Array[Vector3] = []
	for step: float in [1.0, 0.7]:
		for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD,
				(Vector3.RIGHT + Vector3.BACK).normalized(), (Vector3.LEFT + Vector3.BACK).normalized()]:
			tries.append(dir * step)
	for t in tries:
		var off := basis * t
		var q := PhysicsRayQueryParameters3D.create(waist, waist + off + off.normalized() * 0.45, 1 | 2 | 256)
		var skip: Array[RID] = []
		for p in Coop.all():
			skip.append((p as CollisionObject3D).get_rid())
		q.exclude = skip
		if not space.intersect_ray(q).is_empty():
			continue
		var down := PhysicsRayQueryParameters3D.create(waist + off, waist + off - Vector3(0.0, 2.5, 0.0), 1 | 2 | 256)
		var floor_hit := space.intersect_ray(down)
		if floor_hit.is_empty():
			continue
		return (floor_hit["position"] as Vector3) + Vector3(0.0, 0.1, 0.0)
	return spot


func _connect_player() -> void:
	# Co-op: each player rises on their own (`_on_player_respawned`).
	for p in Coop.all():
		if p.has_signal("respawned"):
			p.respawned.connect(_on_player_respawned.bind(p))


func _on_player_respawned(player: Node3D = null) -> void:
	# Co-op: a fallen player rises at the anchor and joins back in; the world
	# resets (the map, the dead coming back) only when nobody was left standing.
	if Coop.active and player != null:
		var standing := false
		for p in Coop.all():
			if p != player and p.get("_dead") != true:
				standing = true
		_place_one(player)
		if standing:
			return
	else:
		_place_player()
	var map = _explore_map_node()
	if map != null and map.has_method("restore"):
		map.restore(_map_snapshot)
	_populate()


## --- The sandbox (sandbox.gd, 2026-10-17) -------------------------------------------
##
## Built only in a sandbox session: the level as normal but EMPTY (no
## population unless the sandbox menu turns `sandbox_population` on), the whole
## map charted, and a flat test plane far off the level (sandbox_world.gd) where
## the player starts and rises after a death. Its menu (sandbox_menu.gd, the `
## key) is a CanvasLayer added last under the root -- so it reads its keys
## before anything else, as the workbench screen does -- and freed with the
## level.

var _sandbox_world: Node3D = null
var _sandbox_menu: CanvasLayer = null
## The level's own enemies, in the sandbox (its menu's switch).
var sandbox_population := false


func _build_sandbox() -> void:
	_sandbox_world = load("res://scripts/sandbox_world.gd").new()
	add_child(_sandbox_world)
	_sandbox_world.call("build", self)


func _open_sandbox_menu() -> void:
	if _sandbox_world == null or _sandbox_menu != null:
		return
	_sandbox_menu = CanvasLayer.new()
	_sandbox_menu.set_script(load("res://scripts/sandbox_menu.gd"))
	_sandbox_menu.name = "SandboxMenu"
	_sandbox_menu.call("setup", _sandbox_world, self)
	get_tree().root.add_child.call_deferred(_sandbox_menu)
	tree_exiting.connect(func() -> void:
		if is_instance_valid(_sandbox_menu):
			_sandbox_menu.queue_free())


## The sandbox menu's "Level's own enemies": the normal population, or none.
func set_sandbox_population(on: bool) -> void:
	sandbox_population = on
	if not on:
		# No decrepit queued to come back.
		_decrepit_due.clear()
	_populate()


## Dying resets the run: the same layout, but every enemy and the boss restored
## and the player back at their attuned anchor (or the entrance). The map
## forgets everything charted since that anchor was attuned.
func _populate() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	_boss = null
	_mimic = null
	# The fights are over: a death raises the bars of whatever room it happened
	# in. Without clearing the commitment too, the next _process re-sealed the
	# room at once round the freshly spawned (unengaged) champion, and the
	# player could never get back in.
	_boss_committed = false
	_mimic_committed = false
	for room in _gates.size():
		seal_room(room, false)
	if _rats_node != null and is_instance_valid(_rats_node):
		_rats_node.free()
		_rats_node = null
	# The sandbox's level is empty unless its menu asks for the population.
	if Sandbox.active and not sandbox_population:
		return
	_note_spawn_eye()
	# Reseed so a reset reproduces the same population rather than drifting.
	_rng.seed = _active_seed
	_hand_rng.seed = hash(_active_seed + 4111)
	_spawn_boss()
	_stock_jail_cells()
	_spawn_enemies()
	_spawn_convoys()
	_spawn_stalker()
	_spawn_decrepits()
	_spawn_sewer_lizards()
	_spawn_rats()
	_spawn_chests()
	if modules and _module_level != null:
		_report_room_intruders()
	# After the count, which is of the corridors: each chest room puts back its
	# own -- a prison's enforcers and loose prisoners, the mimic -- which this
	# repopulate (or the first build) has just cleared.
	for p in _puzzles:
		p.call("on_world_reset")
	if _surgery != null:
		_surgery.call("on_world_reset")


## Counts enemies that spawned inside a room, against how many should have.
##
## Chest rooms are guarded ON PURPOSE -- `_spawn_room_packs` puts
## `chest_room_pack` enemies in each, so a chest is defended rather than just
## lying there -- so the right number is that many per chest room, and none in
## the boss room. Before the corridor spawner was told about the rooms it was
## 47 of 92 instead of 20: the open courtyards had swamped the candidate list.
func _report_room_intruders() -> void:
	var total := 0
	var inside := 0
	var chest_path := chest_scene.resource_path if chest_scene != null else ""
	var mimic_path := mimic_scene.resource_path if mimic_scene != null else ""
	for node in _spawned:
		if not is_instance_valid(node) or not (node is Node3D) or node == _boss:
			continue
		var path: String = node.scene_file_path
		if path == chest_path or path == mimic_path:
			continue
		# A convoy's controller sits at the origin; its crew are counted.
		if node.has_method("is_broken"):
			continue
		# The sewer's, under the map: a room above them is not theirs.
		if (node as Node3D).global_position.y < -4.0:
			continue
		total += 1
		var tile := world_to_tile((node as Node3D).global_position)
		if is_in_boss_room(tile) or is_in_treasure_room(tile):
			inside += 1
	var guards := 0 if not _puzzles.is_empty() else chest_room_pack * treasure_centres.size()
	print("[modules] %d enemies spawned, %d inside rooms (%d expected: the chest guards)"
		% [total, inside, guards])
	if inside > guards:
		push_warning("%d more enemies spawned inside rooms than the chest guards account for"
			% (inside - guards))


func _spawn_boss() -> void:
	# Killed once, dead for good: a death or a reload does not bring him back.
	if boss_scene == null or boss_defeated:
		return
	var boss := boss_scene.instantiate()
	boss.position = tile_to_world(boss_tile()) + Vector3(0, 0.4, 0)
	_boss = boss
	if boss.has_signal("died"):
		boss.died.connect(_on_boss_died)
	if not _boss_hall.is_empty():
		# Waiting at his throne, facing the doorway, guarding the whole hall --
		# and only the hall: the zone has a height, so walking the corridors
		# under it does not wake him.
		boss.position = _boss_hall["boss_spot"]
		boss.rotation.y = _boss_hall["boss_yaw"]
		boss.aggro_box_extents = _boss_hall["zone_extents"]
		boss.aggro_box_origin = _boss_hall["zone_centre"]
		boss.leash_radius = 0.0
		boss.collision_mask |= BOSS_WALL_LAYER
		add_child(boss)
		if boss.has_signal("summoned"):
			boss.summoned.connect(_on_boss_summoned)
		_spawned.append(boss)
		return
	# The chamber is a square, so the guarded zone is a box matching its floor
	# rather than a radius. Pulled in slightly so a player standing in a doorway
	# is outside it and the boss does not lean into the corridor.
	var half: float = float(boss_room_tiles) * tile_size * 0.5 - tile_size * 0.25
	boss.aggro_box_extents = Vector3(half, 0.0, half)
	boss.leash_radius = 0.0
	# Walled into his courtyard; see `_boss_court_gates`.
	if modules:
		boss.collision_mask |= BOSS_WALL_LAYER
	add_child(boss)
	if boss.has_signal("summoned"):
		boss.summoned.connect(_on_boss_summoned)
	_spawned.append(boss)


## One chest per treasure room, restocked whenever the world resets.
func _spawn_chests() -> void:
	# The puzzle rooms raise their own chests (and the mimic), once solved.
	if chest_scene == null or not _puzzles.is_empty():
		return
	# One of them is a mimic. Rolled from the same seeded stream, so a reset
	# restores the same one rather than shuffling the surprise.
	mimic_index = -1
	if spawn_mimic and mimic_scene != null and not chest_perches.is_empty():
		mimic_index = _nearest_room_to_start()

	for i in chest_perches.size():
		var scene: PackedScene = mimic_scene if i == mimic_index else chest_scene
		var chest := scene.instantiate()
		chest.position = chest_perches[i]
		add_child(chest)
		if i == mimic_index:
			_mimic = chest
		_spawned.append(chest)


## Which treasure room the player reaches first, so the mimic is always the
## first chest they meet. (Only without puzzle rooms: with them the mimic's room
## is the one reached LAST, `_far_room_from_start`.)
##
## Measured by walking the maze rather than by straight-line distance: a room
## twenty metres away through a wall is further off than one forty metres away
## down a corridor, and the point is which one you actually arrive at.
func _nearest_room_to_start() -> int:
	if treasure_centres.is_empty():
		return -1

	var steps := {}
	var queue: Array[Vector2i] = [_start_tile]
	steps[_start_tile] = 0
	var head := 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		for step in DIRECTIONS.values():
			var next: Vector2i = tile + step
			if steps.has(next) or not is_open(next):
				continue
			steps[next] = int(steps[tile]) + 1
			queue.append(next)

	var best := -1
	var shortest := 1 << 30
	for index in treasure_centres.size():
		var centre: Vector2i = treasure_centres[index]
		if not steps.has(centre):
			continue
		var walk: int = steps[centre]
		if walk < shortest:
			shortest = walk
			best = index
	# Every room walled off from the start would be a broken maze, but fall
	# back rather than handing out -1 and quietly spawning no mimic at all.
	return best if best >= 0 else 0


func _spawn_enemies() -> void:
	if enemy_scene == null:
		return
	var spots := _spawn_candidates()
	_patrol_points.clear()
	for tile in spots:
		_patrol_points.append(tile_to_world(tile))
	var taken: Array[Vector2i] = []
	var placed := 0
	var attempts := 0
	var want := enemy_count
	if modules and _module_level != null and enemies_per_corridor_cell > 0.0:
		want = roundi(float(_corridor_cell_count()) * enemies_per_corridor_cell)
	var limit := want * 60

	while placed < want and not spots.is_empty() and attempts < limit:
		attempts += 1
		var pick: int = _rng.randi_range(0, spots.size() - 1)
		var tile: Vector2i = spots[pick]

		# Keep encounters apart; if the map runs out of room, relax rather than
		# spawning nothing.
		var crowded := false
		if attempts < limit / 2:
			for other in taken:
				if Vector2(tile - other).length() < float(min_enemy_spacing):
					crowded = true
					break
		if crowded:
			continue
		spots.remove_at(pick)
		taken.append(tile)

		# One roll decides the whole group, so a pack is all of a kind: a knot
		# of reds or a lone crier, never a mixed committee.
		var flying: bool = flyer_scene != null and _rng.randf() < flyer_share
		var pack := _rng.randi_range(
			flyer_pack_min if flying else red_pack_min,
			flyer_pack_max if flying else red_pack_max)
		pack = mini(pack, want - placed)
		placed += _spawn_pack(tile, flying, pack)

	_spawn_room_packs(taken)


## A group dropped around one tile. Returns how many actually went down.
func _spawn_pack(tile: Vector2i, flying: bool, count: int) -> int:
	var scene: PackedScene = flyer_scene if flying else enemy_scene
	if scene == null or count <= 0:
		return 0
	# A skeleton pack of two or more mostly brings an archer at its back
	# (archer.gd): never alone, so it has fellows to stand behind. Four or more
	# may bring a second.
	var archers: Array[int] = []
	if not flying and count >= 2 and _rng.randf() < archer_share:
		archers.append(count - 1)
		if count >= 4 and _rng.randf() < second_archer_share:
			archers.append(count - 2)
	# A shield at the head of a pack with someone to guard.
	var shield := not flying and (count >= 3 or (count >= 2 and not archers.is_empty())) \
		and _hand_rng.randf() < shield_share
	var leader: Node3D = null
	var members: Array[Node3D] = []
	for i in count:
		var enemy: Node3D = scene.instantiate()
		members.append(enemy)
		if i == 0:
			leader = enemy
		if i in archers:
			# Before it enters the tree: its numbers are set in its _init.
			enemy.set_script(ARCHER_SCRIPT)
		elif not flying:
			# Every other skeleton wears a hand of its own (prosthetic.gd).
			enemy.set_script(PROSTHETIC)
			enemy.set("hand", &"shield" if shield and i == 0 else _melee_hand())
		# Spread inside the tile rather than stacking on its centre: bodies
		# that spawn exactly overlapping shove each other apart hard enough to
		# launch the pile.
		var jitter := Vector3(
			_rng.randf_range(-1.3, 1.3), 0.0, _rng.randf_range(-1.3, 1.3))
		# Decided before it enters the tree, because a sentry needs placing
		# differently from a wanderer and _ready captures where it stands.
		# Skeleton packs in the corridors are always on patrol, so they all roam.
		var roams: bool = enemy.get("wanders") != null \
			and ((not flying and patrols) or _rng.randf() < wander_share)
		if not roams:
			jitter = _off_the_wall(tile, jitter)
		enemy.position = tile_to_world(tile) + jitter \
			+ Vector3(0, 1.6 if flying else 0.3, 0)
		if not roams and enemy.get("wanders") != null:
			enemy.rotation.y = _open_heading(tile)

		add_child(enemy)
		enemy.aggro_range = enemy_aggro_range
		_give_wander_area(enemy, tile, roams)
		_spawned.append(enemy)
	# Every skeleton pack walks with a enforcer (enforcer.gd), which keeps close
	# to the pack's first skeleton while they amble.
	if not flying and enforcers_with_packs and leader != null:
		var w := _spawn_enforcer(tile, leader, members)
		# It passes through its own pack: two of them standing side by side in a
		# corridor otherwise wall in its wider body (measured: one of six stuck
		# 7.6 m from its escort, wedged between two sentries).
		for m in members:
			(w as PhysicsBody3D).add_collision_exception_with(m)
		w.set("pack", members)
		count += 1
		# On patrol: the column walks the corridors, the enforcer at its back.
		if patrols and not _patrol_points.is_empty():
			var column: Array[Node3D] = []
			column.assign(members)
			column.append(w)
			var p: Node = PATROL.new()
			p.name = "Patrol"
			add_child(p)
			p.call("setup", column, _patrol_points, _rng.randi())
			_spawned.append(p)
	return count


## --- Haul convoys (convoy.gd, 2026-10-09) ---------------------------------------
##
## Skeletons moving a cart of coins and crystals round the corridors' loops
## with an enforcer behind. They start somewhere far from the player and from each
## other, already moving, every time the world is populated.

@export var convoy_count := 4
## Corridor cells on loops per convoy sent out (up to `convoy_count`).
@export var convoy_loop_cells := 40
## Nearest a convoy may start to the player, and to another convoy.
@export var convoy_start_clear := 45.0
const CONVOY := preload("res://scripts/convoy.gd")
var _convoy_net := {}
var _convoys: Array[Node3D] = []


func _spawn_convoys() -> void:
	_convoys.clear()
	if not modules or _module_level == null or convoy_count <= 0 or enemy_scene == null:
		return
	if _convoy_net.is_empty():
		_convoy_net = CONVOY.network(_module_level)
	var loops: Array = _convoy_net["cells"]
	if loops.size() < 30:
		print("[convoys] only %d corridor cells on loops; none sent out" % loops.size())
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var from: Vector3 = player.global_position if player != null else _module_level.spawn
	var starts: Array[Vector3] = []
	var tries := 0
	# One per `convoy_loop_cells` of loop: four on a small network spent most of
	# their time waiting for each other.
	var want := clampi(loops.size() / convoy_loop_cells, 1, convoy_count)
	while _convoys.size() < want and tries < 400:
		tries += 1
		var cell: Vector2i = loops[_rng.randi_range(0, loops.size() - 1)]
		var at: Vector3 = _module_level.to_world(cell)
		if at.distance_to(from) < convoy_start_clear or _seen_by_player(at):
			continue
		var crowded := false
		for s in starts:
			if s.distance_to(at) < convoy_start_clear:
				crowded = true
		if crowded:
			continue
		var c: Node3D = CONVOY.spawn(self, _module_level, _convoy_net, cell, _rng.randi())
		if c == null:
			continue
		_spawned.append(c)
		_convoys.append(c)
		starts.append(at)
	print("[convoys] %d sent out over %d corridor cells on loops (of %d)"
		% [_convoys.size(), loops.size(), _corridor_cell_count()])


@export var enforcers_with_packs := true
## An enforcer's beam reaches 20 m (enforcer.gd BEAM_RANGE), so it notices further
## than a skeleton does.
@export var enforcer_aggro_range := 22.0
const ENFORCER_SCRIPT := preload("res://scripts/enforcer.gd")


func _spawn_enforcer(tile: Vector2i, escort: Node3D, members: Array[Node3D] = []) -> Node3D:
	var w: Node3D = enemy_scene.instantiate()
	w.set_script(ENFORCER_SCRIPT)
	# Beside its escort, on whichever side leaves it furthest from the rest of
	# the pack: it does not collide with them, and asleep it would stand inside
	# one until woken.
	var best := escort.position + Vector3(1.4, -0.3, 0.0)
	var best_gap := -1.0
	for k in 16:
		var a := TAU * float(k) / 16.0 + _rng.randf_range(0.0, 0.3)
		var at := escort.position + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(1.2, 1.8)
		at.y = tile_to_world(tile).y
		var near := world_to_tile(at)
		if not is_open(near) or _room_of(near) != _room_of(tile):
			continue
		var gap := INF
		for m in members:
			gap = minf(gap, Vector2(m.position.x - at.x, m.position.z - at.z).length())
		if gap > best_gap:
			best_gap = gap
			best = at
	w.position = best + Vector3(0.0, 0.3, 0.0)
	w.rotation.y = _open_heading(tile)
	add_child(w)
	w.set("aggro_range", enforcer_aggro_range)
	_give_wander_area(w, tile, true)
	w.set("escort", escort)
	_spawned.append(w)
	return w


## Pulls a spawn offset back out of any wall it is pressed against.
##
## Only sentries need this. A wanderer walks off within a second or two, so
## where it starts hardly registers; one that never moves stands exactly where
## it was put for the whole game, and nose-to-the-masonry looks like a mistake.
func _off_the_wall(tile: Vector2i, offset: Vector3) -> Vector3:
	for step in DIRECTIONS.values():
		if is_open(tile + step):
			continue
		var into := Vector3(float(step.x), 0.0, float(step.y))
		var amount := offset.dot(into)
		if amount > 0.0:
			# Flatten the component heading into the wall, then stand off it.
			offset -= into * (amount + sentry_wall_clearance)
	return offset


## Which way to face so there is somewhere to look.
##
## Picks a single open direction and measures how far it runs, then takes the
## longest. Summing the open neighbours instead looks reasonable and is wrong:
## in a straight corridor the two ends cancel to zero, leaving nothing to face
## and a random yaw that lands in a side wall about half the time.
func _open_heading(tile: Vector2i) -> float:
	var best: Array[Vector2i] = []
	var furthest := 0
	for step in DIRECTIONS.values():
		var reach := 0
		while reach < sentry_sightline and is_open(tile + step * (reach + 1)):
			reach += 1
		if reach == 0:
			continue
		if reach > furthest:
			furthest = reach
			best = [step]
		elif reach == furthest:
			best.append(step)

	if best.is_empty():
		# Walled in on all four sides, which should not happen, but facing a
		# random way is no worse than facing a chosen wall.
		return _rng.randf() * TAU
	# Ties broken at random, so a crossroads is not all facing the same way.
	var pick: Vector2i = best[_rng.randi() % best.size()]
	# Matches _face in enemy.gd, which points the body's -Z down the heading.
	return atan2(-float(pick.x), -float(pick.y))


## A knot of enemies in each treasure room, so the chest is guarded rather than
## merely placed. They are given the room as their wander area, which keeps
## them inside it until they actually see you.
func _spawn_room_packs(taken: Array[Vector2i]) -> void:
	# A puzzle room is guarded by its puzzle, not by skeletons.
	if enemy_scene == null or chest_room_pack <= 0 or not _puzzles.is_empty():
		return
	var half := treasure_room_tiles / 2

	for centre in treasure_centres:
		var spots: Array[Vector2i] = []
		for dz in range(-half, half + 1):
			for dx in range(-half, half + 1):
				var tile := centre + Vector2i(dx, dz)
				# Off the pedestal itself, so nothing spawns on the chest.
				if not is_open(tile) or tile.distance_to(centre) < 1.5:
					continue
				spots.append(tile)
		if spots.is_empty():
			continue

		var left := chest_room_pack
		while left > 0:
			var tile: Vector2i = spots[_rng.randi() % spots.size()]
			var flying: bool = flyer_scene != null and _rng.randf() < flyer_share * 0.5
			var group := mini(_rng.randi_range(
				flyer_pack_min if flying else red_pack_min,
				flyer_pack_max if flying else red_pack_max), left)
			left -= _spawn_pack(tile, flying, group)
			taken.append(tile)


## Hands an enemy the places it is allowed to idle: open tiles near its spawn
## that are the same kind of place. That is what stops a corridor guard from
## ambling into a treasure room, and a room guard from ambling out, before
## either of them has any reason to leave.
func _give_wander_area(enemy: Node, tile: Vector2i, roams := true) -> void:
	if enemy.get("wander_spots") == null:
		return
	enemy.wanders = roams
	var home_room := _room_of(tile)
	var spots: Array[Vector3] = []
	for dz in range(-wander_tiles, wander_tiles + 1):
		for dx in range(-wander_tiles, wander_tiles + 1):
			var candidate := tile + Vector2i(dx, dz)
			if not is_open(candidate) or _room_of(candidate) != home_room:
				continue
			spots.append(tile_to_world(candidate))
	enemy.wander_spots = spots
	enemy.wander_radius = float(wander_tiles) * tile_size

	# How far off a spot still counts as being on it. A little over half a tile,
	# so the allowed tiles join up into one continuous patch without reaching
	# into the tile beyond.
	enemy.wander_tolerance = tile_size * 0.55




## Which enclosed space a tile belongs to: -1 for open maze, 0 for the chamber,
## and 1 upward for each treasure room.
func _room_of(tile: Vector2i) -> int:
	if is_in_boss_room(tile):
		return 0
	var half := treasure_room_tiles / 2
	for index in treasure_centres.size():
		var centre: Vector2i = treasure_centres[index]
		if absi(tile.x - centre.x) <= half and absi(tile.y - centre.y) <= half:
			return index + 1
	return -1


## Open tiles that are neither in the chamber nor near the player's start.
## `in_sight_too`: skip the sight test (the Remnant starts 100 m off, past it).
func _spawn_candidates(in_sight_too := false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in tiles:
		for x in tiles:
			var tile := Vector2i(x, z)
			if not is_open(tile) or _is_reserved(tile):
				continue
			if Vector2(tile - _start_tile).length() <= float(safe_tiles_from_start):
				continue
			# The module level's rooms are open courtyards in which every tile
			# is floor, against corridors one tile wide, so as candidates they
			# swamped the maze: measured, 47 of 92 enemies spawned inside a
			# room. They hold their champion -- the boss, the mimic -- and the
			# corridors hold everything else. (The tile maze's treasure rooms
			# were small and deliberately guarded, so it keeps its old rule.)
			if modules and (is_in_treasure_room(tile) or is_in_morgue(tile) or is_in_surgery(tile)):
				continue
			# Nor beside one: a pack is scattered up to 1.3 m (a tile) round its
			# tile, and from a doorway that put members inside the room, where the
			# puzzle seal shuts them in with the player (2 of 229 on the big maze).
			if modules and _touches_room(tile):
				continue
			# Never on top of a chest: a body spawned inside solid geometry gets
			# shoved out hard.
			# Clear of the chest and the pillars standing around it.
			var on_chest := false
			for centre in treasure_centres:
				if absi(centre.x - tile.x) <= 2 and absi(centre.y - tile.y) <= 2:
					on_chest = true
					break
			if on_chest:
				continue
			# Not where the player can see it appear.
			if not in_sight_too and _seen_by_player(tile_to_world(tile)):
				continue
			out.append(tile)
	return out


## Module cells outside every room: what per-corridor densities count.
func _corridor_cell_count() -> int:
	var n := 0
	for key in _module_level.cells:
		if _module_level.cells[key].room < 0:
			n += 1
	return n


func _touches_room(tile: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var t := tile + Vector2i(dx, dy)
			if is_in_treasure_room(t) or is_in_morgue(t) or is_in_surgery(t) or is_in_boss_room(t):
				return true
	return false


## --- Nothing spawns in sight (2026-10-14) ----------------------------------------
##
## Every (re)population -- the first build, and a death -- skips spawn spots the
## player can see from where they stand: a clear line on the sight layer (doors
## and walls) from their eye to a body's height over the spot, within
## SPAWN_SIGHT_RANGE. Fog hides anything further. The player is placed before
## `_populate` runs, so on a respawn this is the anchor they rise at.
const SPAWN_SIGHT_RANGE := 70.0
const SPAWN_SIGHT_POINTS := [Vector3(0, 1.0, 0), Vector3(0, 2.4, 0), Vector3(1.3, 1.0, 1.3),
	Vector3(-1.3, 1.0, 1.3), Vector3(1.3, 2.4, -1.3), Vector3(-1.3, 2.4, -1.3)]
var _spawn_eye := Vector3.INF
var _spawn_sight := PhysicsRayQueryParameters3D.new()


func _seen_by_player(point: Vector3) -> bool:
	if _spawn_eye == Vector3.INF:
		return false
	if point.distance_squared_to(_spawn_eye) > (SPAWN_SIGHT_RANGE + 2.0) * (SPAWN_SIGHT_RANGE + 2.0):
		return false
	# Where a pack's bodies can actually be: anywhere in the 1.3 m it is
	# scattered over, from a skeleton's chest to a crier's hover (measured: two
	# criers in sight from a tile whose centre at 1.2 m was hidden by a pier).
	_spawn_sight.collision_mask = 2
	for off: Vector3 in SPAWN_SIGHT_POINTS:
		var at := point + off
		if at.distance_squared_to(_spawn_eye) > SPAWN_SIGHT_RANGE * SPAWN_SIGHT_RANGE:
			continue
		_spawn_sight.from = _spawn_eye
		_spawn_sight.to = at
		if get_world_3d().direct_space_state.intersect_ray(_spawn_sight).is_empty():
			return true
	return false


func _note_spawn_eye() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_spawn_eye = Vector3.INF
	if player == null:
		return
	_spawn_eye = player.global_position + Vector3(0.0, 1.6, 0.0)
	_spawn_sight.exclude = [(player as CollisionObject3D).get_rid()] if player is CollisionObject3D else []


## --- The decrepit enforcer (2026-10-15) and the sewer lizards (2026-10-16) ----------
##
## Feral, rotted enforcers (decrepit.gd) hunt the sewer -- only down there, at
## most `decrepit_max` at once, and always placed one at a time: each in a sewer
## cell at least `decrepit_spawn_clear` from the player, out of their sight, and
## `decrepit_apart` from every other one. Placed with the population (so a death
## resets them); one killed, another comes `decrepit_respawn` seconds later.
## The sewer lizards (sewer_lizard.gd), its common vermin, come with the
## population too: `sewer_lizards_per_cell` of the sewer's cells, out of sight.

const DECREPIT_SCRIPT := preload("res://scripts/decrepit.gd")
const LIZARD_SCRIPT := preload("res://scripts/sewer_lizard.gd")
@export var decrepit_enabled := true
@export var decrepit_max := 3
@export var decrepit_respawn := 45.0
@export var decrepit_spawn_clear := 30.0
@export var decrepit_apart := 40.0
@export var sewer_lizards_per_cell := 0.15
@export var sewer_lizard_clear := 16.0
var _decrepits: Array = []
var _decrepit_due: Array[float] = []


func _spawn_decrepits() -> void:
	_decrepits.clear()
	_decrepit_due.clear()
	for i in decrepit_max:
		_spawn_decrepit()


func _alive_decrepits() -> Array:
	var out := []
	for d in _decrepits:
		if is_instance_valid(d) and not d.get("_dying"):
			out.append(d)
	return out


func _spawn_decrepit() -> void:
	if not decrepit_enabled or _sewer == null or enemy_scene == null:
		return
	var alive := _alive_decrepits()
	if alive.size() >= decrepit_max:
		return
	var spot = _sewer_spot(decrepit_spawn_clear, alive, decrepit_apart)
	if spot == null:
		return
	var d: CharacterBody3D = enemy_scene.instantiate()
	d.set_script(DECREPIT_SCRIPT)
	d.set("sewer", _sewer)
	add_child(d)
	d.global_position = (spot as Vector3) + Vector3(0.0, 0.3, 0.0)
	d.rotation.y = randf() * TAU
	_spawned.append(d)
	d.connect("died", _on_decrepit_died)
	_decrepits.append(d)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	print("[decrepit] spawned %.0f m from the player (%d alive)" % [(spot as Vector3).distance_to(
		player.global_position if player != null else Vector3.ZERO), alive.size() + 1])


func _spawn_sewer_lizards() -> void:
	if _sewer == null or enemy_scene == null or sewer_lizards_per_cell <= 0.0:
		return
	var map = _sewer.get("map")
	var count := int(round(float(map.cells.size()) * sewer_lizards_per_cell))
	var placed: Array = []
	for i in count:
		var spot = _sewer_spot(sewer_lizard_clear, placed, 6.0)
		if spot == null:
			break
		var l: CharacterBody3D = enemy_scene.instantiate()
		l.set_script(LIZARD_SCRIPT)
		l.set("sewer", _sewer)
		add_child(l)
		l.global_position = (spot as Vector3) + Vector3(randf_range(-1.0, 1.0), 0.25, randf_range(-1.0, 1.0))
		l.rotation.y = randf() * TAU
		_spawned.append(l)
		placed.append(l)
	print("[sewer] %d lizards" % placed.size())


## A sewer cell at least `clear` from the player and out of their sight, and
## `apart` from each of `others`; the furthest from the player if none qualify.
func _sewer_spot(clear: float, others: Array, apart: float):
	var map = _sewer.get("map")
	if map == null or map.cells.is_empty():
		return null
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var from: Vector3 = player.global_position if player != null else Vector3.ZERO
	var eye := from + Vector3(0.0, 1.6, 0.0)
	var space := get_world_3d().direct_space_state
	var ok: Array[Vector3] = []
	var best = null
	var best_d := -1.0
	for key in map.cells:
		var p: Vector3 = map.to_world(key)
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		var crowded := false
		for o in others:
			if is_instance_valid(o) and Vector2(p.x - o.global_position.x, p.z - o.global_position.z).length() < apart:
				crowded = true
		if d > best_d and not crowded:
			best_d = d
			best = p
		if d < clear or crowded:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, p + Vector3(0.0, 1.0, 0.0), 2 | 256)
		if space.intersect_ray(q).is_empty():
			continue
		ok.append(p)
	if ok.is_empty():
		return best
	var roll := RandomNumberGenerator.new()
	roll.randomize()
	return ok[roll.randi_range(0, ok.size() - 1)]


## --- Rats (rat.gd, 2026-10-18) ---------------------------------------------------
##
## Harmless, fast, catchable with E: `rats_in_corridors` on corridor tiles (the
## patrol points `_spawn_enemies` gathered), each at least `rat_clear` from the
## player and `rat_apart` from every other, and `rats_in_sewer` in the sewer's
## cells. (A share of the patrol points was 293 rats: they are tiles, not
## cells.) With the population, so a death resets them -- under their own
## node, not `_spawned`, so the room census (`_report_room_intruders`) does not
## count them as guards.
const RAT_SCRIPT := preload("res://scripts/rat.gd")
@export var rats_in_corridors := 24
@export var rats_in_sewer := 8
@export var rat_clear := 10.0
@export var rat_apart := 6.0
var _rats_node: Node3D
var _rat_rng := RandomNumberGenerator.new()


func _spawn_rats() -> void:
	if _rats_node != null and is_instance_valid(_rats_node):
		_rats_node.free()
	_rats_node = Node3D.new()
	_rats_node.name = "Rats"
	add_child(_rats_node)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var from: Vector3 = player.global_position if player != null else Vector3.ZERO
	var placed: Array[Vector3] = []
	var spots := _patrol_points.duplicate()
	var want := rats_in_corridors
	var tries := 0
	# Their own generator, off the level seed: drawing from `_rng` shifted every
	# roll after it (the chests and all they bring), and the population was no
	# longer the one this seed has always made.
	_rat_rng.seed = hash(_active_seed + 7919)
	while placed.size() < want and not spots.is_empty() and tries < want * 40:
		tries += 1
		var p: Vector3 = spots[_rat_rng.randi_range(0, spots.size() - 1)]
		if p.distance_to(from) < rat_clear:
			continue
		var crowded := false
		for o in placed:
			if o.distance_to(p) < rat_apart:
				crowded = true
				break
		if crowded:
			continue
		spots.erase(p)
		placed.append(p)
		_add_rat(p)
	var corridor := placed.size()
	if _sewer != null and rats_in_sewer > 0:
		var below: Array = []
		for i in rats_in_sewer:
			var spot = _sewer_spot(rat_clear, below, rat_apart)
			if spot == null:
				break
			var r := _add_rat(spot as Vector3)
			below.append(r)
	print("[rats] %d in the corridors, %d in the sewer" % [corridor, _rats_node.get_child_count() - corridor])


func _add_rat(at: Vector3) -> Node3D:
	var r := CharacterBody3D.new()
	r.set_script(RAT_SCRIPT)
	r.position = at + Vector3(_rat_rng.randf_range(-0.8, 0.8), 0.15, _rat_rng.randf_range(-0.8, 0.8))
	_rats_node.add_child(r)
	return r


func _on_decrepit_died() -> void:
	_decrepit_due.append(Time.get_ticks_msec() / 1000.0 + decrepit_respawn)


func _tick_decrepit() -> void:
	if _decrepit_due.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _decrepit_due[0]:
		return
	_decrepit_due.remove_at(0)
	_spawn_decrepit()
