extends Node
## Headless tests for the destruction module. Run with a fixed simulation step:
##   Godot --headless --fixed-fps 60 --path <P> res://tests/test_destruction.tscn
## (a scene wrapper is needed because autoload globals are not visible to --script scripts).
## Writes res://tests/out/destruction_metrics.json and exits with 0 when every check passes.

const D := preload("res://game/destruction/destruction_defs.gd")
const OUT := "res://tests/out/destruction_metrics.json"

var results := {}
var all_ok := true
var _t_last := 0
var phys_timer: PhysTimer


## Wall time from the first physics callback of a frame to the first process callback: physics scripts
## plus the Jolt step. (Performance.TIME_PHYSICS_PROCESS is a one-second maximum, not per frame.)
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
	phys_timer = PhysTimer.new()
	add_child(phys_timer)
	await get_tree().process_frame
	results["engine"] = Engine.get_version_info()["string"]
	results["started"] = Time.get_datetime_string_from_system()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
	if only == "" or only.contains("a"):
		await _test_wall_blast()
	if only == "" or only.contains("b"):
		await _test_ground_floor()
	if only == "" or only.contains("c"):
		await _test_tower_blasts()
	if only == "" or only.contains("e"):
		await _test_topple()
	if only == "" or only.contains("f"):
		await _test_masonry_one_side()
	if only == "" or only.contains("g"):
		await _test_rubble_and_teardown()
	var expected := ["a_wall_blast", "b_ground_floor_collapse", "c_tower_20_blasts", "e_tower_topple", "f_masonry_one_side",
		"g_rubble_and_teardown"]
	for name in expected:
		if only != "" and not only.contains(name.substr(0, 1)):
			continue
		if not results.has(name) or (results[name]["checks"] as Array).size() < 2:
			all_ok = false
			print("[FAIL] %s did not run to completion" % name)
	results["all_ok"] = all_ok
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("RESULT ", "PASS" if all_ok else "FAIL")
	get_tree().quit(0 if all_ok else 1)


func _check(test: String, name: String, ok: bool, detail: String) -> void:
	if not results.has(test):
		results[test] = {"checks": []}
	results[test]["checks"].append({"name": name, "ok": ok, "detail": detail})
	if not ok:
		all_ok = false
	print("[%s] %s %s: %s" % ["PASS" if ok else "FAIL", test, name, detail])


func _world() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500, 4, 500)
	cs.shape = box
	cs.position = Vector3(0, -2, 0)
	ground.add_child(cs)
	root.add_child(ground)
	var sm := StructureManager.create_world(root)
	root.set_meta(&"sm", sm)
	return root


func _sm(root: Node3D) -> StructureManager:
	return root.get_meta(&"sm")


func _free(root: Node3D) -> void:
	root.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Per-frame sampler: wall time between frames, destruction logic time, physics time, body counts.
class Sampler:
	var frame_ms := PackedFloat32Array()
	var logic_ms := PackedFloat32Array()
	var physics_ms := PackedFloat32Array()
	var active := PackedInt32Array()
	var awake := PackedInt32Array()
	var rubble := PackedInt32Array()
	var sm_ms := PackedFloat32Array()
	var damage_ms := PackedFloat32Array()
	var dm_ms := PackedFloat32Array()
	var dm_phys_ms := PackedFloat32Array()
	var _last := 0

	func start() -> void:
		_last = Time.get_ticks_usec()

	func sample(sm: StructureManager, with_awake: bool, phys_frame_ms: float) -> void:
		var now := Time.get_ticks_usec()
		frame_ms.append((now - _last) / 1000.0)
		_last = now
		var dm := sm.debris
		logic_ms.append((sm.frame_usec + sm.physics_usec + sm.last_damage_usec + dm.frame_usec + dm.physics_usec) / 1000.0)
		sm_ms.append((sm.frame_usec + sm.physics_usec) / 1000.0)
		damage_ms.append(sm.last_damage_usec / 1000.0)
		dm_ms.append(dm.frame_usec / 1000.0)
		dm_phys_ms.append(dm.physics_usec / 1000.0)
		physics_ms.append(phys_frame_ms)
		active.append(dm.active_count())
		rubble.append(dm.rubble_count)
		if with_awake:
			awake.append(dm.awake_count())

	static func stats(a: PackedFloat32Array) -> Dictionary:
		if a.is_empty():
			return {}
		var s := Array(a)
		s.sort()
		var total := 0.0
		for v in a:
			total += v
		return {"avg": snappedf(total / a.size(), 0.001), "p50": snappedf(s[s.size() / 2], 0.001),
			"p95": snappedf(s[int(s.size() * 0.95)], 0.001), "max": snappedf(s[s.size() - 1], 0.001), "n": a.size()}

	func summary() -> Dictionary:
		var aw := 0
		for v in awake:
			aw = maxi(aw, v)
		var ac := 0
		for v in active:
			ac = maxi(ac, v)
		return {"frame_ms": stats(frame_ms), "logic_ms": stats(logic_ms), "physics_ms": stats(physics_ms),
			"logic_breakdown_avg_ms": {"structure_process": stats(sm_ms).get("avg", 0.0), "damage_callbacks": stats(damage_ms).get("avg", 0.0),
				"debris_process": stats(dm_ms).get("avg", 0.0), "debris_physics": stats(dm_phys_ms).get("avg", 0.0)},
			"max_active_bodies": ac, "max_awake_bodies": aw, "final_rubble": rubble[rubble.size() - 1] if not rubble.is_empty() else 0}


