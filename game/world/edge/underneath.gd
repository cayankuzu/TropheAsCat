class_name Underneath
extends Node
## Falling off the Table (docs/DESIGN.md section 4, "the edge"). When Trophe goes over the rim she does not
## simply reappear: she drifts down past the cut side of the slab, under its glowing underside, along the
## curtain of the Owner's code, at a calm terminal speed and turning slowly; streaks of light rush past;
## the Owner speaks; then a soft flash and she drops back onto the Table from the sky. About five seconds,
## and any key or click skips it.
##
## The cat's own void rule calls `void_handler` instead of its plain re-drop while this node is set up.

const FALL_SECONDS := 5.0
const SKIP_AFTER := 0.8
const TERMINAL := 22.0
const PUSH := 36.0           ## m/s away from the slab at first (slowing to 8), so she sees it whole
const FIRST := ["Please do not fall off the Table.", "...Again."]
const LINES := [
	"Gravity is not a toy, Trophe.",
	"You fell off my Table. I will put you back. Gently.",
	"There is nothing down there. I checked. Twice.",
	"Off the Table. Of course. Everything goes off the Table with you.",
]

var falling := false
var falls := 0
## Seconds into the current fall.
var t := 0.0

var _main: Node
var _cat: CatPlayer
var _out := Vector3.ZERO
var _streak_left := 0.0
var _flash: ColorRect
var _layer: CanvasLayer
var _rng := RandomNumberGenerator.new()


func setup(main: Node, cat: CatPlayer) -> void:
	_main = main
	_cat = cat
	_rng.randomize()
	cat.void_handler = _on_void
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 1.0, 0.97, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_flash)


func _physics_process(delta: float) -> void:
	if _cat == null or not is_instance_valid(_cat):
		return
	var p := _cat.global_position
	if not falling:
		# Over the rim and below its line: she is off the Table.
		if (absf(p.x) > TableEdge.HALF + 1.0 or absf(p.z) > TableEdge.HALF + 1.0) and p.y < TableEdge.RIM_Y + 20.0 and not _cat.is_on_floor():
			_start()
		return
	t += delta
	# A calm drift: a capped fall, carried away from the slab (her air control would brake a push, and
	# there is nothing out here to collide with).
	var v := _cat.velocity
	v.y = maxf(v.y, -TERMINAL)
	_cat.velocity = v
	_cat.global_position += _out * lerpf(PUSH, 8.0, clampf(t / FALL_SECONDS, 0.0, 1.0)) * delta * clampf(t / 0.5, 0.0, 1.0)
	# The camera looks back at the Table: at its cut side first, then up at its underside as she drops
	# below it.
	if _cat.camera != null:
		_cat.camera.yaw = lerp_angle(_cat.camera.yaw, atan2(_out.x, _out.z), minf(delta * 4.0, 1.0))
		_cat.camera.pitch = lerpf(_cat.camera.pitch, lerpf(-0.05, 0.3, clampf(t / FALL_SECONDS, 0.0, 1.0)), minf(delta * 3.0, 1.0))
	_streaks(delta)
	if t >= FALL_SECONDS:
		_finish()


func _process(delta: float) -> void:
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 1.6, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not falling or t < SKIP_AFTER:
		return
	var skip := (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


## The cat's void rule (below the Table, or far out): the fall plays if it is not already playing.
func _on_void() -> void:
	if not falling:
		_start()


func _start() -> void:
	falling = true
	t = 0.0
	falls += 1
	var p := _cat.global_position
	_out = Vector3(signf(p.x) if absf(p.x) >= absf(p.z) else 0.0, 0.0, signf(p.z) if absf(p.z) > absf(p.x) else 0.0)
	if _out == Vector3.ZERO:
		_out = Vector3(p.x, 0.0, p.z).normalized() if Vector3(p.x, 0.0, p.z).length_squared() > 1.0 else Vector3.FORWARD
	var hud: MiniHud = (_main.get("hud") as MiniHud) if _main != null else null
	if hud != null:
		if falls == 1:
			hud.say(FIRST[0], 2.2, true)
			get_tree().create_timer(1.7, false).timeout.connect(func() -> void:
				if is_instance_valid(hud):
					hud.say(FIRST[1], 2.5))
		else:
			hud.say(LINES[_rng.randi() % LINES.size()], 3.5, true)
	Audio.play_ui(&"whoosh", -6.0)


func _finish() -> void:
	falling = false
	_flash.color.a = 0.85
	_cat.drop_from_sky()
	Audio.play_ui(&"ui_unlock", -8.0)


## Streaks of light rushing up past her: the fall reads as speed even in an empty void.
func _streaks(delta: float) -> void:
	var fx := WorldFX.instance
	if fx == null:
		return
	_streak_left -= delta
	while _streak_left <= 0.0:
		_streak_left += 0.02
		var at := _cat.global_position + Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-14.0, -4.0), _rng.randf_range(-9.0, 9.0))
		fx.sparks.emit(at, Vector3(0.0, 46.0, 0.0), Color(0.6, 1.0, 0.95, 0.5), 0.45, 0.05, 0.02)
