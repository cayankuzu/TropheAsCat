class_name BuildingGenerator
extends RefCounted
## Procedural buildings made of structural elements with quantised real sizes.
## Topology (rests-on / lateral / attached / touch) comes from the generator's grid indices, so the
## support graph never depends on geometric overlap tests.
##
## Facades (2026-11-17): every design picks a look from its seed with a second random generator, so the
## structure of a design (bays, storeys, partitions) is the same as before and only the materials and the
## facade parts change. Facade parts (ledges, cornices, awnings, balconies, chimneys, canopies, rooftop
## plant, signs) are ATTACHED elements that carry nothing and never overlap another element: they hang
## on the bay, parapet, gable or slab they belong to and fall when it goes.
##
## Conventions: storey f spans y in [f*H, (f+1)*H]. The slab of level L (L >= 1) is the floor of storey L
## and the ceiling of storey L-1; it belongs to storey L-1 in the data. Verticals of storey f rest on the
## verticals below and on the level-f slab panels next to their base, slabs rest on the verticals of the
## storey below them, so RESTS_ON edges always point downward (acyclic support flow).

const D := preload("res://game/destruction/destruction_defs.gd")
const H := D.STOREY_H

const COLUMN := D.Kind.COLUMN
const SLAB := D.Kind.SLAB
const WALL := D.Kind.WALL
const PIER := D.Kind.PIER
const SILL := D.Kind.SILL
const LINTEL := D.Kind.LINTEL
const CORE := D.Kind.CORE
const PARTITION := D.Kind.PARTITION
const GLASS := D.Kind.GLASS
const MULLION := D.Kind.MULLION
const PARAPET := D.Kind.PARAPET
const RAILING := D.Kind.RAILING
const ROOF := D.Kind.ROOF
const GABLE := D.Kind.GABLE
const FLOOR := D.Kind.FLOOR
const DOOR := D.Kind.DOOR
const RIDGE := D.Kind.RIDGE
const SPANDREL := D.Kind.SPANDREL
const TRIM := D.Kind.TRIM
const AWNING := D.Kind.AWNING
const BALCONY_SLAB := D.Kind.BALCONY
const CHIMNEY := D.Kind.CHIMNEY
const FIXTURE := D.Kind.FIXTURE

const VERT := D.Role.VERTICAL
const HORZ := D.Role.HORIZONTAL
const ATT := D.Role.ATTACHED

# Bay content slots of a perimeter wall bay.
const S_PA := 0
const S_PB := 1
const S_SILL := 2
const S_GLASS := 3
const S_LINTEL := 4
const S_WALL := 5

enum BayType { WINDOW, SOLID, DOOR, BALCONY }

## Tower looks: curtain glass, mullion (frame), spandrel panel and crown materials. Stone looks have deep
## stone piers and tall stone spandrels, so their windows read as punched openings.
const TOWER_LOOKS := [
	{"glass": &"glass_sky", "frame": &"alu", "panel": &"panel_white", "crown": &"panel_white", "stone": false},
	{"glass": &"glass_teal", "frame": &"metal_white", "panel": &"panel_graphite", "crown": &"panel_graphite", "stone": false},
	{"glass": &"glass_bronze", "frame": &"panel_champagne", "panel": &"panel_champagne", "crown": &"panel_champagne", "stone": false},
	{"glass": &"glass_silver", "frame": &"stone", "panel": &"stone", "crown": &"stone", "stone": true},
	{"glass": &"glass_sky", "frame": &"stone_warm", "panel": &"stone_warm", "crown": &"stone_warm", "stone": true},
	{"glass": &"glass_silver", "frame": &"panel_graphite", "panel": &"panel_graphite", "crown": &"alu", "stone": false},
]
## Apartment looks: upper walls, the stone ground floor, trim, window frames, balcony railings.
const APARTMENT_LOOKS := [
	{"wall": &"brick", "base": &"stone", "trim": &"trim_white", "frame": "white", "rail": &"rail_black"},
	{"wall": &"brick_old", "base": &"stone_warm", "trim": &"trim_cream", "frame": "green", "rail": &"rail_black"},
	{"wall": &"brick_dark", "base": &"stone", "trim": &"trim_white", "frame": "white", "rail": &"rail_black"},
	{"wall": &"render_cream", "base": &"stone_warm", "trim": &"trim_white", "frame": "green", "rail": &"rail_green"},
	{"wall": &"render_sage", "base": &"stone", "trim": &"trim_white", "frame": "white", "rail": &"rail_black"},
	{"wall": &"render_terracotta", "base": &"stone_warm", "trim": &"trim_cream", "frame": "white", "rail": &"rail_black"},
	{"wall": &"render_sky", "base": &"stone", "trim": &"trim_white", "frame": "white", "rail": &"rail_white"},
	{"wall": &"render_ochre", "base": &"stone_warm", "trim": &"trim_white", "frame": "brown", "rail": &"rail_black"},
	{"wall": &"render_rose", "base": &"stone", "trim": &"trim_white", "frame": "white", "rail": &"rail_black"},
]
## Shop fronts: [sign band, awning, shop window].
const SHOP_BRANDS := [
	[&"sign_green", &"awning_green", &"shop_green"], [&"sign_burgundy", &"awning_red", &"shop_red"],
	[&"sign_navy", &"awning_blue", &"shop_blue"], [&"sign_gold", &"awning_yellow", &"shop_yellow"],
	[&"sign_teal", &"awning_teal", &"shop_teal"],
]
const PASTELS: Array[StringName] = [&"pastel_cream", &"pastel_sage", &"pastel_rose", &"pastel_sky", &"pastel_ochre"]
const HOUSE_FRAMES: PackedStringArray = ["white", "white", "white", "green", "brown", "black"]
const HOUSE_DOORS: Array[StringName] = [&"door_red", &"door_green", &"door_blue", &"door_white", &"door_black", &"door_yellow"]
const HOUSE_ROOFS: Array[StringName] = [&"roof", &"roof", &"roof_slate", &"roof_brown"]
const DECKS: Array[StringName] = [&"concrete_light", &"deck_red", &"deck_blue", &"deck_yellow", &"deck_green"]
const CLADDINGS: Array[StringName] = [&"clad_blue", &"clad_grey", &"clad_red", &"clad_white", &"clad_green"]


static func generate(style: int, seed_value: int) -> BuildingData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d := BuildingData.new()
	d.style = style
	d.seed_value = seed_value
	match style:
		D.Style.TOWER:
			_tower(d, rng)
		D.Style.APARTMENT:
			_apartment(d, rng)
		D.Style.PARKING:
			_parking(d, rng)
		D.Style.WAREHOUSE:
			_warehouse(d, rng)
		D.Style.MALL:
			_mall(d, rng)
		D.Style.CANOPY:
			_canopy(d, rng)
		D.Style.SHOP:
			_shop(d, rng)
		_:
			_house(d, rng)
	d.finalize()
	return d


static func _xf(center: Vector3, along_z: bool = false) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI * 0.5) if along_z else Basis.IDENTITY, center)


# --------------------------------------------------------------------------------------------------
# Frame buildings (tower, parking): columns on a 6 m grid, 3 x 3 m slab panels, concrete cores.
# --------------------------------------------------------------------------------------------------

## Grid point (i, j) of a 6 m grid touches the 3 m panels (2i-1|2i, 2j-1|2j).
static func _panels_around(i: int, j: int) -> Array[Vector2i]:
	return [Vector2i(2 * i - 1, 2 * j - 1), Vector2i(2 * i, 2 * j - 1), Vector2i(2 * i - 1, 2 * j), Vector2i(2 * i, 2 * j)]


## Core walls around bay (ci, cj): side 0 south, 1 north, 2 west, 3 east, two 2.7 m segments per side.
## Returns [side, seg, centre_xz, along_z, panels(outside, inside), corner grid point].
static func _core_walls(ci: int, cj: int, x0: float, z0: float, sides: Array[int]) -> Array:
	var out: Array = []
	for side in sides:
		for seg in 2:
			var along := 0.3 + 1.35 + 2.7 * seg
			var c := Vector2.ZERO
			var pans: Array[Vector2i] = []
			var corner := Vector2i.ZERO
			match side:
				0:
					c = Vector2(x0 + ci * 6.0 + along, z0 + cj * 6.0)
					pans = [Vector2i(2 * ci + seg, 2 * cj - 1), Vector2i(2 * ci + seg, 2 * cj)]
					corner = Vector2i(ci + seg, cj)
				1:
					c = Vector2(x0 + ci * 6.0 + along, z0 + (cj + 1) * 6.0)
					pans = [Vector2i(2 * ci + seg, 2 * cj + 2), Vector2i(2 * ci + seg, 2 * cj + 1)]
					corner = Vector2i(ci + seg, cj + 1)
				2:
					c = Vector2(x0 + ci * 6.0, z0 + cj * 6.0 + along)
					pans = [Vector2i(2 * ci - 1, 2 * cj + seg), Vector2i(2 * ci, 2 * cj + seg)]
					corner = Vector2i(ci, cj + seg)
				_:
					c = Vector2(x0 + (ci + 1) * 6.0, z0 + cj * 6.0 + along)
					pans = [Vector2i(2 * ci + 2, 2 * cj + seg), Vector2i(2 * ci + 1, 2 * cj + seg)]
					corner = Vector2i(ci + 1, cj + seg)
			out.append([side, seg, c, side >= 2, pans, corner])
	return out


