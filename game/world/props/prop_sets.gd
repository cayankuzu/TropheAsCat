class_name PropSets
extends RefCounted
## Composed places that fill the open spots of the city layout, built out of BreakableProps through a
## StreetDressing: flea markets with tables full of vases (the first thing every cat pushes off), cafe
## terraces on the plazas, village greens, works yards, one fuel depot (the biggest chain reaction on
## the Table), gardens beside houses and picnic spots in the Park.
## Every function returns the spots where a person may stand ({pos, yaw}), for People.add_stander.

const FRAGILE: Array[StringName] = [&"vase_a", &"vase_b", &"vase_c", &"vase_d", &"vase_e", &"jug", &"bottles", &"frame", &"clock", &"bust", &"cat_souvenir", &"vase_b", &"vase_c"]
const STURDY: Array[StringName] = [&"kettle", &"brass_pot", &"brass_vase", &"bowl", &"boombox", &"duck", &"microwave", &"tv_a", &"tv_b", &"desk_lamp", &"toolbox"]
const MARKET_TABLES: Array[StringName] = [&"table_long", &"table_dining", &"table_coffee", &"desk", &"console", &"table_round", &"table_long"]
const MARKET_FURNITURE: Array[StringName] = [&"armchair", &"armchair_modern", &"lounge_chair", &"sofa", &"cabinet", &"grandfather_clock", &"bed", &"nightstand", &"ottoman", &"stove", &"green_chair", &"dining_chair", &"bar_chair", &"school_desk", &"school_chair", &"shelves"]
const YARD_STUFF: Array[StringName] = [&"container", &"crate", &"box", &"drum", &"toolbox", &"tyre", &"container", &"crate", &"box"]


## A flea market in the court of an apartment block: two rows of stalls along x facing an aisle, every
## table covered with things, furniture for sale at both ends.
static func market(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var standers: Array[Dictionary] = []
	for row: float in [-1.0, 1.0]:
		var x := -26.0
		while x <= 26.0:
			var id := MARKET_TABLES[rng.randi_range(0, MARKET_TABLES.size() - 1)]
			var table := d.add_prop(id, center + Vector3(x + rng.randf_range(-0.3, 0.3), 0.0, row * 3.4), rng.randf_range(-0.06, 0.06))
			if table != null:
				_cover(d, table, rng)
				if rng.randf() < 0.3:
					# The seller stands behind the stall and looks across it at the aisle.
					standers.append({"pos": center + Vector3(x, 0.0, row * 4.9), "yaw": 0.0 if row < 0.0 else PI})
			x += rng.randf_range(4.6, 5.6)
	for end: float in [-1.0, 1.0]:
		for i in 6:
			var id := MARKET_FURNITURE[rng.randi_range(0, MARKET_FURNITURE.size() - 1)]
			d.add_prop(id, center + Vector3(end * rng.randf_range(29.5, 34.0), 0.0, rng.randf_range(-5.5, 5.5)), rng.randf() * TAU)
	# Shoppers in the aisle.
	for i in 4:
		standers.append({"pos": center + Vector3(rng.randf_range(-24.0, 24.0), 0.0, rng.randf_range(-1.0, 1.0)), "yaw": (0.0 if rng.randf() < 0.5 else PI) + rng.randf_range(-0.5, 0.5)})
	return standers


## A cafe terrace on a Downtown plaza: tables and chairs around a statue of the cat, a coffee cart,
## planters and seating at the edges.
static func cafe(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var standers: Array[Dictionary] = []
	d.add_prop(&"cat_statue", center, rng.randf() * TAU)
	for i in range(-1, 2):
		for j in range(-1, 2):
			if i == 0 and j == 0:
				continue
			var at := center + Vector3(i * 5.2 + rng.randf_range(-0.4, 0.4), 0.0, j * 5.2 + rng.randf_range(-0.4, 0.4))
			d.add_prop(&"table_set", at, rng.randf() * TAU)
			if rng.randf() < 0.45:
				standers.append({"pos": at + Vector3(rng.randf_range(-1.0, 1.0), 0.0, 1.4), "yaw": PI + rng.randf_range(-0.6, 0.6)})
	var cart := d.add_prop(&"coffee_cart", center + Vector3(-11.5, 0.0, rng.randf_range(-3.0, 3.0)), PI * 0.5)
	if cart != null:
		standers.append({"pos": cart.global_position + Vector3(-1.3, 0.0, 0.0), "yaw": PI * 0.5})
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			d.add_prop(&"planter", center + Vector3(sx * 12.5, 0.0, sz * 12.5), PI * 0.5 if rng.randf() < 0.5 else 0.0)
	d.add_prop(&"seating", center + Vector3(0.0, 0.0, 13.2), PI)
	d.add_prop(&"seating", center + Vector3(0.0, 0.0, -13.2), 0.0)
	d.add_prop(&"bins", center + Vector3(11.8, 0.0, rng.randf_range(-4.0, 4.0)), PI * 0.5)
	return standers


## The green in the middle of a block of houses: benches around a statue, planters, a couple of tables.
static func green(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator, statue: bool = true) -> Array[Dictionary]:
	var standers: Array[Dictionary] = []
	var turn := rng.randf() * TAU
	if statue:   # (the first green has the clock tower of SetPieces in its middle instead)
		d.add_prop(&"cat_statue", center, turn)
	for k in 4:
		var a := PI * 0.5 * k
		var out := Vector3(sin(a), 0.0, cos(a))
		d.add_prop(&"bench", center + out * 6.0, a + PI)   # facing the statue
		d.add_prop(&"planter", center + out * 10.5 + out.cross(Vector3.UP) * 2.5, a)
	for k in 2:
		var at := center + Vector3(rng.randf_range(-9.0, 9.0), 0.0, (9.0 if k == 0 else -9.0))
		var table := d.add_prop(&"table_round", at, 0.0)
		if table != null:
			_cover(d, table, rng)
			standers.append({"pos": at + Vector3(1.4, 0.0, 0.0), "yaw": -PI * 0.5})
	return standers


## An empty plot of the Works: stacks of containers, crates and boxes, shelves, ladders, a generator.
static func yard(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	for pile in 5:
		var base := center + Vector3(rng.randf_range(-18.0, 18.0), 0.0, rng.randf_range(-10.0, 10.0))
		for i in rng.randi_range(3, 6):
			var id := YARD_STUFF[rng.randi_range(0, YARD_STUFF.size() - 1)]
			var under := d.add_prop(id, base + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6)), rng.randf() * TAU)
			if under != null and id != &"tyre" and id != &"drum" and rng.randf() < 0.35:
				d.add_on_top(YARD_STUFF[rng.randi_range(0, 2)], under, Vector3.ZERO, rng.randf() * TAU)
	for i in 3:
		d.add_prop(&"shelves", center + Vector3(-20.0 + i * 2.2, 0.0, -12.5), 0.0)
	d.add_prop(&"ladder", center + Vector3(-13.0, 0.0, -12.6), 0.0)
	d.add_prop(&"generator", center + Vector3(20.0, 0.0, 11.0), rng.randf() * TAU)
	d.add_prop(&"aircon", center + Vector3(16.0, 0.0, -12.0), 0.0)
	d.add_prop(&"power_box", center + Vector3(21.5, 0.0, -11.5), 0.0)
	return [{"pos": center + Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-4.0, 4.0)), "yaw": rng.randf() * TAU}]


