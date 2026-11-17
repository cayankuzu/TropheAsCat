extends RigidBody3D

var lifetime: float = 3.2
var initial_scale: Vector3 = Vector3.ONE

func _ready() -> void:
	initial_scale = scale
	# Add slight random impulse and spin
	apply_torque_impulse(Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)))

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 1.0:
		# Smoothly shrink before vanishing
		var shrink_factor = max(0.01, lifetime / 1.0)
		scale = initial_scale * shrink_factor
	if lifetime <= 0.0:
		queue_free()