func _conservation(test: String, sm: StructureManager, bid: int) -> void:
	# Wait for queued fractures: a destroyed element only becomes pieces when its job runs.
	for i in 600:
		if sm._fracture_jobs.is_empty() and sm._builds.is_empty() and sm._breaking.is_empty():
			break
		await get_tree().process_frame
	var b := sm.buildings[bid]
	var total := b.data.total_mass()
	var removed := total - sm.intact_mass(bid)
	var dm := sm.debris
	var held := dm.debris_mass + dm.rubble_mass
	var recount := dm.recount_debris_mass() + dm.recount_rubble_mass()
	var err := absf(held - removed) / maxf(removed, 1.0)
	results[test]["mass"] = {"building_kg": total, "removed_kg": removed, "debris_kg": dm.debris_mass, "rubble_kg": dm.rubble_mass,
		"recount_kg": recount, "relative_error": err, "fractured_kg": sm.mass_fractured, "detached_kg": sm.mass_detached}
	_check(test, "conservation", err <= 0.05 and absf(recount - held) <= maxf(held, 1.0) * 0.001,
		"removed %.0f kg, debris+rubble %.0f kg (recount %.0f), error %.3f%%" % [removed, held, recount, err * 100.0])


## Rubble resting on nothing (frozen in flight, or left behind when what carried it went away). Settled
## rubble must touch the ground, an intact element or other grounded rubble.
func _floating(test: String, sm: StructureManager) -> void:
	var t0 := Time.get_ticks_msec()
	var fl := sm.debris.floating_rubble()
	var dm := sm.debris
	results[test]["floating_rubble"] = fl
	results[test]["forced_freezes"] = dm.forced_freezes
	results[test]["forced_fast_freezes"] = dm.forced_fast_freezes
	results[test]["dropped_freezes"] = dm.dropped_freezes
	results[test]["rubble_support_wakes"] = dm.rubble_support_wakes
	results[test]["support_checks"] = dm.support_checks
	print("  %s floating rubble: %d of %d pieces, %.0f kg, max gap %.1f m %s; forced freezes %d (moving %d, dropped %d); support checks %d, wakes %d [%d ms]" % [test,
		fl["count"], fl["total"], fl["mass"], fl["max_gap"], fl["by_reason"], dm.forced_freezes, dm.forced_fast_freezes, dm.dropped_freezes,
		dm.support_checks, dm.rubble_support_wakes, Time.get_ticks_msec() - t0])
	print("    pending support checks: ", fl["pending_checks"])
	for s in fl["samples"]:
		print("    floating: ", s)
	var allowed := maxi(3, int(fl["total"]) / 500)
	_check(test, "no floating rubble", int(fl["count"]) <= allowed and float(fl["max_gap"]) <= 2.0,
		"%d of %d rubble pieces rest on nothing (allowed %d), largest gap under one %.1f m (allowed 2.0 m)" % [fl["count"], fl["total"], allowed, fl["max_gap"]])


# --------------------------------------------------------------------------------------------------

