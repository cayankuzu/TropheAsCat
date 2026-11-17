extends Node
## Windowed check of the composed places of the city: a flea market (and a vase swatted off its table),
## a cafe terrace, and the fuel depot going up. Saves tests/out/places_*.png and prints PLACES_* lines.
## Run: Godot --path <P> res://tests/shot_places.tscn --resolution 1280x720

const OUT := "res://tests/out/"
const T0 := 430

var _frame := 0
var _main: Node3D
var _cat: CatPlayer
var _cam: Camera3D
var _city: CityLayout
var _dressing: StreetDressing
var _vase: BreakableProp
var _vase_start := Vector3.ZERO
var _vase_broke_at := -1
var _vase_swatted := false
var _broken := 0
var _broken_before_depot := 0
var _frame_ms := PackedFloat32Array()
var _last_usec := 0


func _ready() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and _frame > 200:
		_frame_ms.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	var f := _frame - T0
	if _vase_swatted and _vase_broke_at < 0 and (not is_instance_valid(_vase) or _vase.is_broken()):
		_vase_broke_at = f
	match f:
		0:
			_city = _main.get("city") as CityLayout
			_dressing = _main.get_node("StreetDressing") as StreetDressing
			_cat = Game.player as CatPlayer
			var kinds := {}
			for p in _dressing.props:
				kinds[p.prop_id] = true
				p.broken.connect(func(_b: BreakableProp) -> void: _broken += 1)
			print("PLACES_COUNT props=%d kinds=%d courts=%d plazas=%d greens=%d yards=%d gardens=%d people=%d" % [_dressing.prop_count(), kinds.size(), _city.courts.size(),
				_city.plazas.size(), _city.greens.size(), _city.yards.size(), _city.gardens.size(), (_main.get_node("People") as People).count()])
			_cam = Camera3D.new()
			_cam.fov = 55.0
			_cam.far = 2000.0
			add_child(_cam)
			_cam.make_current()
			var court := _city.courts[0]
			_move_cat(court + Vector3(-30.0, 0.5, 6.0))
			_cam.look_at_from_position(court + Vector3(-24.0, 3.6, 0.5), court + Vector3(6.0, 0.6, 0.0), Vector3.UP)
		60:
			_save("places_market.png")
			# The fragile thing on a table nearest to the camera gets a paw swat along the aisle.
			var court := _city.courts[0]
			for p in _dressing.props:
				if p.fragile and p.global_position.y > 0.4 and (_vase == null or p.global_position.distance_to(court + Vector3(-20.0, 0.0, 0.0)) < _vase.global_position.distance_to(court + Vector3(-20.0, 0.0, 0.0))):
					_vase = p
			_vase_start = _vase.global_position
			_cam.look_at_from_position(_vase_start + Vector3(-2.2, 1.0, 2.6), _vase_start, Vector3.UP)
			print("PLACES_VASE %s at %s parked=%s frozen=%s hp=%.0f" % [_vase.prop_id, _vase_start.snapped(Vector3.ONE * 0.01), _vase.parked, _vase.freeze, _vase.hp])
		90:
			var hit := DamageHit.point(_vase.global_position, Vector3(1.0, 0.25, 0.3).normalized(), 3000.0, 300.0, DamageHit.Kind.BLUNT, _cat)
			DamageRouter.apply_hit(hit, _vase, _vase.get_rid())
			print("PLACES_SWAT broken at once=%s" % [not is_instance_valid(_vase) or _vase.is_broken()])
			_vase_swatted = true
		96:
			_save("places_vase_flying.png")
		200:
			print("PLACES_VASE_END broke %s frames after the swat (%s)" % [_vase_broke_at - 90 if _vase_broke_at >= 0 else -1,
				"still whole, %.1f m away" % _vase.global_position.distance_to(_vase_start) if is_instance_valid(_vase) and not _vase.is_broken() else "gone"])
			var plaza := _city.plazas[0]
			_move_cat(plaza + Vector3(15.0, 0.5, 15.0))
			_cam.look_at_from_position(plaza + Vector3(-17.0, 7.0, -17.0), plaza + Vector3(0.0, 0.5, 0.0), Vector3.UP)
		260:
			_save("places_cafe.png")
			if not _city.yards.is_empty():
				var yard := _city.yards[0]
				_move_cat(yard + Vector3(0.0, 0.5, -34.0))
				_cam.look_at_from_position(yard + Vector3(-6.0, 9.0, -30.0), yard + Vector3(0.0, 0.5, 2.0), Vector3.UP)
		330:
			_save("places_depot.png")
			_broken_before_depot = _broken
			var drum: BreakableProp = null
			for p in _dressing.props:
				if is_instance_valid(p) and p.prop_id == &"fuel_drum" and not _city.yards.is_empty() and p.global_position.distance_to(_city.yards[0]) < 16.0:
					if drum == null or p.global_position.x < drum.global_position.x:
						drum = p
			if drum != null:
				DamageRouter.apply_hit(DamageHit.point(drum.global_position + Vector3.UP * 0.4, Vector3.DOWN, 9000.0, 50.0, DamageHit.Kind.BLUNT, _cat), drum, drum.get_rid())
		372:
			_save("places_depot_blast.png")
		520:
			print("PLACES_DEPOT props broken by the chain: %d" % (_broken - _broken_before_depot))
			var sorted := Array(_frame_ms)
			sorted.sort()
			var n := sorted.size()
			var sum := 0.0
			for v: float in sorted:
				sum += v
			print("PLACES_FRAME_MS avg=%.2f p50=%.2f p95=%.2f p99=%.2f n=%d" % [sum / n, sorted[n >> 1], sorted[int(n * 0.95)], sorted[int(n * 0.99)], n])
			# A park block from above: the paths between the groves, the benches beside them.
			var park: Vector3 = CityLayout.block_centres(CityLayout.District.PARK)[0]
			_move_cat(park + Vector3(-20.0, 0.5, 8.0))
			_cam.look_at_from_position(park + Vector3(-58.0, 46.0, 62.0), park + Vector3(0.0, 0.0, 4.0), Vector3.UP)
		580:
			_save("places_park_paths.png")
			var plaza := _city.plazas[0]
			_move_cat(plaza + Vector3(15.0, 0.5, 15.0))
			_cam.look_at_from_position(plaza + Vector3(2.0, 95.0, 46.0), plaza + Vector3(0.0, 0.5, 0.0), Vector3.UP)
		640:
			_save("places_downtown_ground.png")
			get_tree().quit(0)


func _move_cat(to: Vector3) -> void:
	_cat.global_position = to
	_cat.velocity = Vector3.ZERO
	_cat.reset_physics_interpolation()


func _save(file: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + file)
	print("saved ", file)
