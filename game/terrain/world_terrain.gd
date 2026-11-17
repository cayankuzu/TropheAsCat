class_name WorldTerrain
extends Node3D
## The destructible ground of the 1024 x 1024 m slab: Voxel Tools smooth terrain (VoxelLodTerrain +
## Transvoxel), strata shader, digging, damage, persistence. Sets Game.terrain.
##
## Usage: add WorldTerrain.new() to the world. Everything else is built in code.
## Coordinates in this API are world metres. The voxel node is scaled by voxel_size.
## Damage arrives through DamageRouter: the voxel collision bodies report the VoxelLodTerrain child as
## their collider, the router walks up to this node's receive_damage().

signal terrain_edited(aabb: AABB)                               ## After every applied edit (world AABB).
signal dug(center: Vector3, radius: float, layer: StringName)   ## Material removed (for debris / FX).
signal edits_saved(path: String, ok: bool)
signal edits_loaded(path: String, ok: bool)

const WORLD_HALF := 512.0
const WORLD_BOTTOM := -48.0
const DEFAULT_SAVE_PATH := "user://terrain/edits.sqlite"
const SAVE_VERSION := 2
const BLOCK := 16                       ## Voxel Tools data block size (voxels).
const MAX_ADD_RADIUS := 12.0
const TOP_LIMIT := 96.0                 ## Highest y the voxel volume stores (rubble piles on hills).
const MAX_LOD_VOXEL_M := 16.0           ## Voxel size of the coarsest LOD (coarser ones break the slab).
const WAKE_MASK := Layers.DEBRIS | Layers.DEBRIS_SMALL | Layers.PROPS | Layers.NPC | Layers.PLAYER
const WAKE_BATCH := 512                 ## Results per wake query; repeated (excluding woken bodies) until done.
const LOAD_GUARD_FRAMES := 90           ## Longest wait for a stale async edit to land after load_edits().
const RIDGE_ASYNC_MIN_R := 8.0          ## Craters this big build their ejecta ridge on worker threads.
const SlabGenerator := preload("res://game/terrain/voxel_generator.gd")
const RIDGE_SPHERES := 64               ## Spheres in such a ridge.

@export var voxel_size := 0.5           ## Metres per voxel (chosen by measurement, see tests).
@export var lod_distance_m := 40.0      ## Radius of full-detail meshes around each viewer.
@export var collision_lod_count := 3    ## LODs that get colliders (LOD0 1:1, coarser ones further out).
@export var view_distance_m := 2400.0
@export var mesh_block_size := 16       ## Voxels per mesh block edge (16 or 32).
@export var max_lod_voxel_m := MAX_LOD_VOXEL_M   ## Voxel size of the coarsest LOD; sets lod_count.
@export var half_voxel_offset := true   ## Keep y = 0 and y = -48 off voxel sample planes (see _build_voxels).
## Main-thread time for voxel edits per frame, physics steps included (ARCHITECTURE: destruction <= 2 ms).
@export var edit_budget_ms := 2.0
@export var async_radius_m := 10.0      ## Spheres at least this big are edited on a worker thread.
@export var crater_scale := 1.0         ## Multiplies the excavated volume of blasts.
@export var max_crater_radius := 24.0
@export var blunt_dent_threshold_j := 8000.0
@export var lava_light_count := 6
## Voxel Tools' clipbox streaming supports several viewers but, in 1.7 with this setup, logs
## "Didn't expect missing sibling" and leaves the slab unmeshed when the viewer is high up. The legacy
## octree meshes everything with LOD around ONE viewer (player, else camera), so it is the default.
@export var clipbox_streaming := false

var voxels: VoxelLodTerrain
var _vt: VoxelToolLodTerrain
var _material: ShaderMaterial
var _mask_tex: ImageTexture
var _player_viewer: VoxelViewer
var _camera_viewer: VoxelViewer
var _anchors: Dictionary = {}           # Node3D -> VoxelViewer (collision-only)
var _queue: Array[PackedFloat32Array] = []   # [mode, x, y, z, r, force_async, ridge id]
var _in_flight: Array[Dictionary] = []       # async edits not yet visible in the voxel data
var _ring_queue: Array[Dictionary] = []      # crater ejecta ridges waiting for their bowl: {points, radii, centre, r} (world)
var _ridges: Dictionary = {}                 # ridge id -> {left: spheres not landed, aabb}: one signal per ridge
var _next_ridge := 1
var _load_guards: Array[Dictionary] = []     # async edits in flight during load_edits(): {edit, blocks, watch, frame, landed_frame}
var _guard_truth: Dictionary = {}            # Vector3i -> loaded VoxelBuffer (null = generator) for guarded blocks
var _restore_queue: Array[Vector3i] = []     # guarded blocks to restore again, within the edit budget
var _budget_frame := -1
var _frame_usec := 0
var _vol_lo := Vector3.ZERO                  # stored voxel volume (world): edits are clipped to it
var _vol_hi := Vector3.ZERO
var _wake_shape := BoxShape3D.new()
var _wake_query := PhysicsShapeQueryParameters3D.new()
var _edited_blocks: Dictionary = {}     # Vector3i (LOD0 data block) -> true
var _blasts: Array[Dictionary] = []     # radial hits DamageRouter announced this frame: {hit, done}
var _blasts_clear_queued := false
var _warned_unmatched := false
var _lights: Array[OmniLight3D] = []
var _light_phase: PackedFloat32Array = []
var _next_light := 0
var _stats := {"edits": 0, "edit_usec_total": 0, "edit_usec_max": 0, "queued_max": 0}


