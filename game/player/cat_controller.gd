class_name CatPlayer
extends CharacterBody3D
## Trophe, the player cat: locomotion (walk / trot / gallop / stalk), jump + charged pounce, wall
## climbing with mantles and wall jumps, rearing up on the hind legs to aim / hold / throw, grab and
## throw, tools, sky drops from the void and lava launches. There is no health and no death.
##
## Physics: one sphere (r = RADIUS) on Layers.PLAYER, colliding with Layers.WALKABLE. The node origin is
## at the paws. The visual (Visual/Model) is smoothed per rendered frame; gameplay runs at the physics
## tick. Bots and tests drive the cat through `bot_input` instead of the InputMap.

signal mode_changed(old_mode: int, new_mode: int)
signal landed(impact_speed: float)
signal dropped_from_sky(at: Vector3)
signal lava_launched(at: Vector3)
signal threw(body: RigidBody3D, velocity: Vector3)

enum Mode { GROUND, AIR, CLIMB, MANTLE }

const MODEL_SCALE := 0.66          ## GLB withers 0.50 -> 0.33 m, nose to tail tip 0.66 m.
const BODY_CENTER_Z := 0.07        ## Model-space z of the torso centre, placed over the sphere.
const RADIUS := 0.19
const CLIMB_MODEL_ANCHOR := Vector3(0.0, 0.8, 0.17)   ## Model point pinned to the wall contact in the climb clip.
const WORLD_LIMIT_XZ := 560.0
const WORLD_LIMIT_Y := -60.0
const RESPAWN_HALF := 450.0
const SKY_HEIGHT := 250.0
const FLOOR_COS := 0.64             ## cos(50 deg): steeper than this is a wall.
const CAT_RENDER_LAYER := 1 << 1    ## Visual layer of the cat meshes (contact-shadow decal skips it).
const HEAD_BONE := "head_12"
## Head-bone space (model units): +Y runs to the nose, +Z out of the top of the skull.
const MOUTH_LOCAL := Vector3(0.0, 0.1, -0.05)
const EYES_LOCAL := Vector3(0.0, 0.115, 0.033)

@export_group("Ground speeds (m/s)")
@export var walk_speed := 2.2
@export var trot_speed := 5.0
@export var gallop_speed := 13.0
@export var stalk_speed := 0.5
@export var stand_speed := 1.3
@export_group("Ground handling")
@export var accel := 20.0
@export var gallop_accel := 12.5
@export var brake := 26.0
@export var turn_rate_slow := 11.0
@export var turn_rate_fast := 6.0
@export var step_height := 0.45
@export_group("Air")
@export var jump_height := 1.6
@export var gravity_up := 22.0
@export var gravity_down := 31.0
@export var jump_cut_gravity := 55.0
@export var terminal_speed := 55.0
@export var air_accel := 9.0
@export var sky_air_accel := 16.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.15
@export_group("Pounce")
@export var pounce_charge_time := 0.85
@export var pounce_tap_time := 0.16
@export var pounce_min_height := 1.4
@export var pounce_max_height := 6.0
@export var pounce_min_distance := 3.0
@export var pounce_max_distance := 14.0
@export var charge_max_speed := 3.2   ## Crouching slower than this, Space charges a pounce instead of jumping.
@export_group("Climb")
@export var climb_speed := 2.6
@export var climb_sprint_speed := 4.2
@export var mantle_time := 0.42
@export var wall_jump_out := 6.0
@export var wall_jump_up := 7.5
@export_group("Landing")
@export var heavy_landing_speed := 9.0
@export var blast_landing_speed := 22.0
@export var landing_mass := 60.0    ## Effective mass of the super cat in landing blasts (kg).
@export_group("Lava")
@export var lava_launch_speed := 35.0

var mode: int = Mode.AIR
## When set, the controller reads this every tick instead of the InputMap (bots, tests, replays).
var bot_input: CatInput = null
var camera: CatCamera
var animator: CatAnimator
var grab: CatGrab
var belt: ToolBelt
## Follows the head bone (after the pose modifier): hats, eye beams and the mouth hang off it.
var head_socket: BoneAttachment3D
## Follows the hips bone the same way: where the pee leaves her.
var hip_socket: BoneAttachment3D
var pose: CatPoseModifier
var stats := {
	"max_overlap_time": 0.0, "depenetrations": 0, "safe_resets": 0, "nonfinite": 0, "sky_drops": 0,
	"lava_launches": 0, "landings": 0, "max_impact": 0.0, "landing_blasts": 0, "climbs": 0, "mantles": 0,
	"wall_jumps": 0, "pounces": 0, "jumps": 0, "step_ups": 0, "throws": 0,
}

