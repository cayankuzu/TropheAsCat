class_name ScorchDecals
extends Node3D
## A ring of pooled Decals for marks left on surfaces: soot with an optional cooling glow (explosions,
## laser melt spots) and glowing wet splats (acid residue, slime). The oldest mark is recycled when the
## ring is full. Marks whose surface has gone (wall destroyed, ground dug away) fade out instead of
## hanging in the air: a few are checked with a ray every second.

const HOT := Color(1.0, 0.42, 0.1)
## Render layer 2 holds the cat (see CatPlayer.CAT_RENDER_LAYER); marks never project onto it.
const CULL_MASK := 0xFFFFF & ~(1 << 1)
const DEPTH := 0.7
const ORPHAN_FADE := 0.5

@export var pool_size := 56
## Soot fades away this many seconds after it was made (0 = stays until recycled).
@export var scorch_seconds := 120.0
@export var orphan_checks_per_second := 8.0

var placed := 0
var orphaned := 0

var _decals: Array[Decal] = []
var _alive := PackedByteArray()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()          # total seconds, 0 = until recycled
var _fade := PackedFloat32Array()          # seconds of the final fade-out
var _alpha := PackedFloat32Array()         # albedo strength at full
var _glow := PackedFloat32Array()          # emission energy at birth
var _glow_seconds := PackedFloat32Array()
var _glow_age := PackedFloat32Array()
var _normal := PackedVector3Array()
var _next := 0
var _check := 0
var _check_debt := 0.0
var _active := 0
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_ray.collision_mask = Layers.SOLID
	for i in pool_size:
		var d := Decal.new()
		d.name = "Mark%d" % i
		d.visible = false
		d.cull_mask = CULL_MASK
		d.upper_fade = 0.35
		d.lower_fade = 0.35
		d.normal_fade = 0.35
		d.distance_fade_enabled = true
		d.distance_fade_begin = 90.0
		d.distance_fade_length = 25.0
		d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(d)
		_decals.append(d)
		_alive.append(0)
		_age.append(0.0)
		_life.append(0.0)
		_fade.append(1.0)
		_alpha.append(1.0)
		_glow.append(0.0)
		_glow_seconds.append(0.0)
		_glow_age.append(0.0)
		_normal.append(Vector3.UP)


func active_count() -> int:
	return _active


## Soot mark of `radius` metres on the surface at pos. heat > 0 adds a glow of that emission energy
## that cools over glow_seconds. Returns a handle for reheat().
func scorch(pos: Vector3, normal: Vector3, radius: float, heat: float = 0.0, glow_color: Color = HOT, glow_seconds: float = 2.5) -> int:
	var i := _take(pos, normal, radius)
	var d := _decals[i]
	d.texture_albedo = FxTextures.scorch()
	d.texture_emission = FxTextures.glow() if heat > 0.0 else null
	d.modulate = Color(glow_color.r, glow_color.g, glow_color.b, 1.0) if heat > 0.0 else Color.WHITE
	d.albedo_mix = 1.0
	d.emission_energy = heat
	_life[i] = scorch_seconds
	_fade[i] = 6.0
	_alpha[i] = 1.0
	_glow[i] = heat
	_glow_seconds[i] = maxf(glow_seconds, 0.05)
	_glow_age[i] = 0.0
	return i


## Keeps a mark made by scorch() glowing (a beam dwelling on one spot) and lets it grow to `radius`.
func reheat(handle: int, heat: float, radius: float) -> void:
	if handle < 0 or handle >= _decals.size() or _alive[handle] == 0:
		return
	var d := _decals[handle]
	if d.texture_emission == null:
		d.texture_emission = FxTextures.glow()
	_glow[handle] = maxf(heat, _glow[handle])
	_glow_age[handle] = 0.0
	_age[handle] = 0.0
	d.emission_energy = _glow[handle]
	var want := radius * 2.0
	if want > d.size.x:
		d.size = Vector3(want, DEPTH, want)


## Wet glowing splat (acid residue, slime) that dims over glow_seconds and is gone after `seconds`.
func splat(pos: Vector3, normal: Vector3, radius: float, color: Color, glow: float = 1.5, seconds: float = 6.0, glow_seconds: float = 3.0) -> int:
	var i := _take(pos, normal, radius)
	var d := _decals[i]
	d.texture_albedo = FxTextures.splat()
	d.texture_emission = FxTextures.splat_glow() if glow > 0.0 else null
	d.modulate = Color(color.r, color.g, color.b, 1.0)
	d.albedo_mix = 0.9
	d.emission_energy = glow
	_life[i] = seconds
	_fade[i] = minf(2.0, seconds * 0.4)
	_alpha[i] = 0.9
	_glow[i] = glow
	_glow_seconds[i] = maxf(glow_seconds, 0.05)
	_glow_age[i] = 0.0
	return i


func _take(pos: Vector3, normal: Vector3, radius: float) -> int:
	var i := _next
	_next = (_next + 1) % _decals.size()
	if _alive[i] == 0:
		_active += 1
	_alive[i] = 1
	_age[i] = 0.0
	placed += 1
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	_normal[i] = n
	var d := _decals[i]
	# The decal projects along its local -Y: Y = surface normal, random roll around it.
	var x := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
	var b := Basis(x, n, x.cross(n)).rotated(n, randf() * TAU)
	d.global_transform = Transform3D(b, pos)
	d.size = Vector3(radius * 2.0, DEPTH, radius * 2.0)
	d.visible = true
	return i


func _process(delta: float) -> void:
	if _active == 0:
		return
	for i in _decals.size():
		if _alive[i] == 0:
			continue
		var d := _decals[i]
		_age[i] += delta
		if _glow[i] > 0.0:
			_glow_age[i] += delta
			var k := 1.0 - _glow_age[i] / _glow_seconds[i]
			if k <= 0.0:
				_glow[i] = 0.0
				d.emission_energy = 0.0
				d.texture_emission = null
			else:
				d.emission_energy = _glow[i] * k * k
		if _life[i] > 0.0:
			var left := _life[i] - _age[i]
			if left <= 0.0:
				_alive[i] = 0
				_active -= 1
				d.visible = false
			elif left < _fade[i]:
				d.albedo_mix = _alpha[i] * left / _fade[i]
	_check_orphans(delta)


func _check_orphans(delta: float) -> void:
	_check_debt += orphan_checks_per_second * delta
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	while _check_debt >= 1.0:
		_check_debt -= 1.0
		_check = (_check + 1) % _decals.size()
		var i := _check
		if _alive[i] == 0 or _age[i] < 0.5:
			continue
		if _life[i] > 0.0 and _life[i] - _age[i] <= ORPHAN_FADE:
			continue
		var p := _decals[i].global_position
		_ray.from = p + _normal[i] * 0.3
		_ray.to = p - _normal[i] * 0.4
		if space.intersect_ray(_ray).is_empty():
			# Nothing left to sit on: finish with a quick fade.
			orphaned += 1
			_life[i] = _age[i] + ORPHAN_FADE
			_fade[i] = ORPHAN_FADE
