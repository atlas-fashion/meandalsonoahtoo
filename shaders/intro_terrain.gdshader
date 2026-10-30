shader_type spatial;

// The intro's forested hill (note 131; scripts/intro_world.gd). Forest floor
// (the project's ground texture, recoloured to needle litter), moss and grass
// in patches and in the clearing, packed dirt on the path, rock where it is
// steep. Vertex colour: r the path, g the clearing round the ruins.

uniform sampler2D ground_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_scale = 0.32;
uniform float rock_scale = 0.12;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz * ground_scale;
	vec3 g = texture(ground_tex, uv).rgb;
	float lum = dot(g, vec3(0.299, 0.587, 0.114));
	float big = texture(noise_tex, wpos.xz * 0.012).r;
	float mid = texture(noise_tex, wpos.xz * 0.06 + vec2(0.37)).r;

	// Needle litter: browns by the texture's own light and dark.
	vec3 litter = mix(vec3(0.11, 0.075, 0.05), vec3(0.4, 0.28, 0.16), smoothstep(0.03, 0.32, lum));
	litter *= mix(0.8, 1.1, mid);
	// Moss in broad patches, grass where the clearing is open to the sky.
	float clearing = COLOR.g;
	float moss_amt = smoothstep(0.45, 0.75, big * 0.7 + mid * 0.3) * 0.75;
	vec3 moss = mix(vec3(0.07, 0.13, 0.04), vec3(0.2, 0.3, 0.08), smoothstep(0.05, 0.35, lum));
	vec3 grass = mix(vec3(0.16, 0.22, 0.06), vec3(0.36, 0.42, 0.14), smoothstep(0.05, 0.4, lum)) * mix(0.85, 1.1, mid);
	vec3 col = mix(litter, moss, moss_amt);
	col = mix(col, grass, clamp(clearing * (0.65 + 0.35 * mid), 0.0, 1.0));

	// The path: packed, paler earth, its edges ragged.
	float path = smoothstep(0.25, 0.75, COLOR.r + (mid - 0.5) * 0.35);
	vec3 dirt = mix(vec3(0.2, 0.15, 0.1), vec3(0.42, 0.33, 0.22), smoothstep(0.05, 0.35, lum));
	col = mix(col, dirt, path);

	// Rock where it is steep (triplanar on the sides).
	vec3 n = normalize(wnrm);
	float steep = smoothstep(0.62, 0.45, n.y);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 r = texture(rock_tex, wpos.zy * rock_scale).rgb * w.x + texture(rock_tex, wpos.xz * rock_scale).rgb * w.y
		+ texture(rock_tex, wpos.xy * rock_scale).rgb * w.z;
	col = mix(col, r * vec3(0.75, 0.72, 0.68), steep);

	ALBEDO = col;
	NORMAL_MAP = texture(ground_nrm, uv).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.4, path);
	ROUGHNESS = mix(0.95, 0.85, path);
	SPECULAR = 0.25;
}