var _visual: Node3D
var _model: Node3D
var _shadow: Decal
var _in := CatInput.new()
var _prev := CatInput.new()
var _queued_slot := -1
var _queued_cycle := 0
var _facing := Vector3.FORWARD
var _speed := 0.0
var _anim_speed := 0.0
var _yaw_rate := 0.0
var _bend := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _jumped := false
var _jump_held_rise := false
var _charging := false
var _charge_t := 0.0
var _queued_jump := 0.0   # seconds a jump pressed during a landing waits
var _pounce := false
var _land_lock := 0.0
var _land_lock_total := 0.0
var _wall_n := Vector3.BACK
var _wall_push_t := 0.0
var _climb_cooldown := 0.0
var _climb_boost := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _sky_drop := false
## Called instead of the plain re-drop when she leaves the Table (the Underneath sets it; game/world/edge).
var void_handler: Callable = Callable()
var _spin_axis := Vector3.RIGHT
var _spin_angle := 0.0
var _spin_speed := 0.0
var _lava_cd := 0.0
var _wedged_t := 0.0
var _stand := 0.0
var _throw_pose := 0.0
var _aim_hold := 0.0     ## Seconds a tool still wants the upright, camera-facing stance.
var _arms_hold := 0.0    ## Seconds a tool still wants the front paws held forward.
var _tall_hold := 0.0    ## Seconds a tool still wants her bolt upright (see hold_tall_stance).
var _ground_up := Vector3.UP
var _vel_before := Vector3.ZERO
var _visual_offset := Vector3.ZERO
var _vis_quat := Quaternion.IDENTITY
var _climb_w := 0.0
var _idle_t := 0.0
var _overlap_t := 0.0
var _safe_pos := Vector3.ZERO
var _safe_t := 0.0
var _focus_h := 0.36
var _hit_stop_seq := 0
var _probe_shape := SphereShape3D.new()
var _probe_query := PhysicsShapeQueryParameters3D.new()
var _ray_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_ensure_input_actions()
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WALKABLE
	add_to_group(&"protected")
	add_to_group(&"player")
	floor_max_angle = acos(FLOOR_COS)
	floor_snap_length = 0.32
	floor_constant_speed = true
	floor_block_on_wall = true
	floor_stop_on_slope = true
	max_slides = 6
	safe_margin = 0.01
	_visual = $Visual
	_model = $Visual/Model
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * MODEL_SCALE), _ground_model_origin())
	var skel: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = _model.find_child("AnimationPlayer", true, false)
	animator = $Animator
	animator.setup(_model, ap, skel, MODEL_SCALE)
	pose = CatPoseModifier.new()
	pose.name = "CatPoseModifier"
	skel.add_child(pose)
	head_socket = BoneAttachment3D.new()
	head_socket.name = "HeadSocket"
	skel.add_child(head_socket)
	head_socket.bone_name = HEAD_BONE
	hip_socket = BoneAttachment3D.new()
	hip_socket.name = "HipSocket"
	skel.add_child(hip_socket)
	hip_socket.bone_name = CatPoseModifier.B_HIPS
	_tune_materials()
	_add_contact_shadow()
	camera = $CameraRig
	camera.target = self
	grab = $Grab
	grab.setup(self)
	belt = $ToolBelt
	belt.setup(self)
	belt.set_tool(0, $ToolBelt/Paw)
	ToolKit.attach(self)
	var f := -global_basis.z
	_facing = Vector3(f.x, 0.0, f.z).normalized() if absf(f.y) < 0.99 else Vector3.FORWARD
	camera.yaw = atan2(-_facing.x, -_facing.z)
	_vis_quat = _visual_basis(_facing, Vector3.UP).get_rotation_quaternion()
	_safe_pos = global_position
	_probe_query.shape = _probe_shape
	_probe_query.collision_mask = Layers.WALKABLE
	_probe_query.exclude = [get_rid()]
	_ray_query.collision_mask = Layers.WALKABLE
	_ray_query.exclude = [get_rid()]
	Game.register_player(self)
	_set_mode(Mode.AIR)


## Game.player must not dangle once this cat is freed (level unload / reload); a newer cat that already
## registered itself is left alone.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(Game) and is_same(Game.player, self):
		Game.player = null


## Player-module input actions that game/core does not define (yet): "walk" (Alt) for the slow tier.
static func _ensure_input_actions() -> void:
	if InputMap.has_action(&"walk"):
		return
	InputMap.add_action(&"walk")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ALT
	InputMap.action_add_event(&"walk", ev)


func _unhandled_input(event: InputEvent) -> void:
	if bot_input != null:
		return
	for i in ToolBelt.SLOT_COUNT:
		if event.is_action_pressed(StringName("tool_%d" % (i + 1))):
			_queued_slot = i
	if event.is_action_pressed(&"tool_next") or event.is_action_pressed(&"tool_wheel_down"):
		_queued_cycle += 1
	elif event.is_action_pressed(&"tool_wheel_up"):
		_queued_cycle -= 1


# --- public API -----------------------------------------------------------------------------------

func is_grounded() -> bool:
	return mode == Mode.GROUND


func is_standing() -> bool:
	return _stand > 0.5


func get_facing() -> Vector3:
	return _facing


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_stand_amount() -> float:
	return _stand


func is_charging() -> bool:
	return _charging


## Aim direction for swats and grabs: the camera ray while standing, the body heading otherwise.
func get_aim_forward() -> Vector3:
	if _stand > 0.5 and camera != null:
		return camera.get_aim_direction()
	return _facing


func get_aim_point() -> Vector3:
	if camera != null:
		return camera.get_aim_point()
	return global_position + _facing * 30.0


func get_chest_position() -> Vector3:
	return global_position + Vector3.UP * (0.24 + 0.24 * _stand) + _facing * (0.12 - 0.06 * _stand)


## Just in front of the mouth, as drawn (the head socket is one rendered frame behind the body).
func get_mouth_position() -> Vector3:
	if head_socket != null and head_socket.is_inside_tree():
		return head_socket.global_transform * MOUTH_LOCAL
	return get_chest_position() + _facing * 0.15


## Between the eyes, as drawn.
func get_eye_position() -> Vector3:
	if head_socket != null and head_socket.is_inside_tree():
		return head_socket.global_transform * EYES_LOCAL
	return get_chest_position() + Vector3.UP * 0.08 + _facing * 0.15


## Tools call this on every tick they need the cat upright and facing where the camera looks (beams,
## casting, peeing). with_arms also holds the front paws forward.
func hold_aim_stance(seconds: float = 0.3, with_arms: bool = false) -> void:
	_aim_hold = maxf(_aim_hold, seconds)
	if with_arms:
		_arms_hold = maxf(_arms_hold, seconds)


