class_name HairballCannonTool
extends CatTool
## Tool 4, the Hairball Cannon. The Owner's vacuum robot fed Trophe every hair on the Table; she gives
## them back. Hold primary to cough up dense hairballs: real rigid bodies whose impacts become BLUNT
## hits (0.5*m*v^2) through ThrownBodyWatcher. A ball that has come to rest turns into a light prop
## the cat can pick up and throw; the oldest ones puff away when too many lie around.

const SHOT_RANGE := 200.0
const FUR := Color(0.44, 0.38, 0.32)
const REST_MASS := 6.0

@export var muzzle_speed := 55.0
@export var ball_mass := 180.0
@export var ball_radius := 0.3
@export var cooldown := 0.42
@export var max_alive := 16

var shots := 0
var last_ball: RigidBody3D = null

var _held := false
var _cooldown_left := 0.0
var _balls: Array[RigidBody3D] = []
var _born: Array[float] = []
var _time := 0.0

static var _mesh: SphereMesh = null
static var _shape: SphereShape3D = null
static var _physics: PhysicsMaterial = null


func _init() -> void:
	tool_name = "Hairball Cannon"
	tool_id = &"hairball"


## The fur material is built with the world, not on the first shot (a new material variant costs a
## shader compile); the hidden instance makes the renderer take it in right away.
func _ready() -> void:
	if _mesh == null:
		_build_shared()
	var warm := MeshInstance3D.new()
	warm.name = "Prewarm"
	warm.mesh = _mesh
	warm.visible = false
	add_child(warm)


func unequip() -> void:
	_held = false
	super()


func primary(pressed: bool) -> void:
	_held = pressed


func process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _held:
		cat.hold_aim_stance(0.3)
		if _cooldown_left <= 0.0:
			_fire()


## Runs whether or not the tool is equipped: balls already in the world still have to settle.
func _physics_process(delta: float) -> void:
	_time += delta
	var fx := WorldFX.instance
	for i in range(_balls.size() - 1, -1, -1):
		var b := _balls[i]
		if not is_instance_valid(b):
			_balls.remove_at(i)
			_born.remove_at(i)
			continue
		var age := _time - _born[i]
		# Past the reach of the world there is no ground under it any more.
		if cat != null and is_instance_valid(cat) and b.global_position.distance_to(cat.global_position) > DamageRouter.REACH:
			_poof(b)
			_balls.remove_at(i)
			_born.remove_at(i)
			continue
		if fx != null and age < 0.5:
			fx.puff(b.global_position, Vector3.ZERO, Color(FUR.r, FUR.g, FUR.b, 0.35), 0.7, ball_radius * 1.2, ball_radius * 2.4)
		# The watcher frees itself once the ball has slowed down: from then on it is just a ball of hair.
		if b.mass > REST_MASS and age > 0.3 and b.get_node_or_null(^"ThrownBodyWatcher") == null:
			b.mass = REST_MASS
			b.collision_layer = Layers.PROPS
	while _balls.size() > max_alive:
		_poof(_balls[0])
		_balls.remove_at(0)
		_born.remove_at(0)


func _fire() -> void:
	_cooldown_left = cooldown
	shots += 1
	var mouth := muzzle()
	var dir := (crosshair_point(SHOT_RANGE) - mouth).normalized()
	var spawn := mouth + dir * (ball_radius + 0.2)
	if not trace(cat.get_chest_position(), spawn + dir * ball_radius).is_empty():
		spawn = cat.get_chest_position()   # nose against a wall: the ball starts inside the cat instead
	var ball := _make_ball()
	cat.get_parent().add_child(ball)
	ball.global_position = spawn
	ball.linear_velocity = dir * muzzle_speed
	ball.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	ball.reset_physics_interpolation()
	ThrownBodyWatcher.attach(ball, cat)
	_balls.append(ball)
	_born.append(_time)
	last_ball = ball
	if cat.camera != null:
		cat.camera.add_trauma(0.2)
	Audio.play_3d(&"hairball_fire", mouth, 1.0)
	var fx := WorldFX.instance
	if fx != null:
		fx.puff(mouth + dir * 0.3, dir * 2.5, Color(FUR.r, FUR.g, FUR.b, 0.5), 0.8, 0.3, 1.1)


func _make_ball() -> RigidBody3D:
	if _mesh == null:
		_build_shared()
	_mesh.radius = ball_radius
	_mesh.height = ball_radius * 2.0
	_shape.radius = ball_radius
	var body := RigidBody3D.new()
	body.name = "Hairball"
	body.mass = ball_mass
	body.collision_layer = Layers.PROJECTILE
	body.collision_mask = Layers.SOLID
	body.physics_material_override = _physics
	body.continuous_cd = true
	body.angular_damp = 0.6
	var col := CollisionShape3D.new()
	col.shape = _shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	body.add_child(mi)
	return body


func _poof(ball: RigidBody3D) -> void:
	if not is_instance_valid(ball):
		return
	var fx := WorldFX.instance
	if fx != null:
		for i in 5:
			fx.puff(ball.global_position, Vector3(randf() - 0.5, randf() * 0.8, randf() - 0.5) * 1.5, Color(FUR.r, FUR.g, FUR.b, 0.55), randf_range(0.8, 1.4), ball_radius, ball_radius * 3.0)
	ball.queue_free()


static func _build_shared() -> void:
	_shape = SphereShape3D.new()
	_physics = PhysicsMaterial.new()
	_physics.bounce = 0.25
	_physics.friction = 0.9
	_mesh = SphereMesh.new()
	_mesh.radial_segments = 20
	_mesh.rings = 10
	# Matted fur: fine noise for the strands, a rim that reads as fuzz against the light.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	var strands := NoiseTexture2D.new()
	strands.width = 256
	strands.height = 256
	strands.seamless = true
	strands.noise = noise
	var bumps := NoiseTexture2D.new()
	bumps.width = 256
	bumps.height = 256
	bumps.seamless = true
	bumps.as_normal_map = true
	bumps.bump_strength = 14.0
	bumps.noise = noise
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FUR
	mat.albedo_texture = strands
	mat.normal_enabled = true
	mat.normal_texture = bumps
	mat.normal_scale = 1.4
	mat.roughness = 1.0
	mat.uv1_scale = Vector3(3.0, 2.0, 1.0)
	mat.rim_enabled = true
	mat.rim = 0.55
	mat.rim_tint = 0.5
	_mesh.material = mat
