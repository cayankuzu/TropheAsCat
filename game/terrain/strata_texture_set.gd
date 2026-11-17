class_name StrataTextureSet
extends Resource
## Baked, BPTC-compressed, mipmapped layers for the strata shader (see tools/bake_strata_textures.gd).
## Texture2DArray does not serialise its layers, so the Images are stored here and uploaded at load.

const PATH := "res://game/terrain/textures/strata_set.res"

@export var albedo_layers: Array[Image] = []   ## RGB albedo (sRGB) + A height, one per TerrainStrata slot.
@export var nrm_layers: Array[Image] = []      ## RG normal (GL), B roughness, A ambient occlusion.
@export var lava_emission: Image = null

static var _albedo_tex: Texture2DArray = null
static var _nrm_tex: Texture2DArray = null
static var _lava_tex: ImageTexture = null


## Returns {albedo: Texture2DArray, nrm: Texture2DArray, lava_emission: ImageTexture}, or {} if not baked.
static func load_textures() -> Dictionary:
	if _albedo_tex == null:
		if not ResourceLoader.exists(PATH):
			push_error("StrataTextureSet: %s missing; run res://game/terrain/tools/bake_strata_textures.gd" % PATH)
			return {}
		var s := load(PATH) as StrataTextureSet
		_albedo_tex = Texture2DArray.new()
		_albedo_tex.create_from_images(s.albedo_layers)
		_nrm_tex = Texture2DArray.new()
		_nrm_tex.create_from_images(s.nrm_layers)
		_lava_tex = ImageTexture.create_from_image(s.lava_emission)
	return {"albedo": _albedo_tex, "nrm": _nrm_tex, "lava_emission": _lava_tex}
