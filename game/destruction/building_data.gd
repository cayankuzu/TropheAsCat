class_name BuildingData
extends RefCounted
## Static description of one procedural building: structural elements with quantised sizes plus a
## topology graph that the generator builds from its grid (no geometric tests).
## Local frame: footprint centred on the origin, ground at y = 0, 1 unit = 1 m.

const D := preload("res://game/destruction/destruction_defs.gd")

var style: int = 0
var seed_value: int = 0
var storeys: int = 0
## True for moment frames (columns + slabs): the structure above a failing storey stays connected and
## can overturn as one block. Masonry cannot carry an overhang: its unsupported parts break away and
## fall before the rest is checked for overturning.
var monolithic := true
var bounds := AABB()
var materials: Array[StringName] = []

# Per element (index = element id).
var kind := PackedByteArray()
var role := PackedByteArray()
var shape := PackedByteArray()
var mat := PackedByteArray()          ## index into materials
var dims := PackedVector3Array()      ## full size of the element box (prism: base, height, thickness)
var xf: Array[Transform3D] = []       ## element frame relative to the building
var storey := PackedInt32Array()      ## storey the element belongs to (slabs: the storey below them)
var anchor := PackedByteArray()       ## 1 when the element touches the ground
var cant_max := PackedByteArray()     ## lateral cantilever hops a horizontal element may span
var mass := PackedFloat32Array()      ## kg
var max_hp := PackedFloat32Array()    ## J (MaterialDB.element_hp)
## Per material index: 1 when the material is a kind of glass (cached for the hot paths of the destruction).
var glass_mats := PackedByteArray()

# Adjacency in CSR form: neighbours of i are adj_to[adj_start[i] .. adj_start[i + 1] - 1].
var adj_start := PackedInt32Array()
var adj_to := PackedInt32Array()
var adj_type := PackedByteArray()

var _pending_edges: Array[PackedInt32Array] = []
var _edge_keys: Dictionary = {}


func count() -> int:
	return kind.size()


func material_name(i: int) -> StringName:
	return materials[mat[i]]


func is_glass(i: int) -> bool:
	return glass_mats[mat[i]] == 1


func volume(i: int) -> float:
	return D.shape_volume(dims[i], shape[i])


func add(k: int, r: int, material: StringName, size: Vector3, t: Transform3D, st: int, touches_ground: bool = false,
		cant: int = 1, shp: int = D.Shape.BOX) -> int:
	var i := kind.size()
	var mi := materials.find(material)
	if mi < 0:
		mi = materials.size()
		materials.append(material)
	kind.append(k)
	role.append(r)
	shape.append(shp)
	mat.append(mi)
	dims.append(size)
	xf.append(t)
	storey.append(st)
	anchor.append(1 if touches_ground else 0)
	cant_max.append(cant)
	_pending_edges.append(PackedInt32Array())
	return i


## upper rests on lower (lower carries upper).
func rests_on(upper: int, lower: int) -> void:
	_edge(upper, lower, D.Edge.RESTS_ON)
	_edge(lower, upper, D.Edge.CARRIES)


func lateral(a: int, b: int) -> void:
	_edge(a, b, D.Edge.LATERAL)
	_edge(b, a, D.Edge.LATERAL)


func attach(element: int, host: int) -> void:
	_edge(element, host, D.Edge.ATTACHED_TO)
	_edge(host, element, D.Edge.HOSTS)


func touch(a: int, b: int) -> void:
	_edge(a, b, D.Edge.TOUCH)
	_edge(b, a, D.Edge.TOUCH)


func _edge(a: int, b: int, t: int) -> void:
	if a < 0 or b < 0 or a == b:
		return
	var key := (a * 1048576 + b) * 8 + t
	if _edge_keys.has(key):
		return
	_edge_keys[key] = true
	_pending_edges[a].append(b * 8 + t)


## Builds the CSR adjacency and computes mass, HP and bounds. Call once after all add()/link calls.
func finalize() -> void:
	var n := count()
	adj_start.resize(n + 1)
	var total := 0
	for i in n:
		adj_start[i] = total
		total += _pending_edges[i].size()
	adj_start[n] = total
	adj_to.resize(total)
	adj_type.resize(total)
	var w := 0
	for i in n:
		for packed in _pending_edges[i]:
			adj_to[w] = packed >> 3
			adj_type[w] = packed & 7
			w += 1
	_pending_edges.clear()
	_edge_keys.clear()
	glass_mats.resize(materials.size())
	for mi in materials.size():
		glass_mats[mi] = 1 if MaterialDB.is_glass(materials[mi]) else 0
	mass.resize(n)
	max_hp.resize(n)
	var first := true
	for i in n:
		var m: StringName = materials[mat[i]]
		var v := volume(i)
		mass[i] = v * MaterialDB.density(m)
		max_hp[i] = MaterialDB.element_hp(m, v)
		var half := dims[i] * 0.5
		var box := xf[i] * AABB(-half, dims[i])
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)


func neighbours(i: int) -> PackedInt32Array:
	return adj_to.slice(adj_start[i], adj_start[i + 1])


func total_mass() -> float:
	var s := 0.0
	for m in mass:
		s += m
	return s
