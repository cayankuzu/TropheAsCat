extends Node
## Autoload "Game": global references, input map and time scale.
## Modules register themselves here so others can find them without hard scene paths.

signal player_registered(player: Node3D)

var player: Node3D = null
var world_root: Node3D = null
var terrain: Node = null
var structures: Node = null   ## StructureManager
var debris: Node = null       ## DebrisManager
## The lite build: the browser demo (or any export with the "demo" feature). Fewer walkers and cars, and
## the ground without Voxel Tools (FlatTerrain). Tests may set it before main.tscn is built.
var lite := OS.has_feature("web") or OS.has_feature("demo")

var _time_scale_requests: Dictionary = {}   # key -> scale
var _perf_left := 5.0
## "-- --no-hud" on the command line hides every HUD layer (store-page screenshots from the test scenes).
var _no_hud := OS.get_cmdline_user_args().has("--no-hud")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	set_process(lite or _no_hud)


## The lite build prints its frame rate and draw calls every 5 s (read in the browser's console).
func _process(_delta: float) -> void:
	if _no_hud:
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		if not lite:
			return
	# Wall-clock time: when frames are slow, Godot clamps the game's delta to the physics steps it runs.
	var now := Time.get_ticks_msec() * 0.001
	if now < _perf_left:
		return
	_perf_left = now + 2.0
	var line := "PERF fps=%d draws=%d objects=%d prims=%d physics_ms=%.1f process_ms=%.1f nodes=%d bodies=%d" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)]
	print(line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__perf = %s;" % JSON.stringify(line))
		# Profiling switch for the browser demo: window.__cmd = "shadow" / "glow" / "fog" / "sky" / "ui" / "scale"
		# or the name of a world node ("Terrain", "StreetDressing", "Nature", ...) toggles it.
		var cmd := str(JavaScriptBridge.eval("(window.__cmd || '')"))
		if cmd != "":
			JavaScriptBridge.eval("window.__cmd = '';")
			_debug_toggle(cmd)


func _debug_toggle(cmd: String) -> void:
	var root := get_tree().root
	match cmd:
		"shadow":
			for l in root.find_children("*", "DirectionalLight3D", true, false):
				(l as DirectionalLight3D).shadow_enabled = not (l as DirectionalLight3D).shadow_enabled
		"glow", "fog", "sky":
			for we in root.find_children("*", "WorldEnvironment", true, false):
				var e := (we as WorldEnvironment).environment
				if cmd == "glow":
					e.glow_enabled = not e.glow_enabled
				elif cmd == "fog":
					e.fog_enabled = not e.fog_enabled
				else:
					e.background_mode = Environment.BG_COLOR if e.background_mode == Environment.BG_SKY else Environment.BG_SKY
		"ui":
			for c in root.find_children("*", "CanvasLayer", true, false):
				(c as CanvasLayer).visible = not (c as CanvasLayer).visible
		"scale":
			get_viewport().scaling_3d_scale = 0.4 if get_viewport().scaling_3d_scale > 0.5 else 0.75
		_:
			var n := root.find_child(cmd, true, false)
			if n is Node3D:
				(n as Node3D).visible = not (n as Node3D).visible


func get_world_3d() -> World3D:
	var vp := get_viewport()
	return vp.world_3d if vp != null else null


func register_player(p: Node3D) -> void:
	player = p
	# Nobody may hold on to a cat that has left (quitting to the title frees the whole world).
	p.tree_exiting.connect(func() -> void:
		if player == p:
			player = null, CONNECT_ONE_SHOT)
	player_registered.emit(p)


## Several systems may want slow motion at once (rewind, chaos governor, abilities).
## The lowest requested scale wins; pass 1.0 or call clear_time_scale to release.
func request_time_scale(key: StringName, scale: float) -> void:
	_time_scale_requests[key] = clampf(scale, 0.05, 1.0)
	_apply_time_scale()


func clear_time_scale(key: StringName) -> void:
	_time_scale_requests.erase(key)
	_apply_time_scale()


func _apply_time_scale() -> void:
	var s := 1.0
	for v in _time_scale_requests.values():
		s = minf(s, v)
	Engine.time_scale = s


func _setup_input() -> void:
	_key(&"move_forward", [KEY_W, KEY_UP])
	_key(&"move_back", [KEY_S, KEY_DOWN])
	_key(&"move_left", [KEY_A, KEY_LEFT])
	_key(&"move_right", [KEY_D, KEY_RIGHT])
	_key(&"jump", [KEY_SPACE])
	_key(&"sprint", [KEY_SHIFT])
	_key(&"crouch", [KEY_CTRL, KEY_C])
	_key(&"interact", [KEY_F])
	_key(&"grab", [KEY_E])
	_key(&"rewind", [KEY_R])
	_key(&"slow_motion", [KEY_Q])
	_key(&"stand_up", [KEY_Z])
	_key(&"pause", [KEY_ESCAPE])
	_key(&"tool_next", [KEY_TAB])
	for i in range(1, 10):
		_key(StringName("tool_%d" % i), [KEY_0 + i])
	_mouse(&"attack", MOUSE_BUTTON_LEFT)
	_mouse(&"aim", MOUSE_BUTTON_RIGHT)
	_mouse(&"tool_wheel_up", MOUSE_BUTTON_WHEEL_UP)
	_mouse(&"tool_wheel_down", MOUSE_BUTTON_WHEEL_DOWN)


func _key(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
