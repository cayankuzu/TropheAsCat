extends Node3D

@export var width: int = 4
@export var depth: int = 4
@export var height_floors: int = 6
@export var block_size: float = 1.5

var block_scene = preload("res://scenes/destruction/destructible_block.tscn")

func _ready() -> void:
	generate_building()

func generate_building() -> void:
	if not block_scene:
		return
	
	var half_w = float(width) * 0.5 * block_size
	var half_d = float(depth) * 0.5 * block_size
	
	for y in range(height_floors):
		for x in range(width):
			for z in range(depth):
				# Only generate outer shell walls and floors (hollow inside for great collapse physics)
				var is_wall = (x == 0 or x == width - 1 or z == 0 or z == depth - 1)
				var is_floor = (y % 2 == 0)
				
				if is_wall or is_floor:
					var blk = block_scene.instantiate()
					add_child(blk)
					
					var pos_x = float(x) * block_size - half_w
					var pos_y = float(y) * block_size + block_size * 0.5
					var pos_z = float(z) * block_size - half_d
					blk.position = Vector3(pos_x, pos_y, pos_z)
					
					# Assign block type: corners = concrete, windows = glass, walls = brick
					if is_wall and not is_floor and (x + z) % 2 == 1:
						blk.block_type = "glass"
						blk.max_health = 25.0
					elif (x == 0 or x == width - 1) and (z == 0 or z == depth - 1):
						blk.block_type = "concrete"
						blk.max_health = 80.0
					else:
						blk.block_type = "brick"
						blk.max_health = 50.0
					
					blk.setup_material()
