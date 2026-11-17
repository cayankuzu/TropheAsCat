extends Node
## Store-page pictures (2026-11-17): the HUD hidden, a free camera. A view over the city at golden hour,
## Trophe on the crossing with the dominoes and the people, and a tower blown at its foot coming down in front
## of her (three moments). Saves tests/out/mk_*.png at the window's resolution (run it at 1920x1080).
## Run: Godot --path <P> res://tests/shot_marketing.tscn --resolution 1920x1080

const OUT := "res://tests/out/"
const T0 := 430
const D := preload("res://game/destruction/destruction_defs.gd")
const Util := preload("res://tests/city_test_util.gd")

var _frame := 0
var _main: Node3D
var _cam: Camera3D
var _cat: CatPlayer
var _tower := {}
var _car: BreakableProp


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_hud() -> void:
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f == 0:
		_hide_hud()
		_cat = Game.player as CatPlayer
		_cam = Camera3D.new()
		_cam.fov = 58.0
		_cam.far = 3000.0
		add_child(_cam)
		_cam.make_current()
		_cam.look_at_from_position(Vector3(150.0, 70.0, 170.0), Vector3(-20.0, 8.0, -10.0), Vector3.UP)
	elif f == 20:
		_save("mk_city.png")
		# The cover: Trophe walks towards the camera while the parked cars behind her go up.
		var dressing := _main.get("dressing") as StreetDressing
		var best := 1.0e9
		for a in dressing.props:
			if not a.wreck or a.global_position.length() > 110.0:
				continue
			for b in dressing.props:
				if b != a and b.wreck and a.global_position.distance_to(b.global_position) < best:
					best = a.global_position.distance_to(b.global_position)
					_car = a
		var v := _car.global_position
		var dir := Vector3(-v.x, 0.0, -v.z).normalized()   # towards the middle of the city, along the street
		var spot := v + dir * 7.0
		_cat.global_position = Vector3(spot.x, TerrainShape.height_at(spot.x, spot.z) + 0.4, spot.z)
		_cat.velocity = Vector3.ZERO
		_cat.reset_physics_interpolation()
		_cat.face(dir)
		_cam.fov = 50.0
		var side := dir.cross(Vector3.UP) * 1.6
		_cam.look_at_from_position(spot + dir * 4.6 + side + Vector3.UP * 0.9, spot - dir * 3.0 + Vector3.UP * 1.3, Vector3.UP)
	elif f == 80:
		_cat.face(Vector3(_cam.global_position.x - _cat.global_position.x, 0.0, _cam.global_position.z - _cat.global_position.z))
		DamageRouter.apply_blast(DamageHit.blast(_car.global_position + Vector3.UP * 0.8, 3.5, 3.0e6, 4000.0, DamageHit.Kind.EXPLOSION, _cat))
	elif f == 88:
		_save("mk_cover_a.png")
	elif f == 96:
		_save("mk_cover_b.png")
	elif f == 106:
		_save("mk_cover_c.png")
	elif f == 122:
		_save("mk_cover_d.png")
		# A tower ahead of her, blown at its foot.
		var city := _main.get("city") as CityLayout
		_tower = city.nearest_lot(D.Style.TOWER, Vector3(60.0, 0.0, -60.0))
		var c: Vector3 = _tower["pos"]
		var to_cat := Vector3(0.0, 0.0, 34.0)
		var spot := c + to_cat
		_cat.global_position = Vector3(spot.x, TerrainShape.height_at(spot.x, spot.z) + 0.5, spot.z)
		_cat.velocity = Vector3.ZERO
		_cat.reset_physics_interpolation()
		_cam.fov = 62.0
		_cam.look_at_from_position(spot + Vector3(3.0, 1.6, 6.5), c + Vector3(0.0, 16.0, 0.0), Vector3.UP)
	elif f == 140:
		var bid := int(_tower["bid"])
		for h: float in [1.5, 5.0]:
			DamageRouter.apply_blast(DamageHit.blast(Util.wall_point(bid, h), 7.0, 6.0e6, 12000.0))
	elif f == 175:
		_save("mk_collapse_a.png")
	elif f == 230:
		_save("mk_collapse_b.png")
	elif f == 300:
		_save("mk_collapse_c.png")
		get_tree().quit(0)
