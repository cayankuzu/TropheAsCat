class_name WorldLook
extends Node3D
## The look of the Table ("the Owner's perfect home", docs/DESIGN.md section 2): HDRI sky over the dark
## Underneath, warm sun with cascaded shadows, aerial haze, SSAO / SSIL, glow, tonemapping and the one
## colour grade. Instance res://game/world/environment/world_look.tscn once in the world.
##
## GI decision (measured, see tests/out/environment_metrics.json and the module report): no SDFGI.
## Indirect light = sky radiance (its lower hemisphere is a warm ground bounce) + SSAO + SSIL.
## use_sdfgi stays as a comparison switch only.

signal quality_changed(level: int)
signal time_of_day_changed(preset: StringName)

enum Quality { LOW, MEDIUM, HIGH }

const SKY_SHADER := preload("res://game/world/environment/table_sky.gdshader")
const TIME_GOLDEN_HOUR := &"golden_hour"
const TIME_DUSK := &"dusk"

## Per time of day. Angles in degrees; azimuth 0 = -Z, 90 = +X (direction TOWARDS the sun).
## hdri_u / hdri_elev: where the panorama's own sun sits (measured from the files).
const TIMES := {
	&"golden_hour": {
		"panorama": "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_4k.hdr",
		"hdri_u": 0.5947, "hdri_elev": 47.8, "hdri_sun_dim": 0.55,
		"sun_azimuth": 52.0, "sun_elevation": 27.0,
		"sun_color": Color(1.0, 0.80, 0.58), "sun_energy": 2.3, "sun_angular": 0.7,
		"sky_energy": 0.9, "sky_tint": Color(0.93, 0.97, 1.06),
		"horizon_tint": Color(1.0, 0.76, 0.52), "horizon_strength": 0.5, "horizon_falloff": 5.0,
		"sun_glow": 0.32, "sun_disc": 1.0,
		"bounce": Color(0.34, 0.29, 0.22),
		"ambient_energy": 1.0,
		"fog_color": Color(0.98, 0.80, 0.62), "fog_density": 0.00055, "fog_aerial": 0.82, "fog_sun_scatter": 0.22,
		"exposure": 1.0, "glow_intensity": 0.55, "glow_bloom": 0.03,
		"saturation": 1.1,
	},
	&"dusk": {
		"panorama": "res://assets/sky/belfast_sunset_puresky_4k.hdr",
		"hdri_u": 0.6045, "hdri_elev": 2.1, "hdri_sun_dim": 0.0,
		"sun_azimuth": 66.0, "sun_elevation": 7.5,
		"sun_color": Color(1.0, 0.56, 0.36), "sun_energy": 1.35, "sun_angular": 1.4,
		"sky_energy": 0.36, "sky_tint": Color(0.86, 0.84, 1.12),
		"horizon_tint": Color(1.0, 0.62, 0.42), "horizon_strength": 0.3, "horizon_falloff": 7.0,
		"sun_glow": 0.2, "sun_disc": 0.6,
		"bounce": Color(0.20, 0.17, 0.19),
		"ambient_energy": 1.15,
		"fog_color": Color(0.80, 0.56, 0.60), "fog_density": 0.0009, "fog_aerial": 0.75, "fog_sun_scatter": 0.3,
		"exposure": 1.1, "glow_intensity": 0.8, "glow_bloom": 0.06,
		"saturation": 1.08,
	},
}

## Per quality level (index = Quality). Shadow distance in metres; "ssao" / "ssil" are RenderingServer
## quality enums (-1 = off); "msaa" / "aa" are Viewport enums; "detail" scales other modules' density.
const QUALITIES: Array[Dictionary] = [
	{   # LOW
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "shadow_distance": 110.0, "shadow_atlas": 2048,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "blend_splits": false,
		"ssao": RenderingServer.ENV_SSAO_QUALITY_LOW, "ssao_half": true,
		"ssil": -1, "msaa": Viewport.MSAA_DISABLED, "aa": Viewport.SCREEN_SPACE_AA_FXAA,
		"glow_bicubic": false, "lod_threshold": 2.0, "detail": 0.5,
	},
	{   # MEDIUM
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "shadow_distance": 200.0, "shadow_atlas": 4096,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "blend_splits": false,
		"ssao": RenderingServer.ENV_SSAO_QUALITY_MEDIUM, "ssao_half": true,
		"ssil": RenderingServer.ENV_SSIL_QUALITY_LOW, "msaa": Viewport.MSAA_DISABLED, "aa": Viewport.SCREEN_SPACE_AA_SMAA,
		"glow_bicubic": true, "lod_threshold": 1.0, "detail": 0.8,
	},
	{   # HIGH
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "shadow_distance": 280.0, "shadow_atlas": 8192,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH, "blend_splits": true,
		"ssao": RenderingServer.ENV_SSAO_QUALITY_HIGH, "ssao_half": false,
		"ssil": RenderingServer.ENV_SSIL_QUALITY_MEDIUM, "msaa": Viewport.MSAA_2X, "aa": Viewport.SCREEN_SPACE_AA_SMAA,
		"glow_bicubic": true, "lod_threshold": 1.0, "detail": 1.0,
	},
]

