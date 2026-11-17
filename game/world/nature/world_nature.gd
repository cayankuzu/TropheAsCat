class_name WorldNature
extends Node3D
## The protected nature of the Table: street trees, groves and bushes (EZ-Tree models, three LODs each).
## Every tree is a StaticBody3D on Layers.PROTECTED in group "protected", so DamageRouter never harms
## it and answers with the CAT-PROOF feedback instead. A tree owns its clod of earth (the root ball,
## pinned to the Table by the Owner): blast or dig the ground away and the tree stays where it was,
## standing on its clod. Bushes have no collider; the cat walks through them.

const ROOT := "res://assets/models/nature/"
const SOIL_TEXTURE := "res://assets/textures/Ground048/Ground048_2K-JPG_Color.jpg"
## The models are authored at about 10 units per metre.
const UNIT := 0.1
## End of LOD0, LOD1 and LOD2 in metres from the camera; LOD_MARGIN is the hysteresis around each.
const LOD_END: Array[float] = [70.0, 170.0, 520.0]
const LOD_MARGIN := 5.0
const LOD_END_LITE: Array[float] = [40.0, 100.0, 210.0]   ## the lite build (browser demo)

## size = multiplier on UNIT; trunk = trunk radius and crown = height of the lowest leaves, in model units.
const TREES := {
	&"oak_large": {"size": 1.3, "trunk": 2.86, "crown": 18.7, "top": 108.0},
	&"oak_medium": {"size": 1.3, "trunk": 1.28, "crown": 12.4, "top": 72.0},
	&"ash_large": {"size": 1.3, "trunk": 2.85, "crown": 19.5, "top": 96.0},
	&"ash_medium": {"size": 1.2, "trunk": 1.88, "crown": 16.0, "top": 84.0},
	&"aspen_large": {"size": 1.1, "trunk": 1.05, "crown": 45.0, "top": 105.0},
	&"pine_large": {"size": 1.5, "trunk": 1.17, "crown": 5.8, "top": 68.5},
	&"pine_medium": {"size": 1.5, "trunk": 0.96, "crown": 5.8, "top": 51.0},
}
const BUSHES := {
	&"bush_1": {"size": 0.6},
	&"bush_2": {"size": 0.7},
	&"bush_3": {"size": 0.6},
}
const GROVE_TREES: Array[StringName] = [&"oak_large", &"ash_large", &"oak_medium", &"ash_medium", &"aspen_large", &"oak_medium", &"pine_large", &"pine_medium", &"aspen_large"]
const GROVE_BUSHES: Array[StringName] = [&"bush_1", &"bush_2", &"bush_3"]
## One species per avenue; which one depends on the road, so neighbouring streets differ.
const STREET_SPECIES: Array[StringName] = [&"ash_medium", &"oak_medium", &"aspen_large"]

## Distance of the street-tree line from the road centre (on the sidewalk, 16 m roads with 4 m sidewalks).
const STREET_OFFSET := 10.5
## Trees keep this far from any road centre line unless they are street trees.
const ROAD_CLEARANCE := 14.5

var trees: Array[StaticBody3D] = []
var bushes: Array[Node3D] = []

var _parts := {}                    # "species/lod" -> Array of [Mesh, Transform3D]
var _clod_mesh: CylinderMesh
var _trunk_shapes := {}             # "radius/height" -> CylinderShape3D
var _clod_shapes := {}


func _ready() -> void:
	# Built with the world: a new material variant costs a shader compile when it is created.
	var soil := StandardMaterial3D.new()
	soil.albedo_texture = load(SOIL_TEXTURE) as Texture2D
	soil.albedo_color = Color(0.72, 0.62, 0.52)
	soil.roughness = 1.0
	soil.uv1_triplanar = true
	soil.uv1_world_triplanar = true
	soil.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_clod_mesh = CylinderMesh.new()
	_clod_mesh.top_radius = 1.0
	_clod_mesh.bottom_radius = 0.45
	_clod_mesh.height = 1.0
	_clod_mesh.radial_segments = 12
	_clod_mesh.rings = 2
	_clod_mesh.material = soil


func tree_count() -> int:
	return trees.size()


## Files this class reads (the composition root asks worker threads for them ahead of time).
static func model_paths() -> PackedStringArray:
	var paths := PackedStringArray([SOIL_TEXTURE])
	for species: StringName in TREES.keys() + BUSHES.keys():
		for lod in 3:
			paths.append("%s%s/tree_LOD%d.glb" % [ROOT, species, lod])
	return paths


