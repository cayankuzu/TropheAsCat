class_name MaterialDB
extends RefCounted
## Physical and visual data for every man-made material, plus cached render materials.
##
## Units: density kg/m^3; toughness kJ per m^3 of element volume (element HP = toughness * volume * 1000 J);
## tile_m = metres covered by one texture repeat (object-space triplanar, so fracture pieces keep the
## exact texture of the element they came from as long as their mesh stays in the element's local frame).
##
## Facade variants (2026-11-17): a variant behaves exactly like its base material (density, toughness,
## sound, how it breaks, the glass rules of the destruction module) and only looks different: rendered
## brick in pastel colours, stone cladding, painted signs, windows with frames and curtains, tinted tower
## glass. Code that asks what a material IS compares base_of(name) or calls is_glass(name), never the
## variant's own name.

const TEX_ROOT := "res://assets/textures/"

const DATA := {
	&"concrete":       {"tex": "Concrete048", "interior": "Concrete044D", "tile_m": 2.5, "density": 2400.0, "toughness": 60.0, "tint": Color(0.92, 0.92, 0.9), "brittle": false, "sound": &"concrete"},
	&"concrete_light": {"tex": "Concrete034", "interior": "Concrete044D", "tile_m": 2.5, "density": 2300.0, "toughness": 45.0, "tint": Color(1, 1, 1), "brittle": false, "sound": &"concrete"},
	&"brick":          {"tex": "Bricks051", "interior": "Bricks051", "tile_m": 1.6, "density": 1900.0, "toughness": 30.0, "tint": Color(1, 1, 1), "brittle": false, "sound": &"brick"},
	&"brick_old":      {"tex": "Bricks097", "interior": "Bricks097", "tile_m": 1.6, "density": 1900.0, "toughness": 24.0, "tint": Color(1, 1, 1), "brittle": false, "sound": &"brick"},
	&"plaster":        {"tex": "Plaster001", "interior": "Concrete044D", "tile_m": 2.0, "density": 900.0, "toughness": 8.0, "tint": Color(0.95, 0.94, 0.9), "brittle": true, "sound": &"plaster"},
	&"glass":          {"tex": "", "interior": "", "tile_m": 1.0, "density": 2500.0, "toughness": 1.0, "tint": Color(0.75, 0.88, 0.95, 0.35), "brittle": true, "sound": &"glass"},
	&"steel":          {"tex": "PaintedMetal004", "interior": "PaintedMetal004", "tile_m": 2.0, "density": 7850.0, "toughness": 220.0, "tint": Color(0.55, 0.57, 0.6), "brittle": false, "sound": &"metal"},
	&"metal_rusty":    {"tex": "Metal063", "interior": "Metal063", "tile_m": 2.0, "density": 7850.0, "toughness": 150.0, "tint": Color(1, 1, 1), "brittle": false, "sound": &"metal"},
	&"wood":           {"tex": "WoodFloor064", "interior": "WoodFloor064", "tile_m": 2.0, "density": 600.0, "toughness": 15.0, "tint": Color(1, 1, 1), "brittle": false, "sound": &"wood"},
	&"tile":           {"tex": "Tiles141", "interior": "Concrete044D", "tile_m": 1.5, "density": 2300.0, "toughness": 20.0, "tint": Color(1, 1, 1), "brittle": true, "sound": &"ceramic"},
	&"roof":           {"tex": "RoofingTiles013A", "interior": "WoodFloor064", "tile_m": 2.0, "density": 1500.0, "toughness": 12.0, "tint": Color(1, 1, 1), "brittle": true, "sound": &"ceramic"},
	&"asphalt":        {"tex": "Asphalt033", "interior": "Gravel043", "tile_m": 4.0, "density": 2300.0, "toughness": 40.0, "tint": Color(1, 1, 1), "brittle": false, "sound": &"concrete"},
	## Hollow sheet-metal things counted as solid boxes (roof plant, railings, awnings, signs): the density
	## is what such a box weighs per cubic metre of its outline, not the density of steel.
	&"sheet_metal":    {"tex": "PaintedMetal004", "interior": "PaintedMetal004", "tile_m": 2.0, "density": 250.0, "toughness": 40.0, "tint": Color(0.75, 0.77, 0.8), "brittle": false, "sound": &"metal"},
	&"paving":         {"tex": "PavingStones142", "interior": "Gravel043", "tile_m": 3.0, "density": 2300.0, "toughness": 30.0, "tint": Color(1, 1, 1), "brittle": false, "sound": &"concrete"},
}

