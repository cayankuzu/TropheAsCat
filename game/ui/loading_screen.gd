class_name LoadingScreen
extends CanvasLayer
## What the player sees while the Table is read and built: the (wrong) name of the game, a progress bar,
## the stage under way in the Owner's monospace, the Owner fussing, and a tip. The grid behind it drifts
## slowly, so the screen never looks frozen even when a stage takes a moment.

const QUIPS := [
	"Fluffing the cushions.",
	"Hiding the vases. Higher.",
	"Counting the dominoes. Forty-four. Good.",
	"Polishing the little people.",
	"Locking the cat flap.",
	"Asking the pigeons to behave.",
	"Gluing the tables to the floor. Just in case.",
	"Labelling everything that is NOT a toy.",
]
const TIPS := [
	"Hold Q when a tower starts to go: slow motion, and the sound slows with it.",
	"Things that break in a row count as a chain. Long chains earn a title.",
	"The trees, the pigeons and the dogs are CAT-PROOF. Everything else is not.",
	"Hold the left mouse button with the pee in paw (2): she stands up for it.",
	"A swat sends a vase flying; it breaks where it lands.",
	"Esc pauses, saves and changes the settings.",
]

var _root: Control
var _bar_fill: ColorRect
var _bar_back: ColorRect
var _stage: Label
var _quip: Label
var _grid: Control
var _target := 0.0
var _shown := 0.0
var _quip_left := 0.0
var _rng := RandomNumberGenerator.new()


class Grid extends Control:
	var drift := 0.0

	func _draw() -> void:
		var step := 48.0
		var c := Color(0.55, 0.95, 0.9, 0.05)
		var off := fmod(drift, step)
		var x := -step + off
		while x < size.x + step:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), c, 1.0)
			x += step
		var y := -step + off * 0.5
		while y < size.y + step:
			draw_line(Vector2(0.0, y), Vector2(size.x, y), c, 1.0)
			y += step


func _init() -> void:
	layer = 100
	_rng.randomize()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = UiKit.NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_grid = Grid.new()
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_grid)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	center.add_child(column)
	var title := UiKit.label("TROPHE AS CAT", 84, UiKit.FREDOKA, 600)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var bar_row := CenterContainer.new()
	column.add_child(bar_row)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1.0, 1.0, 1.0, 0.08)
	_bar_back.custom_minimum_size = Vector2(560, 6)
	bar_row.add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UiKit.TEAL
	_bar_fill.size = Vector2(0, 6)
	_bar_back.add_child(_bar_fill)
	_stage = UiKit.owner_label("waking up the Table", 20)
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_stage)
	_quip = UiKit.label("", 18, UiKit.MONO, 400, Color(1, 1, 1, 0.45))
	_quip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_quip)

	var tip := UiKit.label(TIPS[_rng.randi() % TIPS.size()], 20, UiKit.NUNITO, 600, Color(1, 1, 1, 0.55))
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tip.offset_top = -90.0
	tip.offset_bottom = -50.0
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(tip)


## Share done (0..1) and what is being built.
func set_progress(fraction: float, what: String) -> void:
	_target = maxf(_target, clampf(fraction, 0.0, 1.0))
	_stage.text = "> " + tr(what)


func progress() -> float:
	return _shown


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, delta * 1.5)
	_bar_fill.size = Vector2(_bar_back.size.x * _shown, _bar_back.size.y)
	_grid.drift += delta * 14.0
	_grid.queue_redraw()
	_quip_left -= delta
	if _quip_left <= 0.0:
		_quip_left = 2.4
		_quip.text = "> " + tr(String(QUIPS[_rng.randi() % QUIPS.size()]))


## Fades away and frees itself.
func fade_out(seconds: float = 0.7) -> void:
	_target = 1.0
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, seconds)
	await t.finished
	queue_free()
