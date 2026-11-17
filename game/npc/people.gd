class_name People
extends Node3D
## The little people of the Table: painted porcelain figurines the Owner set out to make its city look
## lived in (2026-11-17: real people in real clothes, Quaternius' modular men and women under a glaze, a
## cast per district: suits downtown, overalls in the works, beachwear in the park, and now and then
## something odd from the Owner's toy box). They walk the sidewalk around their block, stop to idle or
## fiddle with something, sit on benches, wave and say "Nice kitty?" when Trophe comes close (the rude
## ones kick at her), run when something blows up or comes down near them, and shatter into porcelain
## when they are hit: shards, dust and a head that rolls away (and can be picked up and thrown).
##
## One node runs all of them. Only people near the player are drawn, animated and solid (a kinematic
## capsule on Layers.NPC registered with DamageRouter); the others just keep their place in time.

signal person_shattered(at: Vector3)
signal called_police(at: Vector3)   ## a witness got through to the police (Chaos adds heat)

const CAST_ROOT := "res://assets/models/humans/city/"
## [model, districts it lives in (CityLayout.District; none = anywhere), weight, rude]. The rude kick at
## the cat instead of waving.
const CAST := [
	["M_Suit", [1, 5], 24, false], ["W_Suit", [1, 5], 24, false], ["W_Formal", [1, 2, 5], 20, false],
	["M_Casual_2", [1, 2, 4, 5, 7], 32, false], ["W_Casual", [1, 2, 4, 5, 7], 32, false],
	["M_Casual_Hoodie", [2, 3, 4, 5, 6, 7], 28, true], ["W_Punk", [2, 4, 5], 12, true], ["M_Punk", [2, 3, 4], 12, true],
	["M_Worker", [3, 6], 32, false], ["W_Worker", [3, 6], 24, false], ["M_Farmer", [2, 3, 6, 7], 12, false],
	["M_Beach", [4, 5, 7], 16, false], ["W_Adventurer", [2, 4, 7], 12, false], ["M_Adventurer", [4, 7], 8, false],
	["W_Soldier", [3, 6], 4, true], ["M_Swat", [1, 3, 6], 4, true],
	# The odd ones: the Owner's toy box leaks into the city now and then.
	["M_King", [], 1, false], ["W_Witch", [], 1, true], ["W_Medieval", [], 1, false], ["M_Spacesuit", [], 1, false], ["W_SciFi", [], 1, false],
]
## Clips that loop (the packs' clips come without a loop flag).
const LOOPS: Array[StringName] = [&"Idle", &"Idle_Neutral", &"Walk", &"Run", &"Run_Back", &"Run_Left", &"Run_Right", &"Idle_Gun", &"Idle_Sword", &"Interact", &"Wave"]
## Skin tones (sRGB) of the glaze variants 1..3; variant 0 keeps the model's own.
const SKINS: Array[Color] = [Color(0.96, 0.78, 0.64), Color(0.74, 0.52, 0.36), Color(0.45, 0.3, 0.2)]
const HAIRS: Array[Color] = [Color(0.12, 0.09, 0.07), Color(0.55, 0.42, 0.25), Color(0.32, 0.2, 0.12)]
## Hue turns of the clothes of the glaze variants 1..3.
const HUE_TURNS: Array[float] = [0.13, -0.2, 0.5]
const VARIANTS := 4
const FONT_PATH := "res://assets/fonts/Nunito.ttf"

enum State { WALK, PAUSE, PANIC, SIT, FALL, GONE, FILM, CALL, CHASE }

const BLOCK := 128.0
## Half the side of the square a walker follows: the sidewalk lane between the lamp posts and the trees.
const LANE_HALF := 54.4
const ACTIVE_RADIUS := 95.0
const SLEEP_RADIUS := 108.0
const MAX_ACTIVE := 44
const WALK_SPEED := 1.3          ## the pace the Walk clip was made for
const RUN_SPEED := 4.6           ## the pace the Run clip was made for
const SHATTER_J := 600.0         ## a hit with at least this much energy breaks a person (a paw swat has 3000)
const PERSON_KG := 70.0
const MAX_HEADS := 24
const LINES: PackedStringArray = ["Nice kitty?", "Good kitty...", "Pspsps?", "Is that a cat?", "Who let her in?", "Shoo. Shoo!", "Not the vase."]
## What the officers (1) and the firefighters (2) of the Owner's response say to her (Police).
const OFFICER_LINES: PackedStringArray = ["Freeze, kitty!", "Paws where I can see them!", "Step away from the vase.", "We have you surrounded. Sort of.", "Do not make me use the spray bottle."]
const FIRE_LINES: PackedStringArray = ["Who started this?", "Stand back, kitty.", "Nobody panic!", "Is that... a bald cat?"]
## What the rude ones say while they kick at her (they never connect: the Owner cat-proofed her).
const RUDE: PackedStringArray = ["Get lost, furball!", "Scram!", "Not on my watch.", "Beat it, bald cat!", "Try me."]
## Porcelain glazes: mostly white, a few pastel.
const GLAZES: Array[Color] = [Color(0.95, 0.94, 0.9), Color(0.95, 0.94, 0.9), Color(0.93, 0.95, 0.97), Color(0.86, 0.92, 0.97), Color(0.97, 0.88, 0.88), Color(0.88, 0.96, 0.9)]
## What someone says when the cat pees on them (a hit of at most WET_J joules).
const SOAKED: PackedStringArray = ["Not the shoes!", "Bad kitty!", "Ew. EW!", "These were new!", "Why is it warm?"]
const WET_J := 60.0
const PAUSE_CLIPS: Array[StringName] = [&"Idle", &"Idle_Neutral", &"Idle", &"Interact", &"Idle_Neutral"]

