class_name StreetDressing
extends Node3D
## Street furniture and loose things on the sidewalks of the two central roads: lamp posts on the
## curb, benches, bins, planters, drums and gas bottles, boxes, barriers, a coffee cart, and cat statues
## on the corners of the central crossing. Everything is a BreakableProp. Placement is seeded, so the
## block looks the same on every run. The city module will take over the layout later; the prop
## definitions and add_prop() stay.

const ROOT := "res://assets/models/props/"

const DEFS := {
	&"lamp": {"model": "street_lamp_01/street_lamp_01_1k.gltf", "material": &"steel", "mass": 90.0, "hp": 30000.0, "anchored": true, "solid": 0.25},
	&"bench": {"model": "painted_wooden_bench/painted_wooden_bench_1k.gltf", "material": &"wood", "mass": 35.0, "hp": 9000.0, "solid": 0.2},
	&"seating": {"model": "modular_street_seating/modular_street_seating_1k.gltf", "material": &"concrete", "mass": 390.0, "hp": 60000.0, "anchored": true, "solid": 0.45},
	&"barrier": {"model": "concrete_road_barrier_02/concrete_road_barrier_02_1k.gltf", "material": &"concrete", "mass": 380.0, "hp": 60000.0, "solid": 0.7},
	&"bins": {"model": "metal_trash_can/metal_trash_can_1k.gltf", "material": &"steel", "mass": 45.0, "hp": 6000.0, "solid": 0.3},
	&"planter": {"model": "planter_box_02/planter_box_02_1k.gltf", "material": &"wood", "mass": 40.0, "hp": 5000.0, "solid": 0.6},
	&"propane": {"model": "propane_tank/propane_tank_1k.gltf", "material": &"steel", "mass": 18.0, "hp": 2500.0, "shape": "cylinder", "solid": 0.5,
		"blast": {"radius": 5.0, "energy": 9.0e5, "impulse": 5000.0}},
	&"fuel_drum": {"model": "barrel_01/Barrel_01_1k.gltf", "material": &"metal_rusty", "mass": 60.0, "hp": 4000.0, "shape": "cylinder", "solid": 0.5,
		"blast": {"radius": 6.0, "energy": 1.2e6, "impulse": 7000.0}},
	&"drum": {"model": "barrel_02/Barrel_02_1k.gltf", "material": &"metal_rusty", "mass": 25.0, "hp": 4000.0, "shape": "cylinder", "solid": 0.4},
	&"box": {"model": "cardboard_box_01/cardboard_box_01_1k.gltf", "material": &"wood", "mass": 3.0, "hp": 300.0, "solid": 0.3},
	&"crate": {"model": "plastic_crate_02/plastic_crate_02_1k.gltf", "material": &"plaster", "mass": 2.5, "hp": 400.0, "solid": 0.3},
	&"sign": {"model": "wetfloorsign_01/WetFloorSign_01_1k.gltf", "material": &"plaster", "mass": 1.5, "hp": 200.0, "solid": 0.2},
	&"generator": {"model": "portable_generator/portable_generator_1k.gltf", "material": &"steel", "mass": 70.0, "hp": 6000.0, "solid": 0.5,
		"blast": {"radius": 4.0, "energy": 6.0e5, "impulse": 3500.0}},
	&"coffee_cart": {"model": "coffeecart_01/CoffeeCart_01_1k.gltf", "material": &"wood", "mass": 180.0, "hp": 14000.0, "solid": 0.25},
	&"table_set": {"model": "outdoor_table_chair_set_01/outdoor_table_chair_set_01_1k.gltf", "material": &"steel", "mass": 30.0, "hp": 3000.0, "solid": 0.15},
	&"cat_statue": {"model": "concrete_cat_statue/concrete_cat_statue_1k.gltf", "material": &"concrete", "mass": 390.0, "hp": 40000.0, "scale": 6.0, "anchored": true, "solid": 0.6},

	# Things that stand on tables. Fragile ones break when they fall off; light ones fly when swatted.
	&"vase_a": {"model": "antique_ceramic_vase_01/antique_ceramic_vase_01_1k.gltf", "material": &"tile", "mass": 2.5, "hp": 12.0, "shape": "cylinder", "fragile": true},
	&"vase_b": {"model": "ceramic_vase_01/ceramic_vase_01_1k.gltf", "material": &"tile", "mass": 1.8, "hp": 10.0, "shape": "cylinder", "fragile": true},
	&"vase_c": {"model": "ceramic_vase_02/ceramic_vase_02_1k.gltf", "material": &"tile", "mass": 1.5, "hp": 10.0, "shape": "cylinder", "fragile": true},
	&"vase_d": {"model": "ceramic_vase_03/ceramic_vase_03_1k.gltf", "material": &"tile", "mass": 1.0, "hp": 8.0, "shape": "cylinder", "fragile": true},
	&"vase_e": {"model": "ceramic_vase_04/ceramic_vase_04_1k.gltf", "material": &"tile", "mass": 1.4, "hp": 10.0, "shape": "cylinder", "fragile": true},
	&"jug": {"model": "jug_01/jug_01_1k.gltf", "material": &"tile", "mass": 0.8, "hp": 6.0, "fragile": true},
	&"bottles": {"model": "wine_bottles_01/wine_bottles_01_1k.gltf", "material": &"glass", "mass": 2.0, "hp": 8.0, "fragile": true},
	&"frame": {"model": "standing_picture_frame_01/standing_picture_frame_01_1k.gltf", "material": &"glass", "mass": 0.4, "hp": 4.0, "fragile": true},
	&"clock": {"model": "alarm_clock_01/alarm_clock_01_1k.gltf", "material": &"steel", "mass": 0.4, "hp": 5.0, "fragile": true},
	&"bust": {"model": "marble_bust_01/marble_bust_01_1k.gltf", "material": &"concrete", "mass": 5.5, "hp": 40.0, "fragile": true},
	&"cat_souvenir": {"model": "concrete_cat_statue/concrete_cat_statue_1k.gltf", "material": &"concrete", "mass": 1.2, "hp": 12.0, "fragile": true},
	&"tv_a": {"model": "television_01/Television_01_1k.gltf", "material": &"glass", "mass": 5.5, "hp": 60.0, "fragile": true},
	&"tv_b": {"model": "television_02/television_02_1k.gltf", "material": &"glass", "mass": 4.5, "hp": 50.0, "fragile": true},
	&"microwave": {"model": "vintage_microwave/vintage_microwave_1k.gltf", "material": &"steel", "mass": 5.0, "hp": 400.0, "scale": 0.5},
	&"kettle": {"model": "vintage_electric_kettle/vintage_electric_kettle_1k.gltf", "material": &"steel", "mass": 1.2, "hp": 300.0},
	&"brass_pot": {"model": "brass_pot_01/brass_pot_01_1k.gltf", "material": &"steel", "mass": 2.2, "hp": 600.0, "shape": "cylinder"},
	&"brass_vase": {"model": "brass_vase_03/brass_vase_03_1k.gltf", "material": &"steel", "mass": 0.6, "hp": 300.0, "shape": "cylinder"},
	&"bowl": {"model": "wooden_bowl_02/wooden_bowl_02_1k.gltf", "material": &"wood", "mass": 0.2, "hp": 150.0},
	&"boombox": {"model": "boombox/boombox_1k.gltf", "material": &"plaster", "mass": 3.0, "hp": 200.0},
	&"duck": {"model": "rubber_duck_toy/rubber_duck_toy_1k.gltf", "material": &"plaster", "mass": 0.25, "hp": 60000.0},
	&"toolbox": {"model": "metal_toolbox/metal_toolbox_1k.gltf", "material": &"steel", "mass": 6.5, "hp": 3000.0},
	&"desk_lamp": {"model": "desk_lamp_arm_01/desk_lamp_arm_01_1k.gltf", "material": &"steel", "mass": 2.0, "hp": 200.0},

	# Tables and other things to put them on.
	&"table_long": {"model": "woodentable_01/WoodenTable_01_1k.gltf", "material": &"wood", "mass": 25.0, "hp": 5000.0, "solid": 0.3},
	&"table_dining": {"model": "dining_table/dining_table_1k.gltf", "material": &"wood", "mass": 45.0, "hp": 9000.0, "solid": 0.2},
	&"table_coffee": {"model": "coffeetable_01/CoffeeTable_01_1k.gltf", "material": &"wood", "mass": 20.0, "hp": 5000.0, "solid": 0.3},
	&"table_round": {"model": "coffee_table_round_01/coffee_table_round_01_1k.gltf", "material": &"wood", "mass": 22.0, "hp": 5000.0, "shape": "cylinder", "solid": 0.3},
	&"table_modern": {"model": "modern_coffee_table_01/modern_coffee_table_01_1k.gltf", "material": &"steel", "mass": 12.0, "hp": 4000.0, "solid": 0.3},
	&"desk": {"model": "metal_office_desk/metal_office_desk_1k.gltf", "material": &"steel", "mass": 55.0, "hp": 12000.0, "solid": 0.3},
	&"console": {"model": "classicconsole_01/ClassicConsole_01_1k.gltf", "material": &"wood", "mass": 35.0, "hp": 7000.0, "solid": 0.4},
	&"nightstand": {"model": "classicnightstand_01/ClassicNightstand_01_1k.gltf", "material": &"wood", "mass": 14.0, "hp": 3500.0, "solid": 0.6},
	&"stool": {"model": "woodentable_02/WoodenTable_02_1k.gltf", "material": &"wood", "mass": 3.0, "hp": 900.0, "solid": 0.4},

	# Furniture and odd things for markets, gardens, yards.
	&"cabinet": {"model": "drawer_cabinet/drawer_cabinet_1k.gltf", "material": &"wood", "mass": 60.0, "hp": 9000.0, "solid": 0.6},
	&"armchair": {"model": "armchair_01/ArmChair_01_1k.gltf", "material": &"wood", "mass": 28.0, "hp": 6000.0, "solid": 0.4},
	&"armchair_modern": {"model": "modern_arm_chair_01/modern_arm_chair_01_1k.gltf", "material": &"wood", "mass": 22.0, "hp": 5000.0, "solid": 0.4},
	&"lounge_chair": {"model": "mid_century_lounge_chair/mid_century_lounge_chair_1k.gltf", "material": &"wood", "mass": 24.0, "hp": 5000.0, "solid": 0.3},
	&"green_chair": {"model": "greenchair_01/GreenChair_01_1k.gltf", "material": &"wood", "mass": 9.0, "hp": 2500.0, "solid": 0.3},
	&"dining_chair": {"model": "dining_chair_02/dining_chair_02_1k.gltf", "material": &"wood", "mass": 6.0, "hp": 1800.0, "solid": 0.2},
	&"school_chair": {"model": "schoolchair_01/SchoolChair_01_1k.gltf", "material": &"steel", "mass": 6.0, "hp": 2000.0, "solid": 0.2},
	&"school_desk": {"model": "schooldesk_01/SchoolDesk_01_1k.gltf", "material": &"wood", "mass": 12.0, "hp": 3000.0, "solid": 0.3},
	&"bar_chair": {"model": "bar_chair_round_01/bar_chair_round_01_1k.gltf", "material": &"steel", "mass": 5.0, "hp": 1800.0, "shape": "cylinder", "solid": 0.2},
	&"ottoman": {"model": "ottoman_01/Ottoman_01_1k.gltf", "material": &"wood", "mass": 8.0, "hp": 2500.0, "solid": 0.7},
	&"sofa": {"model": "sofa_01/Sofa_01_1k.gltf", "material": &"wood", "mass": 40.0, "hp": 8000.0, "solid": 0.5},
	&"bed": {"model": "gothicbed_01/GothicBed_01_1k.gltf", "material": &"wood", "mass": 80.0, "hp": 12000.0, "solid": 0.3},
	&"grandfather_clock": {"model": "vintage_grandfather_clock_01/vintage_grandfather_clock_01_1k.gltf", "material": &"wood", "mass": 45.0, "hp": 2500.0, "solid": 0.5},
	&"stove": {"model": "electric_stove/electric_stove_1k.gltf", "material": &"steel", "mass": 45.0, "hp": 9000.0, "solid": 0.5},
	&"ladder": {"model": "ladder_sectioned_01/ladder_sectioned_01_1k.gltf", "material": &"steel", "mass": 9.0, "hp": 2500.0, "solid": 0.1},
	&"shelves": {"model": "steel_frame_shelves_01/steel_frame_shelves_01_1k.gltf", "material": &"steel", "mass": 30.0, "hp": 5000.0, "scale": 0.1, "solid": 0.15},
	&"aircon": {"model": "exterior_aircon_unit/exterior_aircon_unit_1k.gltf", "material": &"steel", "mass": 40.0, "hp": 7000.0, "solid": 0.6},
	&"power_box": {"model": "power_box_01/power_box_01_1k.gltf", "material": &"steel", "mass": 15.0, "hp": 4000.0, "solid": 0.7},
	&"tyre": {"model": "old_tyre/old_tyre_1k.gltf", "material": &"plaster", "mass": 9.0, "hp": 80000.0, "solid": 0.4},
	&"container": {"model": "industrial_pastic_container/industrial_pastic_container_1k.gltf", "material": &"plaster", "mass": 4.0, "hp": 900.0, "solid": 0.3},
	&"planter_small": {"model": "planter_box_01/planter_box_01_1k.gltf", "material": &"wood", "mass": 28.0, "hp": 4000.0, "solid": 0.6},
}

