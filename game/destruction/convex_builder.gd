class_name ConvexBuilder
extends RefCounted
## Convex polyhedron utilities shared by intact element meshes and fracture cells.
## Planes use Godot's convention: outward normals, a point is inside when distance_to(p) <= 0.
## Pure math on packed arrays, safe to run on worker threads.

const ON_PLANE_EPS := 1e-3
const MERGE_EPS_SQ := 1e-8


static func box_planes(size: Vector3) -> Array[Plane]:
	var h := size * 0.5
	return [Plane(Vector3.RIGHT, h.x), Plane(Vector3.LEFT, h.x), Plane(Vector3.UP, h.y),
		Plane(Vector3.DOWN, h.y), Plane(Vector3.BACK, h.z), Plane(Vector3.FORWARD, h.z)]


## Gable prism: triangle (-hx,-hy) (hx,-hy) (0,hy) in local XY, extruded along Z.
static func prism_planes(size: Vector3) -> Array[Plane]:
	var h := size * 0.5
	var nl := Vector3(-2.0 * h.y, h.x, 0.0).normalized()
	var nr := Vector3(2.0 * h.y, h.x, 0.0).normalized()
	return [Plane(nl, nl.dot(Vector3(-h.x, -h.y, 0.0))), Plane(nr, nr.dot(Vector3(h.x, -h.y, 0.0))),
		Plane(Vector3.DOWN, h.y), Plane(Vector3.BACK, h.z), Plane(Vector3.FORWARD, h.z)]


static func shape_planes(size: Vector3, shape: int) -> Array[Plane]:
	return prism_planes(size) if shape == DestructionDefs.Shape.PRISM else box_planes(size)


## Builds the faces of the polyhedron bounded by planes. Faces lying on planes[0 .. n_orig-1] go to the
## "surface" arrays, the others (fracture planes) to the "interior" arrays. Triangles are emitted
## clockwise seen from outside (Godot front faces).
## Returns {} on degenerate input, else keys: sv, sn, iv, in, points, centroid, volume, aabb.
static func build(planes: Array[Plane], n_orig: int) -> Dictionary:
	var raw := Geometry3D.compute_convex_mesh_points(planes)
	var pts := PackedVector3Array()
	for p in raw:
		var dup := false
		for q in pts:
			if p.distance_squared_to(q) < MERGE_EPS_SQ:
				dup = true
				break
		if not dup:
			pts.append(p)
	if pts.size() < 4:
		return {}
	var o := Vector3.ZERO
	for p in pts:
		o += p
	o /= float(pts.size())
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	var iv := PackedVector3Array()
	var inn := PackedVector3Array()
	var volume := 0.0
	var cen := Vector3.ZERO
	var idx := PackedInt32Array()
	var ang := PackedFloat32Array()
	for pi in planes.size():
		var pl: Plane = planes[pi]
		idx.clear()
		for vi in pts.size():
			if absf(pl.distance_to(pts[vi])) < ON_PLANE_EPS:
				idx.append(vi)
		var k := idx.size()
		if k < 3:
			continue
		var c := Vector3.ZERO
		for vi in idx:
			c += pts[vi]
		c /= float(k)
		var u := pts[idx[0]] - c
		if u.length_squared() < 1e-12:
			continue
		u = u.normalized()
		var w := pl.normal.cross(u)
		ang.resize(k)
		for a in k:
			var r := pts[idx[a]] - c
			ang[a] = atan2(r.dot(w), r.dot(u))
		# Insertion sort by angle (k is small).
		for a in range(1, k):
			var av := ang[a]
			var ai := idx[a]
			var b := a - 1
			while b >= 0 and ang[b] > av:
				ang[b + 1] = ang[b]
				idx[b + 1] = idx[b]
				b -= 1
			ang[b + 1] = av
			idx[b + 1] = ai
		var p0 := pts[idx[0]]
		var surface := pi < n_orig
		for t in range(1, k - 1):
			var p1 := pts[idx[t + 1]]
			var p2 := pts[idx[t]]
			if surface:
				sv.append(p0)
				sv.append(p1)
				sv.append(p2)
				sn.append(pl.normal)
				sn.append(pl.normal)
				sn.append(pl.normal)
			else:
				iv.append(p0)
				iv.append(p1)
				iv.append(p2)
				inn.append(pl.normal)
				inn.append(pl.normal)
				inn.append(pl.normal)
			var tv := absf((p0 - o).dot((p1 - o).cross(p2 - o))) / 6.0
			volume += tv
			cen += tv * (o + p0 + p1 + p2) * 0.25
	if volume <= 1e-9:
		return {}
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return {"sv": sv, "sn": sn, "iv": iv, "in": inn, "points": pts, "centroid": cen / volume, "volume": volume, "aabb": box}


## Main-thread helper: ArrayMesh with up to two surfaces (outer faces, broken faces).
static func make_mesh(cell: Dictionary, surface_mat: Material, interior_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var sv: PackedVector3Array = cell["sv"]
	var iv: PackedVector3Array = cell["iv"]
	if sv.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = sv
		arr[Mesh.ARRAY_NORMAL] = cell["sn"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, surface_mat)
	if iv.size() > 0:
		var arr2 := []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = iv
		arr2[Mesh.ARRAY_NORMAL] = cell["in"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
		mesh.surface_set_material(mesh.get_surface_count() - 1, interior_mat)
	return mesh
