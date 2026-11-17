class_name WizardHatTool
extends CatTool
## Tool 3, the Wizard Hat. The Owner dressed Trophe up for a cute photo; the hat turned out to work.
## Hold primary to gather a fireball between the front paws (up to charge_time), release to cast it at
## the crosshair: a tap is a small firebolt, a full charge levels a house front.

const CAST_RANGE := 220.0
const HAT_SCALE := 1.3

@export var charge_time := 1.1
@export var cooldown := 0.3
@export var speed := 42.0
@export var blast_radius := Vector2(4.0, 9.0)        ## metres, tap .. full charge
@export var blast_energy := Vector2(1.5e6, 9.0e6)    ## joules
@export var blast_impulse := Vector2(4000.0, 14000.0)

var casts := 0
var last_fireball: Fireball = null

var _charging := false
var _charge := 0.0
var _cooldown_left := 0.0
var _hat: Node3D = null
var _glow_tick := 0


func _init() -> void:
	tool_name = "Wizard Hat"
	tool_id = &"wizard_hat"


## The hat is built with the world, not on first use: its two new material variants cost a shader
## compile that would otherwise freeze the first equip for a fifth of a second.
func _ready() -> void:
	var belt := get_parent() as ToolBelt
	if belt != null and belt.cat != null:
		_attach_hat(belt.cat)


func equip(owner_cat: CatPlayer) -> void:
	super(owner_cat)
	_attach_hat(cat)
	if _hat != null:
		_hat.visible = true


func unequip() -> void:
	_charging = false
	_charge = 0.0
	if _hat != null:
		_hat.visible = false
	super()


func _exit_tree() -> void:
	if _hat != null and is_instance_valid(_hat):
		_hat.queue_free()
		_hat = null


func primary(pressed: bool) -> void:
	if cat == null:
		return
	if pressed:
		if _cooldown_left <= 0.0 and not _charging:
			_charging = true
			_charge = 0.0
	elif _charging:
		_cast()


## Charging does not lock the belt: switching away simply lets the fire go out.
func get_charge() -> float:
	return _charge if _charging else 0.0


func process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not _charging:
		return
	_charge = minf(_charge + delta / charge_time, 1.0)
	cat.hold_aim_stance(0.4, true)
	var fx := WorldFX.instance
	if fx == null:
		return
	var p := _hands()
	var size := lerpf(0.05, 0.2, _charge)
	fx.flame(p + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * size * 0.3, Vector3.UP * 0.2, randf_range(0.12, 0.22), size, size * 0.5, Color(1.0, 0.5, 0.14, 0.5))
	_glow_tick += 1
	if _glow_tick % 4 == 0:
		fx.lights.flash(p, Color(1.0, 0.6, 0.25), 0.5 + 1.5 * _charge, 2.5 + 2.0 * _charge, 0.18)
	if _charge >= 1.0 and _glow_tick % 3 == 0:
		fx.sparks.emit(p, Vector3(randf() - 0.5, randf(), randf() - 0.5) * 3.0, WorldFX.EMBER, 0.5, 0.03, 0.01)


func _cast() -> void:
	_charging = false
	_cooldown_left = cooldown
	casts += 1
	var k := _charge
	_charge = 0.0
	var origin := _hands()
	var dir := (crosshair_point(CAST_RANGE) - origin).normalized()
	var ball := Fireball.new()
	ball.name = "Fireball"
	ball.source = cat
	ball.velocity = dir * speed
	ball.blast_radius = lerpf(blast_radius.x, blast_radius.y, k)
	ball.energy = lerpf(blast_energy.x, blast_energy.y, k)
	ball.impulse = lerpf(blast_impulse.x, blast_impulse.y, k)
	ball.visual_radius = lerpf(0.16, 0.42, k)
	cat.get_parent().add_child(ball)
	ball.global_position = origin + dir * 0.2
	ball.reset_physics_interpolation()
	last_fireball = ball
	cat.hold_aim_stance(0.45)
	cat.play_cast_thrust(0.35)
	if cat.camera != null:
		cat.camera.add_trauma(0.12 + 0.2 * k)
	Audio.play_3d(&"fire_whoosh", origin, 0.7 + 0.5 * k)
	var fx := WorldFX.instance
	if fx != null:
		fx.lights.flash(origin, Color(1.0, 0.62, 0.28), 3.0 + 3.0 * k, 6.0, 0.25)
		for i in 6:
			fx.flame(origin, dir * randf_range(2.0, 6.0) + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0, randf_range(0.2, 0.4), 0.25, 0.08, Color(1.0, 0.5, 0.14, 0.7))


func _attach_hat(wearer: CatPlayer) -> void:
	if _hat == null and wearer.head_socket != null:
		_hat = _build_hat()
		_hat.visible = false
		wearer.head_socket.add_child(_hat)


## The spot between the front paws where the fire gathers.
func _hands() -> Vector3:
	return cat.get_chest_position() + cat.get_facing() * 0.28 - Vector3.UP * 0.06


## Pointed hat with a bent tip, a brim and a gold band, built in head-bone space (model units):
## +Y runs to the nose, +Z out of the top of the skull, so the hat's own +Y is turned onto +Z and
## tipped a little backwards.
func _build_hat() -> Node3D:
	var hat := Node3D.new()
	hat.name = "WizardHat"
	hat.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(100.0)).scaled(Vector3.ONE * HAT_SCALE), Vector3(0.0, 0.052, 0.082))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.13, 0.5)
	cloth.roughness = 0.9
	cloth.rim_enabled = true
	cloth.rim = 0.35
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.74, 0.25)
	gold.metallic = 0.7
	gold.roughness = 0.35
	_hat_part(hat, 0.072, 0.074, 0.006, Vector3(0.0, 0.0, 0.0), 0.0, cloth)        # brim
	_hat_part(hat, 0.018, 0.036, 0.085, Vector3(0.0, 0.045, 0.0), 0.0, cloth)      # crown
	_hat_part(hat, 0.0375, 0.0375, 0.014, Vector3(0.0, 0.011, 0.0), 0.0, gold)     # band
	_hat_part(hat, 0.0, 0.018, 0.07, Vector3(0.0, 0.116, -0.016), -28.0, cloth)    # bent tip
	return hat


func _hat_part(hat: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, tilt_deg: float, material: Material) -> void:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = 20
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.layers = CatPlayer.CAT_RENDER_LAYER
	mi.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(tilt_deg)), pos)
	hat.add_child(mi)
