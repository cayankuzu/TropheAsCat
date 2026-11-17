shader_type spatial;
render_mode cull_back, shadows_disabled;
// Opaque wet droplets and bits (acid, slime, fur): small spheres stretched along their velocity by
// the process shader. COLOR.rgb is the albedo, COLOR.a the emission strength (0 = not glowing).

uniform float gloss = 0.85;

varying vec4 v_color;


void vertex() {
	v_color = COLOR;
}


void fragment() {
	ALBEDO = v_color.rgb;
	ROUGHNESS = 1.0 - gloss;
	SPECULAR = 0.7;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = v_color.rgb * v_color.a * (0.7 + rim * 1.3);
}
