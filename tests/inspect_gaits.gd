extends SceneTree
## Measures, in model units of the hero GLB: the natural ground speed of each locomotion clip (from paw
## stance phases), the withers height and body length of the mesh, and whether clips carry root motion.
## Run: Godot --headless --path <P> --script res://tests/inspect_gaits.gd

const CAT := "res://assets/models/cat/sphynx_cat.glb"
const PAWS := ["f_digit3_claw.L_20", "f_digit3_claw.R_41", "h_digit3_claw.L_73", "h_digit3_claw.R_90"]
const GAITS := ["Cat_Walk", "Cat_Trot", "Cat_Gallop_Run", "Cat_Stalk_Hunt", "Cat_Climb_Tree", "Cat_Swim"]

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
	_measure_mesh()
	_measure_gaits()
	quit(0)
	return true


func _measure_mesh() -> void:
	var mi: MeshInstance3D = _root.find_child("Object_115", true, false)
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var xf := mi.global_transform
	var withers := -1.0
	var nose := -10.0
	var rump := 10.0
	var top := -1.0
	for v in verts:
		var p := xf * v
		top = maxf(top, p.y)
		if p.z > 0.12 and p.z < 0.28:
			withers = maxf(withers, p.y)
		if p.y > 0.25:
			nose = maxf(nose, p.z)
		if p.y > 0.3 and p.y < 0.5 and absf(p.x) < 0.08 and p.z < -0.1:
			rump = minf(rump, p.z)
	print("MESH verts=%d withers_y=%.3f top_y=%.3f nose_z=%.3f rump_z(approx, includes tail base)=%.3f" % [verts.size(), withers, top, nose, rump])


func _measure_gaits() -> void:
	var skel: Skeleton3D = _root.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = _root.find_child("AnimationPlayer", true, false)
	for an in GAITS:
		var a := ap.get_animation(an)
		ap.play(an)
		var n := 240
		var dt := a.length / float(n)
		var pos: Array = []
		for k in PAWS.size():
			pos.append(PackedVector3Array())
		var ids: Array[int] = []
		for b in PAWS:
			ids.append(skel.find_bone(b))
		for i in n + 1:
			ap.seek(i * dt, true)
			skel.force_update_all_bone_transforms()
			for k in PAWS.size():
				var arr: PackedVector3Array = pos[k]
				arr.append(skel.get_bone_global_pose(ids[k]).origin)
				pos[k] = arr
		var line := "%-16s len=%.3f" % [an, a.length]
		var axis := 2   # z for ground gaits; y for climbing (paws push down the wall)
		if an == "Cat_Climb_Tree":
			axis = 1
		for k in PAWS.size():
			var arr: PackedVector3Array = pos[k]
			# Stance = samples where the paw is within 15% of its travel range of its support plane.
			var lo := 1e9
			var hi := -1e9
			var plane_lo := 1e9
			var plane_hi := -1e9
			for p in arr:
				var c: float = p[axis]
				lo = minf(lo, c)
				hi = maxf(hi, c)
				var s: float = p.y if axis == 2 else p.z
				plane_lo = minf(plane_lo, s)
				plane_hi = maxf(plane_hi, s)
			var tol := (plane_hi - plane_lo) * 0.15 + 0.004
			var speed_sum := 0.0
			var cnt := 0
			for i in n:
				var p0: Vector3 = arr[i]
				var p1: Vector3 = arr[i + 1]
				var s0: float = p0.y if axis == 2 else p0.z
				var in_stance := (s0 - plane_lo) < tol if axis == 2 else (plane_hi - s0) < tol
				if in_stance:
					speed_sum += -(p1[axis] - p0[axis]) / dt
					cnt += 1
			var v := speed_sum / maxf(cnt, 1)
			line += " | %s stance=%d%% v=%.3f range=%.3f" % [PAWS[k].substr(0, 12), int(100.0 * cnt / n), v, hi - lo]
		print(line)
