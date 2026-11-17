class_name Police
extends Node
## The Owner's response to the chaos stars (2026-11-17). Every star asks for more: a police car at one
## star, one more at each star after that, a road block of barriers from three stars, the fire brigade at
## four, a SWAT van at five. The units are cars of the traffic (Traffic.dispatch): they come in from out of
## sight with flashing lights and a siren, drive at Trophe, stop across their lane near her and let out
## their people (officers who walk up to her, point and order her about; the rude ones swing at her and
## never connect: she is the Owner's cat). Everything is breakable: a unit that is hit becomes a car prop
## (more heat), an officer shatters like anyone else (more heat). When the stars are gone the units drive
## off and are taken off the roads out of sight, and their people leave once she is away from them.
## A rewind sends everyone home at once.

enum Kind { POLICE, FIRE, SWAT }

const CARS_PER_STAR: Array[int] = [0, 1, 2, 3, 4, 5]
const DISPATCH_EVERY := 3.5   ## seconds between two units sent
const LEAVE_DISTANCE := 230.0 ## a unit that left is taken off the roads this far from Trophe
const AWAY_RESUME := 70.0     ## a parked unit follows again when she is farther than this...
const AWAY_SECONDS := 6.0     ## ...for this long
const MAX_OFFICERS := 16
const MAX_BLOCKS := 6
const FIGURES := {Kind.POLICE: [&"M_Swat", &"W_Soldier"], Kind.FIRE: [&"M_Worker", &"W_Worker"], Kind.SWAT: [&"M_Swat", &"M_Swat", &"W_Soldier", &"M_Swat"]}


class Unit:
	var car: Traffic.Car
	var kind := 0
	var deployed := false
	var leaving := false
	var away := 0.0
	var lights: Node3D = null
	var lamps: Array[MeshInstance3D] = []
	var light: OmniLight3D = null
	var siren: AudioStreamPlayer3D = null


var units: Array[Unit] = []
var officers: Array[int] = []     ## people ids of everyone the units let out
var dispatched := 0
var arrived := 0
var blocks := 0

var _traffic: Traffic
var _people: People
var _dressing: StreetDressing
var _chaos: Chaos
var _wait := 0.0
var _t := 0.0
var _calm := true
var _siren_wav: AudioStreamWAV
var _lamp_on := {}                # colour name -> material
var _lamp_off: StandardMaterial3D
var _swat_paint: StandardMaterial3D
var _lamp_mesh: BoxMesh
var _rng := RandomNumberGenerator.new()


func setup(main: Node, chaos: Chaos) -> void:
	_traffic = main.get("traffic") as Traffic
	_people = main.get("people") as People
	_dressing = main.get("dressing") as StreetDressing
	_chaos = chaos
	_rng.seed = 911
	if _traffic != null:
		_traffic.unit_crashed.connect(_on_crashed)
	chaos.stars_changed.connect(_on_stars)
	Timeline.rewind_started.connect(dismiss_all)
	_siren_wav = _make_siren()
	for colour: String in ["red", "blue", "white"]:
		var m := StandardMaterial3D.new()
		var c: Color = {"red": Color(1.0, 0.12, 0.1), "blue": Color(0.15, 0.35, 1.0), "white": Color(1.0, 0.95, 0.85)}[colour]
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 4.0
		_lamp_on[colour] = m
	_lamp_off = StandardMaterial3D.new()
	_lamp_off.albedo_color = Color(0.25, 0.25, 0.28)
	_lamp_off.roughness = 0.3
	_swat_paint = StandardMaterial3D.new()
	_swat_paint.albedo_color = Color(0.09, 0.11, 0.16)
	_swat_paint.roughness = 0.45
	_swat_paint.metallic = 0.3
	_lamp_mesh = BoxMesh.new()
	_lamp_mesh.size = Vector3(0.4, 0.12, 0.22)


func active_units() -> int:
	var n := 0
	for u in units:
		if not u.car.gone and not u.leaving:
			n += 1
	return n


