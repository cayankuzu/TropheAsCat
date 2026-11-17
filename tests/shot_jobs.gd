extends Node
## Windowed check of the jobs (2026-11-17): the first job waits at its marker, Trophe walks into it, twelve
## fragile things break, the job pays; a ball of golden yarn is picked up. Saves tests/out/jobs_*.png and
## prints JOBS_* lines.
## Run: Godot --path <P> res://tests/shot_jobs.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _jobs: Jobs
var _ok := true


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _move_cat(to: Vector3) -> void:
	_cat.global_position = Vector3(to.x, TerrainShape.height_at(to.x, to.z) + 0.5, to.z)
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f == 0:
		_cat = Game.player as CatPlayer
		_jobs = _main.get("jobs") as Jobs
		print("JOBS_OFFER offered=%d (%s), yarn placed %d" % [_jobs.offered, Jobs.JOBS[_jobs.offered]["title"] if _jobs.offered >= 0 else "-", _jobs._yarns.size()])
		_ok = _ok and _jobs.offered == 0 and _jobs._yarns.size() >= 20
		_move_cat(Jobs.JOBS[0]["at"])
	elif f == 30:
		print("JOBS_START current=%d" % _jobs.current)
		_ok = _ok and _jobs.current == 0
		get_viewport().get_texture().get_image().save_png(OUT + "jobs_start.png")
		# Twelve fragile things break.
		var dressing := _main.get("dressing") as StreetDressing
		var n := 0
		for p in dressing.props:
			if n >= 13:
				break
			if is_instance_valid(p) and p.fragile and not p.is_broken():
				p.receive_damage(DamageHit.point(p.global_position, Vector3.UP, 1.0e5, 0.0, DamageHit.Kind.EXPLOSION, null), 0)
				n += 1
	elif f == 120:
		print("JOBS_DONE done=%s catnip=%d level=%d next=%d" % [_jobs.done, _jobs.catnip, _jobs.level, _jobs.offered])
		_ok = _ok and _jobs.done.has(&"vases") and _jobs.catnip >= 50 and _jobs.offered == 1
		get_viewport().get_texture().get_image().save_png(OUT + "jobs_done.png")
		var y: Node3D = _jobs._yarns[12]
		_move_cat(y.global_position - Vector3.UP * 0.4)
	elif f == 160:
		print("JOBS_YARN found=%d catnip=%d" % [_jobs.yarn_found.size(), _jobs.catnip])
		_ok = _ok and _jobs.yarn_found.size() >= 1
		var state := _jobs.save_state()
		print("JOBS_SAVE %s" % JSON.stringify(state))
		print("JOBS_RESULT ok=%s" % _ok)
		get_tree().quit(0)
