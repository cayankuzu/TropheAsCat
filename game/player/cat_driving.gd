class_name CatDriving
extends Node
## Driving (2026-11-17): Trophe gets into any car (F): a parked one, or one of the traffic (carjacked out of
## it; a police car adds heat). A cat at the wheel. W/S throttle and brake/reverse, A/D steer, Space the
## handbrake (slides), F again to get out. Arcade handling on the car prop itself (it stays the breakable
## car it was): grip, a top speed of about 115 km/h, steering that tightens with speed. What the car runs
## into at speed is hit with the energy of the crash: walls give, props fly, people shatter; crash too hard
## and the car itself wrecks and burns: she is thrown out (CAT-PROOF) and the car goes up.
##
## While she drives she rides along hidden inside the car (the camera follows her), so the police, the chaos
## stars and everything else that looks for her finds the car.

const REACH := 3.6            ## how close a car must be to get in
const TOP_SPEED := 32.0       ## m/s
const REVERSE_SPEED := 9.0
const ACCEL := 9.5
const BRAKE := 16.0
const COAST := 2.5
const STEER := 1.9            ## rad/s at speed
const GRIP := 0.02            ## share of sideways speed left after a second (a lot of grip)
const SLIDE := 0.55           ## with the handbrake
const HIT_MIN_SPEED := 4.0
const HIT_COOLDOWN := 0.35

var car: BreakableProp = null
## Last frame's handling, for tests: [grounded, throttle, forward speed, freeze, sleeping].
var debug := []
var f_presses := 0
var cars_taken := 0
var distance := 0.0

var _main: Node
var _cat: CatPlayer
var _layer: CanvasLayer
var _prompt: Label
var _speedo: Label
var _engine: AudioStreamPlayer3D
var _engine_wav: AudioStreamWAV
var _scan := 0.0
var _near: Object = null       # the car she could get into (a prop or a traffic car)
var _cam_settle := 0.0         # seconds the camera still swings round behind the car she got into
var _hit_cool := {}
var _saved_layer := 0
var _saved_mask := 0
var _box := BoxShape3D.new()
var _wheels := PhysicsMaterial.new()      # the box of the car slides on the road like it has wheels
var _saved_material: PhysicsMaterial = null
var _shape_q := PhysicsShapeQueryParameters3D.new()


func setup(main: Node, cat: CatPlayer) -> void:
	_main = main
	_cat = cat
	_engine_wav = _make_engine()
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	_prompt = _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -262.0    # above the controls line and the tool belt of the HUD
	_prompt.offset_bottom = -218.0
	_prompt.offset_left = -400.0
	_prompt.offset_right = 400.0
	_speedo = _label(54, HORIZONTAL_ALIGNMENT_RIGHT)
	_speedo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_speedo.offset_left = -360.0
	_speedo.offset_top = -170.0
	_speedo.offset_right = -40.0
	_speedo.offset_bottom = -100.0
	_shape_q.shape = _box
	_shape_q.collision_mask = Layers.STRUCTURE | Layers.PROPS | Layers.NPC | Layers.RUBBLE | Layers.DEBRIS
	Timeline.rewind_started.connect(_on_rewind)
	_wheels.friction = 0.04
	_wheels.rough = false


func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", UiKit.font(UiKit.FREDOKA, 600))
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", Color(1.0, 0.97, 0.9))
	l.add_theme_color_override(&"font_outline_color", Color(0.05, 0.07, 0.12, 0.85))
	l.add_theme_constant_override(&"outline_size", 10)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	_layer.add_child(l)
	return l


func driving() -> bool:
	return car != null


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_F:
		return
	f_presses += 1
	if car != null:
		_get_out(false)
	elif _near != null:
		_get_in(_near)
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _cat == null or not is_instance_valid(_cat):
		return
	if car == null:
		_scan -= delta
		if _scan <= 0.0:
			_scan = 0.2
			_near = _find_car()
			_prompt.visible = _near != null
			_prompt.text = tr("[F]  Get in")
		_speedo.visible = false
		return
	if not is_instance_valid(car) or car.is_broken() or car.is_wreck():
		_get_out(true)   # it went up: she is thrown clear
		return
	_drive(delta)
	if _cat.camera != null:
		var fwd := -car.global_basis.z
		_cam_settle = maxf(_cam_settle - delta, 0.0)
		_cat.camera.follow_heading(fwd, absf(car.linear_velocity.dot(fwd.normalized())), delta, _cam_settle > 0.0)


