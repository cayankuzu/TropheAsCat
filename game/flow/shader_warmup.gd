class_name ShaderWarmup
extends RefCounted
## Shader warm-up (2026-11-17). OpenGL and WebGL (the browser demo, and the PC game's OpenGL fallback) compile
## a material's shader the first time something with it is drawn, and Vulkan / Direct3D 12 do the same on the
## first run on a machine: that frame stalls, tens of milliseconds on a PC and far more in a browser. The
## first look round the city, the first person who walked up (92 ms on the 2026-11-17 bench) and the first
## explosion each stuttered. While the loading screen still covers the world, run() draws everything once
## from high above the Table: every draw range opened, every hidden part shown, the sun's shadow stretched
## over all of it, a figure of every kind of person and a burst of every effect deep under the ground; then
## it puts everything back.

const FRAMES := 3
## Effects go off this far under the ground of the middle of the city: drawn (and so compiled) behind the
## loading screen, never seen.
const UNDER := 40.0


static func run(main: Node3D, camera: Camera3D) -> void:
	if main == null or camera == null or DisplayServer.get_name() == "headless":
		return
	var tree := main.get_tree()
	var t0 := Time.get_ticks_msec()
	# Everything shown, every draw range opened.
	var hidden: Array[Node3D] = []
	var ranged: Array[GeometryInstance3D] = []
	var ranges := PackedFloat32Array()
	for n in main.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if not n3.visible:
			hidden.append(n3)
			n3.visible = true
		var g := n3 as GeometryInstance3D
		if g != null and (g.visibility_range_begin > 0.0 or g.visibility_range_end > 0.0):
			ranged.append(g)
			ranges.append(g.visibility_range_begin)
			ranges.append(g.visibility_range_end)
			g.visibility_range_begin = 0.0
			g.visibility_range_end = 0.0
	# The camera high over the middle of the Table, the whole city in view; the sun's shadow over all of it.
	var cam_xf := camera.global_transform
	var cam_fov := camera.fov
	var cam_far := camera.far
	var reach := CityLayout.half_extent() + 120.0
	var height := reach / tan(deg_to_rad(40.0)) + 60.0
	camera.fov = 80.0
	camera.far = height * 2.0 + 800.0
	camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0.0, height, 0.0))
	var look := main.get("look") as WorldLook
	var sun: DirectionalLight3D = look.sun if look != null else null
	var shadow_mode := DirectionalLight3D.SHADOW_ORTHOGONAL
	var shadow_distance := 0.0
	if sun != null:
		shadow_mode = sun.directional_shadow_mode
		shadow_distance = sun.directional_shadow_max_distance
		sun.directional_shadow_max_distance = camera.far
	# A figure of every kind of person, and every effect, under the ground in the middle of the city.
	var below := Vector3(0.0, TerrainShape.height_at(0.0, 0.0) - UNDER, 0.0)
	var figures: Array[Node3D] = []
	var people := main.get("people") as People
	if people != null:
		figures = people.sample_figures(below)
	var sm := Game.structures as StructureManager
	if sm != null:
		var prop_materials: Array[StringName] = []
		var dressing := main.get("dressing") as StreetDressing
		if dressing != null:
			var seen := {}
			for p in dressing.props:
				if is_instance_valid(p) and not seen.has(p.material_name):
					seen[p.material_name] = true
					prop_materials.append(p.material_name)
		figures.append_array(sm.warm_samples(below, prop_materials))
	var dfx := main.get_node_or_null(^"DestructionFX") as DestructionFX
	if dfx != null:
		dfx.dust(below, Vector3.ONE * 2.0, &"concrete", 0.6)
		dfx.impact_dust(below + Vector3(6.0, 0.0, 0.0), 0.6)
		dfx.chips(below + Vector3(-6.0, 0.0, 0.0), Vector3.ONE, &"glass", 0.6)
	var wfx := WorldFX.instance
	if wfx != null:
		wfx.spark_burst(below, Vector3.UP, 12)
		wfx.puff(below, Vector3.UP, WorldFX.SOOT, 1.0, 1.0, 2.0)
		wfx.flame(below, Vector3.UP, 1.0, 1.0, 1.5)
		wfx.splash(below, Vector3.UP, 6, WorldFX.ACID)
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	# Everything back as it was.
	for i in ranged.size():
		var g := ranged[i]
		if is_instance_valid(g):
			g.visibility_range_begin = ranges[i * 2]
			g.visibility_range_end = ranges[i * 2 + 1]
	for n in hidden:
		if is_instance_valid(n):
			n.visible = false
	for f in figures:
		if is_instance_valid(f):
			f.queue_free()
	if sun != null and is_instance_valid(sun):
		sun.directional_shadow_mode = shadow_mode
		sun.directional_shadow_max_distance = shadow_distance
	if is_instance_valid(camera):
		camera.fov = cam_fov
		camera.far = cam_far
		camera.global_transform = cam_xf
	await tree.process_frame
	print("ShaderWarmup: %d ms (%d hidden parts shown, %d draw ranges opened, %d figures)" % [Time.get_ticks_msec() - t0, hidden.size(), ranged.size(), figures.size()])