## Ground strata textures for the terrain module (not destructible elements).
const STRATA := {
	&"grass": "Grass005", &"gravel": "Gravel043", &"soil": "Ground048", &"clay": "Clay005",
	&"sand": "Ground054", &"rock": "Rock064", &"rock_deep": "Rock058", &"lava": "Lava004",
}

## Window frame colours and the curtains that go with them (FacadeTextures draws the windows).
const FRAMES := {
	"white": Color(0.92, 0.91, 0.87), "green": Color(0.15, 0.3, 0.22),
	"brown": Color(0.33, 0.21, 0.13), "black": Color(0.11, 0.11, 0.12),
}
const CURTAINS := {
	"white": Color(0.93, 0.87, 0.74), "green": Color(0.64, 0.17, 0.15),
	"brown": Color(0.9, 0.84, 0.7), "black": Color(0.52, 0.58, 0.64),
}
const WINDOW_KINDS: PackedStringArray = ["plain", "curtain", "blind", "lit"]

## name -> {base, and what changes}. tex / tile_m / tint: a textured look; metal or glass: [albedo,
## metallic, roughness] for an untextured one; proc + uv (+ a, b, kind, emit): a FacadeTextures look
## whose texture covers exactly one face of uv metres, the size of the element it is made for.
static var VARIANTS := _make_variants()
static var _bases := _make_bases()
static var _merged: Dictionary = {}
static var _surface_cache: Dictionary = {}
static var _interior_cache: Dictionary = {}


static func has(material: StringName) -> bool:
	return DATA.has(material) or VARIANTS.has(material)


## The material a variant behaves like (the name itself for a base material).
static func base_of(material: StringName) -> StringName:
	var b: Variant = _bases.get(material)
	return material if b == null else b


static func is_glass(material: StringName) -> bool:
	return base_of(material) == &"glass"


static func density(material: StringName) -> float:
	return _data(material)["density"]


## Joules needed to destroy an element of this material and volume.
static func element_hp(material: StringName, volume_m3: float) -> float:
	return _data(material)["toughness"] * 1000.0 * maxf(volume_m3, 0.001)


static func is_brittle(material: StringName) -> bool:
	return _data(material)["brittle"]


static func sound_kind(material: StringName) -> StringName:
	return _data(material)["sound"]


## Paths of the maps for an ambientCG id, e.g. maps_for("Concrete048")["Color"].
static func maps_for(tex_id: String) -> Dictionary:
	var out := {}
	if tex_id == "":
		return out
	for m in ["Color", "NormalGL", "Roughness", "AmbientOcclusion", "Metalness", "Displacement", "Emission", "Opacity"]:
		var p := "%s%s/%s_2K-JPG_%s.jpg" % [TEX_ROOT, tex_id, tex_id, m]
		if ResourceLoader.exists(p):
			out[m] = p
	return out


