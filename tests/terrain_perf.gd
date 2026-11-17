extends SceneTree
## Windowed benchmark: 10 digs per second next to a third-person camera, vsync off, frame times recorded.
##   Godot_console.exe --path <project> --script res://tests/terrain_perf.gd --resolution 1280x720 -- <voxel_size> <tag> [mesh_block lod_voxel offset scenario]
## scenario "digs" (default) or "blasts": one explosion per second 25-70 m from the camera, craters 6-24 m.
## Writes res://tests/out/terrain_perf_<tag>.json

const BASELINE_S := 4.0
const DIG_S := 20.0
const DIGS_PER_S := 10.0

var terrain: Node3D
var cam: Camera3D
var voxel_size := 0.5
var tag := "run"
var phase := "load"
var t_phase := 0
var last_us := 0
var dig_acc := 0.0
var rng := RandomNumberGenerator.new()
var frames := {"baseline": [] as Array[float], "dig": [] as Array[float]}
var proc := {"baseline": [] as Array[float], "dig": [] as Array[float]}   # node _process of the frame (Voxel Tools + terrain + this)
var phys := {"baseline": [] as Array[float], "dig": [] as Array[float]}   # physics steps of the frame
var rest := {"baseline": [] as Array[float], "dig": [] as Array[float]}   # rendering, sync and the rest
var gpu := {"baseline": [] as Array[float], "dig": [] as Array[float]}
var end_mark: EndMark
var _t_proc := 0
var _t_phys := 0
var _prev := [0.0, 0.0]   # process and rest of the previous frame


## Runs after every other node's _process: marks the end of the process phase.
class EndMark extends Node:
	var t := 0

	func _process(_d: float) -> void:
		t = Time.get_ticks_usec()
var quiet := 0
var digs := 0
var latency_ms: Array[float] = []
var probes: Array = []
var scenario := "digs"
var blast_acc := 0.0
var blasts := 0
var blast_radii: Array[float] = []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		voxel_size = float(a[0])
	if a.size() > 1:
		tag = a[1]
	var mbs := int(a[2]) if a.size() > 2 else 16
	var max_lod_voxel := float(a[3]) if a.size() > 3 else 16.0
	var offset := a[4] != "0" if a.size() > 4 else true
	scenario = a[5] if a.size() > 5 else "digs"
	rng.seed = 99
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(TerrainTestEnv.make_environment())
	world.add_child(TerrainTestEnv.make_sun())
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.position = Vector3(0.0, 7.0, 24.0)
	world.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.0, 0.0), Vector3.UP)
	terrain = load("res://game/terrain/world_terrain.gd").new()
	terrain.voxel_size = voxel_size
	terrain.mesh_block_size = mbs
	terrain.max_lod_voxel_m = max_lod_voxel
	terrain.half_voxel_offset = offset
	world.add_child(terrain)
	end_mark = EndMark.new()
	end_mark.process_priority = 1 << 30
	world.add_child(end_mark)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


func _physics_process(_delta: float) -> bool:
	if _t_phys == 0:
		_t_phys = Time.get_ticks_usec()
	return false


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	var dt_ms := (now - last_us) / 1000.0 if last_us > 0 else 0.0
	last_us = now
	# dt_ms = previous frame's process + its rendering + this frame's physics steps.
	var phys_ms := (now - _t_phys) / 1000.0 if _t_phys > 0 else 0.0
	_prev = [(end_mark.t - _t_proc) / 1000.0 if _t_proc > 0 else 0.0, ((_t_phys if _t_phys > 0 else now) - end_mark.t) / 1000.0 if end_mark.t > 0 else 0.0, phys_ms]
	_t_phys = 0
	_t_proc = now
	match phase:
		"load":
			var n := 0
			var tasks: Dictionary = VoxelEngine.get_stats().get("tasks", {})
			for k in tasks:
				n += int(tasks[k])
			quiet = quiet + 1 if n == 0 else 0
			if quiet > 30:
				phase = "baseline"
				t_phase = now
		"baseline":
			_record("baseline", dt_ms)
			if now - t_phase > BASELINE_S * 1e6:
				phase = "dig"
				t_phase = now
		"dig":
			_record("dig", dt_ms)
			if scenario == "blasts":
				blast_acc += dt_ms / 1000.0
				if blast_acc >= 1.0:
					blast_acc -= 1.0
					_blast()
			else:
				dig_acc += dt_ms / 1000.0 * DIGS_PER_S
				while dig_acc >= 1.0:
					dig_acc -= 1.0
					_dig()
			_poll_probes(now)
			if now - t_phase > DIG_S * 1e6:
				_finish()
				return true
	return false


