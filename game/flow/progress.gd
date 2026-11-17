extends Node
## Autoload "Progress": TABLE CLEARED %, the Owner's milestones and the tool unlocks (docs/DESIGN.md
## section 3).
##
## TABLE CLEARED % = destroyed man-made mass / total man-made mass. Terrain, nature and animals are not
## part of it. Building mass comes from the StructureManager (built_mass, and gone_mass: every element
## that is no longer part of a standing building, whether it broke where it stood or fell with a
## piece of the building); props and vehicles add themselves (add_total_mass when they appear,
## add_destroyed_mass when they break).
##
## Each milestone is one of the Owner's attempts to stop Trophe, and each one backfires into a tool.

signal cleared_changed(percent: float)
signal milestone_reached(index: int, tool_id: StringName)
signal tool_unlocked(tool_id: StringName)
signal sandbox_changed(on: bool)
## The chain: things broken in quick succession. title is "" below the first rank.
signal chain_changed(count: int, title: String)
signal chain_ended(count: int)

## Tool ids used across modules.
const TOOL_PAW := &"paw"
const TOOL_PEE := &"pee"       ## there from the start, like the paw; TOOL_ACID is its upgrade
const TOOL_LASER := &"laser"
const TOOL_REWIND := &"rewind"
const TOOL_WIZARD := &"wizard_hat"
const TOOL_HAIRBALL := &"hairball"
const TOOL_ACID := &"acid"

## In order. percent: TABLE CLEARED % that triggers it; owner: what the Owner says as it tries.
## The city weighs about 234,000 t: a house is 0.03 %, an apartment block 1 %, a tower 2 %. With the
## paw alone the first tool has to come after a handful of houses, not after a whole apartment block,
## so the first steps are small and the later ones wide.
const MILESTONES := [
	{"percent": 0.2, "tool": TOOL_LASER, "name": "Laser Dot",
		"owner": "Look, Trophe: a red dot! Go on, chase the dot. Away from the buildings."},
	{"percent": 1.0, "tool": TOOL_REWIND, "name": "Rewind",
		"owner": "No harm done. I will simply undo that. Ctrl, Z. There."},
	{"percent": 3.0, "tool": TOOL_WIZARD, "name": "Wizard Hat",
		"owner": "Hold still, just one photo. Who is a little wizard? You are."},
	{"percent": 8.0, "tool": TOOL_HAIRBALL, "name": "Hairball Cannon",
		"owner": "The vacuum robot will tidy this up. It loves hair."},
	{"percent": 15.0, "tool": TOOL_ACID, "name": "Acid Pee",
		"owner": "Bad kitty. Spray bottle. I did not want to do this. ...Trophe, no. Not on the tower."},
]

## Every tool from the start (for players who only want chaos, and for tests). F1 toggles it until the
## pause menu exists; the command line argument "-- --sandbox" starts with it on.
var sandbox_all_tools := false:
	set(value):
		if sandbox_all_tools == value:
			return
		sandbox_all_tools = value
		sandbox_changed.emit(value)
		# One signal is enough: listeners look at every tool again.
		tool_unlocked.emit(TOOL_PAW)

## A break within this many seconds of the last one keeps the chain going.
const CHAIN_WINDOW := 2.4
## Ranks of a chain, highest first: [breaks needed, what the screen says].
const CHAIN_RANKS := [[150, "TABLE FLIP"], [90, "TROPHE-POCALYPSE"], [45, "CAT-ASTROPHE"], [20, "BAD KITTY"], [8, "NAUGHTY"]]
## Building elements are many and small: this many of them count as one break.
const ELEMENTS_PER_BREAK := 8.0

var chain := 0
var best_chain := 0
var breaks_total := 0
## True while a saved game is put back: milestones unlock their tools without the Owner's toast.
var restoring := false

var _chain_left := 0.0
var _element_credit := 0.0
var _hooked_structures := 0

var total_mass := 0.0       ## kg of man-made things on the Table
var destroyed_mass := 0.0   ## kg of them that are gone

var _unlocked := {}             # tool id -> true
var _next_milestone := 0
var _last_percent := -1.0
var _structures_id := 0         # instance id of the StructureManager whose totals are folded in
var _structures_built := 0.0
var _structures_gone := 0.0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--sandbox"):
		sandbox_all_tools = true


## A new Table: nothing built, nothing destroyed, nothing unlocked. The sandbox switch is kept.
func reset() -> void:
	total_mass = 0.0
	destroyed_mass = 0.0
	_unlocked.clear()
	_next_milestone = 0
	_last_percent = -1.0
	_structures_id = 0
	_structures_built = 0.0
	_structures_gone = 0.0
	chain = 0
	best_chain = 0
	breaks_total = 0
	_chain_left = 0.0
	_element_credit = 0.0
	cleared_changed.emit(0.0)


func cleared_percent() -> float:
	if total_mass <= 0.0:
		return 0.0
	return clampf(100.0 * destroyed_mass / total_mass, 0.0, 100.0)