## What stands in one gap between two street trees: [weight, [[id, shift along the road, distance from
## the road centre, extra yaw in degrees], ...]]. Yaw 0 faces the road.
const CLUSTERS := [
	[26, [[&"bench", 0.0, 11.3, 0.0]]],
	[14, [[&"bench", -0.6, 11.3, 0.0], [&"bins", 1.4, 11.4, 0.0]]],
	[8, [[&"bins", 0.0, 11.4, 0.0]]],
	[10, [[&"planter", -1.0, 11.2, 0.0], [&"planter", 1.0, 11.2, 0.0]]],
	[7, [[&"fuel_drum", -0.5, 11.0, 0.0], [&"drum", 0.3, 11.3, 40.0], [&"propane", 0.9, 10.7, 0.0]]],
	[9, [[&"box", -0.4, 11.2, 20.0], [&"box", 0.2, 11.4, -35.0], [&"crate", 0.6, 10.9, 10.0]]],
	[6, [[&"barrier", -0.9, 8.6, 90.0], [&"barrier", 0.9, 8.6, 90.0], [&"sign", 0.0, 9.6, 0.0]]],
	[5, [[&"table_set", 0.0, 10.9, 90.0]]],
	[4, [[&"coffee_cart", 0.0, 10.6, 0.0], [&"crate", 1.8, 11.0, 15.0]]],
	[4, [[&"seating", 0.0, 11.2, 0.0]]],
	[4, [[&"generator", 0.0, 11.1, 0.0], [&"propane", 0.8, 11.3, 0.0]]],
	[3, []],
]

