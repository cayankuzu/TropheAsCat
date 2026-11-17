class_name ToolBelt
extends Node
## Nine tool slots (keys 1-9), Tab / mouse wheel cycling over the filled slots. Slot 0 is the Paw.

signal tool_changed(slot: int, tool: CatTool)

const SLOT_COUNT := 9

var slots: Array[CatTool] = []
var current_slot := -1
var cat: CatPlayer = null


func _init() -> void:
	slots.resize(SLOT_COUNT)


func setup(owner_cat: CatPlayer) -> void:
	cat = owner_cat


func set_tool(slot: int, tool: CatTool) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	if slots[slot] != null and slots[slot] != tool:
		if current_slot == slot:
			slots[slot].unequip()
		slots[slot].queue_free()
	slots[slot] = tool
	if tool != null and tool.get_parent() == null:
		add_child(tool)
	if current_slot == -1 and tool != null:
		select(slot)


func get_current() -> CatTool:
	return slots[current_slot] if current_slot >= 0 else null


func select(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT or slots[slot] == null or slot == current_slot:
		return false
	var cur := get_current()
	if cur != null:
		if cur.is_busy():
			return false
		cur.unequip()
	current_slot = slot
	slots[slot].equip(cat)
	tool_changed.emit(slot, slots[slot])
	return true


## Selects the next (dir > 0) or previous filled slot.
func cycle(dir: int) -> bool:
	if current_slot < 0:
		return false
	for i in range(1, SLOT_COUNT):
		var s := posmod(current_slot + i * signi(dir), SLOT_COUNT)
		if slots[s] != null:
			return select(s)
	return false


func primary(pressed: bool) -> void:
	var t := get_current()
	if t != null:
		t.primary(pressed)


func secondary(pressed: bool) -> void:
	var t := get_current()
	if t != null:
		t.secondary(pressed)


func tick(delta: float) -> void:
	var t := get_current()
	if t != null:
		t.process(delta)


func wants_stand_pose() -> bool:
	var t := get_current()
	return t != null and t.wants_stand_pose