## Quality applied in _ready(); change it at runtime with set_quality().
@export_enum("Low", "Medium", "High") var initial_quality: int = Quality.HIGH
@export var initial_time: StringName = TIME_GOLDEN_HOUR
## Comparison switch only (see the GI decision above): adds SDFGI on top of the chosen quality.
@export var use_sdfgi := false:
	set(value):
		use_sdfgi = value
		if environment != null:
			_apply_gi()

var environment: Environment
var sun: DirectionalLight3D

var _quality := -1
var _time: StringName = &""
var _sky_material: ShaderMaterial
var _panoramas: Dictionary = {}   # path -> Texture2D


func _ready() -> void:
	add_to_group(&"world_look")
	var world_env := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		add_child(world_env)
	sun = get_node_or_null(^"Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	environment = Environment.new()
	world_env.environment = environment
	_build_static()
	set_time_of_day(initial_time)
	set_quality(initial_quality)


## Applies one of the three presets (Quality.LOW / MEDIUM / HIGH): shadow cascades and resolution, SSAO and
## SSIL quality, anti-aliasing and glow filtering. Other modules scale their own detail from
## quality_changed (or detail_scale()).
func set_quality(level: int) -> void:
	level = clampi(level, Quality.LOW, Quality.HIGH)
	_quality = level
	var q := QUALITIES[level]
	sun.directional_shadow_mode = q["shadow_mode"]
	sun.directional_shadow_max_distance = q["shadow_distance"]
	sun.directional_shadow_blend_splits = q["blend_splits"]
	if Game.lite:   # the browser demo: one short shadow pass around the camera
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 45.0
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow_atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q["shadow_filter"])
	RenderingServer.environment_set_ssao_quality(q["ssao"], q["ssao_half"], 0.5, 2, 50.0, 300.0)
	var ssil: int = q["ssil"]
	environment.ssil_enabled = ssil >= 0
	if ssil >= 0:
		RenderingServer.environment_set_ssil_quality(ssil, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_glow_set_use_bicubic_upscale(q["glow_bicubic"])
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = q["msaa"]
		vp.screen_space_aa = q["aa"]
		vp.use_taa = false
		vp.use_debanding = true
		vp.mesh_lod_threshold = q["lod_threshold"]
	_apply_gi()
	quality_changed.emit(level)


func get_quality() -> int:
	return _quality


## 0..1 multiplier other modules use for their own density / draw distance at the current quality.
func detail_scale() -> float:
	return float(QUALITIES[maxi(_quality, 0)]["detail"])


## &"golden_hour" (default) or &"dusk". Unknown names are ignored with a warning.
func set_time_of_day(preset: StringName) -> void:
	if not TIMES.has(preset):
		push_warning("WorldLook: unknown time of day '%s'" % preset)
		return
	_time = preset
	var t: Dictionary = TIMES[preset]
	var az := deg_to_rad(float(t["sun_azimuth"]))
	var el := deg_to_rad(float(t["sun_elevation"]))
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)   # a light shines along its -Z
	sun.light_color = t["sun_color"]
	sun.light_energy = t["sun_energy"]
	sun.light_angular_distance = t["sun_angular"]

	# Turn the panorama so its own sun sits at the scene sun's azimuth.
	var hdri_az := (float(t["hdri_u"]) - 0.5) * TAU
	var hdri_el := deg_to_rad(float(t["hdri_elev"]))
	_sky_material.set_shader_parameter(&"panorama", _panorama(t["panorama"]))
	_sky_material.set_shader_parameter(&"pano_yaw", az - hdri_az)
	_sky_material.set_shader_parameter(&"hdri_sun_dir", Vector3(sin(az) * cos(hdri_el), sin(hdri_el), -cos(az) * cos(hdri_el)))
	_sky_material.set_shader_parameter(&"hdri_sun_dim", t["hdri_sun_dim"])
	_sky_material.set_shader_parameter(&"sky_energy", t["sky_energy"])
	_sky_material.set_shader_parameter(&"sky_tint", t["sky_tint"])
	_sky_material.set_shader_parameter(&"horizon_tint", t["horizon_tint"])
	_sky_material.set_shader_parameter(&"horizon_strength", t["horizon_strength"])
	_sky_material.set_shader_parameter(&"horizon_falloff", t["horizon_falloff"])
	_sky_material.set_shader_parameter(&"sun_glow", t["sun_glow"])
	_sky_material.set_shader_parameter(&"sun_disc", t["sun_disc"])
	_sky_material.set_shader_parameter(&"bounce_color", t["bounce"])

	environment.ambient_light_energy = t["ambient_energy"]
	environment.fog_light_color = t["fog_color"]
	environment.fog_density = t["fog_density"]
	environment.fog_aerial_perspective = t["fog_aerial"]
	environment.fog_sun_scatter = t["fog_sun_scatter"]
	environment.tonemap_exposure = t["exposure"]
	environment.glow_intensity = t["glow_intensity"]
	environment.glow_bloom = t["glow_bloom"]
	environment.adjustment_saturation = t["saturation"]
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# The Compatibility renderer (the browser demo) has no aerial perspective, SSAO or SSIL: the warm haze
		# tints everything sepia and the shade goes flat. A thinner, cooler haze and more sky light instead.
		environment.fog_density = float(t["fog_density"]) * 0.3
		environment.fog_light_color = (t["fog_color"] as Color).lerp(Color(0.72, 0.8, 0.92), 0.65)
		environment.ambient_light_energy = float(t["ambient_energy"]) * 1.4
		environment.adjustment_saturation = float(t["saturation"]) * 1.15
	time_of_day_changed.emit(preset)


