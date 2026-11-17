class_name CatAnimator
extends Node
## Builds and drives the cat's AnimationTree (constructed in code from CatAnimLibrary).
##
## Root blend tree:  sm (state machine) -> swat (OneShot, upper body only) -> output
## States: move (BlendSpace1D idle/walk/trot/gallop), stalk (BlendSpace1D crouch/stalk),
## air (BlendSpace1D fall/apex/rise poses), land, charge (pounce wiggle), pounce_land, climb, swim,
## hiss, lick. Loops are speed-synced: each gait has its own TimeScale fed by v / natural speed.

const STATES: Array[StringName] = [&"move", &"stalk", &"air", &"land", &"charge", &"pounce_land", &"climb", &"swim", &"hiss", &"lick"]
## Cross-fade time into each state.
const XFADE := {
	&"move": 0.22, &"stalk": 0.25, &"air": 0.12, &"land": 0.05, &"charge": 0.14, &"pounce_land": 0.06,
	&"climb": 0.14, &"swim": 0.3, &"hiss": 0.25, &"lick": 0.35,
}
## Playback-rate limits per gait (outside these the feet slide instead of the legs blurring).
const RATE_LIMITS := {
	&"walk": Vector2(0.6, 2.4), &"trot": Vector2(1.0, 2.6), &"gallop": Vector2(1.1, 2.4),
	&"stalk": Vector2(0.5, 3.4), &"climb": Vector2(0.7, 3.2), &"swim": Vector2(0.8, 2.5),
}
## Speed (m/s) bands for the gait blend: [start, full] of each blend segment.
const GAIT_BANDS := [Vector2(0.05, 0.3), Vector2(0.95, 1.25), Vector2(2.4, 2.9)]
const UPPER_BODY_ROOTS := ["scapula.L_35", "scapula.R_56", "neck_01_14"]

var tree: AnimationTree
var model_scale := 1.0
var skeleton: Skeleton3D

var _playback: AnimationNodeStateMachinePlayback
var _state: StringName = &"move"
var _timed_left := -1.0
var _timed_return: StringName = &"move"
var _lib: AnimationLibrary


func setup(model_root: Node3D, source_player: AnimationPlayer, skel: Skeleton3D, scale_factor: float) -> void:
	model_scale = scale_factor
	skeleton = skel
	_lib = CatAnimLibrary.get_library(source_player)
	source_player.active = false
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.add_animation_library(&"", _lib)
	tree.root_node = tree.get_path_to(model_root)
	tree.tree_root = _build_root(model_root)
	tree.active = true
	_playback = tree.get(&"parameters/sm/playback")
	_playback.start(&"move")


func get_state() -> StringName:
	return _state


func travel(state: StringName) -> void:
	_timed_left = -1.0
	if state == _state:
		return
	_state = state
	_playback.travel(state)


## Plays a non-looping state for `duration` seconds, then travels to `return_to`.
func play_timed(state: StringName, duration: float, return_to: StringName = &"move") -> void:
	if _state != state:
		_state = state
		_playback.travel(state)
	else:
		_playback.start(state, true)
	_timed_left = duration
	_timed_return = return_to


func is_timed_active() -> bool:
	return _timed_left > 0.0


func clip_length(clip: StringName) -> float:
	return _lib.get_animation(clip).length


func set_move_speed(v: float) -> void:
	tree.set(&"parameters/sm/move/blend_position", gait_coordinate(v))
	tree.set(&"parameters/sm/move/walk/ts/scale", _rate(&"walk", v))
	tree.set(&"parameters/sm/move/trot/ts/scale", _rate(&"trot", v))
	tree.set(&"parameters/sm/move/gallop/ts/scale", _rate(&"gallop", v))


func set_stalk_speed(v: float) -> void:
	tree.set(&"parameters/sm/stalk/blend_position", clampf(v / 0.15, 0.0, 1.0))
	tree.set(&"parameters/sm/stalk/stalk/ts/scale", _rate(&"stalk", v))


func set_air_velocity(vy: float) -> void:
	tree.set(&"parameters/sm/air/blend_position", clampf(vy / 7.0, -1.0, 1.0))


## Signed climb speed along the wall (negative = down, plays backwards).
func set_climb_speed(v: float) -> void:
	var r := 0.0
	if absf(v) > 0.05:
		r = _rate(&"climb", absf(v)) * signf(v)
	tree.set(&"parameters/sm/climb/ts/scale", r)


func set_swim_speed(v: float) -> void:
	tree.set(&"parameters/sm/swim/ts/scale", _rate(&"swim", maxf(v, 0.3)))


func set_charge(c: float) -> void:
	tree.set(&"parameters/sm/charge/ts/scale", lerpf(0.8, 2.6, c))


func play_land(impact_speed: float) -> float:
	var heavy := clampf((impact_speed - 6.0) / 16.0, 0.0, 1.0)
	var rate := lerpf(2.4, 0.95, heavy)
	tree.set(&"parameters/sm/land/ts/scale", rate)
	var d := clip_length(&"land") / rate
	play_timed(&"land", d * 0.85)
	return d


func play_pounce_land() -> float:
	tree.set(&"parameters/sm/pounce_land/ts/scale", 1.5)
	var d := clip_length(&"pounce_land") / 1.5
	play_timed(&"pounce_land", d * 0.9)
	return d


