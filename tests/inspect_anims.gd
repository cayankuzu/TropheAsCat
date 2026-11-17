extends SceneTree
## Samples key bones of every clip over time (model space, unscaled) to understand timing and posture.

const CAT := "res://assets/models/cat/sphynx_cat.glb"
const BONES := ["hips_106", "chest_57", "head_12", "hand.L_29", "hand.R_50", "foot.L_82", "foot.R_99", "tail_05_65"]

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
	_dump()
	quit(0)
	return true


func _dump() -> void:
	var skel: Skeleton3D = _root.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = _root.find_child("AnimationPlayer", true, false)
	var ids: Array[int] = []
	for b in BONES:
		ids.append(skel.find_bone(b))
	var only := OS.get_cmdline_user_args()
	for an in ap.get_animation_list():
		if only.size() > 0 and not only.has(String(an)):
			continue
		var a := ap.get_animation(an)
		print("=== ", an, " len=", a.length)
		ap.play(an)
		var step := 0.1 if a.length <= 3.0 else 0.2
		if a.length < 1.0:
			step = 0.0667
		var t := 0.0
		while t <= a.length + 0.001:
			ap.seek(t, true)
			skel.force_update_all_bone_transforms()
			var line := "t=%.2f" % t
			for k in ids.size():
				var gp: Transform3D = skel.get_bone_global_pose(ids[k])
				line += " | %s(%.2f,%.2f,%.2f)" % [BONES[k].substr(0, 6), gp.origin.x, gp.origin.y, gp.origin.z]
			var h: Vector3 = skel.get_bone_global_pose(ids[0]).origin
			var c: Vector3 = skel.get_bone_global_pose(ids[1]).origin
			var pitch := rad_to_deg(atan2(c.y - h.y, c.z - h.z))
			line += " | spine_pitch=%.0f" % pitch
			print(line)
			t += step