## Reactions to chaos they see from a safe distance (2026-11-17): some film it with their phones (every phone
## adds views, see `views`), some call the police (Chaos heat), and the rude ones near Trophe chase her and
## kick her away (it never hurts her; she just flies a little).
const FILM_LINES: PackedStringArray = ["Are you getting this?", "This is going viral.", "I am LIVE. Say hi, everyone.", "Like and subscribe!", "Nobody is going to believe this.", "Hashtag bald cat."]
const CALL_LINES: PackedStringArray = ["Hello, police? A bald cat!", "Yes, a CAT. No, I have not been drinking.", "Send everyone. She has a hat.", "It is happening again. Send someone!"]
const CALLED_LINE := "They are on their way!"
const CHASE_LINES: PackedStringArray = ["Come here, you!", "Not on my street!", "I will show you vases!", "Get back here, furball!"]
const KICK_LINES: PackedStringArray = ["Take that!", "And stay out!", "Shoo! SHOO!"]
const FILM_CHANCE := 0.35
const CALL_CHANCE := 0.15
const CHASE_CHANCE := 0.45
const CALL_SECONDS := 3.5
const CHASE_SPEED := 4.2
const VIEWS_PER_SECOND := 140.0          ## per phone filming her chaos


class Person:
	var id := 0
	var visual: Node3D = null
	var anim: AnimationPlayer = null
	var body := RID()
	var block := Vector3.ZERO      # centre of the block whose sidewalk it walks
	var t := 0.0                   # metres along the lane
	var dir := 1.0
	var speed := 1.3
	var state := State.WALK
	var timer := 0.0               # seconds left in PAUSE / PANIC, seconds until the next pause in WALK
	var pos := Vector3.ZERO
	var yaw := 0.0
	var vy := 0.0
	var clip: StringName = &""
	var active := false
	var bench: BreakableProp = null
	var bench_at := Vector3.ZERO
	var ground_in := 0.0
	var spoke := false
	var size := 1.0
	var glaze := 0
	var look := 0                  # which figure of CAST
	var tint := 0                  # which glaze variant of it (skin, hair and clothes colours)
	var after: StringName = &""    # the clip to go back to when a one-shot clip has played
	var officer := 0               # 1: an officer, 2: a firefighter of the Owner's response (Police)
	var off_lane := false          # stands somewhere of its own (a stall, a cafe); runs freely when scared
	var run_dir := Vector3.ZERO
	var steer_in := 0.0
	var focus := Vector3.ZERO         # what a FILM witness films
	var phone: Node3D = null         # the phone in the hand (FILM, CALL)


var people: Array[Person] = []
var soaked := 0
var shattered := 0
var panics := 0

var _cast: Array[PackedScene] = []
var _cast_rude: Array[bool] = []
var _phone_box: BoxMesh = null
## Views of her chaos on the phones of the city (FILM witnesses add them; the HUD shows them, Jobs saves them).
var views := 0.0
var views_mult := 1.0             ## the shop's PAPARAZZI MAGNET doubles it
var meow_radius := 9.0            ## the shop's BIG LUNGS doubles it
var calls := 0
var kicks := 0
var _overrides: Array = []        # per figure, per variant: {source material: glazed material}
var _skin: Array = []             # per figure, per variant: the glazed skin (for the head that rolls away)
var _sit_drop := PackedFloat32Array()   # per figure: how far the hips come down when it sits
var _glazes: Array[StandardMaterial3D] = []
var _capsule := CapsuleShape3D.new()
var _shards: Array[Mesh] = []
var _shard_shapes: Array[Shape3D] = []
var _head_mesh: SphereMesh
var _head_shape := SphereShape3D.new()
var _heads: Array[RigidBody3D] = []
var _tags: Array[Label3D] = []
var _tag_left := PackedFloat32Array()
var _next_tag := 0
var _active_count := 0
var _scan := 0
var _rng := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters3D.new()


## Files this class reads (the composition root asks worker threads for them ahead of time).
static func model_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Array in CAST:
		out.append(CAST_ROOT + String(c[0]) + ".gltf")
	return out


func _ready() -> void:
	_rng.seed = 4711
	for c: Array in CAST:
		_add_figure(load(CAST_ROOT + String(c[0]) + ".gltf") as PackedScene, bool(c[3]))
	# Built with the world: a new material variant costs a shader compile when it is created.
	for tint in GLAZES:
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		m.roughness = 0.16
		m.metallic_specular = 0.6
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.08
		m.rim_enabled = true
		m.rim = 0.25
		_glazes.append(m)
	_capsule.radius = 0.28
	_capsule.height = 1.7
	for dims: Vector3 in [Vector3(0.22, 0.3, 0.06), Vector3(0.14, 0.2, 0.05), Vector3(0.3, 0.16, 0.07), Vector3(0.1, 0.12, 0.05), Vector3(0.18, 0.4, 0.08)]:
		var shard := PrismMesh.new()
		shard.size = dims
		shard.left_to_right = 0.3
		shard.material = _glazes[0]
		_shards.append(shard)
		var box := BoxShape3D.new()
		box.size = dims
		_shard_shapes.append(box)
	_head_mesh = SphereMesh.new()
	_head_mesh.radius = 0.105
	_head_mesh.height = 0.24
	_head_mesh.radial_segments = 16
	_head_mesh.rings = 8
	_head_mesh.material = _glazes[0]
	_head_shape.radius = 0.105
	var font: Font = load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) else null
	for i in 5:
		var tag := Label3D.new()
		tag.name = "Tag%d" % i
		if font != null:
			tag.font = font
		tag.font_size = 40
		tag.outline_size = 10
		tag.pixel_size = 0.0007
		tag.fixed_size = true
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.shaded = false
		tag.modulate = Color(1.0, 1.0, 1.0)
		tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
		tag.visible = false
		tag.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(tag)
		_tags.append(tag)
		_tag_left.append(0.0)
	_ray.collision_mask = Layers.TERRAIN | Layers.STRUCTURE | Layers.RUBBLE
	DamageRouter.blast.connect(_on_blast)
	Timeline.people = self


