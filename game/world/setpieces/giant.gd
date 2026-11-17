class_name Giant
extends RigidBody3D
## A giant of a set piece (2026-11-17): the Ferris wheel of the fair, the tower crane of the Yards, the
## clock tower of the Old Quarter. It stands still (frozen, solid, climbable) and takes what is thrown at it
## until it has taken `hold_j` joules; then it lets go (`release`): it tips over away from the last hit, or
## the wheel starts to roll. Everything it runs into or lands on is hit with the energy of the contact, so
## it crushes cars, props, people and walls on its way. A falling giant breaks into its sections when it
## comes down (each one a debris piece that goes on tumbling); the wheel breaks when it falls on its side.
##
## Its sections ({mesh, shape, xf, mass, material}) are drawn and collide as one body until it breaks.
## A released giant out of reach of the terrain around Trophe waits frozen until she comes back. A rewind
## to before the release puts it back where it stood.

signal let_go(giant: Giant)
signal broke(giant: Giant)

enum Fall { TIP, ROLL }

const CONTACT_MIN_SPEED := 1.6   ## m/s of closing speed from which a contact hurts
const CONTACT_MAX_J := 450000.0
const CONTACT_COOLDOWN := 0.3
const FAR := 110.0               ## a released giant farther than this from Trophe waits frozen

var title := ""
var hold_j := 150000.0
var taken := 0.0
var fall := Fall.TIP
var released := false
var broken := false
var released_at := -1.0
var home := Transform3D.IDENTITY
## Sections: {mesh, shape, xf (local), mass, material}.
var sections: Array[Dictionary] = []
## The way a rolling giant rolls when the hit gives no better hint (a unit vector on the ground).
var roll_hint := Vector3.RIGHT

var _contacts: Array = []          # [collider object, rid, point, normal, speed] gathered in the physics step
var _cooldown := {}                # collider id -> seconds of the clock until it can be hit again
var _last_dir := Vector3.ZERO
var _waiting := false
var _down_t := 0.0
## Half the width of its base the way it tips: it turns round that edge while it tips.
var base_half := 1.0
var tipping := false
var _pivot := Vector3.ZERO
var _axis := Vector3.ZERO
var _omega := 0.0
var _d := 1.0                      # pivot to centre of mass
var _r2 := 1.0                     # radius of gyration about the centre of mass, squared
var _height := 1.0
var _free_t := 0.0                 # seconds since it stopped turning round its base
var _rng := RandomNumberGenerator.new()


