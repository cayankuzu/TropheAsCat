class_name FxTextures
extends RefCounted
## Procedural textures shared by the FX shaders and decals. Each is built once, on first use
## (WorldFX asks for all of them while the world loads, so nothing is generated during play).

const DECAL_SIZE := 96

static var _noise: NoiseTexture2D = null
static var _scorch: ImageTexture = null
static var _glow: ImageTexture = null
static var _splat: ImageTexture = null
static var _splat_glow: ImageTexture = null


## Seamless greyscale noise for puff erosion and flame flicker.
static func noise() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_octaves = 3
		_noise = NoiseTexture2D.new()
		_noise.width = 128
		_noise.height = 128
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = n
	return _noise


## Soot mark: near-black, ragged rim, a few radial streaks.
static func scorch() -> Texture2D:
	if _scorch == null:
		_scorch = _radial(_scorch_pixel, 19)
	return _scorch


## Soft white disc for emission (hot metal, laser dot, acid glow); tinted by Decal.modulate.
static func glow() -> Texture2D:
	if _glow == null:
		_glow = _radial(_glow_pixel, 7)
	return _glow


## Wet splat (acid residue, slime): blobby outline with satellite drops; light grey so modulate tints it.
static func splat() -> Texture2D:
	if _splat == null:
		_splat = _radial(_splat_pixel.bind(false), 31)
	return _splat


## Emission companion of splat(): the same shape, bright in the thick middle.
static func splat_glow() -> Texture2D:
	if _splat_glow == null:
		_splat_glow = _radial(_splat_pixel.bind(true), 31)
	return _splat_glow


static func _scorch_pixel(r: float, n: float, rays: float) -> Color:
	var edge := r * (1.0 + 0.3 * n + 0.28 * rays)
	var a := 1.0 - smoothstep(0.3, 0.98, edge)
	var shade := lerpf(0.035, 0.09, clampf(edge, 0.0, 1.0))
	return Color(shade * 1.1, shade, shade * 0.9, a * 0.94)


static func _glow_pixel(r: float, n: float, _rays: float) -> Color:
	var v := pow(clampf(1.0 - r * (1.0 + 0.12 * n), 0.0, 1.0), 1.8)
	return Color(v, v, v, 1.0)


static func _splat_pixel(r: float, n: float, rays: float, emission: bool) -> Color:
	var edge := r * (1.0 + 0.2 * n) - rays * 0.3
	var a := 1.0 - smoothstep(0.52, 0.66, edge)
	if emission:
		var v := a * (0.35 + 0.65 * clampf(1.0 - edge * 1.4, 0.0, 1.0))
		return Color(v, v, v, 1.0)
	var shade := lerpf(0.85, 0.5, clampf(edge * 1.5, 0.0, 1.0))
	return Color(shade, shade, shade, a * 0.9)


## Fills a DECAL_SIZE square from pixel(r, noise, rays): r = distance from the centre (1 at the edge),
## noise and rays in -1..1 (rays depends on the angle only: streaks and lobes).
static func _radial(pixel: Callable, seed_value: int) -> ImageTexture:
	var size := DECAL_SIZE
	var noise_gen := FastNoiseLite.new()
	noise_gen.seed = seed_value
	noise_gen.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_gen.frequency = 0.045
	noise_gen.fractal_octaves = 2
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var half := (size - 1) * 0.5
	var i := 0
	for y in size:
		for x in size:
			var dx := (x - half) / half
			var dy := (y - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var n := noise_gen.get_noise_2d(x, y) * 2.0
			var inv := 1.0 / maxf(r, 0.001)
			var rays := noise_gen.get_noise_2d(300.0 + dx * inv * 42.0, 300.0 + dy * inv * 42.0) * 2.0
			var c: Color = pixel.call(r, clampf(n, -1.0, 1.0), clampf(rays, -1.0, 1.0))
			data[i] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			data[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			data[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			data[i + 3] = int(clampf(c.a, 0.0, 1.0) * 255.0)
			i += 4
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
