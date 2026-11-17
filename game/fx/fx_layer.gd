class_name FxLayer
extends GPUParticles3D
## One fixed-size ring of GPU particles that is fed only from script through emit(). A whole class of
## effects (every spark in the world, every smoke puff...) is one draw call and can never exceed its
## particle count: when all particles are alive, new ones are dropped by the GPU.
## The node never emits on its own; fx_process.gdshader moves, sizes and retires the particles.

const PROCESS_SHADER := preload("res://game/fx/fx_process.gdshader")
const EMIT_ALL := EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY | EMIT_FLAG_COLOR | EMIT_FLAG_CUSTOM
## Particles live in world space, so the layer is always "in view".
const WORLD_AABB := AABB(Vector3(-800.0, -150.0, -800.0), Vector3(1600.0, 700.0, 1600.0))

## Emissions accepted per rendered frame (the rest are dropped and counted).
var frame_budget := 256
var emitted := 0
var dropped := 0

var _frame := -1
var _frame_count := 0


## process: uniforms of fx_process.gdshader (gravity, drag, stretch, size_ease, wander).
static func create(layer_name: String, count: int, max_life: float, process: Dictionary, mesh: Mesh, sorted: bool) -> FxLayer:
	var layer := FxLayer.new()
	layer.name = layer_name
	layer.amount = count
	layer.lifetime = max_life
	layer.emitting = false
	layer.one_shot = false
	layer.local_coords = false
	layer.fixed_fps = 0
	layer.interpolate = false
	layer.explosiveness = 0.0
	layer.visibility_aabb = WORLD_AABB
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.draw_order = DRAW_ORDER_VIEW_DEPTH if sorted else DRAW_ORDER_INDEX
	layer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mat := ShaderMaterial.new()
	mat.shader = PROCESS_SHADER
	for key: String in process:
		mat.set_shader_parameter(key, process[key])
	layer.process_material = mat
	layer.draw_pass_1 = mesh
	layer.frame_budget = mini(count, 256)
	return layer


## Emits one particle. life in seconds (at most this layer's max_life), sizes in metres.
func emit(pos: Vector3, velocity: Vector3, color: Color, life: float, size_start: float, size_end: float) -> void:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_frame_count = 0
	if _frame_count >= frame_budget:
		dropped += 1
		return
	_frame_count += 1
	emitted += 1
	emit_particle(Transform3D(Basis.IDENTITY, pos), velocity, color, Color(0.0, minf(life, lifetime), size_start, size_end), EMIT_ALL)
