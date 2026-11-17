class_name BreakableProp
extends RigidBody3D
## One man-made thing standing in the world: a bench, a lamp post, a bin, a gas bottle, a parked car.
## It is a rigid body on Layers.PROPS that the cat can push, grab and throw (when light and not bolted
## down), that takes DamageHits through receive_damage(), and that breaks into real debris when its
## hit points run out: the pieces are a Voronoi fracture of its bounding box in its material (from the
## destruction module's FractureLibrary), thinned out so a slender thing does not turn into a solid
## block of rubble. Props with a `blast` explode when they break (gas, fuel) and set off their neighbours.

const D := preload("res://game/destruction/destruction_defs.gd")
const SOUNDS := {
	&"steel": &"impact_metal", &"metal_rusty": &"impact_metal", &"wood": &"impact_wood",
	&"concrete": &"impact_concrete", &"plaster": &"impact_plaster", &"glass": &"impact_glass",
	&"tile": &"impact_ceramic", &"sheet_metal": &"impact_metal",
}
const MASK := Layers.TERRAIN | Layers.STRUCTURE | Layers.DEBRIS | Layers.DEBRIS_SMALL | Layers.RUBBLE | Layers.PROPS | Layers.NPC | Layers.PLAYER | Layers.PROTECTED
## A hit never throws a prop faster than this, whatever its impulse says (a 3 kg box and a 9 kN*s blast).
const MAX_PUSH_SPEED := 18.0
## Props whose largest side is smaller than this just burst into chips.
const MIN_FRACTURE_SIZE := 0.3
## Own speed lost in one tick (m/s) above which a prop is hurt by what it ran into.
const CRASH_DV := 6.0
## The same for fragile things (vases, bottles, screens): a fall from a table is enough.
const FRAGILE_CRASH_DV := 2.2
## A blunt hit on something lighter than this that is not fragile-proof only knocks it away; what it
## lands on does the breaking. Swatting a vase sends it flying instead of bursting it on the spot.
const KNOCK_MASS := 6.0
const BLAST_DELAY := 0.12
## The terrain streams collision about 160 m around the player; props stay put beyond this.
const GROUND_RANGE := 140.0
const WRECK_SMOKE_SECONDS := 26.0

signal broken(prop: BreakableProp)
signal wrecked(prop: BreakableProp)

var prop_id: StringName = &""
var material_name: StringName = &"steel"
var hp := 5000.0
var max_hp := 5000.0
## Bolted to the ground (frozen) until a hit of at least unbolt_energy joules frees it.
var anchored := false
var unbolt_energy := 4000.0
## Share of the bounding box that is actually material (a bench is mostly air).
var solid_fraction := 0.3
## {radius, energy, impulse} of the explosion when the prop breaks; empty for inert props.
var blast := {}
var size := Vector3.ONE        ## Bounding box of the model, metres.
var center := Vector3.ZERO     ## Centre of that box in body space.
## A loose prop is frozen while nobody is near: the terrain only has collision around the player, so a
## free body far away would fall through the world. Whoever owns the props (StreetDressing) parks and
## unparks them as the player moves.
var parked := false
## Vehicles die twice: the first time the fuel goes off and a charred, burning wreck is left; the wreck
## is still a prop and breaks apart for good when its hit points run out again.
var wreck := false
## Breaks when it falls off a table (see FRAGILE_CRASH_DV).
var fragile := false
## Share of a crash that hurts it (0.12 while Trophe drives it: bumps are part of driving).
var crash_scale := 1.0

var _blast_def := {}   # the blast it was made with (a rewind gives the fuel back)

var _wrecked := false
var _smoke_left := 0.0
var _smoke_tick := 0.0
var _fire_loop := -1
var _unbolted := false

static var _charred := {}   # material -> its charred copy
var _broken := false
var _break_dir := Vector3.ZERO
var _break_cause := 0
var _break_source: Node = null
var _break_wait := 0.0
var _prev_v := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


