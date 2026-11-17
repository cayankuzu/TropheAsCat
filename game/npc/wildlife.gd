class_name Wildlife
extends Node3D
## The wild and the farm animals of the Table (2026-11-17), Quaternius' Ultimate Animated Animals: deer and
## stags at the edge of the groves of the outer Park and on the hills, a fox in every park, a wolf pack far
## out on the hills, horses, cows, a bull, donkeys and alpacas in the paddock of the petting farm, huskies
## and shibas in the back gardens of the Suburbs.
##
## Like every animal of the Table they are CAT-PROOF: their bodies are on Layers.PROTECTED in group
## "protected", so nothing hurts them and whatever is aimed at them gets the shield for an answer. They
## graze, idle and wander around their home. When Trophe comes close, when something blows up near them or
## when she swats one, the wild ones gallop off and the farm animals trot to the far side of the paddock;
## the dogs come running at her and bark, which does nothing at all.
##
## Only the animals near Trophe are drawn and moved.

const ROOT := "res://assets/models/animals/wild/"
## kind: [model, height (m), walk and run speed (m/s), how close Trophe may come (m), what it does then]
const SPECIES := {
	&"deer": ["Deer", 1.45, 1.2, 8.5, 16.0, &"flee"],
	&"stag": ["Stag", 2.0, 1.2, 8.0, 18.0, &"flee"],
	&"fox": ["Fox", 0.55, 1.1, 6.5, 11.0, &"flee"],
	&"wolf": ["Wolf", 0.85, 1.3, 7.5, 14.0, &"flee"],
	&"horse": ["Horse", 1.85, 1.4, 5.5, 5.0, &"shy"],
	&"horse_white": ["Horse_White", 1.85, 1.4, 5.5, 5.0, &"shy"],
	&"cow": ["Cow", 1.45, 0.9, 3.2, 4.0, &"shy"],
	&"bull": ["Bull", 1.6, 0.9, 4.0, 5.0, &"shy"],
	&"donkey": ["Donkey", 1.3, 1.0, 3.8, 4.5, &"shy"],
	&"alpaca": ["Alpaca", 1.75, 1.0, 4.2, 4.5, &"shy"],
	&"husky": ["Husky", 0.62, 1.3, 6.0, 9.0, &"chase"],
	&"shiba": ["ShibaInu", 0.48, 1.2, 5.5, 9.0, &"chase"],
}
const ACTIVE_RADIUS := 95.0
const LOOPS: Array[StringName] = [&"Idle", &"Idle_2", &"Idle_2_HeadLow", &"Eating", &"Walk", &"Gallop"]
const IDLES: Array[StringName] = [&"Idle", &"Idle_2", &"Idle_2_HeadLow"]
const BLAST_SCARE := 40.0
const MEOW_SCARE := 18.0
## The hills between the city and the rim where the herds live, as (x, z) homes.
const HILL_HERDS: Array[Vector2] = [Vector2(448.0, -150.0), Vector2(-448.0, 250.0), Vector2(160.0, 452.0), Vector2(-300.0, -452.0),
	Vector2(452.0, 330.0), Vector2(-452.0, -60.0), Vector2(320.0, -452.0)]
const WOLF_DEN := Vector2(-440.0, -400.0)

enum Act { IDLE, GRAZE, WALK, RUN, REACT }


class Beast:
	var kind: StringName
	var root: Node3D
	var anim: AnimationPlayer
	var body: AnimatableBody3D
	var home := Vector3.ZERO
	var area := Rect2()           # where it may go (x, z)
	var pos := Vector3.ZERO
	var yaw := 0.0
	var act := Act.IDLE
	var timer := 0.0
	var target := Vector3.ZERO
	var clip: StringName = &""
	var active := false
	var walk := 1.2
	var run := 8.0
	var shy := 10.0
	var nature: StringName = &"flee"


var beasts: Array[Beast] = []
var flights := 0        ## times an animal ran from Trophe or a blast
var chases := 0         ## times a dog came running at her

