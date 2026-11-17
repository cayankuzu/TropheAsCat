class_name StructureManager
extends Node3D
## Owns procedural buildings.
##  * Intact elements: one static PhysicsServer3D body each (shared shape per size, layer STRUCTURE,
##    registered with DamageRouter) and one MultiMesh instance in a (size, material) group.
##  * Damage lowers element HP (cracks drawn by a MultiMesh overlay); at zero HP the element fractures
##    into cached Voronoi pieces handed to the DebrisManager.
##  * The SupportSolver re-evaluates support after every removal; unsupported components fall as
##    RigidBody3D clusters (<= cluster_max_elements shapes, split by storey and region) released
##    bottom-up over a few frames. Cantilever failures sag around their supported edge first, overloaded
##    verticals are crushed after a short delay, and an overturning storey turns everything above it
##    into one compound that hinges about the edge of the remaining supports.
##  * Clusters break up on hard impacts by peeling element groups off into new bodies, nearest first.
## All heavy work runs from _process inside logic_budget_ms.

signal element_destroyed(building_id: int, element_id: int, cause_id: int)
signal element_damaged(building_id: int, element_id: int, hp_fraction: float)
signal cluster_detached(body: RigidBody3D, building_id: int, element_ids: PackedInt32Array)
signal building_toppled(building_id: int, storey: int)
## A masonry storey lost the weight above it off its remaining walls; they are being crushed.
signal storey_failed(building_id: int, storey: int)

const D := preload("res://game/destruction/destruction_defs.gd")
const CRACK_SHADER := preload("res://game/destruction/crack_overlay.gdshader")
const INTACT := D.State.INTACT
const PENDING := D.State.PENDING
const DESTROYED := D.State.DESTROYED
const DETACHED := D.State.DETACHED
const VERT := D.Role.VERTICAL
const HORZ := D.Role.HORIZONTAL
const LATERAL := D.Edge.LATERAL
const SRC_STATIC := 0
const SRC_BODY := 1
const PANCAKE_DEPTH := 3.4   ## m below a landing floor plate whose walls it crushes
const PANCAKE_MAX_VICTIMS := 24
const TOPPLE_MAX_ANGLE := 1.45  ## rad, end of the scripted hinge phase (the block is nearly flat)

## Element id of the stand-in collider of a dormant building.
const PROXY := D.ID_STRIDE - 1

@export var logic_budget_ms := 0.8
## Budget of all destruction logic in one frame: this manager, the debris manager and what both did in
## the physics tick. What the others already spent is taken out of this manager's share (down to 40 %
## of logic_budget_ms, so the queues always move).
@export var total_budget_ms := 1.8

## 1 while the destruction logic fits total_budget_ms, up to 4 when it runs that many times over it
## (a slow machine, or more going on than the budget covers).
var overload := 1.0
var _logic_ema := 0.0

## Dormant buildings. A city has far more elements than the physics engine has bodies, so a building
## the player is not near keeps one box collider (the proxy) instead of a body per element. It wakes
## (gets its element bodies, a few per frame) when the player comes within wake_distance, and at once
## when anything damages it: the hit on the proxy is then passed on to the elements by geometry. A
## building goes dormant again when the player is beyond sleep_distance and nothing has happened to
## it for sleep_quiet_seconds. Without a player (tests) nothing ever wakes or sleeps by distance.
@export var wake_distance := 80.0
@export var sleep_distance := 130.0
@export var sleep_quiet_seconds := 8.0
@export var wake_bodies_per_frame := 100
@export var dormancy_scan_per_frame := 8

var bodies_alive := 0             ## element bodies in the physics space right now
## Mass for the TABLE CLEARED % (the Progress autoload reads both): everything placed, and every
## element that is no longer part of a standing building, whether it broke where it stood or came
## down with a piece of the building. An element is counted once, when it stops being intact.
var built_mass := 0.0
var gone_mass := 0.0
var wakes := 0
var sleeps := 0

var _waking: Array[int] = []      # ids of buildings whose element bodies are being created
var _sleeping: Array[int] = []    # ids of dormant buildings whose element bodies are still being freed
var _scan_building := 0
var _last_blast: DamageHit = null   # the radial hit DamageRouter announced last (its deliveries follow in the same call)
@export var cluster_max_elements := 32
@export var storey_release_delay := 0.0
@export var topple_omega := 0.22
@export var topple_margin_ratio := 0.0
@export var break_dv := 3.5
@export var break_chunk_max := 16   ## largest group peeled off a breaking cluster in one physics tick
@export var sag_degrees := 6.0
@export var sag_seconds := 0.6
@export var max_sag_elements := 64
@export var pancake_energy_factor := 2.0
@export var crush_delay_min := 0.12
@export var crush_delay_max := 0.45
@export var prewarm_patterns := true


class Building:
	var id := 0
	var data: BuildingData
	var xform := Transform3D.IDENTITY
	var root: Node3D
	var solver: SupportSolver
	var state := PackedByteArray()
	var hp := PackedFloat32Array()
	var damage_pt := PackedVector3Array()
	var cur_xf: Array[Transform3D] = []
	var bodies: Array[RID] = []
	var group := PackedInt32Array()
	var inst := PackedInt32Array()
	var groups: Array[InstanceGroup] = []
	var dirty := false
	var cause := 0   ## cause_id of the latest hit that took something out; inherited by its chain reaction
	## Dormant buildings have no element bodies, only `proxy` (one box). See "Dormant buildings" below.
	var awake := true
	var proxy := RID()
	var proxy_shape: BoxShape3D = null
	var wake_next := 0          ## next element to get its body while the building is waking up
	var world_box := AABB()
	var last_active := -100.0   ## _time of the latest damage or collapse work
	var failing: Dictionary = {}   ## masonry storeys whose remaining walls are being crushed (see _fail_storey)
	var far: MeshInstance3D = null   ## the merged far LOD (see "Far LOD")
	var gone_count := 0              ## elements no longer standing; the far LOD only shows a whole building
	var doors := PackedInt32Array()  ## elements that open when Trophe comes up to them (doors, roller doors)
	var door_open := {}              ## element -> true while it stands open


class FractureJob:
	var building := 0
	var element := 0
	var source := 0
	var slot := -1
	var gen := -1
	var variant := 4
	var local_hit := Vector3.ZERO
	var dir := Vector3.ZERO
	var impulse := 0.0
	var cause := 0
	var crushed := false   ## broken by load or a landing floor: pieces are pulverised (small tier)


class ClusterBuild:
	var building := 0
	var elems := PackedInt32Array()
	var release_time := 0.0
	var use_pivot := false
	var pivot := Vector3.ZERO
	var ang := Vector3.ZERO
	var big := false
	var cause := 0
	var cluster: DebrisCluster = null
	var group: ReleaseGroup = null
	var single := -1          ## element id when this build is one loose element


## Chunks of one failing component are built over several frames but start falling in the same frame,
## so the block drops as a whole instead of separating storey by storey.
class ReleaseGroup:
	var total := 0
	var ready: Array[ClusterBuild] = []


## Hinge phase of an overturning structure: the compound is kinematic and rotates about the edge of
## the remaining supports under gravity torque until its leading base edge reaches the ground, then it
## continues as a dynamic body with the same motion. Avoids a 1000 t body being propped by rubble.
class Topple:
	var cluster: DebrisCluster
	var building := 0
	var slot := -1
	var gen := -1
	var pivot := Vector3.ZERO
	var axis := Vector3.FORWARD
	var start_xf := Transform3D.IDENTITY
	var theta := 0.0
	var omega := 0.0
	var theta_max := 0.2
	var inertia := 1.0
	var mass := 1.0
	var ground_y := 0.0
	var crush_order := PackedInt32Array()     ## local indices sorted by the angle at which they reach the ground
	var crush_theta := PackedFloat32Array()
	var crush_next := 0


class Sag:
	var building := 0
	var elems := PackedInt32Array()
	var pivot_local := Vector3.ZERO
	var axis_local := Vector3.RIGHT
	var start := 0.0
	var duration := 0.6
	var max_angle := 0.1


var debris: DebrisManager = null
var fx: DestructionFX = null
var fracture := FractureLibrary.new()
var crack_material: ShaderMaterial
var buildings: Array[Building] = []

var _fracture_jobs: Array[FractureJob] = []
var _builds: Array[ClusterBuild] = []
var _breaking: Array[DebrisCluster] = []
var _sags: Array[Sag] = []
var _topples: Array[Topple] = []
var _crush_b := PackedInt32Array()
var _crush_e := PackedInt32Array()
var _crush_t := PackedFloat64Array()
var _crush_c := PackedInt32Array()
var _static_by_rid: Dictionary = {}   # intact element body RID -> building_id * ID_STRIDE + element

## World rewind (Timeline): every element that leaves the structure is logged with this node's clock;
## rewinding brings them back, newest first, without debris or effects. While `rewinding` the frame
## logic stands still.
const REWIND_WINDOW := 17.0
var rewinding := false
var revived := 0
var _gone_t := PackedFloat64Array()
var _gone_b := PackedInt32Array()
var _gone_e := PackedInt32Array()
var _rw_now := 0.0

## Far LOD (2026-11-17): beyond far_lod_distance a whole building is drawn as one merged mesh of its
## outside (a surface per material, shared by every lot of the same design) instead of a MultiMesh per
## element kind; up close and once it has lost anything, it is drawn element by element as before. The
## merged meshes are made one design per frame after the city is placed, so loading does not wait.
@export var far_lod_distance := 240.0
const LITE_FAR_LOD := 70.0
const FAR_HIDDEN_KINDS := [D.Kind.PARTITION, D.Kind.CORE, D.Kind.COLUMN, D.Kind.SLAB, D.Kind.FLOOR, D.Kind.MULLION]
var _far_meshes: Dictionary = {}   # BuildingData instance id -> ArrayMesh
var _far_queue := PackedInt32Array()
var _pancake_query := PhysicsShapeQueryParameters3D.new()
var _pancake_box := BoxShape3D.new()
var _time := 0.0
var _rng := RandomNumberGenerator.new()

# Statistics.
var frame_usec := 0               ## logic time of the last _process
var physics_usec := 0             ## logic time of the last _physics_process (cluster break-up)
var damage_usec := 0              ## receive_damage time accumulated since the last _process
var last_damage_usec := 0
var elements_destroyed := 0
var clusters_created := 0
var mass_fractured := 0.0         ## kg of elements turned into fracture pieces
var mass_detached := 0.0          ## kg of intact elements that left their building as bodies
var topples := 0
var storeys_failed := 0           ## masonry storeys crushed by an eccentric load (see _fail_storey)
var pancaked := 0                 ## elements crushed by landing floor plates
var coarse_fractures := 0         ## fractures switched to the coarse pattern because the debris budget was full
var prof_build_usec := 0
var prof_visual_usec := 0
var prof_remove_usec := 0
var prof_fracture_usec := 0
var prof_solve_usec := 0


func _enter_tree() -> void:
	Game.structures = self


func _exit_tree() -> void:
	clear()
	fracture.shutdown()
	if Game.structures == self:
		Game.structures = null


## Teardown: removes every building (server bodies, visuals), all pending work, and the debris and
## rubble of the DebrisManager (its bodies refer to these buildings' element data).
func clear() -> void:
	_static_by_rid.clear()
	for b in buildings:
		for i in b.bodies.size():
			var rid := b.bodies[i]
			if rid.is_valid():
				DamageRouter.unregister_rid(rid)
				PhysicsServer3D.free_rid(rid)
				b.bodies[i] = RID()
		_drop_proxy(b)
		if is_instance_valid(b.root):
			b.root.queue_free()
	# Clusters built but not yet handed to the DebrisManager are bodies outside the tree.
	for cb in _builds:
		var waiting: Array[ClusterBuild] = [cb]
		if cb.group != null:
			waiting.append_array(cb.group.ready)
			cb.group.ready.clear()
		for w in waiting:
			if w.cluster != null and is_instance_valid(w.cluster.body) and not w.cluster.body.is_inside_tree():
				w.cluster.body.free()
	buildings.clear()
	_waking.clear()
	_sleeping.clear()
	built_mass = 0.0
	gone_mass = 0.0
	bodies_alive = 0
	_fracture_jobs.clear()
	_builds.clear()
	_breaking.clear()
	_sags.clear()
	_topples.clear()
	_crush_b.clear()
	_crush_e.clear()
	_crush_t.clear()
	_crush_c.clear()
	if is_instance_valid(debris):
		debris.clear()