## Builds a prop from a definition:
## {model: path, material, mass, hp, anchored?, shape? ("box" | "cylinder"), solid?, scale?, blast?, unbolt?}.
## The model is re-seated so the prop's origin is the middle of its footprint on the ground.
static func create(id: StringName, def: Dictionary) -> BreakableProp:
	var scene := load(def["model"]) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	return from_model(id, def, model)


## Same, from an already instantiated model (a single car cut out of a pack, for instance).
static func from_model(id: StringName, def: Dictionary, model: Node3D) -> BreakableProp:
	var prop := BreakableProp.new()
	prop.name = String(id)
	prop.prop_id = id
	prop.material_name = def.get("material", &"steel")
	prop.max_hp = float(def.get("hp", 5000.0))
	prop.hp = prop.max_hp
	prop.anchored = bool(def.get("anchored", false))
	prop.unbolt_energy = float(def.get("unbolt", prop.max_hp * 0.25))
	prop.solid_fraction = float(def.get("solid", 0.3))
	prop.blast = def.get("blast", {})
	prop._blast_def = (prop.blast as Dictionary).duplicate()
	prop.wreck = bool(def.get("wreck", false))
	prop.fragile = bool(def.get("fragile", false))
	model.transform = Transform3D(Basis.from_scale(Vector3.ONE * float(def.get("scale", 1.0))) * model.transform.basis, Vector3.ZERO)
	prop.add_child(model)
	var box := bounds_of(model, prop)
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	prop.size = box.size
	prop.center = Vector3(0.0, box.size.y * 0.5, 0.0)
	# Small things stop being drawn sooner than big ones.
	var biggest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var far := clampf(biggest * 60.0, 70.0, 220.0)
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for node: Node in meshes:
		(node as MeshInstance3D).visibility_range_end = far
		(node as MeshInstance3D).visibility_range_end_margin = 8.0
		if biggest < 0.7:
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var col := CollisionShape3D.new()
	col.name = "Shape"
	if String(def.get("shape", "box")) == "cylinder":
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(box.size.x, box.size.z) * 0.48
		cyl.height = box.size.y
		col.shape = cyl
	else:
		var bs := BoxShape3D.new()
		bs.size = box.size * Vector3(0.94, 1.0, 0.94)
		col.shape = bs
	col.position = prop.center
	prop.add_child(col)
	prop.mass = float(def.get("mass", 20.0))
	prop.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	prop.center_of_mass = Vector3(0.0, box.size.y * 0.4, 0.0)
	prop.collision_layer = Layers.PROPS
	prop.collision_mask = MASK
	prop.continuous_cd = prop.mass < 30.0
	prop.can_sleep = true
	# Every prop starts frozen: bolted ones until a hard hit, loose ones until the player comes near.
	prop.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	prop.freeze = true
	prop.parked = not prop.anchored
	prop.set_physics_process(false)
	prop._rng.randomize()
	return prop


