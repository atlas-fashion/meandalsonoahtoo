// The roots' bark and their gold veins (note 176), shared by root_bark.gdshader
// (the roots grown over walls, pillars, arches and vaults) and root_tip.gdshader
// (the living tips that whip).
//
// The mesh is a swept tube (ruin_roots.gd): UV.x runs once round the tube, UV.y
// along it (one unit per BARK_V metres), UV2.x from 0 at the strand's root to 1
// at its tip, UV2.y a per-strand seed. COLOR.r shades the bark, COLOR.g scales
// the strand's gold. Everything is drawn here from noise -- no textures -- so
// one material serves every root in the level.
//
// The noise is periodic round the tube (the lattice wraps every `period` cells
// in x), so the seam where UV.x goes from 1 back to 0 never shows.

uniform vec3 bark_dark : source_color = vec3(0.045, 0.036, 0.03);
uniform vec3 bark_light : source_color = vec3(0.3, 0.245, 0.19);
uniform vec3 bark_moss : source_color = vec3(0.07, 0.075, 0.045);
uniform vec3 vein_colour : source_color = vec3(1.0, 0.66, 0.22);
uniform float vein_energy = 1.05;
uniform float vein_width = 0.11;
// How much of a strand's length carries gold at all (higher: fewer streaks).
uniform float vein_patch = 0.5;
uniform float bump = 2.2;

vec2 _rh(vec2 p, float period) {
	p.x = mod(p.x, period);
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

// Gradient noise in [-1, 1], periodic in x every `period` lattice cells.
float rnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(_rh(i, period), f);
	float b = dot(_rh(i + vec2(1.0, 0.0), period), f - vec2(1.0, 0.0));
	float c = dot(_rh(i + vec2(0.0, 1.0), period), f - vec2(0.0, 1.0));
	float d = dot(_rh(i + vec2(1.0, 1.0), period), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.6;
}

// Bark height in [0, 1]: long fibres (fine round the tube, long along it) over
// broad cracked plates.
float bark_height(vec2 uv, float seed) {
	vec2 p = vec2(uv.x * 7.0, uv.y * 0.9 + seed * 13.0);
	float plates = rnoise(p, 7.0);
	float fibre = rnoise(vec2(uv.x * 21.0, uv.y * 1.6 + plates * 0.35 + seed * 7.0), 21.0);
	float fine = rnoise(vec2(uv.x * 42.0, uv.y * 4.0 + seed * 3.0), 42.0);
	float ridge = 1.0 - abs(plates);
	return clamp(0.5 + 0.28 * fibre + 0.12 * fine + 0.22 * (ridge - 0.5), 0.0, 1.0);
}

// The gold: thin streaks in the bark's cracks, running along the strand and
// broken into lengths -- a few strokes round the tube, not rings of it.
float vein_mask(vec2 uv, float seed) {
	float wander = rnoise(vec2(uv.x * 2.0, uv.y * 0.5 + seed * 5.0), 2.0);
	float line = abs(rnoise(vec2(uv.x * 4.0 + wander * 0.45, uv.y * 0.3 + seed * 11.0), 4.0));
	float streak = 1.0 - smoothstep(vein_width * 0.3, vein_width, line);
	// Broken along its length into strokes.
	float dash = smoothstep(0.5, 0.62, rnoise(vec2(uv.x * 4.0, uv.y * 1.3 + seed * 3.0), 4.0) * 0.5 + 0.5);
	float patches = rnoise(vec2(uv.x * 2.0, uv.y * 0.22 + seed * 17.0), 2.0) * 0.5 + 0.5;
	return streak * dash * smoothstep(vein_patch, vein_patch + 0.16, patches);
}

// Writes the bark: albedo, roughness, a normal map from the height, and the
// gold. `glow` scales the gold (0 = dead), `rot` darkens and greys it.
void root_surface(vec2 uv, vec2 uv2, vec4 col, float glow, float rot, float time,
		out vec3 albedo, out float rough, out vec3 nmap, out vec3 emit) {
	float seed = uv2.y;
	float h = bark_height(uv, seed);
	float e = 0.012;
	float hx = bark_height(uv + vec2(e, 0.0), seed);
	float hy = bark_height(uv + vec2(0.0, e * 4.0), seed);
	vec2 grad = vec2(h - hx, h - hy) * vec2(1.0, 0.25) / e;
	nmap = normalize(vec3(grad * bump * 0.06, 1.0)) * 0.5 + 0.5;

	float moss = smoothstep(0.25, 0.75, rnoise(vec2(uv.x * 2.0, uv.y * 0.3 + seed * 9.0), 2.0) * 0.5 + 0.5);
	vec3 bark = mix(bark_dark, bark_light, smoothstep(0.32, 0.72, h));
	// Deep in the cracks it is nearly black.
	bark *= mix(0.35, 1.0, smoothstep(0.22, 0.5, h));
	bark = mix(bark, bark_moss, moss * 0.45);
	bark *= col.r;
	// Dead: drier, greyer, darker.
	vec3 grey = vec3(dot(bark, vec3(0.3, 0.5, 0.2)));
	bark = mix(bark, grey * vec3(0.95, 0.9, 0.85) * 0.8, rot);

	float v = vein_mask(uv, seed) * col.g;
	// A slow pulse travels down the root, so it reads as alive.
	float pulse = 0.72 + 0.28 * sin(uv.y * 1.7 - time * 1.4 + seed * 6.2831);
	emit = vein_colour * v * vein_energy * glow * pulse;
	// And the whole root very faintly warm with it, so it shows as a shape in the
	// dark between torches rather than as floating streaks.
	emit += vein_colour * 0.02 * col.g * glow;
	// The gold shows in the bark's colour too, dulled when the glow is gone.
	albedo = mix(bark, vein_colour * 0.32, v * mix(0.25, 0.55, clamp(glow, 0.0, 1.0)));
	rough = mix(0.86, 0.6, v);
}
