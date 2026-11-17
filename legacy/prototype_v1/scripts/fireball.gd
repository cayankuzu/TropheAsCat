extends Area3D

const SPEED = 48.0
const DAMAGE = 100.0
const EXPLOSION_RADIUS = 3.8

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 4.0

var explosion_scene = preload("res://scenes/destruction/explosion_effect.tscn")

func setup_velocity(dir: Vector3) -> void:
	direction = dir.normalized()
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += direction * SPEED * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	explode()

func _on_area_entered(area: Area3D) -> void:
	explode()

func explode() -> void:
	# Spawn visual & audio explosion effect
	if explosion_scene:
		var exp_node = explosion_scene.instantiate()
		get_parent().add_child(exp_node)
		exp_node.global_position = global_position
	
	# Damage nearby destructible objects in radius
	var space_state = get_world_3d().direct_space_state
	var shape = SphereShape3D.new()
	shape.radius = EXPLOSION_RADIUS
	
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collide_with_bodies = true
	
	var results = space_state.intersect_shape(query, 32)
	for hit in results:
		var collider = hit.collider
		if collider.is_in_group("nature"):
			if collider.has_method("defend"):
				collider.defend(global_position)
		elif collider.has_method("damage_block"):
			collider.damage_block(DAMAGE, global_position)
		elif collider is RigidBody3D:
			var push_dir = (collider.global_position - global_position).normalized() + Vector3.UP * 0.5
			collider.apply_central_impulse(push_dir * 18.0)
	
	queue_free()