func _test_wall_blast() -> void:
	var test := "a_wall_blast"
	results[test] = {"checks": []}
	var root := _world()
	var sm := _sm(root)
	var bid := sm.spawn_building(D.Style.APARTMENT, 7, Transform3D.IDENTITY)
	sm.fracture.flush()
	await get_tree().process_frame
	var b := sm.buildings[bid]
	var initial := sm.count_intact(bid)
	var target := -1
	for e in sm.find_elements(bid, 2, [D.Kind.WALL]):
		if is_equal_approx(b.data.dims[e].y, D.STOREY_H):
			target = e
			break
	var xf := sm.element_world_transform(bid, target)
	var normal := xf.basis.z.normalized()
	if normal.dot(xf.origin - b.xform.origin) < 0.0:
		normal = -normal
	var center := xf.origin + normal * 0.6
	DamageRouter.apply_blast(DamageHit.blast(center, 1.8, 260000.0, 6000.0))
	for i in 240:
		await get_tree().process_frame
	var intact := sm.count_intact(bid)
	results[test]["target_element"] = target
	results[test]["target_size"] = str(b.data.dims[target])
	results[test]["destroyed"] = sm.elements_destroyed
	results[test]["intact_before"] = initial
	results[test]["intact_after"] = intact
	_check(test, "wall panel destroyed", b.state[target] == D.State.DESTROYED, "element %d state %d" % [target, b.state[target]])
	_check(test, "building stands", intact >= initial * 0.95 and sm.topples == 0, "%d of %d elements intact, topples %d" % [intact, initial, sm.topples])
	var un := sm.count_unanchored(bid)
	var unsup := b.solver.count_alive_unsupported()
	_check(test, "all intact elements anchored", un == 0 and unsup == 0, "unanchored %d, unsupported %d" % [un, unsup])
	_floating(test, sm)
	await _free(root)


func _test_ground_floor() -> void:
	var test := "b_ground_floor_collapse"
	results[test] = {"checks": []}
	var root := _world()
	var sm := _sm(root)
	var bid := sm.spawn_building(D.Style.APARTMENT, 7, Transform3D.IDENTITY)
	sm.fracture.flush()
	await get_tree().process_frame
	var b := sm.buildings[bid]
	var upper := 0
	for i in b.data.count():
		if b.data.storey[i] >= 1:
			upper += 1
	var targets := sm.find_elements(bid, 0, [D.Kind.PIER, D.Kind.WALL, D.Kind.SILL, D.Kind.COLUMN])
	for e in targets:
		sm.destroy_element(bid, e)
	var sampler := Sampler.new()
	sampler.start()
	var t_detached := -1.0
	var t_down := -1.0
	var frames := 0
	while frames < 720:
		await get_tree().process_frame
		frames += 1
		sampler.sample(sm, frames % 10 == 0, phys_timer.last_ms)
		if t_detached < 0.0:
			var still := 0
			for i in b.data.count():
				if b.data.storey[i] >= 1 and b.state[i] == D.State.INTACT:
					still += 1
			if still == 0:
				t_detached = frames / 60.0
		if t_down < 0.0 and t_detached >= 0.0 and frames % 6 == 0:
			if maxf(sm.debris.max_debris_height(), sm.debris.max_rubble_height()) < 6.0:
				t_down = frames / 60.0
	var top := maxf(sm.debris.max_debris_height(), sm.debris.max_rubble_height())
	var limit := b.data.bounds.size.y * 0.5
	var high := sm.debris.pieces_above(limit)
	if not high.is_empty():
		results[test]["pieces_above_8m"] = str(high.slice(0, 10))
		for h in high.slice(0, 10):
			var info: String = h[0]
			var parts := info.split("/")
			var elem := -1
			if parts.size() == 2:
				elem = int(parts[1])
			var kind := D.KIND_NAMES[b.data.kind[elem]] if elem >= 0 else "piece"
			print("  high piece: %s %s at %s mass %.0f" % [info, kind, h[1], h[2]])
	results[test]["destroyed_ground_verticals"] = targets.size()
	results[test]["upper_elements"] = upper
	results[test]["t_all_upper_detached_s"] = t_detached
	results[test]["t_debris_below_6m_s"] = t_down
	results[test]["highest_piece_after_12s_m"] = top
	results[test]["clusters_created"] = sm.clusters_created
	results[test]["perf"] = sampler.summary()
	results[test]["building_height_m"] = b.data.bounds.size.y
	var h95 := sm.debris.mass_height_percentile(0.95)
	var h50 := sm.debris.mass_height_percentile(0.5)
	results[test]["mass_height_p95_m"] = h95
	results[test]["mass_height_p50_m"] = h50
	var h_limit := b.data.bounds.size.y * 0.4
	_check(test, "full collapse within 12 s", t_detached >= 0.0 and t_detached <= 12.0 and h95 < h_limit,
		"all %d upper elements detached at %.2f s; after 12 s 95%% of the mass lies below %.1f m (median %.1f m, limit 40%% of %.1f m = %.1f m); highest fragment %.1f m" % [upper, t_detached, h95, h50, b.data.bounds.size.y, h_limit, top])
	_check(test, "no unanchored intact element", sm.count_unanchored(bid) == 0, "unanchored %d, intact %d" % [sm.count_unanchored(bid), sm.count_intact(bid)])
	await _conservation(test, sm, bid)
	_floating(test, sm)
	await _free(root)