func _ready() -> void:
	process_priority = -10
	_build_voxels()
	_build_viewers()
	_build_lights()
	_register()


## _ready runs once; after a remove_child() + add_child() only this re-registers the node.
func _enter_tree() -> void:
	if voxels != null:
		_register()


func _exit_tree() -> void:
	if Game.terrain == self:
		Game.terrain = null
	if DamageRouter.blast.is_connected(_on_router_blast):
		DamageRouter.blast.disconnect(_on_router_blast)


func _register() -> void:
	Game.terrain = self
	if not DamageRouter.blast.is_connected(_on_router_blast):
		DamageRouter.blast.connect(_on_router_blast)


func _process(_delta: float) -> void:
	_update_viewers()
	while not _queue.is_empty() and _budget_used() < _budget_usec():
		var e: PackedFloat32Array = _queue.pop_front()
		_apply(int(e[0]), Vector3(e[1], e[2], e[3]), e[4], true, e[5] > 0.5, int(e[6]))
	_apply_rings()
	_poll_in_flight()
	_poll_load_guards()
	_animate_lights()


## Edit time spent in this frame. Physics steps run before _process in the same frame (same process-frame
## number), so edits made from physics callbacks and from _process share one budget.
func _budget_used() -> int:
	var f := Engine.get_process_frames()
	if f != _budget_frame:
		_budget_frame = f
		_frame_usec = 0
	return _frame_usec


## At least 1 us, so a frame that has not edited anything yet always makes progress.
func _budget_usec() -> int:
	return maxi(int(edit_budget_ms * 1000.0), 1)


# ---------------------------------------------------------------- queries

## Stratum by geology at a world position (also for dug-out space): &"grass", &"asphalt", &"paving",
## &"gravel", &"soil", &"clay", &"sand", &"rock", &"rock_deep", &"lava", &"bedrock".
## Above the original surface: &"rubble" where material was added (mounds, crater rims), else &"air".
## Outside the slab: &"void".
func get_layer_at(pos: Vector3) -> StringName:
	var i := TerrainStrata.layer_index_at(pos)
	if i == -1:
		return &"void"
	if i == -2:
		return &"rubble" if is_solid_at(pos) else &"air"
	return TerrainStrata.layer_name(i)


## True in the magma band, or standing on it (within 0.6 m above).
func is_lava_at(pos: Vector3) -> bool:
	if TerrainStrata.layer_index_at(pos) == TerrainStrata.LAVA:
		return true
	return TerrainStrata.layer_index_at(pos + Vector3(0.0, -0.6, 0.0)) == TerrainStrata.LAVA


## Energy to excavate one cubic metre at pos, in joules.
func get_resistance_at(pos: Vector3) -> float:
	return TerrainStrata.resistance_kj(TerrainStrata.layer_index_at(pos)) * 1000.0


## Height of the ORIGINAL (undug) surface.
func get_original_height(x: float, z: float) -> float:
	return TerrainShape.height_at(x, z)


## Signed distance to the current ground surface in metres (negative inside the ground). Outside the stored
## voxel volume (where Voxel Tools returns a constant) the distance to that volume is added, which never
## underestimates how far away the ground is.
func sdf_at(pos: Vector3) -> float:
	var q := pos.clamp(_vol_lo, _vol_hi)
	return _vt.get_voxel_f_interpolated(voxels.to_local(q)) * voxel_size + pos.distance_to(q)


func is_solid_at(pos: Vector3) -> bool:
	return sdf_at(pos) < 0.0


## Outward ground normal estimated from the SDF.
func sdf_normal(pos: Vector3) -> Vector3:
	var e := voxel_size
	var g := Vector3(
		sdf_at(pos + Vector3(e, 0, 0)) - sdf_at(pos - Vector3(e, 0, 0)),
		sdf_at(pos + Vector3(0, e, 0)) - sdf_at(pos - Vector3(0, e, 0)),
		sdf_at(pos + Vector3(0, 0, e)) - sdf_at(pos - Vector3(0, 0, e)))
	return g.normalized() if g.length_squared() > 1e-8 else Vector3.UP


# ---------------------------------------------------------------- editing

## Remove a sphere of ground. Applied immediately while this frame's edit budget lasts, else queued.
## Spheres of async_radius_m and more are edited on a worker thread and land a few frames later.
func dig_sphere(center: Vector3, radius: float) -> void:
	_enqueue(VoxelTool.MODE_REMOVE, center, minf(radius, max_crater_radius))


## Add a sphere of ground (rubble mound).
func add_sphere(center: Vector3, radius: float) -> void:
	var c := center.clamp(Vector3(-WORLD_HALF, WORLD_BOTTOM, -WORLD_HALF), Vector3(WORLD_HALF, TOP_LIMIT - radius, WORLD_HALF))
	_enqueue(VoxelTool.MODE_ADD, c, minf(radius, MAX_ADD_RADIUS))


## Remove an axis-aligned box of ground (cuts, foundations, test pits). Synchronous.
func dig_box(box: AABB) -> void:
	var lo := Vector3i(voxels.to_local(box.position).floor())
	var hi := Vector3i(voxels.to_local(box.end).ceil())
	_vt.mode = VoxelTool.MODE_REMOVE
	_vt.do_box(lo, hi)
	_mark_edited_box(Vector3(lo) - Vector3.ONE * 2.0, Vector3(hi) + Vector3.ONE * 2.0)
	terrain_edited.emit(box)
	_wake_bodies(box)


