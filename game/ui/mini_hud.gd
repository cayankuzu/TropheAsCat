class_name MiniHud
extends CanvasLayer
## The HUD next to GameHud: a crosshair, TABLE CLEARED % as a gold ring gauge at the top, the Owner's line
## and the new tool when a milestone is reached, the tools as icon slots (keys 1-5, the held one gold-rimmed
## with its name) and a controls line that fades after a few seconds.

const FONT_PATH := "res://assets/fonts/Nunito.ttf"
const OWNER_FONT_PATH := "res://assets/fonts/JetBrainsMono.ttf"
const HINT := "LMB use    RMB aim    1-5 / wheel tools    E grab    Space jump    Shift sprint    F car    Q slow motion    M meow"
const HINT_SECONDS := 16.0
const TOAST_SECONDS := 7.0
const DIM := Color(1.0, 1.0, 1.0, 0.5)
const LIT := Color(1.0, 0.93, 0.62, 1.0)
const OWNER_TEAL := Color(0.55, 0.95, 0.9)

var _cat: CatPlayer = null
var _strip: HBoxContainer
var _hint: Label
var _hint_left := HINT_SECONDS
var _font: Font = null
var _scale := 1.0

var _cleared: Label
var _ring: ClearedRing
var _owner_line: Label
var _new_tool: Label
var _toast_left := 0.0
var _shown_percent := 0.0
var _target_percent := 0.0
var _chain: Label
var _chain_title: Label
var _chain_box: VBoxContainer
var _chain_fade := 0.0
var _chain_punch := 0.0
# The Owner's line: typed out, then faded; at most two more wait their turn.
var _say_text := ""
var _say_shown := 0.0
var _say_left := 0.0
var _say_queue: Array[Array] = []
var _flash: Label
var _flash_left := 0.0


class Crosshair extends Control:
	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, 7.0, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.35), 3.5, true)
		draw_arc(c, 7.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.85), 1.5, true)
		draw_circle(c, 1.6, Color(1.0, 1.0, 1.0, 0.9))


## TABLE CLEARED as a ring: a dark disc, a faint track and a gold arc from twelve o'clock, the number inside.
class ClearedRing extends Control:
	var percent := 0.0
	var font: Font
	var ui := 1.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 5.0 * ui
		draw_circle(c, r + 4.0 * ui, Color(0.03, 0.04, 0.07, 0.6))
		draw_arc(c, r, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.14), 4.5 * ui, true)
		var k := clampf(percent / 100.0, 0.0, 1.0)
		if k > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * maxf(k, 0.012), 72, Color(1.0, 0.86, 0.35), 4.5 * ui, true)
		if font != null:
			var text := ("%.2f%%" if percent < 10.0 else "%.1f%%") % percent
			var fs := int(15.0 * ui)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4.0 * ui), Color(0.0, 0.0, 0.0, 0.6))
			draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.82))


