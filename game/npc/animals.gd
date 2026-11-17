class_name Animals
extends Node3D
## The animals of the Table: flocks of pigeons and the dogs of the park. All of them are CAT-PROOF:
## their bodies are in group "protected" on Layers.PROTECTED, so nothing can hurt them, and whatever
## is aimed at them gets the shield for an answer.
##
## Pigeons stand about in flocks. When Trophe comes close, when something explodes nearby, when she
## meows or when one of them is shot at, the flock goes up, circles above its square and comes back
## down once the coast is clear. Flight is drawn, not simulated: every bird follows its own ring
## around the home of its flock. The model only has a standing pose, so in the air it is pitched
## forward and gets two flat wings that beat.
##
## A dog sits where it was put and gets up to watch Trophe when she is near. A blast nearby and it
## plays dead; a meow and it rolls over; a swat and it shakes itself (the shield has answered already).

const PIGEON := "res://assets/models/animals/pigeon/Pigeon.glb"
const DOG := "res://assets/models/animals/shiba/shiba.glb"
const PIGEON_SCALE := 0.4
const DOG_SCALE := 0.006
const ACTIVE_RADIUS := 75.0     ## Flocks and dogs farther from Trophe than this are hidden and still.
const SCARE_RADIUS := 7.5
const BLAST_SCARE := 32.0
const MEOW_SCARE := 16.0
const CLEAR_RADIUS := 13.0      ## A flock lands again when Trophe is at least this far from its home...
const AIR_MIN := 7.0            ## ...and it has been up for this many seconds.
const CLIMB_SECONDS := 1.9
const LAND_SECONDS := 2.6
const FLIGHT_PITCH := 1.2       ## Radians the standing model is tipped forward in the air.
const DOG_NOTICE := 7.0
const DOG_SIT := &"0|sitting_0"
const DOG_STAND := &"0|standing_0"
const DOG_SHAKE := &"0|shake_0"
const DOG_ROLL := &"0|rollover_0"
const DOG_DEAD := &"0|play_dead_0"

enum Flight { GROUND, UP, CIRCLE, DOWN }


class Bird:
	var root: Node3D
	var model: Node3D
	var anim: AnimationPlayer
	var wings: Array[MeshInstance3D] = []
	var body: StaticBody3D
	var spot := Vector3.ZERO     # where it stands
	var yaw := 0.0
	var ring := 12.0             # radius of its circle in the air
	var height := 11.0
	var phase := 0.0
	var speed := 0.6             # radians per second around the ring
	var delay := 0.0             # seconds it waits before it follows the flock
	var flap := 0.0
	var from := Vector3.ZERO     # where the current climb or descent started
	var pos := Vector3.ZERO


class Flock:
	var home := Vector3.ZERO
	var birds: Array[Bird] = []
	var state := Flight.GROUND
	var t := 0.0        # seconds in the current state
	var air := 0.0      # seconds since take-off
	var active := false


class Dog:
	var root: Node3D
	var anim: AnimationPlayer
	var clip: StringName = &""
	var busy := 0.0     # seconds the current trick still runs
	var yaw := 0.0
	var pos := Vector3.ZERO
	var active := false


var flocks: Array[Flock] = []
var dogs: Array[Dog] = []
var takeoffs := 0
var landings := 0
var tricks := {}         # dog clip -> times played as a trick

var _rng := RandomNumberGenerator.new()
var _pigeon_scene: PackedScene
var _dog_scene: PackedScene
var _wing_mesh: ArrayMesh
var _bird_shape := SphereShape3D.new()
var _dog_shape := BoxShape3D.new()
var _scan_in := 0.0


static func model_paths() -> PackedStringArray:
	return PackedStringArray([PIGEON, DOG])


func _ready() -> void:
	_rng.seed = 2917
	_pigeon_scene = load(PIGEON) as PackedScene
	_dog_scene = load(DOG) as PackedScene
	_bird_shape.radius = 0.11
	_dog_shape.size = Vector3(0.3, 0.45, 0.6)
	# One flat wing along +X, in the plane of the bird's back.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline: Array[Vector3] = [Vector3(0.0, 0.0, 0.06), Vector3(0.14, 0.0, 0.07), Vector3(0.3, 0.0, 0.0), Vector3(0.16, 0.0, -0.07), Vector3(0.0, 0.0, -0.06)]
	for i: int in [0, 1, 2, 0, 2, 3, 0, 3, 4]:
		st.set_normal(Vector3.UP)
		st.add_vertex(outline[i])
	_wing_mesh = st.commit()
	var feather := StandardMaterial3D.new()
	feather.albedo_color = Color(0.56, 0.55, 0.58)
	feather.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # a flat card lit from above turns sky blue
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wing_mesh.surface_set_material(0, feather)
	DamageRouter.blast.connect(_on_blast)
	DamageRouter.protected_hit.connect(_on_protected_hit)


