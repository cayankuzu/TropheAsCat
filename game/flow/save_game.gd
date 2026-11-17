class_name SaveGame
extends RefCounted
## Saved games (2026-11-17): an autosave and three slots under user://saves/slot_<n>/.
##
## The city is built the same way every time, so a save is only what changed: which elements of which
## building are gone, which props are gone or burnt out, which dominoes lie where, which of the little
## people are shattered, the dug terrain (Voxel Tools' own store), where Trophe was, and the progress
## (unlocked tools, the best chain). Loading builds a fresh Table and takes those things out again,
## silently: no debris, no fire, no sound. The rubble is gone; the Owner's vacuum robot took it.

const VERSION := 1
const AUTOSAVE := 0
const SLOT_COUNT := 4          ## the autosave and slots 1 to 3
const ROOT := "user://saves/"


static func dir(slot: int) -> String:
	return ROOT + "slot_%d/" % slot


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(dir(slot) + "save.json")


## {time, cleared, unix} of a slot, or {} when it is empty or unreadable.
static func info(slot: int) -> Dictionary:
	var data := _read(slot)
	if data.is_empty():
		return {}
	return {"time": String(data.get("time", "")), "cleared": float(data.get("cleared", 0.0)), "unix": float(data.get("unix", 0.0))}


## The slot with the newest save, -1 when there is none.
static func latest() -> int:
	var best := -1
	var best_t := -1.0
	for slot in SLOT_COUNT:
		var i := info(slot)
		if not i.is_empty() and float(i["unix"]) > best_t:
			best_t = i["unix"]
			best = slot
	return best


static func slot_name(slot: int) -> String:
	return Lang.t("Autosave") if slot == AUTOSAVE else Lang.t("Slot %d") % slot


## What a menu shows for a slot.
static func describe(slot: int) -> String:
	var i := info(slot)
	if i.is_empty():
		return Lang.t("%s  -  empty") % slot_name(slot)
	return Lang.t("%s  -  %.2f %% cleared  -  %s") % [slot_name(slot), float(i["cleared"]), String(i["time"]).replace("T", " ").left(16)]


## Writes the game of a running main scene (game/main.gd) into a slot. Returns false when it could not.
static func write(main: Node, slot: int) -> bool:
	var sm := Game.structures as StructureManager
	if sm == null or not is_instance_valid(sm):
		return false
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(dir(slot))
	var buildings := {}
	for bid in sm.building_count():
		var gone := sm.removed_elements(bid)
		if not gone.is_empty():
			buildings[str(bid)] = Array(gone)
	var cat := Game.player
	var at := cat.global_position if cat != null and is_instance_valid(cat) else Vector3(0.0, 0.0, 14.0)
	if absf(at.x) > 480.0 or absf(at.z) > 480.0 or at.y < -40.0:
		at = Vector3(0.0, 0.0, 14.0)   # she was falling off the Table: she comes back at the crossing
	var data := {
		"version": VERSION,
		"unix": Time.get_unix_time_from_system(),
		"time": Time.get_datetime_string_from_system(false, true),
		"cleared": Progress.cleared_percent(),
		"building_count": sm.building_count(),
		"progress": Progress.save_state(),
		"buildings": buildings,
		"props": (main.get("dressing") as StreetDressing).save_state(),
		"dominoes": (main.get("dominoes") as DominoRun).save_state(),
		"people": (main.get("people") as People).save_state(),
		"cat": [at.x, at.y, at.z],
		"jobs": (main.get("jobs") as Jobs).save_state() if main.get("jobs") != null else {},
	}
	var terrain := main.get("terrain") as Node
	if terrain != null:
		terrain.call(&"save_edits", dir(slot) + "terrain.sqlite")
	var f := FileAccess.open(dir(slot) + "save.json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	print("SaveGame: %s written in %d ms (%d buildings changed)" % [slot_name(slot), Time.get_ticks_msec() - t0, buildings.size()])
	return true


## Puts a saved game back into a freshly built main scene. Returns {cat: Vector3} (where Trophe was), or {}
## when the slot could not be read.
static func apply(main: Node, slot: int) -> Dictionary:
	var data := _read(slot)
	if data.is_empty():
		return {}
	var sm := Game.structures as StructureManager
	Progress.begin_restore()
	# A save from another build of the city keeps its progress but not its world.
	if int(data.get("building_count", -1)) == sm.building_count():
		var buildings: Dictionary = data.get("buildings", {})
		for key: String in buildings:
			sm.restore_removed(int(key), PackedInt32Array(buildings[key]))
		(main.get("dressing") as StreetDressing).restore_state(data.get("props", {}))
		(main.get("dominoes") as DominoRun).restore_state(data.get("dominoes", {}))
		(main.get("people") as People).restore_state(data.get("people", []))
		var terrain := main.get("terrain") as Node
		if terrain != null and FileAccess.file_exists(dir(slot) + "terrain.sqlite"):
			terrain.call(&"load_edits", dir(slot) + "terrain.sqlite")
	Progress.end_restore(data.get("progress", {}))
	Jobs.pending = data.get("jobs", {})   # the jobs are made when play begins; they take it from there
	var c: Array = data.get("cat", [0.0, 0.0, 14.0])
	return {"cat": Vector3(float(c[0]), float(c[1]), float(c[2]))}


static func _read(slot: int) -> Dictionary:
	var path := dir(slot) + "save.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != VERSION:
		return {}
	return parsed
