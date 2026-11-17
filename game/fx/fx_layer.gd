class_name FxLayer
extends GPUParticles3D
## One fixed-size ring of GPU particles that is fed only from script through emit(). A whole class of
## effects (every spark in the world, every smoke puff...) is one draw call and can never exceed its
## particle count: when all particles are alive, new ones are dropped by the GPU.
## The node never emits on its own; fx_process.gdshader moves, sizes and retires the particles.
##
## The Compatibility renderer (the browser demo, the PC game's OpenGL fallback) cannot emit GPU particles from
## script (2026-11-17: every flame, smoke puff, spark and pee drop was missing there). On it the layer runs the
## same motion on the CPU (`cpu`, see _process: the code of fx_process.gdshader) and draws its particles as one
## MultiMesh with the same draw material: per instance the transform, the colour and the custom data
## (age, life, size at birth, size at death), which is what the draw shaders read.

const PROCESS_SHADER := preload("res://game/fx/fx_process.gdshader")
const EMIT_ALL := EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY | EMIT_FLAG_COLOR | EMIT_FLAG_CUSTOM
## Particles live in world space, so the layer is always "in view".
const WORLD_AABB := AABB(Vector3(-800.0, -150.0, -800.0), Vector3(1600.0, 700.0, 1600.0))
## Most particles one CPU layer keeps alive (the script moves every one of them each frame).
const CPU_CAPACITY := 320
## Floats per instance in a MultiMesh buffer with colours and custom data: 3x4 transform, colour, custom.
const STRIDE := 20

## Emissions accepted per rendered frame (the rest are dropped and counted).
var frame_budget := 256
var emitted := 0
var dropped := 0
## True on the Compatibility renderer: the particles are simulated here and drawn as a MultiMesh.
var cpu := false

var _frame := -1
var _frame_count := 0

var _gravity := Vector3(0.0, -9.8, 0.0)
var _drag := 0.0
var _stretch := 0.0
var _size_ease := 1.0
var _wander := 0.0
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _buffer := PackedFloat32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _col := PackedColorArray()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _s0 := PackedFloat32Array()
var _s1 := PackedFloat32Array()
var _id := PackedInt32Array()
## Slots stay put while a particle lives (the draw shaders turn a puff by its INSTANCE_ID): the dead ones are
## collapsed to nothing in the buffer and their slots wait in _free; only slots below _high are drawn.
var _live := PackedByteArray()
var _free := PackedInt32Array()
var _high := 0
var _alive := 0
var _next_id := 0


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
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		layer._setup_cpu(mini(count, CPU_CAPACITY), process, mesh)
	return layer


func _setup_cpu(capacity: int, process: Dictionary, mesh: Mesh) -> void:
	cpu = true
	amount = 1   # the GPU side stays idle
	_gravity = process.get("gravity", _gravity)
	_drag = float(process.get("drag", 0.0))
	_stretch = float(process.get("stretch", 0.0))
	_size_ease = float(process.get("size_ease", 1.0))
	_wander = float(process.get("wander", 0.0))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	_mm.custom_aabb = WORLD_AABB
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "CpuParticles"
	_mmi.multimesh = _mm
	_mmi.top_level = true
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_mmi)
	_buffer.resize(capacity * STRIDE)
	_buffer.fill(0.0)
	# Packed arrays are values: each one is resized itself.
	_pos.resize(capacity)
	_vel.resize(capacity)
	_col.resize(capacity)
	_age.resize(capacity)
	_life.resize(capacity)
	_s0.resize(capacity)
	_s1.resize(capacity)
	_id.resize(capacity)
	_live.resize(capacity)
	_live.fill(0)
	_free.resize(capacity)
	for k in capacity:
		_free[k] = capacity - 1 - k   # slot 0 is handed out first
	set_process(true)


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
	if cpu:
		if _free.is_empty():
			dropped += 1
			return
		var i := _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		_live[i] = 1
		_alive += 1
		_high = maxi(_high, i + 1)
		_pos[i] = pos
		_vel[i] = velocity
		_col[i] = color
		_age[i] = 0.0
		_life[i] = minf(life, lifetime)
		_s0[i] = size_start
		_s1[i] = size_end
		_id[i] = _next_id
		_next_id = (_next_id + 1) % 4096
		emitted += 1
		return
	emitted += 1
	emit_particle(Transform3D(Basis.IDENTITY, pos), velocity, color, Color(0.0, minf(life, lifetime), size_start, size_end), EMIT_ALL)


## The CPU path: fx_process.gdshader's motion for every live particle, then one buffer upload.
func _process(delta: float) -> void:
	if not cpu:
		set_process(false)
		return
	if _alive == 0:
		if _mm.visible_instance_count != 0:
			_mm.visible_instance_count = 0
			_high = 0
		return
	for i in _high:
		if _live[i] == 0:
			continue
		var age := _age[i] + delta
		var o := i * STRIDE
		if age >= _life[i]:
			_live[i] = 0
			_alive -= 1
			_free.append(i)
			for k in 12:
				_buffer[o + k] = 0.0   # collapsed: drawn as nothing
			continue
		_age[i] = age
		var acc := _gravity
		if _wander > 0.0:
			var ph := age * 1.7 + float(_id[i]) * 12.9898
			acc += _wander * Vector3(sin(ph), 0.35 * sin(ph * 1.31 + 2.0), cos(ph * 0.83 + float(_id[i])))
		var v := (_vel[i] + acc * delta) / (1.0 + _drag * delta)
		_vel[i] = v
		var p := _pos[i] + v * delta
		_pos[i] = p
		var t := clampf(age / maxf(_life[i], 0.001), 0.0, 1.0)
		var size := lerpf(_s0[i], _s1[i], pow(t, _size_ease))
		var bx := Vector3(size, 0.0, 0.0)
		var by := Vector3(0.0, size, 0.0)
		var bz := Vector3(0.0, 0.0, size)
		if _stretch > 0.0:
			var speed := v.length()
			var y := v / speed if speed > 0.001 else Vector3.UP
			var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
			var z := x.cross(y)
			bx = x * size
			by = y * (size + speed * _stretch)
			bz = z * size
		# Row-major 3x4: x, y and z rows of the basis columns, then the origin column.
		_buffer[o] = bx.x
		_buffer[o + 1] = by.x
		_buffer[o + 2] = bz.x
		_buffer[o + 3] = p.x
		_buffer[o + 4] = bx.y
		_buffer[o + 5] = by.y
		_buffer[o + 6] = bz.y
		_buffer[o + 7] = p.y
		_buffer[o + 8] = bx.z
		_buffer[o + 9] = by.z
		_buffer[o + 10] = bz.z
		_buffer[o + 11] = p.z
		var c := _col[i]
		_buffer[o + 12] = c.r
		_buffer[o + 13] = c.g
		_buffer[o + 14] = c.b
		_buffer[o + 15] = c.a
		_buffer[o + 16] = age
		_buffer[o + 17] = _life[i]
		_buffer[o + 18] = _s0[i]
		_buffer[o + 19] = _s1[i]
	while _high > 0 and _live[_high - 1] == 0:
		_high -= 1
	RenderingServer.multimesh_set_buffer(_mm.get_rid(), _buffer)
	_mm.visible_instance_count = _high
