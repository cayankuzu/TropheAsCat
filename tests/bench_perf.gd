extends Node
## Performance bench (2026-11-17). Builds the city as the game does (the full one, or the browser demo's with
## "-- --lite"), lets Trophe land, then measures with vsync off, frame by frame: the wall-clock frame time;
## the script time of every part of the world in the process pass and in the physics callbacks (probe nodes
## stand between the children of main.tscn: at equal priority the tree order is the order of the callbacks);
## the time between the end of the physics callbacks and the next tick or the process pass (deferred calls,
## the physics step and the transform sync of moving bodies); and the render CPU / GPU time. Stretches:
## quiet (she stands at the landing spot) and chaos (a blast near her every second). Every frame over 33 ms
## is logged with its split and its three most expensive parts. Prints BENCH lines and writes
## tests/out/bench_<mode>.json. (Performance.TIME_PROCESS is the worst frame of the last second.)
## Run: Godot --path <P> res://tests/bench_perf.tscn --resolution 1280x720 [--rendering-driver opengl3]
##      -- [--lite] [--quality=0|1|2] [--tag=name] [--frames=N] [--warmup] [--title]

const OUT := "res://tests/out/"
const SETTLE := 300        ## frames after begin() before measuring (the fall from the sky, the first wakes)
const QUIET := 400
const CHAOS := 480
const BLAST_EVERY := 60
const HITCH_MS := 33.4
## Spots round the landing place (x, z offsets from main.SPAWN) where the chaos stretch sets off its blasts.
const BLASTS: Array[Vector2] = [Vector2(0.0, -14.0), Vector2(12.0, 6.0), Vector2(-12.0, 6.0), Vector2(14.0, 26.0),
	Vector2(-14.0, 26.0), Vector2(0.0, 40.0), Vector2(18.0, -10.0)]


## Stamps the time when its callbacks run; where it stands decides what the gaps between stamps measure.
class Probe:
	extends Node
	var proc_usec := 0
	var phys_usec := 0

	func _init(priority: int) -> void:
		process_priority = priority
		process_physics_priority = priority
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_d: float) -> void:
		proc_usec = Time.get_ticks_usec()

	func _physics_process(_d: float) -> void:
		phys_usec = Time.get_ticks_usec()


var lite := OS.get_cmdline_user_args().has("--lite")
var quality := -1
var tag := ""
var frames_scale := 1.0

var _main: Node3D
var _phase := "build"
var _frame := 0
var _last_usec := 0
var _rows: Array[Dictionary] = []
var _report := {}
var _vp_rid: RID
var _build_start := 0
var _first: Probe          # runs before every other callback
var _last: Probe           # runs after every other physics callback
var _parts: Array[Probe] = []       # _parts[i] stands before part i of main; the last one after the last part
var _part_names: PackedStringArray = []
var _phys_cb := 0.0        # physics callback ms summed over the ticks since the last process frame
var _phys_other := 0.0
var _ticks := 0
var _part_phys := PackedFloat64Array()   # per part, physics ms summed over the ticks of this frame
var _proc_start := 0       # process_frame signal: the process pass begins
var _tick_first := 0       # start of the first physics tick of this frame (0: no tick yet)
var _prev_end := 0         # this node's _process in the previous frame (the process pass was over)
var _blast_ms := 0.0       # what DamageRouter.apply_blast took in this frame
var _hitches: Array = []
var _census_list: Array = []
var _census_i := -1
var _census_base := 0.0
var _acc := {}             # stretch -> {"proc": PackedFloat64Array sum, "phys": sum, "max": max per frame}
var _sections := {}        # stretch -> {section: [ms, calls, worst ms in one frame]} (PerfProbe)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			quality = int(a.get_slice("=", 1))
		elif a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
		elif a.begins_with("--frames="):
			frames_scale = float(a.get_slice("=", 1))
	if lite:
		Game.lite = true
		CityLayout.BLOCKS_OUT = 1
		CityLayout.INNER_OUT = 1
	if quality < 0:
		quality = 0 if lite else 2
	PerfProbe.on = true
	Perf.governor = false   # the bench measures one fixed level and resolution
	Perf.set_choice(quality)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_first = Probe.new(-2147483647)
	_last = Probe.new(2147483647)
	add_child(_first)
	add_child(_last)
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(func() -> void: _proc_start = Time.get_ticks_usec())
	process_priority = 2147483646   # just before the last probe: the process pass is nearly over
	_build_start = Time.get_ticks_msec()
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Probes between the children of main (Trophe and the HUD came in with begin()).
func _place_part_probes() -> void:
	var kids := _main.get_children()
	_part_names.clear()
	for k in kids:
		var p := Probe.new(0)
		_main.add_child(p)
		_main.move_child(p, k.get_index())
		_parts.append(p)
		_part_names.append(String(k.name))
	var tail := Probe.new(0)
	_main.add_child(tail)
	_parts.append(tail)
	_part_phys.resize(_part_names.size())
	_part_phys.fill(0.0)