## Cluster weights per district (CityLayout.District), in the order of CLUSTERS: downtown sits and
## drinks coffee, the old quarter has benches and bins, the works keep fuel and crates on the pavement,
## the park is benches and little else; the Strip shops and sits, the Yards keep drums and crates out,
## the Suburbs are quiet.
const DISTRICT_WEIGHTS := {
	1: [20, 12, 6, 16, 0, 2, 2, 10, 10, 10, 0, 12],
	2: [28, 16, 10, 12, 1, 10, 2, 6, 3, 2, 0, 10],
	3: [4, 4, 8, 0, 20, 16, 16, 0, 1, 0, 12, 19],
	4: [34, 16, 6, 8, 0, 0, 0, 6, 4, 6, 0, 20],
	5: [18, 14, 10, 14, 1, 6, 4, 6, 8, 8, 1, 10],
	6: [2, 2, 8, 0, 22, 18, 18, 0, 0, 0, 14, 16],
	7: [20, 10, 12, 16, 0, 6, 1, 4, 1, 2, 0, 28],
}
## Share of the usual number of parked cars per district.
const DISTRICT_CAR_FILL := {1: 1.0, 2: 0.9, 3: 0.7, 4: 0.35, 5: 0.8, 6: 0.5, 7: 0.75}

const LAMP_OFFSET := 8.8          ## Lamp posts stand just behind the curb (the road is 8 m to each side).
const CROSSING_CLEARANCE := 20.0
const UNPARK_DISTANCE := 20.0
const PARK_DISTANCE := 48.0
const SCAN_PER_TICK := 32

