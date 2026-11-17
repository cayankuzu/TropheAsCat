class_name Traffic
extends Node3D
## Cars that drive (2026-11-17). The road grid of the city (CityLayout.road_lines) carries a fleet of cars
## on the right-hand lane of every road: they cruise, keep their distance to the car ahead, wait their
## turn at a crossing (one car in a crossing at a time), go straight or turn there along a smooth curve,
## brake for Trophe, rubble, wrecks and people in the lane, and honk while they are stuck.
##
## A driving car is a puppet: a kinematic body on Layers.PROPS that the cat can ride on, push against and
## swat. The first hit or blast that reaches it turns it into an ordinary car prop (StreetDressing), with
## the speed it had, and hands the hit on: from then on it crashes, burns and breaks like every parked
## car. Its place in the fleet is taken by a new car somewhere out of sight.
##
## Every car keeps driving wherever it is; only cars near Trophe are drawn, solid and look ahead.
##
## Units (2026-11-17): the Police sends cars of its own into the traffic (`dispatch`). A unit in pursuit
## drives the road grid towards Trophe (at every crossing it takes the way that brings it nearest to her),
## goes through crossings first, and stops in its lane when it is close to her (`unit_arrived`): it then
## blocks the lane, and the traffic behind it queues and honks. A unit that is hit becomes a car prop like
## any other (`unit_crashed`) and does not come back; `retire_unit` takes one off the roads.

signal unit_arrived(car)
signal unit_crashed(car)

const LANE := 2.3            ## lane centre from the road's centre line (right-hand traffic)
const CRUISE := 11.0         ## m/s (40 km/h)
const ACCEL := 2.6
const BRAKE := 8.0
const GAP := 3.5             ## metres kept between bumpers when stopped
const BOX := 13.0            ## a crossing reaches this far from its centre along each road
const NEAR := 170.0          ## cars nearer than this to Trophe are drawn and solid...
const FAR := 190.0           ## ...and stop being so beyond this
const LOOK := 16.0           ## how far a near car looks ahead for obstacles
const LOOK_MASK := Layers.STRUCTURE | Layers.RUBBLE | Layers.PROPS | Layers.DEBRIS | Layers.PROTECTED | Layers.NPC | Layers.PLAYER
const RUN_OVER_SPEED := 4.0  ## m/s from which a car breaks a person in its way
const PURSUIT := 19.0        ## m/s of a unit on its way to Trophe
const ARRIVE := 24.0         ## a unit in pursuit stops when it is this close to her

class Car:
	var id := 0
	var vname: StringName
	var axis := 0            # 0: along x (road at z = line); 1: along z (road at x = line)
	var line := 0.0
	var dir := 1.0           # +1 / -1 along the axis
	var s := 0.0             # where along the axis
	var speed := 0.0
	var cruise := CRUISE
	var length := 4.5
	var turning := false
	var t := 0.0             # metres travelled on the curve through a crossing
	var curve_len := 1.0
	var p0 := Vector3.ZERO
	var p1 := Vector3.ZERO
	var p2 := Vector3.ZERO
	var crossing := Vector2i.ZERO
	var next := Vector4.ZERO # axis, line, dir, s after the crossing
	var pos := Vector3.ZERO
	var yaw := 0.0
	var node: Node3D = null
	var body: AnimatableBody3D = null
	var near := false
	var blocked := 0.0       # seconds stopped by something in the lane
	var look_in := 0.0
	var obstacle := INF      # metres to the nearest thing in the lane (near cars)
	var honk_in := 0.0
	var gone := false
	var height := 1.5
	var unit := false        # sent by the Police: not part of the fleet, never comes back
	var pursuit := false     # on its way to Trophe
	var parked := false      # stopped where it arrived; it blocks its lane
	var paint: Material = null   # one colour over the whole model (the SWAT van)
	var pull := 0.0          # metres pulled over towards the curb (making way for a siren)
	var yield_t := 0.0       # seconds it still waits pulled over
	var width := 1.8
	var driver: Node3D = null    # the porcelain driver in its seat (near Trophe only, see _seat_driver)
	var driver_look := -1
	var driver_tint := -1


