class_name VehicleLibrary
extends Node3D
## Cuts single vehicles out of the two vehicle packs. Each pack is one GLB that shows all its vehicles
## side by side, turned at showroom angles, in millimetre-like units; the passenger pack even keeps
## bodies and wheels as separate siblings. This node loads the packs once, groups wheels with their
## body, and keeps one hidden prototype per vehicle as a child: +Z along the length, origin on the
## ground, metres. build() hands out copies.

const PASSENGER_PACK := "res://assets/models/vehicles/passenger_cars.glb"
const SERVICE_PACK := "res://assets/models/vehicles/service_vehicles.glb"

var passenger: Array[StringName] = []   ## Names of the everyday cars (compact, sedan, pickup, ...).
var service: Array[StringName] = []     ## Names of the service vehicles (taxi, ambulance, citybus, ...).

var _protos := {}   # name -> Node3D


func _ready() -> void:
	visible = false
	_load_passenger()
	_load_service()


## Files this class reads (the composition root asks worker threads for them ahead of time).
static func model_paths() -> PackedStringArray:
	return PackedStringArray([PASSENGER_PACK, SERVICE_PACK])


func has_vehicle(vehicle: StringName) -> bool:
	return _protos.has(vehicle)


## A fresh model of one vehicle, or null if the packs do not hold it.
func build(vehicle: StringName) -> Node3D:
	var proto := _protos.get(vehicle) as Node3D
	if proto == null:
		return null
	var copy := proto.duplicate() as Node3D
	copy.name = String(vehicle)
	return copy


func _load_passenger() -> void:
	var scene := load(PASSENGER_PACK) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate() as Node3D
	var hub := _hub(root)
	var chain := _chain(root, hub)
	var bodies: Array[Node3D] = []
	var wheels: Array[Node3D] = []
	for c in hub.get_children():
		var n := c as Node3D
		if n == null:
			continue
		var lname := String(n.name).to_lower()
		if lname.contains("body"):
			bodies.append(n)
		elif lname.begins_with("wheel"):
			wheels.append(n)
	# A wheel belongs to the body whose middle is nearest to it on the showroom floor.
	var centres: Array[Vector3] = []
	var sets: Array[Array] = []
	for b in bodies:
		centres.append(b.transform * _local_bounds(b).get_center())
		sets.append([])
	for w in wheels:
		var best := -1
		var best_d := 1.0e18
		for i in bodies.size():
			var d := Vector2(w.position.x - centres[i].x, w.position.z - centres[i].z).length_squared()
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			sets[best].append(w)
	for i in bodies.size():
		var mine: Array = sets[i]
		if mine.size() != 4:
			continue
		var pts: Array[Vector3] = []
		var mid := Vector3.ZERO
		for w: Node3D in mine:
			pts.append(w.position)
			mid += w.position / 4.0
		var vname := StringName(String(bodies[i].name).to_lower().replace("body", "").strip_edges().replace(" ", "_"))
		var parts: Array[Node3D] = [bodies[i]]
		for w: Node3D in mine:
			parts.append(w)
		# The body shell says which way the car points (in one model the wheels sit at an angle to
		# it); the wheels only give the middle.
		var dir := _principal_direction(bodies[i])
		if dir == Vector3.ZERO:
			dir = _wheelbase_direction(pts)
		_add(vname, parts, dir, mid, chain)
		# A car that is not clearly longer than wide in its own frame was modelled in some pose that
		# does not park (the coupe of this pack comes out 3.7 m wide): leave it out.
		var proto := _protos[vname] as Node3D
		var box := BreakableProp.bounds_of(proto, proto)
		if box.size.x > 2.9 or box.size.x > box.size.z * 0.62:
			_protos.erase(vname)
			proto.free()
			continue
		passenger.append(vname)
	root.free()


