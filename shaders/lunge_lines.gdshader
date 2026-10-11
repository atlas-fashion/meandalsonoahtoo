shader_type canvas_item;

// White speed lines rushing outward from the middle of the view as the thrust's
// lunge carries the player forward, with a soft white rim. Procedural like the
// dash streaks -- it never samples the screen -- and the node is hidden outright
// when `strength` is 0, so it costs nothing outside the half second it shows.

uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Seconds since the lunge, on the GAME clock (fed by the HUD), so slow motion
// slows the lines with everything else.
uniform float clock = 0.0;
uniform float aspect = 1.777;

float hash(float n) {
	return fract(sin(n * 127.1 + 3.7) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	// Aspect-corrected, so the lanes are evenly spread on a wide screen.
	uv.x *= aspect;
	float r = length(uv);
	float a = atan(uv.y, uv.x);

	// The view is cut into angular lanes; some of them carry a dash of light
	// that races from near the middle out past the edge of the screen.
	float lanes = 110.0;
	float f = (a / TAU + 0.5) * lanes;
	float lane = floor(f);
	float across = abs(fract(f) - 0.5) * 2.0;
	float h = hash(lane);
	// Thin lines, a little different in each lane.
	float line = 1.0 - smoothstep(0.08 + 0.1 * hash(lane + 5.3), 0.2 + 0.12 * hash(lane + 9.1), across);

	// Each dash starts somewhere along its lane and runs outward, fast.
	float run = h + clock * (2.4 + 2.2 * hash(lane + 2.9));
	float head = mix(0.12, 1.25, fract(run));
	float len = 0.12 + 0.3 * hash(lane + 7.0);
	// Bright at the head, fading back along its tail; sharp ahead of the head.
	float dash = smoothstep(head - len, head, r) * (1.0 - smoothstep(head, head + 0.015, r));
	float lit = step(0.45, hash(lane + 11.0));

	// Nothing over the crosshair; full strength from a third of the way out.
	float keep_clear = smoothstep(0.1, 0.32, r);
	float lines = line * dash * lit * keep_clear;

	// A soft white rim, the edges of the view washing out with the speed.
	float rim = smoothstep(0.5, 1.05, r) * 0.32;

	COLOR = vec4(1.0, 1.0, 1.0, clamp(lines * 0.9 + rim, 0.0, 1.0) * strength);
}
