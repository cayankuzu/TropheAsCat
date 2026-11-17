// Strata ground shader for WorldTerrain (VoxelLodTerrain + Transvoxel).
// World-space triplanar PBR. The layer is chosen by depth below the ORIGINAL surface (shared heightmap),
// with noisy, height-blended boundaries. Mirrors TerrainStrata.layer_index_at() on the CPU.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ---- Voxel Tools 1.7 Transvoxel LOD transitions (verbatim from the extension's built-in shader) ----
uniform int u_transition_mask;

float get_transvoxel_secondary_factor(int idata) {
	int transition_mask = u_transition_mask & 0xff;
	int cell_border_mask = idata & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	int m = transition_mask & cell_border_mask;
	float t = float(m != 0);
	t *= float((vertex_border_mask & ~transition_mask) == 0);
	return t;
}

vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);
	float secondary_factor = get_transvoxel_secondary_factor(idata);
	vec3 secondary_position = fdata.xyz;
	vec3 pos = mix(vertex_pos, secondary_position, secondary_factor);
	int itransition = (idata >> 16) & 0xff;
	float transition_cull = float(itransition == 0 || (itransition & u_transition_mask) != 0);
	pos *= transition_cull;
	return pos;
}

// ---- Shared world data ----
uniform sampler2D u_height : filter_nearest, repeat_disable;      // FORMAT_RF, TerrainShape.heightmap()
uniform float u_hm_offset = 520.0;
uniform float u_hm_size = 1041.0;
uniform sampler2D u_mask : filter_linear, repeat_disable;         // R road, G sidewalk, B grass (1 m/px)
uniform float u_mask_size = 1024.0;
uniform sampler2D u_noise : filter_linear, repeat_enable;         // TerrainStrata.noise_image()
uniform float u_noise_tile = 160.0;
uniform float u_noise_fine = 6.0;

// ---- Materials ----
uniform sampler2DArray u_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray u_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D u_lava_emission : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 u_layer_a[11];   // tile_m, texture slot, normal strength, roughness multiplier
uniform vec4 u_layer_b[11];   // tint rgb, unused

// ---- Strata ----
uniform vec4 u_bound_depth = vec4(1.5, 8.0, 14.0, 20.0);
uniform vec3 u_bound_y = vec3(-38.0, -44.0, -47.0);
uniform float u_bound_amp[7];
uniform float u_bound_jit[7];
uniform vec3 u_skin = vec3(0.22, 0.16, 0.30);    // road, sidewalk, grass skin thickness
uniform float u_blend = 0.35;                     // half width of a strata boundary blend (m)
uniform float u_height_blend = 0.45;              // how much texture height shifts a boundary (m)
uniform float u_triplanar_sharpness = 5.0;

// ---- Look ----
uniform float u_lava_energy = 7.0;
uniform float u_lava_flow = 0.012;
uniform vec3 u_lava_heat_color : source_color = vec3(1.0, 0.33, 0.06);
uniform float u_underside_glow = 1.6;
uniform float u_far_start = 25.0;
uniform float u_far_end = 160.0;
uniform bool u_grid_markings = true;
// The rim (2026-11-17): within u_rim_width of the slab's edge the Table turns into the Owner's wireframe.
uniform float u_world_half = 512.0;
uniform float u_rim_width = 28.0;
uniform float u_rim_grid = 2.5;
uniform vec3 u_rim_color = vec3(0.45, 0.95, 0.88);
uniform int u_debug_view = 0;   // 1 = depth (r) / above-surface (g) / skin (b), 2 = surface mask
uniform float u_grid_period = 128.0;
uniform float u_road_half = 8.0;
uniform float u_sidewalk = 4.0;

// Layer ids (TerrainStrata enum)
const int GRASS = 0;
const int ASPHALT = 1;
const int PAVING = 2;
const int GRAVEL = 3;
const int SOIL = 4;
const int CLAY = 5;
const int SAND = 6;
const int ROCK = 7;
const int ROCK_DEEP = 8;
const int LAVA = 9;
const int BEDROCK = 10;

varying vec3 v_wpos;
varying vec3 v_wnormal;
varying float v_depth;

