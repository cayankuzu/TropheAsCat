class_name DestructionFX
extends Node3D
## Pooled GPU particle bursts for destruction: billowing dust, flying chips, glass glints.
## Bursts that land close together in space and time are merged so a collapse does not exhaust the pool.

@export var dust_pool := 32
@export var chip_pool := 20

var _dust: Array[GPUParticles3D] = []
var _dust_mat: Array[ParticleProcessMaterial] = []
var _dust_next := 0
var _chips: Array[GPUParticles3D] = []
var _chip_mat: Array[ParticleProcessMaterial] = []
var _chip_next := 0
var _recent_pos := PackedVector3Array()
var _recent_t := PackedFloat64Array()
var _time := 0.0
var bursts := 0
## Share of each burst that is emitted at the current graphics level (Perf "dust"): thick clouds of big
## translucent quads are the most expensive thing on the screen of a weak GPU.
var _density := 1.0
var _dust_look: StandardMaterial3D


func _ready() -> void:
	var puff := _puff_texture()
	var dust_draw := QuadMesh.new()
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = puff
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.billboard_keep_scale = true
	dm.proximity_fade_enabled = true
	dm.proximity_fade_distance = 1.2
	dm.roughness = 1.0
	dm.metallic_specular = 0.0
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	dm.backlight_enabled = true
	dm.backlight = Color(0.35, 0.33, 0.3)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dust_draw.material = dm
	_dust_look = dm
	for i in dust_pool:
		var p := GPUParticles3D.new()
		var pm := _dust_process()
		p.process_material = pm
		p.draw_pass_1 = dust_draw
		p.amount = 56
		p.lifetime = 6.0
		p.one_shot = true
		p.explosiveness = 0.8
		p.randomness = 0.5
		p.emitting = false
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		p.visibility_aabb = AABB(Vector3(-25, -6, -25), Vector3(50, 40, 50))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_dust.append(p)
		_dust_mat.append(pm)
	var chip_draw := BoxMesh.new()
	chip_draw.size = Vector3(0.09, 0.06, 0.07)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.9
	chip_draw.material = cm
	for i in chip_pool:
		var p := GPUParticles3D.new()
		var pm := _chip_process()
		p.process_material = pm
		p.draw_pass_1 = chip_draw
		p.amount = 48
		p.lifetime = 2.2
		p.one_shot = true
		p.explosiveness = 0.95
		p.randomness = 0.3
		p.emitting = false
		p.visibility_aabb = AABB(Vector3(-15, -10, -15), Vector3(30, 25, 30))
		add_child(p)
		_chips.append(p)
		_chip_mat.append(pm)
	_apply_level()
	Perf.level_changed.connect(func(_l: int) -> void: _apply_level())


func _process(delta: float) -> void:
	_time += delta


func _apply_level() -> void:
	_density = Perf.budget(&"dust")
	# Proximity fade reads the depth buffer (a depth copy on OpenGL / WebGL): only above the Low level.
	_dust_look.proximity_fade_enabled = Perf.level > 0


func _dust_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3.ONE
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 2.8
	p.gravity = Vector3(0.0, 0.18, 0.0)
	p.damping_min = 0.8
	p.damping_max = 1.8
	p.scale_min = 1.4
	p.scale_max = 3.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -12.0
	p.angular_velocity_max = 12.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(0.25, 0.8))
	sc.add_point(Vector2(1.0, 1.5))
	var sct := CurveTexture.new()
	sct.curve = sc
	p.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.04, Color(1, 1, 1, 0.92))
	g.add_point(0.35, Color(1, 1, 1, 0.7))
	g.add_point(0.7, Color(1, 1, 1, 0.35))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	p.color_ramp = gt
	return p


