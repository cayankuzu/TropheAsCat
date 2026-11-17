shader_type spatial;
// Overlay for bodies held by the cat's telekinesis: an inflated back-face shell that only shows around
// the silhouette (a soft glowing outline), plus a faint pulse. Works for flat-faced props like crates.
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.42, 0.82, 1.0, 1.0);
uniform float intensity = 1.6;
uniform float shell = 0.035;

void vertex() {
	// Inflate radially from the object origin: hard-edged meshes (split normals) stay closed.
	VERTEX += normalize(VERTEX + vec3(1e-5)) * shell;
}

void fragment() {
	float pulse = 0.7 + 0.3 * sin(TIME * 5.5);
	// Back faces of the shell: brighter where they turn edge-on (the outline), fading inward.
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = glow_color.rgb * intensity * pulse;
	ALPHA = clamp(0.25 + edge * 0.75, 0.0, 1.0);
}