## Box around every mesh under `model`, in the space of `space` (an ancestor of the meshes or the model itself).
static func bounds_of(model: Node3D, space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var nodes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		nodes.append(model)
	for node: Node in nodes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.transform
		var p := mi.get_parent() as Node3D
		while p != null and p != space:
			xf = p.transform * xf
			p = p.get_parent() as Node3D
		var a := xf * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


## Counts towards the Table (TABLE CLEARED %) and queues the fracture pattern so the first break does
## not have to wait for it.
func _ready() -> void:
	Progress.add_total_mass(mass)
	sleeping_state_changed.connect(_on_sleeping_state_changed)
	var structures := Game.structures as StructureManager
	if structures != null and maxf(size.x, maxf(size.y, size.z)) >= MIN_FRACTURE_SIZE:
		if not Game.lite:
			structures.fracture.prewarm(_fracture_size(), D.Shape.BOX, material_name)


func is_broken() -> bool:
	return _broken


## Freezes a loose prop that has come to rest (see `parked`).
func park() -> void:
	if _broken or parked or (anchored and not _unbolted):
		return
	parked = true
	freeze = true


func unpark() -> void:
	if not parked:
		return
	parked = false
	freeze = false
	sleeping = true


## True where the terrain has collision: within the streaming range around the player.
func has_ground() -> bool:
	return Game.player == null or Game.player.global_position.distance_to(global_position) < GROUND_RANGE


func is_wreck() -> bool:
	return _wrecked


## Saved games: the prop was gone when the game was saved. It goes now, without debris or sound.
func restore_broken() -> void:
	if _broken:
		return
	_broken = true
	Progress.add_destroyed_mass(mass)
	queue_free()


## Saved games: the prop was a burnt-out wreck (charred, cold, its fuel spent).
func restore_wreck() -> void:
	if _wrecked or _broken:
		return
	_wrecked = true
	hp = max_hp
	blast = {}
	_char()
	Progress.add_destroyed_mass(mass * 0.5)


func receive_damage(hit: DamageHit, _user_id: int) -> void:
	if _broken:
		return
	if _wrecked and hit.cause_id == _break_cause:
		return   # the chain reaction that wrecked it does not also take the wreck apart
	var factor := 1.0
	match hit.kind:
		DamageHit.Kind.HEAT:
			factor = 0.5
		DamageHit.Kind.ACID:
			factor = 0.8
		DamageHit.Kind.SONIC:
			factor = 0.1
	var knocked := hit.kind == DamageHit.Kind.BLUNT and hit.impulse > 0.0 and mass < KNOCK_MASS and not anchored and has_ground()
	if not knocked:
		hp -= hit.energy * factor
	if freeze and has_ground():
		if anchored and not _unbolted:
			if hit.energy >= unbolt_energy or hp <= 0.0:
				_unbolted = true
				freeze = false
		else:
			parked = false
			freeze = false
		if not freeze:
			Timeline.prop_awake(self)
	if not freeze and hit.impulse > 0.0:
		var dir := hit.direction
		if dir == Vector3.ZERO:
			dir = (global_transform * center - hit.position).normalized()
		sleeping = false
		apply_impulse(dir * minf(hit.impulse, mass * MAX_PUSH_SPEED), hit.position - global_position)
	if hp <= 0.0:
		_begin_break(hit.direction, hit.cause_id, hit.source)
	elif hit.kind == DamageHit.Kind.BLUNT and hit.energy > 400.0:
		Audio.play_3d(SOUNDS.get(MaterialDB.base_of(material_name), &"impact_concrete"), hit.position, clampf(hit.energy / max_hp, 0.3, 1.0))


## A prop that slams into something at speed is hurt by its own crash (a thrown bin bursts on the wall).
## Only a loss of speed counts, so being thrown, swatted or blasted away is not a crash.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var v := state.linear_velocity
	var loss := _prev_v.length() - v.length()
	var was := _prev_v
	_prev_v = v
	if loss > (FRAGILE_CRASH_DV if fragile else CRASH_DV) and not _broken:
		hp -= 0.5 * mass * loss * loss * crash_scale
		if hp <= 0.0:
			_begin_break.call_deferred(was.normalized(), 0, null)


func _begin_break(dir: Vector3, cause: int, source: Node) -> void:
	if _broken:
		return
	_broken = true
	_break_dir = dir
	_break_cause = cause if cause != 0 else DamageRouter.new_cause_id()
	_break_source = source
	_break_wait = 0.0
	set_physics_process(true)
	_try_break()


## The pattern may still be on a worker thread: keep asking for a few ticks, then burst without pieces.
func _physics_process(delta: float) -> void:
	if _broken:
		_break_wait += delta
		_try_break()
	elif _smoke_left > 0.0:
		_smoke(delta)
	else:
		set_physics_process(false)


func _try_break() -> void:
	if wreck and not _wrecked:
		_become_wreck()
		return
	if _fire_loop >= 0:
		Audio.stop_loop(_fire_loop)
		_fire_loop = -1
	var structures := Game.structures as StructureManager
	var debris := Game.debris as DebrisManager
	var big := maxf(size.x, maxf(size.y, size.z)) >= MIN_FRACTURE_SIZE
	var pattern: FractureLibrary.Pattern = null
	# Far from the player there is no ground for the pieces to land on: dust and chips only.
	if big and structures != null and debris != null and has_ground():
		pattern = structures.fracture.get_pattern(_fracture_size(), D.Shape.BOX, material_name, 4, true)
		if pattern == null and _break_wait < 0.25:
			return
	var xf := global_transform * Transform3D(Basis.IDENTITY, center)
	var lin := linear_velocity
	if pattern != null:
		# The pattern is that of a smaller box (see _fracture_size): its pieces are moved apart again so
		# they start spread over the whole prop, with air between them.
		var spread := 1.0 / _shrink() - 1.0
		var total := maxf(pattern.volume, 0.0001)
		for cell in pattern.cells:
			var m := maxf(mass * cell.volume / total, 0.3)
			var away := (xf.basis * cell.centroid).normalized()
			var v := lin + _break_dir * _rng.randf_range(1.0, 3.5) + away * _rng.randf_range(0.5, 2.5) + Vector3.UP * _rng.randf_range(0.3, 1.8)
			var spin := Vector3(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0))
			var tier := DebrisManager.T2 if (m < 40.0 or cell.max_extent < 0.3) else DebrisManager.T1
			debris.spawn_piece(cell.mesh, cell.shape, xf * Transform3D(Basis.IDENTITY, cell.centroid * spread), cell.centroid, m, v, spin, tier, material_name, _break_cause)
	if structures != null and structures.fx != null:
		var strength := clampf(mass / 400.0, 0.15, 1.0)
		structures.fx.dust(xf.origin, size, material_name, strength)
		structures.fx.chips(xf.origin, size * 0.6, material_name, strength, _break_dir * 2.0 + lin)
	Audio.play_3d(SOUNDS.get(MaterialDB.base_of(material_name), &"impact_concrete"), xf.origin, 1.0)
	if mass > 150.0:
		Audio.play_3d(&"collapse_small", xf.origin, clampf(mass / 800.0, 0.4, 1.0))
	Progress.add_destroyed_mass(mass * (0.5 if _wrecked else 1.0))
	Progress.report_break()
	Timeline.record_prop(self, &"break", global_transform)
	broken.emit(self)
	if blast.is_empty():
		_retire()
		return
	# Fuel and gas go off a moment after the shell gives way; neighbours then follow one by one.
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	set_physics_process(false)
	var at := xf.origin
	var hit := DamageHit.blast(at, float(blast.get("radius", 5.0)), float(blast.get("energy", 1.5e6)), float(blast.get("impulse", 5000.0)), DamageHit.Kind.EXPLOSION, _break_source if is_instance_valid(_break_source) else null)
	hit.cause_id = _break_cause
	get_tree().create_timer(BLAST_DELAY, false, true).timeout.connect(func() -> void:
		if not _broken:
			return   # rewound before the blast
		DamageRouter.apply_blast(hit)
		_retire())


