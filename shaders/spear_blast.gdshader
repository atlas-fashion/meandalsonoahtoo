shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// The thrown spear's fireball (scripts/spear.gd _blast_visual): a sphere that
// is hottest where it faces the camera and thins to nothing at its rim, broken
// up by rolling noise, so it reads as a burst of fire rather than a solid ball.
// `fade` 0 -> 1 burns it out from the edges inward.

instance uniform float fade = 0.0;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = noise(obj * 3.2 + vec3(0.0, -TIME * 2.5, 0.0)) * 0.6
		+ noise(obj * 7.5 + vec3(TIME * 1.3)) * 0.4;
	float heat = facing * facing * (0.45 + 0.75 * n) - fade * 0.9;
	float a = smoothstep(0.04, 0.45, heat);
	vec3 col = mix(vec3(0.85, 0.16, 0.03), vec3(1.0, 0.55, 0.16), smoothstep(0.15, 0.5, heat));
	col = mix(col, vec3(1.0, 0.92, 0.72), smoothstep(0.55, 0.9, heat));
	ALBEDO = col * a * 1.6;
	ALPHA = a;
}
