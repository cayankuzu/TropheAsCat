extends SceneTree
## Headless terrain tests. Writes res://tests/out/terrain_metrics.json and exits 0 when everything passed.
##   Godot_console.exe --headless --path <project> --script res://tests/test_terrain.gd [-- voxel_size]

const SAVE_PATH := "user://terrain_test/edits.sqlite"


class Receiver extends StaticBody3D:
	var hits := 0

	func receive_damage(_hit: DamageHit, _user_id: int) -> void:
		hits += 1

var terrain: Node3D        # WorldTerrain (loaded at runtime: autoload names are unknown when a --script main loop compiles)
var world: Node3D
var cam: Camera3D
var metrics := {}
var failures: Array[String] = []
var rng := RandomNumberGenerator.new()
var voxel_size := 0.5


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		voxel_size = float(args[0])
	rng.seed = 1234
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	world = Node3D.new()
	root.add_child(world)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 6.0, 0.0)
	world.add_child(cam)
	var t0 := Time.get_ticks_msec()
	terrain = _make_terrain()
	var ready_frames := await _wait_ground(Vector3(0.0, 0.0, 0.0), 0.0)
	metrics["startup_ms_to_collision_at_origin"] = Time.get_ticks_msec() - t0
	metrics["startup_frames"] = ready_frames
	await _wait_settled()
	metrics["startup_ms_to_settled"] = Time.get_ticks_msec() - t0
	metrics["voxel_size_m"] = voxel_size
	metrics["lod_count"] = terrain.voxels.lod_count
	var th := Time.get_ticks_usec()
	TerrainShape._compute_heightmap()
	metrics["heightmap_build_ms"] = (Time.get_ticks_usec() - th) / 1000.0
	var graph := terrain.voxels.generator as VoxelGeneratorGraph
	metrics["generator_us_per_voxel_batch"] = graph.debug_measure_microseconds_per_voxel(false)
	metrics["generator_us_per_voxel_single"] = graph.debug_measure_microseconds_per_voxel(true)

	_test_shape_and_layers()
	await _test_damage_routing()
	await _test_random_digs()
	await _test_collision_latency()
	await _test_physics_spheres()
	await _test_save_load()

	metrics["failures"] = failures
	metrics["passed"] = failures.is_empty()
	metrics["terrain_stats"] = terrain.get_stats()
	metrics["static_memory_mb"] = OS.get_static_memory_usage() / 1048576.0
	var f := FileAccess.open("res://tests/out/terrain_metrics.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(metrics, "  ", false))
	f.close()
	print(JSON.stringify(metrics, "  ", false))
	print("TERRAIN TESTS ", "PASSED" if failures.is_empty() else "FAILED: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _make_terrain() -> Node3D:
	var t: Node3D = load("res://game/terrain/world_terrain.gd").new()
	t.voxel_size = voxel_size
	world.add_child(t)
	return t


func _check(cond: bool, what: String) -> bool:
	if not cond:
		failures.append(what)
		push_error("FAIL: " + what)
	return cond


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _ray_y(x: float, z: float, from_y: float = 60.0) -> float:
	var space := terrain.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -60.0, z), 1)
	var r := space.intersect_ray(q)
	return r["position"].y if not r.is_empty() else -INF


func _wait_settled() -> void:
	var quiet := 0
	for i in 1800:
		await process_frame
		var n := 0
		var tasks: Dictionary = VoxelEngine.get_stats().get("tasks", {})
		for k in tasks:
			n += int(tasks[k])
		quiet = quiet + 1 if n == 0 else 0
		if quiet >= 10:
			return


func _wait_ground(p: Vector3, expect_y: float) -> int:
	for i in 1200:
		await process_frame
		if absf(_ray_y(p.x, p.z) - expect_y) < 0.05:
			return i
	_check(false, "ground collision never appeared at %s" % p)
	return -1


# ------------------------------------------------------------------ 1. shape and layers