func _chip_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3.ONE
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_min = 0.4
	p.scale_max = 1.4
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	p.collision_bounce = 0.15
	p.collision_friction = 0.6
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(0.8, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	p.scale_curve = sct
	return p


static func _puff_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var half := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dx := (x - half) / half
			var dy := (y - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var f := clampf(1.0 - r, 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			img.set_pixel(x, y, Color(1, 1, 1, f * (0.5 + 0.5 * n)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _merge(pos: Vector3, radius: float, window: float) -> bool:
	var r2 := radius * radius
	for i in range(_recent_pos.size() - 1, -1, -1):
		if _time - _recent_t[i] > window:
			continue
		if _recent_pos[i].distance_squared_to(pos) < r2:
			return true
	if _recent_pos.size() > 64:
		_recent_pos = _recent_pos.slice(32)
		_recent_t = _recent_t.slice(32)
	_recent_pos.append(pos)
	_recent_t.append(_time)
	return false


## Dust where an element broke. extents: element size; strength 0..1.
func dust(pos: Vector3, extents: Vector3, material: StringName, strength: float) -> void:
	var t_probe := PerfProbe.begin()
	dust_timed(pos, extents, material, strength)
	PerfProbe.add(&"fx_dust", t_probe)


func dust_timed(pos: Vector3, extents: Vector3, material: StringName, strength: float) -> void:
	if MaterialDB.is_glass(material):
		return
	if _merge(pos, 2.2, 0.35):
		return
	var p := _dust[_dust_next]
	var pm := _dust_mat[_dust_next]
	_dust_next = (_dust_next + 1) % _dust.size()
	pm.emission_box_extents = extents * 0.5 + Vector3(0.15, 0.15, 0.15)
	pm.color = DestructionDefs.dust_color(material)
	pm.scale_min = 1.8 + strength * 1.8
	pm.scale_max = 3.2 + strength * 4.0
	pm.initial_velocity_max = 2.0 + strength * 3.0
	pm.spread = 80.0
	pm.direction = Vector3.UP
	pm.gravity = Vector3(0.0, 0.12, 0.0)
	p.amount_ratio = clampf(0.45 + strength * 0.55, 0.3, 1.0) * _density
	p.lifetime = 5.0 + strength * 4.0
	p.global_position = pos
	p.restart()
	bursts += 1


## Big low dust cloud where a heavy body hit the ground.
func impact_dust(pos: Vector3, strength: float, material: StringName = &"concrete") -> void:
	var t_probe := PerfProbe.begin()
	impact_dust_timed(pos, strength, material)
	PerfProbe.add(&"fx_impact_dust", t_probe)


func impact_dust_timed(pos: Vector3, strength: float, material: StringName = &"concrete") -> void:
	if _merge(pos, 4.0, 0.5):
		return
	var p := _dust[_dust_next]
	var pm := _dust_mat[_dust_next]
	_dust_next = (_dust_next + 1) % _dust.size()
	var w := 1.5 + strength * 4.0
	pm.emission_box_extents = Vector3(w, 0.5, w)
	pm.color = DestructionDefs.dust_color(material)
	pm.scale_min = 3.0 + strength * 3.0
	pm.scale_max = 5.0 + strength * 7.0
	pm.initial_velocity_max = 3.0 + strength * 6.0
	pm.spread = 88.0
	pm.direction = Vector3.UP
	pm.gravity = Vector3(0.0, 0.06, 0.0)
	p.amount_ratio = clampf(0.5 + strength * 0.5, 0.4, 1.0) * _density
	p.lifetime = 7.0 + strength * 5.0
	p.global_position = pos + Vector3(0.0, 0.4, 0.0)
	p.restart()
	bursts += 1


func chips(pos: Vector3, extents: Vector3, material: StringName, strength: float, velocity: Vector3 = Vector3.ZERO) -> void:
	var t_probe := PerfProbe.begin()
	chips_timed(pos, extents, material, strength, velocity)
	PerfProbe.add(&"fx_chips", t_probe)


func chips_timed(pos: Vector3, extents: Vector3, material: StringName, strength: float, velocity: Vector3 = Vector3.ZERO) -> void:
	var p := _chips[_chip_next]
	var pm := _chip_mat[_chip_next]
	_chip_next = (_chip_next + 1) % _chips.size()
	pm.emission_box_extents = extents * 0.5
	var c := DestructionDefs.dust_color(material)
	if MaterialDB.is_glass(material):
		c = Color(0.75, 0.9, 1.0)
	pm.color = c.darkened(0.15)
	pm.initial_velocity_max = 3.0 + strength * 6.0
	if velocity.length_squared() > 0.01:
		pm.direction = velocity.normalized()
		pm.spread = 50.0
	else:
		pm.direction = Vector3.UP
		pm.spread = 75.0
	p.amount_ratio = clampf(0.3 + strength * 0.7, 0.2, 1.0) * maxf(_density, 0.5)
	p.global_position = pos
	p.restart()