func _ready() -> void:
	if Game.lite:
		# The browser demo on an integrated GPU: the merged far mesh of a building (1 draw call) from 70 m on,
		# instead of its element groups (tens of draw calls each).
		far_lod_distance = minf(far_lod_distance, LITE_FAR_LOD)
	crack_material = ShaderMaterial.new()
	crack_material.shader = CRACK_SHADER
	_rng.seed = 0x5EED
	DamageRouter.blast.connect(_on_router_blast)
	if debris == null:
		debris = Game.debris as DebrisManager
	if debris != null:
		debris.structures = self
		if debris.fx == null:
			debris.fx = fx


## Creates the DebrisManager, DestructionFX and StructureManager under parent and wires them together.
static func create_world(parent: Node) -> StructureManager:
	var fx_node := DestructionFX.new()
	fx_node.name = "DestructionFX"
	parent.add_child(fx_node)
	var dm := DebrisManager.new()
	dm.name = "DebrisManager"
	dm.fx = fx_node
	parent.add_child(dm)
	var sm := StructureManager.new()
	sm.name = "StructureManager"
	sm.debris = dm
	sm.fx = fx_node
	dm.structures = sm
	parent.add_child(sm)
	return sm


# --------------------------------------------------------------------------------------------------
# Buildings
# --------------------------------------------------------------------------------------------------

## awake = false creates the building dormant (see "Dormant buildings"): the way to place a whole city.
func add_building(data: BuildingData, xform: Transform3D, awake: bool = true) -> int:
	var b := Building.new()
	b.id = buildings.size()
	b.data = data
	b.xform = global_transform * xform
	b.root = Node3D.new()
	b.root.name = "Building%d_%s" % [b.id, D.STYLE_NAMES[data.style]]
	add_child(b.root)
	b.root.global_transform = b.xform
	b.solver = SupportSolver.new()
	b.solver.setup(data)
	var n := data.count()
	b.state.resize(n)
	b.state.fill(INTACT)
	b.hp = data.max_hp.duplicate()
	b.damage_pt.resize(n)
	b.cur_xf = data.xf.duplicate()
	b.bodies.resize(n)
	b.group.resize(n)
	b.inst.resize(n)
	var group_by_key: Dictionary = {}
	var counts: Dictionary = {}
	for i in n:
		var key := ElementLibrary.size_key(data.dims[i], data.shape[i]) + "|" + String(data.material_name(i))
		counts[key] = counts.get(key, 0) + 1
	for i in n:
		var mname := data.material_name(i)
		var key := ElementLibrary.size_key(data.dims[i], data.shape[i]) + "|" + String(mname)
		var gi: int = group_by_key.get(key, -1)
		if gi < 0:
			gi = b.groups.size()
			group_by_key[key] = gi
			var mesh := ElementLibrary.mesh(data.dims[i], data.shape[i], mname)
			b.groups.append(InstanceGroup.new(b.root, mesh, counts[key], true, not MaterialDB.is_glass(mname), false))
			if prewarm_patterns and not Game.lite:
				fracture.prewarm(data.dims[i], data.shape[i], mname)
				fracture.get_pattern(data.dims[i], data.shape[i], mname, FractureLibrary.COARSE_VARIANT, false)
		b.group[i] = gi
		b.inst[i] = b.groups[gi].add(i, data.xf[i])
	b.world_box = b.xform * data.bounds
	built_mass += data.total_mass()
	buildings.append(b)
	for i in data.count():
		var mname := String(data.material_name(i))
		if data.kind[i] == D.Kind.DOOR or mname.begins_with("tower_door"):
			b.doors.append(i)
	if far_lod_distance > 0.0:
		_far_queue.append(b.id)
	if awake:
		for i in n:
			_create_body(b, i)
		b.wake_next = n
	else:
		b.awake = false
		_make_proxy(b)
	return b.id


func spawn_building(style: int, seed_value: int, xform: Transform3D, awake: bool = true) -> int:
	return add_building(BuildingGenerator.generate(style, seed_value), xform, awake)


# --------------------------------------------------------------------------------------------------
# Dormant buildings
# --------------------------------------------------------------------------------------------------

func is_awake(bid: int) -> bool:
	return buildings[bid].awake


## The static body of one intact element (nothing happens if it has one, or is no longer intact).
func _create_body(b: Building, i: int) -> void:
	if b.state[i] != INTACT or b.bodies[i].is_valid():
		return
	var rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(rid, ElementLibrary.collision_shape(b.data.dims[i], b.data.shape[i]).get_rid())
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, b.xform * b.cur_xf[i])
	PhysicsServer3D.body_set_collision_layer(rid, Layers.STRUCTURE)
	PhysicsServer3D.body_set_collision_mask(rid, 0)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
	PhysicsServer3D.body_set_space(rid, get_world_3d().space)
	DamageRouter.register_rid(rid, self, b.id * D.ID_STRIDE + i)
	_static_by_rid[rid] = b.id * D.ID_STRIDE + i
	b.bodies[i] = rid
	bodies_alive += 1


func _make_proxy(b: Building) -> void:
	if b.proxy.is_valid():
		return
	b.proxy_shape = BoxShape3D.new()
	b.proxy_shape.size = b.data.bounds.size
	var rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(rid, b.proxy_shape.get_rid(), Transform3D(Basis.IDENTITY, b.data.bounds.get_center()))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, b.xform)
	PhysicsServer3D.body_set_collision_layer(rid, Layers.STRUCTURE)
	PhysicsServer3D.body_set_collision_mask(rid, 0)
	PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
	PhysicsServer3D.body_set_space(rid, get_world_3d().space)
	DamageRouter.register_rid(rid, self, b.id * D.ID_STRIDE + PROXY)
	b.proxy = rid


func _drop_proxy(b: Building) -> void:
	if b.proxy.is_valid():
		DamageRouter.unregister_rid(b.proxy)
		PhysicsServer3D.free_rid(b.proxy)
		b.proxy = RID()
		b.proxy_shape = null


## Gives a dormant building all its element bodies now (damage does this; proximity wakes it gradually).
func wake_building(bid: int) -> void:
	var b := buildings[bid]
	if b.awake:
		return
	if _sleeping.has(bid):
		_sleeping.erase(bid)
		b.wake_next = 0   # it was still giving its bodies back: only the missing ones are made again
	for i in range(b.wake_next, b.data.count()):
		_create_body(b, i)
	_finish_wake(b)


func _finish_wake(b: Building) -> void:
	b.wake_next = b.data.count()
	b.awake = true
	_drop_proxy(b)
	_waking.erase(b.id)
	wakes += 1


## Makes a quiet building dormant: the proxy goes in now, the element bodies are given back a batch
## per frame (see _update_dormancy). A building with nothing left standing gets no proxy.
func sleep_building(bid: int) -> void:
	var b := buildings[bid]
	if not b.awake:
		return
	b.awake = false
	b.wake_next = 0
	sleeps += 1
	for i in b.state.size():
		if b.state[i] == INTACT:
			_make_proxy(b)
			break
	_sleeping.append(bid)


## Frees up to max_count element bodies of a dormant building, starting at b.wake_next. True when none are left.
func _free_bodies(b: Building, max_count: int) -> bool:
	var n := b.bodies.size()
	var done := 0
	while b.wake_next < n and done < max_count:
		var rid := b.bodies[b.wake_next]
		if rid.is_valid():
			_static_by_rid.erase(rid)
			DamageRouter.unregister_rid(rid)
			PhysicsServer3D.free_rid(rid)
			b.bodies[b.wake_next] = RID()
			bodies_alive -= 1
			done += 1
		b.wake_next += 1
	if b.wake_next >= n:
		b.wake_next = 0
		return true
	return false


func _can_sleep(b: Building) -> bool:
	return not b.dirty and b.failing.is_empty() and _time - b.last_active > sleep_quiet_seconds and b.solver.is_idle()


## A few buildings per frame are checked against the player's position; waking buildings get their
## bodies a batch at a time.
func _update_dormancy() -> void:
	var player := Game.player
	if player != null and is_instance_valid(player) and not buildings.is_empty():
		var at := player.global_position
		for k in mini(dormancy_scan_per_frame, buildings.size()):
			_scan_building = (_scan_building + 1) % buildings.size()
			var b := buildings[_scan_building]
			var d := at.distance_to(at.clamp(b.world_box.position, b.world_box.end))
			if not b.awake:
				if d < wake_distance and b.proxy.is_valid() and not _waking.has(b.id):
					if _sleeping.has(b.id):
						_sleeping.erase(b.id)
						b.wake_next = 0
					_waking.append(b.id)
			elif d > sleep_distance and _can_sleep(b):
				sleep_building(b.id)
	if not _sleeping.is_empty():
		var sb := buildings[_sleeping[0]]
		if _free_bodies(sb, wake_bodies_per_frame * 3):
			_sleeping.remove_at(0)
	var left := wake_bodies_per_frame
	while left > 0 and not _waking.is_empty():
		var b := buildings[_waking[0]]
		var n := b.data.count()
		while left > 0 and b.wake_next < n:
			if b.state[b.wake_next] == INTACT and not b.bodies[b.wake_next].is_valid():
				_create_body(b, b.wake_next)
				left -= 1
			b.wake_next += 1
		if b.wake_next >= n:
			_finish_wake(b)


func _on_router_blast(hit: DamageHit) -> void:
	_last_blast = hit


## A hit landed on the proxy of a dormant building: wake it and pass the hit on to its elements.
func _proxy_hit(b: Building, hit: DamageHit) -> void:
	wake_building(b.id)
	var n := b.data.count()
	var to_local := b.xform.affine_inverse()
	if hit.radius > 0.0:
		# DamageRouter hands a blast to each body as a copy moved to that body; the blast itself was
		# announced just before (same cause).
		var blast := _last_blast if _last_blast != null and _last_blast.cause_id == hit.cause_id else hit
		var centre := to_local * blast.position
		for e in n:
			if b.state[e] != INTACT:
				continue
			var half := b.data.dims[e] * 0.5
			var reach := blast.radius + half.length()
			if centre.distance_squared_to(b.cur_xf[e].origin) > reach * reach:
				continue
			var lc := b.cur_xf[e].affine_inverse() * centre
			var q := lc.clamp(-half, half)
			var d := lc.distance_to(q)
			if d >= blast.radius:
				continue
			var h := blast.falloff_copy(d)
			var wp := (b.xform * b.cur_xf[e]) * q
			h.position = wp
			h.direction = (wp - blast.position).normalized() if d > 0.01 else Vector3.UP
			_apply_damage(b, e, h, q)
		return
	# Point hit: the first intact element along the direction of the hit, starting just outside.
	var dir := to_local.basis * hit.direction
	var start := to_local * hit.position - dir * 0.75
	var best := -1
	var best_t := 1.0e9
	var best_local := Vector3.ZERO
	for e in n:
		if b.state[e] != INTACT:
			continue
		var half := b.data.dims[e] * 0.5
		var to := b.cur_xf[e].origin - start
		if dir == Vector3.ZERO:
			var d2 := to.length_squared()
			if d2 < best_t:
				best_t = d2
				best = e
				best_local = (b.cur_xf[e].affine_inverse() * (start)).clamp(-half, half)
			continue
		var along := to.dot(dir)
		var size := half.length()
		if along < -size or along - size > best_t or to.length_squared() - along * along > size * size:
			continue
		var inv := b.cur_xf[e].affine_inverse()
		var lo := inv * start
		var ld := inv.basis * dir
		var t_in := -1.0e9
		var t_out := 1.0e9
		for a in 3:
			if absf(ld[a]) < 1e-6:
				if absf(lo[a]) > half[a]:
					t_in = 1.0e9
				continue
			var t1 := (-half[a] - lo[a]) / ld[a]
			var t2 := (half[a] - lo[a]) / ld[a]
			t_in = maxf(t_in, minf(t1, t2))
			t_out = minf(t_out, maxf(t1, t2))
		if t_in <= t_out and t_out >= 0.0 and t_in < best_t:
			best_t = maxf(t_in, 0.0)
			best = e
			best_local = (lo + ld * best_t).clamp(-half, half)
	if best >= 0:
		_apply_damage(b, best, hit, best_local)


