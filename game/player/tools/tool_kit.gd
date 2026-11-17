class_name ToolKit
extends RefCounted
## The cat's tools in belt order (keys 1-5) and the rule for handing them out: a tool is on the belt
## when Progress says it is unlocked. The paw and the pee are there from the start; the Acid Pee
## milestone does not add a tool, it turns the pee into acid. Rewind and slow motion are held keys,
## not belt tools.

const ORDER: Array[StringName] = [&"paw", &"pee", &"laser", &"wizard_hat", &"hairball"]


static func create(tool_id: StringName) -> CatTool:
	match tool_id:
		&"laser":
			return LaserDotTool.new()
		&"wizard_hat":
			return WizardHatTool.new()
		&"hairball":
			return HairballCannonTool.new()
		&"pee":
			return PeeTool.new()
	return null


## Belt slot of a tool; the acid upgrade lives in the pee's slot.
static func slot_of(tool_id: StringName) -> int:
	return ORDER.find(&"pee" if tool_id == &"acid" else tool_id)


## Puts every unlocked tool on the cat's belt and keeps doing so as Progress unlocks more.
static func attach(cat: CatPlayer) -> void:
	sync(cat)
	var follow := func(_id: StringName) -> void:
		if is_instance_valid(cat):
			ToolKit.sync(cat)
	Progress.tool_unlocked.connect(follow)
	# A lambda on an autoload signal outlives the cat: take it off when she leaves (quit to title).
	cat.tree_exiting.connect(func() -> void:
		if Progress.tool_unlocked.is_connected(follow):
			Progress.tool_unlocked.disconnect(follow), CONNECT_ONE_SHOT)


static func sync(cat: CatPlayer) -> void:
	for slot in range(1, ORDER.size()):
		var id := ORDER[slot]
		if cat.belt.slots[slot] == null and Progress.is_tool_unlocked(id):
			var tool := create(id)
			if tool != null:
				tool.name = String(id).capitalize().replace(" ", "")
				cat.belt.set_tool(slot, tool)
