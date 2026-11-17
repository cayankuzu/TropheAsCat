class_name SupportSolver
extends RefCounted
## Incremental structural support for one building.
##
## Rules (evaluated per element, re-evaluated through a worklist when a neighbour changes):
##  * VERTICAL: supported if it touches the ground or rests on a supported element below it.
##  * HORIZONTAL: "direct" if it rests on a supported vertical; otherwise it may cantilever through
##    lateral neighbours, cant = 1 + min(neighbour cant), and is supported while cant <= cant_max.
##  * ATTACHED: supported while any structural host is supported.
## RESTS_ON edges always point downward and lateral chains are capped, so removals converge.
## Removing a vertical also redistributes its load to nearby verticals of the same storey (overload
## failures) and marks the storey for an overturning check (centre of mass above vs support hull).

const D := preload("res://game/destruction/destruction_defs.gd")
const RESTS_ON := D.Edge.RESTS_ON
const CARRIES := D.Edge.CARRIES
const LATERAL := D.Edge.LATERAL
const ATTACHED_TO := D.Edge.ATTACHED_TO
const HOSTS := D.Edge.HOSTS
const VERT := D.Role.VERTICAL
const HORZ := D.Role.HORIZONTAL
const CINF := D.CANT_INF

const REDISTRIBUTE_RADIUS := 7.0
const SAFETY_CONCRETE := 2.4
const SAFETY_MASONRY := 2.8

var data: BuildingData
var alive := PackedByteArray()
var sup := PackedByteArray()
var cant := PackedByteArray()
var queued := PackedByteArray()
var work := PackedInt32Array()
var work_head := 0
var newly_unsupported := PackedInt32Array()

var load_kg := PackedFloat32Array()
var capacity_kg := PackedFloat32Array()
var verticals_by_storey: Array[PackedInt32Array] = []
var mass_above := PackedFloat64Array()
var mom_x_above := PackedFloat64Array()
var mom_z_above := PackedFloat64Array()
var overturn_dirty := PackedByteArray()
var evaluations := 0


func setup(d: BuildingData) -> void:
	data = d
	var n := d.count()
	alive.resize(n)
	alive.fill(1)
	sup.resize(n)
	sup.fill(0)
	cant.resize(n)
	cant.fill(CINF)
	queued.resize(n)
	queued.fill(0)
	load_kg.resize(n)
	load_kg.fill(0.0)
	capacity_kg.resize(n)
	capacity_kg.fill(0.0)
	var storeys := d.storeys + 1
	verticals_by_storey.clear()
	for f in storeys:
		verticals_by_storey.append(PackedInt32Array())
	mass_above.resize(storeys)
	mass_above.fill(0.0)
	mom_x_above.resize(storeys)
	mom_x_above.fill(0.0)
	mom_z_above.resize(storeys)
	mom_z_above.fill(0.0)
	overturn_dirty.resize(storeys)
	overturn_dirty.fill(0)
	for i in n:
		var st := d.storey[i]
		if d.role[i] == VERT:
			verticals_by_storey[st].append(i)
		_add_mass_above(i, 1.0)
	for f in storeys:
		var verts := verticals_by_storey[f]
		var area := 0.0
		for v in verts:
			area += d.dims[v].x * d.dims[v].z
		if area <= 0.0:
			continue
		for v in verts:
			var share := mass_above[f] * d.dims[v].x * d.dims[v].z / area
			load_kg[v] = share
			var mname := d.material_name(v)
			var mbase := MaterialDB.base_of(mname)
			var sf := SAFETY_CONCRETE if mbase == &"concrete" or mbase == &"concrete_light" else SAFETY_MASONRY
			capacity_kg[v] = share * sf + 1000.0
	# Initial solve: everything is pushed once in storey order and must end up supported.
	var order := range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return d.storey[a] * 4 + d.role[a] < d.storey[b] * 4 + d.role[b])
	for i: int in order:
		_push(i)
	run(1 << 30)
	newly_unsupported.clear()