# --------------------------------------------------------------------------------------------------
# Damage
# --------------------------------------------------------------------------------------------------

func receive_damage(hit: DamageHit, user_id: int) -> void:
	var t0 := Time.get_ticks_usec()
	var bid := user_id >> 16
	var e := user_id & 0xFFFF
	if bid >= 0 and bid < buildings.size():
		var b := buildings[bid]
		if e == PROXY:
			_proxy_hit(b, hit)
		elif b.state[e] == INTACT:
			_apply_damage(b, e, hit, _local_hit(b, e, hit))
	damage_usec += Time.get_ticks_usec() - t0


func _local_hit(b: Building, e: int, hit: DamageHit) -> Vector3:
	var inv := (b.xform * b.cur_xf[e]).affine_inverse()
	var h := b.data.dims[e] * 0.5
	if hit.radius > 0.0 and hit.direction != Vector3.ZERO:
		# Blasts report the element origin; use the face point that looks at the blast centre.
		var d := (inv.basis * -hit.direction).normalized()
		var t := 1.0e9
		for a in 3:
			if absf(d[a]) > 1e-4:
				t = minf(t, h[a] / absf(d[a]))
		return (d * t).clamp(-h, h)
	return (inv * hit.position).clamp(-h, h)


static func _kind_factor(kind: int, material: StringName) -> float:
	match kind:
		DamageHit.Kind.SONIC:
			if MaterialDB.is_glass(material):
				return 1000.0
			return 0.6 if MaterialDB.base_of(material) == &"plaster" else 0.03
		DamageHit.Kind.HEAT:
			return 0.5
		DamageHit.Kind.ACID:
			return 0.8
		DamageHit.Kind.CUT:
			return 1.5
	return 1.3 if MaterialDB.is_brittle(material) else 1.0


func _apply_damage(b: Building, e: int, hit: DamageHit, local: Vector3) -> void:
	var mname := b.data.material_name(e)
	var dmg := hit.energy * _kind_factor(hit.kind, mname)
	if b.data.is_glass(e) and (hit.kind == DamageHit.Kind.SONIC or hit.energy > 3.0):
		dmg = b.hp[e] + 1.0
	if dmg <= 0.0:
		return
	b.last_active = _time
	b.hp[e] -= dmg
	b.damage_pt[e] = local
	if b.hp[e] <= 0.0:
		destroy_element(b.id, e, hit, local, hit.kind == DamageHit.Kind.CRUSH)
		return
	_update_crack(b, e)
	element_damaged.emit(b.id, e, b.hp[e] / b.data.max_hp[e])


func _crack_color(b: Building, e: int) -> Color:
	var frac := 1.0 - b.hp[e] / maxf(b.data.max_hp[e], 0.001)
	if frac < 0.02:
		return Color(0, 0, 0, 0)
	var p := b.damage_pt[e]
	return Color(frac, p.x, p.y, p.z)


func _update_crack(b: Building, e: int) -> void:
	var k := b.inst[e]
	if k < 0:
		return
	var g := b.groups[b.group[e]]
	g.set_custom(k, _crack_color(b, e))
	if not g.has_overlay:
		g.mmi.material_overlay = crack_material
		g.has_overlay = true


## Destroys an intact element: it leaves the support graph now and fractures as soon as its pattern is
## ready and the debris budget allows.
func destroy_element(bid: int, e: int, hit: DamageHit = null, local: Vector3 = Vector3.ZERO, crushed: bool = false) -> void:
	var b := buildings[bid]
	if b.state[e] != INTACT:
		return
	if not b.awake:
		wake_building(bid)   # whatever takes an element out needs its neighbours to be solid
	b.last_active = _time
	b.state[e] = PENDING
	gone_mass += b.data.mass[e]
	_log_gone(b, e)
	b.hp[e] = 0.0
	var cause := hit.cause_id if hit != null and hit.cause_id != 0 else b.cause
	if cause == 0:
		cause = DamageRouter.new_cause_id()
	b.cause = cause
	# The collision body goes now (nothing may rest on a destroyed element); the visual stays until
	# the fracture pieces replace it a few frames later.
	_remove_body(b, e)
	var over := b.solver.remove(e, true)
	for v in over:
		_schedule_crush(bid, v, cause)
	b.dirty = true
	var job := FractureJob.new()
	job.building = bid
	job.element = e
	job.source = SRC_STATIC
	job.local_hit = local
	job.crushed = crushed
	job.variant = FractureLibrary.COARSE_VARIANT if crushed else FractureLibrary.variant_for(b.data.dims[e], local)
	job.cause = cause
	if hit != null:
		job.dir = hit.direction
		job.impulse = hit.impulse
	_fracture_jobs.append(job)
	fracture.get_pattern(b.data.dims[e], b.data.shape[e], b.data.material_name(e), job.variant)
	elements_destroyed += 1
	element_destroyed.emit(bid, e, job.cause)


func _schedule_crush(bid: int, e: int, cause: int) -> void:
	_crush_b.append(bid)
	_crush_e.append(e)
	_crush_t.append(_time + _rng.randf_range(crush_delay_min, crush_delay_max))
	_crush_c.append(cause)


func _process_crush() -> void:
	var i := 0
	while i < _crush_t.size():
		if _crush_t[i] > _time:
			i += 1
			continue
		var bid := _crush_b[i]
		var e := _crush_e[i]
		var cause := _crush_c[i]
		var last := _crush_t.size() - 1
		_crush_b[i] = _crush_b[last]
		_crush_e[i] = _crush_e[last]
		_crush_t[i] = _crush_t[last]
		_crush_c[i] = _crush_c[last]
		_crush_b.resize(last)
		_crush_e.resize(last)
		_crush_t.resize(last)
		_crush_c.resize(last)
		var b := buildings[bid]
		if b.state[e] == INTACT:
			var top := Vector3(0.0, b.data.dims[e].y * 0.45, 0.0)
			var hit := DamageHit.point((b.xform * b.cur_xf[e]) * top, Vector3.DOWN, b.hp[e] + 1.0, 0.0, DamageHit.Kind.CRUSH)
			hit.cause_id = cause
			destroy_element(bid, e, hit, top)
		elif b.state[e] == DETACHED:
			_crush_detached(b, e, cause)


## The crush of a failing storey also reaches its walls that came loose before their turn (as loose
## elements, or inside a falling cluster). Left alone they stand under the block like legs, settle into
## rubble while they still carry it, and hold it up for good: rubble is never crushed.
func _crush_detached(b: Building, e: int, cause: int) -> void:
	var hit := DamageHit.point(Vector3.ZERO, Vector3.DOWN, b.hp[e] + 1.0, 0.0, DamageHit.Kind.CRUSH)
	hit.cause_id = cause
	for s in debris._t1_active:
		if debris._kind[s] == DebrisManager.Kind.ELEMENT:
			if debris._owner_b[s] == b.id and debris._owner_e[s] == e:
				hit.position = debris._body[s].global_position
				on_element_damage(s, hit)
				return
		elif debris._kind[s] == DebrisManager.Kind.CLUSTER:
			var c := debris._cluster[s]
			if c == null or c.building != b.id or c.freezing or c.kinematic:
				continue
			var i := c.elems.find(e)
			if i >= 0 and c.owners[i] >= 0:
				hit.position = c.body.global_transform * (c.locals[i] * c.elem_com[i])
				_damage_cluster_element(c, hit)
				return


# --------------------------------------------------------------------------------------------------
# Frame update
# --------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if rewinding:
		return
	_update_doors(delta)
	var t0 := Time.get_ticks_usec()
	_time += delta
	_prune_gone_log()
	if not _far_queue.is_empty():
		_process_far_queue()
	var budget := int(logic_budget_ms * 1000.0)
	if debris != null:
		# The debris manager runs before this node in the frame, so its numbers are this frame's.
		var spent := physics_usec + damage_usec + debris.physics_usec + debris.frame_usec
		budget = clampi(int(total_budget_ms * 1000.0) - spent, budget * 2 / 5, budget)
		# How far the whole destruction logic runs over its budget, smoothed over about a third of a
		# second. The debris manager sheds its least important work by this factor (see overload).
		_logic_ema = lerpf(_logic_ema, float(spent + frame_usec), 0.05)
		overload = clampf(_logic_ema / (total_budget_ms * 1000.0), 1.0, 4.0)
	var end := t0 + budget
	_update_dormancy()
	fracture.poll(budget * 20 / 100)
	_process_crush()
	_process_sags()
	_solve(mini(Time.get_ticks_usec() + budget * 30 / 100, end))
	_process_builds(mini(Time.get_ticks_usec() + budget * 30 / 100, end))
	# A long fracture queue means destroyed elements are still drawn whole: it always gets a slice.
	var fr_share := 25 if _fracture_jobs.size() < 24 else 60
	_process_fractures(maxi(end, Time.get_ticks_usec() + budget * fr_share / 100))
	frame_usec = Time.get_ticks_usec() - t0
	last_damage_usec = damage_usec
	damage_usec = 0


func is_busy() -> bool:
	if not _fracture_jobs.is_empty() or not _builds.is_empty() or not _breaking.is_empty() or not _sags.is_empty() \
			or not _crush_t.is_empty() or not _topples.is_empty():
		return true
	for b in buildings:
		if b.dirty:
			return true
	return false


# --------------------------------------------------------------------------------------------------
# Fracture
# --------------------------------------------------------------------------------------------------

func _process_fractures(deadline: int) -> void:
	var i := 0
	while i < _fracture_jobs.size():
		if Time.get_ticks_usec() > deadline:
			return
		var job := _fracture_jobs[i]
		var b := buildings[job.building]
		var e := job.element
		var mname := b.data.material_name(e)
		# Destruction LOD: with the debris budget nearly full, fracture into the few big cells of the coarse
		# pattern (always prewarmed); every extra piece would only push a falling one into early rubble.
		if job.variant != FractureLibrary.COARSE_VARIANT and debris.active_count() > debris.awake_budget * 9 / 10 \
				and fracture.has_pattern(b.data.dims[e], b.data.shape[e], mname, FractureLibrary.COARSE_VARIANT):
			job.variant = FractureLibrary.COARSE_VARIANT
			coarse_fractures += 1
		var pat := fracture.get_pattern(b.data.dims[e], b.data.shape[e], mname, job.variant)
		if pat == null:
			i += 1
			continue
		var t0 := Time.get_ticks_usec()
		debris.make_room(pat.cells.size())
		_execute_fracture(job, pat)
		_fracture_jobs.remove_at(i)
		prof_fracture_usec += Time.get_ticks_usec() - t0


