class_name Opening
extends CanvasLayer
## The opening (2026-11-17), on a New Table, before Trophe drops onto the crossing: about fourteen seconds,
## letterboxed, with the Owner's subtitles. The camera comes down over the Table at golden hour while the
## Owner introduces its perfect world; a line of code is typed in the middle of the screen,
## `> spawn(TROPHE AS CAT)`, glitches and settles as CAT AS TROPHE ("...wait. That is not what I typed.");
## the camera swoops down to the crossing ("...Oh no.") and the game begins. Any key or click skips it.

const LINES := [
	[0.8, 3.0, "This is my Table."],
	[3.9, 3.4, "Everything on it is exactly where I put it. Every vase. Every brick. Every little person."],
	[7.4, 2.6, "Nothing here ever falls over. Nothing here ever breaks."],
	[10.9, 2.0, "...wait. That is not what I typed."],
	[12.7, 1.6, "...Oh no."],
]
const LENGTH := 14.4
const GLITCH := "#%&@$/<>?!"

var skipped := false

var _t := 0.0
var _cam: Camera3D
var _black: ColorRect
var _top: ColorRect
var _bottom: ColorRect
var _sub: Label
var _code: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 30
	_rng.randomize()
	_black = _rect(Color.BLACK)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top = _rect(Color.BLACK)
	_bottom = _rect(Color.BLACK)
	_sub = _text(UiKit.MONO, 30, Color(0.62, 0.98, 0.92))
	_code = _text(UiKit.MONO, 46, Color(0.95, 0.97, 1.0))
	_layout()


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _text(font_path: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", UiKit.font(font_path, 500))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", c)
	l.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	l.add_theme_constant_override(&"outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	var bar := size.y * 0.11
	_top.position = Vector2.ZERO
	_top.size = Vector2(size.x, bar)
	_bottom.position = Vector2(0.0, size.y - bar)
	_bottom.size = Vector2(size.x, bar)
	_sub.position = Vector2(size.x * 0.1, size.y - bar - 110.0)
	_sub.size = Vector2(size.x * 0.8, 100.0)
	_code.position = Vector2(0.0, size.y * 0.42)
	_code.size = Vector2(size.x, 90.0)


## Plays it with the camera of the title. Returns when it is over or skipped.
func play(cam: Camera3D) -> void:
	_cam = cam
	while _t < LENGTH and not skipped:
		await get_tree().process_frame
		_t += get_process_delta_time()
		_update()
	# Bars and black away quickly.
	var out := 0.0
	while out < 0.5:
		await get_tree().process_frame
		out += get_process_delta_time()
		var k := 1.0 - out / 0.5
		_top.modulate.a = k
		_bottom.modulate.a = k
		_sub.modulate.a = k
		_code.modulate.a = k
		_black.modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _t < 0.8:
		return
	if (event is InputEventKey and (event as InputEventKey).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		skipped = true
		get_viewport().set_input_as_handled()


func _update() -> void:
	_layout()
	_black.modulate.a = clampf(1.0 - _t / 1.2, 0.0, 1.0)
	# The camera: down over the Table, then a swoop to the crossing.
	if _cam != null and is_instance_valid(_cam):
		var k := smoothstep(0.0, 11.5, _t)
		var from := Vector3(420.0, 240.0, 420.0).lerp(Vector3(70.0, 48.0, 80.0), k)
		var look := Vector3(0.0, 0.0, 0.0).lerp(Vector3(0.0, 4.0, 10.0), k)
		if _t > 11.5:
			var s := smoothstep(11.5, LENGTH, _t)
			from = Vector3(70.0, 48.0, 80.0).lerp(Vector3(9.0, 6.0, 34.0), s)
			look = Vector3(0.0, 4.0, 10.0).lerp(Vector3(0.0, 1.0, 14.0), s)
		_cam.look_at_from_position(from, look, Vector3.UP)
	# Subtitles.
	var line := ""
	for l: Array in LINES:
		if _t >= float(l[0]) and _t < float(l[0]) + float(l[1]):
			line = l[2]
	_sub.text = tr(line)
	# The line of code: typed, glitched, settled.
	var typed := "> spawn(TROPHE AS CAT)"
	if _t < 9.2:
		_code.text = ""
	elif _t < 10.4:
		_code.text = typed.left(int((_t - 9.2) / 1.2 * typed.length()))
	elif _t < 11.0:
		var glitch := ""
		for ch in typed:
			glitch += ch if _rng.randf() < 0.55 else GLITCH[_rng.randi_range(0, GLITCH.length() - 1)]
		_code.text = glitch
		_code.position.x = _rng.randf_range(-12.0, 12.0)
		_code.add_theme_color_override(&"font_color", Color(1.0, 0.35, 0.4) if _rng.randf() < 0.5 else Color(0.4, 1.0, 0.95))
	elif _t < 12.6:
		_code.position.x = 0.0
		_code.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.35))
		_code.text = "CAT AS TROPHE"
	else:
		_code.text = ""
