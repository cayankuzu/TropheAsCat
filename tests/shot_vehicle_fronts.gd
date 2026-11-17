extends Node3D
## Windowed check (2026-11-17): every vehicle of VehicleLibrary in a grid, seen from the side, its -Z end (the
## front, by the convention of Traffic, CatDriving and the props) marked by a red post: every nose must touch
## its post (VehicleLibrary.NOSE_AT_PLUS_Z turns the ones whose long axis came out the other way). Saves
## tests/out/vehicle_fronts.png. Run: Godot --path <P> res://tests/shot_vehicle_fronts.tscn --resolution 1920x1080

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.8, 0.86)
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var lib := VehicleLibrary.new()
	add_child(lib)
	var names: Array[StringName] = lib.passenger + lib.service
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(1.0, 0.1, 0.1)
	post_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in names.size():
		var m := lib.build(names[i])
		var col := i % 4
		var row := i / 4
		var at := Vector3(col * 13.5, row * -6.5, 0.0)
		# Lengthwise along screen x: the model's -Z points to screen right.
		m.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), at)
		add_child(m)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.25, 3.5, 0.25)
		pm.material = post_mat
		post.mesh = pm
		var box := BreakableProp.bounds_of(m, m)
		post.position = at + Vector3(box.size.z * 0.5 + 0.6, 1.75, 0.0)
		add_child(post)
		var label := Label3D.new()
		label.text = String(names[i])
		label.font_size = 96
		label.pixel_size = 0.01
		label.position = at + Vector3(0.0, 4.2, 0.0)
		label.modulate = Color(0.05, 0.05, 0.1)
		add_child(label)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 34.0
	cam.position = Vector3(20.0, -11.0, 40.0)
	cam.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tests/out/vehicle_fronts.png")
	get_tree().quit()