## Builds the body from its sections: a visual and a collision shape each, the mass and centre of mass of
## them all. Call before it enters the tree.
func build(list: Array[Dictionary], extra_shapes: Array = []) -> void:
	sections = list
	var total := 0.0
	var com := Vector3.ZERO
	for s in sections:
		var box: Shape3D = s.get("shape")
		var top := (s["xf"] as Transform3D).origin.y + ((box as BoxShape3D).size.y * 0.5 if box is BoxShape3D else 0.0)
		_height = maxf(_height, top)
		var mi := MeshInstance3D.new()
		mi.mesh = s["mesh"]
		mi.transform = s["xf"]
		add_child(mi)
		if s.get("shape") != null and not bool(s.get("no_collide", false)):
			var cs := CollisionShape3D.new()
			cs.shape = s["shape"]
			cs.transform = s["xf"]
			add_child(cs)
		total += float(s["mass"])
		com += (s["xf"] as Transform3D).origin * float(s["mass"])
	for e: Array in extra_shapes:   # [shape, transform]: one smooth shape instead of the sections' (the wheel)
		var cs := CollisionShape3D.new()
		cs.shape = e[0]
		cs.transform = e[1]
		add_child(cs)
	mass = maxf(total, 1.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com / maxf(total, 1.0)
	collision_layer = Layers.STRUCTURE
	collision_mask = Layers.TERRAIN | Layers.STRUCTURE | Layers.DEBRIS | Layers.RUBBLE | Layers.PROPS | Layers.PROTECTED | Layers.PLAYER
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	contact_monitor = true
	max_contacts_reported = 12
	continuous_cd = true
	can_sleep = false
	_rng.randomize()


func _ready() -> void:
	home = global_transform
	DamageRouter.register_rid(get_rid(), self, 0)
	Progress.add_total_mass(mass)
	Timeline.rewind_stopped.connect(_after_rewind)


func _exit_tree() -> void:
	DamageRouter.unregister_rid(get_rid())


## DamageRouter entry: hits add up; past `hold_j` it lets go, away from the last hit.
func receive_damage(hit: DamageHit, _user_id: int) -> void:
	if broken:
		return
	var d := hit.direction if hit.direction != Vector3.ZERO else (global_position - hit.position)
	d.y = 0.0
	if d.length_squared() > 0.0001:
		_last_dir = d.normalized()
	if released:
		if hit.impulse > 0.0 and not freeze:
			apply_impulse(_last_dir * minf(hit.impulse, mass * 2.0), hit.position - global_position)
		return
	taken += hit.energy
	if taken >= hold_j:
		release()


func release() -> void:
	if released:
		return
	released = true
	released_at = Timeline.now
	freeze = false
	sleeping = false
	var dir := _last_dir if _last_dir != Vector3.ZERO else Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	match fall:
		Fall.ROLL:
			# Along its own plane, the way the hit pushed it (or the way it was told to go).
			var axle := global_basis.z.normalized()
			var along := (dir - axle * dir.dot(axle))
			along = along.normalized() if along.length_squared() > 0.04 else roll_hint
			if along.dot(roll_hint) < -0.2 and _rng.randf() < 0.5:
				along = roll_hint
			var radius := 13.5
			var speed := 6.5
			linear_velocity = along * speed
			angular_velocity = Vector3.UP.cross(along).normalized() * (speed / radius)
		_:
			# It turns round the edge of its base away from the hit, like a felled tree, faster and faster
			# (see _integrate_forces), and falls freely from 60 degrees on.
			_axis = Vector3.UP.cross(dir).normalized()
			_pivot = global_position + dir * base_half
			_d = maxf(_pivot.distance_to(global_transform * center_of_mass), 1.0)
			_r2 = _height * _height / 12.0
			_omega = 0.3
			tipping = true
	Progress.report_break(12)
	let_go.emit(self)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not released or broken:
		return
	if tipping:
		var com := state.transform * center_of_mass
		var arm := com - _pivot
		var lean := clampf(Vector2(arm.x, arm.z).length() / maxf(arm.length(), 0.01), 0.0, 1.0)
		_omega += 1.4 * 9.8 * _d * lean / (_d * _d + _r2) * state.step
		state.angular_velocity = _axis * _omega
		state.linear_velocity = (_axis * _omega).cross(arm)
		if state.transform.basis.y.normalized().dot(Vector3.UP) < 0.5:
			tipping = false
	for i in state.get_contact_count():
		var obj := state.get_contact_collider_object(i)
		var rid := state.get_contact_collider(i)
		var point := state.get_contact_collider_position(i)
		var normal := state.get_contact_local_normal(i)
		var v := state.get_velocity_at_local_position(point - state.transform.origin) - state.get_contact_collider_velocity_at_position(i)
		var speed := absf(v.dot(normal))
		if speed >= CONTACT_MIN_SPEED:
			_contacts.append([obj, rid, point, -normal, speed])


func _physics_process(delta: float) -> void:
	if not released or broken:
		return
	var player := Game.player
	if player != null and is_instance_valid(player):
		var far := global_position.distance_to(player.global_position) > FAR
		if far and not freeze:
			freeze = true      # no ground out there: it waits
			_waiting = true
		elif not far and _waiting:
			freeze = false
			_waiting = false
	var now := Time.get_ticks_msec() * 0.001
	for c: Array in _contacts:
		var obj: Object = c[0]
		var key := obj.get_instance_id() if obj != null else int(c[1].get_id())
		if float(_cooldown.get(key, 0.0)) > now:
			continue
		_cooldown[key] = now + CONTACT_COOLDOWN
		var speed: float = c[4]
		var share := mass * 0.25
		var energy := minf(0.5 * share * speed * speed, CONTACT_MAX_J)
		var hit := DamageHit.point(c[2], c[3], energy, share * speed * 0.3, DamageHit.Kind.CRUSH, self)
		DamageRouter.apply_hit(hit, obj, c[1])
	var hardest := 0.0
	for c: Array in _contacts:
		hardest = maxf(hardest, float(c[4]))
	_contacts.clear()
	if fall == Fall.TIP and not tipping:
		_free_t += delta
		if hardest > 3.5 or _free_t > 2.5:
			break_up()   # it came down on something (or it has been falling long enough)
			return
	# A falling giant breaks when it is down; the wheel when it lies on its side.
	var down := false
	if fall == Fall.ROLL:
		down = absf(global_basis.z.normalized().dot(Vector3.UP)) > 0.75
	else:
		down = global_basis.y.normalized().dot(Vector3.UP) < 0.55
	_down_t = _down_t + delta if down else 0.0
	if _down_t > (0.25 if fall == Fall.TIP else 0.6):
		break_up()


## Into its sections: each one a debris piece moving the way that part of it moved.
func break_up() -> void:
	if broken:
		return
	broken = true
	var debris := Game.debris as DebrisManager
	var xf := global_transform
	var com := xf * center_of_mass
	var cause := DamageRouter.new_cause_id()
	if debris != null:
		debris.make_room(sections.size())
		for s in sections:
			if bool(s.get("no_piece", false)):
				continue
			var at: Transform3D = xf * (s["xf"] as Transform3D)
			var v := linear_velocity + angular_velocity.cross(at.origin - com)
			debris.spawn_piece(s["mesh"], s["shape"], at, Vector3.ZERO, float(s["mass"]), v, angular_velocity * 0.6, DebrisManager.T1, s.get("material", &"steel"), cause)
	Progress.add_destroyed_mass(mass)
	Progress.report_break(sections.size())
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	DamageRouter.unregister_rid(get_rid())
	broke.emit(self)


## A rewind to before it let go: it stands again where it stood.
func _after_rewind() -> void:
	if not released or released_at < 0.0 or Timeline.now > released_at:
		return
	released = false
	broken = false
	tipping = false
	_free_t = 0.0
	taken = 0.0
	_down_t = 0.0
	_waiting = false
	_contacts.clear()
	visible = true
	freeze = true
	global_transform = home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = Layers.STRUCTURE
	collision_mask = Layers.TERRAIN | Layers.STRUCTURE | Layers.DEBRIS | Layers.RUBBLE | Layers.PROPS | Layers.PROTECTED | Layers.PLAYER
	DamageRouter.register_rid(get_rid(), self, 0)
	reset_physics_interpolation()
