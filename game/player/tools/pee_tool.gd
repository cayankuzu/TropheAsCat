class_name PeeTool
extends CatTool
## Tool 2, Pee. Trophe has it from the first second: hold primary and she rears up on her hind legs and
## marks her territory, a stream that lands where the crosshair points.
##
## Plain pee harms nothing. It leaves puddles, nudges light things (a vase walks off its table and
## breaks on the ground) and sends whoever it lands on running. At the last milestone the Owner tries
## the spray bottle and Trophe answers in kind: from then on it is Acid Pee, and every drop that lands
## leaves a pool that eats into whatever is under it (ACID hits several times a second, weakening as
## the pool dries and following the surface as it recedes: walls get holes, the ground gets shafts).
##
## Drops are not physics bodies. The whole parabola of a drop is traced when it leaves; the drawn
## droplet (a WorldFX blob with no drag) flies the same parabola and dies at the traced impact time.

const PEE := Color(0.98, 0.84, 0.2)
const ACID := Color(0.74, 0.95, 0.2)
const GRAVITY := 9.8
const STEP := 0.06            ## Seconds of flight per traced segment.
const MAX_FLIGHT := 2.4
const AIM_RANGE := 40.0
## Droplets drawn per traced drop: they fill the gaps so the arc reads as a stream.
const DRAWN_PER_DROP := 3
## From the hips bone to where the stream starts (metres, along her facing and up).
const ORIGIN_FORWARD := 0.03
const ORIGIN_UP := -0.2
const POOL_MERGE := 0.5       ## A drop landing this close to a pool tops it up instead of adding one.
const POOL_REACH := 1.2       ## How far behind the eaten surface a pool looks for the next one.
const PUDDLE_MERGE := 0.3
const PUDDLE_SECONDS := 14.0
const MAX_PUDDLES := 40
## What a plain drop does to the thing it lands on: no damage worth the name, a small push.
const WET_ENERGY := 20.0
const WET_IMPULSE := 0.9

@export var stream_speed := 13.0           ## Reaches about 17 m on flat ground.
@export var drops_per_second := 30.0
@export var spread_deg := 2.2
@export var pool_seconds := 3.5
@export var pool_tick_hz := 5.0
@export var energy_per_tick := 9000.0     ## Joules of ACID at full strength (structures take 80 %).
@export var max_pools := 24

## True once the Acid Pee milestone is reached (or in the sandbox).
var acid := false
var drops := 0
var landings := 0
var nudges := 0             ## plain drops that landed on a light prop or a person
var energy_dealt := 0.0

var _held := false
var _emit_debt := 0.0
var _flights: Array[Dictionary] = []   # {t, pos, normal, dir, collider, rid, person}
var _pools: Array[Dictionary] = []     # {pos, normal, left, tick}
var _puddles: Array[Dictionary] = []   # {pos, left}
var _cause := 0
var _loop := -1
var _sizzle: Node3D
var _fume_toggle := false


func _init() -> void:
	tool_name = "Pee"
	tool_id = &"pee"


func _ready() -> void:
	_sizzle = Node3D.new()
	_sizzle.name = "Sizzle"
	_sizzle.top_level = true
	add_child(_sizzle)
	_refresh()
	Progress.tool_unlocked.connect(_on_tool_unlocked)


func _on_tool_unlocked(_id: StringName) -> void:
	_refresh()


func _refresh() -> void:
	acid = Progress.is_tool_unlocked(Progress.TOOL_ACID)
	tool_name = "Acid Pee" if acid else "Pee"


func unequip() -> void:
	_held = false
	super()


func primary(pressed: bool) -> void:
	_held = pressed
	if pressed:
		_cause = DamageRouter.new_cause_id()


func pool_count() -> int:
	return _pools.size()


func puddle_count() -> int:
	return _puddles.size()


func process(delta: float) -> void:
	if not _held:
		_emit_debt = 0.0
		return
	cat.hold_tall_stance(0.3)
	_emit_debt += drops_per_second * delta
	while _emit_debt >= 1.0:
		_emit_debt -= 1.0
		_drop()


