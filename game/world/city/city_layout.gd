class_name CityLayout
extends RefCounted
## The city of the first Table: 6 x 6 blocks around the central crossing (roads every 128 m, ring roads at
## 256 m and 384 m). The old city inside the first ring road is split into four districts that meet at the
## crossing where Trophe lands, and each quarter goes on into an outer ring of its own:
##
##   -x, +z  THE PARK      no buildings: lawns, groves, bushes (the outer ring is park as well)
##   +x, +z  DOWNTOWN      towers around a plaza in every block, a few lower blocks between them
##           THE STRIP     (outer ring) malls behind their car parks, fuel stations, rows of shops
##   -x, -z  OLD QUARTER   brick apartments along the streets, houses behind them and in rows
##           SUBURBS       (outer ring) detached houses with front fences, driveways and back gardens
##   +x, -z  WORKS         parking decks, brick sheds, open yards
##           THE YARDS     (outer ring) corrugated warehouses round a loading yard, container stacks
##
## build() places every building dormant (StructureManager wakes what the player comes near). The layout
## is seeded: the same city every run, and the old city is laid out first, so it is the same as it was
## before the outer ring was added. Nature, street dressing and tests ask this class where things are.

const D := preload("res://game/destruction/destruction_defs.gd")

enum District { NONE, DOWNTOWN, OLD_QUARTER, WORKS, PARK, STRIP, YARDS, SUBURBS }
const DISTRICT_NAMES: PackedStringArray = ["", "Downtown", "Old Quarter", "Works", "The Park", "The Strip", "The Yards", "Suburbs"]

const BLOCK := 128.0
## Blocks from the central crossing to the edge of the city in each direction.
static var BLOCKS_OUT := 1 if _small() else 3
## Blocks of the old city (inside the first ring road) in each direction.
static var INNER_OUT := 1 if _small() else 2
## Half the side of the square inside a block that is neither road nor sidewalk.
const LOT_HALF := 52.0
## Different designs per building style (generator seeds 1..N); lots share them.
const DESIGNS_PER_STYLE := 16
## Car parks: bays 2.5 m wide in rows along x, two rows of 5 m back to back after a 6 m aisle, every 16 m
## in z, on the world grid the terrain shader paints them on (surface mask alpha below 0.5). A car park is
## a rectangle whose z edges lie on that 16 m grid.
const BAY_W := 2.5
const BAY_PERIOD := 16.0
const BAY_ROWS: Array[float] = [8.5, 13.5]   ## row centres, metres into a period
## The paths through a park block, in block coordinates (x, z): in from the west and out to the north
## past the picnic spot, with a branch to the south. They keep clear of the three groves.
const PARK_PATHS := [
	[Vector2(-52.0, 4.0), Vector2(-8.0, 3.0), Vector2(8.0, 12.0), Vector2(20.0, 22.0), Vector2(26.0, 38.0), Vector2(30.0, 52.0)],
	[Vector2(-8.0, 3.0), Vector2(-3.0, -25.0), Vector2(-2.0, -52.0)],
]
const PATH_HALF_WIDTH := 1

