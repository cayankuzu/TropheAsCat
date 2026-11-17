shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Sparks and embers: a camera-facing streak along the particle Y axis (the process shader
// stretches it along the velocity). COLOR.rgb is HDR, COLOR.a scales the brightness.

varying vec4 v_color;
varying float v_t;


void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(normalize(axis), to_cam);
	float sl = length(side);
	side = sl > 0.001 ? side / sl : vec3(1.0, 0.0, 0.0);
	vec3 wp = centre + axis * VERTEX.y + side * (VERTEX.x * width);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
	v_color = COLOR;
	v_t = clamp(INSTANCE_CUSTOM.x / max(INSTANCE_CUSTOM.y, 0.001), 0.0, 1.0);
}


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float across = 1.0 - abs(p.x);
	float along = 1.0 - smoothstep(0.35, 1.0, abs(p.y));
	float shape = across * across * along;
	float fade = 1.0 - smoothstep(0.55, 1.0, v_t);
	// Sparks cool from white-hot through their colour as they age.
	vec3 hot = mix(vec3(1.0), v_color.rgb, smoothstep(0.0, 0.25, v_t));
	ALBEDO = hot * v_color.a;
	ALPHA = shape * fade;
}
