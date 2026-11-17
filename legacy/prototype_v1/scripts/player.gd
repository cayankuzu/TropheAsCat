extends CharacterBody3D

# --- PLAYER STATE & TUNING ---
const SPEED_WALK = 7.0
const SPEED_SPRINT = 13.0
const JUMP_VELOCITY = 10.0
const GRAVITY = 24.0
const MOUSE_SENSITIVITY = 0.003

enum Mode {
	ROAM = 1,
	WIZARD_FIRE = 2,
	HAIRBALL = 3,
	ACID = 4
}

var current_mode: Mode = Mode.ROAM
var is_casting: bool = false
var acid_active: bool = false

# History buffer for Rewind (R key)
var history: Array = []
const MAX_HISTORY = 300 # ~5 seconds at 60fps
var is_rewinding: bool = false

# Nodes
@onready var visual_root = $VisualRoot
@onready var wizard_hat = $VisualRoot/Head/WizardHat
@onready var cast_point = $VisualRoot/CastPoint
@onready var spring_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D
@onready var tail = $VisualRoot/Tail
@onready var audio_player = $AudioStreamPlayer3D
@onready var acid_beam = $VisualRoot/AcidBeam
@onready var acid_particles = $VisualRoot/AcidParticles

# Cooldowns
var attack_cooldown: float = 0.0
var walk_anim_time: float = 0.0

# Sound preloads
var snd_meow = preload("res://assets/audio/sfx_meow.wav")
var snd_magic = preload("res://assets/audio/sfx_magic_cast.wav")
var snd_hairball = preload("res://assets/audio/sfx_hairball.wav")
var snd_acid = preload("res://assets/audio/sfx_acid_sizzle.wav")
var snd_rocket = preload("res://assets/audio/sfx_rocket_launch.wav")
var snd_glitch = preload("res://assets/audio/sfx_glitch.wav")

# Projectile preloads
var fireball_scene = preload("res://scenes/weapons/fireball.tscn")
var hairball_scene = preload("res://scenes/weapons/hairball.tscn")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_mode(Mode.ROAM)
	if acid_beam:
		acid_beam.visible = false
	if acid_particles:
		acid_particles.emitting = false

func _unhandled_input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		spring_arm.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-65), deg_to_rad(45))
	
	# Esc releases mouse
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Mode Selection
	if Input.is_action_just_pressed("mode_1"):
		set_mode(Mode.ROAM)
	elif Input.is_action_just_pressed("mode_2"):
		set_mode(Mode.WIZARD_FIRE)
	elif Input.is_action_just_pressed("mode_3"):
		set_mode(Mode.HAIRBALL)
	elif Input.is_action_just_pressed("mode_4"):
		set_mode(Mode.ACID)

func set_mode(new_mode: Mode) -> void:
	current_mode = new_mode
	if not wizard_hat and has_node("VisualRoot/Head/WizardHat"):
		wizard_hat = $VisualRoot/Head/WizardHat
	if wizard_hat:
		wizard_hat.visible = (current_mode == Mode.WIZARD_FIRE)
	
	# Play subtle audio feedback
	if audio_player and is_inside_tree():
		audio_player.stream = snd_meow if current_mode == Mode.ROAM else snd_glitch
		audio_player.pitch_scale = 1.0 + float(current_mode) * 0.15
		audio_player.play()
	
	# Update HUD event if exists
	if is_inside_tree():
		var t = get_tree()
		if t:
			var hud = t.get_first_node_in_group("hud")
			if hud and hud.has_method("update_mode_ui"):
				hud.update_mode_ui(current_mode)

