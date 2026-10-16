// The sewer's one stone (sewer.gd): every wall, vault, dome, walkway and channel
// is drawn with this, so nothing anywhere meets anything else at a seam.
//
// The Higgsfield brick (tools/build_sewer_texture.py) is mapped in WORLD space on
// all three axes, and over it, all driven by world-space masks:
//   black mold    -- the Higgsfield mold colonies, laid where a low-frequency
//                    noise, the lower walls, vertical damp streaks and the vault's
//                    crown say they grow;
//   a sludge line -- the wall's foot, where the muck rises and dries, wet;
//   sludge        -- the Higgsfield muck over the walkways, glistening;
//   slime         -- the channel below the walkways, wet through.
// `floor_y` is the walkways' height; heights below are relative to it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D brick_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mold_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sludge_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sludge_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform float floor_y = -12.0;
// Repeats per metre.
uniform float brick_scale = 0.34;
uniform float mold_scale = 0.3;
uniform float sludge_scale = 0.42;
uniform vec3 brick_tint : source_color = vec3(1.0, 0.95, 0.9);
uniform vec3 mold_dark : source_color = vec3(0.012, 0.014, 0.01);
uniform vec3 slime_colour : source_color = vec3(0.035, 0.04, 0.022);
uniform float normal_depth = 0.9;
uniform float brick_ease = 0.4;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Triplanar weights, sharp, so a curved vault blends projections over a narrow band.
vec3 weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(8.0));
	return w / (w.x + w.y + w.z);
}

// UVs for each projection, laid so that "up the image" is world up on walls and
// world +z on floors (the normal maps are green-up).
vec2 uv_x(vec3 p) { return vec2(p.z, -p.y); }
vec2 uv_y(vec3 p) { return vec2(p.x, -p.z); }
vec2 uv_z(vec3 p) { return vec2(p.x, -p.y); }

vec4 tri(sampler2D t, vec3 p, vec3 w, float s) {
	return texture(t, uv_x(p) * s) * w.x + texture(t, uv_y(p) * s) * w.y + texture(t, uv_z(p) * s) * w.z;
}

// (Its own function: a GLSL helper may only be handed samplers with the same hints.)
float tri_noise(vec3 p, vec3 w, float s) {
	return texture(noise_tex, uv_x(p) * s).r * w.x + texture(noise_tex, uv_y(p) * s).r * w.y
		+ texture(noise_tex, uv_z(p) * s).r * w.z;
}

// A tangent-space normal from a map's red and green (z rebuilt: the import may
// have packed it as two channels), its slope scaled by `depth`.
vec3 unpack(vec2 rg, float depth) {
	vec2 xy = rg * 2.0 - 1.0;
	return vec3(xy * depth, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Whiteout-blended triplanar normal mapping; returns a world normal.
vec3 tri_normal(sampler2D t, vec3 p, vec3 n, vec3 w, float s, float depth) {
	vec3 tx = unpack(texture(t, uv_x(p) * s).xy, depth);
	vec3 ty = unpack(texture(t, uv_y(p) * s).xy, depth);
	vec3 tz = unpack(texture(t, uv_z(p) * s).xy, depth);
	// uv_x = (z, -y): tangent x -> world z, green (image up) -> world +y.
	vec3 nx = vec3(abs(tx.z) * n.x, tx.y + n.y, tx.x + n.z);
	// uv_y = (x, -z): tangent x -> world x, green -> world +z.
	vec3 ny = vec3(ty.x + n.x, abs(ty.z) * n.y, ty.y + n.z);
	// uv_z = (x, -y): tangent x -> world x, green -> world +y.
	vec3 nz = vec3(tz.x + n.x, tz.y + n.y, abs(tz.z) * n.z);
	return normalize(nx * w.x + ny * w.y + nz * w.z);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = weights(n);
	float h = wpos.y - floor_y;
	float up = n.y;
	float wall = 1.0 - smoothstep(0.45, 0.75, abs(up));

	vec3 brick = tri(brick_albedo, wpos, w, brick_scale).rgb;
	// The generated brick is speckled; in faint light only its brightest specks
	// caught, and the walls read as glitter. Its contrast is eased toward its own
	// mean colour (bricks and mortar still read).
	brick = mix(brick, vec3(0.17, 0.15, 0.13), brick_ease) * brick_tint;
	// Grime: the brick itself darkens in broad, uneven patches.
	float big = tri_noise(wpos, w, 0.07);
	float fine = tri_noise(wpos, w, 0.55);
	brick *= mix(0.6, 1.05, smoothstep(0.25, 0.75, big * 0.7 + fine * 0.3));

	// --- Black mold.
	// Damp runs down the walls in streaks: noise stretched tall.
	float streak = texture(noise_tex, vec2((wpos.x + wpos.z) * 0.9, wpos.y * 0.09)).r;
	float low = 1.0 - smoothstep(0.0, 1.8, h);
	float crown = smoothstep(2.8, 4.2, h);
	float cover = big * 1.25 - 0.45 + low * 0.5 + (streak - 0.45) * 0.7 * wall + crown * 0.25;
	vec4 mold = tri(mold_tex, wpos, w, mold_scale);
	// Thin cover shows the colonies; heavy cover is solid black growth.
	float m = clamp(mold.a * smoothstep(0.05, 0.55, cover) * 1.3 + smoothstep(0.55, 1.1, cover) * mix(0.25, 0.6, fine), 0.0, 1.0);
	m *= step(-0.02, h);
	vec3 col = mix(brick, mix(mold_dark, mold.rgb * 0.18, 0.35), m);

	// --- Sludge on the walkways.
	// Triplanar like the brick: projected from above it smeared down the wall's foot
	// and the channel's sides as vertical streaks.
	vec3 sludge = tri(sludge_tex, wpos, w, sludge_scale).rgb;
	float floorish = smoothstep(0.55, 0.85, up) * step(-0.05, h) * step(h, 0.3);
	float spread = smoothstep(0.2, 0.55, tri_noise(wpos + vec3(17.0), w, 0.12) + 0.2);
	float on_floor = floorish * spread;
	col = mix(col, sludge * 0.75, on_floor);

	// --- The sludge line at the foot of every wall, its top ragged.
	float line_top = 0.32 + 0.22 * fine + 0.12 * streak;
	float foot = wall * (1.0 - smoothstep(line_top - 0.12, line_top, h)) * step(-0.05, h);
	col = mix(col, sludge * 0.5 + slime_colour * 0.4, foot * 0.85);

	// --- The channel: slimed through, wet.
	float chan = 1.0 - smoothstep(-0.06, 0.0, h);
	col = mix(col, mix(slime_colour, sludge * 0.45, 0.5), chan * 0.9);

	ALBEDO = col;

	float wet = max(max(on_floor, foot), chan);
	float rough = mix(0.82, 0.2, wet);
	rough = mix(rough, 0.96, m * (1.0 - wet * 0.6));
	ROUGHNESS = rough;
	SPECULAR = mix(0.18, 0.6, wet);

	// Normals: brick everywhere, flattened where mold fills the joints, the muck's
	// own relief where it lies.
	vec3 nb = tri_normal(brick_normal, wpos, n, w, brick_scale, normal_depth * (1.0 - 0.6 * m));
	vec3 ns = tri_normal(sludge_normal, wpos, n, w, sludge_scale, 1.0);
	vec3 nw = normalize(mix(nb, ns, max(on_floor, foot * 0.6)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
