shader_type spatial;

// The dark earth under the flagstones -- what shows in the joints between them
// (note 121). The sewer's Higgsfield sludge (wet, clumped muck) recoloured from
// its olive to a dark brown by its own luminance, projected from above in world
// space, so neighbouring cells' beds run on as one ground.

uniform sampler2D dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Metres of ground one repeat of the texture covers.
uniform float span = 0.85;
// Its darkest clods and its lightest grit; the luminance picks between them.
uniform vec3 deep : source_color = vec3(0.1, 0.075, 0.053);
uniform vec3 grit : source_color = vec3(0.42, 0.315, 0.22);
// How much of the source's own colour survives (its greens read as moss).
uniform float keep_hue = 0.18;
uniform float relief = 1.4;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / span;
	vec3 src = texture(dirt, uv).rgb;
	float lum = dot(src, vec3(0.299, 0.587, 0.114));
	vec3 earth = mix(deep, grit, smoothstep(0.02, 0.3, lum));
	// A trace of the original hue, scaled to the earth's brightness.
	vec3 hue = src / max(lum, 0.001) * dot(earth, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(earth, hue, keep_hue);
	NORMAL_MAP = texture(dirt_normal, uv).rgb;
	NORMAL_MAP_DEPTH = relief;
	// Damp: the clods matte, the wet film between them a little glossy.
	ROUGHNESS = mix(0.93, 0.5, smoothstep(0.22, 0.55, lum));
	SPECULAR = 0.35;
}
