class_name TerrainStrata
extends RefCounted
## Ground layers: what is where, how hard it is to dig, and how it looks.
##
## The CPU classification below and strata.gdshader implement the same function (same constants, same
## noise image, same heightmap), so get_layer_at() names what the player sees.
##
## Depth model (d = depth below the ORIGINAL surface, h = original surface height):
##   skin     0 .. SKIN[surface]          asphalt / paving / grass, from the surface mask
##   base     skin .. 1.5                 gravel under roads and sidewalks, soil under grass
##   soil     1.5 .. 8
##   clay     8 .. 14
##   sand     14 .. 20                    (aquifer)
##   rock     20 .. y = -38               shallow layers follow the surface, deep ones are horizontal,
##   rock_deep  y = -38 .. -44            so under the flat city this is exactly 20-38 / 38-44 / 44-47 m
##   lava     y = -44 .. -47              and under the hills the rock is simply thicker.
##   bedrock  y = -47 .. -48              underside of the slab
## Every boundary is displaced by noise (BOUND_AMP large-scale, BOUND_JIT small-scale).

enum { GRASS, ASPHALT, PAVING, GRAVEL, SOIL, CLAY, SAND, ROCK, ROCK_DEEP, LAVA, BEDROCK }
const LAYER_COUNT := 11
const NAMES: Array[StringName] = [&"grass", &"asphalt", &"paving", &"gravel", &"soil", &"clay", &"sand", &"rock", &"rock_deep", &"lava", &"bedrock"]

## Texture array slots (ambientCG ids). BEDROCK reuses ROCK_DEEP's slot with its own tint.
const TEX_IDS: Array[String] = ["Grass005", "Asphalt033", "PavingStones142", "Gravel043", "Ground048", "Clay005", "Ground054", "Rock064", "Rock058", "Lava004"]
const TEX_SLOT: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 8]
const TILE_M: Array[float] = [3.2, 4.0, 2.6, 2.2, 3.0, 4.0, 3.0, 6.0, 7.0, 6.0, 9.0]
const NORMAL_STRENGTH: Array[float] = [0.8, 1.0, 1.0, 1.0, 1.0, 0.9, 0.9, 1.0, 1.1, 0.8, 1.0]
const ROUGHNESS_MUL: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 0.95, 1.0, 1.0, 0.95, 0.85, 1.0]
const TINT: Array[Color] = [
	Color(0.78, 0.86, 0.66), Color(0.82, 0.82, 0.84), Color(0.96, 0.95, 0.92), Color(0.66, 0.63, 0.58),
	Color(1.0, 0.95, 0.92), Color(0.98, 0.9, 0.82), Color(1.0, 0.97, 0.9), Color(0.94, 0.92, 0.88),
	Color(0.62, 0.6, 0.6), Color(1.0, 1.0, 1.0), Color(0.22, 0.2, 0.2),
]

## Energy to excavate one cubic metre, kJ (same scale as MaterialDB toughness: concrete = 60).
const RESISTANCE_KJ: Array[float] = [12.0, 40.0, 30.0, 22.0, 16.0, 28.0, 12.0, 120.0, 220.0, 8.0, 400.0]

const SKIN_ROAD := 0.22
const SKIN_SIDEWALK := 0.16
const SKIN_GRASS := 0.30
## Boundaries 0..3 are depths below the original surface, 4..6 are absolute heights.
const BOUND_DEPTH: Array[float] = [1.5, 8.0, 14.0, 20.0]
const BOUND_Y: Array[float] = [-38.0, -44.0, -47.0]
const BOUND_AMP: Array[float] = [0.25, 1.2, 1.0, 1.6, 1.5, 0.6, 0.3]
const BOUND_JIT: Array[float] = [0.08, 0.3, 0.25, 0.35, 0.4, 0.2, 0.12]
const NOISE_TILE_M := 160.0       ## Large-scale boundary noise repeats every 160 m.
const NOISE_FINE_SCALE := 6.0     ## Fine jitter uses the same image 6x smaller.
const NOISE_SIZE := 256

## Surface mask: 1 m per pixel, pixel (i, j) covers world x in [i - 512, i - 511), same for z.
## R = road, G = sidewalk, B = grass, A = 255, or 0 where car park bays are painted (CityLayout).
const MASK_SIZE := 1024
const ROAD_SPACING := 128
const ROAD_HALF_WIDTH := 8
const SIDEWALK_WIDTH := 4