var _scenes := {}       # kind -> PackedScene
var _scale := {}        # kind -> model scale
var _shapes := {}       # kind -> BoxShape3D (in the scaled model's space)
var _rng := RandomNumberGenerator.new()
var _scan_in := 0.0


static func model_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for kind: StringName in SPECIES:
		out.append(ROOT + String(SPECIES[kind][0]) + ".gltf")
	return out


## The paddock of the petting farm, in the outer Park (x, z).
static func paddock_rect() -> Rect2:
	var c := CityLayout.block_centre(Vector2i(-3, 1))
	return Rect2(c.x + 8.0, c.z - 50.0, 42.0, 24.0)


func _ready() -> void:
	_rng.seed = 5150
	DamageRouter.blast.connect(_on_blast)
	DamageRouter.protected_hit.connect(_on_protected_hit)


func count() -> int:
	return beasts.size()


## Herds in the outer Park and on the hills, a fox in every park block, the wolves, the paddock and the
## dogs of the Suburbs.
func populate(city: CityLayout) -> void:
	var parks := CityLayout.block_centres(CityLayout.District.PARK)
	for i in parks.size():
		var block := parks[i]
		add_animal(&"fox", block + Vector3(-25.0, 0.0, -23.0), Rect2(block.x - 42.0, block.z - 40.0, 34.0, 34.0))
		if i >= 4:   # the outer Park: deer at the edge of the northern grove
			var home := block + Vector3(-34.0, 0.0, 30.0)
			var area := Rect2(home.x - 16.0, home.z - 18.0, 32.0, 36.0)
			for k in _rng.randi_range(2, 4):
				add_animal(&"deer", home + _jitter(5.0), area)
			if _rng.randf() < 0.6:
				add_animal(&"stag", home + _jitter(5.0), area)
	for h in HILL_HERDS:
		var home := Vector3(h.x, 0.0, h.y)
		var area := Rect2(h.x - 26.0, h.y - 26.0, 52.0, 52.0)
		for k in _rng.randi_range(3, 5):
			add_animal(&"deer", home + _jitter(8.0), area)
		add_animal(&"stag", home + _jitter(8.0), area)
	for k in 3:
		add_animal(&"wolf", Vector3(WOLF_DEN.x, 0.0, WOLF_DEN.y) + _jitter(6.0), Rect2(WOLF_DEN.x - 24.0, WOLF_DEN.y - 24.0, 48.0, 48.0))
	var pen := paddock_rect().grow(-2.0)
	for kind: StringName in [&"horse", &"horse_white", &"cow", &"cow", &"cow", &"bull", &"donkey", &"donkey", &"alpaca", &"alpaca"]:
		var at := Vector3(_rng.randf_range(pen.position.x, pen.end.x), 0.0, _rng.randf_range(pen.position.y, pen.end.y))
		add_animal(kind, at, pen)
	for i in city.backyards.size():
		if i % 4 != 1:
			continue
		var spot: Vector3 = city.backyards[i]["pos"]
		add_animal(&"husky" if _rng.randf() < 0.5 else &"shiba", spot + _jitter(2.0), Rect2(spot.x - 8.0, spot.z - 6.0, 16.0, 12.0))