## Gets a figure ready once: its looping clips, a sitting clip made from its idle, and its glazed
## materials in every variant.
func _add_figure(scene: PackedScene, rude: bool) -> void:
	_cast.append(scene)
	_cast_rude.append(rude)
	var per_variant: Array = []
	var skins: Array = []
	for v in VARIANTS:
		per_variant.append({})
		skins.append(null)
	_overrides.append(per_variant)
	_skin.append(skins)
	_sit_drop.append(0.0)
	if scene == null:
		return
	var tmp := scene.instantiate()
	var players := tmp.find_children("*", "AnimationPlayer", true, false)
	var skeletons := tmp.find_children("*", "Skeleton3D", true, false)
	if not players.is_empty():
		var anim := players[0] as AnimationPlayer
		var lib := anim.get_animation_library(&"")
		for clip in LOOPS:
			if lib.has_animation(clip):
				lib.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		if not skeletons.is_empty() and lib.has_animation(&"Idle") and not lib.has_animation(&"Sit"):
			var sit := _make_sit(lib.get_animation(&"Idle"), skeletons[0] as Skeleton3D, _sit_drop.size() - 1)
			if sit != null:
				lib.add_animation(&"Sit", sit)
	for node in tmp.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si) as StandardMaterial3D
			if src == null or (per_variant[0] as Dictionary).has(src):
				continue
			var lname := src.resource_name.to_lower()
			for v in VARIANTS:
				var m := src.duplicate() as StandardMaterial3D
				var c := m.albedo_color
				if v > 0:
					if lname.contains("skin"):
						c = SKINS[v - 1]
					elif lname.contains("hair") or lname.contains("brow"):
						c = HAIRS[v - 1]
					elif not lname.contains("eye") and c.s > 0.12:
						c = Color.from_hsv(fposmod(c.h + HUE_TURNS[v - 1], 1.0), c.s, c.v, c.a)
				m.albedo_color = c
				# The glaze of a painted porcelain figure.
				m.roughness = 0.32
				m.metallic = 0.0
				m.metallic_specular = 0.55
				m.clearcoat_enabled = true
				m.clearcoat = 0.6
				m.clearcoat_roughness = 0.18
				(per_variant[v] as Dictionary)[src] = m
				if lname.contains("skin"):
					skins[v] = m
	tmp.free()


## A sitting clip made from the idle one: the thighs swing forward and the shins hang down again, so the
## figure sits on whatever is under its hips once it is lowered by the length of its thigh.
func _make_sit(idle: Animation, sk: Skeleton3D, figure: int) -> Animation:
	var sit := idle.duplicate(true) as Animation
	var lateral := Vector3.RIGHT
	var found := 0
	for side in [".L", ".R"]:
		var thigh := sk.find_bone("UpperLeg" + side)
		var shin := sk.find_bone("LowerLeg" + side)
		if thigh < 0 or shin < 0:
			continue
		var thigh_rest := sk.get_bone_global_rest(thigh)
		var shin_rest := sk.get_bone_global_rest(shin)
		_sit_drop[figure] = maxf(_sit_drop[figure], thigh_rest.origin.distance_to(shin_rest.origin))
		for pair: Array in [[thigh, -PI * 0.5, thigh_rest], [shin, PI * 0.5, shin_rest]]:
			var axis := ((pair[2] as Transform3D).basis.inverse() * lateral).normalized()
			var turn := Quaternion(axis, float(pair[1]))
			var bone_name := sk.get_bone_name(int(pair[0]))
			for t in sit.get_track_count():
				if sit.track_get_type(t) != Animation.TYPE_ROTATION_3D:
					continue
				if sit.track_get_path(t).get_concatenated_subnames() != bone_name:
					continue
				for k in sit.track_get_key_count(t):
					var q: Quaternion = sit.track_get_key_value(t, k)
					sit.track_set_key_value(t, k, q * turn)
				found += 1
	sit.loop_mode = Animation.LOOP_LINEAR
	return sit if found == 4 else null


func count() -> int:
	return people.size()


func alive_count() -> int:
	var n := 0
	for p in people:
		if p.state != State.GONE:
			n += 1
	return n


func active_count() -> int:
	return _active_count


## Walkers on the sidewalk around one block (its centre given), spread around the lane.
func add_walkers(block: Vector3, n: int) -> void:
	for i in n:
		var p := _new_person(block)
		p.block = block
		p.t = _rng.randf() * LANE_HALF * 8.0
		p.dir = 1.0 if _rng.randf() < 0.5 else -1.0
		p.speed = _rng.randf_range(1.05, 1.5)
		p.timer = _rng.randf_range(4.0, 18.0)
		_place_on_lane(p)


## Someone sitting on a bench (until the bench is moved or broken, or something scares them).
func add_sitter(bench: BreakableProp) -> void:
	var p := _new_person(bench.global_position)
	p.state = State.SIT
	p.bench = bench
	p.bench_at = bench.global_position
	# The seat of the bench model looks along its +Z, like a person. The sitting clip keeps the hips a
	# third of a metre behind the feet, so the person stands in front of the middle of the seat.
	p.yaw = bench.global_rotation.y
	p.pos = bench.global_position + Vector3(sin(p.yaw), 0.0, cos(p.yaw)) * 0.02
	p.block = Vector3(floorf(p.pos.x / BLOCK) * BLOCK + BLOCK * 0.5, 0.0, floorf(p.pos.z / BLOCK) * BLOCK + BLOCK * 0.5)
	p.speed = _rng.randf_range(1.1, 1.4)


## Someone who stands at a spot of their own (behind a stall, by a cafe table) until something scares them.
func add_stander(at: Vector3, yaw: float) -> void:
	var p := _new_person(at)
	p.off_lane = true
	p.state = State.PAUSE
	p.timer = 1.0e9
	p.pos = at
	p.yaw = yaw
	p.block = Vector3(floorf(at.x / BLOCK) * BLOCK + BLOCK * 0.5, 0.0, floorf(at.z / BLOCK) * BLOCK + BLOCK * 0.5)