## Share of the curb slots that hold a car, and how far parked cars stay from a crossing.
const CAR_FILL := 0.45
const CAR_CROSSING_CLEARANCE := 26.0
## Service vehicles that turn up among the parked cars, by weight.
const SERVICE_WEIGHTS := {
	&"taxi": 5, &"police_sedan": 3, &"postvan": 3, &"ambulance": 2, &"rdservtruck": 2,
	&"towtruck": 1, &"garbage_truck": 1, &"citybus": 1, &"school_bus": 1, &"fire_truck": 1,
}

var props: Array[BreakableProp] = []
## The name of every prop made here while the world was built, in order (saved games find them again by
## name).
var all_names := PackedStringArray()
## Set once the world stands: props made after that (cleanup robots, tape, road blocks, crashed cars of the
## traffic) are not in a fresh world, so they are left out of saved games.
var sealed := false
var vehicles: VehicleLibrary = null

var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _scan := 0


func prop_count() -> int:
	return props.size()


## Files this class reads (the composition root asks worker threads for them ahead of time).
static func model_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for def: Dictionary in DEFS.values():
		paths.append(ROOT + String(def["model"]))
	return paths


## Loose props are free only around the player (see BreakableProp.parked): a few are checked per tick.
func _physics_process(_delta: float) -> void:
	if Game.player == null or props.is_empty():
		return
	var at := Game.player.global_position
	for i in mini(SCAN_PER_TICK, props.size()):
		_scan = (_scan + 1) % props.size()
		var p := props[_scan]
		if not is_instance_valid(p):
			props.remove_at(_scan)
			if props.is_empty():
				return
			continue
		var d := p.global_position.distance_to(at)
		if p.parked:
			if d < UNPARK_DISTANCE:
				p.unpark()
		elif not p.freeze and p.sleeping and d > PARK_DISTANCE:
			p.park()


