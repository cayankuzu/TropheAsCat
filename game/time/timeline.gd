extends Node
## Autoload "Timeline": world rewind (docs/DESIGN.md section 3, "Rewind"). The Owner tried Ctrl+Z on
## a block; now it is Trophe's: hold R and the Table runs backwards for up to WINDOW seconds, release it
## and time runs forward from there.
##
## Nothing is re-simulated and no full state is stored. Each part keeps what it needs, in its own clock:
##  * StructureManager logs every element that leaves a building and brings it back, newest first.
##  * DebrisManager knows when and where every piece of debris was born; while the cursor approaches a
##    piece's birth the piece flies back there, and it is gone when the cursor passes it. Falling blocks
##    fly back into the building, fracture cells back into their wall: the collapse plays in reverse.
##  * Props and people log their breaks here (props wait hidden for WINDOW seconds before they are
##    freed); awake props leave a trail of transforms every SAMPLE_EVERY seconds that is played back.
## All of them are driven by one number, the depth: seconds of game time back from the start of the rewind.
## The ground keeps its craters, fires and scorch marks fade on their own, Trophe stays where she is.

signal rewind_started
signal rewind_stopped
@warning_ignore("unused_signal")
signal time_mode_changed(mode: StringName)   ## &"normal", &"rewind"

const WINDOW_SECONDS := 15.0
## Seconds of history per second of holding R, after a short run-up.
const SPEED := 1.6
const RUN_UP := 0.7
const SAMPLE_EVERY := 0.1
## The world almost stands still while it is rewound (the camera still turns).
const TIME_SCALE := 0.05

## Game seconds since the world was made (the clock of props and people).
var now := 0.0
## Seconds rewound so far (while rewinding).
var depth := 0.0
## The People node of the current world (it registers itself).
var people: People = null
var rewinds := 0

var _rewinding := false
var _held := 0.0
var _rw_now := 0.0
var _max_depth := 0.0
var _start := 0.0
var _events: Array[Array] = []        # [time, kind, object, data] of props and people, oldest first
var _retired: Array[Array] = []       # [time, prop] broken props kept out of the world
var _awake: Dictionary = {}           # prop instance id -> prop, while it moves
var _trails: Dictionary = {}          # prop instance id -> [prop, PackedFloat64Array times, Array[Transform3D]]
var _sample_left := 0.0
var _played: Dictionary = {}          # prop instance id -> true for props moved by the playback
var _fx: RewindFX


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_fx = RewindFX.new()
	_fx.name = "RewindFX"
	add_child(_fx)


func is_rewinding() -> bool:
	return _rewinding


## A new world: forget everything that belonged to the old one.
func reset() -> void:
	if _rewinding:
		_rewinding = false
		Game.clear_time_scale(&"rewind")
		_fx.stop()
	now = 0.0
	depth = 0.0
	_start = 0.0
	_events.clear()
	_retired.clear()
	_awake.clear()
	_trails.clear()
	_played.clear()
	people = null


## Rewind is Trophe's once the Owner has tried it (the 1 % milestone) or in the sandbox.
func available() -> bool:
	return Progress.is_tool_unlocked(&"rewind") and _managers_ready() and Game.player != null


func max_depth() -> float:
	return minf(WINDOW_SECONDS, now - _start)


# --------------------------------------------------------------------------------------------------
# Recording (called by props and people)
# --------------------------------------------------------------------------------------------------

## kind: &"break" (xf: where it broke) or &"wreck".
func record_prop(prop: BreakableProp, kind: StringName, xf: Transform3D) -> void:
	if _rewinding:
		return
	_events.append([now, kind, prop, xf])


func record_person(owner_node: People, id: int, before: int) -> void:
	if _rewinding:
		return
	_events.append([now, &"shatter", owner_node, [id, before]])


## A broken prop waits out of the world until it can no longer be rewound to.
func retire_prop(prop: BreakableProp) -> void:
	_retired.append([now, prop])


## A prop started to move: its trail is recorded until it rests again.
func prop_awake(prop: BreakableProp) -> void:
	if _rewinding:
		return
	var id := prop.get_instance_id()
	if not _awake.has(id):
		_awake[id] = prop
		_sample(prop)


# --------------------------------------------------------------------------------------------------
# Rewinding
# --------------------------------------------------------------------------------------------------

func begin_rewind() -> void:
	if _rewinding or not available():
		return
	_max_depth = max_depth()
	if _max_depth <= 0.05:
		return
	_rewinding = true
	rewinds += 1
	depth = 0.0
	_held = 0.0
	_rw_now = now
	_played.clear()
	Game.request_time_scale(&"rewind", TIME_SCALE)
	(Game.structures as StructureManager).rewind_begin()
	(Game.debris as DebrisManager).rewind_begin()
	_fx.start()
	rewind_started.emit()
	time_mode_changed.emit(&"rewind")


func end_rewind() -> void:
	if not _rewinding:
		return
	_apply(depth)
	var sm := Game.structures as StructureManager
	var dm := Game.debris as DebrisManager
	if sm != null and is_instance_valid(sm):
		sm.rewind_end(depth)
	if dm != null and is_instance_valid(dm):
		dm.rewind_end(depth)
	var cut := _rw_now - depth
	# Props the playback moved go on from where they are now, as if they had been there all along.
	for id: int in _played:
		var trail: Array = _trails.get(id, [])
		if trail.is_empty() or not is_instance_valid(trail[0]):
			continue
		var prop: BreakableProp = trail[0]
		if prop.is_broken():
			continue
		if prop.has_ground():
			prop.parked = false
			prop.freeze = false
			prop.sleeping = false
		_cut_trail(id, cut)
	for id: int in _trails.keys():
		_cut_trail(id, cut)
	now = cut
	_rewinding = false
	_awake.clear()
	Game.clear_time_scale(&"rewind")
	_fx.stop()
	rewind_stopped.emit()
	time_mode_changed.emit(&"normal")


