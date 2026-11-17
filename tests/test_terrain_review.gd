extends SceneTree
## Regression tests added in review (defects found after the first build). Headless:
##   Godot_console.exe --headless --path <project> --script res://tests/test_terrain_review.gd
## Writes res://tests/out/terrain_review_metrics.json and exits 0 when everything passed.

const SAVE_A := "user://terrain_review/a.sqlite"


class Receiver extends StaticBody3D:
	var hits := 0
	var on_hit: Callable

	func receive_damage(hit: DamageHit, _user_id: int) -> void:
		hits += 1
		if on_hit.is_valid():
			on_hit.call(hit)


## Digs from a physics callback (as debris impacts do) on one chosen physics frame.
class PhysDigger extends Node:
	var terrain: Node3D
	var fire_at := -1

	func _physics_process(_d: float) -> void:
		if Engine.get_physics_frames() != fire_at:
			return
		for i in 60:
			terrain.dig_sphere(Vector3(-40.0 + (i % 10) * 4.0, 0.0, 40.0 + (i / 10) * 4.0), 1.8)


## Edit time per frame, sampled after the terrain's _process (physics-step edits of the frame included).
class FrameMeter extends Node:
	var terrain: Node3D
	var last := -1
	var per_frame: Array[int] = []

	func _process(_d: float) -> void:
		var tot := int(terrain.get_stats()["edit_usec_total"])
		if last >= 0:
			per_frame.append(tot - last)
		last = tot