## First death of a vehicle: the fuel goes off, the shell is thrown, charred and left burning.
func _become_wreck() -> void:
	Timeline.record_prop(self, &"wreck", global_transform)
	_wrecked = true
	_broken = false
	hp = max_hp
	_smoke_left = WRECK_SMOKE_SECONDS
	_smoke_tick = 0.0
	_char()
	var at := global_transform * center
	Audio.play_3d(&"car_crash", at, 1.0)
	_fire_loop = Audio.start_loop(&"fire_loop", self)
	Progress.add_destroyed_mass(mass * 0.5)
	Progress.report_break(2)
	wrecked.emit(self)
	if freeze and has_ground():
		parked = false
		freeze = false
	if not freeze:
		sleeping = false
		apply_central_impulse(Vector3(_rng.randf_range(-1.0, 1.0), 3.2, _rng.randf_range(-1.0, 1.0)) * mass)
		apply_torque_impulse(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)) * mass * 1.5)
	if blast.is_empty():
		return
	var hit := DamageHit.blast(at, float(blast.get("radius", 6.0)), float(blast.get("energy", 3.0e6)), float(blast.get("impulse", 9000.0)), DamageHit.Kind.EXPLOSION, _break_source if is_instance_valid(_break_source) else null)
	hit.cause_id = _break_cause
	blast = {}
	get_tree().create_timer(BLAST_DELAY, false, true).timeout.connect(func() -> void: DamageRouter.apply_blast(hit))


