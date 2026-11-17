extends Node
## Windowed check of the doors (2026-11-17): Trophe walks up to the front door of a house, it swings open,
## she walks in. Saves tests/out/doors_*.png and prints DOORS_* lines.
## Run: Godot --path <P> res://tests/shot_doors.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const D := preload("res://game/destruction/destruction_defs.gd")

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _bot := CatInput.new()
var _lot := {}
var _room := AABB()
var _xf := Transform3D.IDENTITY


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
		_lot = city.nearest_lot(D.Style.HOUSE, Vector3(-320.0, 0.0, -224.0))   # a suburban house facing its street
		var sm := Game.structures as StructureManager
		sm.wake_building(int(_lot["bid"]))
		_xf = Transform3D(Basis(Vector3.UP, float(_lot["yaw"])), _lot["pos"])
		_room = PropSets._room(sm.buildings[int(_lot["bid"])].data, 0.3)
		# In front of the middle of side 0 (the door), facing the house.
		var door_x := _door_x(sm.buildings[int(_lot["bid"])].data)
		var start := _xf * Vector3(door_x, 0.0, _room.position.z - 3.0)
		_cat.global_position = start + Vector3.UP * 0.4
		_cat.velocity = Vector3.ZERO
		_cat.reset_physics_interpolation()
		_cat.face(_xf.basis * Vector3(0.0, 0.0, 1.0))
		_cat.bot_input = _bot
	elif f == 40 or f == 100:
		# Again once the ground there has its collision (it streams in round her).
		var sm := Game.structures as StructureManager
		var start := _xf * Vector3(_door_x(sm.buildings[int(_lot["bid"])].data), 0.0, _room.position.z - 3.0)
		_cat.global_position = start + Vector3.UP * 0.4
		_cat.velocity = Vector3.ZERO
		_cat.reset_physics_interpolation()
		_cat.face(_xf.basis * Vector3(0.0, 0.0, 1.0))
	elif f == 160:
		_bot.move = Vector2(0.0, 1.0)   # walk forward (towards the door)
	elif f == 300:
		_bot.move = Vector2.ZERO
		var sm := Game.structures as StructureManager
		var local := _xf.affine_inverse() * _cat.global_position
		var inside := _room.grow(0.2).has_point(Vector3(local.x, _room.get_center().y, local.z))
		print("DOORS_RESULT ok=%s opened=%d cat inside the house=%s (local %s)" % [inside and sm.doors_opened > 0, sm.doors_opened, inside, local.snapped(Vector3.ONE * 0.1)])
		get_viewport().get_texture().get_image().save_png(OUT + "doors_inside.png")
		get_tree().quit(0)


## Local x of the middle of the front door of a house design.
func _door_x(data: BuildingData) -> float:
	for i in data.count():
		if data.kind[i] == D.Kind.DOOR and data.storey[i] == 0:
			return data.xf[i].origin.x
	return 0.0
