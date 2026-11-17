class_name CatCamera
extends Node3D
## Third-person orbit camera for the cat: SpringArm3D with collision, mouse look, smoothing, speed FOV
## kick, over-the-shoulder aim framing and trauma-based shake (also fed by DamageRouter.blast).
## The rig is top_level and follows the cat's interpolated transform every rendered frame.

@export var mouse_sensitivity := 0.0024
@export var pitch_min_deg := -72.0
@export var pitch_max_deg := 50.0
@export var arm_length := 1.6
@export var aim_arm_length := 1.45
@export var shoulder_offset := 0.36
@export var base_fov := 50.0       ## Vertical FOV (Camera3D keeps height).
@export var sprint_fov_kick := 11.0
@export var aim_fov := 46.0
@export var follow_rate_xz := 20.0
@export var follow_rate_y := 9.0
@export var max_shake_deg := Vector3(4.0, 4.0, 6.0)   ## pitch, yaw, roll at full trauma
@export var trauma_decay := 1.15

var yaw := 0.0
var pitch := deg_to_rad(-11.0)
var trauma := 0.0
## 0..1 over-the-shoulder blend, driven by the cat (standing / aiming).
var aim_blend := 0.0
## Extra arm length requested by the cat (e.g. to frame a held object).
var extra_distance := 0.0
var target: CatPlayer = null

var _pivot: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _dip := 0.0
var _dip_vel := 0.0
var _idle_look_t := 0.0
var _focus := Vector3.ZERO
var _initialized := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.name = "SpringArm3D"
	var probe := SphereShape3D.new()
	probe.radius = 0.14
	_arm.shape = probe
	_arm.collision_mask = Layers.WALKABLE
	_arm.margin = 0.06
	_arm.spring_length = arm_length
	_pivot.add_child(_arm)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = base_fov
	_camera.near = 0.03
	_camera.far = 3000.0
	_arm.add_child(_camera)
	_noise.seed = 7
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2
	if not DamageRouter.blast.is_connected(_on_blast):
		DamageRouter.blast.connect(_on_blast)


func get_camera() -> Camera3D:
	return _camera


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Vertical camera dip (landings). Positive = down.
func add_dip(amount: float) -> void:
	_dip_vel += amount * 9.0


## Point the camera at in world space (centre ray hit, or far point). The ray starts level with the cat,
## so nothing between the camera and the cat becomes the target, and it ignores the held body (which
## floats in front of the standing cat, often across the crosshair).
func get_aim_point(max_dist: float = 200.0) -> Vector3:
	var from := _camera.global_position
	var dir := -_camera.global_basis.z
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = []
	if target != null:
		from += dir * maxf(dir.dot(target.get_chest_position() - from), 0.0)
		ex.append(target.get_rid())
		if target.grab != null and target.grab.is_holding():
			ex.append(target.grab.held.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, Layers.SOLID, ex)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	return from + dir * max_dist


## Bodies the arm must not collide with (e.g. the prop held overhead).
func set_arm_exclusion(rid: RID, excluded: bool) -> void:
	if excluded:
		_arm.add_excluded_object(rid)
	else:
		_arm.remove_excluded_object(rid)


func get_aim_direction() -> Vector3:
	return -_camera.global_basis.z


func snap_to_target() -> void:
	if target == null:
		return
	_focus = target.get_camera_focus()
	global_position = _focus
	_initialized = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens := mouse_sensitivity * lerpf(1.0, 0.6, aim_blend)
		yaw -= mm.relative.x * sens
		pitch = clampf(pitch - mm.relative.y * sens, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		_idle_look_t = 0.0
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target == null:
		return
	if not _initialized:
		snap_to_target()
	var real_delta := delta / maxf(Engine.time_scale, 0.05)
	var want := target.get_camera_focus()
	var kxz := 1.0 - exp(-follow_rate_xz * delta)
	var ky := 1.0 - exp(-(follow_rate_y if target.is_grounded() else follow_rate_y * 2.2) * delta)
	_focus.x = lerpf(_focus.x, want.x, kxz)
	_focus.z = lerpf(_focus.z, want.z, kxz)
	_focus.y = lerpf(_focus.y, want.y, ky)
	if _focus.distance_to(want) > 8.0:
		_focus = want

	# Lazy auto-follow: when running fast without mouse input, drift behind the cat.
	_idle_look_t += real_delta
	var spd := target.get_horizontal_speed()
	if _idle_look_t > 1.4 and spd > 6.0 and target.is_grounded() and aim_blend < 0.1:
		var heading := target.get_facing()
		var want_yaw := atan2(-heading.x, -heading.z)
		yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-0.9 * delta * clampf((spd - 6.0) / 7.0, 0.0, 1.0)))

	# Landing dip spring.
	_dip_vel += (-_dip * 120.0 - _dip_vel * 16.0) * real_delta
	_dip += _dip_vel * real_delta

	global_position = _focus + Vector3(0.0, -_dip * 0.12, 0.0)
	_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_arm.spring_length = lerpf(arm_length, aim_arm_length, aim_blend) + extra_distance
	_arm.position = Vector3(shoulder_offset * aim_blend, 0.0, 0.0)

	var speed_k := clampf((spd - 5.5) / 7.5, 0.0, 1.0)
	var fov_target := lerpf(base_fov + sprint_fov_kick * speed_k, aim_fov, aim_blend)
	_camera.fov = lerpf(_camera.fov, fov_target, 1.0 - exp(-6.0 * real_delta))

	# Trauma shake (squared for a punchy falloff), in real time so slow-motion still shakes.
	trauma = maxf(trauma - trauma_decay * real_delta, 0.0)
	_noise_t += real_delta * 28.0
	var s := trauma * trauma
	_camera.rotation = Vector3(
		deg_to_rad(max_shake_deg.x) * s * _noise.get_noise_2d(_noise_t, 0.0),
		deg_to_rad(max_shake_deg.y) * s * _noise.get_noise_2d(0.0, _noise_t),
		deg_to_rad(max_shake_deg.z) * s * _noise.get_noise_2d(_noise_t, _noise_t))


func _on_blast(hit: DamageHit) -> void:
	if not is_inside_tree():
		return
	var d := hit.position.distance_to(global_position)
	var reach := hit.radius * 5.0 + 12.0
	var falloff := clampf(1.0 - d / reach, 0.0, 1.0)
	var strength := clampf(0.25 + hit.energy / 120000.0, 0.25, 1.0)
	add_trauma(strength * falloff * falloff)
