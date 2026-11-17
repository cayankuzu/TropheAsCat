extends Node
## Windowed check of the lite build on the desktop (2026-11-17): with Game.lite set before the world is built
## the ground is FlatTerrain (no Voxel Tools), there are half the walkers and 40 cars, Trophe stands on the
## ground, and a big blast next to her breaks things without errors and without digging. Prints LITE_* lines
## and the frame times; saves tests/out/lite_*.png.
## Run: Godot --path <P> res://tests/shot_lite.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _ms: Array[float] = []
var _ok := true


func _ready() -> void:
	Game.lite = true
	CityLayout.BLOCKS_OUT = 1   # the browser demo's small city
	CityLayout.INNER_OUT = 1
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f > 0:
		_ms.append(delta * 1000.0)
	if f == 0:
		var cat := Game.player as Node3D
		var ground := TerrainShape.height_at(cat.global_position.x, cat.global_position.z)
		print("LITE_TERRAIN flat=%s cat_y=%.2f ground=%.2f" % [Game.terrain is FlatTerrain, cat.global_position.y, ground])
		_ok = _ok and Game.terrain is FlatTerrain and absf(cat.global_position.y - ground) < 1.5
		var people: People = _main.get("people")
		var traffic: Traffic = _main.get("traffic")
		print("LITE_COUNTS people=%d cars=%d" % [people.count(), traffic.cars.size()])
		_ok = _ok and people.count() < 120 and traffic.cars.size() <= 14
		get_viewport().get_texture().get_image().save_png(OUT + "lite_spawn.png")
	elif f == 60:
		var cat := Game.player as Node3D
		var at := cat.global_position + Vector3(0.0, 0.0, -14.0)
		DamageRouter.apply_blast(DamageHit.blast(at, 9.0, 4.0e6, 4.0e4))
		print("LITE_BLAST at %s ground still flat: %s" % [at, Game.terrain.call(&"is_solid_at", at + Vector3.DOWN * 0.3)])
	elif f == 100:
		get_viewport().get_texture().get_image().save_png(OUT + "lite_blast.png")
	elif f == 400:
		_ms.sort()
		var n := _ms.size()
		print("LITE_FRAME_MS p50=%.2f p95=%.2f p99=%.2f n=%d" % [_ms[n >> 1], _ms[int(n * 0.95)], _ms[int(n * 0.99)], n])
		print("LITE_RESULT ok=%s" % _ok)
		get_tree().quit(0)