func _execute_fracture(job: FractureJob, pat: FractureLibrary.Pattern) -> void:
	var b := buildings[job.building]
	var e := job.element
	var mname := b.data.material_name(e)
	var xf: Transform3D
	var lin := Vector3.ZERO
	var ang := Vector3.ZERO
	var com: Vector3
	if job.source == SRC_STATIC:
		if b.state[e] != PENDING:
			return
		xf = b.xform * b.cur_xf[e]
		com = xf * D.shape_centroid(b.data.dims[e], b.data.shape[e])
		_remove_static(b, e)
	else:
		if not debris.is_live(job.slot, job.gen):
			b.state[e] = DETACHED   # it settled into rubble meanwhile; it stays whole
			return
		var body := debris.body_of(job.slot)
		xf = body.global_transform
		lin = body.linear_velocity
		ang = body.angular_velocity
		com = xf * body.center_of_mass
		debris.release(job.slot)
	b.state[e] = DESTROYED
	mass_fractured += b.data.mass[e]
	var density := MaterialDB.density(mname)
	var hit_w := xf * job.local_hit
	var kick := clampf(job.impulse / maxf(b.data.mass[e], 1.0), 0.0, 12.0 if b.data.is_glass(e) else 16.0)
	var glass := b.data.is_glass(e)
	var planar := _is_planar(b.data.dims[e])
	var dir := _escape_direction(b.data.dims[e], xf, job.dir, job.local_hit)
	if planar and dir.length_squared() < 0.01:
		dir = _escape_direction(b.data.dims[e], xf, Vector3.ZERO, Vector3.ZERO)
	var crumble := (kick < 0.8 and job.source == SRC_STATIC) or job.crushed
	if crumble and kick < 1.2:
		kick = 1.2   # crushed or destroyed in place: crumble out of the slot instead of restacking in it
	var center_w := xf * D.shape_centroid(b.data.dims[e], b.data.shape[e])
	for cell in pat.cells:
		var m := cell.volume * density
		var cw := xf * cell.centroid
		var v := lin + ang.cross(cw - com)
		var away := cw - hit_w
		var near := 1.0 / (1.0 + away.length() * 1.2)
		v += dir * kick * (0.55 + near) * _rng.randf_range(0.8, 1.2)
		if planar:
			v += dir * _rng.randf_range(0.0, 0.5) + Vector3(0.0, _rng.randf_range(-0.2, 0.3), 0.0)
		else:
			var radial := cw - (center_w if crumble else hit_w)
			radial.y *= 0.3
			v += radial.normalized() * kick * (0.8 if crumble else 0.25 * near)
			v += Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(0.0, 0.4), _rng.randf_range(-0.35, 0.35))
		var spin := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * (0.8 + kick * 0.25)
		# Crushed elements are pulverised: their pieces are small debris that falling floors pass through.
		var tier := DebrisManager.T2 if (glass or crumble or m < 40.0 or cell.max_extent < 0.3) else DebrisManager.T1
		debris.spawn_piece(cell.mesh, cell.shape, xf, cell.centroid, m, v, ang + spin, tier, mname, job.cause)
	if fx != null:
		var size := b.data.dims[e]
		var strength := clampf(b.data.mass[e] / 3000.0, 0.15, 1.0)
		fx.dust(xf * D.shape_centroid(size, b.data.shape[e]), size, mname, strength)
		fx.chips(hit_w, size * 0.4, mname, strength, job.dir * kick + lin)


## Pieces of a wall or slab span its full thickness, and in-plane motion only wedges them against
## the neighbours, so the push goes mostly along the thin axis, away from the side that was hit.
static func _escape_direction(size: Vector3, xf: Transform3D, dir: Vector3, local_hit: Vector3) -> Vector3:
	if not _is_planar(size):
		return dir
	var t := FractureLibrary._sorted_axes(size)[2]
	var ld := xf.basis.inverse() * dir
	var s := signf(ld[t])
	if absf(ld[t]) < 0.2:
		if absf(local_hit[t]) > 1e-4:
			s = -signf(local_hit[t])
		else:
			s = -1.0 if t == 1 else (1.0 if int(absf(xf.origin.x * 7.0 + xf.origin.z * 3.0)) % 2 == 0 else -1.0)
	var out := ld * 0.15
	out[t] = s * maxf(absf(ld[t]), 0.9)
	return (xf.basis * out).normalized()


static func _is_planar(size: Vector3) -> bool:
	var axes := FractureLibrary._sorted_axes(size)
	return size[axes[2]] <= size[axes[1]] * 0.42


## wake: let the DebrisManager wake what rested on the element (callers that remove many neighbouring
## elements at once pass false and wake their combined box instead).
func _remove_body(b: Building, e: int, wake: bool = true) -> void:
	var rid := b.bodies[e]
	if rid.is_valid():
		_static_by_rid.erase(rid)
		DamageRouter.unregister_rid(rid)
		PhysicsServer3D.free_rid(rid)
		b.bodies[e] = RID()
		bodies_alive -= 1
		debris.support_removed(rid)
		if wake:
			# Recorded rubble was queued by support_removed; this wakes sleeping debris on the element and
			# rubble whose support was never recorded.
			debris.wake_box(b.xform * b.cur_xf[e], b.data.dims[e], NAN, 48)
			if b.cur_xf[e] != b.data.xf[e]:
				debris.wake_box(b.xform * b.data.xf[e], b.data.dims[e], NAN, 48)   # it sagged away from what lay on it


func _remove_static(b: Building, e: int, wake: bool = true) -> void:
	_remove_body(b, e, wake)
	var k := b.inst[e]
	if k >= 0:
		var moved := b.groups[b.group[e]].remove(k)
		if moved >= 0:
			b.inst[moved] = k
		b.inst[e] = -1


# --------------------------------------------------------------------------------------------------
# Support and detachment
# --------------------------------------------------------------------------------------------------

func _solve(deadline: int) -> void:
	for b in buildings:
		if not b.dirty:
			continue
		var left := deadline - Time.get_ticks_usec()
		if left <= 0:
			return
		if not b.solver.run(left):
			return
		# A frame overturns with its unsupported overhang still attached (its weight is the lever).
		# Masonry sheds the overhang first; only what still stands is checked for overturning, otherwise
		# a block with one end blown out would pivot whole and stand up on that end.
		if not b.data.monolithic:
			_detach_pending(b)
		var margin := topple_margin_ratio * minf(b.data.bounds.size.x, b.data.bounds.size.z)
		var toppled := false
		for f in b.solver.overturn_dirty.size():
			if b.solver.overturn_dirty[f] == 1:
				var hinge := b.solver.check_overturn(f, margin)
				if hinge.is_empty():
					continue
				if not b.data.monolithic:
					_fail_storey(b, f)
					continue
				_start_topple(b, hinge)
				toppled = true
				break
		if toppled:
			continue
		_detach_pending(b)
		b.dirty = not b.solver.is_idle()


## Masonry walls cannot carry the storeys above as a rigid cantilever: once that weight no longer lies over
## the remaining walls of storey f, the eccentric load crushes them and everything above drops onto the
## storey below (and pancakes there) instead of hinging over as one box.
func _fail_storey(b: Building, f: int) -> void:
	if b.failing.has(f):
		return
	b.failing[f] = true
	storeys_failed += 1
	for v in b.solver.verticals_by_storey[f]:
		# Walls that already came loose are crushed too (see _crush_detached).
		if (b.solver.alive[v] == 1 and b.state[v] == INTACT) or b.state[v] == DETACHED:
			_schedule_crush(b.id, v, b.cause)
	storey_failed.emit(b.id, f)


func _detach_pending(b: Building) -> void:
	var un := b.solver.newly_unsupported
	b.solver.newly_unsupported = PackedInt32Array()
	if not un.is_empty():
		_detach_unsupported(b, un)


func _detach_unsupported(b: Building, list: PackedInt32Array) -> void:
	var n := b.data.count()
	var mark := PackedByteArray()
	mark.resize(n)
	var cand := PackedInt32Array()
	for e in list:
		if mark[e] == 0 and b.state[e] == INTACT and b.solver.alive[e] == 1 and b.solver.sup[e] == 0:
			mark[e] = 1
			cand.append(e)
	var adj_start := b.data.adj_start
	var adj_to := b.data.adj_to
	for s in cand:
		if mark[s] != 1:
			continue
		var comp := PackedInt32Array([s])
		mark[s] = 2
		var head := 0
		while head < comp.size():
			var e := comp[head]
			head += 1
			for k in range(adj_start[e], adj_start[e + 1]):
				var j := adj_to[k]
				if mark[j] == 1:
					mark[j] = 2
					comp.append(j)
		_detach_component(b, comp)


func _detach_component(b: Building, comp: PackedInt32Array) -> void:
	# Non-structural elements standing on the ground right under a falling slab (partitions, doors)
	# would prop it up; in reality the slab crushes them, so they shatter now.
	# Likewise everything non-structural inside a storey whose verticals are all gone pancakes with it.
	var members: Dictionary = {}
	for e in comp:
		members[e] = true
	var failed: Dictionary = {}
	for e in comp:
		var st := b.data.storey[e]
		if b.data.role[e] == D.Role.ATTACHED and not failed.has(st):
			var any := false
			for v in b.solver.verticals_by_storey[st]:
				if b.solver.alive[v] == 1 or members.has(v):
					any = true   # still standing, or falling with the rest
					break
			failed[st] = not any
	var kept := PackedInt32Array()
	for e in comp:
		var crushed: bool = b.data.role[e] == D.Role.ATTACHED and (bool(failed.get(b.data.storey[e], false)) or (b.data.anchor[e] == 1 and _ceiling_in(b, e, members)))
		if crushed:
			var top := Vector3(0.0, b.data.dims[e].y * 0.45, 0.0)
			var hit := DamageHit.point((b.xform * b.cur_xf[e]) * top, Vector3.DOWN, b.hp[e] + 1.0, 0.0, DamageHit.Kind.CRUSH)
			hit.cause_id = b.cause
			destroy_element(b.id, e, hit, top, true)
		else:
			kept.append(e)
	comp = kept
	for e in comp:
		b.solver.remove(e, false)
		b.state[e] = DETACHED
		gone_mass += b.data.mass[e]
		_log_gone(b, e)
	var sag := _find_sag(b, comp)
	var delay0 := 0.0
	var use_pivot := false
	var ang := Vector3.ZERO
	var pivot := Vector3.ZERO
	if sag != null:
		_sags.append(sag)
		delay0 = sag.duration
		use_pivot = true
		ang = (b.xform.basis * sag.axis_local).normalized() * (2.0 * sag.max_angle / sag.duration)
		pivot = b.xform * sag.pivot_local
	var min_st := 1 << 20
	for e in comp:
		min_st = mini(min_st, b.data.storey[e])
	# Facade parts (ledges, cornices, awnings, balconies, chimneys, roof plant) fall on their own, a
	# balcony in one piece with its railings: inside a wall's cluster they would stick out of it, and when
	# that cluster settles and later breaks up, a ledge could be left hanging in the air.
	var structural := PackedInt32Array()
	var facade := PackedInt32Array()
	for e in comp:
		if b.data.kind[e] >= D.Kind.TRIM:
			facade.append(e)
		else:
			structural.append(e)
	var chunks := _split_chunks(b, structural, cluster_max_elements)
	if not facade.is_empty():
		chunks.append_array(_facade_groups(b, facade))
	var group := ReleaseGroup.new() if chunks.size() > 1 else null
	for ch in chunks:
		var st := 1 << 20
		for e in ch:
			st = mini(st, b.data.storey[e])
		var cb := ClusterBuild.new()
		cb.building = b.id
		cb.elems = ch
		cb.cause = b.cause
		cb.release_time = _time + delay0 + storey_release_delay * (st - min_st)
		cb.use_pivot = use_pivot
		cb.ang = ang
		cb.pivot = pivot
		cb.group = group
		if group != null:
			group.total += 1
		_builds.append(cb)


## True when a horizontal host directly above element e (its ceiling) is among members.
func _ceiling_in(b: Building, e: int, members: Dictionary) -> bool:
	var top := b.data.xf[e].origin.y + b.data.dims[e].y * 0.5
	for k in range(b.data.adj_start[e], b.data.adj_start[e + 1]):
		if b.data.adj_type[k] != D.Edge.ATTACHED_TO:
			continue
		var h := b.data.adj_to[k]
		if b.data.role[h] == HORZ and members.has(h):
			var bottom := b.data.xf[h].origin.y - b.data.dims[h].y * 0.5
			if absf(bottom - top) < 0.05:
				return true
	return false


