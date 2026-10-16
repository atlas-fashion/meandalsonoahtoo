// A firefly in the sewer (sewer.gd `_build_fireflies`): a soft glowing dot,
// camera-facing, added on. The particle's COLOR carries its blink (the process
// material's colour ramp) and its hue.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float glow = 3.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float core = smoothstep(0.35, 0.0, r);
	float halo = smoothstep(1.0, 0.0, r) * 0.25;
	ALBEDO = COLOR.rgb * (core + halo) * glow * COLOR.a;
}
