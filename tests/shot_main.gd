extends Node
## Windowed smoke test of the composed world: loads res://game/main.tscn, waits for streaming,
## takes screenshots from the cat's camera and from an aerial camera, fires two blasts, reports, quits.
## Run: Godot --path <P> res://tests/shot_main.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const D := preload("res://game/destruction/destruction_defs.gd")
const Util := preload("res://tests/city_test_util.gd")
var _frame := 0
var _main: Node3D
var _aerial: Camera3D
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _last_usec := 0


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	# The world is built over several frames now: the numbers come when it stands.
	_main.connect(&"world_ready", func() -> void:
		print("MAIN_LOAD_MS world built in %d ms (%d ms after the engine started): %s" % [_main.call(&"build_ms"), Time.get_ticks_msec(), ", ".join(_main.get("load_report"))]))
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > 120:
		var ms := float(now - _last_usec) / 1000.0
		_frame_ms.append(ms)
		# The frame after a screenshot is always long (saving the PNG); anything else here is a real hitch.
		if ms > 50.0:
			print("MAIN_HITCH frame=%d ms=%.0f%s" % [_frame, ms, " (screenshot)" if _frame in [601, 691, 901] else ""])
	_last_usec = now
	if _frame == 600:
		_save("main_player_view.png")
	elif _frame == 610:
		_aerial = Camera3D.new()
		_aerial.fov = 60.0
		_aerial.far = 3000.0
		add_child(_aerial)
		_aerial.look_at_from_position(Vector3(-125, 100, -125), Vector3(40, 8, 40), Vector3.UP)
		_aerial.make_current()
	elif _frame == 690:
		_save("main_aerial.png")
	elif _frame == 700:
		# One blast each on the nearest tower, apartment block and house, and one on open ground.
		var city := _main.get("city") as CityLayout
		var at: Vector3 = Game.player.global_position
		var energies := {D.Style.TOWER: 6.0e6, D.Style.APARTMENT: 5.0e6, D.Style.HOUSE: 4.0e6}
		for style: int in energies:
			var lot := city.nearest_lot(style, at)
			if not lot.is_empty():
				var p := Util.wall_point(lot["bid"], 5.0 if style != D.Style.HOUSE else 2.0)
				print("MAIN_BLAST %s at %s, %.0f m from the cat" % [D.STYLE_NAMES[style], p.snapped(Vector3.ONE * 0.1), p.distance_to(at)])
				DamageRouter.apply_blast(DamageHit.blast(p, 6.5, energies[style], 9000.0))
		DamageRouter.apply_blast(DamageHit.blast(Vector3(-30.0, 0.5, 30.0), 6.0, 4.0e6, 6000.0))
	elif _frame == 900:
		_save("main_after_blast.png")
		var stats: Dictionary = {}
		if Game.structures != null:
			stats = Game.structures.call(&"stats")
		print("MAIN_STATS ", JSON.stringify(stats))
		var sorted := Array(_frame_ms)
		sorted.sort()
		var n := sorted.size()
		if n > 0:
			var sum := 0.0
			for v: float in sorted:
				sum += v
			print("MAIN_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f n=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], n])
		print("MAIN_CAT_POS ", Game.player.global_position if Game.player != null else Vector3.INF)
		print("MAIN_PROGRESS cleared %.3f %% (%.0f t of %.0f t), next milestone %d, belt %d tools" % [Progress.cleared_percent(), Progress.destroyed_mass / 1000.0,
			Progress.total_mass / 1000.0, Progress.next_milestone(), (Game.player as CatPlayer).belt.slots.filter(func(t: CatTool) -> bool: return t != null).size()])
		var city2 := _main.get("city") as CityLayout
		var nature := _main.get_node("Nature") as WorldNature
		var dressing := _main.get_node("StreetDressing") as StreetDressing
		print("MAIN_CITY buildings=%d (downtown %d, old quarter %d, works %d) trees=%d bushes=%d props=%d draw=%d prims=%d" % [city2.lots.size(),
			city2.count_in(CityLayout.District.DOWNTOWN), city2.count_in(CityLayout.District.OLD_QUARTER), city2.count_in(CityLayout.District.WORKS),
			nature.tree_count(), nature.bushes.size(), dressing.prop_count(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
		get_tree().quit(0)


func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + file)
	print("saved ", file)