func _load_service() -> void:
	var scene := load(SERVICE_PACK) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate() as Node3D
	var hub := _hub(root)
	var chain := _chain(root, hub)
	for c in hub.get_children():
		var n := c as Node3D
		if n == null:
			continue
		# The length is the longer of the two local axes that lie flat on the floor.
		var box := _local_bounds(n)
		var dir := Vector3.ZERO
		var longest := -1.0
		for axis in 3:
			var world_axis := n.transform.basis[axis].normalized()
			if absf(world_axis.y) < 0.5 and box.size[axis] > longest:
				longest = box.size[axis]
				dir = Vector3(world_axis.x, 0.0, world_axis.z).normalized()
		if longest <= 0.0:
			continue
		var vname := StringName(String(n.name).to_lower().replace(" ", "_"))
		var parts: Array[Node3D] = [n]
		_add(vname, parts, dir, n.position, chain)
		service.append(vname)
	root.free()


## Stores a prototype built from `parts` (siblings in the pack's hub): the frame is turned so `dir`
## becomes +Z and moved to `mid` on the floor, then the pack's own scale is applied on top.
func _add(vname: StringName, parts: Array[Node3D], dir: Vector3, mid: Vector3, chain: Transform3D) -> void:
	var frame := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(mid.x, 0.0, mid.z))
	var inv := frame.affine_inverse()
	var proto := Node3D.new()
	proto.name = String(vname)
	var holder := Node3D.new()
	holder.name = "Pack"
	holder.transform = Transform3D(chain.basis, Vector3.ZERO)
	proto.add_child(holder)
	for n in parts:
		var copy := n.duplicate() as Node3D
		copy.transform = inv * n.transform
		holder.add_child(copy)
	add_child(proto)
	_protos[vname] = proto


## The node under which the vehicles sit: the first one down the single-child chain with several children.
static func _hub(root: Node3D) -> Node3D:
	var node := root
	while node.get_child_count() == 1 and node.get_child(0) is Node3D:
		node = node.get_child(0) as Node3D
	return node


## Transform of the hub relative to the pack root (carries the unit scale).
static func _chain(root: Node3D, hub: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := hub
	while n != null and n != root:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


## Box around the meshes of `node`, in its own space.
static func _local_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var mine := node as MeshInstance3D
	if mine != null and mine.mesh != null:
		box = mine.get_aabb()
		first = false
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.transform
		var p := mi.get_parent() as Node3D
		while p != null and p != node:
			xf = p.transform * xf
			p = p.get_parent() as Node3D
		var a := xf * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


## Long axis of a body on the floor of its parent space: the principal axis of its vertices seen from
## above (a car is more than twice as long as it is wide, so this is unambiguous).
static func _principal_direction(node: Node3D) -> Vector3:
	var pts := PackedVector2Array()
	var nodes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		nodes.append(node)
	for m: Node in nodes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node3D = mi
		while p != null and p != node.get_parent():
			xf = p.transform * xf
			p = p.get_parent() as Node3D
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, int(verts.size() / 600.0))
			for i in range(0, verts.size(), step):
				var v := xf * verts[i]
				pts.append(Vector2(v.x, v.z))
	if pts.size() < 8:
		return Vector3.ZERO
	var mean := Vector2.ZERO
	for q in pts:
		mean += q / pts.size()
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for q in pts:
		var d := q - mean
		sxx += d.x * d.x
		szz += d.y * d.y
		sxz += d.x * d.y
	var angle := 0.5 * atan2(2.0 * sxz, sxx - szz)
	return Vector3(cos(angle), 0.0, sin(angle))


## Four wheels form a rectangle: its longer side is the wheelbase. Of the six distances between the
## wheels the two largest are the diagonals, the next two the wheelbase.
static func _wheelbase_direction(pts: Array[Vector3]) -> Vector3:
	var pairs := []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var d := pts[j] - pts[i]
			d.y = 0.0
			pairs.append([d.length(), d])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var dir: Vector3 = pairs[2][1]
	return dir.normalized()