## Outer surface material (shared, cached). Object-space triplanar.
static func surface(material: StringName) -> Material:
	if _surface_cache.has(material):
		return _surface_cache[material]
	var d := _data(material)
	var mat: StandardMaterial3D
	if d.has("proc"):
		mat = FacadeTextures.material(d)
	elif d.has("glass"):
		# Tower glass: built like the base glass (same shader), tinted and more reflective.
		var look: Array = d["glass"]
		mat = _build("", 1.0, look[0])
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.metallic = look[1]
		mat.roughness = look[2]
		mat.metallic_specular = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif d.has("metal"):
		# Painted or anodised metal: the painted-metal relief without its colour (as ElementLibrary's steel).
		var look: Array = d["metal"]
		mat = _build("PaintedMetal004", 2.0, look[0])
		mat.albedo_texture = null
		mat.metallic_texture = null
		mat.roughness_texture = null
		mat.metallic = look[1]
		mat.roughness = look[2]
	else:
		mat = _build(d["tex"], d["tile_m"], d["tint"])
		if material == &"glass":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = d["tint"]
			mat.roughness = 0.04
			mat.metallic = 0.1
			mat.metallic_specular = 0.9
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_surface_cache[material] = mat
	return mat


## Material for faces created by fracture (broken concrete, brick core, splintered wood). A variant shows
## the core of its base: rendered brick breaks open to brick.
static func interior(material: StringName) -> Material:
	if _interior_cache.has(material):
		return _interior_cache[material]
	var d := _data(material)
	var mat: StandardMaterial3D
	if is_glass(material):
		mat = surface(material).duplicate()
		mat.albedo_color = Color(0.7, 0.9, 0.95, 0.6)
	elif d.has("metal"):
		mat = surface(material).duplicate()
		mat.albedo_color = (d["metal"][0] as Color).lightened(0.25)
		mat.roughness = 0.25
	else:
		var base: Dictionary = DATA.get(base_of(material), DATA[&"concrete"])
		mat = _build(d["interior"], base["tile_m"] * 0.6, (base["tint"] as Color).darkened(0.08))
	_interior_cache[material] = mat
	return mat


static func strata_maps(layer: StringName) -> Dictionary:
	return maps_for(STRATA.get(layer, ""))


static func _data(material: StringName) -> Dictionary:
	if DATA.has(material):
		return DATA[material]
	var cached: Variant = _merged.get(material)
	if cached != null:
		return cached
	var v: Dictionary = VARIANTS.get(material, {})
	var merged: Dictionary = DATA.get(v.get("base", &"concrete"), DATA[&"concrete"]).duplicate()
	for k: String in v:
		merged[k] = v[k]
	_merged[material] = merged
	return merged