func _test_tower_blasts() -> void:
	var test := "c_tower_20_blasts"
	results[test] = {"checks": []}
	var root := _world()
	var sm := _sm(root)
	var bid := sm.spawn_building(D.Style.TOWER, 11, Transform3D.IDENTITY)
	sm.fracture.flush()
	await get_tree().process_frame
	var b := sm.buildings[bid]
	var box := b.data.bounds
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ref_before := _reference_ms()
	var sampler := Sampler.new()
	sampler.start()
	var blasts := 0
	var frames := 0
	var blast_log: Array = []
	while frames < 20 * 15 + 420:
		if frames % 15 == 0 and blasts < 20:
			var p := Vector3(rng.randf_range(box.position.x - 1.0, box.end.x + 1.0), rng.randf_range(1.0, box.end.y - 2.0),
				rng.randf_range(box.position.z - 1.0, box.end.z + 1.0))
			var h := DamageHit.blast(p, rng.randf_range(4.0, 7.0), rng.randf_range(200000.0, 600000.0), rng.randf_range(8000.0, 20000.0))
			DamageRouter.apply_blast(h)
			blast_log.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1), snappedf(h.radius, 0.1), roundi(h.energy)])
			blasts += 1
		await get_tree().process_frame
		frames += 1
		sampler.sample(sm, frames % 5 == 0, phys_timer.last_ms)
		if frames % 60 == 0:
			var dm := sm.debris
			print("  c f%d frame %.1f ms logic %.2f (sm %.2f dmg %.2f dm %.2f dmphys %.2f) active %d rubble %d builds %d fr %d breaking %d topples %d" % [frames,
				sampler.frame_ms[-1], sampler.logic_ms[-1], sampler.sm_ms[-1], sampler.damage_ms[-1], sampler.dm_ms[-1], sampler.dm_phys_ms[-1],
				dm.active_count(), dm.rubble_count, sm._builds.size(), sm._fracture_jobs.size(), sm._breaking.size(), sm.topples])
	var pdm := sm.debris
	print("  c totals: %d elements destroyed (%d coarse fractures), %d bodies spawned, %d frozen (%d forced, %d dropped), %d support checks, %d rubble fell again; freeze time %.0f ms, spawn time %.0f ms" % [
		sm.elements_destroyed, sm.coarse_fractures, pdm.spawned_total, pdm.frozen_total, pdm.forced_freezes, pdm.dropped_freezes, pdm.support_checks,
		pdm.rubble_support_wakes, pdm.prof_freeze_usec / 1000.0, pdm.prof_spawn_usec / 1000.0])
	results[test]["blasts"] = blast_log
	results[test]["elements"] = b.data.count()
	results[test]["intact_after"] = sm.count_intact(bid)
	results[test]["elements_destroyed"] = sm.elements_destroyed
	results[test]["clusters_created"] = sm.clusters_created
	results[test]["topples"] = sm.topples
	results[test]["perf"] = sampler.summary()
	var lstats: Dictionary = sampler.summary()["logic_ms"]
	# The same script work takes up to 70 % longer when this laptop is busy or throttled. The fixed loop
	# says how fast the machine was during this run (REFERENCE_NOMINAL_MS when it is not held back); the
	# check itself stays absolute, the detail shows what the number means at nominal speed.
	var ref := (ref_before + _reference_ms()) * 0.5
	results[test]["machine_reference_ms"] = ref
	_check(test, "destruction logic <= 2 ms avg", lstats["avg"] <= 2.0, "avg %.3f ms, p95 %.3f ms, max %.3f ms; machine reference %.1f ms (nominal %.0f): %.2f ms at nominal speed" % [
		lstats["avg"], lstats["p95"], lstats["max"], ref, REFERENCE_NOMINAL_MS, lstats["avg"] * REFERENCE_NOMINAL_MS / maxf(ref, 1.0)])
	_check(test, "no unanchored intact element", sm.count_unanchored(bid) == 0, "unanchored %d" % sm.count_unanchored(bid))
	await _conservation(test, sm, bid)
	_floating(test, sm)
	await _free(root)


