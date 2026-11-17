extends Node
## Windowed look at the facades: a downtown tower from the pavement, the shop front and the balcony side of
## an Old Quarter apartment block, a row of houses, a parking deck, and the city from above. Saves
## tests/out/facade_*.png and prints FACADE_* lines (element counts per style, materials in use).
## Run: Godot --path <P> res://tests/shot_facades.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const D := preload("res://game/destruction/destruction_defs.gd")

var _frame := 0
var _main: Node3D
var _city: CityLayout
var _cat: CatPlayer
var _cam: Camera3D
var _frame_ms := PackedFloat32Array()
var _last_usec := 0


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > T0:
		_frame_ms.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	var f := _frame - T0
	match f:
		0:
			_city = _main.get("city") as CityLayout
			_cat = Game.player as CatPlayer
			_cam = Camera3D.new()
			_cam.fov = 60.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
			_report()
			var tower := _lot(D.Style.TOWER, Vector3(70.0, 0.0, 70.0))
			_look_at_front(tower, 15.0, 1.6, 9.0)
		50:
			_save("facade_tower.png")
			var tower := _lot(D.Style.TOWER, Vector3(70.0, 0.0, 70.0))
			_look_at_front(tower, 26.0, 1.7, 26.0)
		90:
			_save("facade_tower_full.png")
			var apt := _lot(D.Style.APARTMENT, Vector3(-64.0, 0.0, -104.0), CityLayout.District.OLD_QUARTER)
			_look_at_front(apt, 11.0, 1.7, 3.2)
		140:
			_save("facade_shops.png")
			var apt := _lot(D.Style.APARTMENT, Vector3(-64.0, 0.0, -104.0), CityLayout.District.OLD_QUARTER)
			_look_at_front(apt, -13.0, 4.5, 6.0)
		190:
			_save("facade_balconies.png")
			var house := _lot(D.Style.HOUSE, Vector3(-150.0, 0.0, -40.0), CityLayout.District.OLD_QUARTER)
			_look_at_front(house, 9.0, 1.7, 3.0, 4.0)
		240:
			_save("facade_houses.png")
			var deck := _lot(D.Style.PARKING, Vector3(100.0, 0.0, -100.0))
			_look_at_front(deck, 9.0, 1.7, 5.0)
		290:
			_save("facade_parking.png")
			_move_cat(Vector3(-60.0, 0.5, -60.0))
			_cam.look_at_from_position(Vector3(40.0, 120.0, 60.0), Vector3(-60.0, 0.0, -60.0), Vector3.UP)
		350:
			_save("facade_aerial.png")
			_cam.look_at_from_position(Vector3(-20.0, 60.0, -20.0), Vector3(90.0, 10.0, 90.0), Vector3.UP)
		410:
			_save("facade_downtown.png")
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			var sum := 0.0
			for v: float in sorted:
				sum += v
			print("FACADE_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f n=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n])
			get_tree().quit(0)


## Element counts per style (mean over the city's designs) and the materials in use.
func _report() -> void:
	var sm := Game.structures as StructureManager
	var per_style := {}
	var mats := {}
	var total := 0
	for lot in _city.lots:
		var b = sm.buildings[int(lot["bid"])]
		var data: BuildingData = b.data
		total += data.count()
		var s := int(lot["style"])
		var acc: Array = per_style.get(s, [0, 0])
		acc[0] += data.count()
		acc[1] += 1
		per_style[s] = acc
		for m in data.materials:
			mats[m] = true
	var line := ""
	for s: int in per_style:
		line += "%s %d avg (%d) " % [D.STYLE_NAMES[s], per_style[s][0] / per_style[s][1], per_style[s][1]]
	print("FACADE_ELEMENTS total=%d %s" % [total, line])
	print("FACADE_MATERIALS %d in use" % mats.size())
	print("FACADE_LOAD ", " | ".join(_main.get("load_report")))


## The lot of a style nearest to a point (in a district when one is given).
func _lot(style: int, near: Vector3, district: int = -1) -> Dictionary:
	var best := {}
	var best_d := 1.0e18
	for lot in _city.lots:
		if int(lot["style"]) != style or (district >= 0 and int(lot["district"]) != district):
			continue
		var d := (lot["pos"] as Vector3).distance_squared_to(near)
		if d < best_d:
			best_d = d
			best = lot
	return best


## Camera in front of side 0 of a lot (negative distance: behind it, at side 1), at a height, looking at
## a point `aim_h` metres up the facade, shifted `along` metres along it.
func _look_at_front(lot: Dictionary, distance: float, height: float, aim_h: float, along: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, float(lot["yaw"]))
	var out := basis * Vector3(0.0, 0.0, -1.0)
	var side := basis * Vector3(1.0, 0.0, 0.0)
	var pos: Vector3 = lot["pos"]
	var depth: float = (lot["size"] as Vector2).y if absf(out.z) > 0.5 else (lot["size"] as Vector2).x
	var face := pos + out * (depth * 0.5 * signf(distance))
	var eye := face + out * distance + side * along + Vector3.UP * height
	_move_cat(eye - Vector3.UP * (height - 0.5) + side * 2.0)
	_cam.look_at_from_position(eye, face + side * along * 0.3 + Vector3.UP * aim_h, Vector3.UP)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = to
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
