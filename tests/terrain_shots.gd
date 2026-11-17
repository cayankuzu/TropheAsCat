extends SceneTree
## Windowed screenshot run for the terrain (aerial, strata quarry, blast crater, magma shaft, slab edge).
##   Godot_console.exe --path <project> --script res://tests/terrain_shots.gd --resolution 1280x720 [-- shot_names... noedits clipbox voxel=<m>]
## PNGs go to res://tests/out/terrain_<name>.png.

const SHOTS := {
	"aerial": [Vector3(-250.0, 170.0, 300.0), Vector3(60.0, -20.0, -40.0), 55.0],
	"aerial_high": [Vector3(0.0, 760.0, 690.0), Vector3(0.0, 0.0, 30.0), 50.0],
	"quarry": [Vector3(40.0, 14.0, 162.0), Vector3(40.0, -30.0, 78.0), 68.0],
	"crater": [Vector3(-66.0, 13.0, -58.0), Vector3(-92.0, -5.0, -84.0), 62.0],
	"crater_rim": [Vector3(-77.0, 2.2, -73.0), Vector3(-92.0, -0.8, -86.0), 66.0],
	"crater_big": [Vector3(268.0, 22.0, -150.0), Vector3(220.0, -8.0, -190.0), 62.0],
	"shaft": [Vector3(-151.5, 16.0, 121.8), Vector3(-150.0, -46.0, 120.0), 50.0],
	"corner": [Vector3(-300.0, 140.0, -170.0), Vector3(-320.0, 0.0, -320.0), 60.0],
	"edge": [Vector3(-860.0, -110.0, 960.0), Vector3(-470.0, -14.0, 480.0), 46.0],
	"underside": [Vector3(-300.0, -260.0, 420.0), Vector3(-60.0, -48.0, 120.0), 60.0],
	"detail": [Vector3(125.5, 2.6, 50.0), Vector3(135.0, -0.8, 39.0), 62.0],
	"ground": [Vector3(10.0, 1.6, 30.0), Vector3(40.0, 0.0, 10.0), 70.0],
	"top": [Vector3(0.0, 1500.0, 0.01), Vector3(0.0, 0.0, 0.0), 0.0],
}

var terrain: Node3D   # WorldTerrain; loaded at runtime because autoload names do not exist yet when a --script main loop compiles
var cam: Camera3D
var queue: Array[String] = []
var current := ""
var wait := 0
var frame := 0
var no_edits := false
var debug_view := 0


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var clipbox := args.has("clipbox")
	no_edits = args.has("noedits")
	var voxel := 0.5
	for a: String in args.duplicate():
		if a.begins_with("voxel="):
			voxel = float(a.substr(6))
			args.erase(a)
		elif a.begins_with("debug="):
			debug_view = int(a.substr(6))
			args.erase(a)
	args.erase("clipbox")
	args.erase("noedits")
	queue.assign(args if not args.is_empty() else ["aerial", "aerial_high", "quarry", "crater", "crater_rim", "crater_big", "shaft", "edge", "underside", "detail", "ground"])
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(TerrainTestEnv.make_environment())
	world.add_child(TerrainTestEnv.make_sun())
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.near = 0.1
	world.add_child(cam)
	terrain = load("res://game/terrain/world_terrain.gd").new()
	terrain.clipbox_streaming = clipbox
	terrain.voxel_size = voxel
	world.add_child(terrain)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2 and debug_view != 0:
		(terrain.voxels.material as ShaderMaterial).set_shader_parameter(&"u_debug_view", debug_view)
	if frame == 2 and not no_edits:
		_make_edits()
	if frame < 3:
		return false
	if current == "":
		if queue.is_empty():
			print("shots done")
			quit(0)
			return true
		current = queue.pop_front()
		var s: Array = SHOTS[current]
		if s[2] <= 0.0:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 1150.0
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = s[2]
		cam.global_position = s[0]
		cam.look_at(s[1], Vector3.UP)
		wait = 0
		return false
	wait += 1
	var tasks := _pending_tasks()
	if (wait > 45 and tasks == 0 and terrain.pending_edits() == 0) or wait > 900:
		var img := root.get_viewport().get_texture().get_image()
		var path := "res://tests/out/terrain_%s.png" % current
		img.save_png(path)
		print("saved ", path, " after ", wait, " frames, tasks=", tasks)
		current = ""
	return false


func _pending_tasks() -> int:
	var st: Dictionary = VoxelEngine.get_stats()
	var tasks: Dictionary = st.get("tasks", {})
	var n := 0
	for k in tasks:
		n += int(tasks[k])
	return n


func _make_edits() -> void:
	var t := Time.get_ticks_msec()
	# Terraced quarry down into the magma: the walls are a geology cross-section.
	var c := Vector3(40.0, 0.0, 96.0)
	var level_h := 6.6
	for k in 7:
		var hs := 46.0 - 6.5 * k
		var y_lo := -level_h * (k + 1)
		var y_hi := 4.0 if k == 0 else -level_h * k + 0.05
		terrain.dig_box(AABB(Vector3(c.x - hs, y_lo, c.z - hs), Vector3(2.0 * hs, y_hi - y_lo, 2.0 * hs)))
	print("quarry boxes ms: ", Time.get_ticks_msec() - t)
	# Blast crater (with ejecta rim) between two roads, and a maximum-size one (r = 24 m, ridge built from
	# async spheres) on the lawn south-east of it.
	terrain.explode(Vector3(-92.0, 0.5, -84.0), 30.0, 2.5e7)
	terrain.explode(Vector3(220.0, 0.5, -190.0), 40.0, 3.0e8)
	# Magma shaft.
	var y := 1.0
	while y > -40.0:
		terrain.dig_sphere(Vector3(-150.0, y, 120.0), 6.0)
		y -= 2.5
	terrain.dig_sphere(Vector3(-150.0, -42.0, 120.0), 4.0)
	# Bite out of the slab edge to show the strata from outside.
	for i in 8:
		terrain.dig_sphere(Vector3(-512.0, -6.0 - i * 5.0, 470.0 - i * 2.0), 14.0)
	# Small-scale damage at the x = 128 road edge: blunt dents, a heat pit, a rubble mound on the lawn.
	for i in 5:
		var hit := DamageHit.point(Vector3(130.0 + i * 1.7, 0.0, 44.0 - i * 1.1), Vector3(0.3, -1.0, 0.0), 40000.0 + 15000.0 * i, 10.0, DamageHit.Kind.BLUNT)
		terrain.receive_damage(hit, 0)
	terrain.receive_damage(DamageHit.point(Vector3(132.0, 0.0, 36.5), Vector3.DOWN, 500000.0, 0.0, DamageHit.Kind.HEAT), 0)
	terrain.add_sphere(Vector3(143.0, -0.7, 41.0), 1.9)
	terrain.flush_edits()
	print("edits: ", terrain.get_stats(), " total ms ", Time.get_ticks_msec() - t)
