shader_type sky;
// The sky of the Table: an HDRI panorama above the horizon and the Underneath (a calm dark void) below it.
// No TIME and no POSITION on purpose: either one makes Godot re-render the radiance map every frame.

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float pano_yaw = 0.0;                 // radians; turns the panorama so its sun sits over the scene's sun
uniform float sky_energy = 1.0;
uniform vec3 sky_tint : source_color = vec3(1.0);
uniform float highlight_clamp = 24.0;         // caps the HDRI sun so the radiance map has no fireflies
uniform vec3 hdri_sun_dir = vec3(0.0, 1.0, 0.0);   // world direction of the panorama's own sun (after pano_yaw)
uniform float hdri_sun_dim = 0.0;             // 0..1: how much of that hotspot is taken out
uniform vec3 horizon_tint : source_color = vec3(1.0, 0.78, 0.56);
uniform float horizon_strength = 0.5;         // warm band along the horizon
uniform float horizon_falloff = 5.0;
uniform float sun_glow = 0.35;                // warm scattering around the scene's sun
uniform float sun_disc = 1.0;                 // brightness of the drawn sun disc (background only)
uniform vec3 void_top : source_color = vec3(0.035, 0.06, 0.085);
uniform vec3 void_bottom : source_color = vec3(0.004, 0.007, 0.014);
uniform vec3 void_line : source_color = vec3(0.35, 0.85, 0.82);   // thin horizon line where the render ends
uniform float void_line_energy = 0.6;
uniform vec3 bounce_color : source_color = vec3(0.30, 0.27, 0.22);  // lower hemisphere as lighting sees it

const float TAU_F = 6.28318530718;

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec2 uv = vec2(fract(atan(d.x, -d.z) / TAU_F + 0.5 - pano_yaw / TAU_F), acos(clamp(max(d.y, 0.0), -1.0, 1.0)) / PI);
	vec3 col = min(texture(panorama, uv).rgb, vec3(highlight_clamp));
	col *= 1.0 - hdri_sun_dim * smoothstep(0.90, 0.995, dot(d, hdri_sun_dir));
	col *= sky_tint * sky_energy;

	float horizon = exp(-up * horizon_falloff);
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, horizon_tint * lum * 1.25, horizon * horizon_strength);
	if (LIGHT0_ENABLED) {
		float mu = max(dot(d, LIGHT0_DIRECTION), 0.0);
		vec3 warm = LIGHT0_COLOR * sky_energy;
		col += warm * sun_glow * (0.55 * pow(mu, 6.0) + 1.6 * pow(mu, 64.0)) * (0.35 + 0.65 * horizon);
		if (!AT_CUBEMAP_PASS) {
			float ang = acos(min(mu, 1.0));
			col += warm * sun_disc * 24.0 * (1.0 - smoothstep(0.011, 0.016, ang));
		}
	}

	if (AT_CUBEMAP_PASS) {
		// Ambient light and reflections see a soft ground bounce under the horizon, as if the Table went on.
		float down = clamp(-d.y, 0.0, 1.0);
		vec3 ground = bounce_color * sky_energy * mix(1.0, 0.55, down);
		COLOR = mix(ground, col, smoothstep(-0.06, 0.04, d.y));
	} else {
		float down = clamp(-d.y, 0.0, 1.0);
		vec3 v = mix(void_top, void_bottom, pow(down, 0.55));
		v += void_line * void_line_energy * exp(-abs(d.y + 0.004) * 520.0);
		COLOR = mix(v, col, smoothstep(-0.012, 0.004, d.y));
	}
}
