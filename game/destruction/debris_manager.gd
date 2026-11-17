class_name DebrisManager
extends Node3D
## Dynamic debris and permanent rubble.
##  * PIECE: one Voronoi cell of a fractured element (pooled RigidBody3D).
##  * ELEMENT: a whole loose element (pooled RigidBody3D); it can still fracture.
##  * CLUSTER: a falling compound of intact elements (DebrisCluster, its own RigidBody3D).
## T1 bodies (large pieces, elements, clusters) collide with everything and deal impact damage through
## DamageRouter when their velocity changes abruptly. T2 pieces use DEBRIS_SMALL and ignore each other.
## Settled bodies become static rubble (PhysicsServer3D body + batched MultiMesh, layer RUBBLE) and stay
## forever; wake_rubble() turns a piece back into a body. Over the awake budget the oldest / farthest
## bodies are frozen into rubble. Nothing is ever deleted.

signal debris_spawned(body: RigidBody3D)
signal debris_frozen(body: RigidBody3D, rubble_rid: RID)
signal rubble_woken(rubble_rid: RID, body: RigidBody3D)
signal rubble_moved(rubble_rid: RID, xform: Transform3D)   ## lost its support and was set down lower
signal impact(position: Vector3, energy: float, material: StringName)   ## a debris body landed hard (sound, effects)

enum Kind { PIECE, ELEMENT, CLUSTER }

const T1 := 0
const T2 := 1
const MASK_T1 := Layers.TERRAIN | Layers.STRUCTURE | Layers.DEBRIS | Layers.DEBRIS_SMALL | Layers.RUBBLE | Layers.PROPS | Layers.NPC | Layers.PLAYER | Layers.PROTECTED
## Small chunks touch the world and get pushed by large pieces (MASK_T1), never each other or clusters.
const MASK_T2 := Layers.TERRAIN | Layers.STRUCTURE | Layers.RUBBLE | Layers.PROPS | Layers.PROTECTED
## Clusters and loose elements ignore small chunks in every state: they see dynamic large debris and
## large rubble through the DEBRIS bit (large rubble is on RUBBLE | DEBRIS, small rubble on RUBBLE only),
## so a small chunk frozen inside a falling floor can never prop it up or push it.
const MASK_CLUSTER := MASK_T1 & ~Layers.DEBRIS_SMALL & ~Layers.RUBBLE
const LAYER_RUBBLE_LARGE := Layers.RUBBLE | Layers.DEBRIS
const LAYER_RUBBLE_SMALL := Layers.RUBBLE
## What rubble may rest on: static things only (a dynamic body under it can move away).
const STATIC_SUPPORT := Layers.TERRAIN | Layers.STRUCTURE | Layers.RUBBLE | Layers.PROTECTED
const SUPPORT_PROBE := 0.08        ## m below a rubble piece's lowest point where its support must be
const BELOW_STATIC := 0
const BELOW_DYNAMIC := 1
const BELOW_NOTHING := 2
const CHECK_NONE := 0
const CHECK_QUEUED := 1
const CHECK_ACTIVE := 2
const RUBBLE_FLAG := 1 << 30
const IGNORE_IMPACT_TICKS := 3
const MAX_PUSH_DV := 18.0   ## m/s, largest velocity change one hit may give a debris body
## Sustained load: a resting cluster turns contact force into CRUSH damage on what carries it
## (energy per second = CRUSH_K * force). Rigid bodies never fail under static load otherwise, and a
## plaster partition would hold four storeys.
const CRUSH_K := 3.0
const CRUSH_MIN_IMPULSE := 150.0   ## N*s per tick, about 9 kN
const KILL_Y := -90.0   ## below the Table: loose debris that gets here is removed
const CRUSH_EVERY := 6             ## ticks between load checks of a resting cluster
const CLUSTER_AWAKE_SECONDS := 4.0
const MAX_IMPACTS_PER_TICK := 16
const IMPACT_SIGNAL_MIN_J := 2000.0   ## impacts below this are silent
const IMPACT_BUDGET_USEC := 2500   ## impacts beyond this keep their pre-impact velocity and run next tick

@export var awake_budget := 1500
@export var settle_seconds := 1.0
## When the budget is nearly full, bodies that have been at rest this long are frozen early, so the
## budget is enforced with resting bodies instead of ones still in flight.
@export var rest_seconds := 0.25
@export var max_active_seconds := 30.0
@export var support_checks_per_frame := 48
@export var impact_dv := 3.0
## A loose piece that lands with less kinetic energy than this is not worth an impact: it could not
## crack anything it touches, and handling it (contact query, hits, dust) costs as much as a big one.
## Clusters and whole elements are always handled.
@export var piece_impact_min_j := 1000.0
@export var impact_energy_factor := 1.0
@export var budget_ms := 0.5
@export var pool_prewarm := 384
@export var pool_spare := 192            ## bodies kept ready when the scene is quiet

var structures: StructureManager = null
var fx: DestructionFX = null

# Active records, index = slot id.
var _body: Array[RigidBody3D] = []
var _kind := PackedByteArray()
var _tier := PackedByteArray()
var _used := PackedByteArray()
var _mesh: Array[Mesh] = []
var _shape: Array[Shape3D] = []
var _mass := PackedFloat32Array()
var _com := PackedVector3Array()
var _mat: Array[StringName] = []
var _owner_b := PackedInt32Array()
var _owner_e := PackedInt32Array()
var _cluster: Array[DebrisCluster] = []
var _spawn_t := PackedFloat64Array()
var _spawn_xf: Array[Transform3D] = []   # where each record was born (world rewind flies it back there)
## When it was born for the rewind. Unlike _spawn_t (its age for freezing) a woken rubble piece keeps the
## birth it had as debris here.
var _born := PackedFloat64Array()
var _checked_t := PackedFloat64Array()
var _still := PackedFloat32Array()
var _prev_v := PackedVector3Array()
var _prev_w := PackedVector3Array()
var _pre_w_tick := PackedVector3Array()   # angular velocity before this tick (clusters)
var _ticks := PackedInt32Array()
var _cause := PackedInt32Array()
var _gen := PackedInt32Array()
var _registered := PackedByteArray()
var _free_slots := PackedInt32Array()
var _active := PackedInt32Array()
var _active_pos := PackedInt32Array()
var _t1_active := PackedInt32Array()   # the T1 subset of _active (impact and load checks)
var _t1_pos := PackedInt32Array()
# Age order of the active non-cluster bodies, oldest first: an intrusive list over slots, so the budget
# never walks over records that are gone.
var _age_prev := PackedInt32Array()
var _age_next := PackedInt32Array()
var _age_head := -1
var _age_tail := -1
var _pool: Array[RigidBody3D] = []
var _phys_mat := PhysicsMaterial.new()
var _scan := 0
var _time := 0.0
var _tick := 0
var _freeze_queue := PackedInt64Array()   # (gen << 32) | slot, bodies found at rest by the scan
var _fq_head := 0
var _slot_by_rid: Dictionary = {}          # body RID -> slot
var _wake_query := PhysicsShapeQueryParameters3D.new()
var _wake_shape := BoxShape3D.new()
var _support_ray := PhysicsRayQueryParameters3D.new()
var _drop_ray := PhysicsRayQueryParameters3D.new()
var _below_ray := PhysicsRayQueryParameters3D.new()
var _support_rid := RID()                  # static body found by the last _below / _drop_to_rest ray
var _below_slot := -1                      # debris body the last _below found under a body (BELOW_DYNAMIC)
var _check_queue := PackedInt32Array()    # rubble ids whose support may be gone
var _check_head := 0
var _freezing: Array[DebrisCluster] = []   # big clusters turned into rubble a few elements per frame

# Rubble records, index = rubble id (stable; freed ids are reused).
var _rb_rid: Array[RID] = []
var _rb_xf: Array[Transform3D] = []
var _rb_mesh: Array[Mesh] = []
var _rb_shape: Array[Shape3D] = []
var _rb_mass := PackedFloat32Array()
var _rb_com := PackedVector3Array()
var _rb_mat: Array[StringName] = []
var _rb_owner_b := PackedInt32Array()
var _rb_owner_e := PackedInt32Array()
var _rb_group := PackedInt32Array()
var _rb_inst := PackedInt32Array()
var _rb_alive := PackedByteArray()
var _rb_check := PackedByteArray()      # 1 while queued for a support check
var _rb_on: Array[RID] = []             # the static body this piece was found resting on (RID() if unknown)
var _resting_on: Dictionary = {}        # static body RID -> PackedInt32Array of rubble ids recorded on it
var _rb_free := PackedInt32Array()
var _rb_by_rid: Dictionary = {}
var _rb_groups: Array[InstanceGroup] = []
var _rb_group_by_mesh: Dictionary = {}

# Statistics.
var debris_mass := 0.0
var rubble_mass := 0.0
var rubble_count := 0
var spawned_total := 0
var frozen_total := 0
var forced_freezes := 0
var forced_fast_freezes := 0   ## forced freezes of bodies still moving faster than 1 m/s
var lost_total := 0            ## loose bodies removed below KILL_Y
var dropped_freezes := 0       ## bodies moved down to their landing spot before freezing
var rubble_support_wakes := 0  ## rubble pieces that lost what carried them (woken, or dropped as rubble)
var rubble_drops := 0          ## of those, moved straight down as rubble because the budget was full
var support_checks := 0
var unsupported_wakes := 0
var prof_support_usec := 0
var prof_drop_usec := 0
var prof_freeze_usec := 0
var prof_scan_usec := 0
var prof_spawn_usec := 0
var prof_add_usec := 0
var prof_deact_usec := 0
var prof_below_usec := 0
var prof_freezes := 0
var freeze_reason := 0               ## diagnostics: why the next rubble piece is created (see _rb_reason)
var _rb_reason := PackedByteArray()  # 0 settled, 1 forced at rest, 2 forced + dropped, 3 forced in place, 4 cluster, 5 direct
var _rb_time := PackedFloat32Array() # when it became rubble (diagnostics)
var _rb_checked := PackedFloat32Array()  # when its support was last checked, -1 never (diagnostics)
var _rb_born := PackedFloat64Array()     # when the piece was born as debris (world rewind)
var _rb_born_xf: Array[Transform3D] = []

