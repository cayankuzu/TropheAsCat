extends Node
## Autoload "Perf" (2026-11-17): keeps the game smooth on any machine, from a browser on an office laptop to a
## gaming PC.
##
## A level (WorldLook.Quality LOW / MEDIUM / HIGH) decides what the world spends: how far props, trees and the
## details of buildings are drawn, how many people move near Trophe, how many pieces of debris stay awake, how
## thick the dust of a collapse is, how many cars drive (when the world is built), and the shadows and
## screen-space effects (WorldLook.QUALITIES). Systems read budget() when they build and again on
## level_changed.
##
## Auto (the default, Settings.quality = -1): the starting level comes from the machine (the browser, the
## renderer, the kind of GPU, the CPU's threads); then, while Trophe plays, a governor holds the frame time. It
## moves the 3D resolution first (FSR 1 upscaling on Vulkan / Direct3D 12, bilinear on OpenGL / WebGL; the
## HUD stays sharp), and when the resolution has been at its floor for a few seconds, or the CPU is the
## bottleneck, it steps the level down; with plenty of room for a long while it steps back up, never above
## what the machine started with plus one. A level chosen by hand stays; the resolution still adapts.

signal level_changed(level: int)

enum { LOW, MEDIUM, HIGH }

## Per level (index = LOW, MEDIUM, HIGH). Distances in metres.
const BUDGETS := {
	&"prop_range": [90.0, 160.0, 260.0],        ## loose things outside (benches, bins, lamps)
	&"big_range": [170.0, 260.0, 420.0],        ## cars, containers, kiosks
	&"inside_range": [32.0, 40.0, 45.0],        ## furniture behind the walls
	&"far_lod": [120.0, 180.0, 240.0],          ## a building turns into its merged far mesh
	&"tree_lod0": [45.0, 60.0, 70.0],           ## end of each tree LOD
	&"tree_lod1": [115.0, 145.0, 170.0],
	&"tree_lod2": [300.0, 420.0, 520.0],
	&"people": [20.0, 32.0, 44.0],              ## people animated and solid at once
	&"debris_awake": [450.0, 850.0, 1500.0],    ## debris bodies simulated at once
	&"dust": [0.4, 0.7, 1.0],                   ## share of the dust and chips of a collapse
	&"cars": [60.0, 85.0, 110.0],               ## traffic (when the world is built)
	&"scale_floor": [0.5, 0.58, 0.67],          ## the governor's lowest 3D resolution
}
## The browser demo (Game.lite) never draws further than this, whatever the level.
const LITE_CAPS := {&"prop_range": 70.0, &"big_range": 140.0, &"inside_range": 30.0, &"far_lod": 70.0,
	&"tree_lod0": 40.0, &"tree_lod1": 100.0, &"tree_lod2": 210.0, &"cars": 14.0, &"people": 22.0}

## The frame time the governor holds (60 fps); the display's own rate when that is lower.
const TARGET_FPS := 60.0
const WINDOW := 0.5            ## seconds per measurement
const SCALE_STEP_DOWN := 0.08
const SCALE_STEP_UP := 0.04
const LEVEL_COOLDOWN := 10.0   ## seconds between level changes
const UP_AFTER := 24           ## windows with plenty of room before a level goes up (12 s)
const DOWN_AFTER := 6          ## windows at the floor (or CPU-bound) before a level goes down (3 s)

## The effective level.
var level: int = HIGH
## Auto: the governor may change the level. False when the player picked one in Settings.
var auto := true
## What the machine looked like at start (see machine_level()).
var machine: int = HIGH
## The current 3D resolution scale.
var scale := 1.0
## Off: the governor leaves resolution and level alone (tests, benchmarks).
var governor := true

var _look: WorldLook = null
var _vp_rid := RID()
var _acc_ms := 0.0
var _acc_gpu := 0.0
var _acc_n := 0
var _acc_t := 0.0
var _last_usec := 0
var _slow := 0
var _fast := 0
var _cooldown := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	machine = machine_level()
	level = machine
	scale = start_scale()


## The level a machine starts at: LOW in the browser and on the OpenGL fallback (no Vulkan or Direct3D 12:
## an old GPU), by the kind and age of the GPU otherwise, capped by the CPU's threads.
func machine_level() -> int:
	if OS.has_feature("web") or Game.lite:
		return LOW
	if DisplayServer.get_name() == "headless":
		return HIGH
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return LOW
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var lvl: int = HIGH
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			# Older or entry-level discrete cards.
			for old: String in ["gtx 7", "gtx 9", "gtx 10", "gt 7", "gt 10", "mx1", "mx2", "mx3", "mx4", "mx5", "rx 4", "rx 5", "r7 ", "r9 ", "hd 7", "quadro k", "quadro m"]:
				if gpu.contains(old):
					lvl = MEDIUM
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			lvl = LOW
			# The newer integrated GPUs keep up with an entry-level card.
			for strong: String in ["iris xe", "arc", "780m", "760m", "880m", "890m", "8060s", "8050s", "radeon 7", "radeon 8", "apple m"]:
				if gpu.contains(strong):
					lvl = MEDIUM
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU, RenderingDevice.DEVICE_TYPE_CPU:
			lvl = LOW   # a virtual machine or a software renderer
		_:
			lvl = MEDIUM
	var threads := OS.get_processor_count()
	if threads <= 4:
		lvl = mini(lvl, LOW)
	elif threads <= 8:
		lvl = mini(lvl, MEDIUM)
	return lvl