## Turns her, and the camera behind her, to look along `direction` at once (spawns, cut scenes).
func face(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	_facing = flat.normalized()
	_vis_quat = _visual_basis(_facing, Vector3.UP).get_rotation_quaternion()
	if camera != null:
		camera.yaw = atan2(-_facing.x, -_facing.z)


## Tools call this on every tick they need her bolt upright on the hind legs like a person, belly
## forward and front paws down (peeing). Includes the aim stance.
func hold_tall_stance(seconds: float = 0.3) -> void:
	_aim_hold = maxf(_aim_hold, seconds)
	_tall_hold = maxf(_tall_hold, seconds)


## The hips as drawn (one rendered frame behind the body, like the head socket).
func get_hip_position() -> Vector3:
	if hip_socket != null and hip_socket.is_inside_tree():
		return hip_socket.global_position
	return global_position + Vector3.UP * 0.2 - _facing * 0.15


## One forward thrust of the front paws (casting, shoving).
func play_cast_thrust(seconds: float = 0.3) -> void:
	_throw_pose = maxf(_throw_pose, seconds)


func get_camera_focus() -> Vector3:
	var p := get_global_transform_interpolated().origin
	var f := p + Vector3.UP * _focus_h
	if mode == Mode.CLIMB:
		f += _wall_n * 0.35
	return f


## Teleports the cat ~250 m above a random spot of the playable area; it falls with air steering and
## lands on its feet with a blast. `at` (x, z) overrides the random spot.
func drop_from_sky(at: Vector3 = Vector3.INF) -> void:
	var x := randf_range(-RESPAWN_HALF, RESPAWN_HALF)
	var z := randf_range(-RESPAWN_HALF, RESPAWN_HALF)
	if at.is_finite():
		x = at.x
		z = at.z
	var ground := _ground_height_at(x, z)
	if grab.is_holding():
		grab.release(Vector3.ZERO)
	global_position = Vector3(x, ground + SKY_HEIGHT, z)
	velocity = Vector3(0.0, -6.0, 0.0)
	_speed = 0.0
	_charging = false
	_pounce = false
	_sky_drop = true
	_spin_speed = 0.0
	_spin_angle = 0.0
	_set_mode(Mode.AIR)
	reset_physics_interpolation()
	if camera != null:
		camera.snap_to_target()
	stats["sky_drops"] += 1
	dropped_from_sky.emit(global_position)


func on_swat_started() -> void:
	animator.play_swat()
	if _stand > 0.5:
		_throw_pose = 0.3


func on_swat_connected(_count: int) -> void:
	if camera != null:
		camera.add_trauma(0.2)
	_hit_stop(0.06, 0.2)


# --- tick -------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_read_input()
	_check_bounds()
	_check_lava(delta)
	_handle_actions()
	_climb_cooldown = maxf(_climb_cooldown - delta, 0.0)
	match mode:
		Mode.GROUND:
			_tick_ground(delta)
		Mode.AIR:
			_tick_air(delta)
		Mode.CLIMB:
			_tick_climb(delta)
		Mode.MANTLE:
			_tick_mantle(delta)
	grab.tick(delta)
	belt.tick(delta)
	_update_stand(delta)
	_update_anim(delta)
	_watchdog(delta)


func _read_input() -> void:
	_prev.copy_from(_in)
	if bot_input != null:
		_in.copy_from(bot_input)
		bot_input.tool_slot = -1
		bot_input.tool_cycle = 0
	else:
		_in.read_devices()
		_in.tool_slot = _queued_slot
		_in.tool_cycle = _queued_cycle
		_queued_slot = -1
		_queued_cycle = 0


func _handle_actions() -> void:
	if _in.grab and not _prev.grab:
		grab.toggle()
	if grab.is_holding():
		if _in.attack and not _prev.attack:
			grab.begin_throw_charge()
		if not _in.attack and _prev.attack and grab.charging:
			var body := grab.held
			var v := grab.finish_throw()
			_throw_pose = 0.45
			stats["throws"] += 1
			threw.emit(body, v)
			if camera != null:
				camera.add_trauma(0.12)
	else:
		if _in.attack != _prev.attack:
			belt.primary(_in.attack)
	if _in.aim != _prev.aim:
		belt.secondary(_in.aim)
	if _in.tool_slot >= 0:
		belt.select(_in.tool_slot)
	if _in.tool_cycle != 0:
		belt.cycle(_in.tool_cycle)
	if _in.interact and not _prev.interact and mode == Mode.GROUND and _speed < 0.3 and not grab.is_holding():
		animator.play_timed(&"hiss", animator.clip_length(&"hiss") * 0.9)


func _tick_ground(dt: float) -> void:
	var wish := _wish()
	var amount := minf(wish.length(), 1.0)
	var dir := wish / amount if amount > 0.01 else Vector3.ZERO
	_land_lock = maxf(_land_lock - dt, 0.0)
	var lock_k := 1.0 - (_land_lock / _land_lock_total if _land_lock_total > 0.0 else 0.0)

	# Space jumps the moment it is pressed (held longer, higher). Crouching (Ctrl) and slow, it charges a
	# pounce instead, released with Space. A press during a landing is kept and jumps as soon as it can.
	var pressed := _in.jump and not _prev.jump
	if pressed and _land_lock >= 0.1:
		_queued_jump = jump_buffer_time + _land_lock
	_queued_jump = maxf(_queued_jump - dt, 0.0)
	if (pressed or _queued_jump > 0.0) and _land_lock < 0.1 and not _charging:
		_queued_jump = 0.0
		if _in.crouch and _speed <= charge_max_speed and _stand <= 0.5 and not grab.is_holding():
			_charging = true
			_charge_t = 0.0
		else:
			_jump(sqrt(2.0 * gravity_up * jump_height), _in.jump)
			return
	if _charging:
		_charge_t += dt
		if not _in.jump:
			_charging = false
			if _charge_t < pounce_tap_time:
				_jump(sqrt(2.0 * gravity_up * jump_height), false)
			else:
				_launch_pounce(clampf((_charge_t - pounce_tap_time) / pounce_charge_time, 0.0, 1.0))
			return

	var vel_h := Vector3.ZERO
	if _charging:
		_facing = _turn_toward(_facing, _camera_forward_flat(), 9.0 * dt)
		_speed = move_toward(_speed, 0.0, brake * dt)
		vel_h = _facing * _speed
		_yaw_rate = 0.0
	elif _stand > 0.5:
		var face_cam := _in.aim or grab.is_holding() or _aim_hold > 0.0
		var want_face := _camera_forward_flat() if face_cam or dir == Vector3.ZERO else dir
		if face_cam or dir != Vector3.ZERO:
			_facing = _turn_toward(_facing, want_face, 8.0 * dt)
		var target_v := dir * stand_speed * amount * lock_k
		var cur := Vector3(velocity.x, 0.0, velocity.z)
		vel_h = cur.move_toward(target_v, accel * dt)
		_speed = vel_h.length()
		_yaw_rate = 0.0
	else:
		var target_speed := _tier_speed(amount)
		var prev_facing := _facing
		if amount > 0.01:
			var ang := _facing.signed_angle_to(dir, Vector3.UP)
			var spd_k := clampf(_speed / gallop_speed, 0.0, 1.0)
			var rate := lerpf(turn_rate_slow, turn_rate_fast, spd_k)
			if _speed < 1.2:
				rate = 16.0
			var skid := absf(ang) > 2.2 and _speed > 6.5
			if skid:
				rate *= 1.8
				target_speed = 0.0
			else:
				target_speed *= lerpf(1.0, 0.55, clampf(absf(ang) / PI, 0.0, 1.0))
			_facing = _facing.rotated(Vector3.UP, clampf(ang, -rate * dt, rate * dt)).normalized()
		else:
			target_speed = 0.0
		target_speed *= lock_k
		if target_speed > _speed:
			_speed = minf(_speed + (accel if _speed < trot_speed else gallop_accel) * dt, target_speed)
		else:
			_speed = maxf(_speed - brake * dt, target_speed)
		_yaw_rate = prev_facing.signed_angle_to(_facing, Vector3.UP) / dt
		vel_h = _facing * _speed

	velocity.x = vel_h.x
	velocity.z = vel_h.z
	velocity.y -= gravity_down * dt
	_move()
	var real_h := get_real_velocity()
	real_h.y = 0.0
	if _stand <= 0.5 and not _charging:
		_speed = minf(_speed, real_h.length() + accel * dt * 2.0)
	_push_bodies()

	if not is_on_floor():
		_coyote = coyote_time
		_jumped = false
		_set_mode(Mode.AIR)
		return
	_coyote = coyote_time
	_ground_align()
	if dir != Vector3.ZERO and is_on_wall() and not _charging:
		if _try_step_up(dir):
			return
		_check_climb(dir, false, dt)
	else:
		_wall_push_t = 0.0
	_safe_t += dt


func _tick_air(dt: float) -> void:
	_coyote -= dt
	_jump_buffer -= dt
	var wish := _wish()
	var amount := minf(wish.length(), 1.0)
	var dir := wish / amount if amount > 0.01 else Vector3.ZERO
	if _in.jump and not _prev.jump:
		if _coyote > 0.0 and not _jumped:
			_jump(sqrt(2.0 * gravity_up * jump_height), true)
			return
		_jump_buffer = jump_buffer_time
	var g := gravity_down
	if velocity.y > 0.0:
		g = gravity_up
		if _jump_held_rise and not _in.jump:
			g = jump_cut_gravity
	velocity.y = maxf(velocity.y - g * dt, -terminal_speed)
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if amount > 0.01:
		var acc := sky_air_accel if _sky_drop else air_accel * (0.4 if _pounce else 1.0)
		var max_h := maxf(h.length(), 16.0 if _sky_drop else 4.5)
		h = h.move_toward(dir * max_h * amount, acc * dt)
	velocity.x = h.x
	velocity.z = h.z
	if h.length() > 0.8:
		_facing = _turn_toward(_facing, h.normalized(), 7.0 * dt)
	elif dir != Vector3.ZERO:
		_facing = _turn_toward(_facing, dir, 8.0 * dt)
	_yaw_rate = 0.0
	_move()
	if is_on_floor():
		_land()
		return
	# Wedged on steep geometry (crevice between rubble, edge of a slope) without falling: allow a jump.
	var slow := get_real_velocity().length() < 0.6 and get_slide_collision_count() > 0
	_wedged_t = _wedged_t + dt if slow else 0.0
	if _wedged_t > 0.25:
		_coyote = coyote_time
		_jumped = false
	if dir != Vector3.ZERO:
		_check_climb(dir, true, dt)


func _tick_climb(dt: float) -> void:
	_climb_boost = move_toward(_climb_boost, 0.0, 7.0 * dt)
	var c := _center()
	var hit := _ray(c, c - _wall_n * (RADIUS + 0.5))
	if hit.is_empty():
		hit = _ray(c - _wall_up() * 0.12, c - _wall_up() * 0.12 - _wall_n * (RADIUS + 0.5))
	if hit.is_empty():
		if not _try_mantle():
			_vault_or_detach()
		return
	var n: Vector3 = hit["normal"]
	if n.y > FLOOR_COS:
		if not _try_mantle():
			_facing = _flat(-_wall_n, _facing)
			_set_mode(Mode.GROUND)
		return
	if n.y < -0.45:
		_detach(false)
		return
	_wall_n = _wall_n.slerp(n, 1.0 - exp(-20.0 * dt)).normalized()
	var up_w := _wall_up()
	var right_w := up_w.cross(_wall_n).normalized()
	var m := _in.move
	var lat := m.x
	if camera != null and Basis(Vector3.UP, camera.yaw).x.dot(right_w) < 0.0:
		lat = -lat
	var spd := climb_sprint_speed if _in.sprint else climb_speed
	var v := up_w * (m.y * spd + _climb_boost) + right_w * (lat * spd * 0.75)
	if absf(lat) > 0.05:
		var side := c + right_w * signf(lat) * (RADIUS + 0.15)
		if _ray(side, side - _wall_n * (RADIUS + 0.5)).is_empty():
			v -= right_w * v.dot(right_w)
	var dist := (c - (hit["position"] as Vector3)).dot(n)
	v += -_wall_n * (dist - (RADIUS + 0.03)) * 10.0
	velocity = v
	_move()
	_facing = _flat(-_wall_n, _facing)
	if _in.jump and not _prev.jump:
		_wall_jump(lat)
		return
	if _in.crouch and not _prev.crouch:
		_detach(true)
		return
	if m.y > 0.05 or _climb_boost > 0.5:
		var head := _center() + up_w * (RADIUS + 0.28)
		if _ray(head, head - _wall_n * (RADIUS + 0.55)).is_empty():
			if _try_mantle():
				return
	if m.y < -0.05:
		var below := _ray(_center(), _center() - Vector3.UP * (RADIUS + 0.15))
		if not below.is_empty() and (below["normal"] as Vector3).y > 0.7:
			_facing = _flat(_wall_n, _facing)
			_speed = 0.0
			_set_mode(Mode.GROUND)


func _tick_mantle(dt: float) -> void:
	_mantle_t = minf(_mantle_t + dt / mantle_time, 1.0)
	var t := _mantle_t
	var a := _mantle_from
	var b := _mantle_to
	var ctrl := Vector3(a.x, maxf(a.y, b.y) + 0.4, a.z)
	var p := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
	var prev := global_position
	global_position = p
	velocity = (p - prev) / dt
	if _mantle_t >= 1.0:
		_speed = 1.5
		velocity = _facing * _speed
		stats["mantles"] += 1
		_set_mode(Mode.GROUND)
		apply_floor_snap()
		animator.play_land(5.0)


# --- movement helpers -------------------------------------------------------------------------------

func _move() -> void:
	_vel_before = velocity
	move_and_slide()


func _wish() -> Vector3:
	var m := _in.move.limit_length(1.0)
	var yaw := camera.yaw if camera != null else 0.0
	return Basis(Vector3.UP, yaw) * Vector3(m.x, 0.0, -m.y)


func _tier_speed(amount: float) -> float:
	if _in.crouch:
		return stalk_speed
	if _in.sprint:
		return gallop_speed
	if _in.walk or amount < 0.6:
		return walk_speed * clampf(amount / 0.6, 0.3, 1.0) if not _in.walk else walk_speed
	return trot_speed


func _camera_forward_flat() -> Vector3:
	if camera == null:
		return _facing
	return Basis(Vector3.UP, camera.yaw) * Vector3.FORWARD


func _turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var ang := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(ang, -max_angle, max_angle)).normalized()