func _managers_ready() -> bool:
	var sm: Object = Game.structures
	var dm: Object = Game.debris
	return sm != null and dm != null and is_instance_valid(sm) and is_instance_valid(dm)


func _process(delta: float) -> void:
	if _rewinding:
		if not _managers_ready():
			reset()
			return
		var real := delta / maxf(Engine.time_scale, 0.0001)
		_held += real
		var rate := lerpf(0.4, SPEED, clampf(_held / RUN_UP, 0.0, 1.0))
		depth = minf(depth + real * rate, _max_depth)
		_apply(depth)
		_fx.show_depth(depth, _max_depth)
		return
	now += delta
	_sample_left -= delta
	if _sample_left <= 0.0:
		_sample_left = SAMPLE_EVERY
		for id: int in _awake.keys():
			var obj: Variant = _awake[id]   # untyped first: the prop may have been freed with its world
			if not is_instance_valid(obj) or (obj as BreakableProp).is_broken():
				_awake.erase(id)
				continue
			var prop := obj as BreakableProp
			_sample(prop)
			if prop.freeze or prop.sleeping:
				_awake.erase(id)
	_prune()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"rewind"):
		begin_rewind()
	elif event.is_action_released(&"rewind"):
		end_rewind()


## Puts everything where it was `d` seconds before the rewind began.
func _apply(d: float) -> void:
	var sm := Game.structures as StructureManager
	var dm := Game.debris as DebrisManager
	sm.rewind_to(d)
	dm.rewind_to(d)
	var cut := _rw_now - d
	while not _events.is_empty() and float(_events[_events.size() - 1][0]) > cut:
		var ev: Array = _events.pop_back()
		_undo(ev)
	if people != null and is_instance_valid(people):
		people.rewind_heads(cut)
	for id: int in _trails:
		var trail: Array = _trails[id]
		if not is_instance_valid(trail[0]):
			continue
		var prop := trail[0] as BreakableProp
		if prop.is_broken():
			continue
		var times: PackedFloat64Array = trail[1]
		if times.is_empty() or cut >= times[times.size() - 1]:
			continue
		var xfs: Array = trail[2]
		var xf: Transform3D = xfs[0]
		var k := times.bsearch(cut)
		if k > 0 and k < times.size():
			var t0 := times[k - 1]
			var t1 := times[k]
			xf = (xfs[k - 1] as Transform3D).interpolate_with(xfs[k], clampf((cut - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0))
		prop.freeze = true
		prop.global_transform = xf
		prop.reset_physics_interpolation()
		_played[id] = true


func _undo(ev: Array) -> void:
	var obj: Variant = ev[2]
	if not is_instance_valid(obj):
		return
	match StringName(ev[1]):
		&"break":
			(obj as BreakableProp).unbreak(ev[3])
			for i in range(_retired.size() - 1, -1, -1):
				if _retired[i][1] == obj:
					_retired.remove_at(i)
		&"wreck":
			(obj as BreakableProp).unwreck()
		&"shatter":
			var data: Array = ev[3]
			(obj as People).unshatter(int(data[0]), int(data[1]))


func _sample(prop: BreakableProp) -> void:
	var id := prop.get_instance_id()
	var trail: Array = _trails.get(id, [])
	if trail.is_empty():
		trail = [prop, PackedFloat64Array(), []]
		_trails[id] = trail
	var times: PackedFloat64Array = trail[1]
	times.append(now)
	trail[1] = times
	(trail[2] as Array).append(prop.global_transform)


func _cut_trail(id: int, cut: float) -> void:
	var trail: Array = _trails.get(id, [])
	if trail.is_empty():
		return
	var times: PackedFloat64Array = trail[1]
	var k := times.bsearch(cut, false)
	if k < times.size():
		trail[1] = times.slice(0, k)
		trail[2] = (trail[2] as Array).slice(0, k)
	if (trail[1] as PackedFloat64Array).is_empty():
		_trails.erase(id)


## What can no longer be rewound to is forgotten; broken props that waited for it are freed.
func _prune() -> void:
	var limit := now - WINDOW_SECONDS
	_start = maxf(_start, 0.0)
	while not _events.is_empty() and float(_events[0][0]) < limit:
		_events.pop_front()
	while not _retired.is_empty() and float(_retired[0][0]) < limit:
		var r: Array = _retired.pop_front()
		if is_instance_valid(r[1]):
			(r[1] as Node).queue_free()
	if Engine.get_process_frames() % 30 == 0:
		for id: int in _trails.keys():
			var trail: Array = _trails[id]
			if not is_instance_valid(trail[0]):
				_trails.erase(id)
				continue
			var times: PackedFloat64Array = trail[1]
			var k := times.bsearch(limit)
			if k >= times.size() and not _awake.has(id):
				_trails.erase(id)
			elif k > 1:
				# Keep one sample before the window: it is where the prop rested before it moved.
				trail[1] = times.slice(k - 1)
				trail[2] = (trail[2] as Array).slice(k - 1)
