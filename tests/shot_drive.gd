extends Node
## Windowed check of driving (2026-11-17): Trophe gets into a parked car (F), drives it forward for four
## seconds, steers, gets out. Saves tests/out/drive_*.png and prints DRIVE_* lines.
## Run: Godot --path <P> res://tests/shot_drive.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _drive: CatDriving
var _car: BreakableProp
var _start := Vector3.ZERO
var _front := Vector3.ZERO
var _ok := true


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = down
		Input.parse_input_event(k)


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f == 0:
		_cat = Game.player as CatPlayer
		_drive = _main.get("driving") as CatDriving
		# The parked car nearest to the crossing where she lands.
		var dressing := _main.get("dressing") as StreetDressing
		# A parked car with 40 m of free road ahead of it.
		var best := 1.0e9
		var space := get_viewport().world_3d.direct_space_state
		for p in dressing.props:
			if is_instance_valid(p) and p.wreck and not p.is_broken():
				var d := p.global_position.distance_to(_cat.global_position)
				if d >= best or d < 8.0 or d > 160.0:
					continue
				var fwd := -p.global_basis.z.normalized()
				var from := p.global_position + Vector3.UP * 0.8 + fwd * (p.size.z * 0.5 + 0.3)
				var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 40.0, Layers.STRUCTURE | Layers.PROPS | Layers.PROTECTED)
				if space.intersect_ray(q).is_empty():
					best = d
					_car = p
		var side := _car.global_basis.x.normalized()
		_cat.global_position = _car.global_position + side * (_car.size.x * 0.5 + 1.0) + Vector3.UP * 0.4
		_cat.velocity = Vector3.ZERO
		_cat.reset_physics_interpolation()
	elif f == 90:
		_key(KEY_F)
	elif f == 100:
		print("DRIVE_IN driving=%s car=%s presses %d" % [_drive.driving(), _car.prop_id, _drive.f_presses])
		_ok = _ok and _drive.driving()
		_start = _car.global_position
		_front = -_car.global_basis.z.normalized()
		Input.action_press(&"move_forward")
	elif f == 200:
		print("DRIVE_DEBUG ", _drive.debug)
	elif f == 340:
		var moved := _car.global_position - _start
		var along := moved.dot(_front)
		print("DRIVE_GO moved %.1f m, %.1f m of it forward, %.1f m/s" % [moved.length(), along, _car.linear_velocity.length()])
		_ok = _ok and along > 25.0 and _car.linear_velocity.length() > 12.0
		get_viewport().get_texture().get_image().save_png(OUT + "drive_go.png")
		Input.action_press(&"move_right")
	elif f == 400:
		Input.action_release(&"move_right")
		Input.action_release(&"move_forward")
		var heading := -_car.global_basis.z.normalized()
		print("DRIVE_TURN heading turned %.0f degrees" % rad_to_deg(_front.angle_to(heading)))
		_ok = _ok and _front.angle_to(heading) > deg_to_rad(15.0)
	elif f == 520:
		print("DRIVE_BEFORE_OUT presses %d driving=%s" % [_drive.f_presses, _drive.driving()])
		_key(KEY_F)
	elif f == 525:
		print("DRIVE_AFTER_OUT presses %d driving=%s" % [_drive.f_presses, _drive.driving()])
	elif f == 540:
		print("DRIVE_OUT driving=%s cat visible=%s physics=%s F presses seen %d, paused=%s" % [_drive.driving(), _cat.visible, _cat.is_physics_processing(), _drive.f_presses, get_tree().paused])
		_ok = _ok and not _drive.driving() and _cat.visible and _cat.is_physics_processing()
		get_viewport().get_texture().get_image().save_png(OUT + "drive_out.png")
		print("DRIVE_RESULT ok=%s" % _ok)
		get_tree().quit(0)
