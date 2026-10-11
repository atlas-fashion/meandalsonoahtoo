shader_type canvas_item;

// The Shade is near (hud._update_dread): pale frost creeping in from the edges
// of the view, a band that thickens the closer it is, brightest on the side it
// is on, pulsing with a heartbeat that quickens as it closes. While it HUNTS
// the player the very edge also darkens, closing the view in.
//
// Measured from the screen's BORDER, not its centre: a circle from the centre
// swallowed the sides of an ultrawide view long before it touched the top and
// bottom. Cold blue-white, because the level is lit red and orange (the damage
// marker learned that red at the rim vanishes into the torchlight here).
// Procedural, and hidden outright while the Shade is far away.

uniform float strength : hint_range(0.0, 1.0) = 0.0;
// 0 is dead ahead, positive to the right, radians.
uniform float bearing = 0.0;
uniform float hunted : hint_range(0.0, 1.0) = 0.0;
// The heartbeat's envelope, 0..1, driven by the HUD.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;
uniform float aspect = 1.777;
uniform vec4 frost_tint : source_color = vec4(0.72, 0.86, 1.0, 1.0);
// 0 while it is drawn once at load to compile, 1 after.
uniform float opacity = 1.0;

// Arithmetic hash (Dave Hoskins). The usual fract(sin(dot(...))) loses
// precision on large arguments on the GPU and came out as hard-edged squares.
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

// Three rotated octaves: plain value noise lines up with its grid and, behind
// a threshold, reads as squares.
float fbm(vec2 p) {
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float total = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 3; i++) {
		total += noise(p) * weight;
		p = turn * p * 2.03 + vec2(17.1, 3.7);
		weight *= 0.5;
	}
	return total / 0.875;
}

void fragment() {
	vec2 uv = UV;
	// Distance to the nearest edge of the screen, in screen heights.
	vec2 d = min(uv, 1.0 - uv);
	float border = min(d.x * aspect, d.y);

	vec2 c = uv - 0.5;
	c.x *= aspect;
	float a = atan(c.x, -c.y);
	float off = abs(a - bearing);
	off = min(off, 6.2831853 - off);
	float toward = 1.0 - smoothstep(0.3, 1.8, off);

	vec2 p = c * 4.5 + vec2(clock * 0.04, -clock * 0.025);
	float n = fbm(p);
	// The band of frost: a sliver at the edge from afar, about an eighth of the
	// screen height when it is on top of you, deeper on its side, and ragged.
	float band = mix(0.015, 0.12, strength) * (1.0 + 0.5 * toward) * (1.0 + 0.1 * pulse);
	float frost = 1.0 - smoothstep(band * 0.3, band, border + (n - 0.5) * band * 0.8);
	// Veins of brighter ice through it.
	float veins = smoothstep(0.6, 0.75, fbm(p * 2.3 + 5.0)) * frost;

	float frost_alpha = (frost * (0.28 + 0.25 * toward) + veins * 0.25)
		* smoothstep(0.0, 0.15, strength) * (0.8 + 0.3 * pulse);
	vec3 colour = mix(frost_tint.rgb, vec3(1.0), veins * 0.6 + toward * 0.15);

	// Hunted: the very edge goes dark, beating with the heart.
	float dark = (1.0 - smoothstep(0.0, 0.09 + 0.03 * pulse, border)) * hunted * (0.55 + 0.35 * pulse);
	float alpha = clamp(frost_alpha + dark, 0.0, 1.0);
	colour = mix(colour, vec3(0.0), dark / max(frost_alpha + dark, 0.0001));
	COLOR = vec4(colour, alpha * opacity);
}
