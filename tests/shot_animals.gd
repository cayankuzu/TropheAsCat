extends Node
## Windowed check of the animals: a flock on the ground, its take-off when Trophe comes close, the
## landing once she has gone, and a dog that watches her, shakes off a swat and plays dead at a blast.
## Saves tests/out/animals_*.png and prints ANIMALS_* lines.
## Run: Godot --path <P> res://tests/shot_animals.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _animals: Animals
var _cat: CatPlayer
var _cam: Camera3D
var _flock: Animals.Flock
var _dog: Animals.Dog
var _protected := 0
var _mass_before := 0.0
var _frame_ms := PackedFloat32Array()
var _last_usec := 0


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DamageRouter.protected_hit.connect(func(_hit: DamageHit, _target: Object) -> void: _protected += 1)


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > T0:
		_frame_ms.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	var f := _frame - T0
	match f:
		0:
			_animals = _main.get_node("Animals") as Animals
			_cat = Game.player as CatPlayer
			print("ANIMALS_COUNT flocks=%d pigeons=%d dogs=%d" % [_animals.flocks.size(), _animals.pigeon_count(), _animals.dog_count()])
			print("ANIMALS_LANDING flock 0 state=%d takeoffs=%d (the landing sends it up)" % [_animals.flocks[0].state, _animals.takeoffs])
			_save("animals_landing.png")
			_flock = _animals.flocks[1]
			_move_cat(_flock.home + Vector3(30.0, 0.5, 0.0))
			_cam = Camera3D.new()
			_cam.fov = 50.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
			_cam.look_at_from_position(_flock.home + Vector3(2.6, 0.7, 2.6), _flock.home + Vector3(0.0, 0.12, 0.0), Vector3.UP)
		40:
			print("ANIMALS_GROUND state=%d active=%s birds=%d" % [_flock.state, _flock.active, _flock.birds.size()])
			_save("animals_flock.png")
			_cam.look_at_from_position(_flock.home + Vector3(7.0, 1.6, 7.0), _flock.home + Vector3(0.0, 2.2, 0.0), Vector3.UP)
		50:
			_move_cat(_flock.home + Vector3(5.0, 0.5, 0.0))
		88:
			_save("animals_takeoff.png")
			print("ANIMALS_TAKEOFF state=%d takeoffs=%d" % [_flock.state, _animals.takeoffs])
			_cam.look_at_from_position(_flock.home + Vector3(24.0, 1.5, 24.0), _flock.home + Vector3(0.0, 10.0, 0.0), Vector3.UP)
		150, 151, 152, 153, 154, 155, 156:
			# Close to one bird in the air (the camera has to ride along for the picture to hold it).
			var bird := _flock.birds[0]
			_cam.look_at_from_position(bird.pos + Vector3(0.9, 0.25, 0.9), bird.pos, Vector3.UP)
			if f == 156:
				_save("animals_bird.png")
				_cam.look_at_from_position(_flock.home + Vector3(24.0, 1.5, 24.0), _flock.home + Vector3(0.0, 10.0, 0.0), Vector3.UP)
		200:
			_save("animals_circle.png")
			print("ANIMALS_CIRCLE state=%d air=%.1f" % [_flock.state, _flock.air])
			_move_cat(_flock.home + Vector3(40.0, 0.5, 0.0))
		700:
			print("ANIMALS_LANDED state=%d landings=%d" % [_flock.state, _animals.landings])
			_dog = _animals.dogs[0]
			_move_cat(_dog.pos + Vector3(3.0, 0.5, 2.0))
			_cam.look_at_from_position(_dog.pos + Vector3(1.5, 0.6, 2.4), _dog.pos + Vector3(0.0, 0.25, 0.0), Vector3.UP)
			_mass_before = Progress.destroyed_mass
		800:
			_save("animals_dog.png")
			print("ANIMALS_DOG clip=%s active=%s" % [_dog.clip, _dog.active])
			var body := _dog.root.find_children("*", "StaticBody3D", true, false)[0] as StaticBody3D
			DamageRouter.apply_hit(DamageHit.point(_dog.pos + Vector3.UP * 0.25, Vector3(-1.0, 0.0, 0.0), 3000.0, 300.0, DamageHit.Kind.BLUNT, _cat), body, body.get_rid())
		806:
			print("ANIMALS_SWAT protected hits=%d dog clip=%s still at %s" % [_protected, _dog.clip, (_dog.root.global_position - _dog.pos).length() < 0.01])
		860:
			DamageRouter.apply_blast(DamageHit.blast(_dog.pos + Vector3(9.0, 0.5, 0.0), 5.0, 200000.0, 3000.0, DamageHit.Kind.EXPLOSION, _cat))
		960:
			_save("animals_dog_dead.png")
			print("ANIMALS_BLAST dog clip=%s tricks=%s" % [_dog.clip, JSON.stringify(_animals.tricks)])
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			var sum := 0.0
			for v: float in sorted:
				sum += v
			print("ANIMALS_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f n=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n])
			get_tree().quit(0)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = to
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