func add_animal(kind: StringName, at: Vector3, area: Rect2) -> void:
	var scene := _scene(kind)
	if scene == null:
		return
	var spec: Array = SPECIES[kind]
	var b := Beast.new()
	b.kind = kind
	b.home = Vector3(at.x, _ground(at.x, at.z), at.z)
	b.pos = b.home
	b.area = area
	b.yaw = _rng.randf() * TAU
	b.walk = float(spec[2]) * _rng.randf_range(0.9, 1.1)
	b.run = float(spec[3]) * _rng.randf_range(0.9, 1.1)
	b.shy = float(spec[4])
	b.nature = spec[5]
	b.timer = _rng.randf_range(0.0, 6.0)
	b.act = Act.GRAZE if _rng.randf() < 0.5 else Act.IDLE
	b.root = Node3D.new()
	b.root.name = "%s%d" % [String(kind).capitalize().replace(" ", ""), beasts.size()]
	b.root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(b.root)
	var model := scene.instantiate() as Node3D
	model.scale = Vector3.ONE * float(_scale[kind])
	b.root.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		b.anim = players[0] as AnimationPlayer
	b.body = AnimatableBody3D.new()
	b.body.sync_to_physics = false
	b.body.collision_layer = Layers.PROTECTED
	b.body.collision_mask = 0
	b.body.add_to_group(&"protected")
	b.body.set_meta(&"beast", beasts.size())
	var shape := CollisionShape3D.new()
	var box: BoxShape3D = _shapes[kind]
	shape.shape = box
	shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	b.body.add_child(shape)
	b.root.add_child(b.body)
	b.root.visible = false
	_sync(b)
	beasts.append(b)


## The model of a kind, loaded once: its clips that loop, the scale that gives it its height, its box.
func _scene(kind: StringName) -> PackedScene:
	if _scenes.has(kind):
		return _scenes[kind]
	var spec: Array = SPECIES[kind]
	var scene := load(ROOT + String(spec[0]) + ".gltf") as PackedScene
	_scenes[kind] = scene
	if scene == null:
		return null
	var tmp := scene.instantiate() as Node3D
	var box := BreakableProp.bounds_of(tmp, tmp)
	var k := float(spec[1]) / maxf(box.size.y, 0.01)
	_scale[kind] = k
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, box.size.y * 0.8, box.size.z) * k
	_shapes[kind] = shape
	var players := tmp.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var lib := (players[0] as AnimationPlayer).get_animation_library(&"")
		for clip in LOOPS:
			if lib.has_animation(clip):
				lib.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	tmp.free()
	return scene


func _process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var cat_at := player.global_position
	_scan_in -= delta
	if _scan_in <= 0.0:
		_scan_in = 0.5
		for b in beasts:
			var near := b.pos.distance_to(cat_at) < ACTIVE_RADIUS
			if near != b.active:
				b.active = near
				b.root.visible = near
				if b.anim != null:
					if near:
						b.clip = &""
					else:
						b.anim.pause()
	for b in beasts:
		if b.active:
			_tick(b, delta, cat_at)


func _tick(b: Beast, delta: float, cat_at: Vector3) -> void:
	var to_cat := cat_at - b.pos
	to_cat.y = 0.0
	var d := to_cat.length()
	if d < b.shy and b.act != Act.RUN and b.act != Act.REACT:
		_startle(b, cat_at)
	b.timer -= delta
	match b.act:
		Act.IDLE, Act.GRAZE:
			if b.act == Act.GRAZE:
				_play(b, &"Eating")
			elif b.clip == &"" or not IDLES.has(b.clip):
				_play(b, IDLES[_rng.randi_range(0, IDLES.size() - 1)])
			if b.nature == &"chase" and d < b.shy * 1.6:
				b.yaw = lerp_angle(b.yaw, atan2(to_cat.x, to_cat.z), minf(delta * 4.0, 1.0))
			if b.timer <= 0.0:
				_next(b)
		Act.REACT:
			if b.timer <= 0.0:
				_startle(b, cat_at)
		Act.WALK, Act.RUN:
			var run := b.act == Act.RUN
			if run and b.nature == &"chase":
				# Runs at her, but not out of the street it lives in.
				var at := cat_at - to_cat.normalized() * 1.6 if d > 0.1 else b.pos
				var reach := b.area.grow(14.0)
				b.target = Vector3(clampf(at.x, reach.position.x, reach.end.x), at.y, clampf(at.z, reach.position.y, reach.end.y))
			var dir := b.target - b.pos
			dir.y = 0.0
			var dist := dir.length()
			_play(b, &"Gallop" if run else &"Walk", (b.run / 8.0 if run else b.walk / 1.2))
			if dist < 0.4 or b.timer <= 0.0:
				if run and b.nature == &"chase" and dist < 0.6:
					_play(b, &"Attack")   # barks at her (it does nothing; she is the Owner's cat)
					b.act = Act.REACT
					b.timer = 1.6
				else:
					b.act = Act.IDLE
					b.timer = _rng.randf_range(2.0, 5.0)
					b.clip = &""
			else:
				var speed := b.run if run else b.walk
				b.pos += dir / dist * minf(speed * delta, dist)
				b.pos.y = _ground(b.pos.x, b.pos.z)
				b.yaw = lerp_angle(b.yaw, atan2(dir.x, dir.z), minf(delta * (7.0 if run else 3.0), 1.0))
	_sync(b)


