class_name DebrisCluster
extends RefCounted
## A group of intact building elements falling as one RigidBody3D compound.
## Built incrementally (shapes are added under a time budget), rendered by one MultiMesh per element
## mesh, and broken up later by peeling element subsets off into new bodies.

var body: RigidBody3D
var building := 0
var elems := PackedInt32Array()
var locals: Array[Transform3D] = []      ## element frame relative to the body
var meshes: Array[Mesh] = []
var shapes: Array[Shape3D] = []
var masses := PackedFloat32Array()
var elem_com := PackedVector3Array()     ## element centre of mass in its own frame
var customs := PackedColorArray()        ## crack data per element (see crack_overlay.gdshader)
var owners := PackedInt32Array()         ## shape owner id per local index, -1 once peeled
var vgroup := PackedInt32Array()
var vinst := PackedInt32Array()
var groups: Array[InstanceGroup] = []
var alive := 0
var mass := 0.0
var cause := 0
var slot := -1
var breaking := false
var break_point := Vector3.ZERO
var break_energy := 0.0              ## < 0 once the impact zone of the current break has been handled
var chunk_max := 32
var has_pre := false                 ## break from an end impact: pieces keep the pre-impact motion
var pre_v := Vector3.ZERO
var pre_w := Vector3.ZERO
var pre_com := Vector3.ZERO
var freezing := false
var kinematic := false               ## driven by a scripted hinge rotation (StructureManager.Topple)
var shadows := PackedByteArray()
var _cursor := 0
var _group_by_mesh: Dictionary = {}
var _counts: Dictionary = {}


## world_xfs: current world transform of every element. The body frame is aligned with frame_basis and
## centred on the combined centre of mass.
func begin(p_building: int, p_elems: PackedInt32Array, world_xfs: Array[Transform3D], frame_basis: Basis) -> void:
	building = p_building
	elems = p_elems
	var n := elems.size()
	var com := Vector3.ZERO
	mass = 0.0
	for i in n:
		com += (world_xfs[i] * elem_com[i]) * masses[i]
		mass += masses[i]
	com /= maxf(mass, 0.001)
	body = RigidBody3D.new()
	body.transform = Transform3D(frame_basis, com)
	var inv := body.transform.affine_inverse()
	locals.resize(n)
	for i in n:
		locals[i] = inv * world_xfs[i]
	owners.resize(n)
	owners.fill(-1)
	vgroup.resize(n)
	vinst.resize(n)
	alive = n
	body.mass = maxf(mass, 1.0)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.ZERO
	_cursor = 0
	_counts.clear()
	for i in n:
		var key := meshes[i].get_rid()
		_counts[key] = int(_counts.get(key, 0)) + 1


## Adds collision shapes and render instances until done or the deadline passes.
## Returns true when every element is in.
func build_step(deadline_usec: int) -> bool:
	while _cursor < elems.size():
		var i := _cursor
		var o := body.create_shape_owner(body)
		body.shape_owner_add_shape(o, shapes[i])
		body.shape_owner_set_transform(o, locals[i])
		owners[i] = o
		var key := meshes[i].get_rid()
		var gi: int = _group_by_mesh.get(key, -1)
		if gi < 0:
			gi = groups.size()
			_group_by_mesh[key] = gi
			groups.append(InstanceGroup.new(body, meshes[i], int(_counts.get(key, 4)), true, shadows[i] == 1, true))
		vgroup[i] = gi
		vinst[i] = groups[gi].add(i, locals[i], customs[i])
		_cursor += 1
		if (_cursor & 7) == 0 and Time.get_ticks_usec() > deadline_usec:
			return _cursor >= elems.size()
	return true


func finish_visuals(overlay: Material) -> void:
	if overlay != null:
		for g in groups:
			for k in g.count:
				if g.customs[k].r > 0.01:
					g.mmi.material_overlay = overlay
					g.has_overlay = true
					break


func world_transform(i: int) -> Transform3D:
	return body.global_transform * locals[i]


## Removes elements (local indices) from this body: shapes, visuals, mass. Centre of mass is updated.
func peel(indices: PackedInt32Array) -> void:
	for i in indices:
		if owners[i] < 0:
			continue
		body.remove_shape_owner(owners[i])
		owners[i] = -1
		var g := groups[vgroup[i]]
		var moved := g.remove(vinst[i])
		if moved >= 0:
			vinst[moved] = vinst[i]
		vinst[i] = -1
		alive -= 1
		mass -= masses[i]
	if alive > 0:
		var com := Vector3.ZERO
		var m := 0.0
		for i in elems.size():
			if owners[i] >= 0:
				com += (locals[i] * elem_com[i]) * masses[i]
				m += masses[i]
		body.mass = maxf(m, 1.0)
		body.center_of_mass = com / maxf(m, 0.001)


func alive_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in elems.size():
		if owners[i] >= 0:
			out.append(i)
	return out