## A failing horizontal region that still touches a supported neighbour swings down around the shared
## top edge before it lets go.
func _find_sag(b: Building, comp: PackedInt32Array) -> Sag:
	if comp.size() > max_sag_elements:
		return null
	var members: Dictionary = {}
	for e in comp:
		members[e] = true
	for e in comp:
		if b.data.role[e] != HORZ:
			continue
		for k in range(b.data.adj_start[e], b.data.adj_start[e + 1]):
			if b.data.adj_type[k] != LATERAL:
				continue
			var nb := b.data.adj_to[k]
			if members.has(nb) or b.solver.alive[nb] == 0 or b.solver.sup[nb] == 0:
				continue
			var ce := b.data.xf[e].origin
			var cn := b.data.xf[nb].origin
			var dir := cn - ce
			dir.y = 0.0
			if dir.length_squared() < 1e-6:
				continue
			var pv := (ce + cn) * 0.5
			pv.y = ce.y + b.data.dims[e].y * 0.5
			var axis := dir.normalized().cross(Vector3.UP)
			if axis.cross(ce - pv).y > 0.0:
				axis = -axis
			var s := Sag.new()
			s.building = b.id
			s.elems = comp
			s.pivot_local = pv
			s.axis_local = axis
			s.start = _time
			s.duration = sag_seconds
			s.max_angle = deg_to_rad(sag_degrees)
			return s
	return null


func _process_sags() -> void:
	for i in range(_sags.size() - 1, -1, -1):
		var s := _sags[i]
		var b := buildings[s.building]
		var t := clampf((_time - s.start) / s.duration, 0.0, 1.0)
		var rot := Basis(s.axis_local, s.max_angle * t * t)
		var about := Transform3D(rot, s.pivot_local - rot * s.pivot_local)
		for e in s.elems:
			if b.state[e] != DETACHED or b.inst[e] < 0:
				continue
			var nx := about * b.data.xf[e]
			b.cur_xf[e] = nx
			b.groups[b.group[e]].set_transform(b.inst[e], nx)
			if b.bodies[e].is_valid():
				PhysicsServer3D.body_set_state(b.bodies[e], PhysicsServer3D.BODY_STATE_TRANSFORM, b.xform * nx)
		if t >= 1.0:
			_sags.remove_at(i)


## Chunks are floor plates: a slab travels with the walls standing on it, never with the partitions,
## glass or columns under it (those would prop it up when it lands).
## Facade parts grouped by what holds them to each other (a balcony slab and its railings); most are alone.
func _facade_groups(b: Building, facade: PackedInt32Array) -> Array[PackedInt32Array]:
	var left := {}
	for e in facade:
		left[e] = true
	var out: Array[PackedInt32Array] = []
	var adj_start := b.data.adj_start
	var adj_to := b.data.adj_to
	for s in facade:
		if not left.has(s):
			continue
		left.erase(s)
		var g := PackedInt32Array([s])
		var head := 0
		while head < g.size():
			var e := g[head]
			head += 1
			for k in range(adj_start[e], adj_start[e + 1]):
				var j := adj_to[k]
				if left.has(j):
					left.erase(j)
					g.append(j)
		out.append(g)
	return out


func _split_chunks(b: Building, comp: PackedInt32Array, max_n: int) -> Array[PackedInt32Array]:
	var by_storey: Dictionary = {}
	for e in comp:
		var st := b.data.storey[e] + (1 if b.data.role[e] == HORZ else 0)
		if not by_storey.has(st):
			by_storey[st] = []
		(by_storey[st] as Array).append(e)
	var keys := by_storey.keys()
	keys.sort()
	var out: Array[PackedInt32Array] = []
	for st in keys:
		_bisect(b, PackedInt32Array(by_storey[st]), max_n, out)
	return out


func _bisect(b: Building, elems: PackedInt32Array, max_n: int, out: Array[PackedInt32Array]) -> void:
	if elems.size() <= max_n:
		out.append(elems)
		return
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := -mn
	for e in elems:
		var p := b.cur_xf[e].origin
		mn = mn.min(p)
		mx = mx.max(p)
	var axis := 0 if (mx.x - mn.x) >= (mx.z - mn.z) else 2
	var arr := Array(elems)
	var xfs := b.cur_xf
	arr.sort_custom(func(p: int, q: int) -> bool: return xfs[p].origin[axis] < xfs[q].origin[axis])
	var half := arr.size() >> 1
	_bisect(b, PackedInt32Array(arr.slice(0, half)), max_n, out)
	_bisect(b, PackedInt32Array(arr.slice(half)), max_n, out)


func _start_topple(b: Building, hinge: Dictionary) -> void:
	var f: int = hinge["storey"]
	var elems := PackedInt32Array()
	var loose := PackedInt32Array()
	for i in b.data.count():
		if b.state[i] != INTACT or b.solver.alive[i] == 0:
			continue
		var st := b.data.storey[i]
		if st > f or (st == f and b.data.role[i] == HORZ):
			elems.append(i)
		elif st == f and b.data.role[i] == D.Role.ATTACHED:
			loose.append(i)   # glass, partitions... of the failing storey hang below the hinge
	if elems.is_empty():
		return
	for e in elems:
		b.solver.remove(e, false)
		b.state[e] = DETACHED
		gone_mass += b.data.mass[e]
		_log_gone(b, e)
	if not loose.is_empty():
		_detach_component(b, loose)
	var a2: Vector2 = hinge["a"]
	var b2: Vector2 = hinge["b"]
	var out: Vector2 = hinge["out"]
	var pivot_local := Vector3((a2.x + b2.x) * 0.5, hinge["pivot_y"], (a2.y + b2.y) * 0.5)
	var axis_local := Vector3.UP.cross(Vector3(out.x, 0.0, out.y)).normalized()
	var cb := ClusterBuild.new()
	cb.building = b.id
	cb.elems = elems
	cb.cause = b.cause
	cb.release_time = _time
	cb.use_pivot = true
	cb.pivot = b.xform * pivot_local
	cb.ang = (b.xform.basis * axis_local).normalized() * topple_omega
	cb.big = true
	_builds.append(cb)
	topples += 1
	b.dirty = true
	building_toppled.emit(b.id, f)


func _process_builds(deadline: int) -> void:
	var i := 0
	while i < _builds.size():
		var cb := _builds[i]
		if cb.release_time > _time:
			i += 1
			continue
		if Time.get_ticks_usec() > deadline:
			return
		if _step_build(cb, deadline):
			_builds.remove_at(i)
		else:
			return


func _step_build(cb: ClusterBuild, deadline: int) -> bool:
	var b := buildings[cb.building]
	if cb.cluster == null and cb.single < 0:
		var list := PackedInt32Array()
		for e in cb.elems:
			if b.state[e] == DETACHED and b.inst[e] >= 0:
				list.append(e)
		if list.is_empty():
			_group_done(cb, false)
			return true
		if list.size() == 1 and not cb.big:
			cb.single = list[0]
		else:
			var c := DebrisCluster.new()
			var world: Array[Transform3D] = []
			for e in list:
				_append_element(c, b, e)
				world.append(b.xform * b.cur_xf[e])
			c.begin(b.id, list, world, b.xform.basis)
			cb.cluster = c
	if cb.cluster != null:
		var t0 := Time.get_ticks_usec()
		if not cb.cluster.build_step(deadline):
			prof_build_usec += Time.get_ticks_usec() - t0
			return false
		var t1 := Time.get_ticks_usec()
		cb.cluster.finish_visuals(crack_material)
		prof_build_usec += t1 - t0
		prof_visual_usec += Time.get_ticks_usec() - t1
	_group_done(cb, true)
	return true


## A build is constructed; activate it now, or together with the rest of its group.
func _group_done(cb: ClusterBuild, has_body: bool) -> void:
	if cb.group == null:
		if has_body:
			_activate_build(cb)
		return
	cb.group.total -= 1
	if has_body:
		cb.group.ready.append(cb)
	if cb.group.total == 0:
		for r in cb.group.ready:
			_activate_build(r)
		cb.group.ready.clear()


func _activate_build(cb: ClusterBuild) -> void:
	var b := buildings[cb.building]
	if cb.single >= 0:
		if b.state[cb.single] == DETACHED and b.inst[cb.single] >= 0:
			_detach_single(b, cb.single, cb)
		return
	var c := cb.cluster
	var t2 := Time.get_ticks_usec()
	var box := AABB()
	for k in c.elems.size():
		var e := c.elems[k]
		var half := b.data.dims[e] * 0.5
		var eb := (b.xform * b.cur_xf[e]) * AABB(-half, b.data.dims[e])
		box = eb if k == 0 else box.merge(eb)
		_remove_static(b, e, false)
	# Rubble recorded on these elements was queued by _remove_static (support_removed); this box query
	# also wakes sleeping debris on the block and rubble whose support was never recorded.
	debris.wake_box(Transform3D(Basis.IDENTITY, box.get_center()), box.size, box.position.y, 512)
	prof_remove_usec += Time.get_ticks_usec() - t2
	var lin := Vector3.ZERO
	var ang := Vector3.ZERO
	if cb.use_pivot and not cb.big:
		ang = cb.ang
		lin = ang.cross(c.body.transform.origin - cb.pivot)
	mass_detached += c.mass
	clusters_created += 1
	if cb.big:
		c.kinematic = true
		c.body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		c.body.freeze = true
	var s := debris.register_cluster(c, lin, ang, cb.cause)
	if cb.big:
		_start_hinge(b, c, s, cb)
	cluster_detached.emit(c.body, b.id, c.elems)


func _start_hinge(b: Building, c: DebrisCluster, s: int, cb: ClusterBuild) -> void:
	var tp := Topple.new()
	tp.cluster = c
	tp.slot = s
	tp.gen = debris.slot_gen(s)
	tp.pivot = cb.pivot
	tp.axis = cb.ang.normalized()
	tp.start_xf = c.body.global_transform
	tp.mass = c.mass
	tp.omega = cb.ang.length() * 0.25
	tp.building = b.id
	tp.ground_y = b.xform.origin.y
	var inertia := 0.0
	var top_theta := TOPPLE_MAX_ANGLE
	var g := tp.ground_y + 1.0 - tp.pivot.y
	var order: Array[Vector2] = []
	for i in c.elems.size():
		var r := tp.start_xf * (c.locals[i] * c.elem_com[i]) - tp.pivot
		var perp := r - tp.axis * r.dot(tp.axis)
		inertia += c.masses[i] * perp.length_squared()
		# Height of the element centre while rotating about the hinge: y(t) = A cos t + B sin t.
		var a_coef := r.y
		var b_coef := tp.axis.cross(r).y
		var rr := sqrt(a_coef * a_coef + b_coef * b_coef)
		var hit := TOPPLE_MAX_ANGLE + 1.0
		if rr > 1e-3 and absf(g / rr) <= 1.0:
			var phi := atan2(b_coef, a_coef)
			var d := acos(g / rr)
			for cand in [phi - d, phi + d, phi - d + TAU, phi + d - TAU]:
				if cand > 0.0 and cand < hit:
					hit = cand
		order.append(Vector2(hit, i))
	order.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	for o in order:
		tp.crush_order.append(int(o.y))
		tp.crush_theta.append(o.x)
	tp.inertia = maxf(inertia, 1.0)
	tp.theta_max = top_theta
	_topples.append(tp)


func _physics_process(delta: float) -> void:
	# Break-up edits the MultiMeshes of moving clusters, which must happen on the physics tick.
	var t0 := Time.get_ticks_usec()
	_process_breaking(t0 + int(logic_budget_ms * 250.0))
	_process_topples(delta)
	physics_usec = Time.get_ticks_usec() - t0   # includes the hinge phase (grinding is the costly part)