## One tool on the belt: a dark rounded slot with a drawn icon and its key; the held one is gold-rimmed,
## bigger, and has its name under it.
class ToolSlot extends Control:
	static var _box: StyleBoxFlat = null
	static var _box_held: StyleBoxFlat = null
	var key := 1
	var title := ""
	var icon := &""
	var held := false
	var font: Font
	var ui := 1.0

	func _draw() -> void:
		if _box == null:
			_box = StyleBoxFlat.new()
			_box.bg_color = Color(0.03, 0.04, 0.07, 0.62)
			_box.set_corner_radius_all(10)
			_box.border_color = Color(1.0, 1.0, 1.0, 0.16)
			_box.set_border_width_all(2)
			_box_held = _box.duplicate() as StyleBoxFlat
			_box_held.bg_color = Color(0.1, 0.08, 0.03, 0.75)
			_box_held.border_color = Color(1.0, 0.86, 0.35, 0.95)
			_box_held.set_border_width_all(3)
		var side := size.x
		draw_style_box(_box_held if held else _box, Rect2(Vector2.ZERO, Vector2(side, side)))
		_draw_icon(Rect2(Vector2(side * 0.16, side * 0.16), Vector2(side * 0.68, side * 0.68)))
		if font != null:
			var fs := int(12.0 * ui)
			draw_string_outline(font, Vector2(side * 0.1, fs + 2.0 * ui), str(key), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(3.0 * ui), Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(side * 0.1, fs + 2.0 * ui), str(key), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))
			if held:
				var ts := int(14.0 * ui)
				var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
				var at := Vector2(side * 0.5 - w * 0.5, side + ts + 4.0 * ui)
				draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, int(4.0 * ui), Color(0, 0, 0, 0.7))
				draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(1.0, 0.93, 0.62))

	func _draw_icon(r: Rect2) -> void:
		var p := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
		var u := r.size.x
		var alpha := 1.0 if held else 0.7
		match icon:
			&"paw":
				var col := Color(1.0, 0.8, 0.78, alpha)
				draw_circle(p.call(0.5, 0.66), u * 0.19, col)
				for t: Vector2 in [Vector2(0.24, 0.42), Vector2(0.4, 0.26), Vector2(0.6, 0.26), Vector2(0.76, 0.42)]:
					draw_circle(p.call(t.x, t.y), u * 0.085, col)
			&"pee", &"acid":
				var col := Color(0.98, 0.85, 0.28, alpha) if icon == &"pee" else Color(0.55, 1.0, 0.35, alpha)
				draw_circle(p.call(0.5, 0.64), u * 0.24, col)
				draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.08), p.call(0.72, 0.56), p.call(0.28, 0.56)]), col)
				draw_circle(p.call(0.42, 0.62), u * 0.06, Color(1, 1, 1, 0.55 * alpha))
			&"laser":
				var red := Color(1.0, 0.18, 0.15, alpha)
				draw_arc(p.call(0.5, 0.5), u * 0.3, 0.0, TAU, 40, Color(red, 0.45 * alpha), u * 0.05, true)
				draw_circle(p.call(0.5, 0.5), u * 0.12, red)
				for k in 4:
					var a := TAU * k / 4.0 + PI * 0.25
					var d := Vector2(cos(a), sin(a))
					draw_line(p.call(0.5, 0.5) + d * u * 0.38, p.call(0.5, 0.5) + d * u * 0.5, red, u * 0.05, true)
			&"hat":
				var purple := Color(0.52, 0.32, 0.9, alpha)
				draw_colored_polygon(PackedVector2Array([p.call(0.56, 0.02), p.call(0.78, 0.72), p.call(0.26, 0.72)]), purple)
				draw_rect(Rect2(p.call(0.1, 0.7), Vector2(u * 0.8, u * 0.12)), purple.darkened(0.25))
				draw_circle(p.call(0.5, 0.45), u * 0.07, Color(1.0, 0.86, 0.3, alpha))
			&"hairball":
				var col := Color(0.86, 0.68, 0.62, alpha)
				draw_circle(p.call(0.5, 0.52), u * 0.3, col)
				for k in 3:
					draw_arc(p.call(0.38 + 0.12 * k, 0.5), u * 0.13, PI * 0.1, PI * 1.2, 12, col.darkened(0.35), u * 0.04, true)
			_:
				draw_circle(p.call(0.5, 0.5), u * 0.25, Color(1, 1, 1, alpha))


const TOOL_ICONS := {"Paw": &"paw", "Pee": &"pee", "Acid Pee": &"acid", "Laser Dot": &"laser", "Wizard Hat": &"hat", "Hairball Cannon": &"hairball"}