float hm_texel(ivec2 p) {
	ivec2 q = clamp(p, ivec2(0), ivec2(int(u_hm_size) - 1));
	return texelFetch(u_height, q, 0).r;
}

// Same bilinear as the voxel graph Image node and TerrainShape.height_at().
float surface_height(vec2 xz) {
	vec2 p = clamp(xz + vec2(u_hm_offset), vec2(0.0), vec2(u_hm_size - 1.001));
	ivec2 i0 = ivec2(floor(p));
	vec2 f = p - vec2(i0);
	float a = mix(hm_texel(i0), hm_texel(i0 + ivec2(1, 0)), f.x);
	float b = mix(hm_texel(i0 + ivec2(0, 1)), hm_texel(i0 + ivec2(1, 1)), f.x);
	return mix(a, b, f.y);
}

void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_depth = surface_height(v_wpos.xz) - v_wpos.y;
}

float boundary_offset(int i, vec2 xz) {
	float fi = float(i + 1);
	vec2 uv = xz / u_noise_tile + fract(vec2(0.173 * fi, 0.311 * fi));
	float large = texture(u_noise, uv).r;
	float fine = texture(u_noise, uv * u_noise_fine).b;
	return u_bound_amp[i] * (2.0 * large - 1.0) + u_bound_jit[i] * (2.0 * fine - 1.0);
}

float nominal_boundary(int i, float h) {
	if (i < 4) {
		return u_bound_depth[i];
	}
	return h - u_bound_y[i - 4];
}

// Painted markings for the default road grid (TerrainStrata.default_mask): centre dashes, edge lines,
// zebra crossings. Disabled when a custom surface mask is set.
float lane_paint(vec2 xz) {
	vec2 c = xz - round(xz / u_grid_period) * u_grid_period;
	vec2 a = abs(c);
	vec2 fw = max(fwidth(xz), vec2(1e-4));
	float hw = u_road_half;
	float clear = hw + u_sidewalk;                       // intersection box incl. sidewalks
	float along_z = step(a.x, hw) * step(clear + 6.0, a.y);   // road running along z, away from crossings
	float along_x = step(a.y, hw) * step(clear + 6.0, a.x);
	float centre_z = (1.0 - smoothstep(0.07, 0.07 + fw.x, a.x)) * step(fract(xz.y / 9.0), 0.42);
	float centre_x = (1.0 - smoothstep(0.07, 0.07 + fw.y, a.y)) * step(fract(xz.x / 9.0), 0.42);
	float edge_z = 1.0 - smoothstep(0.07, 0.07 + fw.x, abs(a.x - (hw - 0.65)));
	float edge_x = 1.0 - smoothstep(0.07, 0.07 + fw.y, abs(a.y - (hw - 0.65)));
	float paint = max((centre_z + edge_z) * along_z, (centre_x + edge_x) * along_x);
	// Zebra crossings just outside each intersection.
	float zebra_z = step(a.x, hw - 1.0) * step(clear + 0.8, a.y) * step(a.y, clear + 4.6) * step(fract(c.x / 1.1), 0.5);
	float zebra_x = step(a.y, hw - 1.0) * step(clear + 0.8, a.x) * step(a.x, clear + 4.6) * step(fract(c.y / 1.1), 0.5);
	// Stop lines.
	float stop_z = step(a.x, hw - 1.0) * step(c.x, 0.0) * (1.0 - smoothstep(0.2, 0.2 + fw.y, abs(a.y - (clear + 5.4))));
	float stop_x = step(a.y, hw - 1.0) * step(0.0, c.y) * (1.0 - smoothstep(0.2, 0.2 + fw.x, abs(a.x - (clear + 5.4))));
	return clamp(max(paint, max(max(zebra_z, zebra_x), max(stop_z, stop_x))), 0.0, 1.0);
}

