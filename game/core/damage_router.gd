extends Node
## Autoload "DamageRouter": the single entry point for damage.
##
## Receivers:
##  * Bodies created directly on PhysicsServer3D (structure elements, rubble) have no Node, so their
##    owner registers the body RID here with register_rid(rid, handler, user_id).
##  * Node-based receivers implement `func receive_damage(hit: DamageHit, user_id: int) -> void`.
##    The router calls it on the collider, or on the first ancestor that has it.
##  * Nodes in group "protected" (trees, plants, animals, the cat) never take damage; the router
##    emits protected_hit so feedback VFX can play, and pushes nothing.
##  * Any other RigidBody3D just receives the impulse.

signal damage_applied(hit: DamageHit, target: Object)
signal protected_hit(hit: DamageHit, target: Object)
signal blast(hit: DamageHit)   ## Emitted once per radial hit (VFX, audio, camera shake, NPC panic).

const MAX_BLAST_RESULTS := 512
## The Table only reacts around Trophe: nothing farther than this from the player takes damage. The
## terrain has collision for about 160 m around the player, so whatever broke out there would fall
## through the world. Tools keep their ranges inside it. Without a player (tests) there is no limit.
const REACH := 150.0

var _rid_handlers: Dictionary = {}   # RID -> [handler: Object, user_id: int]
var _next_cause_id: int = 1
var _sphere := SphereShape3D.new()


func register_rid(rid: RID, handler: Object, user_id: int) -> void:
	_rid_handlers[rid] = [handler, user_id]


func unregister_rid(rid: RID) -> void:
	_rid_handlers.erase(rid)


func new_cause_id() -> int:
	_next_cause_id += 1
	return _next_cause_id


## Deliver a point hit to one collider (from a ray or contact result: pass its "collider" and "rid").
func apply_hit(hit: DamageHit, collider: Object, rid: RID = RID()) -> void:
	var t_probe := PerfProbe.begin()
	apply_hit_timed(hit, collider, rid)
	PerfProbe.add(&"router_hit", t_probe)


func apply_hit_timed(hit: DamageHit, collider: Object, rid: RID = RID()) -> void:
	if hit.cause_id == 0:
		hit.cause_id = new_cause_id()
	if not in_reach(hit.position):
		return
	_deliver(hit, collider, rid)


## True when a point is close enough to the player for the world to react there (see REACH).
func in_reach(pos: Vector3) -> bool:
	var p := Game.player
	return p == null or not is_instance_valid(p) or p.global_position.distance_squared_to(pos) <= REACH * REACH


## Deliver a radial hit to everything in hit.radius.
func apply_blast(hit: DamageHit, world: World3D = null, mask: int = Layers.DAMAGEABLE) -> void:
	var t_probe := PerfProbe.begin()
	apply_blast_timed(hit, world, mask)
	PerfProbe.add(&"router_blast", t_probe)


func apply_blast_timed(hit: DamageHit, world: World3D = null, mask: int = Layers.DAMAGEABLE) -> void:
	if hit.cause_id == 0:
		hit.cause_id = new_cause_id()
	if world == null:
		world = Game.get_world_3d()
	if world == null or hit.radius <= 0.0:
		return
	blast.emit(hit)
	if not in_reach(hit.position):
		return   # seen and heard, but too far away to change anything
	_sphere.radius = hit.radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis.IDENTITY, hit.position)
	q.collide_with_areas = false
	# Jolt returns one result per triangle of a concave shape (the voxel terrain gives hundreds), so the
	# terrain layer is queried on its own (it cannot use up MAX_BLAST_RESULTS) and each body is hit once.
	var seen := {}
	for layer_mask: int in [mask & ~Layers.TERRAIN, mask & Layers.TERRAIN]:
		if layer_mask == 0:
			continue
		q.collision_mask = layer_mask
		var results := world.direct_space_state.intersect_shape(q, MAX_BLAST_RESULTS)
		for r in results:
			var collider: Object = r.get("collider")
			var rid: RID = r.get("rid", RID())
			if seen.has(rid):
				continue
			seen[rid] = true
			var p := _closest_point_guess(collider, rid, hit.position)
			var h := hit.falloff_copy(p.distance_to(hit.position))
			h.direction = (p - hit.position).normalized() if p.distance_squared_to(hit.position) > 0.0001 else Vector3.UP
			h.position = p
			_deliver(h, collider, rid)


func _deliver(hit: DamageHit, collider: Object, rid: RID) -> void:
	if rid.is_valid() and _rid_handlers.has(rid):
		var entry: Array = _rid_handlers[rid]
		var handler: Object = entry[0]
		if is_instance_valid(handler):
			handler.call(&"receive_damage", hit, entry[1])
			damage_applied.emit(hit, handler)
		else:
			_rid_handlers.erase(rid)
		return
	if collider == null or not is_instance_valid(collider):
		return
	var node := collider as Node
	if node != null and _is_protected(node):
		protected_hit.emit(hit, node)
		return
	var receiver := _find_receiver(node)
	if receiver != null:
		receiver.call(&"receive_damage", hit, 0)
		damage_applied.emit(hit, receiver)
		return
	var body := collider as RigidBody3D
	if body != null and hit.impulse > 0.0:
		var dir := hit.direction if hit.direction != Vector3.ZERO else (body.global_position - hit.position).normalized()
		body.apply_impulse(dir * hit.impulse, hit.position - body.global_position)
		damage_applied.emit(hit, body)


func _is_protected(node: Node) -> bool:
	var n := node
	for i in 4:
		if n == null:
			return false
		if n.is_in_group(&"protected"):
			return true
		n = n.get_parent()
	return false


func _find_receiver(node: Node) -> Object:
	var n := node
	for i in 4:
		if n == null:
			return null
		if n.has_method(&"receive_damage"):
			return n
		n = n.get_parent()
	return null


func _closest_point_guess(collider: Object, rid: RID, center: Vector3) -> Vector3:
	var n3 := collider as Node3D
	if n3 != null:
		return n3.global_position
	if rid.is_valid():
		var xf: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
		return xf.origin
	return center
