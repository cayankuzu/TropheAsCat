extends Node
## Windowed check of the opening set piece: the domino run in front of the landing spot. One paw swat
## at the first tile, then the test follows the run to its finale (fuel drums, a truck, parked cars).
## Saves tests/out/domino_*.png and prints DOMINO_* lines.
## Run: Godot --path <P> res://tests/shot_dominoes.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const TIMEOUT := 1700

var _frame := 0
var _main: Node3D
var _run: DominoRun
var _cat: CatPlayer
var _cam: Camera3D
var _dressing: StreetDressing
var _broken := 0
var _swat_frame := -1
var _all_down_frame := -1
var _wave_saved := false
var _first := Vector3.ZERO
var _last := Vector3.ZERO
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
	if f < 0:
		return
	if f == 0:
		_run = _main.get_node("Dominoes") as DominoRun
		_dressing = _main.get_node("StreetDressing") as StreetDressing
		_cat = Game.player as CatPlayer
		_first = _run.tiles[0].global_position
		_last = _run.tiles[_run.tiles.size() - 1].global_position
		for p in _dressing.props:
			p.broken.connect(func(_b: BreakableProp) -> void: _broken += 1)
		print("DOMINO_COUNT tiles=%d first=%s last=%s cat=%s upright=%.2f" % [_run.tiles.size(), _first.snapped(Vector3.ONE * 0.1),
			_last.snapped(Vector3.ONE * 0.1), _cat.global_position.snapped(Vector3.ONE * 0.1), _run.tiles[0].global_basis.y.y])
		_save("domino_start.png")   # what the player sees after landing
	elif f == 12:
		_cam = Camera3D.new()
		_cam.fov = 55.0
		_cam.far = 2000.0
		add_child(_cam)
		_cam.make_current()
		var first := _run.tiles[0]
		var hit := DamageHit.point(first.global_position + Vector3.UP * 1.6, Vector3(0.0, 0.0, 1.0), 3000.0, 300.0, DamageHit.Kind.BLUNT, _cat)
		DamageRouter.apply_hit(hit, first, first.get_rid())
		_swat_frame = f
	# Q held for half a second while the run goes: slow motion, and back.
	if f == 60:
		var press := InputEventAction.new()
		press.action = &"slow_motion"
		press.pressed = true
		Input.parse_input_event(press)
	elif f == 75:
		print("DOMINO_SLOWMO held: time scale %.2f, audio %.2f" % [Engine.time_scale, AudioServer.playback_speed_scale])
	elif f == 90:
		var release := InputEventAction.new()
		release.action = &"slow_motion"
		release.pressed = false
		Input.parse_input_event(release)
	elif f == 100:
		print("DOMINO_SLOWMO released: time scale %.2f, audio %.2f" % [Engine.time_scale, AudioServer.playback_speed_scale])
	if _cam != null and _all_down_frame < 0:
		# Ride along beside the falling front.
		var front := _first.lerp(_last, clampf(float(_run.fallen) / _run.tiles.size(), 0.0, 1.0))
		_cam.look_at_from_position(front + Vector3(9.0, 3.6, -7.0), front + Vector3(0.0, 1.0, 5.0), Vector3.UP)
	if _swat_frame >= 0 and not _wave_saved and _run.fallen >= 14:
		_wave_saved = true
		_save("domino_wave.png")
		print("DOMINO_WAVE 14 down %d frames after the swat" % (f - _swat_frame))
	if _swat_frame >= 0 and _all_down_frame < 0 and _run.fallen >= _run.tiles.size():
		_all_down_frame = f
		_cam.look_at_from_position(_last + Vector3(3.5, 7.5, -13.0), _last + Vector3(0.0, 1.0, 7.0), Vector3.UP)
	if _all_down_frame >= 0 and f == _all_down_frame + 24:
		_save("domino_finale.png")
	if (_all_down_frame >= 0 and f == _all_down_frame + 200) or f == TIMEOUT:
		_save("domino_after.png")
		var frames := (_all_down_frame if _all_down_frame >= 0 else f) - _swat_frame
		var seconds := frames / 60.0
		print("DOMINO_RESULT fallen=%d of %d in %d frames (%.1f s, %.1f m/s)%s" % [_run.fallen, _run.tiles.size(), frames, seconds,
			_first.distance_to(_last) / maxf(seconds, 0.01), "" if _all_down_frame >= 0 else "  TIMEOUT"])
		print("DOMINO_FINALE props broken=%d best chain=%d (%s)" % [_broken, Progress.best_chain, Progress.chain_title(Progress.best_chain)])
		var sorted := Array(_frame_ms)
		sorted.sort()
		var n := sorted.size()
		var sum := 0.0
		for v: float in sorted:
			sum += v
		print("DOMINO_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f n=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n])
		get_tree().quit(0)


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