## Every block of the city gets its walkers by district; one bench in four gets a sitter.
func populate(dressing: StreetDressing) -> void:
	var per_district := {CityLayout.District.DOWNTOWN: 9, CityLayout.District.OLD_QUARTER: 6, CityLayout.District.WORKS: 3, CityLayout.District.PARK: 5,
		CityLayout.District.STRIP: 7, CityLayout.District.YARDS: 2, CityLayout.District.SUBURBS: 4}
	for district: int in per_district:
		for block in CityLayout.block_centres(district):
			add_walkers(block, ceili(per_district[district] * (0.5 if Game.lite else 1.0)))
	if dressing != null:
		for prop in dressing.props:
			if prop.prop_id == &"bench" and _rng.randf() < 0.25:
				add_sitter(prop)


func _new_person(at: Vector3) -> Person:
	var p := Person.new()
	p.id = people.size()
	p.size = _rng.randf_range(0.9, 1.06)
	p.glaze = _rng.randi_range(0, _glazes.size() - 1)
	p.look = _pick_figure(CityLayout.district_at(at))
	p.tint = _rng.randi_range(0, VARIANTS - 1)
	people.append(p)
	Progress.add_total_mass(PERSON_KG)
	return p


## A figure of the cast for someone in a district, by weight.
func _pick_figure(district: int) -> int:
	var total := 0
	for c: Array in CAST:
		if (c[1] as Array).is_empty() or (c[1] as Array).has(district):
			total += int(c[2])
	var pick := _rng.randi_range(0, maxi(total - 1, 0))
	for i in CAST.size():
		var c: Array = CAST[i]
		if (c[1] as Array).is_empty() or (c[1] as Array).has(district):
			pick -= int(c[2])
			if pick < 0:
				return i
	return 3


# --------------------------------------------------------------------------------------------------
# Frame update
# --------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player) or people.is_empty():
		return
	var cat_at := player.global_position
	# A few people per tick are checked for coming into or going out of range.
	for k in mini(10, people.size()):
		_scan = (_scan + 1) % people.size()
		var p := people[_scan]
		if p.state == State.GONE:
			continue
		var d := p.pos.distance_to(cat_at)
		if p.active and d > SLEEP_RADIUS:
			_deactivate(p)
		elif not p.active and d < ACTIVE_RADIUS and _active_count < MAX_ACTIVE:
			_activate(p)
	for p in people:
		if p.state == State.GONE:
			continue
		if p.active:
			_tick_active(p, delta, cat_at)
		elif p.state == State.WALK:
			p.t += p.dir * p.speed * delta   # out of sight they simply keep walking
			_place_on_lane(p)
	for i in _tags.size():
		if _tag_left[i] > 0.0:
			_tag_left[i] -= delta
			_tags[i].modulate.a = clampf(_tag_left[i] / 0.5, 0.0, 1.0)
			_tags[i].outline_modulate.a = 0.7 * clampf(_tag_left[i] / 0.5, 0.0, 1.0)
			if _tag_left[i] <= 0.0:
				_tags[i].visible = false


func _tick_active(p: Person, delta: float, cat_at: Vector3) -> void:
	if p.officer != 0 and p.state == State.PAUSE:
		_tick_officer(p, delta, cat_at)
		return
	match p.state:
		State.WALK:
			p.t += p.dir * p.speed * delta
			_place_on_lane(p)
			_play(p, &"Walk", p.speed / WALK_SPEED)
			p.timer -= delta
			if p.timer <= 0.0:
				p.state = State.PAUSE
				p.timer = _rng.randf_range(3.0, 8.0)
				p.spoke = false
				_play(p, PAUSE_CLIPS[_rng.randi_range(0, PAUSE_CLIPS.size() - 1)], 1.0)
		State.PAUSE:
			p.timer -= delta
			if p.clip == &"":
				_play(p, PAUSE_CLIPS[p.id % PAUSE_CLIPS.size()], 1.0)   # just came into view standing
			var to_cat := cat_at - p.pos
			if to_cat.length_squared() < 16.0:
				# Trophe is close: turn to her and say something.
				p.yaw = lerp_angle(p.yaw, atan2(to_cat.x, to_cat.z), minf(delta * 6.0, 1.0))
				if not p.spoke:
					p.spoke = true
					if _cast_rude[p.look] and _rng.randf() < 0.6:
						_say(p, RUDE[_rng.randi_range(0, RUDE.size() - 1)])
						_play_once(p, &"Kick_Right" if _rng.randf() < 0.5 else &"Punch_Right", &"Idle")
					else:
						_say(p, LINES[_rng.randi_range(0, LINES.size() - 1)])
						_play(p, &"Wave", 1.0)
			if p.timer <= 0.0 and not p.off_lane:
				p.state = State.WALK
				p.timer = _rng.randf_range(6.0, 20.0)
		State.PANIC:
			if p.off_lane:
				_run_free(p, delta)
			else:
				p.t += p.dir * p.speed * delta
				_place_on_lane(p)
			_play(p, &"Run", p.speed / RUN_SPEED)
			p.timer -= delta
			if p.timer <= 0.0:
				p.speed = _rng.randf_range(1.05, 1.5)
				if p.off_lane:
					p.state = State.PAUSE     # catches their breath where they ended up
					p.timer = 1.0e9
					p.spoke = false
					_play(p, &"Idle", 1.0)
				else:
					p.state = State.WALK
					p.timer = _rng.randf_range(5.0, 14.0)
		State.SIT:
			_play(p, &"Sit", 1.0)
			if not is_instance_valid(p.bench) or p.bench.is_broken() or p.bench.global_position.distance_to(p.bench_at) > 0.3:
				_stand_up(p, p.pos, true)
			elif (cat_at - p.pos).length_squared() < 9.0 and not p.spoke:
				p.spoke = true
				_say(p, LINES[_rng.randi_range(0, LINES.size() - 1)])
		State.FALL:
			p.vy -= 9.8 * delta
			p.pos.y += p.vy * delta
			var ground := _ground_under(p.pos, 2.5)
			if is_finite(ground) and p.pos.y <= ground:
				if p.vy < -6.5:
					_shatter(p, Vector3.DOWN, 0)
					return
				p.pos.y = ground
				p.vy = 0.0
				p.state = State.PANIC
				p.speed = _rng.randf_range(4.4, 5.4)
				p.timer = 3.0
			elif p.pos.y < -45.0:
				_shatter(p, Vector3.DOWN, 0)
				return
		State.FILM:
			var seen := p.focus - p.pos
			p.yaw = lerp_angle(p.yaw, atan2(seen.x, seen.z), minf(delta * 5.0, 1.0))
			_play(p, &"Idle_Gun_Pointing", 1.0)
			views += VIEWS_PER_SECOND * views_mult * delta
			p.timer -= delta
			if (cat_at - p.pos).length_squared() < 9.0:
				_scare(p, cat_at, 5.0)   # she came for the phone
			elif p.timer <= 0.0:
				_back_to_walk(p)
		State.CALL:
			var away := p.pos - cat_at
			p.yaw = lerp_angle(p.yaw, atan2(away.x, away.z), minf(delta * 4.0, 1.0))   # turned away from her
			_play(p, &"Wave", 1.0)
			p.timer -= delta
			if (cat_at - p.pos).length_squared() < 9.0:
				_scare(p, cat_at, 5.0)   # the call is dropped
			elif p.timer <= 0.0:
				calls += 1
				called_police.emit(p.pos)
				_say(p, CALLED_LINE)
				_scare(p, cat_at, 5.0)
		State.CHASE:
			var to_her := cat_at - p.pos
			to_her.y = 0.0
			var dist := to_her.length()
			p.timer -= delta
			if dist > 0.05:
				p.yaw = lerp_angle(p.yaw, atan2(to_her.x, to_her.z), minf(delta * 8.0, 1.0))
			if not _cat_on_foot() or p.timer <= 0.0 or dist > 26.0:
				_back_to_walk(p)
			elif dist < 1.3:
				_kick(p, to_her / maxf(dist, 0.01))
			else:
				p.pos += to_her / dist * CHASE_SPEED * delta
				_play(p, &"Run", CHASE_SPEED / RUN_SPEED)
	if p.state == State.WALK or p.state == State.PANIC or p.state == State.PAUSE or p.state == State.CHASE:
		p.ground_in -= delta
		if p.ground_in <= 0.0:
			p.ground_in = 0.35
			var ground := _ground_under(p.pos, 2.2)
			if not is_finite(ground):
				p.state = State.FALL    # the sidewalk under them is gone
				p.vy = 0.0
				_play(p, &"HitRecieve_2", 1.0)
			elif ground > p.pos.y + 0.6:
				p.dir = -p.dir          # a pile of rubble in the way: turn round
			else:
				p.pos.y = ground
	_sync(p)