## The fuel depot of the Works: rows of fuel drums and gas bottles behind a line of barriers. One spark
## and the whole plot goes up, drum after drum.
static func fuel_depot(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	for i in 7:
		for j in 4:
			d.add_prop(&"fuel_drum", center + Vector3(-9.0 + i * 3.0 + rng.randf_range(-0.2, 0.2), 0.0, -4.5 + j * 3.0 + rng.randf_range(-0.2, 0.2)), rng.randf() * TAU)
	for i in 8:
		d.add_prop(&"propane", center + Vector3(-10.5 + i * 3.0, 0.0, 8.5), rng.randf() * TAU)
	for i in 6:
		d.add_prop(&"barrier", center + Vector3(-12.5 + i * 5.0, 0.0, -9.5), 0.0)
	d.add_prop(&"generator", center + Vector3(14.5, 0.0, 0.0), 0.0)
	d.add_prop(&"sign", center + Vector3(-14.0, 0.0, -11.0), 0.0)
	return [{"pos": center + Vector3(15.5, 0.0, 6.0), "yaw": -PI * 0.5}]


## Benches and a bin along the paths of a park block (CityLayout.PARK_PATHS), each facing its path.
static func park_path(d: StreetDressing, block: Vector3) -> void:
	d.add_prop(&"bench", block + Vector3(-30.0, 0.0, 6.6), PI)
	d.add_prop(&"bins", block + Vector3(-33.2, 0.0, 6.6), PI)
	d.add_prop(&"bench", block + Vector3(-8.6, 0.0, -14.0), PI * 0.5)
	d.add_prop(&"bench", block + Vector3(12.2, 0.0, 19.2), 2.45)


## A corner of a garden beside a house: a chair or two, something to put a cup on, and whatever was left out.
static func garden(d: StreetDressing, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, yaw)
	d.add_prop(&"green_chair" if rng.randf() < 0.6 else &"dining_chair", at + basis * Vector3(-0.8, 0.0, 0.0), yaw + PI * 0.5)
	var stool := d.add_prop(&"stool", at, yaw)
	if stool != null:
		var small: Array[StringName] = [&"jug", &"bowl", &"vase_d", &"clock", &"duck", &"brass_vase", &"frame"]
		d.add_on_top(small[rng.randi_range(0, small.size() - 1)], stool, Vector3.ZERO, rng.randf() * TAU)
	if rng.randf() < 0.5:
		d.add_prop(&"planter_small", at + basis * Vector3(0.6, 0.0, 1.1), yaw)
	if rng.randf() < 0.25:
		d.add_prop(&"tyre" if rng.randf() < 0.5 else &"ladder", at + basis * Vector3(1.4, 0.0, -0.4), rng.randf() * TAU)


## A picnic spot on a lawn of the Park.
static func picnic(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var standers: Array[Dictionary] = []
	for i in 3:
		var at := center + Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		d.add_prop(&"table_set", at, rng.randf() * TAU)
		standers.append({"pos": at + Vector3(1.5, 0.0, 0.3), "yaw": -PI * 0.5})
	var stool := d.add_prop(&"stool", center + Vector3(0.0, 0.0, 7.5), 0.0)
	if stool != null:
		d.add_on_top(&"boombox", stool, Vector3.ZERO, 0.0)
	d.add_prop(&"duck", center + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0)), rng.randf() * TAU)
	return standers