func pigeon_count() -> int:
	var n := 0
	for f in flocks:
		n += f.birds.size()
	return n


func dog_count() -> int:
	return dogs.size()


## Flocks on the squares, courts and greens of the city and in the Park, one where Trophe lands, and a
## dog at every picnic spot and on every green.
func populate(city: CityLayout, landing: Vector3) -> void:
	add_flock(landing, 9)
	for plaza in city.plazas:
		add_flock(plaza + Vector3(9.0, 0.0, 8.0), _rng.randi_range(6, 9))
	for court in city.courts:
		add_flock(court + Vector3(-12.0, 0.0, 5.0), _rng.randi_range(6, 8))
	for green in city.greens:
		add_flock(green + Vector3(4.0, 0.0, -3.5), _rng.randi_range(5, 8))
		add_dog(green + Vector3(-3.5, 0.0, 3.0), _rng.randf() * TAU)
	for block in CityLayout.block_centres(CityLayout.District.PARK):
		add_flock(block + Vector3(8.0, 0.0, 14.0), _rng.randi_range(7, 10))
		add_flock(block + Vector3(-6.0, 0.0, -38.0), _rng.randi_range(5, 8))
		add_dog(block + Vector3(25.0, 0.0, 41.0), PI)


func add_flock(home: Vector3, count: int) -> void:
	var f := Flock.new()
	f.home = Vector3(home.x, _ground(home.x, home.z), home.z)
	var turn := 1.0 if _rng.randf() < 0.5 else -1.0
	for i in count:
		var b := Bird.new()
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 2.4
		b.spot = Vector3(f.home.x + cos(a) * r, 0.0, f.home.z + sin(a) * r)
		b.spot.y = _ground(b.spot.x, b.spot.z) + 0.01
		b.yaw = _rng.randf() * TAU
		b.ring = _rng.randf_range(9.0, 16.0)
		b.height = _rng.randf_range(9.0, 15.0)
		b.phase = _rng.randf() * TAU
		b.speed = _rng.randf_range(0.5, 0.72) * turn
		b.delay = _rng.randf_range(0.0, 0.45)
		b.flap = _rng.randf() * TAU
		b.pos = b.spot
		_build_bird(b, flocks.size())
		f.birds.append(b)
	flocks.append(f)


func add_dog(at: Vector3, yaw: float) -> void:
	if _dog_scene == null:
		return
	var d := Dog.new()
	d.pos = Vector3(at.x, _ground(at.x, at.z) + 0.01, at.z)
	d.yaw = yaw
	d.root = Node3D.new()
	d.root.name = "Dog%d" % dogs.size()
	d.root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(d.root)
	var model := _dog_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * DOG_SCALE
	d.root.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		d.anim = players[0]
		for clip: StringName in [DOG_SIT, DOG_STAND]:
			if d.anim.has_animation(clip):
				d.anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var body := StaticBody3D.new()
	body.collision_layer = Layers.PROTECTED
	body.collision_mask = 0
	body.add_to_group(&"protected")
	body.set_meta(&"dog", dogs.size())
	var shape := CollisionShape3D.new()
	shape.shape = _dog_shape
	shape.position = Vector3(0.0, 0.23, 0.0)
	body.add_child(shape)
	d.root.add_child(body)
	d.root.transform = Transform3D(Basis(Vector3.UP, yaw), d.pos)
	d.root.visible = false
	dogs.append(d)


## Everything with wings within `radius` of a point goes up.
func scare(at: Vector3, radius: float) -> void:
	for f in flocks:
		if f.active and f.home.distance_to(at) < radius:
			_take_off(f)


