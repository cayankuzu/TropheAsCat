extends Node
## Windowed screenshot harness for the cat (needs a real window, 1280x720):
##   Godot --path <P> res://tests/player_shots.tscn --resolution 1280x720 --fixed-fps 60 [-- only=idle,stand]
## Drives the cat with bot input and saves PNGs to res://tests/out/shot_*.png.

const LEVEL := preload("res://tests/player_test_level.tscn")

var level: Node3D
var cat: CatPlayer
var bot := CatInput.new()
var debug_cam: Camera3D
var only: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	level = LEVEL.instantiate()
	add_child(level)
	cat = level.get_node("Cat")
	cat.bot_input = bot
	debug_cam = Camera3D.new()
	debug_cam.fov = 40.0
	add_child(debug_cam)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	await _frames(30)
	if _want("idle"):
		await _shot_idle()
	if _want("stand"):
		await _shot_stand()
	if _want("hold"):
		await _shot_hold()
	if _want("gallop"):
		await _shot_gallop()
	if _want("pounce"):
		await _shot_pounce()
	if _want("climb"):
		await _shot_climb()
	if _want("swat"):
		await _shot_swat()
	if _want("stalk"):
		await _shot_stalk()
	if _want("land"):
		await _shot_land()
	if only.has("top"):   # debug only: top-down view with a shadow-test box
		await _shot_top()
	get_tree().quit()


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func _reset_cat(pos: Vector3, yaw_deg: float) -> void:
	bot.clear()
	if cat.grab.is_holding():
		cat.grab.release(Vector3.ZERO)
	cat.global_position = pos
	cat.velocity = Vector3.ZERO
	cat._set_mode(CatPlayer.Mode.AIR)
	cat.camera.yaw = deg_to_rad(yaw_deg)
	cat._facing = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3.FORWARD
	cat.reset_physics_interpolation()
	cat.camera.snap_to_target()


func _game_cam() -> void:
	cat.camera.get_camera().make_current()


## Places the debug camera at `offset` from the cat (in the cat's facing frame) looking at its body.
func _debug_cam(offset_local: Vector3, look_h: float = 0.25) -> void:
	var f := cat.get_facing()
	var r := f.cross(Vector3.UP).normalized()
	var p := cat.global_position + r * offset_local.x + Vector3.UP * offset_local.y - f * offset_local.z
	debug_cam.global_position = p
	debug_cam.look_at(cat.global_position + Vector3.UP * look_h, Vector3.UP)
	debug_cam.make_current()