## One protected tree standing on the ground at (at.x, at.z). size multiplies the species' own size.
func add_tree(species: StringName, at: Vector3, yaw: float = 0.0, size: float = 1.0) -> StaticBody3D:
	var info: Dictionary = TREES[species]
	var k := UNIT * float(info["size"]) * size
	var ground := _ground(at.x, at.z)
	var body := StaticBody3D.new()
	body.name = "%s_%d" % [species, trees.size()]
	body.collision_layer = Layers.PROTECTED
	body.collision_mask = 0
	body.add_to_group(&"protected")
	body.set_meta(&"species", species)

	# Trunk: a cylinder up into the crown, so the cat can climb well past the lowest leaves.
	var trunk_r := maxf(float(info["trunk"]) * k * 1.1, 0.14)
	var trunk_h := lerpf(float(info["crown"]), float(info["top"]), 0.45) * k
	var trunk := CollisionShape3D.new()
	trunk.name = "Trunk"
	trunk.shape = _cylinder(_trunk_shapes, trunk_r, trunk_h)
	trunk.position.y = trunk_h * 0.5
	body.add_child(trunk)

	# The clod: hidden just under the surface until the ground around it is gone.
	var clod_r := clampf(trunk_r * 3.2, 0.7, 1.5)
	var clod_h := clod_r * 1.8
	var low := ground
	for i in 4:
		var a := TAU * i / 4.0
		low = minf(low, _ground(at.x + cos(a) * clod_r, at.z + sin(a) * clod_r))
	var clod_top := low - ground - 0.08
	var clod := MeshInstance3D.new()
	clod.name = "Clod"
	clod.mesh = _clod_mesh
	clod.transform = Transform3D(Basis.from_scale(Vector3(clod_r, clod_h, clod_r)), Vector3(0.0, clod_top - clod_h * 0.5, 0.0))
	body.add_child(clod)
	var clod_col := CollisionShape3D.new()
	clod_col.name = "ClodShape"
	clod_col.shape = _cylinder(_clod_shapes, clod_r * 0.8, clod_h)
	clod_col.position.y = clod_top - clod_h * 0.5
	body.add_child(clod_col)

	body.add_child(_plant_visual(species, k, yaw))
	add_child(body)
	body.global_position = Vector3(at.x, ground, at.z)
	trees.append(body)
	return body


## One bush (no collider) on the ground at (at.x, at.z).
func add_bush(species: StringName, at: Vector3, yaw: float = 0.0, size: float = 1.0) -> Node3D:
	var info: Dictionary = BUSHES[species]
	var visual := _plant_visual(species, UNIT * float(info["size"]) * size, yaw)
	visual.name = "%s_%d" % [species, bushes.size()]
	add_child(visual)
	visual.global_position = Vector3(at.x, _ground(at.x, at.z), at.z)
	bushes.append(visual)
	return visual


## Avenue trees on both sidewalks of the given roads, one species per road, leaving the crossings open.
## `lines` holds the offsets of the road centre lines; every offset stands for one road along x and one
## along z (the default is the two central roads). Returns how many were planted.
func add_street_trees(half_extent: float = 200.0, spacing: float = 24.0, seed_value: int = 7, lines: PackedFloat32Array = PackedFloat32Array([0.0])) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var road_spacing := float(TerrainStrata.ROAD_SPACING)
	var planted := 0
	var n := int(half_extent / spacing)
	for axis in 2:
		for line in lines:
			var species := STREET_SPECIES[posmod(axis + int(roundf(line / road_spacing)), STREET_SPECIES.size())]
			for i in range(-n, n + 1):
				var along := i * spacing
				# Keep the crossings with the other roads open.
				var to_crossing := absf(along - roundf(along / road_spacing) * road_spacing)
				if to_crossing < 16.0:
					continue
				for side: float in [-1.0, 1.0]:
					var across := line + side * STREET_OFFSET
					var p := Vector3(along, 0.0, across) if axis == 0 else Vector3(across, 0.0, along)
					add_tree(species, p, rng.randf() * TAU, rng.randf_range(0.9, 1.1))
					planted += 1
	return planted