func _jump(vy: float, held: bool) -> void:
	velocity.y = vy
	_jumped = true
	_jump_held_rise = held
	_coyote = 0.0
	_jump_buffer = 0.0
	stats["jumps"] += 1
	_set_mode(Mode.AIR)


func _launch_pounce(c: float) -> void:
	var h := lerpf(pounce_min_height, pounce_max_height, c)
	var dist := lerpf(pounce_min_distance, pounce_max_distance, c)
	var vy := sqrt(2.0 * gravity_up * h)
	var t := vy / gravity_up + sqrt(2.0 * h / gravity_down)
	var dir := _camera_forward_flat()
	_facing = dir
	velocity = dir * (dist / t) + Vector3.UP * vy
	_pounce = true
	_jumped = true
	_jump_held_rise = false
	stats["pounces"] += 1
	stats["last_pounce_charge"] = c
	_set_mode(Mode.AIR)
	if camera != null:
		camera.add_trauma(0.1 + 0.15 * c)


func _land() -> void:
	var impact := maxf(-_vel_before.y, 0.0)
	stats["landings"] += 1
	stats["max_impact"] = maxf(stats["max_impact"], impact)
	stats["last_impact"] = impact
	var was_sky := _sky_drop
	_sky_drop = false
	_spin_speed = 0.0
	_spin_angle = 0.0
	_set_mode(Mode.GROUND)
	var h := Vector3(velocity.x, 0.0, velocity.z)
	_speed = h.length()
	if _speed > 0.5:
		_facing = h.normalized()
	_jumped = false
	_coyote = coyote_time
	if _pounce:
		_pounce = false
		animator.play_pounce_land()
		_set_land_lock(0.18)
		_speed *= 0.55
	elif impact > heavy_landing_speed:
		animator.play_land(impact)
		var heavy := clampf((impact - heavy_landing_speed) / 26.0, 0.0, 1.0)
		_set_land_lock(lerpf(0.08, 0.3, heavy))   # a short stumble, not a stop
		_speed *= lerpf(0.9, 0.5, heavy)
	elif impact > 3.5:
		animator.play_land(impact)
	if camera != null:
		camera.add_trauma(clampf((impact - 8.0) / 40.0, 0.0, 0.75))
		camera.add_dip(clampf(impact / 25.0, 0.05, 1.2))
	if was_sky or impact > blast_landing_speed:
		_landing_blast(impact)
	if _jump_buffer > 0.0:
		_jump(sqrt(2.0 * gravity_up * jump_height), true)
	landed.emit(impact)