## World rewind (Timeline): debris born after the rewind cursor flies back to where it was born during
## the last REWIND_FLY seconds before its birth and is removed when the cursor passes it. While
## `rewinding` the frame logic stands still.
const REWIND_FLY := 1.1
const REWIND_LAG := 0.12
var rewinding := false
var _rw_now := 0.0
var _rw_from: Dictionary = {}   # slot, or -1 - rubble index -> transform when it started flying back
var impacts_total := 0
var crush_checks := 0
var crush_hits := 0
var crush_energy := 0.0
var frame_usec := 0          ## logic time of the last _process
var physics_usec := 0        ## logic time of the last _physics_process


func _enter_tree() -> void:
	Game.debris = self


func _exit_tree() -> void:
	clear()
	if Game.debris == self:
		Game.debris = null


## Frees all rubble server bodies and returns every active body to the pool (teardown / tests).
func clear() -> void:
	for s in _active.duplicate():
		_deactivate(s)
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1:
			DamageRouter.unregister_rid(_rb_rid[idx])
			PhysicsServer3D.free_rid(_rb_rid[idx])
			_rb_alive[idx] = 0
	_rb_by_rid.clear()
	for g in _rb_groups:
		g.free_node()
	_rb_groups.clear()
	_rb_group_by_mesh.clear()
	_rb_free.clear()
	for idx in _rb_alive.size():
		_rb_free.append(idx)
	rubble_count = 0
	rubble_mass = 0.0
	debris_mass = 0.0
	_freeze_queue.clear()
	_fq_head = 0
	_check_queue.clear()
	_check_head = 0
	_rb_check.fill(0)
	_rb_on.fill(RID())
	_resting_on.clear()
	_freezing.clear()
	_age_head = -1
	_age_tail = -1


func _ready() -> void:
	_phys_mat.friction = 0.65
	_phys_mat.bounce = 0.05
	_support_ray.collision_mask = STATIC_SUPPORT
	_drop_ray.collision_mask = STATIC_SUPPORT
	_drop_ray.hit_from_inside = true   # a corner already inside something static means it rests there
	_below_ray.collision_mask = STATIC_SUPPORT | Layers.DEBRIS | Layers.DEBRIS_SMALL
	for i in pool_prewarm:
		_pool.append(_new_pooled_body())


func _new_pooled_body() -> RigidBody3D:
	var b := RigidBody3D.new()
	b.physics_material_override = _phys_mat
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.can_sleep = true
	var mi := MeshInstance3D.new()
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	b.add_child(cs)
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.visible = false
	add_child(b)
	return b


func _take_body() -> RigidBody3D:
	if _pool.is_empty():
		return _new_pooled_body()
	return _pool.pop_back()


func _alloc_slot() -> int:
	var s: int
	if not _free_slots.is_empty():
		s = _free_slots[_free_slots.size() - 1]
		_free_slots.resize(_free_slots.size() - 1)
	else:
		s = _body.size()
		_body.append(null)
		_kind.append(0)
		_tier.append(0)
		_used.append(0)
		_mesh.append(null)
		_shape.append(null)
		_mass.append(0.0)
		_com.append(Vector3.ZERO)
		_mat.append(&"")
		_owner_b.append(-1)
		_owner_e.append(-1)
		_cluster.append(null)
		_spawn_t.append(0.0)
		_spawn_xf.append(Transform3D.IDENTITY)
		_born.append(0.0)
		_checked_t.append(0.0)
		_still.append(0.0)
		_prev_v.append(Vector3.ZERO)
		_prev_w.append(Vector3.ZERO)
		_pre_w_tick.append(Vector3.ZERO)
		_ticks.append(0)
		_cause.append(0)
		_gen.append(0)
		_registered.append(0)
		_active_pos.append(-1)
		_t1_pos.append(-1)
		_age_prev.append(-1)
		_age_next.append(-1)
	_gen[s] += 1
	_used[s] = 1
	_cluster[s] = null
	_owner_b[s] = -1
	_owner_e[s] = -1
	_still[s] = 0.0
	_ticks[s] = 0
	_spawn_t[s] = _time
	_born[s] = _time
	_checked_t[s] = _time
	return s


func _activate(s: int, lin: Vector3) -> void:
	_slot_by_rid[_body[s].get_rid()] = s
	_prev_v[s] = lin
	_prev_w[s] = _body[s].angular_velocity
	_active_pos[s] = _active.size()
	_active.append(s)
	if _tier[s] == T1:
		_t1_pos[s] = _t1_active.size()
		_t1_active.append(s)
	if _kind[s] != Kind.CLUSTER:   # clusters are never frozen by the budget (see _freeze_oldest)
		_age_prev[s] = _age_tail
		_age_next[s] = -1
		if _age_tail >= 0:
			_age_next[_age_tail] = s
		else:
			_age_head = s
		_age_tail = s
	debris_mass += _mass[s]
	spawned_total += 1
	debris_spawned.emit(_body[s])


## Make room for n new bodies when the budget would be exceeded: bodies already at rest first, then
## the oldest ones.
func make_room(n: int) -> void:
	var excess := _active.size() + n - awake_budget
	if excess > 0:
		excess -= _drain_rest(excess, 1 << 62)
	if excess > 0:
		_freeze_oldest(excess)


func active_count() -> int:
	return _active.size()


func awake_count() -> int:
	var c := 0
	for s in _active:
		if not _body[s].sleeping:
			c += 1
	return c


func spawn_piece(mesh: Mesh, shape: Shape3D, xf: Transform3D, com: Vector3, mass: float, lin: Vector3, ang: Vector3,
		tier: int, material: StringName, cause: int) -> int:
	var s := _alloc_slot()
	_kind[s] = Kind.PIECE
	_setup_pooled(s, mesh, shape, xf, com, mass, lin, ang, tier, material, cause)
	return s


func spawn_element(building: int, element: int, mesh: Mesh, shape: Shape3D, xf: Transform3D, com: Vector3, mass: float,
		lin: Vector3, ang: Vector3, material: StringName, cause: int) -> int:
	var s := _alloc_slot()
	_kind[s] = Kind.ELEMENT
	_owner_b[s] = building
	_owner_e[s] = element
	_setup_pooled(s, mesh, shape, xf, com, mass, lin, ang, T1, material, cause)
	# Whole elements plough through small rubble like clusters do (they may appear inside it when a
	# cluster breaks up).
	_body[s].collision_mask = MASK_CLUSTER
	return s


func _setup_pooled(s: int, mesh: Mesh, shape: Shape3D, xf: Transform3D, com: Vector3, mass: float, lin: Vector3, ang: Vector3,
		tier: int, material: StringName, cause: int) -> void:
	var t0 := Time.get_ticks_usec()
	var b := _take_body()
	_body[s] = b
	_tier[s] = tier
	_mesh[s] = mesh
	_shape[s] = shape
	_mass[s] = mass
	_com[s] = com
	_mat[s] = material
	_cause[s] = cause
	(b.get_child(0) as MeshInstance3D).mesh = mesh
	(b.get_child(1) as CollisionShape3D).shape = shape
	b.mass = maxf(mass, 0.5)
	b.center_of_mass = com
	# Reused pool bodies often have the right settings already; server writes are the expensive part.
	var layer := Layers.DEBRIS if tier == T1 else Layers.DEBRIS_SMALL
	if b.collision_layer != layer:
		b.collision_layer = layer
	# Checked on its own: a crushed element body changes layer without dropping its contact reports.
	if b.contact_monitor != (tier == T1):
		b.contact_monitor = tier == T1
		b.max_contacts_reported = 4 if tier == T1 else 0
	var mask := MASK_T1 if tier == T1 else MASK_T2
	if b.collision_mask != mask:
		b.collision_mask = mask
	b.global_transform = xf
	_spawn_xf[s] = xf
	b.process_mode = Node.PROCESS_MODE_INHERIT
	b.visible = true
	b.sleeping = false
	b.linear_velocity = lin
	b.angular_velocity = ang
	b.reset_physics_interpolation()
	DamageRouter.register_rid(b.get_rid(), self, s + 1)
	_registered[s] = 1
	_activate(s, lin)
	prof_spawn_usec += Time.get_ticks_usec() - t0


func register_cluster(c: DebrisCluster, lin: Vector3, ang: Vector3, cause: int) -> int:
	var s := _alloc_slot()
	var b := c.body
	_body[s] = b
	_kind[s] = Kind.CLUSTER
	_tier[s] = T1
	_mass[s] = c.mass
	_mesh[s] = null
	_shape[s] = null
	_cluster[s] = c
	_owner_b[s] = c.building
	_cause[s] = cause
	c.slot = s
	c.cause = cause
	b.physics_material_override = _phys_mat
	b.collision_layer = Layers.DEBRIS
	b.collision_mask = MASK_CLUSTER
	b.contact_monitor = true
	b.max_contacts_reported = 8
	b.can_sleep = false   # re-enabled after CLUSTER_AWAKE_SECONDS, see _process
	add_child(b)
	b.linear_velocity = lin
	b.angular_velocity = ang
	b.reset_physics_interpolation()
	_spawn_xf[s] = b.global_transform
	DamageRouter.register_rid(b.get_rid(), self, s + 1)
	_registered[s] = 1
	_activate(s, lin)
	return s


