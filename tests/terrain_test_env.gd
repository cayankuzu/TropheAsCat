class_name TerrainTestEnv
extends RefCounted
## Sky, sun and post-processing for terrain screenshots and benchmarks (stand-in for the world module).


static func make_environment() -> WorldEnvironment:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = load("res://assets/sky/kloofendal_48d_partly_cloudy_puresky_4k.hdr")
	mat.energy_multiplier = 1.0
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.7, 0.82)
	env.fog_density = 0.00016
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	return we


static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, -38.0, 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	return sun
