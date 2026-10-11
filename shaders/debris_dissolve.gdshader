shader_type spatial;
render_mode cull_disabled;

// A door piece crumbling away: the door's own textures, eaten through by noise
// as `dissolve` runs 0 -> 1, with a thin ember-hot rim where it is giving way.
// `dissolve` is an INSTANCE uniform, so every piece shares one material per
// source surface and still crumbles on its own clock.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
// Repeat: the piece's coordinates run well outside 0..1, and a clamped noise
// reads one edge value everywhere -- the same flat burn as before.
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float normal_strength = 1.0;
uniform float roughness = 0.95;
uniform bool has_normal = false;
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float edge_width = 0.05;
uniform float edge_glow = 2.2;
uniform float noise_scale = 0.9;

instance uniform float dissolve = 0.0;

// The noise is laid on the piece's OWN space, not its UVs: the door is on a
// texture atlas, so a piece covers a sliver of UV, the noise read flat across
// it, and the whole slab burned as one rim and blinked out.
varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float n = texture(noise_tex, local_pos.xy * noise_scale + vec2(local_pos.z * 0.7)).r;
	// Slightly beyond 1 so a fully dissolved piece leaves nothing behind.
	float cut = dissolve * 1.08;
	if (n < cut) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.0;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	float rim = 1.0 - smoothstep(cut, cut + edge_width, n);
	EMISSION = edge_color.rgb * edge_glow * rim * step(0.001, dissolve);
}
