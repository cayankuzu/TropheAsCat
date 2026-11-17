class_name Jobs
extends Node
## Jobs and golden yarn (2026-11-17): what keeps you on the Table. The cats who live under the Table have
## requests (dark ones, politely put). One job at a time waits at a gold marker (a ring and a beam, on the
## radar); walk into it and the job starts with the asker's line; the panel at the top left shows the goal,
## the count and the clock; done, it pays catnip, and every two jobs Trophe levels up (she jumps higher and
## runs faster). Thirty balls of golden yarn are hidden over the map (on roofs, inside houses, in the
## groves, on the containers); each pays catnip too. Saved with the game.

signal job_done(id: StringName)

const JOBS := [
	{"id": &"vases", "from": "Mrs. Pebbles", "title": "NOT THE VASE", "ask": "Knock 12 fragile things off their tables", "line": "Humans keep their whole lives on shelves. Help them let go.", "kind": &"fragile", "goal": 12, "time": 0.0, "pay": 50, "at": Vector3(-128.0, 0.0, -150.0)},
	{"id": &"rush", "from": "Tom (one eye)", "title": "RUSH HOUR", "ask": "Wreck 5 cars in 90 seconds", "line": "They honk at me every morning. Every. Single. Morning.", "kind": &"wrecks", "goal": 5, "time": 90.0, "pay": 80, "at": Vector3(14.0, 0.0, 60.0)},
	{"id": &"joyride", "from": "Biscuit", "title": "JOYRIDE", "ask": "Drive a car for a kilometre", "line": "I always wanted to drive. I have no thumbs. Neither do you. Go.", "kind": &"drive", "goal": 1000, "time": 0.0, "pay": 60, "at": Vector3(-14.0, 0.0, -40.0)},
	{"id": &"people", "from": "Duchess", "title": "PORCELAIN SEASON", "ask": "Shatter 10 of the little people", "line": "They pet without asking. Consent works both ways, darling.", "kind": &"people", "goal": 10, "time": 0.0, "pay": 90, "at": Vector3(64.0, 0.0, 64.0)},
	{"id": &"pumps", "from": "Mr. Whiskers", "title": "GAS PRICES", "ask": "Blow up the pumps of a fuel station", "line": "They stopped selling tuna. Then they stopped selling hope.", "kind": &"pumps", "goal": 4, "time": 0.0, "pay": 120, "at": Vector3(268.0, 0.0, 152.0)},
	{"id": &"stars", "from": "The Boss", "title": "FIVE STAR REVIEW", "ask": "Reach five chaos stars", "line": "The Owner thinks it runs this Table. Leave it a review.", "kind": &"stars", "goal": 5, "time": 0.0, "pay": 150, "at": Vector3(14.0, 0.0, 14.0)},
	{"id": &"wheel", "from": "Noodle", "title": "BIG WHEEL", "ask": "Send the Ferris wheel rolling", "line": "Round and round and nobody ever gets anywhere. Like my nine lives.", "kind": &"wheel", "goal": 1, "time": 0.0, "pay": 150, "at": Vector3(-60.0, 0.0, 300.0)},
	{"id": &"topple", "from": "Madame Claw", "title": "URBAN RENEWAL", "ask": "Bring a whole building down", "line": "That building was blocking my view of the other building.", "kind": &"topple", "goal": 1, "time": 0.0, "pay": 200, "at": Vector3(100.0, 0.0, 100.0)},
	{"id": &"crane", "from": "Socks", "title": "HEAVY LIFTING", "ask": "Knock the tower crane over", "line": "It lifts things all day and never says thank you. Smug.", "kind": &"crane", "goal": 1, "time": 0.0, "pay": 200, "at": Vector3(250.0, 0.0, -300.0)},
	{"id": &"clock", "from": "Old Grey", "title": "CLOCK OUT", "ask": "Topple the clock tower", "line": "It chimes at six in the morning. I am a cat. I do not do six in the morning.", "kind": &"tower", "goal": 1, "time": 0.0, "pay": 200, "at": Vector3(-110.0, 0.0, -100.0)},
]
const YARN_COUNT := 30
const YARN_PAY := 10
const MARKER_RADIUS := 2.4

