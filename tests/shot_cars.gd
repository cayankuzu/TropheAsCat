extends Node
## Windowed check of the parked cars in the composed world: lists what the vehicle library cut out of
## the packs, looks along a parked row, wrecks one car and watches the chain reaction.
## Saves tests/out/cars_*.png and prints CARS_* lines.
## Run: Godot --path <P> res://tests/shot_cars.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _dressing: StreetDressing
var _cars: Array[BreakableProp] = []
var _wrecked := 0
var _broken := 0
var _victim: BreakableProp
var _frame_ms := PackedFloat32Array()
var _last_usec := 0


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > 200:
		_frame_ms.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	var f := _frame - T0
	match f:
		0:
			_dressing = _main.get_node("StreetDressing") as StreetDressing
			print("CARS_LIBRARY passenger=%s service=%s" % [_dressing.vehicles.passenger, _dressing.vehicles.service])
			var kinds := {}
			var sizes := {}
			for p in _dressing.props:
				if p.wreck:
					_cars.append(p)
					kinds[p.prop_id] = int(kinds.get(p.prop_id, 0)) + 1
					sizes[p.prop_id] = "%.1fx%.1fx%.1f %dkg" % [p.size.x, p.size.y, p.size.z, int(p.mass)]
					p.wrecked.connect(func(_c: BreakableProp) -> void: _wrecked += 1)
					p.broken.connect(func(_c: BreakableProp) -> void: _broken += 1)
			print("CARS_COUNT %d kinds=%s" % [_cars.size(), JSON.stringify(kinds)])
			print("CARS_SIZES ", JSON.stringify(sizes))
			# The victim: the car with the closest neighbour, so the chain has somewhere to go.
			var best := 1.0e9
			for a in _cars:
				for b in _cars:
					if a != b and a.global_position.distance_to(b.global_position) < best and a.global_position.length() < 120.0:
						best = a.global_position.distance_to(b.global_position)
						_victim = a
			print("CARS_VICTIM %s at %s neighbour=%.1f m" % [_victim.prop_id, _victim.global_position, best])
			_cat = Game.player as CatPlayer
			var v := _victim.global_position
			_cat.global_position = v + Vector3(11.0, 0.6, 11.0)
			_cat.velocity = Vector3.ZERO
			_cat.reset_physics_interpolation()
			_cam = Camera3D.new()
			_cam.fov = 55.0
			_cam.far = 3000.0
			add_child(_cam)
			_cam.look_at_from_position(v + Vector3(9.0, 3.2, 9.0), v + Vector3(0.0, 0.8, 0.0), Vector3.UP)
			_cam.make_current()
		40:
			_save("cars_row.png")
			var lowest := 1.0e9
			for c in _cars:
				lowest = minf(lowest, c.global_position.y)
			print("CARS_LOWEST_Y %.2f victim_parked=%s" % [lowest, _victim.parked])
		50:
			DamageRouter.apply_blast(DamageHit.blast(_victim.global_position + Vector3.UP * 0.8, 3.0, 2.0e6, 3000.0, DamageHit.Kind.EXPLOSION, _cat))
		70:
			_save("cars_blast.png")
		420:
			_save("cars_wrecks.png")
			print("CARS_RESULT wrecked=%d broken=%d victim_wreck=%s" % [_wrecked, _broken, is_instance_valid(_victim) and _victim.is_wreck()])
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			var sum := 0.0
			for v2: float in sorted:
				sum += v2
			print("CARS_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f n=%d draw=%d prims=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
			get_tree().quit(0)


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
