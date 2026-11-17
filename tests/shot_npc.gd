extends Node
## Windowed look at the living city (2026-11-17): people on a Downtown plaza, someone on a bench, walkers
## in the Old Quarter, the paddock of the petting farm, deer in the outer Park before and after Trophe
## runs at them, a dog of the Suburbs coming at her, a herd on the hills. Saves tests/out/npc_*.png and
## prints NPC_* lines (the cast in use, the animals by kind and size, flights and chases).
## Run: Godot --path <P> res://tests/shot_npc.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _people: People
var _wild: Wildlife
var _target: Wildlife.Beast = null


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
			_people = _main.get("people") as People
			_wild = _main.get("wildlife") as Wildlife
			_cam = Camera3D.new()
			_cam.fov = 55.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
			_report()
			var city := _main.get("city") as CityLayout
			var plaza: Vector3 = city.plazas[0]
			_move_cat(plaza + Vector3(0.0, 0.5, -8.0))
			_cam.look_at_from_position(plaza + Vector3(-9.0, 2.2, -14.0), plaza + Vector3(2.0, 1.0, 2.0), Vector3.UP)
		120:
			_save("npc_plaza.png")
			var sitter := _first_person(People.State.SIT)
			if sitter != null:
				var fwd := Vector3(sin(sitter.yaw), 0.0, cos(sitter.yaw))
				_move_cat(sitter.pos + fwd * 6.0 + Vector3.UP * 0.5)
				_cam.look_at_from_position(sitter.pos + fwd * 3.0 + Vector3(1.2, 1.4, 0.0), sitter.pos + Vector3.UP * 0.8, Vector3.UP)
		200:
			_save("npc_sitter.png")
			_move_cat(Vector3(-117.0, 0.5, -80.0))
		260:
			var walker := _first_person(People.State.WALK, Vector3(-117.0, 0.0, -80.0))
			if walker != null:
				var fwd := Vector3(sin(walker.yaw), 0.0, cos(walker.yaw))
				_cam.look_at_from_position(walker.pos + fwd * 5.0 + Vector3(1.5, 1.6, 0.0), walker.pos + Vector3.UP * 1.0, Vector3.UP)
		262:
			_save("npc_walker.png")
			var pen := Wildlife.paddock_rect()
			var c := Vector3(pen.get_center().x, 0.0, pen.get_center().y)
			_move_cat(c + Vector3(0.0, 0.5, -30.0))
			_cam.look_at_from_position(c + Vector3(-6.0, 6.0, -28.0), c, Vector3.UP)
		360:
			_save("npc_paddock.png")
			_target = _first_beast(&"deer", true)
			if _target != null:
				_move_cat(_target.pos + Vector3(30.0, 0.5, 0.0))
				_cam.look_at_from_position(_target.pos + Vector3(14.0, 3.0, 8.0), _target.pos + Vector3.UP * 0.8, Vector3.UP)
		440:
			_save("npc_deer.png")
			if _target != null:
				_move_cat(_target.pos + Vector3(5.0, 0.5, 0.0))
		500:
			_save("npc_deer_flee.png")
			_target = _first_beast(&"husky", false)
			if _target == null:
				_target = _first_beast(&"shiba", false)
			if _target != null:
				_move_cat(_target.pos + Vector3(6.0, 0.5, 2.0))
				_cam.look_at_from_position(_target.pos + Vector3(9.0, 2.5, 7.0), _target.pos + Vector3(3.0, 0.4, 1.0), Vector3.UP)
		580:
			_save("npc_dog.png")
			_target = _first_beast(&"stag", false, 400.0)
			if _target != null:
				_move_cat(_target.pos + Vector3(-40.0, 0.5, 0.0))
				_cam.look_at_from_position(_target.pos + Vector3(-22.0, 6.0, -12.0), _target.pos + Vector3.UP * 1.0, Vector3.UP)
		680:
			_save("npc_hills.png")
			print("NPC_REACT flights=%d chases=%d people active=%d" % [_wild.flights, _wild.chases, _people.active_count()])
			get_tree().quit(0)


func _report() -> void:
	var figures := {}
	for p in _people.people:
		var n := String(People.CAST[p.look][0])
		figures[n] = int(figures.get(n, 0)) + 1
	print("NPC_PEOPLE %d: %s" % [_people.count(), figures])
	var kinds := {}
	for b in _wild.beasts:
		kinds[b.kind] = int(kinds.get(b.kind, 0)) + 1
	print("NPC_WILD %d: %s" % [_wild.count(), kinds])
	print("NPC_SCALE %s" % [_wild._scale])
	print("NPC_LOAD ", " | ".join(_main.get("load_report")))


func _first_person(state: int, near: Vector3 = Vector3.ZERO) -> People.Person:
	var best: People.Person = null
	var best_d := 1.0e18
	for p in _people.people:
		if p.state != state:
			continue
		var d := p.pos.distance_squared_to(near) if near != Vector3.ZERO else float(p.id)
		if d < best_d:
			best_d = d
			best = p
	return best


func _first_beast(kind: StringName, outer_park: bool, min_reach: float = 0.0) -> Wildlife.Beast:
	for b in _wild.beasts:
		if b.kind != kind:
			continue
		if outer_park and maxf(absf(b.pos.x), absf(b.pos.z)) < 256.0:
			continue
		if maxf(absf(b.pos.x), absf(b.pos.z)) < min_reach:
			continue
		return b
	return null


func _move_cat(to: Vector3) -> void:
	_cat.global_position = Vector3(to.x, TerrainShape.height_at(to.x, to.z) + 0.5, to.z)
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