## Apply every queued and in-flight edit now, synchronously (saving, loading, tests).
func flush_edits() -> void:
	while true:
		while not _queue.is_empty():
			var e: PackedFloat32Array = _queue.pop_front()
			_apply(int(e[0]), Vector3(e[1], e[2], e[3]), e[4], false, false, int(e[6]))
		for f in _in_flight:
			# Spheres are idempotent: redoing the in-flight edit synchronously makes the data final now.
			_vt.mode = f["mode"]
			_vt.do_sphere(voxels.to_local(f["center"]), f["radius"] / voxel_size)
			_after_edit(f["mode"], f["center"], f["radius"], f["ridge"])
		_in_flight.clear()
		if _ring_queue.is_empty():
			break
		_apply_rings(false)   # small ridges now, big ones into the queue
	_drain_restores(false)


## Edits not yet visible in the voxel data (queued, in flight, ridges, post-load repairs).
func pending_edits() -> int:
	return _queue.size() + _in_flight.size() + _ring_queue.size() + _load_guards.size() + _restore_queue.size()


func _enqueue(mode: int, center: Vector3, radius: float, force_async: bool = false) -> void:
	if radius <= 0.01 or not is_finite(center.x + center.y + center.z):
		return
	if _queue.is_empty() and _budget_used() < _budget_usec():
		_apply(mode, center, radius, true, force_async)
	else:
		_queue.append(PackedFloat32Array([mode, center.x, center.y, center.z, radius, 1.0 if force_async else 0.0, 0.0]))
		_stats["queued_max"] = maxi(_stats["queued_max"], _queue.size())


## ridge > 0: a sphere of that crater ridge (reported once for the whole ridge, see _after_edit).
func _apply(mode: int, center: Vector3, radius: float, allow_async: bool, force_async: bool = false, ridge: int = 0) -> void:
	_budget_used()
	var t := Time.get_ticks_usec()
	var lc := voxels.to_local(center)
	var lr := radius / voxel_size
	_vt.mode = mode as VoxelTool.Mode
	_mark_edited(lc, lr + 2.0)
	if allow_async and (force_async or radius >= async_radius_m):
		# Probe a point the edit must flip, to know when the worker thread has landed it: inside the sphere
		# below its centre for a dig, just under its top for added material.
		var probe := center - Vector3(0.0, radius * 0.5, 0.0) if mode == VoxelTool.MODE_REMOVE else center + Vector3(0.0, radius - voxel_size, 0.0)
		var before := sdf_at(probe)
		_vt.do_sphere_async(lc, lr)
		if (mode == VoxelTool.MODE_REMOVE and before < 0.0) or (mode == VoxelTool.MODE_ADD and before > 0.0):
			_in_flight.append({"mode": mode, "center": center, "radius": radius, "probe": probe, "frame": Engine.get_process_frames(), "ridge": ridge})
		else:
			_after_edit(mode, center, radius, ridge)
	else:
		_vt.do_sphere(lc, lr)
		_after_edit(mode, center, radius, ridge)
	var dt := Time.get_ticks_usec() - t
	_frame_usec += dt
	_stats["edits"] += 1
	_stats["edit_usec_total"] += dt
	_stats["edit_usec_max"] = maxi(_stats["edit_usec_max"], dt)


func _poll_in_flight() -> void:
	for i in range(_in_flight.size() - 1, -1, -1):
		var f: Dictionary = _in_flight[i]
		if _probe_landed(f) or Engine.get_process_frames() - int(f["frame"]) > 60:
			_in_flight.remove_at(i)
			_after_edit(f["mode"], f["center"], f["radius"], f["ridge"])


## True once the async edit `f` shows at its probe point.
func _probe_landed(f: Dictionary) -> bool:
	var s := sdf_at(f["probe"])
	return s > 0.0 if int(f["mode"]) == VoxelTool.MODE_REMOVE else s < 0.0


## Runs once the edit is visible in the voxel data. The spheres of a crater ridge report once, together,
## when the last of them has landed.
func _after_edit(mode: int, center: Vector3, radius: float, ridge: int = 0) -> void:
	if ridge > 0:
		var g: Dictionary = _ridges.get(ridge, {})
		g["left"] = int(g.get("left", 1)) - 1
		if int(g["left"]) <= 0:
			_ridges.erase(ridge)
			_report_edit(g.get("aabb", AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)))
		return
	_report_edit(AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0))
	if mode == VoxelTool.MODE_REMOVE:
		dug.emit(center, radius, get_layer_at(center - Vector3(0.0, radius * 0.6, 0.0)))
		_maybe_light_lava(center, radius)


func _report_edit(aabb: AABB) -> void:
	terrain_edited.emit(aabb)
	_wake_bodies(aabb.grow(0.5))


## Jolt does not wake sleeping bodies when the ground under them changes: do it here, for every body in the
## box (a rubble pile can hold far more than one query returns).
func _wake_bodies(aabb: AABB) -> void:
	var space := get_world_3d().direct_space_state
	_wake_shape.size = aabb.size
	_wake_query.shape = _wake_shape
	_wake_query.transform = Transform3D(Basis.IDENTITY, aabb.get_center())
	_wake_query.collision_mask = WAKE_MASK
	_wake_query.collide_with_areas = false
	_wake_query.exclude = []
	var seen: Array[RID] = []
	while true:
		var results := space.intersect_shape(_wake_query, WAKE_BATCH)
		for r in results:
			var rid: RID = r.get("rid", RID())
			var body := r.get("collider") as RigidBody3D
			if body != null:
				body.sleeping = false
			elif rid.is_valid():
				var mode := PhysicsServer3D.body_get_mode(rid)
				if mode == PhysicsServer3D.BODY_MODE_RIGID or mode == PhysicsServer3D.BODY_MODE_RIGID_LINEAR:
					PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
			seen.append(rid)
		if results.size() < WAKE_BATCH:
			break
		_wake_query.exclude = seen


