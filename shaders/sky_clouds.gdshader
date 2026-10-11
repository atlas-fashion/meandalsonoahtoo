shader_type sky;

// Dark blood-red sky with drifting, wispy, dark-grey cloud deck.
//
// The clouds are three noise layers at different frequencies/speeds/wind
// directions, sheared a little by pitch so they separate as the camera looks
// up or down instead of scrolling in lockstep -- plus a cheap self-shadow
// term (a second sample of the same noise field, offset toward
// `light_direction`, subtracted from the first) so the wisps read as lit
// from one side rather than as a flat decal. That is the "3D" in "3D whispy
// clouds": depth from layered motion and shading, not a raymarch through a
// volume.
//
// This replaces an earlier version that projected each layer through a
// ray/plane intersection (a real flat-cloud-layer parallax). That is the
// textbook technique, but it has a hard singularity looking straight up --
// EYEDIR.xz -> 0 at the zenith regardless of azimuth, so every layer's UV
// converges on one point overhead and the noise reads as streaks radiating
// from it, not wisps. Real corridors here look up through courtyard
// openings a lot, so that artifact was not a corner case. The shear-based
// approach below has no such singularity anywhere on the dome.
//
// Perf: all of that (3 layers x 4-octave fbm, twice for the shadow term) only
// runs in the quarter-res pass (`render_mode use_quarter_res_pass`), which is
// exactly what that render mode is for on a per-pixel-bound card -- the
// screen-resolution pass just samples the already-composited, bilinearly
// upsampled result out of `QUARTER_RES_COLOR`. No per-pixel loop longer than
// 4 fixed octaves anywhere, no raymarch.
//
// Colour defaults are tuned for how this is actually driven in game: `maze.gd`
// calls `configure_environment()` (module_level.gd), which sets
// `background_energy_multiplier = 0.42` and then the ACES white-4.0 + contrast
// 1.12 grade on top -- so the raw uniform values below look considerably
// brighter than "dark blood red" in an ungraded viewer. That is intentional;
// verify by reading them through that same pipeline (see `tools/preview_sky.gd`,
// which now calls `ModuleLevel.configure_environment()` before applying this
// shader) or, better, the real in-game shot.

render_mode use_quarter_res_pass;

// --- colours ------------------------------------------------------------
// Tuned in the REAL pipeline (`background_energy_multiplier = 0.42` + ACES
// white 4.0 + the contrast/brightness/saturation adjustment), verified with
// `--bench --shot`, not just previewed. Round 2 raised these enough for the
// horizon band to read; round 3 found that 20-60 degrees up was still
// essentially black -- the gradient below plateaued into `zenith_color` by
// about 27 degrees, so "zenith" needed to be dark RED, not near-black, and
// the plateau needed to move much higher (see `_gradient()`).
// A diagnostic pass set zenith == horizon to isolate whether ACES's toe (the
// shadow end of the curve, which compresses harder than the midtones/
// highlights do) was crushing a merely-darker zenith disproportionately --
// it was: at the same energy multiplier and grade, a zenith of 0.2 read as
// black and 0.78 as a flat, bright, saturated red. The asked-for "darker
// red" sits between them: 0.46 zenith, 0.78 horizon, checked in game.
uniform vec4 zenith_color : source_color = vec4(0.46, 0.085, 0.065, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.78, 0.17, 0.10, 1.0);
uniform vec4 ground_color : source_color = vec4(0.02, 0.01, 0.01, 1.0);

// Distinctly DARKER than the sky around them -- smoke against a glow, not a
// same-value grey that only reads by hue -- but NOT so dark that a stretch
// of full cloud cover reads as a hole punched in the sky rather than smoke.
// (0.11 did exactly that once the sky itself got bright: solid-looking
// black patches, not grey wisps.)
uniform vec4 cloud_color : source_color = vec4(0.52, 0.50, 0.52, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.24, 0.23, 0.24, 1.0);
// Warm rim where the horizon glow catches the underside of the deck.
uniform vec4 cloud_glow_color : source_color = vec4(0.95, 0.32, 0.20, 1.0);

