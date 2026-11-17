extends Node
## Windowed check of the Owner's vacuum robots (2026-11-17): a house blown down, the robots coming out of
## the buildings next to it, rubble vanishing into them, one robot swatted to pieces (more chaos heat), the
## DO NOT TOUCH tape round the ruin at three stars, and everything sent home by a rewind. Saves
## tests/out/robots_*.png and prints ROBOTS_* lines.
## Run: Godot --path <P> res://tests/shot_robots.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const D := preload("res://game/destruction/destruction_defs.gd")
const Util := preload("res://tests/city_test_util.gd")

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _robots: CleanupRobots
var _chaos: Chaos
var _bid := -1
var _center := Vector3.ZERO
var _rubble_before := 0
var _heat_before := 0.0
var _ok := true


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	match f:
		0:
			_cat = Game.player as CatPlayer
			_robots = _main.get("robots") as CleanupRobots
			_chaos = _main.get("chaos") as Chaos
			var city := _main.get("city") as CityLayout
			var lot := city.nearest_lot(D.Style.HOUSE, Vector3(-60.0, 0.0, -60.0))
			_bid = int(lot["bid"])
			_center = lot["pos"]
			_cam = Camera3D.new()
			_cam.fov = 60.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
			_move_cat(_center + Vector3(0.0, 0.5, 22.0))
			_cam.look_at_from_position(_center + Vector3(14.0, 12.0, 18.0), _center, Vector3.UP)
		30, 60, 90:
			DamageRouter.apply_blast(DamageHit.blast(Util.wall_point(_bid, 2.0), 6.5, 4.0e6, 9000.0))
		600:
			var debris := Game.debris as DebrisManager
			_rubble_before = debris.rubble_near(_center, CleanupRobots.WORK_RADIUS, 3.0, 4096).size()
			var sent := _robots.robots.size()
			if sent == 0:
				sent = _robots.call_out(_center, true)
			print("ROBOTS_OUT %d rubble pieces round the ruin, %d robots out" % [_rubble_before, _robots.robots.size()])
			_ok = _ok and _rubble_before > 0 and _robots.robots.size() > 0
		660:
			_save("robots_out.png")
		1500:
			var debris := Game.debris as DebrisManager
			var left := debris.rubble_near(_center, CleanupRobots.WORK_RADIUS, 3.0, 4096).size()
			print("ROBOTS_WORK vacuumed %d, %d pieces left of %d, %d robots out" % [_robots.vacuumed, left, _rubble_before, _robots.robots.size()])
			_ok = _ok and _robots.vacuumed >= 8   # (the pile keeps growing while the debris settles)
			if _robots.robots.is_empty():
				_robots.call_out(_center, true)   # someone to swat
			if not _robots.robots.is_empty():
				var r: CleanupRobots.Robot = _robots.robots[0]
				var at := r.prop.global_position
				_cam.look_at_from_position(at + Vector3(2.5, 1.6, 2.5), at, Vector3.UP)
		1530:
			_save("robots_work.png")
			_heat_before = _chaos.heat
			if not _robots.robots.is_empty():
				var r: CleanupRobots.Robot = _robots.robots[0]
				var at := r.prop.global_position + Vector3.UP * 0.1
				DamageRouter.apply_hit(DamageHit.point(at, Vector3.FORWARD, 9000.0, 60.0, DamageHit.Kind.BLUNT, null), r.prop, r.prop.get_rid())
		1620:
			print("ROBOTS_WRECKED %d wrecked, heat %.1f -> %.1f" % [_robots.wrecked, _heat_before, _chaos.heat])
			_ok = _ok and _robots.wrecked >= 1
			_chaos.add(100.0)
			_robots.tape_worst_ruin()
			_cam.look_at_from_position(_center + Vector3(-12.0, 7.0, 16.0), _center, Vector3.UP)
		1680:
			_save("robots_tape.png")
			print("ROBOTS_TAPE stars %d, %d ruins taped, %d tape props" % [_chaos.stars, _robots.taped, _robots.tape_props.size()])
			_ok = _ok and _robots.taped >= 1 and _robots.tape_props.size() > 4
			_robots.send_home()
		1700:
			print("ROBOTS_HOME %d robots out, %d tape props" % [_robots.robots.size(), _robots.tape_props.size()])
			_ok = _ok and _robots.robots.is_empty() and _robots.tape_props.is_empty()
			print("ROBOTS_RESULT ok=%s called=%d vacuumed=%d wrecked=%d" % [_ok, _robots.called, _robots.vacuumed, _robots.wrecked])
			get_tree().quit(0)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = Vector3(to.x, TerrainShape.height_at(to.x, to.z) + 0.5, to.z)
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