func _mark_edited(local_center: Vector3, local_radius: float) -> void:
	_mark_edited_box(local_center - Vector3.ONE * local_radius, local_center + Vector3.ONE * local_radius)


func _mark_edited_box(local_lo: Vector3, local_hi: Vector3) -> void:
	for bp in _blocks_in_box(local_lo, local_hi):
		_edited_blocks[bp] = true


## LOD0 data blocks overlapping a box in voxel (local) units.
func _blocks_in_box(local_lo: Vector3, local_hi: Vector3) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var lo := (local_lo / BLOCK).floor()
	var hi := (local_hi / BLOCK).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				out.append(Vector3i(x, y, z))
	return out


# ---------------------------------------------------------------- damage

## Called by DamageRouter (directly for ray/contact hits on the voxel colliders, or per overlapping
## collision block for apply_blast).
func receive_damage(hit: DamageHit, _user_id: int) -> void:
	var h := hit
	if hit.radius > 0.0:
		if hit.kind == DamageHit.Kind.EXPLOSION:
			_stats["explosion_hits"] = int(_stats.get("explosion_hits", 0)) + 1
		# apply_blast hands every overlapping collision block a falloff copy moved to the collider's origin
		# (this terrain's voxel node). Recover the blast it announced just before and handle it once.
		var src := _match_blast(hit)
		if not src.is_empty():
			if src["done"]:
				return
			src["done"] = true
			h = src["hit"]
		elif hit.position.is_equal_approx(voxels.global_position):
			# A router copy whose blast was not announced: its centre is unknown, and digging at the
			# collider origin (the world origin) would be wrong.
			if not _warned_unmatched:
				_warned_unmatched = true
				push_warning("WorldTerrain: radial hit without a matching DamageRouter.blast was ignored")
			return
		if h.kind != DamageHit.Kind.EXPLOSION:
			h = _radial_to_ground(h)
			if h == null:
				return
	match h.kind:
		DamageHit.Kind.EXPLOSION:
			explode(h.position, h.radius, h.energy)
		DamageHit.Kind.BLUNT:
			if h.energy >= blunt_dent_threshold_j:
				_point_dig(h, 0.25, 0.25, 1.5, 0.45)
		DamageHit.Kind.HEAT, DamageHit.Kind.ACID:
			_point_dig(h, 1.0, 0.2, 3.0, -0.3)
		DamageHit.Kind.CUT:
			_point_dig(h, 0.6, 0.15, 0.8, -0.2)
		_:
			pass


## The blast announced this frame whose falloff copy `hit` is: an exact match (energy and direction as
## DamageHit.falloff_copy and DamageRouter give them), else the newest unhandled blast with the same cause,
## kind and radius. {} if no blast was announced for it (a radial hit made some other way).
func _match_blast(hit: DamageHit) -> Dictionary:
	var loose := {}
	for i in range(_blasts.size() - 1, -1, -1):
		var e: Dictionary = _blasts[i]
		var b: DamageHit = e["hit"]
		if b.cause_id != hit.cause_id or b.kind != hit.kind or not is_equal_approx(b.radius, hit.radius):
			continue
		var d := hit.position.distance_to(b.position)
		var dir := (hit.position - b.position).normalized() if d * d > 0.0001 else Vector3.UP
		if is_equal_approx(b.falloff_copy(d).energy, hit.energy) and dir.is_equal_approx(hit.direction):
			return e
		if loose.is_empty() or (bool(loose["done"]) and not bool(e["done"])):
			loose = e
	return loose


## A radial hit that is not an explosion (shockwave, fire, acid splash) acts on the ground point nearest its
## centre with the energy left after the linear falloff. null when the ground is out of its reach.
func _radial_to_ground(b: DamageHit) -> DamageHit:
	var s := sdf_at(b.position)
	if s > b.radius:
		return null
	var h := b.falloff_copy(maxf(s, 0.0))
	h.normal = Vector3.UP
	if s > 0.0:
		h.normal = sdf_normal(b.position)
		h.position = b.position - h.normal * s
	h.direction = -h.normal
	return h


## Crater from a blast centred at `center` (may be above or inside the ground).
## Excavated volume = energy / layer resistance, so the radius grows with cbrt(energy) and is smaller in
## rock. Returns the crater radius in metres (0 if the blast does not reach the ground).
func explode(center: Vector3, blast_radius: float, energy_j: float) -> float:
	var s := sdf_at(center)
	var reach := maxf(blast_radius, 0.5)
	if s > reach:
		return 0.0
	var ground := center
	var up := Vector3.UP
	if s > 0.0:
		up = sdf_normal(center)
		ground = center - up * s
	else:
		up = sdf_normal(center + Vector3.UP * 0.5)
	var e := energy_j * clampf(1.0 - maxf(s, 0.0) / reach, 0.0, 1.0) * crater_scale
	var layer := TerrainStrata.layer_index_at(ground - up * 0.4)
	if layer < 0:
		layer = TerrainStrata.SOIL
	var vol := e / (TerrainStrata.resistance_kj(layer) * 1000.0)
	# The bowl below (sphere 1.05 r raised by 0.3 r) removes about 1.41 r^3.
	var r := minf(pow(vol / 1.41, 1.0 / 3.0), max_crater_radius)
	if r < 0.25:
		return 0.0
	_stats["craters"] = int(_stats.get("craters", 0)) + 1
	_enqueue(VoxelTool.MODE_REMOVE, ground + up * r * 0.3, minf(r * 1.05, max_crater_radius), r >= RIDGE_ASYNC_MIN_R)
	# The lobes and the ejecta lip lie round the crater on level ground. On a steep face (the wall of an
	# older crater, a blast in the same spot again) a lip would stand up as a ring in the air: none there.
	if r >= 1.5 and up.y > 0.7:
		_crater_detail(ground, Vector3.UP, r)
	return r


