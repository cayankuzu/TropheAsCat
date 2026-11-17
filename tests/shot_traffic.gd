extends Node
## Windowed check of the traffic (2026-11-17): cars through a Downtown crossing, a car that brakes and
## honks for Trophe standing in its lane, a blast on a busy street that throws driving cars off the road,
## and a street from above. Saves tests/out/traffic_*.png and prints TRAFFIC_* lines.
## Run: Godot --path <P> res://tests/shot_traffic.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _traffic: Traffic
var _victim: Traffic.Car = null
var _ms := PackedFloat32Array()
var _last := 0
var _ok := true


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _frame > T0 and _last > 0:
		_ms.append((now - _last) / 1000.0)
	_last = now
	var f := _frame - T0
	match f:
		0:
			_cat = Game.player as CatPlayer
			_traffic = _main.get("traffic") as Traffic
			_cam = Camera3D.new()
			_cam.fov = 60.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
			_move_cat(Vector3(140.0, 0.5, 141.0))
			_cam.look_at_from_position(Vector3(152.0, 14.0, 152.0), Vector3(128.0, 0.0, 128.0), Vector3.UP)
		150:
			_save("traffic_crossing.png")
			var near := 0
			var moving := 0
			for c in _traffic.cars:
				if c.near and not c.gone:
					near += 1
					if c.speed > 3.0:
						moving += 1
			print("TRAFFIC_CARS %d driving, %d near Trophe, %d of them moving" % [_traffic.driving(), near, moving])
			_ok = _ok and _traffic.driving() > 90 and moving > 0
			# Stand in the lane of a car coming along.
			for c in _traffic.cars:
				if c.near and not c.gone and not c.turning and c.speed > 6.0:
					_victim = c
					break
			if _victim != null:
				var fwd := Vector3(sin(_victim.yaw), 0.0, cos(_victim.yaw))
				_move_cat(_victim.pos + fwd * 22.0)
				_cam.look_at_from_position(_victim.pos + fwd * 30.0 + Vector3(5.0, 3.0, 0.0) + Vector3(fwd.z, 0.0, -fwd.x) * 4.0, _victim.pos, Vector3.UP)
		360:
			if _victim != null:
				print("TRAFFIC_BLOCKED speed %.2f m/s, %.1f m from the cat, honks %d" % [_victim.speed, _victim.pos.distance_to(_cat.global_position), _traffic.honks])
				_ok = _ok and _victim.speed < 0.5
			_save("traffic_blocked.png")
			if _victim != null:
				var at := _victim.pos + Vector3.UP * 0.8
				DamageRouter.apply_blast(DamageHit.blast(at, 5.0, 3.0e6, 16000.0, DamageHit.Kind.EXPLOSION, null))
		390:
			_save("traffic_crash.png")
		420:
			print("TRAFFIC_CRASH crashed %d, still driving %d" % [_traffic.crashed, _traffic.driving()])
			_ok = _ok and _traffic.crashed >= 1
			_save("traffic_after.png")
			_move_cat(Vector3(-200.0, 0.5, -117.0))
			_cam.look_at_from_position(Vector3(-170.0, 30.0, -150.0), Vector3(-230.0, 0.0, -128.0), Vector3.UP)
		560:
			_save("traffic_street.png")
			var sorted := Array(_ms)
			sorted.sort()
			var n := sorted.size()
			print("TRAFFIC_FRAME_MS p50=%.2f p95=%.2f p99=%.2f n=%d" % [sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n])
			_ok = _ok and _traffic.honks > 0
			print("TRAFFIC_RESULT ok=%s honks=%d run_over=%d" % [_ok, _traffic.honks, _traffic.run_over])
			get_tree().quit(0)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = Vector3(to.x, TerrainShape.height_at(to.x, to.z) + 0.5, to.z)
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