var cars: Array[Car] = []
var crashed := 0         ## cars that left the traffic because something hit them
var honks := 0
var run_over := 0

var _dressing: StreetDressing
var _lines := PackedFloat32Array()
var _reach := 384.0
var _closed: Array[Vector4] = []     # axis, line, s0, s1: road stretches no car drives on
var _owner := {}                     # Vector2i crossing -> car id
var _rng := RandomNumberGenerator.new()
var _horn: AudioStreamWAV
var _ray := PhysicsRayQueryParameters3D.new()
var _shapes := {}                    # vehicle name -> BoxShape3D
var _free := PackedFloat32Array()    # per car: metres of free lane ahead of it
var _cat_at := Vector3.INF
## The people of the city (set by the composition root): every car near Trophe has one of them at the wheel,
## seen through the glass, and they get out and run when she takes the car or something hits it.
var people: People = null
const DRIVER_RANGE := 75.0
var _driver_scan := 0
var _follow_tick := 0


## `count` cars on the roads `lines` (CityLayout.road_lines), none on the `closed` stretches.
func setup(dressing: StreetDressing, lines: PackedFloat32Array, count: int, closed: Array[Vector4] = []) -> void:
	_dressing = dressing
	_lines = lines
	_reach = lines[lines.size() - 1]
	_closed = closed
	_rng.seed = 808
	_horn = _make_horn()
	_ray.collision_mask = LOOK_MASK
	_ray.hit_from_inside = false
	for i in count:
		var c := Car.new()
		c.id = i
		_spawn(c, Vector3.INF)
		cars.append(c)


func driving() -> int:
	var n := 0
	for c in cars:
		if not c.gone:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if cars.is_empty() or Timeline.is_rewinding():
		return
	var player := Game.player
	var cat_at := player.global_position if player != null and is_instance_valid(player) else Vector3.INF
	_cat_at = cat_at
	# The free road ahead of each car changes slowly: worked out 20 times a second (it sorts every lane).
	_follow_tick = (_follow_tick + 1) % 3
	if _follow_tick == 0 or _free.size() != cars.size():
		_follow_distances()
	for c in cars:
		if c.gone:
			continue
		var d := c.pos.distance_to(cat_at) if cat_at != Vector3.INF else INF
		if not c.near and d < NEAR:
			_show(c, true)
		elif c.near and d > FAR:
			_show(c, false)
		_drive(c, delta, cat_at)
	# One car a tick is checked for a driver to seat (a figure costs a millisecond or two to make).
	if people != null and cat_at != Vector3.INF:
		_driver_scan = (_driver_scan + 1) % cars.size()
		var dc := cars[_driver_scan]
		if not dc.gone and dc.near and dc.driver == null and dc.node != null and not dc.parked and dc.pos.distance_to(cat_at) < DRIVER_RANGE:
			_seat_driver(dc)


## Each car's free road ahead: to the car in front in its lane.
func _follow_distances() -> void:
	_free.resize(cars.size())
	var lanes := {}
	for c in cars:
		_free[c.id] = INF
		if c.gone or c.turning:
			continue
		var key := Vector3(c.axis, c.line, c.dir)
		if not lanes.has(key):
			lanes[key] = []
		(lanes[key] as Array).append(c)
	for key: Vector3 in lanes:
		var row: Array = lanes[key]
		var dir := key.z
		row.sort_custom(func(a: Car, b: Car) -> bool: return a.s * dir < b.s * dir)
		# Cars just ahead of a unit with its siren on pull over to the curb and wait.
		for i in row.size():
			var a: Car = row[i]
			if not a.pursuit:
				continue
			for j in range(i + 1, row.size()):
				var b: Car = row[j]
				if absf(b.s - a.s) > 45.0:
					break
				if not b.unit:
					b.yield_t = 3.0
		for i in row.size() - 1:
			var a: Car = row[i]
			var j := i + 1
			if a.pursuit:
				while j < row.size() and (row[j] as Car).yield_t > 0.0 and not (row[j] as Car).unit:
					j += 1   # it drives past the ones that pulled over
				if j >= row.size():
					continue
			var b: Car = row[j]
			_free[a.id] = absf(b.s - a.s) - (a.length + b.length) * 0.5 - GAP
	# Cars turning through a crossing hold up whoever comes out right behind them.
	for c in cars:
		if c.gone or not c.turning:
			continue
		for o in cars:
			if o.gone or o.turning or o.axis != int(c.next.x) or o.line != c.next.y or o.dir != c.next.z:
				continue
			var gap := (o.s - c.next.w) * o.dir
			if gap < 0.0 and gap > -40.0:
				_free[o.id] = minf(_free[o.id], -gap - o.length - GAP)