// Painted bays of the car parks (surface mask alpha 0): 2.5 m bays in rows along x, two rows of 5 m back
// to back after a 6 m aisle, every 16 m in z (CityLayout.BAY_PERIOD). Lines fade where they get thinner
// than a pixel.
float bay_paint(vec2 xz) {
	vec2 fw = max(fwidth(xz), vec2(1e-4));
	float zz = mod(xz.y, 16.0);
	float rows = step(6.0, zz);
	float sx = abs(xz.x - round(xz.x / 2.5) * 2.5);
	float sep = (1.0 - smoothstep(0.06, 0.06 + fw.x, sx)) * rows;
	float mid = 1.0 - smoothstep(0.06, 0.06 + fw.y, abs(zz - 11.0));
	float fade = 1.0 - smoothstep(0.1, 0.35, max(fw.x, fw.y));
	return clamp(max(sep, mid), 0.0, 1.0) * mix(0.25, 1.0, fade);
}

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi cell border (F2 - F1), for crack patterns.
float voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(n + g) - f;
			float dd = dot(r, r);
			if (dd < f1) {
				f2 = f1;
				f1 = dd;
			} else if (dd < f2) {
				f2 = dd;
			}
		}
	}
	return sqrt(f2) - sqrt(f1);
}

struct Surf {
	vec3 albedo;
	vec3 normal;     // world space
	float rough;
	float ao;
	float height;
};

// Triplanar sample of one layer. tw = triplanar weights (zeroed below a threshold), g* = world-pos gradients.
Surf sample_layer(int L, vec3 P, vec3 N, vec3 tw, vec3 gx, vec3 gy, float far_k) {
	vec4 la = u_layer_a[L];
	float s = 1.0 / la.x;
	float slot = la.y;
	vec4 acc_a = vec4(0.0);
	vec4 acc_n = vec4(0.0);
	vec3 nrm = vec3(0.0);
	if (tw.x > 0.0) {
		vec2 uv = vec2(P.z, -P.y) * s;
		vec2 dx = vec2(gx.z, -gx.y) * s;
		vec2 dy = vec2(gy.z, -gy.y) * s;
		vec4 a = textureGrad(u_albedo, vec3(uv, slot), dx, dy);
		vec4 n = textureGrad(u_nrm, vec3(uv, slot), dx, dy);
		vec3 tn = vec3(n.xy * 2.0 - 1.0, 0.0);
		tn.xy *= la.z;
		tn.z = sqrt(max(1.0 - dot(tn.xy, tn.xy), 0.0));
		vec3 wn = vec3(tn.xy + N.zy, abs(tn.z) * N.x);
		nrm += wn.zyx * tw.x;
		acc_a += a * tw.x;
		acc_n += n * tw.x;
	}
	if (tw.y > 0.0) {
		vec2 uv = vec2(P.x, -P.z) * s;
		vec2 dx = vec2(gx.x, -gx.z) * s;
		vec2 dy = vec2(gy.x, -gy.z) * s;
		vec4 a = textureGrad(u_albedo, vec3(uv, slot), dx, dy);
		vec4 n = textureGrad(u_nrm, vec3(uv, slot), dx, dy);
		if (far_k > 0.0) {
			// Far away the top projection also reads a 5x larger repeat to hide tiling.
			vec2 uv2 = uv * 0.2 + vec2(0.37, 0.71);
			vec4 a2 = textureGrad(u_albedo, vec3(uv2, slot), dx * 0.2, dy * 0.2);
			a = mix(a, vec4(mix(a.rgb, a2.rgb, 0.5) * mix(1.0, (dot(a2.rgb, vec3(0.333)) + 0.2) / (dot(a.rgb, vec3(0.333)) + 0.2), 0.35), a.a), far_k);
		}
		vec3 tn = vec3(n.xy * 2.0 - 1.0, 0.0);
		tn.xy *= la.z * (1.0 - 0.5 * far_k);
		tn.z = sqrt(max(1.0 - dot(tn.xy, tn.xy), 0.0));
		vec3 wn = vec3(tn.xy + N.xz, abs(tn.z) * N.y);
		nrm += wn.xzy * tw.y;
		acc_a += a * tw.y;
		acc_n += n * tw.y;
	}
	if (tw.z > 0.0) {
		vec2 uv = vec2(P.x, -P.y) * s;
		vec2 dx = vec2(gx.x, -gx.y) * s;
		vec2 dy = vec2(gy.x, -gy.y) * s;
		vec4 a = textureGrad(u_albedo, vec3(uv, slot), dx, dy);
		vec4 n = textureGrad(u_nrm, vec3(uv, slot), dx, dy);
		vec3 tn = vec3(n.xy * 2.0 - 1.0, 0.0);
		tn.xy *= la.z;
		tn.z = sqrt(max(1.0 - dot(tn.xy, tn.xy), 0.0));
		vec3 wn = vec3(tn.xy + N.xy, abs(tn.z) * N.z);
		nrm += wn.xyz * tw.z;
		acc_a += a * tw.z;
		acc_n += n * tw.z;
	}
	Surf o;
	o.albedo = acc_a.rgb * u_layer_b[L].rgb;
	o.height = acc_a.a;
	o.normal = nrm;
	o.rough = clamp(acc_n.b * la.w, 0.04, 1.0);
	o.ao = acc_n.a;
	return o;
}