static var _noise: Image = null
static var _noise_data: PackedByteArray
static var _mask: Image = null
static var _mask_data: PackedByteArray


static func layer_name(index: int) -> StringName:
	return NAMES[index] if index >= 0 and index < LAYER_COUNT else &""


static func resistance_kj(index: int) -> float:
	return RESISTANCE_KJ[index] if index >= 0 and index < LAYER_COUNT else 0.0


## Seamless RGBA8 noise shared by the shader (u_noise) and the CPU classification.
static func noise_image() -> Image:
	if _noise == null:
		var data := PackedByteArray()
		data.resize(NOISE_SIZE * NOISE_SIZE * 4)
		var channels: Array[PackedByteArray] = []
		var specs := [[401, 3.0, 3], [523, 7.0, 3], [647, 11.0, 2], [769, 2.0, 4]]   # seed, features per tile, octaves
		for s in specs:
			var n := FastNoiseLite.new()
			n.seed = s[0]
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = float(s[1]) / NOISE_SIZE
			n.fractal_octaves = s[2]
			var im := n.get_seamless_image(NOISE_SIZE, NOISE_SIZE, false, false, 0.1, true)
			im.convert(Image.FORMAT_L8)
			channels.append(im.get_data())
		for i in NOISE_SIZE * NOISE_SIZE:
			data[i * 4] = channels[0][i]
			data[i * 4 + 1] = channels[1][i]
			data[i * 4 + 2] = channels[2][i]
			data[i * 4 + 3] = channels[3][i]
		_noise = Image.create_from_data(NOISE_SIZE, NOISE_SIZE, false, Image.FORMAT_RGBA8, data)
		_noise_data = data
	return _noise


## Default mask: 16 m roads every 128 m with 4 m sidewalks on the flat plateau, grass elsewhere.
static func default_mask() -> Image:
	var im := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8)
	im.fill(Color8(0, 0, 255, 255))
	@warning_ignore("integer_division")
	var half := MASK_SIZE / 2
	var reach := int(TerrainShape.CITY_HALF)
	var span := Rect2i(half - reach, 0, 2 * reach, 0)
	var lines: Array[int] = []
	@warning_ignore("integer_division")
	var c := -(reach / ROAD_SPACING) * ROAD_SPACING
	while c <= reach:
		lines.append(c)
		c += ROAD_SPACING
	var sw := ROAD_HALF_WIDTH + SIDEWALK_WIDTH
	for pass_i in 2:
		var w := sw if pass_i == 0 else ROAD_HALF_WIDTH
		var col := Color8(0, 255, 0, 255) if pass_i == 0 else Color8(255, 0, 0, 255)
		for line in lines:
			var a := half + line - w
			im.fill_rect(Rect2i(a, span.position.x, 2 * w, span.size.x), col)   # road along z
			im.fill_rect(Rect2i(span.position.x, a, span.size.x, 2 * w), col)   # road along x
	return im


static func set_mask(image: Image) -> Image:
	var im := image.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != MASK_SIZE or im.get_height() != MASK_SIZE:
		im.resize(MASK_SIZE, MASK_SIZE, Image.INTERPOLATE_NEAREST)
	_mask = im
	_mask_data = im.get_data()
	return im


static func mask_image() -> Image:
	if _mask == null:
		set_mask(default_mask())
	return _mask


## Bilinear mask sample (matches the GPU's linear filter with clamp-to-edge). x = road, y = sidewalk, z = grass.
static func mask_at(x: float, z: float) -> Vector3:
	if _mask == null:
		mask_image()
	var px := clampf(x + MASK_SIZE * 0.5 - 0.5, 0.0, MASK_SIZE - 1.001)
	var pz := clampf(z + MASK_SIZE * 0.5 - 0.5, 0.0, MASK_SIZE - 1.001)
	var x0 := int(px)
	var z0 := int(pz)
	var fx := px - x0
	var fz := pz - z0
	var out := Vector3.ZERO
	for c in 3:
		var i := (z0 * MASK_SIZE + x0) * 4 + c
		var a := lerpf(_mask_data[i], _mask_data[i + 4], fx)
		var b := lerpf(_mask_data[i + MASK_SIZE * 4], _mask_data[i + MASK_SIZE * 4 + 4], fx)
		out[c] = lerpf(a, b, fz) / 255.0
	return out