## Time of _reference_ms() on the development laptop when it is not throttled (lowest value seen).
const REFERENCE_NOMINAL_MS := 17.0


## A fixed amount of script work (vector maths and array writes), timed: a yardstick for machine speed.
func _reference_ms() -> float:
	var t0 := Time.get_ticks_usec()
	var acc := Vector3.ZERO
	var arr := PackedFloat32Array()
	arr.resize(1024)
	for i in 300000:
		acc += Vector3(i & 7, 1.0, 0.5).cross(Vector3.UP) * 0.001
		arr[i & 1023] = acc.x
	return (Time.get_ticks_usec() - t0) / 1000.0


## Masonry with every ground-floor wall gone except the back one: the weight above no longer lies over the
## remaining wall. The block must not hinge over as one rigid box (it used to, and came to rest standing on
## its end); the back wall is crushed and the storeys above drop and pancake.
func _test_masonry_one_side() -> void:
	var test := "f_masonry_one_side"
	results[test] = {"checks": []}
	var root := _world()
	var sm := _sm(root)
	var bid := sm.spawn_building(D.Style.APARTMENT, 7, Transform3D.IDENTITY)
	sm.fracture.flush()
	await get_tree().process_frame
	var b := sm.buildings[bid]
	# 35 cm behind the line of the front wall. Measured on the walls, not on the bounds: awnings and
	# ledges stand out in front of the wall (2026-11-17).
	var back_z := INF
	for e in sm.find_elements(bid, 0, [D.Kind.PIER, D.Kind.WALL]):
		back_z = minf(back_z, b.data.xf[e].origin.z)
	back_z += 0.35
	var upper := 0
	var heights: Array[Vector2] = []
	for i in b.data.count():
		if b.data.storey[i] >= 1:
			upper += 1
		heights.append(Vector2((b.xform * b.data.xf[i]).origin.y, b.data.mass[i]))
	heights.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var h95_before := 0.0
	var acc := 0.0
	for h in heights:
		acc += h.y
		if acc >= b.data.total_mass() * 0.95:
			h95_before = h.x
			break
	var biggest := [0]
	sm.cluster_detached.connect(func(_body: RigidBody3D, _id: int, elems: PackedInt32Array) -> void:
		biggest[0] = maxi(biggest[0], elems.size()))
	var cut := 0
	for e in sm.find_elements(bid, 0, [D.Kind.PIER, D.Kind.WALL, D.Kind.SILL]):
		if b.data.xf[e].origin.z > back_z:
			sm.destroy_element(bid, e)
			cut += 1
	var trace := PackedFloat32Array()
	for i in 600:
		await get_tree().process_frame
		if i % 60 == 59:
			trace.append(snappedf(sm.debris.mass_height_percentile(0.95), 0.1))
		if i < 240 and i % 20 == 19:
			var s0 := [0, 0, 0, 0]
			var s0_vert := 0
			for e in b.data.count():
				if b.data.storey[e] == 0:
					s0[b.state[e]] += 1
					if b.state[e] == D.State.INTACT and b.data.role[e] == D.Role.VERTICAL:
						s0_vert += 1
			print("    f t=%.2f s0 %s intact verticals %d crush queue %d failed %d active %d rubble %d top %.1f" % [(i + 1) / 60.0, s0, s0_vert, sm._crush_t.size(),
				sm.storeys_failed, sm.debris.active_count(), sm.debris.rubble_count, sm.debris.mass_height_percentile(1.0)])
	var still := 0
	for i in b.data.count():
		if b.data.storey[i] >= 1 and b.state[i] == D.State.INTACT:
			still += 1
	var h95 := sm.debris.mass_height_percentile(0.95)
	# Diagnostics only (the pile height varies from run to run): how the pile came down over time and
	# what is left of each storey.
	var per_storey := {}
	for i in b.data.count():
		var key := "s%d" % b.data.storey[i]
		if not per_storey.has(key):
			per_storey[key] = [0, 0, 0, 0]
		per_storey[key][b.state[i]] += 1
	print("  f h95 every second: %s; percentiles 25/50/75/100: %.1f %.1f %.1f %.1f; active %d rubble %d forced %d dropped %d; clusters %d; per storey [intact, pending, destroyed, detached]: %s" % [trace,
		sm.debris.mass_height_percentile(0.25), sm.debris.mass_height_percentile(0.5), sm.debris.mass_height_percentile(0.75), sm.debris.mass_height_percentile(1.0),
		sm.debris.active_count(), sm.debris.rubble_count, sm.debris.forced_freezes, sm.debris.dropped_freezes, sm.clusters_created, JSON.stringify(per_storey)])
	# Like a soft-storey failure the block drops at least one storey; it need not pancake completely.
	var h_limit := h95_before - 2.0
	var centroid := sm.debris.mass_centroid()
	results[test]["walls_cut"] = cut
	results[test]["topples"] = sm.topples
	results[test]["storeys_failed"] = sm.storeys_failed
	results[test]["largest_cluster_elements"] = biggest[0]
	results[test]["mass_height_p95_m"] = h95
	results[test]["mass_height_p95_before_m"] = h95_before
	results[test]["debris_centroid"] = str(centroid)
	_check(test, "no rigid topple", sm.topples == 0 and sm.storeys_failed >= 1 and biggest[0] <= sm.cluster_max_elements,
		"topples %d, failed storeys %d, largest falling cluster %d elements (limit %d)" % [sm.topples, sm.storeys_failed, biggest[0], sm.cluster_max_elements])
	_check(test, "upper storeys came down", still == 0 and h95 <= h_limit and absf(centroid.z) < b.data.bounds.size.z * 0.3,
		"%d of %d upper elements still intact after 10 s; 95%% of the mass below %.1f m (was %.1f m, limit %.1f m); debris centroid %s" % [still, upper,
			h95, h95_before, h_limit, centroid])
	await _conservation(test, sm, bid)
	_floating(test, sm)
	await _free(root)