func _test_shape_and_layers() -> void:
	var max_city := 0.0
	for i in 4000:
		var x := rng.randf_range(-396.0, 396.0)
		var z := rng.randf_range(-396.0, 396.0)
		max_city = maxf(max_city, absf(TerrainShape.height_at(x, z)))
	var max_h := 0.0
	var min_edge := INF
	for i in 512:
		var a := float(i) / 512.0 * TAU
		var p := Vector2(cos(a), sin(a))
		p = p / maxf(absf(p.x), absf(p.y)) * 511.0
		var h := TerrainShape.height_at(p.x, p.y)
		max_h = maxf(max_h, h)
		min_edge = minf(min_edge, h)
	metrics["city_max_abs_height_m"] = max_city
	metrics["hills_max_height_m"] = max_h
	metrics["hills_min_height_at_edge_m"] = min_edge
	_check(max_city == 0.0, "city plateau not exactly flat (%f)" % max_city)
	_check(max_h > 30.0 and max_h < 45.0, "hills max height %f not ~40" % max_h)

	# CPU heightmap vs voxel data (generator) agreement
	var worst := 0.0
	var sign_ok := true
	for i in 300:
		var x := rng.randf_range(-505.0, 505.0)
		var z := rng.randf_range(-505.0, 505.0)
		var h := TerrainShape.height_at(x, z)
		worst = maxf(worst, absf(terrain.sdf_at(Vector3(x, h, z))))
		sign_ok = sign_ok and terrain.sdf_at(Vector3(x, h - 1.0, z)) < 0.0 and terrain.sdf_at(Vector3(x, h + 1.0, z)) > 0.0
	metrics["heightmap_vs_voxel_sdf_max_error_m"] = worst
	_check(worst < 0.1 and sign_ok, "CPU height disagrees with voxel SDF (max %f m)" % worst)

	# Layer table at sample depths (mid-layer, clear of the noisy boundaries)
	var road := Vector3(0.0, 0.0, 60.0)       # on the x = 0 road
	var lawn := Vector3(60.0, 0.0, 60.0)      # middle of a block
	var walk := Vector3(10.0, 0.0, 60.0)      # sidewalk next to the x = 0 road
	var cases := [
		[road, 0.1, &"asphalt"], [road, 0.8, &"gravel"], [walk, 0.08, &"paving"], [walk, 0.8, &"gravel"],
		[lawn, 0.1, &"grass"], [lawn, 0.8, &"soil"], [lawn, 5.0, &"soil"], [lawn, 11.0, &"clay"],
		[lawn, 17.0, &"sand"], [lawn, 29.0, &"rock"], [road, 41.0, &"rock_deep"], [lawn, 45.5, &"lava"],
		[road, 47.75, &"bedrock"], [lawn, -1.0, &"air"],
	]
	var results := []
	for c in cases:
		var p: Vector3 = c[0] - Vector3(0.0, c[1], 0.0)
		var got: StringName = terrain.get_layer_at(p)
		results.append("%s@%.2f=%s" % [c[2], c[1], got])
		_check(got == c[2], "layer at depth %.2f expected %s got %s" % [c[1], c[2], got])
	# Hills: shallow layers follow the surface, deep ones are horizontal.
	var hx := 480.0
	var hz := 0.0
	var hh := TerrainShape.height_at(hx, hz)
	var hill_cases := [[hh - 5.0, &"soil"], [hh - 17.0, &"sand"], [-20.0, &"rock"], [-41.0, &"rock_deep"], [-45.5, &"lava"]]
	for c in hill_cases:
		var got2: StringName = terrain.get_layer_at(Vector3(hx, c[0], hz))
		results.append("hill y%.1f=%s" % [c[0], got2])
		_check(got2 == c[1], "hill layer at y %.1f expected %s got %s" % [c[0], c[1], got2])
	metrics["hill_sample_surface_height_m"] = hh
	_check(terrain.get_layer_at(Vector3(600.0, 0.0, 0.0)) == &"void", "outside slab must be void")
	_check(terrain.get_layer_at(Vector3(0.0, -48.5, 0.0)) == &"void", "below the bottom must be void")
	_check(terrain.is_lava_at(Vector3(60.0, -45.5, 60.0)), "is_lava_at in the magma band")
	_check(terrain.is_lava_at(Vector3(60.0, -43.6, 60.0)), "is_lava_at standing on magma")
	_check(not terrain.is_lava_at(Vector3(60.0, -30.0, 60.0)), "no lava in rock")
	_check(terrain.get_resistance_at(Vector3(60.0, -30.0, 60.0)) > terrain.get_resistance_at(Vector3(60.0, -5.0, 60.0)), "rock must be harder than soil")
	metrics["layer_samples"] = results


# ------------------------------------------------------------------ 2. damage through DamageRouter