## Irregular floor (a few lobes) and an ejecta lip: a low, continuous ridge just outside the rim, so part
## of the dug volume stays on the ground as rubble. The ridge is a tube through 28 points around the rim.
func _crater_detail(ground: Vector3, up: Vector3, r: float) -> void:
	var t1 := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := up.cross(t1)
	var seed_v := int(absf(ground.x) * 13.0 + absf(ground.z) * 7.0 + absf(ground.y) * 3.0)
	for i in 4:
		var h := _hash01(seed_v + i * 7919)
		var a := TAU * (float(i) + h) / 4.0
		var dir := t1 * cos(a) + t2 * sin(a)
		# Lobes of big craters (up to 11 m, 1-2.5 ms each on the main thread) go to worker threads too.
		_enqueue(VoxelTool.MODE_REMOVE, ground + dir * r * (0.3 + 0.2 * h) - up * r * 0.25, r * (0.38 + 0.1 * h), r >= RIDGE_ASYNC_MIN_R)
	var n := 28
	var hs := PackedFloat32Array()
	for k in n:
		hs.append(_hash01(seed_v + k * 104729))
	# Small ridges: one do_path call on the main thread (cost grows with r^3: ~0.8 ms at 8 m). Bigger ones
	# (~22 ms in one call at 24 m) are a ring of overlapping spheres edited on worker threads, spaced at a
	# third of their radius so the crest stays smooth.
	var small := r < RIDGE_ASYNC_MIN_R
	var steps := n if small else RIDGE_SPHERES
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for j in steps + 1 if small else steps:   # the path repeats its first point to close the ring
		var u := float(j % steps) * n / float(steps)
		var k0 := int(u)
		var h := lerpf(hs[k0 % n], hs[(k0 + 1) % n], u - k0)
		var a := TAU * u / float(n)
		var dir := t1 * cos(a) + t2 * sin(a)
		pts.append(ground + dir * r * (1.12 + 0.08 * h) - up * r * 0.27)
		radii.append(r * (0.31 + 0.07 * h))
	_ring_queue.append({"points": pts, "radii": radii, "centre": ground, "r": r})


## A ridge is applied once the bowl edits before it have landed (added material must not be carved by a
## bowl still in flight): a small one as a single do_path, a big one as async spheres through the queue.
func _apply_rings(budgeted: bool = true) -> void:
	while not _ring_queue.is_empty() and _queue.is_empty() and _in_flight.is_empty():
		if budgeted and float(_ring_queue[0]["r"]) < RIDGE_ASYNC_MIN_R and _budget_used() >= _budget_usec():
			return
		var e: Dictionary = _ring_queue.pop_front()
		var pts: PackedVector3Array = e["points"]
		var radii: PackedFloat32Array = e["radii"]
		var c: Vector3 = e["centre"]
		var rr: float = float(e["r"]) * 1.6
		var aabb := AABB(c - Vector3.ONE * rr, Vector3.ONE * rr * 2.0)
		if float(e["r"]) >= RIDGE_ASYNC_MIN_R:
			var id := _next_ridge
			_next_ridge = _next_ridge % 1000000 + 1   # stays exact in the queue's float32
			_ridges[id] = {"left": pts.size(), "aabb": aabb}
			for i in pts.size():
				_queue.append(PackedFloat32Array([VoxelTool.MODE_ADD, pts[i].x, pts[i].y, pts[i].z, radii[i], 1.0, id]))
			continue
		_budget_used()
		var t := Time.get_ticks_usec()
		var lp := PackedVector3Array()
		var lr := PackedFloat32Array()
		for i in pts.size():
			lp.append(voxels.to_local(pts[i]))
			lr.append(radii[i] / voxel_size)
		_vt.mode = VoxelTool.MODE_ADD
		_vt.do_path(lp, lr)
		for i in lp.size() - 1:
			var pad := Vector3.ONE * (maxf(lr[i], lr[i + 1]) + 2.0)
			_mark_edited_box(lp[i].min(lp[i + 1]) - pad, lp[i].max(lp[i + 1]) + pad)
		var dt := Time.get_ticks_usec() - t
		_frame_usec += dt
		_stats["ridge_path_usec_max"] = maxi(int(_stats.get("ridge_path_usec_max", 0)), dt)
		_report_edit(aabb)


static func _hash01(n: int) -> float:
	return float(((n * 2654435761) ^ (n >> 7)) & 0xFFFF) / 65535.0


func _point_dig(hit: DamageHit, efficiency: float, r_min: float, r_max: float, offset: float) -> void:
	var n := hit.normal
	if hit.direction != Vector3.ZERO and (n.length_squared() < 0.5 or n.is_equal_approx(Vector3.UP)):
		n = -hit.direction   # DamageHit.normal defaults to UP when the caller did not know it
	if n.length_squared() < 0.5:
		n = Vector3.UP
	n = n.normalized()
	var layer := TerrainStrata.layer_index_at(hit.position - n * 0.3)
	if layer < 0:
		return
	var vol := hit.energy * efficiency / (TerrainStrata.resistance_kj(layer) * 1000.0)
	var r := pow(3.0 * vol / (4.0 * PI), 1.0 / 3.0)
	if r < r_min:
		return
	r = minf(r, r_max)
	dig_sphere(hit.position + n * r * offset, r)


