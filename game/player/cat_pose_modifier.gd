class_name CatPoseModifier
extends SkeletonModifier3D
## Procedural layer over the animated pose of the Sphynx rig (skeleton space = model space, +Z forward).
##
##  * stand: rears the cat up on its hind legs. The pelvis and lumbar spine pitch up around the hip
##    joints, the hip joints drop to standing height, the hind legs are solved with an analytic two-bone
##    IK onto plantigrade feet, the tail is laid back on the ground and the head is levelled.
##  * arms_up / arms_forward: front-leg targets while standing (overhead hold, throw/cast thrust).
##  * look: head and neck turn toward look_target (world space), limited.
##  * turn_bend: lateral spine curve into turns, tail counter-swings.
## Values are expected pre-smoothed by the controller; this node only reads them.

@export_range(0.0, 1.0) var stand := 0.0
@export_range(0.0, 1.0) var arms_up := 0.0
@export_range(0.0, 1.0) var arms_forward := 0.0
## On top of stand: bolt upright like a person, belly forward, front paws down (peeing).
@export_range(0.0, 1.0) var tall := 0.0
@export_range(-1.0, 1.0) var turn_bend := 0.0
@export_range(0.0, 1.0) var look_weight := 0.0
var look_target := Vector3.ZERO
## Hind-leg stepping while standing: phase in radians, amount 0..1.
var step_phase := 0.0
var step_amount := 0.0

@export var body_pitch_deg := 86.0
@export var pelvis_share := 0.55          ## Part of the pitch taken by the pelvis; the rest by the spine.
@export var tall_pitch_deg := 93.0
@export var tall_pelvis_share := 0.82
@export var tall_hip_rise := 0.02
@export var hip_height := 0.27            ## Hip-joint height when standing (model units).
@export var hip_forward := 0.03           ## Forward shift of the hip joints when standing.
@export var hock_height := 0.055
@export var hock_back := 0.07             ## Hock behind the hip joint.
@export var stance_width := 1.15          ## Hind-feet width multiplier.

const B_HIPS := "hips_106"
const SPINE := ["spine_01_60", "spine_02_59", "spine_03_58", "chest_57"]
const NECK := ["neck_01_14", "neck_02_13", "head_12"]
const TAIL := ["tail_01_69", "tail_02_68", "tail_03_67", "tail_04_66", "tail_05_65", "tail_06_64", "tail_07_63", "tail_08_62", "tail_09_61"]
const LEGS := {
	&"L": ["thigh.L_86", "shin.L_84", "foot.L_82", "h_digit3_01.L_75"],
	&"R": ["thigh.R_103", "shin.R_101", "foot.R_99", "h_digit3_01.R_92"],
}
const ARMS := {
	&"L": ["upperarm.L_33", "forearm.L_31", "hand.L_29", "f_digit3_01.L_22", "scapula.L_35"],
	&"R": ["upperarm.R_54", "forearm.R_52", "hand.R_50", "f_digit3_01.R_43", "scapula.R_56"],
}
## [parent, helper, child]: helpers keep their input-pose relation to the child bone.
const HELPERS := [
	["hips_106", "jnt_hip.L_104", "thigh.L_86"], ["thigh.L_86", "jnt_knee.L_85", "shin.L_84"], ["shin.L_84", "jnt_hock.L_83", "foot.L_82"],
	["hips_106", "jnt_hip.R_105", "thigh.R_103"], ["thigh.R_103", "jnt_knee.R_102", "shin.R_101"], ["shin.R_101", "jnt_hock.R_100", "foot.R_99"],
	["scapula.L_35", "jnt_shoulder.L_34", "upperarm.L_33"], ["upperarm.L_33", "jnt_elbow.L_32", "forearm.L_31"], ["forearm.L_31", "jnt_wrist.L_30", "hand.L_29"],
	["scapula.R_56", "jnt_shoulder.R_55", "upperarm.R_54"], ["upperarm.R_54", "jnt_elbow.R_53", "forearm.R_52"], ["forearm.R_52", "jnt_wrist.R_51", "hand.R_50"],
]
## Neutral head direction (head bone +Y) of the idle pose in model space.
const HEAD_NEUTRAL := Vector3(0.0, 0.23, 0.97)