func play_swat(rate: float = 1.8) -> void:
	tree.set(&"parameters/swat_ts/scale", rate)
	tree.set(&"parameters/swat/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_swat_active() -> bool:
	return bool(tree.get(&"parameters/swat/active"))


func _process(delta: float) -> void:
	if _timed_left > 0.0:
		_timed_left -= delta
		if _timed_left <= 0.0:
			_timed_left = -1.0
			_state = _timed_return
			_playback.travel(_timed_return)


## Maps ground speed (m/s) to the 0..3 coordinate of the move blend space (idle, walk, trot, gallop).
static func gait_coordinate(v: float) -> float:
	var g := 0.0
	for i in GAIT_BANDS.size():
		var band: Vector2 = GAIT_BANDS[i]
		g += clampf((v - band.x) / (band.y - band.x), 0.0, 1.0)
	return g


func _rate(gait: StringName, v: float) -> float:
	var natural: float = CatAnimLibrary.NATURAL_SPEED[gait] * model_scale
	var lim: Vector2 = RATE_LIMITS[gait]
	return clampf(v / natural, lim.x, lim.y)


func _build_root(model_root: Node3D) -> AnimationNodeBlendTree:
	var root := AnimationNodeBlendTree.new()
	var sm := _build_state_machine()
	root.add_node(&"sm", sm, Vector2(0, 0))
	var swat_anim := AnimationNodeAnimation.new()
	swat_anim.animation = &"swat"
	root.add_node(&"swat_anim", swat_anim, Vector2(0, 200))
	var swat_ts := AnimationNodeTimeScale.new()
	root.add_node(&"swat_ts", swat_ts, Vector2(200, 200))
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.06
	shot.fadeout_time = 0.18
	shot.filter_enabled = true
	_set_upper_body_filter(shot, model_root)
	root.add_node(&"swat", shot, Vector2(400, 0))
	root.connect_node(&"swat_ts", 0, &"swat_anim")
	root.connect_node(&"swat", 0, &"sm")
	root.connect_node(&"swat", 1, &"swat_ts")
	root.connect_node(&"output", 0, &"swat")
	return root


func _build_state_machine() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 0.0
	move.max_space = 3.0
	move.add_blend_point(_anim(&"idle"), 0.0, -1, &"idle")
	move.add_blend_point(_scaled(&"walk"), 1.0, -1, &"walk")
	move.add_blend_point(_scaled(&"trot"), 2.0, -1, &"trot")
	move.add_blend_point(_scaled(&"gallop"), 3.0, -1, &"gallop")
	sm.add_node(&"move", move, Vector2(0, 0))

	var stalk := AnimationNodeBlendSpace1D.new()
	stalk.min_space = 0.0
	stalk.max_space = 1.0
	stalk.add_blend_point(_anim(&"crouch"), 0.0, -1, &"crouch")
	stalk.add_blend_point(_scaled(&"stalk"), 1.0, -1, &"stalk")
	sm.add_node(&"stalk", stalk, Vector2(200, 0))

	var air := AnimationNodeBlendSpace1D.new()
	air.min_space = -1.0
	air.max_space = 1.0
	air.add_blend_point(_anim(&"air_fall"), -1.0, -1, &"fall")
	air.add_blend_point(_anim(&"air_apex"), 0.0, -1, &"apex")
	air.add_blend_point(_anim(&"air_rise"), 1.0, -1, &"rise")
	sm.add_node(&"air", air, Vector2(400, 0))

	sm.add_node(&"land", _scaled(&"land"), Vector2(600, 0))
	sm.add_node(&"charge", _scaled(&"wiggle"), Vector2(0, 200))
	sm.add_node(&"pounce_land", _scaled(&"pounce_land"), Vector2(200, 200))
	sm.add_node(&"climb", _scaled(&"climb"), Vector2(400, 200))
	sm.add_node(&"swim", _scaled(&"swim"), Vector2(600, 200))
	sm.add_node(&"hiss", _anim(&"hiss"), Vector2(0, 400))
	sm.add_node(&"lick", _anim(&"lick"), Vector2(200, 400))

	for from in STATES:
		for to in STATES:
			if from == to:
				continue
			var trans := AnimationNodeStateMachineTransition.new()
			trans.xfade_time = XFADE[to]
			trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			trans.reset = true
			sm.add_transition(from, to, trans)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"move", start)
	return sm


func _anim(clip: StringName) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


## Animation -> TimeScale "ts" wrapped in a blend tree, so each loop gets its own playback rate.
func _scaled(clip: StringName) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"anim", _anim(clip), Vector2(0, 0))
	bt.add_node(&"ts", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node(&"ts", 0, &"anim")
	bt.connect_node(&"output", 0, &"ts")
	return bt


func _set_upper_body_filter(node: AnimationNode, model_root: Node3D) -> void:
	var skel_path := String(model_root.get_path_to(skeleton))
	var roots: Array[int] = []
	for b in UPPER_BODY_ROOTS:
		roots.append(skeleton.find_bone(b))
	for i in skeleton.get_bone_count():
		var p := i
		while p >= 0:
			if roots.has(p):
				node.set_filter_path(NodePath("%s:%s" % [skel_path, skeleton.get_bone_name(i)]), true)
				break
			p = skeleton.get_bone_parent(p)
	node.set_filter_path(NodePath("%s:%s" % [skel_path, "chest_57"]), true)