func _test_damage_routing() -> void:
	var router: Node = root.get_node("/root/DamageRouter")
	var space := terrain.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(20.0, 10.0, -20.0), Vector3(20.0, -10.0, -20.0), 1)
	var r := space.intersect_ray(q)
	_check(not r.is_empty(), "ray must hit terrain")
	if r.is_empty():
		return
	var collider: Object = r["collider"]
	metrics["ray_collider_class"] = collider.get_class()
	metrics["ray_collider_is_voxel_child_of_terrain"] = collider is Node and (collider as Node).get_parent() == terrain
	metrics["ray_rid_valid"] = (r["rid"] as RID).is_valid()
	_check(collider is VoxelLodTerrain and (collider as Node).get_parent() == terrain, "collider should be the VoxelLodTerrain child")

	var dug_count := [0]
	var on_dug := func(_c: Vector3, _r: float, _l: StringName) -> void: dug_count[0] += 1
	terrain.dug.connect(on_dug)

	var heat := DamageHit.point(r["position"], Vector3.DOWN, 300000.0, 0.0, DamageHit.Kind.HEAT)
	heat.normal = r["normal"]
	router.apply_hit(heat, collider, r["rid"])
	terrain.flush_edits()
	var heat_ok: bool = terrain.sdf_at(r["position"] - Vector3(0.0, 0.3, 0.0)) > 0.0
	_check(heat_ok, "HEAT hit through DamageRouter.apply_hit must dig")

	await _frames(3)
	var craters_before := int(terrain.get_stats().get("craters", 0))
	var hits_before := int(terrain.get_stats().get("explosion_hits", 0))
	var blast := DamageHit.blast(Vector3(40.0, 1.5, 40.0), 8.0, 5.0e6, 0.0)
	router.apply_blast(blast, terrain.get_world_3d())
	terrain.flush_edits()
	var craters := int(terrain.get_stats().get("craters", 0)) - craters_before
	metrics["blast_craters_made"] = craters
	metrics["blast_deliveries_to_terrain_bodies"] = int(terrain.get_stats().get("explosion_hits", 0)) - hits_before
	_check(craters == 1, "one blast must make exactly one crater (got %d)" % craters)
	_check(terrain.sdf_at(Vector3(40.0, -1.0, 40.0)) > 0.0, "blast through DamageRouter.apply_blast must make a crater")

	# A ground-level blast must still reach every structure in range (terrain triangles must not use up
	# DamageRouter.MAX_BLAST_RESULTS).
	var receivers: Array[Receiver] = []
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	for i in 60:
		var rcv := Receiver.new()
		rcv.collision_layer = Layers.STRUCTURE
		rcv.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = box
		rcv.add_child(cs)
		var a := float(i) / 60.0 * TAU
		rcv.position = Vector3(-80.0, 0.3, -60.0) + Vector3(cos(a), 0.0, sin(a)) * (2.0 + float(i % 6))
		world.add_child(rcv)
		receivers.append(rcv)
	await _frames(3)
	var hits_before2 := int(terrain.get_stats().get("explosion_hits", 0))
	router.apply_blast(DamageHit.blast(Vector3(-80.0, 0.5, -60.0), 9.0, 1.0e6, 0.0), terrain.get_world_3d())
	var reached := 0
	for rcv in receivers:
		reached += 1 if rcv.hits > 0 else 0
		rcv.queue_free()
	metrics["ground_blast_structures_reached"] = "%d/60" % reached
	metrics["ground_blast_terrain_deliveries"] = int(terrain.get_stats().get("explosion_hits", 0)) - hits_before2
	_check(reached == 60, "ground-level blast reached only %d of 60 structures" % reached)
	terrain.flush_edits()

	dug_count[0] = 0
	var soft := DamageHit.point(Vector3(-20.0, 0.0, -30.0), Vector3.DOWN, 1000.0, 10.0, DamageHit.Kind.BLUNT)
	terrain.receive_damage(soft, 0)
	var hard := DamageHit.point(Vector3(-24.0, 0.0, -30.0), Vector3.DOWN, 60000.0, 10.0, DamageHit.Kind.BLUNT)
	terrain.receive_damage(hard, 0)
	terrain.flush_edits()
	metrics["blunt_dents"] = dug_count[0]
	_check(dug_count[0] == 1, "weak BLUNT must not dent, strong BLUNT must (got %d dents)" % dug_count[0])
	terrain.dug.disconnect(on_dug)

	var r_soil: float = terrain.explode(Vector3(-60.0, 0.0, 30.0), 5.0, 2.0e6)
	terrain.dig_sphere(Vector3(-100.0, -22.0, 30.0), 3.0)
	var r_rock: float = terrain.explode(Vector3(-100.0, -30.0, 30.0), 5.0, 2.0e6)
	terrain.flush_edits()
	metrics["crater_radius_2MJ_soil_m"] = r_soil
	metrics["crater_radius_2MJ_rock_m"] = r_rock
	_check(r_rock > 0.0 and r_rock < r_soil * 0.7, "rock must resist more than soil (%f vs %f)" % [r_rock, r_soil])
	var r_big: float = terrain.explode(Vector3(-160.0, 0.0, 30.0), 5.0, 16.0e6)
	metrics["crater_radius_16MJ_soil_m"] = r_big
	_check(absf(r_big / r_soil - 2.0) < 0.05, "crater radius must scale with cbrt(energy)")
	await _frames(2)


