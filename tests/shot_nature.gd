extends Node
## Windowed check of the protected nature in the composed world: lasers a street tree (CAT-PROOF ripple
## and tag), blasts the ground under it (the tree must stay on its clod), then looks at the block from
## above. Saves tests/out/nature_*.png and prints NATURE_* lines.
## Run: Godot --path <P> res://tests/shot_nature.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const TREE := Vector3(10.5, 0.0, 24.0)
const STAND := Vector3(2.0, 1.0, 34.0)

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _bot := CatInput.new()
var _cam: Camera3D
var _frame_ms := PackedFloat32Array()
var _last_usec := 0
var _tree_y := 0.0


func _ready() -> void:
	Progress.sandbox_all_tools = true   # this test needs every tool on the belt
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > 200 and _frame < T0:
		_frame_ms.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	var f := _frame - T0
	match f:
		0:
			var nature := _main.get_node("Nature") as WorldNature
			print("NATURE_COUNT trees=%d bushes=%d" % [nature.tree_count(), nature.bushes.size()])
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			var sum := 0.0
			for v: float in sorted:
				sum += v
			print("NATURE_FRAME_MS avg=%.2f p50=%.2f p95=%.2f draw=%d prims=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
			_cat = Game.player as CatPlayer
			_cat.global_position = STAND
			_cat.velocity = Vector3.ZERO
			_cat.reset_physics_interpolation()
			_cat.bot_input = _bot
			var d := TREE - STAND
			_cat.camera.yaw = atan2(-d.x, -d.z)
			_cat.camera.pitch = deg_to_rad(3.0)
			_cat.camera.snap_to_target()
		60:
			_bot.tool_slot = ToolKit.slot_of(&"laser")
		70:
			var hit := _cat.belt.get_current().crosshair_hit()
			var col: Object = hit.get("collider")
			print("NATURE_AIM pos=", hit.get("position"), " protected=", col != null and CatTool.is_cat_proof(col as Node))
			for t in (_main.get_node("Nature") as WorldNature).trees:
				if Vector2(t.global_position.x - TREE.x, t.global_position.z - TREE.z).length() < 0.5:
					_tree_y = t.global_position.y
			_bot.attack = true
		86:
			_save("nature_catproof.png")
		110:
			_bot.attack = false
			print("NATURE_ANSWERS ", WorldFX.instance.shield.answers)
		130:
			DamageRouter.apply_blast(DamageHit.blast(TREE + Vector3(0.0, 0.3, 2.5), 6.0, 5.0e6, 8000.0, DamageHit.Kind.EXPLOSION, null))
		215:
			_cam = Camera3D.new()
			_cam.fov = 55.0
			_cam.far = 3000.0
			add_child(_cam)
			_cam.look_at_from_position(TREE + Vector3(-9.0, 3.0, 9.0), TREE + Vector3(0.0, 1.0, 0.0), Vector3.UP)
			_cam.make_current()
		220:
			_save("nature_clod.png")
			for t in (_main.get_node("Nature") as WorldNature).trees:
				if Vector2(t.global_position.x - TREE.x, t.global_position.z - TREE.z).length() < 0.5:
					print("NATURE_TREE_MOVED ", absf(t.global_position.y - _tree_y) > 0.001, " ground_now=", Game.terrain.call(&"sdf_at", TREE + Vector3(0.0, -0.5, 2.0)))
			print("NATURE_ANSWERS_AFTER_BLAST ", WorldFX.instance.shield.answers)
		225:
			_cam.look_at_from_position(Vector3(-70.0, 60.0, 80.0), Vector3(20.0, 0.0, -10.0), Vector3.UP)
		240:
			_save("nature_aerial.png")
			print("NATURE_AERIAL draw=%d prims=%d fps=%.0f" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), Performance.get_monitor(Performance.TIME_FPS)])
			get_tree().quit(0)


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