func _ready() -> void:
	layer = 10
	_font = _load_font(FONT_PATH, 700)
	var cross := Crosshair.new()
	cross.name = "Crosshair"
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.resized.connect(cross.queue_redraw)
	add_child(cross)

	# Top centre: the goal of the game, and what the Owner has to say about it.
	var top := VBoxContainer.new()
	top.name = "Top"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 14.0
	top.offset_bottom = 220.0
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", 4)
	add_child(top)
	_cleared = _label(tr("TABLE CLEARED"), 20)
	_cleared.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_cleared)
	var bar_row := CenterContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bar_row)
	_ring = ClearedRing.new()
	_ring.font = _font
	_ring.custom_minimum_size = Vector2(72.0, 72.0)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(_ring)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 4.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_owner_line = _label("", 17)
	_owner_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_owner_line.modulate = OWNER_TEAL
	var owner_font := _load_font(OWNER_FONT_PATH, 500)
	if owner_font != null:
		_owner_line.add_theme_font_override(&"font", owner_font)
	_owner_line.visible = false
	top.add_child(_owner_line)
	_new_tool = _label("", 24)
	_new_tool.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_new_tool.modulate = LIT
	_new_tool.visible = false
	top.add_child(_new_tool)

	# Right of the crosshair: the chain of things broken in quick succession, and its rank.
	_chain_box = VBoxContainer.new()
	_chain_box.name = "Chain"
	_chain_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_chain_box.offset_left = 90.0
	_chain_box.offset_top = -60.0
	_chain_box.offset_right = 520.0
	_chain_box.offset_bottom = 60.0
	_chain_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_chain_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain_box.modulate.a = 0.0
	add_child(_chain_box)
	_chain = _label("", 40)
	_chain.modulate = LIT
	_chain_box.add_child(_chain)
	_chain_title = _label("", 22)
	_chain_box.add_child(_chain_title)
	Progress.chain_changed.connect(_on_chain)
	Progress.chain_ended.connect(_on_chain_ended)

	# Bottom right: a short note (SAVED, AUTOSAVED).
	_flash = _label("", 18)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_flash.offset_left = -420.0
	_flash.offset_top = -64.0
	_flash.offset_right = -28.0
	_flash.offset_bottom = -26.0
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flash.modulate = OWNER_TEAL
	_flash.visible = false
	add_child(_flash)

	var column := VBoxContainer.new()
	column.name = "Bottom"
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	column.offset_top = -200.0
	column.offset_bottom = -20.0
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_hint = _label(HINT, 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.8)
	column.add_child(_hint)
	_strip = HBoxContainer.new()
	_strip.name = "Tools"
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_constant_override(&"separation", 14)
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_strip)

	Progress.tool_unlocked.connect(_on_tool_unlocked)
	Progress.cleared_changed.connect(_on_cleared_changed)
	Progress.milestone_reached.connect(_on_milestone)
	_target_percent = Progress.cleared_percent()
	_shown_percent = _target_percent
	get_viewport().size_changed.connect(_rescale)
	_rescale()


func setup(cat: CatPlayer) -> void:
	_cat = cat
	cat.belt.tool_changed.connect(func(_slot: int, _tool: CatTool) -> void: _rebuild())
	_rebuild()


func _process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		_hint.modulate.a = 0.8 * clampf(_hint_left / 2.0, 0.0, 1.0)
		if _hint_left <= 0.0:
			_hint.visible = false
	# The number runs up to the real value instead of jumping when a whole block comes down.
	if not is_equal_approx(_shown_percent, _target_percent):
		var step := maxf(absf(_target_percent - _shown_percent) * 3.0, 0.02) * delta
		_shown_percent = move_toward(_shown_percent, _target_percent, step)
		_show_percent()
	if _chain_punch > 0.0:
		_chain_punch = maxf(_chain_punch - delta * 5.0, 0.0)
		_chain.scale = Vector2.ONE * (1.0 + 0.35 * _chain_punch)
	if _chain_fade > 0.0:
		_chain_fade -= delta
		_chain_box.modulate.a = clampf(_chain_fade / 1.2, 0.0, 1.0)
	if _toast_left > 0.0:
		_toast_left -= delta
		_new_tool.modulate.a = clampf(_toast_left / 1.2, 0.0, 1.0)
		if _toast_left <= 0.0:
			_new_tool.visible = false
	if _say_left > 0.0:
		_say_left -= delta
		if _say_shown < _say_text.length():
			_say_shown += delta * 45.0
			_owner_line.text = _say_text.left(int(_say_shown))
		_owner_line.modulate.a = clampf(_say_left, 0.0, 1.0)
		if _say_left <= 0.0:
			_owner_line.visible = false
			if not _say_queue.is_empty():
				var next: Array = _say_queue.pop_front()
				_show_line(next[0], next[1])
	if _flash_left > 0.0:
		_flash_left -= delta
		_flash.modulate.a = clampf(_flash_left, 0.0, 1.0)
		if _flash_left <= 0.0:
			_flash.visible = false


func _show_percent() -> void:
	_cleared.text = tr("TABLE CLEARED")
	_ring.percent = _shown_percent
	_ring.queue_redraw()


func _on_tool_unlocked(_id: StringName) -> void:
	_rebuild.call_deferred()


