extends Control

@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel
@onready var sub_label = $CenterContainer/VBoxContainer/SubLabel
@onready var prompt_label = $CenterContainer/VBoxContainer/PromptLabel
@onready var glitch_player = $AudioStreamPlayer
@onready var bg_color = $ColorRect

var step: int = 0
var timer: float = 0.0
var glitch_chars = "!@#$%^&*<>[]{}0101"
var is_starting: bool = false

func _ready() -> void:
	title_label.text = "ROPHE  AS  CAT"
	sub_label.text = "[ SYSTEM INITIALIZING... ]"
	prompt_label.modulate.a = 0.0
	
	# Load sound
	var sound = load("res://assets/audio/sfx_glitch.wav")
	if sound:
		glitch_player.stream = sound
		glitch_player.play()

func _process(delta: float) -> void:
	timer += delta
	
	if step == 0 and timer > 1.2:
		# Trigger glitch swap
		step = 1
		timer = 0.0
		glitch_player.play()
	elif step == 1:
		# Scramble glitch letters for 0.6 seconds
		if timer < 0.6:
			var scrambled = ""
			for i in range(12):
				scrambled += glitch_chars[randi() % glitch_chars.length()]
			title_label.text = scrambled
			title_label.modulate = Color(randf_range(0.5, 1.0), 0.2, randf_range(0.8, 1.0))
		else:
			# Morph into CAT AS ROPHE
			step = 2
			timer = 0.0
			title_label.text = "CAT  AS  ROPHE"
			title_label.modulate = Color(1.0, 0.3, 0.4) # Neon Pink / Red
			sub_label.text = "« C A T A S T R O P H E »"
			sub_label.modulate = Color(0.2, 0.9, 1.0)
			
			# Boom sound
			var boom = load("res://assets/audio/sfx_explosion.wav")
			if boom:
				glitch_player.stream = boom
				glitch_player.play()
	elif step == 2:
		# Pulse the start prompt
		prompt_label.modulate.a = abs(sin(timer * 3.5))

func _input(event: InputEvent) -> void:
	if is_starting:
		return
	if event is InputEventKey and event.is_pressed():
		start_game()
	elif event is InputEventMouseButton and event.is_pressed():
		start_game()

func start_game() -> void:
	is_starting = true
	var meow = load("res://assets/audio/sfx_meow.wav")
	if meow:
		glitch_player.stream = meow
		glitch_player.play()
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	)