func _record(key: String, dt_ms: float) -> void:
	(frames[key] as Array).append(dt_ms)
	(proc[key] as Array).append(_prev[0])
	(rest[key] as Array).append(_prev[1])
	(phys[key] as Array).append(_prev[2])
	(gpu[key] as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))


func _dig() -> void:
	digs += 1
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * 18.0
	var p := Vector3(cos(a) * d, 0.0, sin(a) * d - 4.0)
	var r := rng.randf_range(1.0, 4.0) if digs % 10 != 0 else 6.0
	var space := terrain.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40.0, p.z), Vector3(p.x, -60.0, p.z), 1)
	var hit := space.intersect_ray(q)
	var y0: float = hit["position"].y if not hit.is_empty() else 0.0
	var sink := rng.randf_range(0.0, minf(1.5, r * 0.4))
	terrain.dig_sphere(Vector3(p.x, y0 - sink, p.z), r)
	if digs % 5 == 0 and not hit.is_empty():
		probes.append([p, y0 - sink - r * 0.6, Time.get_ticks_usec()])


## An explosion on the ground 25-70 m in front of the camera; energies give 6-24 m craters in soil.
func _blast() -> void:
	blasts += 1
	var a := rng.randf_range(-1.2, 1.2)
	var d := rng.randf_range(25.0, 70.0)
	var p := Vector3(sin(a) * d, 0.5, -cos(a) * d)
	var e := pow(rng.randf_range(6.0, 24.0), 3.0) * 1.41 * 16000.0
	blast_radii.append(terrain.explode(p, 30.0, e))


func _poll_probes(now: int) -> void:
	var space := terrain.get_world_3d().direct_space_state
	for i in range(probes.size() - 1, -1, -1):
		var pr: Array = probes[i]
		var p: Vector3 = pr[0]
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40.0, p.z), Vector3(p.x, -60.0, p.z), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["position"].y < pr[1]:
			latency_ms.append((now - int(pr[2])) / 1000.0)
			probes.remove_at(i)
		elif now - int(pr[2]) > 2e6:
			latency_ms.append(2000.0)
			probes.remove_at(i)


func _stats(a: Array) -> Dictionary:
	var s := a.duplicate()   # Array(a) would be the same array: sorting it would break index-aligned data
	s.sort()
	if s.is_empty():
		return {}
	var over := 0
	var sum := 0.0
	for v in s:
		sum += v
		if v > 16.667:
			over += 1
	return {"n": s.size(), "avg": sum / s.size(), "p50": s[s.size() / 2], "p95": s[int(s.size() * 0.95)], "p99": s[int(s.size() * 0.99)], "max": s[-1], "over_16_6ms_pct": 100.0 * over / s.size()}


## Frames over 16.6 ms in the measured phase: [second into the phase, frame, process, physics, render+rest, gpu]
## (times in ms).
func _spikes() -> Array:
	var out := []
	var f: Array = frames["dig"]
	var t := 0.0
	for i in f.size():
		t += f[i]
		if f[i] > 16.667:
			out.append([snappedf(t / 1000.0, 0.01), snappedf(f[i], 0.01), snappedf(proc["dig"][i], 0.01), snappedf(phys["dig"][i], 0.01), snappedf(rest["dig"][i], 0.01), snappedf(gpu["dig"][i], 0.01)])
	return out


func _finish() -> void:
	var out := {
		"voxel_size": voxel_size, "tag": tag, "scenario": scenario, "digs": digs, "digs_per_s": DIGS_PER_S, "seconds": DIG_S,
		"blasts": blasts, "blast_crater_radii_m": blast_radii,
		"frame_ms": {"baseline": _stats(frames["baseline"]), "dig": _stats(frames["dig"])},
		"process_ms": {"baseline": _stats(proc["baseline"]), "dig": _stats(proc["dig"])},
		"physics_ms": {"baseline": _stats(phys["baseline"]), "dig": _stats(phys["dig"])},
		"render_rest_ms": {"baseline": _stats(rest["baseline"]), "dig": _stats(rest["dig"])},
		"gpu_ms": {"baseline": _stats(gpu["baseline"]), "dig": _stats(gpu["dig"])},
		"collision_latency_ms": _stats(latency_ms),
		"spike_frames": _spikes(),
		"terrain": terrain.get_stats(),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	}
	var f := FileAccess.open("res://tests/out/terrain_perf_%s.json" % tag, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", false))
	f.close()
	root.get_viewport().get_texture().get_image().save_png("res://tests/out/terrain_perf_%s.png" % tag)
	print(JSON.stringify(out, "  ", false))
	quit(0)
