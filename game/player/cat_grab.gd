class_name CatGrab
extends Node
## Telekinetic grab and throw. E picks the best RigidBody3D in front of the cat (rubble is woken via
## Game.debris.wake_rubble first), holds it overhead with a velocity drive (no reparenting) and a glow;
## LMB charges and throws it along the camera aim. ThrownBodyWatcher turns its impacts into damage.

signal grabbed(body: RigidBody3D)
signal released(body: RigidBody3D, thrown: bool)

const GRAB_MASK := Layers.PROPS | Layers.DEBRIS | Layers.DEBRIS_SMALL | Layers.RUBBLE
const GLOW_SHADER := preload("res://game/player/telekinesis_glow.gdshader")

@export var grab_range := 2.5
@export var mass_limit := 400.0
@export var hold_stiffness := 14.0      ## 1/s, light bodies; heavy ones are softer.
@export var max_hold_speed := 22.0
@export var throw_speed_min := 13.0
@export var throw_speed_max := 32.0
@export var throw_charge_time := 0.7

var cat: CatPlayer
var held: RigidBody3D = null
var charging := false
var charge := 0.0

var _saved := {}
var _glow_light: OmniLight3D = null
var _overlays: Array = []   # [MeshInstance3D, previous overlay]
var _hold_extent := 0.5
var _stuck_t := 0.0
var _pending_rubble_pos := Vector3.ZERO
var _pending_ticks := 0
var _glow_mat: ShaderMaterial = null
var _held_rid := RID()


func setup(owner_cat: CatPlayer) -> void:
	cat = owner_cat


func is_holding() -> bool:
	return held != null and is_instance_valid(held)


## E pressed: grab if empty-handed, otherwise set the held body down gently.
func toggle() -> void:
	if is_holding():
		release(Vector3.ZERO)
	else:
		try_grab()


func try_grab() -> bool:
	var space := cat.get_world_3d().direct_space_state
	var origin := cat.get_chest_position()
	var fwd := cat.get_aim_forward()
	_pending_ticks = 0
	# A rubble piece straight ahead is woken first so it can be grabbed as a dynamic body.
	var rq := PhysicsRayQueryParameters3D.create(origin, origin + fwd * grab_range, GRAB_MASK | Layers.STRUCTURE | Layers.TERRAIN)
	rq.exclude = [cat.get_rid()]
	var ray := space.intersect_ray(rq)
	var rubble_hit := false
	if not ray.is_empty():
		var rid: RID = ray.get("rid", RID())
		if rid.is_valid() and (PhysicsServer3D.body_get_collision_layer(rid) & Layers.RUBBLE) != 0:
			var woke := _wake_rubble(rid)
			if woke != null:
				return _grab_body(woke)
			_pending_rubble_pos = ray["position"]
			rubble_hit = true
	var best := _find_best(space, origin, fwd)
	if best != null:
		return _grab_body(best)
	if rubble_hit:
		_pending_ticks = 3   # rubble may need a physics step to turn dynamic
	return false


func _wake_rubble(rid: RID) -> RigidBody3D:
	if Game.debris == null or not Game.debris.has_method(&"wake_rubble"):
		return null
	var r: Variant = Game.debris.call(&"wake_rubble", rid)
	return r as RigidBody3D if r is RigidBody3D else null


func _find_best(space: PhysicsDirectSpaceState3D, origin: Vector3, fwd: Vector3) -> RigidBody3D:
	var sphere := SphereShape3D.new()
	sphere.radius = grab_range
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, origin)
	q.collision_mask = GRAB_MASK
	q.exclude = [cat.get_rid()]
	var best: RigidBody3D = null
	var best_score := INF
	for r in space.intersect_shape(q, 48):
		var body := r.get("collider") as RigidBody3D
		if body == null or not _grabbable(body):
			continue
		var to := body.global_position - origin
		var d := to.length()
		var facing := fwd.dot(to / maxf(d, 0.001))
		if facing < -0.15:
			continue
		var score := d * (1.7 - facing)
		if score < best_score:
			best_score = score
			best = body
	return best


func _grabbable(body: RigidBody3D) -> bool:
	return not body.freeze and body.mass <= mass_limit and not is_protected(body)


