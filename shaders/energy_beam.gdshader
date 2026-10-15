// A beam of yellow energy from the prison's generator to a cell's lock
// (dungeon_room.gd `_build_beams`). Drawn on a unit cylinder (height 1, along
// +Y from the generator end at -0.5 to the lock at +0.5) that the node scales
// to the beam's length; additive, so it reads as light, not as a tube.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.78, 0.22);
uniform float energy = 2.6;

instance uniform float beam_length = 8.0;
instance uniform float power = 1.0;
instance uniform float seed = 0.0;

varying float along;

void vertex() {
	along = VERTEX.y + 0.5;
	// Pinned at both ends, the middle shivers a few centimetres.
	float pin = sin(along * PI);
	float k = along * beam_length;
	float t = TIME * 7.0 + seed * 13.0;
	VERTEX.x += pin * 0.035 * (sin(k * 1.7 + t) + 0.5 * sin(k * 4.3 - t * 1.6));
	VERTEX.z += pin * 0.035 * (cos(k * 1.3 - t * 1.2) + 0.5 * sin(k * 3.7 + t * 1.9));
}

void fragment() {
	// Bright down the middle of the beam, soft at its edges, whatever the angle.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 3.0);
	// Pulses running out from the generator toward the lock.
	float k = along * beam_length;
	float pulse = 0.55 + 0.45 * pow(0.5 + 0.5 * sin(k * 2.2 - TIME * 14.0 + seed * 5.0), 6.0);
	float hum = 0.85 + 0.15 * sin(TIME * 37.0 + seed * 3.0);
	// Fades in over the last few centimetres at each end, so it never ends on a cut.
	float ends = smoothstep(0.0, 0.25 / beam_length, along) * smoothstep(1.0, 1.0 - 0.25 / beam_length, along);
	float a = core * pulse * hum * ends * power;
	ALBEDO = colour * energy * a;
}