func _count(kind: int) -> int:
	var n := 0
	for u in units:
		if u.kind == kind and not u.car.gone and not u.leaving:
			n += 1
	return n


func _process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player) or _traffic == null:
		return
	var cat := player.global_position
	_t += delta
	_chaos.watched = _sees(cat)
	var stars := _chaos.stars
	_wait -= delta
	if stars > 0 and _wait <= 0.0:
		if _count(Kind.POLICE) < CARS_PER_STAR[stars]:
			_send(Kind.POLICE)
		elif stars >= 4 and _count(Kind.FIRE) < 1:
			_send(Kind.FIRE)
		elif stars >= 5 and _count(Kind.SWAT) < 1:
			_send(Kind.SWAT)
	for i in range(units.size() - 1, -1, -1):
		var u := units[i]
		var c := u.car
		if c.gone:
			units.remove_at(i)
			continue
		_dress(u)
		_signal(u, not u.leaving)
		if u.leaving:
			if c.pos.distance_to(cat) > LEAVE_DISTANCE:
				_traffic.retire_unit(c)
			continue
		if c.parked:
			if not u.deployed and c.speed <= 0.05:
				_deploy(u, cat)
			if c.pos.distance_to(cat) > AWAY_RESUME:
				u.away += delta
				if u.away > AWAY_SECONDS:
					# She got away: after her again (its people stay where they got out).
					u.away = 0.0
					c.parked = false
					c.pursuit = true
			else:
				u.away = 0.0
	if _calm:
		# Everyone who got out goes home once she is not looking.
		for i in range(officers.size() - 1, -1, -1):
			var id := officers[i]
			var p: People.Person = null
			if id >= 0 and id < _people.people.size():
				p = _people.people[id]
			if p == null or p.state == People.State.GONE:
				officers.remove_at(i)
			elif not p.active or p.pos.distance_to(cat) > 35.0:
				_people.retire(id)
				officers.remove_at(i)


## True when a unit on duty or one of its people is close enough to see her.
func _sees(cat: Vector3) -> bool:
	for u in units:
		if not u.car.gone and not u.leaving and u.car.pos.distance_to(cat) < 50.0:
			return true
	for id in officers:
		if id >= 0 and id < _people.people.size():
			var p := _people.people[id]
			if p.state != People.State.GONE and p.pos.distance_to(cat) < 40.0:
				return true
	return false


func _send(kind: int) -> void:
	var vname: StringName = [&"police_sedan", &"fire_truck", &"postvan"][kind]
	var vehicles := _dressing.vehicles if _dressing != null else null
	if vehicles != null and not vehicles.has_vehicle(vname):
		vname = &"police_sedan"
	var c := _traffic.dispatch(vname, _swat_paint if kind == Kind.SWAT else null)
	var u := Unit.new()
	u.car = c
	u.kind = kind
	units.append(u)
	dispatched += 1
	_wait = DISPATCH_EVERY


func _on_stars(s: int) -> void:
	_calm = s == 0
	if s == 0:
		for u in units:
			_leave(u)


## Drives off as ordinary traffic, lights and siren off.
func _leave(u: Unit) -> void:
	if u.leaving or u.car.gone:
		return
	u.leaving = true
	u.car.pursuit = false
	u.car.parked = false
	u.car.cruise = Traffic.CRUISE


## The unit stopped near her: it turns across its lane and lets its people out; from three stars a police
## car also puts barriers across the road ahead of it.
func _deploy(u: Unit, cat: Vector3) -> void:
	u.deployed = true
	arrived += 1
	var c := u.car
	var heading := Vector3(c.dir, 0.0, 0.0) if c.axis == 0 else Vector3(0.0, 0.0, c.dir)
	var side := Vector3(heading.z, 0.0, -heading.x)
	c.yaw += 0.55 if _rng.randf() < 0.5 else -0.55
	var figures: Array = FIGURES[u.kind]
	for i in figures.size():
		if _alive_officers() >= MAX_OFFICERS:
			break
		var s := -1.0 if i % 2 == 0 else 1.0
		var at := c.pos + side * s * (1.9 + 0.5 * floorf(i / 2.0)) + heading * _rng.randf_range(-1.0, 1.0)
		var to_cat := cat - at
		var id := _people.add_officer(at, atan2(to_cat.x, to_cat.z), figures[i], 2 if u.kind == Kind.FIRE else 1)
		if id >= 0:
			officers.append(id)
	if u.kind == Kind.POLICE and _chaos.stars >= 3 and blocks < MAX_BLOCKS and _dressing != null:
		blocks += 1
		var base := c.pos + heading * 7.5
		for k: float in [-1.0, 0.0, 1.0]:
			_dressing.add_prop(&"barrier", base + side * k * 2.4, atan2(heading.x, heading.z))


