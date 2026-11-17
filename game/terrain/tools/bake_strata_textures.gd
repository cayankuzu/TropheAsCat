extends SceneTree
## Offline bake of the strata texture arrays (run once after changing TerrainStrata.TEX_IDS):
##   Godot_console.exe --headless --path <project> --script res://game/terrain/tools/bake_strata_textures.gd [-- 2048]
## Output: StrataTextureSet.PATH (BPTC, mipmapped; uploaded as two Texture2DArrays at load):
##   albedo_layers  RGB = albedo (sRGB), A = height (Displacement)
##   nrm_layers     RG = NormalGL xy, B = roughness, A = ambient occlusion
##   lava_emission  Lava004 emission (1K)


func _initialize() -> void:
	var size := 2048
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		size = int(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(StrataTextureSet.PATH.get_base_dir()))
	var t0 := Time.get_ticks_msec()
	var s := StrataTextureSet.new()
	for id in TerrainStrata.TEX_IDS:
		var t := Time.get_ticks_msec()
		s.albedo_layers.append(_albedo_height(id, size))
		s.nrm_layers.append(_normal_rough_ao(id, size))
		print("%s packed+compressed in %d ms" % [id, Time.get_ticks_msec() - t])
	var emi := _load_map("Lava004", "Emission")
	emi.convert(Image.FORMAT_RGBA8)
	emi.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	emi.generate_mipmaps()
	emi.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
	s.lava_emission = emi
	_save(s, StrataTextureSet.PATH)
	print("bake done in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
	else:
		print("saved ", path)


func _load_map(id: String, map: String) -> Image:
	var path := "res://assets/textures/%s/%s_2K-JPG_%s.jpg" % [id, id, map]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.clear_mipmaps()
	return im


func _gray(id: String, map: String, size: int, fallback: int) -> PackedByteArray:
	var im := _load_map(id, map)
	if im == null:
		var out := PackedByteArray()
		out.resize(size * size)
		out.fill(fallback)
		return out
	im.convert(Image.FORMAT_L8)
	if im.get_width() != size:
		im.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return im.get_data()


func _albedo_height(id: String, size: int) -> Image:
	var im := _load_map(id, "Color")
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != size:
		im.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var data := im.get_data()
	var height := _gray(id, "Displacement", size, 128)
	var count := size * size
	var demoss := id == "Rock064"
	for i in count:
		var o := i * 4
		if demoss:
			# Rock064 is a mossy wall; turn yellow-green moss into grey-brown mineral staining so the
			# stone reads as jointed bedrock rather than a buried garden wall.
			var c := Color8(data[o], data[o + 1], data[o + 2])
			var k := smoothstep(0.09, 0.15, c.h) * (1.0 - smoothstep(0.42, 0.5, c.h)) * smoothstep(0.1, 0.3, c.s)
			if k > 0.0:
				var stone := Color.from_hsv(0.075, 0.18, c.v * 0.8)
				var m := c.lerp(stone, k)
				data[o] = m.r8
				data[o + 1] = m.g8
				data[o + 2] = m.b8
		data[o + 3] = height[i]
	var out := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	out.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
	return out


func _normal_rough_ao(id: String, size: int) -> Image:
	var im := _load_map(id, "NormalGL")
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != size:
		im.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var data := im.get_data()
	var rough := _gray(id, "Roughness", size, 200)
	var ao := _gray(id, "AmbientOcclusion", size, 255)
	for i in size * size:
		data[i * 4 + 2] = rough[i]
		data[i * 4 + 3] = ao[i]
	var out := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	out.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_GENERIC)
	return out
