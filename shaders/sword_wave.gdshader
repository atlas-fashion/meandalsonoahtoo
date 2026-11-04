// The heavy slash's gold wave (sword_wave.gd, note 160), and the gold on the
// blade as it winds up (player.gd `_blade_glow`). Unshaded and additive: a hot
// white-gold edge along the front (UV.y 0), gold falling off behind it (UV.y 1),
// the tips (UV.x 0 and 1) thinning away, and a flicker running along it so it
// reads as energy rather than a painted shape. Over 1.0 so the glow pass blooms
// it on the presets that have glow; without glow it is still a bright gold.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(1.0, 0.93, 0.7);
uniform vec3 gold : source_color = vec3(1.0, 0.62, 0.12);
uniform float strength = 3.0;
// 0 = fully on, 1 = gone.
instance uniform float fade = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float along = UV.x;
	float back = UV.y;
	float tips = smoothstep(0.0, 0.22, along) * smoothstep(1.0, 0.78, along);
	// A sharp bright edge, then a softer gold tail.
	float edge = exp(-back * 9.0);
	float tail = pow(1.0 - back, 2.2);
	float flick = 0.7 + 0.6 * noise(vec2(along * 14.0 - TIME * 9.0, back * 3.0 + TIME * 2.0));
	vec3 col = core * edge * 1.6 + gold * tail * flick;
	ALBEDO = col * strength * tips * (1.0 - fade);
}
