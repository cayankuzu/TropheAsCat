extends RigidBody3D

const SPEED = 40.0
const IMPACT_FORCE = 35.0
const DAMAGE = 150.0

var lifetime: float = 4.0
var explosion_scene = preload("res://scenes/destruction/explosion_effect.tscn")

func setup_velocity(dir: Vector3) -> void:
	linear_velocity = dir.normalized() * SPEED

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	
	if body.is_in_group("nature"):
		if body.has_method("defend"):
			body.defend(global_position)
		queue_free()
		return
	
	if body.has_method("damage_block"):
		body.damage_block(DAMAGE, global_position)
	elif body is RigidBody3D:
		var push = linear_velocity.normalized() * IMPACT_FORCE
		body.apply_central_impulse(push)
	
	# Spawn impact
	if explosion_scene:
		var exp_node = explosion_scene.instantiate()
		get_parent().add_child(exp_node)
		exp_node.global_position = global_position
	
	queue_free()
