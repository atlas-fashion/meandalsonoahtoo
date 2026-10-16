// The sewer's water (sewer.gd `_build_water`): thick, near-black sludge-water in
// the channels. It is laid as one plane per cell under the walkways -- the floor
// hides it everywhere but the channel -- and mapped in WORLD space, so it runs on
// through every tunnel and chamber with no join.
//
// Two layers of the Higgsfield muck drift slowly against each other (the
// surface barely moves; it is more sludge than stream); where a low-frequency
// noise rises, matte scum floats on the glossy black liquid.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sludge_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sludge_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 liquid : source_color = vec3(0.018, 0.02, 0.012);
uniform float drift = 0.012;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * drift;
	vec2 a = p * 0.34 + vec2(t, t * 0.35);
	vec2 b = vec2(p.y, -p.x) * 0.27 + vec2(-t * 0.6, t * 0.8);
	vec3 c = texture(sludge_tex, a).rgb * 0.5 + texture(sludge_tex, b).rgb * 0.5;
	float scum = smoothstep(0.52, 0.72, texture(noise_tex, p * 0.05 + vec2(t * 0.25, -t * 0.1)).r
		+ (texture(noise_tex, p * 0.31 - vec2(t)).r - 0.5) * 0.25);
	ALBEDO = mix(liquid + c * 0.05, c * 0.55, scum);
	ROUGHNESS = mix(0.06, 0.75, scum);
	SPECULAR = 0.55;
	vec2 na = texture(sludge_normal, a).xy * 2.0 - 1.0;
	vec2 nb = texture(sludge_normal, b).xy * 2.0 - 1.0;
	vec3 tn = normalize(vec3((na + nb) * mix(0.12, 0.9, scum), 1.0));
	NORMAL_MAP = tn * 0.5 + 0.5;
}
