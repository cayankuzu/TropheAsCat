class_name LightFlashPool
extends Node3D
## Pooled shadowless OmniLight3Ds for short flashes (explosions, impacts, muzzle glows). When every
## light is busy, the dimmest one is taken over, so a barrage costs at most pool_size lights.

@export var pool_size := 8

var flashes := 0
var stolen := 0

var _lights: Array[OmniLight3D] = []
var _energy := PackedFloat32Array()
var _duration := PackedFloat32Array()
var _age := PackedFloat32Array()
var _active := 0


func _ready() -> void:
	for i in pool_size:
		var l := OmniLight3D.new()
		l.name = "Flash%d" % i
		l.shadow_enabled = false
		l.visible = false
		l.omni_attenuation = 1.3
		l.light_specular = 0.4
		l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(l)
		_lights.append(l)
		_energy.append(0.0)
		_duration.append(0.0)
		_age.append(0.0)
	set_process(false)


func active_count() -> int:
	return _active


## A light that starts at `energy` and falls to zero over `duration` seconds (quadratic ease).
func flash(pos: Vector3, color: Color, energy: float, radius: float, duration: float) -> void:
	if _lights.is_empty():
		return
	var slot := -1
	var dimmest := INF
	for i in _lights.size():
		if not _lights[i].visible:
			slot = i
			break
		var left := _lights[i].light_energy
		if left < dimmest:
			dimmest = left
			slot = i
	var l := _lights[slot]
	if l.visible:
		stolen += 1
	else:
		_active += 1
	flashes += 1
	_energy[slot] = energy
	_duration[slot] = maxf(duration, 0.02)
	_age[slot] = 0.0
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.visible = true
	set_process(true)


func _process(delta: float) -> void:
	for i in _lights.size():
		var l := _lights[i]
		if not l.visible:
			continue
		_age[i] += delta
		var k := 1.0 - _age[i] / _duration[i]
		if k <= 0.0:
			l.visible = false
			_active -= 1
		else:
			l.light_energy = _energy[i] * k * k
	if _active <= 0:
		_active = 0
		set_process(false)