## Slot of the active body that owns rid, or -1.
func slot_of_rid(rid: RID) -> int:
	return _slot_by_rid.get(rid, -1)


## Generation of a slot; it changes every time the slot is reused, so a stored (slot, gen) pair
## identifies one record even when pooled bodies and slots are recycled.
func slot_gen(s: int) -> int:
	return _gen[s] if s >= 0 and s < _gen.size() else -1


func is_live(s: int, gen: int) -> bool:
	return s >= 0 and s < _used.size() and _used[s] == 1 and _gen[s] == gen


func body_of(s: int) -> RigidBody3D:
	return _body[s] if s >= 0 and s < _body.size() and _used[s] == 1 else null


func cluster_of(s: int) -> DebrisCluster:
	return _cluster[s] if s >= 0 and s < _cluster.size() and _used[s] == 1 else null


func kind_of(s: int) -> int:
	return _kind[s]


func owner_element(s: int) -> Vector2i:
	return Vector2i(_owner_b[s], _owner_e[s])


## Reference velocity for impact detection (a scripted motion handed over to physics).
func set_prev_velocity(s: int, v: Vector3, w: Vector3 = Vector3.ZERO) -> void:
	_prev_v[s] = v
	_prev_w[s] = w


## Angular velocity of a cluster one tick before the current one (pre-impact motion).
func pre_impact_angular(s: int) -> Vector3:
	return _pre_w_tick[s]


func slot_mass(s: int) -> float:
	return _mass[s]


func set_slot_mass(s: int, m: float) -> void:
	debris_mass += m - _mass[s]
	_mass[s] = m


## Removes a record without turning it into rubble, because its mass moves into other records
## (an element body replaced by its fracture pieces, a cluster peeled into smaller bodies).
func release(s: int) -> void:
	if s < 0 or s >= _used.size() or _used[s] == 0:
		return
	_deactivate(s)


func _deactivate(s: int) -> void:
	var b := _body[s]
	_slot_by_rid.erase(b.get_rid())
	if _registered[s] == 1:
		DamageRouter.unregister_rid(b.get_rid())
		_registered[s] = 0
	var p := _active_pos[s]
	if p >= 0:
		var last := _active[_active.size() - 1]
		_active[p] = last
		_active_pos[last] = p
		_active.resize(_active.size() - 1)
		_active_pos[s] = -1
	var tp := _t1_pos[s]
	if tp >= 0:
		var last1 := _t1_active[_t1_active.size() - 1]
		_t1_active[tp] = last1
		_t1_pos[last1] = tp
		_t1_active.resize(_t1_active.size() - 1)
		_t1_pos[s] = -1
	debris_mass -= _mass[s]
	_used[s] = 0
	if _kind[s] == Kind.CLUSTER:
		_cluster[s] = null
		b.queue_free()
	else:
		var ap := _age_prev[s]
		var an := _age_next[s]
		if ap >= 0:
			_age_next[ap] = an
		else:
			_age_head = an
		if an >= 0:
			_age_prev[an] = ap
		else:
			_age_tail = ap
		_age_prev[s] = -1
		_age_next[s] = -1
		# Mesh and shape stay assigned (cached pattern resources): a disabled body is out of the space and
		# hidden, and clearing them is two server round trips per freeze.
		b.process_mode = Node.PROCESS_MODE_DISABLED
		b.visible = false
		_pool.append(b)
	_body[s] = null
	_mesh[s] = null
	_shape[s] = null
	_free_slots.append(s)


# --------------------------------------------------------------------------------------------------
# Impacts
# --------------------------------------------------------------------------------------------------



func _physics_process(_delta: float) -> void:
	if rewinding:
		return
	var t0 := Time.get_ticks_usec()
	_tick += 1
	var parity := _tick & 1
	# Over budget, light pieces are the first thing to go unheard: the floor rises with the square of
	# the overload (2 x over budget: pieces under 4 kJ land without an impact).
	var over := structures.overload if structures != null else 1.0
	var piece_floor := piece_impact_min_j * over * over
	var hits := PackedInt32Array()
	var dvs := PackedFloat32Array()
	var pvs := PackedVector3Array()
	var crush := PackedInt32Array()
	for s in _t1_active:
		# Loose pieces are checked every other tick (their velocity change then spans two ticks).
		if _kind[s] == Kind.PIECE and (s & 1) != parity:
			continue
		var b := _body[s]
		var v := b.linear_velocity
		var pv := _prev_v[s]
		_prev_v[s] = v
		if _kind[s] == Kind.CLUSTER:
			var pw := _prev_w[s]
			_prev_w[s] = b.angular_velocity
			_pre_w_tick[s] = pw
		_ticks[s] += 1
		if _ticks[s] <= IGNORE_IMPACT_TICKS:
			continue
		var dv := (v - pv).length()
		if dv >= (impact_dv + 1.0 if _kind[s] == Kind.PIECE else impact_dv):
			if _kind[s] == Kind.PIECE and 0.5 * _mass[s] * dv * dv < piece_floor:
				continue
			hits.append(s)
			dvs.append(dv)
			pvs.append(pv)
		elif (_tick + s) % CRUSH_EVERY == 0 and v.length_squared() < 1.0 and not b.sleeping \
				and (_kind[s] == Kind.CLUSTER or (_kind[s] == Kind.ELEMENT and _mass[s] > 1500.0)):
			crush.append(s)
	# Heavy bodies first; the rest of a burst of impacts waits for the next tick (velocity history kept).
	var order := range(hits.size())
	if hits.size() > MAX_IMPACTS_PER_TICK:
		order.sort_custom(func(p: int, q: int) -> bool: return _mass[hits[p]] > _mass[hits[q]])
	var handled := 0
	var impact_deadline := t0 + IMPACT_BUDGET_USEC
	while handled < mini(order.size(), MAX_IMPACTS_PER_TICK) and Time.get_ticks_usec() < impact_deadline:
		var k: int = order[handled]
		var s := hits[k]
		if _used[s] == 1:
			_handle_impact(s, dvs[k], pvs[k])
		handled += 1
	for n in range(handled, order.size()):
		var s := hits[order[n]]
		_prev_v[s] = pvs[order[n]]
	for s in crush:
		if _used[s] == 1 and (_cluster[s] == null or not _cluster[s].kinematic):
			_apply_crush(s)
	if not _freezing.is_empty():
		_process_freezing(Time.get_ticks_usec() + int(budget_ms * 400.0))
	physics_usec = Time.get_ticks_usec() - t0


func _apply_crush(s: int) -> void:
	var b := _body[s]
	var state := PhysicsServer3D.body_get_direct_state(b.get_rid())
	if state == null:
		return
	var targets: Array[Object] = []
	var rids: Array[RID] = []
	var points := PackedVector3Array()
	var energies := PackedFloat32Array()
	var n := state.get_contact_count()
	# Only a few contacts are reported, so each loaded one carries at least an equal weight share.
	var weight_share := _mass[s] * 9.81 / maxf(float(n), 1.0)
	for k in n:
		var imp := state.get_contact_impulse(k).length()
		if imp < CRUSH_MIN_IMPULSE:
			continue
		var rid := state.get_contact_collider(k)
		if _rb_by_rid.has(rid):
			continue   # resting on rubble is fine, rubble does not get crushed
		targets.append(state.get_contact_collider_object(k))
		rids.append(rid)
		points.append(state.get_contact_collider_position(k))
		energies.append(maxf(imp * 60.0, weight_share) * CRUSH_K * (float(CRUSH_EVERY) / 60.0))
	crush_checks += 1
	for k in targets.size():
		crush_hits += 1
		crush_energy += energies[k]
		var hit := DamageHit.point(points[k], Vector3.DOWN, energies[k], 0.0, DamageHit.Kind.CRUSH)
		hit.cause_id = _cause[s]
		DamageRouter.apply_hit(hit, targets[k], rids[k])
		if _used[s] == 0:
			return


func _handle_impact(s: int, dv: float, pv: Vector3) -> void:
	var b := _body[s]
	var state := PhysicsServer3D.body_get_direct_state(b.get_rid())
	if state == null:
		return
	impacts_total += 1
	var energy := 0.5 * _mass[s] * dv * dv * impact_energy_factor
	var cc := state.get_contact_count()
	var contact := b.global_position
	if cc > 0:
		var acc := Vector3.ZERO
		var share := energy / float(cc)
		var dir := pv.normalized()
		var targets: Array[Object] = []
		var rids: Array[RID] = []
		var points := PackedVector3Array()
		var counts := PackedInt32Array()
		# A loose piece is small next to what it lands on: its first contact stands for all of them
		# (clusters and whole elements span several bodies and are looked at contact by contact).
		if _kind[s] == Kind.PIECE:
			cc = 1
			share = energy
		for k in cc:
			var p := state.get_contact_collider_position(k)
			acc += p
			var rid := state.get_contact_collider(k)
			# Loose pieces and rubble do nothing with a hit that carries no impulse (see receive_damage):
			# they are the bulk of what debris lands on, and not worth a delivery each.
			var ts: int = _slot_by_rid.get(rid, -1)
			if (ts >= 0 and _kind[ts] == Kind.PIECE) or _rb_by_rid.has(rid):
				continue
			var u := rids.find(rid)
			if u < 0:
				rids.append(rid)
				targets.append(state.get_contact_collider_object(k))
				points.append(p)
				counts.append(1)
			else:
				points[u] += p
				counts[u] += 1
		contact = acc / float(cc)
		# One hit per body touched: the contact points on the same body share its part of the energy.
		for u in rids.size():
			var hit := DamageHit.point(points[u] / float(counts[u]), dir, share * counts[u], 0.0, DamageHit.Kind.BLUNT, null)
			hit.cause_id = _cause[s]
			DamageRouter.apply_hit(hit, targets[u], rids[u])
	if _used[s] == 0:
		return
	if energy >= IMPACT_SIGNAL_MIN_J:
		impact.emit(contact, energy, _mat[s])
	if structures == null:
		return
	match _kind[s]:
		Kind.CLUSTER:
			structures.on_cluster_impact(s, contact, energy, dv, pv, _pre_w_tick[s])
		Kind.ELEMENT:
			structures.on_element_impact(s, contact, energy, dv)
		_:
			if fx != null and energy > 30000.0:
				fx.impact_dust(contact, clampf(energy / 400000.0, 0.15, 1.0), _mat[s])