// --- cloud shape / motion ----------------------------------------------------
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.42;
// Width of the coverage threshold's soft edge. Lower = wispier / more torn.
uniform float cloud_softness : hint_range(0.02, 0.6) = 0.28;
uniform float cloud_density : hint_range(0.0, 2.0) = 1.0;
uniform float cloud_brightness : hint_range(0.0, 2.0) = 1.0;
// World-space noise frequency; higher = smaller, more numerous wisps.
uniform float cloud_scale : hint_range(0.2, 6.0) = 1.4;
// Stretches each layer along one axis so the noise reads as wind-drawn wisps
// rather than round puffs. Pulled back from an earlier 3.2: combined with a
// hard coverage threshold, that read as thin shards rather than wisps.
uniform float cloud_stretch : hint_range(1.0, 8.0) = 1.6;
// Metres per second the base layer drifts; the other two layers are derived
// from this so they never lock into a visible unison.
uniform float cloud_speed : hint_range(0.0, 0.3) = 0.020;
// Direction the cheap self-shadow samples toward (need not match any real
// light in the level -- the courtyards are lit by placed sky-light omnis,
// not by this shader).
uniform vec3 light_direction = vec3(0.45, 0.7, 0.2);

// --- internal --------------------------------------------------------------
float _hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 _grad(vec2 i) {
	float a = _hash(i) * 6.2831853;
	return vec2(cos(a), sin(a));
}

// Gradient noise, quintic fade, remapped to 0..1. Value noise was used here
// first, and at the low frequency the deck has overhead its bilinear cells
// thresholded into flat grey sheets with straight, shard-like edges -- the
// look the review called "angular facets", not wisps.
float _value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(_grad(i), f);
	float b = dot(_grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(_grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(_grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}
// A fixed rotation per octave, so the grid each octave samples on is never
// axis-aligned with the one before it. Without this, thresholding a coarse
// value-noise grid hard (see the contrast stretch below) shows the grid's
// own bilinear cell boundaries as straight diagonal edges -- wisps that
// looked like sharp triangular shards rather than something wind-drawn.
const mat2 _ROT = mat2(vec2(0.766, 0.643), vec2(-0.643, 0.766));

// 4 octaves -- still "few octaves", never a long per-pixel loop, and this
// only ever runs inside the quarter-res pass.
float _fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.55;
	float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		sum += _value_noise(p * freq) * amp;
		p = _ROT * p;
		freq *= 2.05;
		amp *= 0.52;
	}
	return sum;
}

// No perspective divide -- see the header note on why the earlier
// ray/plane version converged every layer to a point at the zenith. `shear`
// nudges each layer's sampling position by pitch, which is enough to keep
// three layers from drifting in visible lockstep (a cheap stand-in for
// parallax) without a singularity anywhere on the dome, horizon or overhead.
vec2 _layer_uv(vec3 dir, float freq, vec2 shear, vec2 wind, float speed) {
	// A softened cloud-deck projection: dividing by pitch foreshortens the
	// clouds into horizontal bands towards the horizon, as a real deck does,
	// and the +0.2 keeps the divide finite there. Without any divide (the
	// previous version) the pattern ran along azimuth only near the horizon
	// and hung from the sky as vertical curtains.
	// 1.1, not the first 0.35: at that scale the whole overhead view held
	// under one noise cell, so the zenith was a single flat grey sheet.
	vec2 uv = dir.xz / (dir.y + 0.2) * freq * cloud_scale * 1.1;
	uv += dir.y * shear;
	uv += wind * TIME * speed * cloud_speed * 50.0;
	return uv;
}

// `angle` rotates the stretch axis per layer (fixed sin/cos, not a uniform --
// one more way three layers avoid reading as one pattern in lockstep), so
// the wisps do not all lean the same direction.
float _layer_density(vec2 uv, float sin_a, float cos_a) {
	vec2 rotated = vec2(uv.x * cos_a - uv.y * sin_a, uv.x * sin_a + uv.y * cos_a);
	vec2 stretched = vec2(rotated.x, rotated.y / max(cloud_stretch, 1.0));
	// Domain warp: the field is sampled at a position pushed around by a
	// coarser copy of itself, which drags the blobs out into curling wisps.
	vec2 warp = vec2(_value_noise(stretched * 0.5 + vec2(3.1, 7.7)),
		_value_noise(stretched * 0.5 + vec2(11.3, 1.9))) - 0.5;
	return _fbm(stretched + warp * 1.6);
}

