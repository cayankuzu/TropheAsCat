extends Node3D
## City-scale check of the destruction module: 250 buildings on the road grid, all placed dormant.
## A probe stands in for the player. Reports how long the city takes to build, how many physics bodies
## exist, what waking, sleeping and hitting a dormant building cost, and the idle logic time.
## Headless: Godot --headless --path <P> res://tests/test_city_scale.tscn --fixed-fps 60
## Windowed (adds a camera and prints render numbers): Godot --path <P> res://tests/test_city_scale.tscn

const D := preload("res://game/destruction/destruction_defs.gd")
const BLOCK := 128.0
const BODY_LIMIT := 60000

var all_ok := true
var _sm: StructureManager
var _probe: Node3D


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 2.0, 2000.0)
	shape.shape = box
	shape.position.y = -1.0
	ground.add_child(shape)
	add_child(ground)
	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2000.0, 2000.0)
		floor_mesh.mesh = plane
		add_child(floor_mesh)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
		sun.shadow_enabled = true
		add_child(sun)
		var cam := Camera3D.new()
		cam.far = 3000.0
		add_child(cam)
		cam.look_at_from_position(Vector3(40.0, 70.0, 330.0), Vector3(0.0, 10.0, 0.0), Vector3.UP)
		cam.make_current()

	_sm = StructureManager.create_world(self)
	Game.structures = _sm
	Game.debris = _sm.debris
	await get_tree().process_frame

	# 25 blocks of 10 lots each: half houses, the rest apartments, towers and parking decks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var styles := [D.Style.HOUSE, D.Style.HOUSE, D.Style.HOUSE, D.Style.HOUSE, D.Style.HOUSE, D.Style.APARTMENT, D.Style.APARTMENT,
		D.Style.APARTMENT, D.Style.TOWER, D.Style.PARKING]
	var t0 := Time.get_ticks_msec()
	var elements := 0
	var by_style := {}
	for bx in range(-2, 3):
		for bz in range(-2, 3):
			for lot in 10:
				var style: int = styles[lot]
				var at := Vector3(bx * BLOCK + 64.0 + (lot % 5 - 2) * 21.0, 0.0, bz * BLOCK + 64.0 + (25.0 if lot < 5 else -25.0))
				var bid := _sm.spawn_building(style, rng.randi_range(1, 60), Transform3D(Basis(Vector3.UP, PI * 0.5 * rng.randi_range(0, 3)), at), false)
				elements += _sm.buildings[bid].data.count()
				by_style[D.STYLE_NAMES[style]] = int(by_style.get(D.STYLE_NAMES[style], 0)) + 1
	var build_ms := Time.get_ticks_msec() - t0
	print("CITY built %d buildings (%s) with %d elements in %d ms; bodies %d, pattern jobs %d" % [_sm.building_count(), by_style, elements, build_ms,
		_sm.bodies_alive, _sm.fracture.pending_count()])
	_check("all buildings start dormant", _sm.bodies_alive == 0 and _awake() == 0, "bodies %d, awake %d" % [_sm.bodies_alive, _awake()])

	# The player appears in the middle of the city.
	_probe = Node3D.new()
	_probe.name = "Probe"
	add_child(_probe)
	_probe.global_position = Vector3(0.0, 1.0, 0.0)
	Game.register_player(_probe)
	var logic := await _run(180)
	var near := _awake()
	print("CITY probe at the centre: %d buildings awake, %d bodies, logic avg %.3f ms max %.3f ms" % [near, _sm.bodies_alive, logic[0], logic[1]])
	_check("buildings near the player wake up", near > 0 and near < 60 and _sm._waking.is_empty(), "%d awake, %d still waking" % [near, _sm._waking.size()])
	_check("body count stays under the limit", _sm.bodies_alive < BODY_LIMIT, "%d bodies (limit %d)" % [_sm.bodies_alive, BODY_LIMIT])

	# Beyond the reach of the world nothing reacts (DamageRouter.REACH).
	var out_b := _sm.buildings[_farthest_dormant(Vector3(0.0, 1.0, 0.0), D.Style.APARTMENT)]
	var out_wall := out_b.world_box.get_center()
	out_wall.z = out_b.world_box.end.z + 0.5
	out_wall.y = 4.0
	var out_before := _sm.elements_destroyed
	DamageRouter.apply_blast(DamageHit.blast(out_wall, 6.0, 5.0e6, 8000.0))
	_check("a blast beyond the reach of the world changes nothing", not out_b.awake and _sm.elements_destroyed == out_before,
		"awake %s, %d elements destroyed, %.0f m from the probe" % [out_b.awake, _sm.elements_destroyed - out_before, out_wall.distance_to(_probe.global_position)])

	# A blast on a dormant building inside the reach wakes it and takes elements out.
	var far_b := _dormant_between(Vector3(0.0, 1.0, 0.0), 95.0, 135.0, D.Style.APARTMENT)
	var fb := _sm.buildings[far_b]
	var wall := fb.world_box.get_center()
	wall.z = fb.world_box.end.z + 0.5
	wall.y = 4.0
	var before := _sm.elements_destroyed
	var t1 := Time.get_ticks_usec()
	DamageRouter.apply_blast(DamageHit.blast(wall, 6.0, 5.0e6, 8000.0))
	var blast_usec := Time.get_ticks_usec() - t1
	_check("a blast on a dormant building wakes it and destroys elements", fb.awake and _sm.elements_destroyed > before,
		"awake %s, %d elements destroyed, call took %.1f ms, %.0f m from the probe" % [fb.awake, _sm.elements_destroyed - before, blast_usec / 1000.0,
			wall.distance_to(_probe.global_position)])

	# A point hit found by a ray on another dormant building reaches the element behind the proxy.
	var far_c := _dormant_between(Vector3(0.0, 1.0, 0.0), 85.0, 125.0, D.Style.TOWER)
	var cb := _sm.buildings[far_c]
	var target := cb.world_box.get_center()
	target.y = 10.0
	var from := target + Vector3(0.0, 0.0, cb.world_box.size.z + 30.0)
	var ray := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, target, Layers.STRUCTURE))
	var hp_before := _hp_sum(cb)
	var destroyed_before := _sm.elements_destroyed
	if not ray.is_empty():
		var t2 := Time.get_ticks_usec()
		var hit := DamageHit.point(ray["position"], (target - from).normalized(), 4.0e5, 500.0, DamageHit.Kind.BLUNT)
		DamageRouter.apply_hit(hit, ray.get("collider"), ray["rid"])
		print("CITY point hit on a dormant tower took %.1f ms" % [(Time.get_ticks_usec() - t2) / 1000.0])
	_check("a point hit on a dormant building reaches an element", not ray.is_empty() and cb.awake and (_hp_sum(cb) < hp_before or _sm.elements_destroyed > destroyed_before),
		"ray hit %s, awake %s, hit points %.0f -> %.0f, destroyed %d" % [not ray.is_empty(), cb.awake, hp_before, _hp_sum(cb), _sm.elements_destroyed - destroyed_before])
	await _run(120)

	# The player moves to a far corner: the centre goes back to sleep, the corner wakes.
	var awake_centre := _awake_within(Vector3(0.0, 1.0, 0.0), 60.0)
	_probe.global_position = Vector3(2.0 * BLOCK + 64.0, 1.0, 2.0 * BLOCK + 64.0)
	logic = await _run(int((_sm.sleep_quiet_seconds + 4.0) * 60.0))
	var still_centre := _awake_within(Vector3(0.0, 1.0, 0.0), 60.0)
	var corner := _awake_within(_probe.global_position, 60.0)
	print("CITY probe at the corner: %d buildings awake (%d near the probe, %d left awake at the centre of %d), %d bodies, wakes %d sleeps %d, logic avg %.3f ms max %.3f ms" % [
		_awake(), corner, still_centre, awake_centre, _sm.bodies_alive, _sm.wakes, _sm.sleeps, logic[0], logic[1]])
	_check("buildings the player left go dormant again", awake_centre > 0 and still_centre == 0 and corner > 0 and _sm.sleeps > 0,
		"centre %d -> %d awake, corner %d awake, sleeps %d" % [awake_centre, still_centre, corner, _sm.sleeps])
	_check("body count stays under the limit after moving", _sm.bodies_alive < BODY_LIMIT, "%d bodies" % _sm.bodies_alive)
	# By now the collapse of the blasted building has settled and nothing is waking or going dormant.
	var idle := await _run(240)
	_check("idle destruction logic stays small", idle[0] < 0.3, "avg %.3f ms, max %.3f ms over 4 s with %d buildings" % [idle[0], idle[1], _sm.building_count()])

	if windowed:
		await _run(120)
		print("CITY render: fps %.0f, draw calls %d, primitives %d" % [Performance.get_monitor(Performance.TIME_FPS),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])

	Game.player = null
	print("RESULT ", "PASS" if all_ok else "FAIL")
	_sm.clear()
	await get_tree().process_frame
	get_tree().quit(0 if all_ok else 1)


