shader_type canvas_item;

// Soft streaks racing past the edges of the view during a dash.
//
// Deliberately procedural: it never samples the screen texture, so it costs
// almost nothing on a weak card. A real radial blur would read the framebuffer
// dozens of times per pixel for an effect that is on screen for a fifth of a
// second. The node is hidden outright when strength is 0, so the rest of the
// time it costs nothing at all.

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.76, 0.86, 1.0, 1.0);
// Screen-space direction the world is sliding, so the streaks pile up on the
// side you are dashing away from. Zero for a straight-ahead dash, which then
// reads as an even tunnel.
uniform vec2 lean = vec2(0.0, 0.0);
uniform float aspect = 1.777;

void fragment() {
	vec2 uv = UV - 0.5;
	// Aspect-corrected, or the clear middle would be an oval on a wide screen.
	uv.x *= aspect;
	float r = length(uv);

	// Nothing anywhere near the crosshair, building only out at the rim. For
	// reference in this aspect-corrected space: 0 is the centre, 0.5 is the
	// top and bottom edges, 0.89 the left and right ones, ~1.02 the corners.
	// Starting at 0.42 leaves the whole middle of the view clean and puts the
	// weight on the sides and corners, where peripheral motion belongs.
	float edge = smoothstep(0.42, 0.78, r);

	// Two sets of radial spokes at unrelated frequencies, so it reads as
	// streaking rather than as a regular fan.
	float a = atan(uv.y, uv.x);
	float streak = pow(sin(a * 43.0) * 0.5 + 0.5, 3.0);
	streak = max(streak, pow(sin(a * 26.0 + 1.7) * 0.5 + 0.5, 4.0));

	float bias = 0.62 + 0.38 * dot(normalize(uv + vec2(1e-5)), lean);
	COLOR = vec4(tint.rgb, edge * streak * bias * strength * tint.a);
}
