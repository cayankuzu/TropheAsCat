extends Node3D
## Windowed showcase for the destruction module: four buildings on flat ground under an HDRI sky,
## scripted blasts, screenshots and frame timings.
## Run: Godot --path <P> res://tests/shot_destruction.tscn --resolution 1280x720 -- --scenario=apartment
## Scenarios: overview, apartment, tower, closeup, glass.

const SKY := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_4k.hdr"
const OUT := "res://tests/out/"

var sm: StructureManager
var cam: Camera3D
var scenario := "overview"
var ids := {}
var t := 0.0
var events: Array = []          # [time, Callable]
var frame_ms := PackedFloat32Array()
var logic_ms := PackedFloat32Array()
var physics_ms := PackedFloat32Array()
var measure_from := 1.0e9
var measure_to := 0.0
var quit_at := 10.0
var _shot_pending: Array[String] = []
var _skip_frames := 0
var _phys: PhysTimer
var prefix := ""                ## --prefix=xyz_ puts xyz_ in front of every PNG / metrics file name


## Wall time from the first physics callback of a frame to the first process callback (physics scripts
## plus the Jolt step).
class PhysTimer:
	extends Node
	var t_phys := 0
	var last_ms := 0.0

	func _init() -> void:
		process_physics_priority = -100000
		process_priority = -100000

	func _physics_process(_d: float) -> void:
		if t_phys == 0:
			t_phys = Time.get_ticks_usec()

	func _process(_d: float) -> void:
		last_ms = (Time.get_ticks_usec() - t_phys) / 1000.0 if t_phys > 0 else 0.0
		t_phys = 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.get_slice("=", 1)
		elif a.begins_with("--prefix="):
			prefix = a.get_slice("=", 1)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_phys = PhysTimer.new()
	add_child(_phys)
	_environment()
	_ground()
	sm = StructureManager.create_world(self)
	ids["apartment"] = sm.spawn_building(DestructionDefs.Style.APARTMENT, 7, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	ids["tower"] = sm.spawn_building(DestructionDefs.Style.TOWER, 11, Transform3D(Basis.IDENTITY, Vector3(-38, 0, -34)))
	ids["parking"] = sm.spawn_building(DestructionDefs.Style.PARKING, 5, Transform3D(Basis.IDENTITY, Vector3(34, 0, -30)))
	ids["house"] = sm.spawn_building(DestructionDefs.Style.HOUSE, 3, Transform3D(Basis(Vector3.UP, 0.3), Vector3(-30, 0, 14)))
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 1500.0
	add_child(cam)
	_look(Vector3(48, 18, 46), Vector3(-4, 8, -12))
	match scenario:
		"overview":
			_scenario_overview()
		"apartment":
			_scenario_apartment()
		"tower":
			_scenario_tower()
		"closeup":
			_scenario_closeup()
		"glass":
			_scenario_glass()
		"dust":
			_scenario_dust()
		"pancake":
			_scenario_pancake()
		"storm":
			_scenario_storm()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load(SKY)
	pano.energy_multiplier = 0.75
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -128.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)


func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	mi.mesh = pm
	var ground_mat := MaterialDB.surface(&"asphalt").duplicate() as StandardMaterial3D
	ground_mat.albedo_color = Color(0.55, 0.55, 0.56)
	mi.material_override = ground_mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.TERRAIN
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 4, 600)
	cs.shape = box
	cs.position = Vector3(0, -2, 0)
	body.add_child(cs)
	add_child(body)
	var pc := GPUParticlesCollisionBox3D.new()
	pc.size = Vector3(600, 2, 600)
	pc.position = Vector3(0, -1, 0)
	add_child(pc)


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _at(time: float, c: Callable) -> void:
	events.append([time, c])


func _shot(name: String) -> void:
	_shot_pending.append(name)


func _blast(center: Vector3, radius: float, energy: float, impulse: float) -> void:
	DamageRouter.apply_blast(DamageHit.blast(center, radius, energy, impulse))


