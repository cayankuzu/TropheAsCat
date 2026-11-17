class_name CleanupRobots
extends Node
## The Owner's vacuum robots (2026-11-17). After a building comes down, or after a long chain, a few round
## robots roll out of the nearest standing buildings, drive to the rubble, vacuum it up piece by piece (a
## puff and a fwump) and roll back home when they are full or the mess is gone. They are ordinary breakable
## props steered from here: Trophe can push them, ride them, swat them over (they right themselves) and
## break them (a little battery pop; the Owner is sad, and it adds chaos heat). A robot that finds her in its
## way stops and beeps.
##
## At three chaos stars the Owner also puts DO NOT TOUCH tape round the worst ruin near her.
## A rewind sends the robots home and takes the tape down; neither is saved.

enum Job { OUT, SEEK, GO, SUCK, HOME }

const MAX_ROBOTS := 4
const SPEED := 2.6
const CAPACITY := 40          ## pieces a robot carries before it goes home
const REACH := 1.25           ## flat distance from which it vacuums a piece
const WORK_RADIUS := 28.0     ## how far from the mess it looks for rubble
const CALL_CHAIN := 18        ## a chain at least this long calls them out...
const CALL_PIECES := 10       ## ...if there is at least this much rubble about
const CALL_EVERY := 20.0      ## seconds between two call-outs
const TOPPLE_DELAY := 6.0     ## seconds after a building comes down before they come
const GIVE_UP := 3.0          ## seconds without getting nearer before it tries another piece
const WRECK_HEAT := 8.0
const MAX_TAPED := 3
const CALL_LINES: PackedStringArray = ["The robots will tidy up. Please let them.", "Cleaning crew. Do not chase them.", "I will have this swept up in no time."]
const WRECK_LINES: PackedStringArray = ["That robot had a name. It was Dusty.", "Another one. They have families, Trophe. Small ones.", "I am adding robots to the list."]
const TAPE_LINE := "Do not touch. I mean it."
const ROBOT_DEF := {"material": &"plaster", "mass": 9.0, "hp": 6500.0, "shape": "cylinder", "solid": 0.55,
	"blast": {"radius": 2.4, "energy": 1.6e5, "impulse": 1400.0}}


class Robot:
	var prop: BreakableProp
	var home := Vector3.ZERO      # the door it came out of
	var mess := Vector3.ZERO
	var job := Job.OUT
	var target := -1              # rubble index it is after
	var target_at := Vector3.ZERO
	var carried := 0
	var timer := 0.0
	var best := INF               # nearest it got to its target so far
	var since_better := 0.0
	var skip := {}                # rubble it gave up on -> until when (seconds of the clock)
	var led: MeshInstance3D
	var beep_in := 0.0
	var tipped := 0.0
	var probe_in := 0.0
	var detour := Vector3.ZERO     # the way round something in its way
	var detour_t := 0.0
	var side := 1.0               # which way it goes round things (each robot its own)


var robots: Array[Robot] = []
var called := 0
var vacuumed := 0
var wrecked := 0
var taped := 0
var tape_props: Array[BreakableProp] = []

var _dressing: StreetDressing
var _chaos: Chaos
var _voice: OwnerVoice
var _since_call := CALL_EVERY
var _taped_bids := {}
var _rng := RandomNumberGenerator.new()
var _white: StandardMaterial3D
var _dark: StandardMaterial3D
var _teal: StandardMaterial3D
var _red: StandardMaterial3D
var _meshes := {}
var _fwump: AudioStreamWAV
var _beep: AudioStreamWAV


func setup(main: Node, chaos: Chaos) -> void:
	_dressing = main.get("dressing") as StreetDressing
	_voice = main.get("owner_voice") as OwnerVoice
	_chaos = chaos
	_rng.seed = 4040
	Progress.chain_ended.connect(_on_chain_ended)
	Timeline.rewind_started.connect(send_home)
	chaos.stars_changed.connect(_on_stars)
	var sm := Game.structures as StructureManager
	if sm != null:
		sm.building_toppled.connect(_on_topple)
	_white = StandardMaterial3D.new()
	_white.albedo_color = Color(0.93, 0.94, 0.96)
	_white.roughness = 0.28
	_white.clearcoat_enabled = true
	_white.clearcoat = 0.5
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.1, 0.11, 0.13)
	_dark.roughness = 0.6
	_teal = _lamp(Color(0.35, 1.0, 0.9))
	_red = _lamp(Color(1.0, 0.2, 0.15))
	for spec: Array in [["body", 0.34, 0.36, 0.11], ["bumper", 0.37, 0.37, 0.05], ["cap", 0.17, 0.18, 0.03]]:
		var m := CylinderMesh.new()
		m.top_radius = spec[1]
		m.bottom_radius = spec[2]
		m.height = spec[3]
		m.radial_segments = 28
		_meshes[spec[0]] = m
	var led := SphereMesh.new()
	led.radius = 0.035
	led.height = 0.07
	_meshes["led"] = led
	var brush := BoxMesh.new()
	brush.size = Vector3(0.12, 0.02, 0.12)
	_meshes["brush"] = brush
	_fwump = _make_fwump()
	_beep = _make_beep()


