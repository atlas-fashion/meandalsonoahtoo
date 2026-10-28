shader_type fog;

// The sewer's ground mist (note 121; scripts/sewer.gd `_build_mist`): one
// FogVolume per cell, from the water up past head height. Its density falls
// away with height over the water and is torn into drifting wisps by two
// octaves of 3D noise sampled in WORLD space, scrolling at different speeds and
// directions -- so neighbouring cells' boxes are one mist with no seams, and it
// rolls slowly along the pipes rather than sitting still.

uniform sampler3D noise : repeat_enable;
// Density at the water at its thickest (added to the air's own mist).
uniform float density = 0.9;
uniform vec3 albedo : source_color = vec3(0.76, 0.79, 0.76);
// World height of the water, and how fast the mist thins above it (metres to
// fall to 1/e).
uniform float water_y = -12.42;
uniform float thin = 0.75;
// A floor of mist that never thins away entirely, up to the vault.
uniform float haze = 0.035;
// Metres per repeat of the large and the small noise.
uniform float span = 7.0;
uniform float span_fine = 2.3;
uniform vec3 wind = vec3(0.16, 0.025, 0.07);

void fog() {
	float h = max(WORLD_POSITION.y - water_y, 0.0);
	float fall = exp(-h / thin);
	vec3 p = WORLD_POSITION / span + wind * TIME / span;
	vec3 q = WORLD_POSITION / span_fine - vec3(wind.z, -wind.y, wind.x) * 1.7 * TIME / span_fine;
	float n = texture(noise, p).r * 0.68 + texture(noise, q).r * 0.32;
	// Wisps: thick where the noise is high, clear lanes where it is low.
	float wisps = smoothstep(0.32, 0.78, n);
	// Fade in from the box's top and its bottom only; across the cells' shared
	// sides the boxes run into one another.
	float v = UVW.y;
	float edge = smoothstep(0.0, 0.08, v) * (1.0 - smoothstep(0.82, 1.0, v));
	DENSITY = (density * fall * wisps + haze * (0.4 + 0.6 * wisps)) * edge;
	ALBEDO = albedo;
}
