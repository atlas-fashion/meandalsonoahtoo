shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

// A thin health bar over an enemy's head, facing the camera. Opaque -- no
// blending, so a corridor full of them costs a few dozen pixels each and no
// sorting. Every enemy shares this one material; its three values are INSTANCE
// uniforms, set by scripts/enemy_health_bar.gd, all as fractions of max health:
//   shown   the red bar, which snaps down on damage and climbs on a gain
//   health  the true value: green from `shown` up to it while the red climbs
//   trail   orange from `health` up to it after damage, until it drains away

uniform vec4 back_color : source_color = vec4(0.05, 0.04, 0.04, 1.0);
uniform vec4 health_color : source_color = vec4(0.79, 0.16, 0.16, 1.0);
uniform vec4 trail_color : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform vec4 gain_color : source_color = vec4(0.42, 0.9, 0.48, 1.0);
// Fraction of the quad's height left as a dark rim.
uniform float rim = 0.22;

instance uniform float shown = 1.0;
instance uniform float health = 1.0;
instance uniform float trail = 1.0;

void vertex() {
	// Billboard: keep the node's position and scale, take the camera's rotation.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	mat4 face = mat4(
		INV_VIEW_MATRIX[0] * scale.x,
		INV_VIEW_MATRIX[1] * scale.y,
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * face;
}

void fragment() {
	vec2 px = fwidth(UV);
	// The rim: a dark outline all round, at least a pixel, so the bar reads
	// against bright stone as well as dark.
	float edge_y = max(rim * 0.5, px.y);
	// The same number of PIXELS at the ends as along the top and bottom.
	float edge_x = edge_y / max(px.y, 1e-6) * px.x;
	vec3 col = back_color.rgb;
	float x = (UV.x - edge_x) / max(1.0 - 2.0 * edge_x, 1e-4);
	bool inside = UV.y > edge_y && UV.y < 1.0 - edge_y && x >= 0.0 && x <= 1.0;
	if (inside) {
		if (x < shown) {
			col = health_color.rgb;
		} else if (x < health) {
			col = gain_color.rgb;
		} else if (x < trail) {
			col = trail_color.rgb;
		}
	}
	ALBEDO = col;
}