var _ids := {}
var _ready_ok := false
var _time := 0.0


func _ready() -> void:
	_cache_ids()


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_cache_ids()


func _cache_ids() -> void:
	var sk := get_skeleton()
	if sk == null:
		_ready_ok = false
		return
	var names: Array = [B_HIPS] + SPINE + NECK + TAIL
	for side in LEGS:
		names += LEGS[side]
	for side in ARMS:
		names += ARMS[side]
	for h in HELPERS:
		names += h
	for n in names:
		_ids[n] = sk.find_bone(n)
	_ready_ok = not _ids.values().has(-1)


func _process_modification_with_delta(delta: float) -> void:
	if not _ready_ok:
		_cache_ids()
		if not _ready_ok:
			return
	_time += delta
	var w := smoothstep(0.0, 1.0, stand)
	if w <= 0.001 and absf(turn_bend) <= 0.001 and look_weight <= 0.001:
		return
	var sk := get_skeleton()
	var before := {}
	for h in HELPERS:
		before[h[1]] = sk.get_bone_global_pose(_ids[h[1]])
		before[h[2]] = sk.get_bone_global_pose(_ids[h[2]])
	var feet := {}
	for side in LEGS:
		feet[side] = sk.get_bone_global_pose(_ids[LEGS[side][2]])

	if absf(turn_bend) > 0.001:
		_apply_turn_bend(sk)
	if w > 0.001:
		_apply_stand(sk, w, feet)
	_apply_head(sk, w)
	_fix_helpers(sk, before)


func _apply_turn_bend(sk: Skeleton3D) -> void:
	# Positive bend curves the spine to the cat's left (+X side).
	var total := deg_to_rad(26.0) * turn_bend
	for i in SPINE.size():
		_rotate_global(sk, _ids[SPINE[i]], Basis(Vector3.UP, total / SPINE.size()))
	for i in range(1, 5):
		_rotate_global(sk, _ids[TAIL[i]], Basis(Vector3.UP, -total * 0.22))


func _apply_stand(sk: Skeleton3D, w: float, feet: Dictionary) -> void:
	var breathe := sin(_time * 2.4) * deg_to_rad(1.2)
	var pitch := deg_to_rad(lerpf(body_pitch_deg, tall_pitch_deg, tall)) * w + breathe * w
	var share := lerpf(pelvis_share, tall_pelvis_share, tall)
	var hips_id: int = _ids[B_HIPS]
	var thigh_l: int = _ids[LEGS[&"L"][0]]
	var thigh_r: int = _ids[LEGS[&"R"][0]]
	var joint := (sk.get_bone_global_pose(thigh_l).origin + sk.get_bone_global_pose(thigh_r).origin) * 0.5
	var joint_target := joint.lerp(Vector3(0.0, hip_height + tall_hip_rise * tall, joint.z + hip_forward), w)

	# Pelvis: rotate around the hip joints, then move them to standing height.
	var rot := Basis(Vector3.RIGHT, -pitch * share)
	var hips := sk.get_bone_global_pose(hips_id)
	var hips_new := Transform3D(rot * hips.basis, joint_target + rot * (hips.origin - joint))
	sk.set_bone_global_pose(hips_id, hips_new)
	# The spine takes the rest of the pitch, most of it low in the back.
	var lumbar := pitch * (1.0 - share)
	var shares := [0.32, 0.28, 0.22, 0.18]
	for i in SPINE.size():
		_rotate_global(sk, _ids[SPINE[i]], Basis(Vector3.RIGHT, -lumbar * shares[i]))

	# Hind legs: plantigrade feet under the hip joints.
	for side in LEGS:
		var names: Array = LEGS[side]
		var sgn := 1.0 if side == &"L" else -1.0
		var thigh_pos := sk.get_bone_global_pose(_ids[names[0]]).origin
		var old_foot: Transform3D = feet[side]
		var step := step_amount * w
		var ph := step_phase + (0.0 if side == &"L" else PI)
		var stand_hock := Vector3(thigh_pos.x * stance_width, hock_height + maxf(0.0, cos(ph)) * 0.05 * step,
				joint_target.z - hock_back + sin(ph) * 0.07 * step)
		var hock := old_foot.origin.lerp(stand_hock, w)
		var pole := Vector3(0.25 * sgn, 0.0, 1.0).normalized()
		_solve_two_bone(sk, _ids[names[0]], _ids[names[1]], _ids[names[2]], hock, pole)
		var foot_dir := Vector3(0.04 * sgn, -0.3, 1.0).normalized()
		var cur := _bone_dir(sk, _ids[names[2]], _ids[names[3]])
		_aim_bone(sk, _ids[names[2]], cur, cur.slerp(foot_dir, w))

	# Tail: down from the rump to the ground, back along it, tip curling up.
	_aim_chain_bone(sk, TAIL[0], TAIL[1], Vector3(0.0, -0.72, -0.7), w)
	_aim_chain_bone(sk, TAIL[2], TAIL[3], Vector3(0.0, -0.12, -1.0), w)
	_aim_chain_bone(sk, TAIL[6], TAIL[7], Vector3(0.0, 0.3, -1.0), w)

	_apply_arms(sk, w)