## Hinge phase of every toppling block (see Topple).
func _process_topples(delta: float) -> void:
	for i in range(_topples.size() - 1, -1, -1):
		var tp := _topples[i]
		if not debris.is_live(tp.slot, tp.gen):
			_topples.remove_at(i)
			continue
		var body := tp.cluster.body
		var com := body.global_transform * body.center_of_mass
		var torque := (com - tp.pivot).cross(Vector3(0.0, -9.81 * tp.cluster.mass, 0.0)).dot(tp.axis)
		tp.omega = maxf(tp.omega + torque / tp.inertia * delta, 0.05)
		tp.theta += tp.omega * delta
		var rot := Basis(tp.axis, tp.theta)
		body.global_transform = Transform3D(rot, tp.pivot - rot * tp.pivot) * tp.start_xf
		_topple_crush(tp, 32)
		if not debris.is_live(tp.slot, tp.gen):
			_topples.remove_at(i)   # everything was ground in
			continue
		if tp.theta >= tp.theta_max or tp.cluster.alive < 8:
			_topple_sweep(tp)
			_topples.remove_at(i)
			if not debris.is_live(tp.slot, tp.gen):
				continue
			body.freeze = false
			var w := tp.axis * tp.omega
			body.angular_velocity = w
			body.linear_velocity = w.cross(body.global_transform * body.center_of_mass - tp.pivot)
			debris.set_prev_velocity(tp.slot, body.linear_velocity, w)
			tp.cluster.kinematic = false
			# The block meets the ground now. A building is not a rigid body: it breaks up from the leading
			# end instead of landing (or coming to rest standing on its end) as one piece.
			if tp.cluster.alive > cluster_max_elements:
				_begin_break(tp.cluster, _leading_point(tp), 0.5 * tp.inertia * tp.omega * tp.omega)


## Centre of the alive element farthest from the hinge: the end of a toppling block that lands first.
func _leading_point(tp: Topple) -> Vector3:
	var c := tp.cluster
	var t := c.body.global_transform
	var best := t.origin
	var best_d := -1.0
	for i in c.alive_indices():
		var p := t * (c.locals[i] * c.elem_com[i])
		var d := p.distance_squared_to(tp.pivot)
		if d > best_d:
			best_d = d
			best = p
	return best


## The leading floors of a toppling block are ground into the earth as it rotates past them, so the
## hinge keeps turning instead of the block landing flat on its base. Ground-in elements become static
## rubble right away (coarse fracture cells when that pattern is ready), which keeps the body count flat.
func _topple_crush(tp: Topple, limit: int) -> void:
	var c := tp.cluster
	var batch := PackedInt32Array()
	while tp.crush_next < tp.crush_order.size() and tp.crush_theta[tp.crush_next] <= tp.theta and batch.size() < limit:
		var i := tp.crush_order[tp.crush_next]
		tp.crush_next += 1
		if c.owners[i] >= 0:
			batch.append(i)
	_grind(tp, batch)


## Before the block turns dynamic, everything still reaching below ground level is ground in too, so
## the solver does not start from a deep penetration (that would stop the block dead).
func _topple_sweep(tp: Topple) -> void:
	var c := tp.cluster
	var b := buildings[tp.building]
	var t := c.body.global_transform
	var batch := PackedInt32Array()
	for i in c.alive_indices():
		var xf := t * c.locals[i]
		var h := b.data.dims[c.elems[i]] * 0.5
		var low := xf.origin.y - absf(xf.basis.x.y) * h.x - absf(xf.basis.y.y) * h.y - absf(xf.basis.z.y) * h.z
		if low < tp.ground_y - 0.05:
			batch.append(i)
	_grind(tp, batch)


func _grind(tp: Topple, batch: PackedInt32Array) -> void:
	var c := tp.cluster
	var b := buildings[tp.building]
	if batch.is_empty():
		return
	var t := c.body.global_transform
	var xfs: Array[Transform3D] = []
	for i in batch:
		xfs.append(t * c.locals[i])
	var slot := c.slot
	c.peel(batch)
	debris.set_slot_mass(slot, c.mass)
	if c.alive == 0:
		debris.release(slot)   # all of it is rubble now; an empty body would fall forever
	for k in batch.size():
		var i := batch[k]
		var e := c.elems[i]
		var mname := b.data.material_name(e)
		var pat := fracture.get_pattern(b.data.dims[e], b.data.shape[e], mname, FractureLibrary.COARSE_VARIANT, true)
		if pat != null:
			var density := MaterialDB.density(mname)
			# Small-rubble layer: the still-rotating block must not come to rest on its own ground-in base.
			# Cells above the ground are set down onto it rather than left where the block passed; cells that
			# already reach the ground need no cast.
			for cell in pat.cells:
				var low := (xfs[k] * cell.mesh.get_aabb()).position.y
				debris.add_rubble(cell.mesh, cell.shape, xfs[k], cell.volume * density, cell.centroid, mname, -1, -1, true, low > tp.ground_y + 0.05)
			b.state[e] = DESTROYED
			b.hp[e] = 0.0
			mass_fractured += b.data.mass[e]
			element_destroyed.emit(b.id, e, c.cause)
		else:
			debris.add_rubble(c.meshes[i], c.shapes[i], xfs[k], c.masses[i], c.elem_com[i], mname, b.id, e, true, true)
		pancaked += 1
	if fx != null and not batch.is_empty():
		var p0 := xfs[0].origin
		fx.impact_dust(Vector3(p0.x, tp.ground_y, p0.z), clampf(batch.size() / 12.0, 0.3, 1.0), b.data.material_name(c.elems[batch[0]]))


func _append_element(c: DebrisCluster, b: Building, e: int) -> void:
	var mname := b.data.material_name(e)
	c.meshes.append(ElementLibrary.mesh(b.data.dims[e], b.data.shape[e], mname))
	c.shapes.append(ElementLibrary.collision_shape(b.data.dims[e], b.data.shape[e]))
	c.masses.append(b.data.mass[e])
	c.elem_com.append(D.shape_centroid(b.data.dims[e], b.data.shape[e]))
	c.customs.append(_crack_color(b, e))
	c.shadows.append(0 if b.data.is_glass(e) else 1)


func _detach_single(b: Building, e: int, cb: ClusterBuild) -> void:
	var xf := b.xform * b.cur_xf[e]
	var com_local := D.shape_centroid(b.data.dims[e], b.data.shape[e])
	var lin := Vector3.ZERO
	var ang := Vector3.ZERO
	if cb.use_pivot:
		ang = cb.ang
		lin = ang.cross(xf * com_local - cb.pivot)
	_remove_static(b, e)
	var mname := b.data.material_name(e)
	mass_detached += b.data.mass[e]
	debris.spawn_element(b.id, e, ElementLibrary.mesh(b.data.dims[e], b.data.shape[e], mname),
		ElementLibrary.collision_shape(b.data.dims[e], b.data.shape[e]), xf, com_local, b.data.mass[e], lin, ang, mname, cb.cause)


# --------------------------------------------------------------------------------------------------
# Falling bodies: impacts and break-up
# --------------------------------------------------------------------------------------------------

func on_cluster_impact(slot: int, contact: Vector3, energy: float, dv: float, pre_v: Vector3 = Vector3.ZERO, pre_w: Vector3 = Vector3.ZERO) -> void:
	if dv < break_dv:
		return
	var c := debris.cluster_of(slot)
	if c == null or c.freezing or c.kinematic:
		return
	# An impact at the far end of a long body (a toppling tower's top) crushes locally; the rest of the
	# building is not rigid and keeps its motion.
	var com := c.body.global_transform * c.body.center_of_mass
	var extent := 0.0
	for i in mini(c.elems.size(), 64):
		extent = maxf(extent, c.locals[i].origin.length())
	var end_impact := contact.distance_to(com) > maxf(extent * 0.45, 6.0)
	_pancake(c, energy * pancake_energy_factor, contact)
	if debris.cluster_of(slot) == c:
		_begin_break(c, contact, energy)
		if end_impact and c.breaking:
			c.has_pre = true
			c.pre_v = pre_v
			c.pre_w = pre_w
			c.pre_com = com


## A floor plate that lands hard crushes the walls of the storey directly under its footprint
## (static or falling, any building), nearest to the impact first, until its impact energy is spent.
## Energy left over crushes the body's own lowest walls that carry a floor above them, so a falling
## multi-storey block pancakes storey by storey instead of landing as one rigid piece. This is what
## turns a soft-storey drop into a progressive collapse; contact forces alone cannot, because rigid
## walls carry any static load.
func _pancake(c: DebrisCluster, energy: float, contact: Vector3) -> void:
	var b := buildings[c.building]
	var t := c.body.global_transform
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var plate := false
	for i in c.alive_indices():
		var e := c.elems[i]
		if b.data.role[e] != HORZ:
			continue
		var half := b.data.dims[e] * 0.5
		var box := (t * c.locals[i]) * AABB(-half, b.data.dims[e])
		lo = lo.min(box.position)
		hi = hi.max(box.end)
		plate = true
	if not plate:
		return
	var size := Vector3(hi.x - lo.x - 0.3, PANCAKE_DEPTH, hi.z - lo.z - 0.3)
	if size.x < 0.3 or size.z < 0.3:
		return
	var centre := Vector3((lo.x + hi.x) * 0.5, lo.y - PANCAKE_DEPTH * 0.5, (lo.z + hi.z) * 0.5)
	_pancake_box.size = size
	_pancake_query.shape = _pancake_box
	_pancake_query.transform = Transform3D(Basis.IDENTITY, centre)
	_pancake_query.collision_mask = Layers.STRUCTURE | Layers.DEBRIS
	_pancake_query.exclude = [c.body.get_rid()]
	var query_box := AABB(centre - size * 0.5, size)
	var victims: Array = []   # [distance, kind, building, element, slot, local index]
	var seen: Dictionary = {}   # results come once per overlapping shape of a compound body
	for r in get_world_3d().direct_space_state.intersect_shape(_pancake_query, 128):
		var rid: RID = r["rid"]
		if seen.has(rid):
			continue
		seen[rid] = true
		if _static_by_rid.has(rid):
			var uid: int = _static_by_rid[rid]
			var bb := buildings[uid >> 16]
			var ee := uid & 0xFFFF
			if bb.data.role[ee] != HORZ and bb.state[ee] == INTACT:
				victims.append([(bb.xform * bb.cur_xf[ee].origin).distance_to(contact), 0, bb.id, ee, -1, -1])
			continue
		var s := debris.slot_of_rid(rid)
		if s < 0:
			continue
		match debris.kind_of(s):
			DebrisManager.Kind.CLUSTER:
				var oc := debris.cluster_of(s)
				if oc == null or oc.kinematic or oc.freezing:
					continue
				var ob := buildings[oc.building]
				var ot := oc.body.global_transform
				for i in oc.alive_indices():
					var ee := oc.elems[i]
					var p := ot * (oc.locals[i] * oc.elem_com[i])
					if ob.data.role[ee] != HORZ and query_box.has_point(p):
						victims.append([p.distance_to(contact), 1, ob.id, ee, s, i])
			DebrisManager.Kind.ELEMENT:
				var own := debris.owner_element(s)
				if own.x >= 0 and buildings[own.x].data.role[own.y] != HORZ and buildings[own.x].state[own.y] == DETACHED:
					victims.append([debris.body_of(s).global_position.distance_to(contact), 2, own.x, own.y, s, -1])
	victims.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	# Own walls of the lowest storey that still has a floor above it inside this body.
	var own_lowest := 1 << 20
	var top_floor := -1
	for i in c.alive_indices():
		var e := c.elems[i]
		if b.data.role[e] == HORZ:
			top_floor = maxi(top_floor, b.data.storey[e])
		else:
			own_lowest = mini(own_lowest, b.data.storey[e])
	if own_lowest <= top_floor and own_lowest < (1 << 20):
		var own_victims: Array = []
		for i in c.alive_indices():
			var e := c.elems[i]
			if b.data.role[e] != HORZ and b.data.storey[e] == own_lowest:
				own_victims.append([(t * (c.locals[i] * c.elem_com[i])).distance_to(contact), 1, b.id, e, c.slot, i])
		own_victims.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		victims.append_array(own_victims)
	var left := energy
	var peel_lists: Dictionary = {}   # cluster slot -> PackedInt32Array of local indices
	# One landing crushes at most this many walls (nearest first): a whole toppled block hitting the ground
	# at once would otherwise spawn and fracture hundreds of elements in a single physics tick.
	var crushed_max := PANCAKE_MAX_VICTIMS
	for v in victims:
		var vb := buildings[v[2]]
		var ve: int = v[3]
		var need := vb.hp[ve]
		if left <= 0.0 or crushed_max <= 0:
			break
		crushed_max -= 1
		if int(v[1]) == 0:
			# Intact element: the landing floor deals CRUSH damage through the router like any hit.
			var spend := minf(left, need)
			left -= spend
			var rid := vb.bodies[ve]
			if rid.is_valid():
				var top := Vector3(0.0, vb.data.dims[ve].y * 0.45, 0.0)
				var hit := DamageHit.point((vb.xform * vb.cur_xf[ve]) * top, Vector3.DOWN, spend, 0.0, DamageHit.Kind.CRUSH)
				hit.cause_id = c.cause
				DamageRouter.apply_hit(hit, null, rid)
				if vb.state[ve] != INTACT:
					pancaked += 1
			continue
		if left < need:
			vb.hp[ve] -= left
			left = 0.0
			break
		left -= need
		vb.hp[ve] = 0.0
		pancaked += 1
		match int(v[1]):
			1:
				var lst: PackedInt32Array = peel_lists.get(v[4], PackedInt32Array())
				lst.append(v[5])
				peel_lists[v[4]] = lst
			_:
				_queue_body_fracture(v[4], vb, ve, debris.body_of(v[4]).global_position, Vector3.DOWN, 0.0, c.cause, true)
	for s in peel_lists:
		var oc := debris.cluster_of(s)
		if oc == null:
			continue
		var ob := buildings[oc.building]
		var ot := oc.body.global_transform
		var ov := oc.body.linear_velocity
		var ow := oc.body.angular_velocity
		var ocom := ot * oc.body.center_of_mass
		var lst: PackedInt32Array = peel_lists[s]
		var xfs: Array[Transform3D] = []
		for i in lst:
			xfs.append(ot * oc.locals[i])
		oc.peel(lst)
		debris.set_slot_mass(oc.slot, oc.mass)
		for k in lst.size():
			var i := lst[k]
			var ee := oc.elems[i]
			var ns := debris.spawn_element(ob.id, ee, oc.meshes[i], oc.shapes[i], xfs[k], oc.elem_com[i], oc.masses[i],
				ov + ow.cross(xfs[k] * oc.elem_com[i] - ocom), ow, ob.data.material_name(ee), c.cause)
			_queue_body_fracture(ns, ob, ee, xfs[k].origin, Vector3.DOWN, 0.0, c.cause, true)
		var rest := oc.alive_indices()
		if rest.size() == 1:
			_peel_off(oc, ob, rest, ot, ov, ow, ocom)
		if oc.alive == 0:
			debris.release(oc.slot)


