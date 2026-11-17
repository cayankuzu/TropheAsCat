class_name InstanceGroup
extends RefCounted
## One MultiMeshInstance3D with swap-remove bookkeeping. Keeps CPU copies of transforms and custom data
## so removals and growth never read back from the RenderingServer.

var mmi: MultiMeshInstance3D
var mm: MultiMesh
var owners := PackedInt32Array()      ## instance index -> owner id (element or rubble id)
var xfs: Array[Transform3D] = []
var customs := PackedColorArray()
var count := 0
var capacity := 0
var has_overlay := false


func _init(parent: Node, mesh: Mesh, initial_capacity: int, custom_data: bool, shadows: bool, interpolated: bool) -> void:
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom_data
	mm.mesh = mesh
	capacity = maxi(initial_capacity, 1)
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	owners.resize(capacity)
	xfs.resize(capacity)
	customs.resize(capacity)
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not interpolated:
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


func add(owner: int, xf: Transform3D, custom: Color = Color(0, 0, 0, 0)) -> int:
	if count == capacity:
		_grow()
	var k := count
	owners[k] = owner
	xfs[k] = xf
	customs[k] = custom
	mm.set_instance_transform(k, xf)
	if mm.use_custom_data:
		mm.set_instance_custom_data(k, custom)
	count += 1
	mm.visible_instance_count = count
	return k


## Removes instance k by moving the last instance into its slot.
## Returns the owner id that now lives at index k, or -1 when k was the last instance.
func remove(k: int) -> int:
	var last := count - 1
	var moved := -1
	if k != last:
		moved = owners[last]
		owners[k] = moved
		xfs[k] = xfs[last]
		customs[k] = customs[last]
		mm.set_instance_transform(k, xfs[k])
		if mm.use_custom_data:
			mm.set_instance_custom_data(k, customs[k])
	count = last
	mm.visible_instance_count = count
	return moved


func set_transform(k: int, xf: Transform3D) -> void:
	xfs[k] = xf
	mm.set_instance_transform(k, xf)


func set_custom(k: int, c: Color) -> void:
	customs[k] = c
	if mm.use_custom_data:
		mm.set_instance_custom_data(k, c)


func _grow() -> void:
	var new_cap := capacity * 2
	owners.resize(new_cap)
	xfs.resize(new_cap)
	customs.resize(new_cap)
	mm.instance_count = new_cap
	for k in count:
		mm.set_instance_transform(k, xfs[k])
		if mm.use_custom_data:
			mm.set_instance_custom_data(k, customs[k])
	capacity = new_cap
	mm.visible_instance_count = count


func free_node() -> void:
	if is_instance_valid(mmi):
		mmi.queue_free()