## A hit's impulse is meant for a body of a few square metres. Smaller bodies catch less of a blast
## (impulse ~ cross-section) and every push is capped, so light chunks do not leave at rifle speed.
static func scaled_impulse(impulse: float, mass: float, density: float) -> float:
	var area := pow(maxf(mass, 0.1) / maxf(density, 100.0), 2.0 / 3.0)
	return minf(impulse * clampf(area / 2.0, 0.02, 1.0), maxf(mass, 1.0) * MAX_PUSH_DV)


## DamageRouter entry for registered debris bodies and rubble.
func receive_damage(hit: DamageHit, user_id: int) -> void:
	if user_id & RUBBLE_FLAG:
		var idx := user_id & ~RUBBLE_FLAG
		if idx >= _rb_alive.size() or _rb_alive[idx] == 0 or hit.kind == DamageHit.Kind.CRUSH:
			return
		var m := maxf(_rb_mass[idx], 1.0)
		var imp := scaled_impulse(hit.impulse, m, MaterialDB.density(_rb_mat[idx]))
		# Only a hit that pushes wakes rubble: debris landing on a pile carries no impulse, and a piece woken
		# at rest would only sit there until the budget freezes it again.
		if imp > 0.0 and (imp / m > 0.8 or hit.energy / m > 40.0):
			var body := _wake_index(idx)
			var dir := hit.direction if hit.direction != Vector3.ZERO else (body.global_position - hit.position).normalized()
			if imp > 0.0:
				body.apply_impulse(dir * imp, hit.position - body.global_position)
		return
	var s := user_id - 1   # 0 means "found by ancestor lookup", which is never a registered body
	if s < 0 or s >= _used.size() or _used[s] == 0:
		return
	var b := _body[s]
	if hit.impulse > 0.0:
		var density := 2000.0 if _kind[s] == Kind.CLUSTER else MaterialDB.density(_mat[s])
		var imp := scaled_impulse(hit.impulse, _mass[s], density)
		var d := hit.direction if hit.direction != Vector3.ZERO else (b.global_position - hit.position).normalized()
		b.apply_impulse(d * imp, hit.position - b.global_position)
	if structures == null:
		return
	match _kind[s]:
		Kind.CLUSTER:
			structures.on_cluster_damage(s, hit)
		Kind.ELEMENT:
			structures.on_element_damage(s, hit)


# --------------------------------------------------------------------------------------------------
# Settling, budget, rubble
# --------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if rewinding:
		return
	var t0 := Time.get_ticks_usec()
	_time += delta
	var deadline := t0 + int(budget_ms * 1000.0)
	var n := _active.size()
	var steps := mini(n, 160)
	var settle := minf(rest_seconds, settle_seconds) if n > awake_budget * 9 / 10 else settle_seconds
	var lost := PackedInt32Array()
	for k in steps:
		if _scan >= _active.size():
			_scan = 0
		var s := _active[_scan]
		_scan += 1
		var b := _body[s]
		var dt := _time - _checked_t[s]
		_checked_t[s] = _time
		var lv := b.linear_velocity.length_squared()
		var is_cluster := _kind[s] == Kind.CLUSTER
		if not is_cluster and b.global_position.y < KILL_Y:
			lost.append(s)
			continue
		# Clusters only settle when Jolt puts them to sleep: a slowly starting topple must not freeze.
		if b.sleeping or (not is_cluster and lv < 0.04 and b.angular_velocity.length_squared() < 0.12):
			_still[s] += dt
		else:
			_still[s] = 0.0
		var age := _time - _spawn_t[s]
		if is_cluster and not b.can_sleep and age > CLUSTER_AWAKE_SECONDS:
			b.can_sleep = true
		var cluster_busy := is_cluster and _cluster[s] != null and (_cluster[s].breaking or _cluster[s].freezing or _cluster[s].kinematic)
		if not cluster_busy and (_still[s] >= settle or (age > max_active_seconds and lv < 4.0)):
			_freeze_queue.append((_gen[s] << 32) | s)
	# Whatever fell off the Table (or through ground that has no collision yet) is gone.
	for s in lost:
		if _used[s] == 1:
			lost_total += 1
			_deactivate(s)
	prof_scan_usec += Time.get_ticks_usec() - t0
	# Rubble that lost its support falls again; settled bodies become rubble; then the budget is
	# enforced (with bodies at rest first, see make_room).
	_process_support_checks(Time.get_ticks_usec() + int(budget_ms * 400.0))
	_drain_rest(1 << 30, deadline)
	var excess := _active.size() - awake_budget
	if excess > 0:
		excess -= _drain_rest(excess, 1 << 62)
	if excess > 0:
		_freeze_oldest(excess, maxi(deadline, Time.get_ticks_usec() + 300))
	if _pool.size() < pool_spare and _active.size() < awake_budget / 2 and Time.get_ticks_usec() < deadline:
		for k in 6:
			_pool.append(_new_pooled_body())
	frame_usec = Time.get_ticks_usec() - t0


func _process_freezing(deadline: int) -> void:
	while not _freezing.is_empty():
		var c := _freezing[0]
		if c.slot < 0 or _used[c.slot] == 0 or _cluster[c.slot] != c:
			_freezing.pop_front()
			continue
		var alive := c.alive_indices()
		var chunk := alive.slice(0, mini(alive.size(), 24))
		freeze_reason = 4
		_cluster_to_rubble(c, chunk)
		freeze_reason = 0
		c.peel(chunk)
		set_slot_mass(c.slot, c.mass)
		if c.alive == 0:
			debris_frozen.emit(c.body, RID())
			_deactivate(c.slot)
			_freezing.pop_front()
		if Time.get_ticks_usec() > deadline:
			return


## Freezes up to max_n bodies the scan found at rest (skipping ones that started moving again).
## Returns how many were frozen.
func _drain_rest(max_n: int, deadline: int) -> int:
	var done := 0
	while _fq_head < _freeze_queue.size() and done < max_n and Time.get_ticks_usec() <= deadline:
		var e := _freeze_queue[_fq_head]
		_fq_head += 1
		var s := int(e & 0xFFFFFFFF)
		if _used[s] == 0 or _gen[s] != int(e >> 32):
			continue
		var b := _body[s]
		if _kind[s] != Kind.CLUSTER:
			if not b.sleeping and b.linear_velocity.length_squared() > 0.25:
				_still[s] = 0.0   # knocked loose since the scan saw it; it is not rubble yet
				continue
			var below := _below(s)
			if below == BELOW_DYNAMIC:
				# Resting on a body that may still move: it becomes rubble after that one has. When that one is
				# at rest too and lies on static things, it goes first and this one follows straight away.
				var s2 := _below_slot
				if s2 >= 0 and _used[s2] == 1 and _kind[s2] != Kind.CLUSTER and (_body[s2].sleeping or _still[s2] > 0.0) \
						and _body[s2].linear_velocity.length_squared() < 0.04:
					var below2 := _below(s2)
					if below2 != BELOW_DYNAMIC:
						_freeze_piece(s2, below2)
						done += 1
						below = _below(s)
				if below == BELOW_DYNAMIC:
					# The negative still time spaces out the retries.
					_still[s] = -2.0 * rest_seconds
					continue
			_freeze_piece(s, below)
		else:
			if _touches_dynamic(s):
				_still[s] = -2.0 * rest_seconds
				continue
			freeze(s)
		done += 1
	if _fq_head >= _freeze_queue.size():
		_freeze_queue.clear()
		_fq_head = 0
	elif _fq_head > 4096:
		_freeze_queue = _freeze_queue.slice(_fq_head)
		_fq_head = 0
	return done


## Over budget: among the oldest bodies, freeze resting ones first, then the slowest and farthest.
## A body still in flight is dropped to its landing spot by freeze(), never left hanging in the air.
func _freeze_oldest(count: int, deadline: int = 1 << 62) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var eye := cam.global_position if cam != null else Vector3.ZERO
	var cand: Array[Vector2] = []   # (score, slot)
	var want := clampi(count * 3, 24, 256)
	var s := _age_head
	while s >= 0 and cand.size() < want:
		var b := _body[s]
		var speed := b.linear_velocity.length()
		var far := b.global_position.distance_to(eye) * 0.05
		var resting := b.sleeping or (_still[s] > 0.0 and speed < 0.5)
		cand.append(Vector2((-1000.0 if resting else speed) - far, s))
		s = _age_next[s]
	cand.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
	var done := 0
	for c in cand:
		if done >= count or Time.get_ticks_usec() > deadline:
			break
		var cs := int(c.y)
		if _used[cs] == 0:
			continue
		if _body[cs].linear_velocity.length_squared() > 1.0:
			forced_fast_freezes += 1
		freeze_reason = 1
		freeze(cs)
		freeze_reason = 0
		forced_freezes += 1
		done += 1