func _drive(c: Car, delta: float, cat_at: Vector3) -> void:
	if c.parked:
		# A unit that arrived: it rolls to a stop and stays where it is (the Police may turn it across).
		if c.speed > 0.0:
			c.speed = maxf(c.speed - BRAKE * 1.4 * delta, 0.0)
			c.s += c.speed * delta * c.dir
			_place(c)
		_sync(c)
		return
	if c.yield_t > 0.0:
		c.yield_t -= delta
	c.pull = move_toward(c.pull, 2.1 if c.yield_t > 0.0 else 0.0, delta * 1.6)
	if c.pursuit and not c.turning and cat_at != Vector3.INF and c.pos.distance_to(cat_at) < _arrive_distance(cat_at):
		c.parked = true
		c.pursuit = false
		if c.driver != null and is_instance_valid(c.driver):
			c.driver.queue_free()   # the officers get out (Police)
		c.driver = null
		unit_arrived.emit(c)
		_sync(c)
		return
	var limit := c.cruise
	var free := _free[c.id]
	var at_line := false
	if not c.turning:
		# The stop line of the next crossing: a car waits there while another one is in it.
		var cx := _next_crossing(c)
		var to_line := (cx - BOX - c.length * 0.5 - c.s * c.dir) if c.dir > 0.0 else (-cx - BOX - c.length * 0.5 + c.s)
		if to_line <= 0.6:
			if _enter(c, cx):
				free = INF
			else:
				free = minf(free, maxf(to_line, 0.0))
				at_line = true   # waiting its turn: nothing to honk about
		elif to_line < 25.0:
			limit = minf(limit, 10.0 if c.pursuit else 6.5)   # slows down for the crossing
	if c.near:
		c.look_in -= delta
		if c.look_in <= 0.0:
			c.look_in = 0.2
			_look_ahead(c, cat_at)
		free = minf(free, c.obstacle)
	# Speed: brake for what is ahead, otherwise towards the cruising speed.
	if c.yield_t > 0.0:
		limit = 0.0   # pulled over: lets the siren past
	var want := limit
	if free < INF:
		want = minf(want, sqrt(maxf(free, 0.0) * 2.0 * BRAKE * 0.6))
		if free < 0.5:
			want = 0.0
	if c.speed > want:
		c.speed = maxf(c.speed - BRAKE * delta, want)
	else:
		c.speed = minf(c.speed + ACCEL * delta, want)
	if c.speed < 0.3 and free < 2.0 and c.near and not at_line:
		# Stuck: the driver honks soon when something is in the lane, later when it is the queue.
		c.blocked += delta
		c.honk_in -= delta
		if c.blocked > (0.8 if c.obstacle < 2.0 else 2.5) and c.honk_in <= 0.0:
			c.honk_in = _rng.randf_range(2.5, 4.5)
			_honk(c)
	else:
		c.blocked = 0.0
	var step := c.speed * delta
	if c.turning:
		c.t += step
		var k := clampf(c.t / c.curve_len, 0.0, 1.0)
		var a := c.p0.lerp(c.p1, k)
		var b := c.p1.lerp(c.p2, k)
		var p := a.lerp(b, k)
		var tangent := b - a
		c.pos = Vector3(p.x, _ground(p.x, p.z), p.z)
		if tangent.length_squared() > 1.0e-6:
			c.yaw = atan2(tangent.x, tangent.z)
		if k >= 1.0:
			c.turning = false
			c.axis = int(c.next.x)
			c.line = c.next.y
			c.dir = c.next.z
			c.s = c.next.w
			if _owner.get(c.crossing, -1) == c.id:
				_owner.erase(c.crossing)
	else:
		c.s += step * c.dir
		_place(c)
	_sync(c)


