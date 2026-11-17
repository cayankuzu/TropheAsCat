@tool
extends EditorExportPlugin
## For exports with the "web" feature only: every 2D texture larger than MAX_SIZE is shrunk to it (aspect
## kept, mipmaps rebuilt) and stored compressed (S3TC, which desktop browsers support) or, for HDR images
## such as the sky panoramas, as a smaller float texture. The desktop builds keep the full textures.

const MAX_SIZE := 256
const MAX_SIZE_HERO := 512             ## Trophe herself (files under /cat/ or named sphynx*)
const MAX_SIZE_HDR := 1024
const MAX_SIZE_ARRAY := 512            ## the ground's texture layers (they tile, so they stay sharper)

var _count := 0


func _get_name() -> String:
	return "TropheWebTextures"


func _begin_customize_resources(_platform: EditorExportPlatform, features: PackedStringArray) -> bool:
	_count = 0
	return features.has("web")


func _get_customization_configuration_hash() -> int:
	return hash("trophe-web-textures-v2-%d-%d-%d-%d" % [MAX_SIZE, MAX_SIZE_HERO, MAX_SIZE_HDR, MAX_SIZE_ARRAY])


func _customize_resource(resource: Resource, path: String) -> Resource:
	var script := resource.get_script() as Script
	if script != null and script.resource_path.ends_with("strata_texture_set.gd"):
		return _shrink_strata(resource)
	if resource is Texture2DArray:
		return _shrink_array(resource as Texture2DArray)
	if not (resource is CompressedTexture2D or resource is ImageTexture):
		return null
	var img := (resource as Texture2D).get_image()
	if img == null:
		return null
	var hdr := img.get_format() >= Image.FORMAT_RF and img.get_format() <= Image.FORMAT_RGBE9995
	var hero := path.contains("/cat/") or path.get_file().begins_with("sphynx")
	var limit := MAX_SIZE_HDR if hdr else (MAX_SIZE_HERO if hero else MAX_SIZE)
	var w := img.get_width()
	var h := img.get_height()
	if maxi(w, h) <= limit:
		return null
	if img.is_compressed():
		img.decompress()
	var k := float(limit) / float(maxi(w, h))
	img.clear_mipmaps()
	img.resize(maxi(int(w * k), 4), maxi(int(h * k), 4), Image.INTERPOLATE_LANCZOS)
	_count += 1
	if hdr:
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	img.generate_mipmaps()
	# A plain ImageTexture holding S3TC data: PortableCompressedTexture2D rendered blank in WebGL 2.
	img.compress(Image.COMPRESS_S3TC)
	return ImageTexture.create_from_image(img)


## StrataTextureSet (the ground's layers, stored as Images): each layer to MAX_SIZE_ARRAY, compressed again in
## the format it had (BPTC), so all layers of an array keep one format.
func _shrink_strata(src: Resource) -> Resource:
	var out: Resource = (src.get_script() as GDScript).new()
	var albedo: Array[Image] = []
	for im: Image in src.get(&"albedo_layers"):
		albedo.append(_smaller(im, MAX_SIZE_ARRAY))
	var nrm: Array[Image] = []
	for im: Image in src.get(&"nrm_layers"):
		nrm.append(_smaller(im, MAX_SIZE_ARRAY))
	out.set(&"albedo_layers", albedo)
	out.set(&"nrm_layers", nrm)
	var lava: Image = src.get(&"lava_emission")
	out.set(&"lava_emission", _smaller(lava, MAX_SIZE_ARRAY) if lava != null else null)
	_count += albedo.size() + nrm.size() + 1
	return out


func _smaller(src: Image, limit: int) -> Image:
	var im := src.duplicate() as Image
	var fmt := im.get_format()
	var mode := -1
	if fmt == Image.FORMAT_BPTC_RGBA:
		mode = Image.COMPRESS_BPTC
	elif fmt >= Image.FORMAT_DXT1 and fmt <= Image.FORMAT_DXT5:
		mode = Image.COMPRESS_S3TC
	if im.is_compressed():
		im.decompress()
	var had_mips := src.has_mipmaps()
	im.clear_mipmaps()
	var w := im.get_width()
	var h := im.get_height()
	if maxi(w, h) > limit:
		var k := float(limit) / float(maxi(w, h))
		im.resize(maxi(int(w * k), 4), maxi(int(h * k), 4), Image.INTERPOLATE_LANCZOS)
	if had_mips:
		im.generate_mipmaps()
	if mode != -1:
		im.compress(mode as Image.CompressMode)
	return im


## The ground's layered textures (StrataTextureSet): every layer to MAX_SIZE_ARRAY, S3TC when all layers
## end up in the same format (an array needs one), else uncompressed.
func _shrink_array(arr: Texture2DArray) -> Resource:
	var layers: Array[Image] = []
	var changed := false
	for i in arr.get_layers():
		var im := arr.get_layer_data(i)
		if im == null:
			return null
		im = im.duplicate() as Image
		if im.is_compressed():
			im.decompress()
		im.clear_mipmaps()
		var w := im.get_width()
		var h := im.get_height()
		if maxi(w, h) > MAX_SIZE_ARRAY:
			var k := float(MAX_SIZE_ARRAY) / float(maxi(w, h))
			im.resize(maxi(int(w * k), 4), maxi(int(h * k), 4), Image.INTERPOLATE_LANCZOS)
			changed = true
		im.generate_mipmaps()
		layers.append(im)
	if not changed:
		return null
	var raw: Array[Image] = []
	for im in layers:
		raw.append(im.duplicate() as Image)
	var fmt := -1
	var same := true
	for im in layers:
		im.compress(Image.COMPRESS_S3TC)
		if fmt == -1:
			fmt = im.get_format()
		same = same and im.get_format() == fmt
	var out := Texture2DArray.new()
	out.create_from_images(layers if same else raw)
	_count += 1
	return out


func _end_customize_resources() -> void:
	print("TropheWebTextures: %d textures shrunk for the web" % _count)