## One prop standing on the ground at (at.x, at.z), turned by yaw.
## on_ground = false keeps at.y as given (things that stand on a table). `inside` = behind walls (the
## furniture of a house): drawn only near and without a shadow.
func add_prop(id: StringName, at: Vector3, yaw: float = 0.0, on_ground: bool = true, inside: bool = false) -> BreakableProp:
	var def: Dictionary = DEFS[id].duplicate()
	def["model"] = ROOT + String(def["model"])
	if not _scenes.has(id):
		_scenes[id] = load(def["model"])
	var scene := _scenes[id] as PackedScene
	if scene == null:
		return null
	var prop := BreakableProp.from_model(StringName("%s_%d" % [id, props.size()]), def, scene.instantiate() as Node3D)
	prop.prop_id = id
	add_child(prop)
	if not sealed:
		all_names.append(String(prop.name))
	var y := _ground(at.x, at.z) + 0.01 if on_ground else at.y
	prop.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.z))
	prop.reset_physics_interpolation()
	props.append(prop)
	if inside:
		prop.set_meta(&"inside", true)   # counted by the OFFICE SPACE job and the HOUSE CALL achievement
		for node in prop.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			mi.visibility_range_end = minf(mi.visibility_range_end, 45.0) if mi.visibility_range_end > 0.0 else 45.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif Game.lite:
		_limit_range(prop, LITE_RANGE)
	return prop