func get_time_of_day() -> StringName:
	return _time


## Unit vector from the world towards the sun.
func sun_direction() -> Vector3:
	return sun.global_basis.z


## Everything that does not depend on the time of day or the quality level.
func _build_static() -> void:
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var e := environment
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_white = 6.0
	e.tonemap_agx_contrast = 1.3

	e.ssao_enabled = true
	e.ssao_radius = 1.6
	e.ssao_intensity = 2.6
	e.ssao_power = 1.6
	e.ssao_detail = 0.5
	e.ssao_horizon = 0.06
	e.ssao_sharpness = 0.98
	e.ssao_light_affect = 0.12   # a little AO in direct light too: grounds props and rubble
	e.ssil_radius = 6.0
	e.ssil_intensity = 0.9
	e.ssil_sharpness = 0.98
	e.ssil_normal_rejection = 1.0

	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_strength = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.glow_hdr_threshold = 1.05
	e.glow_hdr_scale = 2.0
	e.glow_hdr_luminance_cap = 16.0
	var levels: Array[float] = [0.0, 0.5, 1.0, 0.8, 0.5, 0.3, 0.0]
	for i in levels.size():
		e.set_glow_level(i, levels[i])

	# Aerial haze: thin, takes its colour from the sky behind it, warms up towards the sun.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_sky_affect = 0.0
	e.fog_height_density = 0.0

	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.03
	e.adjustment_color_correction = ColorGrade.build_lut()

	sun.shadow_enabled = true
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_split_1 = 0.055
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_fade_start = 0.86
	sun.directional_shadow_pancake_size = 30.0
	sun.light_specular = 1.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY


func _apply_gi() -> void:
	environment.sdfgi_enabled = use_sdfgi
	if use_sdfgi:
		environment.sdfgi_cascades = 4
		environment.sdfgi_min_cell_size = 0.4
		environment.sdfgi_use_occlusion = true
		environment.sdfgi_read_sky_light = true
		environment.sdfgi_energy = 1.0
		RenderingServer.gi_set_use_half_resolution(true)


func _panorama(path: String) -> Texture2D:
	if not _panoramas.has(path):
		_panoramas[path] = load(path) as Texture2D
	return _panoramas[path]
