extends Node3D
## Windowed check (2026-11-17): a tree drawn the old way (MeshInstance3D per part) beside the same tree in a
## MultiMesh batch (WorldNature.build_batches). Saves tests/out/tree_batch.png.

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.7, 0.78, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(sun)
	var scene := load("res://assets/models/nature/oak_large/tree_LOD0.glb") as PackedScene
	var root := scene.instantiate() as Node3D
	var parts := []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		parts.append([mi.mesh, mi.transform, mi.material_override, mi.get_surface_override_material_count()])
		print("PART %s mesh=%s override=%s surf_overrides=%d surf_mat=%s" % [mi.name, mi.mesh, mi.material_override, mi.get_surface_override_material_count(), mi.mesh.surface_get_material(0)])
	var k := 0.13
	# A 40 m chunk of 16 trees, the old way on the left, batched on the right (lod_bias as WorldNature sets it).
	for side: float in [-1.0, 1.0]:
		var origin := Vector3(side * 26.0, 0.0, 0.0)
		var frames: Array[Transform3D] = []
		for i in 16:
			frames.append(Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * k), Vector3((i % 4) * 9.0 - 13.5, 0.0, (i / 4) * -9.0)))
		if side < 0.0:
			for f in frames:
				for p: Array in parts:
					var mi := MeshInstance3D.new()
					mi.mesh = p[0]
					mi.transform = Transform3D(f.basis, f.origin + origin) * (p[1] as Transform3D)
					add_child(mi)
		else:
			for p: Array in parts:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = p[0]
				mm.instance_count = frames.size()
				for i in frames.size():
					mm.set_instance_transform(i, frames[i] * (p[1] as Transform3D))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.lod_bias = float(OS.get_environment("TREE_LOD_BIAS")) if OS.get_environment("TREE_LOD_BIAS") != "" else 1.0
				add_child(mmi)
				mmi.position = origin
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 12.0, 28.0)
	cam.look_at(Vector3(0.0, 5.0, -14.0), Vector3.UP)
	cam.fov = 75.0
	cam.make_current()
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tests/out/tree_batch_%s.png" % (OS.get_environment("TREE_LOD_BIAS") if OS.get_environment("TREE_LOD_BIAS") != "" else "1"))
	get_tree().quit()