## State that a saved game hands over before the jobs exist (see SaveGame.apply).
static var pending := {}

var done: Array[StringName] = []
var catnip := 0
var level := 1
var yarn_found := PackedInt32Array()
var current := -1          ## index into JOBS of the job under way, -1 none
var offered := -1          ## index of the job waiting at its marker

var _main: Node
var _cat: CatPlayer
var _base := 0.0
var _left := 0.0
var _count := 0.0
var _poll := 0.0
var _toppled := 0
var _marker: Node3D
var _yarns: Array[Node3D] = []
var _panel: Label
var _banner: Label
var _banner_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(main: Node, cat: CatPlayer) -> void:
	_main = main
	_cat = cat
	_rng.seed = 1977
	var sm := Game.structures as StructureManager
	if sm != null:
		sm.building_toppled.connect(_on_topple)
	_panel = _label(24, HORIZONTAL_ALIGNMENT_LEFT, Control.PRESET_TOP_LEFT, Vector2(28.0, 84.0), Vector2(720.0, 160.0))
	_banner = _label(46, HORIZONTAL_ALIGNMENT_CENTER, Control.PRESET_CENTER_TOP, Vector2(-640.0, 300.0), Vector2(1280.0, 160.0))
	_banner.modulate.a = 0.0
	_place_yarn()
	if not pending.is_empty():
		restore_state(pending)
		pending = {}
	_offer_next()


func _label(size: int, align: HorizontalAlignment, preset: Control.LayoutPreset, at: Vector2, extent: Vector2) -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var l := Label.new()
	l.add_theme_font_override(&"font", UiKit.font(UiKit.FREDOKA, 600))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.82))
	l.add_theme_color_override(&"font_outline_color", Color(0.04, 0.05, 0.1, 0.9))
	l.add_theme_constant_override(&"outline_size", 10)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(preset)
	l.offset_left = at.x
	l.offset_top = at.y
	l.offset_right = at.x + extent.x
	l.offset_bottom = at.y + extent.y
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	return l


func _process(delta: float) -> void:
	if _cat == null or not is_instance_valid(_cat):
		return
	var at := _cat.global_position
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	# The marker of the job on offer: walk into it.
	if current < 0 and offered >= 0 and _marker != null:
		_marker.rotate_y(delta * 1.5)
		if Vector2(at.x - _marker.global_position.x, at.z - _marker.global_position.z).length() < MARKER_RADIUS and absf(at.y - _marker.global_position.y) < 4.0:
			_start(offered)
	# Golden yarn.
	for i in _yarns.size():
		var y := _yarns[i]
		if y == null or not y.visible:
			continue
		y.rotate_y(delta * 2.0)
		if y.global_position.distance_to(at + Vector3.UP * 0.25) < 1.1:
			_find_yarn(i)
	if current >= 0:
		_poll -= delta
		if _poll <= 0.0:
			_poll = 0.5
			_count = _measure(JOBS[current]["kind"]) - _base
		var job: Dictionary = JOBS[current]
		if float(job["time"]) > 0.0:
			_left -= delta
		var goal := float(job["goal"])
		var shown := minf(_count, goal)
		var clock := "" if float(job["time"]) <= 0.0 else "   %d:%02d" % [int(maxf(_left, 0.0) / 60.0), int(maxf(_left, 0.0)) % 60]
		var unit := " m" if job["kind"] == &"drive" else ""
		_panel.text = "%s\n%s  (%d%s / %d%s)%s\n%s" % [tr(job["title"]), tr(job["ask"]), int(shown), unit, int(goal), unit, clock, _status()]
		if _count >= goal:
			_finish(true)
		elif float(job["time"]) > 0.0 and _left <= 0.0:
			_finish(false)
	else:
		var next := "" if offered < 0 else "\n" + tr("Next: %s (gold marker on the radar)") % tr(JOBS[offered]["title"])
		_panel.text = _status() + next