# ------------------------------------------------------------------ 3. 100 random digs

func _test_random_digs() -> void:
	terrain.flush_edits()   # earlier craters may still have edits queued under the per-frame budget
	var before: Dictionary = terrain.get_stats()
	var t := Time.get_ticks_usec()
	var worst := 0
	for i in 100:
		var c := Vector3(rng.randf_range(-70.0, 70.0), -rng.randf_range(0.0, 40.0), rng.randf_range(-70.0, 70.0))
		var r := rng.randf_range(0.5, 6.0)
		var t1 := Time.get_ticks_usec()
		terrain.dig_sphere(c, r)
		worst = maxi(worst, Time.get_ticks_usec() - t1)
		if i % 10 == 9:
			await process_frame
	await _frames(30)
	var after: Dictionary = terrain.get_stats()
	metrics["random_digs"] = int(after["edits"]) - int(before["edits"])
	metrics["random_digs_total_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	metrics["random_dig_call_max_ms"] = worst / 1000.0
	_check(metrics["random_digs"] == 100, "100 digs must be applied (got %d)" % metrics["random_digs"])


# ------------------------------------------------------------------ 4. collision latency

func _measure_latency(p: Vector3, radius: float) -> Array:
	var y0 := _ray_y(p.x, p.z)
	var target := y0 - radius * 0.75
	var t := Time.get_ticks_usec()
	var f0 := Engine.get_process_frames()
	terrain.dig_sphere(Vector3(p.x, y0, p.z), radius)
	for i in 240:
		await process_frame
		if _ray_y(p.x, p.z) < target:
			return [(Time.get_ticks_usec() - t) / 1000.0, Engine.get_process_frames() - f0]
	return [INF, -1]


func _test_collision_latency() -> void:
	var small_ms: Array[float] = []
	var small_frames: Array[int] = []
	for i in 20:
		var a := float(i) / 20.0 * TAU
		var p := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(10.0, 28.0) + Vector3(-1.0, 0.0, 1.0)
		var tasks_before: Dictionary = VoxelEngine.get_stats().get("tasks", {})
		var res: Array = await _measure_latency(p, 2.0)
		small_ms.append(res[0])
		small_frames.append(res[1])
		print("latency trial %d at %s: %.1f ms, %d frames, tasks before %s" % [i, p, res[0], res[1], tasks_before])
		await _frames(2)
	var big_ms: Array[float] = []
	for i in 4:
		var p := Vector3(-40.0 + 26.0 * i, 0.0, -75.0)
		var res: Array = await _measure_latency(p, 12.0)
		big_ms.append(res[0])
		await _frames(2)
	small_ms.sort()
	big_ms.sort()
	metrics["collision_latency_r2m_ms"] = {"p50": small_ms[10], "p95": small_ms[18], "max": small_ms[19], "frames_max": small_frames.max()}
	metrics["collision_latency_r12m_async_ms"] = {"min": big_ms[0], "max": big_ms[3]}
	_check(small_ms[19] <= 100.0, "collision must be ready within 100 ms of a dig (max %.1f ms)" % small_ms[19])


# ------------------------------------------------------------------ 5. 200 spheres on freshly dug ground

func _test_physics_spheres() -> void:
	var c := Vector3(-30.0, 0.0, 30.0)
	for i in 6:
		var a := float(i) / 6.0 * TAU
		terrain.dig_sphere(c + Vector3(cos(a) * 6.0, 0.0, sin(a) * 6.0), rng.randf_range(4.0, 7.0))
	terrain.dig_sphere(c + Vector3(0.0, -2.0, 0.0), 6.0)
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	var bodies: Array[RigidBody3D] = []
	for i in 200:
		var b := RigidBody3D.new()
		b.collision_layer = Layers.DEBRIS
		b.collision_mask = Layers.TERRAIN | Layers.DEBRIS
		b.mass = 5.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		b.add_child(mi)
		b.position = c + Vector3((i % 20) * 0.8 - 7.6, 4.0 + (i / 20) * 1.0, ((i * 7) % 20) * 0.8 - 7.6)
		world.add_child(b)
		bodies.append(b)
	var t := Time.get_ticks_msec()
	# After 3 s dig fresh holes under the resting pile.
	while Time.get_ticks_msec() - t < 3000:
		await physics_frame
	for i in 3:
		terrain.dig_sphere(c + Vector3(-3.0 + 3.0 * i, -4.0, 0.0), 3.0)
	while Time.get_ticks_msec() - t < 10000:
		await physics_frame
	var fell := 0
	var embedded := 0
	var lowest := INF
	var awake := 0
	for b in bodies:
		var p := b.global_position
		lowest = minf(lowest, p.y)
		if p.y < -48.0:
			fell += 1
		elif terrain.sdf_at(p) < -0.3:
			embedded += 1
		if not b.sleeping:
			awake += 1
	metrics["spheres_200"] = {"fell_into_void": fell, "inside_ground": embedded, "lowest_y": lowest, "awake_after_10s": awake}
	_check(fell == 0 and embedded == 0, "spheres fell through the ground (void %d, inside %d)" % [fell, embedded])
	for b in bodies:
		b.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ 6. save / load round trip

func _test_save_load() -> void:
	var region := AABB(Vector3(100.0, -14.0, 100.0), Vector3(24.0, 16.0, 24.0))
	var region2 := AABB(Vector3(150.0, -10.0, 150.0), Vector3(12.0, 12.0, 12.0))
	var pristine2: int = terrain.debug_region_hash(region2)
	for i in 5:
		terrain.dig_sphere(region.position + Vector3(4.0 + 4.0 * i, 14.0 - 2.0 * i, 6.0 + 3.0 * i), 3.0 + i * 0.5)
	terrain.add_sphere(region.position + Vector3(12.0, 15.0, 12.0), 2.0)
	terrain.flush_edits()
	var h1: int = terrain.debug_region_hash(region)
	var t := Time.get_ticks_usec()
	var saved_ok: bool = terrain.save_edits(SAVE_PATH)
	metrics["save_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	metrics["saved_blocks"] = terrain.get_stats()["edited_blocks"]
	metrics["save_file_bytes"] = FileAccess.get_file_as_bytes(SAVE_PATH).size()
	_check(saved_ok, "save_edits failed")
	for i in 3:
		terrain.dig_sphere(region.get_center() + Vector3(i * 3.0 - 3.0, -2.0, 0.0), 2.5)
	terrain.dig_sphere(region2.get_center(), 4.0)
	terrain.flush_edits()
	var h2: int = terrain.debug_region_hash(region)
	_check(h2 != h1, "post-save edits must change the region")
	t = Time.get_ticks_usec()
	var loaded_ok: bool = terrain.load_edits(SAVE_PATH)
	metrics["load_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	var h3: int = terrain.debug_region_hash(region)
	var h_r2: int = terrain.debug_region_hash(region2)
	metrics["save_load_same_instance"] = {"h_saved": h1, "h_modified": h2, "h_loaded": h3, "region2_reverted": h_r2 == pristine2}
	_check(loaded_ok and h3 == h1, "load_edits must reproduce the saved voxels")
	_check(h_r2 == pristine2, "blocks edited after the save must revert to pristine on load")

	# Fresh terrain instance + load.
	terrain.queue_free()
	await _frames(3)
	terrain = _make_terrain()
	await _frames(5)
	var h_fresh: int = terrain.debug_region_hash(region)
	var loaded2: bool = terrain.load_edits(SAVE_PATH)
	var h4: int = terrain.debug_region_hash(region)
	metrics["save_load_fresh_instance"] = {"h_before_load": h_fresh, "h_loaded": h4}
	_check(loaded2 and h4 == h1, "a fresh WorldTerrain must reproduce the saved voxels")
	# The reloaded crater (sphere r = 3 at y = 0) must also be collidable.
	cam.position = Vector3(110.0, 6.0, 110.0)
	var p := region.position + Vector3(4.0, 0.0, 6.0)
	var ok := false
	for i in 600:
		await process_frame
		if _ray_y(p.x, p.z) < -2.5:
			ok = true
			break
	_check(ok, "reloaded crater must be collidable")
