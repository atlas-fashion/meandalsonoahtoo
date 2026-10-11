shader_type spatial;

// A torch flame: a camera-facing card (turning about Y only, so it stays
// upright) with the fire drawn procedurally -- a teardrop of heat eaten away by
// rising noise, mapped through a blackbody-ish ramp from dull red at the edges
// through orange to a pale yellow core, and added onto the scene.
//
// The previous flame was an unshaded orange sphere, which read as a flat disc.
//
// Per-torch variation rides on INSTANCE uniforms, so all 170-odd torches share
// one material: `seed` offsets the noise and `intensity` is the flicker that
// torch.gd drives in step with its light.
//
// `halo` switches the same card to a soft round glow behind the flame. The game
// runs with bloom off on the lower presets, and without it the flame had no
// glow round it at all.

render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float seed = 0.0;
instance uniform float intensity = 1.0;
// 0 fire, 1 ice blue: the Remnant is near (torch.gd `chill`).
instance uniform float chill = 0.0;
uniform bool halo = false;
uniform float brightness = 1.6;
uniform float speed = 1.9;

vec2 _hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

float _noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(_hash2(i), f);
	float b = dot(_hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(_hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(_hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}

float _fbm(vec2 p) {
	return _noise(p) * 0.6 + _noise(p * 2.1 + 1.7) * 0.28 + _noise(p * 4.3 + 4.1) * 0.12;
}

void vertex() {
	// Y-locked billboard, as StandardMaterial3D's BILLBOARD_FIXED_Y builds it,
	// keeping the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec3 _fire(float heat) {
	vec3 ember = vec3(0.55, 0.06, 0.01);
	vec3 orange = vec3(1.0, 0.36, 0.04);
	vec3 amber = vec3(1.0, 0.62, 0.16);
	vec3 core = vec3(1.0, 0.86, 0.55);
	vec3 c = mix(ember, orange, smoothstep(0.08, 0.4, heat));
	c = mix(c, amber, smoothstep(0.55, 0.85, heat));
	return mix(c, core, smoothstep(0.9, 1.0, heat));
}

// The same flame gone cold: deep blue at the edges through ice blue to a
// near-white core.
vec3 _ice(float heat) {
	vec3 edge = vec3(0.02, 0.12, 0.45);
	vec3 blue = vec3(0.16, 0.5, 1.0);
	vec3 pale = vec3(0.5, 0.82, 1.0);
	vec3 core = vec3(0.85, 0.95, 1.0);
	vec3 c = mix(edge, blue, smoothstep(0.08, 0.4, heat));
	c = mix(c, pale, smoothstep(0.55, 0.85, heat));
	return mix(c, core, smoothstep(0.9, 1.0, heat));
}

void fragment() {
	float t = TIME * speed + seed * 17.0;
	// v runs 0 at the base of the flame to 1 at its tip.
	float v = 1.0 - UV.y;
	float x = UV.x - 0.5;

	if (halo) {
		float d = length(vec2(x, (v - 0.45) * 1.15)) * 2.0;
		float glow = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
		ALBEDO = mix(vec3(1.0, 0.38, 0.08), vec3(0.25, 0.6, 1.0), chill) * glow * 0.32 * intensity;
	} else {
		// The flame sways and licks: the whole column bends with a slow noise,
		// and fine rising noise tears the edges and the tip.
		float sway = (_noise(vec2(t * 0.7, seed)) - 0.5) * 0.22 * v * v;
		float lick = _fbm(vec2(x * 4.0 + seed, v * 3.2 - t * 2.4));
		float tear = _fbm(vec2(x * 9.0 - seed, v * 7.0 - t * 4.2));
		float px = x - sway + (lick - 0.5) * 0.3 * v;

		// Teardrop: round at the base, tapering to a point.
		// A first version at 0.34 with a 1.15 taper was a thin, near-white jet,
		// a candle rather than a torch. Wider, and hotter only at its heart.
		// The width itself wavers with the noise, which splits the upper half
		// into separate tongues instead of one smooth teardrop.
		float radius = 0.46 * sqrt(clamp(v / 0.22, 0.0, 1.0)) * pow(1.0 - v, 1.1)
			* (0.65 + 0.7 * lick);
		float body = 1.0 - smoothstep(radius * 0.45, radius, abs(px));
		float heat = body * (1.0 - v * 0.62);
		heat -= (tear - 0.45) * 1.15 * v;
		heat *= smoothstep(0.0, 0.05, v);
		// The tongues ran on to the top of the card still bright and stopped
		// in a straight line there. They burn out over the top of it instead,
		// at a height the rising noise keeps moving, so the tip thins and
		// cools through the ember reds to nothing rather than being cut.
		float burnout = 0.58 + 0.2 * _fbm(vec2(x * 3.0 + seed * 3.1, t * 0.9));
		heat *= 1.0 - smoothstep(burnout, 0.96, v);
		heat = clamp(heat, 0.0, 1.0);

		ALBEDO = mix(_fire(heat), _ice(heat), chill) * heat * brightness * intensity;
	}
}
