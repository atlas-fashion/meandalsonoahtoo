shader_type spatial;
// cull_disabled because the leaves are single-sided quads and you will walk
// all the way around the plant.
render_mode cull_disabled;

// How far the tip wanders, in metres.
uniform float sway_amount = 1.0;
uniform float sway_speed = 0.32;
// Set per plant, so a room full of them never sways in unison.
uniform float phase = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
// Height at which the bend reaches full strength. Matches the mesh.
uniform float reference_height = 100.0;

void vertex() {
	// Bend grows with the square of height, the way a real stalk does: rooted
	// hard at the ground, loosest at the tip. A flat multiplier would swing the
	// whole plant like a signpost.
	float k = VERTEX.y / reference_height;
	k = k * k;

	float t = TIME * sway_speed + phase;
	// Two waves at unrelated rates on each axis, so the motion never visibly
	// loops and the tip traces a slow wander rather than a circle.
	float x = sin(t) * 0.62 + sin(t * 1.73 + 1.1) * 0.38;
	float z = cos(t * 0.81 + 0.6) * 0.55 + sin(t * 1.31 + 2.2) * 0.45;

	VERTEX.x += x * sway_amount * k;
	VERTEX.z += z * sway_amount * k;
}

void fragment() {
	// Stalk and leaf colours are baked into the vertices, which keeps the whole
	// plant to one surface and one draw call.
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.1;
}