## What it does next on its own: graze, stand about, or wander to a spot near its home.
func _next(b: Beast) -> void:
	var roll := _rng.randf()
	if roll < 0.4:
		b.act = Act.GRAZE
		b.timer = _rng.randf_range(5.0, 12.0)
	elif roll < 0.7:
		b.act = Act.IDLE
		b.timer = _rng.randf_range(3.0, 8.0)
		b.clip = &""
	else:
		b.act = Act.WALK
		b.timer = 20.0
		b.target = _inside(b, b.home + _jitter(12.0))


## Trophe (or a bang) too close: the wild ones gallop away, the farm animals trot off within their
## paddock, the dogs come running at her.
func _startle(b: Beast, from: Vector3) -> void:
	var away := b.pos - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3(_rng.randf() - 0.5, 0.0, _rng.randf() - 0.5).normalized()
	b.act = Act.RUN
	match b.nature:
		&"chase":
			chases += 1
			b.timer = 5.0
		&"shy":
			flights += 1
			b.timer = 4.0
			b.target = _inside(b, b.pos + away * _rng.randf_range(8.0, 14.0))
		_:
			flights += 1
			b.timer = 7.0
			b.target = _inside(b, b.pos + away.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * _rng.randf_range(28.0, 40.0))


func _inside(b: Beast, p: Vector3) -> Vector3:
	var x := clampf(p.x, b.area.position.x, b.area.end.x)
	var z := clampf(p.z, b.area.position.y, b.area.end.y)
	return Vector3(x, _ground(x, z), z)


func _jitter(r: float) -> Vector3:
	return Vector3(_rng.randf_range(-r, r), 0.0, _rng.randf_range(-r, r))


func _play(b: Beast, clip: StringName, rate: float = 1.0) -> void:
	if b.anim == null:
		return
	if b.clip != clip:
		if not b.anim.has_animation(clip):
			return
		b.clip = clip
		b.anim.play(clip, 0.3)
		if not LOOPS.has(clip):
			b.anim.seek(0.0, true)
	b.anim.speed_scale = rate


func _sync(b: Beast) -> void:
	var xf := Transform3D(Basis(Vector3.UP, b.yaw), b.pos)
	b.root.global_transform = xf


## Everything within `radius` of a point is startled by it.
func scare(at: Vector3, radius: float) -> void:
	for b in beasts:
		if b.active and b.pos.distance_squared_to(at) < radius * radius:
			_startle(b, at)


func _on_blast(hit: DamageHit) -> void:
	scare(hit.position, BLAST_SCARE + hit.radius)


## Swatted or shot at: the shield has answered; it flinches, then does what it does.
func _on_protected_hit(_hit: DamageHit, target: Object) -> void:
	var node := target as Node
	if node == null or not node.has_meta(&"beast"):
		return
	var index := int(node.get_meta(&"beast"))
	if index < 0 or index >= beasts.size():
		return
	var b := beasts[index]
	b.act = Act.REACT
	b.timer = 0.7
	_play(b, &"Idle_HitReact1")


## A meow startles everything near her.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M and Game.player != null:
		scare(Game.player.global_position, MEOW_SCARE)


func _ground(x: float, z: float) -> float:
	if Game.terrain != null and Game.terrain.has_method(&"get_original_height"):
		return Game.terrain.call(&"get_original_height", x, z)
	return 0.0
