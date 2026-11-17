extends Node
## Prints, for every vehicle of VehicleLibrary, its size, the material names of its meshes and its height
## profile along its length (-Z to +Z), to find which end is the front.

func _ready() -> void:
	var lib := VehicleLibrary.new()
	add_child(lib)
	await get_tree().process_frame
	for vname: StringName in lib.passenger + lib.service:
		var m := lib.build(vname)
		add_child(m)
		var box := BreakableProp.bounds_of(m, m)
		var bins := PackedFloat32Array()
		bins.resize(12)
		bins.fill(-1.0e9)
		var mats := {}
		var names := {}
		for node in m.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			names[String(mi.name)] = true
			var xf := m.global_transform.affine_inverse() * mi.global_transform
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat != null:
					mats[mat.resource_name] = true
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for i in range(0, verts.size(), maxi(1, verts.size() / 4000)):
					var v := xf * verts[i]
					var k := clampi(int((v.z - box.position.z) / box.size.z * 12.0), 0, 11)
					bins[k] = maxf(bins[k], v.y)
		var prof := []
		for b in bins:
			prof.append("%.2f" % b)
		print("VEH %s size %s | heights -Z..+Z: %s" % [vname, box.size, " ".join(prof)])
		print("    meshes: %s" % ", ".join(names.keys()))
		print("    mats: %s" % ", ".join(mats.keys()))
		m.free()
	get_tree().quit()