## One block of park: three groves with bushes around an open lawn. Returns how many trees were planted.
func add_park_block(center: Vector3, seed_value: int) -> int:
	var planted := 0
	planted += add_grove(center + Vector3(-25.0, 0.0, -23.0), 20.0, 14, seed_value, false)
	planted += add_grove(center + Vector3(27.0, 0.0, -5.0), 18.0, 12, seed_value + 1, false)
	planted += add_grove(center + Vector3(-7.0, 0.0, 29.0), 19.0, 13, seed_value + 2, false)
	return planted


## A small wood: up to `count` trees scattered in a disc, big ones near the middle, with bushes around
## the rim. Spots on roads, sidewalks or building lots are skipped (pass check_lots = false where there
## are no buildings: the check looks at every building). Returns how many trees were planted.
func add_grove(center: Vector3, radius: float, count: int, seed_value: int, check_lots: bool = true) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < count and tries < count * 30:
		tries += 1
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		var p := Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)
		if not is_free(p, 3.0, check_lots):
			continue
		var ok := true
		for q in spots:
			if q.distance_to(p) < 4.6:
				ok = false
				break
		if ok:
			spots.append(p)
	for p in spots:
		var central := p.distance_to(Vector3(center.x, 0.0, center.z)) < radius * 0.45
		var species: StringName = GROVE_TREES[rng.randi_range(0, 1)] if central else GROVE_TREES[rng.randi_range(2, GROVE_TREES.size() - 1)]
		add_tree(species, p, rng.randf() * TAU, rng.randf_range(0.85, 1.15))
	for i in int(count * 0.8):
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.55, 1.1)
		var p := Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)
		if not is_free(p, 1.5, check_lots):
			continue
		var near_trunk := false
		for q in spots:
			if q.distance_to(p) < 1.6:
				near_trunk = true
				break
		if not near_trunk:
			add_bush(GROVE_BUSHES[rng.randi_range(0, GROVE_BUSHES.size() - 1)], p, rng.randf() * TAU, rng.randf_range(0.8, 1.25))
	return spots.size()


## True when the spot is lawn: off the roads and sidewalks and at least `margin` metres clear of every
## building lot known to Game.structures.
func is_free(at: Vector3, margin: float, check_lots: bool = true) -> bool:
	var road_spacing := float(TerrainStrata.ROAD_SPACING)
	if absf(at.x - roundf(at.x / road_spacing) * road_spacing) < ROAD_CLEARANCE:
		return false
	if absf(at.z - roundf(at.z / road_spacing) * road_spacing) < ROAD_CLEARANCE:
		return false
	var structures := Game.structures as StructureManager
	if check_lots and structures != null:
		var p := Vector2(at.x, at.z)
		for bid in structures.building_count():
			if structures.building_footprint(bid).grow(margin).has_point(p):
				return false
	return true


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0


## The three LODs of a plant under one node; each mesh shows only inside its own distance band.
func _plant_visual(species: StringName, k: float, yaw: float) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * k), Vector3.ZERO)
	var ends: Array[float] = LOD_END if not Game.lite else LOD_END_LITE
	for lod in 3:
		var begin := 0.0 if lod == 0 else ends[lod - 1]
		for part: Array in _lod_parts(species, lod):
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			mi.visibility_range_begin = begin
			mi.visibility_range_begin_margin = LOD_MARGIN if lod > 0 else 0.0
			mi.visibility_range_end = ends[lod]
			mi.visibility_range_end_margin = LOD_MARGIN
			if lod == 2:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # too far away to tell
			visual.add_child(mi)
	return visual


## Meshes of one LOD file, loaded once: an Array of [Mesh, Transform3D relative to the model root].
func _lod_parts(species: StringName, lod: int) -> Array:
	var key := "%s/%d" % [species, lod]
	if _parts.has(key):
		return _parts[key]
	var parts := []
	var scene := load("%s%s/tree_LOD%d.glb" % [ROOT, species, lod]) as PackedScene
	if scene != null:
		var root := scene.instantiate() as Node3D
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var xf := mi.transform
			var parent := mi.get_parent() as Node3D
			while parent != null and parent != root:
				xf = parent.transform * xf
				parent = parent.get_parent() as Node3D
			parts.append([mi.mesh, xf])
		root.free()
	_parts[key] = parts
	return parts


static func _cylinder(cache: Dictionary, radius: float, height: float) -> CylinderShape3D:
	var key := "%.2f/%.1f" % [radius, height]
	if cache.has(key):
		return cache[key]
	var shape := CylinderShape3D.new()
	shape.radius = snappedf(radius, 0.01)
	shape.height = snappedf(height, 0.1)
	cache[key] = shape
	return shape