## wake_rubble (grab / throw) round trip, then teardown in the middle of a collapse: every server body,
## DamageRouter registration and node of the module must be gone afterwards.
func _test_rubble_and_teardown() -> void:
	var test := "g_rubble_and_teardown"
	results[test] = {"checks": []}
	var handlers0: int = DamageRouter._rid_handlers.size()
	var orphans0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var root := _world()
	var sm := _sm(root)
	var dm := sm.debris
	var bid := sm.spawn_building(D.Style.APARTMENT, 7, Transform3D.IDENTITY)
	sm.fracture.flush()
	await get_tree().process_frame
	for e in sm.find_elements(bid, 0, [D.Kind.PIER, D.Kind.WALL, D.Kind.SILL]):
		sm.destroy_element(bid, e)
	for i in 420:
		await get_tree().process_frame
	# Wake the heaviest settled piece as if the cat grabbed it.
	var best := RID()
	var best_m := 0.0
	for rid in dm.rubble_rids():
		var m: float = dm._rb_mass[dm._rb_by_rid[rid]]
		if m > best_m:
			best_m = m
			best = rid
	var woken := []
	dm.rubble_woken.connect(func(r: RID, body: RigidBody3D) -> void: woken.append([r, body]))
	var held0 := dm.debris_mass + dm.rubble_mass
	var rubble0 := dm.rubble_count
	var body := dm.wake_rubble(best)
	var ok := body != null and is_instance_valid(body) and body.is_inside_tree() and body.visible and not dm.is_rubble(best) \
		and dm.rubble_count == rubble0 - 1 and absf(body.mass - best_m) < 0.01 * best_m + 0.5 and woken.size() == 1 \
		and DamageRouter._rid_handlers.has(body.get_rid()) and absf(dm.debris_mass + dm.rubble_mass - held0) < 1.0
	_check(test, "wake_rubble returns a live body", ok, "mass %.0f kg -> body %s (mass %.0f), rubble %d -> %d, signal %d, held mass change %.2f kg" % [best_m,
		body, body.mass if body != null else 0.0, rubble0, dm.rubble_count, woken.size(), dm.debris_mass + dm.rubble_mass - held0])
	if body != null:
		body.apply_central_impulse(Vector3(0.0, 3.0, 0.0) * body.mass)
	# A second building collapses; tear everything down while clusters are still being built, bodies fall
	# and fracture jobs wait.
	var tid := sm.spawn_building(D.Style.TOWER, 11, Transform3D(Basis.IDENTITY, Vector3(70.0, 0.0, 0.0)))
	for e in sm.find_elements(tid, 0, [D.Kind.COLUMN, D.Kind.CORE]):
		sm.destroy_element(tid, e)
	for i in 4:
		await get_tree().process_frame
	results[test]["in_flight_at_teardown"] = {"active": dm.active_count(), "rubble": dm.rubble_count, "fracture_jobs": sm._fracture_jobs.size(),
		"builds": sm._builds.size()}
	var space := root.get_world_3d().direct_space_state
	await _free(root)
	var q := PhysicsShapeQueryParameters3D.new()
	var big := BoxShape3D.new()
	big.size = Vector3(1000, 400, 1000)
	q.shape = big
	q.collision_mask = 0xFFFFFFFF
	var left := space.intersect_shape(q, 64).size()
	var handlers := DamageRouter._rid_handlers.size() - handlers0
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphans0
	_check(test, "teardown leaves nothing behind", left == 0 and handlers == 0 and orphans <= 0 and Game.structures == null and Game.debris == null,
		"bodies left in the space %d, DamageRouter registrations left %d, new orphan nodes %d, Game refs %s %s" % [left, handlers, orphans, Game.structures, Game.debris])


