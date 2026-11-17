class_name ElementLibrary
extends RefCounted
## Shared render meshes and collision shapes of intact elements, one per quantised size (and material
## for meshes). Meshes are built from the same plane set as fracture cells, so a fracture piece's
## outer faces coincide exactly with the intact element they replace.

static var _meshes: Dictionary = {}   # String -> ArrayMesh
static var _shapes: Dictionary = {}   # String -> Shape3D
static var _surface: Dictionary = {}  # StringName -> Material
static var _interior: Dictionary = {}


static func size_key(size: Vector3, shape: int) -> String:
	return "%d_%d_%d_%d" % [roundi(size.x * 1000.0), roundi(size.y * 1000.0), roundi(size.z * 1000.0), shape]


## Render material for the outer faces of elements and fracture pieces. MaterialDB's material, except
## two building-specific looks: tinted reflective window glass and dark anodised mullion metal.
static func surface_material(material: StringName) -> Material:
	var m: Material = _surface.get(material)
	if m != null:
		return m
	var base := MaterialDB.surface(material)
	if material == &"glass":
		var g := base.duplicate() as StandardMaterial3D
		g.albedo_color = Color(0.1, 0.13, 0.16, 0.6)
		g.metallic = 0.85
		g.roughness = 0.03
		g.metallic_specular = 1.0
		m = g
	elif material == &"steel":
		var s := base.duplicate() as StandardMaterial3D
		s.albedo_texture = null
		s.albedo_color = Color(0.13, 0.135, 0.145)
		s.metallic_texture = null
		s.metallic = 0.75
		s.roughness_texture = null
		s.roughness = 0.38
		m = s
	else:
		m = base
	_surface[material] = m
	return m


## Render material for faces created by fracture.
static func interior_material(material: StringName) -> Material:
	var m: Material = _interior.get(material)
	if m != null:
		return m
	if material == &"steel":
		var s := surface_material(material).duplicate() as StandardMaterial3D
		s.albedo_color = Color(0.42, 0.43, 0.45)
		s.roughness = 0.25
		m = s
	else:
		m = MaterialDB.interior(material)
	_interior[material] = m
	return m


static func mesh(size: Vector3, shape: int, material: StringName) -> ArrayMesh:
	var key := size_key(size, shape) + "|" + String(material)
	var m: ArrayMesh = _meshes.get(key)
	if m == null:
		var cell := ConvexBuilder.build(ConvexBuilder.shape_planes(size, shape), 99)
		var mat := surface_material(material)
		m = ConvexBuilder.make_mesh(cell, mat, mat)
		_meshes[key] = m
	return m


static func collision_shape(size: Vector3, shape: int) -> Shape3D:
	var key := size_key(size, shape)
	var s: Shape3D = _shapes.get(key)
	if s == null:
		if shape == DestructionDefs.Shape.PRISM:
			var cell := ConvexBuilder.build(ConvexBuilder.prism_planes(size), 99)
			var c := ConvexPolygonShape3D.new()
			c.points = cell["points"]
			s = c
		else:
			var b := BoxShape3D.new()
			b.size = size
			s = b
		_shapes[key] = s
	return s


static func mesh_count() -> int:
	return _meshes.size()