func _build_bird(b: Bird, flock_index: int) -> void:
	b.root = Node3D.new()
	b.root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(b.root)
	if _pigeon_scene != null:
		b.model = _pigeon_scene.instantiate() as Node3D
		b.model.scale = Vector3.ONE * PIGEON_SCALE * _rng.randf_range(0.92, 1.1)
		b.root.add_child(b.model)
		var players := b.model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			b.anim = players[0]
			var clips := b.anim.get_animation_list()
			if not clips.is_empty():
				b.anim.get_animation(clips[0]).loop_mode = Animation.LOOP_LINEAR
	for sgn: float in [1.0, -1.0]:
		var wing := MeshInstance3D.new()
		wing.mesh = _wing_mesh
		wing.position = Vector3(0.025 * sgn, 0.035, 0.05)   # at the shoulders of the bird as it flies
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wing.visible = false
		b.root.add_child(wing)
		b.wings.append(wing)
	b.body = StaticBody3D.new()
	b.body.collision_layer = Layers.PROTECTED
	b.body.collision_mask = 0
	b.body.add_to_group(&"protected")
	b.body.set_meta(&"flock", flock_index)
	var shape := CollisionShape3D.new()
	shape.shape = _bird_shape
	shape.position = Vector3(0.0, 0.1, 0.0)
	b.body.add_child(shape)
	b.root.add_child(b.body)
	b.root.transform = Transform3D(Basis(Vector3.UP, b.yaw), b.spot)
	b.root.visible = false


func _process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var cat_at := player.global_position
	_scan_in -= delta
	if _scan_in <= 0.0:
		_scan_in = 0.4
		for f in flocks:
			var near := f.home.distance_to(cat_at) < ACTIVE_RADIUS
			if near != f.active:
				_set_flock_active(f, near)
		for d in dogs:
			var near := d.pos.distance_to(cat_at) < ACTIVE_RADIUS
			if near != d.active:
				d.active = near
				d.root.visible = near
				if d.anim != null:
					if near:
						_dog_play(d, DOG_SIT)
					else:
						d.anim.pause()
	for f in flocks:
		if not f.active:
			continue
		var flat := Vector2(cat_at.x - f.home.x, cat_at.z - f.home.z).length()
		match f.state:
			Flight.GROUND:
				if flat < SCARE_RADIUS:
					_take_off(f)
			_:
				_fly(f, delta, flat)
	for d in dogs:
		if d.active:
			_tick_dog(d, delta, cat_at)


func _set_flock_active(f: Flock, on: bool) -> void:
	f.active = on
	if not on and f.state != Flight.GROUND:
		_settle(f)
	for b in f.birds:
		b.root.visible = on
		if b.anim != null:
			if on:
				var clips := b.anim.get_animation_list()
				if not clips.is_empty():
					b.anim.play(clips[0], -1.0, _rng.randf_range(0.8, 1.3))
					b.anim.seek(_rng.randf() * b.anim.current_animation_length, true)
			else:
				b.anim.pause()


func _take_off(f: Flock) -> void:
	if f.state == Flight.UP or f.state == Flight.CIRCLE:
		return
	if f.state == Flight.GROUND:
		f.air = 0.0
		takeoffs += 1
		Audio.play_3d(&"pigeon_flap", f.home + Vector3.UP * 0.5, 1.0)
		var fx := WorldFX.instance
		if fx != null:
			fx.puff(f.home + Vector3.UP * 0.2, Vector3.UP * 1.0, Color(0.92, 0.92, 0.94, 0.22), 0.7, 0.4, 1.1)
	f.state = Flight.UP
	f.t = 0.0
	for b in f.birds:
		b.from = b.pos
		b.body.collision_layer = 0
		if b.anim != null:
			b.anim.pause()
		for w in b.wings:
			w.visible = true