# --------------------------------------------------------------------------------------------------
# The outer ring (2026-11-17)
# --------------------------------------------------------------------------------------------------

## A 20 ft shipping container: a box of corrugated sheet in one of the colours of the docks, 2.3 t.
const CONTAINER_SIZE := Vector3(2.44, 2.59, 6.06)
const CONTAINER_LOOKS: Array[StringName] = [&"clad_red", &"clad_blue", &"clad_green", &"clad_grey", &"clad_white", &"clad_red"]
const PUMP_SIZE := Vector3(0.55, 1.85, 0.9)
const YARD_TRUCKS: Array[StringName] = [&"rdservtruck", &"postvan", &"garbage_truck", &"towtruck"]

static var _screen: StandardMaterial3D = null


## A painted car park (CityLayout.car_parks): cars in about a third of the bays, nose in or out, bins at
## the ends of the first aisle and somebody walking back to a car.
static func car_park(d: StreetDressing, rect: Rect2, rng: RandomNumberGenerator, fill: float = 0.35) -> Array[Dictionary]:
	var w := CityLayout.BAY_W
	var n0 := int(ceilf((rect.position.x + 1.0) / w))
	var n1 := int(floorf((rect.end.x - 1.0) / w))
	var z := rect.position.y
	while z + CityLayout.BAY_PERIOD <= rect.end.y + 0.01:
		for row: float in CityLayout.BAY_ROWS:
			for n in range(n0, n1):
				if rng.randf() > fill:
					continue
				var at := Vector3((n + 0.5) * w + rng.randf_range(-0.1, 0.1), 0.0, z + row + rng.randf_range(-0.15, 0.15))
				d.park_in_bay(at, (0.0 if rng.randf() < 0.5 else PI) + deg_to_rad(rng.randf_range(-3.0, 3.0)), rng)
		z += CityLayout.BAY_PERIOD
	d.add_prop(&"bins", Vector3(rect.position.x + 1.0, 0.0, rect.position.y + 3.0), PI * 0.5)
	d.add_prop(&"bins", Vector3(rect.end.x - 1.0, 0.0, rect.position.y + 3.0), -PI * 0.5)
	var c := rect.get_center()
	return [{"pos": Vector3(c.x + rng.randf_range(-12.0, 12.0), 0.0, rect.position.y + 3.0), "yaw": rng.randf() * TAU}]