static func _tower(d: BuildingData, rng: RandomNumberGenerator) -> void:
	var bx := rng.randi_range(3, 5)
	var bz := rng.randi_range(3, 4)
	var floors := rng.randi_range(8, 14)
	var t := 0.3
	var vh := H - t
	var w := bx * 6.0
	var dp := bz * 6.0
	var x0 := -w * 0.5
	var z0 := -dp * 0.5
	var npx := bx * 2
	var npz := bz * 2
	var ci := bx >> 1
	var cj := bz >> 1
	d.storeys = floors + 1
	var look_rng := _look_rng(d)
	var look: Dictionary = TOWER_LOOKS[look_rng.randi() % TOWER_LOOKS.size()]
	var cols: Dictionary[Vector3i, int] = {}
	var pans: Dictionary[Vector3i, int] = {}
	var cores: Dictionary[Vector3i, int] = {}
	var core_defs := _core_walls(ci, cj, x0, z0, [0, 1, 2, 3])

	for f in floors + 1:
		var penthouse := f == floors
		# Columns of storey f.
		for i in bx + 1:
			for j in bz + 1:
				if penthouse and not (i >= ci and i <= ci + 1 and j >= cj and j <= cj + 1):
					continue
				var x := x0 + i * 6.0 + (0.3 if i == 0 else (-0.3 if i == bx else 0.0))
				var z := z0 + j * 6.0 + (0.3 if j == 0 else (-0.3 if j == bz else 0.0))
				var id := d.add(COLUMN, VERT, &"concrete", Vector3(0.6, vh, 0.6), _xf(Vector3(x, f * H + vh * 0.5, z)), f, f == 0, 0)
				cols[Vector3i(i, j, f)] = id
				if f > 0:
					d.rests_on(id, cols.get(Vector3i(i, j, f - 1), -1))
					for p in _panels_around(i, j):
						d.rests_on(id, pans.get(Vector3i(p.x, p.y, f), -1))
		# Core walls of storey f.
		for cw in core_defs:
			var c: Vector2 = cw[2]
			var key := Vector3i(cw[0], cw[1], f)
			var id := d.add(CORE, VERT, &"concrete", Vector3(2.7, vh, 0.3), _xf(Vector3(c.x, f * H + vh * 0.5, c.y), cw[3]), f, f == 0, 0)
			cores[key] = id
			if f > 0:
				d.rests_on(id, cores.get(Vector3i(cw[0], cw[1], f - 1), -1))
				for p: Vector2i in cw[4]:
					d.rests_on(id, pans.get(Vector3i(p.x, p.y, f), -1))
			var corner: Vector2i = cw[5]
			d.touch(id, cols.get(Vector3i(corner.x, corner.y, f), -1))
			if cw[1] == 1:
				d.touch(id, cores.get(Vector3i(cw[0], 0, f), -1))
		# Slab panels of level f + 1.
		var lv := f + 1
		for px in npx:
			for pz in npz:
				var in_core := (px >> 1) == ci and (pz >> 1) == cj
				if penthouse and not in_core:
					continue
				if in_core and lv < floors:
					continue   # elevator / stair shaft
				var c := Vector3(x0 + 1.5 + 3.0 * px, lv * H - t * 0.5, z0 + 1.5 + 3.0 * pz)
				var id := d.add(SLAB, HORZ, &"concrete", Vector3(3.0, t, 3.0), _xf(c), f, false, 1)
				pans[Vector3i(px, pz, lv)] = id
				d.rests_on(id, cols.get(Vector3i((px + 1) >> 1, (pz + 1) >> 1, f), -1))
				d.lateral(id, pans.get(Vector3i(px - 1, pz, lv), -1))
				d.lateral(id, pans.get(Vector3i(px, pz - 1, lv), -1))
		for cw in core_defs:
			var wall_id: int = cores[Vector3i(cw[0], cw[1], f)]
			for p: Vector2i in cw[4]:
				var pid: int = pans.get(Vector3i(p.x, p.y, lv), -1)
				if pid >= 0:
					d.rests_on(pid, wall_id)
		if penthouse:
			continue
		_curtain_wall(d, f, w, dp, npx, npz, pans, look, floors)
		# Office partitions on mid-bay lines (never on column or core lines).
		for i in bx:
			for pz in npz:
				if i == ci and pz >= 2 * cj - 1 and pz <= 2 * cj + 2:
					continue   # would cross the core walls
				if rng.randf() > 0.28:
					continue
				var x := x0 + 3.0 + 6.0 * i
				var c := Vector3(x, f * H + vh * 0.5, z0 + 1.5 + 3.0 * pz)
				var id := d.add(PARTITION, ATT, &"plaster", Vector3(3.0, vh, 0.1), _xf(c, true), f, f == 0, 0)
				for lvl in [f, f + 1]:
					d.attach(id, pans.get(Vector3i(2 * i, pz, lvl), -1))
					d.attach(id, pans.get(Vector3i(2 * i + 1, pz, lvl), -1))

	_frame_parapet(d, floors, npx, npz, x0, z0, pans)
	_tower_extras(d, look, look_rng, floors, w, dp, npx, npz, ci, cj, pans)


## A frame building's concrete parapet round the roof (level `floors`).
static func _frame_parapet(d: BuildingData, floors: int, npx: int, npz: int, x0: float, z0: float, pans: Dictionary[Vector3i, int]) -> void:
	var top := floors
	var py := top * H + 0.5
	for px in npx:
		var cx := x0 + 1.5 + 3.0 * px
		var s := d.add(PARAPET, ATT, &"concrete_light", Vector3(3.0, 1.0, 0.25), _xf(Vector3(cx, py, z0 + 0.125)), top - 1, false, 0)
		d.attach(s, pans.get(Vector3i(px, 0, top), -1))
		var n := d.add(PARAPET, ATT, &"concrete_light", Vector3(3.0, 1.0, 0.25), _xf(Vector3(cx, py, -z0 - 0.125)), top - 1, false, 0)
		d.attach(n, pans.get(Vector3i(px, npz - 1, top), -1))
	for pz in npz:
		var length := 2.75 if pz == 0 or pz == npz - 1 else 3.0
		var cz := z0 + 1.5 + 3.0 * pz + (0.125 if pz == 0 else (-0.125 if pz == npz - 1 else 0.0))
		var wst := d.add(PARAPET, ATT, &"concrete_light", Vector3(length, 1.0, 0.25), _xf(Vector3(x0 + 0.125, py, cz), true), top - 1, false, 0)
		d.attach(wst, pans.get(Vector3i(0, pz, top), -1))
		var est := d.add(PARAPET, ATT, &"concrete_light", Vector3(length, 1.0, 0.25), _xf(Vector3(-x0 - 0.125, py, cz), true), top - 1, false, 0)
		d.attach(est, pans.get(Vector3i(npx - 1, pz, top), -1))


