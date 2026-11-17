shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
// The Owner's CAT-PROOF answer: a camera-facing ring that runs outward over a hexagon lattice.
// It belongs to the simulation layer, so it draws over the world instead of being hidden by it.

instance uniform float progress = 0.0;                                    // 0..1 over the life of the ripple
instance uniform vec4 tint : source_color = vec4(0.45, 0.95, 0.9, 1.0);

// 0 in the middle of a hexagon cell, 0.5 on its edge.
float hex_edge(vec2 uv, float cells) {
	const vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 p = uv * cells;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return max(dot(g, vec2(0.8660254, 0.5)), g.y);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float front = mix(0.12, 0.93, 1.0 - pow(1.0 - progress, 2.5));          // the ring eases outward
	float ring = 1.0 - smoothstep(0.0, 0.1, abs(r - front));
	float inside = 1.0 - smoothstep(front - 0.03, front, r);
	float lattice = smoothstep(0.4, 0.5, hex_edge(p, 4.5));
	float fade = 1.0 - smoothstep(0.5, 1.0, progress);
	float rim = 1.0 - smoothstep(0.9, 1.0, r);
	ALBEDO = tint.rgb * 2.2;
	ALPHA = (ring * 0.9 + inside * lattice * 0.6 + inside * 0.05) * fade * rim * tint.a;
}