## Same rule as DamageRouter: the node or one of its first ancestors is in group "protected".
static func is_protected(node: Node) -> bool:
	var n := node
	for i in 4:
		if n == null:
			return false
		if n.is_in_group(&"protected"):
			return true
		n = n.get_parent()
	return false


func _grab_body(body: RigidBody3D) -> bool:
	if not _grabbable(body):
		return false
	held = body
	_held_rid = body.get_rid()
	charging = false
	charge = 0.0
	_pending_ticks = 0
	_pending_rubble_pos = Vector3.ZERO
	_saved = {"gravity_scale": body.gravity_scale, "can_sleep": body.can_sleep, "angular_damp": body.angular_damp}
	body.gravity_scale = 0.0
	body.can_sleep = false
	body.sleeping = false
	body.angular_damp = 4.0
	body.add_collision_exception_with(cat)
	cat.add_collision_exception_with(body)
	if cat.camera != null:
		cat.camera.set_arm_exclusion(body.get_rid(), true)
	_hold_extent = _estimate_extent(body)
	_stuck_t = 0.0
	_apply_glow(body)
	grabbed.emit(body)
	return true


## Releases the held body. A non-zero velocity is a throw.
func release(throw_velocity: Vector3) -> void:
	if not is_holding():
		if _held_rid.is_valid():
			_forget_freed_body()
		return
	var body := held
	held = null
	_held_rid = RID()
	charging = false
	if cat.camera != null:
		cat.camera.set_arm_exclusion(body.get_rid(), false)
	_remove_glow(body)
	body.gravity_scale = _saved.get("gravity_scale", 1.0)
	body.can_sleep = _saved.get("can_sleep", true)
	body.angular_damp = _saved.get("angular_damp", 0.0)
	var thrown := throw_velocity != Vector3.ZERO
	if thrown:
		body.linear_velocity = throw_velocity
		body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4)) * clampf(60.0 / body.mass, 0.2, 1.0)
		ThrownBodyWatcher.attach(body, cat)
	else:
		body.linear_velocity = cat.velocity * 0.5
	# Keep ignoring the cat briefly so the throw does not clip it. Bound by id: the body may be freed
	# (shattered, converted to rubble) before the timer fires.
	get_tree().create_timer(0.3, true, true).timeout.connect(_restore_collision.bind(body.get_instance_id(), body.get_rid()))
	released.emit(body, thrown)


func begin_throw_charge() -> void:
	if is_holding():
		charging = true
		charge = 0.0


## Throws along the camera aim with the accumulated charge. Returns the throw velocity.
func finish_throw() -> Vector3:
	if not is_holding():
		charging = false
		return Vector3.ZERO
	var mass_k := clampf(sqrt(120.0 / maxf(held.mass, 1.0)), 0.35, 1.0)
	var speed := lerpf(throw_speed_min, throw_speed_max, charge) * mass_k
	# Aim above the crosshair point by the ballistic drop so the body arrives where the camera points.
	var from := held.global_position
	var target := cat.get_aim_point()
	var d := from.distance_to(target)
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * float(_saved.get("gravity_scale", 1.0))
	var t := d / maxf(speed, 1.0)
	target += Vector3.UP * minf(0.5 * g * t * t, d * 0.5)
	var dir := (target - from).normalized()
	if dir.length_squared() < 0.5:
		dir = cat.get_aim_forward()
	if d < 4.0 or dir.y < -0.35:
		# The crosshair is on the ground right in front of her: a throw that would go into the floor goes
		# forward in an arc instead.
		var fwd := cat.get_aim_forward()
		fwd.y = 0.0
		dir = (fwd.normalized() + Vector3.UP * 0.3).normalized() if fwd.length_squared() > 0.01 else Vector3.UP
	var v := dir * speed
	release(v)
	return v


