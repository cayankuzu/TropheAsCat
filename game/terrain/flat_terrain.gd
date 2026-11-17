class_name FlatTerrain
extends Node3D
## The ground without Voxel Tools (2026-11-17), for builds where the voxel extension does not exist (the
## browser demo, whose platform has no build of it): the same slab as WorldTerrain (TerrainShape's heights,
## the cut at +-512 m, the bottom at -48 m) as one mesh with the strata shader and a HeightMapShape3D
## collider. It answers the queries the game makes of the ground the same way, but it cannot be dug:
## blasts leave their scorch marks and rubble, not craters, and there are no ground edits to save.
## main.gd makes it instead of WorldTerrain when ClassDB has no VoxelLodTerrain.

@warning_ignore("unused_signal")
signal terrain_edited(aabb: AABB)   ## never: this ground is not edited (same API as WorldTerrain)
@warning_ignore("unused_signal")
signal dug(center: Vector3, radius: float, layer: StringName)
signal edits_saved(path: String, ok: bool)
signal edits_loaded(path: String, ok: bool)

const WORLD_HALF := TerrainShape.WORLD_HALF
const WORLD_BOTTOM := TerrainShape.WORLD_BOTTOM
const MESH_STEP := 4                    ## metres between the mesh's height samples (the city is flat)

var _material: ShaderMaterial
var _mask_tex: ImageTexture
var _body: StaticBody3D


func _ready() -> void:
	process_priority = -10
	_build_material()
	_build_mesh()
	_build_collider()
	Game.terrain = self


func _enter_tree() -> void:
	if _body != null:
		Game.terrain = self


func _exit_tree() -> void:
	if Game.terrain == self:
		Game.terrain = null


# ---------------------------------------------------------------- queries (as WorldTerrain)

func get_layer_at(pos: Vector3) -> StringName:
	var i := TerrainStrata.layer_index_at(pos)
	if i == -1:
		return &"void"
	if i == -2:
		return &"air"
	return TerrainStrata.layer_name(i)


func is_lava_at(pos: Vector3) -> bool:
	return TerrainStrata.layer_index_at(pos) == TerrainStrata.LAVA or TerrainStrata.layer_index_at(pos + Vector3(0.0, -0.6, 0.0)) == TerrainStrata.LAVA


func get_resistance_at(pos: Vector3) -> float:
	return TerrainStrata.resistance_kj(TerrainStrata.layer_index_at(pos)) * 1000.0


func get_original_height(x: float, z: float) -> float:
	return TerrainShape.height_at(x, z)


## The slab's signed distance, as the voxel generator defines it (exact enough above the ground).
func sdf_at(pos: Vector3) -> float:
	var top := pos.y - TerrainShape.height_at(pos.x, pos.z)
	return maxf(maxf(top, WORLD_BOTTOM - pos.y), maxf(absf(pos.x) - WORLD_HALF, absf(pos.z) - WORLD_HALF))


func is_solid_at(pos: Vector3) -> bool:
	return sdf_at(pos) < 0.0


func sdf_normal(pos: Vector3) -> Vector3:
	var e := 0.5
	var g := Vector3(
		sdf_at(pos + Vector3(e, 0, 0)) - sdf_at(pos - Vector3(e, 0, 0)),
		sdf_at(pos + Vector3(0, e, 0)) - sdf_at(pos - Vector3(0, e, 0)),
		sdf_at(pos + Vector3(0, 0, e)) - sdf_at(pos - Vector3(0, 0, e)))
	return g.normalized() if g.length_squared() > 1e-8 else Vector3.UP


# ---------------------------------------------------------------- what WorldTerrain edits (nothing here)

func dig_sphere(_center: Vector3, _radius: float) -> void:
	pass


func add_sphere(_center: Vector3, _radius: float) -> void:
	pass


func dig_box(_box: AABB) -> void:
	pass


func flush_edits() -> void:
	pass


func pending_edits() -> int:
	return 0


func explode(_center: Vector3, _blast_radius: float, _energy_j: float) -> float:
	return 0.0


func receive_damage(_hit: DamageHit, _user_id: int) -> void:
	pass


func save_edits(path: String = "") -> bool:
	edits_saved.emit(path, true)
	return true


func load_edits(path: String = "") -> bool:
	edits_loaded.emit(path, true)
	return true


func add_collision_anchor(_node: Node3D, _radius_m: float = 48.0) -> void:
	pass


func remove_collision_anchor(_node: Node3D) -> void:
	pass


func get_stats() -> Dictionary:
	return {"flat": true, "edits": 0}


