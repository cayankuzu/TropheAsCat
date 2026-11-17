extends Node3D
## Headless check of the Progress autoload (TABLE CLEARED %, milestones, tool unlocks) and of the mass the
## StructureManager reports to it.
## Run: Godot --headless --path <P> res://tests/test_progress.tscn --fixed-fps 60

const D := preload("res://game/destruction/destruction_defs.gd")

var all_ok := true
var _milestones: Array = []
var _unlocks: Array = []
var _percents: Array = []


func _ready() -> void:
	Progress.sandbox_all_tools = false
	Progress.reset()
	Progress.milestone_reached.connect(func(index: int, tool_id: StringName) -> void: _milestones.append([index, tool_id]))
	Progress.tool_unlocked.connect(func(tool_id: StringName) -> void: _unlocks.append(tool_id))
	Progress.cleared_changed.connect(func(p: float) -> void: _percents.append(p))

	# --- Known masses fed by hand -------------------------------------------------------------
	# The thresholds come from Progress.MILESTONES, so retuning them does not break this test.
	var steps: Array = Progress.MILESTONES
	var p0 := float(steps[0]["percent"])
	var p2 := float(steps[2]["percent"])
	var p_last := float(steps[steps.size() - 1]["percent"])
	Progress.set_total_mass(1.0e6)
	_check("starts with the paw only", Progress.is_tool_unlocked(&"paw") and not Progress.is_tool_unlocked(&"laser") and Progress.cleared_percent() == 0.0,
		"paw %s, laser %s, %.2f %%" % [Progress.is_tool_unlocked(&"paw"), Progress.is_tool_unlocked(&"laser"), Progress.cleared_percent()])
	_raise_to(p0 * 0.5)
	_check("half the first threshold unlocks nothing", is_equal_approx(Progress.cleared_percent(), p0 * 0.5) and _milestones.is_empty(),
		"%.3f %% of %.3f %%, milestones %s" % [Progress.cleared_percent(), p0, _milestones])
	_raise_to(p0)
	_check("the first threshold unlocks the Laser Dot", _milestones == [[0, &"laser"]] and Progress.is_tool_unlocked(&"laser") and not Progress.is_tool_unlocked(&"wizard_hat"),
		"at %.3f %%: milestones %s" % [Progress.cleared_percent(), _milestones])
	_raise_to(p2 + 0.01)   # one big collapse passes Rewind and the Wizard Hat together
	_check("a big collapse passes two milestones in order", _milestones == [[0, &"laser"], [1, &"rewind"], [2, &"wizard_hat"]] and Progress.next_milestone() == 3,
		"at %.3f %%: milestones %s, next %d" % [Progress.cleared_percent(), _milestones, Progress.next_milestone()])
	_raise_to(p_last)
	_check("the last threshold has unlocked everything", Progress.is_tool_unlocked(&"hairball") and Progress.is_tool_unlocked(&"acid") and Progress.next_milestone() == steps.size(),
		"%.1f %%, unlock signals %s" % [Progress.cleared_percent(), _unlocks])
	var ordered := true
	for i in range(1, steps.size()):
		if float(steps[i]["percent"]) <= float(steps[i - 1]["percent"]):
			ordered = false
	_check("the thresholds rise", ordered, "%s" % [steps.map(func(m: Dictionary) -> float: return m["percent"])])
	Progress.add_destroyed_mass(5.0e6)
	_check("the percentage stops at 100", Progress.cleared_percent() == 100.0, "%.1f %%" % Progress.cleared_percent())
	var rising := true
	for i in range(1, _percents.size()):
		if _percents[i] < _percents[i - 1]:
			rising = false
	_check("cleared_changed only ever rises", rising and _percents.size() >= 5, "%s" % [_percents])

	# --- The sandbox switch ----------------------------------------------------------------------
	Progress.reset()
	_unlocks.clear()
	_check("reset locks the tools again", not Progress.is_tool_unlocked(&"laser") and Progress.cleared_percent() == 0.0 and Progress.next_milestone() == 0,
		"laser %s, %.2f %%" % [Progress.is_tool_unlocked(&"laser"), Progress.cleared_percent()])
	Progress.sandbox_all_tools = true
	_check("the sandbox unlocks everything and says so", Progress.is_tool_unlocked(&"acid") and not _unlocks.is_empty(), "acid %s, signals %s" % [Progress.is_tool_unlocked(&"acid"), _unlocks])
	Progress.sandbox_all_tools = false

	# --- The chain, and the pee ------------------------------------------------------------------
	Progress.reset()
	var chains := []
	var ended := []
	Progress.chain_changed.connect(func(count: int, title: String) -> void: chains.append([count, title]))
	Progress.chain_ended.connect(func(count: int) -> void: ended.append(count))
	for i in 8:
		Progress.report_break()
	_check("eight breaks in a row are a chain with a rank", Progress.chain == 8 and chains.size() == 8 and chains[7] == [8, "NAUGHTY"] and chains[6] == [7, ""],
		"chain %d, last %s" % [Progress.chain, chains[chains.size() - 1]])
	Progress.report_break(40)
	_check("a long chain earns the title of the game", Progress.chain_title(Progress.chain) == "CAT-ASTROPHE", "%d -> %s" % [Progress.chain, Progress.chain_title(Progress.chain)])
	await get_tree().create_timer(Progress.CHAIN_WINDOW + 0.3).timeout
	_check("the chain ends when nothing breaks for a while and the best one is kept", Progress.chain == 0 and ended == [48] and Progress.best_chain == 48,
		"chain %d, ended %s, best %d" % [Progress.chain, ended, Progress.best_chain])
	_check("the pee is there from the start and acid is its upgrade", Progress.is_tool_unlocked(&"pee") and not Progress.is_tool_unlocked(&"acid")
		and ToolKit.slot_of(&"pee") == 1 and ToolKit.slot_of(&"acid") == 1, "pee %s, acid %s, slots %d and %d" % [Progress.is_tool_unlocked(&"pee"),
		Progress.is_tool_unlocked(&"acid"), ToolKit.slot_of(&"pee"), ToolKit.slot_of(&"acid")])

	# --- Building mass from the StructureManager -------------------------------------------------
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.TERRAIN
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.0, 400.0)
	shape.shape = box
	shape.position.y = -1.0
	ground.add_child(shape)
	add_child(ground)
	var sm := StructureManager.create_world(self)
	Game.structures = sm
	Game.debris = sm.debris
	Progress.reset()
	var bid := sm.spawn_building(D.Style.HOUSE, 5, Transform3D.IDENTITY)
	sm.fracture.flush()
	var b := sm.buildings[bid]
	var built := b.data.total_mass()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a placed building counts towards the total", absf(Progress.total_mass - built) < 1.0 and absf(sm.built_mass - built) < 1.0 and Progress.destroyed_mass == 0.0,
		"house %.0f kg, Progress total %.0f kg, destroyed %.0f kg" % [built, Progress.total_mass, Progress.destroyed_mass])
	# One wall destroyed where it stands.
	var walls := sm.find_elements(bid, 0, [D.Kind.WALL, D.Kind.PIER])
	var first: int = walls[0]
	var first_mass := b.data.mass[first]
	sm.destroy_element(bid, first)
	sm.destroy_element(bid, first)   # a second call must not count it again
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a destroyed element is counted once", absf(sm.gone_mass - first_mass) < 0.5 and absf(Progress.destroyed_mass - first_mass) < 0.5,
		"element %.0f kg, gone %.0f kg, Progress destroyed %.0f kg" % [first_mass, sm.gone_mass, Progress.destroyed_mass])
	# The whole ground floor cut: what falls counts as well, and nothing is counted twice while it breaks up.
	for e in sm.find_elements(bid, 0, [D.Kind.WALL, D.Kind.PIER, D.Kind.SILL, D.Kind.COLUMN]):
		sm.destroy_element(bid, e)
	for i in 360:
		await get_tree().process_frame
	var standing := sm.intact_mass(bid)
	_check("gone mass is exactly what no longer stands", absf(sm.gone_mass - (built - standing)) < 1.0 and sm.gone_mass <= built + 1.0,
		"built %.0f kg, still standing %.0f kg, gone %.0f kg" % [built, standing, sm.gone_mass])
	_check("Progress follows the building", absf(Progress.destroyed_mass - sm.gone_mass) < 1.0 and Progress.cleared_percent() > 50.0,
		"Progress destroyed %.0f kg, cleared %.1f %%, milestones reached %d" % [Progress.destroyed_mass, Progress.cleared_percent(), Progress.next_milestone()])

	print("RESULT ", "PASS" if all_ok else "FAIL")
	sm.clear()
	Game.structures = null
	Game.debris = null
	await get_tree().process_frame
	get_tree().quit(0 if all_ok else 1)


## Destroys enough mass to bring TABLE CLEARED % up to `percent`.
func _raise_to(percent: float) -> void:
	Progress.add_destroyed_mass(maxf(Progress.total_mass * percent / 100.0 - Progress.destroyed_mass, 0.0))


func _check(name_: String, ok: bool, detail: String) -> void:
	if not ok:
		all_ok = false
	print("[%s] %s: %s" % ["PASS" if ok else "FAIL", name_, detail])