func _add_mass_above(i: int, sign_value: float) -> void:
	var st := data.storey[i]
	var top := st if data.role[i] != VERT else st - 1
	if top < 0:
		return
	var m := data.mass[i] * sign_value
	var p := data.xf[i].origin
	for f in top + 1:
		mass_above[f] += m
		mom_x_above[f] += m * p.x
		mom_z_above[f] += m * p.z


func _push(e: int) -> void:
	if queued[e] == 0 and alive[e] == 1:
		queued[e] = 1
		work.append(e)


func is_idle() -> bool:
	return work_head >= work.size()


## Processes queued evaluations until the queue is empty or the budget is spent. Returns true when idle.
func run(budget_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var adj_start := data.adj_start
	var adj_to := data.adj_to
	var adj_type := data.adj_type
	var roles := data.role
	var anchors := data.anchor
	var cmax := data.cant_max
	var count := 0
	while work_head < work.size():
		var e := work[work_head]
		work_head += 1
		queued[e] = 0
		count += 1
		if alive[e] == 1:
			var a0 := adj_start[e]
			var a1 := adj_start[e + 1]
			var r := roles[e]
			var s := 0
			var c := CINF
			if r == VERT:
				if anchors[e] == 1:
					s = 1
				else:
					for k in range(a0, a1):
						if adj_type[k] == RESTS_ON:
							var j := adj_to[k]
							if alive[j] == 1 and sup[j] == 1:
								s = 1
								break
			elif r == HORZ:
				for k in range(a0, a1):
					if adj_type[k] == RESTS_ON:
						var j := adj_to[k]
						if alive[j] == 1 and sup[j] == 1:
							c = 0
							break
				if c != 0:
					for k in range(a0, a1):
						if adj_type[k] == LATERAL:
							var j := adj_to[k]
							if alive[j] == 1 and sup[j] == 1 and cant[j] + 1 < c:
								c = cant[j] + 1
				if c <= cmax[e]:
					s = 1
				else:
					c = CINF
			else:
				for k in range(a0, a1):
					if adj_type[k] == ATTACHED_TO:
						var j := adj_to[k]
						if alive[j] == 1 and sup[j] == 1:
							s = 1
							break
			var changed_s := s != sup[e]
			if changed_s or c != cant[e]:
				sup[e] = s
				cant[e] = c
				for k in range(a0, a1):
					var t := adj_type[k]
					if t == CARRIES or t == HOSTS or t == LATERAL:
						_push(adj_to[k])
				if changed_s and s == 0:
					newly_unsupported.append(e)
		if (count & 63) == 0 and Time.get_ticks_usec() - t0 > budget_usec:
			break
	evaluations += count
	if work_head >= work.size():
		work.clear()
		work_head = 0
		return true
	return false


## Puts element e back into the structure (world rewind): alive again, its weight counted again. Its
## support, and that of everything around it, is evaluated on the next run.
func revive(e: int) -> void:
	if alive[e] == 1:
		return
	alive[e] = 1
	sup[e] = 0
	cant[e] = CINF
	_add_mass_above(e, 1.0)
	if data.role[e] == VERT:
		overturn_dirty[data.storey[e]] = 1
	_push(e)
	for k in range(data.adj_start[e], data.adj_start[e + 1]):
		_push(data.adj_to[k])


## Takes element e out of the structure. When redistribute is true (the element was crushed or
## destroyed in place) its load moves to nearby verticals; returns the ones now overloaded.
func remove(e: int, redistribute: bool) -> PackedInt32Array:
	var over := PackedInt32Array()
	if alive[e] == 0:
		return over
	alive[e] = 0
	sup[e] = 0
	cant[e] = CINF
	for k in range(data.adj_start[e], data.adj_start[e + 1]):
		var t := data.adj_type[k]
		if t == CARRIES or t == HOSTS or t == LATERAL:
			_push(data.adj_to[k])
	_add_mass_above(e, -1.0)
	if data.role[e] == VERT:
		var st := data.storey[e]
		overturn_dirty[st] = 1
		if redistribute and load_kg[e] > 0.0:
			over = _redistribute(e, st)
	return over


func _redistribute(e: int, st: int) -> PackedInt32Array:
	var over := PackedInt32Array()
	var p := data.xf[e].origin
	var verts := verticals_by_storey[st]
	var wsum := 0.0
	var r2 := REDISTRIBUTE_RADIUS * REDISTRIBUTE_RADIUS
	for v in verts:
		if alive[v] == 0 or sup[v] == 0:
			continue
		var q := data.xf[v].origin
		var d2 := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d2 < r2:
			wsum += 1.0 / (1.0 + d2)
	if wsum <= 0.0:
		return over
	var amount := load_kg[e]
	load_kg[e] = 0.0
	for v in verts:
		if alive[v] == 0 or sup[v] == 0:
			continue
		var q := data.xf[v].origin
		var d2 := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d2 < r2:
			load_kg[v] += amount * (1.0 / (1.0 + d2)) / wsum
			if load_kg[v] > capacity_kg[v]:
				over.append(v)
	return over


## Overturning check for storey f. Returns {} when stable, else the hinge description:
## {storey, a, b (hinge segment, building XZ), out (unit direction of the fall), com, pivot_y}.
## The structure above overturns when its centre of mass lies outside the hull of the remaining
## supported verticals by more than margin (overloaded edge supports get there by being crushed).
func check_overturn(f: int, margin: float) -> Dictionary:
	overturn_dirty[f] = 0
	if mass_above[f] < 1000.0:
		return {}
	var pts := PackedVector2Array()
	var top_y := 0.0
	for v in verticals_by_storey[f]:
		if alive[v] == 0 or sup[v] == 0:
			continue
		var t := data.xf[v]
		var hx := t.basis.x * (data.dims[v].x * 0.5)
		var hz := t.basis.z * (data.dims[v].z * 0.5)
		var o := t.origin
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c: Vector3 = o + hx * sx + hz * sz
				pts.append(Vector2(c.x, c.z))
		top_y = maxf(top_y, o.y + data.dims[v].y * 0.5)
	if pts.size() < 3:
		return {}
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() >= 2 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	if hull.size() < 3:
		return {}
	var com := Vector2(mom_x_above[f] / mass_above[f], mom_z_above[f] / mass_above[f])
	var inside := Geometry2D.is_point_in_polygon(com, hull)
	var best := 1.0e9
	var ba := Vector2.ZERO
	var bb := Vector2.ZERO
	for i in hull.size():
		var a := hull[i]
		var b := hull[(i + 1) % hull.size()]
		var cp := Geometry2D.get_closest_point_to_segment(com, a, b)
		var dist := cp.distance_to(com)
		if dist < best:
			best = dist
			ba = a
			bb = b
	if inside or best < margin:
		return {}
	var edge := (bb - ba).normalized()
	var out := Vector2(edge.y, -edge.x)
	var centre := Vector2.ZERO
	for h in hull:
		centre += h
	centre /= float(hull.size())
	if out.dot((ba + bb) * 0.5 - centre) < 0.0:
		out = -out
	return {"storey": f, "a": ba, "b": bb, "out": out, "com": com, "pivot_y": top_y, "inside": inside, "distance": best}


## Number of alive elements with no path to an alive anchor over any edge (tests).
func count_unanchored() -> int:
	var n := data.count()
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	var q := PackedInt32Array()
	for i in n:
		if alive[i] == 1 and data.anchor[i] == 1 and data.role[i] != D.Role.ATTACHED:
			seen[i] = 1
			q.append(i)
	var head := 0
	while head < q.size():
		var e := q[head]
		head += 1
		for k in range(data.adj_start[e], data.adj_start[e + 1]):
			var j := data.adj_to[k]
			if alive[j] == 1 and seen[j] == 0:
				seen[j] = 1
				q.append(j)
	var missing := 0
	for i in n:
		if alive[i] == 1 and seen[i] == 0:
			missing += 1
	return missing


func count_alive() -> int:
	var c := 0
	for a in alive:
		c += a
	return c


func count_alive_unsupported() -> int:
	var c := 0
	for i in alive.size():
		if alive[i] == 1 and sup[i] == 0:
			c += 1
	return c
