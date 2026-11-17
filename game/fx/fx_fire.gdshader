shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Flame puffs and flashes: additive billboards that run a fire ramp over their life
// (white-hot core, COLOR.rgb body, deep red tail). COLOR.a scales the brightness.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float energy = 3.0;
uniform float soft_distance = 0.6;

varying vec4 v_color;
varying float v_t;
varying vec2 v_seed;


float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}


void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	float id = float(INSTANCE_ID);
	float rot = hash(id) * 6.2831853 + (hash(id + 3.0) - 0.5) * 2.0 * INSTANCE_CUSTOM.x;
	float c = cos(rot);
	float s = sin(rot);
	mat4 bb = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(c * size, -s * size, 0.0, 0.0), vec4(s * size, c * size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_color = COLOR;
	v_t = clamp(INSTANCE_CUSTOM.x / max(INSTANCE_CUSTOM.y, 0.001), 0.0, 1.0);
	v_seed = vec2(hash(id + 11.0), hash(id + 23.0));
}


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = texture(noise_tex, UV * 0.7 + v_seed + vec2(0.0, v_t * 0.25)).r;
	// The puff erodes from the rim inward as it burns out.
	float rim = mix(0.95, 0.35, v_t);
	float body = 1.0 - smoothstep(rim * 0.35, rim, r + (n - 0.5) * 0.55);
	float fade = 1.0 - smoothstep(0.5, 1.0, v_t);
	float core = 1.0 - smoothstep(0.0, 0.55, r);
	vec3 col = mix(v_color.rgb, vec3(0.75, 0.12, 0.03), smoothstep(0.35, 1.0, v_t));
	col = mix(col, vec3(1.0, 0.95, 0.8), core * (1.0 - smoothstep(0.0, 0.4, v_t)) * 0.8);
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene.xyz /= scene.w;
	float soft = clamp(1.0 - smoothstep(scene.z + soft_distance, scene.z, VERTEX.z), 0.0, 1.0);
	ALBEDO = col * energy * v_color.a;
	ALPHA = body * fade * soft;
}