func _physics_process(delta: float) -> void:
	# Handle Rewind (Hold R)
	if Input.is_action_pressed("rewind") and history.size() > 0:
		is_rewinding = true
		var prev_state = history.pop_back()
		global_position = prev_state.pos
		velocity = prev_state.vel
		current_mode = prev_state.mode
		wizard_hat.visible = (current_mode == Mode.WIZARD_FIRE)
		return
	else:
		is_rewinding = false
		history.push_back({
			"pos": global_position,
			"vel": velocity,
			"mode": current_mode
		})
		if history.size() > MAX_HISTORY:
			history.pop_front()
	
	# Attack Cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Movement Input
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.y += 1
	if Input.is_action_pressed("move_back"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	input_dir = input_dir.normalized()
	
	var is_sprinting = Input.is_action_pressed("sprint")
	var speed = SPEED_SPRINT if is_sprinting else SPEED_WALK
	
	var forward = -transform.basis.z
	var right = transform.basis.x
	var move_dir = (forward * input_dir.y + right * input_dir.x).normalized()
	
	if move_dir != Vector3.ZERO:
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
		walk_anim_time += delta * (14.0 if is_sprinting else 8.0)
		# Procedural cat swagger & tail wagging
		visual_root.rotation.z = sin(walk_anim_time) * 0.08
		visual_root.rotation.x = sin(walk_anim_time * 2.0) * 0.05
		if tail:
			tail.rotation.y = sin(walk_anim_time * 1.5) * 0.4
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		visual_root.rotation.z = move_toward(visual_root.rotation.z, 0, delta * 3.0)
		visual_root.rotation.x = move_toward(visual_root.rotation.x, 0, delta * 3.0)
		if tail:
			tail.rotation.y = sin(Time.get_ticks_msec() * 0.003) * 0.2
	
	move_and_slide()
	
	# Attacks & Actions
	handle_weapons(delta)
	
	# Magma & Out of Bounds Check
	check_boundaries()

func handle_weapons(delta: float) -> void:
	if current_mode == Mode.ROAM:
		# Just meow on attack
		if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
			attack_cooldown = 0.5
			audio_player.stream = snd_meow
			audio_player.pitch_scale = randf_range(0.9, 1.2)
			audio_player.play()
			spawn_floating_text("MEOW!", Color.YELLOW)
	
	elif current_mode == Mode.WIZARD_FIRE:
		if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
			attack_cooldown = 0.25
			shoot_projectile(fireball_scene, snd_magic)
	
	elif current_mode == Mode.HAIRBALL:
		if Input.is_action_just_pressed("attack") and attack_cooldown <= 0.0:
			attack_cooldown = 0.4
			shoot_projectile(hairball_scene, snd_hairball)
	
	elif current_mode == Mode.ACID:
		if Input.is_action_pressed("attack"):
			fire_acid_stream(delta)
		else:
			stop_acid_stream()

func shoot_projectile(scene: PackedScene, sound: AudioStream) -> void:
	if not scene:
		return
	
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.pitch_scale = randf_range(0.95, 1.1)
		audio_player.play()
	
	var proj = scene.instantiate()
	get_parent().add_child(proj)
	
	var spawn_pos = cast_point.global_position if cast_point else global_position + Vector3(0, 1.0, -1.0)
	proj.global_position = spawn_pos
	
	# Target direction: shoot toward camera center
	var aim_target = get_aim_target()
	var shoot_dir = (aim_target - spawn_pos).normalized()
	proj.setup_velocity(shoot_dir)

func fire_acid_stream(delta: float) -> void:
	if acid_beam:
		acid_beam.visible = true
	if acid_particles:
		acid_particles.emitting = true
	
	if not audio_player.playing or audio_player.stream != snd_acid:
		audio_player.stream = snd_acid
		audio_player.play()
	
	# Raycast hit detection for continuous acid melting
	var origin = cast_point.global_position if cast_point else global_position + Vector3(0, 1, -1)
	var target = get_aim_target()
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		# If collider is nature/tree, trigger green shield!
		if collider.is_in_group("nature"):
			if collider.has_method("defend"):
				collider.defend(result.position)
			return
		
		# If destructible block, melt it!
		if collider.has_method("damage_block"):
			collider.damage_block(60.0 * delta, result.position)

func stop_acid_stream() -> void:
	if acid_beam:
		acid_beam.visible = false
	if acid_particles:
		acid_particles.emitting = false
	if audio_player.stream == snd_acid and audio_player.playing:
		audio_player.stop()

func get_aim_target() -> Vector3:
	var screen_center = get_viewport().get_visible_rect().size * 0.5
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_dir = camera.project_ray_normal(screen_center)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 150.0)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position
	return ray_origin + ray_dir * 80.0

func check_boundaries() -> void:
	var cur_pos = global_position if is_inside_tree() else position
	# 1. Magma check (at y <= -11.0)
	if cur_pos.y <= -11.0:
		# Comic rocket launch!
		velocity.y = 45.0
		velocity.x = randf_range(-10, 10)
		velocity.z = randf_range(-10, 10)
		if audio_player and is_inside_tree():
			audio_player.stream = snd_rocket
			audio_player.play()
		spawn_floating_text("LAVA BURN!! ZOOM!", Color.ORANGE_RED)
	
	# 2. Out of bounds fall into void (y < -26.0 or x/z > 140)
	if cur_pos.y <= -26.0 or abs(cur_pos.x) > 140.0 or abs(cur_pos.z) > 140.0:
		# Respawn safely in the sky, 4 paws landing
		if is_inside_tree():
			global_position = Vector3(randf_range(-10, 10), 22.0, randf_range(-10, 10))
		else:
			position = Vector3(randf_range(-10, 10), 22.0, randf_range(-10, 10))
		velocity = Vector3(0, -4.0, 0)
		if audio_player and is_inside_tree():
			audio_player.stream = snd_glitch
			audio_player.play()
		spawn_floating_text("[ REBOOTING CAT.EXE ]", Color.CYAN)

func spawn_floating_text(msg: String, color: Color) -> void:
	if is_inside_tree():
		var t = get_tree()
		if t:
			var hud = t.get_first_node_in_group("hud")
			if hud and hud.has_method("show_alert"):
				hud.show_alert(msg, color)
