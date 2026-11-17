extends Node
## Windowed look inside (2026-11-17): the living room of a house and a shop from inside, then the house
## blown open and its furniture in the street. Saves tests/out/inside_*.png, prints INSIDE_* lines.
## Run: Godot --path <P> res://tests/shot_inside.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const D := preload("res://game/destruction/destruction_defs.gd")
const Util := preload("res://tests/city_test_util.gd")

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _house := {}
var _shop := {}


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f == 0:
		_cat = Game.player as CatPlayer
		var city := _main.get("city") as CityLayout
		_house = city.nearest_lot(D.Style.HOUSE, Vector3(-150.0, 0.0, -40.0))
		_shop = city.nearest_lot(D.Style.SHOP, Vector3(300.0, 0.0, 200.0))
		var dressing := _main.get("dressing") as StreetDressing
		var inside := 0
		for p in dressing.props:
			var mi := p.find_child("*", true, false) as Node
			if mi != null:
				for node in p.find_children("*", "MeshInstance3D", true, false):
					if (node as MeshInstance3D).visibility_range_end == 45.0:
						inside += 1
						break
		print("INSIDE_PROPS %d props drawn only near (inside), load: %s" % [inside, " | ".join(_main.get("load_report"))])
		_cam = Camera3D.new()
		_cam.fov = 75.0
		add_child(_cam)
		_cam.make_current()
		_look_inside(_house)
	elif f == 40:
		_save("inside_house.png")
		_look_inside(_shop)
	elif f == 80:
		_save("inside_shop.png")
		var city := _main.get("city") as CityLayout
		_look_inside(city.nearest_lot(D.Style.TOWER, Vector3.ZERO), -6.0)
	elif f == 120:
		_save("inside_tower.png")
		var city := _main.get("city") as CityLayout
		_look_inside(city.nearest_lot(D.Style.APARTMENT, Vector3(-100.0, 0.0, 100.0)), -4.0)
	elif f == 160:
		_save("inside_flats.png")
		var at: Vector3 = _house["pos"]
		_move_cat(at + Vector3(0.0, 0.0, 14.0))
		_cam.look_at_from_position(at + Vector3(10.0, 7.0, 14.0), at, Vector3.UP)
	elif f == 190:
		DamageRouter.apply_blast(DamageHit.blast(Util.wall_point(int(_house["bid"]), 1.5), 6.0, 4.0e6, 9000.0))
	elif f == 340:
		_save("inside_blown.png")
		print("INSIDE_RESULT ok=true")
		get_tree().quit(0)


## Camera in the middle of the ground floor of a lot, looking at its back wall.
func _look_inside(lot: Dictionary, from_z := -1.4) -> void:
	var xf := Transform3D(Basis(Vector3.UP, float(lot["yaw"])), lot["pos"])
	var at := xf * Vector3(0.0, 1.6, from_z)
	var to := xf * Vector3(0.0, 0.9, from_z + 4.4)
	_move_cat(xf * Vector3(0.0, 0.0, -12.0))
	_cam.look_at_from_position(at, to, Vector3.UP)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = Vector3(to.x, TerrainShape.height_at(to.x, to.z) + 0.5, to.z)
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