# --------------------------------------------------------------------------------------------------

func _find_car() -> Object:
	var at := _cat.global_position
	var best: Object = null
	var best_d := REACH
	var dressing: StreetDressing = _main.get("dressing")
	if dressing != null:
		for p in dressing.props:
			if not is_instance_valid(p) or not p.wreck or p.is_broken() or p.is_wreck():
				continue
			var d := p.global_position.distance_to(at) - maxf(p.size.x, p.size.z) * 0.5
			if d < best_d:
				best_d = d
				best = p
	var traffic: Traffic = _main.get("traffic")
	if traffic != null:
		for c in traffic.cars:
			if c.gone or not c.near:
				continue
			var d := c.pos.distance_to(at) - c.length * 0.5
			if d < best_d:
				best_d = d
				best = c
	return best


func _get_in(target: Object) -> void:
	var prop: BreakableProp = null
	if target is BreakableProp:
		prop = target
	else:
		var traffic: Traffic = _main.get("traffic")
		prop = traffic.take_car(target as Traffic.Car) if traffic != null else null
	if prop == null or not is_instance_valid(prop):
		return
	car = prop
	cars_taken += 1
	car.unpark()
	car.freeze = false
	car.can_sleep = false
	car.sleeping = false
	_saved_material = car.physics_material_override
	car.crash_scale = 0.12
	if _cat.camera != null:
		_cat.camera.extra_distance = 5.2        # a car needs room behind it
		_cat.camera.set_arm_exclusion(car.get_rid(), true)
		_cam_settle = 0.8
	car.physics_material_override = _wheels
	_saved_layer = _cat.collision_layer
	_saved_mask = _cat.collision_mask
	_cat.collision_layer = 0
	_cat.collision_mask = 0
	_cat.set_physics_process(false)
	_cat.visible = false
	_cat.velocity = Vector3.ZERO
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = _engine_wav
	_engine.unit_size = 10.0
	_engine.max_distance = 120.0
	_engine.volume_db = -8.0
	_engine.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	car.add_child(_engine)
	_engine.play()
	_prompt.text = tr("[F] Get out    [W/S] Drive    [A/D] Steer    [Space] Handbrake")
	_prompt.visible = true
	get_tree().create_timer(4.0, false).timeout.connect(_hide_prompt)


func _hide_prompt() -> void:
	if car != null:
		_prompt.visible = false


func _get_out(thrown: bool) -> void:
	var at := _cat.global_position
	var side := Vector3.RIGHT
	if car != null and is_instance_valid(car):
		side = -car.global_basis.x.normalized()
		at = car.global_position + side * (maxf(car.size.x, 1.6) * 0.5 + 0.9)
		car.can_sleep = true
		car.physics_material_override = _saved_material
		car.crash_scale = 1.0
		if _cat.camera != null:
			_cat.camera.set_arm_exclusion(car.get_rid(), false)
		if _engine != null and is_instance_valid(_engine):
			_engine.queue_free()
	car = null
	_engine = null
	if _cat.camera != null:
		_cat.camera.extra_distance = 0.0
	_cat.global_position = Vector3(at.x, at.y + (2.5 if thrown else 0.4), at.z)
	_cat.collision_layer = _saved_layer
	_cat.collision_mask = _saved_mask
	_cat.set_physics_process(true)
	_cat.visible = true
	_cat.velocity = (Vector3.UP * 9.0 + side * 6.0) if thrown else Vector3.ZERO
	_cat.reset_physics_interpolation()
	_prompt.visible = false
	_speedo.visible = false


func _on_rewind() -> void:
	if car != null:
		_get_out(false)


