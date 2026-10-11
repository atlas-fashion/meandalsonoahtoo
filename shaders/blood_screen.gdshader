shader_type canvas_item;

// Low health (hud._update_blood): blood on the view that builds as health
// falls. `wound` 0 shows nothing; as it rises splatters creep in from the edges
// and corners, droplets spatter ahead of them, a few runs drip down from the
// top, and the rim of the view darkens, throbbing with a heartbeat near death.
//
// DARK blood, not bright red: this level is lit red and orange, and red at the
// rim vanishes into the torchlight (the damage marker learned that). Thick
// blood is near-black crimson, thin edges a deeper red, with a wet sheen.
// Static apart from the drips' length and the pulse, so it reads as blood ON
// the view, not as an effect.

uniform float wound : hint_range(0.0, 1.0) = 0.0;
// The heartbeat's envelope, 0..1, driven by the HUD at low health.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;
uniform float seed = 0.0;
// 0 while it is drawn once at load to compile, 1 after.
uniform float opacity = 1.0;

// Arithmetic hash (Dave Hoskins): fract(sin()) hashing reads as squares on the GPU.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float total = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 4; i++) {
		total += noise(p) * weight;
		p = turn * p * 2.07 + vec2(17.1, 3.7);
		weight *= 0.5;
	}
	return total / 0.9375;
}

// How far into the blood a point is: > 0 inside. Grows inward from the border
// with `w`, further at the corners, ragged with noise.
float field(vec2 uv, vec2 c, float w) {
	vec2 d = min(uv, 1.0 - uv);
	float border = min(d.x * aspect, d.y);
	float corner = length(c) / length(vec2(0.5 * aspect, 0.5));
	// Kept to the margins: at its worst it reaches a fifth of the screen
	// height in (at the corners, more), never across the view.
	float reach = mix(0.01, 0.2, w);
	float edge = 1.0 - border / reach + (corner - 0.72) * 1.4 * w;
	float n = fbm(c * 2.6 + seed);
	// Lobes: the mass breaks up into separate splats with gaps between, not
	// one smooth frame round the view.
	float blobs = fbm(c * 5.0 + seed + 13.0);
	return edge + (n - 0.5) * 0.9 + (blobs - 0.5) * 1.0;
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	c.x *= aspect;
	float w = wound;

	float f = field(uv, c, w);
	float blood = smoothstep(0.0, 0.06, f) * step(0.001, w);

	// Droplets flung just ahead of the main mass -- only near it, so the middle
	// of the view stays clear.
	float near = smoothstep(-0.45, -0.03, f);
	float drop = smoothstep(0.86, 0.89, noise(c * 34.0 + seed * 3.1)) * near;
	drop = max(drop, smoothstep(0.9, 0.93, noise(c * 71.0 + seed * 1.7)) * near * 0.7);

	// A few runs dripping down from the top edge, longer the worse it gets.
	float lanes = 11.0;
	float lx = uv.x * aspect * lanes;
	float lane = floor(lx);
	float live = step(0.75, hash(vec2(lane, seed + 7.0))) * smoothstep(0.5, 0.85, w);
	float run_len = (0.05 + 0.15 * hash(vec2(lane, seed))) * w;
	float run_x = 0.5 + (hash(vec2(lane, seed + 3.0)) - 0.5) * 0.6;
	float wid = mix(0.035, 0.09, hash(vec2(lane, seed + 5.0)));
	float across = abs(fract(lx) - run_x);
	float run = (1.0 - smoothstep(wid * 0.6, wid, across))
		* (1.0 - smoothstep(run_len * 0.8, run_len, uv.y)) * live;
	// A bead at the end of each run.
	float bead = (1.0 - smoothstep(wid * 0.9, wid * 1.5,
		length(vec2(across, (uv.y - run_len * 0.85) * lanes / aspect)))) * live;
	run = max(run, bead);

	float a = clamp(max(max(blood, drop), run), 0.0, 1.0);

	// Thick in the middle of a splat: near black; thin at its edge: deep red.
	float thick = smoothstep(0.0, 0.5, f);
	vec3 colour = mix(vec3(0.09, 0.002, 0.005), vec3(0.03, 0.0, 0.002), thick);
	colour = mix(colour, vec3(0.07, 0.0, 0.004), max(drop, run) * (1.0 - blood));
	// A wet sheen where the surface of the splat slopes toward the light.
	float e = 0.004;
	float slope = field(uv + vec2(e, -e), c + vec2(e * aspect, -e), w) - f;
	colour += vec3(0.3, 0.1, 0.09) * smoothstep(0.012, 0.03, slope) * blood * 0.2;

	// The rim closing in: darker, throbbing with the heart near the end.
	float corner = length(c) / length(vec2(0.5 * aspect, 0.5));
	float vig = smoothstep(0.6, 1.1, corner) * w * (0.15 + 0.15 * pulse * w);

	// Faint: a stain at the edge of the eye, not a curtain over the view. The
	// low-health signal is mostly the world losing its colour (player.gd
	// `_health_saturation`); this only hints at it.
	float alpha = clamp(a * mix(0.12, 0.35, w) + vig * (1.0 - a), 0.0, 1.0);
	vec3 outc = mix(vec3(0.03, 0.0, 0.0), colour, a / max(alpha, 0.0001));
	COLOR = vec4(outc, alpha * opacity);
}