## Runs whether or not the tool is equipped: drops in the air still land, pools keep eating.
func _physics_process(delta: float) -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var f := _flights[i]
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) <= 0.0:
			_flights.remove_at(i)
			_land(f)
	for i in range(_puddles.size() - 1, -1, -1):
		_puddles[i]["left"] = float(_puddles[i]["left"]) - delta
		if float(_puddles[i]["left"]) <= 0.0:
			_puddles.remove_at(i)
	for i in range(_pools.size() - 1, -1, -1):
		if not _tick_pool(_pools[i], delta):
			_pools.remove_at(i)
	if _pools.is_empty():
		if _loop >= 0:
			Audio.stop_loop(_loop)
			_loop = -1
	else:
		_sizzle.global_position = _pools[_pools.size() - 1]["pos"]
		if _loop < 0:
			_loop = Audio.start_loop(&"acid_loop", _sizzle)


## Where the stream leaves her: between the hind legs.
func _origin() -> Vector3:
	return cat.get_hip_position() + cat.get_facing() * ORIGIN_FORWARD + Vector3.UP * ORIGIN_UP


func _drop() -> void:
	drops += 1
	var origin := _origin()
	var dir := _launch_direction(origin, crosshair_point(AIM_RANGE))
	var spread := deg_to_rad(spread_deg)
	dir = (dir + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * tan(spread)).normalized()
	var v := dir * stream_speed * randf_range(0.93, 1.05)
	var life := MAX_FLIGHT
	var prev := origin
	var steps := int(MAX_FLIGHT / STEP)
	for i in range(1, steps + 1):
		var t1 := i * STEP
		var p := origin + v * t1 + Vector3.DOWN * (0.5 * GRAVITY * t1 * t1)
		var hit := trace(prev, p)
		if not hit.is_empty():
			var seg := prev.distance_to(p)
			var frac := prev.distance_to(hit["position"]) / maxf(seg, 0.001)
			life = (i - 1) * STEP + STEP * frac
			var rid: RID = hit.get("rid", RID())
			var push := Vector3(v.x, 0.0, v.z).normalized()
			_flights.append({"t": life, "pos": hit["position"], "normal": hit["normal"], "dir": push, "collider": hit.get("collider"),
				"rid": rid, "person": rid.is_valid() and (PhysicsServer3D.body_get_collision_layer(rid) & Layers.NPC) != 0})
			break
		prev = p
	var fx := WorldFX.instance
	if fx != null:
		var c := ACID if acid else PEE
		var tint := Color(c.r, c.g, c.b, 0.9 if acid else 0.3)   # alpha is the glow of a blob
		var gap := 1.0 / (drops_per_second * DRAWN_PER_DROP)
		for k in DRAWN_PER_DROP:
			# A droplet started dt further along the same parabola is one that left dt earlier.
			var dt := gap * k + 0.012   # a little ahead, so the stretched droplet does not reach back behind her
			if dt >= life:
				break
			fx.blobs.emit(origin + v * dt + Vector3.DOWN * (0.5 * GRAVITY * dt * dt), v + Vector3.DOWN * (GRAVITY * dt), tint, maxf(life - dt, 0.05), 0.042, 0.032)


## The flat arc that lands on `target`; out of reach, the longest arc there is.
func _launch_direction(origin: Vector3, target: Vector3) -> Vector3:
	var to := target - origin
	var flat := Vector3(to.x, 0.0, to.z)
	var d := flat.length()
	if d < 0.05:
		return to.normalized() if to.length_squared() > 0.0001 else Vector3.DOWN
	var v2 := stream_speed * stream_speed
	var disc := v2 * v2 - GRAVITY * (GRAVITY * d * d + 2.0 * to.y * v2)
	var rise := 1.0
	if disc >= 0.0:
		rise = (v2 - sqrt(disc)) / (GRAVITY * d)
	return (flat / d + Vector3.UP * rise).normalized()