## Repeating bilinear noise sample in [0, 1]; uv in tiles (1.0 = one image).
static func noise_at(u: float, v: float, channel: int) -> float:
	if _noise == null:
		noise_image()
	var px := fposmod(u * NOISE_SIZE - 0.5, float(NOISE_SIZE))
	var pz := fposmod(v * NOISE_SIZE - 0.5, float(NOISE_SIZE))
	var x0 := int(px) % NOISE_SIZE
	var z0 := int(pz) % NOISE_SIZE
	var x1 := (x0 + 1) % NOISE_SIZE
	var z1 := (z0 + 1) % NOISE_SIZE
	var fx := px - floorf(px)
	var fz := pz - floorf(pz)
	var a := lerpf(_noise_data[(z0 * NOISE_SIZE + x0) * 4 + channel], _noise_data[(z0 * NOISE_SIZE + x1) * 4 + channel], fx)
	var b := lerpf(_noise_data[(z1 * NOISE_SIZE + x0) * 4 + channel], _noise_data[(z1 * NOISE_SIZE + x1) * 4 + channel], fx)
	return lerpf(a, b, fz) / 255.0


## Offset (m) of boundary i at world (x, z). Mirrors boundary_offset() in strata.gdshader.
static func boundary_offset(i: int, x: float, z: float) -> float:
	var su := fposmod(0.173 * (i + 1), 1.0)
	var sv := fposmod(0.311 * (i + 1), 1.0)
	var u := x / NOISE_TILE_M + su
	var v := z / NOISE_TILE_M + sv
	var large := noise_at(u, v, 0)
	var fine := noise_at(u * NOISE_FINE_SCALE, v * NOISE_FINE_SCALE, 2)
	return BOUND_AMP[i] * (2.0 * large - 1.0) + BOUND_JIT[i] * (2.0 * fine - 1.0)


## Depth (below the original surface) of boundary i at (x, z) with its noise. h = original surface height.
static func boundary_depth(i: int, x: float, z: float, h: float) -> float:
	var nominal := BOUND_DEPTH[i] if i < 4 else h - BOUND_Y[i - 4]
	return nominal + boundary_offset(i, x, z)


## Layer index at a world position by geology (ignores whether it was dug out).
## Returns -1 outside the slab (void) and -2 above the original surface (air).
static func layer_index_at(pos: Vector3) -> int:
	if not TerrainShape.is_inside_slab_xz(pos.x, pos.z) or pos.y < TerrainShape.WORLD_BOTTOM:
		return -1
	var h := TerrainShape.height_at(pos.x, pos.z)
	var d := h - pos.y
	if d < 0.0:
		return -2
	var m := mask_at(pos.x, pos.z)
	var surface := GRASS
	var skin := SKIN_GRASS
	if m.x >= m.y and m.x >= m.z:
		surface = ASPHALT
		skin = SKIN_ROAD
	elif m.y >= m.z:
		surface = PAVING
		skin = SKIN_SIDEWALK
	if d < skin:
		return surface
	var seq: Array[int] = [GRAVEL if m.x + m.y >= 0.5 else SOIL, SOIL, CLAY, SAND, ROCK, ROCK_DEEP, LAVA, BEDROCK]
	var idx := 0
	for i in 7:
		if d >= boundary_depth(i, pos.x, pos.z, h):
			idx = i + 1
	return seq[idx]


## Flat parameter arrays for the shader (one entry per layer).
static func shader_layer_params() -> Dictionary:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for i in LAYER_COUNT:
		a.append(Vector4(TILE_M[i], float(TEX_SLOT[i]), NORMAL_STRENGTH[i], ROUGHNESS_MUL[i]))
		b.append(Vector4(TINT[i].r, TINT[i].g, TINT[i].b, 1.0))
	var amp := PackedFloat32Array(BOUND_AMP)
	var jit := PackedFloat32Array(BOUND_JIT)
	return {
		"u_layer_a": a, "u_layer_b": b, "u_bound_amp": amp, "u_bound_jit": jit,
		"u_bound_depth": Vector4(BOUND_DEPTH[0], BOUND_DEPTH[1], BOUND_DEPTH[2], BOUND_DEPTH[3]),
		"u_bound_y": Vector3(BOUND_Y[0], BOUND_Y[1], BOUND_Y[2]),
		"u_skin": Vector3(SKIN_ROAD, SKIN_SIDEWALK, SKIN_GRASS),
		"u_noise_tile": NOISE_TILE_M, "u_noise_fine": NOISE_FINE_SCALE,
	}