func _apply_arms(sk: Skeleton3D, w: float) -> void:
	for side in ARMS:
		var names: Array = ARMS[side]
		var sgn := 1.0 if side == &"L" else -1.0
		# Relaxed: upper arms down the chest, forearms forward, paws hanging ("T-rex" begging pose).
		var upper_relaxed := Vector3(0.1 * sgn, -0.8, 0.55)
		var fore_relaxed := Vector3(0.0, -0.45, 0.9)
		var hand_relaxed := Vector3(0.0, -0.95, 0.3)
		# Overhead: arms in a V above the head, paws turned up under the held object.
		var upper_up := Vector3(0.5 * sgn, 0.8, 0.3)
		var fore_up := Vector3(0.12 * sgn, 0.97, 0.2)
		var hand_up := Vector3(-0.15 * sgn, 0.85, 0.5)
		var upper_fwd := Vector3(0.1 * sgn, 0.3, 0.95)
		var fore_fwd := Vector3(-0.04 * sgn, 0.2, 1.0)
		var hand_fwd := Vector3(0.0, 0.25, 1.0)
		# Shoulder blades lie down the back of the upright ribcage instead of pushing the arms forward.
		_aim_chain_bone(sk, names[4], names[0], Vector3(0.14 * sgn, -0.55, 0.82), w)
		# Tall: arms down the belly, paws together in front of it.
		var upper_tall := Vector3(0.12 * sgn, -0.95, 0.25)
		var fore_tall := Vector3(-0.12 * sgn, -0.8, 0.6)
		var hand_tall := Vector3(-0.1 * sgn, -0.9, 0.4)
		var ud := upper_relaxed.lerp(upper_up, arms_up).lerp(upper_fwd, arms_forward).lerp(upper_tall, tall)
		var fd := fore_relaxed.lerp(fore_up, arms_up).lerp(fore_fwd, arms_forward).lerp(fore_tall, tall)
		var hd := hand_relaxed.lerp(hand_up, arms_up).lerp(hand_fwd, arms_forward).lerp(hand_tall, tall)
		_aim_chain_bone(sk, names[0], names[1], ud, w)
		_aim_chain_bone(sk, names[1], names[2], fd, w)
		_aim_chain_bone(sk, names[2], names[3], hd, w)


