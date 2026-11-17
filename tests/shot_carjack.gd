extends Node
## Windowed check of carjacking (2026-11-17): a car of the traffic near Trophe has a porcelain driver at the
## wheel; she steps up to it and presses F: she drives it, and the driver gets out of the left door and runs
## off shouting (one more person in the city, panicking, wearing the driver's figure). Saves
## tests/out/carjack_seated.png and tests/out/carjack_out.png and prints CARJACK_* lines.
## Run: Godot --path <P> res://tests/shot_carjack.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _drive: CatDriving
var _traffic: Traffic
var _people: People
var _car: Traffic.Car
var _count0 := 0
var _panics0 := 0
var _ok := true
var _phase := 0
var _wait := 0


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
	if _frame < T0:
		return
	if _phase == 0:
		_cat = Game.player as CatPlayer
		_drive = _main.get("driving") as CatDriving
		_traffic = _main.get("traffic") as Traffic
		_people = _main.get("people") as People
		_phase = 1
	elif _phase == 1:
		# The nearest car that has its driver seated.
		_wait += 1
		var best := 1.0e9
		for c in _traffic.cars:
			if c.gone or c.driver == null or not is_instance_valid(c.driver) or c.parked or c.unit:
				continue
			var d := c.pos.distance_to(_cat.global_position)
			if d < best:
				best = d
				_car = c
		if _car != null:
			print("CARJACK_SEATED car %s at %.0f m, driver figure %s" % [_car.vname, best, _car.driver.name])
			_car.yield_t = 60.0   # it pulls over and waits, as for a siren, so she can reach the door
			# Stand beside its left door, looking at it.
			var side := (_car.node.global_basis.x).normalized()
			_cat.global_position = _car.node.global_position + side * (_car.width * 0.5 + 1.2) + Vector3.UP * 0.4
			_cat.velocity = Vector3.ZERO
			_cat.reset_physics_interpolation()
			_count0 = _people.count()
			_panics0 = _people.panics
			_phase = 2
			_wait = 0
		elif _wait > 900:
			print("CARJACK_SEATED none in 900 frames")
			_ok = false
			_finish()
	elif _phase == 2:
		_wait += 1
		if _wait < 150:
			# Keep beside its left door while it slows down.
			var side := (_car.node.global_basis.x).normalized()
			_cat.global_position = _car.node.global_position + side * (_car.width * 0.5 + 1.2) + Vector3.UP * 0.4
			_cat.velocity = Vector3.ZERO
			if _wait % 30 == 0:
				print("CARJACK_WAIT car speed %.1f, cat %.1f m from it" % [_car.speed, _cat.global_position.distance_to(_car.node.global_position)])
			return
		if _wait == 151:
			get_viewport().get_texture().get_image().save_png(OUT + "carjack_seated.png")
			_key(KEY_F)
		elif _wait == 161:
			var runner_near := false
			for i in range(_count0, _people.count()):
				var p: People.Person = _people.people[i]
				if p.state == People.State.PANIC and p.visual != null and p.pos.distance_to(_cat.global_position) < 12.0:
					runner_near = true
			print("CARJACK_IN driving=%s people %d -> %d panics %d -> %d runner near=%s" % [_drive.driving(), _count0, _people.count(), _panics0, _people.panics, runner_near])
			_ok = _ok and _drive.driving() and _people.count() == _count0 + 1 and runner_near
		elif _wait == 220:
			get_viewport().get_texture().get_image().save_png(OUT + "carjack_out.png")
			_finish()


func _finish() -> void:
	print("CARJACK_RESULT ok=%s" % _ok)
	get_tree().quit(0)
