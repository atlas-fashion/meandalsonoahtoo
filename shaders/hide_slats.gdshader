shader_type canvas_item;

// Shut in a hiding place (hiding_spot.gd). Inside a sarcophagus the view out
// is the real gap between its rim and its propped lid, so this is only the
// dark of the stone box closing in round the edges (`slat_amount` 0). With
// `slat_amount` 1 it is the louvred doors of the earlier wardrobe: dark slats
// across the screen with bright gaps, and a seam where the doors meet.

uniform float aspect = 1.777;
uniform float slat_amount : hint_range(0.0, 1.0) = 0.0;
uniform float slats = 11.0;
uniform float gap : hint_range(0.0, 1.0) = 0.5;
uniform vec4 wood : source_color = vec4(0.03, 0.025, 0.022, 1.0);
// 0 while it is drawn once at load to compile, 1 after.
uniform float opacity = 1.0;

void fragment() {
	vec2 uv = UV;
	float f = fract(uv.y * slats);
	float open = smoothstep(0.0, gap * 0.35, f) * (1.0 - smoothstep(gap * 0.65, gap, f));
	float slat = (1.0 - open) * slat_amount;
	float x = (uv.x - 0.5) * aspect;
	float seam = (1.0 - smoothstep(0.012, 0.03, abs(x))) * slat_amount;
	float frame = smoothstep(aspect * 0.5 - 0.22, aspect * 0.5 - 0.08, abs(x)) * slat_amount;
	// The dark of the box round the edges of the view.
	float vignette = smoothstep(0.3, 0.85, length(vec2(x * 0.75, uv.y - 0.5)));
	float cover = clamp(max(max(slat * 0.97, seam), frame) + vignette * 0.85, 0.0, 1.0);
	COLOR = vec4(wood.rgb, cover * opacity);
}
