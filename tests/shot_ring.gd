extends Node
## Windowed look at the outer ring of the city (2026-11-17): the whole Table from above, a mall behind its
## car park, a fuel station forecourt, the loading yard of the Yards, a plot of container stacks, a street
## of the Suburbs, and a fuel pump blown up next to its neighbours. Saves tests/out/ring_*.png and prints
## RING_SHOT_* lines (counts, frame times, draw calls, the chain at the pumps).
## Run: Godot --path <P> res://tests/shot_ring.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const D := preload("res://game/destruction/destruction_defs.gd")

var _frame := 0
var _main: Node3D
var _city: CityLayout
var _cat: CatPlayer
var _cam: Camera3D
var _pumps: Array[BreakableProp] = []


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	match f:
		0:
			_city = _main.get("city") as CityLayout
			_cat = Game.player as CatPlayer
			_cam = Camera3D.new()
			_cam.fov = 60.0
			_cam.far = 3000.0
			add_child(_cam)
			_cam.make_current()
			var dressing := _main.get("dressing") as StreetDressing
			var by_id := {}
			for p in dressing.props:
				by_id[p.prop_id] = int(by_id.get(p.prop_id, 0)) + 1
			print("RING_SHOT_LOTS %d buildings, %d props (containers %d, pumps %d, fences %d), load %s"
				% [_city.lots.size(), dressing.prop_count(), by_id.get(&"shipping_container", 0), by_id.get(&"fuel_pump", 0), by_id.get(&"fence", 0),
				" | ".join(_main.get("load_report"))])
			_cam.look_at_from_position(Vector3(560.0, 330.0, 560.0), Vector3(40.0, 0.0, 40.0), Vector3.UP)
		60:
			_save("ring_aerial.png")
			_stats("aerial")
			var mall := _lot(D.Style.MALL, Vector3(320.0, 0.0, 320.0))
			_look_at_front(mall, 58.0, 12.0, 2.0)
		120:
			_save("ring_mall.png")
			_stats("mall")
			var spot: Dictionary = _city.forecourts[0]
			var at: Vector3 = spot["pos"]
			_move_cat(at + Vector3(-16.0, 0.5, -20.0))
			_cam.look_at_from_position(at + Vector3(-17.0, 4.5, -21.0), at + Vector3(0.0, 2.0, 0.0), Vector3.UP)
		180:
			_save("ring_fuel.png")
			var yard: Vector3 = _city.loading_yards[0]
			_move_cat(yard + Vector3(-50.0, 0.5, 0.0))
			_cam.look_at_from_position(yard + Vector3(-52.0, 8.0, -3.0), yard + Vector3(10.0, 3.0, 0.0), Vector3.UP)
		240:
			_save("ring_yards.png")
			if not _city.container_yards.is_empty():
				var cy: Vector3 = _city.container_yards[0]
				_move_cat(cy + Vector3(16.0, 0.5, -16.0))
				_cam.look_at_from_position(cy + Vector3(18.0, 7.0, -18.0), cy + Vector3(0.0, 2.0, 0.0), Vector3.UP)
		300:
			_save("ring_containers.png")
			var c: Vector3 = _city.lawns[0]
			_move_cat(c + Vector3(-18.0, 0.5, -57.0))
			_cam.look_at_from_position(c + Vector3(-22.0, 2.6, -58.5), c + Vector3(0.0, 2.0, -38.0), Vector3.UP)
		360:
			_save("ring_suburbs.png")
			_stats("suburbs")
			# The pumps: blow one up and count how many of the station's pumps go with it.
			var spot: Dictionary = _city.forecourts[0]
			var at: Vector3 = spot["pos"]
			_move_cat(at + Vector3(-22.0, 0.5, -24.0))
			_cam.look_at_from_position(at + Vector3(-24.0, 6.0, -26.0), at + Vector3(0.0, 2.5, 0.0), Vector3.UP)
			var dressing := _main.get("dressing") as StreetDressing
			for p in dressing.props:
				if p.prop_id == &"fuel_pump" and p.global_position.distance_to(at) < 8.0:
					_pumps.append(p)
		420:
			var first := _pumps[0]
			var hit := DamageHit.blast(first.global_position + Vector3(0.0, 1.0, 0.0), 2.0, 2.0e6, 4000.0, DamageHit.Kind.EXPLOSION, null)
			DamageRouter.apply_blast(hit)
		445:
			_save("ring_pump_blast.png")
		540:
			var gone := 0
			for p in _pumps:
				if not is_instance_valid(p) or p.is_broken():
					gone += 1
			var sm := Game.structures as StructureManager
			var canopy := _lot(D.Style.CANOPY, (_city.forecourts[0] as Dictionary)["pos"])
			print("RING_SHOT_PUMPS %d of %d pumps went up, canopy elements gone %d" % [gone, _pumps.size(), sm.removed_elements(int(canopy["bid"])).size()])
			_save("ring_pump_after.png")
			get_tree().quit(0)


func _stats(tag: String) -> void:
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("RING_SHOT_FRAME %s fps=%d draws=%d prims=%.2fM" % [tag, Engine.get_frames_per_second(), draws, prims / 1.0e6])


## The lot of a style nearest to a point.
func _lot(style: int, near: Vector3) -> Dictionary:
	var best := {}
	var best_d := 1.0e18
	for lot in _city.lots:
		if int(lot["style"]) != style:
			continue
		var d := (lot["pos"] as Vector3).distance_squared_to(near)
		if d < best_d:
			best_d = d
			best = lot
	return best


## Camera in front of side 0 of a lot, at a height, looking at a point `aim_h` metres up the facade.
func _look_at_front(lot: Dictionary, distance: float, height: float, aim_h: float) -> void:
	var basis := Basis(Vector3.UP, float(lot["yaw"]))
	var out := basis * Vector3(0.0, 0.0, -1.0)
	var pos: Vector3 = lot["pos"]
	var depth: float = (lot["size"] as Vector2).y if absf(out.z) > 0.5 else (lot["size"] as Vector2).x
	var face := pos + out * (depth * 0.5)
	var eye := face + out * distance + Vector3.UP * height
	_move_cat(eye - Vector3.UP * (height - 0.5))
	_cam.look_at_from_position(eye, face + Vector3.UP * aim_h, Vector3.UP)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = to
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
