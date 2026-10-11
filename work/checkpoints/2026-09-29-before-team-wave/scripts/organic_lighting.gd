extends RefCounted

## Bakes the torchlight into the level's MultiMesh instance colours.
##
## This is the affordable substitute for a lightmap. `LightmapGI` cannot light
## a `MultiMeshInstance3D` at all, and a lightmap needs fixed geometry, so
## baking one meant freezing the maze to a single seed and flattening every
## chunk into unique static meshes -- measured at 497 MB of video memory
## against 251 MB for the whole instanced game, on a card with 2 GB. Merely
## having that file in the project took the editor down three times.
##
## So the light is baked per PANEL instead of per texel. Each wall panel, floor
## slab and ceiling slab gets one colour, computed from the torches that reach
## it. Resolution is one value per 2 m panel, which is coarse -- but in a dark
## corridor lit by point torches what the eye reads is the falloff from one pool of
## light to the next, and that is exactly what this reproduces.
##
## What it does NOT give you is shadows or bounced light. A panel behind a
## pillar is lit as though the pillar were not there.
##
## The real win is not the look, it is that the static geometry stops asking
## 209 omni lights to shade it every frame. The lights stay in the scene for
## dynamic objects -- the player, enemies, props -- via `light_cull_mask`.

## Render layer the baked static geometry is moved onto, so torch lights can be
## told to skip it. Layer 1 stays the default everything-else layer.
const STATIC_LAYER := 2

## Below this, a torch contributes nothing worth the arithmetic.
const MIN_CONTRIBUTION := 0.004


## `torches` is an array of {pos: Vector3, colour: Color, energy: float,
## range: float}. `holders` are the nodes whose MultiMeshInstance3D children
## should be lit. Returns how many instances were coloured.
##
## `ambient` is the floor the level never goes below -- without it, a corridor
## out of torch range goes to pure black and the player cannot see the walls at
## all, which reads as a hole rather than as darkness.
static func bake(holders: Array, torches: Array, ambient: Color,
		opts: Dictionary = {}) -> int:
	var exposure: float = float(opts.get("exposure", 1.0))
	var wall_facing: bool = bool(opts.get("facing", true))

	# Bucketed by position: every instance would otherwise test every torch,
	# which is 11,000 x 209 distance checks per build.
	var bucket := 12.0
	var grid := {}
	for i in torches.size():
		var t: Dictionary = torches[i]
		var p: Vector3 = t["pos"]
		var reach: float = float(t["range"])
		var lo := Vector2i(int(floor((p.x - reach) / bucket)), int(floor((p.z - reach) / bucket)))
		var hi := Vector2i(int(floor((p.x + reach) / bucket)), int(floor((p.z + reach) / bucket)))
		for bx in range(lo.x, hi.x + 1):
			for by in range(lo.y, hi.y + 1):
				var key := Vector2i(bx, by)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(i)

	var lit := 0
	for holder in holders:
		if holder == null:
			continue
		for node in (holder as Node).find_children("*", "MultiMeshInstance3D", true, false):
			var mmi: MultiMeshInstance3D = node
			var mm := mmi.multimesh
			if mm == null or not mm.use_colors:
				continue
			# Off the default layer, so the torch lights can be told to ignore
			# it now that its lighting is already in the vertex colour.
			mmi.layers = 1 << (STATIC_LAYER - 1)
			for i in mm.instance_count:
				var xform: Transform3D = mmi.transform * mm.get_instance_transform(i)
				# Sampled a little off the surface and at eye height rather
				# than at the instance origin, which for a wall panel sits on
				# the floor at its base -- lighting it there makes every panel
				# read as though the torch were at its feet.
				var normal: Vector3 = -xform.basis.z.normalized() if wall_facing else Vector3.UP
				var at: Vector3 = xform.origin + normal * 0.3 + Vector3(0.0, 1.4, 0.0)

				var acc := Vector3(ambient.r, ambient.g, ambient.b)
				var key := Vector2i(int(floor(at.x / bucket)), int(floor(at.z / bucket)))
				for idx in grid.get(key, []):
					var t: Dictionary = torches[idx]
					var to_light: Vector3 = (t["pos"] as Vector3) - at
					var dist: float = to_light.length()
					var reach: float = float(t["range"])
					if dist >= reach or dist < 0.001:
						continue
					# Inverse-square, faded to nothing at the light's range so
					# there is no hard edge where a torch stops counting.
					var falloff: float = 1.0 - dist / reach
					var atten: float = falloff * falloff * float(t["energy"])
					if wall_facing:
						# A panel facing away from a torch should not be lit by
						# it. Softened rather than clamped hard, because a
						# single colour for a 2 m panel that is edge-on to the
						# light still catches some of it in reality.
						var ndotl: float = to_light.normalized().dot(normal)
						atten *= clampf(ndotl * 0.75 + 0.25, 0.0, 1.0)
					if atten < MIN_CONTRIBUTION:
						continue
					var c: Color = t["colour"]
					acc += Vector3(c.r, c.g, c.b) * atten
				acc *= exposure
				mm.set_instance_color(i, Color(
					minf(acc.x, 1.0), minf(acc.y, 1.0), minf(acc.z, 1.0), 1.0))
				lit += 1
	return lit


## Stops the torch lights from shading the geometry that already has their
## light baked in, while leaving them lighting everything dynamic.
##
## This is where the frame time comes back. The walls, floor and ceiling are
## almost all of the screen, and they were each asking every torch in range to
## shade them per pixel.
static func exclude_static_from(torch_holder: Node) -> int:
	if torch_holder == null:
		return 0
	var mask := 0xFFFFF & ~(1 << (STATIC_LAYER - 1))
	var changed := 0
	for light in torch_holder.find_children("*", "Light3D", true, false):
		(light as Light3D).light_cull_mask = mask
		changed += 1
	return changed


## Reads the torches back out of the scene, so the bake uses the lights that
## actually exist rather than a second guess at where they were put.
static func collect_torches(torch_holder: Node) -> Array:
	var out: Array = []
	if torch_holder == null:
		return out
	for light in torch_holder.find_children("*", "OmniLight3D", true, false):
		var l: OmniLight3D = light
		# `base_energy` is what `torch.gd` flickers around; `light_energy` is
		# whatever this frame's flicker happens to be, which would bake a
		# random sample of the flame into the wall.
		var owner_node := l.get_parent()
		var energy: float = l.light_energy
		if owner_node != null and "base_energy" in owner_node:
			energy = owner_node.base_energy
		out.append({
			"pos": l.global_position,
			"colour": l.light_color,
			"energy": energy,
			"range": l.omni_range,
		})
	return out