func _test_topple() -> void:
	var test := "e_tower_topple"
	results[test] = {"checks": []}
	var root := _world()
	var sm := _sm(root)
	var bid := sm.spawn_building(D.Style.TOWER, 11, Transform3D.IDENTITY)
	sm.fracture.flush()
	await get_tree().process_frame
	var b := sm.buildings[bid]
	var box := b.data.bounds
	var cut_x := box.position.x + box.size.x * 0.45
	var toppled := []
	sm.building_toppled.connect(func(id: int, st: int) -> void: toppled.append(st))
	var compound: Array = []
	sm.cluster_detached.connect(func(body: RigidBody3D, _id: int, elems: PackedInt32Array) -> void:
		if elems.size() > 200:
			compound.append(body))
	var cut := 0
	for e in sm.find_elements(bid, 0, [D.Kind.COLUMN, D.Kind.CORE]):
		if b.data.xf[e].origin.x > cut_x:
			sm.destroy_element(bid, e)
			cut += 1
	var start_com := Vector3.ZERO
	var tilt := 0.0
	var moved := Vector3.ZERO
	var max_shift_x := 0.0
	for i in 600:
		await get_tree().process_frame
		if not compound.is_empty() and is_instance_valid(compound[0]):
			# The compound breaks up when its hinge phase ends, so its largest motion is what counts.
			var body: RigidBody3D = compound[0]
			var com := body.global_transform * body.center_of_mass
			if start_com == Vector3.ZERO:
				start_com = com
			moved = com - start_com
			max_shift_x = maxf(max_shift_x, moved.x)
			tilt = maxf(tilt, rad_to_deg(acos(clampf(body.global_transform.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0))))
	var pile := sm.debris.mass_centroid()
	var centre := b.xform * b.data.bounds.get_center()
	results[test]["columns_cut"] = cut
	results[test]["topple_storeys"] = toppled
	results[test]["compound_com_shift"] = str(moved)
	results[test]["compound_max_shift_x_m"] = max_shift_x
	results[test]["compound_max_tilt_deg"] = tilt
	results[test]["pile_centroid_shift_x_m"] = pile.x - centre.x
	results[test]["highest_piece_after_10s_m"] = maxf(sm.debris.max_debris_height(), sm.debris.max_rubble_height())
	results[test]["clusters_created"] = sm.clusters_created
	_check(test, "one side cut topples toward the cut", not toppled.is_empty() and max_shift_x > 1.0 and tilt > 5.0 and pile.x - centre.x > 2.0,
		"topple storeys %s, compound max shift toward the cut %.1f m (final %s), max tilt %.1f deg, debris centroid moved %.1f m toward the cut, %d clusters" % [toppled,
			max_shift_x, moved, tilt, pile.x - centre.x, sm.clusters_created])
	await _conservation(test, sm, bid)
	_floating(test, sm)
	await _free(root)