## image: 1 m per pixel over x, z in [-512, 512); R = road, G = sidewalk, B = grass (as WorldTerrain).
func set_surface_mask(image: Image, grid_markings: bool = false) -> void:
	var gpu := TerrainStrata.set_mask(image).duplicate() as Image
	gpu.generate_mipmaps()
	if _mask_tex == null or _mask_tex.get_size() != Vector2(gpu.get_size()):
		_mask_tex = ImageTexture.create_from_image(gpu)
	else:
		_mask_tex.update(gpu)
	if _material != null:
		_material.set_shader_parameter(&"u_mask", _mask_tex)
		_material.set_shader_parameter(&"u_grid_markings", grid_markings)


# ---------------------------------------------------------------- build

func _build_material() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://game/terrain/strata.gdshader")
	var tex := StrataTextureSet.load_textures()
	if not tex.is_empty():
		mat.set_shader_parameter(&"u_albedo", tex["albedo"])
		mat.set_shader_parameter(&"u_nrm", tex["nrm"])
		mat.set_shader_parameter(&"u_lava_emission", tex["lava_emission"])
	mat.set_shader_parameter(&"u_height", ImageTexture.create_from_image(TerrainShape.heightmap()))
	mat.set_shader_parameter(&"u_hm_offset", float(TerrainShape.HM_OFFSET))
	mat.set_shader_parameter(&"u_hm_size", float(TerrainShape.HM_SIZE))
	mat.set_shader_parameter(&"u_mask_size", float(TerrainStrata.MASK_SIZE))
	mat.set_shader_parameter(&"u_transition_mask", 0)
	var noise := TerrainStrata.noise_image().duplicate() as Image
	noise.generate_mipmaps()
	mat.set_shader_parameter(&"u_noise", ImageTexture.create_from_image(noise))
	var params := TerrainStrata.shader_layer_params()
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	_material = mat
	set_surface_mask(TerrainStrata.mask_image(), true)


## The top as a grid (MESH_STEP), the four cut faces down to the bottom, and the bottom.
func _build_mesh() -> void:
	var n := int(2.0 * WORLD_HALF / MESH_STEP) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		var z := -WORLD_HALF + float(j * MESH_STEP)
		for i in n:
			var x := -WORLD_HALF + float(i * MESH_STEP)
			var h := TerrainShape.height_at(x, z)
			verts[j * n + i] = Vector3(x, h, z)
			var dx := TerrainShape.height_at(x + 1.0, z) - TerrainShape.height_at(x - 1.0, z)
			var dz := TerrainShape.height_at(x, z + 1.0) - TerrainShape.height_at(x, z - 1.0)
			norms[j * n + i] = Vector3(-dx, 2.0, -dz).normalized()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# The cut faces: one strip per side, from the top edge down to the bottom.
	var sides := [
		[Vector3.FORWARD, func(k: int) -> int: return k],                     # z = -512, along x
		[Vector3.BACK, func(k: int) -> int: return (n - 1) * n + (n - 1 - k)],  # z = +512
		[Vector3.LEFT, func(k: int) -> int: return (n - 1 - k) * n],           # x = -512
		[Vector3.RIGHT, func(k: int) -> int: return k * n + (n - 1)],          # x = +512
	]
	for s: Array in sides:
		var normal: Vector3 = s[0]
		var at: Callable = s[1]
		var base := verts.size()
		for k in n:
			var top: Vector3 = verts[at.call(k)]
			verts.append(top)
			norms.append(normal)
			verts.append(Vector3(top.x, WORLD_BOTTOM, top.z))
			norms.append(normal)
		for k in n - 1:
			var a := base + k * 2
			idx.append_array([a, a + 1, a + 2, a + 2, a + 1, a + 3])
	var b := verts.size()
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		verts.append(Vector3(c.x * WORLD_HALF, WORLD_BOTTOM, c.y * WORLD_HALF))
		norms.append(Vector3.DOWN)
	idx.append_array([b, b + 2, b + 1, b, b + 3, b + 2])   # clockwise seen from below
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	# CUSTOM0 all zero: no Transvoxel transition data. The strata shader reads it, and OpenGL / WebGL give a
	# missing attribute w = 1, which reads as a transition cell and culls every vertex.
	var custom := PackedFloat32Array()
	custom.resize(verts.size() * 4)
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, _material)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	add_child(mi)


## 1 m cells over the slab, straight from the shared heightmap (pixel 8 is x = -512).
func _build_collider() -> void:
	var size := int(2.0 * WORLD_HALF) + 1
	var start := TerrainShape.HM_OFFSET - int(WORLD_HALF)
	var region := TerrainShape.heightmap().get_region(Rect2i(start, start, size, size))
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = region.get_data().to_float32_array()
	_body = StaticBody3D.new()
	_body.name = "GroundBody"
	_body.collision_layer = Layers.TERRAIN
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body.add_child(cs)
	add_child(_body)