## Start of a physics tick, before its callbacks: closes the previous tick if it ran in this frame.
func _on_physics_frame() -> void:
	var now := Time.get_ticks_usec()
	if _tick_first == 0:
		_tick_first = now
	_close_tick(_prev_end)


var _closed_tick := 0   # the first probe's stamp of the last tick counted


func _close_tick(since: int) -> void:
	if _first.phys_usec <= since or _first.phys_usec == _closed_tick or _last.phys_usec < _first.phys_usec:
		return
	_closed_tick = _first.phys_usec
	_phys_cb += (_last.phys_usec - _first.phys_usec) / 1000.0
	_ticks += 1
	for i in _part_names.size():
		var a := _parts[i].phys_usec
		var b := _parts[i + 1].phys_usec
		if a > 0 and b >= a:
			_part_phys[i] += (b - a) / 1000.0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if _phase == "chaos" and _frame % BLAST_EVERY == 0:
		var b0 := Time.get_ticks_usec()
		_blast(int(_frame / float(BLAST_EVERY)))
		_blast_ms = (Time.get_ticks_usec() - b0) / 1000.0
		now = Time.get_ticks_usec()
	var proc_ms := (now - _first.proc_usec) / 1000.0 if _first.proc_usec > 0 else 0.0
	_close_tick(_prev_end)
	# Physics of this frame: from the start of its first tick to the process pass (callbacks, deferred calls,
	# the physics step, the sync of moving bodies); the rest of the physics share is not callbacks.
	var phys_total := (_proc_start - _tick_first) / 1000.0 if _tick_first > 0 and _proc_start > _tick_first else 0.0
	var tail_other := maxf(phys_total - _phys_cb, 0.0)
	# Before this frame's physics (or process pass): the previous frame's rendering, deferred calls, the swap.
	var start := _tick_first if _tick_first > 0 else _proc_start
	var post_ms := (start - _prev_end) / 1000.0 if _prev_end > 0 and start > _prev_end else 0.0
	_frame += 1
	match _phase:
		"build":
			if _main.get("playing") and Game.player != null:
				_report["build_ms"] = Time.get_ticks_msec() - _build_start
				_report["renderer"] = RenderingServer.get_current_rendering_method()
				_report["adapter"] = RenderingServer.get_video_adapter_name()
				_report["lite"] = lite
				_report["quality"] = quality
				var look := _main.get("look") as WorldLook
				if look != null:
					look.set_quality(quality)
				if OS.get_cmdline_user_args().has("--warmup"):
					_phase = "warmup"
					var cam := get_viewport().get_camera_3d()
					await ShaderWarmup.run(_main, cam)
				_go("settle")
		"settle":
			if _frame >= int(SETTLE * frames_scale):
				PerfProbe.take()   # what the build and the landing timed is not part of the stretches
				if OS.get_cmdline_user_args().has("--title"):
					# Where the title's camera flies (Boot): the whole city in view, the heaviest frame of the demo.
					var cam := Camera3D.new()
					cam.fov = 55.0
					cam.far = 3000.0
					add_child(cam)
					cam.global_position = Boot.ORBIT_CENTRE + Vector3(sin(0.6) * Boot.ORBIT_RADIUS, Boot.ORBIT_HEIGHT, cos(0.6) * Boot.ORBIT_RADIUS)
					cam.look_at(Boot.ORBIT_CENTRE, Vector3.UP)
					cam.make_current()
				_place_part_probes()
				_counts("quiet")
				_go("quiet")
		"quiet":
			_take(ms, proc_ms, tail_other, post_ms)
			if _frame >= int(QUIET * frames_scale):
				_close("quiet")
				_census_list = []
				for k in _main.get_children():
					if k is Node3D and not k is Probe and k != Game.player:
						_census_list.append(k)
				_census_i = -1
				_census_base = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				_report["draw_census"] = {}
				_go("census")
		"census":
			# Each part of the world hidden for 4 frames: the draw calls it costs at this spot.
			if _frame % 4 == 0:
				var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				if _census_i >= 0:
					var n: Node3D = _census_list[_census_i]
					n.visible = true
					(_report["draw_census"] as Dictionary)[String(n.name)] = int(_census_base - draws)
				else:
					_census_base = draws
				_census_i += 1
				if _census_i >= _census_list.size():
					print("BENCH draw census (of %d): %s" % [_census_base, _report["draw_census"]])
					_go("chaos")
				else:
					(_census_list[_census_i] as Node3D).visible = false
		"chaos":
			_take(ms, proc_ms, tail_other, post_ms)
			if _frame >= int(CHAOS * frames_scale):
				_close("chaos")
				_counts("chaos")
				_finish()
	_phys_cb = 0.0
	_phys_other = 0.0
	_ticks = 0
	_part_phys.fill(0.0)
	_tick_first = 0
	_blast_ms = 0.0
	_prev_end = Time.get_ticks_usec()


