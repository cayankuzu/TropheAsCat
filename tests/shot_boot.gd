extends Node
## Windowed check of the frame around play: the loading screen, the title and its glitch, a new game with
## the Owner's greeting, some damage, the pause menu (Esc), a save into slot 3, and then the same game
## loaded into a freshly built Table. Saves tests/out/boot_*.png and prints BOOT_* lines.
## Run: Godot --path <P> res://tests/shot_boot.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const SLOT := 3

var _boot: Boot
var _frame := 0
var _phase := "loading"
var _t := 0
var _glitch_saved := false
var _loading_saved := false
var _saved := {}
var _boots := 0


func _ready() -> void:
	# This node must keep running while the game is paused; the game itself must not.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_new_boot(-1)


func _new_boot(slot: int) -> void:
	Boot.pending_slot = slot
	_boot = (load("res://game/boot.tscn") as PackedScene).instantiate() as Boot
	_boot.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_boot)
	_boots += 1


func _go(phase: String) -> void:
	_phase = phase
	_t = 0


func _process(_delta: float) -> void:
	_frame += 1
	_t += 1
	if _frame > 9000:
		print("BOOT_TIMEOUT in phase ", _phase)
		get_tree().quit(1)
	match _phase:
		"loading":
			if _t == 2:
				_save("boot_loading_first.png")
			if not _loading_saved and is_instance_valid(_boot.loading) and _boot.loading.progress() > 0.4:
				_loading_saved = true
				_save("boot_loading.png")
				print("BOOT_LOADING bar %.2f at frame %d" % [_boot.loading.progress(), _frame])
			if _boot.title != null and not _glitch_saved and _boot.title.title.glitch_t > 0.45:
				_glitch_saved = true
				_save("boot_title_glitch.png")
			if _boot.title != null and _boot.title.ready_for_input:
				print("BOOT_TITLE ready at frame %d, world built in %d ms" % [_frame, _boot.main.call(&"build_ms")])
				_go("title")
		"title":
			if _t == 40:
				_save("boot_title.png")
				_boot.start(-1)   # what New Table does
				_go("intro")
		"intro":
			if _t == 110:
				_save("boot_intro.png")
			if _t == 330:
				_damage()
				_go("damage")
		"damage":
			if _t == 300:
				_press(&"pause")
			if _t == 312:
				print("BOOT_PAUSE paused=%s menu=%s" % [get_tree().paused, (_boot.main.get("pause_menu") as PauseMenu).open])
				_save("boot_pause.png")
				_saved = _snapshot()
				var ok := (_boot.main.get("pause_menu") as PauseMenu).save_to(SLOT)
				print("BOOT_SAVE ok=%s %s" % [ok, JSON.stringify(_saved)])
			if _t == 330:
				_press(&"pause")
			if _t == 340:
				print("BOOT_RESUME paused=%s lines said by the Owner %d" % [get_tree().paused, (_boot.main.get("owner_voice") as OwnerVoice).lines_said])
				_boot.queue_free()
				_go("reload")
		"reload":
			if _t == 5:
				_new_boot(SLOT)
			if _t > 5 and _boot.started_slot == SLOT and not _boot.has_meta(&"seen"):
				_boot.set_meta(&"seen", _frame)
				_go("restored")
		"restored":
			if _t == 90:
				_save("boot_restored.png")
				var now := _snapshot()
				print("BOOT_RESTORED %s" % JSON.stringify(now))
				var same := int(now["removed"]) >= int(_saved["removed"]) and int(now["removed"]) - int(_saved["removed"]) < 60 \
					and absf(float(now["cleared"]) - float(_saved["cleared"])) < 0.05 and int(now["shattered"]) == int(_saved["shattered"]) \
					and int(now["props_gone"]) == int(_saved["props_gone"]) and int(now["dominoes_down"]) == int(_saved["dominoes_down"])
				print("BOOT_RESULT restored=%s boots=%d frames=%d" % [same, _boots, _frame])
				get_tree().quit(0)


## A blast at the nearest building to the landing spot, a swat at the first domino, one shattered person.
func _damage() -> void:
	var main := _boot.main
	var city := main.get("city") as CityLayout
	var best := {}
	var best_d := 1.0e18
	for lot in city.lots:
		var d := (lot["pos"] as Vector3).distance_to(Vector3(0.0, 0.0, 14.0))
		if d < best_d:
			best_d = d
			best = lot
	var at: Vector3 = best["pos"] + Vector3.UP * 3.0
	DamageRouter.apply_blast(DamageHit.blast(at, 7.0, 6.0e6, 8000.0, DamageHit.Kind.EXPLOSION, Game.player))
	var run := main.get("dominoes") as DominoRun
	var first := run.tiles[0]
	DamageRouter.apply_hit(DamageHit.point(first.global_position + Vector3.UP * 1.6, Vector3(0.0, 0.0, 1.0), 3000.0, 300.0, DamageHit.Kind.BLUNT, Game.player), first, first.get_rid())
	var people := main.get("people") as People
	people.receive_damage(DamageHit.point(Vector3.ZERO, Vector3.FORWARD, 2000.0, 0.0, DamageHit.Kind.BLUNT, Game.player), 0)
	print("BOOT_DAMAGE blast at %s (%s, %.0f m from the landing spot)" % [at.snapped(Vector3.ONE * 0.1), D_STYLE[int(best["style"])], best_d])


const D_STYLE := ["tower", "apartment", "parking", "house"]


func _snapshot() -> Dictionary:
	var sm := Game.structures as StructureManager
	var removed := 0
	for bid in sm.building_count():
		removed += sm.removed_elements(bid).size()
	var main := _boot.main
	var props: Dictionary = (main.get("dressing") as StreetDressing).save_state()
	return {"removed": removed, "cleared": snappedf(Progress.cleared_percent(), 0.001), "shattered": (main.get("people") as People).shattered,
		"props_gone": (props["gone"] as PackedStringArray).size(), "wrecks": (props["wrecks"] as PackedStringArray).size(),
		"dominoes_down": (main.get("dominoes") as DominoRun).fallen}


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
