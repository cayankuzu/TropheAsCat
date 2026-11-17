class_name Boot
extends Node
## The first scene of the game (project main scene, game/boot.tscn).
##
## 1. The loading screen comes up at once; the main scene is read on a worker thread and then builds
##    the world over many frames, so the screen stays alive and the bar moves.
## 2. The title over a slow flight round the city: the glitching name and the menu.
## 3. Play: a new Table, or a saved one put back (SaveGame.apply), then Trophe drops from the sky and the
##    Owner speaks. Quitting to the title and loading from the pause menu come back here with
##    pending_slot set: -1 shows the title, a slot loads that game straight away.

const MAIN_SCENE := "res://game/main.tscn"
const ORBIT_CENTRE := Vector3(0.0, 10.0, 30.0)
const ORBIT_RADIUS := 125.0
const ORBIT_HEIGHT := 62.0

## The game to load when this scene comes up (-1: show the title).
static var pending_slot := -1

var main: Node3D
var loading: LoadingScreen
var title: TitleScreen
var camera: Camera3D
## The slot that was put back, -1 for a new Table (set when play starts).
var started_slot := -2

var _orbit := 0.6
var _flying := false


func _ready() -> void:
	Settings.load_and_apply()
	loading = LoadingScreen.new()
	add_child(loading)
	if DisplayServer.get_name() != "headless":
		Audio.set_music_mood(&"intro")
	ResourceLoader.load_threaded_request(MAIN_SCENE)
	_load_main()


func _load_main() -> void:
	var progress := []
	while true:
		var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_error("Boot: could not load %s" % MAIN_SCENE)
			return
		loading.set_progress(0.15 * (float(progress[0]) if not progress.is_empty() else 0.0), "reading the Table")
		await get_tree().process_frame
	var scene := ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
	main = scene.instantiate() as Node3D
	main.set(&"auto_start", false)
	main.connect(&"stage_done", func(what: String, f: float) -> void: loading.set_progress(0.15 + 0.85 * f, what))
	main.connect(&"world_ready", _on_world_ready)
	# The title camera is there before the world: the terrain streams around it until Trophe arrives.
	camera = Camera3D.new()
	camera.name = "TitleCamera"
	camera.fov = 55.0
	camera.far = 3000.0
	add_child(camera)
	_place_camera()
	camera.make_current()
	add_child(main)


func _on_world_ready() -> void:
	var slot := pending_slot
	pending_slot = -1
	if slot >= 0 and SaveGame.exists(slot):
		await loading.fade_out()
		start(slot)
		return
	title = TitleScreen.new()
	add_child(title)
	title.new_game.connect(func() -> void: start(-1))
	title.load_game.connect(start)
	title.quit_game.connect(func() -> void: get_tree().quit())
	_flying = true
	await loading.fade_out()
	title.play()


func _process(delta: float) -> void:
	if _flying and camera != null:
		_orbit += delta * 0.03
		_place_camera()


func _place_camera() -> void:
	camera.global_position = ORBIT_CENTRE + Vector3(sin(_orbit) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(_orbit) * ORBIT_RADIUS)
	camera.look_at(ORBIT_CENTRE, Vector3.UP)


## Play: a new Table (slot -1) or the game of a slot.
func start(slot: int) -> void:
	if started_slot != -2:
		return
	started_slot = slot
	if title != null:
		await title.close()
		title = null
	var at: Vector3 = main.call(&"spawn_point")
	var continued := false
	if slot >= 0:
		var restored := SaveGame.apply(main, slot)
		if not restored.is_empty():
			at = restored["cat"]
			continued = true
	_flying = false
	# A New Table opens with the Owner's short film (not in tests, which run boot inside their own scene).
	if not continued and DisplayServer.get_name() != "headless" and get_tree().current_scene == self and camera != null:
		var opening := Opening.new()
		add_child(opening)
		await opening.play(camera)
		opening.queue_free()
	main.call(&"begin", at)
	if camera != null:
		camera.queue_free()
		camera = null
	if DisplayServer.get_name() != "headless":
		Audio.set_music_mood(&"lounge")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var voice := main.get(&"owner_voice") as OwnerVoice
	if voice != null:
		voice.intro(continued)