## The entrance canopy over the two door modules of side 0, plant on the roof and (on a tower) a mast on
## the penthouse. Bay (ci, cj) is kept free of plant; -1 keeps none free.
static func _tower_extras(d: BuildingData, look: Dictionary, look_rng: RandomNumberGenerator, floors: int, w: float, dp: float,
		npx: int, npz: int, ci: int, cj: int, pans: Dictionary[Vector3i, int], mast: bool = true) -> void:
	var stone: bool = look["stone"]
	var pier_d := 0.26 if stone else 0.12
	var lo := 0.75 if stone else 0.45
	var modules := int(roundf(w / 1.5))
	var u := -w * 0.5 + 1.5 * (modules >> 1)
	var plane := -(dp * 0.5 + 0.08)
	var canopy_y := (H - lo) + 0.12 + 0.11
	var cz := plane - (pier_d - 0.03) - 0.02 - 1.1
	var canopy := d.add(TRIM, ATT, &"plant_alu", Vector3(4.2, 0.22, 2.2), _xf(Vector3(u, canopy_y, cz)), 0, false, 0)
	_attach_edge_panels(d, canopy, 0, u + w * 0.5, npx, npz, 0, pans)
	# Roof plant on panels away from the edge (parapet) and the penthouse.
	var x0 := -w * 0.5
	var z0 := -dp * 0.5
	var spots: Array[Vector2i] = []
	for px in range(1, npx - 1):
		for pz in range(1, npz - 1):
			if (px >> 1) == ci and (pz >> 1) == cj:
				continue
			spots.append(Vector2i(px, pz))
	for i in range(spots.size() - 1, 0, -1):
		var j := look_rng.randi_range(0, i)
		var tmp := spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	for k in mini(4, spots.size()):
		var p := spots[k]
		var tank := k == 3
		var size := Vector3(2.2, 2.0, 2.2) if tank else Vector3(1.6, 1.1, 1.1)
		var c := Vector3(x0 + 1.5 + 3.0 * p.x, floors * H + size.y * 0.5, z0 + 1.5 + 3.0 * p.y)
		var id := d.add(FIXTURE, ATT, &"plant_graphite" if tank else &"plant_alu", size, _xf(c, look_rng.randf() < 0.5), floors, false, 0)
		d.attach(id, pans.get(Vector3i(p.x, p.y, floors), -1))
	if not mast:
		return
	var top := Vector3(x0 + 1.5 + 3.0 * (2 * ci), (floors + 1) * H + 3.0, z0 + 1.5 + 3.0 * (2 * cj))
	var mid := d.add(FIXTURE, ATT, &"plant_alu", Vector3(0.2, 6.0, 0.2), _xf(top), floors, false, 0)
	d.attach(mid, pans.get(Vector3i(2 * ci, 2 * cj, floors + 1), -1))


## Glass curtain wall hung 8 cm outside the slab edges: 1.5 m modules, mullions on every joint and an
## opaque spandrel panel across every slab edge (floor lines). The look sets the materials; a stone look
## has 45 cm stone piers 26 cm deep and taller spandrels. On the top floor the spandrels rise 1.3 m past
## the roof as a crown band and the mullions go up with them; the two middle modules of side 0 on the
## ground floor are the doors.
static func _curtain_wall(d: BuildingData, f: int, w: float, dp: float, npx: int, npz: int, pans: Dictionary[Vector3i, int],
		look: Dictionary, floors: int) -> void:
	var stone: bool = look["stone"]
	var pier_w := 0.45 if stone else 0.08
	var pier_d := 0.26 if stone else 0.12
	var lo := 0.75 if stone else 0.45
	var hi := 0.55 if stone else 0.25
	var top := f == floors - 1
	var crown := 1.3 if top else 0.0
	var g0 := f * H + (0.0 if f == 0 else hi)
	var g1 := (f + 1) * H - lo
	var gw := 1.5 - pier_w
	var m_lo := f * H
	var m_hi := (f + 1) * H + (hi + crown if top else 0.0)
	var y := (m_lo + m_hi) * 0.5
	var s_lo := g1
	var s_hi := (f + 1) * H + hi + crown
	for side in 4:
		var along_z := side >= 2
		var half := (dp if along_z else w) * 0.5
		var modules := int(roundf(half * 2.0 / 1.5))
		var sgn := -1.0 if side == 0 or side == 2 else 1.0
		var plane := sgn * ((w if along_z else dp) * 0.5 + 0.08)
		var glass_ids: Array[int] = []
		for m in modules:
			var u := -half + 0.75 + 1.5 * m
			var gy := (g0 + g1) * 0.5
			var pos := Vector3(plane, gy, u) if along_z else Vector3(u, gy, plane)
			var gmat: StringName = look["glass"]
			if f == 0 and side == 0 and (m == (modules >> 1) - 1 or m == modules >> 1):
				gmat = &"tower_door_s" if stone else &"tower_door"
			var gid := d.add(GLASS, ATT, gmat, Vector3(gw, g1 - g0, 0.03), _xf(pos, along_z), f, f == 0, 0)
			glass_ids.append(gid)
			_attach_edge_panels(d, gid, side, u + half, npx, npz, f, pans)
			var sy := (s_lo + s_hi) * 0.5
			var spos := Vector3(plane, sy, u) if along_z else Vector3(u, sy, plane)
			var sid := d.add(SPANDREL, ATT, look["crown"] if top else look["panel"], Vector3(gw, s_hi - s_lo, 0.04), _xf(spos, along_z), f, false, 0)
			_attach_edge_panels(d, sid, side, u + half, npx, npz, f, pans)
			d.touch(sid, gid)
		for k in modules + 1:
			var u := -half + 1.5 * k
			# Along the wall the pier covers [u0, u1]. Wide stone piers turn the corner as an L: the piers of
			# sides 0 and 1 reach out over the corner, the ones of sides 2 and 3 stop short of them.
			var u0 := u - pier_w * 0.5
			var u1 := u + pier_w * 0.5
			if stone and (k == 0 or k == modules):
				var reach := (0.05 + pier_d) if not along_z else 0.05
				if k == 0:
					u0 = -half - reach
				else:
					u1 = half + reach
			var uc := (u0 + u1) * 0.5
			var off := plane + sgn * (pier_d * 0.5 - 0.03)
			var pos := Vector3(off, y, uc) if along_z else Vector3(uc, y, off)
			var mid := d.add(MULLION, ATT, look["frame"], Vector3(u1 - u0, m_hi - m_lo, pier_d), _xf(pos, along_z), f, f == 0, 0)
			_attach_edge_panels(d, mid, side, clampf(u + half, 0.01, half * 2.0 - 0.01), npx, npz, f, pans)
			if k > 0:
				d.touch(mid, glass_ids[k - 1])
			if k < modules:
				d.touch(mid, glass_ids[k])


static func _attach_edge_panels(d: BuildingData, id: int, side: int, along: float, npx: int, npz: int, f: int, pans: Dictionary[Vector3i, int]) -> void:
	var p := clampi(int(along / 3.0), 0, (npz if side >= 2 else npx) - 1)
	var cell := Vector2i(p, 0)
	match side:
		1:
			cell = Vector2i(p, npz - 1)
		2:
			cell = Vector2i(0, p)
		3:
			cell = Vector2i(npx - 1, p)
	for lvl in [f, f + 1]:
		d.attach(id, pans.get(Vector3i(cell.x, cell.y, lvl), -1))


