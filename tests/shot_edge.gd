extends Node
## Windowed check of the end of the Table: the rim seen from the city and up close, a fall off the edge
## through the Underneath with the drop back onto the Table, and a second fall skipped with a key.
## Saves tests/out/edge_*.png and prints EDGE_* lines.
## Run: Godot --path <P> res://tests/shot_edge.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _under: Underneath
var _phase := "wait"
var _t := 0
var _fall_frames := 0
var _ok := true


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _go(phase: String) -> void:
	_phase = phase
	_t = 0


func _process(_delta: float) -> void:
	_frame += 1
	_t += 1
	match _phase:
		"wait":
			if _frame == T0:
				_cat = Game.player as CatPlayer
				_under = _main.get("underneath") as Underneath
				_cam = Camera3D.new()
				_cam.fov = 60.0
				_cam.far = 4000.0
				add_child(_cam)
				_cam.make_current()
				_move_cat(Vector3(300.0, 2.0, 60.0))
				_cam.look_at_from_position(Vector3(250.0, 4.0, 60.0), Vector3(512.0, 30.0, 60.0), Vector3.UP)
				_go("views")
		"views":
			if _t == 40:
				_save("edge_horizon.png")
				_cam.look_at_from_position(Vector3(330.0, 90.0, 0.0), Vector3(512.0, 20.0, 0.0), Vector3.UP)
			if _t == 80:
				_save("edge_from_city.png")
				_move_cat(Vector3(470.0, TerrainShape.height_at(470.0, 0.0) + 1.0, 0.0))
				_cam.look_at_from_position(Vector3(488.0, TerrainShape.height_at(488.0, 0.0) + 6.0, -14.0), Vector3(520.0, 10.0, 6.0), Vector3.UP)
			if _t == 130:
				_save("edge_rim.png")
				# Over the edge she goes.
				_cat.camera.get_camera().make_current()
				_move_cat(Vector3(515.0, 40.0, 0.0))
				_cat.velocity = Vector3(4.0, 0.0, 0.0)
				_go("fall")
		"fall":
			if _under.falling:
				_fall_frames += 1
			if _t == 70:
				print("EDGE_FALL started=%s falls=%d cat at %s" % [_under.falling, _under.falls, _cat.global_position.snapped(Vector3.ONE * 0.1)])
				_save("edge_fall_1.png")
			if _t == 200:
				_save("edge_fall_2.png")
			if _t > 60 and not _under.falling and _phase == "fall":
				print("EDGE_REDROP after %d frames of falling, cat at %s" % [_fall_frames, _cat.global_position.snapped(Vector3.ONE * 0.1)])
				_ok = _ok and _fall_frames > 200
				_go("landing")
		"landing":
			if _t == 260:
				var p := _cat.global_position
				var inside := absf(p.x) < 500.0 and absf(p.z) < 500.0
				print("EDGE_LANDED at %s inside=%s on_floor=%s" % [p.snapped(Vector3.ONE * 0.1), inside, _cat.is_on_floor()])
				_save("edge_landed.png")
				_ok = _ok and inside
				# A second fall, off the other side, skipped with a key.
				_move_cat(Vector3(-515.0, 40.0, 30.0))
				_cat.velocity = Vector3(-4.0, 0.0, 0.0)
				_go("skip")
		"skip":
			if _t == 90:
				var key := InputEventKey.new()
				key.keycode = KEY_SPACE
				key.physical_keycode = KEY_SPACE
				key.pressed = true
				Input.parse_input_event(key)
				var up := InputEventKey.new()
				up.keycode = KEY_SPACE
				up.physical_keycode = KEY_SPACE
				up.pressed = false
				Input.parse_input_event(up)
			if _t == 96:
				print("EDGE_SKIP falling=%s falls=%d" % [_under.falling, _under.falls])
				_ok = _ok and not _under.falling and _under.falls == 2
				print("EDGE_RESULT ok=%s" % _ok)
				get_tree().quit(0)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = to
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
