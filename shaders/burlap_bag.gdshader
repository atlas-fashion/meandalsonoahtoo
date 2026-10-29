shader_type canvas_item;

// The sack over the player's head (note 128, boss_abduction.gd): coarse burlap
// a few centimetres from the eye, so out of focus. The weave is lit from
// outside -- `glow` is light passing by (torches on the way), `see` lets the
// world itself through the holes in the weave, blurred to nothing but light.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float see = 0.0;
uniform float glow = 0.0;
// The weave's sway as it moves with the head (screen units).
uniform vec2 drift = vec2(0.0);
uniform float aspect = 1.78;

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
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0) + drift;
	// The threads wander: a sack, not a grid.
	vec2 g = p * 38.0;
	g.x += (noise(g * vec2(0.08, 0.5)) - 0.5) * 0.9;
	g.y += (noise(g * vec2(0.5, 0.08) + 7.0) - 0.5) * 0.9;
	vec2 id = floor(g);
	vec2 c = fract(g) - 0.5;
	// Thread widths vary thread to thread; soft-edged, being out of focus.
	float wx = 0.30 + 0.12 * hash(vec2(id.y, 3.0));
	float wy = 0.30 + 0.12 * hash(vec2(id.x, 9.0));
	float tx = smoothstep(wx + 0.2, wx - 0.05, abs(c.y));
	float ty = smoothstep(wy + 0.2, wy - 0.05, abs(c.x));
	float thread = max(tx, ty);
	float hole = 1.0 - thread;
	// Fibres along each thread, and the odd slub.
	float fibre = noise(g * vec2(6.0, 0.7)) * tx + noise(g * vec2(0.7, 6.0)) * ty;
	float slub = noise(g * 0.13);
	// The world, blurred to light, through the holes.
	vec3 world = textureLod(screen, SCREEN_UV, 5.0).rgb;
	vec3 warm = vec3(1.0, 0.62, 0.3);
	vec3 outside = world * see * 1.6 + warm * glow;
	// Lit through from behind, the threads glow the cloth's own brown.
	vec3 cloth = vec3(0.30, 0.20, 0.11) * (0.25 + 0.75 * fibre) * (0.7 + 0.6 * slub);
	vec3 col = cloth * (0.14 + 1.4 * dot(outside, vec3(0.3, 0.5, 0.2))) + outside * hole * 0.8;
	// Darker toward the edges: the sack closes round the face.
	float r = length((UV - 0.5) * vec2(aspect, 1.0));
	col *= mix(1.0, 0.25, smoothstep(0.35, 1.0, r));
	COLOR = vec4(col, 1.0);
}
