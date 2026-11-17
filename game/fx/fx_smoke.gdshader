shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled, diffuse_lambert_wrap;
// Smoke, steam and dust puffs: soft lit billboards with a sphere-like normal, eroding as they age.
// COLOR.rgb is the smoke colour, COLOR.a its peak opacity.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float soft_distance = 1.0;

varying vec4 v_color;
varying float v_t;
varying vec2 v_seed;
varying vec2 v_rot;


float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}


void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	float id = float(INSTANCE_ID);
	float rot = hash(id) * 6.2831853 + (hash(id + 3.0) - 0.5) * 0.9 * INSTANCE_CUSTOM.x;
	float c = cos(rot);
	float s = sin(rot);
	mat4 bb = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(c * size, -s * size, 0.0, 0.0), vec4(s * size, c * size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_color = COLOR;
	v_t = clamp(INSTANCE_CUSTOM.x / max(INSTANCE_CUSTOM.y, 0.001), 0.0, 1.0);
	v_seed = vec2(hash(id + 11.0), hash(id + 23.0));
	v_rot = vec2(c, s);
}


void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(p);
	float n = texture(noise_tex, UV * 0.6 + v_seed).r;
	float n2 = texture(noise_tex, UV * 1.7 + v_seed.yx + vec2(0.0, v_t * 0.1)).r;
	float edge = r + (n - 0.5) * 0.6 + (n2 - 0.5) * 0.25;
	float body = 1.0 - smoothstep(0.45, 0.95, edge);
	// Holes open up in the puff as it thins out.
	float erode = smoothstep(v_t * 0.9 - 0.25, v_t * 0.9 + 0.2, n2 * 0.6 + n * 0.4 + (1.0 - r) * 0.25);
	float fade = smoothstep(0.0, 0.08, v_t) * (1.0 - smoothstep(0.55, 1.0, v_t));
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene.xyz /= scene.w;
	float soft = clamp(1.0 - smoothstep(scene.z + soft_distance, scene.z, VERTEX.z), 0.0, 1.0);
	// View-space normal of a sphere impostor, turned with the roll of the billboard.
	vec2 q = vec2(p.x * v_rot.x + p.y * v_rot.y, -p.x * v_rot.y + p.y * v_rot.x);
	float z = sqrt(max(1.0 - min(dot(q, q), 1.0), 0.0));
	NORMAL = normalize(vec3(q * 0.85, z + 0.35));
	ALBEDO = v_color.rgb * (0.82 + 0.3 * n);
	ROUGHNESS = 1.0;
	BACKLIGHT = v_color.rgb * 0.35;
	ALPHA = body * erode * fade * soft * v_color.a;
}
