shader_type spatial;

// A living root tip (living_root.gd, note 176): the same bark and gold as the
// roots it grows from (root_common.gdshaderinc), bent along a cubic Bezier the
// script drives every frame. The mesh is a straight tapered tube: each vertex's
// ring offset in x and z, how far along it is in UV2.x. Its first control point
// is the base, the origin; `p1`..`p3` (in the tip's own frame) ride on instance
// uniforms, so every tip shares one material and costs one draw.
//
// `glow` is its gold (1 alive, brighter as it draws back to strike, 0 once cut);
// `wilt` 0..1 shrivels and greys it as it dies.

render_mode cull_back;

#include "res://shaders/root_common.gdshaderinc"

instance uniform vec3 p1 = vec3(0.0, -0.3, 0.3);
instance uniform vec3 p2 = vec3(0.0, -0.7, 0.5);
instance uniform vec3 p3 = vec3(0.0, -1.1, 0.4);
instance uniform float glow = 1.0;
instance uniform float wilt = 0.0;

void vertex() {
	float t = UV2.x;
	float it = 1.0 - t;
	vec3 b = 3.0 * it * it * t * p1 + 3.0 * it * t * t * p2 + t * t * t * p3;
	vec3 d = 3.0 * it * it * p1 + 6.0 * it * t * (p2 - p1) + 3.0 * t * t * (p3 - p2);
	vec3 along = normalize(d + vec3(0.0, -1e-4, 1e-5));
	// The frame round the curve: a fixed reference (along the wall) unless the
	// curve itself turns that way, blended so it never flips.
	vec3 ref = normalize(mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), smoothstep(0.8, 0.97, abs(along.x))));
	vec3 n = normalize(cross(ref, along));
	vec3 bn = cross(along, n);
	float shrink = mix(1.0, 0.6, wilt);
	VERTEX = b + (n * VERTEX.x + bn * VERTEX.z) * shrink;
	NORMAL = normalize(n * NORMAL.x + bn * NORMAL.z + along * NORMAL.y);
	TANGENT = normalize(n * TANGENT.x + bn * TANGENT.z + along * TANGENT.y);
	BINORMAL = along;
}

void fragment() {
	vec3 albedo;
	float rough;
	vec3 nmap;
	vec3 emit;
	// The living ones carry more gold than the roots they grow from.
	vec4 col = COLOR;
	col.g *= 1.6;
	root_surface(UV, UV2, col, glow, wilt, TIME, albedo, rough, nmap, emit);
	// The very tip glows a little on its own while it lives.
	emit += vein_colour * smoothstep(0.82, 1.0, UV2.x) * 0.9 * glow;
	emit *= smoothstep(0.05, 0.45, abs(dot(NORMAL, VIEW)));
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	NORMAL_MAP = nmap;
	EMISSION = emit;
}
