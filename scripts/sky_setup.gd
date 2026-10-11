extends RefCounted

## Builds the dark blood-red / wispy-cloud sky and wires it onto an
## Environment. One call: `SkySetup.apply(env)`.
##
## Deliberately does nothing to ambient lighting. The level's own
## `configure_environment()` (in `maze.gd` / `module_level.gd`) sets
## `ambient_light_sky_contribution = 0.0` and drives ambient from a flat
## colour instead -- this file only ever touches `env.sky` and
## `env.background_mode`, so calling `apply()` after or before that setup
## can never fight it.

const CLOUD_SHADER := preload("res://shaders/sky_clouds.gdshader")


static func apply(env: Environment) -> void:
	if env == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	var sky := Sky.new()
	sky.sky_material = mat
	# The shader reads TIME, so by default Godot re-renders the sky's
	# radiance cubemap EVERY frame, visible or not. Measured on the P620 at
	# 3440x1440 that was ~2.5 ms at every station, corridors included. Nothing
	# here needs it: ambient comes from a flat colour (sky contribution 0) and
	# the stone is too rough to show reflections, so the cubemap is kept tiny
	# and refreshed a slice at a time.
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY
