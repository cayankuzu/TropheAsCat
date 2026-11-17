class_name LaserDotTool
extends CatTool
## Tool 2, the Laser Dot. The Owner's laser pointer was meant to keep Trophe busy; she finally caught
## the dot. While the tool is out a harmless red dot follows the crosshair. Holding primary turns it
## into a heat beam from her eyes: HEAT hits at tick_hz on whatever the dot touches (cuts columns, pops
## glass, drills the ground), with sparks, a glowing melt mark and a flash at the contact.

const BEAM_RANGE := 140.0   ## inside DamageRouter.REACH
const RED := Color(1.0, 0.1, 0.05)
const MELT := Color(1.0, 0.36, 0.14)

@export var energy_per_tick := 9000.0     ## Joules of HEAT per tick (structures take half of it).
@export var impulse_per_tick := 40.0
@export var tick_hz := 12.0
@export var mark_spacing := 0.45          ## A new melt mark is laid when the dot has moved this far.

var ticks := 0
var energy_dealt := 0.0

var _firing := false
var _tick_left := 0.0
var _cause := 0
var _loop := -1
var _mark := -1
var _mark_pos := Vector3.INF
var _smoke_toggle := false

var _rig: Node3D            # holds the visuals; lives in world space
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _dot: MeshInstance3D
var _dot_material: StandardMaterial3D

# Result of the last _aim(): where the beam starts, where it ends and what it ends on.
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _normal := Vector3.UP
var _on_surface := false
var _collider: Object = null
var _rid := RID()


func _init() -> void:
	tool_name = "Laser Dot"
	tool_id = &"laser"


func _ready() -> void:
	_build_visuals()
	set_process(false)


func equip(owner_cat: CatPlayer) -> void:
	super(owner_cat)
	set_process(true)


func unequip() -> void:
	_stop()
	super()
	set_process(false)
	_rig.visible = false


func primary(pressed: bool) -> void:
	if pressed and not _firing and cat != null:
		_firing = true
		_tick_left = 0.0
		_cause = DamageRouter.new_cause_id()
		Audio.play_3d(&"laser_zap", cat.get_eye_position(), 1.0)
		_loop = Audio.start_loop(&"laser_loop", _dot)
	elif not pressed:
		_stop()


func is_firing() -> bool:
	return _firing


func process(delta: float) -> void:
	if not _firing:
		return
	cat.hold_aim_stance(0.3)
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left += 1.0 / tick_hz
	_aim()
	if not _on_surface:
		return
	ticks += 1
	energy_dealt += energy_per_tick
	var hit := DamageHit.point(_to, (_to - _from).normalized(), energy_per_tick, impulse_per_tick, DamageHit.Kind.HEAT, cat)
	hit.normal = _normal
	hit.cause_id = _cause
	var pos := _to
	var normal := _normal
	deliver(hit, _collider, _rid)
	_contact_fx(pos, normal)


## Visuals follow the rendered frame, not the physics tick.
func _process(_delta: float) -> void:
	if cat == null or not equipped:
		return
	_aim()
	_rig.visible = true
	var dist := _from.distance_to(_to)
	_dot.visible = _on_surface
	if _on_surface:
		# The dot keeps a readable size far away; it swells and brightens while it burns.
		var size := maxf(0.07, dist * 0.006) * (2.4 if _firing else 1.0)
		_dot.global_transform = Transform3D(_facing_basis(_normal) * Basis.from_scale(Vector3.ONE * size), _to + _normal * 0.02)
		_dot_material.albedo_color = Color(4.0, 0.5, 0.3) if _firing else Color(1.6, 0.12, 0.08)
	_core.visible = _firing
	_halo.visible = _firing
	if _firing and dist > 0.05:
		var flicker := 1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.06)
		_core.global_transform = _beam_transform(_from, _to, 0.006 * flicker)
		_halo.global_transform = _beam_transform(_from, _to, 0.022 * flicker)


func _stop() -> void:
	if not _firing:
		return
	_firing = false
	Audio.stop_loop(_loop)
	_loop = -1
	_mark = -1
	_mark_pos = Vector3.INF


## The beam leaves the eyes, not the camera: whatever stands between the eyes and the crosshair point
## stops it first.
func _aim() -> void:
	_from = cat.get_eye_position()
	var target := crosshair_point(BEAM_RANGE)
	var dir := (target - _from).normalized()
	var hit := trace(_from, target + dir * 0.4)
	_on_surface = not hit.is_empty()
	if _on_surface:
		_to = hit["position"]
		_normal = hit["normal"]
		_collider = hit.get("collider")
		_rid = hit.get("rid", RID())
	else:
		_to = target
		_normal = -dir
		_collider = null
		_rid = RID()


func _contact_fx(pos: Vector3, normal: Vector3) -> void:
	var fx := WorldFX.instance
	if fx == null:
		return
	fx.spark_burst(pos, normal, 5, 6.0)
	fx.lights.flash(pos + normal * 0.2, MELT, 2.2, 5.0, 0.22)
	_smoke_toggle = not _smoke_toggle
	if _smoke_toggle:
		fx.puff(pos + normal * 0.1, normal * 0.6 + Vector3.UP * 0.9, Color(0.2, 0.19, 0.18, 0.5), 1.6, 0.25, 0.9)
	if _mark >= 0 and pos.distance_to(_mark_pos) < mark_spacing:
		fx.marks.reheat(_mark, 3.0, 0.34)
	else:
		_mark = fx.marks.scorch(pos, normal, 0.24, 3.0, MELT, 1.8)
		_mark_pos = pos


func _build_visuals() -> void:
	_rig = Node3D.new()
	_rig.name = "LaserRig"
	_rig.top_level = true
	_rig.visible = false
	_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_rig)
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.0
	tube.height = 1.0
	tube.radial_segments = 8
	tube.rings = 0
	tube.cap_top = false
	tube.cap_bottom = false
	_core = _beam_part(tube, Color(5.0, 2.6, 2.0, 1.0))
	_halo = _beam_part(tube, Color(2.2, 0.16, 0.08, 0.55))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_dot_material = _glow_material(Color(1.6, 0.12, 0.08))
	_dot_material.albedo_texture = FxTextures.glow()
	_dot = MeshInstance3D.new()
	_dot.name = "Dot"
	_dot.mesh = quad
	_dot.material_override = _dot_material
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dot.top_level = true
	_rig.add_child(_dot)


func _beam_part(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _glow_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	_rig.add_child(mi)
	return mi


static func _glow_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.disable_fog = true
	return m


## Unit cylinder (Y axis) stretched from a to b with the given radius.
static func _beam_transform(a: Vector3, b: Vector3, radius: float) -> Transform3D:
	var y := b - a
	var length := y.length()
	var yn := y / length
	var x := yn.cross(Vector3.UP if absf(yn.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(yn)
	return Transform3D(Basis(x * radius, yn * length, z * radius), (a + b) * 0.5)


## Basis whose +Z looks along the normal (a QuadMesh faces +Z).
static func _facing_basis(normal: Vector3) -> Basis:
	var z := normal.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.99 else Vector3.RIGHT).normalized()
	return Basis(x, z.cross(x), z)
