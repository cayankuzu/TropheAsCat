extends Node
## Windowed check of the set pieces (2026-11-17): the Ferris wheel standing and then rolling off east, the
## tower crane before and after it tips over, the clock tower before and after it comes down on the green.
## Saves tests/out/giants_*.png and prints GIANTS_* lines.
## Run: Godot --path <P> res://tests/shot_giants.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _sp: SetPieces
var _start := Vector3.ZERO
var _ok := true


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f == 0:
		_cat = Game.player as CatPlayer
		_sp = _main.get("set_pieces") as SetPieces
		_cam = Camera3D.new()
		_cam.fov = 60.0
		_cam.far = 2000.0
		add_child(_cam)
		_cam.make_current()
		print("GIANTS_BUILT wheel=%s crane=%s tower=%s" % [_sp.wheel != null, _sp.crane != null, _sp.tower != null])
		_ok = _ok and _sp.wheel != null and _sp.crane != null and _sp.tower != null
		_start = _sp.wheel.global_position
		_move_cat(_start + Vector3(-20.0, 0.0, 24.0))
		_cam.look_at_from_position(_start + Vector3(-34.0, 8.0, 40.0), _start + Vector3(10.0, 0.0, 0.0), Vector3.UP)
	elif f == 60:
		_save("giants_wheel.png")
		_sp.wheel.receive_damage(DamageHit.point(_start, Vector3.RIGHT, 30000.0, 3000.0, DamageHit.Kind.BLUNT, null), 0)
	elif f > 60 and f < 420 and f % 30 == 0:
		# Trophe runs along (a giant far from her waits frozen).
		_move_cat(_sp.wheel.global_position + Vector3(-18.0, 0.0, 22.0))
	elif f == 420:
		var w := _sp.wheel.global_position
		_cam.look_at_from_position(w + Vector3(-26.0, 12.0, 30.0), w, Vector3.UP)
	elif f == 424:
		var w := _sp.wheel.global_position
		var rolled := Vector2(w.x - _start.x, w.z - _start.z).length()
		print("GIANTS_WHEEL released=%s rolled %.1f m, broken=%s" % [_sp.wheel.released, rolled, _sp.wheel.broken])
		_ok = _ok and _sp.wheel.released and rolled > 25.0
		_save("giants_wheel_roll.png")
		var c := _sp.crane.global_position
		_move_cat(c + Vector3(-22.0, 0.0, -22.0))
		_cam.look_at_from_position(c + Vector3(-45.0, 18.0, -45.0), c + Vector3(0.0, 18.0, 0.0), Vector3.UP)
	elif f == 480:
		_save("giants_crane.png")
		var c := _sp.crane.global_position
		var away := (c - _cat.global_position)
		away.y = 0.0
		_sp.crane.receive_damage(DamageHit.point(c + Vector3.UP, away.normalized(), 30000.0, 3000.0, DamageHit.Kind.BLUNT, null), 0)
	elif f == 500 or f == 560:
		var g := _sp.crane
		print("GIANTS_DEBUG f=%d freeze=%s sleeping=%s lin=%s ang=%s up=%s pos=%s mass=%.0f com=%s" % [f, g.freeze, g.sleeping, g.linear_velocity.snapped(Vector3.ONE * 0.01), g.angular_velocity.snapped(Vector3.ONE * 0.01), g.global_basis.y.snapped(Vector3.ONE * 0.01), g.global_position.snapped(Vector3.ONE * 0.1), g.mass, g.center_of_mass.snapped(Vector3.ONE * 0.1)])
	elif f == 700:
		print("GIANTS_CRANE released=%s broken=%s debris awake=%d" % [_sp.crane.released, _sp.crane.broken, (Game.debris as DebrisManager).awake_count()])
		_ok = _ok and _sp.crane.broken
		_save("giants_crane_down.png")
		var t := _sp.tower.global_position
		_move_cat(t + Vector3(-18.0, 0.0, -20.0))
		_cam.look_at_from_position(t + Vector3(-40.0, 16.0, -36.0), t + Vector3(0.0, 16.0, 0.0), Vector3.UP)
	elif f == 760:
		_save("giants_tower.png")
		var t := _sp.tower.global_position
		var away := (t - _cat.global_position)
		away.y = 0.0
		_sp.tower.receive_damage(DamageHit.point(t + Vector3.UP, away.normalized(), 40000.0, 3000.0, DamageHit.Kind.BLUNT, null), 0)
	elif f == 980:
		print("GIANTS_TOWER released=%s broken=%s cleared %.2f %%" % [_sp.tower.released, _sp.tower.broken, Progress.cleared_percent()])
		_ok = _ok and _sp.tower.broken
		_save("giants_tower_down.png")
		print("GIANTS_RESULT ok=%s released=%d" % [_ok, _sp.released_count()])
		get_tree().quit(0)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = Vector3(to.x, TerrainShape.height_at(to.x, to.z) + 0.5, to.z)
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