func _debug_state(tag: String) -> void:
	var sk: Skeleton3D = cat.get_node("Visual/Model").find_child("Skeleton3D", true, false)
	var ys := []
	for b in ["f_digit3_claw.L_20", "f_digit3_claw.R_41", "h_digit3_claw.L_73", "h_digit3_claw.R_90", "hips_106"]:
		ys.append(snappedf((sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin.y, 0.001))
	print("%s: mode=%d anim=%s cat_y=%.3f paws/hips world y=%s stand=%.2f visual_y=%.3f" % [tag, cat.mode, cat.animator.get_state(),
		cat.global_position.y, str(ys), cat.get_stand_amount(), (cat.get_node("Visual") as Node3D).global_position.y])


func _save(n: String) -> void:
	_debug_state(n)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/out/shot_%s.png" % n)
	print("saved shot_%s.png" % n)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot_idle() -> void:
	_reset_cat(Vector3(-2, 0.05, 6), 200.0)
	await _frames(90)
	cat.camera.yaw = deg_to_rad(200.0 + 140.0)
	cat.camera.pitch = deg_to_rad(-12.0)
	_game_cam()
	await _frames(40)
	await _save("idle")
	_debug_cam(Vector3(1.6, 0.35, 0.0))
	await _frames(3)
	await _save("idle_side")


func _shot_stand() -> void:
	_reset_cat(Vector3(-2, 0.05, 6), 200.0)
	await _frames(30)
	bot.stand = true
	await _frames(60)
	_debug_cam(Vector3(1.5, 0.4, 0.0), 0.35)
	await _frames(3)
	await _save("stand_side")
	_debug_cam(Vector3(0.9, 0.45, -1.3), 0.35)
	await _frames(3)
	await _save("stand_front")
	bot.stand = false
	bot.aim = true
	await _frames(45)
	_game_cam()
	await _frames(10)
	await _save("stand_aim")
	bot.aim = false
	await _frames(30)


func _shot_hold() -> void:
	var crate: RigidBody3D = level.get_node("Loose1")
	crate.global_position = Vector3(-1.5, 0.4, 5.0)
	crate.rotation = Vector3.ZERO
	crate.linear_velocity = Vector3.ZERO
	_reset_cat(Vector3(-1.5, 0.05, 6.4), 0.0)
	await _frames(30)
	bot.grab = true
	await _frames(2)
	bot.grab = false
	await _frames(70)
	cat.camera.yaw = deg_to_rad(-20.0)
	cat.camera.pitch = deg_to_rad(-6.0)
	_game_cam()
	await _frames(40)
	await _save("hold")
	_debug_cam(Vector3(1.4, 0.75, -1.2), 0.55)
	await _frames(3)
	await _save("hold_front")
	# Throw: charge then release, captured mid-thrust.
	_game_cam()
	bot.attack = true
	await _frames(30)
	bot.attack = false
	await _frames(5)
	await _save("throw")
	await _frames(40)


func _shot_gallop() -> void:
	_reset_cat(Vector3(0, 0.05, 20), -90.0)   # facing +X
	bot.move = Vector2(0, 1)
	bot.sprint = true
	await _frames(100)
	cat.camera.yaw = deg_to_rad(-90.0 + 50.0)
	cat.camera.pitch = deg_to_rad(-10.0)
	_game_cam()
	await _frames(12)
	await _save("gallop")
	_debug_cam(Vector3(2.1, 0.32, -0.5), 0.22)
	await _frames(1)
	await _save("gallop_side")
	bot.clear()
	await _frames(40)


func _shot_pounce() -> void:
	_reset_cat(Vector3(-20, 0.05, 30), -90.0)
	await _frames(20)
	cat.camera.pitch = deg_to_rad(-6.0)
	bot.jump = true
	await _frames(70)
	bot.jump = false
	for i in 120:
		await get_tree().physics_frame
		if cat.velocity.y < 1.0 and cat.mode == CatPlayer.Mode.AIR:
			break
	cat.camera.yaw = deg_to_rad(-90.0 + 70.0)
	_game_cam()
	await _save("pounce")
	_debug_cam(Vector3(3.2, 0.2, 0.6), 0.1)
	await _frames(1)
	await _save("pounce_side")
	await _frames(120)


func _shot_climb() -> void:
	_reset_cat(Vector3(1.0, 0.05, -8.5), 0.0)
	await _frames(20)
	bot.move = Vector2(0, 1)
	for i in 400:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.CLIMB and cat.global_position.y > 3.0:
			break
	bot.move = Vector2.ZERO
	cat.camera.yaw = deg_to_rad(35.0)
	cat.camera.pitch = deg_to_rad(5.0)
	_game_cam()
	await _frames(30)
	await _save("climb")
	bot.move = Vector2(0, 1)
	await _frames(20)
	bot.move = Vector2.ZERO
	_debug_cam(Vector3(2.2, 0.0, 0.6), 0.3)
	await _frames(3)
	await _save("climb_side")


func _shot_swat() -> void:
	_reset_cat(Vector3(-4, 0.05, 6), 90.0)
	await _frames(40)
	_debug_cam(Vector3(1.1, 0.3, -0.9), 0.25)
	bot.attack = true
	await _frames(2)
	bot.attack = false
	await _frames(9)
	await _save("swat")
	await _frames(40)


func _shot_stalk() -> void:
	_reset_cat(Vector3(-4, 0.05, 12), 90.0)
	await _frames(20)
	bot.crouch = true
	bot.move = Vector2(0, 1)
	await _frames(70)
	_debug_cam(Vector3(1.3, 0.25, -0.5), 0.15)
	await _frames(2)
	await _save("stalk")
	bot.clear()
	await _frames(20)


func _shot_land() -> void:
	_reset_cat(Vector3(-4, 9.0, 12), 90.0)
	for i in 200:
		await get_tree().physics_frame
		if cat.mode == CatPlayer.Mode.GROUND:
			break
	await _frames(6)
	_debug_cam(Vector3(1.4, 0.3, -0.6), 0.2)
	await _frames(1)
	await _save("land")
	await _frames(40)


func _shot_top() -> void:
	_reset_cat(Vector3(-4, 0.05, 14), 90.0)
	await _frames(40)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	add_child(box)
	box.global_position = cat.global_position + Vector3(1.0, 0.8, 0.0)
	var sun: DirectionalLight3D = level.get_node("Sun")
	print("sun shadow=%s energy=%.2f dir=%s caster_mask=%s cull=%s" % [sun.shadow_enabled, sun.light_energy, str(-sun.global_basis.z), str(sun.get("shadow_caster_mask")), str(sun.light_cull_mask)])
	var dec: Decal = cat.get_node("Visual/ContactShadow")
	print("decal size=%s pos=%s visible=%s tex=%s mask=%d" % [str(dec.size), str(dec.global_position), str(dec.is_visible_in_tree()), str(dec.texture_albedo), dec.cull_mask])
	debug_cam.global_position = cat.global_position + Vector3(0.3, 2.2, 0.3)
	debug_cam.look_at(cat.global_position, Vector3.FORWARD)
	debug_cam.make_current()
	await _frames(3)
	await _save("top")
