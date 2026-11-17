extends Node3D
## Windowed check (2026-11-17): drivers in their seats. Six vehicles of the traffic, built the way Traffic
## builds a near car (the model turned to face +Z, centred on the body) with a driver seated by
## Traffic.seat_transform, seen from the driver's side and from the front-left. Saves tests/out/drivers_side.png
## and tests/out/drivers_front.png.
## Run: Godot --path <P> res://tests/shot_drivers.tscn --resolution 1600x900

const VEHICLES: Array[StringName] = [&"compact", &"sedan", &"suv", &"pickup", &"taxi", &"citybus"]


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.78, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 60.0, 0.0)
	add_child(sun)
	var people := People.new()
	add_child(people)
	var lib := VehicleLibrary.new()
	add_child(lib)
	var traffic := Traffic.new()
	add_child(traffic)
	var x := 0.0
	for vname in VEHICLES:
		var body := Node3D.new()
		add_child(body)
		var model := lib.build(vname)
		body.add_child(model)
		model.rotate_y(PI)
		var box := BreakableProp.bounds_of(model, body)
		model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
		var c := Traffic.Car.new()
		c.length = box.size.z
		c.height = box.size.y
		c.width = box.size.x
		var d := people.make_driver(body, -1)
		var fig: Node3D = d[0]
		fig.transform = traffic.seat_transform(c, float(d[3]))
		# The cars stand side by side along x, all facing +Z: their left (the driver's side) looks at +X.
		body.position = Vector3(x, 0.0, 0.0)
		x += maxf(c.width, 2.0) + 3.5
	# The same figure on its own beside the row, to see the pose.
	var lone := Node3D.new()
	add_child(lone)
	lone.position = Vector3(-4.0, 0.0, 0.0)
	var ld := people.make_driver(lone, 0)
	var lfig: Node3D = ld[0]
	var players := lfig.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap := players[0] as AnimationPlayer
		print("DRIVER anim=%s playing=%s has_drive=%s has_sit=%s hip_h=%.2f" % [ap.current_animation, ap.is_playing(), ap.has_animation(&"Drive"), ap.has_animation(&"Sit"), float(ld[3])])
		var sk := lfig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var tree := []
		for bi in sk.get_bone_count():
			var par := sk.get_bone_parent(bi)
			tree.append("%s<%s" % [sk.get_bone_name(bi), sk.get_bone_name(par) if par >= 0 else "-"])
		print("BONES ", ", ".join(tree))
		var tracks := []
		var anim_res := ap.get_animation(&"Idle")
		for ti in anim_res.get_track_count():
			var path := String(anim_res.track_get_path(ti))
			if path.contains("Foot") or path.contains("Leg"):
				tracks.append("%s:%d" % [path.get_slice(":", 1), anim_res.track_get_type(ti)])
		print("LEGTRACKS ", ", ".join(tracks))
		for clip: StringName in [&"Idle", &"Sit", &"Drive"]:
			ap.play(clip)
			ap.seek(0.0, true)
			ap.pause()
			sk.force_update_all_bone_transforms()
			var names := []
			for bn: String in ["UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R", "Head"]:
				var bi := sk.find_bone(bn)
				if bi >= 0:
					var gp := sk.global_transform * sk.get_bone_global_pose(bi)
					names.append("%s %s" % [bn, (gp.origin - lone.global_position).snappedf(0.01)])
			print("POSE %s: %s" % [clip, ", ".join(names)])
		ap.play(&"Drive")
		ap.seek(0.0, true)
		ap.pause()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	# From the driver's side of the first three, at eye height.
	cam.fov = 40.0
	cam.global_position = Vector3(30.0, 1.6, 2.0)
	cam.look_at(Vector3(4.0, 1.0, 0.0), Vector3.UP)
	await _frames(4)
	get_viewport().get_texture().get_image().save_png("res://tests/out/drivers_side.png")
	# From the front left, a little above.
	cam.global_position = Vector3(x * 0.5 + 2.0, 4.5, 14.0)
	cam.look_at(Vector3(x * 0.5 - 6.0, 0.8, 0.0), Vector3.UP)
	await _frames(4)
	get_viewport().get_texture().get_image().save_png("res://tests/out/drivers_front.png")
	# The lone figure and the first car from their left side (+X), level.
	cam.global_position = Vector3(-4.0 - 7.0, 0.9, 0.0)
	cam.look_at(Vector3(-4.0, 0.7, 0.0), Vector3.UP)
	cam.fov = 30.0
	await _frames(3)
	get_viewport().get_texture().get_image().save_png("res://tests/out/drivers_pose.png")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
