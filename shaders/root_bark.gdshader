shader_type spatial;

// The roots grown over the dungeon's walls, pillars, arches and vaults (note
// 176): bark and gold veins from root_common.gdshaderinc. One material for every
// root mesh in the level; each mesh's own `life` (its living tips' glow, 1 while
// any of them lives, ruin_roots.gd) and `rot` ride on instance uniforms.

render_mode cull_back;

#include "res://shaders/root_common.gdshaderinc"

instance uniform float life = 1.0;
instance uniform float rot = 0.0;

// Roots hanging free (vertex colour b) sway in the draughts, the more the
// further down they hang (UV2.x), each to its own beat (UV2.y).
void vertex() {
	float w = COLOR.b * UV2.x * UV2.x;
	if (w > 0.0) {
		float t = TIME * 0.7 + UV2.y * 23.0;
		VERTEX.x += (sin(t) + 0.4 * sin(t * 2.3 + 1.0)) * 0.045 * w;
		VERTEX.z += (cos(t * 0.8 + 2.0) + 0.4 * sin(t * 1.9)) * 0.045 * w;
	}
}

void fragment() {
	vec3 albedo;
	float rough;
	vec3 nmap;
	vec3 emit;
	root_surface(UV, UV2, COLOR, life, rot, TIME, albedo, rough, nmap, emit);
	// Seen edge-on a tube crowds its streaks together into a bright outline:
	// they dim toward the silhouette.
	emit *= smoothstep(0.05, 0.45, abs(dot(NORMAL, VIEW)));
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	NORMAL_MAP = nmap;
	EMISSION = emit;
}