## How far the world is along the kind of a job (a running total; a job counts from where it started).
func _measure(kind: StringName) -> float:
	var dressing: StreetDressing = _main.get("dressing")
	match kind:
		&"fragile":
			var n := 0
			for p in dressing.props:
				if is_instance_valid(p) and p.fragile and p.is_broken():
					n += 1
			return n
		&"wrecks":
			var n := 0
			for p in dressing.props:
				if is_instance_valid(p) and p.wreck and (p.is_wreck() or p.is_broken()):
					n += 1
			return n
		&"pumps":
			var n := 0
			for p in dressing.props:
				if is_instance_valid(p) and p.prop_id == &"fuel_pump" and p.is_broken():
					n += 1
			return n
		&"drive":
			var d: CatDriving = _main.get("driving")
			return d.distance if d != null else 0.0
		&"people":
			var people: People = _main.get("people")
			return people.shattered if people != null else 0
		&"stars":
			var chaos: Chaos = _main.get("chaos")
			return chaos.stars if chaos != null else 0
		&"topple":
			return _toppled
		&"wheel", &"crane", &"tower":
			var sp: SetPieces = _main.get("set_pieces")
			if sp == null:
				return 0
			var g: Giant = sp.wheel if kind == &"wheel" else (sp.crane if kind == &"crane" else sp.tower)
			return 1.0 if g != null and g.released else 0.0
	return 0.0


func _on_topple(_bid: int, _storey: int) -> void:
	_toppled += 1


## Whether the city has what a job needs (the small browser demo has no fuel station and no crane yard).
func _possible(job: Dictionary) -> bool:
	var city := _main.get("city") as CityLayout if _main != null else null
	var sp := _main.get("set_pieces") as SetPieces if _main != null else null
	match job["kind"]:
		&"pumps":
			return city == null or not city.forecourts.is_empty()
		&"crane":
			return sp == null or sp.crane != null
		&"tower":
			return sp == null or sp.tower != null
	return true


func _offer_next() -> void:
	offered = -1
	for i in JOBS.size():
		if not done.has(JOBS[i]["id"]) and _possible(JOBS[i]):
			offered = i
			break
	if _marker != null:
		_marker.queue_free()
		_marker = null
	if offered < 0:
		return
	var at: Vector3 = JOBS[offered]["at"]
	_marker = Node3D.new()
	_marker.name = "JobMarker"
	add_child(_marker)
	_marker.global_position = Vector3(at.x, _ground(at.x, at.z) + 0.05, at.z)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.25)
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.75, 0.2)
	gold.emission_energy_multiplier = 2.5
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.7
	torus.outer_radius = 2.0
	ring.mesh = torus
	ring.material_override = gold
	ring.position.y = 0.15
	_marker.add_child(ring)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.9
	cyl.height = 40.0
	beam.mesh = cyl
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.82, 0.3, 0.16)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = glow
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 20.0
	_marker.add_child(beam)


func _start(i: int) -> void:
	current = i
	var job: Dictionary = JOBS[i]
	_base = _measure(job["kind"])
	_count = 0.0
	_left = float(job["time"])
	if _marker != null:
		_marker.queue_free()
		_marker = null
	_show_banner("%s\n%s: \"%s\"" % [tr(job["title"]), tr(job["from"]), tr(job["line"])], 6.0)
	Audio.play_ui(&"owner_chime", -2.0)


func _finish(won: bool) -> void:
	var job: Dictionary = JOBS[current]
	current = -1
	if won:
		done.append(job["id"])
		catnip += int(job["pay"])
		var line := tr("JOB DONE   +%d catnip") % int(job["pay"])
		if done.size() % 2 == 0:
			level += 1
			_apply_level()
			line += "\n" + tr("LEVEL %d: she jumps higher and runs faster") % level
		_show_banner(line, 4.5)
		Audio.play_ui(&"ui_unlock", 0.0)
		job_done.emit(job["id"])
	else:
		_show_banner(tr("JOB FAILED\n%s shrugs. The marker is back.") % tr(job["from"]), 4.0)
	_offer_next()