var lots: Array[Dictionary] = []   ## {bid, style, seed, pos, yaw, district, size (x, z footprint as built)}
## Open places the layout leaves between its buildings, for whoever fills them (see PropSets):
var plazas: Array[Vector3] = []    ## the middle of every Downtown block (34 x 34 m)
var courts: Array[Vector3] = []    ## the strip between the house rows of an apartment block (60 x 16 m along x)
var greens: Array[Vector3] = []    ## the green in the middle of a block of house rows (28 x 28 m)
var yards: Array[Vector3] = []     ## empty plots of the Works (48 x 30 m)
var gardens: Array[Dictionary] = []   ## {pos, yaw}: a spot beside a house of the Old Quarter
## The outer ring (2026-11-17):
var car_parks: Array[Rect2] = []        ## painted car parks (x, z), see BAY_PERIOD
var asphalt: Array[Rect2] = []          ## asphalt without bays (fuel station forecourts)
var paved: Array[Rect2] = []            ## paving: the drives and front paths of the Suburbs
var mall_fronts: Array[Vector3] = []    ## the paved front of a mall between its doors and its car park (96 x 18 m)
var forecourts: Array[Dictionary] = []  ## {pos, seed}: the middle of a fuel station canopy (18 x 12 m) and its design
var loading_yards: Array[Vector3] = []  ## the yard between the two rows of warehouses of a Yards block (96 x 32 m)
var container_yards: Array[Vector3] = []   ## a plot of shipping container stacks instead of a warehouse (36 x 24 m)
var driveways: Array[Dictionary] = []   ## {pos, yaw}: where a suburban house keeps its car
var fences: Array[Dictionary] = []      ## {pos, length}: a run of front fence along x
var backyards: Array[Dictionary] = []   ## {pos, yaw}: a spot in the back garden of a suburban house
var lawns: Array[Vector3] = []          ## the lawn in the middle of a suburban block (96 x 16 m), for a few trees

var _rng := RandomNumberGenerator.new()


## The offsets of the road centre lines of the city, the same along x and z.
## The browser demo (web or "demo" feature) builds the 2 x 2 blocks round the crossing only: one block of
## each old-city district. Tests may set BLOCKS_OUT / INNER_OUT before the world is built.
static func _small() -> bool:
	return OS.has_feature("web") or OS.has_feature("demo")


static func road_lines() -> PackedFloat32Array:
	var lines := PackedFloat32Array()
	for i in range(-BLOCKS_OUT, BLOCKS_OUT + 1):
		lines.append(i * BLOCK)
	return lines


## How far the city reaches from the centre along a road (the ring road and its sidewalk included).
static func half_extent() -> float:
	return BLOCKS_OUT * BLOCK + 12.0


static func district_at(pos: Vector3) -> int:
	var limit := half_extent()
	if absf(pos.x) > limit or absf(pos.z) > limit:
		return District.NONE
	var outer := maxf(absf(pos.x), absf(pos.z)) > INNER_OUT * BLOCK
	if pos.x >= 0.0:
		if pos.z >= 0.0:
			return District.STRIP if outer else District.DOWNTOWN
		return District.YARDS if outer else District.WORKS
	if pos.z >= 0.0:
		return District.PARK
	return District.SUBURBS if outer else District.OLD_QUARTER


## Every block as (bx, bz), its centre at ((bx + 0.5) * BLOCK, (bz + 0.5) * BLOCK): the old city first, in
## the order it always had, then the outer ring.
static func block_order() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for bx in range(-INNER_OUT, INNER_OUT):
		for bz in range(-INNER_OUT, INNER_OUT):
			out.append(Vector2i(bx, bz))
	for bx in range(-BLOCKS_OUT, BLOCKS_OUT):
		for bz in range(-BLOCKS_OUT, BLOCKS_OUT):
			if bx < -INNER_OUT or bx >= INNER_OUT or bz < -INNER_OUT or bz >= INNER_OUT:
				out.append(Vector2i(bx, bz))
	return out


static func block_centre(b: Vector2i) -> Vector3:
	return Vector3(b.x * BLOCK + BLOCK * 0.5, 0.0, b.y * BLOCK + BLOCK * 0.5)


