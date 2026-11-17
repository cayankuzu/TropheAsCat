extends Node
## Windowed check of the chaos stars and the Owner's response (2026-11-17): a real blast raises the heat,
## four stars send police cars and the fire brigade at Trophe, they arrive with flashing lights, turn across
## their lanes, let their people out and put up a road block; five stars send the SWAT van; when the stars
## are gone the units drive off and their people go home once she is away. Saves tests/out/police_*.png and
## prints POLICE_* lines.
## Run: Godot --path <P> res://tests/shot_police.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const SPOT := Vector3(200.0, 0.0, 139.5)

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _chaos: Chaos
var _police: Police
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
			_chaos = _main.get("chaos") as Chaos
			_police = _main.get("police") as Police
			_cam = Camera3D.new()
			_cam.fov = 60.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
			_move_cat(SPOT)
			_cam.look_at_from_position(SPOT + Vector3(-26.0, 22.0, 18.0), SPOT + Vector3(0.0, 0.0, -8.0), Vector3.UP)
		30:
			DamageRouter.apply_blast(DamageHit.blast(SPOT + Vector3(6.0, 0.8, -6.0), 7.0, 3.0e6, 14000.0, DamageHit.Kind.EXPLOSION, null))
		90:
			print("POLICE_REAL heat %.1f stars %d after one blast" % [_chaos.heat, _chaos.stars])
			_ok = _ok and _chaos.heat > 0.0
			_chaos.add(160.0)
		700:
			print("POLICE_SENT stars %d, %d units sent, %d on duty" % [_chaos.stars, _police.dispatched, _police.active_units()])
			_ok = _ok and _chaos.stars >= 4 and _police.dispatched >= 3
		2100:
			var near := 0
			for u in _police.units:
				if not u.car.gone and u.car.parked and u.car.pos.distance_to(_cat.global_position) < 45.0:
					near += 1
			print("POLICE_ARRIVED %d units parked near her, %d arrived in all, %d people out, %d road blocks" % [near, _police.arrived, _police.officers.size(), _police.blocks])
			_ok = _ok and _police.arrived >= 2 and _police.officers.size() >= 2 and _police.blocks >= 1
			_save("police_arrived.png")
			_chaos.add(250.0)
		2120:
			_cam.look_at_from_position(_cat.global_position + Vector3(9.0, 3.5, 9.0), _cat.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		2160:
			_save("police_close.png")
		2900:
			var kinds := {}
			for u in _police.units:
				if not u.car.gone:
					kinds[u.kind] = int(kinds.get(u.kind, 0)) + 1
			print("POLICE_FIVE stars %d, units by kind %s (0 police, 1 fire, 2 SWAT)" % [_chaos.stars, kinds])
			_ok = _ok and _chaos.stars == 5 and kinds.has(Police.Kind.SWAT)
			_cam.look_at_from_position(_cat.global_position + Vector3(-30.0, 26.0, 20.0), _cat.global_position, Vector3.UP)
		2930:
			_save("police_swat.png")
			_chaos.reset()
		2990:
			_move_cat(SPOT + Vector3(-130.0, 0.0, 0.0))
		3800:
			var alive := 0
			for id in _police.officers:
				if _main.get("people").people[id].state != People.State.GONE:
					alive += 1
			print("POLICE_CALM stars %d, %d units on duty, %d people still out" % [_chaos.stars, _police.active_units(), alive])
			_ok = _ok and _chaos.stars == 0 and _police.active_units() == 0 and alive == 0
			_police.dismiss_all()
			print("POLICE_RESULT ok=%s sent=%d arrived=%d blocks=%d" % [_ok, _police.dispatched, _police.arrived, _police.blocks])
			get_tree().quit(0)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = Vector3(to.x, TerrainShape.height_at(to.x, to.z) + 0.5, to.z)
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