## The 3D resolution a level starts at.
func start_scale() -> float:
	if OS.has_feature("web"):
		return 0.8
	return [0.8, 0.9, 1.0][level]


## What a system may spend at the current level (see BUDGETS; the browser demo is capped by LITE_CAPS).
func budget(key: StringName) -> float:
	var v := float((BUDGETS[key] as Array)[level])
	if Game.lite and LITE_CAPS.has(key):
		v = minf(v, float(LITE_CAPS[key]))
	return v


## The tree LOD ends at the current level.
func tree_lod_ends() -> Array[float]:
	return [budget(&"tree_lod0"), budget(&"tree_lod1"), budget(&"tree_lod2")]


## Settings: -1 for Auto, else LOW / MEDIUM / HIGH chosen by hand.
func set_choice(choice: int) -> void:
	auto = choice < 0
	var want := machine if auto else clampi(choice, LOW, HIGH)
	_slow = 0
	_fast = 0
	if want != level:
		_set_level(want)
	elif _look != null:
		_look.set_quality(level)


## The world is built: its look follows the level from now on.
func attach(look: WorldLook) -> void:
	_look = look
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	if _look != null:
		_look.set_quality(level)
	_apply_scale(scale)
	level_changed.emit(level)


func _set_level(lvl: int) -> void:
	level = clampi(lvl, LOW, HIGH)
	_cooldown = LEVEL_COOLDOWN
	if _look != null and is_instance_valid(_look):
		_look.set_quality(level)
	scale = clampf(scale, budget(&"scale_floor"), 1.0)
	_apply_scale(scale)
	level_changed.emit(level)


func _apply_scale(s: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.fsr_sharpness = 0.35
	vp.scaling_3d_scale = s


## The governor: measures the frame time over half a second while Trophe plays and moves the resolution,
## then the level.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	if not governor or _look == null or not is_instance_valid(_look) or Game.player == null:
		return
	if get_tree().paused or Engine.time_scale < 0.5 or not DisplayServer.window_is_focused() or ms > 250.0:
		_acc_n = 0   # menus, slow motion, a rewind, a hidden window or a load: not representative
		_acc_t = 0.0
		_acc_ms = 0.0
		_acc_gpu = 0.0
		return
	_cooldown -= ms / 1000.0
	_acc_ms += ms
	_acc_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	_acc_n += 1
	_acc_t += ms / 1000.0
	if _acc_t < WINDOW:
		return
	var frame := _acc_ms / _acc_n
	var gpu := _acc_gpu / _acc_n
	_acc_n = 0
	_acc_t = 0.0
	_acc_ms = 0.0
	_acc_gpu = 0.0
	_decide(frame, gpu)


func _target_ms() -> float:
	var hz := DisplayServer.screen_get_refresh_rate()
	var fps := TARGET_FPS if hz <= 0.0 else minf(TARGET_FPS, hz)
	return 1000.0 / fps


func _decide(frame: float, gpu: float) -> void:
	var target := _target_ms()
	var floor_s := budget(&"scale_floor")
	var gpu_known := gpu > 0.05
	if frame > target * 1.12:
		_fast = 0
		var cpu_bound := gpu_known and gpu < frame * 0.5
		if not cpu_bound and scale > floor_s + 0.001:
			scale = maxf(scale - SCALE_STEP_DOWN, floor_s)
			_apply_scale(scale)
			return
		_slow += 1
		if auto and _slow >= DOWN_AFTER and level > LOW and _cooldown <= 0.0:
			_slow = 0
			_set_level(level - 1)
		return
	_slow = 0
	var room := gpu < target * 0.55 if gpu_known else frame < target * 0.75
	if frame < target * 1.04 and room:
		_fast += 1
		if scale < 0.999 and _fast >= 4:
			_fast = 0
			scale = minf(scale + SCALE_STEP_UP, 1.0)
			_apply_scale(scale)
		elif scale >= 0.999 and auto and _fast >= UP_AFTER and level < mini(machine + 1, HIGH) and _cooldown <= 0.0:
			_fast = 0
			_set_level(level + 1)
	else:
		_fast = 0