## DamageRouter.blast is emitted before the blast's deliveries, which all happen in the same call.
func _on_router_blast(hit: DamageHit) -> void:
	_blasts.append({"hit": hit, "done": false})
	if not _blasts_clear_queued:
		_blasts_clear_queued = true
		_clear_blasts.call_deferred()


func _clear_blasts() -> void:
	_blasts.clear()
	_blasts_clear_queued = false


# ---------------------------------------------------------------- surface mask

## image: 1 m per pixel over x, z in [-512, 512); R = road, G = sidewalk, B = grass.
## grid_markings paints lane lines for the default 128 m grid only; leave it off for custom layouts.
func set_surface_mask(image: Image, grid_markings: bool = false) -> void:
	var cpu := TerrainStrata.set_mask(image)
	var gpu := cpu.duplicate() as Image
	gpu.generate_mipmaps()
	if _mask_tex == null or _mask_tex.get_size() != Vector2(gpu.get_size()):
		_mask_tex = ImageTexture.create_from_image(gpu)
	else:
		_mask_tex.update(gpu)
	if _material != null:
		_material.set_shader_parameter(&"u_mask", _mask_tex)
		_material.set_shader_parameter(&"u_grid_markings", grid_markings)


# ---------------------------------------------------------------- persistence

## Snapshot every edited block into a VoxelStreamSQLite at `path` (+ a block index next to it). The new
## files are written next to the old ones and swapped in at the end: a failed save keeps the previous one.
func save_edits(path: String = DEFAULT_SAVE_PATH) -> bool:
	flush_edits()
	# Blocks a stale async edit may have reached since load_edits() are put right before the snapshot.
	for g in _load_guards:
		for bp: Vector3i in g["blocks"]:
			_restore_block(bp, _guard_truth.get(bp))
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var tmp := abs_path + ".tmp"
	var ok := _write_snapshot(tmp)
	if ok:
		ok = _replace_file(tmp, abs_path) and _replace_file(tmp + ".blocks", abs_path + ".blocks")
	edits_saved.emit(path, ok)
	return ok


