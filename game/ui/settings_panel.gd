class_name SettingsPanel
extends VBoxContainer
## The settings shared by the title and the pause menu (Settings): mouse sensitivity, three volumes, the
## graphics preset, full screen and the sandbox switch. Every change is applied and saved at once.
## Mouse and keyboard both work: arrows move between the rows and change a slider, Enter toggles.

signal closed

var first: Control
var _main: Node = null


func _init() -> void:
	add_theme_constant_override(&"separation", 10)
	alignment = BoxContainer.ALIGNMENT_CENTER


## main: the running main scene, or null on the title (then the graphics preset waits for the world).
func setup(main: Node) -> void:
	_main = main
	for child in get_children():
		child.queue_free()
	add_child(UiKit.label("SETTINGS", 30, UiKit.FREDOKA, 600))
	first = _slider("Mouse sensitivity", 0.25, 2.5, Settings.mouse, func(v: float) -> void:
		Settings.mouse = v
		if Game.player is CatPlayer:
			Settings.apply_cat(Game.player as CatPlayer))
	_slider("Master volume", 0.0, 1.0, Settings.master, func(v: float) -> void:
		Settings.master = v
		Settings.apply_audio())
	_slider("Music", 0.0, 1.0, Settings.music, func(v: float) -> void:
		Settings.music = v
		Settings.apply_audio())
	_slider("Effects", 0.0, 1.0, Settings.effects, func(v: float) -> void:
		Settings.effects = v
		Settings.apply_audio())
	var row := _row("Graphics")
	var pick := OptionButton.new()
	for q: String in ["Low", "Medium", "High"]:
		pick.add_item(q)
	pick.select(Settings.quality)
	pick.custom_minimum_size = Vector2(240, 44)
	pick.add_theme_font_override(&"font", UiKit.font(UiKit.NUNITO, 700))
	pick.add_theme_font_size_override(&"font_size", 22)
	pick.item_selected.connect(func(i: int) -> void:
		Settings.quality = i
		_changed()
		var look: WorldLook = (_main.get("look") as WorldLook) if _main != null else null
		if look != null:
			look.set_quality(i))
	row.add_child(pick)
	var lang_row := _row("Language")
	var lang := OptionButton.new()
	for n: String in Lang.NAMES:
		lang.add_item(n)
	lang.select(maxi(Lang.LANGUAGES.find(Lang.code()), 0))
	lang.custom_minimum_size = Vector2(240, 44)
	lang.add_theme_font_override(&"font", UiKit.font(UiKit.NUNITO, 700))
	lang.add_theme_font_size_override(&"font_size", 22)
	lang.item_selected.connect(func(i: int) -> void:
		Settings.language = Lang.LANGUAGES[i]
		Lang.setup(Settings.language)
		_changed())
	lang_row.add_child(lang)
	_toggle("Full screen", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply_window())
	_toggle("All tools (sandbox)", Settings.sandbox, func(on: bool) -> void:
		Settings.sandbox = on
		Progress.sandbox_all_tools = on)
	var back := UiKit.button("Back", 24)
	back.pressed.connect(func() -> void: closed.emit())
	add_child(back)


func focus_first() -> void:
	if first != null:
		first.grab_focus()


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	var l := UiKit.label(text, 22)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	add_child(row)
	return row


func _slider(text: String, lo: float, hi: float, value: float, apply: Callable) -> HSlider:
	var row := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 40.0
	s.value = value
	s.custom_minimum_size = Vector2(240, 36)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		_changed())
	row.add_child(s)
	return s


func _toggle(text: String, on: bool, apply: Callable) -> CheckButton:
	var row := _row(text)
	var c := CheckButton.new()
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(v: bool) -> void:
		apply.call(v)
		_changed())
	row.add_child(c)
	return c


func _changed() -> void:
	Settings.save_settings()
