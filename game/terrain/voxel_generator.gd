extends RefCounted
## The Voxel Tools generator of the slab (moved out of TerrainShape on 2026-11-17 so that TerrainShape, which
## every system uses for heights, never names a Voxel Tools class: builds without the extension, such as the
## browser demo, can then load it). Only WorldTerrain preloads this file.
##
## SDF (in voxel units) = max(y - h(x,z), WORLD_BOTTOM - y, |x| - 512, |z| - 512).
## voxel_size = metres per voxel (the VoxelLodTerrain node is scaled by it); y_offset = the node's world y.


static func build(voxel_size: float, y_offset: float = 0.0) -> VoxelGeneratorGraph:
	var g := VoxelGeneratorGraph.new()
	var f := g.get_main_function()
	var ix := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var iy := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
	var iz := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
	var wx := _mul(f, ix, voxel_size)
	var wy := _add(f, _mul(f, iy, voxel_size), y_offset)
	var wz := _mul(f, iz, voxel_size)
	var px := _add(f, wx, float(TerrainShape.HM_OFFSET))
	var pz := _add(f, wz, float(TerrainShape.HM_OFFSET))
	var img := f.create_node(VoxelGraphFunction.NODE_IMAGE_2D, Vector2())
	f.set_node_param(img, 0, TerrainShape.heightmap())
	f.set_node_param(img, 1, 1)   # bilinear
	f.add_connection(px, 0, img, 0)
	f.add_connection(pz, 0, img, 1)
	var top := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2())
	f.add_connection(wy, 0, top, 0)
	f.add_connection(img, 0, top, 1)
	var bottom := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2())
	f.set_node_default_input(bottom, 0, TerrainShape.WORLD_BOTTOM)
	f.add_connection(wy, 0, bottom, 1)
	var side_x := _add(f, _abs(f, wx), -TerrainShape.WORLD_HALF)
	var side_z := _add(f, _abs(f, wz), -TerrainShape.WORLD_HALF)
	var m := _max(f, _max(f, top, bottom), _max(f, side_x, side_z))
	var sdf := _mul(f, m, 1.0 / voxel_size)
	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	f.add_connection(sdf, 0, out, 0)
	var res: Dictionary = g.compile()
	if not res.get("success", false):
		push_error("VoxelGenerator: generator graph failed to compile: %s" % res)
	return g


static func _mul(f: VoxelGraphFunction, src: int, k: float) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2())
	f.add_connection(src, 0, n, 0)
	f.set_node_default_input(n, 1, k)
	return n


static func _add(f: VoxelGraphFunction, src: int, k: float) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2())
	f.add_connection(src, 0, n, 0)
	f.set_node_default_input(n, 1, k)
	return n


static func _abs(f: VoxelGraphFunction, src: int) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_ABS, Vector2())
	f.add_connection(src, 0, n, 0)
	return n


static func _max(f: VoxelGraphFunction, a: int, b: int) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_MAX, Vector2())
	f.add_connection(a, 0, n, 0)
	f.add_connection(b, 0, n, 1)
	return n