func _set_land_lock(t: float) -> void:
	_land_lock = t
	_land_lock_total = t


func _landing_blast(impact: float) -> void:
	var e := 0.5 * landing_mass * impact * impact
	var r := clampf(impact * 0.13, 2.0, 8.0)
	var hit := DamageHit.blast(global_position, r, e, landing_mass * impact, DamageHit.Kind.BLUNT, self)
	hit.normal = Vector3.UP
	stats["landing_blasts"] += 1
	stats["last_blast_energy"] = e
	DamageRouter.apply_blast(hit, get_world_3d())
	if impact > 30.0:
		_hit_stop(0.32, 0.3)


## Brief slow motion through Game's time-scale arbitration (real-time duration). Each hit-stop holds its
## own request key, so overlapping ones do not end each other early; the timer is bound to Game, so the
## request is released even if the cat is freed meanwhile.
func _hit_stop(seconds: float, slow_scale: float) -> void:
	if bot_input != null:
		return   # keep bot runs deterministic
	_hit_stop_seq = (_hit_stop_seq + 1) % 16
	var key := StringName("cat_hit_stop_%d" % _hit_stop_seq)
	Game.request_time_scale(key, slow_scale)
	get_tree().create_timer(seconds, true, false, true).timeout.connect(Game.clear_time_scale.bind(key))


func _try_step_up(dir: Vector3) -> bool:
	var xf := global_transform
	var col := KinematicCollision3D.new()
	var up := step_height
	if test_move(xf, Vector3.UP * up, col):
		up = col.get_travel().length() - 0.01
	if up < 0.06:
		return false
	var xf_up := xf.translated(Vector3.UP * up)
	var fwd := dir * (RADIUS + 0.11)
	if test_move(xf_up, fwd, col):
		return false
	var xf_fwd := xf_up.translated(fwd)
	if not test_move(xf_fwd, Vector3.DOWN * (up + 0.05), col):
		return false
	if col.get_normal().y < 0.7:
		return false
	var final := xf_fwd.origin + col.get_travel()
	var dy := final.y - xf.origin.y
	if dy < 0.04 or dy > step_height:
		return false
	var delta := final - xf.origin
	global_position = final
	reset_physics_interpolation()
	_visual_offset -= delta
	stats["step_ups"] += 1
	return true


func _check_climb(dir: Vector3, from_air: bool, dt: float) -> bool:
	if _climb_cooldown > 0.0 or _stand > 0.3 or grab.is_holding() or _charging:
		_wall_push_t = 0.0
		return false
	var n := _find_wall(dir)
	if n == Vector3.ZERO:
		_wall_push_t = 0.0
		return false
	if not from_air:
		_wall_push_t += dt
		if _wall_push_t < 0.08 or not _taller_than_step(dir):
			return false
	_start_climb(n, from_air)
	return true


func _find_wall(dir: Vector3) -> Vector3:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if n.y < FLOOR_COS and n.y > -0.4 and dir.dot(-_flat(n, dir)) > 0.5:
			return n
	var c := _center()
	var hit := _ray(c, c + dir * (RADIUS + 0.14))
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		if n.y < FLOOR_COS and n.y > -0.4 and dir.dot(-_flat(n, dir)) > 0.5:
			return n
	return Vector3.ZERO


func _taller_than_step(dir: Vector3) -> bool:
	var from := global_position + Vector3.UP * (step_height + 0.08)
	return not _ray(from, from + dir * (RADIUS + 0.35)).is_empty()