## A tool bought in the catnip shop (Jobs.buy): unlocked now, saved with the others.
func grant_tool(tool_id: StringName) -> void:
	_unlocked[tool_id] = true
	tool_unlocked.emit(tool_id)


func is_tool_unlocked(tool_id: StringName) -> bool:
	return sandbox_all_tools or tool_id == TOOL_PAW or tool_id == TOOL_PEE or _unlocked.has(tool_id)


## Index of the next milestone, or MILESTONES.size() when all are reached.
func next_milestone() -> int:
	return _next_milestone


## Called by props and vehicles when they break (buildings are read from the StructureManager).
func add_destroyed_mass(kg: float) -> void:
	if kg <= 0.0:
		return
	destroyed_mass += kg
	_update()


## World rewind: something destroyed is whole again.
func remove_destroyed_mass(kg: float) -> void:
	if kg <= 0.0:
		return
	destroyed_mass = maxf(destroyed_mass - kg, 0.0)
	_update()


## Called by props and vehicles when they appear.
func add_total_mass(kg: float) -> void:
	if kg <= 0.0:
		return
	total_mass += kg
	_update()


## Sets the mass of everything that is not a building in one go (tests, saved games).
func set_total_mass(kg: float) -> void:
	total_mass = maxf(kg, 0.0) + _structures_built
	_update()


## Something man-made broke (a prop, a car, a person; buildings report through their signals). Breaks
## in quick succession form a chain, and long chains earn a rank.
func report_break(count: int = 1) -> void:
	chain += count
	breaks_total += count
	_chain_left = CHAIN_WINDOW
	best_chain = maxi(best_chain, chain)
	chain_changed.emit(chain, chain_title(chain))


func chain_title(count: int) -> String:
	for rank: Array in CHAIN_RANKS:
		if count >= int(rank[0]):
			return rank[1]
	return ""


func _on_element_destroyed(_bid: int, _element: int, _cause: int) -> void:
	_element_credit += 1.0 / ELEMENTS_PER_BREAK
	if _element_credit >= 1.0:
		var n := int(_element_credit)
		_element_credit -= n
		report_break(n)


## Building mass is folded in here: what was built since the last frame and what has come down.
func _process(delta: float) -> void:
	if chain > 0:
		_chain_left -= delta
		if _chain_left <= 0.0:
			var ended := chain
			chain = 0
			chain_ended.emit(ended)
	_sync_structures()


## Folds the building mass of the StructureManager in: what was built and what has come down.
func _sync_structures() -> void:
	var s: Object = Game.structures
	if s == null or not is_instance_valid(s):
		return
	var structures := s as StructureManager
	if structures.get_instance_id() != _hooked_structures:
		_hooked_structures = structures.get_instance_id()
		structures.element_destroyed.connect(_on_element_destroyed)
		structures.building_toppled.connect(func(_b: int, _s: int) -> void: report_break(5))
	if structures.get_instance_id() != _structures_id:
		# Another world (tests build several): what the old one contributed stays as it is.
		_structures_id = structures.get_instance_id()
		_structures_built = 0.0
		_structures_gone = 0.0
	var built := structures.built_mass
	var gone := structures.gone_mass
	if built == _structures_built and gone == _structures_gone:
		return
	total_mass += built - _structures_built
	destroyed_mass += gone - _structures_gone
	_structures_built = built
	_structures_gone = gone
	_update()


## Saved games: what the world itself does not tell (the world puts its own mass back).
func save_state() -> Dictionary:
	var ids: Array[String] = []
	for k: StringName in _unlocked:
		ids.append(String(k))
	return {"unlocked": ids, "next_milestone": _next_milestone, "best_chain": best_chain, "breaks_total": breaks_total}


func begin_restore() -> void:
	restoring = true


func end_restore(state: Dictionary) -> void:
	_sync_structures()
	for id: Variant in state.get("unlocked", []):
		_unlocked[StringName(String(id))] = true
	_next_milestone = maxi(_next_milestone, int(state.get("next_milestone", 0)))
	best_chain = maxi(best_chain, int(state.get("best_chain", 0)))
	breaks_total = maxi(breaks_total, int(state.get("breaks_total", 0)))
	_update()
	restoring = false
	_last_percent = -1.0
	_update()
	tool_unlocked.emit(TOOL_PAW)   # one signal is enough: listeners look at every tool again


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F1:
		sandbox_all_tools = not sandbox_all_tools


func _update() -> void:
	var percent := cleared_percent()
	while _next_milestone < MILESTONES.size() and percent >= float(MILESTONES[_next_milestone]["percent"]):
		var index := _next_milestone
		_next_milestone += 1
		var tool_id: StringName = MILESTONES[index]["tool"]
		_unlocked[tool_id] = true
		if not restoring:
			milestone_reached.emit(index, tool_id)
		tool_unlocked.emit(tool_id)
	if absf(percent - _last_percent) >= 0.0005:
		_last_percent = percent
		cleared_changed.emit(percent)