# --------------------------------------------------------------------------------------------------
# What happens to them
# --------------------------------------------------------------------------------------------------

## DamageRouter entry (the capsule of every active person is registered with its index).
func receive_damage(hit: DamageHit, user_id: int) -> void:
	if user_id < 0 or user_id >= people.size():
		return
	var p := people[user_id]
	if p.state == State.GONE:
		return
	if hit.energy >= SHATTER_J:
		_shatter(p, hit.direction, hit.cause_id)
	else:
		if hit.energy <= WET_J:
			if p.state == State.PANIC:
				return   # already running; the rest of the stream changes nothing
			soaked += 1
			_say(p, SOAKED[_rng.randi() % SOAKED.size()])
		_scare(p, hit.position, 5.0)
		_play_once(p, &"HitRecieve", &"Run")


## Someone of the Owner's response (Police): walks up to Trophe, points at her and orders her about; the
## rude ones swing at her when she is close (it never connects).
func _tick_officer(p: Person, delta: float, cat_at: Vector3) -> void:
	var to_cat := cat_at - p.pos
	to_cat.y = 0.0
	var d := to_cat.length()
	if d > 0.05:
		p.yaw = lerp_angle(p.yaw, atan2(to_cat.x, to_cat.z), minf(delta * 5.0, 1.0))
	p.timer -= delta
	if d > 6.0 and d < 80.0:
		p.pos += to_cat / d * 1.6 * delta
		_play(p, &"Walk", 1.6 / WALK_SPEED)
		p.ground_in -= delta
		if p.ground_in <= 0.0:
			p.ground_in = 0.35
			var ground := _ground_under(p.pos, 2.2)
			if is_finite(ground):
				p.pos.y = ground
	elif d <= 6.0:
		if p.timer <= 0.0:
			p.timer = _rng.randf_range(3.5, 6.5)
			var lines := OFFICER_LINES if p.officer == 1 else FIRE_LINES
			_say(p, lines[_rng.randi_range(0, lines.size() - 1)])
			if d < 2.4 and _cast_rude[p.look]:
				_play_once(p, &"Punch_Right" if _rng.randf() < 0.5 else &"Kick_Right", &"Idle_Gun_Pointing")
		if p.after == &"":
			_play(p, &"Idle_Gun_Pointing" if p.officer == 1 else &"Wave", 1.0)
	else:
		_play(p, &"Idle_Gun" if p.officer == 1 else &"Idle", 1.0)
	_sync(p)


## Someone of the Owner's response out of a unit's car (Police): a figure of CAST by name at a spot of
## its own, awake at once. Returns the id.
func add_officer(at: Vector3, yaw: float, figure: StringName, kind: int = 1) -> int:
	var p := _new_person(at)
	for i in CAST.size():
		if StringName(CAST[i][0]) == figure:
			p.look = i
			break
	p.officer = kind
	p.off_lane = true
	p.state = State.PAUSE
	p.timer = _rng.randf_range(0.5, 2.0)
	p.pos = at
	p.yaw = yaw
	p.block = Vector3(floorf(at.x / BLOCK) * BLOCK + BLOCK * 0.5, 0.0, floorf(at.z / BLOCK) * BLOCK + BLOCK * 0.5)
	_activate(p)
	return p.id


