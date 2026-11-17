class_name WorldFX
extends Node3D
## The world's shared effect layers: sparks, smoke, flames and wet blobs (one draw call each), pooled
## flash lights and surface marks. The composition root adds one; everything else reaches it through
## WorldFX.instance and must cope with null (headless tests run without it).
## Every EXPLOSION blast announced by DamageRouter gets its fireball here, so weapons only add their
## own flavour (trails, muzzle effects, wall marks).

const SPARK_SHADER := preload("res://game/fx/fx_spark.gdshader")
const SMOKE_SHADER := preload("res://game/fx/fx_smoke.gdshader")
const FIRE_SHADER := preload("res://game/fx/fx_fire.gdshader")
const BLOB_SHADER := preload("res://game/fx/fx_blob.gdshader")

const FIRE := Color(1.0, 0.5, 0.14, 1.0)
const EMBER := Color(1.0, 0.58, 0.2, 3.0)
const SOOT := Color(0.09, 0.085, 0.08, 0.75)
const ACID := Color(0.42, 0.95, 0.12)

## Blasts weaker than this are thumps (a landing, a dropped slab), not fireballs.
const FIREBALL_MIN_ENERGY := 4.0e4

static var instance: WorldFX = null

var sparks: FxLayer
var smoke: FxLayer
var fire: FxLayer
var blobs: FxLayer
var lights: LightFlashPool
var marks: ScorchDecals
var shield: CatProofFX

var explosions := 0

var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var noise := FxTextures.noise()
	sparks = FxLayer.create("Sparks", 2048, 1.8, {"gravity": Vector3(0.0, -9.8, 0.0), "drag": 0.5, "stretch": 0.03}, _quad(_material(SPARK_SHADER, {})), false)
	smoke = FxLayer.create("Smoke", 1024, 6.0, {"gravity": Vector3(0.0, 0.7, 0.0), "drag": 1.6, "size_ease": 0.45, "wander": 0.9}, _quad(_material(SMOKE_SHADER, {"noise_tex": noise})), true)
	fire = FxLayer.create("Fire", 1024, 1.6, {"gravity": Vector3(0.0, 2.4, 0.0), "drag": 2.2, "size_ease": 0.5, "wander": 1.6}, _quad(_material(FIRE_SHADER, {"noise_tex": noise, "energy": 2.0})), false)
	# No drag: a blob follows the exact parabola its emitter computed (the acid stream relies on it).
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 10
	ball.rings = 5
	ball.material = _material(BLOB_SHADER, {})
	blobs = FxLayer.create("Blobs", 1024, 3.0, {"gravity": Vector3(0.0, -9.8, 0.0), "drag": 0.0, "stretch": 0.012}, ball, false)
	for layer: FxLayer in [smoke, blobs, sparks, fire]:
		add_child(layer)
	lights = LightFlashPool.new()
	lights.name = "Flashes"
	add_child(lights)
	marks = ScorchDecals.new()
	marks.name = "Marks"
	marks.pool_size = 96
	add_child(marks)
	shield = CatProofFX.new()
	shield.name = "CatProof"
	add_child(shield)
	DamageRouter.blast.connect(_on_blast)
	# Build every procedural texture now, while the world loads, instead of on the first mark in play.
	FxTextures.scorch()
	FxTextures.glow()
	FxTextures.splat()
	FxTextures.splat_glow()


## Fireball of about `radius` metres: flash, flames, sparks, rising smoke and a soot mark on the ground.
func explosion(pos: Vector3, radius: float) -> void:
	explosions += 1
	var r := clampf(radius, 0.5, 14.0)
	lights.flash(pos + Vector3.UP * 0.4, Color(1.0, 0.62, 0.28), 4.0 + r * 2.5, r * 4.0, 0.5)
	# One short white-hot flash, then fewer and dimmer flame puffs than would saturate to white: the
	# fireball has to stay orange and show its shape.
	fire.emit(pos, Vector3.ZERO, Color(1.0, 0.8, 0.5, 1.0), 0.16, r * 0.8, r * 1.7)
	for i in clampi(int(r * 4.0), 8, 32):
		var d := _dir(0.35)
		fire.emit(pos + d * r * 0.15, d * r * _rng.randf_range(1.2, 3.6), Color(FIRE.r, FIRE.g, FIRE.b, 0.6), _rng.randf_range(0.35, 0.95), r * _rng.randf_range(0.2, 0.38), r * _rng.randf_range(0.5, 0.85))
	for i in clampi(int(r * 9.0), 12, 90):
		sparks.emit(pos, _dir(0.5) * _rng.randf_range(5.0, 11.0 + r * 2.0), EMBER, _rng.randf_range(0.5, 1.5), 0.05, 0.02)
	for i in clampi(int(r * 4.5), 6, 36):
		var d := _dir(0.6)
		smoke.emit(pos + d * r * 0.3, d * r * _rng.randf_range(0.5, 1.6) + Vector3.UP * _rng.randf_range(0.5, 2.0), SOOT, _rng.randf_range(2.4, 5.0), r * 0.5, r * _rng.randf_range(1.1, 1.8))
	var ground := _ray(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * maxf(r * 0.8, 1.0))
	if not ground.is_empty():
		marks.scorch(ground["position"], ground["normal"], r * 0.75, 2.5)


## Sparks thrown off a surface (beam contact, metal struck).
func spark_burst(pos: Vector3, normal: Vector3, count: int, speed: float = 7.0, color: Color = EMBER) -> void:
	for i in count:
		var d := (normal * 0.9 + _dir(0.0)).normalized()
		sparks.emit(pos, d * speed * _rng.randf_range(0.4, 1.3), color, _rng.randf_range(0.25, 0.9), 0.035, 0.012)


## One soft lit puff (steam, fumes, dust, fur). color.a is its peak opacity.
func puff(pos: Vector3, velocity: Vector3, color: Color, life: float, size_start: float, size_end: float) -> void:
	smoke.emit(pos, velocity, color, life, size_start, size_end)


## One additive flame puff. color.a scales its brightness.
func flame(pos: Vector3, velocity: Vector3, life: float, size_start: float, size_end: float, color: Color = FIRE) -> void:
	fire.emit(pos, velocity, color, life, size_start, size_end)


## Wet droplets thrown off a surface (acid, slime, fur bits). glow is their emission strength.
func splash(pos: Vector3, normal: Vector3, count: int, color: Color, glow: float = 0.6, speed: float = 3.5) -> void:
	for i in count:
		var d := (normal + _dir(0.2) * 0.9).normalized()
		blobs.emit(pos + normal * 0.05, d * speed * _rng.randf_range(0.4, 1.2), Color(color.r, color.g, color.b, glow), _rng.randf_range(0.4, 1.1), _rng.randf_range(0.04, 0.09), 0.02)


func _on_blast(hit: DamageHit) -> void:
	if hit.kind == DamageHit.Kind.EXPLOSION and hit.energy >= FIREBALL_MIN_ENERGY:
		explosion(hit.position, hit.radius * 0.55)


## Random unit vector; up_bias 0 = any direction, 1 = upper hemisphere only.
func _dir(up_bias: float) -> Vector3:
	var v := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	if v.length_squared() < 0.0001:
		return Vector3.UP
	v = v.normalized()
	v.y = lerpf(v.y, absf(v.y), up_bias)
	return v.normalized()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.TERRAIN | Layers.STRUCTURE | Layers.RUBBLE)
	return world.direct_space_state.intersect_ray(q)


static func _material(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for key: String in params:
		m.set_shader_parameter(key, params[key])
	return m


static func _quad(material: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = material
	return q
