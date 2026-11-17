extends Node
## Windowed check of the people's reactions (2026-11-17): witnesses of chaos at a distance film it (a phone in
## the hand, views go up), call the police (Chaos heat), and a rude one near Trophe chases her and kicks her
## away. Prints REACT_* lines, saves tests/out/react_*.png.
## Run: Godot --path <P> res://tests/shot_react.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _people: People
var _chaser := -1
var _caller := -1
var _heat0 := 0.0
var _ok := true


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _active() -> Array:
	var out := []
	for p in _people.people:
		if p.active and p.state != People.State.GONE and p.officer == 0:
			out.append(p)
	return out


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f == 0:
		_people = _main.get("people") as People
		var cat := Game.player as Node3D
		var act := _active()
		print("REACT_ACTIVE %d near the cat" % act.size())
		# Her chaos, where she stands: witnesses farther than 11 m may film or call, the near ones run.
		var at := cat.global_position
		_people.scare(at, 60.0)
		var n := {}
		for p in act:
			n[p.state] = int(n.get(p.state, 0)) + 1
		print("REACT_STATES film=%d call=%d chase=%d panic=%d" % [n.get(People.State.FILM, 0), n.get(People.State.CALL, 0), n.get(People.State.CHASE, 0), n.get(People.State.PANIC, 0)])
		_ok = _ok and int(n.get(People.State.FILM, 0)) > 0
		# One caller and one chaser for sure.
		var chaos := _main.get("chaos") as Chaos
		_heat0 = chaos.heat if chaos != null else 0.0
		for p in act:
			if _caller < 0 and p.state != People.State.FILM:
				_caller = p.id
				p.state = People.State.CALL
				p.timer = 0.6
			elif _chaser < 0 and p.state != People.State.FILM and p.id != _caller:
				_chaser = p.id
				p.state = People.State.CHASE
				p.timer = 8.0
				p.off_lane = true
				p.pos = cat.global_position + Vector3(3.0, 0.0, 0.0)
	elif f == 30:
		# A close look at someone filming: is the phone in the hand, and the right size?
		for p in _people.people:
			if p.active and p.state == People.State.FILM:
				var cam := Camera3D.new()
				cam.name = "CloseUp"
				add_child(cam)
				var fwd := Vector3(sin(p.yaw), 0.0, cos(p.yaw))
				cam.look_at_from_position(p.pos + fwd * 2.4 + Vector3.UP * 1.7 + fwd.cross(Vector3.UP) * 0.8, p.pos + Vector3.UP * 1.25, Vector3.UP)
				cam.make_current()
				print("REACT_PHONE visible=%s" % (p.phone != null and p.phone.visible))
				break
	elif f == 33:
		get_viewport().get_texture().get_image().save_png(OUT + "react_phone.png")
		var cam := get_node_or_null("CloseUp") as Camera3D
		if cam != null:
			cam.queue_free()
	elif f == 45:
		get_viewport().get_texture().get_image().save_png(OUT + "react_film.png")
		var chaos := _main.get("chaos") as Chaos
		print("REACT_CALL calls=%d heat %.1f -> %.1f" % [_people.calls, _heat0, chaos.heat if chaos != null else -1.0])
		_ok = _ok and _people.calls >= 1 and chaos != null and chaos.heat >= _heat0 + Chaos.CALL_HEAT - 0.5
	elif f == 120:
		var cat := Game.player as CharacterBody3D
		print("REACT_KICK kicks=%d cat_y=%.2f" % [_people.kicks, cat.global_position.y])
		_ok = _ok and _people.kicks >= 1
		print("REACT_VIEWS %.0f filming now %d" % [_people.views, _people.filming_count()])
		_ok = _ok and _people.views > 0.0
		get_viewport().get_texture().get_image().save_png(OUT + "react_later.png")
		print("REACT_RESULT ok=%s" % _ok)
		get_tree().quit(0)