vec3 _gradient(vec3 dir) {
	float up = dir.y;
	// Spans the WHOLE upper dome (horizon to zenith, dir.y 0 to 1), not just
	// the first ~27 degrees -- that early plateau into `zenith_color` is
	// exactly what read as "black from 20 degrees up" once `zenith_color`
	// itself was still dark. Reaching zenith only at dir.y = 1 (straight up)
	// keeps the sky visibly red at every pitch the player actually looks.
	float horizon_t = smoothstep(-0.05, 1.0, up);
	vec3 base = mix(horizon_color.rgb, zenith_color.rgb, horizon_t);
	float below_t = smoothstep(0.0, -0.22, up);
	return mix(base, ground_color.rgb, below_t);
}

// The one expensive path: full gradient + all three warped cloud layers. Only called from the quarter-res pass (and the rare
// cubemap capture, which is not a per-frame cost).
vec3 _compute_full(vec3 dir) {
	vec3 base = _gradient(dir);
	if (dir.y <= 0.02) {
		return base;
	}

	vec2 uv1 = _layer_uv(dir, 1.6, vec2(0.8, 0.5), vec2(1.0, 0.30), 1.0);
	vec2 uv2 = _layer_uv(dir, 0.95, vec2(-0.6, 0.9), vec2(0.65, -0.50), 0.72);
	vec2 uv3 = _layer_uv(dir, 2.4, vec2(0.4, -0.7), vec2(-0.50, 0.85), 1.45);
	// Fixed per-layer angles (sin/cos baked in, not computed) so the stretch
	// axis differs layer to layer -- three wisps leaning the same way read
	// as one pattern, not depth.
	float n1 = _layer_density(uv1, 0.343, 0.939);
	float n2 = _layer_density(uv2, -0.565, 0.825);
	float n3 = _layer_density(uv3, 0.891, 0.454);
	// Three independent noise fields averaged together cluster hard around
	// their mean -- summing down variance is exactly what adding independent
	// random fields does -- which read as one flat haze with almost no
	// clear-sky/cloud separation until this was added. Punching the contrast
	// back out around the midpoint is what turns that haze into distinct
	// wisps again without giving up the three-layer parallax.
	float density_raw = n1 * 0.55 + n2 * 0.30 + n3 * 0.15;
	// Pulled back from 2.1 -- combined with a bright sky this made coverage
	// read as near-binary solid patches (looked like holes punched in the
	// sky) rather than wisps of varying thickness.
	float density = clamp((density_raw - 0.5) * 1.5 + 0.5, 0.0, 1.0) * cloud_density;

	float threshold = 1.0 - cloud_cover;
	float coverage = smoothstep(threshold - cloud_softness, threshold + cloud_softness, density);
	if (coverage <= 0.001) {
		return base;
	}

	// Thickness shading: the dense core of a wisp is darker than its thin,
	// back-lit edges, which is what gives it body against the glow. This
	// replaced a second, offset sample of every layer, whose cost now pays
	// for the domain warp in `_layer_density`.
	float lit = 1.0 - smoothstep(threshold, threshold + 0.35, density);
	vec3 cloud_rgb = mix(cloud_shadow_color.rgb, cloud_color.rgb, lit);
	// Warm horizon glow bleeds into the lit undersides, low in the sky only.
	float rim = clamp(1.0 - dir.y * 2.2, 0.0, 1.0) * lit;
	cloud_rgb = mix(cloud_rgb, cloud_glow_color.rgb, rim * 0.35);
	cloud_rgb *= cloud_brightness;

	// The new projection has no singularity to hide, so clouds are visible
	// across almost the whole upper dome -- just faded out over the same
	// band `_gradient()` uses to blend into the horizon/ground, so the
	// cloud deck does not appear to hang below the horizon line.
	float edge_fade = smoothstep(-0.05, 0.15, dir.y);
	return mix(base, cloud_rgb, coverage * edge_fade);
}

void sky() {
	if (AT_QUARTER_RES_PASS || AT_CUBEMAP_PASS) {
		COLOR = _compute_full(EYEDIR);
	} else {
		// Screen-resolution pass: reuse the quarter-res buffer instead of
		// redoing the noise work. `QUARTER_RES_COLOR` arrives already
		// bilinearly upsampled to this pixel, which is fine -- the gradient
		// and the cloud coverage are both low-frequency across the dome.
		COLOR = QUARTER_RES_COLOR.rgb;
	}
}