static func _build(tex_id: String, tile_m: float, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_triplanar_sharpness = 4.0
	var s := 1.0 / maxf(tile_m, 0.01)
	mat.uv1_scale = Vector3(s, s, s)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var maps := maps_for(tex_id)
	if maps.has("Color"):
		mat.albedo_texture = load(maps["Color"])
	if maps.has("NormalGL"):
		mat.normal_enabled = true
		mat.normal_texture = load(maps["NormalGL"])
	if maps.has("Roughness"):
		mat.roughness_texture = load(maps["Roughness"])
		mat.roughness = 1.0
	if maps.has("Metalness"):
		mat.metallic_texture = load(maps["Metalness"])
		mat.metallic = 1.0
	if maps.has("AmbientOcclusion"):
		mat.ao_enabled = true
		mat.ao_texture = load(maps["AmbientOcclusion"])
	return mat


static func _make_variants() -> Dictionary:
	var v := {
		# Walls. Rendered brick behaves like brick and wears coloured render; pastel houses stay plaster.
		&"render_cream": {"base": &"brick", "tex": "Plaster001", "tile_m": 2.0, "tint": Color(0.96, 0.88, 0.72)},
		&"render_sage": {"base": &"brick", "tex": "Plaster001", "tile_m": 2.0, "tint": Color(0.73, 0.8, 0.65)},
		&"render_terracotta": {"base": &"brick", "tex": "Plaster001", "tile_m": 2.0, "tint": Color(0.9, 0.62, 0.47)},
		&"render_sky": {"base": &"brick", "tex": "Plaster001", "tile_m": 2.0, "tint": Color(0.71, 0.8, 0.88)},
		&"render_rose": {"base": &"brick", "tex": "Plaster001", "tile_m": 2.0, "tint": Color(0.93, 0.74, 0.71)},
		&"render_ochre": {"base": &"brick", "tex": "Plaster001", "tile_m": 2.0, "tint": Color(0.93, 0.77, 0.47)},
		&"render_white": {"base": &"brick", "tex": "Plaster001", "tile_m": 2.0, "tint": Color(0.97, 0.96, 0.93)},
		&"pastel_cream": {"base": &"plaster", "tint": Color(0.97, 0.9, 0.75)},
		&"pastel_sage": {"base": &"plaster", "tint": Color(0.76, 0.84, 0.7)},
		&"pastel_rose": {"base": &"plaster", "tint": Color(0.95, 0.78, 0.76)},
		&"pastel_sky": {"base": &"plaster", "tint": Color(0.74, 0.83, 0.92)},
		&"pastel_ochre": {"base": &"plaster", "tint": Color(0.95, 0.8, 0.52)},
		&"brick_dark": {"base": &"brick", "tint": Color(0.72, 0.64, 0.62)},
		&"fieldstone": {"base": &"brick_old", "tex": "PavingStones142", "tile_m": 2.2, "tint": Color(1.0, 0.97, 0.92)},
		# Stone cladding (square ashlar), trim (cornices, ledges, canopies).
		&"stone": {"base": &"brick", "tex": "Tiles141", "tile_m": 3.6, "tint": Color(0.97, 0.94, 0.87)},
		&"stone_warm": {"base": &"brick", "tex": "Tiles141", "tile_m": 3.6, "tint": Color(0.92, 0.86, 0.76)},
		&"trim_white": {"base": &"concrete_light", "tint": Color(0.98, 0.97, 0.94)},
		&"trim_cream": {"base": &"concrete_light", "tint": Color(0.94, 0.88, 0.77)},
		# Roofs.
		&"roof_slate": {"base": &"roof", "tint": Color(0.46, 0.5, 0.56)},
		&"roof_brown": {"base": &"roof", "tint": Color(0.72, 0.57, 0.46)},
		# Shop sign bands (the lintel over a shop window), on brick.
		&"sign_green": {"base": &"brick", "tex": "PaintedMetal004", "tile_m": 2.0, "tint": Color(0.22, 0.52, 0.34)},
		&"sign_burgundy": {"base": &"brick", "tex": "PaintedMetal004", "tile_m": 2.0, "tint": Color(0.66, 0.17, 0.19)},
		&"sign_navy": {"base": &"brick", "tex": "PaintedMetal004", "tile_m": 2.0, "tint": Color(0.2, 0.3, 0.58)},
		&"sign_gold": {"base": &"brick", "tex": "PaintedMetal004", "tile_m": 2.0, "tint": Color(0.86, 0.68, 0.22)},
		&"sign_teal": {"base": &"brick", "tex": "PaintedMetal004", "tile_m": 2.0, "tint": Color(0.14, 0.56, 0.58)},
		# Tower metal: mullions, spandrel panels, crowns, rooftop plant.
		&"alu": {"base": &"steel", "metal": [Color(0.78, 0.8, 0.83), 0.85, 0.3]},
		&"metal_white": {"base": &"steel", "metal": [Color(0.93, 0.93, 0.91), 0.15, 0.4]},
		&"panel_white": {"base": &"steel", "metal": [Color(0.9, 0.9, 0.88), 0.2, 0.35]},
		&"panel_graphite": {"base": &"steel", "metal": [Color(0.22, 0.23, 0.25), 0.6, 0.35]},
		&"panel_champagne": {"base": &"steel", "metal": [Color(0.8, 0.77, 0.7), 0.7, 0.3]},
		&"plant_alu": {"base": &"sheet_metal", "metal": [Color(0.78, 0.8, 0.83), 0.85, 0.3]},
		&"plant_graphite": {"base": &"sheet_metal", "metal": [Color(0.22, 0.23, 0.25), 0.6, 0.35]},
		# The outer ring (2026-11-17): corrugated cladding and sheet roofs of the docks, roller doors, the
		# light roof of a fuel station canopy.
		&"clad_blue": {"base": &"sheet_metal", "proc": "corrugated", "uv": Vector3.ONE, "a": Color(0.27, 0.42, 0.66)},
		&"clad_grey": {"base": &"sheet_metal", "proc": "corrugated", "uv": Vector3.ONE, "a": Color(0.68, 0.7, 0.72)},
		&"clad_red": {"base": &"sheet_metal", "proc": "corrugated", "uv": Vector3.ONE, "a": Color(0.64, 0.24, 0.19)},
		&"clad_white": {"base": &"sheet_metal", "proc": "corrugated", "uv": Vector3.ONE, "a": Color(0.9, 0.9, 0.88)},
		&"clad_green": {"base": &"sheet_metal", "proc": "corrugated", "uv": Vector3.ONE, "a": Color(0.3, 0.5, 0.39)},
		&"roof_sheet": {"base": &"sheet_metal", "proc": "corrugated", "uv": Vector3.ONE, "a": Color(0.5, 0.52, 0.55)},
		&"roller_door": {"base": &"sheet_metal", "proc": "roller", "uv": Vector3.ONE, "a": Color(0.8, 0.79, 0.74)},
		&"canopy_white": {"base": &"sheet_metal", "metal": [Color(0.95, 0.95, 0.93), 0.1, 0.45]},
		# The set pieces: the lattice of the tower crane (see-through), the face of the clock tower.
		&"lattice_yellow": {"base": &"sheet_metal", "proc": "railing", "uv": Vector3(2.0, 2.0, 2.0), "a": Color(0.95, 0.72, 0.12)},
		&"clock_face": {"base": &"glass", "proc": "clock", "uv": Vector3(3.6, 3.6, 3.6), "emit": 0.35},
		# The Owner's DO NOT TOUCH tape (2 m of it per texture, as high as the tape).
		&"tape": {"base": &"plaster", "proc": "tape", "uv": Vector3(2.0, 0.08, 2.0)},
		# Tower glass: [albedo with alpha, metallic, roughness].
		&"glass_sky": {"base": &"glass", "glass": [Color(0.55, 0.68, 0.8, 0.86), 0.72, 0.04]},
		&"glass_teal": {"base": &"glass", "glass": [Color(0.42, 0.62, 0.62, 0.86), 0.72, 0.04]},
		&"glass_bronze": {"base": &"glass", "glass": [Color(0.58, 0.54, 0.49, 0.86), 0.72, 0.05]},
		&"glass_silver": {"base": &"glass", "glass": [Color(0.69, 0.71, 0.74, 0.86), 0.76, 0.04]},
		# Doors and the shop windows, awnings, railings, the parking decks.
		&"door_glass": {"base": &"glass", "proc": "door_glass", "uv": Vector3(1.5, 2.4, 1.5), "a": Color(0.22, 0.23, 0.24)},
		&"tower_door": {"base": &"glass", "proc": "door_glass", "uv": Vector3(1.42, 2.75, 1.42), "a": Color(0.2, 0.21, 0.22)},
		&"tower_door_s": {"base": &"glass", "proc": "door_glass", "uv": Vector3(1.05, 2.45, 1.05), "a": Color(0.2, 0.21, 0.22)},
		&"rail_black": {"base": &"sheet_metal", "proc": "railing", "uv": Vector3.ONE, "a": Color(0.08, 0.08, 0.09)},
		&"rail_green": {"base": &"sheet_metal", "proc": "railing", "uv": Vector3.ONE, "a": Color(0.12, 0.26, 0.19)},
		&"rail_white": {"base": &"sheet_metal", "proc": "railing", "uv": Vector3.ONE, "a": Color(0.9, 0.9, 0.88)},
		&"parking_sign": {"base": &"sheet_metal", "proc": "parking", "uv": Vector3(2.4, 2.4, 2.4)},
	}
	for frame: String in FRAMES:
		for kind in WINDOW_KINDS:
			v[StringName("window_%s_%s" % [frame, kind])] = {"base": &"glass", "proc": "window", "uv": Vector3(1.5, 1.5, 1.5),
				"a": FRAMES[frame], "b": CURTAINS[frame], "kind": kind, "emit": 0.55 if kind == "lit" else 0.0}
		v[StringName("door_balcony_" + frame)] = {"base": &"glass", "proc": "door_balcony", "uv": Vector3(1.5, 2.4, 1.5), "a": FRAMES[frame]}
	var paints := {"red": Color(0.55, 0.13, 0.12), "green": Color(0.16, 0.34, 0.25), "blue": Color(0.17, 0.28, 0.48),
		"white": Color(0.9, 0.9, 0.87), "black": Color(0.12, 0.12, 0.13), "yellow": Color(0.86, 0.66, 0.2)}
	for paint: String in paints:
		v[StringName("door_" + paint)] = {"base": &"wood", "proc": "door_wood", "uv": Vector3(1.5, 2.4, 1.5), "a": paints[paint]}
	var brands := {"green": [Color(0.15, 0.4, 0.26), Color(0.94, 0.91, 0.82)], "red": [Color(0.7, 0.13, 0.13), Color(0.96, 0.94, 0.9)],
		"blue": [Color(0.15, 0.28, 0.55), Color(0.95, 0.95, 0.92)], "yellow": [Color(0.93, 0.71, 0.16), Color(0.2, 0.2, 0.22)],
		"teal": [Color(0.1, 0.5, 0.52), Color(0.95, 0.93, 0.88)]}
	for brand: String in brands:
		var c: Array = brands[brand]
		v[StringName("awning_" + brand)] = {"base": &"sheet_metal", "proc": "awning", "uv": Vector3.ONE, "a": c[0], "b": c[1]}
		v[StringName("shop_" + brand)] = {"base": &"glass", "proc": "shop", "uv": Vector3(1.5, 2.1, 1.5), "a": Color(0.16, 0.16, 0.17), "b": c[0], "emit": 0.7}
		# The fascia of a fuel station canopy (1.1 m high) and the sign band on a mall roof (2.2 m).
		v[StringName("fascia_" + brand)] = {"base": &"sheet_metal", "proc": "fascia", "uv": Vector3(1.0, 1.1, 1.0), "a": c[0], "b": c[1]}
		v[StringName("mallsign_" + brand)] = {"base": &"sheet_metal", "proc": "fascia", "uv": Vector3(1.0, 2.2, 1.0), "a": c[0], "b": c[1]}
		# A fuel pump (1.85 m) and the price pylon of the station (6.5 m) in the brand.
		v[StringName("pump_" + brand)] = {"base": &"sheet_metal", "proc": "fascia", "uv": Vector3(1.0, 1.85, 1.0), "a": c[0], "b": c[1]}
		v[StringName("pylon_" + brand)] = {"base": &"sheet_metal", "proc": "fascia", "uv": Vector3(1.0, 6.5, 1.0), "a": c[0], "b": c[1]}
	var decks := {"red": Color(0.74, 0.2, 0.17), "blue": Color(0.18, 0.38, 0.7), "yellow": Color(0.94, 0.74, 0.18), "green": Color(0.2, 0.55, 0.32)}
	for deck: String in decks:
		v[StringName("deck_" + deck)] = {"base": &"concrete_light", "proc": "deck", "uv": Vector3.ONE, "a": decks[deck]}
	return v


static func _make_bases() -> Dictionary:
	var out := {}
	for name: StringName in VARIANTS:
		out[name] = VARIANTS[name]["base"]
	return out