## Call after something static in this box went away (an intact element, a rubble piece, dug ground).
## Jolt does not wake sleeping bodies when the static body under them is removed, so sleeping debris
## here is woken, and rubble here whose centre is above min_y (default: the box centre; what lies lower
## did not rest on it) is queued for a support check: unsupported rubble falls again.
func wake_box(xf: Transform3D, size: Vector3, min_y: float = NAN, max_results: int = 128) -> void:
	_wake_shape.size = size + Vector3(0.12, 0.12, 0.12)
	_wake_query.shape = _wake_shape
	_wake_query.transform = xf
	_wake_query.collision_mask = Layers.DEBRIS | Layers.DEBRIS_SMALL | Layers.RUBBLE
	var floor_y := xf.origin.y if is_nan(min_y) else min_y
	for r in get_world_3d().direct_space_state.intersect_shape(_wake_query, max_results):
		var idx: int = _rb_by_rid.get(r["rid"], -1)
		if idx >= 0:
			if _rb_check[idx] == 0 and (_rb_xf[idx] * _rb_com[idx]).y > floor_y:
				_rb_check[idx] = 1
				_check_queue.append(idx)
			continue
		var body := r["collider"] as RigidBody3D
		if body != null and body.sleeping:
			body.sleeping = false
			unsupported_wakes += 1


## True when a short ray down from the piece's centre of mass, reaching a few centimetres below its
## lowest point, meets static ground, an intact element or rubble that is not itself waiting for a check.
## The ray ignores pieces it starts inside.
func _rubble_supported(idx: int, space: PhysicsDirectSpaceState3D, depth: int) -> bool:
	var xf := _rb_xf[idx]
	var p := xf * _rb_com[idx]
	var low := (xf * _rb_mesh[idx].get_aabb()).position.y
	var hit := _cast_down(space, _support_ray, p, Vector3(p.x, low - SUPPORT_PROBE, p.z), _rb_rid[idx], depth)
	if hit.is_empty():
		return false
	if hit["rid"] != _rb_on[idx]:
		_record_support(idx, hit["rid"])
	return true


## First hit of a downward ray that can carry something. Rubble that is itself queued for a support check
## is checked first (it may have to move); rubble whose check is in progress further up this chain is
## passed through, so pieces that lost their support together never hold each other up in mid-air.
func _cast_down(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, from: Vector3, to: Vector3, self_rid: RID, depth: int = 0) -> Dictionary:
	var exclude: Array[RID] = [self_rid]
	for attempt in 4:
		ray.from = from
		ray.to = to
		ray.exclude = exclude
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return hit
		var j: int = _rb_by_rid.get(hit["rid"], -1)
		if j < 0 or (_rb_check[j] == CHECK_NONE and not _rests_on(j, self_rid)):
			return hit
		if _rb_check[j] == CHECK_QUEUED and depth < 4:
			_check_rubble(j, space, depth + 1)
			continue   # cast again: it is settled now, or gone from under the ray
		exclude.append(hit["rid"])
	return {}


## True when rubble j is carried, through its recorded chain of supports, by the body rid (so j cannot
## carry rid: that would be a loop of pieces holding each other up in the air).
func _rests_on(j: int, rid: RID) -> bool:
	var on := _rb_on[j]
	# Chains through a pile can be long; a loop missed here leaves pieces holding each other up in the air.
	for step in 256:
		if not on.is_valid():
			return false
		if on == rid:
			return true
		var k: int = _rb_by_rid.get(on, -1)
		if k < 0:
			return false   # an intact element or the ground
		on = _rb_on[k]
	return false


## Support check of one queued rubble piece: it stays, is set down lower as rubble, or wakes up.
## With the debris budget full, a woken piece would only force another falling body into an early drop,
## so the piece is moved straight down as rubble instead (the same picture for a tenth of the cost).
## Small pieces are checked with the drop cast itself (their lowest corners), large ones with a ray from
## the centre of mass first (a slab resting on one corner of a pile must not count as supported).
func _check_rubble(idx: int, space: PhysicsDirectSpaceState3D, depth: int) -> void:
	_rb_check[idx] = CHECK_ACTIVE
	support_checks += 1
	_rb_checked[idx] = _time
	var tight := _active.size() >= awake_budget * 9 / 10
	if _rb_mass[idx] < 40.0:
		var drop := _drop_distance(_rb_shape[idx], _rb_xf[idx], _rb_com[idx], _rb_rid[idx], 1, depth)
		if drop != INF and drop <= SUPPORT_PROBE:
			if _support_rid != _rb_on[idx]:
				_record_support(idx, _support_rid)
			_rb_check[idx] = CHECK_NONE
			return
		rubble_support_wakes += 1
		if tight and drop != INF:
			_move_rubble_down(idx, drop, _support_rid)
			_rb_check[idx] = CHECK_NONE
			return
		_rb_check[idx] = CHECK_NONE
		if drop != INF:
			_wake_index(idx)
		return
	if _rubble_supported(idx, space, depth):
		_rb_check[idx] = CHECK_NONE
		return
	rubble_support_wakes += 1
	var dropped := tight and _drop_rubble(idx)
	_rb_check[idx] = CHECK_NONE
	if not dropped:
		_wake_index(idx)


func pending_support_checks() -> int:
	return _check_queue.size() - _check_head


## Remembers that rubble idx rests on the static body on (an intact element or another rubble piece;
## the ground never goes away and is not tracked).
func _record_support(idx: int, on: RID) -> void:
	_rb_on[idx] = RID()
	if not on.is_valid() or not (_rb_by_rid.has(on) or (structures != null and structures._static_by_rid.has(on))):
		return
	_rb_on[idx] = on
	var lst: PackedInt32Array = _resting_on.get(on, PackedInt32Array())
	lst.append(idx)
	_resting_on[on] = lst


## Call when a static body that rubble may rest on is removed (StructureManager does this for every
## intact element it takes out). The pieces recorded on it are checked and fall if nothing else holds
## them, however many there are and wherever they lie.
func support_removed(rid: RID) -> void:
	var lst: PackedInt32Array = _resting_on.get(rid, PackedInt32Array())
	if lst.is_empty():
		return
	_resting_on.erase(rid)
	for idx in lst:
		if _rb_alive[idx] == 1 and _rb_on[idx] == rid:
			_rb_on[idx] = RID()
			if _rb_check[idx] == 0:
				_rb_check[idx] = 1
				_check_queue.append(idx)


## Wakes queued rubble that rests on nothing any more. A woken piece queues its own neighbours, so a
## stack falls from the bottom up over a few frames. A long queue (a whole building came loose) gets a
## bigger slice: rubble left hanging in the air is the worst outcome.
func _process_support_checks(deadline: int) -> void:
	if _check_head >= _check_queue.size():
		return
	var space := get_world_3d().direct_space_state
	var n := 0
	var backlog := _check_queue.size() - _check_head
	var cap := support_checks_per_frame if backlog < 256 else support_checks_per_frame * 4
	if backlog >= 256:
		deadline += int(budget_ms * 1000.0)
	while _check_head < _check_queue.size() and n < cap and (n < 8 or Time.get_ticks_usec() <= deadline):
		var idx := _check_queue[_check_head]
		_check_head += 1
		if _rb_alive[idx] == 0 or _rb_check[idx] != CHECK_QUEUED:
			continue   # gone, or already checked out of order (see _cast_down)
		n += 1
		var t0 := Time.get_ticks_usec()
		_check_rubble(idx, space, 0)
		prof_support_usec += Time.get_ticks_usec() - t0
	if _check_head >= _check_queue.size():
		_check_queue.clear()
		_check_head = 0


## Moves a body that has to be frozen while still moving straight down to where it would land, so the
## rubble it becomes rests on something instead of hanging in the air. Rays go down from the lowest
## corners of its collision shape; it stops where the first corner meets a static surface (a shape cast
## through a debris field costs ~0.15 ms, the rays ~0.02 ms). Returns false when nothing is below it.
func _drop_to_rest(s: int) -> bool:
	var b := _body[s]
	var xf := b.global_transform
	var drop := _drop_distance(_shape[s], xf, _com[s], b.get_rid(), 1 if _mass[s] < 40.0 else 2)
	if drop == INF:
		return false
	if drop > 0.01:
		b.global_transform = xf.translated(Vector3(0.0, -drop, 0.0))
		dropped_freezes += 1
	return true


## How far a piece (shape, transform, local centre of mass) can be lowered straight down before it rests on
## a static surface (INF when nothing is below); sets _support_rid to what it lands on. It stops where one of
## its lowest corners meets a surface, provided the surface under its centre of mass is reached by then as
## well. A corner that only grazes the edge or side of a neighbour holds nothing (the piece would slide off;
## as rubble it would hang over the gap), so in that case it goes on down to the surface under its centre
## of mass and may cut into what its corners meet on the way, which reads far better than a gap.
func _drop_distance(shape: Shape3D, xf: Transform3D, com: Vector3, self_rid: RID, corners: int = 2, depth: int = 0) -> float:
	var space := get_world_3d().direct_space_state
	var low_pts := _lowest_corners(shape, xf, maxi(corners, 1))
	if low_pts.is_empty():
		return INF
	var low_y := low_pts[0].y
	var c := xf * com
	var d_com := INF
	var on_com := RID()   # locals: _cast_down may run other pieces' checks, which use _support_rid
	var under := _cast_down(space, _drop_ray, c, Vector3(c.x, minf(low_y - 1.0, -64.0), c.z), self_rid, depth)
	if not under.is_empty():
		d_com = low_y - (under["position"] as Vector3).y
		on_com = under["rid"]
	var d_first := INF
	var on_first := RID()
	for p in low_pts:
		var hit := _cast_down(space, _drop_ray, p + Vector3(0.0, 0.05, 0.0), Vector3(p.x, minf(p.y - 1.0, -64.0), p.z), self_rid, depth)
		if not hit.is_empty():
			var d := p.y - (hit["position"] as Vector3).y
			if d < d_first:
				d_first = d
				on_first = hit["rid"]
	if d_com != INF and (d_first == INF or d_com - d_first > SUPPORT_PROBE):
		_support_rid = on_com
		return d_com
	_support_rid = on_first
	return d_first