static func _parking(d: BuildingData, rng: RandomNumberGenerator) -> void:
	var bx := rng.randi_range(4, 6)
	var bz := rng.randi_range(3, 4)
	var floors := rng.randi_range(3, 4)
	var t := 0.3
	var vh := H - t
	var w := bx * 6.0
	var dp := bz * 6.0
	var x0 := -w * 0.5
	var z0 := -dp * 0.5
	var npx := bx * 2
	var npz := bz * 2
	d.storeys = floors
	var look_rng := _look_rng(d)
	var deck_mat: StringName = DECKS[look_rng.randi() % DECKS.size()]
	var cols: Dictionary[Vector3i, int] = {}
	var pans: Dictionary[Vector3i, int] = {}
	var cores: Dictionary[Vector3i, int] = {}
	# Stair core walls on two sides of an interior bay (interior grid points have no column inset).
	var core_defs := _core_walls(1, 1, x0, z0, [0, 2])
	for f in floors:
		for i in bx + 1:
			for j in bz + 1:
				var x := x0 + i * 6.0 + (0.3 if i == 0 else (-0.3 if i == bx else 0.0))
				var z := z0 + j * 6.0 + (0.3 if j == 0 else (-0.3 if j == bz else 0.0))
				var id := d.add(COLUMN, VERT, &"concrete", Vector3(0.6, vh, 0.6), _xf(Vector3(x, f * H + vh * 0.5, z)), f, f == 0, 0)
				cols[Vector3i(i, j, f)] = id
				if f > 0:
					d.rests_on(id, cols.get(Vector3i(i, j, f - 1), -1))
					for p in _panels_around(i, j):
						d.rests_on(id, pans.get(Vector3i(p.x, p.y, f), -1))
		for cw in core_defs:
			var c: Vector2 = cw[2]
			var id := d.add(CORE, VERT, &"concrete", Vector3(2.7, vh, 0.3), _xf(Vector3(c.x, f * H + vh * 0.5, c.y), cw[3]), f, f == 0, 0)
			cores[Vector3i(cw[0], cw[1], f)] = id
			if f > 0:
				d.rests_on(id, cores.get(Vector3i(cw[0], cw[1], f - 1), -1))
				for p: Vector2i in cw[4]:
					d.rests_on(id, pans.get(Vector3i(p.x, p.y, f), -1))
			var corner: Vector2i = cw[5]
			d.touch(id, cols.get(Vector3i(corner.x, corner.y, f), -1))
		var lv := f + 1
		for px in npx:
			for pz in npz:
				var c := Vector3(x0 + 1.5 + 3.0 * px, lv * H - t * 0.5, z0 + 1.5 + 3.0 * pz)
				var id := d.add(SLAB, HORZ, &"concrete", Vector3(3.0, t, 3.0), _xf(c), f, false, 1)
				pans[Vector3i(px, pz, lv)] = id
				d.rests_on(id, cols.get(Vector3i((px + 1) >> 1, (pz + 1) >> 1, f), -1))
				d.lateral(id, pans.get(Vector3i(px - 1, pz, lv), -1))
				d.lateral(id, pans.get(Vector3i(px, pz - 1, lv), -1))
		for cw in core_defs:
			var wall_id: int = cores[Vector3i(cw[0], cw[1], f)]
			for p: Vector2i in cw[4]:
				var pid: int = pans.get(Vector3i(p.x, p.y, lv), -1)
				if pid >= 0:
					d.rests_on(pid, wall_id)
		# Low concrete railings along the deck edge.
		var ry := lv * H + 0.5
		for px in npx:
			var cx := x0 + 1.5 + 3.0 * px
			var s := d.add(RAILING, ATT, deck_mat, Vector3(3.0, 1.0, 0.2), _xf(Vector3(cx, ry, z0 + 0.1)), f, false, 0)
			d.attach(s, pans[Vector3i(px, 0, lv)])
			var n := d.add(RAILING, ATT, deck_mat, Vector3(3.0, 1.0, 0.2), _xf(Vector3(cx, ry, -z0 - 0.1)), f, false, 0)
			d.attach(n, pans[Vector3i(px, npz - 1, lv)])
			if lv == floors and px == (npx >> 1):
				# The parking sign stands on the top railing of side 0, its readable face outward.
				var sign_c := Vector3(cx, lv * H + 1.05 + 1.2, z0 - 0.06)
				var sign_id := d.add(FIXTURE, ATT, &"parking_sign", Vector3(2.4, 2.4, 0.12), Transform3D(Basis(Vector3.UP, PI), sign_c), f, false, 0)
				d.attach(sign_id, s)
		for pz in npz:
			var length := 2.8 if pz == 0 or pz == npz - 1 else 3.0
			var cz := z0 + 1.5 + 3.0 * pz + (0.1 if pz == 0 else (-0.1 if pz == npz - 1 else 0.0))
			var ws := d.add(RAILING, ATT, deck_mat, Vector3(length, 1.0, 0.2), _xf(Vector3(x0 + 0.1, ry, cz), true), f, false, 0)
			d.attach(ws, pans[Vector3i(0, pz, lv)])
			var es := d.add(RAILING, ATT, deck_mat, Vector3(length, 1.0, 0.2), _xf(Vector3(-x0 - 0.1, ry, cz), true), f, false, 0)
			d.attach(es, pans[Vector3i(npx - 1, pz, lv)])


# --------------------------------------------------------------------------------------------------
# Masonry buildings (apartment, house): load-bearing perimeter walls with window bays on a 3 m grid.
# --------------------------------------------------------------------------------------------------

