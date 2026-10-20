shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Berserk (axe.gd): a ring of red fire burning on the floor round the player's
// feet. A flat plane GROUND_RADIUS across; `strength` 0..1 from
// `axe.berserk_amount()`. Two rings with a band of jagged runes between, a
// glow fading in toward the feet, all flickering. Additive, so where it is dark
// it costs nothing to look at, and it never darkens the floor.

uniform float strength : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float t = TIME;
	float outer = smoothstep(0.035, 0.0, abs(r - 0.92));
	float inner = smoothstep(0.025, 0.0, abs(r - 0.72));
	// Runes: 18 jagged marks round the band between the rings, each flaring on
	// its own beat.
	float seg = a / 6.2831853 * 18.0 + t * 0.35;
	float cell = floor(seg);
	float f = fract(seg);
	float mark = smoothstep(0.18, 0.05, abs(f - 0.5)) * smoothstep(0.1, 0.0, abs(r - 0.82 - (hash(vec2(cell, 3.0)) - 0.5) * 0.06));
	mark *= 0.55 + 0.45 * sin(t * 6.0 + cell * 1.7);
	float glow = (1.0 - smoothstep(0.0, 0.95, r)) * 0.22;
	float flicker = 0.85 + 0.15 * sin(t * 13.0 + r * 9.0);
	float k = (outer + inner * 0.8 + mark + glow) * flicker * strength;
	k *= 1.0 - smoothstep(0.96, 1.0, r);
	ALBEDO = vec3(1.0, 0.16, 0.05) * k * 2.2;
	ALPHA = clamp(k, 0.0, 1.0);
}
