shader_type spatial;

// The surgery's three cables (scripts/surgery.gd): one MultiMesh of short
// sheath sections per cable. Each section's INSTANCE_CUSTOM is its glow:
// r = how much, gba = the colour -- the core's pulses running out along the
// core cable, the warm flare of the arms' and legs' cables feeding it back.

uniform vec4 sheath : source_color = vec4(0.045, 0.045, 0.05, 1.0);
uniform float energy = 3.0;

varying vec4 v_glow;

void vertex() {
	v_glow = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = sheath.rgb;
	ROUGHNESS = 0.62;
	METALLIC = 0.1;
	EMISSION = v_glow.gba * v_glow.r * energy;
}
