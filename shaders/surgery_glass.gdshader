shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// The control room's leaded windows (surgery_control.gd `_glaze`, note 101):
// the Higgsfield leaded-glass picture (textures/surgery_glass.png) on one flat
// pane, its dark lead cames opaque and the pale quarries between them nearly
// clear. Mapped in metres off the pane's own plane, so the diamonds keep their
// size whatever the window is scaled to.

uniform sampler2D pic : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// The picture repeats this many times a metre, and the pane's scale (so the
// mapping is in metres, not in stretched model units).
uniform float tile = 1.1;
uniform vec2 scale = vec2(1.0, 1.0);
// The glass's own colour, and how much of it shows where it is clear.
uniform vec3 tint : source_color = vec3(0.62, 0.7, 0.64);
uniform float clear_alpha = 0.16;

varying vec2 plane;

void vertex() {
	plane = VERTEX.xy * scale;
}

void fragment() {
	vec3 c = texture(pic, plane * tile).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float lead = 1.0 - smoothstep(0.28, 0.5, l);
	ALBEDO = mix(tint * c, vec3(0.04, 0.04, 0.045), lead);
	ALPHA = mix(clear_alpha, 1.0, lead);
	METALLIC = 0.55 * lead;
	ROUGHNESS = mix(0.05, 0.5, lead);
	SPECULAR = 0.5;
}