## Something small on top of a prop that is already standing (a vase on a table): `offset` is measured
## from the middle of the top of `under`, in its own frame.
func add_on_top(id: StringName, under: BreakableProp, offset: Vector3 = Vector3.ZERO, yaw: float = 0.0, inside: bool = false) -> BreakableProp:
	if under == null:
		return null
	var at := under.global_transform * (Vector3(0.0, under.size.y + 0.004, 0.0) + offset)
	return add_prop(id, at, under.global_rotation.y + yaw, false, inside)


## A prop that is a plain box with a look (a MaterialDB variant): a shipping container, a fuel pump, a
## run of fence. `def` is as in DEFS without "model"; `parts` dress the box (in its own frame, the origin
## at its middle); `lift` raises it off the ground (a container on top of another).
func add_box(id: StringName, size: Vector3, look: StringName, def: Dictionary, at: Vector3, yaw: float = 0.0, lift: float = 0.0,
		parts: Array[Node3D] = []) -> BreakableProp:
	var model := MeshInstance3D.new()
	var key := "box %s" % size
	if not _scenes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_scenes[key] = mesh
	model.mesh = _scenes[key]
	model.material_override = MaterialDB.surface(look)
	for part in parts:
		model.add_child(part)
	return add_node_prop(id, model, def, at, yaw, lift)


## A prop made from a model built in code (a vacuum robot): `def` as in DEFS without "model".
func add_node_prop(id: StringName, model: Node3D, def: Dictionary, at: Vector3, yaw: float = 0.0, lift: float = 0.0) -> BreakableProp:
	var prop := BreakableProp.from_model(StringName("%s_%d" % [id, props.size()]), def, model)
	prop.prop_id = id
	add_child(prop)
	if not sealed:
		all_names.append(String(prop.name))
	prop.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, _ground(at.x, at.z) + lift + 0.01, at.z))
	prop.reset_physics_interpolation()
	props.append(prop)
	if Game.lite:
		_limit_range(prop, LITE_RANGE_BIG)
	return prop


## The lite build draws loose things only near the camera (the browser demo runs on integrated GPUs).
const LITE_RANGE := 70.0
const LITE_RANGE_BIG := 140.0


static func _limit_range(prop: Node, metres: float) -> void:
	for node in prop.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.visibility_range_end = minf(mi.visibility_range_end, metres) if mi.visibility_range_end > 0.0 else metres


## A car for a painted bay, a drive or a pump: an everyday car, now and then a taxi or a police car;
## nothing longer than a bay. Returns null when the car did not fit.
func park_in_bay(at: Vector3, yaw: float, rng: RandomNumberGenerator) -> BreakableProp:
	_load_vehicles()
	if vehicles.passenger.is_empty():
		return null
	var vname: StringName = vehicles.passenger[rng.randi_range(0, vehicles.passenger.size() - 1)]
	if rng.randf() < 0.08:
		var special: StringName = [&"taxi", &"police_sedan"][rng.randi_range(0, 1)]
		if vehicles.has_vehicle(special):
			vname = special
	var prop := _vehicle_prop(vname)
	if prop == null:
		return null
	if prop.size.z > 5.4 or prop.size.x > 2.4:
		prop.free()
		return null
	_put(prop, at, yaw)
	return prop


## Saved games: the names of the props that are gone and of the cars that are burnt-out wrecks.
func save_state() -> Dictionary:
	var gone := PackedStringArray()
	var wrecks := PackedStringArray()
	for n in all_names:
		var p := get_node_or_null(NodePath(n)) as BreakableProp
		if p == null or p.is_broken():
			gone.append(n)
		elif p.is_wreck():
			wrecks.append(n)
	return {"gone": gone, "wrecks": wrecks}


func restore_state(state: Dictionary) -> void:
	for n: Variant in state.get("gone", []):
		var p := get_node_or_null(NodePath(String(n))) as BreakableProp
		if p != null:
			p.restore_broken()
	for n: Variant in state.get("wrecks", []):
		var p := get_node_or_null(NodePath(String(n))) as BreakableProp
		if p != null:
			p.restore_wreck()


## Dresses both sidewalks of the roads x = 0 and z = 0 (see dress_roads).
func dress_central_roads(half_extent: float = 190.0, spacing: float = 24.0, seed_value: int = 11) -> int:
	return dress_roads(PackedFloat32Array([0.0]), half_extent, spacing, seed_value)