func _write_snapshot(db_path: String) -> bool:
	for p: String in [db_path, db_path + ".blocks"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var probe := FileAccess.open(db_path, FileAccess.WRITE)   # SQLite starts an empty file as a new database
	if probe == null:
		return false
	probe.close()
	var stream := VoxelStreamSQLite.new()
	stream.database_path = db_path
	var buf := VoxelBuffer.new()
	var positions := PackedInt32Array()
	for bp: Vector3i in _edited_blocks:
		buf.create(BLOCK, BLOCK, BLOCK)
		_vt.copy(bp * BLOCK, buf, VoxelBuffer.CHANNEL_SDF_BIT)
		stream.save_voxel_block(buf, bp, 0)
		positions.append_array(PackedInt32Array([bp.x, bp.y, bp.z]))
	stream.flush()
	stream = null   # closes the database before the file is moved
	var f := FileAccess.open(db_path + ".blocks", FileAccess.WRITE)
	if f == null:
		return false
	f.store_var({"version": SAVE_VERSION, "voxel_size": voxel_size, "blocks": positions})
	f.close()
	return true


static func _replace_file(from: String, to: String) -> bool:
	if FileAccess.file_exists(to) and DirAccess.remove_absolute(to) != OK:
		return false
	return DirAccess.rename_absolute(from, to) == OK


## Restore the ground to the state saved at `path`; blocks edited since then go back to pristine.
## Edits still queued are dropped (the loaded state supersedes them).
func load_edits(path: String = DEFAULT_SAVE_PATH) -> bool:
	var abs_path := ProjectSettings.globalize_path(path)
	var f := FileAccess.open(abs_path + ".blocks", FileAccess.READ)
	if f == null or not FileAccess.file_exists(abs_path):
		edits_loaded.emit(path, false)
		return false
	var index: Dictionary = f.get_var()
	f.close()
	if int(index.get("version", 0)) != SAVE_VERSION or not is_equal_approx(float(index.get("voxel_size", 0.0)), voxel_size):
		push_error("WorldTerrain: %s was saved with another format or voxel size" % path)
		edits_loaded.emit(path, false)
		return false
	_queue.clear()
	_ring_queue.clear()
	_ridges.clear()
	# Voxel Tools cannot cancel an async edit already handed to it: one that has not landed yet will write
	# into the loaded ground later. Its blocks are restored again once it lands (_poll_load_guards).
	var stale: Array[Dictionary] = []
	for e in _in_flight:
		if not _probe_landed(e):
			stale.append(e)
	for g in _load_guards:
		stale.append(g["edit"])
	_in_flight.clear()
	_load_guards.clear()
	_restore_queue.clear()
	_guard_truth.clear()
	var guarded := {}
	var stale_blocks: Array = []
	for e in stale:
		var lc := voxels.to_local(e["center"])
		var lr := float(e["radius"]) / voxel_size + 2.0
		var blocks := _blocks_in_box(lc - Vector3.ONE * lr, lc + Vector3.ONE * lr)
		stale_blocks.append(blocks)
		for bp in blocks:
			guarded[bp] = true
	var stream := VoxelStreamSQLite.new()
	stream.database_path = abs_path
	var saved := {}
	var p: PackedInt32Array = index["blocks"]
	for i in range(0, p.size(), 3):
		saved[Vector3i(p[i], p[i + 1], p[i + 2])] = true
	var ok := true
	for bp: Vector3i in _edited_blocks:
		if not saved.has(bp):
			_restore_block(bp, null)
	var shared := VoxelBuffer.new()
	for bp: Vector3i in saved:
		var buf := VoxelBuffer.new() if guarded.has(bp) else shared   # guarded blocks keep their data
		buf.create(BLOCK, BLOCK, BLOCK)
		if stream.load_voxel_block(buf, bp, 0) != VoxelStream.RESULT_BLOCK_FOUND:
			ok = false
			buf = null
		_restore_block(bp, buf)
		if guarded.has(bp):
			_guard_truth[bp] = buf
	_edited_blocks = saved
	var now := Engine.get_process_frames()
	for i in stale.size():
		var e: Dictionary = stale[i]
		# The landing is visible only if the loaded ground at the probe is in the edit's "before" state.
		var solid_now := sdf_at(e["probe"]) < 0.0
		var watch := solid_now if int(e["mode"]) == VoxelTool.MODE_REMOVE else not solid_now
		_load_guards.append({"edit": e, "blocks": stale_blocks[i], "watch": watch, "frame": now, "landed_frame": -1})
	edits_loaded.emit(path, ok)
	return ok


## Restores the blocks of each stale async edit (see load_edits) two frames after its probe shows that it
## landed, or after LOAD_GUARD_FRAMES when the probe cannot tell; the restores are spread over frames.
func _poll_load_guards() -> void:
	var now := Engine.get_process_frames()
	for i in range(_load_guards.size() - 1, -1, -1):
		var g: Dictionary = _load_guards[i]
		if int(g["landed_frame"]) < 0 and bool(g["watch"]) and _probe_landed(g["edit"]):
			g["landed_frame"] = now
		var landed: int = g["landed_frame"]
		if (landed >= 0 and now - landed >= 2) or now - int(g["frame"]) > LOAD_GUARD_FRAMES:
			_restore_queue.append_array(g["blocks"])
			_load_guards.remove_at(i)
	_drain_restores(true)
	if _load_guards.is_empty() and _restore_queue.is_empty():
		_guard_truth.clear()


func _drain_restores(budgeted: bool) -> void:
	while not _restore_queue.is_empty():
		if budgeted and _budget_used() >= _budget_usec():
			return
		var t := Time.get_ticks_usec()
		var bp: Vector3i = _restore_queue.pop_back()
		_restore_block(bp, _guard_truth.get(bp))
		_frame_usec += Time.get_ticks_usec() - t


func _restore_block(bp: Vector3i, buf: VoxelBuffer) -> void:
	if buf == null:
		buf = VoxelBuffer.new()
		buf.create(BLOCK, BLOCK, BLOCK)
		voxels.generator.generate_block(buf, Vector3(bp * BLOCK), 0)
	_vt.paste(bp * BLOCK, buf, VoxelBuffer.CHANNEL_SDF_BIT)
	var o := voxels.to_global(Vector3(bp * BLOCK))
	terrain_edited.emit(AABB(o, Vector3.ONE * BLOCK * voxel_size))


## Hash of the voxel SDF inside a world-space box (tests, save/load verification).
func debug_region_hash(region: AABB) -> int:
	var lo := Vector3i(voxels.to_local(region.position).floor())
	var size := Vector3i((region.size / voxel_size).ceil())
	var buf := VoxelBuffer.new()
	buf.create(size.x, size.y, size.z)
	_vt.copy(lo, buf, VoxelBuffer.CHANNEL_SDF_BIT)
	return hash(buf.get_channel_as_byte_array(VoxelBuffer.CHANNEL_SDF))


func get_stats() -> Dictionary:
	var s := _stats.duplicate()
	s["edited_blocks"] = _edited_blocks.size()
	s["queued"] = _queue.size()
	s["ridges_pending"] = _ring_queue.size()
	s["load_guards"] = _load_guards.size()
	s["mesh_blocks"] = voxels.debug_get_mesh_block_count()
	s["data_blocks"] = voxels.debug_get_data_block_count()
	s.merge(voxels.get_statistics())
	return s


# ---------------------------------------------------------------- streaming around player and camera

## Keep colliders around an extra node (e.g. a far debris pile) until remove_collision_anchor().
## Only effective with clipbox_streaming (the legacy octree follows a single viewer).
func add_collision_anchor(node: Node3D, radius_m: float = 48.0) -> void:
	if _anchors.has(node) or not clipbox_streaming:
		return
	var v := VoxelViewer.new()
	v.top_level = true
	v.requires_visuals = false
	v.requires_collisions = true
	v.view_distance = int(radius_m)
	add_child(v)
	_anchors[node] = v


func remove_collision_anchor(node: Node3D) -> void:
	if _anchors.has(node):
		(_anchors[node] as Node).queue_free()
		_anchors.erase(node)


func _update_viewers() -> void:
	var cam := get_viewport().get_camera_3d()
	var player := Game.player
	var has_player := player != null and is_instance_valid(player) and player.is_inside_tree()
	if not clipbox_streaming:
		if has_player:
			_player_viewer.global_position = player.global_position
		elif cam != null:
			_player_viewer.global_position = cam.global_position
		return
	if has_player:
		_player_viewer.global_position = player.global_position
	_player_viewer.requires_visuals = has_player
	_player_viewer.requires_collisions = has_player
	if cam != null:
		_camera_viewer.global_position = cam.global_position
	_camera_viewer.requires_collisions = not has_player
	for key: Variant in _anchors.keys():   # untyped: a key may be a freed node
		var viewer := _anchors[key] as Node3D
		if is_instance_valid(key):
			viewer.global_position = (key as Node3D).global_position
		else:
			viewer.queue_free()
			_anchors.erase(key)


# ---------------------------------------------------------------- build

func _build_voxels() -> void:
	voxels = VoxelLodTerrain.new()
	voxels.name = "Voxels"
	voxels.scale = Vector3.ONE * voxel_size
	voxels.generator = SlabGenerator.build(voxel_size, -0.5 * voxel_size if half_voxel_offset else 0.0)
	# Half a voxel down: y = 0 (city) and y = -48 (bottom) then fall between voxel sample planes. On a
	# sample plane Transvoxel's edge clamp lifts the surface by 2 % of a cell at every LOD (0.32 m at
	# 16 m voxels, colliders included); clamp margin 0 instead makes blocks Jolt cannot build.
	voxels.position = Vector3(0.0, -0.5 * voxel_size if half_voxel_offset else 0.0, 0.0)
	voxels.mesher = VoxelMesherTransvoxel.new()
	voxels.mesh_block_size = mesh_block_size
	voxels.full_load_mode_enabled = true
	voxels.streaming_system = VoxelLodTerrain.STREAMING_SYSTEM_CLIPBOX if clipbox_streaming else VoxelLodTerrain.STREAMING_SYSTEM_LEGACY_OCTREE
	var lo := Vector3(-WORLD_HALF - 16.0, WORLD_BOTTOM - 8.0, -WORLD_HALF - 16.0)
	var hi := Vector3(WORLD_HALF + 16.0, TOP_LIMIT, WORLD_HALF + 16.0)
	voxels.voxel_bounds = AABB((lo - voxels.position) / voxel_size, (hi - lo) / voxel_size)
	_vol_lo = lo + Vector3.ONE * voxel_size   # one voxel in, so interpolated reads stay inside
	_vol_hi = hi - Vector3.ONE * voxel_size
	# The coarsest LOD must still resolve a 48 m thick slab: cap its voxels at MAX_LOD_VOXEL_M.
	voxels.lod_count = clampi(int(round(log(max_lod_voxel_m / voxel_size) / log(2.0))) + 1, 3, 10)
	voxels.lod_distance = lod_distance_m / voxel_size
	voxels.view_distance = int(view_distance_m / voxel_size)
	voxels.generate_collisions = true
	voxels.collision_layer = Layers.TERRAIN
	voxels.collision_mask = 0
	voxels.collision_lod_count = collision_lod_count
	voxels.collision_margin = 0.0
	voxels.collision_update_delay = 0
	_material = _build_material()
	voxels.material = _material
	add_child(voxels)
	_vt = voxels.get_voxel_tool() as VoxelToolLodTerrain


func _build_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://game/terrain/strata.gdshader")
	var tex := StrataTextureSet.load_textures()
	if not tex.is_empty():
		mat.set_shader_parameter(&"u_albedo", tex["albedo"])
		mat.set_shader_parameter(&"u_nrm", tex["nrm"])
		mat.set_shader_parameter(&"u_lava_emission", tex["lava_emission"])
	mat.set_shader_parameter(&"u_height", ImageTexture.create_from_image(TerrainShape.heightmap()))
	mat.set_shader_parameter(&"u_hm_offset", float(TerrainShape.HM_OFFSET))
	mat.set_shader_parameter(&"u_hm_size", float(TerrainShape.HM_SIZE))
	mat.set_shader_parameter(&"u_mask_size", float(TerrainStrata.MASK_SIZE))
	var noise := TerrainStrata.noise_image().duplicate() as Image
	noise.generate_mipmaps()
	mat.set_shader_parameter(&"u_noise", ImageTexture.create_from_image(noise))
	var params := TerrainStrata.shader_layer_params()
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	_material = mat
	set_surface_mask(TerrainStrata.mask_image(), true)
	return mat


func _build_viewers() -> void:
	_player_viewer = VoxelViewer.new()
	_player_viewer.name = "PlayerViewer"
	var viewers: Array[VoxelViewer] = [_player_viewer]
	if clipbox_streaming:
		_camera_viewer = VoxelViewer.new()
		_camera_viewer.name = "CameraViewer"
		viewers.append(_camera_viewer)
	for v in viewers:
		v.top_level = true
		v.view_distance = int(view_distance_m)
		add_child(v)
	_update_viewers()


# ---------------------------------------------------------------- lava light

func _build_lights() -> void:
	for i in lava_light_count:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.42, 0.12)
		l.light_energy = 0.0
		l.omni_range = 16.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.visible = false
		l.top_level = true
		add_child(l)
		_lights.append(l)
		_light_phase.append(randf() * TAU)


func _maybe_light_lava(center: Vector3, radius: float) -> void:
	if _lights.is_empty():
		return
	var lava_top := TerrainStrata.BOUND_Y[1]
	var lava_bottom := TerrainStrata.BOUND_Y[2]
	var lowest := center.y - radius
	if lowest > lava_top + 0.6 or center.y + radius < lava_bottom:
		return
	var p := Vector3(center.x, maxf(lowest, lava_bottom) + 1.8, center.z)
	for l in _lights:
		if l.visible and l.global_position.distance_to(p) < 7.0:
			return
	var light := _lights[_next_light]
	_next_light = (_next_light + 1) % _lights.size()
	light.global_position = p
	light.visible = true


func _animate_lights() -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in _lights.size():
		var l := _lights[i]
		if l.visible:
			var ph := _light_phase[i]
			l.light_energy = 2.2 * (0.85 + 0.1 * sin(t * 2.3 + ph) + 0.05 * sin(t * 7.1 + ph * 3.0))
