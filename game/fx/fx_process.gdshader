shader_type particles;
render_mode disable_force;
// Shared process shader of every FxLayer. Particles are only ever born through
// GPUParticles3D.emit_particle(), which supplies position, velocity, colour and
// CUSTOM = (age s, lifetime s, size at birth m, size at death m).

uniform vec3 gravity = vec3(0.0, -9.8, 0.0);
uniform float drag = 0.0;        // 1/s
uniform float stretch = 0.0;     // extra length along the velocity, seconds (0 = round)
uniform float size_ease = 1.0;   // exponent of the size interpolation (< 1 grows fast, then slows)
uniform float wander = 0.0;      // m/s^2 of slow drift (smoke curl)


void write_basis(inout mat4 xf, vec3 vel, float size) {
	if (stretch > 0.0) {
		float speed = length(vel);
		vec3 y = speed > 0.001 ? vel / speed : vec3(0.0, 1.0, 0.0);
		vec3 x = normalize(cross(y, abs(y.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 z = cross(x, y);
		xf[0].xyz = x * size;
		xf[1].xyz = y * (size + speed * stretch);
		xf[2].xyz = z * size;
	} else {
		xf[0].xyz = vec3(size, 0.0, 0.0);
		xf[1].xyz = vec3(0.0, size, 0.0);
		xf[2].xyz = vec3(0.0, 0.0, size);
	}
}


void start() {
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0, 1.0, 0.1, 0.1);
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(0.0);
	}
	if (RESTART_COLOR) {
		COLOR = vec4(1.0);
	}
	write_basis(TRANSFORM, VELOCITY, CUSTOM.z);
}


void process() {
	CUSTOM.x += DELTA;
	float t = clamp(CUSTOM.x / max(CUSTOM.y, 0.001), 0.0, 1.0);
	if (CUSTOM.x >= CUSTOM.y) {
		ACTIVE = false;
	}
	vec3 acc = gravity;
	if (wander > 0.0) {
		float id = float(INDEX);
		float ph = CUSTOM.x * 1.7 + id * 12.9898;
		acc += wander * vec3(sin(ph), 0.35 * sin(ph * 1.31 + 2.0), cos(ph * 0.83 + id));
	}
	VELOCITY += acc * DELTA;
	VELOCITY /= 1.0 + drag * DELTA;
	write_basis(TRANSFORM, VELOCITY, mix(CUSTOM.z, CUSTOM.w, pow(t, size_ease)));
}