## A fuel station forecourt (CityLayout.forecourts): four pumps on low islands along the two inner column
## lines of the canopy, in its brand; cars at some of them, gas bottles for sale by the shop, a power box
## and the price pylon at the corner. Every pump is fuel: one goes up and the next follows.
static func forecourt(d: StreetDressing, spot: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var center: Vector3 = spot["pos"]
	var brand := BuildingGenerator.canopy_brand(int(spot["seed"]))
	var tag := String(brand[1]).replace("awning_", "")
	var pump_look := StringName("pump_" + tag)
	var pump_def := {"material": pump_look, "mass": 420.0, "hp": 6000.0, "anchored": true, "solid": 0.6,
		"blast": {"radius": 9.0, "energy": 2.4e6, "impulse": 12000.0}}
	var kerb_def := {"material": &"concrete", "mass": 900.0, "hp": 40000.0, "anchored": true, "solid": 1.0}
	for sx: float in [-3.0, 3.0]:
		for sz: float in [-2.8, 2.8]:
			var at := center + Vector3(sx, 0.0, sz)
			d.add_box(&"pump_island", Vector3(1.3, 0.18, 4.2), &"concrete_light", kerb_def, at)
			d.add_box(&"fuel_pump", PUMP_SIZE, pump_look, pump_def, at, 0.0, 0.18, _pump_parts())
	# Cars at the pumps, in the three lanes between the islands and the outer columns.
	for lane: float in [-6.0, 0.0, 6.0]:
		for sz: float in [-2.8, 2.8]:
			if rng.randf() < 0.3:
				d.park_in_bay(center + Vector3(lane, 0.0, sz), (0.0 if rng.randf() < 0.5 else PI) + deg_to_rad(rng.randf_range(-4.0, 4.0)), rng)
	for i in 6:
		d.add_prop(&"propane", center + Vector3(10.0 + (i % 3) * 0.7, 0.0, 15.0 + floorf(i / 3.0) * 0.7), rng.randf() * TAU)
	d.add_prop(&"power_box", center + Vector3(-11.0, 0.0, 8.0), PI * 0.5)
	var pylon := StringName("pylon_" + tag)
	d.add_box(&"price_pylon", Vector3(1.8, 6.5, 0.45), pylon, {"material": pylon, "mass": 1200.0, "hp": 30000.0, "anchored": true, "solid": 0.5},
		center + Vector3(-14.0, 0.0, -11.5))
	return [{"pos": center + Vector3(9.5, 0.0, 13.0), "yaw": PI}, {"pos": center + Vector3(rng.randf_range(-6.0, 6.0), 0.0, 7.5), "yaw": rng.randf() * TAU}]


## The two faces of a pump that look at a lane (+x and -x): a lit display and a nozzle in its holster.
static func _pump_parts() -> Array[Node3D]:
	if _screen == null:
		_screen = StandardMaterial3D.new()
		_screen.albedo_color = Color(0.05, 0.07, 0.08)
		_screen.emission_enabled = true
		_screen.emission = Color(0.35, 0.9, 0.75)
		_screen.emission_energy_multiplier = 0.6
		_screen.roughness = 0.2
	var parts: Array[Node3D] = []
	for sgn: float in [-1.0, 1.0]:
		var screen := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.02, 0.3, 0.5)
		screen.mesh = sm
		screen.material_override = _screen
		screen.position = Vector3(sgn * (PUMP_SIZE.x * 0.5 + 0.01), 0.42, 0.0)
		parts.append(screen)
		var nozzle := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.1, 0.28, 0.12)
		nozzle.mesh = nm
		nozzle.material_override = MaterialDB.surface(&"plant_graphite")
		nozzle.position = Vector3(sgn * (PUMP_SIZE.x * 0.5 + 0.05), 0.05, 0.28)
		parts.append(nozzle)
	return parts


## The paved front of a mall between its doors and its car park (CityLayout.mall_fronts): planters and
## benches in a line facing the cars, bins, a coffee cart with a few tables, people about.
static func mall_front(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var standers: Array[Dictionary] = []
	for i in 10:
		d.add_prop(&"planter" if i % 2 == 0 else &"bench", center + Vector3(-42.0 + i * 9.33, 0.0, -9.0), PI)
	for x: float in [-30.0, 30.0]:
		d.add_prop(&"bins", center + Vector3(x, 0.0, -8.0), PI)
	var cart_at := center + Vector3(rng.randf_range(-14.0, 14.0), 0.0, 2.0)
	d.add_prop(&"coffee_cart", cart_at, PI)
	standers.append({"pos": cart_at + Vector3(0.0, 0.0, 1.4), "yaw": PI})
	for i in 4:
		var at := cart_at + Vector3(-7.0 + i * 4.6 + rng.randf_range(-0.6, 0.6), 0.0, -4.5 + rng.randf_range(-0.8, 0.8))
		d.add_prop(&"table_set", at, rng.randf() * TAU)
		if rng.randf() < 0.6:
			standers.append({"pos": at + Vector3(1.4, 0.0, 0.2), "yaw": -PI * 0.5})
	d.add_prop(&"seating", center + Vector3(-24.0, 0.0, 3.0), PI)
	d.add_prop(&"seating", center + Vector3(24.0, 0.0, 3.0), PI)
	return standers


## The loading yard of a Yards block (CityLayout.loading_yards): trucks backed up towards the roller
## doors, piles of crates, boxes and drums, a line of fuel drums and gas bottles at one end (the yard's
## fuse) and a generator.
static func loading_yard(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> Array[Dictionary]:
	for i in rng.randi_range(2, 4):
		var sz := -1.0 if i % 2 == 0 else 1.0
		var at := center + Vector3(rng.randf_range(-34.0, 34.0), 0.0, sz * 10.0)
		d.add_vehicle(YARD_TRUCKS[rng.randi_range(0, YARD_TRUCKS.size() - 1)], at, (0.0 if sz < 0.0 else PI) + deg_to_rad(rng.randf_range(-5.0, 5.0)))
	for pile in 4:
		var base := center + Vector3(rng.randf_range(-36.0, 36.0), 0.0, rng.randf_range(-2.5, 2.5))
		for i in rng.randi_range(3, 6):
			var id := YARD_STUFF[rng.randi_range(0, YARD_STUFF.size() - 1)]
			var under := d.add_prop(id, base + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6)), rng.randf() * TAU)
			if under != null and id != &"tyre" and id != &"drum" and rng.randf() < 0.35:
				d.add_on_top(YARD_STUFF[rng.randi_range(0, 2)], under, Vector3.ZERO, rng.randf() * TAU)
	var end := 44.0 if rng.randf() < 0.5 else -44.0
	for i in 6:
		d.add_prop(&"fuel_drum", center + Vector3(end + rng.randf_range(-0.2, 0.2), 0.0, -7.5 + i * 3.0), rng.randf() * TAU)
	for i in 4:
		d.add_prop(&"propane", center + Vector3(end - signf(end) * 2.2, 0.0, -4.5 + i * 3.0), rng.randf() * TAU)
	d.add_prop(&"generator", center + Vector3(-end * 0.5, 0.0, rng.randf_range(-3.0, 3.0)), rng.randf() * TAU)
	return [{"pos": center + Vector3(rng.randf_range(-20.0, 20.0), 0.0, 4.0), "yaw": rng.randf() * TAU}]