func _fly(f: Flock, delta: float, cat_distance: float) -> void:
	f.t += delta
	f.air += delta
	var done := true
	for b in f.birds:
		var prev := b.pos
		var tip := 1.0
		match f.state:
			Flight.UP:
				var k := clampf((f.t - b.delay) / CLIMB_SECONDS, 0.0, 1.0)
				if k < 1.0:
					done = false
				b.pos = b.from.lerp(_ring_point(f, b), k * k * (3.0 - 2.0 * k))
				tip = minf(k * 5.0, 1.0)
			Flight.CIRCLE:
				b.pos = _ring_point(f, b)
			Flight.DOWN:
				var k := clampf((f.t - b.delay) / LAND_SECONDS, 0.0, 1.0)
				if k < 1.0:
					done = false
				b.pos = b.from.lerp(b.spot, k * k * (3.0 - 2.0 * k))
				tip = 1.0 - smoothstep(0.85, 1.0, k)
		var v := b.pos - prev
		var turn_to := b.root.global_basis
		if v.length_squared() > 1.0e-8 and absf(v.normalized().y) < 0.97:
			turn_to = Basis.looking_at(v, Vector3.UP, true)
		b.root.global_transform = Transform3D(turn_to, b.pos)
		if b.model != null:
			b.model.rotation.x = FLIGHT_PITCH * tip
			b.model.position = Vector3(0.0, -0.04, -0.07) * tip
		b.flap += delta * 46.0
		var beat := sin(b.flap) * 1.0 + 0.15
		b.wings[0].rotation.z = beat
		b.wings[1].rotation.z = PI - beat
	match f.state:
		Flight.UP:
			if done:
				f.state = Flight.CIRCLE
		Flight.CIRCLE:
			if f.air > AIR_MIN and cat_distance > CLEAR_RADIUS:
				f.state = Flight.DOWN
				f.t = 0.0
				for b in f.birds:
					b.from = b.pos
		Flight.DOWN:
			if cat_distance < SCARE_RADIUS:
				_take_off(f)
			elif done:
				_settle(f)
				landings += 1


func _ring_point(f: Flock, b: Bird) -> Vector3:
	var a := b.phase + b.speed * f.air
	return f.home + Vector3(cos(a) * b.ring, b.height + sin(f.air * 0.8 + b.phase) * 1.0, sin(a) * b.ring)


func _settle(f: Flock) -> void:
	f.state = Flight.GROUND
	f.t = 0.0
	for b in f.birds:
		b.pos = b.spot
		b.root.global_transform = Transform3D(Basis(Vector3.UP, b.yaw), b.spot)
		b.body.collision_layer = Layers.PROTECTED
		if b.model != null:
			b.model.rotation.x = 0.0
			b.model.position = Vector3.ZERO
		if b.anim != null and f.active:
			b.anim.play()
		for w in b.wings:
			w.visible = false


func _tick_dog(d: Dog, delta: float, cat_at: Vector3) -> void:
	var to := cat_at - d.pos
	to.y = 0.0
	var near := to.length() < DOG_NOTICE
	if d.busy > 0.0:
		d.busy -= delta
		if d.busy <= 0.0:
			_dog_play(d, DOG_STAND if near else DOG_SIT)
		return
	var want := DOG_STAND if near else DOG_SIT
	if d.clip != want:
		_dog_play(d, want)
	if near and to.length() > 0.4:
		d.yaw = lerp_angle(d.yaw, atan2(to.x, to.z), minf(delta * 3.0, 1.0))
		d.root.rotation.y = d.yaw


func _dog_play(d: Dog, clip: StringName) -> void:
	d.clip = clip
	if d.anim != null and d.anim.has_animation(clip):
		d.anim.play(clip, 0.35)


func _trick(d: Dog, clip: StringName, seconds: float) -> void:
	if not d.active or (d.busy > 0.0 and d.clip == clip):
		return
	d.busy = seconds
	tricks[clip] = int(tricks.get(clip, 0)) + 1
	_dog_play(d, clip)


func _on_blast(hit: DamageHit) -> void:
	scare(hit.position, BLAST_SCARE + hit.radius)
	for d in dogs:
		if d.pos.distance_to(hit.position) < 26.0 + hit.radius:
			_trick(d, DOG_DEAD, 8.0)


## Shot at or swatted: the shield has answered; a pigeon takes its flock up, a dog shakes itself.
func _on_protected_hit(_hit: DamageHit, target: Object) -> void:
	var node := target as Node
	if node == null:
		return
	if node.has_meta(&"flock"):
		var index := int(node.get_meta(&"flock"))
		if index >= 0 and index < flocks.size():
			_take_off(flocks[index])
	elif node.has_meta(&"dog"):
		var index := int(node.get_meta(&"dog"))
		if index >= 0 and index < dogs.size():
			_trick(dogs[index], DOG_SHAKE, 4.0)


## A meow sends the pigeons up and makes a dog roll over.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M and Game.player != null:
		var at := Game.player.global_position
		scare(at, MEOW_SCARE)
		for d in dogs:
			if d.pos.distance_to(at) < 10.0:
				_trick(d, DOG_ROLL, 7.5)


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0