func _start_climb(n: Vector3, from_air: bool) -> void:
	_wall_n = n
	var h := Vector2(velocity.x, velocity.z).length()
	_climb_boost = clampf((h if from_air else _speed) * 0.45, 0.0, 6.0)
	velocity = Vector3.ZERO
	_speed = 0.0
	_pounce = false
	_sky_drop = false
	_wall_push_t = 0.0
	_facing = _flat(-n, _facing)
	stats["climbs"] += 1
	_set_mode(Mode.CLIMB)


func _try_mantle() -> bool:
	var nh := _flat(_wall_n, Vector3.ZERO)
	if nh == Vector3.ZERO:
		return false
	var c := _center()
	for over: float in [0.42, 0.7]:
		var from := c + Vector3.UP * 1.1 - nh * over
		var hit := _ray(from, from - Vector3.UP * 1.9)
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
			continue
		var top: Vector3 = hit["position"]
		if top.y < global_position.y - 0.05:
			continue
		var dest := top + Vector3.UP * 0.02
		if not _sphere_free(dest + Vector3.UP * (RADIUS + 0.01), RADIUS):
			continue
		_mantle_from = global_position
		_mantle_to = dest
		_mantle_t = 0.0
		_facing = -nh
		_set_mode(Mode.MANTLE)
		return true
	return false


## The wall ended without a ledge to stand on (thin wall, fence): hop over it, or let go.
func _vault_or_detach() -> void:
	if _in.move.y > 0.1:
		var nh := _flat(_wall_n, _facing)
		velocity = Vector3.UP * 5.0 - nh * 2.5
		_facing = -nh
		_climb_cooldown = 0.25
		_jumped = true
		_set_mode(Mode.AIR)
	else:
		_detach(false)


func _wall_jump(lateral: float) -> void:
	var right_w := _wall_up().cross(_wall_n).normalized()
	velocity = _wall_n * wall_jump_out + Vector3.UP * wall_jump_up + right_w * lateral * 2.5
	_facing = _flat(_wall_n, _facing)
	_climb_cooldown = 0.35
	_jumped = true
	_jump_held_rise = false
	stats["wall_jumps"] += 1
	_set_mode(Mode.AIR)


func _detach(push: bool) -> void:
	velocity = _wall_n * (2.0 if push else 0.8)
	_facing = _flat(_wall_n, _facing)
	_climb_cooldown = 0.4
	_jumped = true
	_set_mode(Mode.AIR)


func _wall_up() -> Vector3:
	var u := Vector3.UP - _wall_n * Vector3.UP.dot(_wall_n)
	if u.length_squared() < 0.01:
		return _flat(-_wall_n, _facing)
	return u.normalized()


func _set_mode(m: int) -> void:
	if m == mode:
		return
	var old := mode
	mode = m
	motion_mode = MOTION_MODE_FLOATING if (m == Mode.CLIMB or m == Mode.MANTLE) else MOTION_MODE_GROUNDED
	if m != Mode.GROUND:
		_charging = false
	_wedged_t = 0.0
	if m == Mode.AIR or m == Mode.MANTLE:
		animator.travel(&"air")
	elif m == Mode.CLIMB:
		animator.travel(&"climb")
	mode_changed.emit(old, m)


## Shoves dynamic bodies the cat runs into. The strength comes from the speed going into the contact:
## by now _speed has already been cut to the blocked (near zero) real velocity.
func _push_bodies() -> void:
	var into := Vector2(_vel_before.x, _vel_before.z).length()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb == null or rb.freeze or rb == grab.held or CatGrab.is_protected(rb):
			continue   # protected things (animals, plants) are never moved by force
		var push := -col.get_normal()
		push.y = maxf(push.y, 0.0)
		var k := clampf(into * 4.0, 0.0, 60.0) * clampf(40.0 / rb.mass, 0.05, 1.0)
		rb.apply_impulse(push * k * get_physics_process_delta_time() * 10.0, col.get_position() - rb.global_position)


func _ground_align() -> void:
	var n := get_floor_normal()
	var up := n
	var p := global_position
	var f := _facing * 0.2
	var hf := _ray(p + f + Vector3.UP * 0.35, p + f - Vector3.UP * 0.45)
	var hb := _ray(p - f + Vector3.UP * 0.35, p - f - Vector3.UP * 0.45)
	if not hf.is_empty() and not hb.is_empty():
		var slope: Vector3 = (hf["position"] as Vector3) - (hb["position"] as Vector3)
		if slope.length() > 0.05:
			var right := _facing.cross(Vector3.UP).normalized()
			up = (right.cross(slope.normalized()) * 0.7 + n * 0.3).normalized()
	if up.y < 0.5:
		up = Vector3.UP
	_ground_up = up


func _update_stand(dt: float) -> void:
	_throw_pose = maxf(_throw_pose - dt, 0.0)
	_aim_hold = maxf(_aim_hold - dt, 0.0)
	_arms_hold = maxf(_arms_hold - dt, 0.0)
	_tall_hold = maxf(_tall_hold - dt, 0.0)
	var want := mode == Mode.GROUND and not _charging and (_in.aim or _in.stand or grab.is_holding() or _throw_pose > 0.0 or _aim_hold > 0.0 or belt.wants_stand_pose())
	_stand = move_toward(_stand, 1.0 if want else 0.0, dt / (0.24 if want else 0.3))


func _update_anim(dt: float) -> void:
	var real := get_real_velocity()
	var hs := Vector2(real.x, real.z).length() if mode == Mode.GROUND else 0.0
	_anim_speed = lerpf(_anim_speed, hs, 1.0 - exp(-14.0 * dt))
	match mode:
		Mode.GROUND:
			var moving_input := _in.move.length() > 0.05 or _charging or _in.crouch
			if animator.is_timed_active():
				var st := animator.get_state()
				if (st == &"lick" or st == &"hiss") and moving_input:
					animator.travel(&"move")
				elif st == &"land" or st == &"pounce_land" or st == &"lick" or st == &"hiss":
					animator.set_move_speed(_anim_speed)
					return
			if _charging:
				animator.travel(&"charge")
				animator.set_charge(clampf(_charge_t / (pounce_charge_time + pounce_tap_time), 0.0, 1.0))
			elif _in.crouch and _stand < 0.3:
				animator.travel(&"stalk")
				animator.set_stalk_speed(_anim_speed)
			else:
				animator.travel(&"move")
				animator.set_move_speed(_anim_speed if _stand < 0.3 else 0.0)
			_idle_t = _idle_t + dt if (not moving_input and _anim_speed < 0.05 and _stand < 0.05) else 0.0
			if _idle_t > 9.0:
				_idle_t = -6.0
				animator.play_timed(&"lick", animator.clip_length(&"lick") * 0.95)
		Mode.AIR:
			animator.travel(&"air")
			animator.set_air_velocity(velocity.y if not _sky_drop else minf(velocity.y, -3.0))
		Mode.CLIMB:
			animator.travel(&"climb")
			animator.set_climb_speed(velocity.dot(_wall_up()))
		Mode.MANTLE:
			animator.set_air_velocity(lerpf(6.0, -2.0, _mantle_t))


