shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// The intro forest's leaves, needles, ferns and grass (note 131;
// scripts/intro_flora.gd). STAND-IN cards painted in code, to be replaced by
// Higgsfield models. Alpha-cut cards that sway in the wind and let the low sun
// through (backlight). Vertex colour: r how much this vertex sways (0 at the
// trunk, 1 at a tip), g how much light reaches it (inner crown darker).
// A MultiMesh instance's custom data tints it (rgb) per plant.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float cutoff = 0.42;
uniform float sway = 1.0;
uniform float translucency = 0.55;
uniform float roughness = 0.82;
// Wind: xz its heading, z its strength (m at a full tip), w its pace.
uniform vec4 wind = vec4(1.0, 0.35, 0.18, 1.1);

varying vec3 plant_tint;

void vertex() {
	plant_tint = INSTANCE_CUSTOM.rgb;
	if (dot(plant_tint, plant_tint) < 0.0001) {
		plant_tint = vec3(1.0);
	}
	vec3 root = MODEL_MATRIX[3].xyz;
	float phase = dot(root.xz, vec2(0.13, 0.091));
	float t = TIME * wind.w + phase;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// A slow lean with the gusts, and a quicker flutter at the tips.
	float gust = 0.6 + 0.4 * sin(t * 0.37 + phase * 3.0);
	vec2 lean = normalize(wind.xy) * (sin(t) * 0.55 + 0.45) * gust;
	vec3 flutter = vec3(sin(t * 3.1 + wp.y * 1.7 + wp.x), sin(t * 2.3 + wp.z) * 0.4, cos(t * 2.7 + wp.z * 1.3));
	vec3 off = (vec3(lean.x, 0.0, lean.y) + flutter * 0.25) * wind.z * sway * COLOR.r;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	vec3 col = c.rgb * tint * plant_tint * mix(0.45, 1.0, COLOR.g);
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	BACKLIGHT = col * translucency;
}