## Shipping containers stacked one to three high in two rows (CityLayout.container_yards): 2.3 t boxes of
## sheet to climb, push off and blow up.
static func container_yard(d: StreetDressing, center: Vector3, rng: RandomNumberGenerator) -> void:
	for row in 2:
		for col in 6:
			if rng.randf() < 0.15:
				continue
			var at := center + Vector3(-9.0 + col * 3.6, 0.0, -4.5 + row * 9.0)
			var yaw := deg_to_rad(rng.randf_range(-1.5, 1.5))
			for level in rng.randi_range(1, 3):
				var look := CONTAINER_LOOKS[rng.randi_range(0, CONTAINER_LOOKS.size() - 1)]
				d.add_box(&"shipping_container", CONTAINER_SIZE, look, {"material": look, "mass": 2300.0, "hp": 90000.0, "solid": 0.12},
					at, yaw + deg_to_rad(rng.randf_range(-1.0, 1.0)) * level, level * (CONTAINER_SIZE.y + 0.01))


## The car in the drive of a suburban house (CityLayout.driveways), and sometimes the bins beside it.
static func driveway(d: StreetDressing, spot: Dictionary, rng: RandomNumberGenerator) -> void:
	var at: Vector3 = spot["pos"]
	if rng.randf() < 0.8:
		d.park_in_bay(at, float(spot["yaw"]) + (PI if rng.randf() < 0.5 else 0.0) + deg_to_rad(rng.randf_range(-4.0, 4.0)), rng)
	if rng.randf() < 0.5:
		d.add_prop(&"bins", at + Vector3(2.3, 0.0, 0.0), float(spot["yaw"]))


## A run of white picket fence (CityLayout.fences, the paddock): {pos, length, yaw (optional, 0 = along x)}.
static func fence(d: StreetDressing, run: Dictionary) -> void:
	var length := float(run["length"])
	d.add_box(&"fence", Vector3(length, 0.95, 0.06), &"rail_white", {"material": &"rail_white", "mass": 6.0 * length, "hp": 700.0, "solid": 0.08},
		run["pos"], float(run.get("yaw", 0.0)))


## The fence of the petting farm's paddock (Wildlife.paddock_rect): white rails all round in 6 m runs, the
## gate left open in the middle of the south side (the animals keep to the paddock anyway).
static func paddock(d: StreetDressing, rect: Rect2) -> void:
	for z: float in [rect.position.y, rect.end.y]:
		var x := rect.position.x
		while x < rect.end.x - 0.1:
			var length := minf(6.0, rect.end.x - x)
			var mid := x + length * 0.5
			if not (z == rect.position.y and absf(mid - rect.get_center().x) < 3.5):
				fence(d, {"pos": Vector3(mid, 0.0, z), "length": length})
			x += length
	for x: float in [rect.position.x, rect.end.x]:
		var z := rect.position.y
		while z < rect.end.y - 0.1:
			var length := minf(6.0, rect.end.y - z)
			fence(d, {"pos": Vector3(x, 0.0, z + length * 0.5), "length": length, "yaw": PI * 0.5})
			z += length


## The back garden of a suburban house (CityLayout.backyards): the corner of a garden, and sometimes a
## table set on the lawn.
static func backyard(d: StreetDressing, spot: Dictionary, rng: RandomNumberGenerator) -> void:
	garden(d, spot["pos"], spot["yaw"], rng)
	if rng.randf() < 0.45:
		d.add_prop(&"table_set", spot["pos"] + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-2.0, 2.0)), rng.randf() * TAU)


# --------------------------------------------------------------------------------------------------
# Inside (2026-11-17): the ground floors of the houses, the shops and the malls. Behind the walls, so
# drawn only near (StreetDressing.add_prop inside); they spill out when the walls come down.
# --------------------------------------------------------------------------------------------------

const D := preload("res://game/destruction/destruction_defs.gd")


