extends Node
## Windowed check of the street props in the composed world: counts them, looks along a sidewalk,
## swats and blasts a few, and reports what broke. Saves tests/out/props_*.png, prints PROPS_* lines.
## Run: Godot --path <P> res://tests/shot_props.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _bot := CatInput.new()
var _cam: Camera3D
var _dressing: StreetDressing
var _broken := {}
var _frame_ms := PackedFloat32Array()
var _last_usec := 0
var _target: BreakableProp
var _drum: BreakableProp
var _bench_start := Vector3.ZERO


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > 200:
		var ms := float(now - _last_usec) / 1000.0
		_frame_ms.append(ms)
		if ms > 60.0:
			print("PROPS_HITCH f=%d ms=%.0f" % [_frame - T0, ms])
	_last_usec = now
	var f := _frame - T0
	match f:
		0:
			_dressing = _main.get_node("StreetDressing") as StreetDressing
			var kinds := {}
			var awake := 0
			for p in _dressing.props:
				kinds[p.prop_id] = int(kinds.get(p.prop_id, 0)) + 1
				p.broken.connect(func(b: BreakableProp) -> void: _broken[b.prop_id] = int(_broken.get(b.prop_id, 0)) + 1)
				if not p.sleeping and not p.freeze:
					awake += 1
				if p.prop_id == &"bench" and (_target == null or p.global_position.length() < _target.global_position.length()):
					_target = p
				if p.prop_id == &"fuel_drum" and (_drum == null or p.global_position.length() < _drum.global_position.length()):
					_drum = p
			print("PROPS_COUNT total=%d awake=%d kinds=%s" % [_dressing.prop_count(), awake, JSON.stringify(kinds)])
			print("PROPS_TARGET bench=%s drum=%s lowest_y=%.2f" % [_target.global_position if _target != null else Vector3.INF, _drum.global_position if _drum != null else Vector3.INF, _lowest()])
			_cat = Game.player as CatPlayer
			_cat.bot_input = _bot
			_cam = Camera3D.new()
			_cam.fov = 55.0
			_cam.far = 3000.0
			add_child(_cam)
			_cam.look_at_from_position(Vector3(13.5, 2.2, 22.0), Vector3(10.5, 0.8, 70.0), Vector3.UP)
			_cam.make_current()
		20:
			_save("props_sidewalk.png")
		30:
			# Stand the cat in front of the nearest bench and swat it until it breaks.
			var p := _target.global_position
			_bench_start = p
			# The bench stands about 11 m from the centre line of its road: that tells which road it is on.
			var road := float(TerrainStrata.ROAD_SPACING)
			var dx := p.x - roundf(p.x / road) * road
			var dz := p.z - roundf(p.z / road) * road
			var to_road := Vector3(-signf(dx), 0.0, 0.0) if absf(absf(dx) - 11.3) < absf(absf(dz) - 11.3) else Vector3(0.0, 0.0, -signf(dz))
			_cat.global_position = p + to_road * 0.75 + Vector3.UP * 0.3
			_cat.velocity = Vector3.ZERO
			_cat.reset_physics_interpolation()
			_cat.camera.yaw = atan2(to_road.x, to_road.z)
			_cat.camera.pitch = deg_to_rad(-5.0)
			_cat.camera.snap_to_target()
			_bot.aim = true   # rear up and face where the camera looks, so the swats go at the bench
			_cam.look_at_from_position(p + to_road * 3.0 + Vector3(1.5, 1.4, 1.5), p + Vector3.UP * 0.4, Vector3.UP)
		60, 90, 120, 150, 180:
			_bot.attack = true
		62, 92, 122, 152, 182:
			_bot.attack = false
		200:
			_bot.aim = false
			print("PROPS_BENCH broken=%s hp=%s moved=%.1f m" % [not is_instance_valid(_target) or _target.is_broken(), _target.hp if is_instance_valid(_target) else -1.0,
				_target.global_position.distance_to(_bench_start) if is_instance_valid(_target) else -1.0])
			_save("props_bench.png")
		205:
			if _drum != null:
				var d := _drum.global_position
				_cat.global_position = d + Vector3(9.0, 0.5, 9.0).rotated(Vector3.UP, 0.0)
				_cat.velocity = Vector3.ZERO
				_cat.reset_physics_interpolation()
				_cam.look_at_from_position(d + Vector3(7.0, 4.0, 7.0), d + Vector3.UP * 0.5, Vector3.UP)
		240:
			if _drum != null:
				print("PROPS_DRUM parked=%s frozen=%s y=%.2f" % [_drum.parked, _drum.freeze, _drum.global_position.y])
				var hit := DamageHit.point(_drum.global_position + Vector3.UP * 0.4, Vector3.DOWN, 6000.0, 50.0, DamageHit.Kind.BLUNT, _cat)
				DamageRouter.apply_hit(hit, _drum, _drum.get_rid())
		254:
			_save("props_drum_blast.png")
		330:
			_save("props_after.png")
			print("PROPS_BROKEN ", JSON.stringify(_broken))
			var left := 0
			for p in _dressing.props:
				if is_instance_valid(p) and not p.is_broken():
					left += 1
			print("PROPS_LEFT %d lowest_y=%.2f" % [left, _lowest()])
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			var sum := 0.0
			for v: float in sorted:
				sum += v
			print("PROPS_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f n=%d draw=%d prims=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
			get_tree().quit(0)


func _lowest() -> float:
	var y := 1.0e9
	for p in _dressing.props:
		if is_instance_valid(p):
			y = minf(y, p.global_position.y)
	return y


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