## Takes someone out of the city without a sound (an officer gone back to the car).
func retire(id: int) -> void:
	if id < 0 or id >= people.size():
		return
	var p := people[id]
	if p.state == State.GONE:
		return
	_deactivate(p)
	p.state = State.GONE
	p.officer = 0
	if p.visual != null:
		p.visual.queue_free()
		p.visual = null
		p.anim = null


## Everyone active within `radius` of a point runs from it.
func scare(at: Vector3, radius: float) -> void:
	for p in people:
		if p.active and p.state != State.GONE and p.state != State.FALL and p.pos.distance_squared_to(at) < radius * radius:
			if not _react(p, at):
				_scare(p, at, _rng.randf_range(4.0, 7.5))


func _scare(p: Person, from: Vector3, seconds: float) -> void:
	_phone(p, false)
	if p.state == State.SIT:
		_stand_up(p, from, false)
	var already := p.state == State.PANIC
	if not already:
		panics += 1
	p.state = State.PANIC
	p.speed = _rng.randf_range(4.4, 5.4)
	p.timer = maxf(p.timer if already else 0.0, seconds)
	if p.off_lane:
		var away := p.pos - from
		away.y = 0.0
		p.run_dir = away.normalized() if away.length_squared() > 0.01 else Vector3(_rng.randf() - 0.5, 0.0, _rng.randf() - 0.5).normalized()
		p.steer_in = 0.0
		return
	# Along the lane, in whichever direction gets away from the danger.
	var ahead := _lane_point(p.block, p.t + 4.0)
	var behind := _lane_point(p.block, p.t - 4.0)
	p.dir = 1.0 if ahead.distance_squared_to(from) >= behind.distance_squared_to(from) else -1.0


## Off the lane a scared person runs straight away from the danger and turns aside when a wall, a
## tree or a piece of furniture is in the way.
func _run_free(p: Person, delta: float) -> void:
	p.steer_in -= delta
	if p.steer_in <= 0.0:
		p.steer_in = 0.25
		var from := p.pos + Vector3.UP * 0.6
		var q := PhysicsRayQueryParameters3D.create(from, from + p.run_dir * 2.2, Layers.STRUCTURE | Layers.PROPS | Layers.PROTECTED | Layers.RUBBLE)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			p.run_dir = p.run_dir.rotated(Vector3.UP, deg_to_rad(70.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
	p.pos += p.run_dir * p.speed * delta
	p.yaw = lerp_angle(p.yaw, atan2(p.run_dir.x, p.run_dir.z), minf(delta * 10.0, 1.0))


## A witness of chaos at `at` may film it, call the police or (rude, near Trophe) go after her instead of
## running. True when they do one of those (or are already busy with one).
func _react(p: Person, at: Vector3) -> bool:
	if p.officer != 0:
		return false
	if p.state == State.FILM or p.state == State.CALL or p.state == State.CHASE:
		return true
	if p.state != State.WALK and p.state != State.PAUSE:
		return false
	var roll := _rng.randf()
	var cat := Game.player
	if _cast_rude[p.look] and _cat_on_foot() and p.pos.distance_to(cat.global_position) < 14.0 and roll < CHASE_CHANCE:
		p.state = State.CHASE
		p.timer = _rng.randf_range(6.0, 9.0)
		p.off_lane = true            # afterwards they stand where the chase ended
		p.after = &""
		_say(p, CHASE_LINES[_rng.randi_range(0, CHASE_LINES.size() - 1)])
		return true
	if p.pos.distance_to(at) < 11.0:
		return false
	# Only her chaos is worth a phone: something that happens far from Trophe (two cars of the traffic) is not.
	if cat == null or not is_instance_valid(cat) or cat.global_position.distance_to(at) > 40.0:
		return false
	if roll < FILM_CHANCE:
		p.state = State.FILM
		p.focus = at
		p.timer = _rng.randf_range(6.0, 11.0)
		_phone(p, true)
		_say(p, FILM_LINES[_rng.randi_range(0, FILM_LINES.size() - 1)])
		return true
	if roll < FILM_CHANCE + CALL_CHANCE:
		p.state = State.CALL
		p.timer = CALL_SECONDS
		_phone(p, true)
		_say(p, CALL_LINES[_rng.randi_range(0, CALL_LINES.size() - 1)])
		return true
	return false


func _cat_on_foot() -> bool:
	var cat := Game.player
	return cat != null and is_instance_valid(cat) and cat.is_visible_in_tree()


## One kick, a line, and the chase is over: Trophe flies off a little (CatController.kicked).
func _kick(p: Person, dir: Vector3) -> void:
	kicks += 1
	_say(p, KICK_LINES[_rng.randi_range(0, KICK_LINES.size() - 1)])
	_play_once(p, &"Kick_Right", &"Idle")
	p.state = State.PAUSE
	p.timer = 1.0e9
	p.spoke = true
	var cat := Game.player
	if cat != null and cat.has_method(&"kicked"):
		cat.call(&"kicked", dir)


func _back_to_walk(p: Person) -> void:
	_phone(p, false)
	p.spoke = false
	p.speed = _rng.randf_range(1.05, 1.5)
	if p.off_lane:
		p.state = State.PAUSE        # stands where it ended up
		p.timer = 1.0e9
		_play(p, &"Idle", 1.0)
	else:
		p.state = State.WALK
		p.timer = _rng.randf_range(5.0, 14.0)


## The phone in the right hand while filming or calling (made the first time, then shown and hidden).
func _phone(p: Person, on: bool) -> void:
	if p.visual == null:
		return
	if p.phone == null:
		if not on:
			return
		var skels := p.visual.find_children("*", "Skeleton3D", true, false)
		if skels.is_empty():
			return
		var sk := skels[0] as Skeleton3D
		if sk.find_bone("Wrist.R") < 0:
			return
		var att := BoneAttachment3D.new()
		att.bone_name = "Wrist.R"
		sk.add_child(att)
		var s := maxf(sk.global_transform.basis.get_scale().x, 0.0001)
		var mi := MeshInstance3D.new()
		mi.mesh = _phone_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * (p.size / s)
		mi.position = Vector3(0.0, 0.09, 0.02) * (p.size / s)
		att.add_child(mi)
		p.phone = att
	p.phone.visible = on


func _phone_mesh() -> Mesh:
	if _phone_box == null:
		_phone_box = BoxMesh.new()
		_phone_box.size = Vector3(0.075, 0.15, 0.012)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.06, 0.08)
		m.emission_enabled = true
		m.emission = Color(0.55, 0.82, 1.0)
		m.emission_energy_multiplier = 0.9
		_phone_box.material = m
	return _phone_box


## How many are filming her right now.
func filming_count() -> int:
	var n := 0
	for p in people:
		if p.state == State.FILM and p.active:
			n += 1
	return n


## A sitter gets up: onto the nearest point of its block's lane.
func _stand_up(p: Person, from: Vector3, run: bool) -> void:
	var best := 0.0
	var best_d := 1.0e18
	var steps := 64
	for i in steps:
		var t := LANE_HALF * 8.0 * i / steps
		var d := _lane_point(p.block, t).distance_squared_to(p.pos)
		if d < best_d:
			best_d = d
			best = t
	p.t = best
	p.bench = null
	p.state = State.WALK
	p.timer = _rng.randf_range(5.0, 12.0)
	if run:
		_scare(p, from, 5.0)


func _shatter(p: Person, direction: Vector3, cause: int) -> void:
	var at := p.pos
	var dir := direction if direction != Vector3.ZERO else Vector3(_rng.randf() - 0.5, 0.0, _rng.randf() - 0.5).normalized()
	var was_active := p.active
	var before := p.state
	_deactivate(p)
	p.state = State.GONE
	if p.visual != null:
		p.visual.visible = false   # kept for the rewind window
	shattered += 1
	Progress.add_destroyed_mass(PERSON_KG)
	Progress.report_break()
	Timeline.record_person(self, p.id, before)
	person_shattered.emit(at)
	if not was_active:
		return
	var debris := Game.debris as DebrisManager
	if debris != null:
		var use_cause := cause if cause != 0 else DamageRouter.new_cause_id()
		for i in 11:
			var k := _rng.randi_range(0, _shards.size() - 1)
			var offset := Vector3(_rng.randf_range(-0.18, 0.18), _rng.randf_range(0.15, 1.55) * p.size, _rng.randf_range(-0.12, 0.12))
			var xf := Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)), at + offset)
			var v := dir * _rng.randf_range(1.5, 5.0) + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(0.5, 3.5), _rng.randf_range(-1.5, 1.5))
			var spin := Vector3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0))
			debris.spawn_piece(_shards[k], _shard_shapes[k], xf, Vector3.ZERO, PERSON_KG / 14.0, v, spin, DebrisManager.T2, &"tile", use_cause)
	_spawn_head(at + Vector3.UP * 1.62 * p.size, dir * _rng.randf_range(2.0, 4.5) + Vector3.UP * _rng.randf_range(2.0, 4.0), _skin[p.look][p.tint])
	var fx := WorldFX.instance
	if fx != null:
		fx.splash(at + Vector3.UP * 1.0, (dir + Vector3.UP).normalized(), 12, Color(0.96, 0.95, 0.92), 0.0, 4.5)
		for i in 4:
			fx.puff(at + Vector3.UP * _rng.randf_range(0.4, 1.5), Vector3(_rng.randf() - 0.5, _rng.randf() * 0.6, _rng.randf() - 0.5) * 1.6, Color(0.93, 0.92, 0.9, 0.45), _rng.randf_range(0.9, 1.6), 0.4, 1.5)
	Audio.play_3d(&"porcelain_shatter", at + Vector3.UP, 1.0)
	scare(at, 14.0)


