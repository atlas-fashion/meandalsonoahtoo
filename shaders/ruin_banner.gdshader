shader_type spatial;

// A tattered banner hanging in the Hall of Banners (ruin_dressing.gd, note 176):
// heavy wool gone dark with age, a faded gold border and device, the bottom
// torn ragged and holed (alpha cut), sagging and stirring a little in the
// draughts. One material for every banner; each one's colour, device and tear
// on instance uniforms.
//
// The mesh is a grid hanging from its top edge: UV (0,0) top left, (1,1) bottom
// right; the local frame x across, y up (the top at y = 0), z out of the wall.

render_mode cull_disabled;

instance uniform vec3 cloth : source_color = vec3(0.3, 0.04, 0.035);
instance uniform float device = 0.0;
instance uniform float tear_seed = 0.0;
instance uniform float length_m = 2.2;
// 1: a plain rag (the beacon halls' gallery cloths, note 180): no border, no device.
instance uniform float plain = 0.0;
uniform vec3 gold : source_color = vec3(0.62, 0.45, 0.16);
uniform float sway = 0.035;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Hangs from the top edge: the further down, the more it stirs and the
	// more it bellies out from the wall.
	float down = UV.y;
	float t = TIME * 0.45 + tear_seed * 10.0;
	float stir = sin(t + UV.x * 1.7) * 0.6 + sin(t * 1.9 + UV.y * 2.3) * 0.4;
	VERTEX.z += (sin(UV.x * 3.14159) * 0.05 + stir * sway) * down * down;
	VERTEX.x += sin(t * 0.7 + UV.y * 2.0) * sway * 0.35 * down;
}

// The device: one of three heraldic charges in a roundel.
float charge(vec2 p, float which) {
	// p: centred on the device, unit about its radius.
	float r = length(p);
	float ring = smoothstep(0.06, 0.0, abs(r - 0.9)) ;
	float shape = 0.0;
	if (which < 0.5) {
		// A sword, point down.
		float blade = step(abs(p.x), 0.09 - 0.07 * smoothstep(-0.2, -0.75, p.y)) * step(-0.78, p.y) * step(p.y, 0.45);
		float guard = step(abs(p.x), 0.38) * step(abs(p.y - 0.45), 0.06);
		float grip = step(abs(p.x), 0.05) * step(0.45, p.y) * step(p.y, 0.7);
		float pommel = step(length(p - vec2(0.0, 0.76)), 0.09);
		shape = max(max(blade, guard), max(grip, pommel));
	} else if (which < 1.5) {
		// A tower.
		float body = step(abs(p.x), 0.32) * step(-0.7, p.y) * step(p.y, 0.35);
		float crenels = step(abs(p.x), 0.42) * step(0.35, p.y) * step(p.y, 0.55) * step(0.5, fract(p.x * 3.6 + 0.5));
		float gate = step(length(p - vec2(0.0, -0.5)), 0.17) * step(p.y, -0.45);
		shape = max(body, crenels) * (1.0 - gate);
	} else {
		// A crowned skull's crown: three points.
		float band = step(abs(p.x), 0.5) * step(-0.25, p.y) * step(p.y, 0.0);
		float pts = step(abs(p.x), 0.5) * step(0.0, p.y) * step(p.y, 0.55 - abs(fract(p.x * 1.5 + 0.5) - 0.5) * 1.6);
		shape = max(band, pts);
	}
	return max(ring, shape);
}

void fragment() {
	vec2 uv = UV;
	vec2 m = vec2(uv.x, uv.y * length_m);
	// The weave and the grime.
	float weave = vnoise(m * vec2(140.0, 140.0)) * 0.5 + vnoise(m * vec2(70.0, 4.0)) * 0.5;
	float grime = fbm(m * 2.5 + tear_seed * 3.0);
	float soot = smoothstep(0.3, 1.0, uv.y) * 0.35 + smoothstep(0.55, 0.0, uv.y) * 0.15;

	// The torn bottom: a ragged edge eaten up into the cloth, and moth holes.
	float edge = 1.0 - uv.y;
	float rag = fbm(vec2(uv.x * 6.0 + tear_seed * 7.0, 0.5)) * 0.32 + fbm(vec2(uv.x * 23.0, tear_seed)) * 0.08;
	float keep = edge - rag * 0.75;
	// Long rips up from the bottom in two or three places.
	float rip = smoothstep(0.012, 0.0, abs(fract(uv.x * 2.7 + tear_seed) - 0.5) - 0.002) * smoothstep(0.55, 1.0, uv.y);
	float holes = smoothstep(0.78, 0.82, fbm(m * 7.0 + vec2(tear_seed * 13.0)));
	float side_fray = smoothstep(0.0, 0.025, min(uv.x, 1.0 - uv.x) + (fbm(vec2(uv.y * 30.0, tear_seed)) - 0.5) * 0.02);
	if (keep < 0.02 || rip > 0.5 || holes > 0.5 || side_fray < 0.5) {
		discard;
	}

	// Border and device in faded gold thread.
	float bd = min(uv.x, 1.0 - uv.x);
	float band = smoothstep(0.075, 0.07, bd) * smoothstep(0.045, 0.05, bd);
	float top_band = smoothstep(0.09 * 2.2 / length_m, 0.085 * 2.2 / length_m, uv.y) * smoothstep(0.05 * 2.2 / length_m, 0.055 * 2.2 / length_m, uv.y);
	vec2 dp = (vec2(uv.x, uv.y * length_m) - vec2(0.5, 0.75)) / 0.33;
	dp.y = -dp.y;
	float dev = charge(dp, device);
	float thread = max(max(band, top_band), dev) * (0.55 + 0.45 * smoothstep(0.35, 0.65, grime));
	thread *= 1.0 - plain;

	vec3 col = cloth * (0.75 + 0.5 * weave) * (1.0 - soot) * mix(0.75, 1.1, grime);
	col = mix(col, gold * (0.7 + 0.3 * weave), thread * 0.85);
	// Damp and dirt up from the ragged hem.
	col *= mix(1.0, 0.55, smoothstep(0.12, 0.0, keep));
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, thread);
	METALLIC = thread * 0.35;
	SPECULAR = 0.25;
	// Wool is lit through a little.
	BACKLIGHT = cloth * 0.25;
}
