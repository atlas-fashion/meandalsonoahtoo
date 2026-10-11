shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// The drowning court's water (puzzle_room.gd): near-black, glossy, a slow
// ripple in its normal, so it shows the red sky and the torches on its face.
uniform vec4 tint : source_color = vec4(0.015, 0.03, 0.035, 0.88);
uniform vec3 glint : source_color = vec3(0.0);

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;
	float t = TIME * 0.45;
	vec2 n = vec2(
		sin(p.x * 1.7 + t * 1.3) + 0.6 * sin(p.y * 2.3 - t * 1.1) + 0.3 * sin((p.x + p.y) * 4.1 + t * 2.0),
		cos(p.y * 1.9 + t) + 0.6 * cos(p.x * 2.7 - t * 1.4) + 0.3 * cos((p.x - p.y) * 3.7 - t * 1.7)) * 0.06;
	NORMAL = normalize((VIEW_MATRIX * vec4(n.x, 1.0, n.y, 0.0)).xyz);
	// Flat black it read as more floor: a sheen of the red sky at grazing
	// angles, broken up by the ripple, says water.
	// Kept faint: floating, the eye is a hand above the surface and nearly all
	// of it is grazing -- at 0.32 the whole court read as a flat red sheet.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	float ripple = 0.35 + 0.65 * smoothstep(0.2, 1.0, sin(p.x * 3.1 + p.y * 2.2 + t * 2.5));
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	EMISSION = glint + vec3(0.07, 0.016, 0.012) * fres * ripple;
	METALLIC = 0.0;
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
}