## Centres of the blocks of one district (old city first).
static func block_centres(district: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for b in block_order():
		var c := block_centre(b)
		if district_at(c) == district:
			out.append(c)
	return out


## Places the whole city. Returns the number of buildings.
func build(structures: StructureManager, seed_value: int = 2026) -> int:
	_place_lots(seed_value)
	var designs := {}
	for lot in lots:
		_add_lot(structures, lot, designs)
	return lots.size()


## The same as build(), spread over frames so a loading screen stays alive: it yields to the next frame
## about every 90 ms and reports the share of buildings placed to `progress` (0..1).
func build_async(structures: StructureManager, tree: SceneTree, progress: Callable = Callable(), seed_value: int = 2026) -> int:
	_place_lots(seed_value)
	var designs := {}
	var t0 := Time.get_ticks_msec()
	for i in lots.size():
		_add_lot(structures, lots[i], designs)
		if Time.get_ticks_msec() - t0 >= 90:
			if progress.is_valid():
				progress.call(float(i + 1) / lots.size())
			await tree.process_frame
			t0 = Time.get_ticks_msec()
	return lots.size()


func _place_lots(seed_value: int) -> void:
	_rng.seed = seed_value
	lots.clear()
	for list: Array in [plazas, courts, greens, yards, gardens, car_parks, asphalt, paved, mall_fronts, forecourts, loading_yards,
			container_yards, driveways, fences, backyards, lawns]:
		list.clear()
	for b in block_order():
		var c := block_centre(b)
		match district_at(c):
			District.DOWNTOWN:
				_downtown_block(c)
			District.OLD_QUARTER:
				if posmod(b.x + b.y, 2) == 0:
					_terrace_block(c)
				else:
					_cottage_block(c)
			District.WORKS:
				_works_block(c)
			District.STRIP:
				if posmod(b.x + b.y, 2) == 0:
					_mall_block(c)
				else:
					_fuel_block(c)
			District.YARDS:
				_yards_block(c)
			District.SUBURBS:
				_suburb_block(c)


## Lots with the same style and seed share one generated design (StructureManager only reads it).
func _add_lot(structures: StructureManager, lot: Dictionary, designs: Dictionary) -> void:
	var xf := Transform3D(Basis(Vector3.UP, lot["yaw"]), lot["pos"])
	var key := int(lot["style"]) * 1000 + int(lot["seed"])
	if not designs.has(key):
		designs[key] = BuildingGenerator.generate(lot["style"], lot["seed"])
	var bid := structures.add_building(designs[key], xf, false)
	lot["bid"] = bid
	var fp := structures.building_footprint(bid)
	lot["size"] = fp.size


## The surface of the Table under the city, for WorldTerrain.set_surface_mask (call after build):
## paving stones under Downtown, the Strip and the apartment courts, asphalt in the blocks of the Works and
## the Yards, on the forecourts and on the car parks (with painted bays: alpha 0), paths through the Park,
## paved drives in the Suburbs. Only the look and the top stratum change, not the height of the ground.
func surface_mask() -> Image:
	var im := TerrainStrata.default_mask()
	var half := TerrainStrata.MASK_SIZE >> 1
	var paving := Color8(0, 255, 0, 255)
	var tarmac := Color8(255, 0, 0, 255)
	var bays := Color8(255, 0, 0, 0)
	var inner := int(LOT_HALF)
	for c in block_centres(District.DOWNTOWN):
		im.fill_rect(Rect2i(half + int(c.x) - inner, half + int(c.z) - inner, inner * 2, inner * 2), paving)
	for c in block_centres(District.STRIP):
		im.fill_rect(Rect2i(half + int(c.x) - inner, half + int(c.z) - inner, inner * 2, inner * 2), paving)
	for c in block_centres(District.WORKS) + block_centres(District.YARDS):
		im.fill_rect(Rect2i(half + int(c.x) - inner, half + int(c.z) - inner, inner * 2, inner * 2), tarmac)
	for court in courts:
		im.fill_rect(Rect2i(half + int(court.x) - 31, half + int(court.z) - 9, 62, 18), paving)
	for r in asphalt:
		im.fill_rect(_mask_rect(r, half), tarmac)
	for r in car_parks:
		im.fill_rect(_mask_rect(r, half), bays)
	for r in paved:
		im.fill_rect(_mask_rect(r, half), paving)
	for c in block_centres(District.PARK):
		for path: Array in PARK_PATHS:
			for i in range(path.size() - 1):
				var a: Vector2 = path[i]
				var b: Vector2 = path[i + 1]
				var steps := int(a.distance_to(b)) + 1
				for k in steps + 1:
					var p := a.lerp(b, float(k) / steps)
					im.fill_rect(Rect2i(half + int(roundf(c.x + p.x)) - PATH_HALF_WIDTH, half + int(roundf(c.z + p.y)) - PATH_HALF_WIDTH,
						PATH_HALF_WIDTH * 2 + 1, PATH_HALF_WIDTH * 2 + 1), paving)
	return im


static func _mask_rect(r: Rect2, half: int) -> Rect2i:
	return Rect2i(half + int(floorf(r.position.x)), half + int(floorf(r.position.y)), int(r.size.x), int(r.size.y))


## The lot of the given style nearest to a point ({} when there is none).
func nearest_lot(style: int, from: Vector3) -> Dictionary:
	var best := {}
	var best_d := 1.0e18
	for lot in lots:
		if int(lot["style"]) != style:
			continue
		var d := (lot["pos"] as Vector3).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = lot
	return best


func count_in(district: int) -> int:
	var n := 0
	for lot in lots:
		if int(lot["district"]) == district:
			n += 1
	return n


# --------------------------------------------------------------------------------------------------
# Blocks of the old city
# --------------------------------------------------------------------------------------------------

## Eight lots around a plaza: mostly towers, now and then a lower block.
func _downtown_block(c: Vector3) -> void:
	plazas.append(c)
	for i in range(-1, 2):
		for j in range(-1, 2):
			if i == 0 and j == 0:
				continue   # the plaza
			var style: int = D.Style.TOWER if _rng.randf() < 0.75 else D.Style.APARTMENT
			_lot(style, c + Vector3(i * 34.0, 0.0, j * 34.0), _quarter_turn() if style == D.Style.TOWER else _half_turn(), District.DOWNTOWN)


## Apartment rows along the two streets on the z sides, houses down the other two sides and in the court.
func _terrace_block(c: Vector3) -> void:
	courts.append(c)
	for side: float in [-1.0, 1.0]:
		for x: float in [-34.0, 0.0, 34.0]:
			# Side 0 of an apartment (its door and its shops) faces the street. The draw of the old random
			# turn is kept so every later lot keeps its seed.
			var _old_turn := _half_turn()
			_lot(D.Style.APARTMENT, c + Vector3(x, 0.0, side * 40.0), 0.0 if side < 0.0 else PI, District.OLD_QUARTER)
		for z: float in [-16.0, 0.0, 16.0]:
			_lot(D.Style.HOUSE, c + Vector3(side * 44.0, 0.0, z), _quarter_turn(), District.OLD_QUARTER)
		for x: float in [-22.0, -8.0, 8.0, 22.0]:
			_lot(D.Style.HOUSE, c + Vector3(x, 0.0, side * 14.0), _half_turn(), District.OLD_QUARTER)


## Rows of houses around a small green in the middle.
func _cottage_block(c: Vector3) -> void:
	greens.append(c)
	for i in 6:
		for j in 6:
			if (i == 2 or i == 3) and (j == 2 or j == 3):
				continue   # the green
			var at := c + Vector3(-40.0 + i * 16.0, 0.0, -40.0 + j * 16.0)
			_lot(D.Style.HOUSE, at, _half_turn(), District.OLD_QUARTER)
			if _rng.randf() < 0.45:
				gardens.append({"pos": at + Vector3(0.0, 0.0, 7.2), "yaw": _rng.randf() * TAU})


## Six plots: parking decks, brick sheds and open yards.
func _works_block(c: Vector3) -> void:
	for x: float in [-26.0, 26.0]:
		for z: float in [-34.0, 0.0, 34.0]:
			var roll := _rng.randf()
			if roll < 0.15:
				yards.append(c + Vector3(x, 0.0, z))
				continue   # a yard
			var style: int = D.Style.PARKING if roll < 0.8 else D.Style.APARTMENT
			_lot(style, c + Vector3(x, 0.0, z), _half_turn(), District.WORKS)


# --------------------------------------------------------------------------------------------------
# Blocks of the outer ring (2026-11-17)
# --------------------------------------------------------------------------------------------------

## A mall at the back of the block with a shop on either side, its paved front, and a car park of two
## double rows between that and the street.
func _mall_block(c: Vector3) -> void:
	_lot(D.Style.MALL, c + Vector3(0.0, 0.0, 24.0), 0.0, District.STRIP)
	for sx: float in [-1.0, 1.0]:
		_lot(D.Style.SHOP, c + Vector3(sx * 40.0, 0.0, 30.0), 0.0, District.STRIP)
	mall_fronts.append(c + Vector3(0.0, 0.0, -4.0))
	car_parks.append(Rect2(c.x - 48.0, c.z - 48.0, 96.0, 32.0))


## A fuel station on the corner (the canopy over the pumps, its shop behind the forecourt), a car park
## beside it and a row of shops facing the street behind.
func _fuel_block(c: Vector3) -> void:
	var canopy := c + Vector3(-26.0, 0.0, -30.0)
	_lot(D.Style.CANOPY, canopy, 0.0, District.STRIP)
	forecourts.append({"pos": canopy, "seed": lots[lots.size() - 1]["seed"]})
	_lot(D.Style.SHOP, c + Vector3(-26.0, 0.0, -2.0), 0.0, District.STRIP)
	asphalt.append(Rect2(c.x - 50.0, c.z - 50.0, 46.0, 40.0))
	car_parks.append(Rect2(c.x, c.z - 48.0, 48.0, 32.0))
	for x: float in [-33.0, -11.0, 11.0, 33.0]:
		_lot(D.Style.SHOP, c + Vector3(x, 0.0, 38.0), PI, District.STRIP)


## Four warehouses round a loading yard, their roller doors facing it; now and then a plot of container
## stacks instead of one of them.
func _yards_block(c: Vector3) -> void:
	loading_yards.append(c)
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var at := c + Vector3(sx * 26.0, 0.0, sz * 28.0)
			if _rng.randf() < 0.25:
				container_yards.append(at)
				continue
			_lot(D.Style.WAREHOUSE, at, 0.0 if sz > 0.0 else PI, District.YARDS)


## Two rows of detached houses facing the streets, each with a front fence cut open for its path and its
## drive, a car in the drive and a back garden; a lawn with a few trees down the middle of the block.
func _suburb_block(c: Vector3) -> void:
	lawns.append(c)
	for sz: float in [-1.0, 1.0]:
		var yaw := 0.0 if sz < 0.0 else PI
		for x: float in [-39.0, -13.0, 13.0, 39.0]:
			var at := c + Vector3(x, 0.0, sz * 32.0)
			_lot(D.Style.HOUSE, at, yaw, District.SUBURBS)
			driveways.append({"pos": at + Vector3(7.6, 0.0, sz * 9.0), "yaw": yaw})
			# The drive from beside the house out to the street, and the path from the door.
			var z_street := c.z + sz * LOT_HALF
			paved.append(Rect2(at.x + 5.6, minf(at.z, z_street), 4.0, 20.0))
			paved.append(Rect2(at.x - 1.0, minf(at.z + sz * 3.0, z_street), 2.0, 17.0))
			var fz := c.z + sz * (LOT_HALF - 3.0)
			fences.append({"pos": Vector3(at.x - 6.75, 0.0, fz), "length": 11.5})
			fences.append({"pos": Vector3(at.x + 3.25, 0.0, fz), "length": 4.5})
			fences.append({"pos": Vector3(at.x + 11.25, 0.0, fz), "length": 2.5})
			backyards.append({"pos": at + Vector3(_rng.randf_range(-4.0, 4.0), 0.0, -sz * 13.0), "yaw": _rng.randf() * TAU})


func _lot(style: int, pos: Vector3, yaw: float, district: int) -> void:
	lots.append({"bid": -1, "style": style, "seed": _rng.randi_range(1, DESIGNS_PER_STYLE), "pos": pos, "yaw": yaw, "district": district, "size": Vector2.ZERO})


func _half_turn() -> float:
	return PI if _rng.randf() < 0.5 else 0.0


func _quarter_turn() -> float:
	return PI * 0.5 * _rng.randi_range(0, 3)
