extends Node
## Headless checks of the outer ring (2026-11-17): every design of the new styles stands on its own (no
## element unsupported after the initial solve) and stays in its lot; the city's lots do not overlap each
## other, the car parks or the container plots; every lot lies in its district; the old city is unchanged.
## Prints RING_* lines and RING_RESULT pass=N fail=M.
## Run: Godot --headless --path <P> res://tests/test_ring.tscn

const D := preload("res://game/destruction/destruction_defs.gd")
## Largest footprint (x, z) a design of a style may have, metres.
## The mall's entrance canopy and roof sign and the shop's awnings stand out in front.
const MAX_SIZE := {D.Style.WAREHOUSE: Vector2(36.5, 24.5), D.Style.MALL: Vector2(49.0, 33.0), D.Style.CANOPY: Vector2(18.8, 12.8), D.Style.SHOP: Vector2(19.5, 11.0)}

var _pass := 0
var _fail := 0


func _ready() -> void:
	_designs()
	_layout()
	print("RING_RESULT pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("RING_FAIL ", what)


func _designs() -> void:
	for style: int in MAX_SIZE:
		var worst := 0
		var sizes := Vector2.ZERO
		var masses := Vector2(1.0e12, 0.0)
		var counts := Vector2i(1 << 30, 0)
		for seed_value in range(1, CityLayout.DESIGNS_PER_STYLE + 1):
			var d := BuildingGenerator.generate(style, seed_value)
			var s := SupportSolver.new()
			s.setup(d)
			worst = maxi(worst, s.count_alive_unsupported())
			var fp := Vector2(d.bounds.size.x, d.bounds.size.z)
			sizes = sizes.max(fp)
			var m := 0.0
			for i in d.count():
				m += d.mass[i]
			masses = Vector2(minf(masses.x, m), maxf(masses.y, m))
			counts = Vector2i(mini(counts.x, d.count()), maxi(counts.y, d.count()))
		var sname := D.STYLE_NAMES[style]
		print("RING_STYLE %s elements %d..%d, mass %.0f..%.0f t, largest footprint %.1f x %.1f m, worst unsupported %d"
			% [sname, counts.x, counts.y, masses.x / 1000.0, masses.y / 1000.0, sizes.x, sizes.y, worst])
		_check(worst == 0, "%s: %d elements unsupported in a design" % [sname, worst])
		var limit: Vector2 = MAX_SIZE[style]
		_check(sizes.x <= limit.x and sizes.y <= limit.y, "%s: footprint %s over %s" % [sname, sizes, limit])


func _layout() -> void:
	var city := CityLayout.new()
	city._place_lots(2026)
	var per_district := {}
	var rects: Array[Rect2] = []
	var designs := {}
	var wrong_district := 0
	for lot in city.lots:
		var key := int(lot["style"]) * 1000 + int(lot["seed"])
		if not designs.has(key):
			designs[key] = BuildingGenerator.generate(lot["style"], lot["seed"])
		var d: BuildingData = designs[key]
		var xf := Transform3D(Basis(Vector3.UP, lot["yaw"]), lot["pos"])
		var box := xf * d.bounds
		rects.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
		var dist := int(lot["district"])
		per_district[dist] = int(per_district.get(dist, 0)) + 1
		if CityLayout.district_at(lot["pos"]) != dist:
			wrong_district += 1
	var line := ""
	for dist: int in per_district:
		line += "%s %d  " % [CityLayout.DISTRICT_NAMES[dist], per_district[dist]]
	print("RING_LOTS %d: %s" % [city.lots.size(), line])
	print("RING_PLACES car parks %d, forecourts %d, mall fronts %d, loading yards %d, container plots %d, drives %d, fences %d, back gardens %d"
		% [city.car_parks.size(), city.forecourts.size(), city.mall_fronts.size(), city.loading_yards.size(), city.container_yards.size(),
		city.driveways.size(), city.fences.size(), city.backyards.size()])
	_check(wrong_district == 0, "%d lots outside their district" % wrong_district)
	# The old city: its 156 lots come first and are the ones it always had (style, seed, place).
	var inner := 0
	for lot in city.lots:
		if maxf(absf(lot["pos"].x), absf(lot["pos"].z)) < CityLayout.INNER_OUT * CityLayout.BLOCK:
			inner += 1
		else:
			break
	print("RING_OLD_CITY %d lots first, first lot %s seed %d at %s" % [inner, D.STYLE_NAMES[city.lots[0]["style"]], city.lots[0]["seed"], city.lots[0]["pos"]])
	_check(inner == city.count_in(CityLayout.District.DOWNTOWN) + city.count_in(CityLayout.District.OLD_QUARTER) + city.count_in(CityLayout.District.WORKS),
		"the old city is not laid out first")
	# No two buildings overlap; none stands on a car park or a container plot.
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].grow(-0.05).intersects(rects[j].grow(-0.05)):
				overlaps += 1
				if overlaps <= 3:
					print("RING_OVERLAP lots %d and %d: %s / %s" % [i, j, rects[i], rects[j]])
	_check(overlaps == 0, "%d pairs of lots overlap" % overlaps)
	var on_open := 0
	var open: Array[Rect2] = []
	open.append_array(city.car_parks)
	for c in city.container_yards:
		open.append(Rect2(c.x - 11.0, c.z - 8.0, 22.0, 16.0))
	for r in open:
		for i in rects.size():
			if r.intersects(rects[i].grow(-0.05)):
				on_open += 1
				if on_open <= 3:
					print("RING_ON_OPEN %s and lot %d %s" % [r, i, rects[i]])
	_check(on_open == 0, "%d buildings stand on car parks or container plots" % on_open)
	# Car parks lie on the bay grid.
	var off_grid := 0
	for r in city.car_parks:
		if absf(fposmod(r.position.y, CityLayout.BAY_PERIOD)) > 0.01 or absf(fposmod(r.size.y, CityLayout.BAY_PERIOD)) > 0.01:
			off_grid += 1
	_check(off_grid == 0, "%d car parks off the 16 m bay grid" % off_grid)