func tick(delta: float) -> void:
	if _pending_ticks > 0:
		_pending_ticks -= 1
		var space := cat.get_world_3d().direct_space_state
		var b := _find_best(space, _pending_rubble_pos, cat.get_aim_forward())
		if b != null:
			_grab_body(b)
	if _held_rid.is_valid() and not is_instance_valid(held):
		_forget_freed_body()   # (a freed object compares equal to null, so test the RID instead)
	if not is_holding():
		return
	if held.freeze or not held.is_inside_tree():
		release(Vector3.ZERO)   # another system froze it (rubble budget) or took it out of the world
		return
	if charging:
		charge = minf(charge + delta / throw_charge_time, 1.0)
	var target := get_hold_point()
	var to := target - held.global_position
	var k := lerpf(hold_stiffness, 5.0, clampf(held.mass / mass_limit, 0.0, 1.0))
	var want := to * k
	if want.length() > max_hold_speed:
		want = want.normalized() * max_hold_speed
	var blend := 1.0 - exp(-18.0 * delta)
	held.linear_velocity = held.linear_velocity.lerp(want + cat.velocity * 0.85, blend)
	held.angular_velocity = held.angular_velocity.lerp(Vector3(0.0, 0.6, 0.0), 1.0 - exp(-4.0 * delta))
	_stuck_t = _stuck_t + delta if to.length() > 3.0 else 0.0
	if _stuck_t > 0.6:
		release(Vector3.ZERO)
	elif _glow_light != null:
		_glow_light.light_energy = 0.9 + 0.35 * sin(Time.get_ticks_msec() * 0.006) + charge * 1.2


## Where the held body is driven to: in front of and above the standing cat's raised paws, drawn
## back over the head while a throw charges.
func get_hold_point() -> Vector3:
	var fwd := cat.get_facing()
	var c := charge if charging else 0.0
	var up := lerpf(0.55 + _hold_extent * 0.85, 0.75 + _hold_extent, c)
	var ahead := lerpf(0.32 + _hold_extent * 0.5, 0.0, c)
	return cat.global_position + Vector3.UP * up + fwd * ahead


func get_hold_extent() -> float:
	return _hold_extent if is_holding() else 0.0


func _estimate_extent(body: RigidBody3D) -> float:
	var r := 0.25
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var s := cs.shape
		var e := 0.25
		if s is BoxShape3D:
			e = (s as BoxShape3D).size.length() * 0.5
		elif s is SphereShape3D:
			e = (s as SphereShape3D).radius
		elif s is CapsuleShape3D:
			e = (s as CapsuleShape3D).height * 0.5
		elif s is CylinderShape3D:
			e = maxf((s as CylinderShape3D).height * 0.5, (s as CylinderShape3D).radius)
		else:
			e = s.get_debug_mesh().get_aabb().size.length() * 0.5
		r = maxf(r, e + cs.position.length())
	return clampf(r, 0.15, 2.5)


func _apply_glow(body: RigidBody3D) -> void:
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = GLOW_SHADER
	_overlays.clear()
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		_overlays.append([m, m.material_overlay])
		m.material_overlay = _glow_mat
	_glow_light = OmniLight3D.new()
	_glow_light.name = "TelekinesisGlow"
	_glow_light.light_color = Color(0.45, 0.8, 1.0)
	_glow_light.light_energy = 1.0
	_glow_light.omni_range = 1.4 + _hold_extent * 2.0
	_glow_light.shadow_enabled = false
	body.add_child(_glow_light)


func _remove_glow(_body: RigidBody3D) -> void:
	for pair in _overlays:
		var m: MeshInstance3D = pair[0]
		if is_instance_valid(m):
			m.material_overlay = pair[1]
	_overlays.clear()
	if is_instance_valid(_glow_light):
		_glow_light.queue_free()
	_glow_light = null


func _restore_collision(body_id: int, rid: RID) -> void:
	var body := instance_from_id(body_id) as RigidBody3D
	if body != null and body == held:
		return   # grabbed again meanwhile: the exceptions stay
	if body != null:
		body.remove_collision_exception_with(cat)
	PhysicsServer3D.body_remove_collision_exception(cat.get_rid(), rid)


## The held body was freed by another system while held: drop every reference to it.
func _forget_freed_body() -> void:
	held = null
	charging = false
	if cat.camera != null:
		cat.camera.set_arm_exclusion(_held_rid, false)
	PhysicsServer3D.body_remove_collision_exception(cat.get_rid(), _held_rid)
	_held_rid = RID()
	_overlays.clear()
	_glow_light = null
