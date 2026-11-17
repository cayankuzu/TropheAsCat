class_name PawTool
extends CatTool
## Tool 1: the paw swat. A short capsule sweep in front of the cat delivers a BLUNT DamageHit
## (about 3 kJ / 300 N*s) through DamageRouter at the strike frame of the swat animation.
## The ground itself (TERRAIN) is not swatted.

const SWAT_MASK := Layers.DAMAGEABLE & ~Layers.TERRAIN

@export var energy_j := 3000.0
@export var impulse_ns := 300.0
@export var reach := 0.95          ## Capsule length in front of the chest.
@export var radius := 0.26
@export var cooldown := 0.38
@export var strike_delay := 0.11   ## Seconds from input to contact (matches the swat clip at rate 1.8).

var swats := 0
var last_hits: Array = []   ## Colliders hit by the most recent swat (tests read this).

var _cooldown_left := 0.0
var _strike_left := -1.0
var _shape := CapsuleShape3D.new()


func _init() -> void:
	tool_name = "Paw"


func primary(pressed: bool) -> void:
	if not pressed or cat == null or _cooldown_left > 0.0:
		return
	_cooldown_left = cooldown
	_strike_left = strike_delay
	cat.on_swat_started()


func is_busy() -> bool:
	return _strike_left > 0.0


func process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _strike_left > 0.0:
		_strike_left -= delta
		if _strike_left <= 0.0:
			_strike()


func _strike() -> void:
	swats += 1
	last_hits.clear()
	var fwd := cat.get_aim_forward()
	var origin := cat.get_chest_position()
	_shape.radius = radius
	_shape.height = reach + radius * 2.0
	var basis := Basis(Quaternion(Vector3.UP, fwd))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.collision_mask = SWAT_MASK
	q.exclude = [cat.get_rid()]
	q.transform = Transform3D(basis, origin + fwd * (reach * 0.5))
	var space := cat.get_world_3d().direct_space_state
	var hits := space.intersect_shape(q, 8)
	var cause := DamageRouter.new_cause_id()
	var done := {}
	for h in hits:
		var rid: RID = h.get("rid", RID())
		if done.has(rid):
			continue
		done[rid] = true
		var collider: Object = h.get("collider")
		var p := _contact_point(space, origin, fwd, rid, collider)
		var hit := DamageHit.point(p, fwd, energy_j, impulse_ns, DamageHit.Kind.BLUNT, cat)
		hit.cause_id = cause
		hit.normal = -fwd
		DamageRouter.apply_hit(hit, collider, rid)
		last_hits.append(collider)
	if not hits.is_empty():
		cat.on_swat_connected(hits.size())


func _contact_point(space: PhysicsDirectSpaceState3D, origin: Vector3, fwd: Vector3, rid: RID, collider: Object) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * (reach + radius + 0.3), SWAT_MASK)
	q.exclude = [cat.get_rid()]
	var r := space.intersect_ray(q)
	if not r.is_empty() and r.get("rid") == rid:
		return r["position"]
	var n3 := collider as Node3D
	if n3 != null:
		return origin.lerp(n3.global_position, 0.5)
	return origin + fwd * (reach * 0.7)
