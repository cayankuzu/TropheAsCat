extends Node
## Windowed check of the opening film (2026-11-17): plays it over a built world and saves frames at the
## first subtitle, the typed line of code and CAT AS TROPHE. Saves tests/out/opening_*.png, prints OPENING_*.
## Run: Godot --path <P> res://tests/shot_opening.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _opening: Opening
var _cam: Camera3D
var _t := 0.0
var _shots := {1.6: "opening_table.png", 9.9: "opening_code.png", 11.6: "opening_title.png"}


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _process(delta: float) -> void:
	_frame += 1
	if _frame == T0:
		_cam = Camera3D.new()
		_cam.far = 3000.0
		add_child(_cam)
		_cam.make_current()
		_opening = Opening.new()
		add_child(_opening)
		_play()
	elif _opening != null:
		_t += delta
		for at: float in _shots.keys():
			if _t >= at and _shots[at] != "":
				get_viewport().get_texture().get_image().save_png(OUT + String(_shots[at]))
				print("saved ", _shots[at])
				_shots[at] = ""


func _play() -> void:
	await _opening.play(_cam)
	print("OPENING_RESULT ok=%s length %.1f s" % [not _opening.skipped, _t])
	get_tree().quit(0)