func on_cluster_damage(slot: int, hit: DamageHit) -> void:
	var c := debris.cluster_of(slot)
	if c == null or c.freezing or c.kinematic:
		return
	_damage_cluster_element(c, hit)
	if hit.kind != DamageHit.Kind.CRUSH and hit.energy >= 20000.0 and debris.cluster_of(slot) == c:
		_begin_break(c, hit.position, hit.energy)


## The element nearest to the hit takes its full energy (a floor landing on walls breaks the walls it
## lands on); when it fails it is peeled off and fractured.
func _damage_cluster_element(c: DebrisCluster, hit: DamageHit) -> void:
	var b := buildings[c.building]
	var t := c.body.global_transform
	var best := -1
	var best_d := 1.0e9
	for i in c.alive_indices():
		var lp := (t * c.locals[i]).affine_inverse() * hit.position
		var h := b.data.dims[c.elems[i]] * 0.5
		var d := lp.distance_squared_to(lp.clamp(-h, h))
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return
	var e := c.elems[best]
	var mname := b.data.material_name(e)
	b.hp[e] -= hit.energy * _kind_factor(hit.kind, mname)
	if b.hp[e] > 0.0:
		return
	var v := c.body.linear_velocity
	var w := c.body.angular_velocity
	var com_w := t * c.body.center_of_mass
	var xf := t * c.locals[best]
	c.peel(PackedInt32Array([best]))
	debris.set_slot_mass(c.slot, c.mass)
	var s := debris.spawn_element(b.id, e, c.meshes[best], c.shapes[best], xf, c.elem_com[best], c.masses[best],
		v + w.cross(xf * c.elem_com[best] - com_w), w, mname, hit.cause_id)
	var crushed := hit.kind == DamageHit.Kind.CRUSH or hit.kind == DamageHit.Kind.BLUNT
	_queue_body_fracture(s, b, e, hit.position, hit.direction, 0.0 if crushed else hit.impulse, hit.cause_id, crushed)
	var rest := c.alive_indices()
	if rest.size() == 1:
		_peel_off(c, b, rest, t, v, w, com_w)
	if c.alive == 0:
		debris.release(c.slot)


func _begin_break(c: DebrisCluster, point: Vector3, energy: float) -> void:
	if c == null or c.breaking or c.freezing or c.kinematic:
		return
	c.breaking = true
	c.break_point = point
	c.break_energy = energy
	c.has_pre = false
	_breaking.append(c)
	if fx != null:
		var b := buildings[c.building]
		fx.impact_dust(point, clampf(energy / 1.5e6, 0.2, 1.0), b.data.material_name(c.elems[0]))


func _process_breaking(deadline: int) -> void:
	var i := 0
	while i < _breaking.size():
		if Time.get_ticks_usec() > deadline:
			return
		var c := _breaking[i]
		if c.slot < 0 or debris.cluster_of(c.slot) != c:
			_breaking.remove_at(i)
			continue
		if _peel_step(c, deadline):
			c.breaking = false
			_breaking.remove_at(i)
		else:
			i += 1


## Peels groups off a breaking cluster: first the elements around the impact (loose, maybe fractured),
## then connected chunks nearest to the impact until the remainder is small. True when finished.
func _peel_step(c: DebrisCluster, deadline: int) -> bool:
	var b := buildings[c.building]
	var body := c.body
	var t := body.global_transform
	var v := body.linear_velocity
	var w := body.angular_velocity
	var com_w := t * body.center_of_mass
	var alive := c.alive_indices()
	if c.break_energy >= 0.0:
		# Impact zone: elements near the contact come loose; those that took enough energy fracture.
		var r := clampf(1.0 + pow(c.break_energy, 1.0 / 3.0) / 30.0, 1.5, 4.5)
		var near := PackedInt32Array()
		var dists := PackedFloat32Array()
		for i in alive:
			var d := (t * c.locals[i]).origin.distance_to(c.break_point)
			if d < r:
				near.append(i)
				dists.append(d)
		while near.size() > 12:
			var far := 0
			for k in near.size():
				if dists[k] > dists[far]:
					far = k
			near.remove_at(far)
			dists.remove_at(far)
		var share := c.break_energy / maxf(1.0, near.size())
		c.break_energy = -1.0
		# Each chunk is built in one physics tick, so its size bounds the cost of that tick.
		c.chunk_max = clampi(alive.size() >> 2, 6, mini(cluster_max_elements, break_chunk_max))
		for i in near:
			var e := c.elems[i]
			var xf := t * c.locals[i]
			c.peel(PackedInt32Array([i]))
			debris.set_slot_mass(c.slot, c.mass)
			var mname := b.data.material_name(e)
			var com_e := xf * c.elem_com[i]
			var s := debris.spawn_element(b.id, e, c.meshes[i], c.shapes[i], xf, c.elem_com[i], c.masses[i], v + w.cross(com_e - com_w), w, mname, c.cause)
			b.hp[e] -= share * _kind_factor(DamageHit.Kind.BLUNT, mname)
			if b.hp[e] <= 0.0 or b.data.is_glass(e):
				_queue_body_fracture(s, b, e, c.break_point, Vector3.DOWN, 0.0, c.cause, true)
		alive = c.alive_indices()
	var chunk_max := c.chunk_max
	if c.has_pre:
		v = c.pre_v
		w = c.pre_w
		com_w = c.pre_com
	while alive.size() > chunk_max:
		if Time.get_ticks_usec() > deadline:
			return false
		var seed_i := alive[0]
		var best := 1.0e9
		for i in alive:
			var d := (t * c.locals[i]).origin.distance_squared_to(c.break_point)
			if d < best:
				best = d
				seed_i = i
		var chunk := _grow_chunk(c, b, seed_i, alive, chunk_max)
		_peel_off(c, b, chunk, t, v, w, com_w)
		alive = c.alive_indices()
	if alive.size() == 1:
		_peel_off(c, b, alive, t, v, w, com_w)   # a lone element continues as a fracturable element body
	if c.alive == 0:
		debris.release(c.slot)
	elif c.has_pre:
		c.body.linear_velocity = v + w.cross(t * c.body.center_of_mass - com_w)
		c.body.angular_velocity = w
		c.has_pre = false
	return true


## Connected group of up to max_n alive local indices around seed (building adjacency).
func _grow_chunk(c: DebrisCluster, b: Building, seed_i: int, alive: PackedInt32Array, max_n: int) -> PackedInt32Array:
	var local_of: Dictionary = {}
	for i in alive:
		local_of[c.elems[i]] = i
	var out := PackedInt32Array([seed_i])
	var taken: Dictionary = {seed_i: true}
	var head := 0
	while head < out.size() and out.size() < max_n:
		var e := c.elems[out[head]]
		head += 1
		for k in range(b.data.adj_start[e], b.data.adj_start[e + 1]):
			var li: int = local_of.get(b.data.adj_to[k], -1)
			if li >= 0 and not taken.has(li):
				taken[li] = true
				out.append(li)
				if out.size() >= max_n:
					break
	return out


func _peel_off(c: DebrisCluster, b: Building, idx: PackedInt32Array, t: Transform3D, v: Vector3, w: Vector3, com_w: Vector3) -> void:
	if idx.size() == 1:
		var i := idx[0]
		var e := c.elems[i]
		var xf := t * c.locals[i]
		c.peel(idx)
		debris.set_slot_mass(c.slot, c.mass)
		debris.spawn_element(b.id, e, c.meshes[i], c.shapes[i], xf, c.elem_com[i], c.masses[i], v + w.cross(xf * c.elem_com[i] - com_w), w, b.data.material_name(e), c.cause)
		return
	var nc := DebrisCluster.new()
	var elems := PackedInt32Array()
	var world: Array[Transform3D] = []
	for i in idx:
		elems.append(c.elems[i])
		world.append(t * c.locals[i])
		nc.meshes.append(c.meshes[i])
		nc.shapes.append(c.shapes[i])
		nc.masses.append(c.masses[i])
		nc.elem_com.append(c.elem_com[i])
		nc.customs.append(c.customs[i])
		nc.shadows.append(c.shadows[i])
	c.peel(idx)
	debris.set_slot_mass(c.slot, c.mass)
	nc.begin(c.building, elems, world, t.basis)
	nc.build_step(1 << 62)
	nc.finish_visuals(crack_material)
	var com := nc.body.transform.origin
	debris.register_cluster(nc, v + w.cross(com - com_w), w, c.cause)


func on_element_impact(slot: int, contact: Vector3, energy: float, _dv: float) -> void:
	var o := debris.owner_element(slot)
	if o.x < 0:
		return
	var b := buildings[o.x]
	var e := o.y
	if b.state[e] != DETACHED:
		return
	var mname := b.data.material_name(e)
	b.hp[e] -= energy * _kind_factor(DamageHit.Kind.BLUNT, mname)
	if b.hp[e] <= 0.0 or (b.data.is_glass(e) and energy > 5.0):
		_queue_body_fracture(slot, b, e, contact, Vector3.ZERO, 0.0, 0)


func on_element_damage(slot: int, hit: DamageHit) -> void:
	var o := debris.owner_element(slot)
	if o.x < 0:
		return
	var b := buildings[o.x]
	var e := o.y
	if b.state[e] != DETACHED:
		return
	var mname := b.data.material_name(e)
	b.hp[e] -= hit.energy * _kind_factor(hit.kind, mname)
	if b.hp[e] <= 0.0 or (b.data.is_glass(e) and hit.energy > 3.0):
		var crushed := hit.kind == DamageHit.Kind.CRUSH
		_queue_body_fracture(slot, b, e, hit.position, hit.direction, 0.0 if crushed else hit.impulse, hit.cause_id, crushed)