static func _lamp(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m


# --------------------------------------------------------------------------------------------------
# Calling them out
# --------------------------------------------------------------------------------------------------

func _on_topple(bid: int, _storey: int) -> void:
	var sm := Game.structures as StructureManager
	if sm == null:
		return
	var fp := sm.building_footprint(bid)
	var at := Vector3(fp.get_center().x, 0.0, fp.get_center().y)
	get_tree().create_timer(TOPPLE_DELAY, false).timeout.connect(call_out.bind(at, true))


func _on_chain_ended(count: int) -> void:
	if count < CALL_CHAIN or Game.player == null or not is_instance_valid(Game.player):
		return
	call_out(Game.player.global_position)


## Sends robots to the mess round `at` (if there is rubble there and they have not just been out).
func call_out(at: Vector3, force: bool = false) -> int:
	var debris := Game.debris as DebrisManager
	if debris == null or (not force and _since_call < CALL_EVERY):
		return 0
	var mess := at
	mess.y = _ground(mess.x, mess.z)
	var pieces := debris.rubble_near(mess, WORK_RADIUS, 3.0, CALL_PIECES).size()
	if pieces < (1 if force else CALL_PIECES):
		return 0
	var n := mini(MAX_ROBOTS - robots.size(), 2 if pieces < 40 else 3)
	if n <= 0:
		return 0
	_since_call = 0.0
	called += 1
	var door := _door_near(mess)
	for i in n:
		var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * 0.8
		_spawn(door + side, mess)
	if _voice != null and is_instance_valid(_voice):
		_voice.speak(CALL_LINES[_rng.randi_range(0, CALL_LINES.size() - 1)], called == 1)
	return n


## The door of the nearest standing building to the mess (but not the one that came down): the point of
## its footprint nearest to the mess, a step outside. Somewhere near the mess when there is none.
func _door_near(mess: Vector3) -> Vector3:
	var sm := Game.structures as StructureManager
	var best := INF
	var door := mess + Vector3(_rng.randf_range(-14.0, 14.0), 0.0, _rng.randf_range(-14.0, 14.0))
	if sm != null:
		var p := Vector2(mess.x, mess.z)
		for bid in sm.building_count():
			var fp := sm.building_footprint(bid)
			if fp.grow(4.0).has_point(p):
				continue   # the mess itself
			var q := Vector2(clampf(p.x, fp.position.x, fp.end.x), clampf(p.y, fp.position.y, fp.end.y))
			var d := q.distance_to(p)
			if d < best and d < 80.0:
				best = d
				var out := (p - q).normalized() if d > 0.01 else Vector2.RIGHT
				door = Vector3(q.x + out.x * 1.6, 0.0, q.y + out.y * 1.6)
	door.y = _ground(door.x, door.z)
	return door


func _spawn(at: Vector3, mess: Vector3) -> void:
	if _dressing == null:
		return
	var model := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _meshes["body"]
	body.material_override = _white
	body.position.y = 0.085
	model.add_child(body)
	var bumper := MeshInstance3D.new()
	bumper.mesh = _meshes["bumper"]
	bumper.material_override = _dark
	bumper.position.y = 0.045
	model.add_child(bumper)
	var cap := MeshInstance3D.new()
	cap.mesh = _meshes["cap"]
	cap.material_override = _dark
	cap.position.y = 0.155
	model.add_child(cap)
	var led := MeshInstance3D.new()
	led.mesh = _meshes["led"]
	led.material_override = _teal
	led.position = Vector3(0.0, 0.15, 0.27)
	led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(led)
	for s: float in [-1.0, 1.0]:
		var brush := MeshInstance3D.new()
		brush.mesh = _meshes["brush"]
		brush.material_override = _dark
		brush.position = Vector3(s * 0.24, 0.012, 0.24)
		brush.rotation.y = s * 0.6
		model.add_child(brush)
	var to := mess - at
	var prop := _dressing.add_node_prop(&"cleanup_robot", model, ROBOT_DEF.duplicate(true), at, atan2(to.x, to.z), 0.02)
	if prop == null:
		return
	prop.unpark()
	prop.freeze = false
	prop.can_sleep = false
	prop.sleeping = false
	prop.angular_damp = 4.0
	var r := Robot.new()
	r.prop = prop
	r.home = at
	r.mess = mess
	r.led = led
	r.job = Job.OUT
	r.timer = 1.4
	r.side = 1.0 if _rng.randf() < 0.5 else -1.0
	robots.append(r)
	var fx := WorldFX.instance
	if fx != null:
		fx.puff(at + Vector3.UP * 0.3, Vector3.UP * 0.6, Color(0.55, 1.0, 0.95, 0.4), 0.8, 0.3, 0.8)


# --------------------------------------------------------------------------------------------------
# Work
# --------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_since_call += delta
	if robots.is_empty() or Timeline.is_rewinding():
		return
	var player := Game.player
	var cat := player.global_position if player != null and is_instance_valid(player) else Vector3.INF
	var debris := Game.debris as DebrisManager
	var claimed := {}
	for r in robots:
		if r.target >= 0:
			claimed[r.target] = true
	for i in range(robots.size() - 1, -1, -1):
		var r := robots[i]
		var p := r.prop
		if not is_instance_valid(p) or p.is_broken():
			robots.remove_at(i)
			_on_wrecked()
			continue
		if cat == Vector3.INF or p.global_position.distance_to(cat) > 110.0:
			_despawn(r)   # out of sight: back in its cupboard
			robots.remove_at(i)
			continue
		if p.freeze:
			p.parked = false
			p.freeze = false
		# Swatted over: it waits, then rights itself.
		if p.global_basis.y.dot(Vector3.UP) < 0.75:
			r.tipped += delta
			r.led.material_override = _red
			if r.tipped > 2.5 and p.linear_velocity.length() < 0.6:
				var yaw := atan2(p.global_basis.z.x, p.global_basis.z.z)
				p.global_transform = Transform3D(Basis(Vector3.UP, yaw), p.global_position + Vector3.UP * 0.12)
				p.linear_velocity = Vector3.ZERO
				p.angular_velocity = Vector3.ZERO
				r.tipped = 0.0
			continue
		r.tipped = 0.0
		r.led.material_override = _teal if fmod(Time.get_ticks_msec() * 0.001, 1.0) < 0.75 else _dark
		match r.job:
			Job.OUT:
				r.timer -= delta
				_drive(r, r.mess, delta, cat)
				if r.timer <= 0.0:
					r.job = Job.SEEK
			Job.SEEK:
				_stop(r)
				if r.carried >= CAPACITY or debris == null:
					r.job = Job.HOME
					continue
				# The piece nearest to it (the edge of the pile first), as long as it is part of the mess.
				var now := Time.get_ticks_msec() * 0.001
				r.target = -1
				for idx in debris.rubble_near(p.global_position, 14.0, 3.0, 48):
					if not claimed.has(idx) and float(r.skip.get(idx, 0.0)) < now and _flat(debris.rubble_position(idx), r.mess) <= WORK_RADIUS:
						r.target = idx
						break
				if r.target < 0:
					for idx in debris.rubble_near(r.mess, WORK_RADIUS, 3.0, 256):
						if not claimed.has(idx) and float(r.skip.get(idx, 0.0)) < now:
							r.target = idx
							break
				if r.target < 0:
					if debris.rubble_near(r.mess, WORK_RADIUS, 3.0, 1).is_empty():
						r.job = Job.HOME   # all clean
					else:
						r.job = Job.OUT    # nothing it can get at just now: back towards the pile, then again
						r.timer = 1.5
					continue
				claimed[r.target] = true
				r.target_at = debris.rubble_position(r.target)
				r.best = INF
				r.since_better = 0.0
				r.job = Job.GO
			Job.GO:
				if debris == null or not debris.rubble_alive(r.target):
					r.job = Job.SEEK
					continue
				var flat := Vector2(r.target_at.x - p.global_position.x, r.target_at.z - p.global_position.z).length()
				if flat < r.best - 0.25:
					r.best = flat
					r.since_better = 0.0
				else:
					r.since_better += delta
				if flat <= REACH or (flat < 3.2 and r.since_better > 0.6):
					# Close enough, or up against the pile it lies in: it sucks it out from there.
					r.job = Job.SUCK
					r.timer = 0.45
					_stop(r)
				elif r.since_better > GIVE_UP:
					r.skip[r.target] = Time.get_ticks_msec() * 0.001 + 8.0   # tries it again later
					r.job = Job.SEEK
				else:
					_drive(r, r.target_at, delta, cat)
			Job.SUCK:
				_stop(r)
				p.angular_velocity = Vector3(0.0, 5.0, 0.0)
				r.timer -= delta
				if r.timer <= 0.0:
					_vacuum(r, debris)
					r.job = Job.SEEK
			Job.HOME:
				var flat := Vector2(r.home.x - p.global_position.x, r.home.z - p.global_position.z).length()
				if flat < 1.2:
					_despawn(r)
					robots.remove_at(i)
					continue
				_drive(r, r.home, delta, cat)


## Turns towards `to` and rolls there; stops and beeps when Trophe is in its way.
func _drive(r: Robot, to: Vector3, delta: float, cat: Vector3) -> void:
	var p := r.prop
	var at := p.global_position
	var flat := Vector3(to.x - at.x, 0.0, to.z - at.z)
	if flat.length_squared() < 0.0004:
		_stop(r)
		return
	var fwd := Vector3(p.global_basis.z.x, 0.0, p.global_basis.z.z).normalized()
	var want := flat.normalized()
	# Something in the way (a wall, a car, a tree): it goes round it for a moment, always to its own side.
	r.probe_in -= delta
	if r.probe_in <= 0.0:
		r.probe_in = 0.2
		var from := at + Vector3.UP * 0.12
		var q := PhysicsRayQueryParameters3D.create(from, from + want * 1.1, Layers.STRUCTURE | Layers.PROPS | Layers.PROTECTED)
		q.exclude = [p.get_rid()]
		if not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			r.detour = want.rotated(Vector3.UP, deg_to_rad(80.0) * r.side)
			r.detour_t = 0.9
	if r.detour_t > 0.0:
		r.detour_t -= delta
		want = r.detour
	var turn := fwd.signed_angle_to(want, Vector3.UP)
	p.angular_velocity = Vector3(0.0, clampf(turn * 5.0, -3.5, 3.5), 0.0)
	var speed := SPEED * clampf(1.0 - absf(turn) / 1.3, 0.15, 1.0)
	if cat != Vector3.INF:
		var rel := cat - at
		if rel.dot(fwd) > 0.0 and rel.dot(fwd) < 1.4 and absf(rel.dot(Vector3(fwd.z, 0.0, -fwd.x))) < 0.6 and absf(rel.y) < 1.5:
			speed = 0.0
			r.beep_in -= delta
			if r.beep_in <= 0.0:
				r.beep_in = 1.4
				_sound(p, _beep, -10.0)
	var v := fwd * speed
	p.linear_velocity = Vector3(v.x, p.linear_velocity.y, v.z)


func _stop(r: Robot) -> void:
	var v := r.prop.linear_velocity
	r.prop.linear_velocity = Vector3(v.x * 0.5, v.y, v.z * 0.5)
	r.prop.angular_velocity = Vector3.ZERO


## Into the bag: the piece is gone with a puff of its dust and a fwump.
func _vacuum(r: Robot, debris: DebrisManager) -> void:
	if debris == null or not debris.rubble_alive(r.target):
		return
	var at := debris.rubble_position(r.target)
	if debris.take_rubble(r.target) <= 0.0:
		return
	r.carried += 1
	vacuumed += 1
	r.target = -1
	# A gulp takes the little pieces lying right next to it as well.
	var extra := 0
	for idx in debris.rubble_near(at, 1.3, 1.5, 4):
		if extra >= 2 or r.carried >= CAPACITY:
			break
		if _is_claimed(idx):
			continue
		if debris.take_rubble(idx) > 0.0:
			r.carried += 1
			vacuumed += 1
			extra += 1
	var fx := WorldFX.instance
	if fx != null:
		var mouth := r.prop.global_position + Vector3.UP * 0.2
		fx.puff(at, (mouth - at) * 1.5, Color(0.72, 0.7, 0.66, 0.5), 0.7, 0.25, 0.6)
	_sound(r.prop, _fwump, -6.0)


func _is_claimed(idx: int) -> bool:
	for o in robots:
		if o.target == idx:
			return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _despawn(r: Robot) -> void:
	if not is_instance_valid(r.prop):
		return
	var fx := WorldFX.instance
	if fx != null:
		fx.puff(r.prop.global_position + Vector3.UP * 0.3, Vector3.UP * 0.6, Color(0.55, 1.0, 0.95, 0.4), 0.8, 0.3, 0.8)
	r.prop.queue_free()


func _on_wrecked() -> void:
	wrecked += 1
	if _chaos != null:
		_chaos.add(WRECK_HEAT)
	if _voice != null and is_instance_valid(_voice):
		_voice.speak(WRECK_LINES[mini(wrecked - 1, WRECK_LINES.size() - 1)], wrecked == 1)


## A rewind: every robot back in its cupboard, the tape down.
func send_home() -> void:
	for r in robots:
		_despawn(r)
	robots.clear()
	for t in tape_props:
		if is_instance_valid(t):
			t.queue_free()
	tape_props.clear()
	_taped_bids.clear()


# --------------------------------------------------------------------------------------------------
# DO NOT TOUCH
# --------------------------------------------------------------------------------------------------

func _on_stars(stars: int) -> void:
	if stars >= 3:
		tape_worst_ruin()


## Tapes the most broken building within 140 m of Trophe that is not taped yet. Returns its id or -1.
func tape_worst_ruin() -> int:
	var sm := Game.structures as StructureManager
	if sm == null or _dressing == null or taped >= MAX_TAPED or Game.player == null:
		return -1
	var cat := Game.player.global_position
	var worst := -1
	var worst_gone := 0
	for bid in sm.building_count():
		if _taped_bids.has(bid):
			continue
		var gone: int = sm.buildings[bid].gone_count
		if gone <= worst_gone:
			continue
		var fp := sm.building_footprint(bid)
		if Vector2(fp.get_center().x - cat.x, fp.get_center().y - cat.z).length() > 140.0:
			continue
		worst = bid
		worst_gone = gone
	if worst < 0 or worst_gone < 5:
		return -1
	_taped_bids[worst] = true
	taped += 1
	_tape_round(sm.building_footprint(worst).grow(3.0))
	if _voice != null and is_instance_valid(_voice):
		_voice.speak(TAPE_LINE, taped == 1)
	return worst


## Posts every 4 m or so round a rectangle and tape between them at hip height.
func _tape_round(rect: Rect2) -> void:
	var corners := [Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y)]
	var post_def := {"material": &"plant_graphite", "mass": 3.0, "hp": 400.0, "anchored": true, "solid": 0.5}
	var tape_def := {"material": &"tape", "mass": 0.3, "hp": 30.0, "anchored": true, "solid": 0.3}
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var n := maxi(int(ceilf(a.distance_to(b) / 4.0)), 1)
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			var post := _dressing.add_box(&"tape_post", Vector3(0.06, 1.1, 0.06), &"plant_graphite", post_def.duplicate(), Vector3(p0.x, 0.0, p0.y))
			if post != null:
				tape_props.append(post)
			var mid := (p0 + p1) * 0.5
			var dir := p1 - p0
			var tape := _dressing.add_box(&"tape", Vector3(dir.length(), 0.08, 0.02), &"tape", tape_def.duplicate(), Vector3(mid.x, 0.0, mid.y),
				atan2(-dir.y, dir.x), 0.92)
			if tape != null:
				tape_props.append(tape)


# --------------------------------------------------------------------------------------------------
# Sounds (made here, like the horn of the traffic)
# --------------------------------------------------------------------------------------------------

func _sound(p: Node3D, stream: AudioStream, db: float) -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = stream
	s.unit_size = 6.0
	s.max_distance = 60.0
	s.volume_db = db
	s.pitch_scale = _rng.randf_range(0.92, 1.1)
	s.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.add_child(s)
	s.finished.connect(s.queue_free)
	s.play()


## A short suck: noise falling in pitch (0.25 s).
static func _make_fwump() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.25)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var k := lerpf(0.5, 0.06, t)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * k
		var env := sin(PI * minf(t * 1.6, 1.0)) * (1.0 - t)
		data.encode_s16(i * 2, int(clampf(lp * env * 2.2, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s


## Two little beeps.
static func _make_beep() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.32)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var on := t < 0.12 or (t > 0.18 and t < 0.3)
		var v := sin(TAU * 1760.0 * t) * 0.35 if on else 0.0
		data.encode_s16(i * 2, int(v * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0
