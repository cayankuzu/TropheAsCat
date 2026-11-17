class_name Fireball
extends Node3D
## A wizard-hat fireball in flight: flies almost straight, leaves a trail of flame and smoke, and on the
## first solid thing it meets hands an EXPLOSION blast to DamageRouter (WorldFX, Audio and the camera
## all react to that blast on their own).

const GRAVITY := 2.5
const LIFETIME := 3.3   ## about 140 m at cast speed: inside DamageRouter.REACH, then it bursts in the air

var velocity := Vector3.ZERO
var blast_radius := 5.0
var energy := 3.0e6
var impulse := 6000.0
var visual_radius := 0.25
var source: Node = null

var exploded := false

var _age := 0.0
var _source_rid := RID()
var _trail := 0


func _ready() -> void:
	if source is CollisionObject3D:
		_source_rid = (source as CollisionObject3D).get_rid()
	var ball := SphereMesh.new()
	ball.radius = visual_radius
	ball.height = visual_radius * 2.0
	ball.radial_segments = 12
	ball.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(3.2, 1.7, 0.7)
	mat.disable_fog = true
	var mesh := MeshInstance3D.new()
	mesh.mesh = ball
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.0 + visual_radius * 8.0
	light.omni_range = 5.0 + visual_radius * 14.0
	light.shadow_enabled = false
	add_child(light)


func _physics_process(delta: float) -> void:
	if exploded:
		return
	_age += delta
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID)
	if _source_rid.is_valid():
		q.exclude = [_source_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_explode(hit["position"], hit["normal"])
		return
	global_position = to
	_emit_trail(from, to)
	if _age > LIFETIME or to.y < -70.0:
		_explode(to, Vector3.UP)


func _emit_trail(from: Vector3, to: Vector3) -> void:
	var fx := WorldFX.instance
	if fx == null:
		return
	var back := -velocity.normalized()
	for i in 2:
		var p := from.lerp(to, randf())
		fx.flame(p, back * 2.0 + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 1.5, randf_range(0.25, 0.5), visual_radius * 2.2, visual_radius * 0.6)
	_trail += 1
	if _trail % 2 == 0:
		fx.puff(from, back * 1.0, Color(0.13, 0.12, 0.11, 0.45), randf_range(1.0, 1.8), visual_radius * 1.6, visual_radius * 5.0)
	if _trail % 3 == 0:
		fx.sparks.emit(from, back * 3.0 + Vector3(randf() - 0.5, randf(), randf() - 0.5) * 4.0, WorldFX.EMBER, randf_range(0.4, 0.9), 0.04, 0.015)


func _explode(pos: Vector3, normal: Vector3) -> void:
	exploded = true
	# The centre sits just off the surface so the blast reaches what stands in front of it too.
	var hit := DamageHit.blast(pos + normal * 0.35, blast_radius, energy, impulse, DamageHit.Kind.EXPLOSION, source if is_instance_valid(source) else null)
	DamageRouter.apply_blast(hit)
	var fx := WorldFX.instance
	if fx != null and normal.y < 0.7:
		fx.marks.scorch(pos, normal, blast_radius * 0.45, 2.5)   # walls; WorldFX marks the ground itself
	queue_free()