func _check(name_: String, ok: bool, detail: String) -> void:
	if not ok:
		all_ok = false
	print("[%s] %s: %s" % ["PASS" if ok else "FAIL", name_, detail])


## Runs frames and returns [average, maximum] of the destruction logic time per frame in ms.
func _run(frames: int) -> Array:
	var total := 0.0
	var worst := 0.0
	for i in frames:
		await get_tree().process_frame
		var ms := (_sm.frame_usec + _sm.physics_usec + _sm.debris.frame_usec + _sm.debris.physics_usec) / 1000.0
		total += ms
		worst = maxf(worst, ms)
	return [total / maxf(frames, 1), worst]


func _awake() -> int:
	var n := 0
	for b in _sm.buildings:
		if b.awake:
			n += 1
	return n


func _awake_within(at: Vector3, dist: float) -> int:
	var n := 0
	for b in _sm.buildings:
		if b.awake and at.distance_to(at.clamp(b.world_box.position, b.world_box.end)) < dist:
			n += 1
	return n


func _farthest_dormant(at: Vector3, style: int) -> int:
	var best := -1
	var best_d := -1.0
	for b in _sm.buildings:
		if b.awake or b.data.style != style:
			continue
		var d := at.distance_to(b.world_box.get_center())
		if d > best_d:
			best_d = d
			best = b.id
	return best


## A dormant building of one style whose centre is between two distances from a point (the nearest such).
func _dormant_between(at: Vector3, d_min: float, d_max: float, style: int) -> int:
	var best := -1
	var best_d := 1.0e9
	for b in _sm.buildings:
		if b.awake or b.data.style != style:
			continue
		var d := at.distance_to(b.world_box.get_center())
		if d >= d_min and d <= d_max and d < best_d:
			best_d = d
			best = b.id
	return best


func _hp_sum(b: StructureManager.Building) -> float:
	var total := 0.0
	for v in b.hp:
		total += v
	return total