## Arcade handling on the car prop. Its model faces -Z.
func _drive(delta: float) -> void:
	var b := car.global_basis
	var fwd := -b.z.normalized()
	var right := b.x.normalized()
	var up := b.y.normalized()
	var v := car.linear_velocity
	var v_f := v.dot(fwd)
	var v_r := v.dot(right)
	var throttle := Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back")
	var steer := Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left")
	var handbrake := Input.is_action_pressed(&"jump")
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(car.global_position + up * 0.6, car.global_position - up * 0.7,
		Layers.TERRAIN | Layers.STRUCTURE | Layers.RUBBLE | Layers.DEBRIS, [car.get_rid()])
	var grounded := not space.intersect_ray(q).is_empty()
	debug = [grounded, throttle, v_f, car.freeze, car.sleeping, up.y]
	if grounded and up.y > 0.55:
		var target := 0.0
		var rate := COAST
		if throttle > 0.05:
			target = TOP_SPEED * throttle
			rate = ACCEL if v_f >= -0.5 else BRAKE
		elif throttle < -0.05:
			if v_f > 1.0:
				target = 0.0
				rate = BRAKE
			else:
				target = -REVERSE_SPEED * -throttle
				rate = ACCEL * 0.7
		if handbrake:
			target = 0.0
			rate = BRAKE * 0.6
		v_f = move_toward(v_f, target, rate * delta)
		v_r *= pow(SLIDE if handbrake else GRIP, delta)
		var v_up := v.dot(up)
		car.linear_velocity = fwd * v_f + right * v_r + up * minf(v_up, 0.0) + Vector3.DOWN * 0.0
		# Full lock at town speed, calmer on the open road; the handbrake swings the tail.
		var at_speed := lerpf(1.0, 0.55, clampf(absf(v_f) / TOP_SPEED, 0.0, 1.0))
		var turn := -steer * STEER * clampf(absf(v_f) / 7.0, 0.0, 1.0) * at_speed * signf(v_f if absf(v_f) > 0.2 else 1.0) * (1.5 if handbrake else 1.0)
		var w := car.angular_velocity
		car.angular_velocity = Vector3(w.x * 0.85, turn, w.z * 0.85)
	distance += absf(v_f) * delta
	# She rides along hidden in it; the camera follows her.
	_cat.global_position = car.global_position + Vector3.UP * (car.size.y * 0.6 + 0.4)
	_cat.velocity = car.linear_velocity
	var kmh := absf(v_f) * 3.6
	_speedo.visible = true
	_speedo.text = tr("%d km/h") % int(roundf(kmh))
	if _engine != null and is_instance_valid(_engine):
		_engine.pitch_scale = 0.55 + absf(v_f) / TOP_SPEED * 1.2 + absf(throttle) * 0.08
	_ram(fwd, v_f)


## What the front of the car meets at speed takes the crash.
func _ram(fwd: Vector3, v_f: float) -> void:
	if absf(v_f) < HIT_MIN_SPEED:
		return
	var dir := fwd * signf(v_f)
	_box.size = Vector3(maxf(car.size.x, 1.6), maxf(car.size.y * 0.8, 1.0), 1.2)
	_shape_q.transform = Transform3D(car.global_basis, car.global_position + Vector3.UP * car.size.y * 0.5 + dir * (car.size.z * 0.5 + 0.6))
	_shape_q.exclude = [car.get_rid()]
	var now := Time.get_ticks_msec() * 0.001
	var energy := minf(0.5 * car.mass * v_f * v_f * 0.3, 900000.0)
	for r in car.get_world_3d().direct_space_state.intersect_shape(_shape_q, 8):
		var rid: RID = r["rid"]
		var key := rid.get_id()
		if float(_hit_cool.get(key, 0.0)) > now:
			continue
		_hit_cool[key] = now + HIT_COOLDOWN
		var hit := DamageHit.point(car.global_position + dir * car.size.z * 0.5, dir, energy, car.mass * absf(v_f) * 0.2, DamageHit.Kind.BLUNT, _cat)
		DamageRouter.apply_hit(hit, r.get("collider"), rid)


## An engine that hums: a low saw with a little growl, looped (its pitch follows the speed).
static func _make_engine() -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var saw := fmod(t * 55.0, 1.0) * 2.0 - 1.0
		var v := saw * 0.5 + sin(TAU * 110.0 * t) * 0.3 + sin(TAU * 27.5 * t) * 0.25
		data.encode_s16(i * 2, int(clampf(v * 0.45, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s