func _queue_body_fracture(slot: int, b: Building, e: int, point: Vector3, dir: Vector3, impulse: float, cause: int, crushed: bool = false) -> void:
	var body := debris.body_of(slot)
	if body == null or b.state[e] != DETACHED:
		return
	b.state[e] = PENDING
	var job := FractureJob.new()
	job.crushed = crushed
	job.building = b.id
	job.element = e
	job.source = SRC_BODY
	job.slot = slot
	job.gen = debris.slot_gen(slot)
	var h := b.data.dims[e] * 0.5
	job.local_hit = (body.global_transform.affine_inverse() * point).clamp(-h, h)
	job.variant = FractureLibrary.COARSE_VARIANT if crushed else FractureLibrary.variant_for(b.data.dims[e], job.local_hit)
	if crushed:
		# Until its pieces exist, a crushed element must not prop anything up.
		body.collision_layer = Layers.DEBRIS_SMALL
		body.collision_mask = DebrisManager.MASK_T2
	job.dir = dir
	job.impulse = impulse
	job.cause = cause
	_fracture_jobs.append(job)
	fracture.get_pattern(b.data.dims[e], b.data.shape[e], b.data.material_name(e), job.variant)


# --------------------------------------------------------------------------------------------------
# Queries (tests, other modules)
# --------------------------------------------------------------------------------------------------

# --------------------------------------------------------------------------------------------------
# World rewind (Timeline)
# --------------------------------------------------------------------------------------------------

func _log_gone(b: Building, e: int) -> void:
	_lose(b)
	_gone_t.append(_time)
	_gone_b.append(b.id)
	_gone_e.append(e)


func _prune_gone_log() -> void:
	if _gone_t.is_empty() or _gone_t[0] >= _time - REWIND_WINDOW:
		return
	var keep := _gone_t.bsearch(_time - REWIND_WINDOW)
	_gone_t = _gone_t.slice(keep)
	_gone_b = _gone_b.slice(keep)
	_gone_e = _gone_e.slice(keep)


## Stops the frame logic and drops the work in progress (fractures, cluster builds, sags, topples, crushes):
## whatever it was about is brought back by the rewind or stays as it is.
func rewind_begin() -> void:
	rewinding = true
	_rw_now = _time
	_fracture_jobs.clear()
	_builds.clear()
	_breaking.clear()
	_sags.clear()
	_topples.clear()
	_crush_b.clear()
	_crush_e.clear()
	_crush_t.clear()
	_crush_c.clear()
	for b in buildings:
		b.failing.clear()


## Brings back, newest first, every element that left after `depth` seconds before the rewind began.
func rewind_to(depth: float) -> int:
	var cut := _rw_now - depth
	var n := 0
	while not _gone_t.is_empty() and _gone_t[_gone_t.size() - 1] > cut:
		var last := _gone_t.size() - 1
		_revive(buildings[_gone_b[last]], _gone_e[last])
		_gone_t.resize(last)
		_gone_b.resize(last)
		_gone_e.resize(last)
		n += 1
	return n


## The rewind stops `depth` seconds back: the clock goes back with it and the logic runs again (the
## support of everything that came back is checked on the next frames).
func rewind_end(depth: float) -> void:
	rewind_to(depth)
	_time = _rw_now - depth
	rewinding = false


func _revive(b: Building, e: int) -> void:
	if b.state[e] == INTACT:
		return
	b.state[e] = INTACT
	b.hp[e] = b.data.max_hp[e]
	b.damage_pt[e] = Vector3.ZERO
	b.cur_xf[e] = b.data.xf[e]
	var g := b.groups[b.group[e]]
	if b.inst[e] < 0:
		b.inst[e] = g.add(e, b.data.xf[e])
	else:
		g.set_transform(b.inst[e], b.data.xf[e])
		g.set_custom(b.inst[e], Color(0, 0, 0, 0))
	if b.awake:
		_create_body(b, e)
	elif not b.proxy.is_valid():
		_make_proxy(b)
	b.solver.revive(e)
	gone_mass -= b.data.mass[e]
	b.dirty = true
	b.last_active = _time
	revived += 1
	b.gone_count = maxi(b.gone_count - 1, 0)
	if b.gone_count == 0:
		_far_show(b, true)


# --------------------------------------------------------------------------------------------------
# Far LOD
# --------------------------------------------------------------------------------------------------

func _process_far_queue() -> void:
	var merged := 0
	while not _far_queue.is_empty():
		var bid := _far_queue[_far_queue.size() - 1]
		var b := buildings[bid]
		var key := b.data.get_instance_id()
		if not _far_meshes.has(key):
			if merged >= 1:
				return
			_far_meshes[key] = _merge_design(b.data)
			merged += 1
		_far_queue.resize(_far_queue.size() - 1)
		var mi := MeshInstance3D.new()
		mi.name = "FarLOD"
		mi.mesh = _far_meshes[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_begin = far_lod_distance
		mi.visibility_range_begin_margin = 6.0
		b.root.add_child(mi)
		b.far = mi
		_far_show(b, b.gone_count == 0)


## Everything one sees of a design from afar, merged into one surface per material.
func _merge_design(d: BuildingData) -> ArrayMesh:
	var tools := {}
	for i in d.count():
		if FAR_HIDDEN_KINDS.has(d.kind[i]):
			continue
		var mname := d.material_name(i)
		var st: SurfaceTool = tools.get(mname)
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mname] = st
		var m := ElementLibrary.mesh(d.dims[i], d.shape[i], mname)
		for si in m.get_surface_count():
			st.append_from(m, si, d.xf[i])
	var out := ArrayMesh.new()
	for mname: StringName in tools:
		(tools[mname] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, ElementLibrary.surface_material(mname))
	return out


## on: the far mesh takes over beyond far_lod_distance; off: the elements are drawn at every distance.
func _far_show(b: Building, on: bool) -> void:
	if b.far == null:
		return
	b.far.visible = on
	for g in b.groups:
		g.mmi.visibility_range_end = far_lod_distance if on else 0.0
		g.mmi.visibility_range_end_margin = 6.0 if on else 0.0


func _lose(b: Building) -> void:
	b.gone_count += 1
	if b.gone_count == 1:
		_far_show(b, false)


## Saved games: the elements of a building that are no longer standing.
func removed_elements(bid: int) -> PackedInt32Array:
	var b := buildings[bid]
	var out := PackedInt32Array()
	for e in b.state.size():
		if b.state[e] != INTACT:
			out.append(e)
	return out


## Saved games: takes the elements that were gone out of a building, without fracture, debris or
## effects. Whatever is left without support afterwards falls as usual.
func restore_removed(bid: int, elems: PackedInt32Array) -> void:
	if bid < 0 or bid >= buildings.size():
		return
	var b := buildings[bid]
	var taken := 0
	for e in elems:
		if e < 0 or e >= b.state.size() or b.state[e] != INTACT:
			continue
		b.state[e] = DESTROYED
		b.hp[e] = 0.0
		gone_mass += b.data.mass[e]
		_remove_static(b, e, false)
		b.solver.remove(e, false)
		_lose(b)
		taken += 1
	if taken == 0:
		return
	b.dirty = true
	if not b.awake:
		for i in b.state.size():
			if b.state[i] == INTACT:
				return
		_drop_proxy(b)


func count_intact(bid: int) -> int:
	var c := 0
	for s in buildings[bid].state:
		if s == INTACT:
			c += 1
	return c


func count_unanchored(bid: int) -> int:
	return buildings[bid].solver.count_unanchored()


func intact_mass(bid: int) -> float:
	var b := buildings[bid]
	var m := 0.0
	for i in b.data.count():
		if b.state[i] == INTACT:
			m += b.data.mass[i]
	return m


## Element ids of a building filtered by storey (-1 = any) and kinds (empty = any), intact only.
func find_elements(bid: int, storey: int, kinds: Array = []) -> PackedInt32Array:
	var b := buildings[bid]
	var out := PackedInt32Array()
	for i in b.data.count():
		if b.state[i] != INTACT:
			continue
		if storey >= 0 and b.data.storey[i] != storey:
			continue
		if not kinds.is_empty() and not kinds.has(int(b.data.kind[i])):
			continue
		out.append(i)
	return out


func element_world_transform(bid: int, e: int) -> Transform3D:
	var b := buildings[bid]
	return b.xform * b.cur_xf[e]


func element_rid(bid: int, e: int) -> RID:
	return buildings[bid].bodies[e]


func stats() -> Dictionary:
	return {
		"frame_usec": frame_usec, "damage_usec": last_damage_usec, "fracture_jobs": _fracture_jobs.size(),
		"builds": _builds.size(), "breaking": _breaking.size(), "elements_destroyed": elements_destroyed,
		"clusters_created": clusters_created, "patterns": fracture.pattern_count(), "pattern_jobs": fracture.pending_count(),
		"topples": topples, "storeys_failed": storeys_failed, "coarse_fractures": coarse_fractures,
		"buildings": buildings.size(), "bodies": bodies_alive, "waking": _waking.size(), "wakes": wakes, "sleeps": sleeps,
		"built_t": roundi(built_mass / 1000.0), "gone_t": roundi(gone_mass / 1000.0),
	}


func building_count() -> int:
	return buildings.size()


## Axis-aligned world rectangle (x, z) that the building covered when it was built. Placement code
## (nature, props, parked cars) keeps clear of it.
func building_footprint(bid: int) -> Rect2:
	var b := buildings[bid]
	var box := b.xform * b.data.bounds
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


# --------------------------------------------------------------------------------------------------
# Doors (2026-11-17): every building can be entered
# --------------------------------------------------------------------------------------------------

var _door_scan := 0.0
var doors_opened := 0


## A door swings open (away from Trophe, round its hinge) as she comes up to it and closes once she is a
## few steps away; a roller door rolls up. Only standing doors of awake buildings near her.
func _update_doors(delta: float) -> void:
	_door_scan -= delta
	if _door_scan > 0.0:
		return
	_door_scan = 0.1
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var cat: Vector3 = p.global_position
	var c2 := Vector2(cat.x, cat.z)
	for b in buildings:
		if b.doors.is_empty() or not b.awake:
			continue
		var fp := Rect2(b.world_box.position.x, b.world_box.position.z, b.world_box.size.x, b.world_box.size.z)
		if not fp.grow(6.0).has_point(c2):
			continue
		for e in b.doors:
			if b.state[e] != INTACT or b.inst[e] < 0:
				continue
			var at := b.xform * b.data.xf[e].origin
			var d := Vector2(at.x - cat.x, at.z - cat.z).length()
			var open: bool = b.door_open.has(e)
			if not open and d < 1.9 and absf(at.y - cat.y) < 2.2:
				_swing_door(b, e, true, cat)
			elif open and d > 3.5:
				_swing_door(b, e, false, cat)


func _swing_door(b: Building, e: int, open: bool, cat: Vector3) -> void:
	var base: Transform3D = b.data.xf[e]
	var nx := base
	if open:
		b.door_open[e] = true
		doors_opened += 1
		var size: Vector3 = b.data.dims[e]
		if String(b.data.material_name(e)) == "roller_door":
			nx = Transform3D(base.basis, base.origin + Vector3.UP * size.y * 0.85)   # rolls up
		else:
			var to_cat := (b.xform * base).affine_inverse() * cat
			var turn := Basis(Vector3.UP, (-1.0 if to_cat.z > 0.0 else 1.0) * deg_to_rad(88.0))
			var hinge: Vector3 = base * Vector3(-size.x * 0.5, 0.0, 0.0)
			nx = Transform3D(turn, hinge - turn * hinge) * base
	else:
		b.door_open.erase(e)
	b.cur_xf[e] = nx
	b.groups[b.group[e]].set_transform(b.inst[e], nx)
	if b.bodies[e].is_valid():
		PhysicsServer3D.body_set_state(b.bodies[e], PhysicsServer3D.BODY_STATE_TRANSFORM, b.xform * nx)
	Audio.play_3d(&"impact_wood", b.xform * base.origin, 0.25)
