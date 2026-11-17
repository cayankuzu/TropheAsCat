// Damage overlay for intact building elements, drawn as material_overlay on their MultiMeshes.
// INSTANCE_CUSTOM: r = damage 0..1, gba = impact point in the element's local frame (metres).
// Undamaged instances are collapsed in the vertex stage, so they cost no fragments.
// Output multiplies the lit surface (blend_mul): dark crack lines plus soot around the impact.
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

varying vec3 v_local;
varying vec4 v_damage;

void vertex() {
	v_local = VERTEX;
	v_damage = INSTANCE_CUSTOM;
	if (v_damage.r < 0.02) {
		VERTEX = vec3(0.0);
	}
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// Distance to the nearest Voronoi edge (F2 - F1), cheap enough for an overlay.
float voronoi_edge(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 b = vec3(float(i), float(j), float(k));
				vec3 r = b - f + hash3(p + b);
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	float dmg = clamp(v_damage.r, 0.0, 1.0);
	float dist = length(v_local - v_damage.gba);
	float reach = mix(0.35, 2.6, dmg);
	float fade = 1.0 - smoothstep(reach * 0.45, reach, dist);
	float big = 1.0 - smoothstep(0.0, 0.035 + 0.02 * dmg, voronoi_edge(v_local * 2.2));
	float fine = 1.0 - smoothstep(0.0, 0.03, voronoi_edge(v_local * 6.5 + vec3(3.7)));
	float crack = max(big, fine * smoothstep(0.35, 0.9, dmg)) * fade;
	float soot = dmg * 0.45 * (1.0 - smoothstep(0.0, reach * 0.8, dist));
	vec3 col = vec3(1.0) - vec3(0.82, 0.84, 0.86) * crack - vec3(soot);
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
}
