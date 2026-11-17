class_name Achievements
extends Node
## Achievements (2026-11-17): eighteen goals that count across every game. They are kept in
## user://achievements.cfg, not in the save slots: once earned, always earned. Checked once a second from what
## the other systems already count; a new one gets a gold toast at the top right and the Owner's chime. The
## pause menu lists them all (Achievements page).

signal unlocked(id: StringName)

## Where earned achievements are kept (tests point it somewhere else).
static var path := "user://achievements.cfg"
## stat: what is measured (see _stat); goal -1 = "all there are" (the giants of the city, the jobs it offers).
const LIST := [
	{"id": &"first_crack", "title": "FIRST CRACK", "desc": "Break your first thing", "stat": &"breaks", "goal": 1},
	{"id": &"china_shop", "title": "BULL IN A CHINA SHOP", "desc": "Break 100 fragile things", "stat": &"fragile", "goal": 100},
	{"id": &"porcelain", "title": "PORCELAIN SEASON PASS", "desc": "Shatter 50 of the little people", "stat": &"people", "goal": 50},
	{"id": &"demolition", "title": "DEMOLITION EXPERT", "desc": "Bring down 5 buildings", "stat": &"toppled", "goal": 5},
	{"id": &"five_stars", "title": "ALL THE STARS", "desc": "Reach five chaos stars", "stat": &"stars", "goal": 5},
	{"id": &"viral", "title": "GONE VIRAL", "desc": "Get a million views", "stat": &"views", "goal": 1000000},
	{"id": &"road_rage", "title": "ROAD RAGE", "desc": "Wreck 25 cars", "stat": &"wrecks", "goal": 25},
	{"id": &"learner", "title": "LEARNER DRIVER", "desc": "Drive 5 kilometres", "stat": &"driven", "goal": 5000},
	{"id": &"giants", "title": "THE BIGGER THEY ARE", "desc": "Bring down every giant of the city", "stat": &"giants", "goal": -1},
	{"id": &"yarn", "title": "YARN COLLECTOR", "desc": "Find all thirty balls of golden yarn", "stat": &"yarn", "goal": 30},
	{"id": &"employee", "title": "EMPLOYEE OF THE MONTH", "desc": "Finish every job", "stat": &"jobs", "goal": -1},
	{"id": &"table_flip", "title": "TABLE FLIP", "desc": "Clear a tenth of the Table", "stat": &"cleared", "goal": 10},
	{"id": &"chain", "title": "CHAIN REACTION", "desc": "Break 50 things in one chain", "stat": &"chain", "goal": 50},
	{"id": &"house_call", "title": "HOUSE CALL", "desc": "Break 50 things inside the buildings", "stat": &"inside", "goal": 50},
	{"id": &"tough_crowd", "title": "TOUGH CROWD", "desc": "Get kicked by 10 angry humans", "stat": &"kicks", "goal": 10},
	{"id": &"most_wanted", "title": "MOST WANTED", "desc": "Get reported to the police 10 times", "stat": &"calls", "goal": 10},
	{"id": &"baron", "title": "CATNIP BARON", "desc": "Earn 1,000 catnip", "stat": &"catnip", "goal": 1000},
	{"id": &"shopper", "title": "RETAIL THERAPY", "desc": "Buy something in the catnip shop", "stat": &"bought", "goal": 1},
]

var earned: Array[StringName] = []

var _main: Node
var _check_in := 1.0
var _toppled := 0
var _layer: CanvasLayer
var _toast_head: Label
var _toast_title: Label
var _toast_t := 0.0
var _queue: Array[String] = []


func setup(main: Node) -> void:
	_main = main
	var scene := get_tree().current_scene
	if path == "user://achievements.cfg" and scene != null and scene.scene_file_path.begins_with("res://tests/"):
		path = "user://test_achievements.cfg"   # the test scenes never touch the player's achievements
	_load()
	var sm := Game.structures as StructureManager
	if sm != null:
		sm.building_toppled.connect(func(_bid: int, _storey: int) -> void: _toppled += 1)
	_layer = CanvasLayer.new()
	_layer.layer = 9
	add_child(_layer)
	_toast_head = _label(18, Color(1.0, 0.86, 0.35), 150.0)
	_toast_title = _label(28, Color(1.0, 0.96, 0.86), 174.0)