func _go(phase: String) -> void:
	_phase = phase
	_frame = 0
	_rows.clear()


func _take(ms: float, proc_ms: float, tail_other: float, post_ms: float) -> void:
	var parts := PackedFloat64Array()
	parts.resize(_part_names.size())
	for i in _part_names.size():
		var a := _parts[i].proc_usec
		var b := _parts[i + 1].proc_usec
		parts[i] = ((b - a) / 1000.0 if a > 0 and b >= a else 0.0) + _part_phys[i]
	if not _acc.has(_phase):
		var z := PackedFloat64Array()
		z.resize(_part_names.size())
		z.fill(0.0)
		_acc[_phase] = {"sum": z.duplicate(), "max": z.duplicate()}
	var acc: Dictionary = _acc[_phase]
	var sum: PackedFloat64Array = acc["sum"]
	var mx: PackedFloat64Array = acc["max"]
	for i in parts.size():
		sum[i] += parts[i]
		mx[i] = maxf(mx[i], parts[i])
	acc["sum"] = sum
	acc["max"] = mx
	var other := tail_other
	var sec := PerfProbe.take()
	if not _sections.has(_phase):
		_sections[_phase] = {}
	var st: Dictionary = _sections[_phase]
	for k: StringName in sec:
		var v: Array = sec[k]
		var cur: Array = st.get(k, [0.0, 0, 0.0])
		st[k] = [float(cur[0]) + float(v[0]), int(cur[1]) + int(v[1]), maxf(float(cur[2]), float(v[0]))]
	var r := {
		"ms": ms, "process": proc_ms, "physics_cb": _phys_cb, "physics_other": other, "post": post_ms, "blast": _blast_ms, "ticks": _ticks,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"rcpu": RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu(),
		"rgpu": RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
	_rows.append(r)
	if ms > HITCH_MS and _hitches.size() < 300:
		var top: Array = []
		for i in parts.size():
			top.append([parts[i], _part_names[i]])
		top.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
		var tops := []
		for t: Array in top.slice(0, 3):
			tops.append("%s %.1f" % [t[1], t[0]])
		var secs: Array = []
		for k: StringName in sec:
			secs.append([float(sec[k][0]), "%s %.1f/%d" % [k, sec[k][0], sec[k][1]]])
		secs.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
		var sec_top := []
		for s: Array in secs.slice(0, 4):
			sec_top.append(s[1])
		_hitches.append({"sections": ", ".join(sec_top), "phase": _phase, "frame": _frame, "ms": snappedf(ms, 0.1), "process": snappedf(proc_ms, 0.1),
			"blast": snappedf(_blast_ms, 0.1), "physics_cb": snappedf(_phys_cb, 0.1), "physics_other": snappedf(other, 0.1),
			"post": snappedf(post_ms, 0.1), "ticks": _ticks,
			"rcpu": snappedf(r["rcpu"], 0.1), "rgpu": snappedf(r["rgpu"], 0.1), "top": ", ".join(tops)})


func _close(stretch: String) -> void:
	var s := _summary(_rows)
	_report[stretch] = s
	print("BENCH %s %s" % [stretch, _line(s)])
	var acc: Dictionary = _acc.get(stretch, {})
	if acc.is_empty():
		return
	var sum: PackedFloat64Array = acc["sum"]
	var mx: PackedFloat64Array = acc["max"]
	var parts: Array = []
	for i in _part_names.size():
		parts.append({"part": _part_names[i], "avg_ms": snappedf(sum[i] / maxf(_rows.size(), 1.0), 0.001), "max_ms": snappedf(mx[i], 0.01)})
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["avg_ms"]) > float(b["avg_ms"]))
	_report[stretch + "_parts"] = parts
	var line := []
	for p: Dictionary in parts.slice(0, 12):
		line.append("%s %.2f (max %.1f)" % [p["part"], p["avg_ms"], p["max_ms"]])
	print("BENCH %s parts: %s" % [stretch, ", ".join(line)])
	var st: Dictionary = _sections.get(stretch, {})
	var secs: Array = []
	for k: StringName in st:
		secs.append({"section": String(k), "ms_total": snappedf(float(st[k][0]), 0.1), "calls": st[k][1], "worst_frame_ms": snappedf(float(st[k][2]), 0.1)})
	secs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms_total"]) > float(b["ms_total"]))
	_report[stretch + "_sections"] = secs
	var sl := []
	for sx: Dictionary in secs.slice(0, 12):
		sl.append("%s %.1f ms/%d (worst frame %.1f)" % [sx["section"], sx["ms_total"], sx["calls"], sx["worst_frame_ms"]])
	print("BENCH %s sections: %s" % [stretch, ", ".join(sl)])


