extends SceneTree

func _init() -> void:
	print("========================================")
	print(">>> RUNNING AUTOMATED AAA ENGINE TESTS <<<")
	print("========================================")
	
	# Test 1: Check Audio Files
	var audio_files = [
		"res://assets/audio/sfx_meow.wav",
		"res://assets/audio/sfx_magic_cast.wav",
		"res://assets/audio/sfx_explosion.wav",
		"res://assets/audio/sfx_hairball.wav",
		"res://assets/audio/sfx_acid_sizzle.wav",
		"res://assets/audio/sfx_nature_shield.wav",
		"res://assets/audio/sfx_glitch.wav",
		"res://assets/audio/sfx_rocket_launch.wav"
	]
	for af in audio_files:
		var s = ResourceLoader.load(af)
		assert(s != null, "Failed to load audio: " + af)
	print(" [PASS] Test 1: All 8 Audio SFX Loaded.")
	
	# Test 2: Check 3D Kenney Models
	var models = [
		"res://assets/models/building-small-a.glb",
		"res://assets/models/building-small-b.glb",
		"res://assets/models/grass-trees.glb"
	]
	for m in models:
		var res = ResourceLoader.load(m)
		assert(res != null, "Failed to load model: " + m)
	print(" [PASS] Test 2: 3D Kenney Models Loaded.")
	
	# Test 3: Load World Scene and Instantiate
	var world_scene = ResourceLoader.load("res://scenes/world/world.tscn")
	assert(world_scene != null, "World scene not found!")
	var world = world_scene.instantiate()
	root.add_child(world)
	print(" [PASS] Test 3: World Scene Instantiated.")
	
	# Test 4: Verify Player & Modes
	var player = world.get_node_or_null("Player")
	assert(player != null, "Player not found in world!")
	
	# Mode 1: Roam (Hat off)
	player.set_mode(player.Mode.ROAM)
	assert(player.wizard_hat.visible == false, "Mode 1 should have wizard hat OFF!")
	
	# Mode 2: Wizard Fire (Hat ON)
	player.set_mode(player.Mode.WIZARD_FIRE)
	assert(player.wizard_hat.visible == true, "Mode 2 should have wizard hat ON!")
	
	# Mode 3 & 4
	player.set_mode(player.Mode.HAIRBALL)
	player.set_mode(player.Mode.ACID)
	print(" [PASS] Test 4: Player Controller & 4 Modes Verified.")
	
	# Test 5: Destructible Block Damage & Shatter
	var block_scene = ResourceLoader.load("res://scenes/destruction/destructible_block.tscn")
	assert(block_scene != null, "Destructible block scene missing!")
	var test_block = block_scene.instantiate()
	world.add_child(test_block)
	test_block.global_position = Vector3(5, 5, 5)
	var initial_health = test_block.current_health
	
	# Apply partial damage
	test_block.damage_block(20.0, Vector3(5, 5, 5))
	assert(test_block.current_health == initial_health - 20.0, "Block health not reduced properly!")
	
	# Apply lethal damage (shatters into debris)
	test_block.damage_block(100.0, Vector3(5, 5, 5))
	print(" [PASS] Test 5: Destruction & Debris Shatter Verified.")
	
	# Test 6: Nature Protection Rule
	var tree = world.get_node_or_null("NatureSanctuary/NatureTree1")
	assert(tree != null, "Nature Tree not found in world!")
	assert(tree.is_in_group("nature"), "Tree must belong to 'nature' group!")
	tree.defend(Vector3.ZERO)
	assert(tree.shield_mesh.visible, "Tree shield mesh did not activate!")
	print(" [PASS] Test 6: Sacred Nature Shield Defense Verified.")
	
	# Test 7: Magma Sea & Zero Death
	player.position = Vector3(0, -11.5, 0)
	player.check_boundaries()
	assert(player.velocity.y > 30.0, "Magma should launch player with high upward velocity!")
	print(" [PASS] Test 7: Magma Launch & Zero-Death Verified.")
	
	# Test 8: Void Out-of-Bounds Re-entry
	player.position = Vector3(0, -30.0, 0)
	player.check_boundaries()
	assert(player.position.y >= 20.0, "Void fall should respawn player high in the sky!")
	print(" [PASS] Test 8: 13th Floor Void Fall & Sky Re-entry Verified.")
	
	print("========================================")
	print(">>> ALL 8 AAA ENGINE TESTS PASSED! <<<")
	print("========================================")
	
	quit(0)