func _process(delta: float) -> void:
	t += delta
	for i in range(events.size() - 1, -1, -1):
		if events[i][0] <= t:
			var c: Callable = events[i][1]
			events.remove_at(i)
			c.call()
	var after_shot := _skip_frames > 0
	_skip_frames = maxi(_skip_frames - 1, 0)
	if t >= measure_from and t <= measure_to and not after_shot:
		frame_ms.append(delta * 1000.0)
		if delta > 0.025:
			print("long frame %.1f ms at t=%.2f logic %.2f ms (sm %d us + phys %d us, dm %d us + phys %d us) active %d builds %d fr %d" % [delta * 1000.0, t,
				(sm.frame_usec + sm.physics_usec + sm.debris.frame_usec + sm.debris.physics_usec) / 1000.0, sm.frame_usec, sm.physics_usec, sm.debris.frame_usec, sm.debris.physics_usec,
				sm.debris.active_count(), sm._builds.size(), sm._fracture_jobs.size()])
		logic_ms.append((sm.frame_usec + sm.physics_usec + sm.last_damage_usec + sm.debris.frame_usec + sm.debris.physics_usec) / 1000.0)
		physics_ms.append(_phys.last_ms)
	if not _shot_pending.is_empty():
		var names := _shot_pending.duplicate()
		_shot_pending.clear()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		for n in names:
			img.save_png(OUT + prefix + n + ".png")
			print("saved ", prefix + n)
		_skip_frames = 2   # the readback and PNG encode make the next frames long; not simulation cost
	if t >= quit_at:
		_finish()


