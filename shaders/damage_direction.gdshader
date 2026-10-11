shader_type canvas_item;

// The "you were hit, and it came from there" marker.
//
// Written to be seen against a level that is already lit red. A soft red haze
// at the rim vanished completely into red torchlight and a maroon sky -- the
// earlier version was drawing correctly and was still invisible in play. So
// this leans on things the environment does not do: a hard-edged wedge, a
// near-white hot core, and a bright rim line, none of which the fog produces.
//
// Procedural throughout, and the node is hidden between hits, so it costs
// nothing the rest of the time.

uniform float strength : hint_range(0.0, 1.0) = 0.0;
// 0 is dead ahead, positive to your right, in radians.
uniform float bearing = 0.0;
// Half-width of the wedge, grown with the size of the hit.
uniform float spread : hint_range(0.05, 3.15) = 0.6;
uniform vec4 tint : source_color = vec4(1.0, 0.09, 0.07, 1.0);
// The hot centre of the wedge, which is what reads against red surroundings.
uniform vec4 core_tint : source_color = vec4(1.0, 0.72, 0.62, 1.0);
uniform float aspect = 1.777;
// How much of the whole rim lights regardless of direction, so a hit from
// behind still registers as "hit" before you work out where from.
uniform float halo : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= aspect;
	float r = length(uv);

	// A band around the rim. The middle stays clear: this fires exactly when
	// you most need to see what is in front of you.
	float edge = smoothstep(0.16, 0.46, r);

	// Angle measured the same way the bearing is: 0 is straight up the screen,
	// growing clockwise toward the right.
	float screen_angle = atan(uv.x, -uv.y);
	float off = abs(screen_angle - bearing);
	// Wrap, so a wedge pointing behind you does not tear at the seam.
	off = min(off, 6.2831853 - off);

	// Hard shoulder rather than a long fade, so it reads as a deliberate mark
	// rather than as more atmosphere.
	float wedge = 1.0 - smoothstep(spread * 0.55, spread, off);
	// A concentrated core down the middle of the wedge.
	float core = 1.0 - smoothstep(0.0, spread * 0.42, off);

	float shape = max(wedge, halo);
	vec3 colour = mix(tint.rgb, core_tint.rgb, core * 0.75);
	// The core also drives alpha above the wedge's own, giving the middle of
	// the mark real weight.
	float alpha = edge * max(shape, core * 1.15) * strength * tint.a;

	COLOR = vec4(colour, clamp(alpha, 0.0, 1.0));
}
