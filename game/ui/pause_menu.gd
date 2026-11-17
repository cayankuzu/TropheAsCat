class_name PauseMenu
extends CanvasLayer
## Esc pauses the Table: resume, save to a slot, load a game, settings, quit to the title or to the
## desktop. The whole tree stops (get_tree().paused); this layer keeps running. Keyboard and mouse both
## work: arrows and Enter, or point and click; Esc goes back one step and resumes from the top.

const BOOT_SCENE := "res://game/boot.tscn"
const OWNER_LINES := [
	"The Table is holding its breath.",
	"Take your time. The rubble is not going anywhere.",
	"A pause. Thank you. I needed that.",
	"While you are here: the vases miss you. From a distance.",
]

var open := false

var _main: Node
var _dim: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer
var _owner: Label
var _rng := RandomNumberGenerator.new()
var _page := ""


func setup(main: Node) -> void:
	_main = main
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.04, 0.06, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var sb := UiKit.box(Color(0.06, 0.08, 0.12, 0.92), 24, Color(0.55, 0.95, 0.9, 0.35), 2)
	sb.set_content_margin_all(34.0)
	_panel.add_theme_stylebox_override(&"panel", sb)
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	_panel.add_child(column)
	column.add_child(UiKit.label("PAUSED", 46, UiKit.FREDOKA, 600))
	_owner = UiKit.owner_label("", 18)
	column.add_child(_owner)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 10)
	_body.custom_minimum_size = Vector2(620, 0)
	column.add_child(_body)
	visible = false


func _input(event: InputEvent) -> void:
	if _main == null or not bool(_main.get("playing")):
		return
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if not open:
			show_menu()
		elif _page != "main":
			_show_main()
		else:
			resume()


func show_menu() -> void:
	if Timeline.is_rewinding():
		Timeline.end_rewind()
	open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_owner.text = "> " + tr(String(OWNER_LINES[_rng.randi() % OWNER_LINES.size()]))
	_show_main()


func resume() -> void:
	open = false
	visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Saves into a slot from the menu (also used by tests).
func save_to(slot: int) -> bool:
	var ok: bool = _main.call(&"save_game", slot)
	_owner.text = "> " + tr("Saved. I will remember this. All of it." if ok else "I could not write that down. Odd.")
	if _page == "save":
		_show_slots("save")
	return ok


## Builds the Table again and puts the game of a slot back (quit to the title when slot is -1).
func load_from(slot: int) -> void:
	Boot.pending_slot = slot
	get_tree().paused = false
	get_tree().change_scene_to_file(BOOT_SCENE)


func _show_main() -> void:
	_page = "main"
	_clear()
	var first := _button("Resume", resume)
	_button("Save game", func() -> void: _show_slots("save"))
	_button("Load game", func() -> void: _show_slots("load"))
	_button("Catnip shop", _show_shop)
	_button("Achievements", _show_achievements)
	_button("Settings", _show_settings)
	_button("Quit to title", func() -> void:
		_main.call(&"save_game", SaveGame.AUTOSAVE)
		load_from(-1))
	if not OS.has_feature("web"):   # a browser tab cannot be quit from inside
		_button("Quit to desktop", func() -> void:
			_main.call(&"save_game", SaveGame.AUTOSAVE)
			get_tree().quit())
	first.grab_focus()


func _show_slots(mode: String) -> void:
	_page = mode
	_clear()
	_body.add_child(UiKit.label("Save into" if mode == "save" else "Load", 26, UiKit.FREDOKA, 600))
	var first: Button = null
	for slot in SaveGame.SLOT_COUNT:
		if mode == "save" and slot == SaveGame.AUTOSAVE:
			continue
		var b := _button(SaveGame.describe(slot), func() -> void:
			if mode == "save":
				save_to(slot)
			else:
				load_from(slot))
		b.add_theme_font_size_override(&"font_size", 22)
		if mode == "load" and not SaveGame.exists(slot):
			b.disabled = true
		elif first == null:
			first = b
	var back := _button("Back", _show_main)
	(first if first != null else back).grab_focus()


func _show_settings() -> void:
	_page = "settings"
	_clear()
	var panel := SettingsPanel.new()
	_body.add_child(panel)
	panel.setup(_main)
	panel.closed.connect(_show_main)
	panel.focus_first()


## The catnip shop: what the jobs paid for, one button an item.
func _show_shop() -> void:
	_page = "shop"
	_clear()
	var jobs := _main.get("jobs") as Jobs
	if jobs == null:
		_show_main()
		return
	_body.add_child(UiKit.label(tr("CATNIP SHOP") + "  -  " + tr("%d catnip") % jobs.catnip, 26, UiKit.FREDOKA, 600))
	var first: Button = null
	for item: Dictionary in Jobs.SHOP:
		var have := jobs.owns(item)
		var price := tr("OWNED") if have else tr("%d catnip") % int(item["cost"])
		var b := _button("%s  -  %s  -  %s" % [tr(item["title"]), tr(item["desc"]), price], func() -> void:
			if jobs.buy(item["id"]):
				Audio.play_ui(&"owner_chime", -4.0)
				_show_shop())
		b.add_theme_font_size_override(&"font_size", 17)
		b.disabled = not jobs.can_buy(item)
		if first == null and not b.disabled:
			first = b
	var back := _button("Back", _show_main)
	(first if first != null else back).grab_focus()


## Every achievement: the earned ones in gold, the others with how far along they are.
func _show_achievements() -> void:
	_page = "achievements"
	_clear()
	var ach := _main.get("achievements") as Achievements
	if ach == null:
		_show_main()
		return
	_body.add_child(UiKit.label(tr("ACHIEVEMENTS") + "  -  %d / %d" % [ach.earned.size(), Achievements.LIST.size()], 26, UiKit.FREDOKA, 600))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 380.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_body.add_child(scroll)
	for a: Dictionary in Achievements.LIST:
		var got := ach.earned.has(a["id"])
		var p := ach.progress(a)
		var line := ("+ " if got else "- ") + tr(a["title"]) + "  -  " + tr(a["desc"])
		if not got and p.y > 1.0:
			line += "  (%d / %d)" % [int(p.x), int(p.y)]
		list.add_child(UiKit.label(line, 17, UiKit.NUNITO, 600, Color(1.0, 0.86, 0.35) if got else Color(1.0, 1.0, 1.0, 0.72)))
	_button("Back", _show_main).grab_focus()


func _button(text: String, action: Callable) -> Button:
	var b := UiKit.button(text, 26)
	b.pressed.connect(action)
	_body.add_child(b)
	return b


func _clear() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
