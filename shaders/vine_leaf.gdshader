shader_type spatial;

// Huge dead leaves on the pillar vines, stirring in a breeze.
//
// Sway comes from the vertex colours `tools/build_vines.py` writes: COLOR.r is
// 0 at the stalk and 1 at the tip, so the stalk stays on its vine and the tip
// moves most; COLOR.g is a per-leaf phase. The pillar's own world position
// offsets the phase too, so two columns do not breathe in step.
//
// Drawn from both sides (a leaf has no inside), with a little back-light so a
// leaf between you and a torch glows at its thin edges.

render_mode cull_disabled;

uniform vec3 wind_direction = vec3(1.0, 0.0, 0.35);
// Metres at the tip. Slight, as asked: a breeze, not a gale.
uniform float sway = 0.09;
uniform float flutter = 0.035;
uniform float wind_speed = 0.9;

uniform vec4 stalk_color : source_color = vec4(0.13, 0.085, 0.05, 1.0);
uniform vec4 blade_color : source_color = vec4(0.22, 0.12, 0.055, 1.0);
uniform vec4 rim_color : source_color = vec4(0.34, 0.14, 0.05, 1.0);
uniform vec4 vein_color : source_color = vec4(0.42, 0.31, 0.19, 1.0);
uniform vec4 backlight_color : source_color = vec4(0.45, 0.16, 0.04, 1.0);

void vertex() {
	float w = COLOR.r;
	float phase = COLOR.g * 6.2832 + dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.21));
	float gust = sin(TIME * wind_speed + phase) * 0.65
		+ sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.35;
	// The wind is in world space; VERTEX is in the pillar's own space.
	vec3 local_wind = normalize(inverse(mat3(MODEL_MATRIX)) * normalize(wind_direction));
	VERTEX += local_wind * gust * sway * w * w;
	VERTEX.y += sin(TIME * 3.1 + phase * 3.0 + w * 4.0) * flutter * w;
}

void fragment() {
	// UV.x runs stalk (0) to tip (1); UV.y across the blade, 0.5 on the midrib.
	float across = abs(UV.y - 0.5) * 2.0;
	vec3 c = mix(stalk_color.rgb, blade_color.rgb, smoothstep(0.0, 0.35, UV.x));
	// Withered, rusty edges and tip.
	c = mix(c, rim_color.rgb, smoothstep(0.55, 1.0, max(across, UV.x * 0.9)));
	// Midrib and paired side veins angling out towards the tip.
	float midrib = 1.0 - smoothstep(0.0, 0.05, across);
	float side = 1.0 - smoothstep(0.0, 0.07, abs(fract(UV.x * 7.0 - across * 1.6) - 0.5) * 2.0 - 0.9);
	float veins = max(midrib, side * (1.0 - smoothstep(0.7, 1.0, across)) * 0.7);
	c = mix(c, vein_color.rgb, veins * 0.75);
	ALBEDO = c;
	ROUGHNESS = 0.82;
	SPECULAR = 0.2;
	BACKLIGHT = backlight_color.rgb * (0.4 + 0.6 * across);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