var terrain: Node3D
var world: Node3D
var cam: Camera3D
var router: Node
var game: Node
var metrics := {}
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	router = root.get_node("/root/DamageRouter")
	game = root.get_node("/root/Game")
	world = Node3D.new()
	root.add_child(world)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 6.0, 0.0)
	world.add_child(cam)
	terrain = load("res://game/terrain/world_terrain.gd").new()
	world.add_child(terrain)
	await _frames(90)

	_test_contracts()
	_test_sdf_outside_volume()
	await _test_radial_hits()
	await _test_nested_blasts()
	await _test_physics_phase_budget()
	await _test_reenter_tree()
	await _test_big_crater_frame_cost()
	await _test_wake_large_pile()
	await _test_ridge_save_load()
	await _test_load_during_async_edit()
	await _test_failed_save_keeps_old()
	await _test_free_cleanup()

	metrics["failures"] = failures
	metrics["passed"] = failures.is_empty()
	var f := FileAccess.open("res://tests/out/terrain_review_metrics.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(metrics, "  ", false))
	f.close()
	print(JSON.stringify(metrics, "  ", false))
	print("TERRAIN REVIEW TESTS ", "PASSED" if failures.is_empty() else "FAILED: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)


func _check(cond: bool, what: String) -> bool:
	if not cond:
		failures.append(what)
		push_error("FAIL: " + what)
	return cond


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _settle(max_frames: int = 300) -> void:
	for i in max_frames:
		if terrain.pending_edits() == 0:
			return
		await process_frame


func _craters() -> int:
	return int(terrain.get_stats().get("craters", 0))


# ------------------------------------------------------------------ contracts

func _test_contracts() -> void:
	var v: Node = terrain.voxels
	_check(v.collision_layer == Layers.TERRAIN and v.collision_mask == 0, "voxel colliders must be on Layers.TERRAIN with mask 0")
	_check(game.terrain == terrain, "Game.terrain must be set")
	_check(terrain.edit_budget_ms <= 2.0, "edit budget %.1f ms exceeds the 2 ms destruction budget" % terrain.edit_budget_ms)
	# The strata textures and hardness must follow MaterialDB (the lead's table).
	var mismatches: Array[String] = []
	for layer: StringName in MaterialDB.STRATA:
		var i := TerrainStrata.NAMES.find(layer)
		if i < 0 or TerrainStrata.TEX_IDS[TerrainStrata.TEX_SLOT[i]] != MaterialDB.STRATA[layer]:
			mismatches.append(String(layer))
	for layer: StringName in [&"asphalt", &"paving"]:
		var i := TerrainStrata.NAMES.find(layer)
		var d: Dictionary = MaterialDB.DATA[layer]
		if TerrainStrata.TEX_IDS[TerrainStrata.TEX_SLOT[i]] != d["tex"] or not is_equal_approx(TerrainStrata.RESISTANCE_KJ[i], d["toughness"]):
			mismatches.append(String(layer))
	metrics["materialdb_mismatches"] = mismatches
	_check(mismatches.is_empty(), "TerrainStrata disagrees with MaterialDB for %s" % str(mismatches))


# ------------------------------------------------------------------ queries outside the stored volume

func _test_sdf_outside_volume() -> void:
	var cases := [[Vector3(0, 150, 0), 150.0], [Vector3(100, 300, 100), 300.0], [Vector3(600, 0, 0), 88.0], [Vector3(0, -60, 0), 12.0]]
	var got := []
	for c in cases:
		var s: float = terrain.sdf_at(c[0])
		got.append("%s=%.2f" % [c[0], s])
		_check(absf(s - float(c[1])) < 1.0, "sdf_at(%s) = %.2f, expected about %.1f" % [c[0], s, c[1]])
	metrics["sdf_outside_volume"] = got
	# A big blast high above the ground must not leave a crater ridge floating in the sky.
	var before := _craters()
	var r: float = terrain.explode(Vector3(30.0, 150.0, 30.0), 80.0, 1.0e9)
	terrain.flush_edits()
	var sky_solid := 0
	for k in 64:
		var a := float(k) / 64.0 * TAU
		for y in [88.0, 91.0, 93.5, 95.0]:
			if terrain.is_solid_at(Vector3(30.0 + cos(a) * 27.0, y, 30.0 + sin(a) * 27.0)):
				sky_solid += 1
	metrics["high_blast"] = {"crater_r": r, "craters": _craters() - before, "solid_samples_in_sky": sky_solid}
	_check(r == 0.0 and sky_solid == 0, "blast 150 m up made a crater (r %.1f) / %d solid samples in the sky" % [r, sky_solid])


# ------------------------------------------------------------------ radial hits through DamageRouter

func _test_radial_hits() -> void:
	var dug_list: Array = []
	var on_dug := func(c: Vector3, rr: float, _l: StringName) -> void: dug_list.append([c, rr])
	terrain.dug.connect(on_dug)
	# Fire / heat area near (not at) the world origin: one pit under the blast, not at the collider origin.
	var c1 := Vector3(5.0, 0.5, 5.0)
	router.apply_blast(DamageHit.blast(c1, 10.0, 1.0e6, 0.0, DamageHit.Kind.HEAT), terrain.get_world_3d())
	terrain.flush_edits()
	var ok1 := dug_list.size() == 1 and Vector2(dug_list[0][0].x - c1.x, dug_list[0][0].z - c1.z).length() < 1.0
	metrics["radial_heat_digs"] = str(dug_list)
	_check(ok1, "radial HEAT blast at %s must dig once under it, got %s" % [c1, str(dug_list)])
	dug_list.clear()
	# Ground-pound style BLUNT shockwave far from the origin: one dent under it.
	var c2 := Vector3(-200.0, 0.5, 200.0)
	router.apply_blast(DamageHit.blast(c2, 6.0, 2.0e6, 0.0, DamageHit.Kind.BLUNT), terrain.get_world_3d())
	terrain.flush_edits()
	var ok2 := dug_list.size() == 1 and Vector2(dug_list[0][0].x - c2.x, dug_list[0][0].z - c2.z).length() < 1.0
	metrics["radial_blunt_digs"] = str(dug_list)
	_check(ok2, "radial BLUNT blast at %s must dent once under it, got %s" % [c2, str(dug_list)])
	terrain.dug.disconnect(on_dug)
	await _frames(2)


func _test_nested_blasts() -> void:
	# Chain reaction: a structure hit by blast A sets off blast B (same cause_id) inside A's delivery loop.
	var rcv := Receiver.new()
	rcv.collision_layer = Layers.STRUCTURE
	rcv.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	cs.shape = box
	rcv.add_child(cs)
	rcv.position = Vector3(60.0, 0.5, -60.0)
	world.add_child(rcv)
	var fired := [false]
	rcv.on_hit = func(h: DamageHit) -> void:
		if fired[0]:
			return
		fired[0] = true
		var b := DamageHit.blast(Vector3(75.0, 0.5, -60.0), 5.0, 3.0e6, 0.0)
		b.cause_id = h.cause_id
		router.apply_blast(b, terrain.get_world_3d())
	await _frames(3)
	var before := _craters()
	router.apply_blast(DamageHit.blast(Vector3(60.0, 0.5, -60.0), 8.0, 5.0e6, 0.0), terrain.get_world_3d())
	terrain.flush_edits()
	var a_dug: bool = terrain.sdf_at(Vector3(60.0, -1.5, -60.0)) > 0.0
	var b_dug: bool = terrain.sdf_at(Vector3(75.0, -1.0, -60.0)) > 0.0
	metrics["nested_blasts"] = {"craters": _craters() - before, "outer_crater": a_dug, "inner_crater": b_dug}
	_check(_craters() - before == 2 and a_dug and b_dug, "chain blasts must make 2 craters (got %d, outer %s, inner %s)" % [_craters() - before, a_dug, b_dug])
	rcv.queue_free()
	await _frames(2)
	_check(terrain.get("_blasts") == null or (terrain.get("_blasts") as Array).is_empty(), "announced blasts must be cleared at the end of the frame")


# ------------------------------------------------------------------ budget

func _test_physics_phase_budget() -> void:
	var meter := FrameMeter.new()
	meter.terrain = terrain
	meter.process_priority = 1000
	world.add_child(meter)
	var pd := PhysDigger.new()
	pd.terrain = terrain
	world.add_child(pd)
	await _frames(5)
	pd.fire_at = Engine.get_physics_frames() + 3
	await _frames(40)
	var mx := 0
	for v in meter.per_frame:
		mx = maxi(mx, v)
	var budget: float = terrain.edit_budget_ms
	metrics["physics_phase_digs"] = {"max_frame_edit_ms": mx / 1000.0, "budget_ms": budget}
	_check(mx / 1000.0 <= budget + 1.0, "60 digs from a physics callback spent %.2f ms of edits in one frame (budget %.1f)" % [mx / 1000.0, budget])
	meter.queue_free()
	pd.queue_free()
	terrain.flush_edits()
	await _frames(2)


# ------------------------------------------------------------------ tree re-entry

func _test_reenter_tree() -> void:
	world.remove_child(terrain)
	var cleared: bool = game.terrain == null
	world.add_child(terrain)
	await _frames(2)
	var connected: bool = router.blast.is_connected(Callable(terrain, "_on_router_blast"))
	var before := _craters()
	router.apply_blast(DamageHit.blast(Vector3(-60.0, 0.5, 100.0), 6.0, 3.0e6, 0.0), terrain.get_world_3d())
	terrain.flush_edits()
	metrics["reenter_tree"] = {"cleared_on_exit": cleared, "game_terrain": game.terrain == terrain, "blast_connected": connected, "crater_after": _craters() - before}
	_check(cleared and game.terrain == terrain and connected and _craters() - before == 1, "after remove_child + add_child the terrain must re-register (%s)" % str(metrics["reenter_tree"]))
	await _frames(2)


# ------------------------------------------------------------------ big crater: no frame stall

func _test_big_crater_frame_cost() -> void:
	await _settle()
	terrain.set_process(false)   # drive _process by hand to time it
	var blocks0 := int(terrain.get_stats()["edited_blocks"])
	var signals := [0]
	var count_edits := func(_box: AABB) -> void: signals[0] += 1
	terrain.terrain_edited.connect(count_edits)
	var r: float = terrain.explode(Vector3(-20.0, 0.5, -90.0), 40.0, 3.0e8)
	var worst := 0
	var frames := 0
	for i in 300:
		await process_frame
		var t := Time.get_ticks_usec()
		terrain._process(0.016)
		worst = maxi(worst, Time.get_ticks_usec() - t)
		frames = i + 1
		if terrain.pending_edits() == 0:
			break
	terrain.set_process(true)
	# The ridge must exist: material above the original surface on the rim.
	var rim := 0
	for k in 16:
		var a := float(k) / 16.0 * TAU
		for d in [1.05, 1.15, 1.25]:
			if terrain.get_layer_at(Vector3(-20.0 + cos(a) * r * d, 0.6, -90.0 + sin(a) * r * d)) == &"rubble":
				rim += 1
				break
	terrain.terrain_edited.disconnect(count_edits)
	metrics["big_crater"] = {"radius_m": r, "worst_process_ms": worst / 1000.0, "frames_to_finish": frames, "rim_dirs_with_rubble": "%d/16" % rim, "edited_blocks_added": int(terrain.get_stats()["edited_blocks"]) - blocks0, "terrain_edited_signals": signals[0]}
	_check(worst / 1000.0 <= 6.0, "24 m crater stalled a frame for %.1f ms" % (worst / 1000.0))
	_check(terrain.pending_edits() == 0 and rim >= 12, "24 m crater ridge incomplete (pending %d, rim %d/16)" % [terrain.pending_edits(), rim])
	_check(signals[0] >= 2 and signals[0] <= 6, "one crater should report bowl, lobes and ridge in at most 6 terrain_edited signals (got %d)" % signals[0])


# ------------------------------------------------------------------ waking a large pile

func _test_wake_large_pile() -> void:
	var shape := SphereShape3D.new()
	shape.radius = 0.15
	var bodies: Array[RigidBody3D] = []
	var c0 := Vector3(30.0, 0.0, -30.0)
	for i in 400:
		var b := RigidBody3D.new()
		b.collision_layer = Layers.DEBRIS_SMALL
		b.collision_mask = Layers.TERRAIN
		var bcs := CollisionShape3D.new()
		bcs.shape = shape
		b.add_child(bcs)
		b.position = c0 + Vector3((i % 20) * 0.4 - 3.8, 0.16, (i / 20) * 0.4 - 3.8)
		world.add_child(b)
		bodies.append(b)
	await _frames(60)
	for b in bodies:
		b.sleeping = true
	await _frames(2)
	var asleep := 0
	for b in bodies:
		asleep += 1 if b.sleeping else 0
	terrain.dig_sphere(c0 + Vector3(0.0, -6.0, 0.0), 9.0)
	terrain.flush_edits()
	await physics_frame
	var awake := 0
	for b in bodies:
		awake += 0 if b.sleeping else 1
	await _frames(120)
	var floating := 0
	for b in bodies:
		floating += 1 if b.global_position.y > 0.1 else 0
	metrics["wake_400"] = {"asleep_before": asleep, "awake_after_dig": awake, "floating_after_2s": floating}
	_check(asleep == 400 and awake == 400 and floating == 0, "dig under 400 sleeping bodies: %s" % str(metrics["wake_400"]))
	for b in bodies:
		b.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ persistence

func _test_ridge_save_load() -> void:
	# A crater ridge (ejecta ring) inside the saved region must round-trip exactly.
	var region := AABB(Vector3(-140.0, -12.0, -200.0), Vector3(40.0, 18.0, 40.0))
	terrain.explode(Vector3(-120.0, 0.5, -180.0), 12.0, 2.0e7)
	terrain.flush_edits()
	var h1: int = terrain.debug_region_hash(region)
	var ok_save: bool = terrain.save_edits(SAVE_A)
	terrain.dig_sphere(Vector3(-120.0, 0.0, -170.0), 6.0)
	terrain.add_sphere(Vector3(-128.0, 2.0, -188.0), 3.0)
	terrain.flush_edits()
	var h2: int = terrain.debug_region_hash(region)
	var ok_load: bool = terrain.load_edits(SAVE_A)
	var h3: int = terrain.debug_region_hash(region)
	metrics["ridge_save_load"] = {"saved": ok_save, "changed": h2 != h1, "loaded": ok_load, "restored": h3 == h1}
	_check(ok_save and ok_load and h2 != h1 and h3 == h1, "crater with ridge must survive save/load exactly: %s" % str(metrics["ridge_save_load"]))
	await _frames(2)


func _test_load_during_async_edit() -> void:
	# An async (r >= async_radius_m) dig still in flight when load_edits() runs must not end up in the loaded ground.
	var region := AABB(Vector3(150.0, -14.0, -150.0), Vector3(24.0, 16.0, 24.0))
	terrain.dig_sphere(region.get_center() + Vector3(0.0, 6.0, 0.0), 3.0)
	terrain.flush_edits()
	_check(terrain.save_edits(SAVE_A), "save before async test failed")
	var h_saved: int = terrain.debug_region_hash(region)
	await process_frame   # fresh edit budget, so the dig below is handed to Voxel Tools now (not queued)
	terrain.dig_sphere(region.get_center(), 12.0)
	var in_flight: int = terrain.pending_edits()
	var ok: bool = terrain.load_edits(SAVE_A)
	var h_now: int = terrain.debug_region_hash(region)
	await _frames(10)
	await _settle(200)
	var h_later: int = terrain.debug_region_hash(region)
	metrics["load_during_async_edit"] = {"in_flight_at_load": in_flight, "loaded": ok, "equal_after_load": h_now == h_saved, "equal_after_settle": h_later == h_saved}
	_check(in_flight == 1, "test setup: the r = 12 m dig should be in flight (pending %d)" % in_flight)
	_check(ok and h_later == h_saved, "async edit in flight during load_edits() changed the loaded ground: %s" % str(metrics["load_during_async_edit"]))


func _test_failed_save_keeps_old() -> void:
	var region := AABB(Vector3(-40.0, -10.0, 150.0), Vector3(20.0, 12.0, 20.0))
	terrain.dig_sphere(Vector3(-30.0, 0.0, 160.0), 4.0)
	terrain.flush_edits()
	_check(terrain.save_edits(SAVE_A), "first save failed")
	var h_a: int = terrain.debug_region_hash(region)
	terrain.dig_sphere(Vector3(-30.0, -3.0, 160.0), 5.0)
	terrain.flush_edits()
	# Block the save location: a directory where the new database would be written.
	var blocker := ProjectSettings.globalize_path(SAVE_A) + ".tmp"
	DirAccess.make_dir_recursive_absolute(blocker)
	var second: bool = terrain.save_edits(SAVE_A)
	DirAccess.remove_absolute(blocker)
	var loaded: bool = terrain.load_edits(SAVE_A)
	var h_loaded: int = terrain.debug_region_hash(region)
	metrics["failed_save"] = {"second_save_ok": second, "old_save_loads": loaded, "old_state_restored": h_loaded == h_a}
	_check(not second and loaded and h_loaded == h_a, "a failed save must keep the previous save: %s" % str(metrics["failed_save"]))
	await _frames(2)


# ------------------------------------------------------------------ cleanup

func _test_free_cleanup() -> void:
	await _settle()
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var subtree := _count(terrain)
	terrain.queue_free()
	await _frames(3)
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var connected := 0
	for c in router.blast.get_connections():
		connected += 1
	metrics["free_cleanup"] = {"subtree_nodes": subtree, "nodes_freed": nodes_before - nodes_after, "orphans_added": orphans_after - orphans_before, "game_terrain_null": game.terrain == null, "blast_connections_left": connected}
	_check(nodes_before - nodes_after == subtree and orphans_after <= orphans_before and game.terrain == null and connected == 0, "freeing the terrain must free its nodes and unregister: %s" % str(metrics["free_cleanup"]))


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children(true):
		c += _count(ch)
	return c