class Masonry:
	var w: float
	var dp: float
	var bx: int
	var bz: int
	var floors: int
	var wall_mat: StringName
	var slab_mat: StringName
	var slab_t: float
	var slab_kind: int
	var door_mat: StringName
	var door_t: float
	var bay_types: Array[PackedInt32Array] = []   # per side, per bay
	var bays: Dictionary[Vector3i, PackedInt32Array] = {}   # (side, bay, storey) -> slots
	# Facade (see the class header of the generator).
	var base_mat: StringName = &""      # ground-floor walls; the wall material when empty
	var trim_mat: StringName = &""      # ledges and cornice; none when empty
	var frame := "white"                # window frame family (MaterialDB.FRAMES)
	var rail_mat: StringName = &"rail_black"
	var balcony_door: StringName = &"door_balcony_white"
	var brands: Array = []              # per bay of side 0: [sign, awning, shop window], or [] for none
	var parapets: Dictionary[Vector2i, int] = {}   # (side, bay) -> parapet id
	var look_rng: RandomNumberGenerator
	var corners: Dictionary[Vector3i, int] = {}   # (cx, cz, storey) -> id
	var panels: Dictionary[Vector3i, int] = {}    # (i, j, level) -> id
	var cross: Dictionary[Vector3i, int] = {}     # (k, j, storey) -> id

	func side_count(side: int) -> int:
		return bz if side >= 2 else bx

	## Floor panel next to bay b of a side at a level.
	func edge_panel(side: int, b: int, level: int) -> int:
		var c := Vector2i(b, 0)
		match side:
			1:
				c = Vector2i(b, bz - 1)
			2:
				c = Vector2i(0, b)
			3:
				c = Vector2i(bx - 1, b)
		return panels.get(Vector3i(c.x, c.y, level), -1)

	## Structural verticals of a bay (piers or the solid wall).
	func bay_verticals(side: int, b: int, f: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		var slots: PackedInt32Array = bays.get(Vector3i(side, b, f), PackedInt32Array())
		if slots.is_empty():
			return out
		for s in [S_PA, S_PB, S_WALL]:
			if slots[s] >= 0:
				out.append(slots[s])
		return out

	## Corners at the ends of bay b of a side, if it is an end bay.
	func bay_corners(side: int, b: int, f: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		var n := side_count(side)
		var ends: Array[Vector2i] = []
		match side:
			0:
				if b == 0: ends.append(Vector2i(0, 0))
				if b == n - 1: ends.append(Vector2i(1, 0))
			1:
				if b == 0: ends.append(Vector2i(0, 1))
				if b == n - 1: ends.append(Vector2i(1, 1))
			2:
				if b == 0: ends.append(Vector2i(0, 0))
				if b == n - 1: ends.append(Vector2i(0, 1))
			_:
				if b == 0: ends.append(Vector2i(1, 0))
				if b == n - 1: ends.append(Vector2i(1, 1))
		for e in ends:
			var id: int = corners.get(Vector3i(e.x, e.y, f), -1)
			if id >= 0:
				out.append(id)
		return out


static func _side_pos(m: Masonry, side: int, u: float, y: float) -> Vector3:
	match side:
		0:
			return Vector3(u, y, -m.dp * 0.5)
		1:
			return Vector3(u, y, m.dp * 0.5)
		2:
			return Vector3(-m.w * 0.5, y, u)
	return Vector3(m.w * 0.5, y, u)


## Creates the perimeter walls of storey f (corners + every bay), wired to the storey below and to the
## floor panels of level f. Floor panels of level f must already exist.
static func _masonry_storey_walls(d: BuildingData, m: Masonry, f: int) -> void:
	var y0 := f * H
	var wm := m.base_mat if f == 0 and m.base_mat != &"" else m.wall_mat
	for cx in 2:
		for cz in 2:
			var pos := Vector3((cx * 2 - 1) * m.w * 0.5, y0 + H * 0.5, (cz * 2 - 1) * m.dp * 0.5)
			var id := d.add(PIER, VERT, wm, Vector3(0.3, H, 0.3), _xf(pos), f, f == 0, 0)
			m.corners[Vector3i(cx, cz, f)] = id
			if f > 0:
				d.rests_on(id, m.corners.get(Vector3i(cx, cz, f - 1), -1))
				d.rests_on(id, m.panels.get(Vector3i(cx * (m.bx - 1), cz * (m.bz - 1), f), -1))
	for side in 4:
		var along_z := side >= 2
		var n := m.side_count(side)
		var half := (m.dp if along_z else m.w) * 0.5
		var prev_last := -1
		for b in n:
			var a := -half + 3.0 * b + (0.15 if b == 0 else 0.0)
			var e := -half + 3.0 * (b + 1) - (0.15 if b == n - 1 else 0.0)
			var btype := m.bay_types[side][b]
			if btype == BayType.DOOR and f > 0:
				btype = BayType.WINDOW
			if btype == BayType.BALCONY and f == 0:
				btype = BayType.WINDOW
			var brand: Array = []
			if f == 0 and side == 0 and btype == BayType.WINDOW and b < m.brands.size():
				brand = m.brands[b]
			var slots := PackedInt32Array([-1, -1, -1, -1, -1, -1])
			var below: PackedInt32Array = m.bays.get(Vector3i(side, b, f - 1), PackedInt32Array())
			var floor_panel := m.edge_panel(side, b, f) if f > 0 else -1
			if btype == BayType.SOLID:
				var id := d.add(WALL, VERT, wm, Vector3(e - a, H, 0.3), _xf(_side_pos(m, side, (a + e) * 0.5, y0 + H * 0.5), along_z), f, f == 0, 0)
				slots[S_WALL] = id
			else:
				var pa := 0.6 if b == 0 else 0.75
				var pb := 0.6 if b == n - 1 else 0.75
				if n == 1:
					pa = 0.6
					pb = 0.6
				var oa := a + pa
				slots[S_PA] = d.add(PIER, VERT, wm, Vector3(pa, H, 0.3), _xf(_side_pos(m, side, a + pa * 0.5, y0 + H * 0.5), along_z), f, f == 0, 0)
				slots[S_PB] = d.add(PIER, VERT, wm, Vector3(pb, H, 0.3), _xf(_side_pos(m, side, e - pb * 0.5, y0 + H * 0.5), along_z), f, f == 0, 0)
				var mid := oa + 0.75
				if btype == BayType.DOOR:
					slots[S_GLASS] = d.add(DOOR, ATT, m.door_mat, Vector3(1.5, 2.4, m.door_t), _xf(_side_pos(m, side, mid, y0 + 1.2), along_z), f, true, 0)
				elif btype == BayType.BALCONY:
					slots[S_GLASS] = d.add(DOOR, ATT, m.balcony_door, Vector3(1.5, 2.4, 0.02), _xf(_side_pos(m, side, mid, y0 + 1.2), along_z), f, false, 0)
				elif not brand.is_empty():
					# Shop front: a low sill, a tall shop window and the shop's sign band as the lintel.
					slots[S_SILL] = d.add(SILL, ATT, wm, Vector3(1.5, 0.3, 0.3), _xf(_side_pos(m, side, mid, y0 + 0.15), along_z), f, f == 0, 0)
					slots[S_GLASS] = d.add(GLASS, ATT, brand[2], Vector3(1.5, 2.1, 0.02), _xf(_side_pos(m, side, mid, y0 + 1.35), along_z), f, false, 0)
				else:
					slots[S_SILL] = d.add(SILL, ATT, wm, Vector3(1.5, 0.9, 0.3), _xf(_side_pos(m, side, mid, y0 + 0.45), along_z), f, f == 0, 0)
					slots[S_GLASS] = d.add(GLASS, ATT, _window_mat(m), Vector3(1.5, 1.5, 0.02), _xf(_side_pos(m, side, mid, y0 + 1.65), along_z), f, false, 0)
				slots[S_LINTEL] = d.add(LINTEL, ATT, brand[0] if not brand.is_empty() else wm, Vector3(1.5, 0.8, 0.3), _xf(_side_pos(m, side, mid, y0 + 2.8), along_z), f, false, 0)
				for s in [S_SILL, S_GLASS, S_LINTEL]:
					if slots[s] < 0:
						continue
					d.attach(slots[s], slots[S_PA])
					d.attach(slots[s], slots[S_PB])
					d.touch(slots[s], slots[S_PA])
					d.touch(slots[s], slots[S_PB])
				if slots[S_SILL] >= 0:
					d.attach(slots[S_SILL], floor_panel)
					d.touch(slots[S_SILL], slots[S_GLASS])
					if not below.is_empty():
						d.touch(slots[S_SILL], below[S_LINTEL])
				d.touch(slots[S_GLASS], slots[S_LINTEL])
				d.attach(slots[S_GLASS], floor_panel)
				_facade_bay(d, m, side, f, mid, along_z, btype, brand, slots, floor_panel)
			# Vertical continuity with the storey below and bearing on the floor slab.
			for s in [S_PA, S_PB, S_WALL]:
				if slots[s] < 0:
					continue
				if not below.is_empty() and below[s] >= 0:
					d.rests_on(slots[s], below[s])
				elif not below.is_empty():
					for v in m.bay_verticals(side, b, f - 1):
						d.rests_on(slots[s], v)
				d.rests_on(slots[s], floor_panel)
			# Lateral contact along the wall line.
			var first := slots[S_WALL] if slots[S_WALL] >= 0 else slots[S_PA]
			var last := slots[S_WALL] if slots[S_WALL] >= 0 else slots[S_PB]
			if prev_last >= 0:
				d.touch(first, prev_last)
			for c in m.bay_corners(side, b, f):
				d.touch(first if b == 0 else last, c)
			prev_last = last
			m.bays[Vector3i(side, b, f)] = slots


## Outward normal of a side of a masonry building.
static func _side_out(side: int) -> Vector3:
	match side:
		0:
			return Vector3(0.0, 0.0, -1.0)
		1:
			return Vector3(0.0, 0.0, 1.0)
		2:
			return Vector3(-1.0, 0.0, 0.0)
	return Vector3(1.0, 0.0, 0.0)


## A second random generator for the look of a design, so its structure stays as it was.
static func _look_rng(d: BuildingData) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = d.seed_value * 7919 + d.style * 104729 + 17
	return r


## Most windows are plain; some have curtains or blinds, and one in ten has the light on.
static func _window_mat(m: Masonry) -> StringName:
	var r := m.look_rng.randf() if m.look_rng != null else 0.0
	var kind := "plain"
	if r > 0.9:
		kind = "lit"
	elif r > 0.75:
		kind = "blind"
	elif r > 0.55:
		kind = "curtain"
	return StringName("window_%s_%s" % [m.frame, kind])


## Facade parts of one bay that carry nothing: the ledge under a window, the awning over a shop window
## and the balcony in front of a balcony door. They sit outside the wall face and hang on the bay.
static func _facade_bay(d: BuildingData, m: Masonry, side: int, f: int, mid: float, along_z: bool, btype: int, brand: Array,
		slots: PackedInt32Array, floor_panel: int) -> void:
	var out := _side_out(side)
	var y0 := f * H
	var basis := Basis(Vector3.UP, PI * 0.5) if along_z else Basis.IDENTITY
	if btype == BayType.WINDOW and brand.is_empty():
		if m.trim_mat != &"" and slots[S_SILL] >= 0:
			var p := _side_pos(m, side, mid, y0 + 0.9 - 0.035) + out * 0.22
			var ledge := d.add(TRIM, ATT, m.trim_mat, Vector3(1.75, 0.07, 0.14), Transform3D(basis, p), f, false, 0)
			d.attach(ledge, slots[S_SILL])
	elif not brand.is_empty():
		# From the wall just under the sign band, 1.25 m deep, sloping 22 degrees down and out.
		var slope := deg_to_rad(22.0)
		var x_axis := basis.x
		var z_axis := (out * cos(slope) + Vector3.DOWN * sin(slope)).normalized()
		var y_axis := z_axis.cross(x_axis)
		var n := y_axis if y_axis.y > 0.0 else -y_axis
		var top := _side_pos(m, side, mid, y0 + 2.42) + out * 0.18
		var c := top + z_axis * 0.625 - n * 0.025
		var awning := d.add(AWNING, ATT, brand[1], Vector3(2.7, 0.05, 1.25), Transform3D(Basis(x_axis, y_axis, z_axis), c), f, false, 0)
		d.attach(awning, slots[S_PA])
		d.attach(awning, slots[S_PB])
		d.attach(awning, slots[S_LINTEL])
	elif btype == BayType.BALCONY:
		var slab_c := _side_pos(m, side, mid, y0 - 0.08) + out * 0.75
		var slab := d.add(BALCONY_SLAB, ATT, m.trim_mat if m.trim_mat != &"" else &"concrete_light", Vector3(2.7, 0.16, 1.2), Transform3D(basis, slab_c), f, false, 0)
		d.attach(slab, floor_panel)
		d.attach(slab, slots[S_PA])
		d.attach(slab, slots[S_PB])
		var front := d.add(BALCONY_SLAB, ATT, m.rail_mat, Vector3(2.7, 1.0, 0.05), Transform3D(basis, _side_pos(m, side, mid, y0 + 0.5) + out * 1.325), f, false, 0)
		d.attach(front, slab)
		for s: float in [-1.0, 1.0]:
			var sc := _side_pos(m, side, mid + s * 1.325, y0 + 0.5) + out * 0.725
			var rail := d.add(BALCONY_SLAB, ATT, m.rail_mat, Vector3(0.05, 1.0, 1.15), Transform3D(basis, sc), f, false, 0)
			d.attach(rail, slab)


## Floor panels of level lv between the perimeter walls, resting on the walls of storey lv - 1.
static func _masonry_floor(d: BuildingData, m: Masonry, lv: int) -> void:
	var x0 := -m.w * 0.5
	var z0 := -m.dp * 0.5
	var f := lv - 1
	for i in m.bx:
		for j in m.bz:
			var xa := x0 + 3.0 * i + (0.15 if i == 0 else 0.0)
			var xb := x0 + 3.0 * (i + 1) - (0.15 if i == m.bx - 1 else 0.0)
			var za := z0 + 3.0 * j + (0.15 if j == 0 else 0.0)
			var zb := z0 + 3.0 * (j + 1) - (0.15 if j == m.bz - 1 else 0.0)
			var c := Vector3((xa + xb) * 0.5, lv * H - m.slab_t * 0.5, (za + zb) * 0.5)
			var id := d.add(m.slab_kind, HORZ, m.slab_mat, Vector3(xb - xa, m.slab_t, zb - za), _xf(c), f, false, 1)
			m.panels[Vector3i(i, j, lv)] = id
			d.lateral(id, m.panels.get(Vector3i(i - 1, j, lv), -1))
			d.lateral(id, m.panels.get(Vector3i(i, j - 1, lv), -1))
			var edges: Array[Vector2i] = []
			if j == 0:
				edges.append(Vector2i(0, i))
			if j == m.bz - 1:
				edges.append(Vector2i(1, i))
			if i == 0:
				edges.append(Vector2i(2, j))
			if i == m.bx - 1:
				edges.append(Vector2i(3, j))
			for e in edges:
				for v in m.bay_verticals(e.x, e.y, f):
					d.rests_on(id, v)
				for cid in m.bay_corners(e.x, e.y, f):
					d.rests_on(id, cid)
				var slots: PackedInt32Array = m.bays.get(Vector3i(e.x, e.y, f), PackedInt32Array())
				if not slots.is_empty():
					for s in [S_GLASS, S_LINTEL]:
						if slots[s] >= 0:
							d.attach(slots[s], id)
			for k in [i, i + 1]:
				d.rests_on(id, m.cross.get(Vector3i(k, j, f), -1))


static func _masonry_setup(m: Masonry, rng: RandomNumberGenerator, solid_ends_on_short_sides: bool, door_side: int, balcony_side: int = -1) -> void:
	for side in 4:
		var n := m.side_count(side)
		var types := PackedInt32Array()
		types.resize(n)
		for b in n:
			var t := BayType.WINDOW
			if side >= 2 and solid_ends_on_short_sides and (b == 0 or b == n - 1) and n > 2:
				t = BayType.SOLID
			elif rng.randf() < 0.12:
				t = BayType.SOLID
			types[b] = t
		if side == door_side:
			types[n >> 1] = BayType.DOOR
		if side == balcony_side:
			for b in n:
				if b % 2 == 1 and types[b] == BayType.WINDOW:
					types[b] = BayType.BALCONY
		m.bay_types.append(types)


static func _apartment(d: BuildingData, rng: RandomNumberGenerator) -> void:
	var m := Masonry.new()
	m.bx = rng.randi_range(7, 10)
	m.bz = 4
	m.floors = rng.randi_range(4, 6)
	m.w = m.bx * 3.0
	m.dp = m.bz * 3.0
	m.wall_mat = [&"brick", &"brick_old"][rng.randi() % 2]
	m.slab_mat = &"concrete"
	m.slab_t = 0.3
	m.slab_kind = SLAB
	m.door_mat = &"door_glass"
	m.door_t = 0.02
	d.storeys = m.floors
	d.monolithic = false
	m.look_rng = _look_rng(d)
	var look: Dictionary = APARTMENT_LOOKS[m.look_rng.randi() % APARTMENT_LOOKS.size()]
	m.wall_mat = look["wall"]
	m.base_mat = look["base"]
	m.trim_mat = look["trim"]
	m.frame = look["frame"]
	m.rail_mat = look["rail"]
	m.balcony_door = StringName("door_balcony_" + m.frame)
	_masonry_setup(m, rng, true, 0, 1)
	# Shops along the ground floor of side 0 (the street side in the Old Quarter), a new shop every two bays.
	if m.look_rng.randf() < 0.8:
		var first := m.look_rng.randi() % SHOP_BRANDS.size()
		for b in m.bx:
			m.brands.append(SHOP_BRANDS[(first + (b >> 1)) % SHOP_BRANDS.size()])
	var cross_lines: Array[int] = []
	for k in range(2, m.bx, 2):
		cross_lines.append(k)
	var x0 := -m.w * 0.5
	var z0 := -m.dp * 0.5
	var vh := H - m.slab_t
	for f in m.floors:
		_masonry_storey_walls(d, m, f)
		# Load-bearing brick cross walls (party walls) under the slabs.
		for k in cross_lines:
			for j in m.bz:
				var za := z0 + 3.0 * j + (0.15 if j == 0 else 0.0)
				var zb := z0 + 3.0 * (j + 1) - (0.15 if j == m.bz - 1 else 0.0)
				var c := Vector3(x0 + 3.0 * k, f * H + vh * 0.5, (za + zb) * 0.5)
				var id := d.add(WALL, VERT, m.wall_mat, Vector3(zb - za, vh, 0.3), _xf(c, true), f, f == 0, 0)
				m.cross[Vector3i(k, j, f)] = id
				if f > 0:
					d.rests_on(id, m.cross.get(Vector3i(k, j, f - 1), -1))
					d.rests_on(id, m.panels.get(Vector3i(k - 1, j, f), -1))
					d.rests_on(id, m.panels.get(Vector3i(k, j, f), -1))
				d.touch(id, m.cross.get(Vector3i(k, j - 1, f), -1))
				if j == 0 or j == m.bz - 1:
					var side := 0 if j == 0 else 1
					for b in [k - 1, k]:
						for v in m.bay_verticals(side, b, f):
							d.touch(id, v)
		_masonry_floor(d, m, f + 1)
		# Plaster partitions on the odd grid lines, one door gap per line.
		for k in range(1, m.bx, 2):
			var gap := rng.randi_range(0, m.bz - 1)
			for j in m.bz:
				if j == gap:
					continue
				var za := z0 + 3.0 * j + (0.15 if j == 0 else 0.0)
				var zb := z0 + 3.0 * (j + 1) - (0.15 if j == m.bz - 1 else 0.0)
				var c := Vector3(x0 + 3.0 * k, f * H + vh * 0.5, (za + zb) * 0.5)
				var id := d.add(PARTITION, ATT, &"plaster", Vector3(zb - za, vh, 0.1), _xf(c, true), f, f == 0, 0)
				for lvl in [f, f + 1]:
					d.attach(id, m.panels.get(Vector3i(k - 1, j, lvl), -1))
					d.attach(id, m.panels.get(Vector3i(k, j, lvl), -1))
	_parapet(d, m)


## A parapet round the roof edge of a masonry block, and its cornice.
static func _parapet(d: BuildingData, m: Masonry) -> void:
	var top := m.floors - 1
	var py := m.floors * H + 0.45
	for side in 4:
		var along_z := side >= 2
		var n := m.side_count(side)
		var half := (m.dp if along_z else m.w) * 0.5
		for b in n:
			var a := -half + 3.0 * b
			var e := -half + 3.0 * (b + 1)
			if along_z:
				a += 0.15 if b == 0 else 0.0
				e -= 0.15 if b == n - 1 else 0.0
			else:
				a -= 0.15 if b == 0 else 0.0
				e += 0.15 if b == n - 1 else 0.0
			var id := d.add(PARAPET, ATT, m.wall_mat, Vector3(e - a, 0.9, 0.3), _xf(_side_pos(m, side, (a + e) * 0.5, py), along_z), top, false, 0)
			m.parapets[Vector2i(side, b)] = id
			for v in m.bay_verticals(side, b, top):
				d.attach(id, v)
			for c in m.bay_corners(side, b, top):
				d.attach(id, c)
			d.attach(id, m.edge_panel(side, b, m.floors))
	_cornice(d, m, top)


## A cornice round the roof line: 30 cm out from the wall face, one piece per bay hung on its parapet.
## The pieces of sides 0 and 1 run on over the corners, the ones of sides 2 and 3 stop against them.
static func _cornice(d: BuildingData, m: Masonry, top: int) -> void:
	if m.trim_mat == &"":
		return
	for side in 4:
		var along_z := side >= 2
		var n := m.side_count(side)
		var half := (m.dp if along_z else m.w) * 0.5
		var out := _side_out(side)
		var ext := 0.15 if along_z else 0.45
		for b in n:
			var a := -half + 3.0 * b - (ext if b == 0 else 0.0)
			var e := -half + 3.0 * (b + 1) + (ext if b == n - 1 else 0.0)
			var c := _side_pos(m, side, (a + e) * 0.5, m.floors * H + 0.1) + out * 0.3
			var id := d.add(TRIM, ATT, m.trim_mat, Vector3(e - a, 0.34, 0.3), _xf(c, along_z), top, false, 0)
			d.attach(id, m.parapets.get(Vector2i(side, b), -1))


# --------------------------------------------------------------------------------------------------
# The outer ring (2026-11-17): sheds of the docks, the mall, the fuel station canopy, corner shops.
# --------------------------------------------------------------------------------------------------

## A tall shed: a steel frame two storeys high on a 6 m grid with no floor in between (one hall), cladding
## of corrugated sheet hung outside the perimeter columns, two roller doors on side 0, a light roof.
static func _warehouse(d: BuildingData, rng: RandomNumberGenerator) -> void:
	var bx := rng.randi_range(4, 6)
	var bz := rng.randi_range(3, 4)
	var w := bx * 6.0
	var dp := bz * 6.0
	var x0 := -w * 0.5
	var z0 := -dp * 0.5
	var floors := 2
	var t := 0.15
	d.storeys = floors
	var look_rng := _look_rng(d)
	var clad: StringName = CLADDINGS[look_rng.randi() % CLADDINGS.size()]
	var cols: Dictionary[Vector3i, int] = {}
	for f in floors:
		var h := H if f < floors - 1 else H - t
		for i in bx + 1:
			for j in bz + 1:
				var x := x0 + i * 6.0 + (0.2 if i == 0 else (-0.2 if i == bx else 0.0))
				var z := z0 + j * 6.0 + (0.2 if j == 0 else (-0.2 if j == bz else 0.0))
				var id := d.add(COLUMN, VERT, &"steel", Vector3(0.4, h, 0.4), _xf(Vector3(x, f * H + h * 0.5, z)), f, f == 0, 0)
				cols[Vector3i(i, j, f)] = id
				if f > 0:
					d.rests_on(id, cols[Vector3i(i, j, f - 1)])
	var top := floors - 1
	var npx := bx * 2
	var npz := bz * 2
	var pans: Dictionary[Vector2i, int] = {}
	for px in npx:
		for pz in npz:
			var c := Vector3(x0 + 1.5 + 3.0 * px, floors * H - t * 0.5, z0 + 1.5 + 3.0 * pz)
			var id := d.add(ROOF, HORZ, &"roof_sheet", Vector3(3.0, t, 3.0), _xf(c), top, false, 1)
			pans[Vector2i(px, pz)] = id
			d.rests_on(id, cols[Vector3i((px + 1) >> 1, (pz + 1) >> 1, top)])
			d.lateral(id, pans.get(Vector2i(px - 1, pz), -1))
			d.lateral(id, pans.get(Vector2i(px, pz - 1), -1))
	# Cladding in 3 m sheets, a storey high; sides 0 and 1 run on over the corners.
	var doors := [1, bx - 2]
	for f in floors:
		var y := f * H + H * 0.5
		for side in 4:
			var along_z := side >= 2
			var nb := bz if along_z else bx
			var half := (dp if along_z else w) * 0.5
			var line := (w if along_z else dp) * 0.5 + 0.06
			var sgn := -1.0 if side == 0 or side == 2 else 1.0
			for k in nb * 2:
				var u := -half + 1.5 + 3.0 * k
				var length := 3.0
				if not along_z and (k == 0 or k == nb * 2 - 1):
					length = 3.11
					u += -0.055 if k == 0 else 0.055
				var pos := Vector3(sgn * line, y, u) if along_z else Vector3(u, y, sgn * line)
				var bay := k >> 1
				var door := side == 0 and f == 0 and doors.has(bay)
				var id := d.add(DOOR if door else WALL, ATT, &"roller_door" if door else clad, Vector3(length, H, 0.1), _xf(pos, along_z), f, f == 0, 0)
				for g in [bay, bay + 1]:
					var key := Vector3i(g, 0, f)
					match side:
						1:
							key = Vector3i(g, bz, f)
						2:
							key = Vector3i(0, g, f)
						3:
							key = Vector3i(bx, g, f)
					d.attach(id, cols[key])


## The mall: a wide two-storey frame with the glass and spandrels of a tower look, its doors under a
## canopy on side 0, a big sign band on the roof over them and plant on the roof.
static func _mall(d: BuildingData, rng: RandomNumberGenerator) -> void:
	var bx := rng.randi_range(6, 8)
	var bz := rng.randi_range(4, 5)
	var floors := 2
	var t := 0.3
	var vh := H - t
	var w := bx * 6.0
	var dp := bz * 6.0
	var x0 := -w * 0.5
	var z0 := -dp * 0.5
	var npx := bx * 2
	var npz := bz * 2
	d.storeys = floors
	var look_rng := _look_rng(d)
	var look: Dictionary = TOWER_LOOKS[[0, 1, 2, 5][look_rng.randi() % 4]]
	var cols: Dictionary[Vector3i, int] = {}
	var pans: Dictionary[Vector3i, int] = {}
	for f in floors:
		for i in bx + 1:
			for j in bz + 1:
				var x := x0 + i * 6.0 + (0.3 if i == 0 else (-0.3 if i == bx else 0.0))
				var z := z0 + j * 6.0 + (0.3 if j == 0 else (-0.3 if j == bz else 0.0))
				var id := d.add(COLUMN, VERT, &"concrete", Vector3(0.6, vh, 0.6), _xf(Vector3(x, f * H + vh * 0.5, z)), f, f == 0, 0)
				cols[Vector3i(i, j, f)] = id
				if f > 0:
					d.rests_on(id, cols.get(Vector3i(i, j, f - 1), -1))
					for p in _panels_around(i, j):
						d.rests_on(id, pans.get(Vector3i(p.x, p.y, f), -1))
		var lv := f + 1
		for px in npx:
			for pz in npz:
				var c := Vector3(x0 + 1.5 + 3.0 * px, lv * H - t * 0.5, z0 + 1.5 + 3.0 * pz)
				var id := d.add(SLAB, HORZ, &"concrete", Vector3(3.0, t, 3.0), _xf(c), f, false, 1)
				pans[Vector3i(px, pz, lv)] = id
				d.rests_on(id, cols.get(Vector3i((px + 1) >> 1, (pz + 1) >> 1, f), -1))
				d.lateral(id, pans.get(Vector3i(px - 1, pz, lv), -1))
				d.lateral(id, pans.get(Vector3i(px, pz - 1, lv), -1))
		_curtain_wall(d, f, w, dp, npx, npz, pans, look, floors)
	_frame_parapet(d, floors, npx, npz, x0, z0, pans)
	var brand: Array = SHOP_BRANDS[look_rng.randi() % SHOP_BRANDS.size()]
	var sign_mat := StringName(String(brand[1]).replace("awning_", "mallsign_"))
	var sign_id := d.add(TRIM, ATT, sign_mat, Vector3(minf(w * 0.5, 22.0), 2.2, 0.3), _xf(Vector3(0.0, floors * H + 2.1, z0 - 0.42)), floors - 1, false, 0)
	_attach_edge_panels(d, sign_id, 0, w * 0.5, npx, npz, floors - 1, pans)
	_tower_extras(d, look, look_rng, floors, w, dp, npx, npz, -1, -1, pans, false)


## The canopy of a fuel station: slim steel columns two storeys high, a light roof on them and a fascia
## in the colours of its brand all round. The pumps under it are props (they explode).
static func _canopy(d: BuildingData, _rng: RandomNumberGenerator) -> void:
	var bx := 3
	var bz := 2
	var floors := 2
	var t := 0.4
	var w := bx * 6.0
	var dp := bz * 6.0
	var x0 := -w * 0.5
	var z0 := -dp * 0.5
	d.storeys = floors
	var brand := canopy_brand(d.seed_value)
	var fascia := StringName(String(brand[1]).replace("awning_", "fascia_"))
	var cols: Dictionary[Vector3i, int] = {}
	for f in floors:
		var h := H if f < floors - 1 else H - t
		for i in bx + 1:
			for j in bz + 1:
				var x := x0 + i * 6.0 + (0.3 if i == 0 else (-0.3 if i == bx else 0.0))
				var z := z0 + j * 6.0 + (0.3 if j == 0 else (-0.3 if j == bz else 0.0))
				var id := d.add(COLUMN, VERT, &"steel", Vector3(0.35, h, 0.35), _xf(Vector3(x, f * H + h * 0.5, z)), f, f == 0, 0)
				cols[Vector3i(i, j, f)] = id
				if f > 0:
					d.rests_on(id, cols[Vector3i(i, j, f - 1)])
	var top := floors - 1
	var npx := bx * 2
	var npz := bz * 2
	var pans: Dictionary[Vector2i, int] = {}
	for px in npx:
		for pz in npz:
			var c := Vector3(x0 + 1.5 + 3.0 * px, floors * H - t * 0.5, z0 + 1.5 + 3.0 * pz)
			var id := d.add(SLAB, HORZ, &"canopy_white", Vector3(3.0, t, 3.0), _xf(c), top, false, 1)
			pans[Vector2i(px, pz)] = id
			d.rests_on(id, cols[Vector3i((px + 1) >> 1, (pz + 1) >> 1, top)])
			d.lateral(id, pans.get(Vector2i(px - 1, pz), -1))
			d.lateral(id, pans.get(Vector2i(px, pz - 1), -1))
	# Fascia: 3 m pieces round the roof edge, outside it; sides 0 and 1 run on over the corners.
	var y := floors * H - 0.45
	for side in 4:
		var along_z := side >= 2
		var n := npz if along_z else npx
		var half := (dp if along_z else w) * 0.5
		var line := (w if along_z else dp) * 0.5 + 0.15
		var sgn := -1.0 if side == 0 or side == 2 else 1.0
		for k in n:
			var u := -half + 1.5 + 3.0 * k
			var length := 3.0
			if not along_z and (k == 0 or k == n - 1):
				length = 3.3
				u += -0.15 if k == 0 else 0.15
			var pos := Vector3(sgn * line, y, u) if along_z else Vector3(u, y, sgn * line)
			var id := d.add(TRIM, ATT, fascia, Vector3(length, 1.1, 0.3), _xf(pos, along_z), top, false, 0)
			var cell := Vector2i(k, 0)
			match side:
				1:
					cell = Vector2i(k, npz - 1)
				2:
					cell = Vector2i(0, k)
				3:
					cell = Vector2i(npx - 1, k)
			d.attach(id, pans[cell])


## The brand of the fuel station canopy of a design ([sign, awning, shop window]); the pumps under it
## wear it too.
static func canopy_brand(seed_value: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 7919 + D.Style.CANOPY * 104729 + 17
	return SHOP_BRANDS[r.randi() % SHOP_BRANDS.size()]


## A one-storey shop: shop fronts along side 0 in a row of brands with the door in the middle, the walls
## of an apartment look, a parapet and a cornice.
static func _shop(d: BuildingData, rng: RandomNumberGenerator) -> void:
	var m := Masonry.new()
	m.bx = rng.randi_range(3, 6)
	m.bz = 3
	m.floors = 1
	m.w = m.bx * 3.0
	m.dp = m.bz * 3.0
	m.slab_mat = &"concrete"
	m.slab_t = 0.3
	m.slab_kind = SLAB
	m.door_mat = &"door_glass"
	m.door_t = 0.02
	d.storeys = m.floors
	d.monolithic = false
	m.look_rng = _look_rng(d)
	var look: Dictionary = APARTMENT_LOOKS[m.look_rng.randi() % APARTMENT_LOOKS.size()]
	m.wall_mat = look["wall"]
	m.base_mat = look["wall"]
	m.trim_mat = look["trim"]
	m.frame = look["frame"]
	_masonry_setup(m, rng, false, 0)
	var first := m.look_rng.randi() % SHOP_BRANDS.size()
	for b in m.bx:
		m.brands.append(SHOP_BRANDS[(first + (b >> 1)) % SHOP_BRANDS.size()])
	_masonry_storey_walls(d, m, 0)
	_masonry_floor(d, m, 1)
	_parapet(d, m)


static func _house(d: BuildingData, rng: RandomNumberGenerator) -> void:
	var m := Masonry.new()
	m.bx = rng.randi_range(2, 3)
	m.bz = 2
	m.floors = rng.randi_range(1, 2)
	m.w = m.bx * 3.0
	m.dp = m.bz * 3.0
	m.wall_mat = [&"brick", &"brick_old", &"plaster"][rng.randi() % 3]
	m.slab_mat = &"wood"
	m.slab_t = 0.2
	m.slab_kind = FLOOR
	m.door_mat = &"wood"
	m.door_t = 0.06
	d.storeys = m.floors + 1
	d.monolithic = false
	# The look keeps what the house is made of: plaster houses get a pastel coat, brick ones stay brick,
	# old brick ones are sometimes fieldstone cottages.
	m.look_rng = _look_rng(d)
	match m.wall_mat:
		&"plaster":
			m.wall_mat = PASTELS[m.look_rng.randi() % PASTELS.size()]
		&"brick":
			m.wall_mat = &"brick" if m.look_rng.randf() < 0.6 else &"brick_dark"
		_:
			m.wall_mat = &"brick_old" if m.look_rng.randf() < 0.55 else &"fieldstone"
	m.trim_mat = &"trim_white" if m.look_rng.randf() < 0.7 else &"trim_cream"
	m.frame = HOUSE_FRAMES[m.look_rng.randi() % HOUSE_FRAMES.size()]
	m.door_mat = HOUSE_DOORS[m.look_rng.randi() % HOUSE_DOORS.size()]
	var roof_mat: StringName = HOUSE_ROOFS[m.look_rng.randi() % HOUSE_ROOFS.size()]
	var chimney := m.look_rng.randf() < 0.7
	_masonry_setup(m, rng, false, 0)
	for f in m.floors:
		_masonry_storey_walls(d, m, f)
		_masonry_floor(d, m, f + 1)
	# Gable roof, ridge along x, 35 degree pitch, 0.4 m eaves, 0.45 m verge overhang.
	var top := m.floors - 1
	var hw := m.floors * H
	var alpha := deg_to_rad(35.0)
	var hs := m.dp * 0.5 + 0.15
	var ridge_h := hs * tan(alpha)
	var slope_len := (hs + 0.4) / cos(alpha)
	var seg := slope_len * 0.5
	var roof_t := 0.15
	var gables: Array[int] = []
	for gx in 2:
		var gpos := Vector3((gx * 2 - 1) * m.w * 0.5, hw + ridge_h * 0.5, 0.0)
		var g := d.add(GABLE, VERT, m.wall_mat, Vector3(m.dp + 0.3, ridge_h, 0.3), _xf(gpos, true), m.floors, false, 0, D.Shape.PRISM)
		gables.append(g)
		var side := 2 if gx == 0 else 3
		for b in m.bz:
			for v in m.bay_verticals(side, b, top):
				d.rests_on(g, v)
			for c in m.bay_corners(side, b, top):
				d.rests_on(g, c)
	var roofs: Dictionary[Vector3i, int] = {}   # (bay, k, slope) -> id
	var cosa := cos(alpha)
	var sina := sin(alpha)
	for b in m.bx:
		# On the chimney's side the roof ends flush with the gable, so the stack can stand against it.
		var xa := -m.w * 0.5 + 3.0 * b - (0.45 if b == 0 else 0.0)
		var xb := -m.w * 0.5 + 3.0 * (b + 1) + ((0.15 if chimney else 0.45) if b == m.bx - 1 else 0.0)
		var xm := (xa + xb) * 0.5
		for sl in 2:
			var basis: Basis
			if sl == 0:
				basis = Basis(Vector3(1, 0, 0), Vector3(0, cosa, -sina), Vector3(0, sina, cosa))
			else:
				basis = Basis(Vector3(-1, 0, 0), Vector3(0, cosa, sina), Vector3(0, sina, -cosa))
			var ridge := Vector3(xm, hw + ridge_h, 0.0)
			for k in 2:
				var c := ridge - basis.z * (seg * (k + 0.5)) + basis.y * (roof_t * 0.5)
				var id := d.add(ROOF, HORZ, roof_mat, Vector3(xb - xa, roof_t, seg), Transform3D(basis, c), m.floors, false, 2)
				roofs[Vector3i(b, k, sl)] = id
				if k == 1:
					for v in m.bay_verticals(sl, b, top):
						d.rests_on(id, v)
					for cid in m.bay_corners(sl, b, top):
						d.rests_on(id, cid)
				if b == 0:
					d.rests_on(id, gables[0])
				if b == m.bx - 1:
					d.rests_on(id, gables[1])
				d.lateral(id, roofs.get(Vector3i(b - 1, k, sl), -1))
				d.lateral(id, roofs.get(Vector3i(b, k - 1, sl), -1))
		d.lateral(roofs[Vector3i(b, 0, 1)], roofs[Vector3i(b, 0, 0)])
		var cap := d.add(RIDGE, ATT, roof_mat, Vector3(xb - xa, 0.12, 0.36), _xf(Vector3(xm, hw + ridge_h + 0.19, 0.0)), m.floors, false, 0)
		d.attach(cap, roofs[Vector3i(b, 0, 0)])
		d.attach(cap, roofs[Vector3i(b, 0, 1)])
	if chimney:
		# A brick stack against the east gable, from the ground to a metre over the ridge.
		var hc := hw + ridge_h + 1.1
		var stack := d.add(CHIMNEY, ATT, &"brick" if m.wall_mat != &"fieldstone" else &"fieldstone", Vector3(0.6, hc, 1.0),
			_xf(Vector3(m.w * 0.5 + 0.15 + 0.3, hc * 0.5, 0.0)), m.floors, false, 0)
		d.attach(stack, gables[1])
		d.touch(stack, gables[1])