## Moves an unsupported rubble piece straight down onto the static surface under it. Returns false when
## nothing is below it.
func _drop_rubble(idx: int) -> bool:
	var drop := _drop_distance(_rb_shape[idx], _rb_xf[idx], _rb_com[idx], _rb_rid[idx], 1 if _rb_mass[idx] < 40.0 else 2)
	if drop == INF:
		return false
	_move_rubble_down(idx, drop, _support_rid)
	return true


## Lowers a rubble piece by drop metres onto the body on (static body, intact element or rubble).
func _move_rubble_down(idx: int, drop: float, on: RID) -> void:
	var rid := _rb_rid[idx]
	if drop > 0.01:
		var xf := _rb_xf[idx]
		var nxf := xf.translated(Vector3(0.0, -drop, 0.0))
		support_removed(rid)   # what lay on this piece must follow it down
		if _rb_mass[idx] >= 40.0:   # sleeping bodies on it, rubble whose support was never recorded
			var box := _rb_mesh[idx].get_aabb()
			wake_box(Transform3D(xf.basis, xf * box.get_center()), box.size, NAN, 16)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, nxf)
		_rb_xf[idx] = nxf
		_rb_groups[_rb_group[idx]].set_transform(_rb_inst[idx], nxf)
		rubble_moved.emit(rid, nxf)
		rubble_drops += 1
	_record_support(idx, on)
	_support_rid = RID()