void fragment() {
	vec3 P = v_wpos;
	vec3 N = normalize(v_wnormal);
	float d = v_depth;
	float h = P.y + d;   // original surface height here
	vec3 gx = dFdx(P);
	vec3 gy = dFdy(P);
	float dist = length(VERTEX);
	float far_k = smoothstep(u_far_start, u_far_end, dist);

	vec3 tw = pow(abs(N), vec3(u_triplanar_sharpness));
	tw /= (tw.x + tw.y + tw.z);
	tw = max(tw - 0.04, vec3(0.0));
	tw /= (tw.x + tw.y + tw.z);

	// --- Surface mask (crisp edges from a 1 m mask) ---
	vec2 muv = (P.xz + vec2(u_mask_size * 0.5)) / u_mask_size;
	vec4 m_tex = texture(u_mask, muv);
	vec3 m_raw = m_tex.rgb;
	float m_bays = 1.0 - smoothstep(0.35, 0.65, m_tex.a);   // car park bays are painted where alpha is 0
	vec3 fw = max(fwidth(m_raw), vec3(0.02));
	vec3 m = smoothstep(vec3(0.5) - fw, vec3(0.5) + fw, m_raw);
	m /= max(m.r + m.g + m.b, 1e-4);
	bool paved = (m_raw.r + m_raw.g) >= 0.5;

	// --- Strata below the skin ---
	int seq_layer[8] = int[8](paved ? GRAVEL : SOIL, SOIL, CLAY, SAND, ROCK, ROCK_DEEP, LAVA, BEDROCK);
	int idx = 0;
	float near_b = 1e9;
	int near_i = 0;
	float b_lava_top = 0.0;
	float b_lava_bot = 0.0;
	for (int i = 0; i < 7; i++) {
		float b = nominal_boundary(i, h);
		float reach = u_bound_amp[i] + u_bound_jit[i] + u_blend + u_height_blend;
		if (abs(d - b) < reach + 2.5 || i >= 5) {
			b += boundary_offset(i, P.xz);
		}
		if (i == 5) b_lava_top = b;
		if (i == 6) b_lava_bot = b;
		if (d >= b) {
			idx = i + 1;
		}
		if (abs(d - b) < abs(d - near_b)) {
			near_b = b;
			near_i = i;
		}
	}
	int la_up = seq_layer[near_i];
	int la_dn = seq_layer[near_i + 1];
	float s_d = d - near_b;   // > 0 below the nearest boundary
	bool strata_blend = abs(s_d) < (u_blend + u_height_blend) && la_up != la_dn;

	// --- Skin (asphalt / paving / grass) ---
	int s1 = ASPHALT;
	int s2 = PAVING;
	float w1 = m.r;
	float w2 = m.g;
	if (m.b > m.r && m.b > m.g) {
		s1 = GRASS; w1 = m.b;
		if (m.r > m.g) { s2 = ASPHALT; w2 = m.r; } else { s2 = PAVING; w2 = m.g; }
	} else if (m.g > m.r) {
		s1 = PAVING; w1 = m.g;
		if (m.b > m.r) { s2 = GRASS; w2 = m.b; } else { s2 = ASPHALT; w2 = m.r; }
	} else if (m.b > m.g) {
		s2 = GRASS; w2 = m.b;
	}
	w2 = w2 / max(w1 + w2, 1e-4);
	// Coarse LOD meshes only approximate curved ground; widen the "original surface" band with distance.
	float tol = clamp(dist * 0.0016, 0.0, 1.6);
	float skin = dot(m, u_skin) + 0.04 * (texture(u_noise, P.xz / 23.0).g - 0.5) + tol;
	float skin_blend = mix(0.03, 0.12, m.b);
	float skin_w = 1.0 - smoothstep(skin - skin_blend - 0.08, skin + skin_blend, d);

	// Material above the original surface (crater rims, add_sphere mounds) is rubble, not grass/asphalt.
	float rubble_w = smoothstep(0.05 + tol, 0.35 + tol, -d);
	skin_w *= 1.0 - rubble_w;

	// --- Sample ---
	Surf acc;
	acc.albedo = vec3(0.0); acc.normal = vec3(0.0); acc.rough = 0.0; acc.ao = 0.0; acc.height = 0.0;
	float lava_w = 0.0;
	float bedrock_w = 0.0;

	if (rubble_w > 0.001) {
		// Loose ejecta: soil with some gravel; less contrast than either texture alone.
		Surf a = sample_layer(SOIL, P, N, tw, gx, gy, 0.0);
		Surf b = sample_layer(GRAVEL, P, N, tw, gx, gy, 0.0);
		float k = smoothstep(0.35, 0.75, texture(u_noise, P.xz / 9.0 + vec2(P.y * 0.03)).b) * 0.45;
		vec3 dirt = a.albedo * vec3(0.92, 0.86, 0.8);
		vec3 grit = b.albedo * vec3(0.62, 0.58, 0.55);
		acc.albedo += mix(dirt, grit, k) * rubble_w;
		acc.normal += mix(a.normal, b.normal, k) * rubble_w;
		acc.rough += mix(a.rough, b.rough, k) * rubble_w;
		acc.ao += mix(a.ao, b.ao, k) * rubble_w;
	}

	float under_w = (1.0 - skin_w) * (1.0 - rubble_w);
	if (under_w > 0.001) {
		Surf a = sample_layer(strata_blend ? la_up : seq_layer[idx], P, N, tw, gx, gy, 0.0);
		float t_dn = 0.0;
		Surf b = a;
		if (strata_blend) {
			b = sample_layer(la_dn, P, N, tw, gx, gy, 0.0);
			t_dn = smoothstep(-u_blend, u_blend, s_d + (b.height - a.height) * u_height_blend);
		}
		float wa = under_w * (1.0 - t_dn);
		float wb = under_w * t_dn;
		acc.albedo += a.albedo * wa; acc.normal += a.normal * wa; acc.rough += a.rough * wa; acc.ao += a.ao * wa;
		int lay_a = strata_blend ? la_up : seq_layer[idx];
		if (lay_a == LAVA) lava_w += wa;
		if (lay_a == BEDROCK) bedrock_w += wa;
		if (wb > 0.0) {
			acc.albedo += b.albedo * wb; acc.normal += b.normal * wb; acc.rough += b.rough * wb; acc.ao += b.ao * wb;
			if (la_dn == LAVA) lava_w += wb;
			if (la_dn == BEDROCK) bedrock_w += wb;
		}
		// Bedding planes: faint wavy bands inside the thick sedimentary layers.
		int lay_main = seq_layer[idx];
		float period = lay_main == ROCK ? 2.6 : (lay_main == ROCK_DEEP ? 1.7 : (lay_main == SAND ? 0.7 : (lay_main == CLAY ? 1.1 : 0.0)));
		if (period > 0.0) {
			float wob = texture(u_noise, P.xz / 53.0 + vec2(0.3, 0.1)).r * 2.2 + texture(u_noise, P.xz / 11.0).b * 0.5;
			float bed = 0.7 * sin((d + wob) * 6.2831 / period) + 0.3 * sin((d + wob * 0.7) * 6.2831 / (period * 0.37));
			float amp = lay_main == ROCK ? 0.16 : 0.1;
			if (lay_main == ROCK) {
				bed += 0.8 * sin((d + wob * 2.5) * 6.2831 / 7.5);   // coarse beds that still read from far away
			}
			acc.albedo *= 1.0 + under_w * amp * bed;
		}
	}
	if (skin_w > 0.001) {
		Surf a = sample_layer(s1, P, N, tw, gx, gy, far_k);
		float wa = skin_w * (1.0 - w2);
		float wb = skin_w * w2;
		if (wb > 0.01) {
			Surf b = sample_layer(s2, P, N, tw, gx, gy, far_k);
			acc.albedo += b.albedo * wb; acc.normal += b.normal * wb; acc.rough += b.rough * wb; acc.ao += b.ao * wb;
		} else {
			wa = skin_w;
		}
		acc.albedo += a.albedo * wa; acc.normal += a.normal * wa; acc.rough += a.rough * wa; acc.ao += a.ao * wa;

		// Macro variation at non-repeating scales (lawns: lush / dry / dark patches; asphalt: wear).
		float n1 = texture(u_noise, P.xz / 263.0 + vec2(0.13, 0.57)).a;
		float n2 = texture(u_noise, P.xz / 71.0 + vec2(0.61, 0.29)).g;
		float n3 = texture(u_noise, P.xz / 19.0 + vec2(0.37, 0.83)).b;
		float lawn = m.b * skin_w;
		vec3 g = acc.albedo;
		float lum = dot(g, vec3(0.3, 0.55, 0.15));
		g = mix(vec3(lum), g, 0.78);                                     // ambientCG grass is very saturated
		g *= mix(0.72, 1.12, n1) * mix(0.88, 1.08, n2) * mix(0.94, 1.05, n3);
		vec3 dry = vec3(0.66, 0.6, 0.38) * lum * 2.4;
		vec3 lush = g * vec3(0.82, 0.98, 0.88);
		g = mix(g, lush, smoothstep(0.55, 0.8, n2) * 0.6);
		g = mix(g, dry, smoothstep(0.58, 0.82, n1 * 0.65 + n3 * 0.35) * 0.55);
		acc.albedo = mix(acc.albedo, g, lawn);
		float wear = mix(0.9, 1.08, n2) * mix(0.95, 1.04, n3);
		acc.albedo = mix(acc.albedo, acc.albedo * wear, m.r * skin_w);

		// Kerbs, gutters and (default grid only) lane markings.
		float kerb = (1.0 - smoothstep(0.03, 0.13, abs(m_raw.r - 0.5))) * step(0.2, m_raw.g) * skin_w;
		float gutter = smoothstep(0.5, 0.62, m_raw.r) * (1.0 - smoothstep(0.62, 0.9, m_raw.r)) * step(0.15, m_raw.g);
		acc.albedo *= 1.0 - 0.35 * gutter * skin_w;
		acc.albedo = mix(acc.albedo, vec3(0.56, 0.55, 0.52) * (0.9 + 0.2 * n3), kerb);
		acc.rough = mix(acc.rough, 0.85, kerb);
		if (u_grid_markings) {
			float paint = lane_paint(P.xz) * smoothstep(0.6, 0.9, m.r) * skin_w * mix(0.65, 1.0, n3);
			acc.albedo = mix(acc.albedo, vec3(0.78, 0.78, 0.74), paint);
			acc.rough = mix(acc.rough, 0.55, paint);
		}
		if (m_bays > 0.001) {
			float bays = bay_paint(P.xz) * m_bays * smoothstep(0.6, 0.9, m.r) * skin_w * mix(0.7, 1.0, n3);
			acc.albedo = mix(acc.albedo, vec3(0.8, 0.8, 0.76), bays);
			acc.rough = mix(acc.rough, 0.55, bays);
		}
	}

	vec3 n_world = normalize(acc.normal);
	vec3 albedo = acc.albedo;
	float rough = acc.rough;
	float ao = clamp(acc.ao, 0.0, 1.0);
	vec3 emission = vec3(0.0);

	// --- Magma: emissive, slowly flowing, pulsing; heat glow on the rock just above it ---
	if (lava_w > 0.001) {
		vec2 flow = vec2(TIME * u_lava_flow, TIME * u_lava_flow * 0.6);
		vec2 uvy = P.xz / 5.0;
		vec2 uvx = vec2(P.z, -P.y) / 5.0;
		vec2 uvz = vec2(P.x, -P.y) / 5.0;
		vec3 e1 = texture(u_lava_emission, uvy + flow).rgb * tw.y + texture(u_lava_emission, uvx + flow).rgb * tw.x + texture(u_lava_emission, uvz + flow).rgb * tw.z;
		vec3 e2 = texture(u_lava_emission, uvy * 0.37 - flow * 0.7 + 0.31).rgb;
		float pulse = 0.75 + 0.25 * sin(TIME * 0.9 + texture(u_noise, P.xz / 40.0 + TIME * 0.004).r * 12.0);
		vec3 e = (e1 * 0.75 + e2 * 0.45) * pulse;
		emission += e * u_lava_energy * lava_w;
		rough = mix(rough, 0.55, lava_w);
	}
	float heat = (1.0 - smoothstep(0.0, 2.5, b_lava_top - d)) * step(d, b_lava_top) * (1.0 - lava_w);
	emission += u_lava_heat_color * heat * heat * 0.6 * (0.6 + 0.4 * texture(u_noise, P.xz / 7.0).b);

	// --- Underside: cooled basalt crust with glowing cracks (two octaves of Voronoi seams) ---
	if (bedrock_w > 0.001) {
		vec2 q = tw.y >= max(tw.x, tw.z) ? P.xz : (tw.x > tw.z ? vec2(P.z, P.y) : vec2(P.x, P.y));
		q += (texture(u_noise, q / 37.0).rg - 0.5) * 6.0;
		float e1 = voronoi_edge(q / 13.0);
		float e2 = voronoi_edge(q / 4.1 + 7.3);
		// Constant crack width; once a crack is thinner than a pixel, dim it by its pixel coverage.
		float f1 = length(fwidth(q / 13.0));
		float f2 = length(fwidth(q / 4.1));
		float seam = (1.0 - smoothstep(0.0, 0.025 + f1, e1)) * (0.025 / (0.025 + f1))
				+ 0.5 * (1.0 - smoothstep(0.0, 0.03 + f2, e2)) * (0.03 / (0.03 + f2));
		float pulse = 0.8 + 0.2 * sin(TIME * 0.7 + q.x * 0.05 + q.y * 0.031);
		float near_magma = 1.0 - smoothstep(0.0, 0.8, d - b_lava_bot);
		emission += u_lava_heat_color * (seam * u_underside_glow * pulse + near_magma * 0.25) * bedrock_w;
		albedo *= mix(1.0, 0.4, clamp(seam, 0.0, 1.0) * bedrock_w);
	}

	// --- The rim: where the Table ends, the ground becomes a clean wireframe of the Owner's model ---
	float rim_d = u_world_half - max(abs(P.x), abs(P.z));
	if (rim_d < u_rim_width) {
		float rim_k = 1.0 - smoothstep(0.0, u_rim_width, rim_d);
		rim_k = rim_k * rim_k;
		// Only the ground turns to wireframe; the cut side of the slab keeps its strata under a faint grid.
		float top = smoothstep(0.35, 0.85, N.y);
		float side_k = rim_k * (1.0 - top);
		rim_k *= top;
		vec3 cell = abs(fract(P / u_rim_grid) - 0.5);
		vec3 cw = fwidth(P / u_rim_grid) * 1.2 + 0.015;
		vec3 on = 1.0 - smoothstep(vec3(0.0), cw, 0.5 - cell);
		// Lines of the two axes that lie in the surface (picked by the dominant normal axis).
		float line = tw.y >= max(tw.x, tw.z) ? max(on.x, on.z) : (tw.x > tw.z ? max(on.y, on.z) : max(on.x, on.y));
		float edge_line = 1.0 - smoothstep(0.0, 0.6, rim_d);
		float scan = 0.75 + 0.25 * sin(TIME * 1.3 - (P.x + P.z) * 0.05);
		albedo = mix(albedo, vec3(0.025, 0.04, 0.055), rim_k * 0.9);
		rough = mix(rough, 0.6, rim_k);
		emission += u_rim_color * (line * rim_k * 1.4 * scan + edge_line * top * 2.5 + line * side_k * 0.25);
	}

	if (u_debug_view == 1) {
		albedo = vec3(clamp(d / 48.0, 0.0, 1.0), clamp(-d * 4.0, 0.0, 1.0), skin_w);
		emission = albedo * 0.5;
	} else if (u_debug_view == 2) {
		albedo = m_raw;
		emission = albedo * 0.5;
	}
	ALBEDO = albedo * mix(1.0, ao, 0.5);
	ROUGHNESS = rough;
	SPECULAR = 0.45;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	EMISSION = emission;
}