func _apply_head(sk: Skeleton3D, stand_w: float) -> void:
	var head_id: int = _ids[NECK[2]]
	var head := sk.get_bone_global_pose(head_id)
	var cur := head.basis.y.normalized()
	# Standing: return the head to its neutral, level direction (the body pitch tilted it up).
	var desired := cur.slerp(HEAD_NEUTRAL.normalized(), stand_w)
	if look_weight > 0.001:
		var skel_xf := sk.global_transform
		var local_target := skel_xf.affine_inverse() * look_target
		var to := local_target - head.origin
		if to.length_squared() > 1e-6:
			to = to.normalized()
			# Limit yaw to +-75 degrees and pitch to -40..+50 degrees around the neutral direction.
			var yaw := clampf(atan2(to.x, to.z), deg_to_rad(-75.0), deg_to_rad(75.0))
			var pitch := clampf(asin(clampf(to.y, -1.0, 1.0)), deg_to_rad(-40.0), deg_to_rad(50.0))
			var look_dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			desired = desired.slerp(look_dir, look_weight)
	var fractions := [0.35, 0.5, 1.0]
	for i in NECK.size():
		var id: int = _ids[NECK[i]]
		var now := sk.get_bone_global_pose(head_id).basis.y.normalized()
		var target := now.slerp(desired, fractions[i])
		_aim_bone(sk, id, now, target)


## Restores each helper's input-pose orientation relative to the child bone it shadows.
func _fix_helpers(sk: Skeleton3D, before: Dictionary) -> void:
	for h in HELPERS:
		var helper_id: int = _ids[h[1]]
		var child_old: Transform3D = before[h[2]]
		var helper_old: Transform3D = before[h[1]]
		var child_new := sk.get_bone_global_pose(_ids[h[2]])
		var rel := child_old.basis.inverse() * helper_old.basis
		var cur := sk.get_bone_global_pose(helper_id)
		sk.set_bone_global_pose(helper_id, Transform3D(child_new.basis * rel, cur.origin))


## Analytic two-bone IK: places `end`'s origin at `target`, bending toward `pole` (model space).
func _solve_two_bone(sk: Skeleton3D, root: int, mid: int, end: int, target: Vector3, pole: Vector3) -> void:
	var a := sk.get_bone_global_pose(root).origin
	var b := sk.get_bone_global_pose(mid).origin
	var c := sk.get_bone_global_pose(end).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to := target - a
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var u := to.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var p := pole - u * pole.dot(u)
	if p.length_squared() < 1e-8:
		p = Vector3.FORWARD
	p = p.normalized()
	var knee := a + (u * cos_a + p * sqrt(1.0 - cos_a * cos_a)) * l1
	_aim_bone(sk, root, (b - a).normalized(), (knee - a).normalized())
	var b2 := sk.get_bone_global_pose(mid).origin
	var c2 := sk.get_bone_global_pose(end).origin
	_aim_bone(sk, mid, (c2 - b2).normalized(), (a + u * d - b2).normalized())


## Turns `bone` so the direction toward `child` blends toward `dir` (model space) by weight w.
func _aim_chain_bone(sk: Skeleton3D, bone: String, child: String, dir: Vector3, w: float) -> void:
	var b: int = _ids[bone]
	var cur := _bone_dir(sk, b, _ids[child])
	_aim_bone(sk, b, cur, cur.slerp(dir.normalized(), w))


func _bone_dir(sk: Skeleton3D, bone: int, child: int) -> Vector3:
	var o := sk.get_bone_global_pose(bone).origin
	var c := sk.get_bone_global_pose(child).origin
	var d := c - o
	return d.normalized() if d.length_squared() > 1e-10 else Vector3.UP


## Rotates `bone` (around its own origin, in skeleton space) so that direction `from` maps to `to`.
func _aim_bone(sk: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.is_equal_approx(to):
		return
	var axis := from.cross(to)
	if axis.length_squared() < 1e-12:
		return
	var angle := from.angle_to(to)
	_rotate_global(sk, bone, Basis(axis.normalized(), angle))


func _rotate_global(sk: Skeleton3D, bone: int, rot: Basis) -> void:
	var g := sk.get_bone_global_pose(bone)
	sk.set_bone_global_pose(bone, Transform3D(rot * g.basis, g.origin))
