extends Node3D

@onready var audio = $AudioStreamPlayer3D
@onready var particles = $CPUParticles3D
@onready var flash = $OmniLight3D

var timer: float = 0.0

func _ready() -> void:
	audio.pitch_scale = randf_range(0.9, 1.15)
	audio.play()
	particles.emitting = true
	
	# Trigger camera shake on player
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist < 40.0:
			var intensity = clamp((1.0 - dist / 40.0) * 0.4, 0.05, 0.4)
			var spring = player.get_node_or_null("SpringArm3D")
			if spring:
				var tween = create_tween()
				tween.tween_property(spring, "position:y", spring.position.y + intensity, 0.05)
				tween.tween_property(spring, "position:y", 1.6, 0.1)

func _process(delta: float) -> void:
	timer += delta
	if flash:
		flash.light_energy = max(0.0, 5.0 * (1.0 - timer / 0.25))
	if timer > 1.2:
		queue_free()