# --- world checks -------------------------------------------------------------------------------------

func _check_bounds() -> void:
	var p := global_position
	if not p.is_finite() or not velocity.is_finite():
		stats["nonfinite"] += 1
		global_position = _safe_pos
		velocity = Vector3.ZERO
		_set_mode(Mode.AIR)
		reset_physics_interpolation()
		return
	if p.y < WORLD_LIMIT_Y or absf(p.x) > WORLD_LIMIT_XZ or absf(p.z) > WORLD_LIMIT_XZ:
		if void_handler.is_valid():
			void_handler.call()
		else:
			drop_from_sky()


func _check_lava(dt: float) -> void:
	_lava_cd -= dt
	if _lava_cd > 0.0 or Game.terrain == null or not Game.terrain.has_method(&"is_lava_at"):
		return
	if not bool(Game.terrain.call(&"is_lava_at", global_position)):
		return
	_lava_cd = 0.6
	var a := randf() * TAU
	velocity = Vector3(cos(a), 0.0, sin(a)) * 4.0 + Vector3.UP * lava_launch_speed
	_jumped = true
	_pounce = false
	_sky_drop = false
	_charging = false
	_spin_axis = Vector3(cos(a + 1.3), 0.0, sin(a + 1.3))
	_spin_speed = TAU * 2.4
	_spin_angle = 0.0
	_set_mode(Mode.AIR)
	stats["lava_launches"] += 1
	if camera != null:
		camera.add_trauma(0.55)
	lava_launched.emit(global_position)


## A kick from one of the little people (People, CHASE): a short flight away from them. She cannot be
## hurt; it only moves her.
func kicked(direction: Vector3) -> void:
	var d := Vector3(direction.x, 0.0, direction.z)
	d = d.normalized() if d.length_squared() > 0.0001 else -get_facing()
	velocity = d * 6.5 + Vector3.UP * 4.2
	_jumped = true
	_pounce = false
	_charging = false
	_set_mode(Mode.AIR)
	if camera != null:
		camera.add_trauma(0.3)


## Safety net and test probe: never inside a collider for long, never non-finite.
func _watchdog(dt: float) -> void:
	if mode == Mode.MANTLE:
		_overlap_t = 0.0
		return
	_probe_shape.radius = RADIUS - 0.04
	_probe_query.transform = Transform3D(Basis.IDENTITY, _center())
	var ex: Array[RID] = [get_rid()]
	if grab.is_holding():
		ex.append(grab.held.get_rid())
	_probe_query.exclude = ex
	var inside := not get_world_3d().direct_space_state.intersect_shape(_probe_query, 1).is_empty()
	_overlap_t = _overlap_t + dt if inside else 0.0
	stats["max_overlap_time"] = maxf(stats["max_overlap_time"], _overlap_t)
	if _overlap_t > 0.08:
		_depenetrate()
	elif not inside and mode == Mode.GROUND and _safe_t > 0.5:
		_safe_pos = global_position
		_safe_t = 0.0


## Pushes out along the contact normal; if something keeps pressing in (a toppled crate wedged by the
## stack above it), hops to the nearest free spot; after 0.6 s falls back to the last safe position.
func _depenetrate() -> void:
	_probe_shape.radius = RADIUS
	_probe_query.transform = Transform3D(Basis.IDENTITY, _center())
	var info := get_world_3d().direct_space_state.get_rest_info(_probe_query)
	if not info.is_empty():
		var n: Vector3 = info["normal"]
		var p: Vector3 = info["point"]
		var push := RADIUS - (_center() - p).dot(n) + 0.02
		global_position += n * clampf(push, 0.02, 0.5)
		stats["depenetrations"] += 1
	if _overlap_t > 0.13:
		var base := global_position
		for off: Vector3 in [Vector3(0, 0.3, 0), Vector3(0.45, 0.1, 0), Vector3(-0.45, 0.1, 0), Vector3(0, 0.1, 0.45),
				Vector3(0, 0.1, -0.45), Vector3(0, 0.7, 0), Vector3(0.7, 0.4, 0.7), Vector3(-0.7, 0.4, -0.7)]:
			if _sphere_free(base + off + Vector3.UP * RADIUS, RADIUS + 0.01):
				global_position = base + off
				velocity = Vector3.ZERO
				_overlap_t = 0.0
				stats["depenetrations"] += 1
				_set_mode(Mode.AIR)
				break
	if _overlap_t > 0.6:
		global_position = _safe_pos + Vector3.UP * 0.3
		velocity = Vector3.ZERO
		_overlap_t = 0.0
		stats["safe_resets"] += 1
		_set_mode(Mode.AIR)
	reset_physics_interpolation()


func _ground_height_at(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2000.0, z), Vector3(x, -200.0, z), Layers.TERRAIN | Layers.STRUCTURE | Layers.RUBBLE)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	_ray_query.from = from
	_ray_query.to = to
	return get_world_3d().direct_space_state.intersect_ray(_ray_query)


func _sphere_free(center: Vector3, r: float) -> bool:
	_probe_shape.radius = r
	_probe_query.transform = Transform3D(Basis.IDENTITY, center)
	_probe_query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(_probe_query, 1).is_empty()


func _center() -> Vector3:
	return global_position + Vector3.UP * RADIUS


