class_name ThrownBodyWatcher
extends Node
## Attached under a body the cat threw. Turns its impacts into BLUNT DamageHits (energy 0.5*m*v^2 of
## the relative pre-impact speed) through DamageRouter, then restores the body and frees itself.

const MIN_IMPACT_SPEED := 3.5
const MAX_LIFETIME := 6.0
const REHIT_COOLDOWN := 0.2

var body: RigidBody3D
var source: Node
var cause_id := 0
var hits_dealt := 0
var energy_dealt := 0.0

var _prev_velocity := Vector3.ZERO
var _age := 0.0
var _slow_t := 0.0
var _last_hit := {}   # collider RID -> age of last hit
var _saved_monitor := false
var _saved_max_contacts := 0
var _saved_ccd := false
var _retired := false   # replaced by a newer watcher: must neither report nor restore anything
var _source_rid := RID()   # resolved once: the thrower may be freed while the body still flies


static func attach(target: RigidBody3D, thrower: Node) -> ThrownBodyWatcher:
	var w := ThrownBodyWatcher.new()
	w._saved_monitor = target.contact_monitor
	w._saved_max_contacts = target.max_contacts_reported
	w._saved_ccd = target.continuous_cd
	for c in target.get_children():
		var old := c as ThrownBodyWatcher
		if old != null and not old._retired:
			# Thrown again before the previous watcher finished: the body's own settings are the ones
			# that watcher saved, not the ones it switched on.
			w._saved_monitor = old._saved_monitor
			w._saved_max_contacts = old._saved_max_contacts
			w._saved_ccd = old._saved_ccd
			old._retired = true
			old.queue_free()
	w.name = "ThrownBodyWatcher"
	w.body = target
	w.source = thrower
	if thrower is CollisionObject3D:
		w._source_rid = (thrower as CollisionObject3D).get_rid()
	w.cause_id = DamageRouter.new_cause_id()
	target.add_child(w)
	return w


func _ready() -> void:
	body.contact_monitor = true
	body.max_contacts_reported = maxi(_saved_max_contacts, 6)
	# Up to 32 m/s is 0.53 m per tick: without CCD small pieces pass through panes and thin walls.
	body.continuous_cd = true
	_prev_velocity = body.linear_velocity


func _physics_process(delta: float) -> void:
	if _retired:
		return
	if not is_instance_valid(body):
		queue_free()
		return
	_age += delta
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state != null:
		for i in state.get_contact_count():
			_consider_contact(state, i)
	var v := body.linear_velocity
	_slow_t = _slow_t + delta if v.length() < 1.2 else 0.0
	_prev_velocity = v
	if _age > MAX_LIFETIME or _slow_t > 0.4:
		_finish()


func _consider_contact(state: PhysicsDirectBodyState3D, i: int) -> void:
	var rid := state.get_contact_collider(i)
	if rid == _source_rid:
		return
	if _last_hit.has(rid) and _age - float(_last_hit[rid]) < REHIT_COOLDOWN:
		return
	var other_v := state.get_contact_collider_velocity_at_position(i)
	var rel := _prev_velocity - other_v
	var speed := rel.length()
	if speed < MIN_IMPACT_SPEED:
		return
	_last_hit[rid] = _age
	var energy := 0.5 * body.mass * speed * speed
	var pos := state.get_contact_collider_position(i)
	var hit := DamageHit.point(pos, rel, energy, body.mass * speed, DamageHit.Kind.BLUNT, source if is_instance_valid(source) else null)
	hit.normal = state.get_contact_local_normal(i)
	hit.cause_id = cause_id
	hits_dealt += 1
	energy_dealt += energy
	DamageRouter.apply_hit(hit, state.get_contact_collider_object(i), rid)


func _finish() -> void:
	if is_instance_valid(body):
		body.contact_monitor = _saved_monitor
		body.max_contacts_reported = _saved_max_contacts
		body.continuous_cd = _saved_ccd
	queue_free()