func _status() -> String:
	return tr("%d catnip   level %d   yarn %d/%d") % [catnip, level, yarn_found.size(), YARN_COUNT]


func _apply_level() -> void:
	if _cat == null:
		return
	var k := 1.0 + 0.06 * (level - 1)
	_cat.jump_height = 1.6 * k
	_cat.gallop_speed = 13.0 * (1.0 + 0.03 * (level - 1))


func _show_banner(text: String, seconds: float) -> void:
	_banner.text = text
	_banner_t = seconds
	_banner.modulate.a = 1.0


## Thirty balls of golden yarn: on tower roofs, inside houses, in the groves of the Park, on the containers.
func _place_yarn() -> void:
	var spots: Array[Vector3] = []
	var city: CityLayout = _main.get("city")
	var sm := Game.structures as StructureManager
	if city != null and sm != null:
		var towers: Array = []
		var houses: Array = []
		for lot in city.lots:
			if int(lot["style"]) == DestructionDefs.Style.TOWER:
				towers.append(lot)
			elif int(lot["style"]) == DestructionDefs.Style.HOUSE:
				houses.append(lot)
		for k in 10:
			if towers.is_empty():
				break
			var lot: Dictionary = towers[_rng.randi_range(0, towers.size() - 1)]
			var box: AABB = sm.buildings[int(lot["bid"])].world_box
			spots.append(Vector3(box.get_center().x, box.end.y + 0.6, box.get_center().z))
		for k in 10:
			if houses.is_empty():
				break
			var lot: Dictionary = houses[_rng.randi_range(0, houses.size() - 1)]
			spots.append((lot["pos"] as Vector3) + Vector3(0.0, 0.5, 0.0))
		for c in CityLayout.block_centres(CityLayout.District.PARK):
			spots.append(c + Vector3(-25.0, 0.6, -23.0))
		for c in city.container_yards:
			spots.append(c + Vector3(0.0, 8.4, 4.5))
	while spots.size() > YARN_COUNT:
		spots.pop_back()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.78, 0.2)
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.15)
	gold.emission_energy_multiplier = 1.6
	gold.roughness = 0.35
	for p in spots:
		var y := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.28
		s.height = 0.56
		y.mesh = s
		y.material_override = gold
		add_child(y)
		y.global_position = Vector3(p.x, maxf(p.y, _ground(p.x, p.z) + 0.4), p.z)
		_yarns.append(y)


func _find_yarn(i: int) -> void:
	_yarns[i].visible = false
	if not yarn_found.has(i):
		yarn_found.append(i)
		catnip += YARN_PAY
		_show_banner(tr("GOLDEN YARN  %d / %d   +%d catnip") % [yarn_found.size(), YARN_COUNT, YARN_PAY], 2.5)
		Audio.play_ui(&"ui_unlock", -4.0)


## [world position, colour, size, stays on the rim]: the marker of the job on offer.
func radar_blips() -> Array:
	if _marker == null or current >= 0:
		return []
	return [[_marker.global_position, Color(1.0, 0.8, 0.25), 6.5, true]]


func save_state() -> Dictionary:
	var people := _main.get("people") as People if _main != null else null
	return {"done": done.map(func(s: StringName) -> String: return String(s)), "catnip": catnip, "level": level, "yarn": Array(yarn_found), "views": people.views if people != null else 0.0}


func restore_state(state: Dictionary) -> void:
	done.clear()
	for s: Variant in state.get("done", []):
		done.append(StringName(String(s)))
	catnip = int(state.get("catnip", 0))
	var people := _main.get("people") as People if _main != null else null
	if people != null:
		people.views = float(state.get("views", 0.0))
	level = int(state.get("level", 1))
	yarn_found = PackedInt32Array(state.get("yarn", []))
	for i in yarn_found:
		if i >= 0 and i < _yarns.size():
			_yarns[i].visible = false
	_apply_level()
	_offer_next()


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0
