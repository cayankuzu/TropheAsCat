extends SceneTree
## Headless inspection of the hero cat GLB: node tree, skeleton bones, animations, size and forward axis.

const CAT := "res://assets/models/cat/sphynx_cat.glb"

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
	print("== NODE TREE ==")
	_print_tree(_root, 0)

	var skel: Skeleton3D = _find(_root, "Skeleton3D") as Skeleton3D
	print("== SKELETON == ", skel.get_path())
	print("bone_count=", skel.get_bone_count(), " skeleton global xf=", skel.global_transform)
	for i in skel.get_bone_count():
		var gr: Transform3D = skel.get_bone_global_rest(i)
		var wp: Vector3 = skel.global_transform * gr.origin
		var y_axis: Vector3 = (skel.global_transform.basis * gr.basis).y.normalized()
		print("%3d %-26s p=%3d world=(%.3f, %.3f, %.3f) boneY=(%.2f, %.2f, %.2f)" % [
			i, skel.get_bone_name(i), skel.get_bone_parent(i), wp.x, wp.y, wp.z, y_axis.x, y_axis.y, y_axis.z])

	var ap: AnimationPlayer = _find(_root, "AnimationPlayer") as AnimationPlayer
	print("== ANIMATIONS == ", ap.get_path(), " root_node=", ap.root_node)
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		for an in lib.get_animation_list():
			var a: Animation = lib.get_animation(an)
			var kinds := {}
			var hips_track := -1
			for t in a.get_track_count():
				var k := a.track_get_type(t)
				kinds[k] = kinds.get(k, 0) + 1
				var p := str(a.track_get_path(t))
				if p.ends_with(":hips_106") and k == Animation.TYPE_POSITION_3D:
					hips_track = t
			var root_motion := ""
			if hips_track >= 0:
				var n := a.track_get_key_count(hips_track)
				var p0: Vector3 = a.track_get_key_value(hips_track, 0)
				var p1: Vector3 = a.track_get_key_value(hips_track, n - 1)
				var mn := p0
				var mx := p0
				for kk in n:
					var v: Vector3 = a.track_get_key_value(hips_track, kk)
					mn = mn.min(v)
					mx = mx.max(v)
				root_motion = "hips keys=%d start=%s end=%s min=%s max=%s" % [n, str(p0), str(p1), str(mn), str(mx)]
			print("anim='%s' length=%.3f loop=%d tracks=%d types=%s %s" % [an, a.length, a.loop_mode, a.get_track_count(), str(kinds), root_motion])
	if ap.get_animation_list().size() > 0:
		var a0: Animation = ap.get_animation(ap.get_animation_list()[0])
		for t in mini(a0.get_track_count(), 6):
			print("   track ", t, " ", a0.track_get_path(t), " type=", a0.track_get_type(t))

	print("== MESH AABB (rest) ==")
	var total := AABB()
	var first := true
	for mi in _find_all(_root, "MeshInstance3D"):
		var m: MeshInstance3D = mi
		var ab: AABB = m.global_transform * m.get_aabb()
		print("mesh ", m.name, " aabb=", ab, " verts?", m.mesh.get_faces().size() / 3.0 if m.mesh else 0.0, " surfaces=", m.mesh.get_surface_count() if m.mesh else 0, " skin=", m.skin != null)
		if m.mesh:
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				var desc := ""
				if mat is StandardMaterial3D:
					var sm: StandardMaterial3D = mat
					desc = "albedo=%s col=%s normal=%s rough_tex=%s metal=%.2f transp=%d cull=%d sss=%s emis=%s ao=%s" % [
						sm.albedo_texture.resource_path.get_file() if sm.albedo_texture else "-", str(sm.albedo_color),
						str(sm.normal_enabled), str(sm.roughness_texture != null), sm.metallic, sm.transparency, sm.cull_mode,
						str(sm.subsurf_scatter_enabled), str(sm.emission_enabled), str(sm.ao_enabled)]
				print("   surf ", s, " mat=", mat.resource_name if mat else "null", " ", desc)
		if first:
			total = ab
			first = false
		else:
			total = total.merge(ab)
	print("TOTAL AABB=", total, " size=", total.size)


func _print_tree(n: Node, depth: int) -> void:
	var extra := ""
	if n is Node3D:
		var n3: Node3D = n
		extra = " pos=%s rot=%s scale=%s" % [str(n3.position), str(n3.rotation_degrees), str(n3.scale)]
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_print_tree(c, depth + 1)


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null


func _find_all(n: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	if n.get_class() == cls:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_all(c, cls))
	return out