func _finish() -> void:
	set_process(false)
	var res := {"scenario": scenario, "frames": frame_ms.size()}
	if frame_ms.size() > 0:
		var s := Array(frame_ms)
		s.sort()
		var total := 0.0
		for v in frame_ms:
			total += v
		var lt := 0.0
		for v in logic_ms:
			lt += v
		var pt := 0.0
		for v in physics_ms:
			pt += v
		res["avg_frame_ms"] = total / frame_ms.size()
		res["p95_frame_ms"] = s[int(s.size() * 0.95)]
		res["max_frame_ms"] = s[s.size() - 1]
		res["avg_fps"] = 1000.0 / (total / frame_ms.size())
		res["avg_logic_ms"] = lt / logic_ms.size()
		res["avg_physics_ms"] = pt / physics_ms.size()
		var ls := Array(logic_ms)
		ls.sort()
		var ps := Array(physics_ms)
		ps.sort()
		res["p95_logic_ms"] = ls[int(ls.size() * 0.95)]
		res["p95_physics_ms"] = ps[int(ps.size() * 0.95)]
		res["max_physics_ms"] = ps[ps.size() - 1]
		var under := 0
		for v in frame_ms:
			if v <= 1000.0 / 60.0:
				under += 1
		res["frames_at_or_above_60fps_pct"] = 100.0 * under / frame_ms.size()
	res["debris_active"] = sm.debris.active_count()
	res["rubble"] = sm.debris.rubble_count
	res["rubble_batches"] = sm.debris.rubble_batch_count()
	res["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	res["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	res["stats"] = sm.stats()
	if scenario == "storm":
		res["floating_rubble"] = sm.debris.floating_rubble()
		res["forced_fast_freezes"] = sm.debris.forced_fast_freezes
	print("SHOT_METRICS ", JSON.stringify(res))
	var f := FileAccess.open(OUT + prefix + "shot_metrics_%s.json" % scenario, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	get_tree().quit()


# --------------------------------------------------------------------------------------------------

func _scenario_overview() -> void:
	quit_at = 9.0
	_at(1.5, func(): _shot("overview_before"))
	_at(2.0, func(): _look(Vector3(18, 7, 26), Vector3(0, 7, 0)))
	_at(2.6, func(): _shot("overview_apartment"))
	_at(3.0, func(): _look(Vector3(-6, 16, 14), Vector3(-38, 20, -34)))
	_at(3.6, func(): _shot("overview_tower"))
	_at(4.0, func(): _look(Vector3(30, 9, 2), Vector3(34, 4, -30)))
	_at(4.6, func(): _shot("overview_parking"))
	_at(5.0, func(): _look(Vector3(-20, 4, 26), Vector3(-30, 3, 14)))
	_at(5.6, func(): _shot("overview_house"))
	_at(6.0, func(): _look(Vector3(4, 2.2, 9), Vector3(0, 3.0, 6)))
	_at(6.6, func(): _shot("overview_apartment_close"))


func _apartment_collapse(at_time: float) -> void:
	var bid: int = ids["apartment"]
	var box := sm.buildings[bid].data.bounds
	var half := box.size * 0.5
	for k in 9:
		var x := lerpf(-half.x + 1.5, half.x - 1.5, k / 8.0)
		var tt := at_time + k * 0.05
		_at(tt, func(): _blast(Vector3(x, 1.6, -half.z - 0.3), 3.2, 380000.0, 16000.0))
		_at(tt + 0.02, func(): _blast(Vector3(x, 1.6, half.z + 0.3), 3.2, 380000.0, 16000.0))
		_at(tt + 0.04, func(): _blast(Vector3(x, 1.4, 0.0), 4.5, 380000.0, 8000.0))
	_at(at_time + 0.6, func():
		for e in sm.find_elements(bid, 0, [DestructionDefs.Kind.PIER, DestructionDefs.Kind.WALL, DestructionDefs.Kind.SILL]):
			sm.destroy_element(bid, e))


func _scenario_apartment() -> void:
	quit_at = 16.0
	_look(Vector3(30, 14, 34), Vector3(0, 6, 0))
	_at(1.2, func(): _shot("apartment_before"))
	_apartment_collapse(1.5)
	measure_from = 1.5
	measure_to = 13.5
	_at(1.9, func(): _shot("apartment_during_0"))
	_at(2.6, func(): _shot("apartment_during_1"))
	_at(3.4, func(): _shot("apartment_during_2"))
	_at(4.6, func(): _shot("apartment_during_3"))
	_at(13.5, func(): _shot("apartment_after"))
	_at(14.0, func(): _look(Vector3(8, 4, 16), Vector3(0, 1, 2)))
	_at(14.6, func(): _shot("apartment_after_close"))


func _scenario_tower() -> void:
	quit_at = 18.0
	var bid: int = ids["tower"]
	_look(Vector3(-14, 12, -96), Vector3(-24, 12, -34))
	_at(1.2, func(): _shot("tower_before"))
	measure_from = 1.5
	measure_to = 16.0
	var box := sm.buildings[bid].data.bounds
	_at(1.5, func():
		var b := sm.buildings[bid]
		for e in sm.find_elements(bid, 0, [DestructionDefs.Kind.COLUMN, DestructionDefs.Kind.CORE]):
			var p := b.data.xf[e].origin
			if p.x > box.position.x + box.size.x * 0.45:
				sm.destroy_element(bid, e))
	_at(2.0, func(): _shot("tower_during_0"))
	_at(3.0, func(): _shot("tower_during_1"))
	_at(4.2, func(): _shot("tower_during_2"))
	_at(5.6, func(): _shot("tower_during_3"))
	_at(15.5, func(): _shot("tower_after"))


func _scenario_closeup() -> void:
	quit_at = 9.0
	var bid: int = ids["apartment"]
	_look(Vector3(5.5, 5.8, -13.5), Vector3(2.0, 4.8, -6.0))
	_at(0.8, func(): _look(Vector3(2.0, 4.8, -16.0), Vector3(2.0, 4.8, -6.0)))
	_at(1.1, func(): _shot("closeup_front_before"))
	_at(1.2, func(): _look(Vector3(5.5, 5.8, -13.5), Vector3(2.0, 4.8, -6.0)))
	_at(1.3, func(): _shot("closeup_before"))
	_at(1.5, func(): _blast(Vector3(2.0, 4.8, -6.6), 2.2, 160000.0, 9000.0))
	_at(1.62, func(): _shot("closeup_during"))
	_at(2.4, func(): _shot("closeup_during_2"))
	sm.element_destroyed.connect(func(b_id: int, e: int, _c: int) -> void:
		var b := sm.buildings[b_id]
		print("destroyed e%d %s at %s" % [e, DestructionDefs.KIND_NAMES[b.data.kind[e]], b.data.xf[e].origin]))
	_at(3.0, func():
		var b := sm.buildings[bid]
		for e in [219, 220, 221, 222, 223, 224]:
			var g := b.groups[b.group[e]]
			print("e%d state %d inst %d body %s group count %d visible %d mm.count %d" % [e, b.state[e], b.inst[e], b.bodies[e], g.count, g.mm.visible_instance_count, g.mm.instance_count])
		print("debris spawned total ", sm.debris.spawned_total, " active ", sm.debris.active_count(), " rubble ", sm.debris.rubble_count))
	_at(7.0, func(): _shot("closeup_after"))
	_at(7.3, func(): _look(Vector3(2.0, 4.8, -16.0), Vector3(2.0, 4.8, -6.0)))
	_at(7.6, func(): _shot("closeup_front_after"))


## Same as headless test (b): every ground-floor wall removed at once.
func _scenario_pancake() -> void:
	quit_at = 15.0
	var bid: int = ids["apartment"]
	_look(Vector3(26, 10, 30), Vector3(0, 5, 0))
	_at(1.2, func(): _shot("pancake_before"))
	measure_from = 1.5
	measure_to = 14.0
	_at(1.5, func():
		for e in sm.find_elements(bid, 0, [DestructionDefs.Kind.PIER, DestructionDefs.Kind.WALL, DestructionDefs.Kind.SILL]):
			sm.destroy_element(bid, e))
	_at(1.9, func(): _shot("pancake_0"))
	_at(2.4, func(): _shot("pancake_1"))
	_at(3.0, func(): _shot("pancake_2"))
	_at(4.5, func(): _shot("pancake_3"))
	_at(13.5, func(): _shot("pancake_after"))


func _scenario_dust() -> void:
	quit_at = 5.0
	_look(Vector3(20, 3, 30), Vector3(20, 2, 20))
	_at(1.0, func():
		sm.fx.dust(Vector3(18, 1.5, 20), Vector3(0.75, 3.2, 0.3), &"brick", 0.6)
		sm.fx.impact_dust(Vector3(22, 0.2, 20), 0.8, &"concrete")
		sm.fx.chips(Vector3(18, 1.5, 20), Vector3(0.5, 1, 0.3), &"brick", 0.6))
	_at(1.6, func(): _shot("dust_0"))
	_at(3.0, func(): _shot("dust_1"))


## Headless test (c) on screen: 20 random blasts on the tower, one every 0.25 s (seed 42).
func _scenario_storm() -> void:
	quit_at = 16.0
	var bid: int = ids["tower"]
	var b := sm.buildings[bid]
	var box := b.data.bounds
	_look(Vector3(-12, 16, -92), Vector3(-36, 13, -34))
	_at(1.2, func(): _shot("storm_before"))
	measure_from = 1.5
	measure_to = 13.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for k in 20:
		var p := Vector3(rng.randf_range(box.position.x - 1.0, box.end.x + 1.0), rng.randf_range(1.0, box.end.y - 2.0),
			rng.randf_range(box.position.z - 1.0, box.end.z + 1.0))
		var r := rng.randf_range(4.0, 7.0)
		var en := rng.randf_range(200000.0, 600000.0)
		var imp := rng.randf_range(8000.0, 20000.0)
		var wp := b.xform * p
		_at(1.5 + k * 0.25, func(): _blast(wp, r, en, imp))
	_at(3.0, func(): _shot("storm_during_0"))
	_at(6.5, func(): _shot("storm_during_1"))
	_at(13.8, func(): _shot("storm_after"))
	_at(14.2, func(): _look(Vector3(-96, 12, -44), Vector3(-38, 9, -34)))
	_at(14.8, func(): _shot("storm_after_side"))
	_at(15.2, func(): _look(Vector3(-52, 5, -58), Vector3(-38, 6, -34)))
	_at(15.7, func(): _shot("storm_after_close"))


func _scenario_glass() -> void:
	quit_at = 9.0
	var bid: int = ids["tower"]
	_look(Vector3(-8, 8, -8), Vector3(-30, 12, -30))
	_at(1.2, func(): _shot("glass_before"))
	_at(1.5, func():
		var h := DamageHit.blast(Vector3(-28, 10, -22), 14.0, 2000.0, 400.0, DamageHit.Kind.SONIC)
		DamageRouter.apply_blast(h))
	_at(1.8, func(): _shot("glass_during"))
	_at(3.0, func(): _shot("glass_during_2"))
	_at(8.0, func(): _shot("glass_after"))
