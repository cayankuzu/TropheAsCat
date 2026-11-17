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
## The ends of LOD0, LOD1 and LOD2 in metres from the camera come from the graphics level
## (Perf.tree_lod_ends(): 70 / 170 / 520 m at High, 40 / 100 / 210 m in the browser demo); LOD_MARGIN is the
## hysteresis around each.
const LOD_MARGIN := 5.0

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
## In the browser demo plants are drawn in batches (2026-11-17): every species in every CHUNK x CHUNK square
## of the Table is one MultiMesh per LOD and per part of its model, instead of a MeshInstance3D for each part
## of every plant. A batch changes LOD as a whole, by the distance to its middle, so the LOD bands are pushed
## out by CHUNK_PAD. Nature never moves: build_batches() makes the visuals once, after the plants are placed.
const CHUNK := 40.0
const CHUNK_PAD := 14.0
var _pending := {}                    # species -> {Vector2i chunk: Array[Transform3D] (model frames)}
var _batches: Array[MultiMeshInstance3D] = []
var _batch_lod := PackedByteArray()
## The PC game draws every plant on its own (each LOD mesh with its own band): its street trees stand so far
## apart that batches cost more draw calls than they saved, in the shadow cascades above all (2026-11-17
## bench: 305 -> 705 at the landing spot). The browser demo batches (its title view: 286 -> 114).
var _lod_meshes: Array[MeshInstance3D] = []
var _lod_index := PackedByteArray()
var _clod_mesh: CylinderMesh
var _trunk_shapes := {}             # "radius/height" -> CylinderShape3D
var _clod_shapes := {}


func _ready() -> void:
	Perf.level_changed.connect(_on_level)
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
	# Under the ground it costs a draw call (and a shadow) for nothing: drawn only near, where digging can bare
	# it, and not at all where the ground cannot be dug (the browser demo).
	if not Game.lite:
		var clod := MeshInstance3D.new()
		clod.name = "Clod"
		clod.mesh = _clod_mesh
		clod.transform = Transform3D(Basis.from_scale(Vector3(clod_r, clod_h, clod_r)), Vector3(0.0, clod_top - clod_h * 0.5, 0.0))
		clod.visibility_range_end = 60.0
		clod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(clod)
	var clod_col := CollisionShape3D.new()
	clod_col.name = "ClodShape"
	clod_col.shape = _cylinder(_clod_shapes, clod_r * 0.8, clod_h)
	clod_col.position.y = clod_top - clod_h * 0.5
	body.add_child(clod_col)

	add_child(body)
	body.global_position = Vector3(at.x, ground, at.z)
	_queue_plant(species, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * k), Vector3(at.x, ground, at.z)))
	trees.append(body)
	return body


## One bush (no collider) on the ground at (at.x, at.z).
func add_bush(species: StringName, at: Vector3, yaw: float = 0.0, size: float = 1.0) -> Node3D:
	var info: Dictionary = BUSHES[species]
	var k := UNIT * float(info["size"]) * size
	var visual := Node3D.new()   # where it stands (the bush itself is drawn in its batch)
	visual.name = "%s_%d" % [species, bushes.size()]
	add_child(visual)
	var spot := Vector3(at.x, _ground(at.x, at.z), at.z)
	visual.global_position = spot
	_queue_plant(species, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * k), spot))
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


## A plant to draw: its model frame (yaw, scale, where it stands) goes into the batch of its species and chunk.
func _queue_plant(species: StringName, xf: Transform3D) -> void:
	var per: Dictionary = _pending.get(species, {})
	var key := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
	if not per.has(key):
		per[key] = []
	(per[key] as Array).append(xf)
	_pending[species] = per


## The batches of every plant placed since the last call: per species and chunk, a MultiMesh for each part
## of each LOD, its node in the middle of the chunk.
func build_batches() -> void:
	var ends := Perf.tree_lod_ends()
	if not Game.lite:
		for species: StringName in _pending:
			for key: Vector2i in _pending[species]:
				for xf: Transform3D in _pending[species][key]:
					_plant_visual(species, xf, ends)
		_pending.clear()
		return
	for species: StringName in _pending:
		var per: Dictionary = _pending[species]
		for key: Vector2i in per:
			var frames: Array = per[key]
			var centre := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
			for lod in 3:
				for part: Array in _lod_parts(species, lod):
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = part[0]
					mm.instance_count = frames.size()
					for i in frames.size():
						var xf: Transform3D = frames[i]
						mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre) * (part[1] as Transform3D))
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					mmi.lod_bias = 1.5   # the engine picks a mesh LOD for the whole batch by its middle
					mmi.name = "%s_%d_%d_L%d" % [species, key.x, key.y, lod]
					if lod == 2:
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # too far away to tell
					add_child(mmi)
					mmi.global_position = centre
					_set_band(mmi, lod, ends)
					_batches.append(mmi)
					_batch_lod.append(lod)
	_pending.clear()


## One plant drawn on its own: the three LODs of its model, each mesh inside its own distance band.
func _plant_visual(species: StringName, xf: Transform3D, ends: Array[float]) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	visual.global_transform = xf
	for lod in 3:
		for part: Array in _lod_parts(species, lod):
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			_set_mesh_band(mi, lod, ends)
			if lod == 2:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # too far away to tell
			visual.add_child(mi)
			_lod_meshes.append(mi)
			_lod_index.append(lod)


func _set_mesh_band(mi: MeshInstance3D, lod: int, ends: Array[float]) -> void:
	mi.visibility_range_begin = 0.0 if lod == 0 else ends[lod - 1]
	mi.visibility_range_begin_margin = LOD_MARGIN if lod > 0 else 0.0
	mi.visibility_range_end = ends[lod]
	mi.visibility_range_end_margin = LOD_MARGIN


func _set_band(mmi: MultiMeshInstance3D, lod: int, ends: Array[float]) -> void:
	mmi.visibility_range_begin = 0.0 if lod == 0 else ends[lod - 1] + CHUNK_PAD
	mmi.visibility_range_begin_margin = LOD_MARGIN if lod > 0 else 0.0
	mmi.visibility_range_end = ends[lod] + CHUNK_PAD
	mmi.visibility_range_end_margin = LOD_MARGIN


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


## The graphics level changed: the LOD bands of every batch move with it.
func _on_level(_level: int) -> void:
	var ends := Perf.tree_lod_ends()
	for i in _batches.size():
		_set_band(_batches[i], _batch_lod[i], ends)
	for i in _lod_meshes.size():
		_set_mesh_band(_lod_meshes[i], _lod_index[i], ends)