## The head of a broken person rolls away: a light prop the cat can pick up and throw.
func _spawn_head(at: Vector3, velocity: Vector3, glaze: Material = null) -> void:
	var head := RigidBody3D.new()
	head.name = "PorcelainHead"
	head.mass = 3.5
	head.collision_layer = Layers.PROPS
	head.collision_mask = Layers.TERRAIN | Layers.STRUCTURE | Layers.DEBRIS | Layers.RUBBLE | Layers.PROPS | Layers.PROTECTED
	head.continuous_cd = true
	var col := CollisionShape3D.new()
	col.shape = _head_shape
	head.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = _head_mesh
	if glaze != null:
		mi.material_override = glaze
	head.add_child(mi)
	add_child(head)
	head.set_meta(&"born", Timeline.now)
	head.global_position = at
	head.linear_velocity = velocity
	head.angular_velocity = Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0))
	head.reset_physics_interpolation()
	_heads.append(head)
	while _heads.size() > MAX_HEADS:
		var old: RigidBody3D = _heads.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## A meow right next to them is enough to send them running.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M and Game.player != null:
		scare(Game.player.global_position, meow_radius)


func _on_blast(hit: DamageHit) -> void:
	scare(hit.position, hit.radius * 3.0 + 14.0)


# --------------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------------

## Point of the sidewalk lane around a block, t metres along it (clockwise seen from above for dir +1).
func _lane_point(block: Vector3, t: float) -> Vector3:
	var side_len := LANE_HALF * 2.0
	var u := fposmod(t, side_len * 4.0)
	var side := int(u / side_len)
	var s := u - side * side_len - LANE_HALF
	match side:
		0:
			return block + Vector3(s, 0.0, -LANE_HALF)
		1:
			return block + Vector3(LANE_HALF, 0.0, s)
		2:
			return block + Vector3(-s, 0.0, LANE_HALF)
	return block + Vector3(-LANE_HALF, 0.0, -s)


func _place_on_lane(p: Person) -> void:
	var at := _lane_point(p.block, p.t)
	var next := _lane_point(p.block, p.t + p.dir * 0.6)
	p.pos = Vector3(at.x, p.pos.y, at.z)
	var heading := next - at
	if heading.length_squared() > 0.0001:
		p.yaw = lerp_angle(p.yaw, atan2(heading.x, heading.z), 0.25) if p.active else atan2(heading.x, heading.z)


