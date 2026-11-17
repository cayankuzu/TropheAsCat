extends SceneTree
## Checks how the rig's jnt_* helper bones follow their neighbours during animation (parent vs child).

const CAT := "res://assets/models/cat/sphynx_cat.glb"
const TRIPLES := [
	["thigh.L_86", "jnt_knee.L_85", "shin.L_84"],
	["shin.L_84", "jnt_hock.L_83", "foot.L_82"],
	["hips_106", "jnt_hip.L_104", "thigh.L_86"],
	["upperarm.L_33", "jnt_elbow.L_32", "forearm.L_31"],
	["forearm.L_31", "jnt_wrist.L_30", "hand.L_29"],
	["scapula.L_35", "jnt_shoulder.L_34", "upperarm.L_33"],
]

var _root: Node3D
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(CAT)
	_root = ps.instantiate()
	get_root().add_child(_root)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var skel: Skeleton3D = _root.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = _root.find_child("AnimationPlayer", true, false)
	for an in ["Cat_Gallop_Run", "Cat_Leap_Jump"]:
		ap.play(an)
		for t in [0.1, 0.2, 0.3, 1.1, 1.3]:
			if t > ap.get_animation(an).length:
				continue
			ap.seek(t, true)
			skel.force_update_all_bone_transforms()
			var line := "%s t=%.1f" % [an, t]
			for tri in TRIPLES:
				var qa := skel.get_bone_global_pose(skel.find_bone(tri[0])).basis.get_rotation_quaternion()
				var qh := skel.get_bone_global_pose(skel.find_bone(tri[1])).basis.get_rotation_quaternion()
				var qb := skel.get_bone_global_pose(skel.find_bone(tri[2])).basis.get_rotation_quaternion()
				var ab := rad_to_deg(qa.angle_to(qb))
				var ah := rad_to_deg(qa.angle_to(qh))
				var hb := rad_to_deg(qh.angle_to(qb))
				line += " | %s: parent-child=%.0f parent-helper=%.0f helper-child=%.0f" % [tri[1].substr(4, 6), ab, ah, hb]
			print(line)
	quit(0)
	return true