func _label(size: int, color: Color, top: float) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", UiKit.font(UiKit.FREDOKA, 600))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0.04, 0.05, 0.09, 0.9))
	l.add_theme_constant_override(&"outline_size", 10)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	l.offset_left = -560.0
	l.offset_right = -24.0
	l.offset_top = top
	l.offset_bottom = top + 40.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	_layer.add_child(l)
	return l


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		var a := clampf(_toast_t / 0.8, 0.0, 1.0) * clampf((4.5 - _toast_t) / 0.3, 0.0, 1.0)
		_toast_head.modulate.a = a
		_toast_title.modulate.a = a
	elif not _queue.is_empty():
		_show(_queue.pop_front())
	_check_in -= delta
	if _check_in > 0.0 or _main == null:
		return
	_check_in = 1.0
	for a: Dictionary in LIST:
		if earned.has(a["id"]):
			continue
		var goal := _goal(a)
		if goal > 0.0 and _stat(a["stat"]) >= goal:
			_earn(a)


## Where one stands with an achievement: [value, goal] (the pause menu shows it).
func progress(a: Dictionary) -> Vector2:
	return Vector2(minf(_stat(a["stat"]), maxf(_goal(a), 1.0)), _goal(a))


func _goal(a: Dictionary) -> float:
	if int(a["goal"]) >= 0:
		return float(a["goal"])
	match a["stat"]:
		&"giants":
			var sp := _main.get("set_pieces") as SetPieces
			return float(sp.giants.size()) if sp != null else 0.0
		&"jobs":
			var jobs := _main.get("jobs") as Jobs
			return float(jobs.possible_count()) if jobs != null else 0.0
	return 0.0


func _stat(stat: StringName) -> float:
	var people := _main.get("people") as People
	var jobs := _main.get("jobs") as Jobs
	var dressing := _main.get("dressing") as StreetDressing
	match stat:
		&"breaks":
			return Progress.breaks_total
		&"fragile", &"wrecks", &"inside":
			var n := 0
			if dressing != null:
				for p in dressing.props:
					if not is_instance_valid(p):
						continue
					if stat == &"fragile" and p.fragile and p.is_broken():
						n += 1
					elif stat == &"wrecks" and p.wreck and (p.is_wreck() or p.is_broken()):
						n += 1
					elif stat == &"inside" and p.has_meta(&"inside") and p.is_broken():
						n += 1
			return n
		&"people":
			return people.shattered if people != null else 0.0
		&"toppled":
			return _toppled
		&"stars":
			var chaos := _main.get("chaos") as Chaos
			return chaos.best_stars if chaos != null else 0.0
		&"views":
			return people.views if people != null else 0.0
		&"driven":
			var d := _main.get("driving") as CatDriving
			return d.distance if d != null else 0.0
		&"giants":
			var sp := _main.get("set_pieces") as SetPieces
			return sp.released_count() if sp != null else 0.0
		&"yarn":
			return jobs.yarn_found.size() if jobs != null else 0.0
		&"jobs":
			return jobs.done.size() if jobs != null else 0.0
		&"cleared":
			return Progress.cleared_percent()
		&"chain":
			return Progress.best_chain
		&"kicks":
			return people.kicks if people != null else 0.0
		&"calls":
			return people.calls if people != null else 0.0
		&"catnip":
			return jobs.catnip + jobs.spent if jobs != null else 0.0
		&"bought":
			return jobs.owned.size() if jobs != null else 0.0
	return 0.0


func _earn(a: Dictionary) -> void:
	earned.append(a["id"])
	_save()
	unlocked.emit(a["id"])
	_queue.append(String(a["title"]))


func _show(title: String) -> void:
	_toast_head.text = tr("ACHIEVEMENT UNLOCKED")
	_toast_title.text = tr(title)
	_toast_t = 4.5
	Audio.play_ui(&"owner_chime", -2.0)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for id: Variant in cfg.get_value("achievements", "earned", []):
		var s := StringName(String(id))
		if not earned.has(s):
			earned.append(s)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("achievements", "earned", earned.map(func(s: StringName) -> String: return String(s)))
	cfg.save(path)
