extends StaticBody3D

@export_enum("concrete", "brick", "glass", "road", "soil") var block_type: String = "concrete"
@export var max_health: float = 60.0
@export var block_size: Vector3 = Vector3(1.5, 1.5, 1.5)

var current_health: float = 60.0
var debris_scene = preload("res://scenes/destruction/debris_piece.tscn")

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape = $CollisionShape3D

func _ready() -> void:
	current_health = max_health
	setup_material()

func setup_material() -> void:
	if not mesh_instance:
		return
	var mat = StandardMaterial3D.new()
	match block_type:
		"concrete":
			mat.albedo_color = Color(0.68, 0.67, 0.65)
			mat.roughness = 0.8
		"brick":
			mat.albedo_color = Color(0.72, 0.28, 0.22)
			mat.roughness = 0.7
		"glass":
			mat.albedo_color = Color(0.3, 0.85, 0.95, 0.65)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.1
			mat.metallic = 0.4
		"road":
			mat.albedo_color = Color(0.18, 0.18, 0.2)
			mat.roughness = 0.9
		"soil":
			mat.albedo_color = Color(0.42, 0.28, 0.16)
			mat.roughness = 0.95
	
	mesh_instance.set_surface_override_material(0, mat)

func damage_block(amount: float, hit_pos: Vector3) -> void:
	if not mesh_instance and has_node("MeshInstance3D"):
		mesh_instance = $MeshInstance3D
	current_health -= amount
	
	if mesh_instance and is_inside_tree():
		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3(1.08, 1.08, 1.08), 0.05)
		tween.tween_property(mesh_instance, "scale", Vector3.ONE, 0.05)
	
	if current_health <= 0.0:
		shatter(hit_pos)

func shatter(hit_pos: Vector3) -> void:
	# Spawn 4 debris pieces
	if debris_scene:
		var parent = get_parent()
		var offsets = [
			Vector3(-0.35, 0.35, -0.35),
			Vector3(0.35, 0.35, 0.35),
			Vector3(-0.35, -0.35, 0.35),
			Vector3(0.35, -0.35, -0.35)
		]
		
		for offset in offsets:
			var deb = debris_scene.instantiate()
			parent.add_child(deb)
			deb.global_position = global_position + offset
			
			# Outward velocity away from hit_pos
			var fly_dir = (deb.global_position - hit_pos).normalized() + Vector3.UP * 0.4
			deb.linear_velocity = fly_dir * randf_range(8.0, 16.0)
			
			# Inherit color
			var deb_mesh = deb.get_node_or_null("MeshInstance3D")
			if deb_mesh and mesh_instance:
				var block_mat = mesh_instance.get_surface_override_material(0)
				if block_mat:
					deb_mesh.set_surface_override_material(0, block_mat)
	
	queue_free()