## World positions of the n lowest corners of a convex or box shape. Only the world height of each point
## is computed in the selection pass (one dot product); just the n winners are transformed.
static func _lowest_corners(shape: Shape3D, xf: Transform3D, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var convex := shape as ConvexPolygonShape3D
	if convex != null:
		pts = convex.points
	else:
		var box := shape as BoxShape3D
		if box == null:
			return pts
		var h := box.size * 0.5
		for k in 8:
			pts.append(Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	var row := Vector3(xf.basis.x.y, xf.basis.y.y, xf.basis.z.y)
	var best := PackedInt32Array()
	var best_y := PackedFloat32Array()
	for i in pts.size():
		var y := row.dot(pts[i])
		var at := best.size()
		while at > 0 and best_y[at - 1] > y:
			at -= 1
		if at < n:
			best.insert(at, i)
			best_y.insert(at, y)
			if best.size() > n:
				best.resize(n)
				best_y.resize(n)
	var out := PackedVector3Array()
	for i in best:
		out.append(xf * pts[i])
	return out


## What a resting body lies on: one short ray from its centre of mass, since the support has to be under
## it (a body lying on the edge of something static next to a gap is not held there, and as rubble it would
## hang). Large bodies also report contacts: one with another debris body means it may still move away, and
## static contacts on both sides of the centre of mass are a span across a gap, which does hold.
func _below(s: int) -> int:
	var t0 := Time.get_ticks_usec()
	var b := _body[s]
	var mesh := _mesh[s]
	_below_slot = -1
	if mesh == null:
		return BELOW_STATIC
	var xf := b.global_transform
	var c := xf * _com[s]
	var spans := false       # static contacts on both sides of the centre of mass
	var span_on := RID()     # a tracked one among them, recorded as the support
	if _tier[s] == T1:
		var state := PhysicsServer3D.body_get_direct_state(b.get_rid())
		if state != null:
			var held := PackedVector3Array()
			for k in state.get_contact_count():
				var d := state.get_contact_collider_position(k) - c
				if d.y > -0.05:
					continue   # beside or on top of it: does not carry it
				var rid := state.get_contact_collider(k)
				if _slot_by_rid.has(rid):
					_below_slot = _slot_by_rid[rid]
					return BELOW_DYNAMIC
				# Contacts may be stale (an element removed since the last step): only known statics count.
				var tracked := _rb_by_rid.has(rid) or (structures != null and structures._static_by_rid.has(rid))
				if tracked or state.get_contact_collider_object(k) is StaticBody3D:
					held.append(Vector3(d.x, 0.0, d.z))
					if tracked and not span_on.is_valid():
						span_on = rid
			for i in held.size():
				for j in range(i + 1, held.size()):
					if held[i].dot(held[j]) < 0.0:
						spans = true
	_below_ray.from = c
	_below_ray.to = Vector3(c.x, (xf * mesh.get_aabb()).position.y - 0.12, c.z)
	_below_ray.exclude = [b.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_below_ray)
	prof_below_usec += Time.get_ticks_usec() - t0
	if hit.is_empty():
		if spans:
			_support_rid = span_on
			return BELOW_STATIC
		return BELOW_NOTHING
	if _slot_by_rid.has(hit["rid"]):
		_below_slot = _slot_by_rid[hit["rid"]]
		return BELOW_DYNAMIC
	_support_rid = hit["rid"]
	return BELOW_STATIC


## True when a cluster body has a reported contact with another debris body below its centre of mass (it
## may lie on it). Bodies lying on top of it do not count: they wait for it, not the other way round.
func _touches_dynamic(s: int) -> bool:
	var b := _body[s]
	var state := PhysicsServer3D.body_get_direct_state(b.get_rid())
	if state == null:
		return false
	var c_y := (b.global_transform * b.center_of_mass).y
	for k in state.get_contact_count():
		if _slot_by_rid.has(state.get_contact_collider(k)) and state.get_contact_collider_position(k).y < c_y - 0.05:
			return true
	return false


## The static body (element or rubble) under the centre of a piece about to become rubble, or RID().
func _support_under(xf: Transform3D, mesh: Mesh, com: Vector3) -> RID:
	var p := xf * com
	var low := (xf * mesh.get_aabb()).position.y
	var hit := _cast_down(get_world_3d().direct_space_state, _support_ray, p, Vector3(p.x, low - SUPPORT_PROBE, p.z), RID())
	return hit["rid"] if not hit.is_empty() else RID()


## Turns a record into permanent static rubble. Rubble only ever rests on static things: a body still
## moving, or lying on another body, is first dropped to the static surface under it.
func freeze(s: int) -> void:
	if _used[s] == 0:
		return
	if _kind[s] != Kind.CLUSTER:
		var b := _body[s]
		var moving := not b.sleeping and b.linear_velocity.length_squared() > 0.25
		_freeze_piece(s, BELOW_NOTHING if moving else _below(s), moving)
		return
	var t0 := Time.get_ticks_usec()
	var b := _body[s]
	var c := _cluster[s]
	if c.alive > 48:
		if not c.freezing:
			c.freezing = true
			b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			b.freeze = true
			_freezing.append(c)
		return
	frozen_total += 1
	var keep := freeze_reason
	freeze_reason = 4
	_cluster_to_rubble(c, c.alive_indices())
	freeze_reason = keep
	debris_frozen.emit(b, RID())
	_deactivate(s)
	prof_freeze_usec += Time.get_ticks_usec() - t0


func _freeze_piece(s: int, below: int, moving: bool = false) -> void:
	var t0 := Time.get_ticks_usec()
	var b := _body[s]
	frozen_total += 1
	prof_freezes += 1
	var keep_reason := freeze_reason
	if below != BELOW_STATIC:
		_support_rid = RID()
		var old := b.global_transform
		freeze_reason = 2 if _drop_to_rest(s) else 3
		# Something resting on a body that is dropped from under it must not stay asleep in the air.
		if not moving and b.global_transform.origin.y < old.origin.y - 0.05:
			var box := _mesh[s].get_aabb()
			wake_box(Transform3D(old.basis, old * box.get_center()), box.size)
		prof_drop_usec += Time.get_ticks_usec() - t0
	var t1 := Time.get_ticks_usec()
	var rid := _add_rubble(_mesh[s], _shape[s], b.global_transform, _mass[s], _com[s], _mat[s], _owner_b[s], _owner_e[s], _tier[s] == T2, _support_rid, _born[s], _spawn_xf[s])
	var t2 := Time.get_ticks_usec()
	prof_add_usec += t2 - t1
	_support_rid = RID()
	freeze_reason = keep_reason
	debris_frozen.emit(b, rid)
	_deactivate(s)
	prof_deact_usec += Time.get_ticks_usec() - t2
	prof_freeze_usec += Time.get_ticks_usec() - t0


## Elements of a resting cluster become rubble where they are, lowest first, each recording what it
## rests on (the ground, an intact element, or an element of the same cluster already converted).
func _cluster_to_rubble(c: DebrisCluster, indices: PackedInt32Array) -> void:
	var order := Array(indices)
	var t := c.body.global_transform
	order.sort_custom(func(a: int, b: int) -> bool: return (t * c.locals[a]).origin.y < (t * c.locals[b]).origin.y)
	# An element with nothing under its own centre was held by the rest of the block: it is recorded on what
	# the lowest elements rest on, so it is checked again when that goes away.
	var base := RID()
	for i: int in order:
		var xf := t * c.locals[i]
		var on := _support_under(xf, c.meshes[i], c.elem_com[i])
		if not on.is_valid():
			on = base
		elif not base.is_valid():
			base = on
		var born := -1.0
		var born_xf := xf
		if c.slot >= 0 and c.slot < _used.size() and _used[c.slot] == 1 and _cluster[c.slot] == c:
			born = _born[c.slot]
			born_xf = _spawn_xf[c.slot] * c.locals[i]
		_add_rubble(c.meshes[i], c.shapes[i], xf, c.masses[i], c.elem_com[i], _cluster_mat(c, i), c.building, c.elems[i], false, on, born, born_xf)


func _cluster_mat(c: DebrisCluster, i: int) -> StringName:
	if structures != null:
		return structures.buildings[c.building].data.material_name(c.elems[i])
	return &"concrete"


## on: the static body (element or rubble) the piece rests on, when a ray found it; when that body goes
## away the piece is checked (see support_removed).
func _add_rubble(mesh: Mesh, shape: Shape3D, xf: Transform3D, mass: float, com: Vector3, material: StringName, ob: int, oe: int,
		small: bool = false, on: RID = RID(), born: float = -1.0, born_xf: Transform3D = Transform3D.IDENTITY) -> RID:
	var idx: int
	if not _rb_free.is_empty():
		idx = _rb_free[_rb_free.size() - 1]
		_rb_free.resize(_rb_free.size() - 1)
	else:
		idx = _rb_rid.size()
		_rb_rid.append(RID())
		_rb_xf.append(Transform3D.IDENTITY)
		_rb_mesh.append(null)
		_rb_shape.append(null)
		_rb_mass.append(0.0)
		_rb_com.append(Vector3.ZERO)
		_rb_mat.append(&"")
		_rb_owner_b.append(-1)
		_rb_owner_e.append(-1)
		_rb_group.append(-1)
		_rb_inst.append(-1)
		_rb_alive.append(0)
		_rb_check.append(0)
		_rb_on.append(RID())
		_rb_reason.append(0)
		_rb_time.append(0.0)
		_rb_checked.append(-1.0)
		_rb_born.append(0.0)
		_rb_born_xf.append(Transform3D.IDENTITY)
	_rb_born[idx] = born if born >= 0.0 else _time
	_rb_born_xf[idx] = born_xf if born >= 0.0 else xf
	_rb_reason[idx] = freeze_reason
	_rb_time[idx] = _time
	_rb_checked[idx] = -1.0
	_rb_check[idx] = CHECK_NONE   # a stale queue entry of the previous piece with this id is skipped
	_record_support(idx, on)
	var rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(rid, shape.get_rid())
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_collision_layer(rid, LAYER_RUBBLE_SMALL if small else LAYER_RUBBLE_LARGE)
	PhysicsServer3D.body_set_collision_mask(rid, 0)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
	PhysicsServer3D.body_set_space(rid, get_world_3d().space)
	DamageRouter.register_rid(rid, self, RUBBLE_FLAG | idx)
	var key := mesh.get_rid()
	var gi: int = _rb_group_by_mesh.get(key, -1)
	if gi < 0:
		gi = _rb_groups.size()
		_rb_groups.append(InstanceGroup.new(self, mesh, 16, false, not MaterialDB.is_glass(material), false))
		_rb_group_by_mesh[key] = gi
	_rb_rid[idx] = rid
	_rb_xf[idx] = xf
	_rb_mesh[idx] = mesh
	_rb_shape[idx] = shape
	_rb_mass[idx] = mass
	_rb_com[idx] = com
	_rb_mat[idx] = material
	_rb_owner_b[idx] = ob
	_rb_owner_e[idx] = oe
	_rb_group[idx] = gi
	_rb_inst[idx] = _rb_groups[gi].add(idx, xf)
	_rb_alive[idx] = 1
	_rb_by_rid[rid] = idx
	rubble_count += 1
	rubble_mass += mass
	return rid


## Creates a static rubble piece directly (ob/oe: owning building and element for whole elements, -1
## for fracture cells). Used for material that is ground in without a dynamic phase. settle: lower it
## straight down onto what is under it first (a piece that is partly in the ground stays put).
func add_rubble(mesh: Mesh, shape: Shape3D, xf: Transform3D, mass: float, com: Vector3, material: StringName, ob: int, oe: int,
		small: bool, settle: bool = false) -> RID:
	freeze_reason = 5
	var on := RID()
	if settle:
		var drop := _drop_distance(shape, xf, com, RID(), 1 if mass < 40.0 else 2)
		on = _support_rid
		if drop != INF and drop > 0.01:
			xf = xf.translated(Vector3(0.0, -drop, 0.0))
	var rid := _add_rubble(mesh, shape, xf, mass, com, material, ob, oe, small, on)
	_support_rid = RID()
	freeze_reason = 0
	return rid


func is_rubble(rid: RID) -> bool:
	return _rb_by_rid.has(rid)


## Converts a rubble piece back into a dynamic body (for grabbing / throwing). Returns null if rid is
## not rubble.
func wake_rubble(rid: RID) -> RigidBody3D:
	var idx: int = _rb_by_rid.get(rid, -1)
	if idx < 0:
		return null
	return _wake_index(idx)


func _wake_index(idx: int) -> RigidBody3D:
	var rid := _rb_rid[idx]
	DamageRouter.unregister_rid(rid)
	PhysicsServer3D.free_rid(rid)
	_rb_by_rid.erase(rid)
	_rb_on[idx] = RID()
	support_removed(rid)
	var box := _rb_mesh[idx].get_aabb()
	wake_box(Transform3D(_rb_xf[idx].basis, _rb_xf[idx] * box.get_center()), box.size, NAN, 32)
	var g := _rb_groups[_rb_group[idx]]
	var moved := g.remove(_rb_inst[idx])
	if moved >= 0:
		_rb_inst[moved] = _rb_inst[idx]
	_rb_alive[idx] = 0
	_rb_free.append(idx)
	rubble_count -= 1
	rubble_mass -= _rb_mass[idx]
	var s: int
	if _rb_owner_b[idx] >= 0:
		s = spawn_element(_rb_owner_b[idx], _rb_owner_e[idx], _rb_mesh[idx], _rb_shape[idx], _rb_xf[idx], _rb_com[idx], _rb_mass[idx], Vector3.ZERO, Vector3.ZERO, _rb_mat[idx], 0)
	else:
		var tier := T1 if _rb_mass[idx] >= 40.0 else T2
		s = spawn_piece(_rb_mesh[idx], _rb_shape[idx], _rb_xf[idx], _rb_com[idx], _rb_mass[idx], Vector3.ZERO, Vector3.ZERO, tier, _rb_mat[idx], 0)
	_rb_rid[idx] = RID()
	# A woken piece keeps the birth it had as debris (a rewind takes it back there, not here).
	_born[s] = _rb_born[idx]
	_spawn_xf[s] = _rb_born_xf[idx]
	rubble_woken.emit(rid, _body[s])
	return _body[s]


# --------------------------------------------------------------------------------------------------
# World rewind (Timeline)
# --------------------------------------------------------------------------------------------------

func rewind_begin() -> void:
	rewinding = true
	_rw_now = _time
	_rw_from.clear()


## Debris born in the last REWIND_FLY seconds after the cursor flies back to its birth; debris born more
## than REWIND_LAG after the cursor is gone. Returns how many records were removed.
func rewind_to(depth: float) -> int:
	var cut := _rw_now - depth
	var removed := 0
	var i := _active.size() - 1
	while i >= 0:
		if i >= _active.size():
			i = _active.size() - 1
			continue
		var s := _active[i]
		i -= 1
		var born := _born[s]
		if cut >= born + REWIND_FLY:
			continue
		if cut < born - REWIND_LAG:
			_rw_from.erase(s)
			release(s)
			removed += 1
			continue
		var body := _body[s]
		if not _rw_from.has(s):
			_rw_from[s] = body.global_transform
		var u := smoothstep(0.0, 1.0, clampf((born + REWIND_FLY - cut) / REWIND_FLY, 0.0, 1.0))
		body.global_transform = (_rw_from[s] as Transform3D).interpolate_with(_spawn_xf[s], u)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 0:
			continue
		var born := _rb_born[idx]
		if cut >= born + REWIND_FLY:
			continue
		var key := -1 - idx
		if cut < born - REWIND_LAG:
			_rw_from.erase(key)
			_remove_rubble(idx)
			removed += 1
			continue
		if not _rw_from.has(key):
			_rw_from[key] = _rb_xf[idx]
		var u := smoothstep(0.0, 1.0, clampf((born + REWIND_FLY - cut) / REWIND_FLY, 0.0, 1.0))
		var xf := (_rw_from[key] as Transform3D).interpolate_with(_rb_born_xf[idx], u)
		_rb_xf[idx] = xf
		PhysicsServer3D.body_set_state(_rb_rid[idx], PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		_rb_groups[_rb_group[idx]].set_transform(_rb_inst[idx], xf)
	return removed


## The rewind stops `depth` seconds back: everything born after that moment goes (also what was still
## in flight), the clock goes back with it and the logic runs again.
func rewind_end(depth: float) -> void:
	var cut := _rw_now - depth
	var i := _active.size() - 1
	while i >= 0:
		if i >= _active.size():
			i = _active.size() - 1
			continue
		var s := _active[i]
		i -= 1
		if _born[s] > cut:
			release(s)
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1 and _rb_born[idx] > cut:
			_remove_rubble(idx)
	_rw_from.clear()
	_freeze_queue.clear()
	_fq_head = 0
	_time = cut
	rewinding = false


## A rubble piece leaves the world without a trace (world rewind).
func _remove_rubble(idx: int) -> void:
	var rid := _rb_rid[idx]
	DamageRouter.unregister_rid(rid)
	PhysicsServer3D.free_rid(rid)
	_rb_by_rid.erase(rid)
	_rb_on[idx] = RID()
	support_removed(rid)
	var g := _rb_groups[_rb_group[idx]]
	var moved := g.remove(_rb_inst[idx])
	if moved >= 0:
		_rb_inst[moved] = _rb_inst[idx]
	_rb_alive[idx] = 0
	_rb_free.append(idx)
	rubble_count -= 1
	rubble_mass -= _rb_mass[idx]
	_rb_rid[idx] = RID()


## Rubble pieces within `radius` (flat distance) of a point and at most `max_up` above it, nearest first,
## at most `max_n` of them (indices for rubble_position / take_rubble). The Owner's vacuum robots use it.
func rubble_near(at: Vector3, radius: float, max_up: float = 3.0, max_n: int = 64) -> PackedInt32Array:
	var found: Array = []
	var r2 := radius * radius
	for idx in _rb_alive.size():
		if _rb_alive[idx] != 1:
			continue
		var p := _rb_xf[idx].origin
		var d2 := Vector2(p.x - at.x, p.z - at.z).length_squared()
		if d2 <= r2 and p.y - at.y <= max_up:
			found.append([d2, idx])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := PackedInt32Array()
	for i in mini(found.size(), max_n):
		out.append(int(found[i][1]))
	return out


func rubble_alive(idx: int) -> bool:
	return idx >= 0 and idx < _rb_alive.size() and _rb_alive[idx] == 1


func rubble_position(idx: int) -> Vector3:
	return _rb_xf[idx].origin if rubble_alive(idx) else Vector3.INF


## Takes a rubble piece out of the world (into a vacuum robot). Returns its mass, 0 when it was gone.
func take_rubble(idx: int) -> float:
	if not rubble_alive(idx):
		return 0.0
	var m := _rb_mass[idx]
	_remove_rubble(idx)
	return m


func rubble_rids() -> Array[RID]:
	var out: Array[RID] = []
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1:
			out.append(_rb_rid[idx])
	return out


func rubble_batch_count() -> int:
	return _rb_groups.size()


## Highest centre of mass of any active debris body (tests: "has the building come down").
func max_debris_height() -> float:
	var h := -INF
	for s in _active:
		var b := _body[s]
		h = maxf(h, (b.global_transform * b.center_of_mass).y)
	return h


## Highest centre of mass of any rubble piece.
func max_rubble_height() -> float:
	var h := -INF
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1:
			h = maxf(h, (_rb_xf[idx] * _rb_com[idx]).y)
	return h


## Height below which the fraction p of all debris and rubble mass lies (centres of mass).
func mass_height_percentile(p: float) -> float:
	var items: Array[Vector2] = []
	var total := 0.0
	for s in _active:
		var b := _body[s]
		items.append(Vector2((b.global_transform * b.center_of_mass).y, _mass[s]))
		total += _mass[s]
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1:
			items.append(Vector2((_rb_xf[idx] * _rb_com[idx]).y, _rb_mass[idx]))
			total += _rb_mass[idx]
	items.sort_custom(func(a: Vector2, b2: Vector2) -> bool: return a.x < b2.x)
	var acc := 0.0
	for it in items:
		acc += it.y
		if acc >= total * p:
			return it.x
	return items[items.size() - 1].x if not items.is_empty() else 0.0


## Mass-weighted centre of all debris and rubble.
func mass_centroid() -> Vector3:
	var acc := Vector3.ZERO
	var m := 0.0
	for s in _active:
		var b := _body[s]
		acc += (b.global_transform * b.center_of_mass) * _mass[s]
		m += _mass[s]
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1:
			acc += (_rb_xf[idx] * _rb_com[idx]) * _rb_mass[idx]
			m += _rb_mass[idx]
	return acc / maxf(m, 0.001)


## Pieces above a height (diagnostics): [kind/source, position, mass].
func pieces_above(height: float) -> Array:
	var out: Array = []
	for s in _active:
		var p := _body[s].global_transform * _body[s].center_of_mass
		if p.y > height:
			out.append(["active kind %d owner %s sleeping %s v %s" % [_kind[s], owner_element(s), _body[s].sleeping, _body[s].linear_velocity], p, _mass[s]])
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1:
			var p := _rb_xf[idx] * _rb_com[idx]
			if p.y > height:
				out.append(["rubble owner %d/%d" % [_rb_owner_b[idx], _rb_owner_e[idx]], p, _rb_mass[idx]])
	return out


## Diagnostics: rubble resting on nothing. A piece is grounded when the ray down from its centre of mass
## (ignoring pieces it starts inside) or its shape moved down by drop reaches the terrain, an intact
## element, an active body or a grounded piece; groundedness spreads up from the ground only, so pieces
## propping each other up in mid-air count as floating. Returns {count, mass, max_gap, total, ...};
## max_gap is the free fall below a floating piece's centre.
func floating_rubble(drop: float = 0.25) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = Layers.TERRAIN | Layers.STRUCTURE | Layers.RUBBLE | Layers.DEBRIS | Layers.DEBRIS_SMALL | Layers.PROPS
	q.margin = 0.1   # within 10 cm counts as touching (curtain-wall parts hang 8 cm off the slab edge they belong to)
	var down := PhysicsRayQueryParameters3D.new()
	down.collision_mask = q.collision_mask
	var n := _rb_alive.size()
	var grounded := PackedByteArray()
	grounded.resize(n)
	var dependents: Dictionary = {}   # rubble idx -> PackedInt32Array of pieces resting on it
	var queue := PackedInt32Array()
	var total := 0
	for idx in n:
		if _rb_alive[idx] == 0:
			continue
		total += 1
		var supports := PackedInt32Array()
		var root := false
		var p := _rb_xf[idx] * _rb_com[idx]
		down.from = p
		down.to = Vector3(p.x, (_rb_xf[idx] * _rb_mesh[idx].get_aabb()).position.y - drop, p.z)
		down.exclude = [_rb_rid[idx]]
		var hit := space.intersect_ray(down)
		if not hit.is_empty():
			var j: int = _rb_by_rid.get(hit["rid"], -1)
			if j < 0:
				root = true
			else:
				supports.append(j)
		if not root:
			q.shape = _rb_shape[idx]
			q.transform = _rb_xf[idx].translated(Vector3(0.0, -drop, 0.0))
			q.exclude = [_rb_rid[idx]]
			for r in space.intersect_shape(q, 32):
				var j: int = _rb_by_rid.get(r["rid"], -1)
				if j < 0:
					root = true
					break
				if j != idx:
					supports.append(j)
		if root:
			grounded[idx] = 1
			queue.append(idx)
			continue
		for j in supports:
			var lst: PackedInt32Array = dependents.get(j, PackedInt32Array())
			lst.append(idx)
			dependents[j] = lst
	var head := 0
	while head < queue.size():
		var s: int = queue[head]
		head += 1
		for d in dependents.get(s, PackedInt32Array()):
			if grounded[d] == 0:
				grounded[d] = 1
				queue.append(d)
	var count := 0
	var mass := 0.0
	var max_gap := 0.0
	var by_reason := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var samples: Array = []
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = q.collision_mask
	for idx in n:
		if _rb_alive[idx] == 0 or grounded[idx] == 1:
			continue
		count += 1
		mass += _rb_mass[idx]
		by_reason[_rb_reason[idx]] += 1
		var p := _rb_xf[idx] * _rb_com[idx]
		ray.from = p
		ray.to = p + Vector3(0.0, -200.0, 0.0)
		ray.exclude = [_rb_rid[idx]]
		var hit := space.intersect_ray(ray)
		var gap := -1.0
		var below := "nothing"
		if not hit.is_empty():
			gap = p.y - (hit["position"] as Vector3).y
			max_gap = maxf(max_gap, gap)
			var j: int = _rb_by_rid.get(hit["rid"], -1)
			if j >= 0:
				below = "rubble r%d m%.0f" % [_rb_reason[j], _rb_mass[j]]
			elif structures != null and structures._static_by_rid.has(hit["rid"]):
				below = "element"
			elif _slot_by_rid.has(hit["rid"]):
				below = "debris kind %d" % _kind[_slot_by_rid[hit["rid"]]]
			else:
				below = "other %s" % hit["collider"]
		if samples.size() < 12 and gap > 0.5:
			var on := _rb_on[idx]
			var on_s := "none"
			if on.is_valid():
				on_s = "rubble" if _rb_by_rid.has(on) else ("element" if structures != null and structures._static_by_rid.has(on) else "GONE")
			# Where the recorded chain of supports ends.
			var root := idx
			var steps := 0
			var seen := {idx: true}
			while steps < 256 and _rb_on[root].is_valid() and _rb_by_rid.has(_rb_on[root]):
				root = _rb_by_rid[_rb_on[root]]
				steps += 1
				if seen.has(root):
					on_s += " LOOP"
					break
				seen[root] = true
			var rp := _rb_xf[root] * _rb_com[root]
			var r_on := _rb_on[root]
			var r_s := "none" if not r_on.is_valid() else ("element" if structures != null and structures._static_by_rid.has(r_on) else ("rubble" if _rb_by_rid.has(r_on) else "GONE"))
			on_s += " (chain %d -> r%d m%.0f at y %.1f grounded %d on %s, checked %.1f s ago)" % [steps, _rb_reason[root], _rb_mass[root], rp.y, grounded[root], r_s,
				(_time - _rb_checked[root]) if _rb_checked[root] >= 0.0 else -1.0]
			samples.append("r%d m%.0f owner %d/%d at (%.1f, %.1f, %.1f) gap %.2f -> %s; frozen %.1f s ago, check pending %d, last check %.1f s ago, on %s" % [_rb_reason[idx], _rb_mass[idx],
				_rb_owner_b[idx], _rb_owner_e[idx], p.x, p.y, p.z, gap, below, _time - _rb_time[idx], _rb_check[idx],
				(_time - _rb_checked[idx]) if _rb_checked[idx] >= 0.0 else -1.0, on_s])
	return {"count": count, "mass": mass, "max_gap": max_gap, "total": total, "samples": samples,
		"pending_checks": _check_queue.size() - _check_head,
		"by_reason": {"settled": by_reason[0], "forced_at_rest": by_reason[1], "dropped": by_reason[2],
			"forced_in_place": by_reason[3], "cluster": by_reason[4], "direct": by_reason[5]}}


## Mass of active debris recomputed from the records (validates the running total).
func recount_debris_mass() -> float:
	var m := 0.0
	for s in _active:
		m += _mass[s]
	return m


## Mass of rubble recomputed from the records.
func recount_rubble_mass() -> float:
	var m := 0.0
	for idx in _rb_alive.size():
		if _rb_alive[idx] == 1:
			m += _rb_mass[idx]
	return m