## The centre of the next crossing ahead along the car's road.
func _next_crossing(c: Car) -> float:
	var k := c.s / CityLayout.BLOCK
	return ceilf(k) * CityLayout.BLOCK if c.dir > 0.0 else floorf(k) * CityLayout.BLOCK


## Enters the crossing at `cx` on its road if nobody else is in it: picks where to go and lays the curve.
func _enter(c: Car, cx: float) -> bool:
	var key := Vector2i(roundi(cx), roundi(c.line)) if c.axis == 0 else Vector2i(roundi(c.line), roundi(cx))
	if _owner.has(key) and _owner[key] != c.id and not c.pursuit:
		return false   # (a unit with its siren on goes first)
	var options: Array[Vector3] = []   # axis, line, dir of the way out
	var other := 1 - c.axis
	if absf(cx + c.dir * CityLayout.BLOCK) <= _reach + 0.1 and _open(c.axis, c.line, cx + c.dir * BOX * 2.0):
		options.append(Vector3(c.axis, c.line, c.dir))
		options.append(Vector3(c.axis, c.line, c.dir))   # straight on is the likeliest
	for d: float in [-1.0, 1.0]:
		if absf(c.line + d * CityLayout.BLOCK) <= _reach + 0.1 and _open(other, cx, c.line + d * BOX * 2.0):
			options.append(Vector3(other, cx, d))
	if options.is_empty():
		options.append(Vector3(c.axis, c.line, -c.dir))   # a dead end: turn round
	var way := options[_rng.randi_range(0, options.size() - 1)]
	if c.pursuit and _cat_at != Vector3.INF:
		# The way out that brings it nearest to Trophe.
		var best := INF
		for o in options:
			var out := c.line + o.z * BOX if int(o.x) != c.axis else cx + o.z * BOX
			var d := _lane_point(int(o.x), o.y, o.z, out + o.z * CityLayout.BLOCK * 0.5).distance_to(Vector3(_cat_at.x, 0.0, _cat_at.z))
			if int(o.x) == c.axis and o.z != c.dir:
				d += CityLayout.BLOCK   # turning round is the last resort
			if d < best:
				best = d
				way = o
	_owner[key] = c.id
	c.crossing = key
	c.turning = true
	c.t = 0.0
	var out_s := c.line + way.z * BOX if int(way.x) != c.axis else cx + way.z * BOX
	if int(way.x) == c.axis and way.z != c.dir:
		out_s = cx - c.dir * BOX   # back the way it came
	c.next = Vector4(way.x, way.y, way.z, out_s)
	c.p0 = c.pos
	c.p2 = _lane_point(int(way.x), way.y, way.z, out_s)
	if int(way.x) == c.axis and way.z == c.dir:
		c.p1 = (c.p0 + c.p2) * 0.5
	elif int(way.x) == c.axis:
		c.p1 = _lane_point(c.axis, c.line, c.dir, cx) + Vector3(0.0, 0.0, 0.0)
	else:
		# Where the two lanes cross.
		var a := _lane_point(c.axis, c.line, c.dir, cx)
		var b := _lane_point(int(way.x), way.y, way.z, c.line)
		c.p1 = Vector3(b.x, 0.0, a.z) if c.axis == 0 else Vector3(a.x, 0.0, b.z)
	c.curve_len = maxf(_curve_length(c.p0, c.p1, c.p2), 1.0)
	return true