## Smoke and, for the first part, flames from a wreck.
func _smoke(delta: float) -> void:
	_smoke_left -= delta
	_smoke_tick -= delta
	var k := clampf(_smoke_left / WRECK_SMOKE_SECONDS, 0.0, 1.0)
	if k < 0.45 and _fire_loop >= 0:
		Audio.stop_loop(_fire_loop)
		_fire_loop = -1
	if _smoke_tick > 0.0:
		return
	_smoke_tick = 0.14
	var fx := WorldFX.instance
	if fx == null:
		return
	var at := global_transform * (center + Vector3(_rng.randf_range(-0.3, 0.3) * size.x, size.y * 0.3, _rng.randf_range(-0.3, 0.3) * size.z))
	fx.puff(at, Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(1.2, 2.2), _rng.randf_range(-0.3, 0.3)), Color(0.07, 0.065, 0.06, 0.25 + 0.45 * k), _rng.randf_range(2.5, 4.5), 0.8, _rng.randf_range(2.2, 3.6))
	if k > 0.55:
		fx.flame(at, Vector3.UP * _rng.randf_range(0.8, 1.6), _rng.randf_range(0.4, 0.8), 0.7, 0.25, Color(1.0, 0.5, 0.14, 0.55))


## A broken prop is not freed at once: it waits out of the world for the rewind window (Timeline frees
## it), so a rewind can put it back.
func _retire() -> void:
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	set_physics_process(false)
	Timeline.retire_prop(self)


## World rewind: whole again where it was when it broke.
func unbreak(xf: Transform3D) -> void:
	if not _broken:
		return
	_broken = false
	hp = max_hp
	blast = _blast_def.duplicate()
	Progress.remove_destroyed_mass(mass * (0.5 if _wrecked else 1.0))
	visible = true
	collision_layer = Layers.PROPS
	collision_mask = MASK
	freeze = true
	parked = not anchored
	global_transform = xf
	reset_physics_interpolation()
	set_physics_process(_smoke_left > 0.0)


## World rewind: the car was never burnt.
func unwreck() -> void:
	if not _wrecked or _broken:
		return
	_wrecked = false
	hp = max_hp
	blast = _blast_def.duplicate()
	_smoke_left = 0.0
	if _fire_loop >= 0:
		Audio.stop_loop(_fire_loop)
		_fire_loop = -1
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, null)
	Progress.remove_destroyed_mass(mass * 0.5)


func _on_sleeping_state_changed() -> void:
	if not sleeping and not freeze:
		Timeline.prop_awake(self)


## Every surface gets a darkened copy of its own material (same shader, so nothing is compiled).
func _char() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var source := mi.get_active_material(s) as BaseMaterial3D
			if source == null:
				continue
			var burnt := _charred.get(source) as BaseMaterial3D
			if burnt == null:
				burnt = source.duplicate() as BaseMaterial3D
				burnt.albedo_color = Color(source.albedo_color.r * 0.14, source.albedo_color.g * 0.13, source.albedo_color.b * 0.12, source.albedo_color.a)
				burnt.roughness = 1.0
				_charred[source] = burnt
			mi.set_surface_override_material(s, burnt)


## How much smaller than the prop the fractured box is, per axis: a prop that is mostly air (a bench,
## a cart) must not turn into its whole bounding box of solid rubble.
func _shrink() -> float:
	return clampf(pow(solid_fraction, 1.0 / 3.0) * 1.15, 0.45, 1.0)


## Patterns are cached per size: sizes are rounded so that props of one kind share one pattern.
func _fracture_size() -> Vector3:
	var s := size * _shrink()
	return Vector3(maxf(snappedf(s.x, 0.1), 0.2), maxf(snappedf(s.y, 0.1), 0.2), maxf(snappedf(s.z, 0.1), 0.2))