## Dresses both sidewalks of the given roads between the street trees (which stand every `spacing`
## metres) and puts a cat statue on each corner of the central crossing. `lines` holds the offsets of
## the road centre lines: every offset is one road along x and one along z. district_of (a Callable
## taking a Vector3, CityLayout.district_at) picks what stands where; without it every road gets the
## same mix.
func dress_roads(lines: PackedFloat32Array, half_extent: float, spacing: float = 24.0, seed_value: int = 11, district_of: Callable = Callable()) -> int:
	_rng.seed = seed_value
	var before := props.size()
	var road_spacing := float(TerrainStrata.ROAD_SPACING)
	var base_weights: Array = []
	for c: Array in CLUSTERS:
		base_weights.append(int(c[0]))
	var n := int(half_extent / spacing)
	for axis in 2:
		for line in lines:
			for i in range(-n, n):
				var along := (i + 0.5) * spacing
				if absf(along - roundf(along / road_spacing) * road_spacing) < CROSSING_CLEARANCE:
					continue
				for side: float in [-1.0, 1.0]:
					# A lamp post in every second gap, staggered between the two sides.
					if posmod(i + (0 if side < 0.0 else 1), 2) == 0:
						_place(axis, line, along + _rng.randf_range(-0.5, 0.5), side, LAMP_OFFSET, &"lamp", 0.0)
					var across := line + side * 11.0
					var here := Vector3(along, 0.0, across) if axis == 0 else Vector3(across, 0.0, along)
					var weights: Array = base_weights
					if district_of.is_valid():
						weights = DISTRICT_WEIGHTS.get(int(district_of.call(here)), base_weights)
					var total_weight := 0
					for w: int in weights:
						total_weight += w
					var pick := _rng.randi_range(0, maxi(total_weight - 1, 0))
					for k in CLUSTERS.size():
						pick -= int(weights[k])
						if pick < 0:
							var c: Array = CLUSTERS[k]
							var shift := _rng.randf_range(2.5, 6.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
							for item: Array in c[1]:
								_place(axis, line, along + shift + float(item[1]), side, float(item[2]), item[0], deg_to_rad(float(item[3]) + _rng.randf_range(-6.0, 6.0)))
							break
	if lines.has(0.0):
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p := Vector3(sx * 14.6, 0.0, sz * 14.6)
				add_prop(&"cat_statue", p, atan2(-p.x, -p.z))
	return props.size() - before


## One vehicle from the packs as a prop: a heavy steel body with fuel in it. It is wrecked first (blast,
## charred burning shell) and breaks apart when the wreck is destroyed. Returns null for unknown names.
func add_vehicle(vehicle: StringName, at: Vector3, yaw: float = 0.0) -> BreakableProp:
	var prop := _vehicle_prop(vehicle)
	if prop != null:
		_put(prop, at, yaw)
	return prop


## Parks cars along both curbs of the given roads (the default is x = 0 and z = 0): mostly everyday
## cars, now and then a taxi, a van or something bigger, with free slots in between and the crossings
## kept clear. `fill` is the share of slots that hold a car; district_of (see dress_roads) thins it out
## where few people park.
func park_cars(half_extent: float = 185.0, seed_value: int = 23, lines: PackedFloat32Array = PackedFloat32Array([0.0]), fill: float = CAR_FILL, district_of: Callable = Callable()) -> int:
	_load_vehicles()
	if vehicles.passenger.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var road_spacing := float(TerrainStrata.ROAD_SPACING)
	var curb := float(TerrainStrata.ROAD_HALF_WIDTH)
	var before := props.size()
	for axis in 2:
		for line in lines:
			for side: float in [-1.0, 1.0]:
				var along := -half_extent
				while along < half_extent:
					var slot := rng.randf_range(6.4, 7.6)
					var mid := along + slot * 0.5
					along += slot
					if absf(mid - roundf(mid / road_spacing) * road_spacing) < CAR_CROSSING_CLEARANCE:
						continue
					var here_fill := fill
					if district_of.is_valid():
						var across := line + side * 11.0
						var here := Vector3(mid, 0.0, across) if axis == 0 else Vector3(across, 0.0, mid)
						here_fill *= float(DISTRICT_CAR_FILL.get(int(district_of.call(here)), 1.0))
					if rng.randf() > here_fill:
						continue
					var prop := _vehicle_prop(_pick_vehicle(rng))
					if prop == null:
						continue
					if prop.size.z > slot - 0.8:
						# Too long for one slot (a bus, a truck): it takes part of the next one as well.
						var extra := prop.size.z - slot + 1.2
						mid += extra * 0.5
						along += extra
						if absf(mid - roundf(mid / road_spacing) * road_spacing) < CAR_CROSSING_CLEARANCE + prop.size.z * 0.5:
							prop.free()
							continue
					var offset := line + side * (curb - prop.size.x * 0.5 - 0.3)
					var at := Vector3(mid, 0.0, offset) if axis == 0 else Vector3(offset, 0.0, mid)
					var yaw := (PI * 0.5 if axis == 0 else 0.0) + (PI if rng.randf() < 0.5 else 0.0) + deg_to_rad(rng.randf_range(-2.0, 2.0))
					_put(prop, at, yaw)
	return props.size() - before


func _load_vehicles() -> void:
	if vehicles == null:
		vehicles = VehicleLibrary.new()
		vehicles.name = "Vehicles"
		add_child(vehicles)


func _vehicle_prop(vehicle: StringName) -> BreakableProp:
	_load_vehicles()
	var model := vehicles.build(vehicle)
	if model == null:
		return null
	var def := {"material": &"steel", "solid": 0.3, "wreck": true}
	var prop := BreakableProp.from_model(StringName("%s_%d" % [vehicle, props.size()]), def, model)
	prop.prop_id = vehicle
	# About 130 kg per cubic metre of bounding box: 1.4 t for a sedan, 9 t for a city bus.
	prop.mass = clampf(prop.size.x * prop.size.y * prop.size.z * 130.0, 600.0, 16000.0)
	prop.max_hp = prop.mass * 45.0
	prop.hp = prop.max_hp
	var big := prop.mass > 4000.0
	# The radius reaches the next car in a parked row, so a row goes up one car after the other.
	prop.blast = {"radius": 11.0 if big else 9.0, "energy": 3.0e6 if big else 1.5e6, "impulse": 14000.0 if big else 9000.0}
	return prop


func _pick_vehicle(rng: RandomNumberGenerator) -> StringName:
	if rng.randf() < 0.82 or vehicles.service.is_empty():
		return vehicles.passenger[rng.randi_range(0, vehicles.passenger.size() - 1)]
	var total := 0
	for w: int in SERVICE_WEIGHTS.values():
		total += w
	var pick := rng.randi_range(0, total - 1)
	for vehicle: StringName in SERVICE_WEIGHTS:
		pick -= int(SERVICE_WEIGHTS[vehicle])
		if pick < 0:
			return vehicle if vehicles.has_vehicle(vehicle) else vehicles.passenger[0]
	return vehicles.passenger[0]


func _put(prop: BreakableProp, at: Vector3, yaw: float) -> void:
	add_child(prop)
	if not sealed:
		all_names.append(String(prop.name))
	prop.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, _ground(at.x, at.z) + 0.02, at.z))
	prop.reset_physics_interpolation()
	props.append(prop)


## axis 0 = a road along x (at z = line), axis 1 = a road along z (at x = line); side is -1 or +1.
func _place(axis: int, line: float, along: float, side: float, offset: float, id: StringName, yaw_extra: float) -> void:
	var across := line + side * offset
	var at := Vector3(along, 0.0, across) if axis == 0 else Vector3(across, 0.0, along)
	# Yaw that turns the model's +Z toward the road centre line.
	var face := (PI if side > 0.0 else 0.0) if axis == 0 else (-PI * 0.5 if side > 0.0 else PI * 0.5)
	add_prop(id, at, face + yaw_extra)


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0
