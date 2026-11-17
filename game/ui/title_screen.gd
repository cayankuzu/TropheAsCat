class_name TitleScreen
extends CanvasLayer
## The title over a slow flight round the city: "TROPHE AS CAT" tears and glitches into "CAT AS TROPHE"
## (clean slices and offsets with a teal ghost, never green rain), "Nothing is off the table." fades in,
## then the menu: Continue (the newest save), New Table, Load, Settings, Quit. Mouse and keyboard work
## the same: arrows and Enter, or point and click; Esc goes back from a sub-page.

signal new_game
signal load_game(slot: int)
signal quit_game

const HOLD_SECONDS := 1.3
const GLITCH_SECONDS := 1.15

var title: GlitchTitle
var ready_for_input := false

var _root: Control
var _subtitle: Label
var _menu: VBoxContainer
var _page := ""


## The name, cut in horizontal bands. Each band shows a slice of the old or the new name and can slide
## sideways; a teal copy behind it splits the colour while the glitch runs.
class GlitchTitle extends Control:
	const BANDS := 10
	var from_text := "TROPHE AS CAT"
	var to_text := "CAT AS TROPHE"
	var glitch_t := -1.0
	var done := false
	var duration := 1.15
	var _bands: Array[Control] = []
	var _from: Array[Label] = []
	var _to: Array[Label] = []
	var _ghost: Array[Label] = []

	func build(area: Vector2, font_size: int) -> void:
		custom_minimum_size = area
		size = area
		var bh := area.y / BANDS
		for i in BANDS:
			var band := Control.new()
			band.clip_contents = true
			band.position = Vector2(0.0, i * bh)
			band.size = Vector2(area.x, bh + 1.0)
			band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(band)
			_bands.append(band)
			for kind in 3:
				var text := to_text if kind == 2 else from_text
				var col := Color(0.55, 0.95, 0.9, 0.7) if kind == 0 else UiKit.CREAM
				var l := UiKit.label(text, font_size, UiKit.FREDOKA, 600, col)
				l.size = area
				l.position = Vector2(0.0, -i * bh)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				band.add_child(l)
				if kind == 0:
					l.visible = false
					_ghost.append(l)
				elif kind == 1:
					_from.append(l)
				else:
					l.visible = false
					_to.append(l)

	func start() -> void:
		glitch_t = 0.0
		Audio.play_ui(&"glitch", -4.0)

	func _process(delta: float) -> void:
		if glitch_t < 0.0 or done:
			return
		glitch_t += delta
		var k := clampf(glitch_t / duration, 0.0, 1.0)
		for i in BANDS:
			var swapped := randf() < k * 1.3
			_from[i].visible = not swapped
			_to[i].visible = swapped
			var jitter := (1.0 - k) * 80.0
			_bands[i].position.x = randf_range(-jitter, jitter) if randf() < 0.5 else 0.0
			_ghost[i].visible = randf() < 0.45 * (1.0 - k)
			_ghost[i].text = to_text if swapped else from_text
			_ghost[i].position.x = randf_range(4.0, 12.0)
		if k >= 1.0:
			done = true
			for i in BANDS:
				_from[i].visible = false
				_to[i].visible = true
				_ghost[i].visible = false
				_bands[i].position.x = 0.0
			Audio.play_ui(&"ui_unlock", -6.0)


func _init() -> void:
	layer = 60
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# A soft vignette keeps the white letters readable over a bright sky.
	var vignette := TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.45)
	g.fill_to = Vector2(1.1, 1.1)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.03, 0.05, 0.05))
	grad.set_color(1, Color(0.02, 0.03, 0.05, 0.75))
	g.gradient = grad
	vignette.texture = g
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vignette)

	title = GlitchTitle.new()
	title.duration = GLITCH_SECONDS
	title.build(Vector2(1500.0, 190.0), 150)
	# Explicit offsets: a preset computed before the control is in the tree sees no size.
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -750.0
	title.offset_right = 750.0
	title.offset_top = 150.0
	title.offset_bottom = 340.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(title)
	_subtitle = UiKit.label("Nothing is off the table.", 34, UiKit.NUNITO, 600)
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_subtitle.offset_left = -500.0
	_subtitle.offset_right = 500.0
	_subtitle.offset_top = 350.0
	_subtitle.offset_bottom = 400.0
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.modulate.a = 0.0
	_root.add_child(_subtitle)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 330.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override(&"separation", 12)
	_menu.custom_minimum_size = Vector2(560, 0)
	_menu.modulate.a = 0.0
	center.add_child(_menu)
	var hint := UiKit.label("Mouse, or arrows and Enter", 18, UiKit.NUNITO, 600, Color(1, 1, 1, 0.45))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -60.0
	hint.offset_bottom = -28.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(hint)
	if Game.lite:
		var demo := UiKit.label("BROWSER DEMO  -  a lighter city whose ground cannot be dug. The full game: download it on itch.io.", 19, UiKit.NUNITO, 700, Color(1.0, 0.86, 0.35))
		demo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		demo.offset_top = 22.0
		demo.offset_bottom = 56.0
		demo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_root.add_child(demo)


## The sequence: the wrong name, the glitch, the right name, the line, the menu.
func play() -> void:
	title.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(title, "modulate:a", 1.0, 0.8)
	await get_tree().create_timer(HOLD_SECONDS).timeout
	title.start()
	await get_tree().create_timer(GLITCH_SECONDS + 0.2).timeout
	var t2 := create_tween()
	t2.tween_property(_subtitle, "modulate:a", 1.0, 0.8)
	_show_main()
	var t3 := create_tween()
	t3.tween_property(_menu, "modulate:a", 1.0, 0.6)
	ready_for_input = true


## Fades away before play starts.
func close() -> void:
	ready_for_input = false
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.5)
	await t.finished
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if ready_for_input and _page != "main" and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_show_main()


func _show_main() -> void:
	_page = "main"
	_clear()
	var first: Button = null
	var latest := SaveGame.latest()
	if latest >= 0:
		var info := SaveGame.info(latest)
		first = _button(tr("Continue   -   %.2f %% cleared") % float(info.get("cleared", 0.0)), func() -> void: load_game.emit(latest))
	var fresh := _button("New Table", func() -> void: new_game.emit())
	if first == null:
		first = fresh
	var any := false
	for slot in SaveGame.SLOT_COUNT:
		any = any or SaveGame.exists(slot)
	var load_b := _button("Load", _show_load)
	load_b.disabled = not any
	_button("Settings", _show_settings)
	if not OS.has_feature("web"):
		_button("Quit", func() -> void: quit_game.emit())
	first.grab_focus()


func _show_load() -> void:
	_page = "load"
	_clear()
	var first: Button = null
	for slot in SaveGame.SLOT_COUNT:
		var b := _button(SaveGame.describe(slot), func() -> void: load_game.emit(slot))
		b.add_theme_font_size_override(&"font_size", 22)
		if not SaveGame.exists(slot):
			b.disabled = true
		elif first == null:
			first = b
	var back := _button("Back", _show_main)
	(first if first != null else back).grab_focus()


func _show_settings() -> void:
	_page = "settings"
	_clear()
	var panel := SettingsPanel.new()
	_menu.add_child(panel)
	panel.setup(null)
	panel.closed.connect(_show_main)
	panel.focus_first()


func _button(text: String, action: Callable) -> Button:
	var b := UiKit.button(text, 30)
	b.pressed.connect(action)
	_menu.add_child(b)
	return b


func _clear() -> void:
	for child in _menu.get_children():
		_menu.remove_child(child)
		child.queue_free()