## The box inside the walls of the ground floor of a design (its own space), shrunk by `margin`.
static func _room(data: BuildingData, margin: float) -> AABB:
	var box := AABB()
	var first := true
	for i in data.count():
		if data.storey[i] != 0 or data.role[i] != D.Role.VERTICAL:
			continue
		var b := data.xf[i] * AABB(-data.dims[i] * 0.5, data.dims[i])
		box = b if first else box.merge(b)
		first = false
	return box.grow(-margin)


## A living room: a sofa against the back wall with a low table, a dining table with chairs, a cabinet with
## a TV, a plant; vases, jugs and frames on the tables. The door (the middle of the front, -z) stays clear.
static func interior_house(d: StreetDressing, data: BuildingData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var room := _room(data, 0.6)
	if room.size.x < 3.0 or room.size.z < 3.0:
		return
	var yaw := xf.basis.get_euler().y
	var x0 := room.position.x
	var x1 := room.end.x
	var z1 := room.end.z
	var mid := room.get_center()
	var left := mid.x - room.size.x * 0.25
	var right := mid.x + room.size.x * 0.25
	var sofa := d.add_prop(&"sofa" if rng.randf() < 0.7 else &"armchair", xf * Vector3(left, 0.0, z1 - 0.5), yaw + PI, true, true)
	var low := d.add_prop(&"table_coffee", xf * Vector3(left, 0.0, z1 - 2.0), yaw, true, true)
	if low != null:
		d.add_on_top(FRAGILE[rng.randi_range(0, FRAGILE.size() - 1)], low, Vector3.ZERO, rng.randf() * TAU, true)
	var _sofa_kept := sofa
	if rng.randf() < 0.8:
		var table := d.add_prop(&"table_dining", xf * Vector3(right, 0.0, mid.z + 0.6), yaw, true, true)
		if table != null:
			_cover_inside(d, table, rng)
		for s: float in [-1.0, 1.0]:
			d.add_prop(&"dining_chair", xf * Vector3(right + s * 1.1, 0.0, mid.z + 0.6), yaw + s * PI * 0.5 + PI, true, true)
	if rng.randf() < 0.7:
		var cab := d.add_prop(&"cabinet" if rng.randf() < 0.5 else &"console", xf * Vector3(x1 - 0.3, 0.0, mid.z - 0.4), yaw - PI * 0.5, true, true)
		if cab != null:
			d.add_on_top(&"tv_a" if rng.randf() < 0.5 else &"tv_b", cab, Vector3.ZERO, 0.0, true)
	if rng.randf() < 0.5:
		d.add_prop(&"grandfather_clock" if rng.randf() < 0.3 else &"planter_small", xf * Vector3(x0 + 0.4, 0.0, z1 - 0.4), yaw + PI, true, true)


## A shop: shelves along the back wall and down the middle with boxes on them, a counter by the door with
## something to sell on it.
static func interior_shop(d: StreetDressing, data: BuildingData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var room := _room(data, 0.5)
	if room.size.x < 3.0:
		return
	var yaw := xf.basis.get_euler().y
	var n := int(room.size.x / 1.4)
	for row: float in [room.end.z - 0.35, room.get_center().z + 0.6]:
		for i in n:
			var x := room.position.x + 0.7 + 1.4 * i
			var shelf := d.add_prop(&"shelves", xf * Vector3(x, 0.0, row), yaw + PI, true, true)
			if shelf != null and rng.randf() < 0.6:
				d.add_on_top(&"box" if rng.randf() < 0.6 else &"crate", shelf, Vector3.ZERO, rng.randf() * TAU, true)
	var counter := d.add_prop(&"desk", xf * Vector3(room.position.x + 1.0, 0.0, room.position.z + 1.2), yaw + PI * 0.5, true, true)
	if counter != null:
		d.add_on_top(STURDY[rng.randi_range(0, STURDY.size() - 1)], counter, Vector3(0.3, 0.0, 0.0), rng.randf() * TAU, true)
		d.add_on_top(FRAGILE[rng.randi_range(0, FRAGILE.size() - 1)], counter, Vector3(-0.3, 0.0, 0.0), rng.randf() * TAU, true)


## A mall: in every other bay between the columns a pair of shelves back to back with boxes, and a coffee
## counter by the doors.
static func interior_mall(d: StreetDressing, data: BuildingData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var room := _room(data, 1.0)
	var yaw := xf.basis.get_euler().y
	var bx := int(room.size.x / 6.0)
	var bz := int(room.size.z / 6.0)
	var x0 := room.get_center().x - bx * 3.0
	var z0 := room.get_center().z - bz * 3.0
	for i in bx:
		for j in bz:
			if (i + j) % 2 == 1 or (j == 0 and absi(i - (bx >> 1)) <= 1):
				continue   # every other bay, and the way in from the doors
			var c := Vector3(x0 + 3.0 + 6.0 * i, 0.0, z0 + 3.0 + 6.0 * j)
			for s: float in [-0.35, 0.35]:
				var shelf := d.add_prop(&"shelves", xf * (c + Vector3(0.0, 0.0, s)), yaw + (0.0 if s > 0.0 else PI), true, true)
				if shelf != null and rng.randf() < 0.5:
					d.add_on_top(&"box", shelf, Vector3.ZERO, rng.randf() * TAU, true)
	var cart := d.add_prop(&"coffee_cart", xf * Vector3(room.get_center().x + 6.0, 0.0, room.position.z + 3.0), yaw, true, true)
	var _cart_kept := cart


## An office floor (towers, 2026-11-17): rows of desks, each with a monitor, a chair and now and then a lamp
## or something fragile, plus plants, shelves, a sofa corner and a coffee corner; at most MAX_OFFICE_GROUPS.
static func interior_office(d: StreetDressing, data: BuildingData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var groups: Array[StringName] = [&"desk", &"desk", &"desk", &"desk", &"desk", &"desk", &"plant", &"shelf", &"sofa", &"kitchen", &"desk", &"desk", &"plant"]
	_furnish(d, data, xf, rng, groups, MAX_OFFICE_GROUPS, 2.8)


## The flats on the ground floor of an apartment block: beds, sofas with a TV, dining tables, kitchen corners.
static func interior_flats(d: StreetDressing, data: BuildingData, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var groups: Array[StringName] = [&"bed", &"sofa", &"dining", &"kitchen", &"bed", &"plant", &"sofa", &"dining"]
	_furnish(d, data, xf, rng, groups, MAX_FLAT_GROUPS, 3.0)


const MAX_OFFICE_GROUPS := 16
const MAX_FLAT_GROUPS := 10


## Puts furniture groups on a grid of spots (`step` apart) inside the ground floor, skipping every spot where
## something of the building stands (columns, cores, walls, partitions) and the way in from the door (the
## middle of the front, -z). The groups are used in turn; each gets the spot's centre in building space.
static func _furnish(d: StreetDressing, data: BuildingData, xf: Transform3D, rng: RandomNumberGenerator, groups: Array[StringName], max_groups: int, step: float) -> void:
	var room := _room(data, 0.9)
	if room.size.x < step * 2.0 or room.size.z < step * 2.0:
		return
	var obstacles: Array[AABB] = []
	for i in data.count():
		if data.storey[i] == 0 and data.role[i] == D.Role.VERTICAL:
			obstacles.append((data.xf[i] * AABB(-data.dims[i] * 0.5, data.dims[i])).grow(0.3))
	var spots: Array[Vector3] = []
	var nx := int(room.size.x / step)
	var nz := int(room.size.z / step)
	var ox := room.get_center().x - (nx - 1) * step * 0.5
	var oz := room.get_center().z - (nz - 1) * step * 0.5
	for i in nx:
		for j in nz:
			var p := Vector3(ox + i * step, 0.0, oz + j * step)
			if absf(p.x - room.get_center().x) < 1.8 and p.z < room.position.z + 3.5:
				continue   # the way in
			var probe := AABB(p - Vector3(1.0, 0.0, 1.0), Vector3(2.0, 1.0, 2.0))
			var free := true
			for b in obstacles:
				if b.intersects(probe):
					free = false
					break
			if free:
				spots.append(p)
	# A shuffled order, so the groups spread over the floor.
	for i in range(spots.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var t := spots[i]
		spots[i] = spots[k]
		spots[k] = t
	var yaw := xf.basis.get_euler().y
	for n in mini(spots.size(), max_groups):
		var at := spots[n]
		match groups[n % groups.size()]:
			&"desk":
				_desk_group(d, xf, yaw, at, rng)
			&"plant":
				_plant_group(d, xf, yaw, at, rng)
			&"shelf":
				_shelf_group(d, xf, yaw, at, rng)
			&"sofa":
				_sofa_group(d, xf, yaw, at, rng)
			&"kitchen":
				_kitchen_group(d, xf, yaw, at, rng)
			&"bed":
				_bed_group(d, xf, yaw, at, rng)
			&"dining":
				_dining_group(d, xf, yaw, at, rng)


static func _desk_group(d: StreetDressing, xf: Transform3D, yaw: float, at: Vector3, rng: RandomNumberGenerator) -> void:
	var desk := d.add_prop(&"desk" if rng.randf() < 0.75 else &"school_desk", xf * at, yaw, true, true)
	if desk != null:
		d.add_on_top(&"tv_b" if rng.randf() < 0.6 else &"tv_a", desk, Vector3(0.0, 0.0, 0.12), PI, true)
		if rng.randf() < 0.55:
			d.add_on_top(&"desk_lamp" if rng.randf() < 0.5 else FRAGILE[rng.randi_range(0, FRAGILE.size() - 1)], desk, Vector3(desk.size.x * 0.32, 0.0, -0.05), rng.randf() * TAU, true)
	d.add_prop(&"green_chair" if rng.randf() < 0.6 else &"school_chair", xf * (at + Vector3(0.0, 0.0, -0.85)), yaw, true, true)


static func _plant_group(d: StreetDressing, xf: Transform3D, yaw: float, at: Vector3, rng: RandomNumberGenerator) -> void:
	d.add_prop(&"planter_small", xf * at, yaw + rng.randf() * TAU, true, true)
	if rng.randf() < 0.5:
		d.add_prop(&"planter_small", xf * (at + Vector3(0.9, 0.0, 0.3)), yaw + rng.randf() * TAU, true, true)


static func _shelf_group(d: StreetDressing, xf: Transform3D, yaw: float, at: Vector3, rng: RandomNumberGenerator) -> void:
	for s: float in [-0.7, 0.7]:
		var shelf := d.add_prop(&"shelves", xf * (at + Vector3(s, 0.0, 0.0)), yaw + PI, true, true)
		if shelf != null and rng.randf() < 0.6:
			d.add_on_top(&"box" if rng.randf() < 0.5 else &"bottles", shelf, Vector3.ZERO, rng.randf() * TAU, true)


static func _sofa_group(d: StreetDressing, xf: Transform3D, yaw: float, at: Vector3, rng: RandomNumberGenerator) -> void:
	d.add_prop(&"sofa" if rng.randf() < 0.6 else &"lounge_chair", xf * (at + Vector3(0.0, 0.0, 0.8)), yaw + PI, true, true)
	var low := d.add_prop(&"table_coffee", xf * (at + Vector3(0.0, 0.0, -0.4)), yaw, true, true)
	if low != null:
		d.add_on_top(FRAGILE[rng.randi_range(0, FRAGILE.size() - 1)], low, Vector3.ZERO, rng.randf() * TAU, true)
	if rng.randf() < 0.5:
		var cab := d.add_prop(&"cabinet", xf * (at + Vector3(0.0, 0.0, -1.3)), yaw, true, true)
		if cab != null:
			d.add_on_top(&"tv_a" if rng.randf() < 0.5 else &"tv_b", cab, Vector3.ZERO, PI, true)


static func _kitchen_group(d: StreetDressing, xf: Transform3D, yaw: float, at: Vector3, rng: RandomNumberGenerator) -> void:
	var cab := d.add_prop(&"cabinet" if rng.randf() < 0.6 else &"console", xf * at, yaw, true, true)
	if cab != null:
		d.add_on_top(&"microwave", cab, Vector3(-0.2, 0.0, 0.0), 0.0, true)
		d.add_on_top(&"kettle" if rng.randf() < 0.6 else &"jug", cab, Vector3(0.3, 0.0, 0.0), rng.randf() * TAU, true)
	if rng.randf() < 0.5:
		d.add_prop(&"stove", xf * (at + Vector3(1.1, 0.0, 0.0)), yaw, true, true)


static func _bed_group(d: StreetDressing, xf: Transform3D, yaw: float, at: Vector3, rng: RandomNumberGenerator) -> void:
	d.add_prop(&"bed", xf * at, yaw + (PI if rng.randf() < 0.5 else 0.0), true, true)
	var night := d.add_prop(&"nightstand", xf * (at + Vector3(1.2, 0.0, 0.6)), yaw, true, true)
	if night != null:
		d.add_on_top(&"desk_lamp" if rng.randf() < 0.6 else &"clock", night, Vector3.ZERO, rng.randf() * TAU, true)


static func _dining_group(d: StreetDressing, xf: Transform3D, yaw: float, at: Vector3, rng: RandomNumberGenerator) -> void:
	var table := d.add_prop(&"table_dining" if rng.randf() < 0.6 else &"table_round", xf * at, yaw, true, true)
	if table != null:
		_cover_inside(d, table, rng)
	for s: float in [-1.0, 1.0]:
		d.add_prop(&"dining_chair", xf * (at + Vector3(s * 1.05, 0.0, 0.0)), yaw + s * PI * 0.5 + PI, true, true)


static func _cover_inside(d: StreetDressing, table: BreakableProp, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(1, 3):
		var x := rng.randf_range(-0.35, 0.35) * table.size.x
		d.add_on_top(FRAGILE[rng.randi_range(0, FRAGILE.size() - 1)], table, Vector3(x, 0.0, rng.randf_range(-0.15, 0.15)), rng.randf() * TAU, true)


## Puts things on a table: more on a wide one, mostly fragile.
static func _cover(d: StreetDressing, table: BreakableProp, rng: RandomNumberGenerator) -> void:
	var n := clampi(int(table.size.x / 0.42), 2, 5)
	var span := table.size.x * 0.5 - 0.22
	var depth := maxf(table.size.z * 0.5 - 0.2, 0.0)
	for i in n:
		var id := FRAGILE[rng.randi_range(0, FRAGILE.size() - 1)] if rng.randf() < 0.68 else STURDY[rng.randi_range(0, STURDY.size() - 1)]
		var x := lerpf(-span, span, (i + 0.5) / n)
		d.add_on_top(id, table, Vector3(x, 0.0, rng.randf_range(-depth, depth) * 0.6), rng.randf() * TAU)