func _summary(rows: Array[Dictionary]) -> Dictionary:
	if rows.is_empty():
		return {}
	var ms: Array[float] = []
	var sum := {}
	for r in rows:
		ms.append(r["ms"])
		for k: String in r:
			sum[k] = float(sum.get(k, 0.0)) + float(r[k])
	ms.sort()
	var n := ms.size()
	var avg := func(k: String) -> float: return snappedf(float(sum[k]) / n, 0.01)
	var h33 := 0
	var h50 := 0
	var h100 := 0
	for m in ms:
		h33 += int(m > HITCH_MS)
		h50 += int(m > 50.0)
		h100 += int(m > 100.0)
	return {
		"frames": n, "avg_ms": avg.call("ms"), "p50_ms": snappedf(ms[n >> 1], 0.01), "p95_ms": snappedf(ms[int(n * 0.95)], 0.01),
		"p99_ms": snappedf(ms[mini(int(n * 0.99), n - 1)], 0.01), "max_ms": snappedf(ms[n - 1], 0.01),
		"fps": snappedf(1000.0 / maxf(avg.call("ms"), 0.01), 0.1),
		"process_ms": avg.call("process"), "physics_cb_ms": avg.call("physics_cb"), "physics_other_ms": avg.call("physics_other"),
		"post_ms": avg.call("post"),
		"ticks": avg.call("ticks"), "render_cpu_ms": avg.call("rcpu"), "render_gpu_ms": avg.call("rgpu"),
		"draws": int(avg.call("draws")), "objects": int(avg.call("objects")), "prims": int(avg.call("prims")),
		"nodes": int(avg.call("nodes")), "hitches_33": h33, "hitches_50": h50, "hitches_100": h100,
	}


func _line(s: Dictionary) -> String:
	return "fps %.1f avg %.2f p95 %.2f p99 %.2f max %.1f | process %.2f physics callbacks %.2f physics other %.2f post %.2f ticks %.2f | render cpu %.2f gpu %.2f | draws %d objects %d prims %d nodes %d | hitches >33 %d >50 %d >100 %d" % [
		s["fps"], s["avg_ms"], s["p95_ms"], s["p99_ms"], s["max_ms"], s["process_ms"], s["physics_cb_ms"], s["physics_other_ms"], s["post_ms"],
		s["ticks"], s["render_cpu_ms"], s["render_gpu_ms"], s["draws"], s["objects"], s["prims"], s["nodes"], s["hitches_33"], s["hitches_50"], s["hitches_100"]]


func _blast(i: int) -> void:
	if Game.player == null:
		return
	var o: Vector2 = BLASTS[i % BLASTS.size()]
	var at := Vector3(o.x, 0.0, 14.0 + o.y)   # round the landing spot (main.SPAWN)
	at.y = TerrainShape.height_at(at.x, at.z) + 1.0
	DamageRouter.apply_blast(DamageHit.blast(at, 9.0, 4.0e6, 4.0e4))


func _counts(when: String) -> void:
	var c := {}
	var people := _main.get("people") as People
	if people != null:
		c["people"] = people.count()
	var traffic := _main.get("traffic") as Traffic
	if traffic != null:
		c["traffic_cars"] = traffic.cars.size()
	var dressing := _main.get("dressing") as StreetDressing
	if dressing != null:
		c["props"] = dressing.prop_count()
	c["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	c["bodies_active"] = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	c["static_mem_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	c["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	_report["counts_" + when] = c
	print("BENCH counts ", when, " ", c)


func _finish() -> void:
	var mode := ("lite" if lite else "full") + ("_" + tag if tag != "" else "")
	_report["mode"] = mode
	_report["hitches"] = _hitches
	var f := FileAccess.open(OUT + "bench_%s.json" % mode, FileAccess.WRITE)
	f.store_string(JSON.stringify(_report, "  "))
	f.close()
	var worst := _hitches.duplicate()
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms"]) > float(b["ms"]))
	for h: Dictionary in worst.slice(0, 14):
		print("BENCH hitch ", h)
	print("BENCH_DONE ", mode)
	get_tree().quit(0)
