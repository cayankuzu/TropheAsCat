class_name TerrainShape
extends RefCounted
## The ORIGINAL ground surface of the slab (the voxel generator built from it is voxel_generator.gd, so
## that this file names no Voxel Tools class and loads where the extension does not exist).
##
## One heightmap Image (1 m per pixel, float) is the single source of truth for the surface height:
## the VoxelGeneratorGraph samples it (Image node, bilinear), the strata shader samples it (texelFetch +
## the same bilinear), and gameplay queries sample it on the CPU. All three agree to float precision.
##
## Shape: flat city plateau at y = 0, hills up to ~40 m in the outer ring, vertical cut at |x|,|z| = 512,
## flat bottom at y = -48. Nothing exists outside (the void).

const WORLD_HALF := 512.0
const WORLD_BOTTOM := -48.0

## Pixel (i, j) of the heightmap holds the height at world (x, z) = (i - HM_OFFSET, j - HM_OFFSET).
## The 8 m margin beyond the slab keeps bilinear lookups just outside the cut consistent.
const HM_OFFSET := 520
const HM_SIZE := 1041

const PLATEAU_EDGE := 414.0    ## Rounded-square radius where hills start (+- noise).
const PLATEAU_EDGE_NOISE := 8.0
const CORNER_ROUNDING := 8.0   ## Smooth-max k: rounds the plateau corners by up to k*ln2 = 5.5 m.
const HILLS_FULL := 504.0      ## Radius where hills reach their full height.
const HILL_HEIGHT := 46.0      ## Noise keeps the highest hill at about 40 m.
const CITY_HALF := 396.0       ## Guaranteed exactly flat inside this square (default road grid ends here).

static var _heightmap: Image = null
static var _hm_data: PackedFloat32Array


## The shared heightmap (FORMAT_RF, HM_SIZE^2). Built once per process (~0.1 s).
static func heightmap() -> Image:
	if _heightmap == null:
		_heightmap = _compute_heightmap()
		_hm_data = _heightmap.get_data().to_float32_array()
	return _heightmap


## Original surface height at world (x, z), bilinear exactly like the generator's Image node.
static func height_at(x: float, z: float) -> float:
	if _heightmap == null:
		heightmap()
	var px := clampf(x + HM_OFFSET, 0.0, HM_SIZE - 1.001)
	var pz := clampf(z + HM_OFFSET, 0.0, HM_SIZE - 1.001)
	var x0 := int(px)
	var z0 := int(pz)
	var fx := px - x0
	var fz := pz - z0
	var i := z0 * HM_SIZE + x0
	var a := lerpf(_hm_data[i], _hm_data[i + 1], fx)
	var b := lerpf(_hm_data[i + HM_SIZE], _hm_data[i + HM_SIZE + 1], fx)
	return lerpf(a, b, fz)


static func is_inside_slab_xz(x: float, z: float) -> bool:
	return absf(x) <= WORLD_HALF and absf(z) <= WORLD_HALF


static func _smooth_max(a: float, b: float, k: float) -> float:
	var m := maxf(a, b)
	return m + k * log(exp((a - m) / k) + exp((b - m) / k))


static func _compute_heightmap() -> Image:
	var edge := FastNoiseLite.new()
	edge.seed = 1107
	edge.frequency = 1.0 / 170.0
	edge.fractal_octaves = 2
	var hills := FastNoiseLite.new()
	hills.seed = 2311
	hills.frequency = 1.0 / 150.0
	hills.fractal_octaves = 4
	var ridges := FastNoiseLite.new()
	ridges.seed = 3719
	ridges.frequency = 1.0 / 95.0
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 3
	# Hills are low frequency: evaluate on a 2 m grid, then cubic-upsample natively.
	var step := 2.0
	@warning_ignore("integer_division")
	var n := (HM_SIZE + 1) / 2
	var coarse := PackedFloat32Array()
	coarse.resize(n * n)
	var inner_min := PLATEAU_EDGE - PLATEAU_EDGE_NOISE - 8.0
	for j in n:
		var z := float(j) * step - HM_OFFSET
		var az := absf(z)
		for i in n:
			var x := float(i) * step - HM_OFFSET
			var ax := absf(x)
			if maxf(ax, az) < inner_min:
				continue
			var r := _smooth_max(ax, az, CORNER_ROUNDING)
			var inner := PLATEAU_EDGE + PLATEAU_EDGE_NOISE * edge.get_noise_2d(x, z)
			if r <= inner:
				continue
			var t := smoothstep(inner, HILLS_FULL, r)
			var shape := 0.62 + 0.28 * hills.get_noise_2d(x, z) + 0.10 * ridges.get_noise_2d(x, z)
			coarse[j * n + i] = HILL_HEIGHT * t * clampf(shape, 0.2, 1.0)
	# Cubic upsampling of an all-zero neighbourhood is exactly zero, so the city stays exactly flat as long
	# as the hills start more than two coarse pixels (4 m) outside CITY_HALF (checked by the tests).
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, coarse.to_byte_array())
	img.resize(HM_SIZE, HM_SIZE, Image.INTERPOLATE_CUBIC)
	return img

