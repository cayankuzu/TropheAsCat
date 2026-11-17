extends Node
## Windowed check of the world rewind: the domino run goes over and stands up again; an apartment block is
## blown up, collapses and is rewound until it stands as before. Saves tests/out/rewind_*.png and prints
## REWIND_* lines (intact elements, TABLE CLEARED %, fallen dominoes, frame times while rewinding).
## Run: Godot --path <P> res://tests/shot_rewind.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430
const D := preload("res://game/destruction/destruction_defs.gd")
const Util := preload("res://tests/city_test_util.gd")

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _sm: StructureManager
var _run: DominoRun
var _phase := "wait"
var _t := 0
var _bid := -1
var _spot := {}
var _intact0 := 0
var _cleared0 := 0.0
var _collapsed := 0
var _ms := PackedFloat32Array()
var _last := 0
var _ok := true


func _ready() -> void:
	Progress.sandbox_all_tools = true   # the rewind is unlocked at 1 %; the sandbox has it at once
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _go(phase: String) -> void:
	_phase = phase
	_t = 0


func _process(_delta: float) -> void:
	_frame += 1
	_t += 1
	var now := Time.get_ticks_usec()
	if Timeline.is_rewinding() and _last > 0:
		_ms.append(float(now - _last) / 1000.0)
	_last = now
	match _phase:
		"wait":
			if _frame == T0:
				_cat = Game.player as CatPlayer
				_sm = Game.structures as StructureManager
				_run = _main.get("dominoes") as DominoRun
				_cam = Camera3D.new()
				_cam.fov = 55.0
				_cam.far = 2000.0
				add_child(_cam)
				_cam.make_current()
				var first := _run.tiles[0]
				var mid := _run.tiles[_run.tiles.size() >> 1].global_position
				_cam.look_at_from_position(mid + Vector3(2.5, 11.0, -22.0), mid + Vector3(0.0, 0.5, 4.0), Vector3.UP)
				DamageRouter.apply_hit(DamageHit.point(first.global_position + Vector3.UP * 1.6, Vector3(0.0, 0.0, 1.0), 3000.0, 300.0, DamageHit.Kind.BLUNT, _cat), first, first.get_rid())
				_go("dominoes_fall")
		"dominoes_fall":
			if _t == 300:
				_save("rewind_dominoes_down.png")
				print("REWIND_DOMINO before rewind: %d of %d down" % [_run.fallen, _run.tiles.size()])
				Timeline.begin_rewind()
				_go("dominoes_rewind")
		"dominoes_rewind":
			if _t == 120:
				_save("rewind_dominoes_mid.png")
			if Timeline.depth >= Timeline.max_depth() - 0.01 or _t >= 420:
				Timeline.end_rewind()
				_go("dominoes_after")
		"dominoes_after":
			if _t == 20:
				var upright := 0
				for t in _run.tiles:
					if is_instance_valid(t) and t.global_basis.y.y > 0.95:
						upright += 1
				_save("rewind_dominoes_after.png")
				print("REWIND_DOMINO after rewind: %d of %d upright, run says %d down, depth %.1f s" % [upright, _run.tiles.size(), _run.fallen, Timeline.depth])
				_ok = _ok and upright >= _run.tiles.size() - 2
				_building()
				_go("collapse")
		"collapse":
			if _t == 300:
				_collapsed = _sm.count_intact(_bid)
				_save("rewind_collapsed.png")
				print("REWIND_BUILDING collapsed: %d of %d intact, cleared %.3f %%" % [_collapsed, _intact0, Progress.cleared_percent()])
				_ms.clear()
				print("REWIND_DIAG begin: log %d entries from %.2f to %.2f, sm clock %.2f, timeline now %.2f max depth %.2f" % [_sm._gone_t.size(),
					_sm._gone_t[0] if not _sm._gone_t.is_empty() else -1.0, _sm._gone_t[_sm._gone_t.size() - 1] if not _sm._gone_t.is_empty() else -1.0,
					_sm._time, Timeline.now, Timeline.max_depth()])
				Timeline.begin_rewind()
				_go("building_rewind")
		"building_rewind":
			if _t == 90:
				_save("rewind_building_mid.png")
			if Timeline.depth >= Timeline.max_depth() - 0.01 or _t >= 420:
				print("REWIND_DIAG end depth %.2f of %.2f, intact before end %d" % [Timeline.depth, Timeline.max_depth(), _sm.count_intact(_bid)])
				Timeline.end_rewind()
				_go("building_after")
		"building_after":
			if _t == 1 or _t == 10 or _t == 30:
				var counts := [0, 0, 0, 0]
				var b = _sm.buildings[_bid]
				for e in b.state.size():
					counts[b.state[e]] += 1
				print("REWIND_DIAG t=%d states intact/pending/destroyed/detached %s gone log %d, solver busy %s" % [_t, counts, _sm._gone_t.size(), not b.solver.is_idle()])
			if _t == 60:
				var intact := _sm.count_intact(_bid)
				_save("rewind_building_after.png")
				var sorted := Array(_ms)
				sorted.sort()
				var n := maxi(sorted.size(), 1)
				print("REWIND_BUILDING after rewind: %d of %d intact (revived %d), cleared %.3f %% (was %.3f %% before the blast)" % [intact, _intact0,
					_sm.revived, Progress.cleared_percent(), _cleared0])
				print("REWIND_FRAME_MS while rewinding p50=%.2f p95=%.2f max=%.2f n=%d" % [sorted[n >> 1] if not sorted.is_empty() else 0.0,
					sorted[int(n * 0.95)] if not sorted.is_empty() else 0.0, sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0, sorted.size()])
				_ok = _ok and intact >= _intact0 - 2 and _collapsed < _intact0 - 20
				print("REWIND_RESULT ok=%s rewinds=%d" % [_ok, Timeline.rewinds])
				get_tree().quit(0)


## An apartment block of the Old Quarter, the cat beside it, blown up at the ground floor.
func _building() -> void:
	_spot = Util.stand_before(_main, D.Style.APARTMENT, Vector3(-60.0, 0.0, -100.0), 22.0)
	_bid = int(_spot["bid"])
	_sm.wake_building(_bid)
	_intact0 = _sm.count_intact(_bid)
	_cleared0 = Progress.cleared_percent()
	var pos: Vector3 = _spot["position"]
	_cat.global_position = pos
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()
	var centre: Vector3 = _spot["centre"]
	var away := (pos - centre)
	away.y = 0.0
	away = away.normalized()
	_cam.look_at_from_position(centre + away * 40.0 + Vector3.UP * 14.0 + away.cross(Vector3.UP) * 12.0, centre + Vector3.UP * 6.0, Vector3.UP)
	for k in 3:
		var at := centre + away.cross(Vector3.UP) * (k - 1) * 7.0 + Vector3.UP * 1.5
		DamageRouter.apply_blast(DamageHit.blast(at, 7.0, 9.0e6, 9000.0, DamageHit.Kind.EXPLOSION, _cat))


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