func _on_cleared_changed(percent: float) -> void:
	_target_percent = percent


func _on_chain_ended(_n: int) -> void:
	_chain_fade = 1.2


func _on_chain(count: int, title: String) -> void:
	if count < 3:
		return   # two things breaking is not a chain yet
	_chain.text = "x%d" % count
	if title != _chain_title.text:
		_chain_title.text = tr(title)
		if title != "":
			Audio.play_ui(&"ui_unlock", -6.0)
	_chain_box.modulate.a = 1.0
	_chain_fade = 0.0
	_chain_punch = 1.0


func _on_milestone(index: int, tool_id: StringName) -> void:
	var m: Dictionary = Progress.MILESTONES[index]
	var slot := ToolKit.slot_of(tool_id)
	_new_tool.text = tr("NEW:  %s%s") % [tr(m["name"]), "   [%d]" % (slot + 1) if slot >= 0 else (tr("   [hold R]") if tool_id == Progress.TOOL_REWIND else "")]
	_new_tool.visible = true
	_new_tool.modulate.a = 1.0
	_toast_left = TOAST_SECONDS
	say(String(m["owner"]), TOAST_SECONDS, true)
	Audio.play_ui(&"ui_unlock")


## The Owner says something: typed out in teal monospace under TABLE CLEARED, gone after `seconds`.
## While a line is showing, a new one waits its turn (two at most) unless it interrupts.
func say(line: String, seconds: float = 5.0, interrupt: bool = false) -> void:
	line = tr(line)
	if _say_left > 0.0 and not interrupt:
		if _say_queue.size() < 2:
			_say_queue.append([line, seconds])
		return
	_show_line(line, seconds)


func is_speaking() -> bool:
	return _say_left > 0.0 or not _say_queue.is_empty()


## A short note in the corner (SAVED).
func flash(text: String, seconds: float = 2.5) -> void:
	_flash.text = tr(text)
	_flash.visible = true
	_flash.modulate.a = 1.0
	_flash_left = seconds


func _show_line(line: String, seconds: float) -> void:
	_say_text = "> " + line
	_say_shown = 0.0
	_say_left = seconds + line.length() / 45.0
	_owner_line.text = ""
	_owner_line.visible = true
	_owner_line.modulate.a = 1.0


## Text is sized for a 720-pixel-high view and grows with the window.
func _rescale() -> void:
	_scale = clampf(get_viewport().get_visible_rect().size.y / 720.0, 0.75, 3.0)
	_hint.add_theme_font_size_override(&"font_size", int(15.0 * _scale))
	_cleared.add_theme_font_size_override(&"font_size", int(15.0 * _scale))
	_owner_line.add_theme_font_size_override(&"font_size", int(16.0 * _scale))
	_new_tool.add_theme_font_size_override(&"font_size", int(23.0 * _scale))
	_flash.add_theme_font_size_override(&"font_size", int(17.0 * _scale))
	_chain.add_theme_font_size_override(&"font_size", int(40.0 * _scale))
	_chain_title.add_theme_font_size_override(&"font_size", int(21.0 * _scale))
	_ring.custom_minimum_size = Vector2(72.0, 72.0) * _scale
	_ring.ui = _scale
	_show_percent.call_deferred()
	_rebuild()


func _rebuild() -> void:
	if _cat == null or not is_instance_valid(_cat) or _strip == null:
		return
	for child in _strip.get_children():
		child.queue_free()
	for slot in ToolBelt.SLOT_COUNT:
		var tool := _cat.belt.slots[slot]
		if tool == null:
			continue
		var held := slot == _cat.belt.current_slot
		var item := ToolSlot.new()
		item.key = slot + 1
		item.title = tr(tool.tool_name)
		item.icon = TOOL_ICONS.get(tool.tool_name, &"")
		item.held = held
		item.font = _font
		item.ui = _scale
		var side := (62.0 if held else 52.0) * _scale
		item.custom_minimum_size = Vector2(side, side + 24.0 * _scale)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_strip.add_child(item)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if _font != null:
		l.add_theme_font_override(&"font", _font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_constant_override(&"outline_size", 6)
	l.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.55))
	return l


static func _load_font(path: String, weight: int) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var base := load(path) as Font
	if base == null:
		return null
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return v