func _alive_officers() -> int:
	var n := 0
	for id in officers:
		if id >= 0 and id < _people.people.size() and _people.people[id].state != People.State.GONE:
			n += 1
	return n


func _on_crashed(car: Traffic.Car) -> void:
	for u in units:
		if u.car == car:
			_chaos.add(Chaos.UNIT_HEAT)
			return


## A rewind: every unit off the roads and everyone home, at once.
func dismiss_all() -> void:
	for u in units:
		_traffic.retire_unit(u.car)
	units.clear()
	for id in officers:
		_people.retire(id)
	officers.clear()
	_calm = true


## Lights on the roof and a siren, once the car has a body near her.
func _dress(u: Unit) -> void:
	var c := u.car
	if c.node == null or (u.lights != null and is_instance_valid(u.lights)):
		return
	u.lights = Node3D.new()
	u.lights.name = "Lights"
	u.lights.position = Vector3(0.0, c.height + 0.04, -c.length * 0.08)
	c.node.add_child(u.lights)
	u.lamps.clear()
	for s: float in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		lamp.mesh = _lamp_mesh
		lamp.position = Vector3(s * 0.24, 0.06, 0.0)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		u.lights.add_child(lamp)
		u.lamps.append(lamp)
	u.light = OmniLight3D.new()
	u.light.position = Vector3(0.0, 0.5, 0.0)
	u.light.omni_range = 12.0
	u.light.shadow_enabled = false
	u.lights.add_child(u.light)
	u.siren = AudioStreamPlayer3D.new()
	u.siren.stream = _siren_wav
	u.siren.unit_size = 22.0
	u.siren.max_distance = 320.0
	u.siren.volume_db = -7.0
	u.siren.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	c.node.add_child(u.siren)


## The lights flash red and blue (red and white on the fire engine) and the siren wails while it is on
## duty; both are off once it leaves.
func _signal(u: Unit, on: bool) -> void:
	if u.lights == null or not is_instance_valid(u.lights):
		return
	var phase := fmod(_t * 3.2 + u.car.id * 0.37, 1.0) < 0.5
	var second := "white" if u.kind == Kind.FIRE else "blue"
	for i in u.lamps.size():
		var lit := on and (phase == (i == 0))
		u.lamps[i].material_override = (_lamp_on["red"] if i == 0 else _lamp_on[second]) if lit else _lamp_off
	u.light.light_energy = 3.0 if on else 0.0
	u.light.light_color = Color(1.0, 0.15, 0.1) if phase else (Color(0.2, 0.4, 1.0) if second == "blue" else Color(1.0, 0.95, 0.85))
	if u.siren != null and is_instance_valid(u.siren):
		if on and u.car.near and not u.siren.playing:
			u.siren.play(_rng.randf() * 2.0)
		elif (not on or not u.car.near) and u.siren.playing:
			u.siren.stop()


## A wailing siren, 2.4 s that loop: a tone sweeping between 700 and 1300 Hz with a little overtone.
static func _make_siren() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 2.4
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 700.0 + 600.0 * (0.5 - 0.5 * cos(TAU * t / seconds))
		phase += TAU * f / rate
		var v := sin(phase) * 0.7 + sin(phase * 2.0) * 0.2 + (0.1 if fmod(phase, TAU) < PI else -0.1)
		data.encode_s16(i * 2, int(clampf(v * 0.5, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s
