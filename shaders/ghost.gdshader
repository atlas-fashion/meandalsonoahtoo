shader_type spatial;
// The Shade: the big wandering ghost (scripts/stalker.gd).
//
// Translucent and unshaded -- it gives off its own pale light rather than being
// lit, so it reads in the darkest corridor, which is the point: the player has
// to be able to see it coming. A bright rim where the surface turns away from
// the eye, a faint body with slow wisps drifting up through it, and a ragged
// fade to nothing at the bottom, so it floats rather than stands.
//
// Drawn from both sides: the inside of a translucent body adds to its volume.
// One shader for the skeleton and the shroud; the shroud's material also sets
// `flutter`, which ripples its cloth.

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 body_color : source_color = vec4(0.56, 0.72, 0.92, 1.0);
uniform vec4 rim_color : source_color = vec4(0.86, 0.95, 1.0, 1.0);
uniform float body_alpha = 0.16;
uniform float rim_alpha = 0.8;
uniform float rim_power = 2.4;
uniform float fade_height = 1.3;
uniform float flutter = 0.0;
uniform float brightness = 1.0;

// Per instance (set by the script): where its bottom is in the world, how much
// it has brightened (winding up a blow, hunting), and how far a hit has flashed.
instance uniform float base_y = 0.0;
instance uniform float anger = 0.0;
instance uniform float flash = 0.0;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	if (flutter > 0.0) {
		// Cloth: more movement the further down the hem, slow and rolling.
		float hang = clamp(-VERTEX.y + 0.5, 0.0, 2.5);
		float wave = sin(TIME * 1.7 + VERTEX.y * 3.1 + VERTEX.x * 2.3)
			+ 0.6 * sin(TIME * 2.9 + VERTEX.z * 4.0);
		VERTEX += NORMAL * wave * flutter * hang;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - clamp(facing, 0.0, 1.0), rim_power);

	// Wisps drifting upward through the body.
	float n = noise(world_pos * vec3(2.0, 1.4, 2.0) + vec3(0.0, -TIME * 0.9, 0.0));
	n = 0.65 * n + 0.35 * noise(world_pos * 4.3 + vec3(TIME * 0.3, -TIME * 1.7, 0.0));
	float wisps = smoothstep(0.32, 0.85, n);

	// Ragged at the bottom: fades out over fade_height, unevenly.
	float hem = smoothstep(base_y, base_y + fade_height,
		world_pos.y + (n - 0.5) * 0.7);

	vec3 colour = mix(body_color.rgb, rim_color.rgb, rim);
	// Anger leans it colder and brighter; a hit flashes it white.
	colour = mix(colour, vec3(0.75, 0.9, 1.0), anger * 0.5);
	colour = mix(colour, vec3(1.0), flash);
	ALBEDO = colour * brightness * (0.75 + 0.55 * wisps) * (1.0 + 0.6 * anger);

	float alpha = body_alpha * (0.55 + 0.9 * wisps) + rim * rim_alpha;
	alpha *= 1.0 + 0.5 * anger;
	ALPHA = clamp((alpha + flash * 0.4) * hem, 0.0, 1.0);
}