func _land(f: Dictionary) -> void:
	landings += 1
	var pos: Vector3 = f["pos"]
	var normal: Vector3 = f["normal"]
	var fx := WorldFX.instance
	if not acid:
		if fx != null:
			fx.splash(pos, normal, 2, PEE, 0.35, 2.2)
		_wet(f)
		return
	if fx != null:
		fx.splash(pos, normal, 4, ACID, 0.7, 3.0)
		fx.puff(pos + normal * 0.15, normal * 0.5 + Vector3.UP * 0.6, Color(0.95, 0.93, 0.7, 0.4), 1.2, 0.3, 0.9)
	for pool in _pools:
		if (pool["pos"] as Vector3).distance_to(pos) < POOL_MERGE:
			pool["left"] = pool_seconds
			return
	if fx != null:
		fx.marks.splat(pos, normal, randf_range(0.3, 0.45), ACID, 1.3, pool_seconds + 3.0, pool_seconds)
	_pools.append({"pos": pos, "normal": normal, "left": pool_seconds, "tick": randf() / pool_tick_hz})
	if _pools.size() > max_pools:
		_pools.remove_at(0)


## A plain drop: a puddle where it lands, and a nudge for a light prop or a person under it. Nature
## and animals are left alone (it is only pee), so the CAT-PROOF shield has nothing to say.
func _wet(f: Dictionary) -> void:
	var pos: Vector3 = f["pos"]
	var normal: Vector3 = f["normal"]
	var collider: Variant = f["collider"]   # may be gone by the time the drop lands
	var prop: BreakableProp = null
	if is_instance_valid(collider) and collider is BreakableProp:
		prop = collider
	if bool(f["person"]) or (prop != null and prop.mass < BreakableProp.KNOCK_MASS):
		var hit := DamageHit.point(pos, f["dir"], WET_ENERGY, WET_IMPULSE, DamageHit.Kind.BLUNT, cat)
		hit.normal = normal
		hit.cause_id = _cause
		nudges += 1
		DamageRouter.apply_hit(hit, prop, f["rid"])
		return
	for puddle in _puddles:
		if (puddle["pos"] as Vector3).distance_to(pos) < PUDDLE_MERGE:
			return
	var fx := WorldFX.instance
	if fx != null:
		fx.marks.splat(pos, normal, randf_range(0.22, 0.36), PEE, 0.25, PUDDLE_SECONDS, 1.0)
	_puddles.append({"pos": pos, "left": PUDDLE_SECONDS * 0.6})
	if _puddles.size() > MAX_PUDDLES:
		_puddles.remove_at(0)


## One pool, one physics tick. Returns false when the pool is spent or has nothing left to eat.
func _tick_pool(pool: Dictionary, delta: float) -> bool:
	pool["left"] = float(pool["left"]) - delta
	if float(pool["left"]) <= 0.0:
		return false
	pool["tick"] = float(pool["tick"]) - delta
	if float(pool["tick"]) > 0.0:
		return true
	pool["tick"] = 1.0 / pool_tick_hz
	if cat == null or not is_instance_valid(cat):
		return false
	var pos: Vector3 = pool["pos"]
	var normal: Vector3 = pool["normal"]
	# The surface under the pool may have been eaten away since the last tick: find what is there now.
	var under := trace(pos + normal * 0.35, pos - normal * POOL_REACH)
	if under.is_empty():
		return false
	pos = under["position"]
	normal = under["normal"]
	pool["pos"] = pos
	pool["normal"] = normal
	var strength := float(pool["left"]) / pool_seconds
	var hit := DamageHit.point(pos, -normal, energy_per_tick * strength, 0.0, DamageHit.Kind.ACID, cat)
	hit.normal = normal
	hit.cause_id = _cause
	energy_dealt += hit.energy
	deliver(hit, under.get("collider"), under.get("rid", RID()))
	var fx := WorldFX.instance
	if fx != null:
		_fume_toggle = not _fume_toggle
		fx.puff(pos + normal * 0.1, normal * 0.3 + Vector3.UP * 0.8, Color(0.95, 0.93, 0.72, 0.32 * strength + 0.08), 1.4, 0.25, 1.0)
		if _fume_toggle:
			fx.splash(pos, normal, 1, ACID, 0.8, 1.6)
	return true