func _open(axis: int, line: float, s: float) -> bool:
	for r in _closed:
		if int(r.x) == axis and is_equal_approx(r.y, line) and s >= minf(r.z, r.w) and s <= maxf(r.z, r.w):
			return false
	return true


static func _curve_length(a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := 8
	var prev := a
	var total := 0.0
	for i in range(1, n + 1):
		var k := float(i) / n
		var p := a.lerp(b, k).lerp(b.lerp(c, k), k)
		total += prev.distance_to(p)
		prev = p
	return total


func _lane_point(axis: int, line: float, dir: float, s: float) -> Vector3:
	if axis == 0:
		return Vector3(s, 0.0, line + LANE * dir)
	return Vector3(line - LANE * dir, 0.0, s)


## How close a unit comes before it stops: 24 m by a road; when she is inside a block, the nearest point
## of the road to her will do (its people walk the rest).
func _arrive_distance(cat_at: Vector3) -> float:
	var bx := absf(cat_at.x - roundf(cat_at.x / CityLayout.BLOCK) * CityLayout.BLOCK)
	var bz := absf(cat_at.z - roundf(cat_at.z / CityLayout.BLOCK) * CityLayout.BLOCK)
	return maxf(ARRIVE, minf(bx, bz) + 22.0)


func _place(c: Car) -> void:
	var p := _lane_point(c.axis, c.line, c.dir, c.s + 0.0)
	if c.pull > 0.0:
		p += (Vector3(0.0, 0.0, c.dir) if c.axis == 0 else Vector3(-c.dir, 0.0, 0.0)) * c.pull
	c.pos = Vector3(p.x, _ground(p.x, p.z), p.z)
	c.yaw = PI * 0.5 * c.dir if c.axis == 0 else (0.0 if c.dir > 0.0 else PI)


## A near car looks along its lane for Trophe, people, rubble and wrecks; it breaks a person it is about
## to run into at speed.
func _look_ahead(c: Car, cat_at: Vector3) -> void:
	c.obstacle = INF
	var fwd := Vector3(sin(c.yaw), 0.0, cos(c.yaw))
	var nose := c.pos + fwd * (c.length * 0.5) + Vector3.UP * 0.7
	if cat_at != Vector3.INF:
		var rel := cat_at - nose
		var ahead := rel.dot(fwd)
		var side := absf(rel.dot(Vector3(fwd.z, 0.0, -fwd.x)))
		if ahead > -0.5 and ahead < LOOK and side < 1.6 and absf(rel.y) < 3.0:
			c.obstacle = maxf(ahead - 1.0, 0.0)
	var space := get_world_3d().direct_space_state
	for lateral: float in [-0.75, 0.75]:
		var from := nose + Vector3(fwd.z, 0.0, -fwd.x) * lateral
		_ray.from = from
		_ray.to = from + fwd * LOOK
		_ray.exclude = [c.body.get_rid()] if c.body != null else []
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			continue
		var dist := from.distance_to(hit["position"]) - 1.0
		var collider := hit["collider"] as Object
		if collider is AnimatableBody3D and (collider as Node).get_parent() == self:
			continue   # another driving car: lanes and crossings keep them apart (and two cars that waited
			           # for each other in a crossing would wait for ever)
		var layer := 0
		if collider is CollisionObject3D:
			layer = (collider as CollisionObject3D).collision_layer
		elif hit.has("rid"):
			layer = PhysicsServer3D.body_get_collision_layer(hit["rid"])
		if layer & Layers.NPC and dist < 1.2 and c.speed > RUN_OVER_SPEED:
			# Too late to stop.
			var energy := 0.5 * 1400.0 * c.speed * c.speed
			DamageRouter.apply_hit(DamageHit.point(hit["position"], fwd, energy, 1400.0 * c.speed, DamageHit.Kind.BLUNT, self), collider, hit.get("rid", RID()))
			run_over += 1
			continue
		c.obstacle = minf(c.obstacle, maxf(dist, 0.0))


## Puts a car somewhere on the network (not within `away_from` 150 m of a point, when given).
## Puts a car somewhere on the network: not within 150 m of `away_from` (when given), or, with a `band`,
## between band.x and band.y metres from it. `vname` picks the model (otherwise an everyday car).
func _spawn(c: Car, away_from: Vector3, vname: StringName = &"", band: Vector2 = Vector2.ZERO) -> void:
	var t_probe := PerfProbe.begin()
	_spawn_timed(c, away_from, vname, band)
	PerfProbe.add(&"traffic_spawn", t_probe)


func _spawn_timed(c: Car, away_from: Vector3, vname: StringName = &"", band: Vector2 = Vector2.ZERO) -> void:
	var vehicles := _dressing.vehicles if _dressing != null else null
	if _dressing != null and vehicles == null:
		_dressing.park_cars(0.0, 0, PackedFloat32Array(), 0.0)   # loads the vehicle packs
		vehicles = _dressing.vehicles
	c.vname = &"taxi"
	if vname != &"":
		c.vname = vname
	elif vehicles != null and not vehicles.passenger.is_empty():
		c.vname = vehicles.passenger[_rng.randi_range(0, vehicles.passenger.size() - 1)]
		if _rng.randf() < 0.14 and not vehicles.service.is_empty():
			var special: StringName = [&"taxi", &"taxi", &"police_sedan", &"postvan", &"citybus", &"ambulance"][_rng.randi_range(0, 5)]
			if vehicles.has_vehicle(special):
				c.vname = special
	for attempt in 40:
		c.axis = _rng.randi_range(0, 1)
		c.line = _lines[_rng.randi_range(0, _lines.size() - 1)]
		c.dir = 1.0 if _rng.randf() < 0.5 else -1.0
		var block := _rng.randi_range(-int(_reach / CityLayout.BLOCK), int(_reach / CityLayout.BLOCK) - 1)
		c.s = (block + _rng.randf_range(0.2, 0.8)) * CityLayout.BLOCK
		if not _open(c.axis, c.line, c.s):
			continue
		_place(c)
		if band != Vector2.ZERO and away_from != Vector3.INF:
			var d := c.pos.distance_to(away_from)
			if (d < band.x or d > band.y) and attempt < 39:
				continue
		elif away_from != Vector3.INF and c.pos.distance_to(away_from) < 150.0:
			continue
		var crowded := false
		for o in cars:
			if o != c and not o.gone and o.pos.distance_to(c.pos) < 14.0:
				crowded = true
				break
		if not crowded:
			break
	c.turning = false
	c.gone = false
	c.parked = false
	c.cruise = CRUISE * _rng.randf_range(0.85, 1.12)
	c.speed = c.cruise * 0.7
	c.blocked = 0.0
	c.obstacle = INF
	if c.node != null:
		c.node.queue_free()
		c.node = null
		c.body = null
	c.driver = null
	c.near = false


func _show(c: Car, on: bool) -> void:
	var t_probe := PerfProbe.begin()
	_show_timed(c, on)
	PerfProbe.add(&"traffic_show", t_probe)


func _show_timed(c: Car, on: bool) -> void:
	c.near = on
	if on and c.node == null:
		_build(c)
	if c.node != null:
		c.node.visible = on
		if c.body != null:
			c.body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
			c.body.collision_layer = Layers.PROPS if on else 0
	c.obstacle = INF


func _build(c: Car) -> void:
	var vehicles := _dressing.vehicles if _dressing != null else null
	if vehicles == null:
		return
	var model := vehicles.build(c.vname)
	if model == null:
		return
	# The body is the car: it is moved itself (a body moved by its parent keeps its old place in the
	# physics server), and with sync_to_physics the cat can ride on it.
	c.body = AnimatableBody3D.new()
	c.body.name = "Car%d" % c.id
	c.body.sync_to_physics = true
	c.body.collision_layer = Layers.PROPS
	c.body.collision_mask = 0
	c.node = c.body
	add_child(c.body)
	c.body.add_child(model)
	model.rotate_y(PI)   # the packs' cars face -Z; a driving car faces the way it goes (+Z)
	var box := BreakableProp.bounds_of(model, c.body)
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	c.length = box.size.z
	c.height = box.size.y
	c.width = box.size.x
	if c.paint != null:
		for node in model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = c.paint
	var shape := CollisionShape3D.new()
	var key := c.vname
	if not _shapes.has(key):
		var b := BoxShape3D.new()
		b.size = box.size
		_shapes[key] = b
	shape.shape = _shapes[key]
	shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	c.body.add_child(shape)
	DamageRouter.register_rid(c.body.get_rid(), self, c.id)
	_sync(c)
	c.node.reset_physics_interpolation()


## A person of the cast in the driver's seat. The car faces +Z in its body (see _build): the seat is on its
## left (+X), a little behind the middle of a car, right at the front of a bus or a truck.
func _seat_driver(c: Car) -> void:
	var d := people.make_driver(c.body, People.cast_index("M_Swat") if c.unit else -1)
	var fig: Node3D = d[0]
	c.driver = fig
	c.driver_look = d[1]
	c.driver_tint = d[2]
	fig.transform = seat_transform(c, float(d[3]))


const DRIVER_SCALE := 0.9
## From the hips to the top of the head of a seated figure at DRIVER_SCALE, metres.
const DRIVER_TORSO := 0.74


## Where the driver's figure goes in the car's body so that, in the Drive pose (People: hips at hip_h over
## the root, thighs forward, shins to the pedals), the hips rest on the seat and the back leans on it: the
## lower the roof, the lower the seat and the further back it leans (a sports car), so the head stays inside.
func seat_transform(c: Car, hip_h: float) -> Transform3D:
	var big := c.length > 6.2
	var seat_h := clampf(c.height * 0.37, 0.28, 1.25)
	var room := (c.height - 0.07 - seat_h) / DRIVER_TORSO
	var recline := clampf(acos(clampf(room, -1.0, 1.0)), 0.12, 0.6)
	var hips_z := c.length * 0.5 - 1.6 if big else -c.length * 0.06
	var seat := Basis(Vector3.RIGHT, -recline).scaled(Vector3.ONE * DRIVER_SCALE)
	var hip_local := seat * Vector3(0.0, hip_h, 0.0)
	var hips := Vector3(clampf(c.width * 0.2, 0.3, 0.55), seat_h, hips_z)
	return Transform3D(seat, hips - hip_local)


## The driver gets out of the left door and runs from the car (People.add_runner); with no driver seated
## yet (she took a car the moment it came near) one is made on the spot.
func _eject_driver(c: Car, line: String, shatter: Vector3) -> void:
	if people == null or c.node == null:
		return
	var xf := c.node.global_transform
	var door := xf * Vector3(c.width * 0.5 + 0.55, 0.0, -c.length * 0.05)
	var away := (xf.basis * Vector3(1.0, 0.0, -0.3)).normalized()
	var fig := c.driver if c.driver != null and is_instance_valid(c.driver) else null
	c.driver = null
	people.add_runner(door, away, c.driver_look, c.driver_tint, fig, line, shatter)
	c.driver_look = -1
	c.driver_tint = -1


func _sync(c: Car) -> void:
	if c.node != null and c.near:
		c.node.global_transform = Transform3D(Basis(Vector3.UP, c.yaw), c.pos)


## DamageRouter entry: a hit on a driving car turns it into a car prop that takes the hit.
func receive_damage(hit: DamageHit, user_id: int) -> void:
	if user_id < 0 or user_id >= cars.size():
		return
	var c := cars[user_id]
	if c.gone:
		return
	# A blast that throws the car breaks the porcelain driver; anything less sends them running.
	var blast := hit.radius > 0.0 and hit.energy > 2.0e5
	var away := c.pos - hit.position
	var prop := _crash(c, People.CRASH_LINES[_rng.randi_range(0, People.CRASH_LINES.size() - 1)], away if blast else Vector3.ZERO)
	if prop != null:
		prop.receive_damage(hit, 0)


## Leaves the traffic as a car prop moving at the speed it had; a new car takes its place out of sight.
## Its driver gets out of the door and runs, shouting `line` (or breaks, when `shatter` is set).
func _crash(c: Car, line: String = "", shatter: Vector3 = Vector3.ZERO) -> BreakableProp:
	var at := c.pos
	var yaw := c.yaw
	var speed := c.speed
	var vname := c.vname
	if not c.unit:
		_eject_driver(c, line, shatter)
	if c.body != null:
		DamageRouter.unregister_rid(c.body.get_rid())
	if _owner.get(c.crossing, -1) == c.id:
		_owner.erase(c.crossing)
	c.gone = true
	if c.node != null:
		c.node.queue_free()   # with whoever still sat in it
		c.node = null
		c.body = null
	c.driver = null
	crashed += 1
	var prop := _dressing.add_vehicle(vname, at, yaw + PI) if _dressing != null else null   # (the model faces -Z)
	if prop != null:
		prop.freeze = false
		prop.linear_velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * speed
		if c.paint != null:
			for node in prop.find_children("*", "MeshInstance3D", true, false):
				(node as MeshInstance3D).material_override = c.paint
	if c.unit:
		unit_crashed.emit(c)
		return prop
	# The fleet stays the same size: a new car comes in somewhere out of sight.
	get_tree().create_timer(4.0, false).timeout.connect(_respawn.bind(c.id))
	return prop


## Trophe takes a driving car (CatDriving): it leaves the traffic as a car prop at rest under her paws.
func take_car(c: Car) -> BreakableProp:
	if c == null or c.gone:
		return null
	var prop := _crash(c, People.CARJACKED_LINES[_rng.randi_range(0, People.CARJACKED_LINES.size() - 1)])
	if prop != null:
		prop.linear_velocity = Vector3.ZERO
	return prop


## A unit of the Police: `vname` on the roads 110 to 190 m from Trophe, in pursuit of her. A unit that is
## gone is reused.
func dispatch(vname: StringName, paint: Material = null) -> Car:
	var c: Car = null
	for o in cars:
		if o.unit and o.gone:
			c = o
			break
	if c == null:
		c = Car.new()
		c.id = cars.size()
		c.gone = true
		cars.append(c)
	c.unit = true
	c.paint = paint
	_spawn(c, _cat_at, vname, Vector2(110.0, 190.0))
	c.pursuit = true
	c.cruise = PURSUIT
	c.speed = 12.0
	return c


## Takes a unit off the roads (it drove off out of sight).
func retire_unit(c: Car) -> void:
	if c.gone:
		return
	if c.body != null:
		DamageRouter.unregister_rid(c.body.get_rid())
	if _owner.get(c.crossing, -1) == c.id:
		_owner.erase(c.crossing)
	c.gone = true
	c.pursuit = false
	c.parked = false
	if c.node != null:
		c.node.queue_free()
		c.node = null
		c.body = null
	c.driver = null
	c.near = false


func _respawn(id: int) -> void:
	if id < 0 or id >= cars.size() or not cars[id].gone:
		return
	var away := Game.player.global_position if Game.player != null and is_instance_valid(Game.player) else Vector3.INF
	_spawn(cars[id], away)


func _honk(c: Car) -> void:
	honks += 1
	if c.node == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _horn
	p.unit_size = 12.0
	p.max_distance = 140.0
	p.volume_db = -4.0
	p.pitch_scale = _rng.randf_range(0.9, 1.12)
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	c.node.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## A car horn: two detuned square-ish tones with a short attack and release (0.5 s).
static func _make_horn() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.5)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(t / 0.015, 1.0) * minf((0.5 - t) / 0.06, 1.0)
		var v := 0.0
		for f: float in [392.0, 494.0]:
			var ph := fposmod(t * f, 1.0)
			v += (1.0 if ph < 0.5 else -1.0) * 0.55 + sin(TAU * f * t) * 0.45
		v *= 0.22 * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0


func _exit_tree() -> void:
	for c in cars:
		if c.body != null:
			DamageRouter.unregister_rid(c.body.get_rid())
