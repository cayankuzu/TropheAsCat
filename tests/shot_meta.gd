extends Node
## Windowed check of the meta game (2026-11-17): the fourteen jobs, the catnip shop (boosts and an early tool)
## and the achievements (earned from what the game counts, kept in a test file, not the player's), plus the two
## new pages of the pause menu. Prints META_* lines, saves tests/out/meta_*.png.
## Run: Godot --path <P> res://tests/shot_meta.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const TEST_PATH := "user://test_achievements.cfg"

var _frame := 0
var _main: Node3D
var _jobs: Jobs
var _ach: Achievements
var _ok := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps counting while the pause menu has the tree paused
	DirAccess.remove_absolute(TEST_PATH)
	Achievements.path = TEST_PATH
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var f := _frame - T0
	if f == 0:
		_jobs = _main.get("jobs") as Jobs
		_ach = _main.get("achievements") as Achievements
		var cat := Game.player as CatPlayer
		var people := _main.get("people") as People
		print("META_JOBS %d jobs, %d possible here" % [Jobs.JOBS.size(), _jobs.possible_count()])
		_ok = _ok and Jobs.JOBS.size() == 14 and _jobs.possible_count() == 14
		_jobs.catnip = 1000
		var jump0 := cat.jump_height
		var bought := [_jobs.buy(&"springy"), _jobs.buy(&"hat"), _jobs.buy(&"lungs"), _jobs.buy(&"springy")]
		print("META_SHOP bought=%s catnip=%d spent=%d jump %.2f -> %.2f hat=%s meow=%.0f" % [bought, _jobs.catnip, _jobs.spent, jump0, cat.jump_height, Progress.is_tool_unlocked(&"wizard_hat"), people.meow_radius])
		_ok = _ok and bought == [true, true, true, false] and _jobs.catnip == 710 and cat.jump_height > jump0 * 1.1 and Progress.is_tool_unlocked(&"wizard_hat") and is_equal_approx(people.meow_radius, 18.0)
		var state := _jobs.save_state()
		_ok = _ok and (state["owned"] as Array).size() == 3 and int(state["spent"]) == 290
	elif f == 90:
		print("META_ACH earned=%s" % [_ach.earned])
		_ok = _ok and _ach.earned.has(&"shopper") and _ach.earned.has(&"baron")
		var dressing := _main.get("dressing") as StreetDressing
		for p in dressing.props:
			if is_instance_valid(p) and p.fragile and not p.is_broken():
				p.receive_damage(DamageHit.point(p.global_position, Vector3.UP, 1.0e5, 0.0, DamageHit.Kind.EXPLOSION, null), 0)
				break
	elif f == 160:
		print("META_ACH2 earned=%s file=%s" % [_ach.earned, FileAccess.file_exists(TEST_PATH)])
		_ok = _ok and _ach.earned.has(&"first_crack") and FileAccess.file_exists(TEST_PATH)
		get_viewport().get_texture().get_image().save_png(OUT + "meta_toast.png")
		var menu := _main.get("pause_menu") as PauseMenu
		menu.show_menu()
		menu.call(&"_show_shop")
	elif f == 170:
		get_viewport().get_texture().get_image().save_png(OUT + "meta_shop.png")
		var menu := _main.get("pause_menu") as PauseMenu
		menu.call(&"_show_achievements")
	elif f == 180:
		get_viewport().get_texture().get_image().save_png(OUT + "meta_achievements.png")
		var menu := _main.get("pause_menu") as PauseMenu
		menu.resume()
		DirAccess.remove_absolute(TEST_PATH)
		print("META_RESULT ok=%s" % _ok)
		get_tree().quit(0)
