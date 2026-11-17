extends Node
## Windowed check of the little people in the composed city: counts them, looks at a walker and a
## sitter up close, lets one say its line, swats one to pieces and scares the rest with a blast.
## Saves tests/out/people_*.png and prints PEOPLE_* lines.
## Run: Godot --path <P> res://tests/shot_people.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _bot := CatInput.new()
var _cam: Camera3D
var _people: People
var _victim: People.Person
var _sitter: People.Person
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
			_people = _main.get_node("People") as People
			_cat = Game.player as CatPlayer
			_cat.bot_input = _bot
			var walkers := 0
			var sitters := 0
			for p in _people.people:
				if p.state == People.State.SIT:
					sitters += 1
					if _sitter == null or p.pos.distance_to(_cat.global_position) < _sitter.pos.distance_to(_cat.global_position):
						_sitter = p
				else:
					walkers += 1
					if p.active and (_victim == null or p.pos.distance_to(_cat.global_position) < _victim.pos.distance_to(_cat.global_position)):
						_victim = p
			print("PEOPLE_COUNT total=%d walkers=%d sitters=%d active=%d" % [_people.count(), walkers, sitters, _people.active_count()])
			_cam = Camera3D.new()
			_cam.fov = 45.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19:
			# Follow the walker from the side so the picture shows its stride.
			var fwd := Vector3(sin(_victim.yaw), 0.0, cos(_victim.yaw))
			_cam.look_at_from_position(_victim.pos + fwd * 2.6 + fwd.cross(Vector3.UP) * 2.2 + Vector3.UP * 1.3, _victim.pos + Vector3.UP * 0.95, Vector3.UP)
		20:
			_save("people_walker.png")
			print("PEOPLE_WALKER state=%d clip=%s pos=%s yaw=%.2f" % [_victim.state, _victim.clip, _victim.pos.snapped(Vector3.ONE * 0.1), _victim.yaw])
			# Whoever sat near the landing has run off: take the nearest one who is still sitting.
			_sitter = null
			for p in _people.people:
				if p.state == People.State.SIT and (_sitter == null or p.pos.distance_to(_cat.global_position) < _sitter.pos.distance_to(_cat.global_position)):
					_sitter = p
			if _sitter != null:
				# The sitter may be out of range: bring the cat near so it becomes active.
				var out := Vector3(sin(_sitter.yaw), 0.0, cos(_sitter.yaw))
				_cat.global_position = _sitter.pos + out * 6.0 + Vector3.UP * 0.5
				_cat.velocity = Vector3.ZERO
				_cat.reset_physics_interpolation()
				_cam.look_at_from_position(_sitter.pos + out * 3.2 + out.cross(Vector3.UP) * 1.6 + Vector3.UP * 1.2, _sitter.pos + Vector3.UP * 0.7, Vector3.UP)
		80:
			if _sitter != null:
				_save("people_sitter.png")
				print("PEOPLE_SITTER active=%s state=%d clip=%s" % [_sitter.active, _sitter.state, _sitter.clip])
			# Stand the cat in front of a walker that is made to stop, so it speaks; then swat it.
			_victim = null
			for p in _people.people:
				if p.active and p.state == People.State.WALK and (_victim == null or p.pos.distance_to(_cat.global_position) < _victim.pos.distance_to(_cat.global_position)):
					_victim = p
			_victim.state = People.State.PAUSE
			_victim.timer = 30.0
			_victim.spoke = false
			var face := Vector3(sin(_victim.yaw), 0.0, cos(_victim.yaw))
			_cat.global_position = _victim.pos + face * 0.85 + Vector3.UP * 0.2
			_cat.velocity = Vector3.ZERO
			_cat.reset_physics_interpolation()
			_cat.camera.yaw = atan2(face.x, face.z)
			_cat.camera.pitch = deg_to_rad(18.0)
			_cat.camera.snap_to_target()
			_cat.camera.get_camera().make_current()
			_bot.aim = true
		130:
			_save("people_nice_kitty.png")
			_bot.attack = true
		133:
			_bot.attack = false
		146:
			_save("people_shatter.png")
		170:
			print("PEOPLE_SWAT shattered=%d victim_gone=%s panics=%d" % [_people.shattered, _victim.state == People.State.GONE, _people.panics])
			_bot.aim = false
			var before := _people.panics
			DamageRouter.apply_blast(DamageHit.blast(_cat.global_position + Vector3(6.0, 0.5, 0.0), 5.0, 2.0e6, 4000.0, DamageHit.Kind.EXPLOSION, _cat))
			print("PEOPLE_BLAST panics %d -> %d, shattered %d, alive %d" % [before, _people.panics, _people.shattered, _people.alive_count()])
		200:
			# Pee on someone who is not running yet: three drops, one reaction, nobody hurt.
			var dry: People.Person = null
			for p in _people.people:
				if p.active and (p.state == People.State.WALK or p.state == People.State.PAUSE):
					dry = p
					break
			if dry != null:
				var panics_before := _people.panics
				var shattered_before := _people.shattered
				for i in 3:
					DamageRouter.apply_hit(DamageHit.point(dry.pos + Vector3.UP, Vector3(1.0, 0.0, 0.0), 20.0, 0.9, DamageHit.Kind.BLUNT, _cat), null, dry.body)
				print("PEOPLE_WET soaked=%d panics %d -> %d running=%s shattered +%d" % [_people.soaked, panics_before, _people.panics,
					dry.state == People.State.PANIC, _people.shattered - shattered_before])
			else:
				print("PEOPLE_WET nobody calm in reach")
		260:
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			var sum := 0.0
			for v: float in sorted:
				sum += v
			print("PEOPLE_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f n=%d active=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n, _people.active_count()])
			get_tree().quit(0)


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