static func _flat(v: Vector3, fallback: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-4 else fallback


# --- presentation (per rendered frame) ---------------------------------------------------------------

func _process(delta: float) -> void:
	_update_visual(delta)
	_update_pose(delta)
	var want_h := 0.36
	if mode == Mode.GROUND and _in.crouch:
		want_h = 0.26
	want_h = lerpf(want_h, 0.52, _stand)
	if grab.is_holding():
		want_h += 0.1
	_focus_h = lerpf(_focus_h, want_h, 1.0 - exp(-6.0 * delta))
	if camera != null:
		camera.aim_blend = smoothstep(0.0, 1.0, _stand)
		camera.extra_distance = lerpf(camera.extra_distance, grab.get_hold_extent() * 0.9, 1.0 - exp(-4.0 * delta))


func _update_visual(delta: float) -> void:
	var up := Vector3.UP
	var fwd := _facing
	var rate := 14.0
	match mode:
		Mode.GROUND:
			up = _ground_up
		Mode.AIR:
			var hs := Vector2(velocity.x, velocity.z).length()
			if hs > 2.0 and not _sky_drop:
				var pitch := clampf(atan2(velocity.y, hs) * 0.5, -0.5, 0.45)
				up = Vector3.UP.rotated(_facing.cross(Vector3.UP).normalized(), pitch)
			rate = 7.0
		Mode.CLIMB:
			up = _wall_up()
			fwd = -_wall_n
			rate = 18.0
		Mode.MANTLE:
			up = _wall_up().slerp(Vector3.UP, smoothstep(0.3, 1.0, _mantle_t))
			fwd = _facing if _mantle_t > 0.5 else -_wall_n
			rate = 16.0
	var b := _visual_basis(fwd, up)
	if mode == Mode.GROUND and _stand < 0.5:
		var roll := clampf(-_yaw_rate * _speed * 0.012, -0.32, 0.32)   # lean into the turn
		b = Basis(-b.z, roll) * b
		_bend = lerpf(_bend, clampf(_yaw_rate / 5.0, -1.0, 1.0) * clampf(_speed / 3.0, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	else:
		_bend = lerpf(_bend, 0.0, 1.0 - exp(-8.0 * delta))
	if _spin_speed > 0.0:
		if velocity.y > 0.0:
			_spin_angle += _spin_speed * delta
		else:
			var goal := ceilf(_spin_angle / TAU) * TAU
			_spin_angle = move_toward(_spin_angle, goal, _spin_speed * 0.6 * delta)
		b = Basis(_spin_axis, _spin_angle) * b
	_vis_quat = _vis_quat.slerp(b.get_rotation_quaternion(), 1.0 - exp(-rate * delta))
	var climb_target := 1.0 if (mode == Mode.CLIMB or (mode == Mode.MANTLE and _mantle_t < 0.55)) else 0.0
	_climb_w = move_toward(_climb_w, climb_target, delta * 6.0)
	_visual_offset = _visual_offset.lerp(Vector3.ZERO, 1.0 - exp(-16.0 * delta))
	var cw := smoothstep(0.0, 1.0, _climb_w)
	_visual.transform = Transform3D(Basis(_vis_quat), Vector3.UP * (RADIUS * cw) + _visual_offset)
	_model.position = _ground_model_origin().lerp(_climb_model_origin(), cw)


func _update_pose(delta: float) -> void:
	pose.stand = _stand
	pose.tall = move_toward(pose.tall, 1.0 if _tall_hold > 0.0 else 0.0, delta * 5.0)
	var arms_up_target := 0.0
	if grab.is_holding():
		arms_up_target = 1.0 if grab.charging else 0.75
	elif _in.aim:
		arms_up_target = 0.15
	pose.arms_up = move_toward(pose.arms_up, arms_up_target, delta * 4.0)
	var fwd_target := 0.0
	if _throw_pose > 0.0:
		fwd_target = 1.0
	elif grab.is_holding():
		fwd_target = 0.0 if grab.charging else 0.35
	elif _in.aim or _arms_hold > 0.0:
		fwd_target = 0.55
	pose.arms_forward = move_toward(pose.arms_forward, fwd_target, delta * (9.0 if fwd_target > pose.arms_forward else 3.0))
	pose.turn_bend = _bend
	var hs := Vector2(velocity.x, velocity.z).length()
	pose.step_amount = clampf(hs / maxf(stand_speed, 0.1), 0.0, 1.0) if _stand > 0.1 else 0.0
	pose.step_phase += hs * delta * 9.0
	var lw := 0.0
	if camera != null and (mode == Mode.GROUND or mode == Mode.AIR):
		var aim := camera.get_aim_point(60.0)
		pose.look_target = aim
		var to := _flat(aim - global_position, _facing)
		var behind := clampf((to.dot(_facing) + 0.3) / 0.6, 0.0, 1.0)
		lw = lerpf(0.55 * behind * clampf(1.0 - _speed / 8.0, 0.0, 1.0), 1.0, _stand)
		if mode == Mode.AIR:
			lw *= 0.4
	pose.look_weight = lerpf(pose.look_weight, lw, 1.0 - exp(-6.0 * delta))


## Visual frame: +Y = up, -Z = forward (the model is turned 180 degrees inside it).
func _visual_basis(fwd: Vector3, up: Vector3) -> Basis:
	var z := -(fwd - up * fwd.dot(up))
	if z.length_squared() < 1e-6:
		z = up.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := up.cross(z).normalized()
	return Basis(x, up, x.cross(up).normalized())


func _ground_model_origin() -> Vector3:
	return Vector3(0.0, 0.0, BODY_CENTER_Z * MODEL_SCALE)


func _climb_model_origin() -> Vector3:
	var a := CLIMB_MODEL_ANCHOR * MODEL_SCALE
	return Vector3(0.0, -a.y, -RADIUS + a.z)


## Soft blob decal under the paws: grounds the small cat where the sun shadow falls out of view.
## Cat meshes render on layer 2 only, which the decal skips.
func _add_contact_shadow() -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers = CAT_RENDER_LAYER
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.62))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.45, Color(0, 0, 0, 0.32))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_shadow = Decal.new()
	_shadow.name = "ContactShadow"
	_shadow.texture_albedo = tex
	_shadow.size = Vector3(0.42, 0.5, 0.62)
	_shadow.position = Vector3(0.0, 0.18, 0.0)
	_shadow.upper_fade = 0.15
	_shadow.lower_fade = 0.3
	_shadow.cull_mask = 0xFFFFF & ~CAT_RENDER_LAYER
	_visual.add_child(_shadow)


func _tune_materials() -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null or mat.resource_name != "Sphinx_Cat_material":
				continue
			var skin := mat.duplicate() as StandardMaterial3D
			skin.subsurf_scatter_enabled = true
			skin.subsurf_scatter_strength = 0.22
			skin.subsurf_scatter_skin_mode = true
			mi.set_surface_override_material(s, skin)