## Height of the ground under a point (within `reach` below it), or INF when there is none.
func _ground_under(at: Vector3, reach: float) -> float:
	_ray.from = at + Vector3.UP * 1.3
	_ray.to = at + Vector3.DOWN * reach
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return INF
	return (hit["position"] as Vector3).y


func _activate(p: Person) -> void:
	p.active = true
	_active_count += 1
	if p.visual == null:
		p.visual = _cast[p.look].instantiate() as Node3D
		p.visual.name = "Person%d" % p.id
		p.visual.scale = Vector3.ONE * p.size
		add_child(p.visual)
		var players := p.visual.find_children("*", "AnimationPlayer", true, false)
		p.anim = players[0] as AnimationPlayer if not players.is_empty() else null
		var glaze: Dictionary = _overrides[p.look][p.tint]
		for node in p.visual.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			for si in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(si)
				if glaze.has(src):
					mi.set_surface_override_material(si, glaze[src])
	p.visual.visible = true
	p.clip = &""
	var ground := _ground_under(p.pos + Vector3.UP * 0.5, 4.0)
	if is_finite(ground) and p.state != State.SIT:
		p.pos.y = ground
	if not p.body.is_valid():
		p.body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(p.body, PhysicsServer3D.BODY_MODE_KINEMATIC)
		PhysicsServer3D.body_add_shape(p.body, _capsule.get_rid(), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.88, 0.0)))
		PhysicsServer3D.body_set_collision_layer(p.body, Layers.NPC)
		PhysicsServer3D.body_set_collision_mask(p.body, 0)
		PhysicsServer3D.body_set_space(p.body, get_world_3d().space)
		DamageRouter.register_rid(p.body, self, p.id)
		if p.state == State.SIT and is_instance_valid(p.bench):
			# The capsule stands inside the bench: without this the bench is pushed out from under them.
			PhysicsServer3D.body_add_collision_exception(p.body, p.bench.get_rid())
			PhysicsServer3D.body_add_collision_exception(p.bench.get_rid(), p.body)
	_sync(p)
	p.visual.reset_physics_interpolation()


## World rewind: whole again, back to what they were doing (a fall or a panic becomes a pause).
func unshatter(id: int, before: int) -> void:
	if id < 0 or id >= people.size():
		return
	var p := people[id]
	if p.state != State.GONE:
		return
	var was := before as State
	p.state = was if was == State.WALK or was == State.PAUSE or was == State.SIT else State.PAUSE
	_phone(p, false)
	p.timer = 2.0
	if p.visual != null:
		p.visual.visible = false   # shown again when it is activated near Trophe
	shattered -= 1
	Progress.remove_destroyed_mass(PERSON_KG)


## World rewind: heads that rolled after `t` (Timeline clock) are gone.
func rewind_heads(t: float) -> void:
	for i in range(_heads.size() - 1, -1, -1):
		var h := _heads[i]
		if not is_instance_valid(h) or float(h.get_meta(&"born", 0.0)) > t:
			if is_instance_valid(h):
				h.queue_free()
			_heads.remove_at(i)


## Saved games: the ids of the shattered.
func save_state() -> Array:
	var out := []
	for p in people:
		if p.state == State.GONE:
			out.append(p.id)
	return out


## The shattered are gone again, without shards, heads or screams.
func restore_state(ids: Array) -> void:
	for v: Variant in ids:
		var i := int(v)
		if i < 0 or i >= people.size():
			continue
		var p := people[i]
		if p.state == State.GONE:
			continue
		_deactivate(p)
		p.state = State.GONE
		if p.visual != null:
			p.visual.queue_free()
			p.visual = null
			p.anim = null
		shattered += 1
		Progress.add_destroyed_mass(PERSON_KG)


func _deactivate(p: Person) -> void:
	if not p.active:
		return
	p.active = false
	_active_count -= 1
	if p.visual != null:
		p.visual.visible = false
	if p.anim != null:
		p.anim.pause()
	if p.body.is_valid():
		DamageRouter.unregister_rid(p.body)
		PhysicsServer3D.free_rid(p.body)
		p.body = RID()


func _sync(p: Person) -> void:
	if p.visual == null or p.state == State.GONE:
		return
	var at := p.pos
	if p.state == State.SIT:
		at.y -= _sit_drop[p.look] * p.size
	p.visual.global_transform = Transform3D(Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.size), at)
	if p.after != &"" and p.anim != null and not p.anim.is_playing():
		var next := p.after
		p.after = &""
		_play(p, next, 1.0)
	if p.body.is_valid():
		PhysicsServer3D.body_set_state(p.body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(Vector3.UP, p.yaw), p.pos))


func _play(p: Person, clip: StringName, rate: float) -> void:
	if p.anim == null:
		return
	if p.after != &"" and p.anim.is_playing() and clip != p.clip:
		if clip == p.after:
			return   # a one-shot clip is still playing; it hands over by itself
		p.after = &""
	if p.clip != clip:
		if not p.anim.has_animation(clip):
			return
		p.clip = clip
		p.anim.play(clip, 0.25)
	p.anim.speed_scale = rate


## A clip that plays once (a kick, a flinch) and then hands over to `then`.
func _play_once(p: Person, clip: StringName, then: StringName) -> void:
	if p.anim == null or not p.anim.has_animation(clip):
		return
	p.after = &""
	p.clip = clip
	p.anim.play(clip, 0.15)
	p.anim.speed_scale = 1.0
	p.after = then


func _say(p: Person, line: String) -> void:
	var i := _next_tag
	_next_tag = (_next_tag + 1) % _tags.size()
	_tags[i].text = tr(line)
	_tags[i].global_position = p.pos + Vector3.UP * (1.95 * p.size)
	_tags[i].modulate.a = 1.0
	_tags[i].visible = true
	_tag_left[i] = 2.4


func _exit_tree() -> void:
	for p in people:
		if p.body.is_valid():
			DamageRouter.unregister_rid(p.body)
			PhysicsServer3D.free_rid(p.body)
			p.body = RID()
