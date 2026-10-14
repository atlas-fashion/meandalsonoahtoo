shader_type particles;

// One water drop, start to finish, from its age (2026-10-14; scripts/damp.gd).
// The GPUParticles3D sits at a point on the underside of the vault with local
// coordinates, `amount` 1 and `lifetime` = the drip's period, so the drop:
//   - swells as a bead on the stone for `hang` seconds,
//   - lets go and falls under gravity the `fall` metres to the floor,
//     stretching with its speed,
//   - splashes: flattens into a disc on the floor for `splash` seconds,
//   - and is gone until the period comes round again.
// Done by hand rather than with a ParticleProcessMaterial: that one applies
// gravity from birth, so a bead could never hang before it falls, and its
// collision needs collision nodes on the floor.

uniform float fall = 4.8;
uniform float hang = 1.2;
uniform float splash = 0.14;
uniform float gravity = 9.8;
// Where in its period this drip starts, so neighbours do not drop together.
// (Not GPUParticles3D.preprocess: on an emitter that starts switched off, as
// these do until the player comes near, preprocess left it drawing nothing.)
uniform float phase = 0.0;

void start() {
	CUSTOM = vec4(0.0);
	// A small bead to begin with; process() takes it from here.
	TRANSFORM = mat4(vec4(0.35, 0.0, 0.0, 0.0), vec4(0.0, 0.35, 0.0, 0.0),
		vec4(0.0, 0.0, 0.35, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	VELOCITY = vec3(0.0);
}

void process() {
	CUSTOM.x += DELTA;
	float age = mod(CUSTOM.x + phase, LIFETIME);
	float drop_time = sqrt(2.0 * fall / gravity);
	vec3 pos = vec3(0.0);
	vec3 s = vec3(0.0);
	if (age < hang) {
		// The bead gathers, sagging a little as it grows.
		float k = age / hang;
		s = vec3(0.35 + 0.65 * k);
		s.y *= 1.0 + 0.6 * k * k;
		pos.y = -0.006 * k;
	} else if (age < hang + drop_time) {
		float t = age - hang;
		float speed = gravity * t;
		pos.y = -0.006 - 0.5 * gravity * t * t;
		// Thinner and drawn out as it gathers speed.
		s = vec3(0.8, 1.0 + speed * 0.35, 0.8);
	} else if (age < hang + drop_time + splash) {
		float k = (age - hang - drop_time) / splash;
		pos.y = -fall + 0.003;
		// A flat splash spreading out and thinning away.
		s = vec3(1.4 + 4.0 * k, 0.15, 1.4 + 4.0 * k) * (1.0 - k * k);
	}
	TRANSFORM = mat4(vec4(s.x, 0.0, 0.0, 0.0), vec4(0.0, s.y, 0.0, 0.0),
		vec4(0.0, 0.0, s.z, 0.0), vec4(pos, 1.0));
	// Nothing to draw between drops.
	ACTIVE = true;
}
